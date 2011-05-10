# vim:set ts=8 sts=2 noet:

package RPC::Registry;

use strict;
use warnings;

use Data::Dumper;

use RPC::Constants qw/LOG_ERROR/;

our $VERSION = '0.01';

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = bless {} => $class;
  return $self->init(@_);
}

sub init {
  my $self = shift;
  my %arg = @_ & 1 ? die "expected: argument hash.".$/ : @_;
  my %default = ( 
	  version   => $VERSION, 
	  name	    => undef, 
	  packages  => {},
	  incs_ok   => undef,
	  logging   => LOG_ERROR,
  );

  delete @arg{qw/incs_ok packages/}, delete @default{qw/incs_ok packages/}
    if defined $arg{name} && $arg{name} eq '_super_';

  for my $k (keys %default) {
    $self->_member($k, exists $arg{$k} ? $arg{$k} : $default{$k});
  }

  $self->load_file($arg{file}) if exists $arg{file};
    
  return $self;
}

sub load {
  my ($self, $fh) = @_;
  my $slurp = do { local $/; <$fh> };
  my $conf = eval "$slurp";

  # TODO under future versions, provide backwards compatibility
  die "version mismatch.".$/ if $conf->{_version} != $VERSION;

  while (my ($k, $v) = each(%$conf)) {
    $self->{$k} = $v;
  }

  return $self;
}

sub load_file {
  my ($self, $file) = @_;

  open my $fh, '<', $file or die "open error: $!".$/;
  $self->load($fh);
  close $fh or die "close error: $!".$/;

  return $self;
}

sub dump {
  my ($self, $fh) = @_;

  my $d = Data::Dumper->new([ $self ]);
  $d->Terse(1); # avoid '$VAR = ' crap in Data::Dumper output

  print $fh $d->Dump;

  return $self;
}

sub dump_file {
  my ($self, $file) = @_;

  open my $fh, '>', $file or die "open error: $!".$/;
  $self->dump($fh);
  close $fh or die "close error: $!".$/;

  return $self;
}

sub package {
  my ($self, $pkgname) = @_;
  my $packages = $self->packages;
  return exists $packages->{$pkgname} ? $packages->{$pkgname} : undef;
}

sub version { return shift->_member('version', @_); }
sub name { return shift->_member('name', @_); }
sub packages { return shift->_member('packages', @_); }
sub incs_ok { return shift->_member('incs_ok', @_); }
sub logging { return shift->_member('logging', @_); }

sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}

1;

