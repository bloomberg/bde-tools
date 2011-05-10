package Composite::ValueSet;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';

use Util::File::Basename qw(dirname basename);

use Composite::Value;
use Composite::Dimension::States qw(COLLAPSED UNCOLLAPSED IGNORED);

use constant DEFAULT_VALUECLASS => 'Composite::Value';

#==============================================================================

=head1 NAME

Composite::ValueSet - Container for a set of L<Composite::Value> objects.

=head1 SYNOPSIS

    my $valueset=new Composite::ValueSet("My::Composite::Value::Class");
    ...

=head1 DESCRIPTION

C<Composite::ValueSet> provides management for a set of L<Composite::Value>
objects. The values in a value set may be queried, extracted, added to,
removed, or replaced through the value set. Dimensions may also be collapsed
for all values I<en masse>.

This module is intended to be used as a superclass, to be derived from in
child classes that manage a particular type of value, themselves defined as
a subclass of the L<Composite::Value> class.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new([$name])

Create a new instance of a C<Composite::ValueSet> object with the specified
name. The name is purely informational and if left unspecified a default name
of L<ValueSet> is used.

=head2 new($aref [,$init])

Creates a new instance of a C<Composite::ValueSet> object populated with the
provided list of L<Composite::Value> objects, passed in an array reference,
as its contents.

An optional third argument be passed to supply the name. Alternatively, if the
first element of the passed array is not a L<Composite::Value>, it is
evaluated as a string and used for the value set name.

=cut

# Constructor support - all initialisers (or none)
sub initialise {
    my ($self,$args)=@_;

    $self->throw(ref($self)." does not implement 'register' method")
      unless $self->can("register");

    $self->SUPER::initialise($args);
    $self->setValueClass($self->DEFAULT_VALUECLASS) unless $args;
    $self->{values}={};

    $self->{dimension}={};
    $self->{dimension_order}=[];
    $self->register();
}

# Constructor support - scalar initialiser
sub fromString ($$) {
    my ($self,$init)=@_;

    $self->setValueClass($init);

    return $self;
}

