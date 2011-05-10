package BDE::RuleSet;
use strict;

use overload '""' => "toString", fallback => 1;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

#------------------------------------------------------------------------------

=head1 NAME

BDE::RuleSet - Manager for a collection of BDE::Rule objects

=head1 SYNOPSIS

    my $set=new BDE::RuleSet("My set of rules");
    my $rule1=new BDE::Rule::MyRule;
    my $rule2=new BDE::Rule::MyOtherRule;
    $set->addRule($rule1,$rule2);
    my $failures=$set->verify($component); #BDE::Component object
    if ($failures) {
        my $results=$set->getResults();
    }
    $set->resetResults();

=head1 DESCRIPTION

This module provides an object-oriented framework for managing sets of design
rules implemented as subclasses of the L<BDE::Rule::Base> module.

=cut

#------------------------------------------------------------------------------
# Constructor support

=head1 CONSTRUCTORS

=head2 new([$name])

Initialise a new empty ruleset with the specified name. If no name is supplied
a default name of C<RuleSet> is used.

=cut

sub fromString($;$) {
    my ($self,$init)=@_;

    $self->{name}=$init || "RuleSet";
    $self->{rules}={};
}

=head2 new($href)

Initialise a ruleset from the specified hash reference. Valid attributes are:

  name   => the name of the ruleset
  rules  => a reference to an array of rules

=cut

sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->SUPER::initialiseFromHash($args);
    $self->{name}  ||= "RuleSet";
    $self->{rules} ||= {};

    if (ref $self->{rules} eq "ARRAY") {
	# convert array of rules into ruleid=>rule pairs
	$self->{rules} = { map { $_->toString() => $_ } @{$self->{rules}} };
    }
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getName()

Return the name of the ruleset.

=cut

sub getName ($) { return $_[0]->{name}; }

=head2 setName()

Set the name of the ruleset. The name may also be specified at initialisation;
see the synopsis above.

=cut

sub setName ($$) { $_[0]->{name}=$_[1]; }

=head2 getRule($ruleid)

Return the rule object with the specified name from the ruleset, or undef if
the rule is not present. If supplied a rule object as an argument, checks
whether or not the ruleset contains a rule with the same name.

=cut

sub getRule ($$) {
    my ($self,$ruleid)=@_;

    if (exists $self->{rules}{$ruleid}) {
	return $self->{rules}{$ruleid};
    }

    return undef;
}

=head2 getRules()

Return a list of all rules currently registered in the ruleset.

=cut

sub getRules ($) {
    my ($self)=@_;

    return @{[sort values %{$self->{rules}}]};
}

=head2 addRule($rule)

Add the specified rule object to the ruleset, replacing any existing rule with
the same name, if present.

=cut

sub addRule ($$) {
    my ($self,$rule)=@_;
    $self->throw("Not a rule"),return undef
      unless $rule->isa("BDE::Rule::Base");

    $self->{rules}{$rule}=$rule; # stringifies rule to get hash key
    return 1;
}

=head2 addRules(@rules)

Add one or more rules to the ruleset, replacing any existing rules with the
same name, if present.

=cut

sub addRules ($@) {
    my ($self,@rules)=@_;

    foreach my $rule (@rules) {
	return undef unless $self->addRule($rule);
    }

    return 1;
}

=head2 removeRule($ruleid)

Remove the rule with the specified ID from the ruleset. Returns the rule id
if present, or C<undef> otherwise.

=cut

sub removeRule ($$) {
    my ($self,$ruleid)=@_;

    return delete $self->{rules}{$ruleid};
}

=head2 removeRules(@ruleids)

Remove the rules with the specified IDs from the ruleset. Rule IDs that
are not present are ignored.

=cut

sub removeRules ($@) {
    my ($self,@ruleids)=@_;

    $self->removeRule($_) foreach @ruleids;
}

=head2 removeAllRules()

Remove all rules from the ruleset, leaving it empty.

=cut

sub removeAllRules ($) {
    $_[0]->{rules}={};
}

=head2 getResult($ruleid)

