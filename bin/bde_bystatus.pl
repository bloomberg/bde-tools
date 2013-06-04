#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Symbols                         qw/EXIT_FAILURE EXIT_SUCCESS/;
use Util::Message                   qw/error fatal/;
use Production::Services;
use Production::Services::ChangeSet qw/getChangeSetStatus/;

sub usage {
  print STDERR <<EOUSAGE;
$0: Find CSIDs by status in a sweep directory

usage: 
    $0 [ opts ] <sweepdir>

Options:
    
    --status    | -s <status1> <status2> ...    Only list CSIDs with this status
EOUSAGE
}

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        verbose|v+
        status|s=s@
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1;

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

{
    my $svc = Production::Services->new;

    sub status {
        my ($csid, $status) = @_;

        return getChangeSetStatus($svc, $csid);
    }

    my %allowed;
    sub status_allowed {
        my $status = shift;
        @allowed{ @$status } = ();
    }

    sub print_if_ok {
        my ($csid, $status) = @_;

        $status ||= "<no status>";

        print "$csid $status\n" and return if not %allowed;

        print "$csid\n" if exists $allowed{$status};
    }

    sub get_csid {
        my $file = shift;
        open my $fh, $file or error "Could not open $file: $!", return;
        local $/;

        my ($csid) = <$fh> =~ /CSID:(.{18})/;
        return $csid;
    }
}



MAIN: {

    my $opts = getoptions();

    status_allowed($opts->{status}) if $opts->{status};

    my $dir = shift;

    opendir my $dirh, $dir or fatal "Could not open directory '$dir': $!";
    
    my %seen;
    while ($_ = readdir $dirh) {
        next if /^\.\.?$/ || !/\.checkin\.reason$/;
        my $csid = get_csid(File::Spec->catfile($dir, $_)) 
            or next;

        next if exists $seen{ $csid };
        $seen{$csid} = status($csid);

        print_if_ok($csid, $seen{$csid});
    }

    exit EXIT_SUCCESS;
}
__END__

=head1 NAME

bde_bystatus - Find change sets in a sweep directory by status

=head1 SYNOPSIS

    # print all change set IDs along with their status
    $ bde_bystatus /bb/data/sweep-move

    # only print those with status A
    $ bde_bystatus -s A /bb/data/sweep-move

    # only print those with status A or C
    $ bde_bystatus -s A -s C /bb/data/sweep-move

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
