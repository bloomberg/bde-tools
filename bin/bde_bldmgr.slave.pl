#!/bbs/opt/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use File::Path;
use File::Copy;
use Getopt::Long;
use POSIX qw(uname strftime);
use IO::Handle;
use Sys::Hostname;

use BDE::Build::Uplid;
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);
use Util::Message qw(fatal debug);
use Util::Retry qw(
    retry_chdir retry_dir
    retry_open retry_open3 retry_system
);
use Util::File::Basename qw(basename dirname);

#------------------------------------------------------------------------------

use constant FAILED       => "!! FAILED";
use constant NOTSUPPORTED => "!! NOTSUPPORTED";
use constant SUCCEEDED    => "** SUCCEEDED";
use constant DEFAULT_JOBS => 4;

#------------------------------------------------------------------------------

=head1 SYNOPSIS

  bde_bldmgr.slave.pl -h | [-d] [-e] [-f <flags>] \
                           [-l <logdir>] [-r root] [-v] \
                           -t <target>[,<target>...] <group|package>

See C<bde_bldmgr.slave.pl -h> for brief usage information.

=head1 DESCRIPTION

This is the slave script remotely invoked by bde_bldmgr to carry out the build
on a given target machine. It collects the results of invoking a local build
and passes back status information (typically via a rsh-initiated network
connection) to the invoking bde_bldmgr.

=head1 NOTES

This script is not intended to be invoked directly; use bde_bldmgr instead.

=head1 MAINTAINER

  Peter Wainwright (pwainwright@bloomberg.net)

=cut

#------------------------------------------------------------------------------

umask 002;
STDOUT->autoflush(1);

my $iamwindows = ($^O eq 'MSWin32' || $^O eq 'cygwin');
    # TODO: review the 'cygwin' case
my $iammac = ($^O eq 'darwin');

my $pythonprefix="";
my $waf = "waf";

if ($iamwindows) {
    $pythonprefix = "python";
    $waf          = "e:\\git\\bde-oss-tools\\bin\\waf";
}

my $prog       = basename($0);
my $bindir     = $iamwindows ? $FindBin::Bin : dirname($0);
$bindir =~ s|/|\\|sg if $iamwindows;
my $FS         = $iamwindows ? "\\" : "/";
    # TODO: this is a hack - use File::Spec for portable file path manipulation
my $pathsep    = $iamwindows ? ";" : ":";

my %msvc_version_map = {
    "cl-14.00" => "msvc 8.0"
  , "cl-15.00" => "msvc 9.0"
  , "cl-16.00" => "msvc 10.0"
  , "cl-18.00" => "msvc 12.0"
};

unless ($iamwindows) {
    $ENV{RSU_LICENSE_MAP} = "/opt/rational/config/PurifyPlus_License_Map";
}

# gmake standard location: /opt/swt/bin
$ENV{PATH} .= ":".join(':',qw[
    /opt/swt/bin
]);

if ($^O =~ /solaris/) {
    # Sun builds require adding a few paths to the prompt to find things like
    # ar
    $ENV{PATH} .= ":".join(':',$bindir,qw[
        /usr/ccs/bin
    ]);

    # We need to make sure child processes pick up /bbs/opt/bin/perl.
    $ENV{PATH} = "/bbs/opt/bin:$ENV{PATH}";
}

if ($^O =~ /darwin/) {
    # pkg-config may be in /opt/local/bin on darwin
    $ENV{PATH} = "$ENV{PATH}:/opt/local/bin";
}

# Need /opt/swt/bin to find gmake - DRQS 46663127
$ENV{PATH} .= ":".join(':',qw[
    /opt/swt/bin
]);

if ($^O =~ /aix/) {
    # Email from Mark Hannum on 20100720 @ 15:16:33
    #> My guess is that the test script is unsetting the EXTSHM variable ..
    # make sure that 'EXTSHM=on' is set before your pekludge task executes.
    # -Mark

    $ENV{EXTSHM} = "on";
}

if ($^O =~ /hpux/) {
    #DRQS 25995466 Updated. OU Q 'bdet_Datetime::printToBuffer' not returning
    #expect 'bdet_Datetime::printToBuffer' not returning expected value on
    #Windows and HP
    # 6/29/11   14:02:53   RAYMOND SEEHEI CHIU (PROG)
    # Mike G.,
    # Can you see if we can compile with macro _XOPEN_SOURCE=600 and
    # environment variable UNIX_STD=2003 for HP?
    # This is documented in the manual page ("man standards 5")

    $ENV{UNIX_STD} = "2003";
}

