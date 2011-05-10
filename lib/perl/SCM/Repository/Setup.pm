# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Repository::Setup;

use SCM::TransactFS::SVN::Prepare;
use SCM::TransactFS::SVN::Commit;
use Meta::Change::Places qw(:all);
use strict;

sub create {
  my $repospath = shift;
  # FIXME do this via perl bindings, if possible
  system("svnadmin create --fs-type=fsfs $repospath") && return 0;
  return 1;
}

sub layout {
  my ($repos, $repospath) = @_;

  layout_skeleton($repos, $repospath);
  layout_meta($repos, $repospath);

  return 1;
}

sub layout_skeleton {
  my ($repos, $repospath) = @_;

  my @ops = map
  {{
    action => 'mk',
    node_kind => 'dir',
    target_path => "/$_",
    base_temporal => "R:0",
  }}
  qw(trunk tags branches import meta meta/changes);

  my $prepare = SCM::TransactFS::SVN::Prepare->new();
  my $committer = SCM::TransactFS::SVN::Commit->new
  ({
    repos => $repos,
    repospath => $repospath,
    base_temporal => 'R:0',
    author => 'cstools',
    message => 'initial repository skeleton',
  });

  $prepare->tfs_open();
  $committer->tfs_open();
  $committer->tfs_write($_) for map { @{ $prepare->tfs_filter($_) } } @ops;
  $committer->tfs_close();
  $prepare->tfs_close();

  return 1;
}

sub layout_meta {
  my ($repos, $repospath) = @_;

  my $prepare = SCM::TransactFS::SVN::Prepare->new();
  my $committer = SCM::TransactFS::SVN::Commit->new
  ({
    repos => $repos,
    repospath => $repospath,
    base_temporal => 'R:1',
    author => 'cstools',
    message => 'initial metadata layout',
  });

  $prepare->tfs_open();
  $committer->tfs_open();

  my $mkhashdirs = sub {
    my ($f, $depth, $maxdepth, $hashdirs, $path) = @_;
    return 1 if $depth >= $maxdepth;

    for my $hashdir (@$hashdirs) {
      my %op =
      (
        action => 'mk',
        node_kind => 'dir',
        base_temporal => 'R:1',
        target_path => "$path/$hashdir"
      );
      $committer->tfs_write($_) for @{ $prepare->tfs_filter(\%op) };
      $f->($f, $depth+1, $maxdepth, $hashdirs, "$path/$hashdir") or return 0;
    }

    return 1;
  };

  my @hashdirs = getDirectoryHashSpace();
  my $hashlevel = getDirectoryHashLevels();
  my $hashroot = getMetaChangeBasePath();

  $mkhashdirs->($mkhashdirs, 0, $hashlevel, \@hashdirs, $hashroot);

  $committer->tfs_close();
  $prepare->tfs_close();

  return 1;
}

1;

