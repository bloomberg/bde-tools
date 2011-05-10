package Context::Message::Types;

use Symbols;
use vars qw(@ISA $OVERRIDE_PREFIX);
@ISA=qw(Symbols);

$OVERRIDE_PREFIX = "CONTEXT_LEVEL_";

#==============================================================================

=head1 NAME

Context::Message::Types - Provide generic message codes for context messages

=head1 SYNOPSIS

    use Context::Message::Types qw(IS_EMERGENCY EMERGENCY_NAME);

=head1 DESCRIPTION

This module provides constants for generic message types for use with 
L<Context::Message>. Each type is associated with two symbols, one that
provides an abstract numeric severity level and one that provides a
descriptive name for use in generated messages.

=head2 Message Type Severity Constants

    IS_EMERGENCY      60
    IS_ALERT          50
    IS_CRITICAL       40
    IS_ERROR          30
    IS_WARNING        20
    IS_NOTICE         10
    IS_INFO           0
    IS_DEBUG          -10

=head2 Message Type Descriptive Names

    EMERGENCY_NAME    '!! EMERGENCY'
    ALERT_NAME        '!! ERROR ALERT'
    CRITICAL_NAME     '!! CRITICAL ERROR'
    ERROR_NAME        '!! ERROR'
    WARNING_NAME      '?? Warning'
    NOTICE_NAME       '** '
    INFO_NAME         '-- '
    DEBUG_NAME        '[[ '

Note that C<NOTICE_NAME>, C<INFO_NAME>, and C<DEBUG_NAME> correlate with
the corresponding message types in L<Util::Message>.

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)
Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<Context::Message>, L<Context::Message::Codes>, L<Context::Log>

=cut

#==============================================================================

1;

__DATA__

IS_EMERGENCY   => 60
IS_ALERT       => 50
IS_CRITICAL    => 40
IS_ERROR       => 30
IS_WARNING     => 20
IS_NOTICE      => 10
IS_INFO        => 0
IS_DEBUG       => -10

EMERGENCY_NAME => '!! EMERGENCY'
ALERT_NAME     => '!! ERROR ALERT'
CRITICAL_NAME  => '!! CRITICAL ERROR'
ERROR_NAME     => '!! ERROR'
WARNING_NAME   => '?? Warning'
NOTICE_NAME    => '** '
INFO_NAME      => '-- '
DEBUG_NAME     => '[[ '
