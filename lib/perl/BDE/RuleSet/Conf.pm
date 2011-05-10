package BDE::RuleSet::Conf;
use strict;

use BDE::RuleSet;
use vars qw(@ISA);
@ISA=qw(BDE::RuleSet);

use BDE::Util::Nomenclature qw(getTypeName);
use Util::Message qw(fatal warnonce debug);
use vars qw(%RuleSet);
use FindBin;

#------------------------------------------------------------------------------

=head1 NAME

BDE::RuleSet::Conf - Configuration loader and manager for BDE::RuleSet

=head1 SYNOPSIS

    use BDE::RuleSet::Config "/path/to/rules.conf";
    BDE::RuleSet::Config->loadRulesConfiguration("/path/to/morerules.conf");

    my @rulesets = BDE::RuleSet::Config->listRuleSetsInConfig();
    my @rules     = BDE::RuleSet::Config->listRulesInConfig();

    BDE::Ruleset::Config->parseRuleSetConfig(
        "ALLRULES=".(join ',',@rules)
    );

    my $ruleset = BDE::RuleSet::Config->expandRuleSetConfig("ALLRULES");

=head1 DESCRIPTION

Additional class methods that provide handling for default rulesets taken from
a configuration file. This module subclasses BDE::RuleSet so it can be used
in place of that module where configuration file handling is desired.

Configuration information is initially stored purely as text data in the
class, and is shared by all instances of C<BDE::RuleSet::Conf> objects.
The loaded configuration is only converted into instantiated rule and ruleset
objects when a ruleset is actually requested.

=cut

#------------------------------------------------------------------------------

# Any import list items are presumed to be config files
sub import {
    my $package=shift;
    $package->loadRulesConfiguration($_) foreach @_;
}

#------------------------------------------------------------------------------
# Rules configuration data

=head1 METHODS

=head2 loadRulesConfiguration($configfile [,$isoptional])

Class method. Load a ruleset configuration from the file given as the first
argument. The configuration is merged with any existing configuration,
overwriting any rulesets already present with the same name as a ruleset
defined in the configuration file.

On success, returns true. If the configuration file cannot be opened and the
second argument is not passed or is not true, an exception is thrown.
Otherwise, a failure to open the file returns false.

=cut

sub loadRulesConfiguration ($$;$) {
    my ($class,$conf,$optional)=@_;

    unless (open CONF,"$conf") {
	return 0 if $optional;
	fatal "Unable to open '$conf': $!";
    }

    while (<CONF>) {
	next if /^\s*$/ or /^\s*\#/;
	chomp;
	$class->parseRuleSetConfig($_);
    }

    close CONF;
    return 1;
}

=head2 resetRulesConfiguration()

Class method. Reset (remove) all defined rulesets.

=cut

sub resetRulesConfiguration () {
    %RuleSet=();
}

=head2 listRuleSetsInConfig()

Class method. Return a list of all the rulesets contained in the class-level
configuration.

=cut

sub listRuleSetsInConfig($) {
    return sort keys %RuleSet;
}

=head2 listRulesInConfig()

Class method. Return a list of all the rules contained in the currently
defined rulesets. Each rule is returned once, irrespective of how many
rulesets it appears in.

=cut

sub listRulesInConfig ($) {
    # uniquify all keys (rule ids) via temporary hash
    return sort keys %{ { map { $_ => 1 } map { @{$_} } values %RuleSet } };
}

=head2 listRulesConfiguration()

Class method. Print to standard output a formatted list of currently defined
rulesets. See also L<"listRulesInConfig">.

=cut

sub listRulesConfiguration ($) {
    my $length=0;
    foreach (keys %RuleSet) {
	$length=length($_) if length($_)>$length;
    }

    return (join "\n", map {
	sprintf("%${length}s",$_)." => ".join(",",sort @{$RuleSet{$_}})
    } sort keys %RuleSet)."\n";
}


#------------------------------------------------------------------------------
# Rules configuration data

=head2 parseRuleSetConfig($configline)

Class method. Parse the supplied configuration line to extract a ruleset
definition, and then add that definition to the class-level configuration.
A configuration line resembles the following format:

    THISSET = SET1-SET2+RULE1-RULE2

See L<bde_verify.pl> for more examples of ruleset configurations.

=cut

sub parseRuleSetConfig ($$) {
    my ($class,$line)=@_;

    my ($setname,$rules)=split '\s*=>\s*',$line;
    $rules=~s/(\w)([+-])/$1,$2/g; #L1+L2 => L1,+L2
    my @rules=split '[^\w+-]+',$rules;

    s/\s//g foreach @rules;
    $setname=~s/\s//g;

    # a config line that starts without a sign resets any existing rules for
    # that ruleset name. Otherwise, it accretes to the pre-existing definition
    if ($rules[0]=~/^[+-]/) {
	$class->appendRuleSetConfig($setname => @rules);
    } else {
	$class->setRuleSetConfig($setname => @rules);
    }
}

=head2 setRuleSetConfig($setname [,@elements])

Class method. Set the class-level configuration for the specified set name to
be the list of supplied elements. If no list of elements is supplied, the
ruleset configuration becomes defined, but empty.

=cut

sub setRuleSetConfig ($$) {
    my ($class,$setname,@config)=@_;

    $RuleSet{$setname}=\@config;
}

=head2 appendRuleSetConfig($setname,@elements)

