package SCM::Repository;

use strict;

use File::Spec;
use File::Temp qw(tempdir);
use File::chdir;
use HTTP::Date;
use SVN::Repos;
use SVN::Delta;
use SVN::Core;
use SVN::Fs;

use Change::Symbols qw/FILE_IS_RENAMED FILE_IS_COPIED/;
use SCM::Symbols    qw/SCM_CSDB SCM_CSDB_DRIVER
		       SCM_REPOSITORY 
		       SCM_REPOSITORY_AUTOADD SCM_REPOSITORY_AUTOCHANGE/;

use Change::Set;

use Util::Exception	    qw/exception/;
use Meta::Change::Places    qw/:all/;

use SCM::TransactFS::SVN::Prepare;
use SCM::TransactFS::SVN::Commit;

use SCM::TransactFS::CS::FromCS;

use SCM::Repository::Csid2Rev;
use SCM::Repository::Rev2Csid;
use SCM::Repository::BranchInfo;
use SCM::Repository::CommitInfo;

use SCM::Util::Slurp	    qw/:all/;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};
  bless $self => $class;
  $self->init(@_);
  return $self;
}

sub init {
  my $self = shift;
  my %args = @_;

  my $repospath = $args{repository_path} || SCM_REPOSITORY;
  $repospath =~ s{/$}{};  # svn dislikes trailing /

  $self->_repospath($repospath);
  $self->_open unless exists $args{auto_open} && !$args{auto_open};

  return $self;
}

sub DESTROY {
  my $self = shift;
  $self->_close;
}

sub commit {
  my ($self, $cs) = @_;
  my $ops;

  my $branchmap = $self->_branchmap;
  my $fromcs = SCM::TransactFS::CS::FromCS->new({branchmap=>$branchmap});

  $fromcs->tfs_open();
  $ops = $fromcs->tfs_read($cs);
  $fromcs->tfs_close();

  my ($rev, $date, $author);
  my @commitargs = 
  (
    $ops,
    author => $cs->getUser,
    message => $cs->getMessage,
    base_temporal => 'R:' . $self->_headrev,
    cb_resolve_temporal => sub {
      my ($repo, $temporal) = @_;
      return $self->_temporal_to_rev($cs->getMoveType, $temporal);
      return undef;
    },
    cb_committed => sub { ($rev,$date,$author)=@_; },
  );

  local $@;

  $^P ? $self->_commit_ops(@commitargs) :
    eval { $self->_commit_ops(@commitargs) };

  return undef, $@ if $@;
  return $rev, 0;
}

sub commit_bundle {
  my ($self, $bundle) = @_;

  require Change::Util::Bundle;
  my $bndl  = Change::Util::Bundle->new(bundle => $bundle);
  my $cs    = $bndl->cs;

  {
    local $CWD = $bndl->tmp;

    $_->setSource($_->getDestination) for
      grep $_->getType ne FILE_IS_RENAMED && $_->getType ne FILE_IS_COPIED,
      $cs->getFiles;

    return $self->commit($cs);
  }
}

# export directly to disk:
#   * pass in hash of (canonical path, local path) pairs
#   * get back array of canonical paths written out successfully

sub export {
    my ($self, $csid, $files, $checkoutcsid) = @_;
    my $rev = $csid ? $self->_get_rev_from_csid($csid) : $self->_headrev or
	return undef, "Error, no such csid $csid.";

    my $pool = SVN::Pool->new_default(undef);
    my $revroot = $self->_repo->fs->revision_root($rev);
    my @files;

    while (my ($fullpath, $outpath) = each %$files) {
	my $repopath = File::Spec->catfile('/branches', $fullpath);
	$revroot->check_path($repopath, SVN::Pool->new) == $SVN::Node::file or
	    return undef, "Error exporting, $repopath doesn't exist or is no file.";
	$self->_export_file($repopath, $outpath, revroot => $revroot) or
	    return undef, "Error exporting $fullpath to $outpath.";
	$self->_update_tsp($outpath, $rev);
	push @files, $fullpath;
	if (ref $checkoutcsid) {
	    my ($csid, $err) = $self->csid_history($fullpath, limit => 1);
	    $checkoutcsid->{$fullpath} = $csid->[0] if not $err;
	    warn "Checked out: ", $csid ? $csid->[0] : $err, "\n";
	}
    }
    return \@files, 0;
}

