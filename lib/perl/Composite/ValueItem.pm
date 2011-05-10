package Composite::ValueItem;
use strict;

use overload '""' => "toString",
             '+=' => "addeq",
             '+'  => "add",
             fallback => 1;

use Composite::Commands qw(ADD INSERT APPEND OVERRIDE RESET PREPEND);

use base 'BDE::Object';

#==============================================================================

=head1 NAME

Composite::ValueItem - Superclass for individual items of a composite value

=head1 SYNOPSIS

    package My::Derived::ValueItem;

    use base 'Composite::ValueItem';

    # implement additional dimension attributes...

    1;

Then:

    use Composite::Commands qw(ADD);

    my $deriveditem=new My::Derived::Item({
        name    => "item_name",
        value   => "item_value",
        command => ADD
    });

    $deriveditem += $deriveditem; # append item value to itself

    print $deriveditem,"\n";         # 'item_value item_value'
    print $deriveditem->toString(1); # 'item_name=item_value item_value'

=head1 DESCRIPTION

C<Composite::ValueItem> implements a superclass for value item classes, which
are the individual entries in a composite value. When all the dimensions of
a composite value have been collapsed (see L<Composite::Dimension>), the
value items can be combined additively to generate the final concrete value.

All value items are provided with a name, a value, and a command:

=over 4

=item * Value items generally start off with a name, although the name is
        usually removed once the item has been placed into a composite value
        (since the composite value then carries the name). After this point,
        the item becomes anonymous.

=item * The value of a value item is simply its text representation, and is
        the content that is combined with other value items when a composite
        value is rendered.

=item * The command is technically optional, but is generally used by the
        combining algorithm implemented by the value item class to determine
        how two value items are added together. This is the algorithm
        implemented in the superclass in the event a child class does not
        implement an alternate algorithm.

=back

In addition, child classes of this class should provide, at their discretion,
support for any dimensions that the value items contains. These dimensions
are collapsed in the composite value to remove value items from the composite
value until all uncertainty has been resolved and it can be rendered.

C<Composite::ValueItem> instances are not typically created directly. Derived
classes are usually generated through an appropriate parser/generator
mechanism such as L<Build::Option::Parser>, which creates derived class
L<Build::Option::Raw> instances.

=cut

#==============================================================================

=head1 OPERATORS

C<Composite::ValueItem> overloads the C<""> (stringify), C<+>, and C<+=>
operators:

=head2 C<""> (stringify)

In string context, the value of the value items is returned. Note that this is
unusual in the sense that most objects that provide a string context
representation return their name and not their value.

The underlying method is L<"toString">.

=head2 C<+>

The C<+> operator returns a new value item that is the result of combining the
two operand value items according to the command of the second (right hand)
operand. The command of the first (left hand) operand is not relevant and is
ignored.

The underlying method is L<"add">.

=head2 C<+=>

The C<+=> operator modifies the left operand to hold the result of combining
it with the right operand, as C<+> above. Note that C<+=> is more efficient
than using C<+> and then C<=> to assign the result to the value item used as
the left operand, since it avoids the creation of a new value item instance.

The underlying method is L<"addeq">.

=cut

#------------------------------------------------------------------------------

=head1 METHODS

Every value item has at mimimum a command, a name, and a value. Other
attributes may (and certainly will) be added by individual subclasses.

=head2 getCommand()

Get the command for this value item. Returns C<undef> is no command has been
set.

=head2 setCommand($command)

Set the command for this value item. The command argument should be one of the
command constants defined in L<Composite::Commands>. Setting a command that
does not exist will cause the value item to throw an exception if it is used
as the right operand of a C<+> or C<+=> operation.

=cut

sub getCommand ($) {
    return $_[0]->{command} || undef;
}

sub setCommand ($$) {
    $_[0]->{command} = $_[1]; #<<<TODO: check against commandset symbols
}

=head2 getName()

Get the name of this value item. Returns C<undef> if no name has been set. Note
that the name is explicitly cleared when a value item is added to a composite
value (as the value carries the name, its members become anonymous).

=head2 setName($name)

Set the name of this value item to the specified string argument.

=head2 clearName()

Clear the name of this value item. Used by C<Composite::Value>, see
L<"getName"> above.

=cut

sub getName ($) {
    return $_[0]->{name} || undef;
}

sub setName ($$) {
    $_[0]->{name} = $_[1];
}

sub clearName ($) {
    return delete $_[0]->{name};
}

=head2 getValue()

Get the value of this value item. Returns C<undef> if no value has been set.

=head2 setValue($value)

Set the value of this value item to the specified string argument.

=cut

sub getValue ($) {
    return $_[0]->{value} || undef;
}

