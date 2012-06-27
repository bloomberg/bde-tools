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

$SCRIPT_PATH/nightly-run-common-script.sh
