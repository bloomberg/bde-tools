#!/usr/bin/bash

if [ -z "$4" ]
then \
    echo "USAGE: $0 gitpath viewname outputPath tarName uor [uor...]"
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

GITPATH=$1
VIEWNAME=$2
OUTPUTPATH=$3
TARNAME=$4

shift 4

UORLIST="$*"

/usr/atria/bin/cleartool startview $VIEWNAME

if [ $? -ne 0 ]
then \
    echo startview $VIEWNAME failed
    exit 1
fi

cd $GITPATH

if [ $? -ne 0 ]
then \
    echo cd to git repo $GITPATH failed
    exit 1
fi

/opt/swt/bin/git pull

if [ $? -ne 0 ]
then \
    echo git pull failed
    exit 1
fi

echo \$0 is $0, snapshot is $SNAPSHOT
#echo GITPATH=$GITPATH
#echo VIEWNAME=$VIEWNAME
#echo OUTPUTPATH=$OUTPUTPATH
#echo UORLIST=$UORLIST

mkdir -p $OUTPUTPATH

cd $OUTPUTPATH 2>/dev/null || (echo Unable to cd to $OUTPUTPATH; exit 1)

export BDE_PATH=/view/$VIEWNAME/bbcm/infrastructure:/view/$VIEWNAME/bbcm/api:$BDE_PATH

# the -e option makes bde_snapshot.pl snapshot the "etc" directory as well
$SNAPSHOT -e -w $GITPATH -t . -c -j 12 $UORLIST

if [ $? -ne 0 ]
then \
    echo bde_snapshot.pl failed
    exit 1
fi

/opt/swt/bin/tar czf $TARNAME $(ls | grep -v \.tar)

if [ $? -ne 0 ]
then \
    echo tar to $TARNAME failed
    exit 1
fi

echo SUCCESS: results are in $OUTPUTPATH/$TARNAME
exit 0
