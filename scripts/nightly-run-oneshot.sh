#!/bin/bash

echo SCRIPT-TRACE - running $0 -- $*

SCRIPT_NAME=nightly-run-oneshot
BUILD_TYPE=oneshot

BDE_CORE_BRANCH=remotes/origin/master
BDE_BB_BRANCH=remotes/origin/master

BSL_TYPE=internal

CORE_UORS="bdl"
BB_UORS=""

ALL_UORS="$CORE_UORS $BB_UORS"

# redirect outputs so we can track failures - nysbldo2 does
# not mail cron job results
exec > ~bdebuild/logs/log.$SCRIPT_NAME.`date +"%Y%m%d-%H%M%S"` 2>&1

TOOLSPATH=/home/bdebuild/bde-tools-oneshot

export TARGET_OPTION=-pw32

cd $TOOLSPATH
/opt/swt/bin/git pull
cd -

SCRIPT_PATH=$TOOLSPATH/scripts

export TOOLSPATH SCRIPT_PATH SCRIPT_NAME BUILD_TYPE BDE_CORE_BRANCH BDE_BB_BRANCH
export CORE_UORS BB_UORS ALL_UORS
export BSL_TYPE

$SCRIPT_PATH/nightly-run-common-script.sh
