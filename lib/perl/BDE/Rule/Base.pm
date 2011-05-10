package BDE::Rule::Base;
use strict;

use overload '""' => "toString", fallback => 1;
use base qw(BDE::Object);

use Context::Log;
use Context::Message::Codes  qw(EMP_FILE);
use Util::Message qw(debug error alert verbose verbose_alert verbose_error);

#==============================================================================

=head1 NAME

BDE::Rule::Base - Base class for source code verification rules

=head1 SYNOPSIS

    package My::Rule::Q3;
    use strict;

    use base qw(BDE::Rule::Base);

    sub verify ($$;$$) {
        my ($self,$component,$opts,$root)=@_;
	my $result=$self->SUPER::verify($component); #generic rule checks
	return $result unless defined($result) and not $result;

	# implement rule checks here...
        my $result=1; #1+=failure, 0=success

        return $self->setResult($result);
    }

    __DATA__
    The documentation for the rule goes here in POD format.

=head1 DESCRIPTION

C<BDE::Rule::Base> is a base class for deriving source code verification
rules. The synopsis above shows the basic structure of a derived rule class,
in particular the C<verify> method which is the interface to the rule. The
C<verify> method should return a non-zero value on failure, or zero for
success. The rule description should be placed in a C<DATA> section after
the main code.

=cut

#==============================================================================

=head1 CONSTRUCTORS

=head2 new ([$name])

Instantiate a new rule object of the invoking rule subclass. If a name is
supplied, it is used to name the rule, otherwise the rule is named after the
leafname of the rule's class.

The rule is initalised with an undefined result status and a description
which is read from the __DATA__ block in the rule module, if present.

=head2 new ($href)

Instantiate a new rule object of the invoking rule subclass using the supplied
hash reference to supply initial attribute values. Valid attributes are:

    name => the name of the rule
    description => a textual description of the rule
    result => initial result status

=cut

sub new ($) {
    my ($self,@args)=@_;
    my $class=(ref $self) || $self;
    my $name = "unnamed";

    @args=({ name => $args[0]}) if $#args==0 and not ref $args[0];
    $self=$class->SUPER::new(@args);

    $self->{name}        ||= ($class=~/:(\w+)$/) && $1;
    $self->{result}      ||= undef;

    no strict qw(refs);
    local $/=undef;
    unless (exists $self->{description}) {
	$self->{description} = eval "package $class; <DATA>";
    }
    return $self;
}

#------------------------------------------------------------------------------

=head1 ACCESSORS/MUTATORS

=head2 getName

Return the name of the rule. The name can also be derived by using the rule
object in a string context, for example C<print $rule>.

=cut

sub getName        ($)  { return $_[0]->{name};        }

=head2 getDescription

Return the textual documentation describing the rule.

=cut

sub getDescription ($)  { return $_[0]->{description}; }

=head2 getResult

Return the result status of the rule: C<undef> is the initial undefined state,
0 indicates success, and any true value indicates failure.

=cut

sub getResult      ($)  { return $_[0]->{result};      }

=head2 setName

Set the name of the rule.

=cut

sub setName        ($$) { $_[0]->{name} = $_[1];       }

=head2 setDescription

Set the description of the rule.

=cut

sub setDescription ($$) { $_[0]->{description}=$_[1];  }

=head2 setResult

Set the result status of the rule: C<undef> is the initial undefined state,
0 indicates success, and any true value indicates failure.

=cut

sub setResult      ($$) { $_[0]->{result} = $_[1];     }

#------------------------------------------------------------------------------

=head2 verify ($component)

Verify the rule against the supplied component, which must be an object in the
BDE::Component class or a subclass thereof. Return 0 on success, 1 on failure,
or undef if the rule could not be invoked (for example, because the supplied
argument was not a valid component object).

The base C<verify> method simply verifies that the object is a real component
and succeeds if so. However, it sets the rule status to failure so that the
result of invoking the rule is a failure unless a subclassing rule object
overloads it and sets the result to success (presumably after carrying out
a verification step).

This is the primary method of the rule class and must be overloaded and then
called as the first substantive act from inheriting rules.

=cut

sub verify ($$) {
    my ($self,$component)=@_;
    $self->setResult(undef); # clear previous result, if present

    unless ($component) {
	$self->throw("No component");
	return undef;
    }

    unless ($component->isa("BDE::Component")) {
	$self->throw("Not a component: $component");
	return undef;
    }

    verbose("Invoking rule $self->{name} on component $component");

    my $rc = 0;

    my $ctx = $self->getContext();
    $ctx->setDefault(rule => $self->{name});
    foreach my $file ($component->getIntfFile, $component->getImplFile) {
	$ctx->setDefault(fileName    => $file->getName(),
			 displayFrom => $file->getFullSource());
	if ($file->isEmpty()) {
	    $ctx->addError(code        => &EMP_FILE,
                           fileName    => $file->getName(),
			   displayFrom => $file->getFullSource());
	    $rc = 1;
	}
    }


    $self->setResult(1); # rules fail if they're not implemented
    return $rc; # tell child rule class that we (the base class) are happy
}

#------------------------------------------------------------------------------

=head2 resetResult

Reset the result status of the rule to the initial undefined state.

=cut

sub resetResult ($) {
    $_[0]->{result} = undef;
}

=head2 isDone

Return true if the rule has a defined state (i.e it has been invoked) or false
if the rule has an undefined state, indicating that it has not been invoked 
since initialisation or the last reset (see C<resetResult> above).

=cut

sub isDone ($) {
    return (defined $_[0]->getResult())?1:0;
}

#------------------------------------------------------------------------------

sub getContext ($) {
    my $self=shift;

    unless (exists $self->{context}) {
	$self->{context}=new Context::Log(ref $self);
    }

    return $self->{context};
}

sub resetContext ($) {
    my $self=shift;

    if ($self->{context}) {
	$self->{context}->removeAllMessages();
    }
}

#------------------------------------------------------------------------------

sub toString       ($) { return $_[0]->{name} };

#------------------------------------------------------------------------------

sub test {
    my $rule=new BDE::Rule::Base;
    $rule->setName("X1");
    $rule->setDescription("BDE::Rule::Base test rule");
    print "Rule name (explicit): ",$rule->toString(),"\n";
    print "Rule name (implicit): $rule","\n";
    print "Rule description:\n",$rule->getDescription(),"\n";
    print "X1 result : ",$rule->getResult()," (",$rule->isDone(),") \n";
    $rule->setResult(1);
    print "X1 result : ",$rule->getResult()," (",$rule->isDone(),") \n";
    $rule->setResult(0);
    print "X1 result : ",$rule->getResult()," (",$rule->isDone(),") \n";
    $rule->resetResult();
    print "X1 result : ",$rule->getResult()," (",$rule->isDone(),") \n";

    require BDE::FileSystem;
    require BDE::Component;
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    print "Filesystem located at: $root\n";
    foreach (qw[bdem_list bdet_time bteso_spinningeventmanager]) {
	print ">> $_ base path: ",$root->getComponentBasepath($_),"\n";
	my $comp=new BDE::Component($root->getComponentBasepath($_));

	my $result=$rule->verify($comp);
	print "$rule result ($_): $result\n";
    }
}

#------------------------------------------------------------------------------

=head1 AUTHOR

Peter Wainwright (pwainright@bloomberg.net)

=head1 SEE ALSO

L<BDE::RuleSet>

=cut

1;
