package Util::File::NFSLock;

use strict;
use Symbol ();
use Sys::Hostname ();
use Util::Message qw(warning debug3);

#==============================================================================

=head1 NAME

Util::File::NFSLock - lockfile implementation (NFS-safe)

=head1 SYNOPSIS

    use Util::File::NFSLock;

    safe_nfs_signal_traps();

    my $lockfile = "/safe_location/my_lockfile";
    my $unlockfile;
    eval {
      local $SIG{ALRM} = sub { die "alarm\n" };
      alarm(15);
      $unlockfile = safe_nfs_lock($lockfile)
        || warn("unable to obtain lock: $!");
      alarm(0);
    }
    if (defined($@) && $@ ne '') {
	die $@ unless ($@ eq "alarm\n";
        # else timed out
    }

    ...

    safe_nfs_unlock($unlockfile);

=head1 DESCRIPTION

C<Util::File::NFSLock> manages a lockfile in an NFS-safe manner using hard
links

=head1 NOTE

This module will transition to an object class in the next interation.

=cut

#==============================================================================

=head2 safe_nfs_lock()

Creates an NFS-safe lock on the given file.  Takes a path as an argument.
Caller should set an alarm() or some timer around this routine.
Returns token to pass to C<safe_nfs_unlock()> to unlock the file.
Returns undef upon failure.  Note: the file pointed at is created if needed,
and is not removed by C<safe_nfs_unlock()>.  The lock filename should be
taint-safe if running in tainted mode.

=cut

#------------------------------------------------------------------------------

{ # untaint and cache hostname
  my $hostname = "";
  sub _hostname () {
    return ($hostname ne "")
      ? $hostname
      : (Sys::Hostname::hostname() =~ /^([\w-]+)$/)
	  ? ($hostname = $1)
	  : ($hostname = "");
  }
}

sub safe_nfs_lock ($;$) {
return 1;
    my $lockfile = $_[0];
    my $locklink = join('.', $lockfile, _hostname(), $$, $^T); # ok
    $locklink .= ".".$1     # (caller-defined optional tag)
      if (defined($_[1]) && $_[1] =~ /^([\w.-]+)$/);

    my $link_count;
    my $retry_count = 0;
    do {
	## Use stat() on file instead of slightly faster fstat() on filehandle,
	## because stat() on file not open()ed is more robust for link locks.
	## Do not keep open the lockfile since that might lead to .nfsXXXX hard
	## links being left around by NFS clients, which rename the locklink
	## to .nfsXXXX if the file is open by another process, and then might
	## not properly clean up the .nfsXXXX file, leaving around the hard link

	unless (-e $lockfile) {
	    my $LK = Symbol::gensym;
	    open($LK, '>'.$lockfile) and close($LK)
	      || (warning("open $lockfile: $!"), return undef);
	}

	link($lockfile, $locklink);      # (ignore return value from link call)
	stat($lockfile)
	  || (warning("stat $lockfile: $!"),
	      unlink($locklink) || warning("unlink $locklink: $!"),
	      return undef);
	$link_count = (stat _)[3];

	return (new Util::File::NFSLock($locklink))
	  if ($link_count == 2 && -e $locklink);
	  # exactly two links and the second link is ours: good!

	$link_count > 1 && -e $locklink
	  ? unlink $locklink
	      || (warning("unlink $locklink: $!"), return undef)
	  : warning("unable to create $locklink; retrying");
	if (($retry_count++ & 7) == 0) {
	    warning("Waiting for lock ...");
	    debug3("safe_nfs_lock(): "
		  ."hard-link count ($link_count) on $lockfile");
	    if (-s $lockfile) {
		local $/ = undef;
		my $FH = Symbol::gensym;
		open($FH,'<'.$lockfile) && warning(<$FH>);
	    }
	}
	sleep(1 + ($retry_count >> 5)) if ($retry_count > 15);
	select(undef,undef,undef,rand);  # sleep random amount: [0,1) second
    } while (1);
}

#------------------------------------------------------------------------------

=head2 safe_nfs_unlock()

Unlocks a lock created by C<safe_nfs_lock()>
Returns true on success, false on failure.

=cut

#------------------------------------------------------------------------------

sub safe_nfs_unlock ($) {
return 1;
    my $locklink = delete $_[0]->{locklink};
    ##<<<TODO: quick fix; not sure why this is tainted after what is
    ##         done in safe_nfs_lock()
    $locklink=~/^(.*)$/ and $locklink=$1;

    unlink($locklink)
      ? return 1
      : (warning("unlink $locklink: $!"), return 0);

}

sub new ($$) {
    my $class=(ref $_[0]) || $_[0];
    return bless {
        lockpid => $$,
        starttime => $^T,
        locklink => $_[1]
    },$class;
}

sub DESTROY {
    $_[0]->safe_nfs_unlock()
      if exists($_[0]->{locklink}) and $$==$_[0]->{lockpid}
	and $^T==$_[0]->{starttime};
}

#------------------------------------------------------------------------------

=head2 safe_nfs_signal_traps()

Convenience routine to set up simple signal handlers for SIGTERM and SIGINT 
so that lock is cleaned up automatically at program termination due to these
signals.  Do not call this routine if you are catching these signals yourself.
This signal handler catches SIGINT and SIGTERM and then calls exit(1).

=cut

sub safe_nfs_signal_traps {
    $::SIG{INT} = $::SIG{TERM} = sub { exit 1; };
}

#==============================================================================

=head1 AUTHOR

Glenn Strauss (gstrauss1@bloomberg.net)

=cut

1;
