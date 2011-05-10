package SCM::Queue::Sweep;

use strict;
use warnings;

use base qw/SCM::Queue/;

use File::Spec;
use File::Temp                      qw/tempfile/;

use Util::Message                   qw/fatal/;

use SCM::Symbols                    qw/SCM_QUEUE 
                                       SCM_DIR_DONE SCM_DIR_SWEPT SCM_DIR_TMP
                                       SCM_DIR_ABANDON SCM_DIR_FAIL/;
use Change::Symbols                 qw/$STATUS_COMPLETE $STATUS_INPROGRESS
                                       $STATUS_ACTIVE $STATUS_ROLLEDBACK
                                       DEPENDENCY_TYPE_ROLLBACK
                                       $MOVE_REGULAR $MOVE_BUGFIX 
                                       $MOVE_EMERGENCY 
                                       $STAGE_BETA $STAGE_PRODUCTION
				    /;
use SCM::Queue::Job;
use SCM::Approval;

use Change::Util::Canonical	    qw/branch_less/;

our $VERSION = '0.01';

my %movetype2idx = (
        $MOVE_REGULAR    => 0,
        $MOVE_BUGFIX     => 1,
        $MOVE_EMERGENCY  => 2,
);

sub new {
    my ($class, $basedir, %args) = @_;

    my $self = $class->SUPER::new( $basedir );

    return $self;
}

# The purpose of the following two functions is to support both the combined
# tuesday emov sweep as well as the sweep split into beta- and -prod emovs.
# This is done simply by recording each emov twice: as emov (old behaviour)
# and as emov-beta/emov-prod. The sweep calculation is then done over three
# emov sets: emov, emov-beta and emov-prod.

sub get_movetype {
    my $cs = shift;

    my @move = $cs->getMoveType;

    push @move, "$MOVE_EMERGENCY-" . $cs->getStage
        if $cs->isEmergencyMove;

    return @move;
}

sub get_all_movetypes {
    return ($MOVE_REGULAR, $MOVE_BUGFIX,
            "$MOVE_EMERGENCY-$STAGE_BETA", "$MOVE_EMERGENCY-$STAGE_PRODUCTION");
}

# There are two modes of operation:
#   stagedby-mode: 
#	- don't move job files
#	- write FILELIST.* for StagedBy
#	- treat status A and P the same
#   sweep:
#	- move unused job files to sweep/
#	- only consider jobs in status P during sweep calculation
#	    

sub obtain_jobs {
    my ($self,$trim) = @_;

    # sort descending: bigger revisions come first
    my @all = sort by_rev_id $self->get_jobs(SCM_DIR_DONE);

    my $swept_dir = File::Spec->catdir($self->basedir, SCM_DIR_SWEPT);
    my (%available, %status);
    for my $job (@all) {
	my $cs = $job->cs;
        if ($cs->isStructuralChangeSet or $cs->isBregMove) {
            $job->move_to($swept_dir) if $trim;
            next;
        }
        
        $status{$job} = $self->get_dbstatus($job->id) 
            or do {
                $job->move_to(File::Spec->catfile($self->basedir, SCM_DIR_FAIL));
                $self->notify("Cannot determine status for " . $job->id, qw/tvon jdevenpo/);
        };

        $job->change_status($status{$job});

        # emovs are special: record them both under the key
        # 'emov' as well as 'emov-$STAGE'.
        my @move = get_movetype($cs);
        push @{ $available{$_} }, $job for @move;
    }

    return (\%available, \%status);
}

