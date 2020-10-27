#!/bin/bash

# This command must be run from the root of a .git repository.

# It finds all files in the repo where sim_cpp11_features.pl has
# been run before, and reruns it, unless those files are the OUTPUT
# of sim_cpp11_features.pl.

# Its main purpose is to update from the previous "in-file-only" mode
# of sim_cpp11_features.pl (where the expansions were placed in the same
# file) to the new "generate external files" (where the expansions are
# placed in external _cpp03 files) mode in a single, one-time, bulk
# operation.

if [[ "$1" == "--help" || ! -z "$*" ]]
then \
    perl -e'print <<"USAGE"
    USAGE: $ARGV[0]
        This command must be run from the root of a .git repository.

        It finds all files in the repo where sim_cpp11_features.pl has
        been run before, and reruns it, unless those files are the OUTPUT
        of sim_cpp11_features.pl.

        Its main purpose is to update from the previous "in-file-only" mode
        of sim_cpp11_features.pl (where the expansions were placed in the same
        file) to the new "generate external files" (where the expansions are
        placed in external _cpp03 files) mode in a single, one-time, bulk
        operation.
USAGE' $0
    exit 1
fi

if [[ ! -d .git ]]
then \
    echo "Please run from the root of the git repo to transform"
    exit 1
fi

BINPATH=$(dirname $0)
SIM_CPP11=$BINPATH/sim_cpp11_features.pl

GREP=grep
GREP_EXTRA_ARGS='-r'
if [ -x /opt/bb/bin/ag ]
then \
    GREP=/opt/bb/bin/ag
    GREP_EXTRA_ARGS="--nocolor"
fi

# Make sure each file is processed only once, using bash associative arrays
# (https://www.artificialworlds.net/blog/2012/10/17/bash-associative-array-examples/)
# to remember which files are already processed.
declare -A PROCESSED_FILES
export PROCESSED_FILES

# Note that the search term must NOT be a regex - ag crashes on AIX or Sun
# as of 2020/10/12 if there's a regex in the search text.
$GREP -l -i $GREP_EXTRA_ARGS 'command line: sim_cpp11' [a-z]* \
  | grep -v '_cpp03\.' \
  | while read filename
    do \
        export BASENAME=$(basename $filename)
        export PATHNAME=$(dirname $filename)
        export COMPONENT_NAME=$(echo $BASENAME | perl -pe's/\..*//')
        export CPP03_COMPONENT_NAME=${COMPONENT_NAME}_cpp03
        export EXT=$(echo $BASENAME | perl -pe's/^.*?\./\./')

        echo $COMPONENT_NAME: $BASENAME $EXT $filename $PATHNAME

        if [[ "$EXT" =~ \.t\.cpp ]]
        then \
            HEADER="$PATHNAME/$COMPONENT_NAME.h"
            SOURCE="$PATHNAME/$COMPONENT_NAME.cpp"

            echo "------ Test driver"
            echo "   ------ Clean up old expansions"
            perl -i -pe'BEGIN{undef $/} s/{{{.*?}}}//gs;' $filename

            echo "   ------ Run expansion script"
            if [ ! ${PROCESSED_FILES[$filename]+_} ]
            then \
                $SIM_CPP11 $filename
                PROCESSED_FILES[$filename]=1
            fi
            if [ ! ${PROCESSED_FILES[$HEADER]+_} ]
            then \
                $SIM_CPP11 $HEADER
                PROCESSED_FILES[$HEADER]=1
            fi
            if [ ! ${PROCESSED_FILES[$SOURCE]+_} ]
            then \
                $SIM_CPP11 $SOURCE
                PROCESSED_FILES[$SOURCE]=1
            fi
        else
            SOURCE="$PATHNAME/$COMPONENT_NAME.cpp"
            TEST_DRIVER="$PATHNAME/$COMPONENT_NAME.h"
            echo "++++++ Header"
            echo "   ++++++ Run expansion script for .h, .cpp, and lowest .t.cpp"
            if [ ! ${PROCESSED_FILES[$filename]+_} ]
            then \
                $SIM_CPP11 $filename
                PROCESSED_FILES[$filename]=1
            fi
            if [ ! ${PROCESSED_FILES[$SOURCE]+_} ]
            then \
                $SIM_CPP11 $SOURCE
                PROCESSED_FILES[$SOURCE]=1
            fi
            if [ ! ${PROCESSED_FILES[$SOURCE]+_} ]
            then \
                $SIM_CPP11 $SOURCE
                PROCESSED_FILES[$SOURCE]=1
            fi
        fi
        grep -q ${CPP03_COMPONENT_NAME} $PATHNAME/*/*.mem || echo ${CPP03_COMPONENT_NAME} >> $PATHNAME/*/*.mem
        sort -o $PATHNAME/*/*.mem $PATHNAME/*/*.mem
    done

# Copyright 2020 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License.  You may obtain a copy
# of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.

