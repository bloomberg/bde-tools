package Meta::Change::File;

use Storable qw();
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  bless $self, $class;
  return $self->init(@_);
}

sub init {
  my $self = shift;

  if (@_ == 1 && ref($_[0]) eq __PACKAGE__) {
    # copy constructor

    while (my ($k, $v) = each(%{$_[0]})) {
      $self->{$k} = Storable::dclone($v);
    }
  }
  elsif (@_ == 1 && ref($_[0]) eq 'HASH') {
    while (my ($k, $v) = each(%{$_[0]})) {
      $self->{$k} = $v;
    }
  }
  else {
    return undef;
  }

  return $self;
}

sub getPath { return $_[0]->{path}; }
sub setPath { $_[0]->{path} = $_[1]; }
sub getContent { return $_[0]->{content}; }
sub setContent { $_[0]->{content} = $_[1]; }

1;

