#!/bbs/opt/bin/perl

use strict;
use warnings;

use POSIX qw(strftime);

use Getopt::Long;
use Text::Wrap;

$|++;

my %groupLevels = (
    bsl => 0,
    bdl => 1,
    bde => 2,
    bce => 3,
    bae => 4,
    bte => 5,
    bbe => 6,
    bsi => 7,
    e_ipc => 8,
    bap => 9,
    a_comdb2 => 10,
    a_cdrdb => 11,
    a_cdrcache => 12,
);

my %opts;

my %options=(
    'build|b=s'      => "Build to scan for issues (nextrel|dev|bslintdev, default nextrel)"

  , 'date|d=s'       => "Dates to scan for issues."

  , 'component|c=s'  => "Component regex to filter for, e.g. 'list' for any component whose name contains 'list'."

  , 'errors|e'       => "Output only ERRORs."

  , 'failures|f'     => "Output only TEST fails."

  , 'group|g=s'      => "Group (actually, UOR) to filter for, e.g. 'bsl' for bsl (exact match, not a regex)."

  , 'help|h'         => "Print this help text."

  , 'match|m=s'      => "Output only those diagnostics whose text matches this regex, e.g. 'bslstl_sharedptr' to see any SharedPtr-related diagnostics in any package."

  , 'nowarnings|n'   => "Do not output WARNINGs."

  , 'uplid|u=s'      => "UPLID to filter for, e.g. 'unix-SunOS-sparc-5.10-cc-5.10' for that specific UPLID, or 'AIX' for any AIX UPLID.  This is a regex applied to the logfile names."

  , 'ufid|t=s'       => "UFID to filter for, e.g. '^dbg_exc_mt\$' for just dbg_exc_mt, or 'dbg_exc_mt' for any UFID that contains dbg_exc_mt, including _64 or _safe variants.  This is a regex applied to the UFID names."

  , 'summary|s'      => "Summary mode - don't print out details of diagnostics, just a count of each category."

  , 'warnings|w'     => "Output only WARNINGs."

  , 'exclude|x=s'      => "Exclude diagnostics which match this regex."
);

sub usage {
    my $ttySize = `stty size`;
    if (!$? && $ttySize) {
        chomp $ttySize;
        my $cols=(split /\s+/,$ttySize)[1];
        ${Text::Wrap::columns}  = $cols;
    }
    else {
        ${Text::Wrap::columns}  = $72;
    }

    $Text::Wrap::unexpand = 0;

    my $usage = Text::Wrap::fill("       ", "       ", <<"USAGE");

Usage: $0 [options] [log files...]

This script parses the nightly logs for diagnostics, and presents them grouped by UOR and platform.

By default, all categories (WARNINGS, ERRORS, and test FAILS) are displayed for the current date.

If log files are passed on the command line, the --date option is ignored, but the passed-in log files are still filtered by the --uplid and --group options, if any.

Options:

USAGE

    $usage=~s/^\s+//g;

    print $usage,"\n";

    my $prefixString = " "x28;
    foreach (sort keys %options) {
        printf "\t%-20s",$_;
        my $wrapped = Text::Wrap::wrap($prefixString, $prefixString, $options{$_});
        $wrapped=~s/^\s+//g;

        print $wrapped;

        print "\n\n";
    }
}

Getopt::Long::Configure("bundling");
unless (GetOptions(\%opts, sort keys %options)) {
    usage();
    exit 1;
}

if ($opts{build} && $opts{build}!~/^(nextrel|dev|bslintdev)$/) {
    print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
    print "!!! The --build option must be one of nextrel, dev, or bslintdev\n";
    print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
    print "\n";

    usage();
    exit 1;
}

$opts{build}||="nextrel";

foreach (sort keys %opts) {
    # Suppress undef warnings by setting any undefined options to "", which
    # is still 'false'.
    $opts{$_}||="";
}

if ($opts{help}) {
    usage();
    exit 0;
}


sub nameSplit {
    my $name = shift;

    $name=~m{slave(?:\.TEST-RUN)?\.(\d{8})-\d{6}\.([^.]+)\.(.*?)\.(\w+)\.\d+\.log} or die "Badly formed filename '$name'";

    return (date=>$1,group=>$2,uplid=>$3,host=>$4);
}

