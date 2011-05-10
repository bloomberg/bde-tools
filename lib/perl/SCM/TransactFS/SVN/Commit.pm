package SCM::TransactFS::SVN::Commit;

use base qw(SCM::TransactFS::Consumer);
use Util::File::Path;
use SVN::Repos;
use SVN::Delta;
use SVN::Core;
use SVN::Fs;
use IO::File;
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
  $self->{_repospath} = $arg->{repospath};
  $self->{_autoadd} = $arg->{autoadd} || 0;
  $self->{_autochange} = $arg->{autochange} || 0;

  $self->{_cb_resolve_temporal} = $arg->{cb_resolve_temporal} ||
    sub {
      my ($repo, $temporal) = @_;
      return $2 if $temporal =~ /^R(:|_)?(\d+)/;
      return undef;
    };

  $self->{_cb_committed} = $arg->{cb_committed} ||
    sub {
      if (@_) {
        my ($rev, $date, $author) = map defined $_ ? $_ : '(unknown)', @_;
        print "committed rev $rev by $author on $date.\n";
      }
    };

  $self->{_base_temporal} = $arg->{base_temporal};
  $self->{_commit_info} = $arg->{commit_info} ||
  {
    author => $arg->{author} || 'cstools',
    message => $arg->{message} || '', 
  };

  $self->{_op_dispatch} =
  {
    mkfile => '_file_op',
    addfile => '_file_op',
    patchfile => '_file_op',
    writefile => '_file_op',
    rmfile => '_delete_entry',
    cpfile => '_file_op',
    mkdir => '_add_dir',
    rmdir => '_delete_entry',
    cpdir => '_add_dir',
    # mvfile and mvdir must be expanded upstream into cp + rm,
    # at least with the svn of our time
  };

  return $self;
}

sub resolve_temporal {
  my ($self, $temporal) = @_;
  return $self->{_cb_resolve_temporal}->($self->{_repos}, $temporal);
}

sub tfs_open {
  my $self = shift;
  my ($edelta, $ebaton);

  $self->{_pool} = SVN::Pool->new;

  ($edelta, $ebaton) = $self->{_repos}->get_commit_editor(
    "file://$self->{_repospath}",
    '/',
    $self->{_commit_info}->{author},
    $self->{_commit_info}->{message},
    $self->{_cb_committed},
    $self->{_pool},
  );

  $self->{_editor} = SVN::Delta::Editor->new($edelta, $ebaton);
  $self->{_baserev} = $self->resolve_temporal($self->{_base_temporal});
  $self->{_revroot} = $self->{_repos}->fs->revision_root($self->{_baserev});
  $self->{_checkpath} = {};

  # breadcrumb trail for dfs traversal, crumbs consist of
  # [ baton, path/to/node, pool ]

  $self->{_trail} =
    [ { baton => $self->{_editor}->open_root($self->{_baserev}, $self->{_pool}),
        path => '', pool => $self->{_pool} } ];

  return 1;
}

sub tfs_close {
  my $self = shift;

  # close any leftover batons in the trail

  while ($self->{_trail} && @{$self->{_trail}}) {
    $self->_close_dir;
  }

  $self->{_checkpath} = {};
  $self->{_editor}->close_edit($self->{_pool});
  $self->{_editor} = $self->{_revroot} = undef;
  $self->{_pool} = undef;

  return 1;
}

sub tfs_abort {
  my $self = shift;

  # close any leftover batons in the trail

  while ($self->{_trail} && @{$self->{_trail}}) {
    $self->_close_dir;
  }

  $self->{_checkpath} = {};
  $self->{_editor}->abort_edit($self->{_pool}) if $self->{_editor};
  $self->{_editor} = $self->{_revroot} = undef;
  $self->{_pool} = undef;

  return 1;
}

