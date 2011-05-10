package Context::Log;
use strict;

use overload '""' => "toString", fallback => 1;

use base 'BDE::Object';

use Context::Message;
use Context::Message::Types qw(:ALL);

#==============================================================================

=head1 NAME

Context::Log - Manage a collection of context messages

=head1 SYNOPSIS

    use Context::Message::Codes qw(EMP_FILE);
    use Context::Message::Types qw(IS_INFO);

    my $log=new Context::Log();
    $log->setDefault(file => "myfile.txt");
    $log->addError(code => EMP_FILE);
    $log->addMessage(type => IS_INFO, text => "Try adding some content");

    print $log;

=head1 DESCRIPTION

C<Context::Log> is a container class providing management for a collection of
context messages, themselves represented by C<Context::Message> objects, and
provides methods to add, remove, extract, and render messages in order.

A default context message may be set up with the L<"setDefault"> method. This
message is then used to supply default values for messages added with the
L<"addMessage"> method, obviating the need to supply repeated values. However,
the default message should also be reset with L<"resetDefault"> in order to
avoid defaults appearing in contexts for which they were not intended.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new([$name])

Create a new empty instance of a C<Context::Log> object, using the
specified log name if provided. (The name is purely for informational
convenience.) 

=head2 new($aref [,$init])

Creates a new instance of a C<Context::Log> message populated with the
provided list of L<Context::Message> messages, passed in an array reference,
as its contents.

An optional third argument be passed to supply the log name.  Alternatively,
if the first element of the passed array is not a L<Context::Message>, it is
evaluated as a string and used to intialise the log name.

=cut

sub fromString ($$) {
    my ($self,$init)=@_;

    $self->setName($init);
    $self->{messages}=[];
    $self->setDefault();
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
	$self->setName($init);
    }

    $self->{messages} = [];

    # check we weren't passed invalid messages
    foreach my $messageno (0 .. @$aref) {
	my $message=$aref->[$messageno];
	next unless $message;

	$self->throw("Element $messageno is not a Context::Message")
	  unless ($aref->[$messageno])->isa("Context::Message");

        push @{$self->{messages}}, $message;
    }

    $self->setDefault();

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getName()

Return the name of the log.

=cut

sub getName ($) { return $_[0]->{name}; }

=head2 setName()

Set the name of the log. The name may also be specified at initialisation;
see the synopsis above.

=cut

sub setName ($$) { $_[0]->{name}=$_[1]; }

#------------------------------------------------------------------------------

=head2 getMessage($index)

Return the message with the specified ID from the log, or C<undef> if the
message is not present. If supplied with a L<Context::Message> message as an
argument, checks whether or not the log contains a message with the same
name.

=cut

sub getMessage ($$) {
    my ($self,$index)=@_;

    if (abs($index) < scalar(@{$self->{messages}})) {
	return $self->{messages}[$index];
    }

    return undef;
}

=head2 getMessages()

Return a list of all messages currently registered in the log.

=cut

sub getMessages ($) {
    my ($self)=@_;

    return @{$self->{messages}};
}

=head2 addMessage($message)

Add the specified message the log.

=cut

sub addMessage ($$) {
    my $self=shift;
    my $message;

    if (scalar(@_)==1) {
	$message=shift;

	$self->throw("Not an message"),return undef
	  unless $message->isa("Context::Message");
    } else {
	my %attrs = (%{$self->{default}}, @_);
	$message=new Context::Message({%attrs});
    }

    push @{$self->{messages}},$message;
    return 1;
}

=head2 addMessages(@messages)

Add one or more messages to the log.

=cut

sub addMessages ($@) {
    my ($self,@messages)=@_;

    foreach my $message (@messages) {
	return undef unless $self->addMessage($message);
    }

    return 1;
}

=head2 removeMessage($index)

Remove and return the named message from the log. Returns C<undef> if the
named message is not present.

=cut

sub removeMessage ($$) {
    my ($self,$index)=@_;

    return splice @{$self->{messages}},$index;
}

=head2 removeMessages(@indices)

Remove one or more messages by index from the log, if they exist.

=cut

sub removeMessages ($@) {
    my ($self,@indices)=@_;

    return map { $_->removeMesage() } @indices;
}

