#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Change::Util::InterfaceSCM  qw/getFileHistorySCM/;
use Util::File::Basename        qw/basename/;
use Util::Message               qw/fatal/;
use Symbols                     qw/EXIT_SUCCESS EXIT_FAILURE/;
use Change::Symbols             qw/MOVE_REGULAR/;

sub usage {
   
    my $prog = basename($0);

    print <<EOUSAGE;
Usage: $prog -h | [-n <num>] <file> <library>
   
    --debug     | -d        Enable debug reporting.
    --verbose   | -v        Be verbose.
    --help      | -h        This screen.

    --num       | -n <num>  Only see the last <num> changes
    --staged    | -s        Show staged material also
EOUSAGE
}

sub getoptions {
    my %opts;

    if (not GetOptions(\%opts, qw[
        debug|d+
        verbose|v+
        help|h
        num|n=i
        move|m=s
        staged|s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }
    
    usage(), exit EXIT_SUCCESS if $opts{help};
    usage(), exit EXIT_FAILURE if @ARGV != 2;

    Util::Message::set_debug($opts{debug} || 0);
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

MAIN: {

    my $opts = getoptions();
    my ($file, $lib) = @ARGV;

    my ($log, $err) = getFileHistorySCM($file, $lib, $opts->{num}, $opts->{staged});

    fatal $err if $err;

    for (@$log) {
        my ($csid, $date, $author, $log, $move, $status) = @$_;
        print <<EOREC;
-----------------------------------------------------------------------------------------
$csid ($move) with status $status checked in by $author on $date:

$log
EOREC
    }

}
