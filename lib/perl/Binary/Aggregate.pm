package Binary::Aggregate;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';

use Util::File::Basename qw(dirname basename);

use Binary::Object;
use Binary::Archive;

#==============================================================================

=head1 NAME

Binary::Aggregate - Abstract representation of arbitrary binary entities

=head1 SYNOPSIS

    my $aggregate=new Binary::Aggregate("my aggregate");
    print "This is $aggregate\n";

    $aggregate->addBinaryFiles(qw[
        /usr/lib/libsocket.a
        /home/my/lib/mylib.a
        /home/my/build/myobject.o
    ]);

    my @objects_and_archives=$aggregate->getObjects();
    my @symbols=$aggregate->getSymbols();
    my @definedsymbols=$aggregate->getDefinedSymbols();
    my @undefinedsymbols=$aggregate->getUndefinedSymbols();
    my $symbol=$aggregate->getSymbol("connect");

=head1 DESCRIPTION

C<Binary::Aggregate> provides an abstract representation of a binary aggregate,
an arbitrary collection of multiple archives and/or binary objects. It
consists of a collection of one or more L<Binary::Archive> and/or
L<Binary::Object> objects, and provides methods to determine the presence and
status (defined or undefined) of objects and symbols in the aggregate as a
whole.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new([$name])

Create a new instance of a C<Binary::Aggregate> object with the specified
name, or 'Aggregate' if no name is specified. The new object is not initialised
with any archive or objects -- the name is simply an identifier for the
aggregate and plays no part in symbol analysis or file naming.

To populate the aggregate either use the arrary reference form of C<"new"> below,
pass a list of C<Binary::Object> or C<Binary::Archive> objects to
L<"addObjects">, or pass a list of files to L<"readBinaryFiles">.

=head2 new($aref [,$name])

Creates a new instance of a C<Binary::Aggregate> object populated with the
provided list of L<Binary::Archive> and/or L<Binary::Object> objects, passed
in an array reference, as its contents.

An optional third argument be passed to supply the aggregate name.
Alternatively, if the first element of the passed array is not an object, it
is evaluated as a string and used to intialise the aggregate name.

=cut

