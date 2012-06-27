#!/bin/bash

TOOLSPATH=/bbshr/bde/bde-tools
SCRIPT_PATH=$TOOLSPATH/scripts

SCRIPT_NAME=runFromGitDevThenAPI
BUILD_TYPE=dev

BDE_CORE_BRANCH=remotes/origin/dev-integration
BDE_BB_BRANCH=remotes/origin/dev-integration
BAS_BRANCH=remotes/origin/master

CORE_UORS="bsl bst bde bbe bce bae bte"
BB_UORS="bsi zde a_bdema a_bteso a_xercesc e_ipc a_comdb2 z_a_bdema bap z_bae a_cdrcache"
BAS_UORS="bsc a_ossl a_fsipc bas a_xmf a_baslt a_bassvc a_basfs a_bascat a_fsbaem z_bas"

ALL_UORS="$CORE_UORS $BB_UORS $BAS_UORS"

# redirect outputs so we can track failures - nysbldo2 does
# not mail cron job results
exec > ~bdebuild/logs/log.$SCRIPT_NAME.`date +"%Y%m%d-%H%M%S"` 2>&1

export TOOLSPATH SCRIPT_PATH SCRIPT_NAME BUILD_TYPE BDE_CORE_BRANCH BDE_BB_BRANCH BAS_BRANCH
export CORE_UORS BB_UORS BAS_UORS ALL_UORS

BDE_CORE_GIT_REPO=/home/bdebuild/bs/bde-core-${BUILD_TYPE}

BDE_BB_GIT_REPO=/home/bdebuild/bs/bde-bb-${BUILD_TYPE}

BAS_GIT_REPO=/home/bdebuild/bs/bas-libs-${BUILD_TYPE}

BUILD_DIR=/home/bdebuild/bs/build-${BUILD_TYPE}
LOG_DIR=/home/bdebuild/bs/nightly-logs/${BUILD_TYPE}

W32_BUILD_DIR=bdenydev01:/e/nightly_builds/${BUILD_TYPE}
W64_BUILD_DIR=apinydev01:/d/nightly_builds/${BUILD_TYPE}

MAC_BASE_DIR=bdenydev02:/Development/bdebuild/
MAC_BUILD_DIR=${MAC_BASE_DIR}/${BUILD_TYPE}

SNAPSHOT_DIR=/home/bdebuild/bs/snapshot-${BUILD_TYPE}
TARBALL=/home/bdebuild/bs/tars-${BUILD_TYPE}/snapshot-${BUILD_TYPE}.`date +"%Y%m%d"`.tar.gz

export BUILD_DIR LOG_DIR TOOLSPATH

PATH="$TOOLSPATH/bin:$TOOLSPATH/scripts:/opt/swt/bin:/opt/SUNWspro/bin/:/usr/bin:/usr/sbin:/sbin:/usr/bin/X11:/usr/local/bin:/bb/bin:/bb/shared/bin:/bb/shared/abin:/bb/bin/robo:/bbsrc/tools/bbcm:/bbsrc/tools/bbcm/parent:/usr/atria/bin"
export PATH

pushd $BDE_CORE_GIT_REPO 2> /dev/null
/opt/swt/bin/git fetch
/opt/swt/bin/git checkout $BDE_CORE_BRANCH
popd

pushd $BDE_BB_GIT_REPO 2> /dev/null
/opt/swt/bin/git fetch
/opt/swt/bin/git checkout $BDE_BB_BRANCH
popd

pushd $BAS_GIT_REPO 2> /dev/null
/opt/swt/bin/git fetch
/opt/swt/bin/git checkout $BAS_BRANCH
popd

$SCRIPT_PATH/buildSnapshot.sh $TARBALL $SNAPSHOT_DIR \
                              $BDE_CORE_GIT_REPO $BDE_BB_GIT_REPO $BAS_GIT_REPO \
                         -- \
                         $ALL_UORS

cd $BUILD_DIR
echo synchronizing $OUTPUTPATH and $BUILD_DIR

# clean out BUILD_DIR to remove old source files.  We still get incr build
# since the build subdirs are all symlinks to elsewhere.
rm -rf $BUILD_DIR/*

rsync -av $SNAPSHOT_DIR/ $BUILD_DIR/ 2>&1 | perl -pe's/^/UNIX-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $SNAPSHOT_DIR/ $W32_BUILD_DIR/ 2>&1 | perl -pe's/^/W32-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $SNAPSHOT_DIR/ $W64_BUILD_DIR/ 2>&1 | perl -pe's/^/W64-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    $SNAPSHOT_DIR/ $MAC_BUILD_DIR/ 2>&1 | perl -pe's/^/MAC-CP: /'

rsync -av --rsync-path=/usr/bin/rsync \
    /bbshr/bde/bde-tools/ $MAC_BASE_DIR/bde-tools/ 2>&1 | perl -pe's/^/MAC-TOOLS: /'

# remove unix-SunOS-sparc-*-gcc-* build artifacts to get all g++ warnings
find $BUILD_DIR -name 'unix-SunOS-sparc-*-gcc-*' | grep -v -e include -e build | while read dir
do \
    rm -f $dir/*.o
done

# run ${BUILD_TYPE}-core build
$TOOLSPATH/bin/bde_bldmgr -v                \
       -k $TOOLSPATH/etc/bde_bldmgr.config  \
       -f -k -m -i${BUILD_TYPE}-core        \
       $CORE_UORS                           \
       < /dev/null 2>&1                     \
   | $TOOLSPATH/scripts/logTs.pl /home/bdebuild/logs/log.${BUILD_TYPE}-core \
   && $TOOLSPATH/scripts/report-latest ${BUILD_TYPE}-core

# run ${BUILD_TYPE}-bb build
$TOOLSPATH/bin/bde_bldmgr -v                \
       -k $TOOLSPATH/etc/bde_bldmgr.config  \
       -f -k -m -i${BUILD_TYPE}-bb          \
       $BB_UORS                             \
       < /dev/null 2>&1                     \
   | $TOOLSPATH/scripts/logTs.pl /home/bdebuild/logs/log.${BUILD_TYPE}-bb   \
   && $TOOLSPATH/scripts/report-latest ${BUILD_TYPE}-bb

# run ${BUILD_TYPE}-bas build
$TOOLSPATH/bin/bde_bldmgr -v                \
       -k $TOOLSPATH/etc/bde_bldmgr.config  \
       -f -k -m -i${BUILD_TYPE}-bas         \
       $BAS_UORS                            \
       < /dev/null 2>&1                     \
   | $TOOLSPATH/scripts/logTs.pl /home/bdebuild/logs/log.${BUILD_TYPE}-bas   \
   && $TOOLSPATH/scripts/report-latest ${BUILD_TYPE}-bas

# generate gcc warnings
$TOOLSPATH/scripts/generateGccWarningsLogs.pl ${BUILD_TYPE} ${LOG_DIR}

