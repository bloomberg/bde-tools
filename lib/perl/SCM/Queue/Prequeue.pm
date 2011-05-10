# vim:set ts=8 sts=4 noet:

package SCM::Queue::Prequeue;

use strict;
use warnings;

use base                    qw/SCM::Queue/;

use File::Spec;
use File::Temp              qw/tempfile tempdir/;
use File::Basename;
use List::Util		    qw/shuffle/;

use Util::Message           qw/fatal debug error warning/;
use Util::File::Functions   qw/ensure_path/;
use Util::Trigger           qw/triggerPull/;
use Change::Symbols         qw/DEPENDENCY_TYPE_ROLLBACK DEPENDENCY_TYPE_CONTINGENT
                               DEPENDENCY_TYPE_DEPENDENT DEPENDENCY_TYPE_NONE
                               STAGE_PRODUCTION
                               FILE_IS_REMOVED FILE_IS_UNCHANGED FILE_IS_RENAMED
			       STATUS_COMPLETE $STATUS_ACTIVE $STATUS_WAITING
                               STATUS_ROLLEDBACK
			       MOVE_EMERGENCY 
			       DEPENDENCY_NAME
			       $CS_DIFFREPORT_DIR/;
use SCM::Symbols            qw/SCM_REPOSITORY 
                               SCM_QUEUE $SCM_QUEUE 
                               SCM_DIR_DATA $SCM_DIR_PREQUEUE
                               SCM_DIR_PENDING SCM_DIR_ABANDON
			       $SCM_DIR_PENDING $SCM_DIR_TMP 
			       SCM_DIR_DONE SCM_DIR_FAIL
			       SCM_DIR_QUEUE
			       SCM_TESTING_TRIGGER
                               SCM_ROLLBACK_DIRS
                               $SCM_DIR_INPROG
			       SCM_FALLBACK_CSID
			       $SCM_STATS_CHECKIN_WEEKLY
			       $SCM_DIFF_PATH
			       SCM_CSDB SCM_CSDB_DRIVER/;
use Symbols		    qw/$CONSTANT_PATH/;
use Production::Symbols	    qw/BUILD_ONLY_MACHINES/;

use SCM::Queue::Job;
use Change::Util            qw/hashCSID2dir/;
use SCM::Queue::Util        qw/get_job_by_csid get_staged_jobs/;
use SCM::Remote;

our $VERSION = '0.01';

our $CSROLLBACK = '/bbsrc/bin/prod/csrollback';

Util::Message::set_debug(1);

sub new {
    my ($class, $basedir) = @_;
    my $self = $class->SUPER::new( $basedir );

    return $self;
}

sub run {
    my $self = shift;
  
    my $rep;

    my @jobs = $self->filemap_load;
    
    for my $job (@jobs) {

	$self->set_dbstatus($job, $STATUS_ACTIVE)
	    if $job->cs->isStructuralChangeSet;

	$self->branch_bind($job)
	    if not defined $job->cs->getBranch;

	$job->copy_to("$SCM_STATS_CHECKIN_WEEKLY/tmp");

	if (not $job->cs->isStructuralChangeSet and
	    not $job->cs->isRollbackChangeSet) {
	    my $csid = $job->id;
	    my $rem = SCM::Remote->new;
	    $rem->cp_from("$CS_DIFFREPORT_DIR/".hashCSID2dir($csid)."/$csid.diff.html",
			  "$SCM_DIFF_PATH/$csid.rcsdiff.html", 5);
	}

        if ($job->status ne $STATUS_ACTIVE and 
            my @csids = $job->cs->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK)) {
            
            my $rbtarget;
            if (not $rbtarget = $self->rollback_target(@csids)) {
                $job->move_to(File::Spec->catdir($self->basedir, SCM_DIR_FAIL));
                next;
            }
                    
            $self->do_rollback($job, $rbtarget);
            next;
        }
        
        $self->check_dependencies($job);

        my $status = $self->get_dbstatus($job);

	fatal "Something in the database failed: $@"
	    if $@;

        fatal "Got undefined status for " . $_->id
            if not defined $status;

        $job->change_status($status);

        $job->move_to( File::Spec->catdir($self->basedir, SCM_DIR_QUEUE) );
    }

    triggerPull( SCM_TESTING_TRIGGER ) 
    	or fatal("could not trigger ", SCM_TESTING_TRIGGER, ": $!");
}


