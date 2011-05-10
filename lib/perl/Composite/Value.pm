package Composite::Value;
use strict;

use overload '""'     => "toString",
             '+'      => "add",
             '+='     => "addeq",
             fallback => 1;

use base 'BDE::Object';
use Composite::Dimension::States qw(COLLAPSED UNCOLLAPSED IGNORED);

use constant DEFAULT_VALUEITEMCLASS => 'Composite::ValueItem';

#==============================================================================

=head1 NAME

Composite::Value - Aggregate value with multiple dimensions of uncertainty.

=head1 SYNOPSIS

    my $value=new Composite::Value("My composite value");
    my $valueitem1=new Composite::ValueItem(...)
    my $valueitem2=new Composite::ValueItem(...)
    $value->addValueItem($valueitem1,$valueitem2);
    $value->collapseDimension('dimension' => 'value');
    print "Value items remaining: ",join("\n",$value->getValueItems),"\n";
    print "Final value is $value\n";

=head1 DESCRIPTION

C<Composite::Value> implements a composite value comprising or one or more
C<Composite::ValueItem> objects. Each item comprises of a value, a combining
criterion (append, overwrite, prepend, reset), and zero or more dimensions,
each of which must be collapsed with an input value in order to remove items
that do not correspond to that dimension. When all dimensions have been
collapsed, the composite value contains only items that correspond to the
desired composite. The items are then processed in order to derive the final
value for that composite.

Note: In string context, a composite value evaluates to the combination of
its value items, I<not> to its name. Use L<"getName"> to return the name of the
composite value, and L<"render"> to generate a string containing both the
name and value (separated by an equals sign).

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new($name)

Create a new empty instance of a C<Composite::Value> object, using the
specified value name.

=head2 new($aref [,$init])

Creates a new instance of a C<Composite::Value> object populated with the
provided list of L<Composite::ValueItem> objects, passed in an array
reference, as its contents.

An optional third argument be passed to supply the value name.  Alternatively,
if the first element of the passed array is not a L<Composite::ValueItem>,
it is evaluated as a string and used to intialise the value name.

=cut

sub _flushCache ($) {
    delete $_[0]->{cachedString};
}

sub fromString ($$) {
    my ($self,$init)=@_;

    $self->setName($init);
    $self->{items}=[];

    $self->_flushCache();
}

