#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Util::File::Basename qw(dirname basename);
use Binary::Analysis;
use Binary::Analysis::Tools qw(load_objset);
use Binary::Analysis::Demangle;
 use Symbols qw[
     EXIT_FAILURE EXIT_SUCCESS
 ];


sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | changefile
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --instance   | -i           instance to use 
  --verbose    | -v           print details of what's happening

See 'perldoc $prog' for more information.

_USAGE_END
}

=head1 NAME

inject_changeset - insert a changeset into the symbol database

=head1 SYNOPSIS

  $ inject_changeset serialized_cs

=head1 DESCRIPTION

This tool takes one or more serialized changeset files and inserts
them into the symbol database. The program is architecture-agnostic --
it's perfectly valid to inject AIX symbols when running on Solaris or
vice versa.

Injecting symbols into a library creates a new version of that
library. Only one copy of a library will be created per changeset.

=cut

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        instance|i=s
	refresh|r
        verbose|v
        dbtype=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # No file?
    usage(), exit EXIT_FAILURE if !@ARGV;

    # debug mode
    $opts{debug} = 1 if exists $opts{debug};
    $opts{dbtype} = 'informix' unless $opts{dbtype};
    if ($opts{dbtype} ne 'informix' && !defined $opts{instance}) {
      $opts{instance} = 'validation';
    }

    return \%opts;
}

MAIN: {
  my $db;
  my $opts = getoptions();
  $| = 1;
  my $params = {
		cache_mode => 'refreshonce',
	       };
  $params->{instance} = $opts->{instance} if $opts->{instance};
  $params->{dbtype} = $opts->{dbtype} if $opts->{dbtype};
  $params->{debug} = $opts->{debug} if $opts->{debug};
#  exit;
  $db = Binary::Analysis->new($params);

  # Load in the changeset files
  my (%instids);
  foreach my $file (@ARGV) {
    my $fh;
    open $fh, "<$file" or do {warn "can't open $file, $!"; next};
    my $objset = load_objset($fh);
    $db->loadSerializedChangeSet($objset);
  }
  if ($db->{need_symfix}) {
    $db->_flush_symbols;
  }
  $db->commit();
#  sleep 100;
#  $db->{dbh}->rollback;
}
