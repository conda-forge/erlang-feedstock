#!/bin/bash
set -ex

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
  local CC CXX CPP LD AR RANLIB
  CC=${CC_FOR_BUILD}
  CXX=${CXX_FOR_BUILD}
  LD=${CC_FOR_BUILD//gnu-cc/gnu-ld}
  CPP=${CC_FOR_BUILD//gnu-cc/gnu-cpp}
  AR=${CC_FOR_BUILD//gnu-cc/gnu-ar}
  RANLIB=${CC_FOR_BUILD//gnu-cc/gnu-ranlib}
  CFLAGS= CXXFLAGS= ./configure \
      --enable-bootstrap-only \
      --host="${BUILD}" \
      --without-javac \
      || { cat make/config.log ; exit 1; }

  echo "Boostrap build config.log"
  cat make/config.log
  make -j "$CPU_COUNT"
}

# For builds that are cross-compiled (aarch64), we need to build a bootstrap system first.
# https://www.erlang.org/doc/installation_guide/install-cross#Build-and-Install-Procedure_Building-With-configuremake-Directly_Building-a-Bootstrap-System
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" -eq 1 ]]; then
  bootstrap_build
fi

./configure \
    --prefix="${PREFIX}" \
    --with-ssl="${PREFIX}" \
    --without-javac \
    --enable-m${ARCH}-build \
    || { cat make/config.log ; exit 1; }

cat make/config.log
make -j $CPU_COUNT

# Fix up too long shebang line which is blocking tests on Linux
# cf. https://github.com/conda-forge/erlang-feedstock/issues/16
sed -i.bak -e '1 s@.*@#!/usr/bin/env perl@' make/make_emakefile

make release_tests
make install

cd "${ERL_TOP}/release/tests/test_server"
${PREFIX}/bin/erl -s ts install -s ts smoke_test batch -s init stop || ls -lrta ${ERL_TOP}/bin/
cd ${ERL_TOP}
