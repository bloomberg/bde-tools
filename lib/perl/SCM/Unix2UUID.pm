# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Unix2UUID;

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
    cdbpath => "$SCM_UUID_DATA/unix2uuid/unix2uuid.cdb",
    missdir => "$SCM_UUID_DATA/unix2uuid/misses",
    tempdir => "$SCM_UUID_DATA/unix2uuid/tmp",
    cachemisses => 1,
    writemisses => 1,
  );
}

sub fetchmiss {
  my ($self, $uuid) = @_;
  return $self->unix2uuid($uuid);
}

sub unix2uuid {
  my ($self, $unix) = @_;

  usedyn Production::Services::Util, qw/getUUIDFromUnixName/;

  my (@rv) = getUUIDFromUnixName($unix);
  return (0, $rv[0]) if @rv == 1;
  warn $rv[1] if @rv == 2;
  return ($rv[-1], undef);
};

1;

