#!/opt/bb/bin/bash

if [[ -z "$WORKSPACE" ]]
then \
    echo Must specify WORKSPACE environment variable
    exit 1
fi

if [[ -z "$GIT_LOCATION" ]]
then \
    echo Must specify GIT_LOCATION environment variable
    exit 1
fi

echo Operating in WORKSPACE $WORKSPACE

cd "$WORKSPACE"

if [ $? -ne 0 ]
then \
    echo FATAL: Unable to cd into $WORKSPACE
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

if [[ ! -l source ]]
then \
    if [[ ! -d source ]]
    then \
        echo FATAL: source directory is missing, and is not a symlink
        exit 1
    fi

    echo Moving source directory to NFS for dpkg

    rsync -av source/ $GIT_LOCATION/
    rm -rf source
    ln -s $GIT_LOCATION .

    echo "    ===== moved source"
    echo "    " $(ls -ld source)
fi

if [[ ! -d data ]]
then \
    echo Initializing DPKG distro - should be needed only once
    dpkg-distro-dev init .
fi

echo ================================
echo ======= DPKG BUILD PHASE =======
echo ================================

for package in source/bde*tools source/bsl* source/bde-{core,bb,bdx}
do \
    dpkg-distro-dev build $package

    if [ $? -ne 0 ]
    then \
        echo FATAL: failure building $package
        exit 1
    fi
done

BINARY_PACKAGES=$(grep -i '^Package:' source/b*/debian/control   \
                | awk '{print $NF}'                              \
                | sort -u                                        \
                | grep -v 'RSSUITE'                              \
                | perl -e'my $line=join ",", map {chomp; $_} <>;
                          print $line,"\n"')
dpkg-refroot-install $BINARY_PACKAGES

echo ================================
echo ======= ROBO BUILD PHASE =======
echo ================================

cd robo

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

/bbsrc/bin/prod/bin/build/build_prebuild

echo "    ================================"
echo "    ======== ROBO LIB BUILD ========"
echo "    ================================"

mkdir -p build
cd       build

DPKG_DISTRIBUTION="unstable --distro-override=\"$WORKSPACE\"/"          \
    /opt/swt/install/make-3.82/bin/make --no-print-directory -j8 -k     \
    -f ../trunk/etc/buildlibs.mk INSTALLLIBDIR=$(pwd)/lib/              \
    TARGET=install robo_prebuild_libs subdirs 2>&1                      \
    | tee logs/build.$(hostname).$(date +"%Y%m%d-%H%M%S").log
