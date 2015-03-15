#!/bin/bash
VERSION=0.1

DANGER_EXEC=
MYEXEC=

#set MYEXEC to echo for dry run
#MYEXEC="echo [DryRun]"

if [ "${FN_LOG}" = "" ]; then
    FN_LOG="/dev/stderr"
fi

BASEDIR=$(pwd)

# import config file
if [ -f "/etc/makepkg.conf" ]; then
. /etc/makepkg.conf
fi

if [ "${PKGDEST}" = "" ]; then
    PKGDEST="${BASEDIR}/"
fi
if [ "${SRCDEST}" = "" ]; then
    SRCDEST="${BASEDIR}/"
fi
if [ "${SRCPKGDEST}" = "" ]; then
    SRCPKGDEST="${BASEDIR}/"
fi

read_user_config () {
    PARAM_FN="$1"
    . "${PARAM_FN}"
}

#####################################################################
# map pacman package names to debian's
# this will be removed once the big map 'ospkgset' in libbash.sh re-arranged to be the 'pacman first'

p2d_set() {
    PARAM_KEY=$1
    shift
    PARAM_DEBIAN=$1
    shift
    hput "p2d_pkg_Debian_$PARAM_KEY" "$PARAM_DEBIAN"
}

p2d_get () {
    PARAM_OS=$1
    shift
    PARAM_KEY=$1
    shift
    if [ "$PARAM_OS" = "Arch" ]; then
        echo "${PARAM_KEY}"
        return
    fi
    hget "p2d_pkg_${PARAM_OS}_${PARAM_KEY}"
}

#       Arch                Debian
p2d_set 'ncurses'           'libncurses-dev'
p2d_set 'yaourt'            ''
p2d_set 'multipath-tools'   'kpartx'
p2d_set 'qemu-user-static-exp'  'qemu-user-static'
p2d_set base-devel          build-essential
p2d_set abs                 devscripts
p2d_set yaourt              apt-file
p2d_set gcc-libs            build-essential
p2d_set lib32-libstdc++5    lib32stdc++6
p2d_set lib32-zlib          lib32z1
#debian: lib32gcc1 libc6-i386

p2d_set uboot-tools         u-boot-tools

p2d_set util-linux          uuid-runtime
p2d_set libarchive          bsdtar

#####################################################################

#source=(
        #"linux-${NAME_SHORT}::git+https://github.com/raspberrypi/linux.git"
        #"tools-${NAME_SHORT}::git+https://github.com/raspberrypi/tools.git"
        #"rpi-firmware::git+https://github.com/raspberrypi/firmware.git"
        #)
gen_detect_url () {
    PARAM_FN_AWK=$1
    if [ "${PARAM_FN_AWK}" = "" ]; then
        PARAM_FN_AWK="${FN_AWK_DET_URL}"
    fi

    cat << EOF > "${PARAM_FN_AWK}"
#!/usr/bin/awk
# split info from download URL
# Copyright 2015 Yunhui Fu
# License: GPL v3.0 or later

BEGIN {
    FN_OUTPUT=FNOUT
    if ("" == FN_OUTPUT) {
        FN_OUTPUT="guess-linux-dist-output-url"
        print "[DBG] Waring: use the default output file name: " FN_OUTPUT;
        print "[DBG]         please specify the output file name via 'awk -v FNOUT=outfile'";
    }
    dist_tool="wget";
    dist_url="";
    dist_rename="";
}
{
    # process url, such as "http://sample.com/path/to/unix-i386.iso"
    split (\$0, a, ":");
    if (length(a) < 2) {
        # local file
        dist_tool="local";
        dist_url=\$0;
        dist_rename=\$0;

    } else if (length(a) > 2) {
        dist_rename=a[1];
        split (a[3], b, "+");
        if (length(b) > 1) {
            dist_tool=b[1];
            dist_url=b[2] ":" a[4];
        } else {
            dist_tool="wget";
            dist_url=a[3] ":" a[4];
        }
    } else {
        # == 2
        split (a[1], b, "+");
        if (length(b) > 1) {
            dist_tool=b[1];
            dist_url=b[2] ":" a[2];
        } else {
            dist_tool="wget";
            dist_url=a[1] ":" a[2];
            dist_rename="\$(basename " a[1] ":" a[2] ")";
        }
    }
}

END {
    #print "[DBG]" \
        #" dist_tool=" (""==dist_tool?"unknown":dist_tool) \
        #" dist_url=" (""==dist_url?"unknown":dist_url) \
        #" dist_rename=" (""==dist_rename?"unknown":dist_rename) \
        #;
    print "DECLNXOUT_TOOL="   dist_tool    > FN_OUTPUT
    print "DECLNXOUT_URL="    dist_url    >> FN_OUTPUT
    print "DECLNXOUT_RENAME=" dist_rename >> FN_OUTPUT
}
EOF
}

