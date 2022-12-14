#!/bin/bash
# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* ./make/autoconf
cp $BUILD_PREFIX/share/gnuconfig/config.* ./erts/autoconf
cp $BUILD_PREFIX/share/gnuconfig/config.* ./lib/common_test/test_server
set -ex

export LIBRARY_PATH="${PREFIX}/lib:${LIBRARY_PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH}"
export ERL_TOP="${PWD}"

if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -DTARGET_OS_OSX=1"
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
