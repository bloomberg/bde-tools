#!/opt/bb/bin/bash

mkdir -p $WORKSPACE/logs

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
FULL_LOG_LOCATION=${WORKSPACE}/logs/robo-full.$(hostname).${TIMESTAMP}.log
BRIEF_LOG_LOCATION=${WORKSPACE}/logs/robo-brief.$(hostname).${TIMESTAMP}.log
#JOB_LOG_LOCATION=${WORKSPACE}/logs/full-jenkins-job.$(hostname).${TIMESTAMP}.log

# Need a better way to do this - could wrap whole script in () | tee, but that
# is clunky...

#exec > $JOB_LOG_LOCATION 2>&1

if [[ -z "$WORKSPACE" ]]
then \
    echo Must specify WORKSPACE environment variable
    exit 1
fi

DPKG_LOCATION=/bb/bde/bdebuild/jenkins/$(hostname)/dpkg
export DPKG_LOCATION
mkdir -p $DPKG_LOCATION

echo Operating in WORKSPACE $WORKSPACE and DPKG_LOCATION $DPKG_LOCATION

cd "$DPKG_LOCATION"

if [ $? -ne 0 ]
then \
    echo FATAL: Unable to cd into $DPKG_LOCATION
    exit 1
fi

echo Setting up PATH for dpkg

#START Copied from devgit:deveng/chimera contrib/dpkg

# Enable PATH settings required for the use of the dpkg framework.
# See https://cms.prod.bloomberg.com/team/display/sb/DPKG for details.
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
if test -d /opt/swt/bin
then
    for OVERRIDE in \
        /opt/swt/bin/readlink /opt/swt/bin/tar /opt/swt/bin/gmake \
        /opt/swt/bin/find
    do
        PATH=$(/usr/bin/dirname $(/opt/swt/bin/readlink "$OVERRIDE")):$PATH
    done
    PATH=$PATH:/bbsrc/bin/builddeb/prod/bin:/bbs/bin/dpkg/bin
else
    echo "FATAL: contrib/dpkg can only be used with /opt/swt/bin present" >&2
    exit 1
fi

#END   Copied from devgit:deveng/chimera contrib/dpkg

if [[ ! -d data ]]
then \
    echo Initializing DPKG distro - should be needed only once
    dpkg-distro-dev init .
fi

echo Synchronizing source trees
rsync -a $WORKSPACE/source/ ./source/

echo =========================================
echo ======= DPKG GC AND CLEANUP PHASE =======
echo =========================================

dpkg-distro-dev gc
mv data.old data.old.$TIMESTAMP

dpkg-distro-dev scan --rmlock

rm -f .distribution.lock

echo ================================
echo ======= DPKG BUILD PHASE =======
echo ================================

for package in source/bde*tools source/bsl* source/bde-{core,bb,bdx}
do \
    dpkg-distro-dev build $package

    if [ $? -ne 0 ]
    then \
        echo FATAL: failure building $package
        exit 1
    fi
done

BINARY_PACKAGES=$(grep -i '^Package:' source/b*/debian/control   \
                | awk '{print $NF}'                              \
                | sort -u                                        \
                | grep -v 'RSSUITE'                              \
                | perl -e'my $line=join ",", map {chomp; $_} <>;
                          print $line,"\n"')
echo Y | dpkg-refroot-install $BINARY_PACKAGES

echo ================================
echo ======= ROBO BUILD PHASE =======
echo ================================

cd $WORKSPACE/robo

if [ $? -ne 0 ]
then \
    echo FATAL: could not cd in to robo subdir
    exit 1
fi

src_root=$(pwd)/trunk build_root=$(pwd)/build \
    . /bbsrc/bin/prod/bin/build/build_env

echo "    ================================"
echo "    ======== BUILD_PREBUILD ========"
echo "    ================================"

/bbsrc/bin/prod/bin/build/build_prebuild

echo "    ================================"
echo "    ======== ROBO LIB BUILD ========"
echo "    ================================"

mkdir -p build
cd       build

# We want the error code from make to be propagated, not the ones from
# the later stages of the pipe like tee or perl (which should very rarely
# fail)...

set -o pipefail

# The perl "1-liner" at the end of the pipe trims the robo output down to just
# library completion messages, warnings, and errors.  It also logs a copy of
# its output to $BRIEF_LOG_LOCATION.

DPKG_DISTRIBUTION="unstable --distro-override=\"$DPKG_LOCATION\"/"         \
    /opt/swt/install/make-3.82/bin/make --no-print-directory -j8 -k        \
    -f ../trunk/etc/buildlibs.mk INSTALLLIBDIR=$(pwd)/lib/                 \
    TARGET=install robo_prebuild_libs subdirs 2>&1                         \
    | tee $FULL_LOG_LOCATION                                               \
    | perl -ne'
        use POSIX qw(strftime);
        BEGIN{
            $|++;
            my $logname = shift @ARGV;
            open($logFH, ">", $logname)
               or warn "Perl log filter: Cannot open $logname, error $! "
                     . " - continuing.";
        }

        sub output {
            return if $_[0] =~ /\.(f|inc)", line/;
            return if $_[0] =~ /1520-003 \(W\) Option DFP is ignored./;
            return if $_[0] =~ /Debug line numbers >.*Reduce file size/;
            my $timestamp=strftime("%Y%m%d-%H%M%S", localtime);
            print $logFH "$timestamp: ", @_ if defined $logFH;
            print "$timestamp: ", @_;
        }

        output "==== Done $1\n" if /mv -f .*\.a\.tmp (\w+)\.a/;
        output($_) if /\b[Ee]rror:|\([SIEW]\)|\b[Ww]arning:/'              \
            $BRIEF_LOG_LOCATION

SAVED_ERROR=$?

echo "========================================================================"
echo "========================================================================"
#echo "Jenkins job log on $HOSTNAME in        : $JOB_LOG_LOCATION"
echo "Full robo log output on $HOSTNAME in   : $FULL_LOG_LOCATION"
echo "Brief robo log output on $HOSTNAME in  : $BRIEF_LOG_LOCATION"
echo "Make (and final job) return code: $SAVED_ERROR"
echo "========================================================================"
echo "========================================================================"

exit $SAVED_ERROR
