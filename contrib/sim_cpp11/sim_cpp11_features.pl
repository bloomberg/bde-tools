#!/usr/bin/env bash

# 20241210 - there were 2 copies of this script in this repo - unifying them
# to use the version in
# <bde-tools>/BdeBuildSystem/scripts/sim_cpp11_features.pl
# This script is stubbed rather than the other one, since the other location is
# deployed as part of the production release.

SCRIPT_DIR=$(dirname $0)

exec $SCRIPT_DIR/../../BdeBuildSystem/scripts/sim_cpp11_features.pl "$@"
