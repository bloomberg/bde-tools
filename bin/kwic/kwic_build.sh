#! /usr/bin/ksh

: ${BIN:=$(dirname $0)}

HTML_DIR=~tmarshal/public_html/BDEGO/BDE2GO/bde_api_prod/

RELNUMB="2.3"
RELTYPE="Production"


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
