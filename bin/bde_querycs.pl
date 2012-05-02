#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Util::File::Basename qw(basename);

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
);
use Change::Symbols qw(DBPATH DBLOCKFILE);
use Change::DB;
use Util::Message qw(fatal warning error alert);

use Production::Services;
use Production::Services::ChangeSet qw();
use Production::Symbols qw(URL_PREFIX SCM_PRLSPD_ENABLED);
#==============================================================================

=head1 NAME

bde_querycs.pl - List contents of a previously submitted change set

=head1 SYNOPSIS

    $ bde_querycs.pl 4267DA960320E94D

=head1 DESCRIPTION

This tool extracts change set information from the change set database and
presents it to the user in either human- or machine-parsable formats. The
machine-parsable format is suitable for editing as part of a new change set.
(see the C<--from> of L<bde_createcs.pl>).

=head1 EXIT STATUS

A zero exit status is returned if all specfieid change sets were found, or
non-zero if any change set was not located in the database.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] <csid> [<csid>...]
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting

Display options:

  --pretty      | -P              list changes in human-parseable output
                                  (default if run interactively)
  --machine     | -M              list changes in machine-parseable output
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
        deps
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
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{list};

    # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	exit EXIT_FAILURE;
    }
    unless ($opts{pretty} or $opts{machine}) {
	if (-t STDIN) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $pretty=$opts->{pretty};
 

    my @args = map { uc($_) } @ARGV;
    my @changesets;

    my $svc=new Production::Services;

    for (@args) {
      my $changeset = Production::Services::ChangeSet::getChangeSetDbRecord(
		  $svc, $_);
      if ($changeset) {
        push(@changesets,$changeset);
      }
    }

    map { print $_->listChanges($pretty) } @changesets;

    exit 0 if (scalar @changesets == scalar @args); # success

    my %csids;
    foreach (@args) {
	$csids{$_} = undef;
    }
    foreach (@changesets) {
	delete $csids{$_};
    }
    warning "Change set $_ not found in database - try csfind?"
	foreach (keys %csids); 

    exit 1;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_rollbackcs.pl>, L<bde_findcs.pl>

=cut
