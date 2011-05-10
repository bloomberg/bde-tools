#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_buildcover.sh [-h] [-c <css>] <release> <Beta[#]|Production>
# Purpose: Generate a cover page in HTML for BDE TOC, Index, and Doxygen files.
#==============================================================================

syntax="Syntax: "
syntax="${syntax} kwic_buildcover.sh"
syntax="${syntax} [-h] [-c <css>]"
syntax="${syntax} <release> <Beta[#]|Production>"
syntax="${syntax}\n\t-h             -- print usage message"
syntax="${syntax}\n\t-c <css>       -- path to cascading style sheet"
syntax="${syntax}\n\t                  (default: kwic_bde_go.CSS)"

#==============================================================================
# Defaults
#==============================================================================

: ${CSS:="kwic_bde_go.CSS"}

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

while getopts ":h" opt; do
    case $opt in
     c )
        CSS=$OPTARG;;
     h )
        print -u1 "${syntax}"
        exit 0;;
     * )
        print -u2 "${syntax}"
        exit 1;;
    esac
done
shift $(($OPTIND - 1))

if [ $# -ne 2 ]
then
    print -u2 "${syntax}"
    exit 1;
fi

RELEASE_NUMBER=$1
RELEASE_TYPE=$2

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

cat <<!
<html>
<head>
<title>BDE ${RELEASE_NUMBER} Release: ${RELEASE_TYPE}</title>
<link rel="stylesheet" type="text/css" href="${CSS}"/>
<style>
a:hover   { color: #f07c0a; text-decoration: underline}
a:link    { color: black; text-decoration: none }
</style>
</head>
<body>
<h1>BDE ${RELEASE_NUMBER} Release: ${RELEASE_TYPE}</h1>
<ul>
<li>
<a href="kwic_toc.HTML">Table of Contents</h2>
</li>
<li>
<a href="kwic_index.HTML">Index (permuted)</h2>
</li>
<li>
<a href=".">Details (Doxygen)</h2>
</li>
</ul>
</body>
</html>
!
