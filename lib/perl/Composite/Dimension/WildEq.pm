package Composite::Dimension::WildEq;
use strict;

use base 'Composite::Dimension';

#==============================================================================

=head1 NAME

Composite::Dimension::WildEq - Wildcarded string equality collapse superclass

=head1 DESCRIPTION

This dimensional collapse superclass provides the means to collapse a
dimension according to case-sensitive string equality or a wildcard. Either
the test value or the current value may be wildcarded (equal to C<"*">) for
a successful match.

See L<Composite::Dimension>, from which this module is derived, for generic
information on dimensional collapse implementations.

=cut

#==============================================================================

sub match {
    my ($self,$value,$dimensionvalue)=@_;

    $self->throw("What's this? $value") unless ref $value;

    my $testvalue=$value->{$self->getAttribute()};
    return 1 if (not $testvalue) or $testvalue eq '*';
    return 1 if $dimensionvalue eq '*'; #<<<TODO: review this idea later
    return ($testvalue eq $dimensionvalue) ? 1 : 0;
}

sub matchDefault {
    return $_[0]->match($_[1] => $_[0]->DEFAULT);
}

#==============================================================================

=head1 SEE ALSO

L<Composite::Dimension::Eq>, L<Composite::Dimension::Version>,
L<Composite::Dimension>

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
