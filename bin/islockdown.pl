#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:$FindBin::Bin:/usr/local/bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Getopt::Long;

use Util::File::Basename qw(basename);
use Util::Message qw(error debug);
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);

use Production::Services;
use Production::Services::Move qw(getLockdownStatus);

#==============================================================================

=head1 NAME

islockdown.pl - Read lockdown status

=head1 SYNOPSIS

  $ islockdown.pl

=head1 DESCRIPTION

C<islockdown.pl> makes a production service query to determine whether or not
a lockdown is in effect.

In pretty mode, the default when run interactively, or enabled with C<--pretty>
or C<-P>, a message is printed to standard output for human consumption. In
machine mode, the default when run non-interactively, or enabled with
C<--machine> or C<-M>, no message is printed.

On success, a zero exit status is returned if lockdown is not in effect,
or a positive exit status if it is. If an error occurs, an error is issued
to standard out and a negative exit status is returned.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-M|-P]
  --debug       | -d            enable debug reporting
  --help        | -h            usage information (this text)
  --machine     | -M            list changes in machine-parseable output
                                (default if run non-interactively)
  --pretty      | -P            list changes in human-parseable output
                                (default if run interactively)
  --verbose     | -v            enable verbose reporting

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        machine|M
        pretty|P
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

   # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	exit EXIT_FAILURE;
    }
    unless ($opts{pretty} or $opts{machine}) {
	if (-t STDOUT) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#==============================================================================

MAIN: {
    my $opts=getoptions();

    my $svc=new Production::Services();
    my $lockdown=getLockdownStatus($svc);

    unless (defined $lockdown) {
        error "Error occured reading lockdown status";
	error $svc->getError() if $svc->getError();
        exit -1;
    }

    if ($opts->{pretty}) {
        print "Lockdown is ".($lockdown?$lockdown:"not in effect")."\n";
    }

    exit ($lockdown ? 1 : 0);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<isbetaday.pl>, L<cscheckin>

=cut
