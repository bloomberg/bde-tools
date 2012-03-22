#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Cwd;

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT DEFAULT_JOBS
    FILESYSTEM_LOCAL_ONLY FILESYSTEM_VERY_FLAT HOME
);
use Util::Message qw(
    fatal error alert message debug verbose verbose_alert get_verbose
    warning warnonce
);
use Util::File::Basename qw(basename);
use BDE::Component;
#use BDE::Component qw(includeTestByDefault);
use BDE::Util::DependencyCache qw(
    getCachedGroup     getGroupDependencies     getAllGroupDependencies
    getCachedPackage   getPackageDependencies   getAllPackageDependencies
    getCachedComponent getComponentDependencies getAllComponentDependencies
);
use BDE::FileSystem;
use BDE::RuleSet::Conf "$FindBin::Bin/../etc/rules.conf";
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent getType getTypeName
    getPackageGroup isGroupedPackage
    getComponentPackage getComponentGroup isDepartment isFunction
    isAdapter isApplication isApplicationMain isTest isNonCompliant
);
use BDE::Util::RuntimeFlags qw(
    setDeprecationLevel setNoMetaMode getNoMetaMode
);

#==============================================================================

=head1 SYNOPSIS

    # basic use
    $ bde_verify.pl a_bdema_gmalloc_adaptor   # verify component
    $ bde_verify.pl f_ykmnem                  # verify package
    $ bde_verify.pl bde bce bte bse bae       # verify several groups

    # custom rules and rulesets
    $ bde_verify.pl -R Base+Adapter a_bdema   # apply rulesets Base and Adapter
    $ bde_verify.pl -R Department-L2+Q3       # apply customised ruleset
    $ bde_verify.pl -R BigSet-SmallSet        # subtract rulesets

    # custom ruleset configuration
    $ bde_verify.pl -c myrules.conf l_abc     # add custom rulesets

    # display configuration / expansions
    $ bde_verify.pl -c myrules.conf -l        # list out defined rulesets
    $ bde_verify.pl -R BigSet-SmallSet+Q3 -l  # list out rulesets plus the
                                              # expansion of -R specification

=head1 DESCRIPTION

C<bde_verify.pl> carries out source code quality checks on the supplied
source unit (component, package, or package group) using I<rules> that may be
either specified or left to default to an appropriate set based on the type
of the code under review.

=head2 Default Rulesets

Rules are grouped into I<Rulesets> which are defined in the configuration
file C<etc/rules.conf>. The default rulesets invoked when no explicit rules
are requested are:

    Base        - base (core) library
    Enterprise  - enterprise library
    Department  - department library
    Function    - function (biglet)
    Application - application
    Adapter     - adapter
    Wrapper     - wrapper library

Use the C<--list> or C<-l> option to list out the rules configured for each
software category.

=head2 Custom Ruleset Configuration

The default sets may be added to and subtracted from, or new rulesets defined
in a custom rules configuration. By default, a file called C<.rulescf> or
C<rules.conf> in the invoking user's home directory is searched for, but an
explicit ruleset configuration file can also be specified with the C<--config>
or C<-C> option.

A ruleset configuration file contains one line per ruleset definition, with
empty lines and #-prefixed comments also allowed. A ruleset definition is
of the form:

    <ruleset> => <rule|ruleset>,<rule|ruleset>,...

Between rules, a C<+> is equivalent to a comma, and a C<-> may be used to
subtract from the specification so far rather than adding to it. For example:

   PreviousSet => M1+M2,M3+M4
   MyRuleset   => Q3,PreviousSet-M4,M6

This results in C<MyRuleset> containing Q3,M1,M2,M3,M6. Rules will only be
invoked once even if the expansion would cause them to be listed more than
once. Subtracting a rule that is not in the set at the moment of subtraction
has no effect but is otherwise legal.

If the first rule in a ruleset is prefixed with C<+> or C<->, the definition
will modify any previous definition of the same ruleset both within the same
configuration file and in C<etc/rules.conf>. Otherwise it will replace the
previous definition.

=head2 Custom Rules Specification

With the C<--rule> or C<-R> option, an aribitrary list of rules and rulesets
may be specified, using C<,> or C<+> to add rules and C<-> to remove them in
the same manner as a ruleset definition but without the ruleset name:

    $bde_verify.pl -R G1+G2,PreviousSet-M3-M4-OtherSet,Q3 ...

See above and the synopsis for more usage examples.

=head2 Writing and Using Custom Rules

Custom rules may be created by subclassing from the L<BDE::Rule::Base> module
and adding at least a C<verify> method to the subclass. For example:

    package BDE::Rule::Q3;
    use strict;

    use base 'BDE::Rule::Base';
    use BDE::Component;

    sub verify ($$) {
        my ($self,$component)=@_;

        $result = $self->SUPER::verify($component); #generic rule checks
        return $result unless defined($result) and not $result;

        my $ctx = $self->getContext();
        $ctx->addError(text => "my error");

        my $zero_or_one=1; #1 = failure, 0 = success
        return $self->setResult($zero_or_one);
    }

    __DATA__
    The documentation for the rule goes here in POD format.

