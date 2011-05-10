package Build::Option::Factory;
use strict;

use base 'BDE::Object';

use Build::Option::Set;
use Build::Option::Parser;
use Build::Option::Scanner;
use Composite::Commands qw(ADD INSERT);

use BDE::Util::Nomenclature qw(isComponent isPackage isGroup isGroupedPackage
                               getPackageGroup);
use BDE::Util::DependencyCache qw(
    getDependencyBuildOrder getLinkName
);

use Util::File::Basename qw(basename);
use Util::Message qw(verbose verbose2 warning warnonce error);

#==============================================================================

=head1 NAME

BDE::Option::Factory - Construct a BDE::Option::Set from option files

=head1 SYNOPSIS

    my $factory=new Build::Option::Factory;
    $factory->setFinder(new Build::Option::Finder);
    $factory->setDefaultUplid(new BDE::Build::Uplid);
    $factory->setDefaultUfid(new BDE::Build::Ufid("dbg_exc_mt"));

    my $collapsedset=$factory->construct("bde");
    print $collapsedset->render();

    my $collapsedset2=$factory->construct({
        what => "bce"
        ufid => BDE::Build::Ufid->new("dbg_mt");
    });
    print $collapsedset2->render();

    $factory->load("a_bdema");
    my $uncollapsedset=$factory->getValueSet();

=head1 DESCRIPTION

This module maintains an uncollapsed value set, also called the I<raw value
set>, that collects all options for the specified package groups or packages
and provides methods to query and collapse build options.

In order to function, the factory requires a build option finder instance
to be installed. This can be done at the time of construction, or later,
as illustrated in the synopsis above.

=cut

#==============================================================================

#<<<TODO: move to a utility module
sub unique {
    my @in=@_;
    my @out;
    my %seen;

    foreach (@in) {
	next if $seen{$_};
	push @out, $_;
	$seen{$_}=1;
    }

    return @out;
}
#<<<TODO: initialiseFromHash - verify object args are really objects

=head1 CONSTRUCTORS

=cut

sub initialise ($$) {
    my ($self,$init)=@_;

    $self->SUPER::initialise($init);

    unless ($self->getValueSet) {
	my $valueset=new Build::Option::Set();
	$self->setValueSet($valueset);		
    }

    return $self;
}

=head2 new()

=head2 new($optionfinder)

=head2 new($valueset)

Construct a new build option factory instance. If an option finder is provided
then it is installed. Otherwise, it must be provided subsequently with the
L<"setFinder"> method.

A value set may also be provided as an initialiser, in which case it is used
as the in-memory cache of raw options. An empty value set is constructed
internally otherwise. This usage requires L<"setFinder"> as above.

=cut

sub initialiseFromScalar ($$) {
    my ($self,$init)=@_;

    if (ref $init) {
	if ($init->isa("Composite::ValueSet")) {
	    $self->setValueSet($init);
	} elsif ($init->isa("Build::Option::Finder")) {
	    $self->setFinder($init);
	    unless ($self->getValueSet) {
		$self->setValueSet(new Build::Option::Set);		
	    }
	} else {
	    $self->throw("invalid initialiser: $init");
	}
    } else {
	# init = composite value classname
	my $valueset=new Build::Option::Set($init);
	$self->setValueSet($valueset);	
    }

    return $self;
}

#------------------------------------------------------------------------------

=head1 ACCESSOR/MUTATORS

=head2 getFinder()

Get the installed build option finder instance.

=head2 setFinder($finder)

Set the build option finder instance for this factory object.

=cut

sub getFinder         ($) { return $_[0]->{root}; }
sub setFinder        ($$) { $_[0]->throw("Not a Build::Option::Finder")
			      unless $_[1]->isa("Build::Option::Finder");
			    $_[0]->{root}=$_[1]; }

=head2 getDefaultUplid

Get the default UPLID for collapsing. By default, this is not set.

=head2 setDefaultUplid

Set the default UPLID for collapsing. Must be a L<"BDE::Build::Uplid">
instance, or C<undef> to clear the default.

=cut

