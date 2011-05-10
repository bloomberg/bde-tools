package RPC::HTTP::Client;

use base qw/RPC::Client/;
use Net::HTTP;
use RPC::Protocol qw/:all/;
use strict;

sub init {
  my $self = shift;
  my %arg = @_ & 1 ? die "expected: argument hash.".$/ : @_;

  my %default =
  (
    host => undef,
    port => 80,
    uri => undef,
    http => undef
  );

  for my $k (keys %default) {
    $self->_member($k, exists $arg{$k} ? $arg{$k} : $default{$k});
  }

  my $http = Net::HTTP->new
  (
    PeerAddr => $self->host,
    PeerPort => $self->port,
    HTTPVersion => '1.1',
    KeepAlive => 1
  ) or die $@;

  $self->_http($http);
  return $self->SUPER::init(@_);
}

sub _send {
  my ($self, $cmd, $data) = @_;
  my $packed = rpc_pack($cmd, $data);
  return $self->_http->write_request(POST => $self->uri, $packed);
}

sub _recv {
  my $self = shift;
  my $http = $self->_http;
  my ($status, $reason, %headers) = $http->read_response_headers or
    die "http error: invalid response headers".$/;

  my $packed = '';

  while (1) {
    my $buffer;
    my $bytes = $http->read_entity_body($buffer, 1024);
    die "http read error: $!".$/ if !defined $bytes;
    last if $bytes == 0;
    $packed .= $buffer;
  }

  return rpc_unpack($packed);
}

sub host { return shift->_member('host', @_); }
sub port { return shift->_member('port', @_); }
sub uri { return shift->_member('uri', @_); }
sub _http { return shift->_member('http', @_); }

1;

