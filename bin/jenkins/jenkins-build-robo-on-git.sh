#!/opt/bb/bin/bash

if [[ -z "$WORKSPACE" ]]
then \
    echo Must specify WORKSPACE environment variable
    exit 1
fi

DPKG_LOCATION=/bb/bde/bdebuild/jenkins/$(hostname)/dpkg
export DPKG_LOCATION
mkdir -p $DPKG_LOCATION

echo Operating in WORKSPACE $WORKSPACE and DPKG_LOCATION $DPKG_LOCATION

RETRY="$WORKSPACE/source/bde-tools/bin/retry -v -x nonzero -a 3 -p 60 -t 0 "

cd "$DPKG_LOCATION"

if [ $? -ne 0 ]
then \
    echo FATAL: Unable to cd into $DPKG_LOCATION
    exit 1
fi

echo Setting up PATH for dpkg

#START Copied from devgit:deveng/chimera contrib/dpkg

# Enable PATH settings required for the use of the dpkg framework.
# See https://cms.prod.bloomberg.com/team/display/sb/DPKG for details.
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
if test -d /opt/swt/bin
then
    for OVERRIDE in \
        /opt/swt/bin/readlink /opt/swt/bin/tar /opt/swt/bin/gmake \
        /opt/swt/bin/find
    do
        PATH=$(/usr/bin/dirname $(/opt/swt/bin/readlink "$OVERRIDE")):$PATH
    done
    PATH=$PATH:/bbsrc/bin/builddeb/prod/bin:/bbs/bin/dpkg/bin
else
    echo "FATAL: contrib/dpkg can only be used with /opt/swt/bin present" >&2
    exit 1
fi

#END   Copied from devgit:deveng/chimera contrib/dpkg

if [[ ! -d data ]]
then \
    echo Initializing DPKG distro - should be needed only once
    dpkg-distro-dev init .
fi

echo Synchronizing source trees
$RETRY rsync -a $WORKSPACE/source/ ./new-source/ 2>&1

if [ $? -ne 0 ]
then \
    echo FATAL: rsync failed from $WORKSPACE/source/ to ./new-source/
    exit 1
fi

echo ====================================
echo ======= BDE DPKG BUILD PHASE =======
echo ====================================

for package in new-source/bde-{oss-,internal-,}tools new-source/bsl* new-source/bde-core new-source/a_cdb2 new-source/bde-{bb,bdx}
do \
    echo "    ================================"
    echo "    ======= BUILDING $package"
    echo "    ================================"

    time $RETRY dpkg-distro-dev build $package 2>&1

    if [ $? -ne 0 ]
    then \
        echo FATAL: failure building $package
        exit 1
    fi
done

echo =========================================
echo ======= BUILDALL DPKG BUILD PHASE =======
echo =========================================

time $RETRY dpkg-distro-dev buildall 2>&1

if [ $? -ne 0 ]
then \
    echo FATAL: Failure in buildall step
    exit 1
fi

#BINARY_PACKAGES=$(grep -i '^Package:' source/b*/debian/control   \
#                | awk '{print $NF}'                              \
#                | sort -u                                        \
#                | grep -v 'RSSUITE'                              \
#                | perl -e'my $line=join ",", map {chomp; $_} <>;
#                          print $line,"\n"')
#dpkg-refroot-install $BINARY_PACKAGES

echo =========================================
echo ======= REFROOT-INSTALL PHASE ===========
echo =========================================

# Echo a safe # of 'Y' lines so any retries get prompt satisfied.
perl -e'print "Y\n"x10' \
    | time $RETRY dpkg-refroot-install --select robobuild-meta 2>&1

if [ $? -ne 0 ]
then \
    echo FATAL: Failure in dpkg-refroot-install step
    exit 1
fi


echo ================================
echo ======= ROBO BUILD PHASE =======
echo ================================

cd $WORKSPACE/robo

if [ $? -ne 0 ]
then \
    echo FATAL: could not cd in to robo subdir
    exit 1
fi

mkdir -p logs

src_root=$(pwd)/trunk build_root=$(pwd)/build \
    . /bbsrc/bin/prod/bin/build/build_env

echo "    ================================"
echo "    ======== BUILD_PREBUILD ========"
echo "    ================================"

time $RETRY /bbsrc/bin/prod/bin/build/build_prebuild 2>&1

if [ $? -ne 0 ]
then \
    echo FATAL: build_prebuild failed
    exit 1
fi


echo "    ================================"
echo "    ======== ROBO LIB BUILD ========"
echo "    ================================"

mkdir -p build
cd       build

DPKG_DISTRIBUTION="unstable --distro-override=\"$DPKG_LOCATION\"/"      \
    time /opt/swt/install/make-3.82/bin/make --no-print-directory -j8 -k     \
    -f ../trunk/etc/buildlibs.mk INSTALLLIBDIR=$(pwd)/lib/              \
    TARGET=install robo_prebuild_libs subdirs 2>&1                      \
    | tee logs/build.$(hostname).$(date +"%Y%m%d-%H%M%S").log
