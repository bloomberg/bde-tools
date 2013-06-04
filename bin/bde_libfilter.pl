#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use File::Path;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Util::File::Basename qw(basename);

use Getopt::Long;

#use BDE::Util::Nomenclature qw(isOfflineOnly);
use BDE::FileSystem;
use BDE::Util::DependencyCache qw(getCachedGroupOrIsolatedPackage);
use Change::Symbols qw(STAGE_PRODUCTION_ROOT);
use Symbols qw(EXIT_FAILURE EXIT_SUCCESS);
use Util::Message;

#==============================================================================

=head1 NAME



=head1 SYNOPSIS


=head1 DESCRIPTION



=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h |  [-d] [-v] <liblistfile>

  --debug        | -d           enable debug reporting
  --help         | -h           usage information (this text)
  --verbose      | -v           enable verbose reporting
  --where        | -w <dir>     specify explicit alternate root

Query modes:

  --offline      | -o           Filter the list to offline-only libraries
  --gtk          | -g           Filter the list to gtk only libraries
  --big          | -b           Filter the list to big-only libraries.

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
        verbose|v+
	where|root|w|r=s
	offline|o
        gtk|g
        big|b
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    #no arguments
    usage, exit EXIT_FAILURE if @ARGV<1;

    # filesystem root
    $opts{where} = STAGE_PRODUCTION_ROOT unless $opts{where};


    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);


    while (my $lib = <>) {
      chomp $lib;
      next unless $lib;

      # If we can't extract a lib, then we just punt and print it
      $lib =~ /^(lib)?(\w+)/ || do {print $lib, "\n"; next};
      my $little_lib = $2;

      next if $little_lib eq 'a_basglib';
      next if $little_lib eq 'a_bcem';
      
      my $thing = getCachedGroupOrIsolatedPackage($little_lib);
      if (defined $thing) {
	# Is it offline only and we're big only? If so, skip
	next if $opts->{big} && $thing->isOfflineOnly;

	# Is it not offline only and we're offline only?
	next if $opts->{offline} && !$thing->isOfflineOnly;

	# Is it gtk only?
	next if $opts->{gtk} && !$thing->isGTKbuild;
      }
      # Made it through our tests, so I guess we're OK
      print $lib, "\n";
    }

  }