#------------------------------------------------------------------------------
# Process command line

my %opts;

Getopt::Long::Configure("bundling");
unless (GetOptions(\%opts,qw[
    after|A=s
    before|B=s
    build|b=s
    compiler|c=s
    check|C
    debug|d+
    define|D=s@
    express|e
    envbat|E=s
    help|h
    nodepend|n
    make|M=s
    nice|i:i
    options|o=s
    path|P=s@
    jobs|parallel|j|pa:i
    rebuild|R
    uptodate|U
    uplid|u=s
    where|root|w|r=s
    serial|s
    target|t=s
    tag|T=s

    group|g=s
    flags|f=s@
    verbose|v+
    logdir|l=s
    masterlogdir|m=s
])) {
    usage(), exit 0;
}

usage(),exit 0 if $opts{help};

my $after    = $opts{after}    || '';
my $before   = $opts{before}   || '';

my $build    = $opts{build}    || $opts{where};

die "Need a build location or a root location - specify at least one of -b or -w" unless defined $build;

my $compiler = $opts{compiler} || '';
my $check    = $opts{check}    || '';
my $defines  = $opts{define} ? join(' ', map { "-D$_" } @{$opts{define}}) : '';
my $express  = $opts{express}  || 0;
my $make     = $opts{make}     || '';
my $nice     = $opts{nice}     || 0;
my $nodepend = $opts{nodepend} || 0;
my $options  = $opts{options}  || '';
my $rebuild  = $opts{rebuild}  || 0;
my $uptodate = $opts{uptodate} || 0;
my $debug    = $opts{debug}    || 0;
my $group    = $opts{group}    || '';
my $flags    = $opts{flags}    || '';
my $verbose  = $opts{verbose}  || 1;
my $where    = $opts{where}    || $ENV{BDE_ROOT};

my $tag      = $opts{tag}      || "";

my $masterlogdir = $opts{masterlogdir}  || "";

my $uplid;
if ($opts{uplid}) {
    fatal "--uplid and --compiler are mutually exclusive"
      if $opts{compiler};
    $uplid = BDE::Build::Uplid->unexpanded($opts{uplid});
    $compiler=$uplid->compiler()."-".$uplid->compilerversion();

} elsif ($opts{compiler}) {
    $uplid = BDE::Build::Uplid->new({ compiler => $opts{compiler},
                                      where    => $opts{where}
                                    });
} else {
    $uplid = BDE::Build::Uplid->new({ where    => $opts{where} });
}

if ($group) {
    if (@ARGV) {
        usage("Trailing arguments incompatible with --group");
        exit EXIT_FAILURE;
    }
} else {
  SWITCH: foreach (scalar@ARGV) {
        $_==0 and do {
            usage("No --group or trailing group argument supplied");
            exit EXIT_FAILURE;
        };
        $_==1 and do {
            $group = $opts{group} = $ARGV[0];
            last;
        };
      DEFAULT:
        usage("@ARGV: only one trailing group argument allowed");
        exit EXIT_FAILURE;
    }
}

#------------------------------------------------------------------------------
# logging

{
    my $logOpened=0;
    my $logfile;
    my $SLAVELOG;

    sub open_slavelog ($) {
        return $logfile if $logOpened;

        my $logdir=shift;

        my @lt = localtime();
        my $ymdtag = strftime("%Y%m%d", @lt);

        $logdir.="${FS}$ymdtag";

        my $dtag = strftime("%Y%m%d-%H%M%S", @lt);

        unless (retry_dir $logdir) {
            mkpath($logdir, 0, 0777) or die "cannot make '$logdir': $!\n";
        }
        my $logarch = (uname)[0];
        $logarch =~ s/\s+/_/g;
        my $hostname = hostname();
        $logfile = "$logdir${FS}slave.$dtag.$group.$uplid.$hostname.$$.log";

        $SLAVELOG=new IO::Handle;
        retry_open($SLAVELOG,">$logfile")
                                    or die "cannot open build output file: $!";
        $SLAVELOG->autoflush(1);

        $logOpened = 1;

        write_logandverbose("=========== Logfile is $logfile");

        return $logfile;
    }

    sub write_slavelog (@) {
        print $SLAVELOG @_;
    }

    sub close_slavelog () {
        if ($masterlogdir) {
            my $sourcefile = $logfile;

            my $scp = "scp";

            if ($iamwindows) {
                $scp = 'E:\cygwin\bin\scp';
                $sourcefile =~ s{\\}{/}g;
                $sourcefile =~ s{^(\w):}{/$1/};
            }


            write_logandverbose("Running $scp $sourcefile $masterlogdir");

            system("$scp $sourcefile $masterlogdir");
        }

        close $SLAVELOG;
    }
}

