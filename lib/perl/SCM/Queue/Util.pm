# vim:set ts=8 sts=4 sw=4 noet:

package SCM::Queue::Util;

use warnings;
use strict;

use base qw/Exporter/;

use File::Spec;
use File::Temp              qw/tempdir tempfile/;
use Fcntl                   qw/O_WRONLY O_EXCL O_CREAT/;

use SCM::Symbols	    qw/SCM_REPOSITORY
			       $SCM_QUEUE
                               $SCM_DIR_PREQUEUE
                               $SCM_DIR_QUEUE
			       $SCM_DIR_OFFLINE
			       $SCM_DIR_PENDING
			       $SCM_DIR_INPROG
                               $SCM_DIR_DATA
                               $SCM_DIR_REJECT
                               $SCM_DIR_FAIL
                               $SCM_DIR_DONE
                               $SCM_DIR_ABANDON
                               $SCM_DIR_SWEPT/;
use SCM::Queue::Job;
use Change::Util            qw/hashCSID2dir/;
use Util::Message           qw/fatal error/;
use Change::Util::Bundle    qw/bundleChangeSet unbundleChangeSet/;
use Change::Symbols         qw/FILE_IS_UNCHANGED/;

our @EXPORT_OK = qw/get_queued_jobs 
                    csid_to_cs have_completed not_completed get_staged_jobs
                    get_staged_files get_sweep_targets get_job_csid_hash
		    get_job_by_csid parse_filelist
		    get_job_csid_by_move_hash
		  /;

# Call closure on each file in queue.
# Missing closure is fatal.
# $_[0] gives the queue root.
# $_[1] gives a closure for iteration.
# Tail of arguments gives the list of subdirs.
# Return -1 and complain if dir read fails.
# Return 1 if all op calls do the same.
# Return 2 with short circuit if closure returns 2.
# Return 0 otherwise.
# Empty subdir list is trivial success.
# Op takes (subdir,file) pair as arguments.
# NB: Do not assume that each file is a job file.
# Should implement short-circuit return.
sub iterate_job_dirs {# op, basedir, subdir ...
    my ($op,$basedir,@subdirs) = @_;
    $basedir = $SCM_QUEUE if not defined $basedir;
    $op  or  fatal "Missing op in iterate_job_list";

    my $result = 1;
    for my $subdir (@subdirs) {
        my $dir = File::Spec->catdir($basedir, $subdir);
        opendir my $dirh, $dir or do {
	    error "Could not open directory '$dir': $!";
	    return -1;
	};
        while (my $next = readdir $dirh) {
            $op->($dir, $next) == 2  and  return 2;
            $op->($dir, $next)  or  $result = 0;
        }
    }
    return $result;
}

# All submissions not yet committed.
my @enqueued_dirs = (
    $SCM_DIR_PREQUEUE, $SCM_DIR_QUEUE,
    $SCM_DIR_PENDING, $SCM_DIR_INPROG,
    $SCM_DIR_OFFLINE,
);

# All submissions not yet swept into RCS.
my @staged_dirs = (
    @enqueued_dirs, $SCM_DIR_DONE,
);

sub get_job_list {# basedir, subdir ...
    my @files;
    my $op = sub { my($d,$f) = (shift,shift);
		   push(@files,File::Spec->catfile($d,$f));
		   return 1;
		 };
    if (iterate_job_dirs($op,@_) < 0) {
	fatal "cannot get_job_list";
    }
    return \@files;
}

sub get_job_csid_hash {# basedir, subdir ...
    my %jobs;
    my $op = sub { my ($d,$f) = (shift,shift);
		   my ($csid) = SCM::Queue::Job::parse_filename($f)
		       or  return 1;
		   $jobs{$csid} = File::Spec->catfile($d,$f);
		   return 1;
		 };
    if (iterate_job_dirs($op,@_) < 0) {
	fatal "cannot get_job_csid_list";
    }
    return \%jobs;
}

sub get_job_csid_by_move_hash {# basedir, subdir ...
    my %jobs;
    my $move = shift;
    my $op = sub { my ($d,$f) = (shift,shift);
		   my ($csid) = SCM::Queue::Job::parse_filename($f)
		       or  return 1;
		   my $file = File::Spec->catfile($d,$f);
		   my $job = SCM::Queue::Job->new($file);
		   return if $job->cs->getMoveType ne $move;
		   $jobs{$csid} = $file;
		   return 1;
		 };
    if (iterate_job_dirs($op, @_) < 0) {
	fatal "cannot get_job_csid_list";
    }
    return \%jobs;
}

sub get_queue_by_csid {# basedir
    my $basedir = shift;
    $basedir = $SCM_QUEUE if not defined $basedir;
    return get_job_csid_hash($basedir,@enqueued_dirs);
}

sub get_queued_job_files {
    my $basedir = shift;
    $basedir = $SCM_QUEUE if not defined $basedir;
    my $jobs = get_job_csid_hash($basedir,@enqueued_dirs);
    return map $jobs->{$_}, sort keys %$jobs;
}