which uuidgen
if [ ! "$?" = "0" ]; then
    echo "Error: not found uuidgen"
    exit 1
fi

FN_OUT=/tmp/libmkpkg-fnout-$(uuidgen).tmp
FN_AWK_DET_URL=/tmp/libmkpkg-awkdeturl-$(uuidgen).awk
clear_detect_url() {
    rm -f "${FN_AWK_DET_URL}" "${FN_OUT}"
}

detect_url() {
    PARAM_RAWURL="$1"
    if [ "${PARAM_RAWURL}" = "" ]; then
        echo "[DBG] internal parameter error!" >> "${FN_LOG}"
        exit 1
    fi

    DECLNXOUT_TOOL=wget
    DECLNXOUT_URL=
    DECLNXOUT_RENAME=

    if [ ! -f "${FN_AWK_DET_URL}" ]; then
        gen_detect_url "${FN_AWK_DET_URL}"
    fi
    echo "${PARAM_RAWURL}" | gawk -v FNOUT=${FN_OUT} -f "${FN_AWK_DET_URL}"
    if [ -f "${FN_OUT}" ]; then
        . "${FN_OUT}"
    fi
}

check_xxxsum_ok () {
    PARAM_DNFILE=$1
    shift
    PARAM_FNBASE=$1
    shift
    PARAM_CNT=$1
    shift
    PATH_FILE="${PARAM_FNBASE}"
    if [ ! "${PARAM_DNFILE}" = "" ]; then
        PATH_FILE="${PARAM_DNFILE}/${PARAM_FNBASE}"
    fi

    FLG_ERROR=1
#echo "[DBG] checking if file exist: ${PATH_FILE}" >> "${FN_LOG}"
    if [ -f "${PATH_FILE}" ]; then
#echo "[DBG] file exist: ${PATH_FILE}" >> "${FN_LOG}"
        FLG_ERROR=0
        if [[ ${#md5sums[*]} > ${PARAM_CNT} ]]; then
            if [ ! "${md5sums[${PARAM_CNT}]}" = "SKIP" ]; then
                MD5SUM=$(md5sum "${PATH_FILE}" | awk '{print $1}')
                if [ ! "${MD5SUM}" = "${md5sums[${PARAM_CNT}]}" ]; then
                    FLG_ERROR=1
                    echo "[DBG] file md5sum error: ${PATH_FILE}" >> "${FN_LOG}"
                    echo "[DBG] file md5sum=${MD5SUM}; md5[${PARAM_CNT}]=${md5sums[${PARAM_CNT}]}" >> "${FN_LOG}"
                fi
            fi
        fi
        
        if [[ ${#sha1sums[*]} > ${PARAM_CNT} ]]; then
            if [ ! "${sha1sums[${PARAM_CNT}]}" = "SKIP" ]; then
                SHASUM=$(sha1sum "${PATH_FILE}" | awk '{print $1}')
                if [ ! "${SHASUM}" = "${sha1sums[${PARAM_CNT}]}" ]; then
                    FLG_ERROR=1
                    echo "[DBG] file sha1sums error: ${PATH_FILE}" >> "${FN_LOG}"
                    echo "[DBG] file sha1sums=${SHASUM}; sha[${PARAM_CNT}]=${sha1sums[${PARAM_CNT}]}" >> "${FN_LOG}"
                fi
            fi
        fi
        if [[ ${#sha256sums[*]} > ${PARAM_CNT} ]]; then
            if [ ! "${sha256sums[${PARAM_CNT}]}" = "SKIP" ]; then
                SHASUM=$(sha256sum "${PATH_FILE}" | awk '{print $1}')
                if [ ! "${SHASUM}" = "${sha256sums[${PARAM_CNT}]}" ]; then
                    FLG_ERROR=1
                    echo "[DBG] file sha256sums error: ${PATH_FILE}" >> "${FN_LOG}"
                    echo "[DBG] file sha256sums=${SHASUM}; sha[${PARAM_CNT}]=${sha256sums[${PARAM_CNT}]}" >> "${FN_LOG}"
                fi
            fi
        fi
        if [[ ${#sha384sums[*]} > ${PARAM_CNT} ]]; then
            if [ ! "${sha384sums[${PARAM_CNT}]}" = "SKIP" ]; then
                SHASUM=$(sha384sum "${PATH_FILE}" | awk '{print $1}')
                if [ ! "${SHASUM}" = "${sha384sums[${PARAM_CNT}]}" ]; then
                    FLG_ERROR=1
                    echo "[DBG] file sha384sums error: ${PATH_FILE}" >> "${FN_LOG}"
                    echo "[DBG] file sha384sums=${SHASUM}; sha[${PARAM_CNT}]=${sha384sums[${PARAM_CNT}]}" >> "${FN_LOG}"
                fi
            fi
        fi
        if [[ ${#sha512sums[*]} > ${PARAM_CNT} ]]; then
            if [ ! "${sha512sums[${PARAM_CNT}]}" = "SKIP" ]; then
                SHASUM=$(sha512sum "${PATH_FILE}" | awk '{print $1}')
                if [ ! "${SHASUM}" = "${sha512sums[${PARAM_CNT}]}" ]; then
                    FLG_ERROR=1
                    echo "[DBG] file sha512sums error: ${PATH_FILE}" >> "${FN_LOG}"
                    echo "[DBG] file sha512sums=${SHASUM}; sha[${PARAM_CNT}]=${sha512sums[${PARAM_CNT}]}" >> "${FN_LOG}"
                fi
            fi
        fi
    fi
    if [ "${FLG_ERROR}" = "1" ]; then
        echo "false"
    else
        echo "true"
    fi
}

# 解包压缩文件
extract_file () {
  ARG_FN=$1
  if [ -f "${ARG_FN}" ]; then
    FN_CUR=`echo "${ARG_FN}" | awk -F/ '{name=$1; for (i=2; i <= NF; i ++) name=$i } END {print name}'`
    FN_BASE=`echo "${FN_CUR}" | awk -F. '{name=$1; for (i=2; i < NF; i ++) name=name "." $i } END {print name}'`

    case "${FN_CUR}" in
    *.tar.Z)
      echo "extract (tar) ${ARG_FN} ..."
      #compress -dc file.tar.Z | tar xvf -
      tar -xvZf "${ARG_FN}"
      ;;
    *.tar.gz)
      echo "extract (tar) ${ARG_FN} ..."
      tar -xzf "${ARG_FN}"
      ;;
    *.tar.bz2)
      echo "extract (tar) ${ARG_FN} ..."
      tar -xjf "${ARG_FN}"
      ;;
    *.tar.xz)
      echo "extract (tar) ${ARG_FN} ..."
      tar -xJf "${ARG_FN}"
      ;;
    *.cpio.gz)
      echo "extract (cpio) ${ARG_FN} ..."
      gzip -dc "${ARG_FN}" | cpio -div
      ;;
    *.gz)
      echo "extract (gunzip) ${ARG_FN} ..."
      gunzip -d -c "${ARG_FN}" > "${FN_BASE}.tmptmp"
      mv "${FN_BASE}.tmptmp" "${FN_BASE}"
      ;;
    *.bz2)
      echo "extract (bunzip2) ${ARG_FN} ..."
      bunzip2 -d -c "${ARG_FN}" > "${FN_BASE}.tmptmp"
      mv "${FN_BASE}.tmptmp" "${FN_BASE}"
      ;;
    *.xz)
      echo "extract (bunzip2) ${ARG_FN} ..."
      xz -d -c "${ARG_FN}" > "${FN_BASE}.tmptmp"
      mv "${FN_BASE}.tmptmp" "${FN_BASE}"
      ;;
    *.rpm)
      echo "extract (rpm) ${ARG_FN} ..."
      rpm2cpio "${ARG_FN}" | cpio -div
      ;;
    *.rar)
      echo "extract (unrar) ${ARG_FN} ..."
      unrar x "${ARG_FN}"
      ;;
    *.zip)
      echo "extract (unzip) ${ARG_FN} ..."
      unzip "${ARG_FN}"
      ;;
    *.deb)
      # ar xv "${ARG_FN}" && tar -xf data.tar.gz
      echo "extract (dpkg) ${ARG_FN} ..."
      dpkg -x "${ARG_FN}" .
      ;;
    *.dz)
      echo "extract (dictzip) ${ARG_FN} ..."
      dictzip -d -c "${ARG_FN}" > "${FN_BASE}.tmptmp"
      mv "${FN_BASE}.tmptmp" "${FN_BASE}"
      ;;
    *.Z)
      echo "extract (uncompress) ${ARG_FN} ..."
      gunzip -d -c "${ARG_FN}" > "${FN_BASE}.tmptmp"
      mv "${FN_BASE}.tmptmp" "${FN_BASE}"
      ;;
    *.a)
      echo "extract (tar) ${ARG_FN} ..."
      tar -xv "${FN_BASE}"
      ;;
    *.tgz)
      echo "extract (tar) ${ARG_FN} ..."
      tar -xzf "${ARG_FN}"
      ;;
    *.tbz)
      echo "extract (tar) ${ARG_FN} ..."
      tar -xjf "${ARG_FN}"
      ;;
    *.cgz)
      echo "extract (cpio) ${ARG_FN} ..."
      gzip -dc "${ARG_FN}" | cpio -div
      ;;
    *.cpio)
      echo "extract (cpio) ${ARG_FN} ..."
      cpio -div "${ARG_FN}"
      ;;
    *)
      echo "SKIP ${ARG_FN}: unknown type ..."
      ;;
    esac
  else
    echo "Not found file: ${ARG_FN}"
    return 1
  fi
  return 0;
}