open_slavelog($opts{logdir});

sub write_logandverbose (@) {
    write_slavelog @_,"\n";
    print @_,"\n" if $verbose;
}

sub find_waf {
    foreach my $dir (split /$pathsep/, $ENV{PATH}) {
        # Can't use -x here, since waf isn't executable on windows
        if (-e "$dir/waf") {
            return "$dir/waf";
        }
    }
}

if ($iamwindows) {
    $ENV{PATH} = "c:\\python27\\;$ENV{PATH};c:\\wafsupport;e:\\git\\bde-oss-tools\\bin;";
    $ENV{BDE_PATH}.=":e:/git/bde-oss-tools";

    write_logandverbose "PATH is now $ENV{PATH}";
    write_logandverbose "BDE_PATH is now $ENV{BDE_PATH}";
}

if (!find_waf()) {
    if (!$iamwindows) {
        $ENV{PATH} = "/opt/bb/bin:$ENV{PATH}:/bbshr/bde/bde-oss-tools/bin:$FindBin::Bin/../../bde-oss-tools/bin:$FindBin::Bin";
        $ENV{BDE_PATH}.=":/bbshr/bde/bde-oss-tools:$FindBin::Bin/../../bde-oss-tools";

        write_logandverbose "PATH is now $ENV{PATH}";
        write_logandverbose "BDE_PATH is now $ENV{BDE_PATH}";
    }

}
else {
    write_logandverbose "NOT expanding path, waf is ".`which waf`;
}

if (!find_waf()) {
    write_logandverbose("!! Unable to find waf");
    exit 1;
}



# Disabling envbat feature for 'waf' - using Visual Studio env breaks waf.
if (0 && $opts{envbat}) {
    write_logandverbose "Got --envbat $opts{envbat}";
    open ENVBAT,
           "$FindBin::Bin/run_batch_file_and_dump_env.bat \"$opts{envbat}\" |";
    while(<ENVBAT>) {
        /^(.*?)=(.*)$/ and $ENV{$1}=$2;
    }
    close(ENVBAT);

    write_logandverbose "Populated environment to:";
    write_logandverbose "\t$_=$ENV{$_}" foreach sort keys %ENV;
}

if ($opts{path}) {
    write_logandverbose "Got --path @{$opts{path}}";

    my $newpath=(join ":",@{$opts{path}});

    if (exists $ENV{BDE_PATH}) {
        $ENV{BDE_PATH} = "$newpath:$ENV{BDE_PATH}";
    }
    else {
        $ENV{BDE_PATH} = $newpath;
    }

    write_logandverbose "Populated BDE_PATH to: $ENV{BDE_PATH}\n";
}

if ($opts{uptodate} && $opts{rebuild}) {
    fatal "--uptodate and --rebuild are mutually exclusive"
}

unless ($where) {
   $where = $bindir;
   $where =~s|tools/bin/?$||s;
}

usage("No group or package supplied"),exit EXIT_FAILURE
  unless $opts{group};
usage("No target build type supplied"), exit EXIT_FAILURE
  unless $opts{target};

unless ($opts{logdir}) {
    $opts{logdir}="$build/logs";
}

my @targets=split /\W+/,$opts{target};

#------------------------------------------------------------------------------

sub usage {
    my $msg=shift;
    print STDERR "!! $msg\n" if $msg;

    my $DEFAULT_JOBS=DEFAULT_JOBS;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-e] [-f <flags>] \\
                    [-l <logdir>] [-r root] [-v] \\
                    -t <target>[,<target>...] <group|package>
Local options:
  --debug    | -d            enable debug reporting
  --help     | -h            usage information (this text)
  --flags    | -f <f>=<v>    optional arbitrary flags to pass to bde_build.pl
  --logdir   | -l <path>     log destination directory
  --nice     | -i <niceness> "nice" level for slave process (and children)
  --verbose  | -v            enable verbose output in build
  --target   | -t <targets>  build target or comma-separated list of targets
  --where    | -w <dir>      specify explicit root

