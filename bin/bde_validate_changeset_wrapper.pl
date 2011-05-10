#!/bbs/opt/bin/perl-5.8.8 -w
use strict;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Binary::Analysis;
use Binary::Analysis::Tools qw(cs_to_objset);
use File::Temp;
use Change::Set;
use Getopt::Long;
use Util::Message qw(error);
use Util::File::Basename qw(dirname basename);
use Symbols qw[
	       EXIT_FAILURE EXIT_SUCCESS 
	      ];

my $validator = "$FindBin::Bin/bde_validate_changeset.pl";

#==============================================================================

=head1 NAME

validate_changeset_wrapper - wrap symbol extraction and changeset validation

=head1 SYNOPSIS

    $ validate_changeset_wrapper.pl objsetfile

=head1 DESCRIPTION

Takes an object set file as produced by cscompile and validate it.

Note that, theoretically, we should be able to handle
cross-architecture validations by passing in the appropriate
switches. In practice we can't do this. Maybe in the next major rev.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | symbol
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --instance   | -i           instance to use 
  --verbose    | -v           print details of what's happening
  --arch=[solaris|aix]        Look things up on the given architecture

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
        verbose|v
        arch=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # Param check
    usage(), exit EXIT_FAILURE if @ARGV != 1;

    # debug mode
    $opts{debug} = 1 if exists $opts{debug};
    return \%opts;
}

MAIN: {
  my $opts = getoptions();
  my $osetfile = shift @ARGV;
  my $cs = Change::Set->load($osetfile);

  if (!defined $cs) {
    error("Unable to load object set $osetfile");
    exit EXIT_FAILURE;
  }

  my $symfile = $osetfile.'.symbols';
  my $fh;
  open $fh, ">$symfile" || do {error("error $! opening symbol file $symfile"); exit EXIT_FAILURE};

  cs_to_objset($cs, $fh);
  close($fh);

  exit EXIT_SUCCESS if $cs->getUser eq 'registry';

  my @params;
  push @params, $symfile;
  push @params, "--arch=".$opts->{arch} if $opts->{arch};

  my $cmd = join(" ", $validator, @params);
  my $output = `$cmd 2>&1`;
  my $validstat = $? >> 8;
  print $output;
  print "status is $validstat\n";

  exit $validstat;
}
