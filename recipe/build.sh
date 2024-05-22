#!/bin/bash
set -ex

export LIBRARY_PATH="${PREFIX}/lib:${LIBRARY_PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH}"
export ERL_TOP="${PWD}"

if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -DTARGET_OS_OSX=1"
fi

# For builds that are cross-compiled (aarch64), we need to build a bootstrap system first.
# https://www.erlang.org/doc/installation_guide/install-cross#Build-and-Install-Procedure_Building-With-configuremake-Directly_Building-a-Bootstrap-System
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" -eq 1 ]]; then

  # We need to override the host for the bootstrap compilation,
  # otherwise configure fails with:
  # error: Cannot both cross compile and build a bootstrap system
  CC="${CC_FOR_BUILD}" CXX="${CXX_FOR_BUILD}" ./configure \
      --enable-bootstrap-only \
      --host="${BUILD}" \
      --without-javac \
      || { cat make/config.log ; exit 1; }

  make -j $CPU_COUNT
fi

./configure \
    --prefix="${PREFIX}" \
    --with-ssl="${PREFIX}" \
    --without-javac \
    --enable-m${ARCH}-build \
    || { cat make/config.log ; exit 1; }

make -j $CPU_COUNT

# Fix up too long shebang line which is blocking tests on Linux
# cf. https://github.com/conda-forge/erlang-feedstock/issues/16
sed -i.bak -e '1 s@.*@#!/usr/bin/env perl@' make/make_emakefile

make release_tests
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" -ne 1 ]]; then
  cd "${ERL_TOP}/release/tests/test_server"
  ${ERL_TOP}/bin/erl -s ts install -s ts smoke_test batch -s init stop || ls -lrta ${ERL_TOP}/bin/
  cd ${ERL_TOP}
fi

make install
