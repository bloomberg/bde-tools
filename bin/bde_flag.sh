#!/usr/bin/ksh

o=$(dirname $(cd >/dev/null $(dirname $0); pwd -P))/binaries
b=bdeflag.m

case $(uname) in
    "SunOS" ) exec $o/$b.sundev1.tsk "$@" ;;
    "AIX"   ) exec $o/$b.ibm.tsk     "$@" ;;
    "Linux" ) exec $o/$b.linux.tsk   "$@" ;;
    "HP-UX" ) exec $o/$b.hp.tsk      "$@" ;;
esac

echo $0: unrecognized machine type '"'$(uname)'"' 1>&2
