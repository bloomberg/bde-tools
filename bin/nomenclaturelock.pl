#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);
use Getopt::Long;

use Util::Message qw(fatal verbose debug get_verbose warning);
use Util::File::Basename qw(basename);

use BDE::Util::Nomenclature qw(isComponentHeader);

#==============================================================================

=head1 NAME

nomenclaturelock.pl -- Test a header file for acceptance via inc_checkin.

=head1 SYNOPSIS

    # check super_trash.h is a grandfathered header, use debug
    $ nomenclaturelock.pl -d super_trash.h

    # check that badhead_example.h is a bad header, verbose error message
    $ nomenclaturelock.pl -v badhead_example.h

    # check that other_destination.h is not present in explicit destination
    $ nomenclaturelock.pl other_destination.h /bbsrc/bbinc/newCincludeLocn
    $ echo $?

    # check that foobar.h is not a component header at all
    $ nomenclaturelock.pl -d foobar.h

=head1 DESCRIPTION

This short Perl script tests a header file that has been submitted
for inclusion in the general location for header files
(i.e., C</bbsrc/bbinc/Cinclude>) to see whether or not it conforms to
the name for a component header.  If it does, and if the header does
not yet exist in C</bbsrc/bbinc/Cinclude>, the header is rejected.
To get the header to pass:

=over 4

=item *

If it really is a component header, it must be checked into the
appropriate library directory.

=item *

If it is not a component header, change its name so it does not
resemble one (as described by Rules A3 and N1).

=back

By default this tool produces no output but returns a zero exit status if the
header passes, and a non-zero exit status if it fails. To see a visible
report of the status of the header either echo C<$?> or enable debug mode,
which will report the status of the header -- non-conflicting, violating, or
grandfathered.

A descriptive error message can be viewed in the case of a rejected header
with the C<--verbose> or C<-v> option.

=cut

#==============================================================================

sub usage (;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] <header> [<destination>]
  --debug         | -d                 enable debug reporting
  --help          | -h                 usage information (this text).
  --verbose       | -v                 enable verbose reporting

See 'perldoc $prog' for more information.

_USAGE_END
}

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # no arguments
     usage("Nothing to do"), exit EXIT_FAILURE if @ARGV<1
       and (not $opts{libraries} and not $opts{objects});

    return \%opts;
}

MAIN: {
    my $opts=getoptions();

    my ($header,$destination)=@ARGV;

    $destination = "/bbsrc/bbinc/Cinclude" unless defined $destination;

    fatal("$destination is not a valid directory") unless
      -d($destination)
	or (-l($destination) and -d(readlink $destination));

    $header = basename($header); #we only care about the name, not where it is

    if (isComponentHeader $header) {
	if (-f $destination.'/'.$header) {
	    if (get_verbose) {
		warning(qq[
This is a grandfathered header that resembles a component header. Please
consider renaming it, if possible, so that it does not conflict with the
naming standards for components.
]);
	    }
	    debug("Grandfathered header - OK");
	    # resembles component header but is in destination: GRANDFATHERED
	    exit EXIT_SUCCESS;
	} else {
	    # resembles a component header and is not in destination: REJECT
	    verbose(qq[
This is a new header that resembles a component header. If it *is* a component
header then it must be checked in to the library directory with 'checkin', not
into $destination with 'inc_checkin'.

If it is *not* a component header, the header filename must be changed so that
it does not conflict with the nomenclature for a component header. This means
that the header must *not* start with between 4 and 7 letters followed by an
underscore -- see {BP BDE<GO>} for more information on naming standards.
]);
	    debug("New header conflicts with nomenclature - REJECT");
	    exit EXIT_FAILURE;
	}
    }

    debug("Not a component header - OK");
    exit EXIT_SUCCESS; # does not resemble a component header: OK
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::Util::Nomenclature>

=cut

1;
