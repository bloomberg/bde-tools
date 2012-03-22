#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Binary::Analysis;
use Binary::Analysis::Demangle;

 use Symbols qw[
     EXIT_FAILURE EXIT_SUCCESS 
 ];

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | uor
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --instance   | -i           instance to use 
  --verbose    | -v           print details of what's happening

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
        instance|i=s
	refresh|r
        verbose|v
	dbtype=s
        unsafe
        insane
	branch
	buildtag=s
        port=i
        host=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    $opts{debug} = 1 if exists $opts{debug};
    $opts{buildtag} = 'source' unless $opts{buildtag};
    return \%opts;
}

MAIN: {
  my $db;
  my $opts = getoptions();
  $| = 1;
  my $params = {debug => 1,
		cache_mode => 'refreshonce'
	       };
  $params->{instance} = $opts->{instance} if $opts->{instance};
  $params->{dbtype} = $opts->{dbtype} if $opts->{dbtype};
  $params->{autocommit} = 1 if $opts->{insane};
  $params->{commit_piecemeal} = 1 if $opts->{unsafe};
  $params->{basebranch} = $opts->{branch} if $opts->{branch};
  $params->{buildtag} = $opts->{buildtag} if $opts->{buildtag};
  $params->{host} = $opts->{host} if $opts->{host};
  $params->{port} = $opts->{port} if $opts->{port};
  $db = Binary::Analysis->new($params);

  my ($arch, $branch) = ($db->{arch}, $db->{basebranch});
#$arch = 2;
  if ($db->{dbtype} eq 'informix') {
    $db->{dbh}->do("set isolation to committed read");
  }

  my $rows = $db->{dbh}->selectall_arrayref("select entityname, entity.entityid, library.libid, libdirectory, libname, libdate from entity, library, libinstance where enddate = 1999999999 and libinstance.architecture = ? and libinstance.branchid = ? and istemp = 0 and library.libid = libinstance.libid and entity.entityid = libinstance.entityid", undef, $arch, $branch);
  print "Found ", scalar(@$rows), " things\n";
  $db->{dbh}->rollback;
  foreach my $libinst (@$rows) {
    my ($entityname, $entityid, $libid, $path, $name, $date) = @$libinst;
    my ($filedate) = (stat($path."/".$name))[9];
    if (!$filedate) {
      print "Skipping $entityname $path/$name not found\n";
      next;
    }
    # If the date in the db is different, *and* the file date is more
    # than two minutes old, then load it. Otherwise we assume Robo's
    # messing with it so we leave it alone
    if ($date != $filedate && $filedate < (time - 120)) {
      print "$entityname was $date and is $filedate\n";
      $db->loadLibrary($libid, $entityname, $path."/".$name, $entityid);
      $db->commit();
    }
  }
}
