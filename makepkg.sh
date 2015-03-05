#!/bin/bash
#####################################################################
# makepkg.sh for PKGBUILD file
#
# This script will read the config/script from the PKGBUILD file
#
# Copyright 2015 Yunhui Fu
# License: GPL v3.0 or later
#####################################################################
my_getpath () {
  PARAM_DN="$1"
  shift
  #readlink -f
  DN="${PARAM_DN}"
  FN=
  if [ ! -d "${DN}" ]; then
    FN=$(basename "${DN}")
    DN=$(dirname "${DN}")
  fi
  cd "${DN}" > /dev/null 2>&1
  DN=$(pwd)
  cd - > /dev/null 2>&1
  echo "${DN}/${FN}"
}
#DN_EXEC=`echo "$0" | ${EXEC_AWK} -F/ '{b=$1; for (i=2; i < NF; i ++) {b=b "/" $(i)}; print b}'`
DN_EXEC=$(dirname $(my_getpath "$0") )
if [ ! "${DN_EXEC}" = "" ]; then
    DN_EXEC="$(my_getpath "${DN_EXEC}")/"
else
    DN_EXEC="${DN_EXEC}/"
fi

#####################################################################
# check log file
if [ "${FN_LOG}" = "" ]; then
    export FN_LOG="/dev/stderr"
fi
echo "test line" > "${FN_LOG}"
if [ ! "$?" = "0" ]; then
    export FN_LOG="$(pwd)/makepkg.log"
fi

#####################################################################

. ${DN_EXEC}/libbash.sh

if [ ! -f "${DN_EXEC}/libmkpkg.sh" ]; then
    echo "Error, not found file libmkpkg.sh"
    exit 1
fi

. ${DN_EXEC}/libmkpkg.sh

check_valid_path() {
    V=$(my_getpath "$1")
    if [[ "${V}" = "" || "${V}" = "/" ]]; then
        echo "Error: not set path variable: $1"
        exit 1
    fi
}

#####################################################################
# process arguments

usage () {
  PARAM_NAME="$1"
  echo "" >> "/dev/stderr"
  echo "mkpkg.sh" >> "/dev/stderr"
  echo "Written by yhfu, 2015-03" >> "/dev/stderr"
  echo "" >> "/dev/stderr"
  echo "${PARAM_NAME} [options]" >> "/dev/stderr"
  echo "" >> "/dev/stderr"
  echo "Options:" >> "/dev/stderr"
  echo -e "\t--help           Print this message" >> "/dev/stderr"
  echo -e "\t-c, --clean      Clean up work files after build" >> "/dev/stderr"
  echo -e "\t-C, --cleanbuild Remove \$srcdir/ dir before building the package" >> "/dev/stderr"
  echo -e "\t--config <file>  Use an alternate config file (instead of '/etc/makepkg.conf')" >> "/dev/stderr"
  echo "" >> "/dev/stderr"
}

FLG_CLEAN_BEFORE=0
FLG_CLEAN_AFTER=0
FN_PKGBUILD="PKGBUILD"
while [ ! "$1" = "" ]; do
    case "$1" in
    --help|-h)
        usage "$0"
        exit 0
        ;;
    --cleanbuild|-C)
        FLG_CLEAN_BEFORE=1
        ;;
    --clean|-c)
        FLG_CLEAN_AFTER=1
        ;;
    --config)
        shift
        read_user_config "$1"
        if [ ! "$?" = "0" ]; then
            echo "Error in read user config." >> "/dev/stderr"
            exit 1
        fi
        ;;
    --dryrun)
        MYEXEC="echo [DryRun]"
        ;;
    -p)
        shift
        FN_PKGBUILD="$1"
        ;;
    esac
    shift
done

if [ ! -f "${FN_PKGBUILD}" ]; then
    echo "Error, not found file PKGBUILD"
    exit 1
fi

setup_pkgdir
prepare_env

. "${FN_PKGBUILD}"

#####################################################################
DN_ORIGIN=$(pwd)

check_arch

check_makedepends

down_sources

echo "[DBG] check version: $(pkgver)"

check_valid_path "${srcdir}"

${MYEXEC} mkdir -p "${pkgdir}"
check_valid_path "${pkgdir}"
${MYEXEC} rm -rf "${pkgdir}"

if [ "${FLG_CLEAN_BEFORE}" = "1" ]; then
    rm -rf ${srcdir}/*
fi

checkout_sources

# call user's function
type prepare > /dev/null
if [ "$?" = "0" ]; then
    ${MYEXEC} cd "${DN_ORIGIN}"
    ${MYEXEC} prepare
fi

type build > /dev/null
if [ "$?" = "0" ]; then
    ${MYEXEC} cd "${DN_ORIGIN}"
    ${MYEXEC} build
fi

type package > /dev/null
if [ "$?" = "0" ]; then
    ${MYEXEC} cd "${DN_ORIGIN}"
    ${MYEXEC} mkdir -p "${pkgdir}"
    ${MYEXEC} package
fi

${MYEXEC} cd "${DN_ORIGIN}"
${MYEXEC} makepkg_tarpkg

if [ "${FLG_CLEAN_AFTER}" = "1" ]; then
    rm -rf ${srcdir}/*
fi

exit 0
