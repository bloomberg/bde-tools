#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Build::Uplid;
use Build::Option::Finder;
use Build::Option::Factory;

use Util::Message qw(error debug set_debug set_verbose);
use Util::File::Basename qw(basename);

use Symbols qw(DEFAULT_FILESYSTEM_ROOT EXIT_SUCCESS EXIT_FAILURE EXIT_USAGE);

#------------------------------------------------------------------------------

use constant PROGRAM          => basename $0;

#------------------------------------------------------------------------------

=head1 NAME

bde_uplid.pl - Return the platform ID (UPLID) for the platform of invocation

=head1 SYNOPSIS

    Return UPLID         : uplid.pl

    With other compiler  : uplid.pl -c gcc
          ...and version : uplid.pl -c gcc_3.4.2

    Match partial UPLID  : uplid -m unix-SunOS && echo 'matched'

    Match wildcard UPLID : uplid -m unix-*-*-*-cc && echo 'matched'

=head1 DESCRIPTION

Get or match the Uniform PLatform ID (UPLID) for the invoking host.

This script handles platform definitions in the form of an UPLID, a string
uniquely a platform. An UPLID consists of 5 components separated by '-' signs.
These components are:

  - O/S kin           - operating system 'flavor' (e.g. 'unix', 'windows')
  - O/S brand         - O/S name, as vendor defines it (e.g. 'SunOS', 'AIX')
  - Architecture      - O/S-specific hardware name (e.g. 'powerpc', 'i686')
  - O/S version       - O/S-specific version string (e.g. '5.1')
  - Compiler          - requested compiler type (e.g. 'def', 'gcc')
  - Compiler Version  - the version of the compiler

The first four of these are determined from the invoking host. The last two
may be passed in with the --compiler option or derived from the
BDE_SYSTEM_COMPILER environment variable. If not specified, they are instead
calculated by deriving their values from the compiler and compiler version
settings C<default.opts>.

Two modes of operation are available:

=over 4

=item query (default)

with no arguments, the UPLID for the invoking host is
returned. The compiler defaults to 'def' unless specified with -c.

=item match

if --match is specified, the UPLID for the invoking host is
compared to the supplied partial and/or wildcarded pattern.
No text is output: 0 is returned on success, non-zero otherwise.

=back

=head1 NOTES

This tools was originally invoked as part of the build process but has now been
replaced by the L<BDE::Build::Uplid> module, of which it is now a client.

=head1 SEE ALSO

L<BDE::Build::Uplid>

=cut

#--------------------------------------------------------------------------------

sub usage () {
    my $prog=PROGRAM;

    print<<_USAGE_END;
Usage: $prog -h | [-c <comp>] [-m <text>] [-d]

  --compiler | -c  <comp>  compiler name (default: 'def')
  --debug    | -d          enable debug reporting
  --help     | -h          usage information (this text)
  --match    | -m  <text>  match mode: match against wildcard pattern
  --verbose  | -v          enable verbose reporting
  --where    | -w          specify explicit alternate build root (for compiler
                           and compiler version determination)

See 'pod2text $prog' for additional information.

_USAGE_END
}

#------------------------------------------------------------------------------

# fatal error with controlled exit status
sub fatal ($$) {
    my($status,$str) = @_;

    error($str);
    usage();
    exit $status;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts={};

    Getopt::Long::Configure("bundling");
    unless (GetOptions($opts,qw[
	compiler|c=s
	debug|d+
	help|h
	match|m=s
        unexpanded|u
        verbose|v+
	where|root|w|r=s
    ])) {
	usage();
	exit EXIT_USAGE;
    }

    usage(),exit(EXIT_SUCCESS) if $opts->{help};

    # filesystem root
    $opts->{where} = DEFAULT_FILESYSTEM_ROOT unless $opts->{where};

    # accept no trailing arguments
    fatal(EXIT_USAGE,"Unknown arguments: @ARGV") if @ARGV;

    # switch on debug if requested
    set_debug($opts->{debug}) if $opts->{debug};
    set_verbose($opts->{verbose}) if $opts->{verbose};

    my $uplid=$opts->{unexpanded} ?
      unexpanded BDE::Build::Uplid() : new BDE::Build::Uplid({
          compiler=>$opts->{compiler}, where=>$opts->{where}
      });

    my $status;
    if ($opts->{match}) {
	my $match = $opts->{match};
	$match =~ s/^\W(.*)\W$/$1/;  #strip off quotes
	$status=($uplid->matchWild($match))?EXIT_SUCCESS:EXIT_FAILURE;
    } else {
	# just display the UPLID
	print $uplid;
	$status=EXIT_SUCCESS;
    }

    exit $status;
}

#------------------------------------------------------------------------------