down_sources() {
    ${MYEXEC} mkdir -p "${SRCDEST}"
    clear_detect_url
    CNT1=1
    #for i in ${source[*]} ; do
    while [ $CNT1 -le ${#source[*]} ] ; do
        # we have to use CNT, because we need use the index for sha1sum array!
        CNT=$(( $CNT1 - 1 ))
        i=${source[$CNT]}
        echo "[DBG] down url=$i" >> "${FN_LOG}"
        detect_url "$i"
        if [ "${DECLNXOUT_TOOL}" = "" ]; then
            echo "Error: no tool" >> "${FN_LOG}"
            exit 0
        fi
        if [ "${DECLNXOUT_URL}" = "" ]; then
            echo "Error: no url" >> "${FN_LOG}"
            exit 0
        fi
        if [ "${DECLNXOUT_RENAME}" = "" ]; then
            DECLNXOUT_RENAME=$(basename ${DECLNXOUT_URL})
        fi
        #echo "TOOL=${DECLNXOUT_TOOL}; URL=${DECLNXOUT_URL}; rename=${DECLNXOUT_RENAME}; " >> "${FN_LOG}"
        case ${DECLNXOUT_TOOL} in
        git)
            DN0=$(pwd)
            cd "${SRCDEST}"
            case ${DECLNXOUT_RENAME} in
            *.git)
                DECLNXOUT_RENAME=$(echo "${DECLNXOUT_RENAME}" | ${EXEC_AWK} -F. '{b=$1; for (i=2; i < NF; i ++) {b=b "." $(i)}; print b}')
                ;;
            esac
            if [ -d "${DECLNXOUT_RENAME}" ]; then
                cd "${DECLNXOUT_RENAME}"
                echo "[DBG] try git fetch ..."
                ${MYEXEC} git fetch --all
                cd -
            else
                echo "[DBG] try git clone --no-checkout ${DECLNXOUT_URL} ${DECLNXOUT_RENAME} ..."
                ${MYEXEC} git clone --no-checkout "${DECLNXOUT_URL}" ${DECLNXOUT_RENAME}
                cd ${DECLNXOUT_RENAME}
                ${MYEXEC} echo "for branch in \$(git branch -a | grep remotes | grep -v HEAD | grep -v master); do git branch --track \${branch##*/} \$branch ; done" | ${MYEXEC} bash
                ${MYEXEC} git fetch --all
                #${MYEXEC} git pull --all
                cd -
            fi
            cd ${DN0}
            ;;
        hg)
            DN0=$(pwd)
            cd "${SRCDEST}"
            if [ -d "${DECLNXOUT_RENAME}" ]; then
                cd "${DECLNXOUT_RENAME}"
                echo "[DBG] try hg pull ..."
                ${MYEXEC} hg pull
                cd -
            else
                echo "[DBG] try hg clone --no-checkout ${DECLNXOUT_URL} ${DECLNXOUT_RENAME} ..."
                ${MYEXEC} hg clone --no-checkout "${DECLNXOUT_URL}" ${DECLNXOUT_RENAME}
            fi
            cd ${DN0}
            ;;
        svn)
            DN0=$(pwd)
            cd "${SRCDEST}"
            if [ -d "${DECLNXOUT_RENAME}" ]; then
                cd "${DECLNXOUT_RENAME}"
                echo "[DBG] try svn update ..."
                ${MYEXEC} svn update
                cd -
            else
                echo "[DBG] try svn checkout ${DECLNXOUT_URL} ${DECLNXOUT_RENAME} ..."
                ${MYEXEC} svn checkout "${DECLNXOUT_URL}" ${DECLNXOUT_RENAME}
            fi
            cd ${DN0}
            ;;
        wget|local)
            FNDOWN="${DECLNXOUT_RENAME}"
            if [ "${FNDOWN}" = "" ]; then
                FNDOWN=$(echo "${DECLNXOUT_URL}" | awk -F? '{print $1}' | xargs basename)
            fi
            if [ "${DECLNXOUT_TOOL}" = "wget" ]; then
