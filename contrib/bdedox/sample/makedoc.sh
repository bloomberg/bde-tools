#!/bin/bash

# Usage: ./makedoc.sh <path-to-bde-repository>
#
# This script will create doxygen documentation for BDE Release 3.0.0, based on
# the header and package documentation files found in a copy of the BDE
# repository stored at the specified 'path-to-bde-repository'.  The
# repository must have the 'BDE_3.0.0.0' tag checked out.
#
# This script must be run from the 'samples' directory where it is stored, and
# the resulting documentation will be created in a subdirectory named 'output',
# which will be created if necessary.
#
# Note that the Doxygen 1.7.1 executable must be in one of the directories in
# your 'PATH'.

# Generate file list
find "$1/groups" -type f \( \( -name '*.h' -not -path '*+*' \) \
                            -o -name '*.txt' \)                \
    > filelist

# Make working directories
if ! [ -d output ]; then
    mkdir output
else
    rm output/*
fi

if ! [ -d converted ]; then
    mkdir converted
else
    rm converted/*
fi

# Invoke bdedox
../bin/bdedox ./bde300.cfg
if [ $? -ne 0 ]; then
    exit 1
fi

# Clean up temporary directory
if [ -d converted ]; then
    rm -r converted
fi

# Clean up file list
if [ -f filelist ]; then
    rm -r filelist
fi

# -----------------------------------------------------------------------------
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
# ------------------------------ END-OF-FILE ----------------------------------
