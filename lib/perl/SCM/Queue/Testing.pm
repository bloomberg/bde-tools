# vim:set ts=8 sts=4 noet:

package SCM::Queue::Testing;

use strict;
use warnings;

use base qw/SCM::Queue/;

use Fcntl qw/O_WRONLY O_NONBLOCK/;
use File::Spec;

use Util::Message   qw/error fatal debug/;

use Util::Trigger   qw/triggerPull/;
use SCM::Symbols    qw/SCM_DIR_QUEUE 
		       SCM_DIR_PENDING 
		       SCM_DIR_DONE
		       SCM_DIR_TERM
		       SCM_DIR_REJECT
		       SCM_DIR_PRECOMMIT
		       SCM_COMMIT_TRIGGER
		       SCM_PRECOMMIT_TRIGGER
		       SCM_PRIO_EMERGENCY
		       SCM_PRIO_DEVCHANGE
		       SCM_PRIO_IMMEDIATE/;
use SCM::Queue::Job;
use Task::Scheduler;
use SCM::Util       qw/part firstidx/;

our $VERSION = '0.01';

Util::Message::set_debug(1);

sub new {
    my ($class, $basedir, %args) = @_;

    my $self = $class->SUPER::new( $basedir );
    $self->concurrency( defined $args{ concurrency } ? $args{ concurrency } : 4 );

    return $self;
}

sub concurrency {
    my $self = shift;
    return $self->{concurreny} if not @_;
    $self->{concurrency} = shift;
}

