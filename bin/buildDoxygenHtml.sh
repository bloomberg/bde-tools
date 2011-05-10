#!/usr/bin/sh

GRPS="\
 bsl\
 bde\
 bce\
 bte\
 bae\
 e_ipc\
 bas\
 a_baslt\
 a_basfs\
 bap\
 bsi\
 a_xmf\
 bsc\
 a_bdema\
 a_xml2\
 a_xercesc\
 a_comdb2\
 a_cdrcache\
 a_fsipc\
 a_basjni\
 bbe\
 zde\
"


DIR=/bbcm/infrastructure/tools/bin/
CMD=bde_deploydoc
BDE_DEPLOYDOC=$DIR/$CMD
EXCLUDE=$DIR/../etc/bde2doxy_exclude.txt
BDE2GO="/bb/bigstor5/sbreitst/bdedoc/BDEGO/BDE2GO"

RELNO=2.6
RELTYPE=PRODUCTION
DIR_SUFFIX=prod1

OUTDIR="/tmp/outdir_${RELNO}_${DIR_SUFFIX}"
HTMLDIR="${BDE2GO}/bde_api_${RELNO}_${DIR_SUFFIX}"
BASE_TITLE="BDE ${RELNO} ${RELTYPE}"

       DOXYGEN_PROJECT_NAME="BDE Release ${RELNO} ${RELTYPE}"
export DOXYGEN_PROJECT_NAME
       DOXYGEN_PROJECT_NUMBER="${RELNO}"
export DOXYGEN_PROJECT_NUMBER

$BDE_DEPLOYDOC                \
    -v                        \
    --groups ${GRPS}          \
    --original                \
    --debug                   \
    --exclude=$EXCLUDE        \
    --outdir=$OUTDIR          \
    --htmldir=$HTMLDIR        \
    --baseTitle="$BASE_TITLE" \
    --nolocal
