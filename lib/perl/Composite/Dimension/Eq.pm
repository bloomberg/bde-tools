package Composite::Dimension::Eq;
use strict;

use base 'Composite::Dimension';

#==============================================================================

=head1 NAME

Composite::Dimension::Eq - Basic string equality collapse superclass

=head1 DESCRIPTION

This dimensional collapse superclass provides the means to collapse a
dimension according to strict case-sensitive string equality. It does I<not>
recognize wildcards (use L<Composite::Dimension::WildEq> for that).

See L<Composite::Dimension>, from which this module is derived, for generic
information on dimensional collapse implementations.

=cut

#==============================================================================

sub match {
    my ($self,$value,$dimensionvalue)=@_;

    return ($value->{$self->toString() eq $dimensionvalue) ? 1 : 0;
}

sub matchDefault {
    return $_[0]->match($_[1] => $_[0]->DEFAULT);
}

#==============================================================================

=head1 SEE ALSO

L<Composite::Dimension::WildEq>, L<Composite::Dimension::Version>,
L<Composite::Dimension>

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