sub get_jobs {# basedir, subdir ...
    my %jobs;
    my $op = sub { my ($d,$f) = (shift,shift);
		   my ($csid) = SCM::Queue::Job::parse_filename($f)
		      or  return 1;
		   my $file = File::Spec->catfile($d, $f);
		   my $j = eval { SCM::Queue::Job->new($file); };
		   $@  or  $jobs{$file} = $j;
		   return 1;
		 };
    if (iterate_job_dirs($op,@_) < 0) {
	fatal "cannot get_jobs";
    }
    return map $jobs{$_}, sort keys %jobs;
}

sub get_queued_jobs {# basedir
    my $basedir = shift;
    $basedir = $SCM_QUEUE if not defined $basedir;
    return get_jobs($basedir,@enqueued_dirs);
}

sub get_staged_jobs {
    my $basedir = shift;
    $basedir = $SCM_QUEUE if not defined $basedir;
    return get_jobs($basedir,@staged_dirs);
}

sub not_completed {
    my @csid = @_;
    my $job = get_queue_by_csid();
    
    @csid = grep (exists($job->{$_}) => @csid);
    return @csid;
}

# Obsolete: do not use.
sub have_completed {
    my @csid = @_;
    my @dirs = ($SCM_DIR_PREQUEUE, $SCM_DIR_QUEUE, $SCM_DIR_PENDING, $SCM_DIR_INPROG);

    my $pattern = '{' . join(',', map "$SCM_QUEUE/$_", @dirs) . '}/' .
                  '{' . join(',', @csid) . '}*';

    my @found = glob $pattern;
    return @found == 0;
}

sub csid_to_cs {
    my ($csid, $basedir) = @_;

    $basedir = $SCM_QUEUE if not defined $basedir;

    my $csfile = File::Spec->catfile($basedir, $SCM_DIR_DATA, hashCSID2dir($csid), $csid);

    return if not -e $csfile;

    my $cs = Change::Set->new({});
    my $tempdir = tempdir(CLEANUP => 0);

    unbundleChangeSet($cs, $csfile, $tempdir);

    return $cs;
}

sub get_staged_files {
    my $basedir = shift;

    $basedir = $SCM_QUEUE if not defined $basedir;

    my @jobs = get_staged_jobs($basedir);
    my %files;
    for my $job (@jobs) {
        $files{$_->getDestination} = $_->getType for $job->cs->getFiles;
    }
    return \%files;
}

sub get_sweep_targets {
    my ($movetype, $basedir) = @_;

    $basedir = $SCM_QUEUE if not defined $basedir;

    my %files;
    my $f = File::Spec->catfile($basedir, $SCM_DIR_DONE, "FILELIST.$movetype");
    open my $fh, '<', $f or fatal "Could not open $f: $!";
    while (<$fh>) {
	my ($csid, $file) = split /\t/;
	next if not defined $file;
	$files{$file} = $csid;
    }

    return \%files;
}

sub get_job_by_csid {
    my ($csid, $dirs, $basedir) = @_;

    $basedir = $SCM_QUEUE if not defined $basedir;

    my @dirs = ref($dirs) eq 'ARRAY' 
                    ? (@$dirs)
                    : (@staged_dirs);

    my $job;
    my $op = sub { 
        my ($d,$f) = (shift,shift);
        my ($job_csid) = SCM::Queue::Job::parse_filename($f) or return 1;# next
        $job_csid eq $csid  or  return 1;# next
        my $file = File::Spec->catfile($d, $f);
        my $j = eval { SCM::Queue::Job->new($file); };
        $@ and return 0;# next, error
        $job = $j;
        return 2;# done
    };
    if (iterate_job_dirs($op, $basedir, @dirs) < 0) {
	fatal "cannot get_job_by_csid";
    }
    return $job;
}

sub parse_filelist {
    my ($move, $basedir) = @_;

    $basedir = $SCM_QUEUE if not defined $basedir;

    my $filelist = File::Spec->catfile($basedir, $SCM_DIR_DONE, 
				       "FILELIST.$move");

    open my $fh, '<', $filelist or fatal "Cannot open $filelist: $!";

    my %files;
    local *_;
    while (<$fh>) {
	chomp;
	my ($csid, $file) = split or next;
	$files{$file} = $csid;
    }

    return \%files;
}

1;
__END__

=head1 NAME

SCM::Queue::Util - Auxiliary functions for queue management and handling

=head1 SYNOPSIS

    use SCM::Queue::Util qw/get_queued_jobs 
                            unlock_queue/;

    my @jobs = get_queued_jobs;

=head1 FUNCTIONS

=head2 get_queued_jobs( [$dir] )

Returns the list of jobs currently in the queue which has its base-directory in I<$dir>.
I<$dir> defaults to I<SCM_QUEUE> if not specified.

=head2 get_most_recent_versions( $movetype, @files )

Returns the name of a tarball which contains the most recent versions of the
files in I<@files>, for a given movetype I<$movetype>.

If any file in I<@files> does not exist in a change set inside the queue, it
grabs the most recent version of that file from the repository.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
