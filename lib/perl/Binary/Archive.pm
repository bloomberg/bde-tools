package Binary::Archive;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';

use Util::Message qw(debug);
use Util::File::Basename qw(dirname basename);

use Binary::Object;
use Binary::Symbol::Scanner;

#==============================================================================

=head1 NAME

Binary::Archive - Abstract representation of a binary archive (library)

=head1 SYNOPSIS

    my $archive=new Binary::Archive("/usr/lib/libsocket.a");
    print "Archive $archive is located at ",$archive->getPath(),"\n";

    my @objects=$archive->getObjects();
    my @symbols=$archive->getSymbols();
    my @definedsymbols=$archive->getDefinedSymbols();
    my @undefinedsymbols=$archive->getUndefinedSymbols();
    my $symbol=$archive->getSymbol("connect");

=head1 DESCRIPTION

C<Binary::Archive> provides an abstract representation of a binary archive,
i.e. a library. It consists of a collection of one or more binary objects,
themselves represented by C<Binary::Object> objects, and provides methods
to determine the presence and status (defined or undefined) of symbols in
the archive as a whole.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new($filename)

Create a new instance of a C<Binary::Archive> object using the archive filename
passed as the intialiser. Object symbols are found and extracted with
L<Binary::Symbol::Scanner> and L<Binary::Symbol::Parser>. Returns an object
populated with C<Binary::Object> instances on success, or an empty (but valid)
object if no symbols could be found or parsed.

=head2 new($aref [,$init])

Creates a new instance of a C<Binary::Archive> object populated with the
provided list of L<Binary::Object> objects, passed in an array reference,
as its contents.

An optional third argument be passed to supply the archive name and path, but
is not used to read from the filesystem. Alternatively, if the first element
of the passed array is not a L<Binary::Object>, it is evaluated as a string
and used to intialise the archive name and path.

=cut

