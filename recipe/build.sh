#!/usr/bin/env bash
set -ex

export LIBRARY_PATH="${PREFIX}/lib:${LIBRARY_PATH}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH}"
export ERL_TOP="$(pwd)"
./otp_build autoconf
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
