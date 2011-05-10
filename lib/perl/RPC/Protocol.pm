package RPC::Protocol;

use base qw/Exporter/;

our %EXPORT_TAGS = (
  all => [ qw/rpc_send rpc_recv rpc_send_recv rpc_pack rpc_unpack rpc_proxy/ ]
);
our @EXPORT_OK = @{$EXPORT_TAGS{all}};

our $COMMAND_SIZE = 16;
our $PACK_SPEC = sprintf 'a%dNa*', $COMMAND_SIZE;

use strict;

sub rpc_send {
  my $fh = shift;

  if (@_ == 2) {
    my $cmd = shift;
    my $data = shift;
    return rpc_send_raw($fh, rpc_pack($cmd, $data));
  }
  elsif (@_ == 1) {
    my $packed = shift;
    return rpc_send_raw($fh, $packed);
  }
  else {
    die "rpc proto error: command, data expected.".$/;
  }
}

sub rpc_recv {
  my $fh = shift;

  my $cmd = rpc_recv_raw($fh, $COMMAND_SIZE);
  return (undef, undef) if !defined $cmd;
  $cmd =~ s/\0+$//;

  my $length = rpc_recv_raw($fh, 4);
  return (undef, undef) if !defined $length;
  $length = unpack('N', $length);

  my $data = rpc_recv_raw($fh, $length);
  return (undef, undef) if !defined $data;

  return wantarray ? ($cmd, $data) : rpc_pack($cmd, $data); 
}

sub rpc_proxy {
  my (@fh) = @_;

  my @request = rpc_recv($fh[0]);
  rpc_send($fh[2], @request);

  my @response = rpc_recv($fh[3]);
  rpc_send($fh[1], @response);
}

sub rpc_pack {
  my ($cmd, $data) = @_;
  return pack($PACK_SPEC, $cmd, length $data, $data)
}

sub rpc_unpack {
  my $packed = shift;
  my ($cmd, $length, $data) = unpack($PACK_SPEC, $packed);
  $cmd =~ s/\0+$//;
  return ($cmd, $data);
}

sub rpc_send_raw {
  my ($fh, $data) = @_;
  my $length = length $data;
  my $offset = 0;

  while ($offset < $length) {
    my $bytes = syswrite $fh, $data, $length, $offset;
    die "rpc send error: $!" if !defined $bytes;
    return undef if $bytes == 0;  # eof
    $offset += $bytes;
  }

  return $length;
}

sub rpc_recv_raw {
  my ($fh, $length) = @_;
  my $data;
  my $offset = 0;

  while ($offset < $length) {
    my $bytes = sysread $fh, $data, $length, $offset;
    die "rpc recv error: $!" if !defined $bytes;
    return undef if $bytes == 0;  # eof
    $offset += $bytes;
  }

  return $data;
}

1;

