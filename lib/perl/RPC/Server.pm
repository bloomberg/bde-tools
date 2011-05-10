# vim:set ts=8 sts=2 sw=2 noet:

package RPC::Server;

use Storable	    qw/nfreeze thaw/;
use Scalar::Util    qw/blessed refaddr/;

use RPC::Constants  qw/LOG_FATAL LOG_ERROR LOG_WARNING LOG_VERBOSE LOG_DEBUG/;
use RPC::Remote;
use RPC::Registry;
use RPC::Protocol   qw/:all/;
use RPC::Util	    qw/format_args/;
use warnings;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = bless {} => $class;
  return $self->init(@_);
}

sub init {
  my $self = shift;
  my %arg = @_ & 1 ? die "expected: argument hash.".$/ : @_;
  my %default =
  (
    remotes	=> {},
    channels	=> [ \*STDIN, \*STDOUT ],
    registry	=> undef,
    registries	=> undef,
    inc_prefix  => undef,
    inc_match   => undef,
    inc_suffix  => undef,
  );

  for my $k (keys %default) {
    $self->_member($k, exists $arg{$k} ? $arg{$k} : $default{$k});
  }

  return $self;
}

sub run {
  my $self = shift;

  $self->log(LOG_VERBOSE, \&log_func, $self, @_);

  $self->recv_register;

  while (my ($cmd, $data) = $self->_recv) {
    last if !defined $cmd;

    if ($cmd eq 'lib') {
      my $return = $self->loadlib(thaw($data));
      $self->_send('ok', nfreeze($return));
    } elsif ($cmd eq 'call') {
      my $return = $self->call(thaw($data));
      $self->_send('return', nfreeze($return));
    }
    elsif ($cmd eq 'load') {
      my $return = $self->loadpkg(thaw($data));
      $self->_send('return', nfreeze($return));
    }
    elsif ($cmd eq 'unregister') {
      last;
    }
    else {
      $self->send_error(qq{rpc proto error: unknown command "$cmd"});
    }
  }
}

sub call {
  my ($self, $call) = (shift, shift);

  $self->log(LOG_VERBOSE, \&log_func, $self, $call, @_);

  my ($context, $pkg, $method, $arg) =
    @{$call}{qw/context package method arg/};

  return { exception => "rpc error: invalid package $pkg." } if
    !exists $self->registry->packages->{$pkg};
 
  return { exception => "rpc error: invalid method $method." } if
    $method =~ /\W/;
 
  my @rv;
  local $@;

  eval {
    if ($method eq 'DESTROY') {
      $self->destroy(@$arg);
      @rv = ();
    }
    else {
      # incoming: resolve all remote object placeholders 
      $self->unremote($arg);

      my $sub = UNIVERSAL::can($pkg, $method);

      $self->log(LOG_VERBOSE, "${pkg}::$method(" . format_args(@$arg) . ")");
  
      @rv = $sub->(@$arg) if $context->{wantarray};
      @rv = scalar $sub->(@$arg) if !$context->{wantarray};

      # outgoing: replace all remotable objects with placeholders
      $self->remote(\@rv);
    }
  };

  return { exception => $@ } if $@;
  return { result => \@rv };
}

sub loadlib {
  my ($self, $path) = @_;

  $self->log(LOG_VERBOSE, \&log_func, $self, $path);

  return {} if not defined $$path or $$path eq '';

  my $pat = $self->inc_match || qr/^\w+$/;

  return { exception => 'rpc error: requested inc path disallowed.' }
    if $$path !~ /$pat/;

  my $incpath = join '/' => grep defined,
    $self->inc_prefix, $$path, $self->inc_suffix;

  unshift @INC, $incpath;

  return {};
}

sub loadpkg {
  my ($self, $load) = (shift, shift);
  my ($pkg, $import) = @{$load}{qw/name import/};

  $self->log(LOG_VERBOSE, \&log_func, $self, $load);

  return { exception => "rpc error: invalid package $pkg." } if
    !exists $self->registry->packages->{$pkg};
    
  local $@;

  my $error = eval "eval { require $pkg } ? 0 : \$@";
  return { exception => $error } if $error;

  my $rv = eval { $pkg->import(@$import) if $import && @$import; };
  return { exception => $@ } if $@;
  return { result => [ $rv ] };
}

