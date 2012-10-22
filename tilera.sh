#!/bin/bash
#
#Copyright: (C) 2012 Agustin Henze <tin@sluc.org.ar>
#
#License: GPL-3
#This package is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This package is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this package; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

set -a

# Directories
ROOT_DIR="${PWD}"
SOURCES="${ROOT_DIR}/sources"
UNPACKED="${ROOT_DIR}/unpacked"
BUILD="${ROOT_DIR}/build"
DESTDIR="${ROOT_DIR}/install"
STAMPS="${ROOT_DIR}/stamps"
mkdir -p "${SOURCES}"
mkdir -p "${UNPACKED}"
mkdir -p "${BUILD}"
mkdir -p "${DESTDIR}"
mkdir -p "${STAMPS}"

PREFIX=""
TARGET="tilepro-unknown-linux-gnu"

TILE_URL_TILEPRO=http://www.tilera.com/scm/tilepro-x86_64.tar.bz2
TILE_URL_BINUTILS=ftp://sourceware.org/pub/binutils/snapshots/binutils-2.22.90.tar.bz2
TILE_URL_LINUX_KERNEL=https://www.kernel.org/pub/linux/kernel/v3.0/linux-3.2.32.tar.bz2
TILE_URL_GLIBC=ftp://ftp.gnu.org/gnu/libc/glibc-2.16.0.tar.xz
TILE_URL_GCC=ftp://ftp.gnu.org/gnu/gcc/gcc-4.7.2/gcc-4.7.2.tar.bz2
TILE_URL_GDB=ftp://ftp.gnu.org/gnu/gdb/gdb-7.5.tar.bz2

# How many cpus there
if [ "x${CPUS}" == "x" ]; then
    if which getconf > /dev/null; then
        CPUS=$(getconf _NPROCESSORS_ONLN)
    else
        CPUS=1
    fi

    MAKEFLAGS=-j$((CPUS + 1))
else
    MAKEFLAGS=-j${CPUS}
fi

# Log a message out to the console
function log {
    echo "******************************************************************"
    echo "* $*"
    echo "******************************************************************"
}

# Fetch a versioned file from a URL
function fetch {
    if [ ! -e ${STAMPS}/$1.fetch ]; then
        log "Downloading $1 sources..."
        wget -c --no-passive-ftp --no-check-certificate -O $3 $2 && touch ${STAMPS}/$1.fetch
    fi
}

function unpack {
    if [ -e ${STAMPS}/$1.fetch ]; then
        if [ ! -e ${STAMPS}/$1.unpacked ]; then
            log "Unpacking $1 sources..."
            if [ "x$3" == "x" ]; then
                OUT=${UNPACKED}
            else
                OUT=$3
            fi
            tar -C ${OUT} -xvf $2 && touch ${STAMPS}/$1.unpacked
        fi
    fi
}

# Fetch all urls
for URL in $(set | grep TILE_URL_); do
    VAR_ENV=$(echo "${URL}" | sed 's@=.*@@g')
    TOOL_DIR=$(basename $(echo ${!VAR_ENV} | sed 's@\(.*\)\.tar\..*@\1@g'))
    TOOL_NAME=$(echo "${VAR_ENV}" | sed 's@TILE_URL_\(.*\)@\1@g')
    TOOL_VERSION=$(echo ${!VAR_ENV} | sed 's@.*\-\(.*\)\.tar\..*@\1@g')
    URL=${!VAR_ENV}
    OUT=${SOURCES}/$(basename $URL)
    export ${TOOL_NAME}=${TOOL_DIR} ${TOOL_NAME}_VERSION=${TOOL_VERSION}
    fetch ${TOOL_DIR} ${URL} ${OUT}
    unpack ${TOOL_DIR} ${OUT}
done

# Vars env
export LDFLAGS="${LDFLAGS} -L${DESTDIR}/${TARGET}/lib"
export PATH=${DESTDIR}/bin:${PATH}

# Binutils
if [ ! -e ${STAMPS}/${BINUTILS}.build ]; then
    log "Building ${BINUTILS}..."
    rm -rf ${BUILD}/${BINUTILS} && mkdir -p ${BUILD}/${BINUTILS}
    cd ${BUILD}/${BINUTILS}
    ${UNPACKED}/${BINUTILS}/configure \
        --target=${TARGET} \
        --with-sysroot=${DESTDIR} \
        --prefix=${PREFIX}
    make all
    make install
    cd ${ROOT_DIR}
    touch ${STAMPS}/${BINUTILS}.build
fi

# Linux kernel
if [ ! -e ${STAMPS}/${LINUX_KERNEL}.headers ]; then
    log "Installing ${LINUX_KERNEL} headers..."
    rm -rf ${BUILD}/${LINUX_KERNEL} && mkdir -p ${BUILD}/${LINUX_KERNEL}
    cd ${UNPACKED}/${LINUX_KERNEL}
    make headers_install ARCH=tilepro O=${BUILD}/${LINUX_KERNEL}
    mkdir -p ${DESTDIR}/tile/usr
    cp -r ${BUILD}/${LINUX_KERNEL}/usr/include ${DESTDIR}/tile/usr/
    mkdir -p ${DESTDIR}/lib/gcc/${TARGET}
    ln -sf ../../tile ${DESTDIR}/lib/gcc/sysroot
    cd ${ROOT_DIR}
    touch ${STAMPS}/${LINUX_KERNEL}.headers
