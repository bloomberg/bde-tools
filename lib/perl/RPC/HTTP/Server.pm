# vim:set ts=8 sts=2 sw=2 noet:

package RPC::HTTP::Server;

use POSIX qw/dup2 :sys_wait_h/;
use Errno;
use HTTP::Daemon;
use HTTP::Response;

use RPC::Constants  qw/LOG_ERROR LOG_VERBOSE LOG_DEBUG/;
use RPC::Protocol   qw/:all/;
use RPC::Registry;
use strict;

$SIG{ CHLD } = 'IGNORE';

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
    host => 'localhost',
    port => undef,
    max_incoming => 32,
    forking => 1,
    registries => {},
    registry_dir => undef,
    server_opts => {},
  );

  for my $k (keys %default) {
    $self->_member($k, exists $arg{$k} ? $arg{$k} : $default{$k});
  }

  $self->load_registries if $self->registry_dir;
    
  return $self;
}

sub load_registries {
  my $self = shift;

  $self->registries({});
  
  for (glob join '/', $self->registry_dir, '*') {
    next unless -f;
    my $registry = RPC::Registry->new(file => $_);
    $self->registries->{$registry->name} = $registry;
  }

  $self->registries->{_super_} ||= RPC::Registry->new(logging => LOG_ERROR);
}

sub run {
  my $self = shift;

  my $httpd = HTTP::Daemon->new(
    LocalAddr => $self->host,
    LocalPort => $self->port,
    Listen => $self->max_incoming,
    ReuseAddr => 1
  ) or die $@;
 
  while (1) {
    $self->hupflag(0);

    # we may have received a signal here
    # but errno might not necessarily be EINTR
    my $conn = $httpd->accept or do {
      next if $self->hupflag;
      last;
    };
    
    $self->log(LOG_VERBOSE, \&log_accept, $conn);

    if ($self->forking) {
	
      my $pid = fork;

      if (!defined $pid) {
	die "fork error: $!".$/;
      }
      elsif ($pid == 0) {
	$self->client($conn);
	exit 0;
      }
      $self->log(LOG_DEBUG, "forked new process $pid");
    }
    else {
      $self->client($conn);
    }

    $conn->close or die "close error: $!".$/;
  }

  $httpd->close or die "close error: $!".$/;
}

sub client {
  my ($self, $conn) = @_;

  # FIXME think about SIGPIPE 

  my (@c2s, @s2c);

  pipe $c2s[0], $c2s[1] or die "pipe error: $!".$/;
  pipe $s2c[0], $s2c[1] or die "pipe error: $!".$/;

  # fork off the child server to handle the connection

  my $pid = fork;

  if (not defined $pid) {
    die "fork error: $!".$/;
  }
  elsif ($pid > 0) {
    # parent
    $self->log(LOG_DEBUG, "parent process is $$");

    close $c2s[1] or die "close error: $!".$/;
    close $s2c[0] or die "close error: $!".$/;

    # forward http POST request bodies to the rpc server

    while (my $req = $conn->get_request) {
      if ($req->method eq 'POST') {
        rpc_send($s2c[1], $req->content);
        my $packed = rpc_recv($c2s[0]);
        $conn->send_response(HTTP::Response->new(200, 'OK', [], $packed));
      }
      else {
        $conn->send_error;
      }
    }
  
    # FIXME send this with timeout
    rpc_send($s2c[1], 'unregister', '0');
  }
  else {
    # child
    # TODO close _all_ unneeded fds here, not just dark sides of the pipes

    $self->log(LOG_DEBUG, "child process is $$");

    close $c2s[0] or die "close error: $!".$/;
    close $s2c[1] or die "close error: $!".$/;

    # hardwire child server to the pipe, but intentionally continue
    # to capture child's stderr.

    dup2(fileno $s2c[0], 0) or die "dup2 error: $!".$/;
    dup2(fileno $c2s[1], 1) or die "dup2 error: $!".$/;
  
    require RPC::Server;

    my $server = RPC::Server->new(
      registries => $self->registries,
      %{ $self->server_opts }      
    );

    $server->run;

    exit 0;
  }
}

sub registry {
  my ($self, $name) = @_;
  my $registries = $self->registries;
  return exists $registries->{$name} ? $registries->{$name} : undef;
}

sub log {
  my ($self, $level, $thing, @rem) = @_;

  return if $level > $self->logging;

  if (not ref $thing) {
    print STDERR "_super_: $thing\n";
  } else {
    print STDERR "_super_: ", $thing->(@rem), "\n";
  }
}

sub logging { return shift->registry('_super_')->logging; }

sub registries { return shift->_member('registries', @_); }
sub host { return shift->_member('host', @_); }
sub port { return shift->_member('port', @_); }
sub max_incoming { return shift->_member('max_incoming', @_); }
sub forking { return shift->_member('forking', @_); }
sub registry_dir { return shift->_member('registry_dir', @_); }
sub server_opts { return shift->_member('server_opts', @_); }
sub hupflag { return shift->_member('hupflag', @_); }
 
sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}

# some logging output generators
sub log_accept {
  my $conn = shift;
  my $peer = $conn->peerhost . ":" . $conn->peerport;

  return "accepted connection from $peer";
}

1;