#echo "[DBG] check wget file: ${FNDOWN}" >> "${FN_LOG}"
                FLG_OK=$(check_xxxsum_ok "${SRCDEST}" "${FNDOWN}" ${CNT})
            else
#echo "[DBG] check local file: ${FNDOWN}" >> "${FN_LOG}"
                FLG_OK=$(check_xxxsum_ok "${BASEDIR}" "${FNDOWN}" ${CNT})
            fi
            if [ "${FLG_OK}" = "false" ]; then
                echo "[DBG] DECLNXOUT_RENAME=${DECLNXOUT_RENAME}, FNDOWN=${FNDOWN}" >> "${FN_LOG}"
                if [ "${DECLNXOUT_TOOL}" = "wget" ]; then
                    ${MYEXEC} wget -O "${SRCDEST}/${FNDOWN}" "${DECLNXOUT_URL}"
                else
                    echo "Error in checking file: ${DECLNXOUT_RENAME}" >> "${FN_LOG}"
                    exit 1
                fi
#else echo "[DBG] check file ok: ${FNDOWN}" >> "${FN_LOG}"
            fi
            ;;
        *)
            DN0=$(pwd)
            cd "${SRCDEST}"
            echo "[DBG] try ${DECLNXOUT_TOOL} ${DECLNXOUT_URL} ${DECLNXOUT_RENAME} ..."
            ${MYEXEC} ${DECLNXOUT_TOOL} "${DECLNXOUT_URL}" ${DECLNXOUT_RENAME}
           cd ${DN0}
            ;;
        esac
        CNT1=$(( ${CNT1} + 1 ))
    done
}

