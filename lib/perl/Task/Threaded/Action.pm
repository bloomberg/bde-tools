package Task::Threaded::Action;
use strict;

require 5.008;

use threads qw(async);
use Thread::Queue qw(enqueue);

use vars qw(@ISA);

use base 'Task::Action';

use Util::Message qw(debug2 fatal);
use Task::Status;

#==============================================================================

=head1 NAME

Task::Action - Object instance representing an individual task action

=head1 SYNOPSIS

    use Task::Threaded::Action;

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

=head2 runActionAsThread()

Run the action as L<"runAction"> above, but in a child thread. The status
is automatically transitioned to C<IS_RUNNING> (irrespective of what the
status might formerly have been). Returns the thread ID of the child process.

=cut

sub runActionAsThread ($) {
    my $self=shift;

    return undef unless $self->{action};
    $self->setStatus(IS_RUNNING);

    my $thread=async {
        my $rc=$self->runAction();
        my $tid=threads->self()->tid();
        $self->{threadqueue}->enqueue($tid); #indicate we're done
        return $rc;
    };

    return $thread->tid();
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Task::Threaded::Action>, L<Task::Manager>, L<Task::Status>

=cut

1;
