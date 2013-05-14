#!/usr/bin/env bash

# Platform discovery for determining correct binaries
platform=$(uname)
if   [[ "$platform" = "SunOS" ]]; then
    ARCHCODE=sundev1
elif [[ "$platform" = "AIX"   ]]; then
    ARCHCODE=ibm
elif [[ "$platform" = "HP-UX" ]]; then
    ARCHCODE=hp
elif [[ "$platform" = "Linux" ]]; then
    ARCHCODE=linux
else
    print -u2 "!! This version must run on SunOS, AIX, HP-UX, or Linux only."
    exit 1
fi

set -v

pcomp -I. bdeflag_ut.t.cpp bdeflag_ut.cpp
pcomp -I. bdeflag_lines.t.cpp bdeflag_lines.cpp bdeflag_ut.cpp
pcomp -I. bdeflag_place.t.cpp bdeflag_place.cpp bdeflag_lines.cpp \
                                                                 bdeflag_ut.cpp
pcomp -I. bdeflag_group.t.cpp bdeflag_group.cpp bdeflag_place.cpp \
                                               bdeflag_lines.cpp bdeflag_ut.cpp
pcomp -I. bdeflag_componenttable.t.cpp bdeflag_componenttable.cpp \
           bdeflag_group.cpp bdeflag_place.cpp bdeflag_lines.cpp bdeflag_ut.cpp

all.pl bdeflag_ut.t.$ARCHCODE.tsk
all.pl bdeflag_lines.t.$ARCHCODE.tsk
all.pl bdeflag_place.t.$ARCHCODE.tsk
all.pl bdeflag_group.t.$ARCHCODE.tsk
all.pl bdeflag_componenttable.t.$ARCHCODE.tsk

rm -f bdeflag*.t.*.o *.mapfile 00plink* bdeflag_*.t_plink_timestamp*