sub getDefaultUplid   ($) { return $_[0]->{uplid}; }
sub setDefaultUplid  ($$) {
    $_[0]->throw("Not a BDE::Build::Uplid")
      unless (not defined $_[1]) or $_[1]->isa("BDE::Build::Uplid");
    $_[0]->{uplid}=$_[1];
}

=head2 getDefaultUfid

Get the default UFID for collapsing. By default, this is not set.

=head2 setDefaultUfid

Set the default UFID for collapsing. Must be a L<"BDE::Build::Ufid">
instance, or C<undef> to clear the default.

=cut

sub getDefaultUfid    ($) { return $_[0]->{ufid}; }
sub setDefaultUfid   ($$) {
    $_[0]->throw("Not a BDE::Build::Ufid")
      unless (not defined $_[1]) or $_[1]->isa("BDE::Build::Ufid");
    $_[0]->{ufid}=$_[1];
}

#------------------------------------------------------------------------------

sub ucmacro { return uc($_[0]); } #<<<TODO: get from bde_build.pl, reuse

=head1 METHODS

=head2 getElegibleOptionFiles($what)

Get the list of applicable options files (.opts, .defs, and .cap) for the
stated unit of release. This does not necessarily mean that each of these
files actually exists -- L<"load">, which calls this method, deals with that.

