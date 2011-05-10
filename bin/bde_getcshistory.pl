#!/bbs/opt/bin/perl -w
use strict;

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

#==============================================================================

=head1 NAME

cshistory - Return the transaction history for the specified change set

=head1 SYNOPSIS

    # find change sets involving a specified user
    $ cshistory 42E151DE001DA8E31D

=head1 DESCRIPTION

This tool returns the transation history of the specified changeset.

=head1 NOTES

In this implementation, the output is machine-parsable only. The
C<--pretty>, C<--machine>, and C<--expand> options are recognized but not
currently used.

=head1 EXIT STATUS

A zero exit status is returned if any history was found. A non-zero exit
status is returned if no records pertaining to the specified change set ID
were found.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = "cshistory"; #basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-r] <match text>
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting

Display options (NOT CURRENTLY IMPLEMENTED):

  --pretty      | -P              list changes in human-parseable output
                                  (default if run interactively)
  --machine     | -M              list changes in machine-parseable output
                                  (default if run non-interactively)
  --expand      | -x              list full changeset history details
                                  (default: list only brief details)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        expand|x
        help|h
        machine|M
        pretty|P
        regexp|r
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

    my $changedb=new Change::DB('<'.DBPATH);
    error("Unable to access ${\DBPATH}: $!"), return EXIT_FAILURE
      unless defined $changedb;

    my $result=0;

    if (my @history=$changedb->getHistory(uc $ARGV[0])) {
	#if ($opts->{pretty}) {
	    #...
	#} else {
	    #if ($opts->{expand}) {
	        #...
            #} else {
		print map { $_,"\n" } @history; # terse machine-parsable output
	    #}
	#}
    } else {
	$result=1;
	print "$ARGV[0] not found\n";
    }

    exit $result;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_rollbackcs.pl>, L<bde_querycs.pl>

=cut
