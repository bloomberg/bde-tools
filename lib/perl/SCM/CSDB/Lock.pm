package SCM::CSDB::Lock;

use base qw/SCM::CSDB/;
use strict;

our $SQL =
{
  lock_full_path =>
    q{ update file_lock
       set unix_user = %user%
       where
         (file_lock.unix_user is NULL or file_lock.unix_user = %user%) and
         file_lock.file_id =
           (select file_id from canonical_file where path = %path%) },

  unlock_full_path =>
    q{ update file_lock
       set unix_user = NULL
       where
         (file_lock.unix_user = %user% or file_lock.unix_user is NULL) and
          file_lock.file_id =
           (select file_id from canonical_file where path = %path%) },

  steal_full_path =>
    q{ update file_lock
       set unix_user = %user%
       where 
         (file_lock.unix_user = %olduser% or
          file_lock.unix_user = %user% or
          file_lock.unix_user is NULL)
         and file_lock.file_id =
           (select file_id from canonical_file where path = %path%) },

  force_lock_full_path =>
    q{ update file_lock
       set unix_user = %user%
       where
         file_lock.file_id =
           (select file_id from canonical_file where path = %path%) },

  force_unlock_full_path =>
    q{ update file_lock
       set unix_user = NULL
       where
         file_lock.file_id =
           (select file_id from canonical_file where path = %path%) },

  query_owner_by_full_path =>
    q{ select unix_user as user
       from file_lock as l, canonical_file as f
       where l.file_id = f.file_id and f.path = %path% },

  log_event_by_full_path =>
    q{ insert into
       locking_event(event_time, lock_id, unix_user, lock_operation)
         select current year to second, l.lock_id, $eventby$, $operation$
         from file_lock as l, canonical_file as f
         where l.file_id = f.file_id and f.path = %path% }, 

  history_by_full_path =>
    q{ select e.* from locking_event e, file_lock l, canonical_file f
       where e.lock_id = l.lock_id and l.file_id = f.file_id and
         f.path = %path% },

  query_file_by_full_path =>
    q{ select * from canonical_file where path = %path% },

  query_lock_by_full_path =>
    q{ select l.* from file_lock as l, canonical_file as f
       where l.file_id = f.file_id and f.path = %path% },

  query_locks_by_owner =>
    q{ select f.path from canonical_file as f, file_lock as l
       where l.file_id = f.file_id and l.unix_user = %user% },

  make_full_path =>
    q{ insert into canonical_file(path) values (%path%) },

  make_lock_for_full_path =>
    q{ insert into file_lock(file_id)
       select file_id from canonical_file where path = %path% },

  move_full_path =>
    q{ update canonical_file set path = %dstpath% where path = %srcpath% },

  delete_full_path =>
    q{ delete from canonical_file where path = %path% },

  delete_lock_for_full_path =>
    q{ delete from file_lock where
       file_id = (select file_id from canonical_file where path = %path%) },

  delete_logs_for_full_path =>
    q{ delete from locking_event where
       lock_id =
         (select lock_id from file_lock, canonical_file where
          file_lock.file_id = canonical_file.file_id and
          canonical_file.path = %path%) }, 
};

sub lock { return shift->_txnwrap(\&_lock, @_); }
sub unlock { return shift->_txnwrap(\&_unlock, @_); }
sub owner { return shift->_txnwrap(\&_owner, @_); }
sub steal { return shift->_txnwrap(\&_steal, @_); }
sub force { return shift->_txnwrap(\&_force, @_); }
sub mklock { return shift->_txnwrap(\&_mklock, @_); }
sub mkfile { return shift->_txnwrap(\&_mkfile, @_); }
sub mvfile { return shift->_txnwrap(\&_mvfile, @_); }
sub statfile { return shift->_txnwrap(\&_statfile, @_); } 
sub statlock { return shift->_txnwrap(\&_statlock, @_); } 
sub mklockable { return shift->_txnwrap(\&_mklockable, @_); }
sub rmlockable { return shift->_txnwrap(\&_rmlockable, @_); }
sub logevent { return shift->_txnwrap(\&_logevent, @_); }
sub history { return shift->_txnwrap(\&_history, @_); }
sub lockedby { return shift->_txnwrap(\&_lockedby, @_); }

sub _lock {
  my ($self, $param, %args) = @_;

  $param->{operation} = 'L';
  $self->mklockable($param, %args);
  $self->execute('lock_full_path', $param) == 1 or return undef;
  $self->logevent($param, %args) == 1 or return undef;

  return 1;
}

sub _unlock {
  my ($self, $param, %args) = @_;

  $param->{operation} = 'U';
  $self->execute('unlock_full_path', $param) == 1 or return undef;
  $self->logevent($param, %args) == 1 or return undef;

  return 1;
}

sub _steal {
  my ($self, $param, %args) = @_;

  $param->{operation} = 'S';
  $self->execute('steal_full_path', $param) == 1 or return undef;
  $self->logevent($param, %args) == 1 or return undef;

  return 1;
}

sub _force {
  my ($self, $param, %args) = @_;

  $self->mklockable($param, %args);

  if (defined $param->{user}) {
    $param->{operation} = 'F';
    $self->execute('force_lock_full_path', $param) == 1 or return undef;
  }
  else {
    $param->{operation} = 'X';
    $self->execute('force_unlock_full_path', $param) == 1 or return undef;
  }

  $self->logevent($param, %args) == 1 or return undef;

  return 1;
}

sub _owner {
  my ($self, $param, %args) = @_;
  my $row = $self->select_one('query_owner_by_full_path', $param)
    or return undef;
  return $row->{user};
}

sub _mklock {
  my ($self, $param, %args) = @_;
  $self->execute('make_lock_for_full_path', $param) == 1 or return undef;
  return 1;
}

sub _mkfile {
  my ($self, $param, %args) = @_;
  $self->execute('make_full_path', $param) == 1 or return undef;
  return 1;
}

sub _mvfile {
  my ($self, $param, %args) = @_;
  $self->execute('move_full_path', $param) == 1 or return undef;
  return 1;
}

sub _statfile {
  my ($self, $param, %args) = @_;
  my $stat = $self->select_one('query_file_by_full_path', $param);
  return $stat;
}

sub _statlock {
  my ($self, $param, %args) = @_;
  my $stat = $self->select_one('query_lock_by_full_path', $param);
  return $stat;
}

sub _mklockable {
  my ($self, $param, %args) = @_;

  $self->mkfile($param, %args) or return undef
    if !$self->statfile($param, %args);
  $self->mklock($param, %args) or return undef
    if !$self->statlock($param, %args);

  return 1;
}

sub _rmlockable {
  my ($self, $param, %args) = @_;
  $self->execute('delete_logs_for_full_path', $param);
  $self->execute('delete_lock_for_full_path', $param) == 1 or return undef;
  $self->execute('delete_full_path', $param) == 1 or return undef;
  return 1;
}

sub _history {
  my ($self, $param, %args) = @_;
  return $self->select_all('history_by_full_path', $param);
}

sub _logevent {
  my ($self, $param, %args) = @_;
  $param->{eventby} ||= $param->{user};
  $self->execute('log_event_by_full_path', $param) == 1 or return undef;
  return 1;
}

sub _lockedby {
  my ($self, $param, %args) = @_;
  return $self->select_all('query_locks_by_owner', $param);
}

1;