sub fromString ($;$) {
    my ($self,$init)=@_;
    $self->setName($init || 'Aggregate');
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
    if ($init) {
	$self->setPath(dirname $init);
	$self->setName(basename $init);
    }

    # check we weren't passed invalid objects
    $self->{objects} = {};
    foreach my $objectno (0 .. @$aref) {
	my $object=$aref->[$objectno];
	next unless $object;

	$self->throw("Element $objectno is not a Binary::Object")
	  unless ($aref->[$objectno])->isa("Binary::Object")
	    or ($aref->[$objectno])->isa("Binary::Archive")
	      or ($aref->[$objectno])->isa("Binary::Aggregate");

	$self->{objects}{$object}=$object;
    }

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getName()

Return the name of the aggregate.

=cut

sub getName ($) { return $_[0]->{name}; }

=head2 setName()

Set the name of the aggregate. The name may also be specified at
initialisation; see the synopsis above.

=cut

sub setName ($$) { $_[0]->{name}=$_[1]; }

#------------------------------------------------------------------------------

=head2 getObject($objectid)

Return the object or archive with the specified ID from the aggregate, or
C<undef> if the requested object is not present. If supplied with a
L<Binary::Object> or L<Binary::Archive> object as an argument, checks whether
or not the aggregate contains a object with the same name.

Only a directly included object is returned by this method. If the aggregate
contains an archive that in turn contains an object of the requested name,
it is I<not> returned.

The name of this method, and its sibling methods below, retains the word
C<Object> for consistency with the L<Binary::Archive> object, so that an
aggregate can be treated conceptually as an archive (i.e. is polymorphic with
that class in general use). Therefore the return value of the method may
legally be either a L<Binary::Object> or a L<Binary::Archive> (or a subclass
thereof).

=cut

sub getObject ($$) {
    my ($self,$objectid)=@_;

    if (exists $self->{objects}{$objectid}) {
	return $self->{objects}{$objectid};
    }

    return undef;
}

=head2 getObjects()

Return a list of all objects and archives currently registered in the
aggregate. As with L<"getObject"> above, only directly included objects are
returned, not objects within archives.

=cut

sub getObjects ($) {
    my ($self)=@_;

    return wantarray
      ? @{[sort values %{$self->{objects}}]}
      : $self->{objects} || {};
}

=head2 addObject($object)

Add the specified L<Binary::Archive> or L<Binary::Object> object to the
aggregate, replacing any existing object with the same name, if present.

It is also possible to add L<Binary::Aggregate> objects through this method,
allowing aggregates to nest within each other.

=cut

sub addObject ($$) {
    my ($self,$object)=@_;
    $self->throw("Not an object or archive"),return undef
      unless $object->isa("Binary::Object")
	or $object->isa("Binary::Archive")
	  or $object->isa("Binary::Aggregate");

    $self->{objects}{$object}=$object; # stringifies object to get hash key
    return 1;
}

=head2 addObjects(@objects)

Add one or more objects or archives to the aggregate, replacing any existing
objects or archive with the same name, if present.

=cut

sub addObjects ($@) {
    #my ($self,@objects)=@_;
    my $self = shift;

    foreach my $object (@_) {
	return undef unless $self->addObject($object);
    }

    return 1;
}

=head2 addObjectFile($filename)

Create a new L<Binary::Object> object for the specified object file and add
it to the aggregate, replacing any existing object with the same name. See
also L<"addBinaryFile">.

=cut

sub addObjectFile ($$) {
    my ($self,$file)=@_;
    my $object=eval { new Binary::Object($file) };
    return undef unless $object;
    return $self->addObject($object);
}

=head2 addArchiveFile($filename)

Creare a new L<Binary::Archive> object for the specified archive file and add
it to the aggregate, replacing any existing archive with the same name.
See also L<"addBinaryFile">.

=cut

sub addArchiveFile ($$) {
    my ($self,$file)=@_;
    my $archive=eval { new Binary::Archive($file) };
    return undef unless $archive;
    return $self->addObject($archive); #correct - see POD for addObject
}

=head2 addBinaryFile($filename)

Create new L<Binary::Archive> or L<Binary::Object> objects for the specified
file and add it to the aggregate, replacing any existing object or archive
with the same name.

If the supplied filename includes an extension that begins with C<o> (that is,
C<.o>, C<.obj>, etc.) a L<Binary::Object> is created. Otherwise, a
L<Binary::Archive> is created. If this is not the desired behaviour, either
subclass this class and overload the L<"addBinaryFile"> method, or invoke
one of the explict methods L<"addObjectFile"> or L<"addArchiveFile"> instead.

=cut

sub addBinaryFile ($$) {
    my ($self,$file)=@_;

    if ($file=~/\.o\w*$/) {
	return $self->addObjectFile($file);
    } else {
	return $self->addArchiveFile($file);
    }
}

=head2 addBinaryFiles(@filenames)

Create new L<Binary::Archive> or L<Binary::Object> objects for the specified
files and add them to the aggregate, replacing any existing objects or archives
with the same name, if present.

=cut

sub addBinaryFiles($@) {
    my ($self,@files)=@_;

    foreach my $file (@files) {
	return undef unless $self->addBinaryFile($file);
    }

    return 1;
}

=head2 removeObject($objectid)

Remove and return the named object from the aggregate. Returns C<undef> if the
named object is not present.

=cut

sub removeObject ($$) {
    my ($self,$objectid)=@_;

    return delete $self->{objects}{$objectid};
}

=head2 removeObjects(@objectids)

Remove one or more named objects from the aggregate, if present. Supplied object
names that are not present in the aggregate are silently ignored.

=cut

sub removeObjects ($@) {
    my ($self,@objectids)=@_;

    $self->removeObject($_) foreach @objectids;
}

=head2 removeAllObjects()

Remove all currently resident objects from the aggregate.

=cut

sub removeAllObjects ($) {
    $_[0]->{objects}={};
}

#------------------------------------------------------------------------------

=head2 getSymbol($symbolid)

Return the symbol with the given name, if it exists in the aggregate. If
the symbol is not present C<undef> is returned. Only one instance of the
symbol is returned if it is multiply present (for instance, if more than one
object references the symbol).

=cut

sub getSymbol ($$) {
    my ($self,$name)=@_;

    return $self->getDefinedSymbol($name) || $self->getUndefinedSymbol($name);
}

=head2 getDefinedSymbol($symbolid)

Return the defined symbol with the given name, if it exists in the aggregate. If
the symbol is not present or the aggregate references the symbol only, C<undef>
is returned. (Use L<"getSymbolRefs"> to retrieve undefined symbol references in
the presence of a defined symbol.)

=cut

sub getDefinedSymbol ($$) {
    my ($self,$name)=@_;

    foreach my $object (values %{$self->{objects}}) {
	if (my $symbol=$object->getSymbol($name)) {
	    return $symbol if $symbol->isDefined();
	}
    }

    return undef;
}

=head2 getDefinedSymbol($symbolid)

Return the undefined symbol with the given name, if it exists in the aggregate
and no defined version of the symbol is also present. C<undef> is returned
if the symbol is not present, or a defined version of the symbol is found.

=cut

sub getUndefinedSymbol ($$) {
    my ($self,$name)=@_;

    my $result=undef;
    foreach my $object (values %{$self->{objects}}) {
	if (my $symbol=$object->getSymbol($name)) {
	    return undef if $symbol->isDefined();
	    $result=$symbol;
	}
    }

    return $result;
}

=head2 getSymbols()

Return a list of symbol objects for each symbol in the aggregate, defined or
undefined. Only one symbol object is returned for each undefined symbol
present. (More than one object in the aggregate may reference it, but only
the last one encountered is returned).

For most cases L<"getDefinedSymbols"> and L<"getUndefinedSymbols"> are
probably more appropriate than this method.

=cut

sub getSymbols ($) {
    return ($_[0]->getDefinedSymbols,$_[0]->getUndefinedSymbols);
}

=head2 getDefinedSymbols()

Return a list of symbol objects for all defined symbols in this aggregate.
Symbols are presumed to be unique within the aggregate.

=cut

sub getDefinedSymbols ($) {
    my $self = shift;
    my %defined;

    $_->getDefinedSymbols(\%defined) foreach (values %{$self->getObjects()});

    return wantarray ? values %defined : \%defined;
}

=head2 getUndefinedSymbols()

Return a list of symbols objects for all symbols referenced by an object in
the aggregate that are not defined elsewhere in the same aggregate. Only one
instance of each undefined symbol is returned; use L<"getSymbolRefs">
to retrieve all instances of an undefined symbol within the aggregate.

=cut

## XXX: currently callers do double work when getting defined and undefined
##	symbols.  They call getDefinedSymbols and then getUndefinedSymbols
##	but getUndefinedSymbols has to additionally call getDefinedSymbols
##	to create the set of undefined symbols.  There should be a
##	routine to return the set of both.
sub getUndefinedSymbols ($) {
    my $self = shift;
    my(%defined,%undefined);

    foreach my $object (values %{$self->getObjects()}) {
	$object->getDefinedSymbols(\%defined);
	$object->getUndefinedSymbols(\%undefined);
    }
    delete $undefined{$_} foreach (keys %defined);

    return wantarray ? values %undefined : \%undefined;
}

=head2 getAllUndefines()

Return a hash reference to symbols undefined in any archive in the aggregate.

=cut

sub getAllUndefines ($;$) {
    my $self = $_[0];
    my $undefined = $_[1] ||= {};
    map { $_->getAllUndefines($undefined) } values %{$self->getObjects()||{}};
    return $undefined;
}

=head2 getSymbolRefs($symbolid)

Return a list of symbol objects for each undefined reference to the symbol
within the aggregate. This method makes no statement as to whether the symbol
is defined in the aggregate or not.

=cut

sub getSymbolRefs ($$) {
    my($self,$name)=@_;

    my @refs=();

    foreach my $object (values %{$self->{objects}}) {
	if (my $symbol=$object->getDefinedSymbol($name)) {
	    push @refs,$symbol;
	}
    }

    return wantarray ? @refs : \@refs;
}

#------------------------------------------------------------------------------

sub toString ($) {
    return $_[0]->getName();
}

#==============================================================================

sub test (;$) {
    my $aggregate=new Binary::Aggregate("test aggregate");
    print "=== Aggregate $aggregate\n";
    $aggregate->addBinaryFiles(qw[
        /usr/lib/libsocket.a
        /usr/lib/libnls.a
        /does/not/exist.a
    ]);

    my @objects=$aggregate->getObjects();
    print "** Objects: @objects\n";

    my @definedsymbols=$aggregate->getDefinedSymbols();
    print "** Defined: @definedsymbols\n";

    my @undefinedsymbols=$aggregate->getUndefinedSymbols();
    print "** Undefined: @undefinedsymbols\n";

    foreach my $name ('connect','select','foobar','nlsenv') {
	my $symbol=$aggregate->getSymbol($name);

	unless ($symbol) {
	    print "'$name' does not exist in $aggregate\n";
	    next;
	}

	printf "%-30s","'$symbol' found in ".$symbol->getArchive();
	print " -- ",($symbol->isDefined?"*defined*":"UNDEFINED"),
	  " '$symbol'",
	  " type=",  $symbol->getType(),
	  " value=", $symbol->getValue(),
	  " weak=" , ($symbol->isWeak?1:0),
	  "\n";
    }
	
    print "== Done\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainright@bloomberg.net)

=head1 SEE ALSO

L<Binary::Archive>, L<Binary::Object>, L<Binary::Symbol>, L<Binary::Cache>

=cut

1;