# Constructor support - array reference initialiser
sub initialiseFromArray ($$;$) {
    my ($self,$aref,$init)=@_;

    $self->throw("Initialiser passed argument not an array reference")
      unless UNIVERSAL::isa($aref,"ARRAY");

    # a name may be passed in as 2nd arg, or first element of arrayref
    if (not $init and not ref $aref->[0]) {
	$init=shift @$aref;
    }
    if ($init) {
	$self->setValueClass(basename $init);
    } else {
        $self->setValueClass(DEFAULT_VALUECLASS);
    }

    # check we weren't passed invalid values
    my $valueclass=$self->getValueClass();
    foreach my $valueno (0 .. @$aref) {
	my $value=$aref->[$valueno];
	$self->throw("Element $valueno is undefined") unless defined $value;
        $self->throw("Element $valueno ($value) is not a reference")
            unless ref $self;

        if ($value->isa($valueclass)) {
            $self->addValue($value);
        } elsif ($value->isa("Composite::ValueItem")) {
            #<<<TODO: not currently possible to set the item class
            #<<<in constructor, adjust fromString and initialiseFromArray
            #<<<could possibly be got by requiring and asking the value class
            $self->addValueItem($value);
        } else {
	    $self->throw("Element $valueno is not a $valueclass ".
                         "or Composite::ValueItem");
        }
    }

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getValueClass()

Return the name of the accepted class of the composite value objects.
This informs the value set of what type of composite value objects it can
expect to be managing. Any object of the nominated class, or a child class
thereof, will be accepted. If a false or undefined value is passed, the
default class C<Composite::Value> is used.

=cut

sub getValueClass ($) {
    return $_[0]->{valueclass} or $_[0]->DEFAULT_VALUECLASS
}

=head2 setValueClass()

Set the name of the accepted class of the composite value objects. While it is
not enforced that this be a subclass of C<Composite::Value>, it is strongly
recommended.

=cut

sub setValueClass ($$) {
    my ($self,$class)=@_;

    eval "require $class" or $self->throw("Unable to load $class");
    $self->{valueclass}=$class;
}

#<<<TODO: add (set|get)ValueItemClass also? Or... this could/should be got
#<<<by interrogating the value class itself for its preferred item class.

#------------------------------------------------------------------------------

=head2 getValue($valueid)

Return the value with the specified ID from the value set, or C<undef> if the
value is not present. If supplied with a L<Composite::Value> object as an
argument, checks whether or not the value set contains a value with the same
name.

=cut

sub getValue ($$) {
    my ($self,$valueid)=@_;

    if (ref $valueid) {
	$valueid=$valueid->getName();
    }

    if (exists $self->{values}{$valueid}) {
	return $self->{values}{$valueid};
    }

    return undef;
}

=head2 getValues()

Return a list of all values currently registered in the value set.

=cut

sub getValues ($) {
    my ($self)=@_;

    return @{[sort values %{$self->{values}}]};
}

=head2 addValue($value)

Add the specified L<Composite::Value> object to the value set, I<appending> its
value items to any existing value with the same name, if present. See also
L<"replaceValue">.

=cut

sub addValue ($$) {
    my ($self,$value)=@_;
    $self->throw("Not a ".$self->getValueClass),return undef
      unless $value->isa($self->getValueClass);

    my $valuename=$value->getName();
    if (my $existing=$self->{values}{$valuename}) {
        $existing->addValueItems($value->removeValueItems);
        undef $value; #destroy after transfer
    } else {
        $self->{values}{$valuename}=$value;
    }

    return 1;
}

=head2 addValues(@values)

Add one or more values to the value set, replacing any existing values with the
same name, if present.

=cut

sub addValues ($@) {
    my ($self,@values)=@_;

    foreach my $value (@values) {
	return undef unless $self->addValue($value);
    }

    return 1;
}

=head2 replaceValue($value)

Add the specified L<Composite::Value> object to the value set, I<replacing> and
retuning any existing composite value, if present. If no existing value with
the same name is already present, C<undef> is returned. See also L<"addValue">.

=cut

sub replaceValue ($$) {
    my ($self,$value)=@_;
    $self->throw("Not an value"),return undef
      unless $value->isa("Composite::Value");

    my $valuename=$value->getName();
    my $old=(exists $self->{values}{$valuename})
      ? $self->{values}{$valuename} : undef;
    $self->{values}{$valuename}=$value;
    return $old;
}

=head2 replaceValues(@values)

Replace one or more named values from the value set, if present. Supplied
values which do not have correspondingly named values in the set are added.
Returns the list of replaced values (if any).

=cut

sub replaceValues ($@) {
    my ($self,@values)=@_;

    my @result=();
    foreach (@values) {
        my $result=$self->replaceValue($_);
        push @result,$result if defined $result;
    }

    return @result;
}

=head2 replaceAllValues([@values])

Remove and return all existing values in the value set, replacing them with the
list of supplied values. If an empty list is supplied, has the same effect as
L<"removeAllValues">.

=cut

sub replaceAllValues ($@) {
    my ($self,@values)=@_;

    my @result=$self->removeAllValues();
    $self->addValues(@values) if @values;

    return @result;
}

=head2 removeValue($valueid)

Remove and return the named value from the value set. Returns C<undef> if the
named value is not present.

=cut

sub removeValue ($$) {
    my ($self,$valueid)=@_;

    if (ref $valueid) {
	$valueid=$valueid->getName();
    }

    return delete $self->{values}{$valueid};
}

=head2 removeValues(@valueids)

Remove one or more named values from the value set, if present. Supplied value
names that are not present in the value set are silently ignored. Values are
removed by name, so this method will accept any string value to identify a
value, including a composite value not in the set but with the same name as a
value that is.

=cut

sub removeValues ($@) {
    my ($self,@valueids)=@_;

    my @result=();
    foreach (@valueids) {
        my $result=$self->removeValue($_);
        push @result,$result if defined $result;
    }

    return @result;
}

=head2 removeAllValues()

Remove and return all currently resident values from the value set.

=cut

sub removeAllValues ($) {
    my @result=(exists $_[0]->{values})
        ? (values %{$_[0]->{values}}) : ();
    $_[0]->{values}={};
    return @result;
}

#------------------------------------------------------------------------------

=head2 addValueItem($valueitem)

Add the specificed value item to the value set. If a composite value with the
same name is present, the value item is appended to the list of value items
already present in the composite value. Otherwise, a new composite value is
created with the supplied value item as its first (and only) member. Returns
the composite value to which the item was added, whether or not it was 
already present or created as a result of this call.

=cut

sub addValueItem ($$) {
    my ($self,$valueitem)=@_;
    $self->throw("Not a Composite::ValueItem"),return undef
      unless $valueitem->isa("Composite::ValueItem");

    my $name=$valueitem->getName();
    my $value=$self->getValue($name);
    if (defined $value) {
        $value->addValueItem($valueitem);
    } else {
        my $valueclass=$self->getValueClass();
        $value=$valueclass->new($name);
        $value->addValueItem($valueitem);
        $self->addValue($value);
    }
}

=head2 addValueItems(@valueitems)

Add one or more value items to composite value members of the value set, using
L<"addValueItem">. This method allows a complete value set of many composite
values to be generated or augmented with a single source list of value items.
Returns the list of composite values that were either appended to or created
as a result of the call.

=cut

sub addValueItems ($@) {
    my ($self,@valueitems)=@_;

    my %result=(); #uniquifing hash
    foreach (@valueitems) {
        my $result=$self->addValueItem($_);
        $result{$result}=$result; #stringify hash key
    }

    return values %result;
}

#------------------------------------------------------------------------------
#==============================================================================

=head2 getDimension($attr)

Retrieve the dimension object associated with the specified attribute name.

=cut

sub getDimension ($$) {
    my ($self,$attr)=@_;

    if (exists $self->{dimension}{$attr}) {

	my $dimension=$self->{dimension}{$attr}{tool};

	unless (ref $dimension) {
	    $dimension=new $dimension($attr);

	    $self->throw("Not a dimension: $dimension") unless
	      $dimension->isa("Composite::Dimension");

	    $self->{dimension}{$attr}{tool}=$dimension;
	}

        return $dimension;
    }

    $self->throw("No dimension registered for $attr");
}

=head2 getDimensions()

Retrieve all dimension objects associated with the value set.

=cut

sub getDimensions ($) {
    return map { $_[0]->getDimension($_) } keys %{$_[0]->{dimension}};
}

#--- These state methods may have usage issues, not documented for now

sub getDimensionsInState ($$) {
    my ($self,$state)=@_;

    my @results=();
    foreach my $dimension ($self->getDimensions) {
	push @results, $dimension
	  if $self->getDimensionState($dimension) eq $state;
    }

    return @results;
}

sub getUncollapsedDimensions ($) {
    return $_[0]->getDimensionsInState(UNCOLLAPSED);
}

sub getCollapsedDimensions ($) {
    return $_[0]->getDimensionsInState(COLLAPSED);
}

sub getIgnoredDimensions ($) {
    return $_[0]->getDimensionsInState(IGNORED);
}

sub canRender ($) {
    if ($_[0]->getDimensionsInState(UNCOLLAPSED)) {
	return 0;
    }

    return 1;
}

#----

=head2 setDimension($attr => $dimension)

Install a previously constructed dimension object to handle the specified
attribute.

=cut

sub setDimension ($$$) {
    my ($self,$attr,$dimension)=@_;

    #<<<TODO:...get dimensions from registered value object
    #(which gets them from its registered value item object)
    #and check that dimension is being installed for a valid attribute


    unless (ref $dimension) {
	# if passed a classname, load the dimension but don't yet
	# initialise it. We do that only when we need the dimension
	$self->throw("Not a dimension or valid classname: $dimension")
	  unless eval "require $dimension; 1;";
    }

    unless (exists $self->{dimension}{$attr}) {
	push @{ $self->{dimension_order} },$attr;
    }
    $self->{dimension}{$attr}{tool}=$dimension; #can be object or classname

    $self->setDimensionState($attr => UNCOLLAPSED);
}

=head2 removeDimension($attr)

Remove the dimension object associated with the specified attribute. Has no
effect if no dimension is currently associated.

=cut

sub removeDimension ($$) {
    my ($self,$attr)=@_;

    if (exists $self->{dimension}{$attr}) {
	@{ $self->{dimension_order} } = grep {
	    $_ ne $attr
	} @{ $self->{dimension_order} };

        my $tool=$self->{dimension}{$attr}{tool};
        delete $self->{dimension}{$attr};
        return $tool;
    }

    return undef;
}

=head2 removeAllDimensions()

Remove all currently associated dimension objects from the value set.

=cut

sub removeAllDimensions ($) {
    $_[0]->{dimension}={};
    $_[0]->{dimension_order}=[];
}

#------------------------------------------------------------------------------

=head2 getDimensionOrder()

Return the preferred collapse order for dimensions, used when more than one
dimension is collapsed at the same time. By default the preferred order is
established by the order in which the dimensions were originally associated
with the value set.

=head2 setDimensionOrder(@dimensions)

Explicitly set the preferred collapse order for dimensions.

=cut

sub getDimensionOrder ($) {
    return @{ $_[0]->{dimension_order} };
}

sub setDimensionOrder ($@) {
    my ($self,@dimensions)=@_;

    #<<<TODO
    $self->throw("setDimensionOrder: Not yet implemented");
}

#------------------------------------------------------------------------------
#--- These state methods may have usage issues, not documented for now

sub getDimensionState ($$) {
    my ($self,$attr)=@_;

    if (exists $self->{dimension}{$attr}) {
        return $self->{dimension}{$attr}{state};
    }

    return undef;
}

sub setDimensionState ($$$) {
    my ($self,$attr,$state)=@_;

    if (exists $self->{dimension}{$attr}) {
        $self->{dimension}{$attr}{state}=$state; #<<<TODO: verify valid state
    } else {
        $self->throw("Cannot set state for unregistered dimension '$attr'");
    }

    return 1;
}

sub ignoreDimension ($$) {
    my ($self,$dimension)=@_;

    $self->setDimensionState($dimension => IGNORED)
      if $self->getDimensionState($dimension) eq UNCOLLAPSED;
}

sub ignoreDimensions ($@) {
    my ($self,@dimensions)=@_;

    foreach my $dimension (@dimensions) {
	$self->ignoreDimension($dimension);
    }
}

sub unignoreDimension ($$) {
    my ($self,$dimension)=@_;

    $self->setDimensionState($dimension => UNCOLLAPSED)
      if $self->getDimensionState($dimension) eq IGNORED;
}

sub unignoreDimensions ($@) {
    my ($self,@dimensions)=@_;

    foreach my $dimension (@dimensions) {
	$self->unignoreDimension($dimension);
    }
}

#------------------------------------------------------------------------------

=head2 collapseDimension($dimension, $value [,$clone])

Collapse all values in the value set in the specified dimension using the
specified value. If a dimension object is passed, it is used to collapse the
valueset with the supplied value. If a dimension name is passed, the object
is retrieved from the registered dimensions for the set (as set up by
L<"setDimension"> above), if available.

If the optional clone argument is passed a true value, a new value set object
containing collapsed versions of the original values is returned and the
original value set is left unmodified. Otherwise, the set on which the method
is called is modified and returned.

=head2 collapseDimensions($dimensionmap [,$clone])

Collapse all values in the value set in the specified dimensions using the
specified values. The first argument is a hash reference to a hash of
dimensions and dimension values, as supplied to L<"collapseDimension"> above.

If the second clone argument is true, the set is cloned and the clone is
collapsed and returned. Otherwise, the original set is collapsed.

=cut

#<<<TODO: collapseDimensions doesn't use collapseDimension for efficiency.
#<<<TODO: however this makes subclassing more of a pain than it should be
#<<<TODO: (see Build::Option::Set) -- resolve!

sub collapseDimension ($$$;$) {
    my ($self,$dimension,$value,$clone)=@_;

    return $self->collapseDimensions({$dimension => $value},$clone);
}

sub collapseDimensions {
    my ($self,$dimensionmap,$clone)=@_;

    $self->throw("Hash reference required as first argument")
      unless (ref($dimensionmap) and ref($dimensionmap) eq "HASH");

    my @values=();
    if ($clone) {
	@values=$self->getValues();
	$self = $self->clone();
    }

    foreach my $dimension (@{ $self->{dimension_order} }) {
	next unless exists $dimensionmap->{$dimension};

	unless (ref $dimension) {
	    my $registereddimension=$self->getDimension($dimension);
	    $self->throw("Not a dimension: $dimension")
	      unless $registereddimension;
	    $dimension=$registereddimension;
	}

	$self->throw("Not a dimension: $dimension")
	  unless $dimension->isa("Composite::Dimension");

=pod disabled

# this flag needs to be unset if new items are loaded into the valueset.
# a smarter caching mechanism on a per-value and per-dimension basis is
# needed later to improve efficiency.

	my $state=$self->getDimensionState($dimension);
	if ($state==COLLAPSED) {
	    $self->throw("Attempt to collapse collapsed dimension $dimension");
	} elsif ($state==IGNORED) {
	    $self->throw("Attempt to collapse ignored dimension $dimension");
	}

=cut

	# dimensions that initialise their defaults from the options!
	if (my $dimension_cv=$dimension->getDimensionCV) {
	    if (my $value=$self->getValue($dimension_cv)) {
		my $result=$value->getValue();
		#print STDERR $value->dump();
		#die "GOT A DEFAULT: $dimension_cv IS $result\n";
		$dimension->setDefault($result);
	    }
	}

	my $value=$dimensionmap->{$dimension};

	if ($clone) {
	    @values=map {
		$dimension->collapse($_, $value, $clone);
	    } @values;
	    $self->replaceAllValues(@values); #for dimensionCV checks
	} else {
	    map {
		$dimension->collapse($_, $value);
	    } $self->getValues();
	}

	$self->setDimensionState($dimension => COLLAPSED);
    }

    return $self;
}

#------------------------------------------------------------------------------

sub toString ($) {
    return join " ", $_[0]->getValues();
}

#----

sub _processPrefixMacros ($$$) {
    my ($self,$value,$prefix)=@_;

    # add the prefix to each instance of a variable that is mentioned in the
    # definition of another variable
    foreach my $var ($self->getValues) {
	my $name=$var->getName();
        $value =~ s|\$\($name\)|\$(${prefix}${name})|sg;
    }

    return $value;
}

=head2 render([$prefix])

Return a concatenated string of the rendered string representations of every
value in the valueset, as returned by L<Composite::Value/render>. This is
typically the most useful form in which the value set can be rendered.

=cut

sub render ($;$) {
    my $prefix=$_[1] || $_[0]->{prefix} || "";

    my $result = join("\n", (map {
        $_->render($prefix)
    } sort {
	$a->getName() cmp $b->getName()
    } ($_[0]->getValues)))."\n";

    if ($prefix) {
	return $_[0]->_processPrefixMacros($result,$prefix);
    }
    return $result;
}

#----

{ my %expanded; # expansion evaluation cache

  # Private method to expand values; makes use of a cache for efficiency.
  # The cache is clobbered by the public methods before they start, so that
  # this becomes a crude but simple implementation for maintaining computed
  # values without extra logic to determine how 'fresh' a value is.
  sub _expandValue ($$) {
      my ($self,$value)=@_;

      # if passed a string that's not a value, it expands to ""
      unless (ref $value and $value->isa("Composite::Value")) {
	  return "" unless $value=$self->getValue($value);
      }

      my $result=$value->toString();

      # expand (recursively) all referenced variables
      my @varsinstring=($result =~ m/\$\(([^)]+)\)/g);
      foreach my $varinstring (@varsinstring) {
	  unless (exists $expanded{$varinstring}) {
	      $expanded{$varinstring}=$self->_expandValue($varinstring);
	  }
      }

      # replace vars with their (recursively) expanded values
      $result =~ s/\$\(([^)]+)\)/$expanded{$1}/g;

      return $result || "";
  }