sub check_dependencies {
    my ($self, $job) = @_;

    if ($job->cs->isStructuralChangeSet) {
	debug "Found structural change set";
	my @overlap = $self->get_struct_overlap($job);
	debug "Overlap: ", join ' ' => map $_->id, @overlap;
	$self->rollback_struct_overlap($_, $job)
	    for @overlap;
	return;
    }

    my @deps;
    my $move = $job->cs->getMoveType;

    # DEPENDENCY_TYPE_NONE explicitely ignores the contingency
    # on a CSID.
    my %none;
    $none{$_} = 1
        for $job->cs->getDependenciesByType(DEPENDENCY_TYPE_NONE);

    # DEPENDENCY_TYPE_DEPENDENT is strong than _TYPE_CONTINGENT.
    # If a CS already has a dependency, this will take precedence
    # over a contingency due to file overlap.
    my %dependents; # dependencies of type DEPENDENCY_TYPE_DEPENDENT
    $dependents{$_} = 1
        for $job->cs->getDependenciesByType(DEPENDENCY_TYPE_DEPENDENT);

    for my $f ($job->cs->getFiles()) {
	next if $f->getType eq FILE_IS_UNCHANGED;
	for ($self->filemap_get($f, $move)) {
	    $_ eq $job->id  and  last;
            next if exists $dependents{$_} or
                    exists $none{$_};
	    push @deps, $_;
	}
    }

    $self->add_deps($job, @deps);
    $job->add_dep if @deps || %dependents;
}


sub get_struct_overlap {
    my ($self, $job) = @_;
    
    # only interested in overlap with the 'from' field 
    # of a structural changeset. Two cases:
    #	a) a directory: compare with dirname() 
    #	   of 'destination' in staged jobs
    #	b) a file: compare 'from' of struct change with
    #	   'destination' field of staged jobs

    my $struct_move = $job->cs->getMoveType;
    my $raw = ($job->cs->getFiles)[0];

    my $path;
    if ($raw->getType eq FILE_IS_RENAMED) {
	$path = $raw->getSource;
    } else {
	$path = $raw->getDestination;
    }

    for ($path) {
	s!^$CONSTANT_PATH/!!;
	s!^root/!!;
	s/@@.*//;
    }

    my $overlaps;
    if ($path =~ s!/$!!) {
	# directory/library
	require File::Basename;
	$overlaps = sub {
	    my $file = shift;
	    my $dest = dirname($file->getDestination);
	    return if $raw->getType eq FILE_IS_REMOVED and
		      $file->isUnchanged;
	    $dest =~ s!^root/!!;
	    return $path eq $dest;
	};
    } else {
	# file
	$overlaps = sub {
	    my $file = shift;
	    my $dest = $file->getDestination;
	    if ($file->isUnchanged) {
		# for unchanged files, we only care about
		# file moves
		return if $raw->getType ne FILE_IS_RENAMED;
	    }
	    $dest =~ s!^root/!!;
	    return $path eq $dest;
	};
    }

    my @rollback;
    JOB:
    for my $j (get_staged_jobs()) {
	next if $j->cs->isStructuralChangeSet	    or
		$j->cs->getMoveType ne $struct_move or
		$j->cs->isImmediateMove && $struct_move eq MOVE_EMERGENCY;

	for my $file ($j->cs->getFiles) {
	    push @rollback, $j and next JOB if $overlaps->($file);
	}
    }

    return @rollback;
}

sub rollback_struct_overlap {
    my ($self, $job, $struct) = @_;
  
    debug "rolling back " . $job->id;

    # the sooner we move the job-file away the better
    eval {
	$job->move_to($self->basedir, SCM_DIR_ABANDON);
    } if $job->dir =~ /$SCM_DIR_PENDING$/;

    if (SCM::Remote->new->run_ec("$CSROLLBACK --only " . $job->id) != 0) {
	error "failed to rollback " . $job->id;
	return;
    }

    my $csid = $job->id;
    my $move = $job->cs->getMoveType;
    my $rbid = $struct->id;
    my $rb   = $struct->cs->render;

    my $body = <<EOBODY;
Dear developer,

Change set {nxtw MYCS $csid<go>} (movetype $move)
had to be rolled back due to overlap with a restructure request.

Please review the following structural change and resubmit your
change set, making sure that all files are checked into the new
location. {nxtw MYCS $rbid<go>}

EOBODY

    $self->send_message($struct->cs->getUser, [ $job->cs->getUser, qw/gstrauss tvon jdevenpo/ ],
			"Automatic rollback of " . $job->id, $body);
}

