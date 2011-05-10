# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Repository::CommitInfo;

use base qw(Util::CDBCache);
use Util::Message qw/warning fatal/;
use SCM::Symbols qw/$SCM_COMMITINFO_DATA/;
use Storable qw/freeze thaw/;
use SVN::Repos;
use SVN::Core;
use SVN::Fs;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;

  return $class->SUPER::new(
    cdbpath => "$SCM_COMMITINFO_DATA/commitinfo.cdb",
    missdir => "$SCM_COMMITINFO_DATA/misses",
    tempdir => "$SCM_COMMITINFO_DATA/tmp",
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
  my ($self, $branch) = @_;
  return $self->_commitinfo($branch);
}

sub thawvalue {
  my ($self, $value) = @_;
  return thaw($value);
}

sub _commitinfo {
  my ($self, $rev) = @_;
  my $pool = SVN::Pool->new_default(undef);
  my $props = $self->_repo->fs->revision_proplist($rev);
  my %info;

  while (my ($k,$v) = each %$props) {
    $k =~ s/^svn:/scm:/; # continue now-ridiculous tradition of hiding svn
    $info{$k} = $v;
  }
  
  return freeze(\%info);
}

sub _repo { return shift->_member('repo', @_); }

1;