checkout_sources() {
    if [ "${srcdir}/" = "/" ]; then
        echo "Error: not set repo srcdir"
        exit 1
    else
        echo "DONT remove ${srcdir}/!"
    fi
    ${MYEXEC} mkdir -p "${srcdir}"
    clear_detect_url
    for i in ${source[*]} ; do
        echo "[DBG] checkout url=$i" >> "${FN_LOG}"
        detect_url "$i"
        if [ "${DECLNXOUT_TOOL}" = "" ]; then
            echo "Error: no tool" >> "${FN_LOG}"
            exit 0
        fi
        if [ "${DECLNXOUT_URL}" = "" ]; then
            echo "Error: no url" >> "${FN_LOG}"
            exit 0
        fi
        if [ "${DECLNXOUT_RENAME}" = "" ]; then
            DECLNXOUT_RENAME=$(basename ${DECLNXOUT_URL})
        fi
        #echo "TOOL=${DECLNXOUT_TOOL}; URL=${DECLNXOUT_URL}; rename=${DECLNXOUT_RENAME}; " >> "${FN_LOG}"
        FN_BASE="${DECLNXOUT_RENAME}"
        if [ "${FN_BASE}" = "" ]; then
            FN_FULL=$(echo "${DECLNXOUT_URL}" | awk -F? '{print $1}' | xargs basename)
            FN_BASE=$(echo "${FN_FULL}" | ${EXEC_AWK} -F. '{b=$1; for (i=2; i < NF; i ++) {b=b "." $(i)}; print b}')
        fi
        case ${DECLNXOUT_TOOL} in
        git)
            case ${FN_BASE} in
            *.git)
                FN_BASE=$(echo "${FN_BASE}" | ${EXEC_AWK} -F. '{b=$1; for (i=2; i < NF; i ++) {b=b "." $(i)}; print b}')
                ;;
            esac
            echo "[DBG] git FN_BASE=${FN_BASE}"
            if [ -d "${srcdir}/${FN_BASE}" ]; then
                cd "${srcdir}/${FN_BASE}"
                echo "[DBG] try git 'revert' ..."
                #${MYEXEC} git ls-files | ${MYEXEC} xargs git checkout --
                ${MYEXEC} git status | grep "modified:" | awk '{print $2}' | ${MYEXEC} xargs git checkout --
                ${MYEXEC} git fetch --all
                ${MYEXEC} git pull --all
                cd -
            else
                echo "[DBG] try git clone ${SRCDEST}/${FN_BASE} ${srcdir}/${FN_BASE} ..."
                ${MYEXEC} git clone "${SRCDEST}/${FN_BASE}" "${srcdir}/${FN_BASE}"
                #cd "${srcdir}/${FN_BASE}"
                #${MYEXEC} echo "for branch in \$(git branch -a | grep remotes | grep -v HEAD | grep -v master); do git branch --track \${branch##*/} \$branch ; done" | ${MYEXEC} bash
                #${MYEXEC} git fetch --all
                #${MYEXEC} git pull --all
                #cd -
            fi
            ;;
        hg)
            if [ -d "${srcdir}/${FN_BASE}" ]; then
                cd "${srcdir}/${FN_BASE}"
                echo "[DBG] try hg 'revert' ..."
                ${MYEXEC} hg update --clean
                ${MYEXEC} hg revert --all
                cd -
            else
                echo "[DBG] try hg clone ${SRCDEST}/${FN_BASE} ${srcdir}/${FN_BASE} ..."
                ${MYEXEC} hg clone "${SRCDEST}/${FN_BASE}" "${srcdir}/${FN_BASE}"
            fi
            ;;
        svn)
            if [ -d "${srcdir}/${FN_BASE}" ]; then
                cd "${srcdir}/${FN_BASE}"
                echo "[DBG] try svn 'revert' ..."
                ${MYEXEC} svn revert --recursive
                ${MYEXEC} svn update
                cd -
            else
                echo "[DBG] try cp -rp ${SRCDEST}/${FN_BASE} ${srcdir}/${FN_BASE} ..."
                ${MYEXEC} cp -rp "${SRCDEST}/${FN_BASE}" "${srcdir}/${FN_BASE}"
                ${MYEXEC} svn revert --recursive
                ${MYEXEC} svn update
            fi
            ;;
        wget)
            FNDOWN=$(echo "${DECLNXOUT_RENAME}" | awk -F? '{print $1}' | xargs basename)
            ${MYEXEC} rm -f "${srcdir}/${FNDOWN}"
            ${MYEXEC} ln -s "${SRCDEST}/${FNDOWN}" "${srcdir}/${FNDOWN}"
            ( cd ${srcdir}/ && ${MYEXEC} extract_file "${srcdir}/${FNDOWN}" )
            ;;
        local)
            FNDOWN=$(echo "${DECLNXOUT_RENAME}" | awk -F? '{print $1}' | xargs basename)
            ${MYEXEC} rm -f "${srcdir}/${FNDOWN}"
            ${MYEXEC} ln -s "${BASEDIR}/${FNDOWN}" "${srcdir}/${FNDOWN}"
            (cd ${srcdir}/ && ${MYEXEC} extract_file "${srcdir}/${FNDOWN}" )
            ;;
        *)
            DN0=$(pwd)
            echo "[DBG] cp -rp ${SRCDEST}/${FNDOWN} ${srcdir}/${FNDOWN} ..."
            ${MYEXEC} cp -rp "${SRCDEST}/${FNDOWN}" "${srcdir}/${FNDOWN}"
            (cd ${srcdir}/ && ${MYEXEC} extract_file "${srcdir}/${FNDOWN}" )
            cd ${DN0}
            ;;
        esac
    done
}

