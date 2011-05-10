package Lite::Tree::Path;

# this may eventually become a sort of xpath lite, depending
# on what we need it to do.

use base qw(Exporter);

use overload
  fallback => 0,
  q{""} => 'stringify';

our @ISA;
our $VERSION = '0.01';
our %EXPORT_TAGS = (
    all => [ qw(coerce_path) ],
);
our @EXPORT_OK	= map @$_, values %EXPORT_TAGS;
our @EXPORT	= qw();   # nothing by default

use Storable;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  bless $self => $class;
  init($self, @_);

  return $self;
}

sub load {
  return $_[0] if ref($_[0]) eq __PACKAGE__;
  return new(__PACKAGE__, @_);
}

sub coerce_path {
  return load(@_);
}

sub init {
  my $self = shift;

  if (@_ == 1 && ref($_[0]) eq __PACKAGE__) {
    # copy constructor
    while (my ($k, $v) = each(%{$_[0]})) {
      $self->{$k} = Storable::dclone($v);
    }
  }
  elsif (@_ == 1 && !ref($_[0])) {
    # init from a path string
    $self->{_parts} = [ $self->_to_parts($_[0]) ];
  }
  elsif (@_ == 1 && ref($_[0]) eq 'ARRAY') {
    # init from an array ref
    $self->{_parts} = $_[0];
  }
  else {
    # treat init args as array
    $self->{_parts} = [ @_ ];
  }

  return $self;
}

sub stringify { return join('/', $_[0]->parts()); }

sub _to_parts { return grep($_ ne '', split(m{/}, $_[1])); }

sub parts {
  my $self = shift;
  return @_ > 0 ? $self->set_parts(@_) : $self->get_parts();
}

sub get_parts { return @{$_[0]->{_parts}}; }
sub set_parts { $_[0]->{_parts} = $_[1]; }

sub pop { return pop @{$_[0]->{_parts}}; }
sub push { return push @{$_[0]->{_parts}}, $_[1]; }
sub shift { return shift @{$_[0]->{_parts}}; }
sub unshift { return unshift @{$_[0]->{_parts}}, $_[1]; }

1;

