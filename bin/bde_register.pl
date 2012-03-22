#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Util::NameRegistry ();
use BDE::Util::Nomenclature qw(isGroup isIsolatedPackage);
use Util::Message qw(fatal);
use Symbols qw(EXIT_FAILURE EXIT_SUCCESS);

#==============================================================================

=head1 NAME

bde_register.pl - check if a unit-of-release name is properly registered or available

=head1 SYNOPSIS

    $ bde_register.pl nom         validate metadata for existing name 'nom'
    $ bde_register.pl -n nom      only check that name is registered
    $ bde_register.pl -r nom      check name available, validate metadata
    $ bde_register.pl -rn nom     only check if name is available

=head1 DESCRIPTION

C<bde_register.pl> can be used to check if a name is available to be
registered for a new unit-of-release (package group or isoloated package),
or can be used to validate that required metadata has been defined for an
existing unit-of-release.

Exit value is zero if successful; non-zero for failure.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "\n!! @_\n\n" if @_;

    require File::Basename;
    my $prog = File::Basename::basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-n] [-r] [-d[d]] [-v[v]] <group|isolated-package>
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --name_only  | -n           only check if name is registered; no other checks
  --register   | -r           check if new name is available to be registered
  --verbose    | -v           enable verbose reporting

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
        name_only|n
	register|r
        verbose|v+
    ])) {
        usage("Arfle Barfle Gloop?");
        exit EXIT_FAILURE;
    }

    # no arguments
    usage("Nothing to do"), exit EXIT_FAILURE if @ARGV < 1;

    # too many arguments
    usage("Specify only one group or package argument"), exit EXIT_FAILURE
      if @ARGV > 1;

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts = getoptions();
    my $name = shift @ARGV;

    isGroup($name) || isIsolatedPackage($name)
      || fatal("Not a valid unit of release: $name");

    BDE::Util::NameRegistry::isRegisteredName($name)
      ? $opts->{register} && fatal("$name is already registered")
      : $opts->{register} || fatal("$name is not a registered unit-of-release");

    $opts->{name_only}
      || BDE::Util::NameRegistry::prequalifyName($name,$opts->{register})
      || exit(EXIT_FAILURE);

    if ($opts->{register}) {
	print "\nName $name is available.\n\n";
	print "Please file a DRQS IW to group 101 (BDE Group) ",
	      "requesting the name.\n\n" if (!$opts->{name_only});
    }

    exit(EXIT_SUCCESS);
}

#==============================================================================

=head1 AUTHOR

Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<BDE::Util::NameRegistry>

=cut