ARCH_OUT=
check_arch() {
    V=$(uname -m)
    R=
    for i in ${arch[*]} ; do
        if [ "${i}" = "${V}" ]; then
            R=${V}
        fi
        if [ "${i}" = "all" ]; then
            R=all
            break
        fi
    done
    if [ "${R}" = "" ]; then
        echo "Error: not support arch: $arch"
        exit 1
    fi
    ARCH_OUT="${R}"
}

makepkg_tarpkg() {
    PARAM_PKGNAME=$1
    shift

    PREFIX="${PARAM_PKGNAME}-${ARCH_OUT}"
    type pkgver 2>&1 > /dev/null
    if [ "$?" = "0" ]; then
        PREFIX="${PARAM_PKGNAME}-$(pkgver)-${ARCH_OUT}"
    fi
    echo "[DBG] PREFIX=${PREFIX}"

    MYPKGVER=${pkgver}
    type pkgver 2>&1 > /dev/null
    if [ "$?" = "0" ]; then
        MYPKGVER=$(pkgver)
    fi
    MYPACKAGER=${PACKAGER}
    if [ "${PACKAGER}" = "" ]; then
        MYPACKAGER="Unknown Packager"
    fi

    cd "${pkgdir}"
    MYSIZE=$(du -sb | awk '{print $1}')

    cat << EOF > .PKGINFO
# Generated by libmkpkg.sh $VERSION
# $(date)
pkgname = ${PARAM_PKGNAME}
pkgver = ${MYPKGVER}
pkgdesc = ${pkgdesc}
url = ${url}
builddate = $(date +%s)
packager = ${MYPACKAGER}
size = ${MYSIZE}
arch = ${ARCH_OUT}
license = ${license}
backup = ${backup}
EOF
    for i in ${makedepends[*]} ;    do echo "makedepend = ${i}" >> .PKGINFO ; done
    for i in ${groups[*]} ;         do echo "groups = ${i}"     >> .PKGINFO ; done
    for i in ${backup[*]} ;         do echo "backup = ${i}"     >> .PKGINFO ; done
    for i in ${replaces[*]} ;       do echo "replaces = ${i}"   >> .PKGINFO ; done
    for i in ${conflicts[*]} ;      do echo "conflicts = ${i}"  >> .PKGINFO ; done
    for i in ${provides[*]} ;       do echo "provides = ${i}"   >> .PKGINFO ; done
    for i in ${depends[*]} ;        do echo "depends = ${i}"    >> .PKGINFO ; done
    for i in ${optdepends[*]} ;     do echo "optdepends = ${i}" >> .PKGINFO ; done

    if [ ! "${install}" = "" ]; then
        cp "${BASEDIR}/${install}" ".INSTALL"
    else
        touch ".INSTALL"
    fi
    chmod 755 ".INSTALL"

    case ${PKGEXT} in
    *.tar.xz)
        ${MYEXEC} tar -Jcf "${PKGDEST}/${PREFIX}.pkg.tar.xz" .
        ;;
    *.tar.bz2)
        ${MYEXEC} tar -jcf "${PKGDEST}/${PREFIX}.pkg.tar.bz2" .
        ;;
    *)
        ${MYEXEC} tar -zcf "${PKGDEST}/${PREFIX}.pkg.tar.gz" .
        ;;
    esac
}