Return the result status of the specified rule object or rule id, or undef if
the rule does not exist in the ruleset. Note that the status of a rule may
also be undef it has not been invoked since initialisation or the last reset.

=cut

sub getResult ($$) {
    my ($self,$ruleid)=@_;

    if (exists $self->{rules}{$ruleid}) {
	return $self->{rules}{$ruleid}->getResult();
    }

    return undef;
}

=head2 getResults()

In list context, return the results of invoking a ruleset via L<"verify"> as a
list of rule-result pairs, or in scalar context a reference to a hash of
rule-result pairs.

=cut

sub getResults ($) {
    my $results={ map {
	$_ => $_[0]->getResult($_)
    } keys %{$_[0]->{rules}} };

    return wantarray ? %$results : $results;
}

=head2 getFailures()

Return a list of rules which failed on their last invocation.

=cut

sub getFailures ($) {
    my $results=$_[0]->getResults;

    my @results=();
    foreach my $rule (keys %$results) {
	push @results,$rule if $results->{$rule};
    }

    return @results;
}

#------------------------------------------------------------------------------

=head2 resetResults()

Reset all rule results to their intial undefined value. This method may be used
to reset the state of a rulset after it has already been run once.

=cut

sub resetResults ($) {
    $_[0]->{results}={};
    $_->resetResult() foreach $_[0]->getRules();
}

#------------------------------------------------------------------------------

=head2 setNoMeta([$nometa])

Set the ruleset into 'no metadata' mode if the optional argument is true or no
arguments are passed. Set the ruleset into normal full-function mode if the
passed argument is defined but false. Note that use of this mode is deprecated
unless circumstances force it.

=cut

sub setNoMeta ($;$) {
    my ($self,$nometa)=@_;

    $nometa=1 unless defined $nometa;

    $self->{noMetaRules}=1 if $nometa;
}

=head2 getNoMeta()

Query the current setting of 'no metadata' mode. See L<"setNoMeta"> above.

=cut

sub getNoMeta ($) {
    my $self = shift;
    return 1 if $self->{noMetaRules};
    return;
}

#------------------------------------------------------------------------------

=head2 verify($component)

Run all rules in the ruleset on the supplied component, which must be an
object blessed into a BDE::Component class or subclass. Returns the number
of rules that failed on, 0 on success, or undef if the ruleset could not be
invoked because it has no rules.

=cut

sub verify ($$;$) {
    my ($self,$component,$root)=@_;
    $self->throw("No rules"),return undef unless $self->getRules();
    $self->resetResults();
    $_->verify($component,$root,$self->getNoMeta()) foreach $self->getRules();
    return scalar $self->getFailures();
}

#------------------------------------------------------------------------------

sub toString ($) { return $_[0]->{name} };

#------------------------------------------------------------------------------

sub test {
    my $set=new BDE::RuleSet("Test ruleset");
    print "Ruleset name (explicit): ",$set->toString(),"\n";
    print "Ruleset name (implicit): $set","\n";

    require BDE::Rule::L1;
    my $L1=new BDE::Rule::L1;
    my $L1a=new BDE::Rule::L1("L1a");
    print "    Rules (empty): ",join(' ',$set->getRules()),"\n";
    $set->addRules($L1,$L1a);
    print "    Rules (L1,L1a): ",join(' ',$set->getRules()),"\n";

    require BDE::FileSystem;
    require BDE::Component;
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    print ">> Filesystem located at: $root\n";
    foreach (qw[bdem_list bdet_time bteso_spinningeventmanager]) {
	print ">> $_ base path: ",$root->getComponentBasepath($_),"\n";
	my $comp=new BDE::Component($root->getComponentBasepath($_));
	
	my $result=$set->verify($comp);
	print "$set result ($_): [",join('',values(%$result)),"]\n";
	foreach (sort keys %$result) {
	    print "    $_ => $result->{$_}\n";
	}
    }

    print "Done\n";
}

#------------------------------------------------------------------------------

=head1 AUTHOR

Peter Wainwright (pwainright@bloomberg.net)

=head1 SEE ALSO

L<BDE::RuleSet::Conf>, L<BDE::Rule::Base>, L<bde_verify.pl>

=cut

1;
