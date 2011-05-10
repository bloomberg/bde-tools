package SCM::Queue::Commit;

use strict;
use warnings;

use base qw/SCM::Queue/;

use File::Spec;

use Change::Symbols         qw/STATUS_ACTIVE STATUS_ROLLEDBACK $STATUS_ROLLEDBACK
                               $STATUS_WITHDRAWN STATUS_COMPLETE $STATUS_REINSTATED
                               STATUS_REINSTATED STATUS_INPROGRESS STATUS_WAITING
                               DEPENDENCY_TYPE_ROLLBACK
                               DEPENDENCY_TYPE_CONTINGENT
                               DEPENDENCY_TYPE_DEPENDENT/;
use SCM::Symbols	    qw/SCM_REPOSITORY
			       SCM_DIR_PENDING SCM_DIR_ABANDON 
			       SCM_DIR_DONE SCM_DIR_FAIL 
			       SCM_DIR_INPROG/;

use Util::Message	    qw/fatal error debug warning/;
use SCM::Util		    qw/getBundlePath generateDiffReport/;
use SCM::Queue::Util        qw/not_completed/;
use SCM::Repository;

our $VERSION = '0.01';

my $MAX_COMMITS = 24;

sub run {
    my $self = shift;

    # This daemon is single threaded.  Material in SCM_DIR_INPROG
    # must be left over from a previous run.  Push them back to PENDING.
    my @jobs = $self->get_jobs( SCM_DIR_INPROG );
    for (@jobs) {
	$_->move_to(File::Spec->catdir($self->basedir, SCM_DIR_PENDING));
    }

    @jobs = $self->get_pending_jobs;

    for (@jobs) {
	warning("considering ", $_->id);

        if (not $self->check_approval($_)) {
            if ($_->status eq STATUS_ROLLEDBACK or
                $_->status eq STATUS_REINSTATED) {
	        $_->move_to(File::Spec->catdir($self->basedir, SCM_DIR_ABANDON));
            }
            next;
        }
                
        $self->check_dependencies($_) or next;

	$self->csq_status->alterChangeSetDbRecordStatusFrom($_->id, oldstatus => STATUS_WAITING,
								    newstatus => STATUS_ACTIVE,
								    uuid      => $_->cs->getUser)
	    and do {
		warning("status changed from N to A for", $_->id);
		$_->change_status(STATUS_ACTIVE);
	    };

        warning("committing ", $_->id);
        $self->unbundle_commit($_);
    }
}


sub check_dependencies {
    my ($self, $job) = @_;

    # retrieve CSDB record to get dependencies
    my $fromdb = $self->get_dbrecord($job);

    fatal "Error in database: $@"
        if $@;

    if (not defined $fromdb) {
        $job->move_to(File::Spec->catfile($self->basedir, SCM_DIR_FAIL));
        $self->notify("Cannot determine status for " . $job->id, qw/tvon jdevenpo/);
    }

    $job->cs($fromdb);

    $self->dependents_ok($job) or return 0;
    $self->contingents_ok($job) or return 0;

    return 1;
}

sub dependents_ok {
    my ($self, $job) = @_;

    return 1 if not my @deps = $job->cs->getDependenciesByType(DEPENDENCY_TYPE_DEPENDENT);

    # $job is not applicable for commit if any dependency:
    #   a) was rolled back/withdrawn/reinstated
    #   b) is in fail
    #   c) is still in pending/
    # In case of a) or b), $job is considered failed as well
    
    my $csid = $job->id;

    my $failed = File::Spec->catdir($self->basedir, SCM_DIR_FAIL);
    for my $dep (@deps) {

        # first check status
        my $status = $self->get_dbstatus($dep) or return 0;
        if ($status =~ /$STATUS_ROLLEDBACK|$STATUS_WITHDRAWN|$STATUS_REINSTATED/) {
            warning "dependency $dep has status $status - $csid will be abandoned";
            $job->move_to(File::Spec->catdir($self->basedir, SCM_DIR_ABANDON));
            return 0;
        }

        # did dependency fail
        if (my @list = glob "$failed/$dep*") {
            warning "dependency $dep failed - $csid will be abandoned";
            $job->move_to(File::Spec->catdir($self->basedir, SCM_DIR_ABANDON));
            return 0;
        }

        if (my @nc = not_completed($dep)) {
            warning "dependency $dep still undetermined - $csid will be held back";
            return 0;
        }
    }

    return 1;
}

sub contingents_ok {
    my ($self, $job) = @_;

    return 1 if not my @deps = $job->cs->getDependenciesByType(DEPENDENCY_TYPE_CONTINGENT);

    debug("Contingent: ", $job->id,"=>", join(',' => @deps));

    @deps = not_completed(@deps);
    debug("Incomplete: ", $job->id, "=>", join(',' => @deps));
    return 0 if @deps;

    return 1;
}


