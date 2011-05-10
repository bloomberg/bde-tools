package Binary::Symbol;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';

#==============================================================================

=head1 NAME

Binary::Symbol - Abstract representation of a symbol table entry

=head1 SYNOPSIS

    my $entry=new Binary::Symbol({
        name  => "my_symbol",
        weak  => 0,
        type  => "D",
        value => 0x0007834
    });

=head1 DESCRIPTION

C<Binary::Symbol> provides an abstract representation of a symbol table entry
derived from a compiled object or library archive file.

This module is not generally expected to be used to create symbol objects
directly. Rather, C<Binary::Symbol::Scanner> and C<Binary::Symbol::Parser>
are used to generate C<Binary::Symbol> objects from binary object and archives.

=cut

#==============================================================================

=head1 CONSTRUCTOR

=head2 new([$init])

Create a new C<Binary::Symbol> object, optionally by passing in a hash
reference to a list of attributes:

  name
  value
  weak
  type
  object
  archive

See the synopsis for an example.

=head1 METHODS

=head2 getName()

Get the symbol name.

=head2 getLongName()

Get the symbol name qualified by the archive and object in the form:

    <archive>[<object>]:<symbol>

=head2 getLongDelimitedName($delimiter)

Get the symbol name qualified by the archive and object.
Returned delimited by ':', or optional $delimiter passed as argument:

    <archive>:<object>:<symbol>

=head2 getFullName()

As C<getLongName>, except that the archive prefix and the
archive and object suffixes are stripped in the returned string.

=head2 getFullDelimitedName($delimiter)

As C<getLongDelimitedName>, except that the archive prefix and the
archive and object suffixes are stripped in the returned string.

=head2 setName($name)

Set the symbol name.

=head2 getValue()

Get the symbol value.

=head2 setValue($value)

Set the symbol value.

=head2 getType()

Get the (one letter) symbol type.

=head2 setType($type)

Set the (one letter) symbol type.

=head2 getObject()

Get the name of the object to which this symbol belongs.

=head2 setObject($object)

Set the name of the object to which this symbol belongs.

=head2 getArchive()

Get the name of the archive to which this symbol belongs (if any).

=head2 setArchive($archive)

Set the name of the archive to which this symbol belongs (if any).

=cut

sub getName     ($) { return ${$_[0]->{name}};    }
sub getValue    ($) { return 0 unless exists $_[0]->{value};
		      return $_[0]->{value};      }
sub getType     ($) { return ${$_[0]->{type}};    }
sub getObject   ($) { return ${$_[0]->{object}};  }
sub getArchive  ($) { return ${$_[0]->{archive}}; }
sub getSize     ($) { return 0 unless exists $_[0]->{size};
		      return $_[0]->{size};       }
sub getSection  ($) { return 0 unless exists $_[0]->{section};
		      return $_[0]->{section};       }
sub getOffset   ($) { return 0 unless exists $_[0]->{offset};
		      return $_[0]->{offset};       }

sub setName    ($$) { $_[0]->{name}=\("$_[1]");     }
sub setValue   ($$) { $_[0]->{value}=$_[1]+0;       }
sub setType    ($$) { $_[0]->{type}=\("$_[1]");     }
sub setObject  ($$) { $_[0]->{object}=\("$_[1]");   }
sub setArchive ($$) { $_[0]->{archive}=\("$_[1]");  }
sub setSize    ($$) { $_[0]->{size}=$_[1]+0;        }
sub setSection ($$) { $_[0]->{section}=$_[1]+0;     }
sub setOffset  ($$) { $_[0]->{offset}=$_[1]+0;     }

sub isWeak      ($) { return 0 unless exists $_[0]->{weak};
		      return ${$_[0]->{weak}};    }
sub setWeak     ($) { $_[0]->{weak}=$_[1]?\1:\0; }

sub isCommon    ($) { return 0 unless exists $_[0]->{common};
		      return ${$_[0]->{common}};    }
sub setCommon   ($) { $_[0]->{common}=$_[1]?\1:\0; }

sub isTemplate  ($) { return 0 unless exists $_[0]->{template};
		      return ${$_[0]->{template}};    }
sub setTemplate ($) { $_[0]->{template}=$_[1]?\1:\0; }

sub isLocal     ($) { return 0 unless exists $_[0]->{'local'};
		      return ${$_[0]->{'local'}};    }
sub setLocal    ($) { $_[0]->{'local'}=$_[1]?\1:\0; }



sub getLongName ($) {
    return ${$_[0]->{archive}}."[".${$_[0]->{object}}."]:".${$_[0]->{name}};
}

sub getLongDelimitedName ($;$) {
    my $d=defined($_[1]) ? $_[1] : ':';
    return join $d,${$_[0]->{archive}},${$_[0]->{object}},${$_[0]->{name}};
}

sub getFullName ($) {
    my $arc=${$_[0]->{archive}}; $arc=~/^lib([^.]+)/ and $arc=$1;
    my $obj=${$_[0]->{object}}; $obj=~/^([^.]+)/ and $obj=$1;
    return $arc . "[" . $obj . "]:" . ${$_[0]->{name}};
}

sub getFullDelimitedName ($;$) {
    my $d=defined($_[1]) ? $_[1] : ':';
    my $arc=${$_[0]->{archive}}; $arc=~/^lib([^.]+)/ and $arc=$1;
    my $obj=${$_[0]->{object}}; $obj=~/^([^.]+)/ and $obj=$1;
    return join $d,$arc,$obj,${$_[0]->{name}};
}

#------------------------------------------------------------------------------

=head2 isDefined()

Return true if the symbol is defined, false otherwise. This is currently
defined as being equivalent to a type of C<U>, but may change as more
complex criteria develop. Use the method to be sure of future compatibility.

=cut

sub isDefined ($) {
    #<<TODO: Binary::Symbol::Types;
    return ${$_[0]->{type}} ne 'U';
}

=head2 isUndefined()

Return true of the symbol is undefined, false otherwise. This method is
simply the inverse of L<"isDefined">, above.

=cut

sub isUndefined ($) {
    return ! $_[0]->isDefined();
}

#------------------------------------------------------------------------------

sub toString ($) { return ${$_[0]->{name}}; }

#<<TODO: regnerate original parsable symbol string
#<<TODO: combine into universal format:
#<<TODO:    archive[object]: value type[*=weak] symbol

#<<TODO: provide proper abstraction of symbol types

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Binary::Aggregate>, L<Binary::Archive>, L<Binary::Object>,
L<Binary::Symbol::Scanner>, L<Binary::Symbol::Parser>

=cut

1;