sub list_commits {
    my ($self, $branch, $startcsid, $lastn, $endcsid) = @_;

    return $self->csid_history($branch,
			       startcsid    => $startcsid,
			       endcsid	    => $endcsid,
			       limit	    => $lastn,
    );
}

sub head_csid {
  my $self = shift;
  my $pool = SVN::Pool->new_default(undef);
  return $self->_get_csid_from_rev($self->_repo->fs->youngest_rev);
}

sub csid_history {
  my ($self, $path, %arg) = @_;
  my (@csids, %crawl);

  $crawl{path} = $path if defined $path;

  if ($arg{startcsid}) {
    $crawl{startrev} = $self->_get_rev_from_csid($arg{startcsid}) or
      return 0, "CSID not found: $arg{startcsid}.";
  }

  $crawl{startrev} ||= $self->_headrev;

  if ($arg{endcsid}) {
    $crawl{endrev} = $self->_get_rev_from_csid($arg{endcsid}) or
      return 0, "CSID not found: $arg{endcsid}.";
  }

  $crawl{cb_visit} = sub {
    my ($rev) = @_;
    my $csid = $self->_get_csid_from_rev($rev);

    return 1 if !$csid; # keep going, no csid associated with this rev
    return 0 if defined $arg{limit} && @csids >= $arg{limit};

    if (exists $arg{visit}) {
      my $visit = $arg{visit}->($csid);
      return $visit if !$visit;
    }

    unshift @csids, $csid;
    return 1; # keep going
  };

  $self->_cs_crawlback(%crawl);

  return \@csids, 0;
}

sub commit_info {
  my $pool = SVN::Pool->new_default(undef);
  my ($self, %arg) = @_;
  my $rev = $arg{rev} || $self->_get_rev_from_csid($arg{csid});
  return undef unless defined $rev;
  return $self->_commitinfo->get($rev);
}

sub check_paths {
  my $pool = SVN::Pool->new_default(undef);
  my ($self, $branch, $csid, $paths) = @_;
  my $branchmap = $self->_branchmap;
  my $branchpath = getBranchPath($branch, $branchmap);
  my $rev = $self->_get_rev_from_csid($csid) or 
    return undef, "CSID $csid not found.";

  my $revroot = $self->_repo->fs->revision_root($rev);
  my %types = ( $SVN::Node::file=>'f', $SVN::Node::dir=>'d' );
  my %checks;

  for my $path (@$paths) {
    my $pool = SVN::Pool->new;
    $checks{$path} = $types{$revroot->check_path("$branchpath/$path", $pool)};
  }

  return \%checks, 0;
}

sub paths_changed {
  my $pool = SVN::Pool->new_default(undef);
  my ($self, $branch, $csid) = @_;
  my $branchmap = $self->_branchmap;
  my $branchpath = getBranchPath($branch, $branchmap);
  my $rev = $self->_get_rev_from_csid($csid) or 
    return undef, "CSID $csid not found.";

  # FIXME check for matching branch disappears under upfront branching
  my $cs = $self->_get_cs_from_rev($rev);

  unless (getBranchPath($cs->getMoveType, $branchmap) eq $branchpath) {
    return undef, "CSID $csid not found.";
  }

  my $revroot = $self->_repo->fs->revision_root($rev);
  my @allpaths = keys %{ $revroot->paths_changed };
  my %types = ( $SVN::Node::file=>'f', $SVN::Node::dir=>'d' );
  my %paths;

  # only expose paths under /branches/whatever/ as relative ones,
  # and don't expose svn node types to caller

  for my $path (map {$_} @allpaths) {
    my $pool = SVN::Pool->new;
    my $type = $types{$revroot->check_path($path, $pool)} or next;
    $path =~ s{^\Q$branchpath/\E}{} or next;
    $paths{$path} = $type;
  }

  return \%paths, 0;
}

