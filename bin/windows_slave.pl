#!/cygdrive/c/Perl/bin/perl
#!/usr/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use File::Path;
use File::Copy;
use Getopt::Long;
use POSIX qw(uname);
use IO::Handle;

#use BDE::Build::Uplid;
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);
use Util::Retry qw(
    retry_chdir retry_dir
    retry_open retry_open3 retry_system
);
use Util::File::Basename qw(basename dirname);

#------------------------------------------------------------------------------

use constant FAILED       => "!! FAILED";
use constant NOTSUPPORTED => "!! NOTSUPPORTED";
use constant SUCCEEDED    => "** SUCCEEDED";
use constant DEFAULT_JOBS => 2;

### XXX FIXME
my $LOGIN = "bdebuild";
my $SUNBOX = "sundev2.bloomberg.com";

#------------------------------------------------------------------------------

=head1 SYNOPSIS

  linux.slave.pl -h | [-d] [-e] [-f <flags>] \
                           [-l <logdir>] [-r root] [-v] \
                           -t <target>[,<target>...] <group|package>

See C<linux.slave.pl -h> for brief usage information.

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
sub expandCompilerMsgSpec($);
sub searchMessagesForSpecMatches($$$);

umask 002;
STDOUT->autoflush(1);
++$|;

my $iamlinux = 1;
my $prog       = basename($0);
my $perl_bindir     = dirname($0);
my $bindir = $perl_bindir;
if ($perl_bindir =~ /bde_devintegrator/) {
    $perl_bindir = "bde_devintegrator\\tools\\bin";
}
elsif ($perl_bindir =~ /(bde_releaseintegrator[a-z0-9]*)/) {
    $perl_bindir = "$1\\tools\\bin";
}
else {
    $perl_bindir = "bde_integrator\\tools\\bin";
}
#$perl_bindir = "e:\\cygwin\\View\\" . $perl_bindir;
$perl_bindir = "/view/" . $perl_bindir;
print "perl_bindir $perl_bindir\n";
my $FS         = "/";

#------------------------------------------------------------------------------
# Process command line

my %opts;

Getopt::Long::Configure("bundling");
unless (GetOptions(\%opts,qw[
    after|A=s
    before|B=s
    compiler|c=s
    check|C
    debug|d+
    define|D=s@
    express|e
    help|h
    nodepend|n
    make|M=s
    options|o=s
    jobs|parallel|j|pa:i
    rebuild|R
    uptodate|U
    uplid|u=s
    where|root|w|r=s
    serial|s
    target|t=s
    tag|T=s

    warning|W=s
    error|E=s

    group|g=s
    flags|f=s@
    verbose|v+
    logdir|l=s
])) {
    usage(), exit 0;
}

usage(),exit 0 if $opts{help};

my $after    = $opts{after}    || '';
my $before   = $opts{before}   || '';
my $compiler = $opts{compiler} || '';
my $check    = $opts{check}    || '';
my $defines  = $opts{define} ? join(' ', map { "-D$_" } @{$opts{define}}) : '';
my $express  = $opts{express}  || 0;
my $make     = $opts{make}     || '';
my $nodepend = $opts{nodepend} || 0;
my $options  = $opts{options}  || '';
my $rebuild  = $opts{rebuild}  || 0;
my $uptodate = $opts{uptodate} || 0;
my $uplid    = "windows-Windows_NT-x86-5.1-cl-14.00";#new BDE::Build::Uplid( $opts{uplid} || undef );
#my $uplid    = new BDE::Build::Uplid( $opts{uplid} || undef );

my $debug    = $opts{debug}    || 0;
my $group    = $opts{group}    || '';
my $flags    = $opts{flags}    || '';
my $verbose  = $opts{verbose}  || 0;
my $where    = $opts{where}    || $ENV{BDE_ROOT};

my $tag      = $opts{tag}      || "";

my $warnInfo = undef;
my $errInfo  = undef;

if (exists $opts{warning}) {
    $warnInfo=expandCompilerMsgSpec($opts{warning});
}

if (exists $opts{error}) {
    $errInfo=expandCompilerMsgSpec($opts{error});
}