This method is a thin wrapper for L<Build::Option::Finder/getOptionFiles>. It
augments that method by recognizing the special arguments C<default> and C<*>
and returning the default option file only in these cases (derived from
L<Build::Option::Finder/getDefaultOptionFile>.

=cut

sub getElegibleOptionFiles ($$) {
    my ($self,$unit)=@_;

    my $root=$self->getFinder();
    $self->throw("No root available") unless defined $root;

    my @optsfiles=($unit eq "default" or $unit eq "*")
      ? $root->getDefaultOptionFile()
	: $root->getOptionFiles($unit);

    return @optsfiles;
}

=head2 load($what)

Find (using multrooting, see B<BDE::FileSystem>) all dependencies of the
specified unit-of-release, and load all applicable options files present
(including .defs and .cap files as well as .opts files). The list of
elegible files is determined using L<"getElegibleOptionFiles"> above, and
each one found loaded.

An exception is thrown if any option file encounters a parsing error. A
file that is missing is normal and is not considered an error.

=cut

{
    my $scanner=new Build::Option::Scanner();
    my $parser=new Build::Option::Parser();

    my $VS;        # single value set as class data for 'raw' option storage
    my %VS_INC; # like %INC, tracks what has been loaded for all instances

    sub load {
	my ($self,$unit)=@_;

	unless (($unit eq "default" or $unit eq "*")
		or isComponent($unit) or isPackage($unit) or isGroup($unit)) {
	    $self->throw("$unit is not a component, package, or group");
	}

	my $valueset=$self->getValueSet();

	my @optsfiles=$self->getElegibleOptionFiles($unit);

	my $verbose = Util::Message::get_verbose();
	foreach my $optsfile (@optsfiles) {
	    my $base=basename($optsfile);

	    if (exists $VS_INC{$base}) {
		verbose2("$base already loaded") if ($verbose >= 2);
		next;
	    }

	    $VS_INC{$base}=$optsfile;
	    verbose("loading $base from $optsfile") if ($verbose);

	    foreach my $scan ($scanner->scan($optsfile)) {
		my $item=$parser->parse($scan);
		if (ref $item) {
		    $item->setWhat($base);
		    $valueset->addValueItem($item);
		} else {
		    $self->throw("parse of '$scan' failed in $optsfile");
		}
	    }
	}

	return $self;
    }

=head2 getValueSet

Get the value set of loaded options, also called the I<raw value set>. This
value set is the in-memory cache of all loaded options and is the source of
data for the L<"collapse"> method, amongst others.

=cut

    sub getValueSet       ($) { return $VS; }

=head2 setValueSet

Replace the value set of loaded options with a new value set.

=cut

    sub setValueSet       ($) { $_[0]->throw("Not a Composite::ValueSet")
				  unless $_[1]->isa("Composite::ValueSet");
				$VS=$_[1]; }
}

#------------------------------------------------------------------------------

sub addPreCollapseDerivedValues {
    my ($self,$valueset,$unit,$uplid,$ufid)=@_;

    my @deps=getDependencyBuildOrder($unit);

    foreach my $dep (@deps) {
	$valueset->addValueItem(new Build::Option::Raw({
            what  => "$dep.defs", name  => "xxx_DEPENDENCIES",
                                  value => $dep,
	    }));

	$valueset->addValueItem(new Build::Option::Raw({
            what  => "$dep.defs", name  => "xxx_LINKLINE",
                                  value => getLinkName("-l<<",$dep,
						       q[$(UFID)],">>"),
			        command => INSERT,
        }));
    }

    return $self;
}

sub addPostCollapseDerivedValues {
    my ($self,$valueset,$unit,$uplid,$ufid)=@_;

    $valueset->addValueItem(new Build::Option::Raw({
        what  => "default.opts", name  => "xxx_UPLID",
                                 value => $uplid,
    }));

    $valueset->addValueItem(new Build::Option::Raw({
        what  => "default.opts", name  => "xxx_UFID",
                                 value => $ufid,
    }));

    $valueset->addValueItem(new Build::Option::Raw({
        what  => "default.opts", name  => "xxx_LIBUFID",
                                 value => $ufid->toString(1),
    }));
}



#------------------------------------------------------------------------------

# generic helper method to allow all methods below to take a list of args or
# a single hash reference arg to specify dimensions.
# <<<TODO: allow elemental dimensions to be specified discretely
sub _rationaliseArgs {
    my ($self,$what,$uplid,$ufid,$derive)=@_;
    my $dimensions;

    if (ref $what) {
	foreach (qw[what uplid ufid derive]) {
	    $dimensions->{$_}=$what->{$_} if defined $what->{$_};
	}
    } else {
	$dimensions->{what}=$what if defined $what;
	$dimensions->{uplid}=$uplid if defined $uplid;
	$dimensions->{ufid}=$ufid if defined $ufid;
	$dimensions->{derive}=$derive if defined $derive;
    }

    $self->throw("require 'what' dimension") unless $dimensions->{what};

    if (defined $self->getDefaultUfid) {
	$dimensions->{ufid}   = $self->getDefaultUfid()
	  unless defined $dimensions->{ufid};
    }
    if (defined $self->getDefaultUplid) {
	$dimensions->{uplid}  = $self->getDefaultUplid()
	  unless defined $dimensions->{uplid};
    }

    return $dimensions;
}

#----

=head2 collapse($what [,$uplid [,$ufid]])

=head2 collapse({what => $what, uplid => $uplid, ufid => $ufid})

Collapse the currently loaded options using the specified UPLID and UFID
dimensions (the UPLID in turn composed of six elemental dimensions) and
return a new value set containing the collapsed options.

=cut

sub collapse {
    my ($self,$what,$uplid,$ufid)=@_;
    my $dimensions=$self->_rationaliseArgs($what);

    my $valueset=$self->getValueSet();
    my $subset=$valueset->collapseDimensions($dimensions, "clone me");

    # only process caps if UPLID and UFID and unit were all passed in or
    # defaulted (note that the default UPLID/UFID may be unset!)
    if (defined $dimensions->{uplid} and defined $dimensions->{ufid}) {
	# Capability handling is different
	#
	# 1 - 'cascading' capabilities check themselves for all involved
	# units of release. The different units must agree for the capability
	# to be valid. Currently the only such capability is CAPABILITY, and
	# it uses the 'ALWAYS/NEVER' algorithm.
	my $cv=$valueset->getValue("CAPABILITY");
	$cv=new Build::Option("CAPABILITY") unless defined($cv);
	$cv=$self->checkCapability($cv,$dimensions);
	$subset->replaceValue($cv);

	# 2 - 'non-cascading' capabilities don't enforce a check of any
	# kind, they just apply only to the target unit of release. Therefore,
	# capabilty info from dependencies is filtered out and removed from
	# the list of value items attached to the build option.

	# Currently capabilities are allowed anywhere, but 'should' be in the
	# .cap file. Later we may change this logic, e.g to error if a cap
	# is specified in an .opts or .defs file. For now, we use regexp.
	###my $unit_cap=$dimensions->{what}.".cap"
	my @items;
	my $quoted_what = quotemeta($dimensions->{what});
	foreach my $cv ($valueset->getValues()) {
	    next unless ($cv->getName() =~ /^ASSET|^CAPABILITY./);
	    $cv=$valueset->getDimension("ufid")
	      ->collapse($cv,$dimensions->{ufid},"clone me");
	    @items = ();
	    foreach ($cv->getValueItems()) {
		push @items,$_ if ($_->getWhat() =~ /^$quoted_what\./);
	    }
	    $cv->replaceAllValueItems(@items);
	    $subset->replaceValue($cv);
	}
    }

    return $subset;
}

=head2 construct($what [,$uplid [,$ufid [,$derive]]])

=head2 construct({what=>$what, uplid=>$uplid, ufid=>$ufid, derive=>0|1})

Load all the options associated with the specified unit-of-release, using
L<"load">, then collapse them, using L<"collapse">. The entitity to calculate
values for is specified as C<$what>, and is mandatory. All other values are
optional: if unspecified, the UPLID and UFID will adopt default values.

If the optional argument <$derive> is supplied and true, the factory object
will additionally construct and add derived values based on dependency
information and the selected build state, including the UPLID, UFID, link
line, and build-ordered dependeny list. These values can be used to
construct compile and link command lines without external assistance.

=cut

sub construct {
    my ($self,$what,$uplid,$ufid,$derive)=@_;
    my $dimensions=$self->_rationaliseArgs($what,$uplid,$ufid,$derive);
    $derive=delete $dimensions->{derive}; # re-extract again

    $self->load($dimensions->{what});

    my $rawset=$self->getValueSet(); # the base uncollapsed set

    if ($derive and $what ne "default") {
	$self->addPreCollapseDerivedValues($rawset,$dimensions->{what},
				           $dimensions->{uplid},
				           $dimensions->{ufid});
    }

    my $set=$self->collapse($dimensions);

    if ($derive and $what ne "default") {
	$self->addPostCollapseDerivedValues($set, $dimensions->{what},
				           $dimensions->{uplid},
				           $dimensions->{ufid});
    }

    return $set;
}

#------------------------------------------------------------------------------

=head2 isCapable($what [,$uplid [,$ufid]])

=head2 isCapable({what => $what, uplid => $uplid, ufid => $ufid})

Return a true or false result depending on whether the supplied unit of
release will build given the supplied UPLID and UFID (or the default UPLID or
UFID, if not provided).

If a grouped package is supplied, it is silently upgraded to the containing
package group before testing. The L<"load"> method is also invoked to ensure
all applicable information is available before the test for valdity is made.

Currently this method only handles the build capability CAPABILITY, and uses
L<"checkCapability"> below to do the verification.

=cut

sub isCapable {
    my ($self,$what,$uplid,$ufid)=@_;
    my $dimensions=$self->_rationaliseArgs($what,$uplid,$ufid);

    $self->load($dimensions->{what});

    my $cv=$self->getValueSet()->getValue("CAPABILITY");
    unless (defined($cv)) {
	warning("no build capabilities defined for $what");
	return 1;
    }
    my $result = eval { $self->checkCapability($cv,$dimensions); 1; };
    return $result ? 1 : 0;
}

=head2 checkCapability($cv, $what [,$uplid [,$ufid]])

=head2 checkCapability($cv, {what => $what, uplid => $uplid, ufid => $ufid})

Check the validity of a cascading capability, such as C<CAPABILITY>, by
comparing the C<ALWAYS>/C<NEVER> result of collapsing each dependent unit-of-
release against the target given the specified UPLID and UFID. The capability
fails if any dependency (including the target unit-of-release itself) returns
a C<NEVER> result. Any dependency that does not return C<ALWAYS> is considered
a weak assent and generates a warning that the build is allowed, but is not
guaranteed.

If the capability is determined not to be valid, an exception is thrown.

Note that this method is not relevant or applicable to non-cascading
capabilities such as C<ASSET>-class metadata.

=cut

sub checkCapability {
    my ($self,$cv,$what,$uplid,$ufid)=@_;
    $what=getPackageGroup($what) if isGroupedPackage($what);
    my $dimensions=$self->_rationaliseArgs($what,$uplid,$ufid);

    # derive a list of dependencies from the list of options files
    my $unit=$dimensions->{what};
    my @optsfiles=$self->getElegibleOptionFiles($unit);
    my @what=unique (map {
	$_=basename($_); /^([^.]+)/ and $1
    } @optsfiles);

    my $set=$self->getValueSet();
    $uplid=$dimensions->{uplid};
    $ufid=$dimensions->{ufid};

    # clone and collapse down the CV on all dimensions except 'what'.
    my $cloneme="clone me";
    if ($ufid) {
        $cv=$set->getDimension("ufid")->collapse($cv,$ufid,$cloneme);
	$cloneme=undef;
    }
    if ($uplid) {
        $set->getDimension("kin")->collapse($cv,$uplid->kin,$cloneme);
        $set->getDimension("os")->collapse($cv,$uplid->os);
        $set->getDimension("os_v")->collapse($cv,$uplid->osversion);
        $set->getDimension("arch")->collapse($cv,$uplid->arch);
        $set->getDimension("compiler")->collapse($cv,$uplid->compiler);
        $set->getDimension("compiler_v")->collapse($cv,$uplid->compilerversion);
    }

    my $uor=getPackageGroup($unit) || $unit;
    # for each dependency, calculate and test its capability independently
    foreach my $what (@what) {
	next if $what =~ /^default/; # default.opts does not define caps
	my $wuor=getPackageGroup($what) || $what;

	# collapse on direct equivalency of value item 'what' to $what
	my $grp;
	my @items=grep {
	    ($_->getWhat() =~ /^\Q$wuor\E\./)
	} $cv->getValueItems();
	my $capcv=$cv->clone(); #shallow clone
	$capcv->replaceAllValueItems(@items);

	my $result=$capcv->render();
	if ($result =~ /NEVER/) {
	    #optimistic build mode requires no 'NEVER's
	    print STDERR $cv->dump() if Util::Message::get_verbose();
	    #$self->throw(($wuor eq $uor)?"capabilities of $wuor prohibit".
	    error(($wuor eq $uor)?"capabilities of $wuor prohibit".
                                      " $ufid build on $uplid":
                      "capabilities of dependency $wuor prohibit".
                      " $ufid build of $uor on $uplid");
	}
	unless ($result =~/ALWAYS/) {
	    #pessimistic build mode also requires an 'ALWAYS'.
	    warnonce(($wuor eq $uor)?"capabilities of $wuor do not guarantee".
                                      " $ufid build on $uplid":
                      "capabilities of dependency $wuor do not guarantee".
                      " $ufid build of $uor on $uplid");
	}
    }

    return $cv; #return the partially collapsed cv, with the what dimension
                #still uncollapsed, for future reference
}

#------------------------------------------------------------------------------

sub toString { return "options" };

#==============================================================================

sub test (;$$) {
    my $unit=$_[1] || $_[0] || "bde";

    require BDE::FileSystem;
    require BDE::Build::Uplid;
    require BDE::Build::Ufid;
    require Build::Option::Finder;

    Util::Message::set_verbose(1);

    my $finder=new Build::Option::Finder("/bbcm/infrastructure");

    # temporary until dependency cache use in What.pm is
    # resolved more elegantly w.r.t origin of filesystem root.
    require BDE::Util::DependencyCache;
    BDE::Util::DependencyCache::setFileSystemRoot($finder);

    my $factory=new Build::Option::Factory($finder);

    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    my $uplid=new BDE::Build::Uplid({where=>$root});
    $factory->setDefaultUplid($uplid);
    $factory->setDefaultUfid(new BDE::Build::Ufid("dbg_exc_mt"));

    my $collapsedset=$factory->construct($unit);
    print $collapsedset->render(uc($unit)."_");
    print "*** ",$collapsedset->getValue("OPTS_FILE")->render()," ***\n";

}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Build::Option::Set>, L<Build::Option::Finder>

=cut

1;
