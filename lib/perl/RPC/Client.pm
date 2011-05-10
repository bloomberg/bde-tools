package RPC::Client;

use Storable qw/nfreeze thaw/;
use Scalar::Util qw/blessed/;
use RPC::Symbols    qw/RPC_ENABLED/;
use RPC::Remote;
use RPC::Registry;
use RPC::Protocol qw/:all/;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = bless {} => $class;

  return $self if not RPC_ENABLED;
  return $self->init(@_);
}

sub init {
  my $self = shift;
  my %arg = @_ & 1 ? die "expected: argument hash.".$/ : @_;
  my %default = (
    channels => [ \*STDIN, \*STDOUT ],
    registry => undef,
    loaded => {},
  );

  for my $k (keys %default) {
    $self->_member($k, exists $arg{$k} ? $arg{$k} : $default{$k});
  }

  $self->send_register;

  return $self;
}

sub call {
  my ($self, $package, $method) = (shift, shift, shift);
  my $call =
  {
    context => { 'wantarray' => wantarray ? 1 : 0 },
    'package' => $package,
    method => $method,
    arg => [ @_ ],
  }; 

  # load package on demand
  $self->loadpkg($package);

  # resolve rpc-enabled objects into remote placeholders
  $self->remote($call);

  # make the remote call
  $self->_send('call', nfreeze($call));
  my $return = thaw($self->_expect('return', $self->_recv));

  # turn remote placeholders back into rpc-enabled objects
  $self->unremote($call);
  $self->unremote($return);

  return $self->propagate($return);
}

sub loadlib {
  my ($self, $path) = @_;

  $self->_send('lib', nfreeze(\$path));
  my $return = thaw($self->_expect('ok', $self->_recv));

  return $self->propagate($return);
}

sub loadpkg {
  my ($self, $pkg) = (shift, shift);

  return 1 if $self->loaded($pkg);

  my @import = @_;
  my $load = { name => $pkg, 'import' => \@import };
  
  $self->_send('load', nfreeze($load));
  my $return = thaw($self->_expect('return', $self->_recv));

  # no error on remote load, so mark package as loaded
  $self->loaded($pkg, 1);

  return $self->propagate($return);
}

sub loaded {
  my ($self, $pkg) = (shift, shift);
  return @_ ? $self->{_loaded}->{$pkg} = shift : $self->{_loaded}->{$pkg};
}

sub propagate {
  my ($self, $return) = @_;

  # propagate a remote exception
  die $return->{exception} if exists $return->{exception};

  # void context return
  return if !exists $return->{result};

  # scalar or list context return
  return wantarray ? @{$return->{result}} : $return->{result}->[-1];
}

sub remote {
  my ($self, $data) = (shift, shift);

  if (ref $data eq 'ARRAY') {
    for (@$data) {
      $_ = $self->remote($_);
    }
  }
  elsif (ref $data eq 'HASH') {
    while (my ($k, $v) = each(%$data)) {
      $v = $self->remote($v);
    }
  }
  elsif ($self->remotable($data)) {
    # rebless into transportable stub package
    delete $data->{client};
    return bless $data => 'RPC::Remote';
  }

  return $data;
}

sub unremote {
  my ($self, $data) = (shift, shift);

  if (ref $data eq 'ARRAY') {
    for (@$data) {
      $_ = $self->unremote($_);
    }
  }
  elsif (ref $data eq 'HASH') {
    while (my ($k, $v) = each(%$data)) {
      $v = $self->unremote($v);
    }
  }
  elsif (UNIVERSAL::isa($data, 'RPC::Remote')) {
    # rebless stub into local package, hold ref on client
    $data->{client} = $self;
    return bless $data => $data->{package};
  }

  return $data;
}

sub remotable {
  my ($self, $p) = @_;
  my $pkg = blessed $p;

  return 0 if !defined $pkg;
  return exists $self->registry->packages->{$pkg};
}

sub send_register {
  my $self = shift;
  $self->_send('register', nfreeze({ name => $self->registry->name }));
  $self->_expect('ok', $self->_recv);
}

sub send_unregister {
  my $self = shift;
  $self->_send('unregister', nfreeze([]));
  $self->_expect('ok', $self->_recv);
}

sub _expect {
  my ($self, $expect, $cmd, $data) = @_;
  return $data if $expect eq $cmd;
  my $message = "rpc protocol error: $expect expected.";
  $self->_send('error', nfreeze([ $message ]));
  require Carp;
  Carp::confess $message;
}

sub _send { return rpc_send(shift->channels->[1], @_); }
sub _recv { return rpc_recv(shift->channels->[0], @_); }

sub channels { return shift->_member('channels', @_); }
sub registry { return shift->_member('registry', @_); }

sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}

1;

