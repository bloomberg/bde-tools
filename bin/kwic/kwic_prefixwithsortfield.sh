#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_prefixwithsortField.sh [-h] [files]...
# Purpose: Create from first field a "sort" field stripped of non-alpha chars.
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

/opt/swt/bin/perl -e '
    while (<>) {
        my $stringIn = $_; chomp($stringIn);

        my @fields = split(/\|/, $stringIn);
        if (0 == scalar(@fields)) {
            next;
        }
        my $keyField = $fields[0];

        $keyField =~ s/[()<>{}\[\]]//g;
        $keyField =~ s/\&#39;//g;
        $keyField =~ s/\&quot;//g;
        $keyField =~ s/\&amp; //g;
        $keyField =~ s/\&lt;//g;
        $keyField =~ s/\*//g;
        $keyField =~ s/\// /g;
        $keyField =~ s/^ *//g;

        printf "%s\n", $keyField . "|" . $stringIn;
    }
' $*
