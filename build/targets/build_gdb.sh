#!/bin/bash
if [ -z "$GITHUB_WORKSPACE" ];then
    echo "GITHUB_WORKSPACE environemnt variable not set!"
    exit 1
fi
if [ "$#" -ne 1 ];then
    echo "Usage: ${0} [x86|x86_64|armhf|aarch64]"
    echo "Example: ${0} x86_64"
    exit 1
fi
set -e
set -o pipefail
set -x
source $GITHUB_WORKSPACE/build/lib.sh
init_lib $1

build_gdb() {
    cd "${BUILD_DIRECTORY}"
    wget https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz
    tar xf gmp-6.3.0.tar.xz
    cd gmp-6.3.0
    ./configure --host=arm-none-linux-gnueabi --disable-shared --enable-static
    make -j4
    make install

    cd "${BUILD_DIRECTORY}"
    wget https://www.mpfr.org/mpfr-current/mpfr-4.2.1.tar.gz
    tar xzf mpfr-4.2.1.tar.gz
    cd mpfr-4.2.1
    ./configure --host=arm-none-linux-gnueabi --disable-shared --enable-static --with-gmp-build=/work/gmp-6.3.0/
    make -j4
    make install

    fetch "$GIT_BINUTILS_GDB" "${BUILD_DIRECTORY}/binutils-gdb" git
    cd "${BUILD_DIRECTORY}/binutils-gdb/" || { echo "Cannot cd to ${BUILD_DIRECTORY}/binutils-gdb/"; exit 1; }
    git clean -fdx
    git checkout gdb-14.2-release
    CMD="CFLAGS=\"${GCC_OPTS}\" "
    CMD+="CXXFLAGS=\"${GXX_OPTS}\" "
    CMD+="LDFLAGS=\"-static\" "
    if [ "$CURRENT_ARCH" != "x86_64" ];then
        CMD+="CC_FOR_BUILD=\"/x86_64-linux-musl-cross/bin/x86_64-linux-musl-gcc\" "
        CMD+="CPP_FOR_BUILD=\"/x86_64-linux-musl-cross/bin/x86_64-linux-musl-g++\" "
    fi
    CMD+="${BUILD_DIRECTORY}/binutils-gdb/configure --build=x86_64-linux-musl --host=$(get_host_triple) "
    CMD+="--disable-shared --enable-static --enable-gdbserver --disable-nls --disable-inprocess-agent --with-gmp=/usr/local --with-mpfr=/usr/local"

    mkdir -p "${BUILD_DIRECTORY}/gdb_build"
    cd "${BUILD_DIRECTORY}/gdb_build/"
    eval "$CMD"
    make -j4
    
    strip "${BUILD_DIRECTORY}/gdb_build/gdb/gdb" "${BUILD_DIRECTORY}/gdb_build/gdbserver/gdbserver"
}

main() {
    build_gdb
    if [ ! -f "${BUILD_DIRECTORY}/gdb_build/gdb/gdb" ] || \
        [ ! -f "${BUILD_DIRECTORY}/gdb_build/gdbserver/gdbserver" ];then
        echo "[-] Building GDB ${CURRENT_ARCH} failed!"
        exit 1
    fi
    GDB_VERSION=$(get_version "${BUILD_DIRECTORY}/gdb_build/gdb/gdb --version |head -n1 |awk '{print \$4}'")
    GDBSERVER_VERSION=$(get_version "${BUILD_DIRECTORY}/gdb_build/gdbserver/gdbserver --version |head -n1 |awk '{print \$4}'")
    version_number=$(echo "$GDB_VERSION" | cut -d"-" -f2)
    cp "${BUILD_DIRECTORY}/gdb_build/gdb/gdb" "${OUTPUT_DIRECTORY}/gdb${GDB_VERSION}"
    cp "${BUILD_DIRECTORY}/gdb_build/gdbserver/gdbserver" "${OUTPUT_DIRECTORY}/gdbserver${GDBSERVER_VERSION}"
    echo "[+] Finished building GDB ${CURRENT_ARCH}"

    echo "PACKAGED_NAME=gdb${GDB_VERSION}" >> $GITHUB_OUTPUT
    echo "PACKAGED_NAME_PATH=/output/*" >> $GITHUB_OUTPUT
    echo "PACKAGED_VERSION=${version_number}" >> $GITHUB_OUTPUT
}

main
