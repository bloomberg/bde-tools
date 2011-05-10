package Task::Status;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT);
@ISA=qw(Exporter);

@EXPORT=qw[
    IS_SUCCESS IS_FAILURE IS_WAITING IS_RUNNABLE
    IS_RUNNING IS_UNRUNNABLE IS_ABORTED
    MAX_STATUS MIN_STATUS
];

#<<<TODO: convert this module into a derived class of Symbols.pm

#==============================================================================

=head1 NAME

Task::Status - Define standard status constants for task actions

=head1 DESCRIPTION

This module provides exportable constants for task action stati, as used by
L<Task::Manager> and L<Task::Action>. The currently defined stati, their
underlying numeric values, and their meanings are detailed below:

  IS_SUCCESS      0    Action has been run and completed successfully
  IS_FAILURE      1    Action has been run and completed unsuccessfully
  IS_WAITING      2    Action is waiting for a dependent action to complete
  IS_RUNNABLE     3    Action has no pending dependents and is waiting to run
  IS_RUNNING      4    Action is currently running
  IS_UNRUNNABLE   5    Action cannot be run because a dependent action failed
  IS_ABORTED      6    Action was aborted

The numeric value of a status should be considered opaque. However, status
constants are defined to be monotonically numeric positive integer values,
counting from zero. The highest and lowest currently defined constant are
defined by:

  MIN_STATUS      0
  MAX_STATUS      6

This implies that the set of all status values is the range
C<MIN_STATUS>..C<MAX_STATUS>, and so they may be iterated over if required.

Note that L<Task::Action> provides methods to check the status of an action
against each specific state, so it is often not necessary to import these
symbols to check state. See L<Task::Action/"STATUS QUERY METHODS">.

=cut

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Task::Manager>, L<Task::Action>

=cut

1;

#==============================================================================

use constant MIN_STATUS    => 0;

use constant IS_SUCCESS    => 0;
use constant IS_FAILURE    => 1;
use constant IS_WAITING    => 2;
use constant IS_RUNNABLE   => 3;
use constant IS_RUNNING    => 4;
use constant IS_UNRUNNABLE => 5; #a required action IS_FAILURE
use constant IS_ABORTED    => 6; #command was unable to run

use constant MAX_STATUS    => 6;
