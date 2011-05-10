#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_extractpurposes.sh [-h] [file]...
# Purpose: Extract content of '@PURPOSE' lines from BDE header files
#==============================================================================

syntax="Syntax: kwic_extractpurposes.sh [-h] [file]..."
syntax="${syntax}\n\tIf no arguments, file names read from standard input."
syntax="${syntax}\n\t-h --- Print usage message"

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

while getopts ":h" opt; do
    case $opt in
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

(  if [[ $# -lt 1 ]]; then
        cat
   else
        echo "$@"
   fi
)                                                                             |
xargs grep '^//@PURPOSE: '                                                    |
grep -v '://@PURPOSE: TODO: Provide purpose'                                  |
grep -v                                                                       \
  '://@PURPOSE: Provide source control management (versioning) information\.' |
egrep -v                                                                      \
  '://@PURPOSE: Provide versioning information for the .* package group\.'    |
sed 's/:\/\/@PURPOSE: /|/'