# Constructor support - from an array reference
sub initialiseFromArray ($$;$) {
    my ($self,$aref,$init)=@_;

    $self->throw("Initialiser passed argument not an array reference")
      unless UNIVERSAL::isa($aref,"ARRAY");

    # a name may be passed in as 2nd arg, or first element of arrayref
    if (not $init and not ref $aref->[0]) {
	$init=shift @$aref;
    }

    $self->setName($init) if $init;
    $self->{items} = [];
    $self->_flushCache();

    # check we weren't passed invalid items
    foreach my $itemno (0 .. @$aref) {
	my $item=$aref->[$itemno];
	next unless $item;

	$self->throw("Element $itemno is not a Composite::ValueItem")
	  unless ($aref->[$itemno])->isa("Composite::ValueItem");

        push @{$self->{items}}, $item;
    }

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getName()

Return the name of the composite value.

=cut

sub getName ($) { return $_[0]->{name}; }

=head2 setName()

Set the name of the compisite value. The name may also be specified at
initialisation; see the synopsis above.

=cut

sub setName ($$) { $_[0]->{name}=$_[1]; }

=head2 getValueItemClass()

Return the name of the accepted class of the composite value item objects.
This informs the value set of what type of composite value objects it can
expect to be managing. Any object of the nominated class, or a child class
thereof, will be accepted. If a false or undefined value is passed, the
default class C<Composite::Value> is used.

=cut

sub getValueItemClass ($) {
    return $_[0]->{valueitemclass} or $_[0]->DEFAULT_VALUEITEMCLASS
}

=head2 setValueItemClass()

Set the name of the accepted class of the composite value item objects. While
it is not enforced that this be a subclass of C<Composite::Value>, it is
strongly recommended.

=cut

sub setValueItemClass ($$) {
    my ($self,$class)=@_;

    eval "require $class" or $self->throw("Unable to load $class");
    $self->{valueitemclass}=$class;
}

#------------------------------------------------------------------------------

=head2 getValueItem($index)

Return the value item at the specified index from the value, or C<undef> if the
index is not present.

=cut

sub getValueItem ($$) {
    my ($self,$index)=@_;

    if (abs($index) < scalar(@{$self->{items}})) {
	return $self->{items}[$index];
    }

    return undef;
}

=head2 getValueItems()

Return a list of all value items currently registered in the composite value.

=cut

sub getValueItems ($) {
    my ($self)=@_;

    return @{$self->{items}};
}

=head2 addValueItem($item)

Add the specified value item to the composite value.

=cut

sub addValueItem ($$;@) {
    my $self=shift;
    my $item;

    $self->_flushCache();

    if (scalar(@_)==1) {
	$item=shift;

	$self->throw("Not an item"),return undef
	  unless $item->isa("Composite::ValueItem");
    } else {
	#<<<TODO: test/finish
	my %attrs = (%{$self->{default}}, @_);
	$item=new Composite::ValueItem({%attrs});
    }

    push @{$self->{items}},$item;
    return 1;
}

# overload method wrapper for addValueItem above
sub add ($$;$) {
    my ($self,$item,$rhs)=@_;

    $self->throw("LHS cannot be added to") if $rhs;
    $self=$self->clone();
    $self += $item;

    $self->_flushCache();
}

sub addeq ($$;$) {
    my ($self,$item,$rhs)=@_;

    $self->throw("LHS cannot be added to") if $rhs;
    $self->_flushCache();
    return $self->addValueItem($self,$item);
}

=head2 addValueItems(@items)

Add one or more value items to the composite value.

=cut

sub addValueItems ($@) {
    my ($self,@items)=@_;

    $self->_flushCache();

    foreach my $item (@items) {
	return undef unless $self->addValueItem($item);
    }

    return 1;
}

=head2 replaceValueItem($index)

Replace the value item at the specified index with the specified the value.
The old value is retuned, or C<undef> if the index does not exist.

=cut

sub replaceValueItem ($$$) {
    my ($self,$index,$value)=@_;

    $self->_flushCache();

    my $old=$self->{items}[$index];
    $self->{items}[$index]=$value;

    return $old;
}

# sub replaceValueItems ($@) - not implementable

=head2 replaceAllValueItems([@items])

Replace all currently resident value items in the composite value, replacing
them with the supplied value items. If an empty list is supplied, has the same
effect as L<"removeAllValueItems">.

=cut

sub replaceAllValueItems ($@) {
    my ($self,@items)=@_;

    $self->_flushCache();

    my @result=$self->removeAllValueItems();
    $self->addValueItems(@items) if @items;

    return @result;
}

=head2 removeValueItem($index)

Remove and return the value item at the specified index from the value.
Returns C<undef> the index does not exist.

=cut

sub removeValueItem ($$) {
    my ($self,$index)=@_;

    $self->_flushCache();

    return splice @{$self->{items}},$index;
}

=head2 removeValueItems(@indices)

Remove one or more value items by index from the value, if they exist.

=cut

sub removeValueItems ($@) {
    my ($self,@indices)=@_;

    $self->_flushCache();

    $self->removeValueItem($_) foreach @indices;
}

=head2 removeAllValueItems()

Remove all currently resident value items from the value.

=cut

sub removeAllValueItems ($) {
    $_[0]->{items}=[];
    $_[0]->_flushCache();
}

#------------------------------------------------------------------------------

=head1 RENDERING METHODS

=head2 getValue()

Generate a string value for the composite value by evaluating its constituent
value items and combining them in order according to the command set for each
item. The returned string does not include the name of the composite value,
see L<"render"> below for that.

Note: Evaluating the composite value in string context will implicitly call
this method, unless C<toString> is overloaded.

=cut

sub getValue ($) {
    return $_[0]->{cachedString} if exists $_[0]->{cachedString};

    my $self=shift;

    my @items=$self->getValueItems();
    my $result="";
    my $itemCount=scalar @items;
    if($itemCount) {
        $result=shift(@items)->combineValueItemValues(@items);
    }

    $self->{cachedString}=$result;

    return $result;
}

sub toString ($) {
    return $_[0]->getValue();
}

=head2 render()

Generate a string value for the composite value as L<"getValue"> above, but
prefixed with the name of the composite value and an equals sign, in the style
of a makefile macro or environment variable definition.

=cut

sub render ($;$) {
    # $_[1] is prefix, if set.
    return ($_[1] ? $_[1] : "").$_[0]->getName().'='.$_[0]->getValue();
}

=head2 dump()

Generate an extended dump of the contents of the composite value for debugging,
including the detail from each value item in the composite value
(itself generated by calling L<Composite::ValueItem/dump>).

=cut

sub dump ($) {
    my $value=shift;

    return "Value <".$value->getName.">\n".
           (join "\n",map { $_->dump() } ($value->getValueItems())).
           "\n";
}

#==============================================================================

sub test (;$) { }

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Composite::ValueSet>, L<Composite::ValueItem>, L<Composite::Dimension>

=cut

1;
