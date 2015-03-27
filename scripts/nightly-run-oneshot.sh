#!/bin/bash

echo SCRIPT-TRACE - running $0 -- $*

SCRIPT_NAME=nightly-run-oneshot
BUILD_TYPE=oneshot

BDE_CORE_BRANCH=remotes/origin/review/guidutil-win_drqs-63818360
BDE_BB_BRANCH=remotes/origin/master

BSL_TYPE=internal

if true
then
    # just bsl and bdl
    CORE_UORS="bsl bdl"
    BB_UORS=""
else
    # full set
    CORE_UORS="bsl bdl bde bbe bce bae bte"
    BB_UORS="bdx bsi zde a_bdema a_bteso a_xercesc e_ipc z_a_bdema bap a_comdb2 a_cdrdb z_bae a_cdrcache a_iconv"
fi

ALL_UORS="$CORE_UORS $BB_UORS"

echo "Build targets: $ALL_UORS"

# redirect outputs so we can track failures - nysbldo2 does
# not mail cron job results
exec > ~bdebuild/logs/log.$SCRIPT_NAME.`date +"%Y%m%d-%H%M%S"` 2>&1

TOOLSPATH=/home/mgiroux/bde-tools

export TARGET_OPTION="-pw32_2010,w32_2008_dbg,w32_2013_dbg -vvv"

cd $TOOLSPATH
/opt/swt/bin/git pull
cd -

SCRIPT_PATH=$TOOLSPATH/scripts

export TOOLSPATH SCRIPT_PATH SCRIPT_NAME BUILD_TYPE BDE_CORE_BRANCH BDE_BB_BRANCH
export CORE_UORS BB_UORS ALL_UORS
export BSL_TYPE

$SCRIPT_PATH/nightly-run-common-script.sh