=head2 removeAllMessages()

Remove all currently resident messages from the log.

=cut

sub removeAllMessages ($) {
    my $messages=$_[0]->{messages};
    $_[0]->{messages}=[];
    return @$messages if defined wantarray;
}

#------------------------------------------------------------------------------

sub addEmergency { return shift->addMessage(@_, type => IS_EMERGENCY); }
sub addAlert     { return shift->addMessage(@_, type => IS_ALERT);     }
sub addCritical  { return shift->addMessage(@_, type => IS_CRITICAL);  }
sub addError     { return shift->addMessage(@_, type => IS_ERROR);     }
sub addWarning   { return shift->addMessage(@_, type => IS_WARNING);   }
sub addNotice    { return shift->addMessage(@_, type => IS_NOTICE);    }
sub addInfo      { return shift->addMessage(@_, type => IS_INFO);      }
sub addDebug     { return shift->addMessage(@_, type => IS_DEBUG);     }

#<<<TODO:
# sub getErrors -> get all messages of IS_ERROR or higher
# sub getErrorsOnly -> get all messages of IS_ERROR class only
#   ...and so on for all other category types
#
# sub getMessagesOfType($typeid,$typeid...) - retrieve one or more selected
#   classes
#
# sub getLogofType($typeid,$typid...) - retrive all msgs of selected types and
#   return as a new Context::Log
#
# sub removeMessagesofType($typeid,$typeid...) - remove all msgs of selected
#   types from the log and return them (in same manner as 'delete').
# sub addLog($log) - amalgamate another log into this one - use it for
# amalgamating Rules logs into the bde_verify.pl log for instance.

#------------------------------------------------------------------------------
# Default message attributes

=head2 getDefault()

Return the C<Context::Message> object that contains the default settings for
messages added with L<"addMessage"> or L<"addMessages">.

=cut

sub getDefault ($) {
    my $self=shift;

    unless (exists $self->{default}) {
	$self->{default}=$self->resetDefault();
    }

    return $self->{default};
}


=head2 setDefault (attr=>value [,attr=>value ...])

Set the default values for one or more message attributes, as documented by
L<Context::Message/new>. These attributes are used to supply default values
for calls to L<"addMessage"> or L<"addMessages">.

=cut

sub setDefault ($@) {
    my ($self,%attrs)=@_;

    foreach (keys %attrs) {
	$self->{default}->{$_}=$attrs{$_}; #TODO < improve checking
    }
}

=head2 resetDefault()

Reset the default settings for new messages to no defaults. Clears any
default attributes set by L<"setDefault">.

=cut

sub resetDefault ($) {
    $_[0]->{default}=new Context::Message(); #empty
}


#------------------------------------------------------------------------------

sub toString ($) {
    return join "\n",$_[0]->getMessages();
}

#==============================================================================

sub test (;$) {
    eval {
       use Context::Message::Types qw(IS_INFO IS_WARNING IS_ERROR);
       use Context::Message::Codes qw(NO_ERROR EMP_FILE);
       1;
    } or die "Failed to import: $@";

    # 1 - create log
    my $log=new Context::Log();

    # 2 - add a message
    $log->addMessage(new Context::Message({
        code => NO_ERROR, type => IS_INFO, text => "Hi!"
    }));

    # 3 - establish defaults, add a message
    $log->setDefault(type => IS_WARNING, text => 'a default msg');
    $log->setDefault(file => "default.txt");
    $log->addMessage(code => EMP_FILE);
    # 3a - via explicit code method
    $log->addError(code => EMP_FILE);

    # 4 - partially override defaults, add another message
    $log->addMessage(code => NO_ERROR, file => "noerror.txt");

    # 5 - add a Context::Message directly
    my $msg=new Context::Message({
        type=>IS_WARNING,
        code=>EMP_FILE, file => "direct.txt", rule => "straight"
    });
    $log->addMessage($msg); #once
    $log->addMessages($msg,$msg); #and twice more

    # 5 - what did we get?
    print $log,"\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainright@bloomberg.net)

=head1 SEE ALSO

L<Context::Message>, L<Context::Message::Types>, L<Context::Message::Codes>,
L<Util::Message>

=cut

1;
