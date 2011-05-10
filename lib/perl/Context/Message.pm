package Context::Message;
use strict;

use overload '""' => "toString", fallback => 1;
use base 'BDE::Object';

use Context::Message::Types qw(:ALL);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

Context::Message::Entry - Abstract representation of a symbol table entry

=head1 SYNOPSIS

    use Context::Message::Types qw(WARNING);
    use Context::Message::Codes qw(MISSING_INC);
    my $message=new Context::Message({
        code         => MISSING_INC,
        type         => WARNING,
        fileName     => "incwell.txt",
        lineNumber   => 42,
        text         => "Incwell is dry!"
    });

=head1 DESCRIPTION

C<Context::Message> provides an abstract representation of a symbol table entry
derived from a compiled object or library text file.

This module is not generally expected to be used to create symbol objects
directly. Rather, C<Context::Message::Scanner> and C<Context::Message::Parser>
are used to generate C<Context::Message> objects from binary object and texts.

=cut

#<<<TODO: Add a 'column' attribute and use it to render a two-line msg with
#<<<TODO: a caret pointing to that position in the supplementary text?
#<<<TODO: e.g: ?? Warning: Bad foo (file.txt@123): hello foo world

#==============================================================================

=head1 CONSTRUCTOR

=head2 new([$init])

Create a new C<Context::Message> object, optionally by passing in a hash
reference to a list of attributes.

  code        - The short message description, preferably extracted from a 
                symbol module as a constant. See L<Context::Message::Codes>.

  type        - The message classification, modeled on the C<syslog>
                classifications.  See L<Context::Message::Types>.

  rule        - The optional rule ID, for user-defined classification of 
                messages.

  fileName    - The file in which the message arose.

  lineNumber  - The line number in the file at which the message arose (only
                valid if C<filename> set).

  displayFrom - Contents from which to extract line to display (only valid if
                C<filename> and C<lineNumber set, and must be a reference).

  displayLine - Content line to display (only valid if C<displayFrom> not set).

  text        - Supplementary message text.

C<code> and C<type> must be set during the course of processing the current
message; the remaining attributes are optional.

When rendered in string context, the message will adopt an appropriate form
contingent upon which of these attributes is set. Only the type, indicating
the message classification, is truly mandatory -- if unspecified, it defaults
to INFO level.

See the synopsis for usage examples and L<Context::Message::Log/addMessage>
for adding a message to a context log.

=cut

sub initialiseFromHash ($$) {
    my ($self,$init)=@_;

    $self->SUPER::initialiseFromHash($init);

    # if passed an object, this evaluates it into string
    $self->{code} = "".$self->{code};

    $self->{fileName} = basename($self->{fileName}) if $self->{fileName};

    if ($self->{lineNumber}) {
    #if (exists $self->{lineNumber}) {
	# lineNumber might be iterator, in which case we have "0+" overloaded
	my $n = int(0+($self->{lineNumber}));
	$self->{lineNumber} = $n;
        if (!$self->{displayLine} and ref($self->{displayFrom}) and
	    ${$self->{displayFrom}} =~/(?:(.*)\n){$n}/) {
	    $self->{displayLine} = $1;
	}
    }

    return $self;
}

=head1 METHODS

=head2 getType()

Get the numeric message type.

=head2 getTypeName()

Get the message type name (derived from the numeric type).

=head2 setType($typeid)

Set the numeric message type, preferably from one of the symbols defined in
L<Context::Message::Types>, e.g. C<IS_WARNING>.

=head2 getCode()

Set the message code.

=head2 setCode($code)

Set the message code (short message descripttion). While this is a string,
it is recommened that codes are defined by symbol modules - see L<Symbols>
amd L<Context::Message::Codes>.

=head2 getFileName()

Get the filename.

=head2 setFileName($filename)

Set the filename.

=head2 getRule()

Get the rule name.

=head2 setRule($rulename)

Set the rule name. The rule is an additional piece of metadata that
may be used to categorise messages according to a user-defined classification.

=head2 getLineNumber()

Get the numeric line number.

=head2 setLineNumber($linenumber)

Set the numeric line number.

=head2 getDisplayFrom()

Get the "display from" reference.

=head2 setDisplayFrom($ref)

Set the "display from" reference.

=head2 getDisplayLine()

Get the display line.

=head2 setDisplayLine($line)

Set the display line.

=head2 getText()

Get supplementary text.

=head2 setText()

Set supplementary text.

=cut

sub getCode         ($) { return $_[0]->{code}        || "" }
sub getType         ($) { return $_[0]->{type}        || 0  }
sub getRule         ($) { return $_[0]->{rule}        || "" }
sub getFileName     ($) { return $_[0]->{fileName}    || "" }
sub getLineNumber   ($) { return $_[0]->{lineNumber}  || 0  }
sub getDisplayFrom  ($) { return $_[0]->{displayFrom} || 0  }
sub getDisplayLine  ($) { return $_[0]->{displayLine} || "" }
sub getText         ($) { return $_[0]->{text}        || "" }

