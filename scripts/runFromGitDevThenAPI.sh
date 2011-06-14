#!/usr/bin/bash

TOOLSPATH=/home/bdebuild/bde-tools
SCRIPT_NAME=runFromGitDevThenAPI
VIEW_NAME=bde_devintegrator
GIT_REPO=/home/bdebuild/bs/git-bde-dev
BUILD_DIR=/home/bdebuild/bs/build-dev

W32_BUILD_DIR=bdenydev01:/e/nightly_builds/dev
W32_BUILD_DIR=apinydev01:/d/nightly_builds/dev

SNAPSHOT_DIR=/home/bdebuild/bs/snapshot-dev
TARBALL=/home/bdebuild/bs/tars-dev/snapshot-dev.`date +"%Y%m%d"`.tar.gz
DEV_UORS="bsl zde bde bbe bce bae bte bsi                                   \
       a_bdema a_bteso a_xercesc bsc e_ipc a_ossl a_fsipc bas a_xmf         \
       a_baslt a_bassvc bap a_comdb2 a_basfs a_bascat z_bae a_fsbaem z_bas"
API_UORS="api apt apu aps apn blpapi"
FDE_UORS="fde"

# redirect outputs so we can track failures - nysbldo2 does
# not mail cron job results
exec > ~bdebuild/logs/log.$SCRIPT_NAME.`date +"%Y%m%d-%H%M%S"` 2>&1

/usr/atria/bin/cleartool startview $VIEW_NAME

cd $GIT_REPO 2> /dev/null
git pull

SCRIPT_PATH=$(dirname $0)

if [ ! -z "$SCRIPT_PATH" ]
then \
    SCRIPT_PATH="$SCRIPT_PATH/"
fi

PATH="/home/bdebuild/bde-tools/bin:/home/bdebuild/bde-tools/scripts:/opt/SUNWspro/bin/:/bbcm/infrastructure/tools/bin:/usr/bin:/usr/sbin:/sbin:/usr/bin/X11:/usr/local/bin:/bb/bin:/bb/shared/bin:/bb/shared/abin:/bb/bin/robo:/bbsrc/tools/bbcm:/bbsrc/tools/bbcm/parent:/usr/atria/bin"
export PATH

buildSnapshot.sh $TARBALL $OUTPUTPATH $GIT_REPO /view/$VIEW_NAME/bbcm/{infrastructure,api} \
                 -- \
                 $DEV_UORS $API_UORS $FDE_UORS

cd $BUILD_DIR
echo synchronizing $OUTPUTPATH and $BUILD_DIR
# add --delete switch to make sure deleted files are reflected
/opt/swt/bin/rsync -av --delete $OUTPUTPATH/ $BUILD_DIR/

/opt/swt/bin/rsync -av --delete $OUTPUTPATH/ $W32_BUILD_DIR/

/opt/swt/bin/rsync -av --delete $OUTPUTPATH/ $W64_BUILD_DIR/

# run dev build
$TOOLSPATH/bin/bde_bldmgr -v                \
       -k $TOOLSPATH/etc/bde_bldmgr.config  \
       -f -k -m -idev                                                              \
       $DEV_UORS  \
       < /dev/null 2>&1                                      \
   | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev \
   && /home/bdebuild/bin/report-latest dev

# THEN run api and fde builds
$TOOLSPATH/bin/bde_bldmgr -v                \
        -k $TOOLSPATH/etc/bde_bldmgr.config \
        -f -k -m -idev-api -wbde_devintegrator                                     \
        $API_UORS                                                \
        < /dev/null 2>&1                                                \
   | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev-api   \
   && /home/bdebuild/bin/report-latest dev-api &

$TOOLSPATH/bin/bde_bldmgr -v                \
        -k $TOOLSPATH/etc/bde_bldmgr.config \
        -f -k -m -idev-fde -wbde_devintegrator                                     \
        $FDE_UORS                                                                        \
        < /dev/null 2>&1                                              \
  | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev-fde       \
  && /home/bdebuild/bin/report-latest dev-fde &

wait

~bdebuild/bin/generateGccWarningsLogs.pl dev bde_devintegrator

