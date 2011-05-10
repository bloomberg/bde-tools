# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Repository::Rev2Csid;

use base qw(Util::CDBCache);
use Util::Message qw/warning fatal/;
use SCM::Symbols qw/$SCM_REV2CSID_DATA/;
use Meta::Change::Places qw(:all);
use SVN::Repos;
use SVN::Core;
use SVN::Fs;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;

  return $class->SUPER::new(
    cdbpath => "$SCM_REV2CSID_DATA/rev2csid.cdb",
    missdir => "$SCM_REV2CSID_DATA/misses",
    tempdir => "$SCM_REV2CSID_DATA/tmp",
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
  my ($self, $rev) = @_;
  return $self->_rev2csid($rev);
}

sub _rev2csid {
  my ($self, $rev) = @_;
  my $pool = SVN::Pool->new_default(undef);
  my $revroot = $self->_repo->fs->revision_root($rev);
  my $changeplace = getMetaChangeBasePath;
  my $changes = $revroot->paths_changed;
  my $metapath = (map { m{^\Q$changeplace\E}?$_:() } keys %$changes)[0];

  unless (defined $metapath) {
    warning("No changeset metafile found for revision $rev.");
    return undef;
  }
  
  my $csid = (split m{/}, $metapath)[-1]; # csid is basename

  # it is important that changeset metafiles, once added, are never
  # touched again--otherwise we lose 1-1 mapping between csids and revs

  if ($changes->{$metapath}->change_kind != $SVN::Fs::path_change_add) {
    # FIXME this may occur as a result of multiple BREG checkins
    warning("Changeset metafile for $csid modified by later commit.");
  }

  return $csid;
}

sub _repo { return shift->_member('repo', @_); }

1;

