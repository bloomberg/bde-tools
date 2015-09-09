#!/bin/bash

echo SCRIPT-TRACE - running $0 -- $*

SCRIPT_NAME=nightly-run-bsl-internal
BUILD_TYPE=bslintdev

BDE_CORE_BRANCH=remotes/origin/review/2015-opensource-baseline
BDE_BB_BRANCH=remotes/origin/dev-integration

BSL_TYPE=internal

CORE_UORS="bsl bdl bbl btl bal"
BB_UORS=""

ALL_UORS="$CORE_UORS"

# redirect outputs so we can track failures - nysbldo2 does
# not mail cron job results
exec > ~bdebuild/logs/log.$SCRIPT_NAME.`date +"%Y%m%d-%H%M%S"` 2>&1

TOOLSPATH=$(dirname $0)/..
SCRIPT_PATH=$TOOLSPATH/scripts

export TOOLSPATH SCRIPT_PATH SCRIPT_NAME BUILD_TYPE BDE_CORE_BRANCH BDE_BB_BRANCH
export CORE_UORS BB_UORS ALL_UORS
export BSL_TYPE

$SCRIPT_PATH/nightly-run-common-script.sh
