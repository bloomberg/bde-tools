#! /usr/bin/ksh

: ${BIN:=$(dirname $0)}

HTML_DIR=/bb/bigstor5/sbreitst/bdedoc/BDEGO/BDE2GO/bde_api_2.6_beta3X/


RELNUMB="2.6"
RELTYPE="Beta3"


TITLE="Table of Contents: BDE ${RELNUMB} ${RELTYPE}"
${BIN}/kwic_buildtoc.sh \
    -d "${HTML_DIR}"    \
    -t "${TITLE}" > ${HTML_DIR}/kwic_toc.HTML

TITLE="Index: BDE ${RELNUMB} ${RELTYPE}"
${BIN}/kwic_buildindex.sh \
    -d "${HTML_DIR}"    \
    -t "${TITLE}" > ${HTML_DIR}/kwic_index.HTML

cp -p ${BIN}/kwic_bde_go.CSS "${HTML_DIR}"/.

${BIN}/kwic_buildcover.sh  "${RELNUMB}" "${RELTYPE}" \
				  > ${HTML_DIR}/kwic_cover.HTML
