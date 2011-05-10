package Meta::Change::Tree;

# decorates a change tree with meta information about the commit,
# ie the stuff that would normally go into revision properties in
# subversion (but revprops have problems of their own)

use base qw(Change::Tree);
use UNIVERSAL qw();
use Storable qw();
use File::Spec qw();
use Change::File qw();
use Meta::Change::File qw();
use Meta::Change::Places qw(:all);
use Lite::Tree qw();

use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = $class->SUPER::new(@_);

  bless $self, $class;
  init($self, @_);
  
  return $self;
}

sub init {
  my $self = shift;
  die "Expected: argument hash.\n" if @_ & 1;
  my %args = @_;
 
  if (exists($args{meta_change_tree})) {
    # copy constructor

    while (my ($k, $v) = each(%{$args{meta_change_tree}})) {
      $self->{$k} = Storable::dclone($v);
    }
  }
  elsif (exists($args{change_set})) {
    # construct from a Change::Set

    my $cs = $args{change_set};
    $self->addFiles($cs->getFiles());

    my $newtree = {};

    # XXX commit each cs to all branches.
    # for a while, this may be on a per-library basis.
    # eventually branching will be exposed to all.

    my $branchmap = exists($args{branchmap}) ? $args{branchmap} : undef;
    my @branches = defined $branchmap ? keys %$branchmap : ($cs->getMoveType());

    for my $branch (@branches) {
      # rebase the Change::Tree to the appropriate branch path
      my $branchpath = getBranchPath($branch, $branchmap);
      my $branchtree = Lite::Tree::from_path($branchpath);
      my $graft = Lite::Tree::clone($self->{tree});
      Lite::Tree::set_node_at_path($branchtree, $graft, $branchpath);
      Lite::Tree::union_onto($newtree, $branchtree);
    }

    # FIXME egregiously violates encapsulation of parent

    $self->{tree} = $newtree;

    # generate the meta change file, drop it in place

    my $metacontent = $cs->serialise();
    my $metapath = getMetaChangePath($cs);
    my $metacf = Meta::Change::File->new(
    {
      path => $metapath,
      content => $metacontent,
    });

    $self->addFile($metacf);
  }
  else {
    # undefined behavior
    return undef;
  }

  return $self;
}

1;