(See C<Context> and C<Context::Message> for more information on context
operations).

To allow C<bde_verify.pl> to find a custom rule, use the C<--include> or C<-I>
option to expand the default module search path (PERL5LIB may also be used for
this purpose). Paths added with this option are search ahead of the standard
locations so existing rules may also be overridden with localised versions
this way.

Rule modules are searched for in a C<BDE/Rule> subdirectory first, then a
<Rule> subdirectory if not found, and finally directly under each directory in
the path, so C<-I ./myrules> will search for:

    ./myrules/BDE/Rules/Q3.pm
    ./myrules/Rules/Q3.pm
    ./myrules/Q3.pm

The succeeding stages will only be tried if the module is not found under any
of the specified or default include paths, so a standard rules module will
always be found before a similarly named local module unless it is in a
C<BDE/Rules> subdirectory below a directory specified with C<--include>/C<-I>.

=head1 EXIT STATUS

On exit, C<bde_verify.pl> will return the total number of rule violations for
all the components that were tested, or zero if all components passed all
tests.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $DEFAULT_JOBS=DEFAULT_JOBS; #for interpolation
    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-w <dir>] [-X] <component|package|group>
  --debug       | -d           enable debug reporting
  --help        | -h           usage information (this text)
  --include     | -I           add search locations for custom rule modules
  --list        | -l           list configured rules instead of running them,
                               also show expanded list if specified with -R.
  --rule        | -R <rules>   one or more comma-separated rule and/or ruleset
                               names. Disables automatic ruleset determination.
                                 Rules are of the form 'L1','P3'
                                 Rulesets are named in rules.conf
                               The special ruleset 'Default' re-enables the
                               ruleset calculated based on the provided name
  --where       | -w <dir>     specify explicit alternate root
  --noretry     | -X           disable retry semantics on file operations
  --verbose     | -v           enable verbose reporting

See 'perldoc $prog' for more information.

_USAGE_END
}

# NOT DISPLAYED IN USAGE:
# --deprecation | -z[z]        run in deprecatione mode 1 or 2.
# --nometarules | -Z           PRLS mode, disables rule checks that requires
#                              meta-information to be present.

# TODO:

# --jobs        | -j [<jobs>]  build in parallel up to the specified number of
#                              jobs (default: $DEFAULT_JOBS jobs)
#                              default if platform is not 'dg' or 'windows'
# --serial      | -s           serial build (equivalent to -j 1)
#                              default if platform is 'dg' or 'windows'

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        config|c=s
        debug|d+
        help|h
        include|I=s@
        jobs|parallel|j|pa:i
        list|l+
        rule|R=s
        where|root|w|r=s
        serial|s
        noretry|X
        deprecation|z+
        nometarules|Z
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{list};

    # filesystem root
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # custom include paths
    if ($opts{include}) {
	foreach (@{$opts{include}}) {
	    if (-d $_) {
		unshift @INC,$_;
	    } else {
		warnonce "include path '$_' does not exist";
	    }
	}
    }

    if ($opts{nometarules}) {
        setNoMetaMode();
        alert("Running in no meta-rules mode...");
    }
    if ($opts{deprecation}) {
        setDeprecationLevel($opts{deprecation});
        alert("Running at deprecation level $opts{deprecation}...");
    }

    return \%opts;
}

#------------------------------------------------------------------------------

# if we are passed a unit bigger than a component, turn it into a list of the
# components contained within.
sub getComponentsOf ($$) {
    my $item=shift;
    my $nometa=shift;

    my @components=();

    if (isGroup($item)) {
	alert("Checking group $item...");
        getAllGroupDependencies($item) if !$nometa;
	foreach my $pkg (getCachedGroup($item)->getMembers()) {
            getAllPackageDependencies($pkg) if !$nometa;
	    push @components,getCachedPackage($pkg)->getMembers();
	}
        @components = grep { $_ !~ /\./ } @components;
	message("Components: @components") if @components;
    } elsif (isPackage($item)) {
	alert("Checking package $item...");
        if (!$nometa) {
            getAllGroupDependencies(getPackageGroup($item)) if isGroupedPackage($item);
            getAllPackageDependencies($item);
        }
	push @components,getCachedPackage($item)->getMembers();
        @components = grep { $_ !~ /\./ } @components;
	message("Components: @components") if @components;
    } elsif (isComponent($item)) {
	verbose_alert("Checking component $item...");
        if (!$nometa) {
            getAllGroupDependencies(getComponentGroup($item)) if isGroupedPackage(getComponentPackage($item));
            getAllPackageDependencies(getComponentPackage($item));
        }
	push @components,$item;
    }


    return wantarray ? @components : \@components;
}

#------------------------------------------------------------------------------