sub setValue ($$) {
    $_[0]->{value} = $_[1];
}

#------------------------------------------------------------------------------
# generic dimension attribute accessor/nutator.

=head2 getValue($dimension)

Get the value of the specified dimension for this value item.

=head2 setValue($dimension,$value)

Set the value of the specified dimension for this value item to the specified
string argument. (Note that there are unlikely to be many situations in which
this method would be called.)

=cut

sub getDimensionValue ($$) {
    # if $_[1] is in %CLASS::DIMENSIONS...
    return $_[0]->{dimension}{$_[1]};
}

sub setDimensionValue ($$$) {
    $_[0]->{dimension}{$_[1]}=$_[2];
}

#------------------------------------------------------------------------------

=head2 add($other,$onrhs)

This is the implementation method for the C<+> operator. The first argument
is the other operand, and the second is true if this instance was found on
the right hand side, which implies that the left hand side is not an instance
of C<Composite::ValueItem>. In this case the value items is evaluated in
string context, concatenated to the left hand side, and the resulting string
returned to the caller. Otherwise, the value item is cloned, passed
along with the other operand to C<"addeq">, and the return value of that
method returned to the caller.

=cut

sub add ($$) {
    my ($self,$other,$onrhs)=@_;

    if ($onrhs) {
	return $other.$self;
    } else {
	$self=$self->clone();
	return $self->addeq($other);
    }
}

=head2 addeq($other)

This is the implementation method for the C<+=> operator. The passed argument
is the right hand operand, which is combined with the left hand operand
according to the command set for the right hand operand:

    ADD      - append value of RHS to value of LHS, with a space
    INSERT   - prefix value of RHS to value of LHS, with a space
    APPEND   - append value of RHS to value of LHS, no space
    PREPEND  - prefix value of RHS to value of LHS, no space
    OVERRIDE - replace value of LHS with value of RHS

If the command is not recognized (see L<Composte::Commands>) an exception
is thrown. Otherwise, the modified left hand operand is returned to the caller.

=cut

sub addeq ($$;$) {
    my ($self,$other,$onrhs)=@_;

    $self->throw("LHS cannot be added to") if $onrhs;

    return $self->addeqMultiple($other);
}

sub addeqMultiple ($@) {
    my ($self,@others)=@_;

    $self->{value}=$self->combineValueItemValues(@others);
    return $self;
}

sub combineValueItemValues ($@) {
    my ($self,@others)=@_;

    #-- optimisation - discard all items prior to an override
    my @items;
    foreach my $item (reverse @others) {
	unshift @items,$item;
	last if ref($item) and (defined($item->{command}) and
				$item->{command} eq OVERRIDE);
    }
    #--

    my (@lhs,$rhs,$command);

  ITEM: foreach my $item ($self,@others) {
        if (ref $item and $item->isa(ref $self)) {
            # item is one of us
            $rhs=$item->{value};
            $rhs="" unless defined $rhs;
            $command=$item->{command} || ADD;
        } else {
            # treat item as a string; force into string context.
            $rhs="".$item;
            $command=ADD;
        }

      SWITCH: foreach ($command) {
            $_ eq ADD      and do { push @lhs," ",$rhs;    last; };
            $_ eq INSERT   and do { unshift @lhs,$rhs," "; last; };
            $_ eq APPEND   and do { push @lhs,$rhs;        last; };
            $_ eq PREPEND  and do { unshift @lhs,$rhs;     last; };
            $_ eq OVERRIDE and do { @lhs=($rhs);           last; };
          DEFAULT:
            $self->throw("$command not implemented");
        }
    }

    my $lhs=join "",@lhs;
    $lhs=~s/^\s+//; $lhs=~s/\s+$//;
    return $lhs;
}

=head2 toString([$include_name])

This is the implementation method for the C<""> (stringify) operator. With no,
or a false, argument, it returns just the value of the value item. With a
true argument, it prepends the value with the name and an equals sign:

    <NAME>=<VALUE>

=cut

# stringify to value, not name -- unlike most other named objects, the value
# is the real 'content' and the name is often anonymous.
sub toString ($;$) {
    my $value=$_[0]->{value};

    if ($value) {
	if ((substr($value,0,1) eq '{') and (substr($value,-1,1) eq '}')) {
	    # eval Perl expression
	    $value = eval $value;
	} elsif ((substr($value,0,1) eq '`') and (substr($value,-1,1) eq '`')) {
	    # execute external command #<<TODO: efficiency issue multiple execs
	    $value = substr $value,1,-1;
	    $value = qx|$value|;
	}
    }

    return ($_[1] ? ($_[0]->{name}.'='):"").
      (defined($value) ? $value : "");
}

#==============================================================================

1;
