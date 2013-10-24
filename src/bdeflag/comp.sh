#!/usr/bin/env bash

set -x

tabs="$(greptab bdeflag{.m,_group,_place,_lines,_ut,_componenttable}.{h,cpp,t.cpp})"
if [ ! -z "$tabs" ] ; then
    echo Tabs found in $tabs 1>&2
    exit 1
fi

pcomp -I. bdeflag{.m,_group,_place,_lines,_ut,_componenttable}.cpp
rm -f *plink_timestamp* 00plink_*
