#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:${FindBin::Bin}:/usr/local/bin";
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
use Production::Services::Move qw(isValidTester);

#==============================================================================

=head1 NAME

istester.pl - Determine if users are valid testers

=head1 SYNOPSIS

    istester.pl login1 login2 uuid1 uuid2 ...

=head1 DESCRIPTION

C<istester.pl> makes a production service query to determine whether or not
the supplied unix login names and/or UUIDs are valid testers.

In pretty mode, the default when run interactively, or enabled with C<--pretty>
or C<-P>, a message is printed to standard output for human consumption. In
machine mode, the default when run non-interactively, or enabled with
C<--machine> or C<-M>, no message is printed if all users are valid and
a space-separated list of invalid IDs is printed to standard output if any
users are invalid.

On success, a zero exit status is returned if all the supplied user IDs are
valid testees. If any of the users are not valid, a positive exit status
is returned. If an error occurs, an error is issued to standard out and a
negative exit status is returned.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-l <libs>] <tasks>
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting
  --pretty      | -P            list changes in human-parseable output
                                (default if run interactively)
  --machine     | -M            list changes in machine-parseable output
                                (default if run non-interactively)

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

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{libs};

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

    my @users=@ARGV;

    my $svc=new Production::Services();

    my @invalid;
    foreach my $user (@users) {
        my $istester=isValidTester($svc,$user);

        unless (defined $istester) {
            error "Error occured reading tester status for $user";
	    error($svc->getError) if $svc->getError();
            exit -1;
        }

        if ($opts->{pretty}) {
            print $user." is ".($istester ? "" : "NOT ")."a valid tester\n";
        } else {
            push @invalid,$user;
        }
    }

    print join(" ",@invalid),"\n" unless $opts->{pretty};

    exit (@invalid ? scalar(@invalid) : 0);
}
