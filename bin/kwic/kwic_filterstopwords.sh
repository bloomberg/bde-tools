#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_filterstopwords.sh [-s <stopwords>]
# Purpose: Filter out lines begining with any stop-word.
#==============================================================================

syntax="Syntax: "
syntax="${syntax}kwic_filterstopwords.sh"
syntax="${syntax}\n\t-h             -- print usage message"
syntax="${syntax}\n\t-s <stopwords> -- file of stopwords"
syntax="${syntax}\n\t                  (case-sensitive, one word per line"
syntax="${syntax}\n\t                   default: kwic_stopwords.txt)"

#==============================================================================
# Defaults
#==============================================================================

: ${STOPWORDS:="kwic_stopwords.txt"}

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

while getopts ":s:h" opt; do
    case $opt in
     s ) 
        STOPWORDS=$OPTARG;;
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
# Main
#------------------------------------------------------------------------------

nawk '
    BEGIN {
        stopWordsFile = "'"${STOPWORDS}"'";
        while (getline stopWord < stopWordsFile > 0) {
            stopWords[stopWord] = "1";  # The "key" is of import, not the value.
        }
    }
    {
        originalLine = $0
        gsub("\\|"," ")
        sub("\\.$","", $1) #remove tailing period, if any, from first word
        if ($1 in stopWords) {
            next
        } else {
            print originalLine
        }
    }
'
