package Task::Threaded::Manager;
use strict;

use threads qw(async); # requires Perl 5.8!
use Thread::Queue qw(dequeue);

use base 'Task::Manager';

use Task::Status;
use Task::Action;
use Util::Message qw(alert debug debug2 message error fatal verbose verbose2);

#==============================================================================

=head1 NAME

Task::Threaded::Manager - Threaded implementation of task manager

=head1 SYNOPSIS

See L<Task::Manager>

=head1 DESCRIPTION

C<Task::Threaded::Manager> is a threaded implementation of L<Task::Manager>.
It makes use of the L<Task::Threaded::Action> class to implement actions, but
is otherwise identical in operation to the forked version.

=cut

#==============================================================================

=head2 runActionAsThread($action)

Run the action specified as the argument in a child thread, returning the
thread object to the caller. Other than housekeeping on
behalf of the L<"run"> method, from which it is invoked, this method is
identical in effect to L<Task::Action/runActionAsThread>. (See also
L<"runAction"> above.)

This methos is invoked by L<"run"> when the concurrency is greater than 1.

=cut

sub runActionAsThread ($$) {
    my ($self,$act)=@_;

    $act->setStatus(IS_RUNNING);
    $act->{threadqueue}=$self->{threadqueue};
    my $tid = $act->runActionAsThread();
    return undef unless $tid;

    $self->{pids}{$tid}=$act;
    $self->{running}++;
    $self->{queued}--;
    $self->_report_status($tid,$act);

    return $tid;
}

=head2 runActionConcurrently($action)

Overload method. Overloads the base class to call L<"runActionAsThread">
instead of L<Task::Manager/runActionAsProcess>.

=cut

sub runActionConcurrently ($$) {
    return $_[0]->runActionAsThread($_[1]);
}

#------------------------------------------------------------------------------

=head2 joinAction()

Join a completed action child thread in concurrent parallel execution,
blocking until a child thread return status becomes available if necessary.
Returns the action object for the completed thread, or throws an exception
if joining returned an unexpected result.

This method is used by L<"run"> below when running a task set concurrently
using threads, and is not expected to be invoked directly except possbibly by
a derived class with a different implementation of L<"run">.

=cut

sub joinAction ($) {
    my $self=shift;
    my $pids=$self->{pids};
    my $debug = Util::Message::get_debug();

    debug "waiting for ".(scalar(keys %$pids)>1?"one of ":"").join(' ',map {
	"$pids->{$_} ($_)"
    } sort keys %$pids) if $debug;

    my $pid=$self->{threadqueue}->dequeue(); # actually a tid this time
    my $act=$pids->{$pid};
    my $thread=threads->object($pid);
    my $rc=$thread->join();

    debug "joined from $act ($pid): ".($rc?"FAILED ($rc)":"OK") if $debug;
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

Overload method. Overloads the base class to call L<"joinAction">
instead of L<Task::Manager/reapAction>.

=cut

sub retrieveAction ($) {
    return $_[0]->joinAction();
}

#------------------------------------------------------------------------------

# As the base class but throw an error if it isn't a threaded action
sub setAction ($$) {
    my ($self,$act)=@_;

    $self->throw("Not a action") unless $act->isa("Task::Threaded::Action");
    $self->SUPER::setAction($act);
}

# As the base class but initialise a thread queue for the talk-back mechanism.
# This queue is passed to task actions so they can pass their TIDs to the
# manager to indicate that they are done.
sub run ($;$) {
    my ($self,$concurrency)=@_;

    debug "$self running threaded";
    $self->{threadqueue}=new Thread::Queue;

    return $self->SUPER::run($concurrency);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Task::Action>, L<Task::Status>

=cut

1;