=head2 expandValue($value)

Expand and return a string representation of the specified value, with all
references to other values replaced with their string values in turn.
Expansion is recursive, so no references are left in the resulting string.
The name of the value is I<not> prepended in the returned string.

Note that this is a value set method and not a value method because knowledge
of other values is necessary in order to carry out the expansion.

=cut

  sub expandValue ($$) {
      my ($self,$value)=@_;
      %expanded=();

      return $self->_expandValue($value);
  }

=head2 expandValues([$prefix])

Expand all values in the value set, in the manner of L<"expandValue"> above.
As all values are expanded, each value is prefixed with its name and a C<=>
sign in the same manner as L<"render">. An optional prefix may be supplied,
in which case the returned string values are appropriately prefixed.

=cut

  sub expandValues ($;$) {
      my ($self,$prefix)=@_;
      $prefix = $self->{prefix} || "" unless defined $prefix;
      %expanded=();

      my $result = join("\n", (map {
	  $prefix.$_->getName()."=".$self->_expandValue($_)
      } sort {
	  $a->getName() cmp $b->getName()
      } ($_[0]->getValues)))."\n";

      return $result;
  }
}

#----

=head2 dump()

Return a concatenated string of the dumped string representations of every
value in the valueset, as returned by L<Composite::Value/dump>. Intended for
use in debugging only; use L<"render"> for a more useful representation.

=cut

sub dump ($) {
    return (join "\n", (map {
	$_->dump()
    } sort {
	$a->getName() cmp $b->getName()
    } ($_[0]->getValues)))."\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Composite::Value>

=cut

1;
