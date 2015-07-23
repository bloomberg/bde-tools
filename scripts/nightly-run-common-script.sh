#!/bin/bash

# this script requires that several variables be set - see
# nightly-run-nextrel.sh for an example.

# If the TARGET_OPTION variable is set in the environment (usually, from
# OUTSIDE the script which calls this one), it should be set to a
# comma-separated list of platforms to run, prefixed with -p:
#       -ps12,i10

if [[ -z "$TOOLSPATH" || -z "$SCRIPT_PATH" || -z "$SCRIPT_NAME" || -z "$BUILD_TYPE" || -z "$BDE_CORE_BRANCH" || -z "$BDE_BB_BRANCH" ||  -z "$CORE_UORS" || -z "$ALL_UORS" || -z "$BSL_TYPE" ]]
then \
    echo "USAGE: $0"
    echo "    All of the following variables must be exported before this script is invoked:"
    echo "         TOOLSPATH"
    echo "         SCRIPT_PATH"
    echo "         SCRIPT_NAME"
    echo "         BUILD_TYPE"
    echo "         BDE_CORE_BRANCH"
    echo "         BDE_BB_BRANCH"
    echo "         CORE_UORS"
    echo "         ALL_UORS"
    echo "         BSL_TYPE"
    echo "    This variable is OPTIONAL:"
    echo "         BB_UORS"

    exit 1
fi

echo SCRIPT-TRACE - running $0 -- $*

A_CDB2_GIT_REPO=/home/bdebuild/bs/a_cdb2-${BUILD_TYPE}

BDE_BSL_GIT_REPO=/home/bdebuild/bs/bsl-${BSL_TYPE}-${BUILD_TYPE}

BDE_CORE_GIT_REPO=/home/bdebuild/bs/bde-core-${BUILD_TYPE}

BDE_BB_GIT_REPO=/home/bdebuild/bs/bde-bb-${BUILD_TYPE}

BDE_BDX_GIT_REPO=/home/bdebuild/bs/bde-bdx-${BUILD_TYPE}

BUILD_DIR=/home/bdebuild/bs/build-${BUILD_TYPE}
LOG_DIR=/home/bdebuild/bs/nightly-logs/${BUILD_TYPE}

export W96=brmwnydgenap05

W32_BUILD_DIR=bdenydev01:/e/nightly_builds/${BUILD_TYPE}
W64_BUILD_DIR=apinydev01:/d/nightly_builds/${BUILD_TYPE}
W96_BUILD_DIR=$W96:/e/nightly_builds/${BUILD_TYPE}

W32_TOOLS_DIR=bdenydev01:/e/git/bde-tools-${BUILD_TYPE}
W64_TOOLS_DIR=apinydev01:/d/git/bde-tools-${BUILD_TYPE}
W96_TOOLS_DIR=$W96:/e/git/bde-tools-${BUILD_TYPE}

MAC_BASE_DIR=bdenydev02:/Development/bdebuild/
MAC_BUILD_DIR=${MAC_BASE_DIR}/${BUILD_TYPE}
MAC_TOOLS_DIR=${MAC_BASE_DIR}/bde-tools-${BUILD_TYPE}

SNAPSHOT_DIR=/home/bdebuild/bs/snapshot-${BUILD_TYPE}
TARBALL=/home/bdebuild/bs/tars-${BUILD_TYPE}/snapshot-${BUILD_TYPE}.`date +"%Y%m%d"`.tar.gz

TMPDIR=/bb/data/tmp

export BUILD_DIR LOG_DIR TOOLSPATH TMPDIR

PATH="$TOOLSPATH/bin:$TOOLSPATH/scripts:/opt/swt/bin:/opt/SUNWspro/bin/:/usr/bin:/usr/sbin:/sbin:/usr/bin/X11:/usr/local/bin:/bb/bin:/bb/shared/bin:/bb/shared/abin:/bb/bin/robo:/bbsrc/tools/bbcm:/bbsrc/tools/bbcm/parent:/usr/atria/bin"
export PATH

REPO_LIST=
ROOT_REPO=

if [ -e $BDE_BSL_GIT_REPO ]
then \
    pushd $BDE_BSL_GIT_REPO 2> /dev/null
    /opt/swt/bin/git fetch
    /opt/swt/bin/git reset --hard
    /opt/swt/bin/git checkout $BDE_CORE_BRANCH
    popd

    REPO_LIST="$REPO_LIST $BDE_BSL_GIT_REPO"
    ROOT_REPO=$BDE_BSL_GIT_REPO
else
    echo ERROR: Invalid BDE_BSL_GIT_REPO $BDE_BSL_GIT_REPO of type $BSL_TYPE specified
    exit 1
fi