call_packages() {

    type package 2>&1 > /dev/null
    if [ "$?" = "0" ]; then
        echo "[DBG] call user package() ..." >> "${FN_LOG}"
        ${MYEXEC} cd "${srcdir}"
        ${MYEXEC} mkdir -p "${pkgdir}"
        ${MYEXEC} package

        echo "[DBG] make package ..." >> "${FN_LOG}"
        ${MYEXEC} cd "${srcdir}"
        ${MYEXEC} makepkg_tarpkg "${pkgname}"
    else
        for i in ${pkgname[*]} ; do
            F=package_$i
            type $F 2>&1 > /dev/null
            if [ "$?" = "0" ]; then
                echo "[DBG] call user $F() ..." >> "${FN_LOG}"
                prepare_env "${i}"

                ${MYEXEC} cd "${srcdir}"
                ${MYEXEC} rm -rf "${pkgdir}"
                ${MYEXEC} mkdir -p "${pkgdir}"
                ${MYEXEC} $F

                echo "[DBG] make package for $F ..." >> "${FN_LOG}"
                ${MYEXEC} cd "${srcdir}"
                ${MYEXEC} makepkg_tarpkg "${i}"
            fi
        done
    fi
}


PKGEXT=.pkg.tar.xz

setup_pkgdir () {
    FN="/tmp/libmkpkg-pkgname-$(uuidgen)"
    egrep "\w*pkgbase\w*=|\w*pkgname\w*=" "${FN_PKGBUILD}" > "${FN}"
    . "${FN}"
    export pkgname
}

