#!/usr/bin/ksh
#==============================================================================
# Syntax:  sequence.sh [-h] [files]...
# Purpose: Convert 'purpose|filename' to lines permuted sequence on "purpose".
#==============================================================================

syntax="Syntax: "
syntax="${syntax}kwic_prefixwithsortField.sh [-h] [files]..."
syntax="${syntax}\n\t-h          -- print help message"

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

while getopts "h" opt; do
    case $opt in
     h )
        print "${syntax}"
        exit 0;;
    esac
done
shift $(($OPTIND - 1))

nawk '
    BEGIN { FS="|" }
    {
        filename = $1
        purpose  = $2

        sub("^ *", "", filename); #remove  leading blanks
        sub(" *$", "", filename); #remove trailing blanks

        sub("^ *", "", purpose); #remove  leading blanks
        sub(" *$", "", purpose); #remove trailing blanks

        numWords = split(purpose, words, " ")
        for (marker = 1; marker <= numWords; ++marker) {

            #output words to the right of the marker
            for (i = marker; i <= numWords; ++i) {
                format = i < numWords ? "%s " : "%s"
                printf format, words[i]
            }
            printf "|";

            #output words to the left of the marker
            for (i = 1; i < marker; ++i) {
                format = i < marker - 1 ? "%s " : "%s"
                printf format, words[i]
            }
            printf "|";

            printf "%s\n", filename;
        }
    }
' $*