if [ -e $A_CDB2_GIT_REPO ]
then \
    pushd $A_CDB2_GIT_REPO 2> /dev/null
    /opt/swt/bin/git fetch
    /opt/swt/bin/git reset --hard
    /opt/swt/bin/git checkout $BDE_CORE_BRANCH
    popd

    REPO_LIST="$REPO_LIST $A_CDB2_GIT_REPO"
else
    echo WARNING: Invalid A_CDB2_GIT_REPO $A_CDB2_GIT_REPO specified
fi

pushd $BDE_CORE_GIT_REPO 2> /dev/null
/opt/swt/bin/git fetch
/opt/swt/bin/git reset --hard
/opt/swt/bin/git checkout $BDE_CORE_BRANCH
popd

REPO_LIST="$REPO_LIST $BDE_CORE_GIT_REPO"

pushd $BDE_BB_GIT_REPO 2> /dev/null
/opt/swt/bin/git fetch
/opt/swt/bin/git reset --hard
/opt/swt/bin/git checkout $BDE_BB_BRANCH
popd

REPO_LIST="$REPO_LIST $BDE_BB_GIT_REPO"

pushd $BDE_BDX_GIT_REPO 2> /dev/null
/opt/swt/bin/git fetch
/opt/swt/bin/git reset --hard
/opt/swt/bin/git checkout $BDE_BB_BRANCH
popd

REPO_LIST="$REPO_LIST $BDE_BDX_GIT_REPO"

$SCRIPT_PATH/buildSnapshot.sh $TARBALL $SNAPSHOT_DIR \
                              $ROOT_REPO $BDE_CORE_GIT_REPO $REPO_LIST \
                         -- \
                         $ALL_UORS

cd $BUILD_DIR
echo synchronizing $OUTPUTPATH and $BUILD_DIR

# remove unix-SunOS-sparc-*-gcc-* build artifacts to get all g++ warnings
find $BUILD_DIR -name 'unix-SunOS-sparc-*-gcc-*' | grep -v -e include -e build | while read dir
do \
    rm -f $dir/*.o
done

# clean out BUILD_DIR to remove old source files.  We still get incr build
# since the build subdirs are all symlinks to elsewhere.
rm -rf $BUILD_DIR/*

rsync -av $SNAPSHOT_DIR/ $BUILD_DIR/ 2>&1 | perl -pe's/^/UNIX-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $SNAPSHOT_DIR/ $W32_BUILD_DIR/ 2>&1 | perl -pe's/^/W32-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $SNAPSHOT_DIR/ $W64_BUILD_DIR/ 2>&1 | perl -pe's/^/W64-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $SNAPSHOT_DIR/ $W96_BUILD_DIR/ 2>&1 | perl -pe's/^/W96-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
      --timeout=600                   \
    $SNAPSHOT_DIR/ $MAC_BUILD_DIR/ 2>&1 | perl -pe's/^/MAC-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
      --timeout=600                   \
    $TOOLSPATH/ $MAC_TOOLS_DIR/ 2>&1 | perl -pe's/^/MAC-TOOLS: /'

rsync -av --rsync-path=/usr/bin/rsync \
      --timeout=600                   \
    /bbshr/bde/bde-oss-tools/ $MAC_BASE_DIR/bde-oss-tools/ 2>&1 | perl -pe's/^/MAC-OSS-TOOLS: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $TOOLSPATH/ $W32_TOOLS_DIR/ 2>&1 | perl -pe's/^/W32-TOOLS: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $TOOLSPATH/ $W64_TOOLS_DIR/ 2>&1 | perl -pe's/^/W64-TOOLS: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $TOOLSPATH/ $W96_TOOLS_DIR/ 2>&1 | perl -pe's/^/W96-TOOLS: /'

# run ${BUILD_TYPE}-core build

echo Invoking bde_bldmgr for core build

echo Invoking: \
$TOOLSPATH/bin/bde_bldmgr -v                \
       -k $TOOLSPATH/etc/bde_bldmgr.config  \
       -f -k -m -i${BUILD_TYPE}-core        \
       $TARGET_OPTION                       \
       $CORE_UORS                           \
       -vvv


$TOOLSPATH/bin/bde_bldmgr -v                \
       -k $TOOLSPATH/etc/bde_bldmgr.config  \
       -f -k -m -i${BUILD_TYPE}-core        \
       $TARGET_OPTION                       \
       $CORE_UORS $BB_UORS                  \
       -vvv                                 \
       < /dev/null 2>&1                     \
   | $TOOLSPATH/scripts/logTs.pl /home/bdebuild/logs/log.${BUILD_TYPE}-core

touch /home/bdebuild/logs/log.${BUILD_TYPE}-bb

# generate gcc warnings
#$TOOLSPATH/scripts/generateGccWarningsLogs.pl ${BUILD_TYPE} ${LOG_DIR}

