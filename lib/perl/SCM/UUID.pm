# vim:set ts=8 sts=2 sw=2 noet:

package SCM::UUID;

use SCM::Unix2UUID;
use SCM::UUID2Unix;
use SCM::Symbols qw/$SCM_UUID_REBUILD_CACHES/;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = bless {} => $class;
  return $self->init(@_);
}

sub init {
  my $self = shift;

  $self->_unix2uuid(SCM::Unix2UUID->new);
  $self->_uuid2unix(SCM::UUID2Unix->new);

  if ($SCM_UUID_REBUILD_CACHES) {
    $self->_unix2uuid->rebuild if $self->_unix2uuid->loadmisses;
    $self->_uuid2unix->rebuild if $self->_uuid2unix->loadmisses;
  }

  return $self;
}

sub unix2uuid {
  my ($self, $unix) = @_;
  return $self->_unix2uuid->get($unix);
}

sub uuid2unix {
  my ($self, $uuid) = @_;
  return $self->_uuid2unix->get($uuid);
}

sub _unix2uuid { return shift->_member('unix2uuid', @_); }
sub _uuid2unix { return shift->_member('uuid2unix', @_); }

sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}
1;
