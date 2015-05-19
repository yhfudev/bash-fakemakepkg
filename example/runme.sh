#!/bin/bash
#####################################################################
# runme.sh for PKGBUILD file
#
# run the PKGBUILD file
#
# Copyright 2015 Yunhui Fu
# License: GPL v3.0 or later
#####################################################################
PACKAGER="Yunhui Fu <yhfudev@gmail.com>"

DN=$(pwd)

EXEC_MKPKG="makepkg -Asf"
EXEC_MKPKG="${DN}/makepkg.sh"

#export GIT_SSL_NO_VERIFY=true

check_install_tool() {
    if [ ! -x "${EXEC_MKPKG}" ]; then
        git clone https://github.com/yhfudev/bash-fakemakepkg.git "${DN}/fakemakepkg-git"
        EXEC_MKPKG="${DN}/fakemakepkg-git/makepkg.sh"
    fi
    if [ ! -x "${EXEC_MKPKG}" ]; then
        echo "error to get makepkg"
        exit 1
    fi
    ( cd "${DN}/fakemakepkg-git" && git pull )
}

check_install_tool

mkdir -p ${DN}/pkgdst
mkdir -p ${DN}/srcdst
mkdir -p ${DN}/srcpkgdst

if [ ! -f "${DN}/mymakepkg.conf" ]; then
    cat << EOF > "${DN}/mymakepkg.conf"
# generated by $0
# $(date)

PACKAGER="${PACKAGER}"
PKGEXT=.pkg.tar.gz

PKGDEST=${DN}/pkgdst
SRCDEST=${DN}/srcdst
SRCPKGDEST=${DN}/srcpkgdst

DLAGENTS=('ftp::/usr/bin/aria2c -UWget -s4 %u -o %o'
          'http::/usr/bin/aria2c -UWget -s4 %u -o %o'
          'https::/usr/bin/aria2c -UWget -s4 %u -o %o'
          'rsync::/usr/bin/rsync -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
EOF
fi

${EXEC_MKPKG} --config "${DN}/mymakepkg.conf" -p "${DN}/PKGBUILD" --dryrun
if [ ! "$?" = "0" ]; then
    echo "error in checking the script!"
    exit 1
fi
${EXEC_MKPKG} --config "${DN}/mymakepkg.conf" -p "${DN}/PKGBUILD"
