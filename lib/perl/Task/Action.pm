package Task::Action;
use strict;

use vars qw(@ISA);
use overload '""' => "toString", fallback => 1;
use constant FORK_RETRY_COUNT => 10;

use BDE::Object;
@ISA=qw(BDE::Object);

use Util::Message qw(debug2 fatal verbose log_only);
use Task::Status;
use Change::Symbols qw(USER);

#==============================================================================

=head1 NAME

Task::Action - Object instance representing an individual task action

=head1 SYNOPSIS

    use Task::Action;

    sub action_sub (@) {
        print "running action sub: @_\n";
        return 0; #success
    }

    my $action=new Task::Action({
	name   => "example",
	action => \&action_sub,
	args   => [qw(1 2 3)]
    });

    print "Action name: $action\n";
    print "Action status before: ",$cmd1->getStatus(),"\n";
    $action->runAction();
    print "Action status after : ",$cmd1->getStatus(),"\n";

See the test section at the end of the module source for an extended usage
example.

=head1 DESCRIPTION

C<Task::Action> provides the implementation of an individual task action. At
minimum, a task action instance consists of a name and a subroutine code
reference, which is executed when the action is run. Optional argments may be
provided to be passed to the subroutine when it is executed. A list of
required actions may also be defined, and if present is managed by an
instance of L<Task::Manager> to carry out dependency-aware task action sets.

Each action has an associated state, from the list defined in L<Task::Status>.
When an action is run, its status is transitioned to reflect where it is in
its execution cycle. Propagation of action stati to dependent actions is
in turn managed by the controlling L<Task::Manager> instance.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new($name)

Create a new action object with the specified string argument. All attributes
of the action other than the name are empty; to make the action runnable the
L<"setAction"> method must be used to provide a subroutine code reference
for the action to execute.

=head2 new($hashref)

Create a new action object from the specified attribute hash. Valid attributes
are:

    name     - the action name
    action   - the subroutine code reference to execute
    args     - optional arguments to pass to the subroutine on invocation
    requires - array reference of actions on which this action depends
    failok   - allows the action to run even if a dependent action fails

See the L<"setName">, L<"setAction">, L<"setRequires">, and L<"setFailOK">
methods for more information on each of these attributes.

=cut

sub fromString ($$) {
    my ($self,$init)=@_;

    $self->{name}=$init;
    # base attributes
    $self->{location}   = ""; # directory context for command
    $self->{action}     = ""; # what to do, coderef or shell command
    $self->{args}       = []; # sub or CLI arguments
    # advanced attributes
    $self->{requires}   = {}; # dependent actions of this action
    $self->{failok}     = 0;  # dependent actions not runnable if we fail
    $self->{waitingfor} = {}; # still-pending dependent actions
    $self->{logsub}     = \&verbose; # Default to verbose logging

    $self->resetStatus();     # set up initial status
    return $self;
}

sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->SUPER::initialiseFromHash($args);
    # base attributes
    $self->{name}       ||= "unnamed";
    $self->{location}   ||= "";
    $self->{action}     ||= "";
    $self->{args}       ||= [];
    # advanced attributes
    if ($self->{requires}) {
	$self->{requires} = { map {$_=>1} @{$self->{requires}}};
    } else {
	$self->{requires} = {}
    }
    $self->{failok}     ||= 0;
    $self->{waitingfor} ||= { %{$self->{requires}} };
    $self->{logsub}     ||= \&verbose;

    $self->throw("Attribute 'args' not an array ref")
	unless (ref $self->{args});

    $self->resetStatus();
    return $self;
}

#------------------------------------------------------------------------------

=head1 ACCESSORS/MUTATORS

=head2 getName()

Get the name for this action. The action name is used in required action
lists -- see L<"setRequires"> -- to establish action dependencies, as well as
being returned when the action object is evaluated in string context (unless
the C<toString> method is overloaded).

=head2 setName($action_name)

Set the name for this action. See L<"getName">.

=cut

sub getName       ($)  { return $_[0]->{name};      }
sub setName       ($$) { $_[0]->{name} = $_[1];     }

=head2 getAction()

Get the code reference configured as the executable action for this action
object, or return C<undef> if no action is currently set.

=head2 setAction($code_ref [,@args])