if ($opts{uptodate} && $opts{rebuild}) {
    usage("--uptodate and --rebuild are mutually exclusive");
    exit EXIT_FAILURE;
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

unless ($where) {
   $where = $bindir;
   $where =~s|bin/?$|groups|s;
}

usage("No group or package supplied"),exit EXIT_FAILURE
  unless $opts{group};
usage("No target build type supplied"), exit EXIT_FAILURE
  unless $opts{target};

unless ($opts{logdir}) {
    $opts{logdir}=$bindir;
    $opts{logdir} =~ s{/[^/]+/?$}{/logs};
}

my @targets=split /\W+/,$opts{target};

#------------------------------------------------------------------------------
# logging

{
    my $SLAVELOG;

    sub open_slavelog ($) {
        my $logdir=shift;

        my @lt = localtime();
        my $dtag = sprintf "%04d%02d%02d-%02d%02d%02d",
            ($lt[5]+1900),($lt[4]+1),$lt[3],$lt[2],$lt[1],$lt[0];

        unless (retry_dir $logdir) {
            mkpath($logdir, 0, 0777) or die "cannot make '$logdir': $!\n";
        }
        my $logarch = (uname)[0];
        $logarch =~ s/\s+/_/g;
        my $logfile = "$logdir/slave.$dtag.$group.$uplid.log";

        $SLAVELOG=new IO::Handle;
        retry_open($SLAVELOG,">$logfile") or die "cannot open build output file: $!";
        $SLAVELOG->autoflush(1);

        return $logfile;
    }

    sub write_slavelog (@) {
        print $SLAVELOG @_;
    }

    sub close_slavelog () {
        close $SLAVELOG;
    }
}

sub write_logandverbose (@) {
    write_slavelog @_,"\n";
    print @_,"\n" if $verbose;
}

# convert from "stringified" representation to
# "perl" internal ref.  The data to capture is expressed as a
# "stringified" compound perl data structure
# e.g.: '[qr{\s+([^:]+):(\d+): warning: (.*)}, { file=>1, line=>2, message=>3}]'
# The first field is a regex ref with 3 captures
# The second field is a hash ref with 3 keys, file, line,
# and message, with each key being associated with the
# index of the capture containing that field
sub expandCompilerMsgSpec($) {
    my $info=$_[0];

    $info=eval($info);
    return undef if $@;

    if(ref $info ne 'ARRAY') {
        return undef;
    }
    elsif(@{$info} != 2) {
        return undef;
    }
    elsif(uc(ref $info->[0]) ne 'REGEXP') {
        return undef;
    }
    elsif(ref $info->[1] ne 'HASH') {
        return undef;
    }
    elsif(!(     exists $info->[1]{file}
              && exists $info->[1]{line}
              && exists $info->[1]{message}
          ))
    {
        return undef;
    }

    return $info;
}

sub searchMessagesForSpecMatches($$$)
{
    my ($msgs, $spec, $match_r) = @_;

    if ($spec) {
        # the various "map" variables are a way to construct
        # "soft" references to $1, $2, etc...
        my $fileMap="''";
        my $lineMap="''";
        my $msgMap="''";

        if($spec->[1]{file}=~/\d/) {
            $fileMap=sprintf "\$%1d",$spec->[1]{file};
        }
        if($spec->[1]{line}=~/\d/) {
            $lineMap=sprintf "\$%1d",$spec->[1]{line};
        }
        if($spec->[1]{message}=~/\d/) {
            $msgMap=sprintf "\$%1d",$spec->[1]{message};
        }

        my $re=$spec->[0];

        while($msgs =~ /$re/g) {
            push @{$match_r},[eval($fileMap),eval($lineMap),eval($msgMap)];
        }
    }
}

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
  --verbose  | -v            enable verbose output in build
  --target   | -t <targets>  build target or comma-separated list of targets
  --where    | -w <dir>      specify explicit root
  --warning  | -W <warnInfo> specify data needed to capture warnings in compiler
                             output.  The data to capture is expressed as a
                             "stringified" compound perl data structure
                             e.g.: -W '[qr{\\s+([^:]+):(\\d+): warning: (.*)}, { file=>1, line=>2, message=>3}]'
                             The first field is a regex ref with 3 captures
                             The second field is a hash ref with 3 keys, file, line,
                             and message, with each key being associated with the
                             index of the capture containing that field
  --error    | -E <errInfo>  specify data needed to capture errors in compiler
                             output.
                             e.g.: -E '[qr{\\s+([^:]+):(\\d+): error: (.*)}, { file=>1, line=>2, message=>3}]'

Passed to build:
  --after    | -A <target>   make explicit target(s) after regular build
  --before   | -B <target>   make explicit target(s) before regular build
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
  --tag      | -T <string>   add "tag" string to lines of output (defaults to "")
  --rebuild  | -R            force rebuild makefiles even if up to date
  --uptodate | -U            assume makefiles are up-to-date (not with -R)
  --uplid    | -u <uplid>    specify rather than derive platform ID. -c will
                             override or add compiler if specified.

See 'pod2text $0' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

MAIN: {
    # on windows, go to view specified by root
    if ($iamlinux) {
        # we do not care if it works, it will usually already exist
        mkdir($where);
        retry_chdir($where);

        # run startview on $SUNBOX
        my $view = $where;
        $view =~ s|^.*/([^/]+)$|$1|;
        my $cmd = "ssh -q -l $LOGIN $SUNBOX \"/usr/atria/bin/cleartool startview $view\"";
        print "-- running $cmd\n" if $verbose>=1;
        system($cmd) && die("Can't startview");

        # Sync everything but the groups. The "groups" subdir is huge
        # so if we are going to try to sync only what we need there
        my $rsync_flags = ' --rsh=ssh --force -rltgDqz --exclude=logs --exclude=unix-Sun* --exclude=unix-dgux* --exclude=unix-Cygwin* --exclude=unix-HP* --exclude=unix-AIX* --exclude=windows-* --exclude=*dbg* --exclude=unix-Linux* --exclude=scm ';


        my $rsync_cmd = 'rsync --include=groups/releases --exclude=/groups/** '
                      . "$rsync_flags $LOGIN\@$SUNBOX:$where/bbcm/infrastructure/ $where";
        print "-- running $rsync_cmd\n" if $verbose>=1;
        system($rsync_cmd) && warn "non-groups rsync failed $!";

        # try to sync groups, note the rsync might fail if we did not get
        # a group in the groups subdir. It does not matter though
        # this is not what we tried to build
        #
        # XXX It might be a problem in the future, since we have
        # no way of figuring the potential dependencies of $group
        my $g = substr($group, 0, 3);
        if ($g ne $group) {
            $g .= "/$group";
            # if this is a component name, only keep the package name
            $g =~ s/^(.*)_[^_\/]*$/$1/g;
        }
        $rsync_cmd = "rsync $rsync_flags $LOGIN\@$SUNBOX:$where/bbcm/infrastructure/groups/$g/ $where/groups/$g";
        print "-- running $rsync_cmd\n" if $verbose>=1;
        system($rsync_cmd) && print "Could not find group \"$group\", IGNORED";

        # kill the build logs
        # This will allow us to determine very easily if the build updated them
        # and send the content back to the log files in the view
        unlink ("$where/groups/bce/group/build.log",
                "$where/groups/bte/group/build.log");
    }

    # open slave log file; returns log filename
    my $logfile=open_slavelog($opts{logdir});

    # preamble
    write_logandverbose "** $prog started";
    write_logandverbose "-- build root is $where" if $where;
    write_logandverbose "** building targets: @targets";
    write_logandverbose "-- verbosity level $verbose";
    write_logandverbose "-- express mode ".($express?"enabled":"disabled");

    # construct common command arguments
    #my @basecmd=("$perl_bindir${FS}bde_build.pl");
    my @basecmd=("$perl_bindir${FS}bdebuild.bat");

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
    push @basecmd,"-u",$uplid if $uplid;
    push @basecmd,"-w","$perl_bindir\\..\\.." if $where;
    push @basecmd,"-N";

    # on distributed builds, always rebuild and skip non-compliant package tests
    push @basecmd,"-R","-E";

    # -j, -s
    if ($opts{serial}) {
        push @basecmd,"-s";
    } elsif ($opts{jobs}) {
        if ($opts{jobs} > 2) {
                $opts{jobs} = 2;
        }
        push @basecmd,"-j",$opts{jobs};
    } else {
        push @basecmd,"-j2";
    }


    # -f : f=v,f=v,f=v -ff=v -ff=v
    if ($flags) {
        foreach my $flagset (@$flags) {
            foreach my $flag (split ",",$flagset) {
                my ($opt,$value) = split /=/,$flag,2;
                unless ($opt=~/^-/) {
                    $opt=((length $opt>1)?"--":"-").$opt; #may omit leading '-';
                }
                push @basecmd,$opt;
                push @basecmd,$value if defined $value;
            }
        }
    }

    # -t : invoke for each target specified
    for my $target (@targets) {
        if ($target =~ /_64$/) {
                print FAILED," ",$target," ";
                print "[not supported on this machine]\n";
                next;
        }

        # construct target-specific command arguments
        my @cmd = @basecmd;
        push @cmd,"-t",$target,$group;
        print "-- running command: @cmd\n" if $verbose>=2;

        # invoke command
        my ($rdh, $wrh)=(new IO::Handle,new IO::Handle);
        my $pid=retry_open3($rdh,$wrh,$rdh,@cmd);
        my $output="";

        my $prefixString="<< $tag";
        my $logPrefix="";

        if($tag) {
            $logPrefix="$tag: ";
        }

        while (my $line=<$rdh>) {
            print $prefixString,$line if $verbose>=3;
            write_slavelog($logPrefix.$line);
            $output.=$logPrefix.$line;
        }
        close $rdh; close $wrh;
        waitpid($pid,0); #reap child status into $?

        # examine output and send result string
        my $tagTrailer="";
        $tagTrailer=" $tag" if $tag;

        my @warnings;
        my @errors;

        searchMessagesForSpecMatches($output, $warnInfo, \@warnings);
        searchMessagesForSpecMatches($output, $errInfo, \@errors);

        foreach(@warnings) {
            print "$tag-$target\{WARNING\},$_->[0],$_->[1],$_->[2]\n"
        }

        foreach(@errors) {
            print "$tag-$target\{ERROR\},$_->[0],$_->[1],$_->[2]\n"
        }

        if ($? != 0) {
            if ($output =~ /ERROR:\s*Capabilities\s*of\s*\w+\s*deny\s*build/) {
                print NOTSUPPORTED, " ", $target,$tagTrailer," ";
            }
            else {
                print FAILED," ",$target,$tagTrailer," ";
                if ($output =~ /\(see (.*)\)/m) {
                    # This has to be printed first in order not to confuse the
                    # build manager.
                    my $log = $1;
                    $log =~ s/e:\\View//i;
                    $log =~ s/\\/\//g;
                    $log = "/view" . $log;
                    my $old = $log;
                    # fix the name for the report
                    $log =~ s|$where/groups|$where/bbcm/infrastructure/groups|;
                    print "[see $log]\n";
                    if ($iamlinux) {
                        my $dest = dirname($log);
                        # create the directory on sundev2 if needed
                        my $scp = "ssh -q -l $LOGIN $SUNBOX \"mkdir $dest 2>/dev/null\"";
                        print "-- running $scp\n" if $verbose>=1;
                        system($scp);
                        # copy the log file
                        $scp = "scp -q -B $old $LOGIN\@$SUNBOX:$dest";
                        print "-- running $scp\n" if $verbose>=1;
                        system($scp) && print "WARNING unable to copy $old to $dest: $!\n";
                    }
                } elsif ($output =~ /^(ERROR:.*)/m) {
                    print "[$1]";
                } else {
                    my $printed_log = $logfile;
                    $printed_log =~ s|$where/logs|$where/bbcm/infrastructure/logs|;
                    # log file directory was updated
                    $printed_log =~ s|$where/tools/logs|$where/bbcm/infrastructure/tools/logs|;
                    print "[see $printed_log]";
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
    if ($iamlinux) {
        # copy slavelog
        my $log = $logfile;
        # old dir
        $log =~ s|$where/logs|$where/bbcm/infrastructure/logs|;
        # log file directory was updated
        $log =~ s|$where/tools/logs|$where/bbcm/infrastructure/tools/logs|;
        my $dest = dirname($log);
        my $scp = "scp -q -B $logfile $LOGIN\@$SUNBOX:$dest";
        print "-- running $scp\n" if $verbose>=1;
        system($scp);
    }
    if ($iamlinux) {
        my $srcfile, my $destfile;
        # FIXME MAKE A FUNCTION

        # If a new bce build log has been created, send the content
        # to the master log file
        $srcfile = "$where/groups/bce/group/build.log";
        if (-e $srcfile) {
            $destfile = $srcfile;
            # Fix path: The directory structure is different on the Sun boxes
            $destfile =~ s|$where/groups|$where/bbcm/infrastructure/groups|;
            my $cmd = "cat $srcfile | ssh -q -l $LOGIN $SUNBOX \"cat - >> $destfile\"";
            print "-- running $cmd\n" if $verbose>=1;
            system($cmd);

        }

        # Copy bte build log
        $srcfile = "$where/groups/bte/group/build.log";
        if (-e $srcfile) {
            $destfile = $srcfile;
            $destfile =~ s|$where/groups|$where/bbcm/infrastructure/groups|;
            my $cmd = "cat $srcfile | ssh -q -l $LOGIN $SUNBOX \"cat - >> $destfile\"";
            print "-- running $cmd\n" if $verbose>=1;
            system($cmd);
        }
    }
    exit EXIT_SUCCESS;
}

#------------------------------------------------------------------------------

