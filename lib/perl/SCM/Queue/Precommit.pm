# vim:set ts=8 sts=4 noet:

package SCM::Queue::Precommit;

use strict;
use warnings;

use base qw/SCM::Queue/;

use File::Spec;
use List::Util		    qw/shuffle/;

use Util::Message	    qw/error fatal debug/;
use Util::File::Functions   qw/ensure_path/;

use Change::Symbols	qw/$STATUS_ACTIVE $STATUS_COMPLETE $STATUS_INPROGRESS
			   $STATUS_ROLLEDBACK $STATUS_REINSTATED
			   DEPENDENCY_TYPE_ROLLBACK DEPENDENCY_TYPE_CONTINGENT/;
use Production::Symbols	qw/BUILD_ONLY_MACHINES/;
use SCM::Symbols	qw/SCM_DIR_PRECOMMIT $SCM_DIR_PRECOMMIT
			   SCM_DIR_COMPILE_OK
			   SCM_DIR_COMPILE_FAIL
			   SCM_DIR_COMPILE_LOGS
			   SCM_DIR_COMPILE_RB
			   SCM_TMP
			   SCM_CSDB SCM_CSDB_DRIVER/;
use SCM::Queue::Job;
use Task::Scheduler;

our $VERSION = '0.01';

my $CSCOMPILE = '/bbsrc/bin/beta/cscompile';

Util::Message::set_debug(1);

sub new {
    my ($class, $basedir, %args) = @_;

    my $self = $class->SUPER::new($basedir);
    $self->concurrency(defined $args{concurrency} ? $args{concurrency} : 1);

    return $self;
}

sub concurrency {
    my $self = shift;
    return $self->{concurreny} if not @_;
    $self->{concurrency} = shift;
}

sub run {
    my $self = shift;
  
    my @jobs = sort by_timestamp $self->get_jobs(SCM_DIR_PRECOMMIT); 

    my @compile;
    for my $job (@jobs) {
	my $status = $self->get_dbstatus($job);
	$job->change_status($status) if not $@ and $status ne $job->status;
	$job->move_to(File::Spec->catfile($self->basedir, SCM_DIR_COMPILE_RB))
	    if $job->status eq $STATUS_ROLLEDBACK ||
	       $job->status eq $STATUS_REINSTATED;
	push @compile, $job 
	    if ($job->status eq $STATUS_ACTIVE ||
		$job->status eq $STATUS_INPROGRESS ||
		$job->status eq $STATUS_COMPLETE) and $self->deps_done($job);
    }

    my $do_tests = sub {
	my $job = shift;

	$job->change_execpid($$);

	my $target;
	if ($self->compiles_ok($job)) {
	    $target = File::Spec->catdir($self->basedir, SCM_DIR_COMPILE_OK);
	} else {
	    $target = File::Spec->catdir($self->basedir, SCM_DIR_COMPILE_FAIL);
	}
	debug("Move ", $job->name, " to '$target'");
	$job->move_to($target);
	exit 0;
    };

    Task::Scheduler->new(
	slots	    => $self->concurrency,
	data	    => \@compile,
	job	    => $do_tests,
	abnormal    => sub {
	    my $job = shift;
	    fatal("Gripe when trying to compile " . $job->id);
	},
    )->run;
}

sub by_timestamp { 
    $a->timestamp <=> $b->timestamp;
}

sub compiles_ok {
    my ($self, $job) = @_;
   
    # rcp bundle to /bb/csdata/scm/tmp.
    # We use job-filename as directory as it is guaranteed to be unique.
    require SCM::Util;
    my $remote_bundle_path = File::Spec->catdir(SCM_TMP, $job->name);
    my $local_bundle_path = SCM::Util::getBundlePath($job->id);

    my @hosts = shuffle(split /,/, BUILD_ONLY_MACHINES);

    my $ran;
    HOST:
    for my $host (@hosts) {
	my @rcp = (qw/rcp/, $local_bundle_path, "$host:$remote_bundle_path");
	if (system(@rcp) != 0) {
	    error("Could not successfully run: @rcp");
	    next HOST;
	}

	my $cmd = "ssh -2 $host $CSCOMPILE -ddd -vvv --compiletype cb2 -LLoadBundle " . 
		  "--from $remote_bundle_path 2>&1";

	my $logpath = $self->logpath($job->name); 
	warn "running $cmd. Logs in $logpath\n";

	open my $logfh, '>', $logpath
	    or error("Opening $logpath failed: $!");
	open my $cscompile, '-|', $cmd
	    or do {
		error("Could not pipeopen $cmd: $!"); 
		return 0;
	    };

	my $start = time;
	print $logfh $_ while <$cscompile>;
	my $end = time;

	print $logfh "\n", $end - $start, " seconds\n";

	if (not close $cscompile) {
	    error("Could not successfully run: $cmd");
	    my $rc = $? >> 8;
	    next HOST if $rc == 255;
	    return 0;
	} else {
	    return 1;
	}
    }

    # if we get here, we are seriously screwed: No build machine reachable
    fatal("None of the build-machines up");
}

sub logpath {
    my ($self, $job) = @_;

    my ($month, $year) = (localtime)[4,5];

    $month = sprintf "%02i", $month + 1;
    $year += 1900;

    my $dir = File::Spec->catdir($self->basedir, SCM_DIR_COMPILE_LOGS, $year, $month);
    ensure_path($dir);
    return File::Spec->catfile($dir, $job . '.log');
}

{
    my $csdb;
    sub deps_done {
	my ($self, $job) = @_;

	require SCM::CSDB::ChangeSet;
	$csdb     ||= SCM::CSDB::ChangeSet->new(database => SCM_CSDB, driver => SCM_CSDB_DRIVER);
	my $deps    = $csdb->getChangeSetDependencies($job->id);
	my @depids  = map { $deps->{$_} eq DEPENDENCY_TYPE_CONTINGENT ? $_ : () } keys %$deps;

	return 1 if not @depids;

	my $ids = '{' . join(',' => @depids) . '}';

	# if the number of entries is zero, they've all test-compiled
	my @found = glob $self->basedir . "/$SCM_DIR_PRECOMMIT/$ids*";
	return @found == 0;
    }
}

1;

=head1 NAME

SCM::Queue::Precommit - The precommit (pessimistic compile test) daemon

=head1 DESCRIPTION

This daemon's responsibility is to pick up all jobs from I<SCM_DIR_PENDING>
and trigger processes to run test on each job.

Once the test are done, the job is moved to either I<SCM_DIR_PENDING> (in case
the job passed the tests) or I<SCM_DIR_REJECT>.

=head1 CONSTRUCTOR

=head2 new( $basedir, [ concurrency => $num ] )

Constructs a new daemon object which will work on the queue system to be found
in I<$basedir>.

g<concurrency> is the maximum number of parallel jobs to run tests.

=head1 METHODS

=head2 run()

Triggers one run of the daemon. In order to turn this into a long running process, you'll have
to keep calling thsi method continuously, for example thusly:

    my $inc = SCM::Queue::Testing->new( $BASEDIR );

    while () {
	$inc->run;
	select undef, undef, undef, 1;
    }

=head1 SEE ALSO

L<SCM::Symbols>, L<SCM::Queue>, L<SCM::Queue::Job>, L<SCM::Queue::Prequeue>, L<SCM::Queue::Commit>

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