sub run {
    my $self = shift;
  
    # they will be in priority order
    my @jobs = sort by_timestamp $self->get_jobs( SCM_DIR_QUEUE ); 

    for my $job (@jobs) {
	my $status = $self->get_dbstatus($job);
	$job->change_status($status) if not $@ and $status;
    }

    # partition them into priorities
    my @jobs_by_prio = part { $_->priority } @jobs;
     
    my @priorities;
    for my $prio (SCM_PRIO_EMERGENCY .. SCM_PRIO_DEVCHANGE) {
	next if ! $jobs_by_prio[ $prio ];
	my @ary = @{ $jobs_by_prio[$prio] }; 
	for my $idx (0 .. $#ary) {
	    push @{ $priorities[ $prio ] }, [ @ary[ $idx .. $#ary ] ];
	}
    }	
    
    # flatten @priorities again:
    # this involves pushing the whole content of pending/ onto each sublist
    my @pending = sort by_timestamp $self->get_jobs( SCM_DIR_PENDING );
    my @contextes;
    for my $p (@priorities) {
	for my $c (@$p) {   # loop over jobs
	    push @contextes, [ @$c, @pending ];	# the job-lists are prolonged with jobs in pending
	}
    }

    my $do_tests = sub {
	my ($job, @context) = @{ +shift };

	$job->change_execpid( $$ );

	my $target;
	if ( $self->do_tests($job, @context) ) {
	    $target = File::Spec->catdir( $self->basedir, SCM_DIR_PENDING );
	} else {
	    $target = File::Spec->catdir( $self->basedir, SCM_DIR_REJECT );
	}
	# we only move the head of @jobs in order to not move redundantly
	debug("Move ", $job->name, " to '$target'");

	$job->copy_to(File::Spec->catdir($self->basedir, SCM_DIR_PRECOMMIT))
	    or error("Could not move to " . SCM_DIR_PRECOMMIT . ": $!");
	$job->move_to($target);

	exit 0;
    };

    my $termhandler = sub {
	my ($job, @context) = @{ +shift };
	# move back to queue/
	my $dest = File::Spec->catdir( $self->basedir, SCM_DIR_TERM );
	$job->move_to( $dest );
	exit 0;
    };
    my $huphandler = sub {
        my ($job) = shift->[0];
        exit 0;
    };
    my $abnormalhandler = sub {
	my $job = shift;
	my $dest = File::Spec->catdir( $self->basedir, SCM_DIR_REJECT );
	$job->move_to( $dest );
	# NO EXIT HERE! The abnormal handler is run by the parent
    };

    
    Task::Scheduler->new(
	slots	    => $self->concurrency,
	data	    => \@contextes,
	job	    => $do_tests,
	sighandlers => {
	    TERM    => $termhandler,
	    HUP	    => $huphandler,
	},
	abnormal    => $abnormalhandler,
    )->run;

    # filter out imoves and move them to pending/ straight away
    my @imoves;
    if ((my $idx = firstidx { $_->priority == SCM_PRIO_IMMEDIATE } @jobs) > -1) { 
	@imoves = splice @jobs, $idx;
    }

    for (@imoves) {
	$_->copy_to(File::Spec->catdir($self->basedir, SCM_DIR_PRECOMMIT))
	    or error("Could not copy to " . SCM_DIR_PRECOMMIT . ": $!");
	$_->move_to(File::Spec->catdir($self->basedir, SCM_DIR_PENDING));
    }

    debug_jobs(@jobs);
    
    triggerPull(SCM_COMMIT_TRIGGER);
    triggerPull(SCM_PRECOMMIT_TRIGGER);
}

sub by_timestamp { 
    $a->timestamp <=> $b->timestamp;
}

=pod
sub do_precursor {
    my ($self, $pre, $jobs, $downstream) = @_ ;
    
    for my $job (@$jobs) {
	$pre->{ $job->name } = {
	    me	=> $job,
	    pre	=> [],
	} if not exists $pre->{ $job->name };
    	CANDIDATE: for my $c (@$downstream) {
	    debug("checking candidate " . $c->name . " in " . $c->dir);
	    if (any { $job->hasFile($_)  } $c->getFiles) {
		push @{ $pre->{$job->name}->{pre} }, $c;
		debug($c->name . " is precursor");
		next CANDIDATE;
	    }
	}
	debug("done checking precursors for " . $job->name);
    }
}

sub pre_inqueue {
    my ($self, $job) = @_;
   
    debug("checking precursors still in queue for ", $job->name);

    my $pre = $self->pre->{ $job->name }->{pre};
    
    my @dirs = map File::Spec->catdir( $self->basedir, $_ ),
		   SCM_DIR_QUEUE, SCM_DIR_STAGING, SCM_DIR_PENDING, SCM_DIR_RUN;

    for my $p (@$pre) {
	return 1 if any { debug("checking ", $p->dir, " eq $_"); $p->dir eq $_ } @dirs;
    }

    return 0;
}

sub depends_ok {
    my ($self, $job) = @_;
    
    my $deps = $self->pre->{$job->name}->{pre} || [];
    debug("testing dependencies for ", $job->name, ": ", join ", ", map $_->name, @$deps);
    return 1 if not @$deps;
    
    my $done = File::Spec->catdir( $self->basedir, SCM_DIR_DONE );
    
    return 1 if all { $_->dir eq $done } @$deps;
    return 0;
}
=cut

sub do_tests {
    my ($self, $job, @context) = @_;

    # FIXME
    # Call cscompile here similar to how cscheckin does it

    return 1;
}
    

sub debug_jobs {
    for (@_) {
	debug("found " . $_->name . " in " . $_->dir);
    }
}

1;

=head1 NAME

SCM::Queue::Testing - The testing daemon

=head1 DESCRIPTION

This daemon's responsibility is to pick up all jobs from I<SCM_DIR_PENDING>
and trigger processes to run test on each job.

Once the test are done, the job is moved to either I<SCM_DIR_PENDING> (in case
the job passed the tests) or I<SCM_DIR_REJECT>.

=head1 CONSTRUCTOR

=head2 new( $basedir, [ concurrency => $num ] )

Constructs a new daemon object which will work on the queue system to be found
in I<$basedir>.

I<concurrency> is the maximum number of parallel jobs to run tests.

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
