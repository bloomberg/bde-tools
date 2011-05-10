# vim:set ts=8 sts=2 noet:

package RPC::AutoLoad;


use RPC::Symbols    qw/RPC_ENABLED/;
use RPC::Registry;

use strict;

my $enabled = 1;
my $registry;
my $client;
my $globaldestroy;

END {
  # detect global destruction phase so we can avoid late RPC calls
  $globaldestroy = 1;
}

my $autostub = <<'EOSTUB';
package %{package};

sub import {
  goto &%{rpc_autoload_package}::rpc_import;
}

our $AUTOLOAD;

sub AUTOLOAD {
  unshift @_, $AUTOLOAD;
  goto &%{rpc_autoload_package}::rpc_autoload;
}

1;
EOSTUB

sub import {
  my $pkg = shift;
  my $callpkg = caller;
  my %arg = @_;

  {
    no strict 'refs';

    *{"${callpkg}::rpc_begin"} = \&rpc_begin;
    *{"${callpkg}::rpc_end"} = \&rpc_end;
    *{"${callpkg}::rpc_client"} = \&rpc_client;
    *{"${callpkg}::rpc_registry"} = \&rpc_registry;
  }

  return if not RPC_ENABLED;

  $enabled = delete $arg{enabled} if exists $arg{enabled};
  return unless $enabled;

  $registry = RPC::Registry->new(%arg);
  unshift @INC, \&inc;

}

# @INC hook to intercept and replace any package loads marked for rpc

sub inc {
  my ($incstuff, $pm) = @_;
  my $pkg = pm2pkg($pm);

  # continue @INC processing if package is not marked for rpc

  return undef if !exists $registry->packages->{$pkg};

  # package is marked for rpc, impersonate it

  my $selfpkg = __PACKAGE__;
  my $selfpm = pkg2pm($selfpkg);

  # establish stub package which forwards calls to us

  my $stub = $autostub;
  $stub =~ s/\%{package}/$pkg/mg; 
  $stub =~ s/\%{rpc_autoload_package}/$selfpkg/mg;
  eval $stub or die $@;

  # mark pm as included

  $INC{$pm} = $INC{$selfpm};

  # an INC sub must return a file handle to satisfy requirer:
  # use a trivial one that will eval to true. perl 5.8 and up
  # can open the contents of a scalar reference as a file handle
  # (see perldoc perlopen). one could also do this with a pipe.

  open my $pkgfh, '<', \1 or die "open error: $!";
  return $pkgfh;
}

# handle import on behalf of rpc packages

sub rpc_import {
  my $pkg = shift;
  my $callpkg = caller;

  for (@_) {
    no strict 'refs';
    my ($sigil, $sym) = /^(\W?)(.*)$/;

    # TODO for scalars, arrays, and hashes, could use Tie::StdX
    die "rpc: not exporting non-sub $sym".$/ if $sigil;

    # export sub: use same rpc dispatch mechanism as AUTOLOAD
    *{"${callpkg}::${sym}"} = sub {
      unshift @_, "${pkg}::${sym}";
      goto &rpc_autoload;
    };
  }
}

# handle AUTOLOAD on behalf of rpc packages

sub rpc_autoload {
  my $sub = shift;
  my ($pkg, $method) = $sub =~ /^(.+?)::(\w+)$/;

  # don't transmit RPC calls during global destruction. server-side
  # objects will be torn down soon enough when transport is closed.

  return if $globaldestroy;
  return if $method eq 'DESTROY';

  if (exists $registry->packages->{$pkg}) {
    die "rpc error: no rpc client.".$/ unless $client;

    # TODO support dispatching select calls to local handler package

    my $callsub = UNIVERSAL::can($client, 'call');
    unshift @_, $client, $pkg, $method;
    goto &$callsub;
  }
  else {
    die "rpc error: $pkg is not marked for rpc.".$/;
  }
}

sub rpc_begin {
  ($client, my %args) = @_;

  return if not RPC_ENABLED;

  # set INC path on remote end
  $client->loadlib($args{lib}) 
    if exists $args{lib};
}

sub rpc_end {
  $client = undef;
}

sub rpc_client {
  return $client;
}

sub rpc_registry {
  return $registry;
}

sub pm2pkg {
  my $pm = shift;
  return join('::', split m{/}, $pm =~ /^(.+)\.pm$/ ? $1 : $pm);
}

sub pkg2pm {
  my $mod = shift;
  return join('/', split m{::}, $mod).'.pm';
}

1;