sub add_deps {
    my ($self, $job, @deps) = @_;
    return if not @deps;

    warn $job->id . " has contingencies: @deps\n";

    my %pairs = map { $_ => $job->cs->getDependencyType } @deps;
    my $count = $self->add_dbdependency($job, \%pairs);

    if ($@) {
        error "Failed to add contingency on $_ to " . $job->id . ": $@";
    } else {
	warning "$count dependencies added";
    }
}

sub rollback_target {
    my ($self, $id) = @_;

    my $target = $self->get_dbrecord($id);

    return if not defined $target;

    print STDERR $target->serialise;

    # you cannot rollback rollbacks
    if ($target->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK)) {
        warn "cannot rollback a rollback!";
        return;
    }

    return $target;
}

sub do_rollback {
    my ($self, $rb, $rbtarg) = @_;

    require SCM::Repository;
    my $rep = SCM::Repository->new(repository_path => SCM_REPOSITORY);

    # we were asked to rollback change set with ID $id

    my $queue = [ $SCM_DIR_PREQUEUE, SCM_DIR_QUEUE, SCM_DIR_PENDING ];

    $self->rollback_dependencies($rb, $rbtarg);

    if (my $target_in_queue = get_job_by_csid($rbtarg->getID, $queue)) {
	eval {
	    $target_in_queue->move_to(File::Spec->catdir($self->basedir, 
                                                     SCM_DIR_ABANDON));
	};
	if ($@) {
	    # No short circuit, continue.
	    warning("race condition detected and caught: ",$rbtarg->getID," probably in progress");
	}
	else {
	    # Short circuit.
	    warning("rollback target ",$rbtarg->getID," set aside");
	    $self->update_status($rb, STATUS_COMPLETE);
	    $rb->change_status(STATUS_COMPLETE);
	    $rb->move_to(File::Spec->catdir($self->basedir, SCM_DIR_DONE));
	    return;
	}
    }
  
    # not in queue, but maybe in inprogress/:
    # we consider such a job's status indeterminate
    # so we simply let the rollback request sit in the
    # queue and process on the next iteration
    my $id = $rbtarg->getID;
    return if glob "$SCM_QUEUE/$SCM_DIR_INPROG/$id*";

    # check if rollback target ever made it to the repository
    my ($priorid, $err) = $rep->list_commits($rbtarg->getBranch, 
                                             $rbtarg->getID, 2);
    if ($err) {
        # rollback-target never submitted
        warning("rollback target of $rbtarg->getID never committed");
        $self->update_status($rb, STATUS_COMPLETE);
        $rb->change_status(STATUS_COMPLETE);
        $rb->move_to(File::Spec->catdir($self->basedir, SCM_DIR_DONE));
        return;
    }

    # Make sure that the prior has not itself been rolled back
    # If it has, get the prior of the prior, etc...
    $priorid = @$priorid == 1 ? SCM_FALLBACK_CSID : ($priorid->[0] || SCM_FALLBACK_CSID);

    if ($priorid ne SCM_FALLBACK_CSID) {
	while ($self->get_dbstatus($priorid) eq STATUS_ROLLEDBACK) {
	    ($priorid, $err) =  $rep->list_commits($rbtarg->getBranch, $priorid, 2);
	    last if $err;
	    $priorid = @$priorid == 1 ? SCM_FALLBACK_CSID : ($priorid->[0] || SCM_FALLBACK_CSID);
	}

	if (not defined $priorid) {
	    error "Could not get the prior's ID for " . $rbtarg->getID;
	    $rb->move_to(File::Spec->catdir($self->basedir, SCM_DIR_FAIL));
	    return;
	}
    }

    warn "prior ID is $priorid\n";

    (my $files, $err) = $rep->paths_changed($rbtarg->getBranch, $rbtarg->getID);
    
    if ($err) {
        error "Error getting list of files from repository: $err";
        return;
    }

    (my $inprior, $err) = $rep->check_paths($rbtarg->getBranch, 
                                            $priorid, [ keys %$files ]);

    fatal $err if $err;

    my @files = grep $inprior->{$_} && $inprior->{$_} eq 'f', keys %$files;
    my @dirs  = grep $inprior->{$_} && $inprior->{$_} eq 'd', keys %$files;

    # make a canonical-fname => target mapping
    my %target;
    for ($rbtarg->getFiles) {
        my ($base, $dir) = fileparse($_->getDestination);
        @target{ $base, $dir } = ($_->getTarget) x 2;
    }

    # populate bundle skeleton
    my $tmpdir = tempdir(DIR => "$SCM_QUEUE/$SCM_DIR_TMP", CLEANUP => 1);
    ensure_path("$tmpdir/root");
    ensure_path("$tmpdir/root/".dirname($_)) for @files;

    # create a list of files that were unchanged
    # in the change set to be rolled back
    require SCM::Queue::Util;
    my $canonicalcs = SCM::Queue::Util::csid_to_cs($rbtarg->getID);
    my %unchanged;
    for($canonicalcs->getFiles) {
	(my $dest = $_->getDestination) =~ s#^root/##;
	$unchanged{ $dest } = 1 if $_->getType eq FILE_IS_UNCHANGED;
    }

    my $branch = $rb->cs->getBranch;

    # export files to bundle area, but skip unchanged ones
    my %writeme;
    for (@files) {
	next if exists $unchanged{ $_ };
	$writeme{ "$branch/$_" } = "$tmpdir/root/$_";
    }

    (my $written, $err) = $rep->export($priorid, \%writeme);

    fatal $err if $err;

    # add file entries to rollback changeset, but only if they were changed
    for my $f (grep $files->{$_} eq 'f', keys %$files) {

	next if $unchanged{$f};
	my ($dirname, $basename) = (dirname($f), basename($f));
	my $canon = "root/$branch/$f";

	warn "for file $f:\n";

	if ($inprior->{$f}) {
	    $rb->cs->addFile($target{$basename}, $canon, $canon);
	}
	else {
	    $rb->cs->addFile($target{$basename}, $canon, $canon, FILE_IS_REMOVED);
	}
    }
        
    # add dir entries to rollback changeset
    for my $d (grep $files->{$_} eq 'd', keys %$files) {
      my $canon = $d;
      $canon =~ s#/+$##;
      $canon = "root/$canon/";
  
      if ($inprior->{$d}) {
        $rb->cs->addFile($target{$d}, $canon, $canon);
      }
      else {
        if (SCM_ROLLBACK_DIRS) {
          warn "add directory $d: to be removed\n";
          $rb->cs->addFile($target{$d}, $canon, $canon, FILE_IS_REMOVED);
        }
      }
    }

    warn "write new meta file\n";
    open my $meta, '>', "$tmpdir/meta" 
        or fatal "Could not open '$tmpdir/meta' for output: $!";
    print $meta $rb->cs->serialise;
    warn $rb->cs->serialise, "\n";
    close $meta;

    # replace old rollback bundle with a bundle that contains the prior version
    # of the files of the changeset to be rolled back
    {
        local $^W = 0;
        my (undef, $src) = tempfile(OPEN => 0);
        my $dest = File::Spec->catfile($SCM_QUEUE, SCM_DIR_DATA, 
                                       hashCSID2dir($rb->id), $rb->id);
        system "cd $tmpdir && tar cf - meta root | gzip -c > $src && mv $src $dest";
    }

    # update status of rollback to A
    $self->update_status($rb, $STATUS_ACTIVE);
    $rb->change_status($STATUS_ACTIVE);

    # rewrite jobfile and flush to queue/
    $rb->flush_to($rb->dir);
    $rb->move_to(File::Spec->catdir($self->basedir, SCM_DIR_QUEUE));
}