prepare_env() {
    PARAM_PKGNAME=$1
    shift

    if [ "${PARAM_PKGNAME}" = "" ]; then
        if [ 1 -le ${pkgname[*]} ]; then
            PARAM_PKGNAME=${pkgname}
        else
            PARAM_PKGNAME=${pkgname[0]}
        fi
    fi

    srcdir="${BASEDIR}/src"
    pkgdir="${BASEDIR}/pkg/${PARAM_PKGNAME}"

    echo "[DBG] mkdir for required dir ..."
    echo "[DBG] srcdir=${srcdir}"
    echo "[DBG] pkgdir=${pkgdir}"
    echo "[DBG] SRCDEST=${SRCDEST}"
    echo "[DBG] SRCPKGDEST=${SRCPKGDEST}"
    ${MYEXEC} mkdir -p "${srcdir}"
    ${MYEXEC} mkdir -p "${pkgdir}"
    ${MYEXEC} mkdir -p "${SRCDEST}"
}

check_makedepends() {
#set -x
    # add internal depends:
    makedepends+=(
        'util-linux' # for uuidgen
        )

    echo "Checking runtime dependencies..."
    if [ 1 -le ${#optdepends[*]} ]; then
        echo ""
        echo "You may also want to install following packages before this task to get the most wonderful experiences:"
        for i in ${optdepends[*]} ; do
            echo "  $i"
        done
        echo ""
    fi
    LIST_ALT=
    LIST_MISS=
    for i in ${makedepends[*]} ; do
        PKG1x5=$(p2d_get "Debian" "$i")
        if [ "${PKG1x5}" = "" ]; then
            PKG1x5="$i"
        fi
        RET=$(check_installed_package ${PKG1x5})
        #echo "Checking package '$i(${PKG1x5})', return ${RET}"
        if [ ! "$RET" = "ok" ]; then
            RET=$(check_available_package ${PKG1x5})
            if [ ! "$RET" = "ok" ]; then
                LIST_ALT="${LIST_ALT} ${PKG1x5}"
            else
                LIST_MISS="${LIST_MISS} ${PKG1x5}"
            fi
        fi
    done
    if [ ! "${LIST_MISS}" = "" ]; then
        echo "Installing missing dependencies..."
        RET=$(install_package ${LIST_MISS})
        if [ ! "$RET" = "ok" ]; then
            echo "Error return: ${RET}"
            echo "Error in install packages: ${LIST_MISS}"
            exit 1
        fi
    fi
    if [ ! "${LIST_ALT}" = "" ]; then
        echo "Installing missing dependencies with 3rd tools..."
        RET=$(install_package_alt ${LIST_ALT})
        if [ ! "$RET" = "ok" ]; then
            echo "Error return: ${RET}"
            echo "Error in install packages: ${LIST_ALT}"
            exit 1
        fi
    fi
#set +x
}

#NAME_SHORT=rpi

#source=(
        #"linux-${NAME_SHORT}::git+https://github.com/raspberrypi/linux.git"
        #"tools-${NAME_SHORT}::git+https://github.com/raspberrypi/tools.git"
        #"rpi-firmware::git+https://github.com/raspberrypi/firmware.git"
        #"firmware::git+https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
        #"mac80211.patch::https://raw.github.com/offensive-security/kali-arm-build-scripts/master/patches/kali-wifi-injection-3.12.patch"
        #"kali-arm-build-scripts::git+https://github.com/yhfudev/kali-arm-build-scripts.git"
        #)

#down_sources
#checkout_sources

