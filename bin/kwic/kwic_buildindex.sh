#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_buildindex.sh [-d <dir>] [-f <suffix>] [-t <title>] \
#                             [-c <css>]
# Purpose: Generate a KWIC index in HTML of BDE component '@PURPOSE' contents
#==============================================================================

syntax="Syntax: "
syntax="${syntax}kwic_buildindex.sh"
syntax="${syntax}\n\t-h             -- print usage message"
syntax="${syntax}\n\t-d <directory> -- directory of header files"
syntax="${syntax}\n\t                  (default: current directory)"
syntax="${syntax}\n\t-l <file>      -- list of header files"
syntax="${syntax}\n\t-f <suffix>    -- header file suffix"
syntax="${syntax}\n\t                  (default: _8h_source.html)"
syntax="${syntax}\n\t-t <title>     -- title"
syntax="${syntax}\n\t-c <css>       -- path to cascading style sheet"
syntax="${syntax}\n\t                  (default: kwic_bde_go.CSS)"
syntax="${syntax}\n\t-p <path>      -- path for html links"
syntax="${syntax}\n\t                  (default: current directory)"

#==============================================================================
# Defaults
#==============================================================================

: ${DIR:="./"}
: ${SUFFIX:="_8h_source.html"}
: ${TITLE:="Permuted Index: BDE Components"}
: ${CSS:="kwic_bde_go.CSS"}
: ${BIN:=$(dirname $0)}
: ${HTML_PATH:="./"}

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

while getopts ":d:f:t:c:h" opt; do
    case $opt in
     d )
        DIR=$OPTARG;;
     l )
        FILELIST=$OPTARG;;
     f )
        SUFFIX=$OPTARG;;
     t )
        TITLE=$OPTARG;;
     c )
        CSS=$OPTARG;;
     p )
         HTML_PATH=$OPTARG;;
     h )
        print "${syntax}"
        exit 0;;
     * )
        print -u2 "${syntax}"
        exit 1;;
    esac
done
shift $(($OPTIND - 1))

#------------------------------------------------------------------------------
# Basic Error Checking
#------------------------------------------------------------------------------

if [ $DIR ] && [ $FILELIST ]; then
    print -u2 "BOO";
    print -u2 "!! $sytax"
    exit 1;
fi

if [ ! -r $FILELIST ]; then
    print -u2 "!! cannot open for reading: ${FILENAME}."
    exit 1
fi

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

(
    if [ ! -r $FILELIST ]; then
        cat $FILELIST
    else 
        ls $DIR | sed "s!^!$DIR!"
    fi
)                              |
grep "${SUFFIX}$"                 |
${BIN}/kwic_extractpurposes.sh    |
${BIN}/kwic_sequence.sh           |
${BIN}/kwic_prefixwithsortfield.sh|
${BIN}/kwic_filterstopwords.sh    |
sort -t'|' -f +0                  |
${BIN}/kwic_generateindexhtml.sh  \
    -t "${TITLE}"                 \
    -c "${CSS}"                   \
    -f "${SUFFIX}"                \
    -p "${HTML_PATH}"
