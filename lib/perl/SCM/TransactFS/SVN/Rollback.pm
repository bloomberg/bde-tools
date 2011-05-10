package SCM::TransactFS::SVN::Rollback;

use base qw(SCM::TransactFS::Producer);
use SVN::Repos;
use SVN::Core;
use SVN::Fs;
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = $class->SUPER::new(@_);
  return $self;
}

sub init {
  my ($self, $arg) = @_;

  $self->SUPER::init(@_);
  $self->{_repos} = $arg->{repos};

  return $self;
}

sub tfs_read {
  my ($self, $rev) = @_;
  my $pool = SVN::Pool->new;
  my $preroot = $self->{_repos}->fs->revision_root($rev-1, $pool);
  my $postroot = $self->{_repos}->fs->revision_root($rev, $pool);
  my $changes = $postroot->paths_changed($pool);

  my %types = ($SVN::Node::file => 'file', $SVN::Node::dir => 'dir');
  my @ops;

  while (my ($path, $change) = each(%$changes)) {
    my $pretype = $preroot->check_path($path, $pool);
    my $posttype = $postroot->check_path($path, $pool);

    if ($pretype == $SVN::Node::none) {
      # node was absent in previous revision, so remove it
      push @ops,
      {
        action => 'rm',
        node_kind => $types{$posttype},
        target_path => $path,
        base_temporal => "R:$rev",
      };
    }
    else {
      # node was present in previous revision, so resurrect it
      push @ops,
      {
        action => 'cp',
        node_kind => $types{$pretype},
        target_path => $path,
        source_temporal => "R:".($rev-1),
        base_temporal => "R:$rev",
      };
    }
  }

  return \@ops;
}

1;