sub getTypeName ($) {
    my $self=shift;

    my $name=$self->getCtxTypeName($self->getType);
    return $name || '???['.$self->getType().']???';
}

sub setCode        ($$) { $_[0]->{code}        = $_[1];  }
sub setType        ($$) { $_[0]->{type}        = $_[1];  }
sub setRule        ($$) { $_[0]->{rule}        = $_[1];  }
sub setLineNumber  ($$) { $_[0]->{lineNumber}  = $_[1];  }
sub setDisplayFrom ($$) { $_[0]->{displayFrom} = $_[1];  }
sub setDisplayLine ($$) { $_[0]->{displayLine} = $_[1];  }
sub setText        ($$) { $_[0]->{text}        = $_[1];  }

sub setFileName    ($$) { $_[0]->{fileName}    = basename($_[1]);  }

#------------------------------------------------------------------------------

sub toString ($) {
    my $self=shift;

    my $rule = $self->getRule();
    $rule = "[$rule]" if $rule;

    my $message = $self->getTypeName( ). ": $rule " . $self->getCode();
    $message .= " " . $self->getText if $self->getText();

    if (my $fileName = $self->getFileName()) {
	$message .= ", file " . $fileName;
	if ($self->getDisplayLine()) {
	    $message .= ":\n       at line " . $self->getLineNumber() . ": " .
	      $self->getDisplayLine();
	}
	else {
	    $message .= "@" . $self->getLineNumber() if $self->getLineNumber();
	}
    }

    return $message;
}

#------------------------------------------------------------------------------

=head1 CLASS METHODS

These methods provide translation between type IDs and type names. They may
ultimately migrate to L<Context::Message::Types>. See also L<"getTypeName">.

=cut

{
    my (%types,%typenames);

    #<<<TODO: This should either be smarter, or get moved to
    #Context::Message::Types as some kind of 'smart import' post-processing
    #setup step.
    %types=(
	    IS_EMERGENCY() => EMERGENCY_NAME(),
	    IS_ALERT()     => ALERT_NAME(),
	    IS_CRITICAL()  => CRITICAL_NAME(),
	    IS_ERROR()     => ERROR_NAME(),
	    IS_WARNING()   => WARNING_NAME(),
	    IS_NOTICE()    => NOTICE_NAME(),
	    IS_INFO()      => INFO_NAME(),
	    IS_DEBUG()     => DEBUG_NAME(),
	   );
    %typenames = reverse %types; #reverse-map a hash

=head2 getCtxTypeName($typeid)

Return the type name for the specified numeric ID, or C<undef> otherwise.
See L<Context::Message::Types>

=cut

    sub getCtxTypeName ($;$) {
	my $type = defined($_[1])?$_[1]:$_[0]; #method or sub
	if (exists $types{$type}) {
	    return $types{$type};
	}

	return undef;
    }

=head2 getCtxTypeFromName($typename)

Return the type ID for the specified type name, or C<undef> if there is no
corresponding type ID. See L<Context::Message::Types>.

=cut

    sub getCtxTypeFromName ($;$) {
	my $name = defined($_[1])?$_[1]:$_[0]; #method or sub
	if (exists $typenames{$name}) {
	    return $typenames{$name};
	}

	return undef;
    }

=head2 getAllCtxTypes()

Return all valid numeric context type IDs.

=head2 getAllCtxTypeNames()

Return all valid type names.

=cut

    sub getAllCtxTypes ()     { return sort keys %types; }
    sub getAllCtxTypeNames () { return sort keys %typenames; }
}

#==============================================================================

sub test {
    eval {
        use Context::Message::Types qw(IS_INFO IS_ERROR);
        use Context::Message::Codes qw(NO_ERROR);
    };

    my $message=new Context::Message({
        code => NO_ERROR,
        file => "erewhon.txt",
        line => 42,
        type => IS_INFO,
        text => "Hi!"
    });
    print $message,"\n";

    # possible extension - type-specific constructors
    # my $error=error Context::Message(NO_INCLUDE() => "Incwell is dry!");
    # print $error,"\n";
}

sub test2 {
    eval {
        use Source::Iterator;
        use Context::Message::Types qw(IS_INFO IS_ERROR);
        use Context::Message::Codes qw(NO_ERROR);
    };

    my $src = "A\nB\nC\nD\n";
    my $z = new Source::Iterator($src);
    $z->next();
    my $message=new Context::Message({
				      code        => NO_ERROR,
				      type        => IS_INFO,
				      fileName    => "erewhon.txt",
				      lineNumber  => $z,
				      displayFrom => \$src,
				      text        => "Hi!"
				     });
    print $message,"\n";

#    print "LKLKJL" if $z->isa("Source::Iterator::NoRCS");
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Context::Report>, L<Context::Message::Codes>, L<Context::Message::Types>

=cut

1;