sub rollback_dependencies {
    my ($self, $rb, $rbtarg) = @_;

    my $rbid  = $rbtarg->getID;
    my @csids = $self->find_targets($rbid);

    # rollback one after the other
    my $sender = $rb->cs->getUser;
    for my $rec (@csids) {
	my ($csid, $user) = @$rec;
	my $body = <<END;
Dear developer,

Change set {nxtw MYCS $csid<go>} has a dependency
on {nxtw MYCS $rbid<go>} which was just rolled
back. As a consequence, your change set was automatically rolled
back too.
END
	SCM::Remote->new->run_ec("$CSROLLBACK $csid");
	$self->send_message($sender, $user, "Rollback of $csid", $body);
    }

}

sub find_targets {
    my ($self, $csid, $csids) = @_;

    $csids ||= [];

    my %seen;
    @seen{ map $_->[0], @$csids } = @$csids;
    
    my @new;
    my $dep = DEPENDENCY_NAME(DEPENDENCY_TYPE_DEPENDENT);
    for my $rec (@{ $self->csq_changeset->getDepsOfChangeSet($csid, $dep) }) {
	my ($id, $user, $time) = @{$rec}[0,1,3];
	next if $seen{$id};
	push @new, $id;
	push @$csids, [ $id, $user, $time ];
    }

    $self->find_targets($_, $csids) for @new;

    # newest first
    return sort { $b->[2] cmp $a->[2] } @$csids;
}

