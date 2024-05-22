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
  CFLAGS= LDFLAGS= ./configure \
      --enable-bootstrap-only \
      --host="${BUILD}" \
      --build="${BUILD}" \
      --prefix="${BUILD_PREFIX}" \
      --without-javac

  make -j $CPU_COUNT
  make install
fi

./configure \
    --prefix="${PREFIX}" \
    --with-ssl="${PREFIX}" \
    --without-javac \
    --enable-m${ARCH}-build

make -j $CPU_COUNT

# Fix up too long shebang line which is blocking tests on Linux
# cf. https://github.com/conda-forge/erlang-feedstock/issues/16
sed -i.bak -e '1 s@.*@#!/usr/bin/env perl@' make/make_emakefile

make release_tests
cd "${ERL_TOP}/release/tests/test_server"
${ERL_TOP}/bin/erl -s ts install -s ts smoke_test batch -s init stop
cd ${ERL_TOP}

make install