sub tfs_write {
  my ($self, $op) = @_;

  # point trail over to the new path

  $self->_move_trail($op->{target_path}) or return 0;

  my $opname = $op->{action} . $op->{node_kind};
  my $dispatch = $self->{_op_dispatch}->{$opname};

  if (not $dispatch) {
    die qq{Error: don't understand operation "$opname."};
  }

  return $self->$dispatch($op);
}

sub _move_trail {
  my ($self, $path) = @_;

  # upgoing...

  $path = Util::File::Path->new($path);

  while (not $self->_current_path->is_ancestor($path)) {
    $self->_close_dir;
  }

  return 1 if $path eq $self->_current_path;

  # downgoing...

  my $relpath = $path->relative_to($self->_current_path)->parent;

  for my $part (@{$relpath}) {
    $self->_open_dir(join('/', $self->_current_path, $part));
  }

  return 1;
}

sub _current_baton {
  return $_[0]->{_trail}->[0]->{baton};
}

sub _current_path {
  return Util::File::Path->new($_[0]->{_trail}->[0]->{path});
}

sub _current_pool {
  return $_[0]->{_trail}->[0]->{pool};
}

sub _open_dir {
  my ($self, $path) = @_;
  my $baserev = $self->resolve_temporal($self->{_base_temporal});

  # autoadd: turn missing dir opens into adds (*dangerous behavior*)

  if ($self->{_autoadd} && !$self->_check_path($path)) {
    return $self->_add_dir(
    {
      action => 'mk',
      node_kind => 'dir',
      base_temporal => $self->{_base_temporal},
      target_path => $path,
    });
  }

  my $pool = $self->_nested_pool;
  my $dbaton = $self->{_editor}->open_directory(
    $path,
    $self->_current_baton,
    $baserev,
    $pool
  );

  unshift @{$self->{_trail}},
    { path => $path, baton => $dbaton, pool => $pool };

  return 1;
}

sub _close_dir {
  my ($self) = @_;
  my $crumb = shift @{$self->{_trail}};

  $self->{_editor}->close_directory($crumb->{baton}, $crumb->{pool});

  return 1;
}

sub _add_dir {
  my ($self, $op) = @_;
  my $pool = SVN::Pool->new_default;
  my $dbaton = $self->{_editor}->add_directory(
    $op->{target_path},
    $self->_current_baton,
    $self->_get_copy_origin($op),
    $pool,
  );

  $self->{_checkpath}->{$op->{target_path}} = $SVN::Node::dir;

  unshift @{$self->{_trail}},
    { path => $op->{target_path}, baton => $dbaton, pool => $pool };

  return 1;
}

sub _file_op {
  my ($self, $op) = @_;

  die "Error, operation not implemented: patch." if $op->{action} eq 'patch';

  my $pool = SVN::Pool->new;
  my $action = $op->{action};
  my $baserev = $self->resolve_temporal($op->{base_temporal});
  my $fbaton;

  # autoadd: turn writes to missing files into adds (*dangerous*)
  # autochange: turn adds / mks of existing files into writes (*dangerous*)

  if ($self->{_autoadd} && $action eq 'write' &&
     !$self->_check_path($op->{target_path})) {
    $action = 'add';
  }
  elsif ($self->{_autochange} && ($action eq 'add' || $action eq 'mk') &&
         $self->_check_path($op->{target_path})) {
    $action = 'write';
  }
  
  if (grep $action eq $_, qw(add mk cp)) {
    $fbaton = $self->{_editor}->add_file(
      $op->{target_path},
      $self->_current_baton,
      $self->_get_copy_origin($op),
      $pool
    );

    # preserve executable bit if present
    $self->{_editor}->change_file_prop(
            $fbaton, 
            'svn:executable' => '*',
            $pool
    ) if -x $op->{content_path};

    $self->{_checkpath}->{$op->{target_path}} = $SVN::Node::file;
  }
  elsif (grep $action eq $_, qw(write patch)) {
    $fbaton = $self->{_editor}->open_file(
      $op->{target_path},
      $self->_current_baton,
      $baserev,
      $pool
    );
  }

  if (grep $action eq $_, qw(add write patch)) {
    my $handle = $self->{_editor}->apply_textdelta($fbaton, undef, $pool);

    # TODO implement patching here

    if ($op->{content_path}) {
      my $fh = IO::File->new($op->{content_path}) 
        or die "Error opening $op->{content_path} for read: $!.";
      SVN::TxDelta::send_stream($fh, @$handle, $pool);
      undef $fh;
    }
    elsif ($op->{content_stream}) {
      SVN::TxDelta::send_stream($op->{content_stream}, @$handle, $pool);
    }
    elsif ($op->{content}) {
      SVN::TxDelta::send_string($op->{content}, @$handle, $pool);
    }
    else {
      die qq{Error, content expected with "$action" operation.};
    }
  }

  $self->{_editor}->close_file($fbaton, undef, $pool) if $fbaton;

  return 1;
}

sub _delete_entry {
  my ($self, $op) = @_;
  my $pool = $self->_nested_pool;

  my $baton = $self->{_editor}->delete_entry(
    $op->{target_path},
    $self->resolve_temporal($op->{base_temporal}),
    $self->_current_baton,
    $pool,
  );

  $self->{_checkpath}->{$op->{target_path}} = $SVN::Node::none;

  return 1;
}

sub _get_copy_origin {
  my ($self, $op) = @_;
  my ($frompath, $fromrev) = (undef, -1);

  if ($op->{action} eq 'cp') {
    $frompath = "file://" . $self->{_repospath} . $op->{source_path};
    $fromrev = $self->resolve_temporal($op->{source_temporal});
  }

  return $frompath, $fromrev;
}

sub _check_path {
  my ($self, $path) = @_;
  my $pool = SVN::Pool->new_default;
  return $self->{_checkpath}->{$path} if exists $self->{_checkpath}->{$path};
  return $self->{_revroot}->check_path($path);
}

sub _headrev {
  my $self = shift;
  my $pool = SVN::Pool->new;
  return $self->{_repos}->fs->youngest_rev($pool);
}

sub _nested_pool {
  my $self = shift;
  return SVN::Pool->new($self->_current_pool);
}

1;

