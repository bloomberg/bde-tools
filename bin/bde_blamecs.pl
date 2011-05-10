#!/bbs/opt/bin/perl -w

use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use File::Basename              qw/basename/;

use Util::Message               qw/fatal/;
use Symbols                     qw/EXIT_SUCCESS EXIT_FAILURE/;
use Getopt::Long;
use Change::Util::InterfaceSCM  qw/blameSCM/;
use Change::Symbols             qw/MOVE_REGULAR/;

sub usage {
   
    my $prog = basename($0);

    print <<EOUSAGE;
Usage: $prog -h | <file> <library>
   
    --debug     | -d        Enable debug reporting.
    --verbose   | -v        Be verbose.
    --help      | -h        This screen.

EOUSAGE
}

sub getoptions {
    my %opts;

    if (not GetOptions(\%opts, qw[
        debug|d+
        verbose|v+
        help|h
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

    my ($report, $err) = blameSCM($file, $lib, MOVE_REGULAR);

    fatal $err if $err;

    print $report;
}
