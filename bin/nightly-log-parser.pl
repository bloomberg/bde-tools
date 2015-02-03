#!/bbs/opt/bin/perl

use strict;
use warnings;

use POSIX qw(strftime);

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

sub nameSplit {
    my $name = shift;

    $name=~m{slave(?:\.TEST-RUN)?\.(\d{8})-\d{6}\.([^.]+)\.(.*?)\.(\w+)\.\d+\.log} or die "Badly formed $name";

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

if ($ARGV[0] eq "-v") {
    $verbose = 1;
    shift @ARGV;
}

if (!@ARGV) {
    my $ymd = strftime("%Y%m%d", localtime);

    @ARGV=glob("/home/bdebuild/bs/nightly-logs/nextrel/$ymd/*");
}

@ARGV=sort sortFunction grep !/gcc-clang/, @ARGV;

foreach my $argv (@ARGV) {
    my %fileInfo = nameSplit($argv);

    open(IN, "<", $argv);
    my $input = join "", <IN>;
    close(IN);

    print "=============================================================\n";
    print "=============================================================\n";
    print "=============================================================\n";
    print "=============================================================\n";
    printf "==========> Read %8d bytes for %s %s\n",length $input,
                                                       $fileInfo{uplid},
                                                       $fileInfo{group};
    print "=============================================================\n";
    print "=============================================================\n";
    print "=============================================================\n";
    print "=============================================================\n";

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
        my $href = $diagnostics_by_category{$category};
        print "  ---------------------------------------------------\n";
        print "  ---------------------------------------------------\n";
        print "  ------- $category\n";
        print "  ---------------------------------------------------\n";
        print "  ---------------------------------------------------\n";

        foreach my $component (sort keys %{$href}) {
            print "\t >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n";
            print "\t >>>>>> $component\n";
            print "\t >>>>>>      $fileInfo{uplid}\n";
            print "\t >>>>>>      $href->{$component}[0]\n";
            print "\t >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n";
            my $output = $href->{$component}[1];
            $output=~s/^.*CASE\s+\d+: SUCCESS.*\n//gm;
            $output=~s/^.*?\d{6}([:]?)\s*\n//gm;

            if ($verbose) {
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

