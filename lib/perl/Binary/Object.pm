package Binary::Object;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';

use Util::File::Basename qw(dirname basename);

use Binary::Symbol::Scanner;
use Binary::Symbol::Parser;

#==============================================================================

=head1 NAME

Binary::Object - Abstract representation of a binary object file

=head1 SYNOPSIS

    my $object=new Binary::Object("/home/my/build/myobject.o");
    print "Object $object is located at ",$object->getPath(),"\n";

    my @symbols=$object->getSymbols();
    my @definedsymbols=$object->getDefinedSymbols();
    my @undefinedsymbols=$object->getUndefinedSymbols();
    my $symbol=$object->getSymbol("myfunction");

=head1 DESCRIPTION

C<Binary::Object> provides an abstract representation of a binary object,
It consists of a collection of one or more binary symbols, themselves
represented by C<Binary::Symbol> objects, and provides methods to determine
the presence and status (defined or undefined) of symbols in the object.

=cut

#==============================================================================

=head1 CONSTRUCTORS

=head2 new($filename)

Create a new instance of a C<Binary::Object> object using the object filename
passed as the intialiser. Symbols are found and extracted with the
L<Binary::Symbol::Scanner> and L<Binary::Symbol::Parser>. Returns an object
populated with C<Binary::Symbol> instances on success, or an empty (but valid)
object if no symbols could be found or parsed.

=head2 new($aref [,$init])

Creates a new instance of a C<Binary::Object> object populated with the
provided list of L<Binary::Symbol> objects, passed in an array reference,
as its contents.

An optional third argument be passed to supply the object name and path, but
is not used to read from the filesystem. Alternatively, if the first element
of the passed array is not a L<Binary::Symbol>, it is evaluated as a string
and used to intialise the object name and path.

=cut

sub fromString ($$) {
    my ($self,$init)=@_;
    my $scanned=(new Binary::Symbol::Scanner())->scan($init);
    $self->initialiseFromArray([values %{$scanned->{basename($init)}}],$init);
    ## XXX: would be nicer if we had an initialiseFromHash()
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

    #my $element = 0;

    my $symbols = \%{$self->{symbols}};
    foreach my $symbol (@$aref) {

	# check we weren't passed invalid symbols
	#$self->throw("Element $element is not a Binary::Symbol")
	#  unless $symbol->isa("Binary::Symbol");
	#++$element;

	$symbols->{$symbol->getName} = $symbol;
    }

    return 0; # continue
}

#------------------------------------------------------------------------------

=head1 METHODS

=head2 getName()

Get the name of the object.

=head2 setName($name)

Set the name of the object. This should be the leafname only, containing no
path information. See also L<"setPath">.

=head2 getPath ()

Get the path to the object.

=head2 setPath ($path)

Set the path to the object. See also L<"setName">.

=cut

sub getName ($) { return $_[0]->{name}; }
sub getPath ($) { return $_[0]->{path}; }

sub setName ($) { $_[0]->{name}=$_[1];  }
sub setPath ($) { $_[0]->{path}=$_[1];  }

=head2 getSymbol($name)

Return the symbol object with the supplied name, if present, or C<undef>
otherwise.

=cut

sub getSymbol ($$) {
    #my ($self,$name)=@_;

    $_[0]->throw("Undefined or empty name") unless $_[1];

    return $_[0]->{symbols}{$_[1]};
}

=head2 getDefinedSymbol($name)

Return the symbol object with the supplied name if it is present and is a
defined symbol, or C<undef> otherwise.

=cut

sub getDefinedSymbol ($$) {
    #my ($self,$name)=@_;

    my $symbol=$_[0]->getSymbol($_[1]);
    return undef unless $symbol;
    return undef unless $symbol->isDefined();
    return $symbol;
}

=head2 getDefinedSymbol($name)

Return the symbol object with the supplied name if it is present and is an
undefined symbol, or C<undef> otherwise.

=cut

sub getUndefinedSymbol ($$) {
    #my ($self,$name)=@_;

    my $symbol=$_[0]->getSymbol($_[1]);
    return undef unless $symbol;
    return undef unless $symbol->isUndefined();
    return $symbol;
}

=head2 getSymbols()

Return a list of all symbols currently assigned to this object.

=cut

sub getSymbols ($) {
    return wantarray ? values %{$_[0]->{symbols}} : $_[0]->{symbols};
}

=head2 getDefinedSymbols()

Return a list of all symbols that are defined and currently assigned to this
object.  If an optional argument of a hashref is passed, symbols will be added
to the hashref, and the hashref will be returned.

=cut

sub getDefinedSymbols ($;$) {
    if (@_ < 2 && wantarray) {
	return grep { $_->isDefined } (values %{$_[0]->getSymbols});
    }
    else {
	my $defined = $_[1] ||= {};
	foreach (values %{$_[0]->getSymbols}) {
	    next unless $_->isDefined;
	    (exists $defined->{$_})
	      ? (push @{$defined->{$_}{dups}}, $_)
	      : ($defined->{$_} = $_);
	}
	return $defined;
    }
}

=head2 getUndefinedSymbols()

Return a list of all symbols that are undefined and currently assigned to this
object.  If an optional argument of a hashref is passed, symbols will be added
to the hashref, and the hashref will be returned.

=cut

sub getUndefinedSymbols ($;$) {
    if (@_ < 2 && wantarray) {
	return grep { $_->isUndefined } (values %{$_[0]->getSymbols});
    }
    else {
	my $undefined = $_[1] ||= {};
	foreach (values %{$_[0]->getSymbols}) {
	    next unless ($_->isUndefined());
## GPS: FIXME: {refs} should be in the Binary::Symbol.pm module
##	with accessors used here.  Fix symbolvalidate.pl, too.
## GPS: FIXME: should we store getLongName instead of just getObject?
##	Storing only object name assumes unique filenames for ALL objects.
##	(Changing this has ramifications on memory usage)
	    if (exists $undefined->{$_}) {
		# keep hash of all references to this symbol
		$undefined->{$_}{refs}{$_->getObject()} = $_;
	    }
	    else {
		$undefined->{$_} = $_;
		$_->{refs}{$_->getObject()} = $_;
	    }
	}
	return $undefined;
    }
}

=head2 getAllUndefines()

Return a hash reference to symbols undefined in the object.

=cut

sub getAllUndefines ($;$) {
    return scalar getUndefinedSymbols($_[0],$_[1]);
}

#------------------------------------------------------------------------------

sub toString ($) {
    return $_[0]->getName();
}

#==============================================================================

sub test ($) {
    my $object=new Binary::Archive($_[0]);

    print "== Archive: $object\n";
    foreach my $symbol ($object->getSymbols()) {
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

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Binary::Aggregate>, L<Binary::Archive>, L<Binary::Symbol>, L<Binary::Cache>

=cut

1;