sub diff {
  my ($self, $branch, $csid, $canonpath) = @_;
  my $rrev = $self->_get_rev_from_csid($csid);

  return (undef, "No record of changeset $csid found.") if !$rrev;

  my $path;
  my $lrev = $rrev-1;

  $path = $canonpath; 
  $path =~ s{^root/}{};
  $path = getBranchPath($branch, $self->_branchmap()) . "/$path";

  my $basename = (split(m{/}, $path))[-1];
  my $lkind = $self->_check_path($path, rev => $lrev);
  my $rkind = $self->_check_path($path, rev => $rrev);

  my $diff;

  if ($lkind == $SVN::Node::file && $rkind == $SVN::Node::file) {
    local $CWD = tempdir(CLEANUP => 1);
    $self->_export_file($path, "$basename.old", rev => $lrev);
    $self->_export_file($path, "$basename.new", rev => $rrev);
    open my $diff_fh, '-|', "diff -ub $basename.old $basename.new"
      or return (undef, "Error running diff: $?.");
    $diff = slurp($diff_fh);
    $diff_fh = undef;
  }
  else {
    $diff = "... rm $basename" if $lkind == $SVN::Node::file && !$rkind;
    $diff = "... rmdir $basename" if $lkind == $SVN::Node::dir && !$rkind;
    $diff = "... add $basename" if !$lkind && $rkind == $SVN::Node::file;
    $diff = "... mkdir $basename" if !$lkind && $rkind == $SVN::Node::dir;
    $diff .= $/ if $diff;
  }

  unless (defined $diff) {
    return (undef, "Diff unavailable for $canonpath at csid $csid.");
  }

  return ($diff, 0);
}

sub path_exists {
  my ($self, $lroot) = @_;

  $lroot =~ s#^root/##;

  for (qw/move bugf emov stpr/) {
    my $branch = $self->_resolve_branch($_);
    my $fpath  = "branches/$branch/$lroot";
    return $_ if $self->_check_path($fpath);
  }

  return;
}

sub _cs_crawlback {
    my ($self, %arg) = @_;
    my $path = $arg{path}
	or return (undef, "path argument not given");

    my $pool = SVN::Pool->new_default(undef);
    my $startrev = $arg{startrev} || $self->_headrev();
    my $endrev = $arg{endrev} || $self->_get_branch_birthrev($path);
    my $cb_visit = $arg{cb_visit} || sub { my ($rev) = @_; return 1; };

    my $fs = $self->_repo->fs;

    # crawl the revision interval backwards in time, only stopping on
    # revisions where a Change::Set was committed to the branch.

    my $startroot = $fs->revision_root($startrev);
    my $history = $startroot->node_history("/branches/$path");

    my ($branchno) = $path =~ /^(\d+)/;
    while ($history = $history->prev($history, 0)) {
	my ($histpath, $histrev) = $history->location();

	my $histroot = $fs->revision_root($histrev);
	my $changes = $histroot->paths_changed();

	# done, do not look any earlier than this
	last if $histrev <= $endrev;

	# skip, no paths under the branch were actually affected
	next if !grep m!^/branches/$branchno!, keys %$changes;

	# skip if this rev does not involve a Change::Set
	my $cs = $self->_get_cs_from_rev($histrev) or next;

	# visit the revision
	$cb_visit->($histrev) or last;
    }

    return 1;
}

sub _temporal_to_rev {
  my ($self, $branch, $temporal) = @_;
  my ($type, $value) = ($temporal =~ /^(R|C|T|S)(?::|_)([\w-]+)$/);

  if (defined $type and defined $value) {
    if ($type eq 'R') {
      return $value;
    }
    elsif ($type eq 'C') {
      return $self->_get_rev_from_csid($value);
    }
    elsif ($type eq 'T') {
      my $info = $self->_get_branch_tag_info($branch, $value);
      return defined $info ? $info->[1] : undef; 
    }
    elsif ($type eq 'S') {
      return $self->_headrev() if ($value eq 'HEAD');
      return $self->_get_branch_birthrev($branch) if ($value eq 'ORIGIN');
    }
  }

  return undef;
}