Set the code reference for the executable action for this action object,
optionally followed by one or more arguments to be passed as subroutine
parameters. Throws an exception if the first agument is not a code reference.
If any subroutine parameter arguments are specified, they replace any
existing configured arguments (see also L<"setArguments">).

=cut

sub getAction     ($)  { return $_[0]->{action};    }

sub setAction     ($@) {
    my ($self,$cref,@args)=@_;
    if (ref($cref) eq "CODE") {
	$self->{action} = $cref;
	$self->{args}=[@args] if @args;
    } else {
	$self->throw("action must be code reference");
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

=head2 getStatus()

Get the status of this action. See also L<"STATUS METHODS">, below, for methods
to test for a specific state, as described by L<Task::Status>.

=head2 setStatus($status)

Set the action status. The passed status should be one of the symbolic
constants provided by L<Task::Status>. If the specified status lies outside the
range of valid status values, an exception is thrown. Note that it should
be considered unusual to call this methos directly; state management is
more usually handled by methods that transition state like L<"runAction">, in
collaboration with a controlling task manager instance.

=cut

sub getStatus     ($)  { return $_[0]->{status};    }

sub setStatus     ($$) {
    $_[0]->throw("Invalid status")
      unless defined($_[1]) and $_[1]<=MAX_STATUS and $_[1]>=MIN_STATUS;
    $_[0]->{status} = $_[1];
}

=head2 resetStatus()

Reset the action status to the appropriate initial state. For actions that have
required actions configured, this is C<IS_WAITING>. For actions that have no
required actions, it is C<IS_RUNNABLE>.

=cut

sub resetStatus   ($)  {
    my $self=shift;

    if ($self->getRequires()) {
        $self->setStatus(IS_WAITING);
    } else {
        $self->setStatus(IS_RUNNABLE);
    }
}

# currently unused, will be used for CWD when action can also be cmdline.
sub getLocation   ($)  { return $_[0]->{location};  }
sub setLocation   ($$) { $_[0]->{location} = $_[1]; }

=head2 getFailOK()

Get the current value of the I<fail OK> flag for this action object.

=head2 setFailOK($boolean)

Set the I<fail OK> flag for this action. If this flag is set to a true value
then any failing required action is considered a success by this action,
rather than a failure.

Note that the I<fail OK> flag is considered by the controling task manager
only, and not by the action object itself. In particular, this means that
L<"setRequiredActionFailed"> does I<not> respect this flag.

=cut

sub getFailOK     ($)  { return $_[0]->{failok};    }
sub setFailOK     ($$) { $_[0]->{failok} = $_[1];   }

=head2 getArguments()

Get the subroutine arguments currently configured for this action.

=head2 setArguments(@args)

Set the subroutine arguments for this action. These arguments are passed as
parameters to the subroutine code reference set for the action, e.g. by
L<"setAction">. Any existing arguments are replaced and discarded.

=head2 addArguments(@args)

Add the specified arguments to the end of the list of arguments configured
for this action. Otherwise like L<"setArguments"> above.

=cut

sub getArguments  ($)  { return @{$_[0]->{args}};       }
sub setArguments  ($@) { my $self=shift; $self->{args}=[@_]; }
sub addArguments  ($@) { my $self=shift; push @{$self->{args}},@_; }

=head2 getRequires()

Return the list of actions on which this action depends.

=head2 setRequires(@required_action_names)

Set the list of actions on which this action depends, replacing any existing
list, if present. Note that no check is (or can be) made by the action object
to determine if any of the specified actions exist or are present in the
controlling task manager. Pass no arguments or an empty list to clear all
current required actions.

=head2 addRequires(@required_action_names)

Add the specified actions to the existing list of actions on which this
action depends, retaining any existing actions. Duplicate actions are
eliminated.

=cut

sub getRequires   ($)  { return keys %{$_[0]->{requires}};   }
sub setRequires   ($@) { my $self=shift; $self->{requires}={map{$_=>1} @_}; }
sub addRequires   ($@) { my $self=shift; $self->{requires}{$_}=1 foreach @_; }

=head2 requiresAction($action_name)

Return true if this action requires the action specified as the passed
argument, or false otherwise. The argument may be either an action object or
simply the action name provided as a simple string value.

=cut

sub requiresAction ($$) {
    my ($self,$depcmd)=@_;

    return 1 if exists $self->{requires}{$depcmd};
    return 0;
}

=head2 getWaitingFor()

Return the list of actions on which this action depends that it is currently
waiting for. This list is initally equal to the list of required actions
(see L<"getRequires">), but the controlling task manager reduces its size by
one value by calling L<"setRequiredActionSucceeded"> each time a required
action succeeds. When no values are left in the list, the action may be run.

This list represents part of the action's state during the execution of a
set of actions by the controlling task manager. As a consequence, no
method exists to clear or set it. To adjust the required actions of an
action, use L<"setRequires"> or L<"addRequires">.

=cut

sub getWaitingFor ($)  { return keys %{$_[0]->{waitingfor}}; }

#------------------------------------------------------------------------------

=head1 STATUS QUERY METHODS

These methods test the current status of the action against a specific state.
Note that management and transition between these states is handled by the
controlling task manager, not the actions themselves.

=head2 isSucceeded()

Return true if the action has executed successfully, or false otherwise.

=head2 isFailed()

Return true if the action has executed unsuccessfully, or false otherwise.

=head2 isWaiting()

Return true if the action is waiting for one or more required actions to
complete before it can run, or false otherwise.

=head2 isRunnable()

Return true if the action is not waiting on any required actions and is
now waiting to be run by the task manager.

=head2 isUnrunnable()

Return true if the action cannot be run because one of the required actions
it depended upon has failed and it did not have the 'fail OK' flag set (see
L<"setFailOK">), or false otherwise.

=head2 isAborted()

Return true if the action was aborted, or false otherwise.

=cut

sub isSucceeded   ($) { return $_[0]->{status}==IS_SUCCESS;    }
sub isFailed      ($) { return $_[0]->{status}==IS_FAILURE;    }
sub isWaiting     ($) { return $_[0]->{status}==IS_WAITING;    }
sub isRunnable    ($) { return $_[0]->{status}==IS_RUNNABLE;   }
sub isRunning     ($) { return $_[0]->{status}==IS_RUNNING;    }
sub isUnrunnable  ($) { return $_[0]->{status}==IS_UNRUNNABLE; }
sub isAborted     ($) { return $_[0]->{status}==IS_ABORTED;    }

#------------------------------------------------------------------------------

=head1 STATUS TRANSITION METHODS

=head2 removeWaitingFor($action_name)

Remove the action specified as the passed argument from the list of actions
on which this action depends (i.e. the list of waiting actions). Returns
true if the action was found and removed. Throws an exception if the action
whose removal was requested was not a required action of this action.

=cut

sub removeWaitingFor ($$) {
    my ($self,$depcmd)=@_;

    unless ($self->requiresAction($depcmd)) {
	$self->throw("$self does not require $depcmd");
	return undef;
    }

    delete $self->{waitingfor}{$depcmd};
    return 1;
}

=head2 setRequiredActionSucceeded($reqired_action_name)

Inform the action that an action on which it depends has completed
successfully and remove the required action from the list of waiting
dependencies (see L<"removeWaitingFor">). Throws an exception if the
specified action is not in the waiting list.

If no required actions are left in the waiting list, the action status
is transitioned to C<IS_RUNNABLE>.

=cut

sub setRequiredActionSucceeded ($$) {
    my ($self,$depcmd)=@_;

    if ($self->removeWaitingFor($depcmd)) {
	unless ($self->getWaitingFor()) {
	    $self->setStatus(IS_RUNNABLE);
	}
    }

    return undef;
}

=head2 setRequiredActionFailed($required_action_name)

Inform the action that an action on which it depends has completed
unsuccessfully. Throw an exception if the specified action is not in the
waiting list. The action status is transitioned to C<IS_UNRUNNABLE>.

=cut

sub setRequiredActionFailed ($$) {
    my ($self,$depcmd)=@_;

    unless ($self->requiresAction($depcmd)) {
	$self->throw("$self does not require $depcmd");
	return undef;
    }

    $self->{requires}{$depcmd}=0; #indicate failure, initially set to 1

    $self->setStatus(IS_UNRUNNABLE);
}

#------------------------------------------------------------------------------

=head1 ACTION METHODS

=head2 runAction()

Run the action -- execute the code reference (e.g. specified by L<"setAction">)
with the configured arguments (e.g. specified by L<"setArguments">). Return
C<IS_SUCCESS> if the code reference call returns a false value (i.e. 0, "",
C<undef>, etc.), or C<IS_FAILURE> otherwise.

=cut

sub runAction ($) {
    my $self=shift;

    my $action=$self->getAction();
    my @args=$self->getArguments();

    $self->setStatus(IS_RUNNING);
    if (ref $action) {
	my $status=$action->(@args);
	$self->setStatus($status?IS_FAILURE:IS_SUCCESS);
	$self->{logsub}->($self->{name} . " " . ($status?'failed':'succeeded'));
    } else {
	$self->throw("Execute action not implemented");
	# my $pid=retry_open3...
    }

    return $self->getStatus();
}

=head2 runActionAsProcess()

Run the action as L<"runAction"> above, but in a child process. The status
is automatically transitioned to C<IS_RUNNING> (irrespective of what the
status might formerly have been). Returns the process ID of the child process.

=cut

sub runActionAsProcess ($) {
    my $self=shift;

    return undef unless $self->{action};
    $self->setStatus(IS_RUNNING);

    # Running the action can fail if we can't fork, so we need to take
    # this possibility into account
    my $retrycount = FORK_RETRY_COUNT;
    my $backoff = 1;
    my $pid = -1;
    while ($retrycount--) {
      $pid=fork;

      # Did it fail?
      if (!defined $pid) {
	sleep $backoff;
	$backoff *= 2;
	if (FORK_RETRY_COUNT - $retrycount > 3) {
	  my $user = USER;
	  if ($user eq 'noname') {
	    $user = getpwuid($<);
	  }
	  log_only("Fork failed, on retry " . (FORK_RETRY_COUNT - $retrycount) . " for parent pid $$, user $user");
	  dump_pt();
	}

	next;
      }

      # Are we in the kid?
      if (!$pid) {
	my $status=$self->runAction();
	exit $status;
      }

      # Anything else means we spawned a kid OK
      if ($pid) {
	return $pid;
      }
    }

    # Right, if we got here then we didn't succeed. Note that fact
    $self->setStatus(IS_ABORTED);
    return;
}

sub dump_pt {
  return unless $^O eq 'solaris';

  foreach my $fn (</proc/*/psinfo>) {
    my $fh;
    open $fh, "<$fn" or next;
    my $data;
    read $fh, $data, 800;
    close $fh;
    my (undef, $nlwp, $pid, $ppid, $pgid, $sid, $uid, $euid, $gid, $egid) 
      = unpack('i10', $data);
    my $name = substr($data, 88, 16);
    $name =~ s/\x00+$//;
    my $args = substr($data, 104, 80);
    $args =~ s/\x00+$//;
    log_only(join("\t", 'pid', $pid, 'parent', $ppid, 'uid', $uid, 'euid', $euid, 'sid', $sid, $name, $args));
  }
}

#------------------------------------------------------------------------------

sub toString ($) { return $_[0]->{name}; }

#==============================================================================

sub test1 (@) {
    print "running test 1: @_\n";
    return 0; #success
}

sub test2 (@) {
    print "running test 2: @_\n";
    return 1; #failure
}

sub test {
    my $cmd1=new Task::Action({
	name    => "test1",
	action => \&test1,
	args    => [qw(1 2 3)]
    });

    print "Action 1 name (explicit): ",$cmd1->getName(),"\n";
    print "Action 1 name (toString): $cmd1\n";
    print "Action 1 status before  : ",$cmd1->getStatus(),"\n";
    $cmd1->runAction();
    print "Action 1 status after   : ",$cmd1->getStatus(),"\n";

    my $cmd2=new Task::Action({
	name     => "test2",
	action   => \&test2,
	args     => [qw(1 2 3)],
        requires => ["test1"]
    });

    print "Action 2 name (explicit): ",$cmd2->getName(),"\n";
    print "Action 2 name (toString): $cmd2\n";
    print "Action 2 status before  : ",$cmd2->getStatus(),"\n";
    $cmd2->runAction();
    print "Action 2 status after   : ",$cmd2->getStatus(),"\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Task::Threaded::Action>, L<Task::Manager>, L<Task::Status>

=cut

1;
