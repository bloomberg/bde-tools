# vim:set ts=8 sts=2 sw=2 noet:

package SCM::UUID2Unix;

use base qw(Util::CDBCache);
use SCM::Symbols qw/$SCM_UUID_DATA/;
use strict;

sub usedyn (*;@) {
  my $pm = shift;
  my $error = eval "eval { require $pm } ? 0 : \$@";
  die $error if $error;
  $pm->import(@_) if @_;
  return 1;
}

sub new {
  my $this = shift;
  my $class = ref($this) || $this;

  return $class->SUPER::new(
    cdbpath => "$SCM_UUID_DATA/uuid2unix/uuid2unix.cdb",
    missdir => "$SCM_UUID_DATA/uuid2unix/misses",
    tempdir => "$SCM_UUID_DATA/uuid2unix/tmp",
    cachemisses => 1,
    writemisses => 1,
  );
}

sub fetchmiss {
  my ($self, $uuid) = @_;
  return $self->uuid2unix($uuid);
}

sub uuid2unix {
  my ($self, $uuid) = @_;

  usedyn Production::Services::Util, qw/getUnixNameFromUUID/;

  my (@rv) = getUnixNameFromUUID($uuid);
  return (0, $rv[0]) if @rv == 1;
  warn $rv[1] if @rv == 2;
  return ($rv[-1], undef);
};

1;

