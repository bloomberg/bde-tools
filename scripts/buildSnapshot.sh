#!/usr/bin/bash

if [ -z "$4" ]
then \
    echo "USAGE: $0 [-d] tarName outputPath rootpath [path [path...]] -- uor [uor...]"
    echo "    -d: also snapshot docs (optional, and slow)"
    exit 1
fi

if [ "$1" == "-d" ]
then \
    GET_DOCS=1
    shift
else
    GET_DOCS=0
fi

TARNAME=$1
shift

OUTPUTPATH=$1
shift

ROOTPATH=$1
shift

PATHSEP=""

while [ "$1" != "--" ]
do \
    PATHS="$PATHS$PATHSEP$1"
    PATHSEP=":"
    shift
done

if [ "$1" != "--" ]
then \
    echo missing -- separator between paths and uors
    exit 1
fi

# skip the -- separator
shift

UORLIST="$*"

if [ -z "$UORLIST" ]
then \
    echo No UORs specified
    exit 1
fi

if [ ! -z $(dirname $0) ]
then \
    PATH="$(dirname $0)/../bin:$PATH"
fi

SNAPSHOT=$(which bde_snapshot.pl)

if [ -z "$SNAPSHOT" ]
then
    echo Unable to find bde_snapshot.pl
    exit 1
fi

D=$(dirname $SNAPSHOT)
SNAPSHOT=$(cd "$D" 2>/dev/null && pwd || echo "$D")/bde_snapshot.pl

mkdir -p $OUTPUTPATH 2>/dev/null

cd $OUTPUTPATH 2>/dev/null

if [ $? -ne 0 ]
then \
    echo Unable to cd to $OUTPUTPATH
    exit 1
fi

export BDE_PATH="$PATHS:$BDE_PATH"

# the -e option makes bde_snapshot.pl snapshot the "etc" directory as well
$SNAPSHOT -dvvv -e -w $ROOTPATH -t . -c -j 12 $UORLIST

# bde_snapshot.pl doesn't get the subdirs correct for bsl+apache
rsync -av $ROOTPATH/groups/bsl/bsl+apache/ ./groups/bsl/bsl+apache/
# bde_snapshot.pl doesn't get .s files for bces
#rsync -av $ROOTPATH/groups/bce/bces/*.s ./groups/bce/bces/

if [ $? -ne 0 ]
then \
    echo bde_snapshot.pl failed
    exit 1
fi

PREV_PWD=$PWD

if [ $GET_DOCS -ne 0 ]
then \
    echo snapshotting doc files

    export PATHS
    PATHS="$ROOTPATH:$PATHS"

    for uor in $UORLIST;
    do \
        UOR_PATH=$(perl -e'$uor=$ARGV[0]; foreach(split /:/,$ENV{PATHS}) { foreach $part (qw(groups enterprise adapters wrappers legacy)) {if(-e "$_/$part/$uor") {print "$_/$part/$uor"; exit 0;}}} exit 1;' $uor)

        if [ ! -z "$UOR_PATH" ]
        then \
            UOR_BASE=$(perl -e'$ARGV[0]=~m{(.*)/([^/]+/[^/]+)$} or die; print $1' $UOR_PATH)
            UOR_TRAIL=$(perl -e'$ARGV[0]=~m{.*/([^/]+/[^/]+)$} or die; print $1' $UOR_PATH)
            echo "$uor found at $UOR_PATH ($UOR_BASE $UOR_TRAIL)"

            cd $UOR_BASE 2>/dev/null

            for dir in $(find $UOR_TRAIL -type d -name doc)
            do \
                mkdir -p $OUTPUTPATH/$dir
                rsync -av $dir/ $OUTPUTPATH/$dir/
            done
        fi
    done
fi

cd $PREV_PWD 2>/dev/null

/opt/swt/bin/tar czf $TARNAME $(ls | grep -v \.tar)

if [ $? -ne 0 ]
then \
    echo tar to $TARNAME failed
    exit 1
fi

echo SUCCESS: results are in $OUTPUTPATH/$TARNAME
exit 0