sub unbundle_commit {
    my ($self, $job) = @_;

    my $repository = SCM::Repository->new( repository_path => SCM_REPOSITORY );

    eval {
        $job->move_to(File::Spec->catfile($self->basedir, SCM_DIR_INPROG));
    };

    if ($@) {
        warning("race condition detected and caught: ", $job->id, " probably rolled back.\n");
        return;
    }

    # check if $job has already been committed
    if (my $rev = $repository->_get_rev_from_csid($job->id)) {
        debug $job->id . " already committed in an earlier instance (rev $rev)";
        $job->move_to(File::Spec->catdir($self->basedir, SCM_DIR_DONE));
        return;
    }

    my $bundle = getBundlePath($job->id);
    
    my ($rev, $err) = $repository->commit_bundle($bundle);

    # FIXME: Should use Change::Set::isRollbackChangeSet.
    if (!$err) {
	debug("Submit OK for ", $job->name);
	if ($job->cs->isStructuralChangeSet()
	    or  $job->cs->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK)) {
	    $self->set_dbstatus($job, STATUS_COMPLETE);
	}
        generateDiffReport($job->cs, $repository);
	# $self->send_message($job, "Committed");
	$job->move_to( File::Spec->catdir($self->basedir, SCM_DIR_DONE) );
        $job->change_rev_id($rev);
    } elsif ($err == 111) {
        debug("Submit DIED for ", $job->name);
        exit $err;
    } else {
	debug("Submit NOT OK for ", $job->name, ": ", $err);
	$self->send_message($job, "Failed", $err);
	$job->move_to( File::Spec->catdir($self->basedir, SCM_DIR_FAIL) );
    }

    exit if not $MAX_COMMITS--;
}

{

    my ($dbh, $dbs);

    # this sorts by timestamp, but puts breg change sets last.
    # This catches both autobreg change sets as well as structural 
    # change sets touching bregacclib.mk. 
    # We are allowed to permute breg change sets relative to 
    # other submissions because nothing else ever checks into these
    # libraries nor is there overlap.
    # stpr change sets are ordered by time-to-A change.
    sub by_timestamp {
        ($a->cs->isBregMove - $b->cs->isBregMove) 
                        ||                      # if both or neither breg, sort by timestamp
        $a->timestamp <=> $b->timestamp;
    }

    sub get_pending_jobs {
        my $self = shift;
        $dbh = $self->csq_hist;
        $dbs = $self->csq_status;
        return sort by_timestamp $self->get_jobs(SCM_DIR_PENDING);
    }
}

sub send_message {
    my ($self, $job, $message, $err) = @_;

    my $csid = $job->cs->getID();
    my $creator = $job->cs->getUser();
    my $creation_time = $job->cs->getTime();

    require SCM::Message;
    if (not $err) {
        SCM::Message->send_cs_response(
                -csid       => $csid,
                -creator    => $creator,
                -time       => $creation_time,
                -body       => $message,
                -subject    => "CHGS $csid diff report",
        ) or error "Could not send message for '$csid'";
    } else {
        my @to = qw/gstrauss tvon jdevenpo/;
        SCM::Message->send(
                -from       => 'tvon',
                -to         => \@to,
                -subject    => "Commit of " . $job->id . " failed",
                -body       => "Error message:\n\n$err",
        ) or error "Could not send failure message to @to";
    }
}

1;

__END__

=head1 NAME

SCM::Queue::Commit - The commit daemon

=head1 SYNOPSIS

    use SCM::Symbols qw/SCM_QUEUE/;
    use SCM::Queue::Commit;

    my $D = SCM::Queue::Commit->new( SCM_QUEUE );
    $D->run;

=head1 DESCRIPTION

This daemon is the link between the queue and the repository in that it will
commit pending changesets into the repository using L<SCM::Repository>.

It does so picking up all jobfiles from SCM_DIR_PENDING, checking their status
(only jobs with a status of STATUS_ACTIVE or STATUS_COMPLETE will be
considered) and then committing them. Status is checked by making an HTTP requestion
via L<SCM::CSDB::Request>.

Changesets that could be applied succesfully end up in SCM_DIR_DONE, whereas those
where the committal failed will be moved to SCM_DIR_FAIL.

The daemon is reentrant in that it can be interrupted at any time without 
imposing the risk of data corruption. Simply restarting it will make it
pick up the work where it left off.

=head1 CONSTRUCTOR

=head2 new( $basedir )

Constructs a new daemon object which will work on the queue system to be found
in I<$basedir>.

=head1 METHODS

=head2 run()

Triggers one run of the daemon over SCM_DIR_PENDING. 

=head1 SEE ALSO

L<SCM::Symbols>, L<SCM::Queue>, L<SCM::Queue::Job>, L<SCM::Repository>, L<SCM::CSDB::Request>
