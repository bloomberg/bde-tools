package Lite::Tree::Base;

# base class for classes providing tree-like objects. inherit from me if
# you want Lite::Tree to consider you part of the tree structure.
# objects which are not derived from me will not
# be treated as part of the tree structure, ie they will be terminal
# leaves which are never traversed into.

use Storable qw();
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  bless $self => $class;

  return $self;
}

# default implementation - assumes you are a blessed hashref

sub get_children { return keys %{$_[0]} }
sub get_child { return $_[0]->{$_[1]} }
sub set_child { return $_[0]->{$_[1]} = $_[2]; }
sub clone_and_set_child { return $_[0]->{$_[1]} = Storable::dclone($_[2]); }
sub exists_child { return exists($_[0]->{$_[1]}); }

1;

