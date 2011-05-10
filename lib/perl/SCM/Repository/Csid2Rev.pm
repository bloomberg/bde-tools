# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Repository::Csid2Rev;

use base qw(Util::CDBCache);
use Util::Message qw/warning fatal/;
use SCM::Symbols qw/$SCM_CSID2REV_DATA/;
use Meta::Change::Places qw(:all);
use SVN::Repos;
use SVN::Core;
use SVN::Fs;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;

  return $class->SUPER::new(
    cdbpath => "$SCM_CSID2REV_DATA/csid2rev.cdb",
    missdir => "$SCM_CSID2REV_DATA/misses",
    tempdir => "$SCM_CSID2REV_DATA/tmp",
    cachemisses => 1,
    writemisses => 1,
    @_
  );
}

sub init {
  my $self = shift;
  my %arg = @_ & 1 ? fatal("Expected: parameter hash.") : @_;

  fatal("Parameter required: repo.$/")
    unless my $repo = delete $arg{repo};

  $self->SUPER::init(%arg);
  $self->_repo($repo);

  return $self;
}

sub fetchmiss {
  my ($self, $csid) = @_;
  return $self->_csid2rev($csid);
}

sub _csid2rev {
  my ($self, $csid) = @_;
  my $pool = SVN::Pool->new_default(undef);
  my $path = getMetaChangePath($csid);
  my $fs = $self->_repo->fs;
  my $revroot = $fs->revision_root($fs->youngest_rev);

  return undef if not $revroot->check_path($path);

  my $history = $revroot->node_history($path);
  my $birthrev = undef;

  while ($history = $history->prev($history, 0)) {
    my ($histpath, $histrev) = $history->location();
    last if $histpath ne $path; # bail if we cross a copy
    $birthrev = $histrev;
  }

  return $birthrev;
}

sub _repo { return shift->_member('repo', @_); }

1;

