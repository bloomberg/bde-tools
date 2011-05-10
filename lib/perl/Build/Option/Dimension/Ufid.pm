package Build::Option::Dimension::Ufid;
use strict;

use base 'Composite::Dimension';

use BDE::Build::Ufid;

# no DEFAULT_UFID

#==============================================================================

=head1 NAME

Build::Option::Dimension::Ufid - Implement dimensional collapse of Ufid

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

#==============================================================================

# $valueitem->{<attr>} and $dimensionvalue should be BDE::Build::Ufid objects
sub match {
    my ($self,$valueitem,$dimensionvalue)=@_;

    my $attr=$self->getAttribute(); #the attribute we were registered to

    # if the valueitem doesn't have a UFID at all, it matches 'all' of them.
    return 1 unless exists $valueitem->{$attr};

    foreach ($valueitem->{$attr}->getFlags) {
        return 0 unless $dimensionvalue->hasFlag($_);
    }

    return 1;
}

sub matchDefault {
    return 1; # all ufids match in the face of no requested ufid flags
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
