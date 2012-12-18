#!/usr/bin/env bash

SRCS="bdeflag.m.cpp bdeflag_group.cpp bdeflag_place.cpp bdeflag_lines.cpp bdeflag_componenttable.cpp bdeflag_ut.cpp"

tabs="$(greptab $SRCS)"
if [ ! -z "$tabs" ] ; then
    echo Tabs found in $tabs 1>&2
    exit 1
fi

pcomp -I. $SRCS
rm -f *plink_timestamp*
