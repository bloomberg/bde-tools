package Build::Option::Dimension::OS;
use strict;

use base 'Composite::Dimension::WildEq';

use constant DEFAULT => "SunOS";

#==============================================================================

=head1 NAME

Build::Option::Dimension::OS - Implement dimensional collapse of OS

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

#==============================================================================

sub match {
    my ($self,$value,$dimensionvalue)=@_;

    my $os=$value->getOS();
    return 1 if (not $os) or $os eq '*';
    return ($os eq $dimensionvalue) ? 1 : 0;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
