#!/bin/bash

# ----------------------------------------------------------------------------
# Copyright 2016 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE ----------------------------------

#==============================================================================
# Syntax:  bdedox_genhtmlmain.sh [-h] |
#                                [-i doxydir] [-o htmldir] [-r header]
#                                [-p project] [-n projectno]
#                                [-c cfgfile] [file ... ]
#
# Purpose: Runs 'doxygen' in the 'bdedox' framework to create 'main.html'.
#==============================================================================

syntax="Syntax: bdedox_genhtmlmain.sh [-h] |"
syntax="${syntax}\n\t  [-i doxydir] -o [htmldir] [-r header]"
syntax="${syntax}\n\t  [-p projectname] [-n projectnum]"
syntax="${syntax}\n\t  [-c cfgfile]"
syntax="${syntax}\nwhere:"
syntax="${syntax}\n\t-i doxydir   directory containing doxygen files (input)"
syntax="${syntax}\n\t                 default: current directory"
syntax="${syntax}\n\t-o htmldir   directory containing doxygen files (input)"
syntax="${syntax}\n\t                 default: ./html"
syntax="${syntax}\n\t-r header    HTML header file"
syntax="${syntax}\n\t                 default: doxydir/BDEQuickLinks.header"
syntax="${syntax}\n\t-p project   Project name"
syntax="${syntax}\n\t                 default: \"\""
syntax="${syntax}\n\t-n projectno Project number"
syntax="${syntax}\n\t                 default: \"\""
syntax="${syntax}\n\t-c cfgfile   Doxygen configuration file"
syntax="${syntax}\n\t                 default: ./bdedox_doxygen.cfg"

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

DOXYGEN_DOXYDIR="."
DOXYGEN_PROJECT_NAME=""
DOXYGEN_PROJECT_NUMBER=""

progDir=${0%/*}
CFGFILE="$progDir/bdedox_doxygen.cfg"

while getopts ":hi:o:p:n:c:" opt; do
    case $opt in
     h )
        echo "${syntax}"
        exit 0;;
     i )
        DOXYGEN_DOXYDIR=${OPTARG}
        ;;
     o )
        DOXYGEN_HTMLDIR=${OPTARG}
        ;;
     p )
        DOXYGEN_PROJECT_NAME=${OPTARG}
        ;;
     n )
        DOXYGEN_PROJECT_NUMBER=${OPTARG}
        ;;
     c )
        CFGFILE=${OPTARG}
        ;;
     * )
        echo >&2 "${syntax}"
        exit 1;;
    esac
done
shift $(($OPTIND - 1))

: ${DOXYGEN_HTML_HEADER:=$DOXYGEN_DOXYDIR/BDEQuickLinks.header}
: ${DOXYGEN_HTMLDIR:=$DOXYGEN_DOXYDIR/html}

#------------------------------------------------------------------------------
# Check 'doxygen' existance and version.
#------------------------------------------------------------------------------

DOXYGEN_BIN=`which doxygen`

if   [ -x "$DOXYGEN_BIN" ]
then :
else echo >/dev/stderr "!! Not found: $DOXYGEN_BIN"; exit 1
fi

DOXYGEN_VERSION=$($DOXYGEN_BIN --version)
DOXYGEN_VERSION_OK='1.7.1'
case $DOXYGEN_VERSION in
     $DOXYGEN_VERSION_OK) : ;;
                       *) echo >&2 \
              "Doxygen version is $DOXYGEN_VERSION; $DOXYGEN_VERSION_OK needed"
                          exit 1
                          ;;
esac

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

echo "DOXYGEN_DOXYDIR       : $DOXYGEN_DOXYDIR"
echo "DOXYGEN_HTMLDIR       : $DOXYGEN_HTMLDIR"
echo "DOXYGEN_HTML_HEADER   : $DOXYGEN_HTML_HEADER"
echo "DOXYGEN_PROJECT_NAME  : $DOXYGEN_PROJECT_NAME"
echo "DOXYGEN_PROJECT_NUMBER: $DOXYGEN_PROJECT_NUMBER"
echo "CFGFILE               : $CFGFILE"

[ -r "$DOXYGEN_DOXYDIR" ] || {
    echo >&2 "not readable directory: $DOXYGEN_DOXYDIR";
    exit 1
}

[ -w "$DOXYGEN_HTMLDIR" ] || {
    echo >&2 "not writable directory: $DOXYGEN_HTMLDIR";
    exit 1
}

[    "$DOXYGEN_HTML_HEADER" ] &&
[ -r "$DOXYGEN_HTML_HEADER" ] || {
    echo >&2 "cannot read header file: $DOXYGEN_HTML_HEADER";
    exit 1
}

[ -r "$CFGFILE" ] || {
    echo >&2 "cannot read configuration file: $CFGFILE";
    exit 1
}

#Create 'main.html' separately from the rest, then copy to final destination.

IPUT_DIR=$(mktemp -d); echo IPUT_DIR=$IPUT_DIR
[ -r "$IPUT_DIR" ] || {
    echo >&2 "not readable directory: $IPUT_DIR";
    exit 1
}
#trap "rm -rf $IPUT_DIR" EXIT

cat $* >$IPUT_DIR/main.h

OPUT_DIR=$(mktemp -d); echo OPUT_DIR=$OPUT_DIR
[ -w "$OPUT_DIR" ] || {
    echo >&2 "not writable directory: $OPUT_DIR";
    exit 1
}
#trap "rm -rf $IPUT_DIR $OPUT_DIR" EXIT


FINAL_DEST_DIR=$DOXYGEN_HTMLDIR
DOXYGEN_HTMLDIR=$OPUT_DIR
DOXYGEN_DOXYDIR=$IPUT_DIR

export DOXYGEN_DOXYDIR
export DOXYGEN_HTMLDIR
export DOXYGEN_HTML_HEADER
export DOXYGEN_PROJECT_NAME
export DOXYGEN_PROJECT_NUMBER

eval $DOXYGEN_BIN $CFGFILE

[ -r "$OPUT_DIR/main.html" ] || {
    echo >&2 "cannot read: $OPUT_DIR/main.html";
    exit 1
}

cp "$FINAL_DEST_DIR/main.html" "$FINAL_DEST_DIR/mainORIG.html" &&
cp "$OPUT_DIR/main.html" "$FINAL_DEST_DIR/main.html" || {
    echo >&2 "cannot update: $FINAL_DEST_DIR/main.html";
    exit 1
}

exit 0