sub destroy {
  my ($self, $obj) = (shift, shift);

  $self->log(LOG_VERBOSE, \&log_func, $self, $obj);

  die "rpc error: cannot destroy non-remote object.".$/ unless
    UNIVERSAL::isa($obj, 'RPC::Remote');

  my $remotes = $self->_remotes;
  my ($pkg, $id) = ($obj->package, $obj->id);
  my $check = $self->unremote($obj);

  # might not immediately DESTROY: more refs can exist
  delete $remotes->{$id};
}

sub remote {
  my ($self, $data) = (shift, shift);

  $self->log(LOG_VERBOSE, \&log_func, $self, $data, @_);

  my $remotes = $self->_remotes;

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
    my $ref = \$data;
    my ($pkg, $id) = (ref $data, refaddr $ref);
    $remotes->{$id} = $ref;
    return RPC::Remote->new($pkg, $id);
  }

  return $data;
}

sub unremote {
  my ($self, $data) = (shift, shift);

  $self->log(LOG_VERBOSE, \&log_func, $self, $data);

  my $remotes = $self->_remotes;

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
    my ($pkg, $id) = ($data->package, $data->id);
    die "rpc error: no remote object $id.".$/ unless exists $remotes->{$id};
    my $ref = $remotes->{$id};
    die "rpc error: no remote object $id from package $pkg.".$/ if
      $pkg ne ref $$ref;
    return $$ref;
  }

  return $data;
}

sub remotable {
  my ($self, $p) = @_;

  $self->log(LOG_VERBOSE, \&log_func, $self, $p);
  my $pkg = blessed $p;

  return 0 if !defined $pkg;
  return exists $self->registry->packages->{$pkg};
}

sub recv_register {
  my $self = shift;

  $self->log(LOG_VERBOSE, \&log_func, $self, @_);

  while (my ($cmd, $data) = $self->_recv) {
    if ($cmd eq 'register') {
      my $reg = thaw($data);

      if (exists $self->registries->{$reg->{name}}) {
        $self->registry($self->registries->{$reg->{name}});
        $self->send_ok;
        last;
      }
      else {
        $self->send_error("rpc proto error: invalid registry $data");
      }
    }
    else {
      $self->send_error('rpc proto error: expected "register"');
    }
  }
}

sub send_ok {
  my $self = shift;

  $self->log(LOG_VERBOSE, \&log_func, $self);

  $self->_send('ok', nfreeze({}));
}

sub send_error {
  my ($self, $msg) = @_;

  $self->log(LOG_VERBOSE, \&log_func, @_);

  $self->_send('error', nfreeze({ message => $msg }));
}

sub log {
  my ($self, $level, $thing, @rem) = @_;

  return if $level > $self->logging;

  if (not ref $thing) {
    print STDERR "$$: $thing\n";
  } else {
    print STDERR "$$: ", $thing->(@rem), "\n";
  }
}

sub _send { 
  my $self = shift;
  $self->log(LOG_DEBUG, \&log_func, $self, @_);
  return rpc_send($self->channels->[1], @_); 
}

sub _recv { 
  my ($self) = shift;
  $self->log(LOG_DEBUG, \&log_func, $self, @_);
  return rpc_recv($self->channels->[0], @_); 
}

sub logging { 
  my $self = shift;
  return $self->registry ? $self->registry->logging
			 : LOG_DEBUG;
}

sub channels { return shift->_member('channels', @_); }
sub registry { return shift->_member('registry', @_); }
sub registries { return shift->_member('registries', @_); }
sub inc_match { return shift->_member('inc_match', @_); }
sub inc_prefix { return shift->_member('inc_prefix', @_); }
sub inc_suffix { return shift->_member('inc_suffix', @_); }
sub _remotes { return shift->_member('remotes', @_); }

sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}

# some logging output generators
sub log_func {
  my @args = @_;
  my $sub = (caller(2))[3];

  $sub = (caller(3))[3] if $sub eq '(eval)';

  my $args = format_args(@_);
  return "$sub($args)";
}

1;