Class method. Append the specified list of ruleset configuration elements to
the ruleset with the specified name in the class-level configuration. If the
ruleset configuration does not exist, it is created as C<"setRuleSetConfig">.

=cut

sub appendRuleSetConfig ($$) {
    my ($class,$setname,@config)=@_;
    if (exists $RuleSet{$setname}) {
	push @{$RuleSet{$setname}},@config;
    } else {
	$RuleSet{$setname}=\@config;
    }
}

=head2 removeRuleSetConfig($setname)

Class method. Remove the ruleset with the specified set name from the
class-level configuration. Returns true if the ruleset was removed, and false
if no ruleset of the specified name was present in the class-level
configuration.

=cut

sub removeRuleSetConfig ($$) {
    my ($class,$setname)=@_;
    return (delete $RuleSet{$setname})?1:0;
}

=head2 getRuleSetConfig($setname)

Class method. Return the unexpanded configuraion for the specified set name
from the class-level configuration. Returns the list of ruleset elements in
list context, or a reference to an array of the same elements in scalar
context. If the ruleset does not exist in the configuration a warning is
issued, and an empty list or C<undef> is returned, depending on context.

=cut

sub getRuleSetConfig ($$) {
    my ($class,$setname)=@_;
    $setname=getTypeName($setname) if $setname=~/^\d/; #mapping
    unless (exists $RuleSet{$setname}) {
	warnonce "Ruleset $setname is not defined in configuration";
	return; #empty list or undef depending on context.
    }

    return wantarray ? @{$RuleSet{$setname}} : $RuleSet{$setname};
}

=head2 expandRuleSetConfig($setname)

Class method. Retrive the configuration for the specified set name from the
class-level configuration, and expand it to derive the list of rules that it
evaluates to. Returns the expanded list of rule ids in list context, or a
reference to an array of the same rule ids in scalar context. In either case,
the list of rules is unique, even if a rule is specified twice explicitly in
the configuration.

=cut

sub expandRuleSetConfig ($$) {
    my ($class,$setname)=@_;

    my @rulesin=$class->getRuleSetConfig($setname);

    my @rulesout=(); # expanded list of rules, may be dupped
    my %rules=();   # hash of ultimately enabled rules

    foreach my $rule (@rulesin) {
	$rule=~s/^([+-])(.*)$/$2/;
	my $sign=$1 || '+';

	if ($rule=~/^[A-Z]\d(?:[a-z].*|_.*|$)/) {
	    if ($sign eq '-') {
		delete $rules{$rule};
	    } else {
		$rules{$rule}=1;
		push @rulesout,$rule;
	    }
	} else {
	    my @rules=$class->expandRuleSetConfig($rule);
	    foreach my $rule (@rules) {
		if ($sign eq '-') {
		    delete $rules{$rule};
		} else {
		    $rules{$rule}=1;
		    push @rulesout,$rule;
		}
	    }
	}
    }

    # generate unique list from expanded specified order
    my @rulesback=();
    foreach my $rule (@rulesout) {
	if (exists $rules{$rule}) {
	    push @rulesback,$rule;
	    delete $rules{$rule}; #make sure a rule appears only once
	}
    }

    return wantarray ? @rulesback : \@rulesback;
}

#------------------------------------------------------------------------------

=head2 getRuleSet($setname [,@ruleids])

Class method. Instantiate a new L<BDE::RuleSet> instance and populate it with
rule objects according to the provided list of rule ids, which are text
strings containing the name of the rules module to load.

If no list of rule ids is provided (which is the normal case), use the list
of rules previously defined for the specivied rule set, as established by
L<"loadRulesConfiguration">, L<"parseRuleSetConfig">, L<"setRuleSetConfig">,
or L<"setRuleSetConfig">.

If a list of rule ids is not provided and a set of the specified name does not
exist in the class-level configuration, C<undef> is returned. If any of the
specified rule ids does not map to a loadable rules module, an exception is
thrown. Otherwise, a populated C<BDE::RuleSet> object is returned.

=cut

sub getRuleSet ($$;@) {
    my ($class,$setname,@ruleids)=@_;
    $setname=getTypeName(int $setname) if $setname=~/^\d/;
    unless (@ruleids) {
	@ruleids = $class->expandRuleSetConfig($setname);
    }
    return undef unless @ruleids;

    my @rules=();
    foreach my $rule (@ruleids) {
	unless (eval "require BDE::Rule::$rule"
	       or eval "require Rule::$rule"
	       or eval "require $rule") {
           fatal("cannot load rule $rule");
	   return undef;
        }
	$rule="BDE::Rule::$rule"->new();
	push @rules,$rule;
    }

    return $class->new({ name=>$setname, rules=>\@rules });
}

#------------------------------------------------------------------------------

=head2 getCachedRuleSet($setname [,@ruleids])

Class method. As L<"getRuleSet">, but cache the returned L<BDE::RuleSet>
instance in an internal class-level hash keyed on the ruleset name. If the
same ruleset is requested a second time through this method, return the
previously cached ruleset.

=cut

{ my %sets;

  sub getCachedRuleSet ($$;@) {
      my ($class,$type,@ruleids)=@_;

      unless (exists $sets{$type}) {
	  my $ruleset=$class->getRuleSet($type => @ruleids);
	  return undef unless $ruleset;
	  $sets{$type}=$ruleset;
      }

      return $sets{$type};
  }
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::RuleSet>, L<BDE::Rule::Base>, L<bde_verify.pl>

=cut

1;