sub _get_branch_birthrev {
    my ($self, $branchthing) = @_;
    my ($branch) = $branchthing =~ /^(\d+)/;
    return $self->_branchinfo->get($branch)->{birthrev};
}

sub _open {
  my $self = shift;

  # FIXME SVN::Pool::new_default considered harmful
  #
  # The new pool is set as the default pool via a global variable,
  # so creating more than one SCM::Repository is now not safe.
  # However, it seems we must control the default pool in order to
  # avoid $SVN::Core::gpool accumulating memory without bound.
  # Current SCM::Repository usage (as a single instance in a long-
  # running daemon) favors this approach despite the shortcomings.

  my $pool = $self->_pool || SVN::Pool->new_default(undef);
  my $repo = $self->_repo || SVN::Repos::open($self->_repospath, $pool);

  $self->_pool($pool);
  $self->_repo($repo);

  # re-initialize the lookup caches
  $self->_csid2rev(SCM::Repository::Csid2Rev->new(repo => $repo));
  $self->_rev2csid(SCM::Repository::Rev2Csid->new(repo => $repo));
  $self->_branchinfo(SCM::Repository::BranchInfo->new(repo => $repo));
  $self->_commitinfo(SCM::Repository::CommitInfo->new(repo => $repo));

  # rebuild the lookup caches only if there were cache misses
  $self->_csid2rev->rebuild	if $self->_csid2rev->loadmisses;
  $self->_rev2csid->rebuild	if $self->_rev2csid->loadmisses;
  $self->_branchinfo->rebuild	if $self->_branchinfo->loadmisses;
  $self->_commitinfo->rebuild	if $self->_commitinfo->loadmisses;

  return 1;
}

sub _close {
  my $self = shift;

  $self->_repo(undef);
  $self->_csid2rev(undef);
  $self->_rev2csid(undef);
  $self->_branchinfo(undef);
  $self->_pool->clear;

  return 1;
}

sub _commit_ops {
  my ($self, $ops, %arg) = @_;

  my $prepare = SCM::TransactFS::SVN::Prepare->new;
  my $committer = SCM::TransactFS::SVN::Commit->new
  ({
    repos => $self->_repo,
    repospath => $self->_repospath,
    base_temporal => $arg{base_temporal},
    author => $arg{author},
    message => $arg{message},
    cb_committed => $arg{cb_committed},
    cb_resolve_temporal => $arg{cb_resolve_temporal},
    autoadd => SCM_REPOSITORY_AUTOADD,
    autochange => SCM_REPOSITORY_AUTOCHANGE,
  });

  local $SVN::Error::handler = sub {
    my $error = shift;
    $committer->tfs_abort();
    die $self->_commit_error($error);
  };

  $prepare->tfs_open();
  $committer->tfs_open();
  $committer->tfs_write($_) for (map { @{$prepare->tfs_filter($_)} } @$ops);
  $committer->tfs_close();
  $prepare->tfs_close();
}

sub _commit_error {
  my ($self, $error) = @_;
  my $addcr = sub { $_[0] =~ s/([^\n])$/$1\n/; return $_[0] };

  return exception($addcr->($error), 111) unless
    UNIVERSAL::isa($error, '_p_svn_error_t');

  # distinguish errors of the "out-of-date" variety from
  # other more serious svn internal errors

  return exception($addcr->($error->message), $error->apr_err) if
    grep $error->apr_err == $_,
      $SVN::Error::FS_TXN_OUT_OF_DATE,
      $SVN::Error::FS_CONFLICT,
      $SVN::Error::FS_ALREADY_EXISTS,
      $SVN::Error::FS_NOT_DIRECTORY,
      $SVN::Error::FS_NOT_FILE,
      $SVN::Error::FS_NOT_FOUND,
      $SVN::Error::FS_NO_SUCH_ENTRY,
      $SVN::Error::FS_PATH_SYNTAX,
      $SVN::Error::FS_NOT_SINGLE_PATH_COMPONENT,
      $SVN::Error::FS_ROOT_DIR,
      $SVN::Error::FS_NO_SUCH_COPY;

  return exception($addcr->($error->message), 111);
}

sub _get_csid_from_rev {
  my ($self, $rev) = @_;
  return $self->_rev2csid->get($rev);
}