fi

# GCC 1st stage
if [ ! -e ${STAMPS}/${GCC}.build ]; then
    log "Building ${GCC}..."
    rm -rf ${BUILD}/${GCC} && mkdir -p ${BUILD}/${GCC}
    cd ${BUILD}/${GCC}
    ${UNPACKED}/${GCC}/configure \
        --target=${TARGET} \
        --with-gas \
        --disable-multilib \
        --enable-languages=c,c++ \
        --prefix=${PREFIX} \
        --with-build-time-tools=${DESTDIR}/bin \
        --with-sysroot=${UNPACKED}/${TILEPRO}/lib/gcc/sysroot \
        --oldincludedir=${UNPACKED}/${TILEPRO}/tile/usr/include
    make all
    make install
    cd ${ROOT_DIR}
    touch ${STAMPS}/${GCC}.build
fi

# Glibc
if [ ! -e ${STAMPS}/${GLIBC}.build ]; then
    log "Building ${GLIBC}..."
    GLIBC_PORTS=glibc-ports-${GLIBC_VERSION}
    fetch ${GLIBC_PORTS} ftp://ftp.gnu.org/gnu/libc/${GLIBC_PORTS}.tar.xz ${UNPACKED}/${GLIBC}/${GLIBC_PORTS}.tar.xz
    unpack ${GLIBC_PORTS} ${UNPACKED}/${GLIBC}/${GLIBC_PORTS}.tar.xz ${UNPACKED}/${GLIBC}
    rm -rf ${BUILD}/${GLIBC} && mkdir -p ${BUILD}/${GLIBC}
    cd ${BUILD}/${GLIBC}

    echo "install_root=${DESTDIR}/tile" > configparms
    ${UNPACKED}/${GLIBC}/configure \
        --enable-adds-ons=ports,nptl,libidn \
        --prefix=/usr \
        --with-headers=${BUILD}/${LINUX_KERNEL}/usr/include \
        --host=$TARGET \
        libc_cv_z_relro=yes \
        CC="${DESTDIR}/bin/${TARGET}-gcc" \
        CXX="${DESTDIR}/bin/${TARGET}-g++" \
        AR="${DESTDIR}/bin/${TARGET}-ar" \
        AS="${DESTDIR}/bin/${TARGET}-as" \
        LD="${DESTDIR}/bin/${TARGET}-ld" \
        NM="${DESTDIR}/bin/${TARGET}-nm" \
        RANLIB="${DESTDIR}/bin/${TARGET}-ranlib"
    make all
    make install
    touch ${STAMPS}/${GLIBC}.build
fi

# Gdb
# The target tilepro-unknown-linux-gnu is not yet supported
#if [ ! -e ${STAMPS}/${GDB}.build ]; then
    #log "Building ${GDB}..."
    #rm -rf ${BUILD}/${GDB} && mkdir -p ${BUILD}/${GDB}
    #cd ${BUILD}/${GDB}
    #${UNPACKED}/${GDB}/configure \
        #--target=${TARGET} \
        #--prefix=${PREFIX} \
        #--with-sysroot=${DESTDIR}/lib/gcc/sysroot
    #make all
    #make install
    #touch ${STAMPS}/${GDB}.build
#fi

# GCC 2nd stage
if [ ! -e ${STAMPS}/${GCC}.2build ]; then
    log "Building 2nd stage ${GCC}..."
    mkdir -p ${DESTDIR}/lib/gcc/${TARGET}/${GCC_VERSION}/include
    cat > ${DESTDIR}/lib/gcc/${TARGET}/${GCC_VERSION}/include/feedback.h << END
    #define FEEDBACK_ENTER_EXPLICIT(FUNCNAME, SECNAME, SIZE)
    #define FEEDBACK_ENTER(FUNCNAME)
    #define FEEDBACK_REENTER(FUNCNAME)
    #define FEEDBACK_ENTRY(FUNCNAME, SECNAME, SIZE)
END
    rm -rf ${BUILD}/${GCC} && mkdir -p ${BUILD}/${GCC}
    cd ${BUILD}/${GCC}
    ${UNPACKED}/${GCC}/configure \
        --target=${TARGET} \
        --with-gas \
        --disable-multilib \
        --enable-languages=c,c++ \
        --prefix=${PREFIX} \
        --with-build-time-tools=${DESTDIR}/bin \
        --with-sysroot=${DESTDIR}/lib/gcc/sysroot \
        --oldincludedir=${DESTDIR}/tile/usr/include
    make all
    make install
    cd ${ROOT_DIR}
    touch ${STAMPS}/${GCC}.2build
fi
