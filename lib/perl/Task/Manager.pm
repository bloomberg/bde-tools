package Task::Manager;
use strict;

use vars qw(@ISA);
use overload '""' => "toString", fallback => 1;

use BDE::Object;
@ISA=qw(BDE::Object);

use Task::Status;
use Task::Action;
use Util::Message qw(alert debug debug2 message error fatal verbose verbose2);

#==============================================================================

=head1 NAME

Task::Manager - Manage and execute a collection of related task actions

=head1 SYNOPSIS

  use Task::Manager;
  use Task::Action;

  sub action_sub (@) {
      print "running action_sub (pid=$$): @_\n";
      sleep 1;
      return 0; #success; change this to 1 for failure
  }

  my $act1=new Task::Action({
      name => "action 1", action => \&action_sub, args => [qw(1 2 3)]
  });
  my $act2=new Task::Action({
      name => "action 2", action => \&action_sub, args => [qw(1 2 3)]
  });
  my $act3=new Task::Action({
      name => "action 2", action => \&action_sub, args => [qw(4 5 6)],
      requires => ["action 1","action 2"]
  });

  my $mgr=new Task::Manager("Example");
  $mgr->addActions($act1,$act2,$act3);

  print "Name (explicit): ",$mgr->getName(),"\n";
  print "Name (toString): $mgr\n";
  print "Actions: ",join(' ',$mgr->getActions()),"\n";

  my $result=$mgr->run(4); #concurrency=4
  if (not $result) {
      print "Completed OK";
  } else {
      print "Completed with failures: @{[ $mgr->actionsFailed() ]}\n";
  }

=head1 DESCRIPTION

C<Task::Manager> implements a dependency-based job execution engine. Actions,
implemented as L<Task::Action> objects, are registered with the manager to
carry out the parts of the overall task. Once all actions are registered and
associated with each other (for dependencies), the L<"run"> method is invoked
to execute the task set.

See the L<"SYNOPSIS"> for an example of how a task set may be constructed
from task actions and executed using this module.

=head2 Concurrency Semantics and Subclassing

C<Task::Manager> may be subclassed to alter its concurrency engine semantics.
The two primary methods for doing this are L<runActionConcurrently>, which
determines how actions are spawned in a parallel execution environment, and
L<retrieveAction>, which determines how the returned states of finished
actions are recovered when running in parallel.

In this base class a forking model is used. L<Task::Threaded::Manager>
overloads these methods to provide an alternate threaded implementation.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new($name)

Create a new empty instance of a C<Task::Manager> object, using the specified
name if provided. If no name is provided a default name of C<Running> is used.

=cut

sub fromString($$) {
    my ($self,$init)=@_;

    $self->setName($init ? $init : "Running");
    $self->{actions}={};
    $self->{pids}={};
    $self->{quit}=0;
    $self->{logsub} = \&verbose;
}

# this constructor is probably unused and is deprecated, use the array version
sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->SUPER::initialiseFromHash($args);
    $self->{name} ||= "Running";
    $self->{actions} ||= {};
    $self->{pids} ||= {};
    $self->{quit} ||= 0;
    $self->{logsub} ||= \&verbose;
}

=head2 new($arrayref [,$name])

Creates a new instance of a C<Task::Manager> object populated with the
provided list of L<Task::Action> objects, passed in an array
reference, as its contents.

An optional third argument be passed to supply the task manager name.
Alternatively, if the first element of the passed array is not a
L<Task::Action>, it is evaluated as a string and used to intialise the
name of the task manager. If no name is supplied, a default name of C<Running>
is used.

=cut