Passed to build:
  --after    | -A <target>   make explicit target(s) after regular build
  --before   | -B <target>   make explicit target(s) before regular build
  --build    | -b <path>     directory to build in (wscript location)
  --compiler | -c <comp>     compiler definition for system (default: 'def')
  --check    | -C            perform 'checkin' code verification
  --define   | -D <macro>    define one or more makefile macro overrides:
                               <name>[=<value>][,<name>[=<value>]...]
  --express  | -e            express build (do not build or run test drivers)
  --group    | -g <grp|pkg>  the group or package to build (required),
                             may also be specified as a trailing argument.
  --jobs     | -j [<jobs>]   build in parallel up to the specified number of
                             jobs (default: $DEFAULT_JOBS jobs)
                             default if platform is not 'dg'
  --make     | -M <target>   make explicit target(s) only (e.g.: 'buildtest')
                             instead of entering normal build process
  --nodepend | -n            do not build dependent packages (not with groups)
  --options  | -o            specify options file (default: default.opts)
  --serial   | -s            serial build (equivalent to -j1)
                             default if platform is 'dg'
  --tag      | -T <string>   add "tag" string to lines of output
                                                               (defaults to "")
  --rebuild  | -R            force rebuild makefiles even if up to date
  --uptodate | -U            assume makefiles are up-to-date (not with -R)
  --uplid    | -u <uplid>    specify rather than derive platform ID. -c will
                             override or add compiler if specified.

See 'pod2text $0' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

