package Lite::Tree;

# treat things that look like tree structures as if they actually are. :)

# TODO on demand, export aliases for these functions,
# like tree_from_path => Lite::Tree::from_path

use Lite::Tree::Base qw();
use Lite::Tree::Path qw(:all);
use strict;

sub from_path {
  my $path = coerce_path(@_);
  my $node = (my $tree = {});
  
  for ($path->parts()) { $node = $node->{$_} = {}; }

  return $tree;
}

sub from_child_enumerator {
  my $f = shift;
  my $tree = {};

  _create_children("", $tree, 0, $f);

  return $tree;
}

sub _create_children {
  my $parentname = shift;
  my $parent = shift;
  my $depth = shift;
  my $f = shift;

  my %children = $f->(parentname => $parentname,
                      parent => $parent,
                      depth => $depth);

  while (my ($k, $v) = each(%children)) {
    set_child($parent, $k, $v);
    _create_children($k, $v, $depth + 1, $f);
  }

  return $parent;
}

sub get_node {
  my $tree = shift;
  my $path = coerce_path(@_);
  my $node = $tree;

  for my $part ($path->parts()) {
    if (exists($node->{$part})) {
      $node = $node->{$part};
    }
    else {
      return undef;
    }
  }

  return $node;
}

# TODO consolidate logic in .*child.* subs here, possibly via AUTOLOAD

sub get_children {
  my $node = shift;

  if (!ref($node)) {
    return ();
  }
  elsif (ref($node) eq 'HASH') {
    return %$node;
  }
  elsif (UNIVERSAL::isa($node, 'Lite::Tree::Base')) {
    return $node->get_children();
  }
  else {
    return ();
  }
}

sub get_child {
  my $node = shift;
  my $k = shift;

  if (!ref($node)) {
    return undef;
  }
  elsif (ref($node) eq 'HASH') {
    return $node->{$k};
  }
  elsif (UNIVERSAL::isa($node, 'Lite::Tree::Base')) {
    return $node->get_child($k);
  }
  else {
    return undef;
  }
}

sub set_child {
  my $node = shift;
  my $k = shift;
  my $v = shift;

  if (!ref($node)) {
    return undef;
  }
  elsif (ref($node) eq 'HASH') {
    return $node->{$k} = $v;
  }
  elsif (UNIVERSAL::isa($node, 'Lite::Tree::Base')) {
    return $node->set_child($k, $v);
  }
  else {
    return undef;
  }
}

sub clone_and_set_child {
  my $node = shift;
  my $k = shift;
  my $v = shift;

  if (!ref($node)) {
    return undef;
  }
  elsif (ref($node) eq 'HASH') {
    return $node->{$k} = Storable::dclone($v);
  }
  elsif (UNIVERSAL::isa($node, 'Lite::Tree::Base')) {
    return $node->clone_and_set_child($k, $v);
  }
  else {
    return undef;
  }
}

sub exists_child {
  my $node = shift;
  my $k = shift;

  if (!ref($node)) {
    return undef;
  }
  elsif (ref($node) eq 'HASH') {
    return exists($node->{$k});
  }
  elsif (UNIVERSAL::isa($node, 'Lite::Tree::Base')) {
    return $node->exists_child($k);
  }
  else {
    return undef;
  }
}

sub get_parent_node {
  my $tree = shift;
  my $path = coerce_path(@_);
  $path->pop();
  return get_node($tree, $path); 
}

sub clone {
  my $tree = shift;
  return Storable::dclone($tree);
}

# merge two trees to form a new tree. collisions (nodes at the same
# path in both trees that differ in content) are not resolved. in
# the case of a collision, you get the left tree's node.

sub union {
  my $ltree = shift;
  my $rtree = shift;
  my $tree = clone($ltree);
  return union_onto($tree, $rtree);
}

# merge right node onto left node, in place

sub union_onto {
  my $lnode = shift;
  my $rnode = shift;
  my %lchildren = get_children($lnode);
  my %rchildren = get_children($rnode);

  # recurse on children common to both left and right, there
  # may be differences farther down on these branches
  while (my ($k, $v) = each(%lchildren)) {
    if (exists_child($rnode, $k)) {
      union_onto($v, get_child($rnode, $k));
    }
  }

  # add children in right that are missing in left
  while (my ($k, $v) = each(%rchildren)) {
    if (!exists_child($lnode, $k)) {
      clone_and_set_child($lnode, $k, $v);
    }
  }

  return $lnode;
}

sub set_node_at_path {
  my $tree = shift;
  my $node = shift;
  my $path = coerce_path(@_);
  my $basename = $path->pop();
  my $parent = get_node($tree, $path);

  set_child($parent, $basename, $node);

  return $tree;
}

1;