sub run {
    my ($self, %args) = @_;

    my ($mode, $consider_status, @movetypes);

    $mode = $args{mode} || 'stagedby';

    if ($mode eq 'stagedby') {
	$consider_status = qr/(?:$STATUS_ACTIVE|$STATUS_INPROGRESS)/;
	@movetypes  = get_all_movetypes();
    } elsif ($mode eq 'sweep') {
	$consider_status = qr/$STATUS_INPROGRESS/;
	(@movetypes = $args{movetype}) == 1
	    or fatal "Need to specify movetype in sweep mode";
    } else {
	fatal "$mode: Invalid mode of operation";
    }

    $consider_status = qr/$args{status}/ if defined $args{status};

    my ($by_move, $status) = $self->obtain_jobs(($mode eq 'stagedby' ? 1 : 0));

    my $ret;
    for my $move (@movetypes) {

	# for $mode eq 'sweep' there is always only one iteration
	# Further below, we return a hash of active CSIDs after the
	# first iteration since @movetypes only contains one item
	# in sweep-mode.

        my %files;
	# collate jobs by file
        my %allcsids;
        for my $job (@{ $by_move->{$move} }) {
            my @files = $job->cs->getFiles or 
		$job->move_to(File::Spec->catdir($self->basedir, SCM_DIR_SWEPT)); 
	    push @{ $files{branch_less($_)} }, $job for @files;
            $allcsids{ $job->id }++ if $status->{$job} =~ /^$consider_status$/;
	}

	my (%active, %dispose);
    
        my $appr = SCM::Approval->new;
        FILE: for my $f (keys %files) {

	    my @active_job;
	    my @retain_job;
	    # For each file, construct active and retain lists.
            my @per_file = @{ $files{$f} };
           
            for my $idx (0 .. $#per_file) {

                my $j = $per_file[$idx];

                if ($appr->is_withdrawn($j->id)) {
                    if ($status->{$j} ne $STATUS_ROLLEDBACK) {
                        $self->set_dbstatus($j, $STATUS_ROLLEDBACK);
                        $j->change_status($STATUS_ROLLEDBACK);
                    }
                    $j->move_to(File::Spec->catdir($self->basedir, SCM_DIR_ABANDON));
                    next;
                }

                my ($rbtarg) = 
                    $j->cs->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK);

		if ($rbtarg) {
                    # seek forward to job behind rollback target
                    while ($per_file[$idx++]) {
                        my $job = $per_file[$idx] or last;
                        $dispose{$job->id} = $job;
                        last if $per_file[$idx]->id eq $rbtarg;
                    }
                    # by definition, the rollback change set itself has been processed
                    # or else sweepd would not see it:
                    $dispose{$j->id} = $j;
                    next;
                }

                if ($status->{$j} eq $STATUS_COMPLETE) {
                    $dispose{$_->id} = $_ for @per_file[$idx .. $#per_file];
                    next FILE;
                }

                push @{ $active{$f} }, $j;
            }
        }

	# Sweep case: Trim the list to those with status of interest, i.e. in progress.
        # In this case, we must also change the status accordingly of stuff in %retain
        # and those not needed in %active.
	if ($mode ne 'stagedby') {
	    for my $f (keys %active) {
		$active{$f} = [ grep(($status->{$_} =~ m/$consider_status/) => @{$active{$f}}) ];
	    }
	    return (\%active, \%allcsids);
	}

	#### $mode eq 'stagedby'
	# Stagedby case: continue.

	# Prune the head of the active list.
	for my $f (keys %active) {
	    while(my ($j) = @{ $active{$f} }) {
		$status->{$j} =~ m/$consider_status/  and  last;
		shift @{ $active{$f} };
	    }
	}

        # Delete all CSIDs that are active for some file from the disposal list
	for (map @$_ => values %active) {
            delete $dispose{$_->id};
	}

	# Look for everything from main list not marked active.
	my @unused = values %dispose;
	# And move them out.
	for (@unused) {
	    $_->move_to(File::Spec->catdir($self->basedir, SCM_DIR_SWEPT));
	}

	# Write FILELIST.movetype.
	$self->write_filelist($move, \%active, \%allcsids);
    }
    # Someone may wish to detect errors in future.
    return 1;
}

sub write_filelist {
    my ($self, $movetype, $new, $all) = @_;

    my ($tfh, $tname) = tempfile(UNLINK => 0, DIR => join '/', SCM_QUEUE,
                                                               SCM_DIR_TMP);

    Util::Message::set_verbose(1);
    require SCM::Sweep;
    my ($csids, $err) = SCM::Sweep::write_sweep_filelist($new, $all, $tfh);
    fatal $err if $err;

    close $tfh;

    # existing FILELIST
    my $flpath = File::Spec->catfile($self->basedir, SCM_DIR_DONE, 
                                     "FILELIST.$movetype");

    rename $tname => $flpath 
        or fatal "Atomic writing to $flpath failed: $!";
}

sub by_rev_id {
    $b->rev_id <=> $a->rev_id;
}

1; 
=head1 NAME

SCM::Queue::Sweep - The sweep daemon

=head1 DESCRIPTION

This daemon's responsibility is to pick up all jobs from I<SCM_DIR_PENDING>
and trigger processes to run test on each job.

Once the test are done, the job is moved to either I<SCM_DIR_PENDING> (in case
the job passed the tests) or I<SCM_DIR_REJECT>.

=head1 CONSTRUCTOR

=head2 new( $basedir )

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
