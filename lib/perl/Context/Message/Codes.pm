package Context::Message::Codes;
use strict;

use base qw(Symbols);

use vars qw($OVERRIDE_PREFIX);
$OVERRIDE_PREFIX = "CONTEXT_MSG_";

#==============================================================================

=head1 NAME

Context::Message::Codes - Provide generic message codes for context messages

=head1 SYNOPSIS

    use Context::Message::Codes qw(NO_ERROR EMP_FILE);

=head1 DESCRIPTION

This module provides descriptive constants for generic message codes for use
with L<Context::Message>. Currently, the constants provided are:

    NO_ERROR   'no error'
    EMP_FILE   'file is empty'

Specific applications are expected to define their own constants to augment
the ones provided here. In general, message generation should use a 
descriptive constant rather than a literal string for message generation.

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)
Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<Context::Message>, L<Context::Message::Types>

=cut

#==============================================================================

1;

__DATA__

NO_ERROR       => no error
EMP_FILE       => file is empty