MAIN: {
    retry_chdir($build);

    # if NOT on windows, renice process if --nice option is in effect
    if (!$iamwindows) {
        system("renice -n $nice $$") if $nice;
    }

    # open slave log file; returns log filename
    my $logfile=open_slavelog($opts{logdir});

    # preamble
    write_logandverbose "** $prog started";
    write_logandverbose "-- build root is      $where" if $where;
    write_logandverbose "-- build location is  $build" if $build;
    write_logandverbose "** building targets:  @targets";
    write_logandverbose "** building group:    $group";
    write_logandverbose "** building compiler: $compiler";
    write_logandverbose "** building uplid:    $uplid";
    write_logandverbose "-- verbosity level    $verbose";
    write_logandverbose "-- express mode       "
                                              .($express?"enabled":"disabled");
    write_logandverbose "-- build tag          $tag";

    # construct common command arguments
    my @basecmd=($waf);
    if ($iamwindows) {
        @basecmd = ($pythonprefix
                  , $waf
                    ); # for Windows
    }

    $ENV{BDE_ROOT}=$where;
    $ENV{BDE_PATH}="$where:$ENV{BDE_ROOT}";

    # -A, -B, -c, -C, -d, -D, -e, -M, -n, -o, -R, -u, -w
    push @basecmd,"-A",$after if $after;
    push @basecmd,"-B",$before if $before;
    push @basecmd,"-c",$compiler if $compiler;
    push @basecmd,"-C" if $check;
    push @basecmd,"-d" if $debug;
    push @basecmd,$defines if $defines;
    push @basecmd,"-e" if $express;
    push @basecmd,"-M",$make if $make;
    push @basecmd,"-n" if $nodepend;
    push @basecmd,"-o",$options if $options;
    push @basecmd,"-R" if $rebuild;
    push @basecmd,"-U" if $uptodate;
    # Don't specify uplid on windows - bde_build.pl will figure it out from
    # the compiler and the environment.
    push @basecmd,"-u",$uplid if $uplid && !$iamwindows;
    push @basecmd,"-w",$where if $where;

    # on distributed builds, always rebuild
    push @basecmd,"-R";

    # enable retry to try to work around transient nfs failures
    push @basecmd,"-x";

    # -j, -s
    if ($opts{serial}) {
        push @basecmd,"-s";
    } elsif ($opts{jobs}) {
        push @basecmd,"-j",$opts{jobs};
    }

    # -f : f=v,f=v,f=v -ff=v -ff=v
    if ($flags) {
        foreach my $flagset (@$flags) {
            foreach my $flag (split ",",$flagset) {
                my ($opt,$value) = split /=/,$flag,2;
                unless ($opt=~/^-/) {
                    $opt=((length $opt>1)?"--":"-").$opt; #may omit leading '-'
                }
                push @basecmd,$opt;
                push @basecmd,$value if defined $value;
            }
        }
    }

    # -t : invoke for each target specified
    TARGET: for my $target (@targets) {
        write_logandverbose("=============== BUILDING $target for $group");

        my $extraConfigureOptions = "";

        if (!$iamwindows) {
            my $setwafenv = "$pythonprefix $bindir${FS}bde_setwafenv.py -c $compiler -t $target --force_uplid=$uplid";

            write_logandverbose("Setting up waf env, with\n\tBDE_ROOT=$ENV{BDE_ROOT}\n\tBDE_PATH=$ENV{BDE_PATH}\n\tsetwafenv=\"$setwafenv\"\n\tPATH=$ENV{PATH}");

            print `which bde_setwafenv.py`;

            open(SETWAFENV,"$setwafenv|") or die "Unable to run $setwafenv, error $!";

            while(<SETWAFENV>) {
                if (/export\s+(\w+)="(.*)"/) {
                    write_logandverbose "Adding to env: $1=$2";
                    $ENV{$1}=$2;
                }
            }

            close(SETWAFENV);

            write_logandverbose("Done setting up waf env");
        }
        else { # windows
            $ENV{PREFIX}          =
                                  "$ENV{BDE_ROOT}\\install\\$compiler-$target";
            $ENV{PKG_CONFIG_PATH} = "$ENV{PREFIX}\\lib\\pkgconfig";
            $ENV{BDE_WAF_BUILD_DIR} = "$compiler-$target";
            $ENV{BDE_WAF_UFID}      = $target;

            write_logandverbose("Creating $ENV{PKG_CONFIG_PATH} if not present");
            File::Path::mkpath($ENV{PKG_CONFIG_PATH});

            $extraConfigureOptions="--msvc_version=\"$msvc_version_map{$compiler}\"";

            write_logandverbose("Set up waf env, with\n\tBDE_ROOT=$ENV{BDE_ROOT}\n\tBDE_PATH=$ENV{BDE_PATH}\n\tPATH=$ENV{PATH}\n\tPREFIX=$ENV{PREFIX}\n\tPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}\n\tBDE_WAF_UFID=$ENV{BDE_WAF_UFID}");
            write_logandverbose("******\n\tcompiler is \"$compiler\"\n\textraConfigureOptions = \"$extraConfigureOptions\"");
        }

        if ($iammac) {
            # In the mac case, we need to force CC and CXX to clang
            $ENV{CC}="clang";
            $ENV{CXX}="clang++";

            write_logandverbose("On mac, forcing CC=$ENV{CC} and CXX=$ENV{CXX}");
        }

        # construct target-specific command arguments
        write_logandverbose(`$pythonprefix $waf configure $extraConfigureOptions 2>&1`);

        my @cmd = ($waf, 'build');
        unshift @cmd, $pythonprefix if $pythonprefix;
        push @cmd, "--target=$group";
        push @cmd, "--test=build" if $tag=~/TEST-COMPILE/;
        push @cmd, "--test=run" if $tag=~/TEST-RUN/;
        push @cmd, "-kk";
        push @cmd, "-v" if $verbose;

        print "-- running command: @cmd\n" if $verbose>=2;
        write_logandverbose("======== running command: @cmd");

        # invoke command
        my ($rdh, $wrh)=(new IO::Handle,new IO::Handle);
        my $pid=retry_open3($rdh,$wrh,$rdh,@cmd) or die "open3 failed, error $!";
        my $output="";

        my $prefixString="<< $tag";
        my $logPrefix="";

        if($tag) {
            $logPrefix="$tag: ";
        }

        while (my $line=<$rdh>) {
            print $prefixString,$line;
            write_slavelog($logPrefix.strftime(" %H%M%S:",localtime).$line);
            $output.=$logPrefix.$line;
        }

        close $rdh; close $wrh;
        waitpid($pid,0); #reap child status into $?

        # examine output and send result string
        my $tagTrailer="";
        $tagTrailer=" $tag" if $tag;

        if ($? != 0) {
            if ($output =~ /ERROR:\s*Capabilities\s*of\s*\w+\s*deny\s*build/) {
                print NOTSUPPORTED, " ", $target,$tagTrailer," ";
            }
            else {
                print FAILED," ",$target,$tagTrailer," ";
                my $n = undef;
                for my $f (
                          $output =~ /\(see (.*?[\\\/]make\.[^\\\/]+\.log)\)/gm
                          ) {
                        $n = 1;
                        print "[see $f]";
                }
                if (!$n) {
                        for my $e ($output =~ /^(ERROR:.*)/gm) {
                                $n = 1;
                                print "[$e]";
                        }
                }
                if (!$n) {
                        print "[see $logfile]";
                }
            }
        } else {
            print SUCCEEDED," ",$target,$tagTrailer;
        }
        print "\n";
    }

    # postamble
    write_logandverbose "** $prog finished **";

    # close up shop
    close_slavelog();
    exit EXIT_SUCCESS;
}

#------------------------------------------------------------------------------
