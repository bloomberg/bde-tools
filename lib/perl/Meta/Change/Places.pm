package Meta::Change::Places;

# functions to locate metadata places in the repository.
# initially, there may be a lot of fiddling here.

use base qw(Exporter);
use Digest::MD5 qw();

our $VERSION = '0.01';
our %EXPORT_TAGS = (
    all => [ qw(getMetaRootPath getBranchmapPath getMetaChangeBasePath
                getMetaChangePath getDirectoryHashSpace getDirectoryHashLevels
                getBranchRootPath getBranchPath getTagRootPath
                getBranchTagPath) ],
);
our @EXPORT_OK	= map @$_, values %EXPORT_TAGS;
our @EXPORT	= qw();   # nothing by default

use File::Spec qw();
use strict;

# move type aliases: move types mapped to canonical internal name
our %MOVE_TYPES;
@MOVE_TYPES{ qw/dev development prealpha regular move/ } = (qw/dev/) x 5;
@MOVE_TYPES{ qw/bf bug bugf bugfix beta/ }  		= (qw/bf/) x 5;
@MOVE_TYPES{ qw/em emov emove emergency/ }  		= (qw/em/) x 4;
@MOVE_TYPES{ qw/stpr/ }                         = (qw/stpr/) x 1;

sub getMetaRootPath { return "/meta"; }
sub getBranchmapPath { return "/meta/branchmap"; }
sub getMetaChangeBasePath { return "/meta/changes"; }

sub getMetaChangePath {
  my $csthing = shift;
  my $csid = ref($csthing) ? $csthing->getID() : $csthing;

  # path hashing to avoid a giant dir of changesets. use md5:
  #   * to avoid depending heavily on the format of the csid
  #   * to distribute uniformly across directories in long run
  #   * to send nearby csids to non-nearby dirs in short run (avoid DOS attack)

  my $md5size = 16;
  my $md5 = Digest::MD5::md5($csid);
  my @chars = getDirectoryHashSpace();
  my $n = @chars;
  my $levels = getDirectoryHashLevels();

  die "Too many levels ($levels) of directory hashing." if $levels > $md5size;
  die "Too many symbols ($n) to choose from in directory hashing." if $n > 256;

  my @hashdirs = map { $chars[$_ % $n] } (unpack("C16", $md5))[0 .. $levels-1];

  return File::Spec->catdir(getMetaChangeBasePath(), @hashdirs, $csid);
}

sub getDirectoryHashSpace {
  return ('0'..'9', 'a'..'z', 'A'..'Z');
}

sub getDirectoryHashLevels { return 2; }

sub getBranchRootPath { return "/branches"; }

sub resolveBranchName {
  my $branchalias = shift;
  my $branchmap = shift || {};
  my $branchname = $branchalias;

  $branchname = $MOVE_TYPES{$branchname} if exists($MOVE_TYPES{$branchname});
  $branchname = $branchmap->{$branchname} if exists($branchmap->{$branchname});

  return $branchname;
}

sub getBranchPath {
  my $branchalias = shift;
  my $branchmap = shift;
  my $branchname = resolveBranchName($branchalias, $branchmap);
  return File::Spec->catdir(getBranchRootPath(), $branchname);
}

sub getTagRootPath { return "/tags"; }

sub getBranchTagPath {
  my $branchalias = shift;
  my $branchmap = shift;
  my $branchname = resolveBranchName($branchalias, $branchmap);
  return File::Spec->catdir(getTagRootPath(), $branchname);
}

1;

