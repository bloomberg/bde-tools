package Build::Option::Dimension::Compiler;
use strict;

use base 'Composite::Dimension::WildEq';

use constant DEFAULT => "def";

use constant DIMENSION_CV => "BDE_COMPILER_FLAG";

#==============================================================================

=head1 NAME

Build::Option::Dimension::Comp - Implement dimensional collapse of compiler

=cut

#==============================================================================

sub match {
    my ($self,$valueitem,$dimensionvalue)=@_;
    return 1 if $self->SUPER::match($valueitem,$dimensionvalue); #handle '*'

    my $attr=$self->getAttribute(); #the attribute we were registered to

    my $default=$self->getDefault(); #the calculated default compiler id
    my $compiler=$valueitem->{$attr};

#print STDERR $valueitem->dump(),"\n";
#print STDERR "at:",$attr,"\n";
#print STDERR "DV:$dimensionvalue\n";
#print STDERR "DF:",$self->DEFAULT,"\n";
#print STDERR "df:",$default,"\n";
#print STDERR "is:",$compiler,"\n";

    if ($dimensionvalue eq $self->DEFAULT or $dimensionvalue eq $default) {
	# if the dimensionvalue is the default 'def' or is the
	# 'true' default compiler, as calculated, then either 'def'
	# or the true default compiler are valid
	return 1 if $compiler eq $self->DEFAULT or $compiler eq $default;
    } else {
	# otherwise, we need an explcit match
	return 1 if $compiler eq $dimensionvalue;
    }

    return 0;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