sub initialiseFromArray ($$;$) {
    my ($self,$aref,$init)=@_;

    # a name may be passed in as 2nd arg, or first element of arrayref
    if (not $init and not ref $aref->[0]) {
        $init=shift @$aref;
    }

    $self->setName($init ? $init : "Running");
    $self->{pids} ||= {};
    $self->{quit} ||= 0;
    $self->{logsub} ||= \&verbose;

    # check we weren't passed invalid items
    foreach my $actno (0 .. @$aref) {
	my $item=$aref->[$actno];
	next unless $item;

	$self->throw("Element $actno is not a Task::Action")
	  unless ($aref->[$actno])->isa("Task::Action");

        $self->{actions}{$item}=$item;
    }

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getName()

Get the name of the task manager.

=head2 setName($name)

Set the name of the task manager.

=cut

sub getName ($) { return $_[0]->{name}; }
sub setName ($$) { $_[0]->{name}=$_[1]; }

=head2 getAction($name)

Get the action with the specified name from the task manager, or return
C<undef> if no action of that name is held by the manager.

=cut

# get a named action
sub getAction ($$) {
    if (exists $_[0]->{actions}{$_[1]}) {
	return $_[0]->{actions}{$_[1]};
    }
    return undef;
}

=head2 getActions()

Return the list of L<Task::Action> objects currently held by the task manager.

=cut

# get all actions
sub getActions ($) {
    return values %{$_[0]->{actions}};
}

=head2 setAction($action)

Add the specified action to the task manager. Throws an exception if an
action of the same name is already present. See also L<"addAction">.

=cut

# set a action; throw an error if it isn't a action or already exists
sub setAction ($$) {
    my ($self,$act)=@_;

    $self->throw("Not a action") unless $act->isa("Task::Action");
    $self->throw("Action $act exists") if exists $_[0]->{actions}{$act};
    $self->{actions}{$act}=$act; #toString
}

=head2 setActions(@actions)

Add the specified actions to the task manager. Throws an exception of an
action with the same name as any of the actions specified is already present.
See also L<"addActions">.

=cut

sub setActions ($@) {
    my ($self,@acts)=@_;
    $self->setAction($_) foreach @acts;
}

=head2 addAction($action)

Add the specified action to the task manager, replacing any existing action
of the same name if present. See also L<"setAction">.

=cut

sub addAction ($$) {
    my ($self,$act)=@_;

    $self->removeAction($act) if $self->getAction($act);
    $self->setAction($act);
}

=head2 addActions(@actions)

Add the specified actions to the task manager, replacing any existing actions
with the same names if present. See also L<"setActions">.

=cut

sub addActions ($@) {
    my ($self,@acts)=@_;
    $self->addAction($_) foreach @acts;
}

=head2 removeAction($name)

Remove the action with the specified name from the task manager. Returns the
removed action , or C<undef> if no action with the specified name is held by
the manager.

=cut

# remove the named action. return undef if action is not in set
sub removeAction ($$) {
    if (exists $_[0]->{actions}{$_[1]}) {
	return delete $_[0]->{actions}{$_[1]};
    }
    return undef;
}

=head2 removeAllActions()

Remove all actions from the task manager. In non-void context, return the
list of actions removed.

=cut

# remove all actions
sub removeAllActions ($) {
    if (defined wantarray) {
        my @actions=$_[0]->getActions();
        $_[0]->{actions}={};
        return @actions;
    } else {
        $_[0]->{actions}={};
    }
}

=head2 getLogSub()

Returns the sub ref for the current logging sub.

=head2 setLogSub(\&routine)

Set the current logging subroutine

=cut

sub getLogSub {
  return $_[0]->{logsub};
}

sub setLogSub {
  if (defined $_[1]) {
    $_[0]->{logsub} = $_[1];
  } else {
    $_[0]->{logsub} = \&verbose;
  }
}

#------------------------------------------------------------------------------

=head2 getQuitOnFailure()

Get the current setting of the I<quit on failure> flag.

=head2 setQuitOnFailure($boolean)

Set the I<quit on failure> flag. A true value means that the L<"run"> method
will return as soon as it receives a non-zero return status from a failed
completed action. A false value means that the task manager will continue to
process actions that were not impacted by the failed action. See
L<"propagateActionStatus"> and L<Task::Action/setFailOK>.

=cut

sub getQuitOnFailure  ($) { return $_[0]->{quit}; }
sub setQuitOnFailure ($$) { $_[0]->{quit}=$_[1];  }

#------------------------------------------------------------------------------
# Return actions by status

=head1 STATUS QUERY METHODS

=head2 getWaitingActions()

Return the list of all actions held by the manager with a state of
C<IS_WAITING>.

=cut

# get the list of waiting actions
sub getWaitingActions ($) {
    return (grep { $_->isWaiting() } $_[0]->getActions());
}

=head2 getRunnableActions()

Return the list of all actions held by the manager with a state of
C<IS_RUNNABLE>.

=cut

# get the list of runnable actions
sub getRunnableActions ($) {
    return (grep { $_->isRunnable() } $_[0]->getActions());
}

=head2 getRunningActions()

Return the list of all actions held by the manager with a state of
C<IS_RUNNING>.

=cut

# get the list of running actions
sub getRunningActions ($) {
    return (grep { $_->isRunning() } $_[0]->getActions());
}

=head2 getSuccessfulActions()

Return the list of all actions held by the manager with a state of
C<IS_SUCCESSFUL>.

=cut

# get the list of successful actions
sub getSuccessfulActions ($) {
    return (grep { $_->isSuccessful() } $_[0]->getActions());
}

=head2 getFailedActions()

Return the list of all actions held by the manager with a state of
C<IS_FAILED>.

=cut

# get the list of failed actions
sub getFailedActions ($) {
    return (grep { $_->isFailed() } $_[0]->getActions());
}

=head2 getUnrunnableActions()

Return the list of all actions held by the manager with a state of
C<IS_UNRUNNABLE>.

=cut

# get the list of unrunnable actions
sub getUnrunnableActions ($) {
    return (grep { $_->isUnrunnable() } $_[0]->getActions());
}

=head2 getAbortedActions()

Return the list of all actions held by the manager with a state of
C<IS_ABORTED>.

=cut

# get the list of aborted actions
sub getAbortedActions ($) {
    return (grep { $_->isAborted() } $_[0]->getActions());
}

=head2 getPendingActions()

Return the combined list of all actions held by the manager that have yet
to run; i.e. are in a state of C<IS_WAITING> or C<IS_RUNNABLE>.

=cut

# get the list of pending actions = waiting + runnable
sub getPendingActions ($) {
    return grep {
        $_->{status}==IS_WAITING or $_->{status}==IS_RUNNABLE
        #$_->isWaiting() || $_->isRunnable()
    } $_[0]->getActions();
}

=head2 getFinishedActions()

Return the combined list of all actions held by the manager that have been
reached an end state; i.e. are in a state of C<IS_FAILED>, C<IS_SUCCESSFUL>,
or C<IS_ABORTED>.

=cut

# get the list of finished actions = successful + failed + aborted
sub getFinishedActions ($) {
    return (grep {
	$_->isFailed() || $_->isSuccessful() || $_->isAborted()
    } $_[0]->getActions());
}

#------------------------------------------------------------------------------

=head2 actionsWaiting()

Return the number of actions that are waiting.

=head2 actionsRunnable()

Return the number of actions that are runnable.

=head2 actionsRunning()

Return the number of actions that are running.

=head2 actionsSuccessful()

Return the number of actions that have completed successfully.

=head2 actionsFailed()

Return the number of actions that have completed unsucessfully.

=head2 actionsUnrunnable()

Return the number of actions that are unrunnable.

=head2 actionsAborted()

Return the number of actions that have been aborted.

=cut

# fundamental
sub actionsWaiting    ($) { return scalar($_[0]->getWaitingActions());    }
sub actionsRunnable   ($) { return scalar($_[0]->getRunnableActions());   }
sub actionsRunning    ($) { return scalar($_[0]->getRunningActions());    }
sub actionsSuccessful ($) { return scalar($_[0]->getSuccessfulActions()); }
sub actionsFailed     ($) { return scalar($_[0]->getFailedActions());     }
sub actionsUnrunnable ($) { return scalar($_[0]->getUnrunnableActions()); }
sub actionsAborted    ($) { return scalar($_[0]->getAbortedActions());    }

=head2 actionsPending()

Return the combined number of actions that are either waiting or runnable.

=head2 actionsFinished()

Return the combined number of actions that have either succeeded, failed, or
been aborted.

=cut

# derived
sub actionsPending    ($) { return scalar($_[0]->getPendingActions());    }
sub actionsFinished   ($) { return scalar($_[0]->getFinishedActions());   }

#------------------------------------------------------------------------------

=head1 STATUS TRANSITION METHODS

=head2 getNextRunnableAction()

Return the first found action object whose status is C<IS_RUNNABLE>, or
C<undef> if no actions in this state are held by the task manager. If
more than one action is runnable, the action returned is (deliberately) not
deterministic.

=cut

# get a runnable action from the set of those available, or undef if no actions
# in the set are currently runnable.
sub getNextRunnableAction ($) {
    my $self=shift;

    foreach my $act ($self->getActions()) {
        if ($act->isRunnable) {
            debug2 "Next action: $act" if (Util::Message::get_debug >= 2);
            return $act;
        }
    }

    return undef;
}

=head2 propagateActionStatus($action [,$recurse])

This method propagates the status of the action specified as the first
argument to any actions held by the task manager that directly depend upon it,
changing their status as appropriate. If the optional second argument is true,
the changed status of dependent actions (if any) are in turn propagated until
all dependant actions, direct or indirect, have been notified.

The propagation of an action status depends on the status value:

=over 4

=item *

A status of C<IS_SUCCESS> causes C<setRequiredActionSucceeded> to be
called on each dependent action. Unless L<Task::Action> has been
subclassed, this causes the action triggering the
propagation to be removed from those actions' waiting lists, and
causes their status to transition from C<IS_WAITING> to C<IS_RUNNABLE>
if the waiting list becomes empty as a result. No recusion takes place
as the dependent actions affected must still run before their own
statuses can be propagated in turn.

=item *

A status of C<IS_FAILURE> or C<IS_ABORTED> causes
C<setRequiredActionFailed> to be called on each dependent action,
I<unless> that action has the I<fail OK> flag set (see
L<Task::Action/setFailOK>), in which case the failure is treated
as if it were a success and C<setRequiredActionSucceeded> is called
instead. Unless L<Task::Action> has been subclassed, propagating
a failure status to an action that does not have the I<fail OK> flag
set will cause its state to transition to I<IS_UNRUNNABLE>.

=back

=cut

# communicate a finished action's status to the actions waiting for it.
sub propagateActionStatus ($$;$) {
    my ($self,$act,$recurse)=@_;
    my $status=$act->getStatus();
    my $debug = Util::Message::get_debug();

    debug2 "Propagating action '$act' status: $status" if ($debug >= 2);

    foreach my $waitingact ($self->getWaitingActions()) {
	if ($waitingact->requiresAction($act)) {
	    debug2 "  to '$waitingact'" if ($debug >= 2);
	    if ($status==IS_SUCCESS or $act->getFailOK()) {
		$waitingact->setRequiredActionSucceeded($act);
	    } elsif ($status==IS_FAILURE or $status==IS_ABORTED
		     or $status==IS_UNRUNNABLE) {
		$waitingact->setRequiredActionFailed($act);
		$self->propagateActionStatus($waitingact,1); #chain reaction
	    } else {
		$self->throw("Cannot propagate action status $status");
	    }
	}
    }

    if ($status==IS_FAILURE or $status==IS_ABORTED or $status==IS_UNRUNNABLE) {
	#update the count - depending on the size of the chain reaction there
	#could be many of these.
	unless ($recurse) {
	    $self->{unrunnable}=$self->actionsUnrunnable();
	    $self->{queued}=$self->actionsPending();
	}
    }
}

#------------------------------------------------------------------------------

=head1 ACTION METHODS

These methods are involved with the execution of a set of task actions
held by a task manager. The most important of these, and in most cases the
only one client code will need to call directly, is L<"run">.

=head2 run([$concurrency[, $minconcurrency[, $loadcap]]])

Invoke the task set, executing all actions in valid dependency order. If no
concurrency argument is specified, the manager will attempt to execute all
actions in parallel (i.e. concurrency = number of actions defined).

With a concurrency argument, the number of concurrent actions executing in
parallel is limited to the specified positive integer value. If more actions
can run than are permitted at any given moment, the actions are set into
the C<IS_RUNNABLE> state until a running action completes and vacates its
'slot'. A concurrency argument of 1 causes the manager to execute actions
serially. In this case, the action is run directly and not invoked as a
subprocess.

By default, actions running concurrently are invoked as subprocesses, using
C<fork>. If the third optional argument is true, C<Task::Manager> will use
threads instead.

The set of configured actions held by the task manager is checked for
consistency of dependencies prior to starting execution, and an exception is
thrown if any action is configured with a dependency on a required action that
is not held by the task manager.

Start and end messages are automatically emitted by the task manager;
additional information can be generated by enabling debug or verbose messaging.
In particular, a verbose level of 1 will cause this method to emit progress
messages indicating the status counts of the actions in the task manager in
the order running, waiting, queued, failed (including aborted), and unrunnable.
(To silence the start and end messages see L<Util::Message/set_quiet>.)

If the optional C<$minconcurrency> and C<$maxload> parameters are
passed, then Task::Manager will monitor the local system load.  If the
load is below C<$maxload> then Task::Manager will spawn off new tasks
up to a maximum of C<$concurrency> tasks.  If system load is at or
above C<$maxload> then Task::Manager will keep no more than
C<$minconcurrency> tasks. (That is, you'll always have at least
C<$minconcurrency> tasks running, and if system load is less than
C<$maxload> then Task::Manager will keep C<$concurrency> tasks running)

=cut

# run all commands; return no. of unsuccessful commands or 0 if all succeeded
sub run ($;$$) {
    my ($self,$concurrency, $minconcurrency, $maxload)=@_;
    # Defaults to at least one task
    $minconcurrency ||= 1;
    # Zero means no load checking
    $maxload ||= 0;

    if (my @badacts=$self->check) {
        $self->throw("Undefined required actions in task set, cannot".
                     " execute:".join('',map { " '$_'" } @badacts));
    }

    $self->{jobs}       = scalar($self->getActions());
    $self->{queued}     = $self->{jobs};
    $self->{running}    = 0;
    $self->{failed}     = 0;
    $self->{failures}   = [];
    $self->{succeeded}  = 0;
    $self->{unrunnable} = 0;
    $self->{aborted}    = 0;
    $self->{started}    = time;

    $concurrency=$self->{jobs} unless $concurrency>0;

    my $msg = $self->{name} || "Running";
    my $xmsg = $msg?"$msg - ":"";
    alert("${xmsg}starting $self->{jobs} job".(($self->{jobs}==1)?"":"s"));

    my $debug = Util::Message::get_debug();
    PENDING: while (my $pending=$self->actionsPending()) {
	debug "$self->{running}/$concurrency running, ".
          $self->actionsRunnable()."/$pending waiting" if $debug;

	RUNNABLE: while (my $act=$self->getNextRunnableAction()
	       and ($self->{running} < $concurrency)) {
	    debug "going to run: $act" if $debug;
	    if ($concurrency==1) {
		$self->runAction($act);
		$self->propagateActionStatus($act);
		last PENDING if $self->_quitOnFailure($act);
	    } else {
		my $pid = $self->runActionConcurrently($act);
		if ($pid) {
		    debug "started: $act (pid $pid)" if $debug;
		} else {
		    # if the command can't start log it as a failure
		    $act->setStatus(IS_ABORTED);
		    $self->propagateActionStatus($act);
		    error "Unable to start $act" unless $pid;
		}
	    }
	}

	if ($concurrency>1) {
	    # either concurrency has been reached or all pending actions have
	    # unsatisfied dependencies - reap something
	    my $reaped = $self->retrieveAction();
	    $self->propagateActionStatus($reaped);
	    last PENDING if $self->_quitOnFailure($reaped);
	}
    }

    if ($concurrency>1) {
	# clean up outstanding processes
	$self->retrieveAction() while %{$self->{pids}};
    }

    if ($self->{failed}) {
	error("${xmsg}failed for $_") foreach @{$self->{failures}};
        error "${xmsg}failed ($self->{failed} failed, ".
	  "$self->{unrunnable} unrunnable, ".
	    "$self->{aborted} aborted, ".
	      "$self->{succeeded} succeeded of $self->{jobs})";
    }
    my $duration=time-$self->{started};
    alert "${xmsg}finished $self->{jobs} job".(($self->{jobs}==1)?"":"s").
          " in $duration seconds";

    # return no. of failures; 0=success
    return $self->{failed} + $self->{unrunnable} + $self->{aborted};
}

sub _report_status ($) {
    my ($self,$pid,$act,$rc)=@_;

    my $rcmsg=(defined $rc)?($rc?"FAILED ":"finished OK "):"started";
    my $verbose = Util::Message::get_verbose();
    verbose2 "$self action $act ($pid) $rcmsg" if ($verbose >= 2);
    verbose "$self [".
	  "$self->{running} running, ".
          "$self->{queued} queued, ".
          "$self->{succeeded} succeeded, ".
          ($self->{failed}+$self->{aborted})." failed, ".
          "$self->{unrunnable} unrunnable".
          "]" if $verbose;
}

=head2 runAction($action)

Run the action specified as the argument, returning its status to the caller.
Other than hosekeeping on behalf of the L<"run"> method, from which it is
invoked, this method is identical in effect to L<Task::Action/runAction>.

The action is not run in a subprocess, and so the method will not return until
it completes. This methos is invoked by L<"run"> when the concurrency is 1.

=cut

sub runAction ($$) {
    my ($self,$act)=@_;
    $act->setLogSub($self->{logsub});
    my $status=$act->runAction();
    $self->{queued}--;
    if ($status) {
	$self->{failed}++;
    } else {
	$self->{success}++;
    }
    return $status;
}

=head2 runActionAsProcess($action)

Run the action specified as the argument in a child process, returning the
process ID of the child process to the caller. Other than huosekeeping on
behalf of the L<"run"> method, from which it is invoked, this method is
identical in effect to L<Task::Action/runActionAsProcess>. (See also
L<"runAction"> above.)

This methos is invoked by L<"run"> when the concurrency is greater than 1.

=cut

sub runActionAsProcess ($$) {
    my ($self,$act)=@_;

    $act->setStatus(IS_RUNNING);
    $act->setLogSub($self->{logsub});
    my $pid = $act->runActionAsProcess();
    return undef unless $pid;

    $self->{pids}{$pid}=$act;
    $self->{running}++;
    $self->{queued}--;
    $self->_report_status($pid,$act);

    return $pid;
}


=head2 runActionConcurrently($action)

Overload method. This simply calls L<"runActionAsProcess"> in this base class.
Derived classes that implement different concurrency semantics should overload
this method to reference their alternate implementations. (See
L<Task::Threaded::Manager> for an example).

=cut

sub runActionConcurrently ($$) {
    return $_[0]->runActionAsProcess($_[1]);
}

# return true if the action status is a reason to quit
sub _quitOnFailure ($$) {
    my ($self,$act)=@_;

    if ($self->getQuitOnFailure() and
	($act->getStatus()==IS_FAILURE or
	 $act->getStatus()==IS_ABORTED)) {
	alert "Aborting on failure: $act";
	return 1;
    }

    return 0;
}

=head2 reapAction()

Reap a completed action child process in concurrent parallel execution,
blocking until a child process exit status becomes available if necessary.
Returns the action object for the completed process, or throws an exception
if reaping returned an unexpected child process ID. (Typically this is -1,
indicating that no child processes are running, and therefore no exit status
can possibly be reaped. This situation can only be achieved by adding a new
action with unresolvable dependences in the middle of executing the task set
without using L<"check">).

This method is used by L<"run"> below when running a task set concurrently
using C<fork>, and is not expected to be invoked directly except possbibly by
a derived class with a different implementation of L<"run">.

=cut

sub reapAction ($) {
    my $self=shift;
    my $pids=$self->{pids};
    my $debug = Util::Message::get_debug();

    debug "waiting for ".(scalar(keys %$pids)>1?"one of ":"").join(' ',map {
	"$pids->{$_} ($_)"
    } sort keys %$pids) if $debug;

    my $pid=waitpid(-1,0);
    my $rc = $?;
    my $act=$pids->{$pid};

    debug "returned from $act ($pid): ".($rc?"FAILED ($rc)":"OK") if $debug;
    if (exists $pids->{$pid}) {
        $act=delete $pids->{$pid};
    } else {
	foreach my $a (sort $self->getPendingActions()) {
	    my @waits=$a->getWaitingFor();
	    print "  $a [".$a->getStatus()."] waiting for [@waits]\n";
	}
        $self->throw("reaped unexpected child process $pid");
    }

    if ($rc) {
	$act->setStatus(IS_FAILURE);
	$self->{failed}++;
	push @{$self->{failures}}, $act;
    } else {
	$act->setStatus(IS_SUCCESS);
	$self->{succeeded}++;
    };
    $self->{running}--;
    $self->_report_status($pid,$act,$rc);

    return $act;
}

=head2 retrieveAction()

Overload method. Retrieve the return status of a completed action run
concurrently. In the base class forked implementation, this
calls L<"reapAction"> above.

=cut

sub retrieveAction() {
    return $_[0]->reapAction();
}

#------------------------------------------------------------------------------

=head2 check()

Verify that all action dependencies are resolved by correspondingly-named
actions held by the task manager. Returns the list of action names that
could not be resolved, or an empty list (false in scalar context) otherwise.

This method is automatically called by C<"run"> prior to starting execution
of a set of task actions.

=cut

sub check ($) {
    my $self=shift;

    my @errors;
    foreach my $action ($self->getActions) {
        foreach my $required ($action->getRequires) {
            push @errors, $required unless $self->getAction($required)
        }
    }

    return @errors;
}

#------------------------------------------------------------------------------

sub toString ($) { return $_[0]->{name}; }

#------------------------------------------------------------------------------

=head2 dump([$verbose])

Dump out details of each action held by the task manager, including their
names, argument list, and required actions.

=cut

sub dump ($;$) {
    my ($self,$verbose)=@_;

    $self->SUPER::dump() if $verbose;

    my @actions=sort $self->getActions();
    print scalar(@actions), " actions => @actions\n";
    foreach my $a (@actions) {
	my @args=$a->getArguments();
	my @reqs=$a->getRequires();
	print "  $a(",join(",",@args),")\n";
	print "    requires [@reqs]\n" if @reqs;
    }
}

#==============================================================================

sub test_succeed (@) {
    print "running test_succeed ($$): @_\n";
    sleep 1;
    return 0; #success
}

sub test_fail (@) {
    print "running test_fail ($$): @_\n";
    sleep 1;
    return 1; #failure
}

sub test {
    my $act1=new Task::Action({
	name     => "test1",
	action   => \&test_succeed,
	args     => [qw(1 2 3)]
    });

    my $act2=new Task::Action({
	name     => "test2",
	action   => \&test_succeed,
	args     => [qw(4 5 6)],
        requires => ["test1"]
    });

    my $act3=new Task::Action({
	name     => "test3",
	action   => \&test_fail,
	args     => [qw(7 8 9)],
        requires => ["test2"]
    });

    my $act4=new Task::Action({
	name     => "test4",
	action  => \&test_succeed,
	args     => [qw(1 4 9)],
        requires => ["test1","test3"]
    });

    my $act5=new Task::Action({
	name     => "test5",
	action  => \&test_succeed,
	args     => [qw(0 0 7)],
        requires => ["test1","test2"]
    });

    Util::Message::set_debug(2);

    my $mgr=new Task::Manager("Actions");
    print "Name (explicit): ",$mgr->getName(),"\n";
    print "Name (toString): $mgr\n";
    print "Actions: ",join(' ',$mgr->getActions()),"\n";
    $mgr->addAction($act1);
    print "Actions: ",join(' ',$mgr->getActions()),"\n";
    $mgr->addAction($act2);
    print "Actions: ",join(' ',$mgr->getActions()),"\n";
    $mgr->addActions($act3,$act4,$act5);
    print "Actions: ",join(' ',$mgr->getActions()),"\n";
    foreach ($mgr->getActions()) {
	print "    Action $_ status ",$_->getStatus(),"\n";
    }
    print "Runnable actions: ",
	join(' ',$mgr->getRunnableActions()),"\n";
    print "Waiting actions: ",
	join(' ',$mgr->getWaitingActions()),"\n";
    print "Pending actions: ",
	join(' ',$mgr->getPendingActions()),"\n";
    eval { $mgr->run(); };
    foreach ($mgr->getActions()) {
	print "    Action $_ status ",$_->getStatus(),"\n";
    }
    print "Done\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Task::Threaded::Manager>, L<Task::Action>, L<Task::Status>

=cut

1;