# process passed arguments to convert component filename into components. Use
# a hash to eliminate duplicates when both .h and .cpp for the same component
# are present. If a passed argument has an extension but is not a component,
# complain. If a passed argument does not have an extension and is not a
# package or group, also complain -- unless we're flat, in which case assume
# we were called on a grab-bag of good and bad and ignore the bad.
sub parseArgs ($@) {
    my ($nometa,@items)=@_;
    my %args;

    foreach my $item (@items) {
        verbose("Application main '$item' ignored"), next if
          isApplicationMain($item);
        verbose("Test source '$item' ignored"), next if
          isTest($item);
	if ($item=~s/\.\w\w?\w?$//) {
	    if (isComponent $item) {
		$args{$item}=1; #component stripped of extension
	    } else {
		if ($nometa) {
		    verbose "Ignored '$item' - not a component";
		} else {
		    fatal "$item is not a component";
		}
	    }
	} elsif (isComponent $item) {
	    $args{$item}=1; #component stripped of extension
	} else {
	    if (isGroup($item) or isPackage($item)) {
		$args{$item}=1;
	    } else {
		if ($nometa) {
		    verbose "Ignored '$item' - not a group or package";
		} else {
		    fatal "$item is not a group or package";
		}
	    }
	}
    }

    return sort keys %args;
}

#------------------------------------------------------------------------------

sub excludeComponent($) {
    my $component = shift;
    alert("Bypassing deprecated component $component"), return 1 if
      ${$component->getIntfFile->getFullSource} =~ m-//\@DEPRECATED:-;
    #alert("Bypassing component $component due to extract_bracketed limitations"), return 1 if
    #  $component eq "bdeimp_dateutil" or $component eq "bdec_stridxnset";
    return 0;
}

#------------------------------------------------------------------------------

#print "\n\n\n*** dev branch bde_verify temporarily unavailable ***\n";
#print "*** please use bb branch, /bbsrc/bde or /bb/shared/bin version ***\n\n\n";
#exit 0;

MAIN: {
    my $opts=getoptions();

    unless ($opts->{nometarules}) {
#        BDE::Component->includeTestByDefault();
    }

    if ($opts->{config}) {
	BDE::RuleSet::Conf->loadRulesConfiguration($opts->{config});
    } elsif (-f HOME."/.rulesrc") {
	# unix-style default
	BDE::RuleSet::Conf->loadRulesConfiguration(HOME."/.rulesrc",1);
    } elsif (-f HOME."/rules.conf") {
	# windows-style default
	BDE::RuleSet::Conf->loadRulesConfiguration(HOME."/rules.conf",1);
    }

    if ($opts->{list} and not $opts->{rule}) {
	print BDE::RuleSet::Conf->listRulesConfiguration();
	exit EXIT_SUCCESS;
    }

    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    if (getNoMetaMode()) {
	# this allows getCachedComponent to work without a package subdir
	BDE::Util::DependencyCache::setNoMetaChecks($opts->{nometarules});
	$root->setSearchMode(FILESYSTEM_LOCAL_ONLY|FILESYSTEM_VERY_FLAT);
    }

    my $ruleset=undef;
    if ($opts->{rule}) {
	BDE::RuleSet::Conf->parseRuleSetConfig("Custom => $opts->{rule}");
	my @rules=BDE::RuleSet::Conf->expandRuleSetConfig("Custom");
	fatal "No rules expanded from $opts->{rule}\n" unless @rules;

	if ($opts->{list}) {
	    print "Specified rules expand to: @rules\n";
	}
	$ruleset=BDE::RuleSet::Conf->getCachedRuleSet("Custom");
	if ($opts->{list}) {
	    exit EXIT_SUCCESS;
	}
    }

    my @items=parseArgs($opts->{nometarules},@ARGV);

    my $total_result=0;
    foreach my $item (@items) {
	my $result=0;
	my $type=getType($item);
	my $typename=getTypeName($type);

	my @components=getComponentsOf($item,$opts->{nometarules});
        unless (@components) {
            if (isNonCompliant($item) or isApplication($item)) {
                warning("No components for '$item'");
            } else {
	        fatal("No components for '$item'");
            }
        }

	my $set=$ruleset || BDE::RuleSet::Conf->getCachedRuleSet($typename);
	fatal("No default ruleset found for $typename ($type)") unless $set;

	debug("Invoking $typename rules: ".(join ',',$set->getRules()));

	foreach my $component (@components) {
	    $component = getCachedComponent($component);
            if (!excludeComponent($component)) {
                $result += $set->verify($component, $root);
                print STDERR map { $_, "\n" }
                  map { $_->removeAllMessages() }
                    map { $_->getContext() }
                      ($set->getRules());
            }
            $component->removeAll;
	}
	
	if ($result) {
	    # Rules emit their own error msgs normally so we don't need to
	    # emit another one here unless we're being verbose
	    error "$item failed" if get_verbose();
	} else {
            if (! @components) {
                alert "$item (trivial) verified OK";
            } elsif (get_verbose()) {
		alert "$item ".(join ',',$set->getRules)." verified OK";
	    } else {
		alert "$item verified OK";
	    }
	}

	$total_result+=$result;
    }

    exit $total_result;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::RuleSet>, L<BDE::Rule::Base>, L<bde_build.pl>

=cut