sub _get_cs_from_rev {
  my $pool = SVN::Pool->new_default(undef);
  my ($self, $rev) = @_;
  my $metapath = $self->_metapath_from_rev($rev) or return undef;
  my $revroot = $self->_repo->fs->revision_root($rev);
  my $stream = $revroot->file_contents($metapath);
  return Change::Set->new(slurp($stream));
}

sub _metapath_from_rev {
    my $pool = SVN::Pool->new_default(undef);
    my ($self, $rev) = @_;
    my $revroot = $self->_repo->fs->revision_root($rev);
    my $metapath = $self->_metapath_from_changes($revroot->paths_changed);

    warn "Error finding changeset metadata in revision $rev.\n"
	if not defined $metapath;

    return $metapath;
}

sub _metapath_from_changes {
    my ($self, $changes) = @_;
    my $changeplace = getMetaChangeBasePath();
    my $metachanges = { map { ( $_ => $changes->{$_} ) }
	grep !m{\.status$},
	     grep m#^$changeplace/././[A-F0-9]{18}#, keys %$changes };

    if (not %$metachanges) {
	warn "No changeset metafile file\n";
	return;
    }
    if (keys %$metachanges > 1) {
	warn "Multiple changeset metafiles found.\n"; 
	return;
    }

    my ($metapath, $changekind) = %$metachanges;

    # it is important that changeset metafiles, once added, are never
    # touched again--otherwise we lose 1-1 mapping between csids and revs
    if ($changekind->change_kind != $SVN::Fs::path_change_add) {
	warn "Changeset metafile not treated as immutable.\n"; 
	return;
    }

    return $metapath;
}

sub _get_rev_from_csid {
  my ($self, $csid) = @_;
  return $self->_csid2rev->get($csid);
}

sub _resolve_branch {
  my ($self, $movealias) = @_;
  my $branchmap = $self->_branchmap;
  my $movetypes = \%Meta::Change::Places::MOVE_TYPES;

  return $movealias unless exists $movetypes->{$movealias};
  my $move = $movetypes->{$movealias};
  return $branchmap->{$move} if exists $branchmap->{$move};
  return $move;
}

sub _branchmap {
  my ($self) = @_;

  # FIXME: excise - branch bind at client layer using branch tracking
  # facility. work with full repository paths throughout this module.
  return { qw(dev 3 bf 2 em 1 stpr 1) };

  my $mappath = getBranchmapPath();
  my $mapfh = $self->_export_fh($mappath);
  my %map;

  while (<$mapfh>) {
    chomp;
    $map{$1} = $2 if /^(\S+)\s+(\S+)$/;
  }

  return \%map;
}

sub _check_path {
  my ($self, $path, %arg) = @_;
  my $rev = $arg{rev} || $self->_headrev();
  my $revroot = $self->_repo->fs->revision_root($rev);
  return $revroot->check_path($path);
}

sub _export_file {
    my $pool = SVN::Pool->new_default(undef);
    my ($self, $frompath, $topath, %arg) = @_;

    my ($fromfh, $executable) = $self->_export_fh($frompath, %arg)
	or return undef;

    my $tofh;
    if (not ref $topath) {
	open $tofh, '>', $topath
	    or die "Error opening $topath for write: $!";
    } else {
	$tofh = $topath;
    }

    _make_executable($tofh) or warn "Failed to a+x $topath: $!"
	if $executable;

    return slurp($fromfh, $tofh);
}

# NOTE: uses current default pool, as returned SVN::Stream needs one
sub _export_fh {
  my ($self, $path, %arg) = @_;
  my $revroot = $arg{revroot} ||
    $self->_repo->fs->revision_root($arg{rev} || $self->_headrev);
  my $stream = $revroot->file_contents($path);
  my $executable = $revroot->node_prop($path, 'svn:executable');

  return ($stream, $executable);
}

sub _update_tsp {
  my ($self, $path, $rev) = @_;

  my (undef, $info) = $self->commit_info(rev => $rev);
  (my $iso = $info->{'scm:date'}) =~ s/T(.+?)\..*/ $1/;

  # scm:date-property is in GMT
  my $tsp = HTTP::Date::str2time($iso, 'GMT');
  utime($tsp, $tsp, $path);
}

# use with caution! head rev can be changed at any time unless
# serialized commits are enforced externally

sub _headrev {
  my $pool = SVN::Pool->new_default(undef);
  my $self = shift;
  return $self->_repo->fs->youngest_rev;
}

sub _headroot {
  my $self = shift;
  return $self->_repo->fs->revision_root($self->_headrev);
}

sub _repo { return shift->_member('repo', @_); }
sub _repospath { return shift->_member('repospath', @_); }
sub _pool { return shift->_member('pool', @_); }
sub _rev2csid { return shift->_member('rev2csid', @_); }
sub _csid2rev { return shift->_member('csid2rev', @_); }
sub _branchinfo { return shift->_member('branchinfo', @_); }
sub _commitinfo { return shift->_member('commitinfo', @_); }

sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}