sub sortFunction {
    my %a_parts = nameSplit($a);
    my %b_parts = nameSplit($b);

    return $a_parts{date}                cmp $b_parts{date}
        || $a_parts{uplid}               cmp $b_parts{uplid}
        || ($groupLevels{$a_parts{group}}||999)
                                         <=> ($groupLevels{$b_parts{group}}||999)
}

my $verbose = 0;

if (!@ARGV) {
    if ($opts{date}) {
        foreach my $date(split /,/, $opts{date}) {
            my @files = glob("/home/bdebuild/bs/nightly-logs/$opts{build}/$date/*");
            if (!@files) {
                die "Couldn't find any files for date $date and build $opts{build}";
            }
            push @ARGV, @files;
        }
    }
    else {
        my $ymd = strftime("%Y%m%d", localtime);

        @ARGV=glob("/home/bdebuild/bs/nightly-logs/nextrel/$ymd/*");
    }
}

if ($opts{group}) {
    @ARGV=grep /\.$opts{group}\./o, @ARGV;
}

if ($opts{uplid}) {
    @ARGV=grep /$opts{uplid}/o, @ARGV;
}

@ARGV=sort sortFunction grep !/gcc-clang/ , @ARGV;

foreach my $argv (@ARGV) {
    my %fileInfo = nameSplit($argv);

    open(IN, "<", $argv);
    my $input = join "", <IN>;
    close(IN);

    my $banner="";

    $banner.="=============================================================\n";
    $banner.="=============================================================\n";
    $banner.="=============================================================\n";
    $banner.="=============================================================\n";
    $banner.=
       sprintf "==========> Read %8d bytes for %s %s\n           from %s\n",
                                                       length $input,
                                                       $fileInfo{uplid},
                                                       $fileInfo{group},
                                                       $argv
                                                       ;
    $banner.="=============================================================\n";
    $banner.="=============================================================\n";
    $banner.="=============================================================\n";
    $banner.="=============================================================\n";

    $input=~s/TEST-RUN:\s*//g;
    $input=~s/^\d{6}://gm;

    my %diagnostics_by_category;
    my %diagnostics_by_component;

    while($input=~m{\[(\S+) \((WARNING|ERROR|TEST)\)\] <<<<<<<<<<(.*?)>>>>>>>>>>}sg) {
        my ($component, $category, $message) = ($1, $2, $3);
        my $substr=substr($input,0,pos($input));
        my ($ufid) = ($substr=~/BDE_WAF_UFID=(\w+)/g)[-1];

        $diagnostics_by_category{$category}{$component}=[$ufid,$message];
        $diagnostics_by_component{$component}{$category}=[$ufid,$message];
    }

    foreach my $category (sort keys %diagnostics_by_category) {
        next if $opts{errors}     && $category ne "ERROR";
        next if $opts{warnings}   && $category ne "WARNING";
        next if $opts{failures}   && $category ne "TEST";

        next if $opts{nowarnings} && $category eq "WARNING";

        my $href = $diagnostics_by_category{$category};

        my $catbanner="";

        $catbanner.="  ---------------------------------------------------\n";
        $catbanner.="  ---------------------------------------------------\n";
        $catbanner.="  ------- $category\n";
        $catbanner.="  ---------------------------------------------------\n";
        $catbanner.="  ---------------------------------------------------\n";

        foreach my $component (sort keys %{$href}) {
            next if $opts{component} && $component!~/$opts{component}/o;

            my $output = $href->{$component}[1];

            next if $opts{exclude} && $output=~/$opts{exclude}/o;
            next if $opts{match}   && $output!~/$opts{match}/o;

            next if $opts{ufid}    && $href->{$component}[0]!~/$opts{ufid}/o;

            if ($banner) {
                print $banner;
                $banner = "";
            }

            if ($catbanner) {
                print $catbanner;
                $catbanner = "";
            }

            print "\t >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n";
            print "\t >>>>>> $component\n";
            print "\t >>>>>>      $fileInfo{uplid}\n";
            print "\t >>>>>>      $href->{$component}[0]\n";
            print "\t >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n";

            $output=~s/^.*CASE\s+\d+: SUCCESS.*\n//gm;
            $output=~s/^.*?\d{6}([:]?)\s*\n//gm;

            if (!$opts{summary}) {
                $output=~s/^/\t\t/gm;
                print $output,"\n";
            }
            else {
                my $lineCount=($output=~tr/\n/\n/);
                printf "\t\t%d lines\n", $lineCount;
            }
        }
    }
}