sub fromString ($$) {
    my ($self,$init)=@_;

    my $objects = (new Binary::Symbol::Scanner())->scan($init);

    if (scalar keys %$objects) {
	$self->removeAllObjects();

	## XXX: should make a way to pass hash in %objects to initialise object
	##      rather than expanding values into an array ref

	# generate Binary::Object objects and assign them to this archive
	my($object,$syms);
	while (($object,$syms) = each %$objects) {
	    ## XXX: (does not work if $object passed as second arg?)
	    $self->addObject(new Binary::Object([$object, values %$syms]));
	}
    }

    $self->setPath(dirname $init);
    $self->setName(basename $init);

    return $self;
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
    foreach my $objectno (0 .. $#$aref) {
	my $object=$aref->[$objectno] || next;

	$self->throw("Element $objectno is not a Binary::Object")
	  unless ($aref->[$objectno])->isa("Binary::Object");

	$self->{objects}{$object}=$object;
    }

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getName()

Return the name of the archive.

=cut

sub getName ($) { return $_[0]->{name}; }

=head2 setName()

Set the name of the archive. The name may also be specified at initialisation;
see the synopsis above.

=cut

sub setName ($$) { $_[0]->{name}=$_[1]; }

=head2 getPath()

Return the path to the archive.

=cut

sub getPath ($) { return $_[0]->{path}; }

=head2 setName()

Set the path to the archive. The path may also be specified (as part of the
absolute pathname) at initialisation; see the synopsis above.

=cut

sub setPath ($) { $_[0]->{path}=$_[1];  }

#------------------------------------------------------------------------------

=head2 getObject($objectid)

Return the object with the specified ID from the archive, or C<undef> if the
object is not present. If supplied with a L<Binary::Object> object as an
argument, checks whether or not the archive contains a object with the same
name.

=cut

sub getObject ($$) { return $_[0]->{objects}{$_[1]}; }

=head2 getObjects()

Return a list of all objects currently registered in the archive.

=cut

sub getObjects ($) {
    my ($self)=@_;

    return wantarray ? @{[sort values %{$self->{objects}}]} : $self->{objects};
}

=head2 addObject($object)

Add the specified object object to the archive, replacing any existing object
with the same name, if present.

=cut

sub addObject ($$) {
    my ($self,$object)=@_;
    $self->throw("Not an object"),return undef
      unless $object->isa("Binary::Object");

    $self->{objects}{$object}=$object; # stringifies object to get hash key
    return 1;
}

=head2 addObjects(@objects)

Add one or more objects to the archive, replacing any existing objects with the
same name, if present.

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

Creare a new L<Binary::Object> object for the specified object file and add
it to the archive, replacing any existing object with the same name. See
also L<"addBinaryFile">.

=cut

sub addObjectFile ($$) {
    my ($self,$file)=@_;
    my $object=eval { new Binary::Object($file) };
    return undef unless $object;
    return $self->addObject($object);
}

=head2 addBinaryFile($filename)

A straight wrapper for L<"addObjectFile"> above, this method corresponds to
L<Binary::Aggregate/addBinaryFile>, except that since an archive cannot add
another archive as a member, it makes no attempt to identify its argument and
assumes it is to be converted into a L<Binary::Object> instance.

=cut

sub addBinaryFile ($$) {
    my ($self,$file)=@_;

    return $self->addObjectFile($file);
}

=head2 removeObject($objectid)

Remove and return the named object from the archive. Returns C<undef> if the
named object is not present.

=cut

sub removeObject ($$) {
    my ($self,$objectid)=@_;

    return delete $self->{objects}{$objectid};
}

=head2 removeObjects(@objectids)

Remove one or more named objects from the archive, if present. Supplied object
names that are not present in the archive are silently ignored.

=cut

sub removeObjects ($@) {
    my ($self,@objectids)=@_;

    $self->removeObject($_) foreach @objectids;
}

=head2 removeAllObjects()

Remove all currently resident objects from the archive.

=cut

sub removeAllObjects ($) {
    undef %{$_[0]->{objects}};
    $_[0]->{objects}={};
}

#------------------------------------------------------------------------------

=head2 getSymbol($symbolid)

Return the symbol with the given name, if it exists in the archive. If
the symbol is not present C<undef> is returned. If a defined version of the
symbol is present it is returned in preference to any instances of the
same symbol that are undefined. Only one instance of the symbol is returned
if it is multiply undefined (or indeed multiply defined).

=cut

sub getSymbol ($$) {
    my ($self,$name)=@_;

    return $self->getDefinedSymbol($name) || $self->getUndefinedSymbol($name);
}

=head2 getDefinedSymbol($symbolid)

Return the defined symbol with the given name, if it exists in the archive. If
the symbol is not present or the archive references the symbol only, C<undef>
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

Return the undefined symbol with the given name, if it exists in the archive
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

Return a list of symbol objects for each symbol in the archive, defined or
undefined. Only one symbol object is returned for each undefined symbol
present. (More than one object in the archive may reference it, but only
the last one encountered is returned).

For most cases L<"getDefinedSymbols"> and L<"getUndefinedSymbols"> are
probably more appropriate than this method.

=cut

sub getSymbols ($) {
    return ($_[0]->getDefinedSymbols,$_[0]->getUndefinedSymbols);
}

=head2 getDefinedSymbols()

Return a list of symbol objects for all defined symbols in this archive.
Symbols are presumed to be unique within the archive.

=cut

sub getDefinedSymbols ($;$) {
    my $self = $_[0];

    my $defined = $_[1] ||= {};
    $_->getDefinedSymbols($defined) foreach (values %{$self->getObjects()||{}});

    return wantarray ? values %$defined : $defined;
}

=head2 getUndefinedSymbols()

Return a list of symbols objects for all symbols referenced by an object in
the archive that are not defined elsewhere in the same archive. Only one
instance of each undefined symbol is returned; use L<"getSymbolRefs"> to
retrieve all instances of an undefined symbol within the archive.

=cut

sub getUndefinedSymbols ($;$) {
    my $self = $_[0];

    my $defined;
    my $undefined = $_[1] ||= {};
    foreach my $object (values %{$self->getObjects()||{}}) {
	$object->getDefinedSymbols($defined);
	$object->getUndefinedSymbols($undefined);
    }
    delete $undefined->{$_} foreach (keys %$defined);
    return wantarray ? values %$undefined : $undefined;
}

=head2 getAllUndefines()

Return a hash reference to symbols undefined in any object in the archive.

=cut

sub getAllUndefines ($;$) {
    my $self = $_[0];
    my $undefined = $_[1] ||= {};
    map { $_->getAllUndefines($undefined) } values %{$self->getObjects()||{}};
    return $undefined;
}

=head2 getSymbolRefs($symbolid)

Return a list of symbol objects for each undefined reference to the symbol
within the archive. This method makes no statement as to whether the symbol
is defined in the archive or not.

=cut

sub getSymbolRefs ($$) {
    my ($self,$name)=@_;

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
    my $archive=new Binary::Archive($_[0] || "/usr/lib/libsocket.a");
    print "=== Archive $archive is located at ",$archive->getPath(),"\n";

    my @objects=$archive->getObjects();
    print "Objects: @objects\n";

    my @definedsymbols=$archive->getDefinedSymbols();
    print "Defined: @definedsymbols\n";

    my @undefinedsymbols=$archive->getUndefinedSymbols();
    print "Undefined: @undefinedsymbols\n";

    foreach my $name ('connect','select','foobar') {
	my $symbol=$archive->getSymbol($name);

	unless ($symbol) {
	    print "'$name' does not exist in $archive\n";
	    next;
	}

	print "'$symbol'\n";
	print "-- ",($symbol->isDefined?"*defined*":"UNDEFINED"),
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

L<Binary::Aggregate>, L<Binary::Object>, L<Binary::Symbol>, L<Binary::Cache>

=cut

1;
