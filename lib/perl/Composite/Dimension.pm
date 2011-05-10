package Composite::Dimension;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';
use BDE::Object;

#==============================================================================

=head1 NAME

Composite::Dimension - Superclass for a dimensional collapse module

=head1 SYNOPSIS

    package My::Simple::Dimension;
    use strict;
    use base 'Composite::Dimension';

    sub match {
        my ($self,$valueitem,$dimensionvalue)=@_;

        return ($valueitem->getAnAttribute() eq $dimensionvalue) ? 1 : 0;
    }

    sub matchDefault {
        my ($self,$valueitem)=@_;

        return $self->match($valueitem => 'a default value');
    }

    1;

=head1 DESCRIPTION

This module implements the superclass for dimensional collapse modules to
collapse a dimension of a L<Composite::Value> or L<Composite::ValueSet>.
A dimensional collapse module must implement a single method L<"match"> that
takes an object that is blessed into a child class of L<Composite::ValueItem>
and a candidate value to check it against. If the passed value item matches
the candidate value, 1 should be returned, otherwise 0 should be returned.
The criteria for matching are entirely up to the implementation of the module.

Optionally, a C<matchDefault> method may be supplied to provide the means to
collapse a dimension using a suitable default. For many dimensions this simply
means returning 1 to unconditionally match any supplied value item. For
dimensions that cannot collapse to a default, an exception should be thrown.
Otherwise, the value item should be passed to C<match> accompanied by a
suitable default value for the dimension. If no C<matchDefault> method is
provided, an exception is thrown by the superclass if an attempt is made to
collapse a dimension using a default value.

If a dimension needs to carry out any initialisation work, such as determining
a default value, it can implement 

=cut

#==============================================================================

sub initialiseDimension {
    my ($self,$args)=@_;
    # do nothing by default.
}

sub initialise {
    my ($self,$args)=@_;

    # verify that contract is satisfied by subclass
    $self->throw(ref($self)." does not implement 'match' method")
      unless $self->can("match");

    $self->SUPER::initialise($args);

    $self->initialiseDimension(); #for custom setup
}

sub fromString {
    my ($self,$init)=@_;

    $self->{attr}=$init; #the attribute this dimension controls - set by the
                         #registrant, so the dimension need not hardcode it

    return $self;
}

#------------------------------------------------------------------------------
# Registered attribute

sub getAttribute ($)  { return $_[0]->{attr}; }
sub setAttribute ($$) { $_[0]->{attr}=$_[1];  }

#------------------------------------------------------------------------------
# Get/set default dimension value

sub getDefault ($) {
    return $_[0]->{default} if exists $_[0]->{default};
    return $_[0]->DEFAULT() if $_[0]->can("DEFAULT");
}

sub setDefault ($$) {
    $_[0]->{default}=$_[1]; #what 'def' maps to
}

#------------------------------------------------------------------------------

# only used by dimensions that initialise their defaults from a valueset, this
# returns the name of the value that is scanned to establish the default for
# the dimension. The classical example is the compiler ID for build options,
# e.g. BDE_COMPILER_ID. The collapseDimensions method in C::VS takes this
# into account and sets the default prior to collapsing the dimension based
# on the current contents of the set. This has to be done in the C::VS because
# of course the set needs to be queried to find the value of BDE_COMPILER_ID
# (for example).
#
# The default behaviour is to look for a constant DIMENSION_CV in the subclass
# and return that, or undef if none is set.
sub getDimensionCV ($) {
    if ($_[0]->can("DIMENSION_CV")) {
	return $_[0]->DIMENSION_CV();
    }

    return undef;
}

#------------------------------------------------------------------------------

sub collapse ($$$;$) {
    my ($self,$setcvoritem,$dimensionvalue,$clone)=@_;

    $self->throw("Not a reference") unless ref $setcvoritem;
    $self->throw("No value") unless defined $dimensionvalue;

    if ($setcvoritem->isa("Composite::ValueItem")) {

        $setcvoritem=undef
          unless $self->match($setcvoritem => $dimensionvalue);

    } elsif ($setcvoritem->isa("Composite::Value")) {

	#print "CDc:$self($dimensionvalue) BEFORE ",$setcvoritem->dump(),"\n";

        my @items=$setcvoritem->getValueItems();
        @items = grep {
            $self->match($_ => $dimensionvalue);
        } @items;
        $setcvoritem=$setcvoritem->clone() if $clone;
        $setcvoritem->replaceAllValueItems(@items);

	#print "CDc:$self($dimensionvalue) AFTER ",$setcvoritem->dump(),"\n";

    } elsif ($setcvoritem->isa("Composite::ValueSet")) {
	# note that value sets can and should use $cvs->collapseDimension
	# in preference to this if they want to track state correctly.

        my @values=$setcvoritem->getValues();
        @values=map {
            $self->collapse($_, $dimensionvalue, $clone);
        } @values;
        $setcvoritem=$setcvoritem->clone() if $clone;
        $setcvoritem->replaceAllValues(@values);

    } else {

        $self->throw("$setcvoritem is not collapsible");

    }

    return $setcvoritem;
}

=head2 match($valueitem => $dimensionvalue)

To initiate a dimension collapse, the C<match> method should be overloaded
with a method that implements the collapse algorithm for that dimension. The
dimension value is passed as the only argument.

=cut

sub match {
    $_[0]->throw("No match method implemented for $_[0]");
}

=head2 matchDefault($valueitem)

If a dimension has default collapse criteria, the C<matchDefault> method
should be overloaded with a method that implements the default collapse
algorithm. See description and synopsis.

=cut

sub matchDefault {
    my ($self,$valueitem)=@_;

    if ($_[0]->can("DEFAULT")) {
	return $self->match($valueitem => $_[0]->DEFAULT());
    }

    $_[0]->throw("No default collapse criteria implemented for $_[0]");
}

#------------------------------------------------------------------------------

sub toString ($) {
    return (defined $_[0]->{attr}) ? $_[0]->{attr} : "noname";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=head1 SEE ALSO

L<Composite::Value>, L<Composite::ValueSet>

=cut

1;