sub _make_executable {
  my $thing = shift;

  require Fcntl;

  my $exbits  = &Fcntl::S_IXUSR|&Fcntl::S_IXGRP|&Fcntl::S_IXOTH;
  my $perms   = (stat($thing))[2] | $exbits;

  chmod $perms => $thing
    or return;

  return 1;
}

1;

__END__

=head1 NAME

SCM::Repository - Perl interface to the robocop repository.

=head1 SYNOPSIS

  use SCM::Repository;
  
  my $rep = SCM::Repository->new(
     repository_path => '/path/to/repository',
  );

  my $cs = Change::Set->new( ... );

  $rep->submit($cs);
    
=head1 DESCRIPTION

This module implements an interface to the main source code repository.

The main unit of exchange is the Change Set (CS).  Most operations target a
particular development branch (DB).  This terminology may change later.

=head1 METHODS

=head2 new( [OPTIONS] )

Create a new Repository object. Options are:

=over 4

=item * repository

A string specifying the name of the repository

=item * repository_root

A string specifying the path to the repository's root.

=back

If I<OPTIONS> are not specified, some defaults are assumed.

=head2 submit( $cs )

Record a CS I<$cs> for posterity.

=head2 current( $move_type )

Return the designated current DB for the stated I<$move_type>.

=head2 validate( $db, $cs )

Validate I<$cs> in the context of <$db>.

=head2 commit( $db, $csid )

Update changes to I<$db> and mark as coming from <$cs> with I<$csid>.

=head2 ($result, $cs) = revert( $db, @cs )

Attempt to remove the updates I<@cs> from I<$db>. Fails if I<$db> does not
contain I<@cs> or if an intervening CS overlaps. Success creates a new I<$db2>
that differs from I<$db> by I<@cs>. May operate by early branch followed by
reapplication of intervening CSs or by application of reverse update.

Returns a two element list, the first element being the result of the operation
and the second element the new change set.

Assume changesets CS1 .. CSn.  If we want to revert CSa, CSb, CSc (properly
ordered), is rolling back and reappling intermediates always equivalent to
applying reverse changes in reverse order?  If the rollback and retention
sets are disjoint, restrict the view to those files touched by the rollback
set, where the roll forward consists only of the rollback set.  Therefore
they are equivalent.

Consider a single-file, fname and two updates, CS1 and CS2.  Is rollback
plus application of CS2 always equivalent to application of a reverse diff
of CS1?  If the two are disjoint within the file, then in principle the two
methods are equivalent.

Always attempt a reverse merge.  Return the result and the new CS.  If it
fails, merge is required.

=head2 branch( $db, $cs )

Create a new DB by branching before CS I<$cs>.

=head2 merge( $db, $cs )

Merge the selected change set into DB I<$db>.  This may require user
interaction.

=head2 history( $db, $limit )

Fetch the CS history of $db, up to $limit items, 0 means no limit.  Allow limit
to current status?

=head1 EXPORT

None.

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

William Baxter, E<lt>wbaxter1@bloomberg.netE<gt>

Alan Grow, E<lt>agrow@bloomberg.netE<gt>

Tassilo von Parseval, E<lt>tvonparseval@bloomberg.netE<gt>

=cut
