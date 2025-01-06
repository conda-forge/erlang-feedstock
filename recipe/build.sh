#!/bin/bash
set -ex

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* ./erts/autoconf
cp $BUILD_PREFIX/share/gnuconfig/config.* ./make/autoconf
cp $BUILD_PREFIX/share/gnuconfig/config.* ./lib/common_test/test_server

export LIBRARY_PATH="${PREFIX}/lib:${LIBRARY_PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH}"
export ERL_TOP="${PWD}"

if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -DTARGET_OS_OSX=1"
fi

function bootstrap_build {
  echo "Building bootstrap erlang for cross-compilation"
  # We need to override the compilation toolchain that is setup for cross-compilation,
  # the bootstrap system needs to be compiled with the guest (x86) toolchain.
  # Otherwise, configure fails with:
  # error: Cannot both cross compile and build a bootstrap system
  local CC CXX CPP LD AR RANLIB LDFLAGS_CROSS
  CC=${CC_FOR_BUILD}
  CXX=${CXX_FOR_BUILD}
  CPP=${CPP_FOR_BUILD}
  LD=$(echo "${CC_FOR_BUILD}" | sed -E 's/-(cc|clang)$/-ld/')
  AR=$(echo "${CC_FOR_BUILD}" | sed -E 's/-(cc|clang)$/-ar/')
  RANLIB=$(echo "${CC_FOR_BUILD}" | sed -E 's/-(cc|clang)$/-ranlib/')
  LDFLAGS_CROSS=$LDFLAGS
  export LDFLAGS='-Wl,-headerpad_max_install_names -Wl,-dead_strip_dylibs -Wl,-rpath,$BUILD_PREFIX/lib -L$BUILD_PREFIX/lib'

  # NOTE: clang-18 exposes an issue with outdated vendored zlib,
  # so we need to use the system zlib instead, at least until new erlang
  # release which will have updated zlib 1.3.1, see:
  # https://github.com/erlang/otp/pull/8862
  CFLAGS="-O1" CXXFLAGS="-O1" LDFLAGS='-Wl,-headerpad_max_install_names -Wl,-dead_strip_dylibs -Wl,-rpath,$BUILD_PREFIX/lib -L$BUILD_PREFIX/lib' ./configure \
      --enable-bootstrap-only \
      --host="${BUILD}" \
      --without-javac \
      --disable-builtin-zlib \
      || { cat make/config.log; cat erts/config.log; exit 1; }

  echo "======== Boostrap build config.log ==========="
  cat make/config.log
  echo "======== ERTS build config.log ==========="
  cat erts/config.log
  make -j "$CPU_COUNT"
  export LDFLAGS=$LDFLAGS_CROSS
}

# For builds that are cross-compiled (aarch64), we need to build a bootstrap system first.
# https://www.erlang.org/doc/installation_guide/install-cross#Build-and-Install-Procedure_Building-With-configuremake-Directly_Building-a-Bootstrap-System
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" -eq 1 ]]; then
  bootstrap_build
  # erl_xcomp_sysroot is needed for cross-compilation to find SSH headers for target arch.
  # https://github.com/erlang/otp/blob/master/HOWTO/INSTALL-CROSS.md#cross-system-root-locations
  export erl_xcomp_sysroot="${CONDA_BUILD_SYSROOT}"
fi
./configure \
    --prefix="${PREFIX}" \
    --with-ssl="${PREFIX}" \
    --without-javac \
    --enable-m${ARCH}-build

cat make/config.log
make -j $CPU_COUNT

# Fix up too long shebang line which is blocking tests on Linux
# cf. https://github.com/conda-forge/erlang-feedstock/issues/16
sed -i.bak -e '1 s@.*@#!/usr/bin/env perl@' make/make_emakefile

# Create tests
make release_tests

# For unknown reason, cross-compilation does not produce the $ERL_TOP/bin/erl binary.
# It seems to be only generated during the make install step
# so we first run `make install` before running tests.
make install

# Skip tests for osx-arm64 cross-compiled build
if [[ "${target_platform}" == osx-arm64 && "${CONDA_BUILD_CROSS_COMPILATION}" -eq 1  ]]; then
  echo "WARNING: Skipping tests for $target_platform cross-compiled build"
  exit 0
fi

# Run tests
#
# We run epmd server explicitly with -relaxed_command_check
# so that we can later kill it and avoid the following error:
# "Killing not allowed - living nodes in database."
epmd  -daemon -relaxed_command_check
cd "${ERL_TOP}/release/tests/test_server"
${PREFIX}/bin/erl -s ts install -s ts smoke_test batch -s init stop
cd ${ERL_TOP}

# We need to explicitly stop the Erlang Port Mapper Daemon (EPMD),
# otherwise the conda build step fails with:
# File "/opt/conda/lib/python3.10/site-packages/conda_build/build.py", line 1013, in <listcomp>
# if open(os.path.join(prefix, f), "rb+").read().find(b"\x00") != -1
# OSError: [Errno 26] Text file busy: 'build_artifacts/erlang_xxx/_h_env_xxx/lib/erlang/erts-15.0/bin/epmd'
# See: https://manpages.debian.org/testing/erlang-base/epmd.1.en.html
${PREFIX}/bin/epmd -kill
