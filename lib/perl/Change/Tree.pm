package Change::Tree;

use UNIVERSAL qw();
use Storable qw();
use File::Spec qw();
use Lite::Tree qw();
use Change::Util::Interface qw(getCanonicalPath);

use strict;

  # fill in the tree with parts from this Change::File's path.
  # this is done because the baton traversal rules for an svn editor
  # require a tree to be committed in DFS order.
 
sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = { tree => {} };

  bless $self, $class;

  my $init = __PACKAGE__ . "::init";
  $self->$init(@_);
 
  return $self;
}

sub init {
  my $self = shift;
  die "Expected: argument hash.\n" if @_ & 1;
  my %args = @_;

  if (exists($args{change_tree})) {
    # copy constructor

    while (my ($k, $v) = each(%{$args{change_tree}})) {
      $self->{$k} = Storable::dclone($v);
    }
  }
  elsif (exists($args{change_set})) {
    # construct from a Change::Set

    $self->addFiles($args{change_set}->getFiles());
  }
  elsif (exists($args{change_files})) {
    # construct from Change::File list

    $self->addFiles(@{$args{change_files}});
  }
  elsif (exists($args{tree})) {
    # construct from a nested hashref tree structure

    $self->{tree} = Storable::dclone($args{tree});
  }
  else {
    # undefined behavior
    return undef;
  }

  return $self;
}

sub addFiles {
  my $self = shift;

  for (@_) {
    $self->addFile($_);
  }
  
  return 1;
}

sub addFile {
  my $self = shift;
  my $changefile = shift;
  my $path;

  if (UNIVERSAL::isa($changefile, 'Change::File')) {
    my @parts = grep length, File::Spec->splitdir($changefile->getDestination());
    shift @parts;
    $path = File::Spec->catdir(@parts);
  }
  elsif (UNIVERSAL::isa($changefile, 'Meta::Change::File')) {
    $path = $changefile->getPath();
  }

  my $treefrag = Lite::Tree::from_path($path);

  Lite::Tree::set_node_at_path($treefrag, $changefile, $path);
  Lite::Tree::union_onto($self->{tree}, $treefrag);
  
  return 1;
}

# TODO implement these--requires inserting Change::Dirs instead of anonymous
# hashes into the tree, and changes the tree iteration elsewhere. current
# system does not need this.

sub addDir { return 1; }
sub removeDir { return 1; }
sub moveDir { return 1; }

sub getRoot { return $_[0]->{tree}; }

1;