sub send_message {
    my ($self, $from, $to, $subject, $body) = @_;

    require SCM::Message;
    SCM::Message->send(
	    -from	=> $from,
	    -to		=> $to,
	    -subject	=> $subject,
	    -body	=> $body,
    ) or error "Failed to send message";
}

sub by_timestamp {
    $a->timestamp <=> $b->timestamp;
}


# filemap:
# map destination filename => @csids
sub filemap_load {
    my $self = shift;

    my @jobs = sort by_timestamp get_staged_jobs();

    for my $j (@jobs) {
        my $move = $j->cs->getMoveType;
	for my $file ($j->cs->getFiles) {
	    next if $file->getType eq FILE_IS_UNCHANGED;
	    $self->filemap_add($file, $j->id, $move);
	}
    }

    return grep $_->dir =~ /$SCM_DIR_PREQUEUE/, @jobs;
}

sub filemap_add {
    my ($self, $file, $csid, $move) = @_;
    push @{ $self->{filemap}->{$move}->{$file} }, $csid;
}

sub filemap_get {
    my ($self, $file, $move) = @_;
    return @{ $self->{filemap}->{$move}->{$file} || [] };
}


{
    # no caching of branch mapping:
    # a single change set may take several seconds to
    # process; caching the mapping would therefore expose
    # us to potential branch-promotions happening while
    # prequeued is running
    my $csdb;
    sub branch_bind {
	my ($self, $job) = @_;

	require SCM::CSDB::Branching;
	$csdb ||= SCM::CSDB::Branching->new(database	=> SCM_CSDB,
					    driver	=> SCM_CSDB_DRIVER);
	my $branch = $csdb->resolve_alias(alias => $job->cs->getMoveType)->{branch_id};
	$job->cs->setBranch($branch);
	for my $file ($job->cs->getFiles) {
	    (my $dest = $file->getDestination) =~ s!^root/!root/$branch/!;
	    $file->setDestination($dest);
	}
	$job->flush_to(File::Spec->catdir($self->basedir, $SCM_DIR_PREQUEUE));
    }
}

1;

__END__

=head1 NAME

SCM::Queue::Prequeue - Daemon that queues up raw incoming changesets

=head1 DESCRIPTION

I<SCM::Queue::Prequeue> implements the logic behind the prequeue daemon. Its
job is to scan the SCM_DIR_PREQUEUE directory for new entries, normalize these to
job files and move them to queue/. These are either:

=over 4

=item empty files

In this case, the filename is used to grab the actual changeset from data/ and
construct a proper jobfile from it and move it queue/.

=item non-empty files

The entry is already a proper job file in which case it can simply be moved to
queue/.

Additionally, the prequeue daemon will intercept all rollback jobs, extract the
IDs of the changesets to be rolled back and simply create an empty file with
the ID as filename in SCM_DIR_ROLLBACK.

=head1 CONSTRUCTOR

=head2 new( $basedir )

Constructs a new daemon object which will work on the queue system to be found
in I<$basedir>. 

=head1 METHODS

=head2 run()

Makes one run over the involved directories. In order to turn this into
a long running process, you'll have to keep calling this method contuinally
in some way, e.g.:

    my $preq = SCM::Queue::Prequeue->new( $BASEDIR );
    
    while () {
	$preq->run;
	select undef, undef, undef, 1;
    }

=head1 SEE ALSO

L<SCM::Queue>, L<SCM::Queue::Job>

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
