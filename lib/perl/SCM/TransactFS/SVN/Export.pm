package SCM::TransactFS::SVN::Export;

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
  $self->{_recurse} = $arg->{recurse};
  $self->{_cb_resolve_temporal} = $arg->{cb_resolve_temporal} ||
    sub {
      my ($repo, $temporal) = @_;
      return $repo->fs->youngest_rev if $temporal eq 'R:-1';
      return $1+0 if $temporal =~ /^R:(-?\d+)/;
      return undef;
    };

  return $self;
}

sub tfs_read {
  my ($self, $path, $temporal) = @_;
  $path =~ s{/$}{};
  my $rev = $self->_resolve_temporal($temporal);
  return $self->_export_node($path, $rev);
}

sub _export_node {
  my ($self, $path, $rev) = @_;
  my $kind = $self->_revroot($rev)->check_path($path);
  
  if ($kind == $SVN::Node::file) {
    return $self->_export_file($path, $rev);
  }
  elsif ($kind == $SVN::Node::dir) {
    return $self->_export_dir($path, $rev);
  }
  else {
    return undef;
  }
}

sub _export_dir {
  my ($self, $path, $rev) = @_;
  my @ops;

  push @ops,
  {
    action => 'mk',
    node_kind => 'dir',
    target_path => $path,
    base_temporal => $rev,
  };

  if ($self->{_recurse}) {
    for my $entry (keys %{ $self->_revroot($rev)->dir_entries($path) }) {
      my $subops = $self->_export_node("$path/$entry", $rev);
      return undef if not defined $subops;
      push @ops, @{ $subops };
    }
  }

  return \@ops;
}

sub _export_file {
  my ($self, $path, $rev) = @_;
  my @ops;

  push @ops,
  {
    action => 'add',
    node_kind => 'file',
    target_path => $path,
    base_temporal => $rev,
    content_stream => $self->_revroot($rev)->file_contents($path),
  };

  return \@ops;
}

sub _revroot {
  my ($self, $rev) = @_;
  return $self->{_repos}->fs->revision_root($rev);
}

sub _resolve_temporal {
  my ($self, $temporal) = @_;
  return $self->{_cb_resolve_temporal}->($self->{_repos}, $temporal);
}


1;

