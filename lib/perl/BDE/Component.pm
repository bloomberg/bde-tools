package BDE::Component;
use strict;

use IO::File;
use overload '""' => "toString", fallback => 1;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

use Source::File::Slim;

use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::Nomenclature qw(
    isComponent isComponentHeader getComponentPackage getComponentGroup
);
use Util::Message qw(error debug debug2 warning);
use Util::File::Basename qw(dirname basename);
use Util::Retry qw(retry_open retry_firstof);
use BDE::Util::IncludeCache qw(getFileIncludes);
use Symbols qw[
    PACKAGE_META_SUBDIR MEMFILE_EXTENSION $NO_FOLLOW_MARKER $NOT_A_COMPONENT
];

# Package var: default for new components, may be overidden
$BDE::Component::includeTestDriver = 0;

#------------------------------------------------------------------------------

=head1 SYNOPSIS

    use BDE::Component;

    # explicit initialisation of file members
    my $bdet_datetime=new BDE::Component("bdet_datetime");
    $bdet_datetime->readInterface($location_of_interface_file);
    $bdet_datetime->readImplementation($location_of_implementation_file);
    $bdet_datetime->readTestDriver($location_of_implementation_file);

  or:

    # explicit initialisation of component from location
    my $bdet_datetime=new BDE::Component("bdet_datetime");
    $bdet_datetime->readMembers($component_location);
        #read all three files using bdet_datetime as component basename

  or:

    # explicit initialisation of component from basepath
    my $bdet_datetime=new BDE::Component("bdet_datetime");
    $bdet_datetime->readMembers($component_basepath);
        #read all three files, allow a different component basename

  or:

    use BDE::FileSystem;

    # implicit initialisation of component from location
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    my $bdet_datetime_location=$root->getComponentLocation("bdet_datetime");
    my $initialised_bdet_datetime=new BDE::Component($bdet_datetime_location);

  or:

    use BDE::FileSystem;

    # implicit initialisation of component from basepath
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    my $bdet_datetime_basepath=$root->getComponentBasepath("bdet_datetime");
    my $initialised_bdet_datetime=new BDE::Component($bdet_datetime_basepath);

  then:

    my $package=$component->getPackage();
    my $group=$component->getGroup();
    my @pkg_deps=$component->getPackageDependants();
        #dependant packages other than the local package in this group
    my @dependant_components=$component->getComponentOtherGroupDependants();
        #components directly included in the same group but not local package

=head1 DESCRIPTION

This module implements a component object. It manages in-memory copies of the
three component files: interface, implementation, and test driver.

The component object is filesystem independent, and carries no knowledge of
physical location. See the L<BDE::FileSystem> module for methods to derive
pathnames for member and dependency files for initialising BDE::Component
objects. If a pathname to a package directory is provided to the constructor
then it will look for a C<package> subdirectory and attempt to initialise
itself from the membership and dependency files located within it.

=cut

#------------------------------------------------------------------------------
# Constructor support

sub fromString ($$) {
    my ($self,$init)=@_;

    $self->{include_impl}=1;
    $self->{include_test}=$BDE::Component::includeTestDriver;

    if ($init =~ /$FSRE/ and isComponent(basename($init)) and
	(-d dirname($init))) {
	# load component from basepath
	$self->{name}=basename($init);
	$self->readMembers($init);
    }  elsif (-f $init) {
	# load interface file explicitly
	$self->{name}=basename($init);
        $self->{intf} = new Source::File::Slim($init);
    }  elsif (-d $init) {
	# load component from package directory, if name is known
	if ($self->{name}) {
	    $self->readMembers($init);
	} else {
	    $self->throw("Cannot initialise unknown component");
	}
    } elsif (isComponent $init) {
	# name component, no initialisation
	$self->{name}=$init;
    } else {
	$self->throw("Not a valid initialiser: $init");
    }

    return $self;
}

#------------------------------------------------------------------------------

sub readInterface($$) {
   my $self = shift;
   my $fname = shift;

   $self->{intf} = new Source::File::Slim($fname);
}

#------------------------------------------------------------------------------

sub readImplementation($$) {
   my $self = shift;
   my $fname = shift;

   $self->{impl} = new Source::File::Slim($fname);
}

#------------------------------------------------------------------------------

sub readTestDriver($$) {
   my $self = shift;
   my $fname = shift;

   $self->{test} = new Source::File::Slim($fname);
}

#------------------------------------------------------------------------------

# init may be either a directory or a basepath.
sub readMembers ($$) {
    my ($self,$init)=@_;

    # Determine if $init is a directory or a basepath.
    my $basepath;
    if (isComponent(basename($init)) and (-d dirname($init))) {
	$basepath=$init;
    } elsif (-d $init) {
	if ($self->{name}) {
	    $basepath=$init.$FS.$self->{name};
	} else {
	    $self->throw("Cannot initialise unknown component");
	    return undef;
	}
    } else {
	$self->throw("Not a valid component directory or basepath");
	return undef;
    }

    # Read interface file.
    $self->readInterface("$basepath.h");

    # Determine language of component implementation and test driver. Retry
    # semantics make this less trivial than might be otherwise expected.
    my $lang=$self->getLanguage();
    unless ($lang) {
	my $rcspath=$basepath;
	$rcspath=~s|/([^/]+)$|/RCS/$1|;

	my @files=("$basepath.cpp","$basepath.cpp,v","$rcspath.cpp,v",
		   "$basepath.c","$basepath.c,v","$rcspath.c,v");
	my $found=retry_firstof(@files);

	unless ($found) {
	    $self->throw("Cannot find implementation file for $basepath");
	    return undef;
	}
	my $foundfile=$files[$found-1];
	$foundfile=~/\.(\w+)(?:,v)?$/ and $lang=$1;
	$self->setLanguage($lang);
    }

    # Read implementation file.
    $self->readImplementation("$basepath.$lang");

    #TODO: this needs to be cleaner, see notes below
    if ($self->includingTestByDefault) {
        $self->readTestDriver("$basepath.t.$lang");
    } else {
        $self->{testPath} = "$basepath.t.$lang"
	  if -f "$basepath.t.$lang"; #<<<RCS locations?
    }

    return 1;
}

#------------------------------------------------------------------------------

sub setInterface ($$)      { $_[0]->{intf} = $_[1]; }

sub setImplementation ($$) { $_[0]->{impl} = $_[1]; }

sub setTestDriver ($$)     { $_[0]->{test} = $_[1]; }

sub setAll ($$$;$) {
    my ($self,$intf,$impl,$test)=@_;

    $self->setInterface($intf);
    $self->setImplementation($impl);
    $self->setTestDriver($test);

    return 1;
}

#------------------------------------------------------------------------------

sub getInterface ($) {
    return ref($_[0]->{intf}) ? ${$_[0]->{intf}->getSlimSource()} : undef;
}

sub getImplementation ($) {
    return ref($_[0]->{impl}) ? ${$_[0]->{impl}->getSlimSource()} : undef;
}

sub getTestDriver ($) {
    return ref($_[0]->{test}) ? ${$_[0]->{test}->getSlimSource()} : undef;
}

sub getAll ($) {
    my @triplet=(
        $_[0]->getInterface(),
        $_[0]->getImplementation(),
        $_[0]->getTestDriver()
    );

    return wantarray ? @triplet : \@triplet;
}

#------------------------------------------------------------------------------

sub getIntfFile ($) {
    return ref($_[0]->{intf}) ? $_[0]->{intf} : undef;
}

sub getImplFile ($) {
    return ref($_[0]->{impl}) ? $_[0]->{impl} : undef;
}

sub getTstFile ($) {
    return ref($_[0]->{test}) ? $_[0]->{test} : undef;
}

#------------------------------------------------------------------------------

sub removeInterface ($)      { return delete $_[0]->{intf}; }

sub removeImplementation ($) { return delete $_[0]->{impl}; }

sub removeTestDriver ($)     { return delete $_[0]->{test}; }

sub removeAll ($) {
    $_[0]->removeInterface();
    $_[0]->removeImplementation();
    $_[0]->removeTestDriver();

    return undef;
}

#------------------------------------------------------------------------------

sub getLanguage ($) {
    my $self=shift;

    return (exists $self->{lang}) ? $self->{lang} : undef;
}

sub setLanguage ($$) {
    my ($self,$lang)=@_;

    $self->{lang}=$lang;
}

#------------------------------------------------------------------------------

sub getPackage ($) {
    return getComponentPackage($_[0]->{name}) if $_[0]->{name};
    return undef;
}

sub getGroup ($) {
    return getComponentGroup($_[0]->{name}) if $_[0]->{name};
    return undef;
}

#------------------------------------------------------------------------------

{ my %incs; #class data - there can be only one (component of a given name)
  sub _getFileIncludes ($$$) {
      my ($self,$what,$content)=@_;
      my $debug = Util::Message::get_debug();

      if (exists $incs{$what}) {
	  debug2 "Retrieving cached component includes of $what" if ($debug>=2);
      } else {
	  debug2 "Going to read includes of $what" if ($debug >= 2);
	  $incs{$what} = [ getFileIncludes($content,$what,
					   getComponentPackage($self)) ];
      }
      return @{ $incs{$what} };
  }
}

# self, what, content
sub _getFileComponentIncludes ($$$) {
    return map {
      m/^(.*)\.\w+$/ and $1; #return component names
    } grep {
        not $_->isNotAComponent()
    } shift->_getFileIncludes(@_);
}

# self, what, content
sub _getFileNonComponentIncludes ($$$) {
    return grep { $_->isNotAComponent() } shift->_getFileIncludes(@_);
}

#------------------------------------------------------------------------------
# For makefiles, we sometimes have the test driver available and sometimes not
# (in certain kinds of source code distribution, or in 'mkdevdir' style builds.
# So allow new components to automatically look for or not look for it. Note
# that we always require the implementation to be present even if we are not
# going to scan it for dependencies, so we don't have an equivalent for Impl.

# TODO: setting the package var is the only way to do this currently. Add a
# 'read_test' attribute to allow this per-component; implement BDE::Object's
# initialise-from-hash method to handle this.

sub includeTestByDefault ($;$) {
    my ($self,$switch)=@_;

    if ($#_ == 0) {
	$BDE::Component::includeTestDriver = 1;
    } else {
	$BDE::Component::includeTestDriver = $switch;
    }
}

sub excludeTestByDefault ($) {
    $BDE::Component::includeTestDriver = 1;
}

sub includingTestByDefault ($) {
    return $BDE::Component::includeTestDriver;
}

#------------------------------------------------------------------------------
# For makefiles, we care about direct dependencies of implementation and/or
# test driver some times, but we do not care in other situations, so allow it
# to be scanned or not. These methods switch on/off the scanning whereas the
# methods above suppress the reading of the test driver in the first place.

sub includeImplDependants ($;$)   {
    my ($self,$switch)=@_;

    if ($#_ == 0) {
	$_[0]->{include_impl}=1;
    } else {
	$_[0]->{include_impl}=$switch;
    }
}

sub excludeImplDependants ($)   { $_[0]->{include_impl}=0; }

sub includingImplDependants ($) {
    return exists($_[0]->{include_impl}) ? $_[0]->{include_impl} : 0;
}

sub includeTestDependants ($;$)   {
    my ($self,$switch)=@_;

    if ($#_ == 0) {
	$_[0]->{include_test}=1;
    } else {
	$_[0]->{include_test}=$switch;
    }}

sub excludeTestDependants ($)   { $_[0]->{include_test}=0; }

sub includingTestDependants ($) {
    return exists($_[0]->{include_test}) ? $_[0]->{include_test} : 0;
}

# Note: A scanner for test dependencies would switch these on for the initial
# component but leave it off for all dependent components. Hence this is not
# a package-level switch and defaults to off.

#------------------------------------------------------------------------------
# All of the below are 'direct' dependants - no recursion or following
# the first term after the 'get' is what each method returns a list of, i.e.
# getPackageDependants returns a list of packages.
# TODO: add caching of analysed values

# get all direct dependant components of this component. The analysis of the
# implementation and test driver elements is controlled by the include/exclude
# methods, e.g. includeImplDependants, excludeTestDependants. Both default to
# off so only the header is analysed normally -- see above.
sub getDependants ($) {
    my $self=shift;

    return @{$self->{component_dependants}}
                        if exists $self->{component_dependants};

    # if the question cannot be answered, return undef. Note that this
    # property is not replicated in derived methods like getPackageDependants,
    # which return ().
    return undef unless defined $self->{intf};
    return undef if $self->{include_impl} and not defined($self->{impl});

    my @deps=();

    # header dependencies
    my $intf=$self->{intf};
    push @deps, $self->_getFileComponentIncludes($self->{name}."(intf)",$intf);

    # implementation dependencies, excluding the component's own header
    if ($self->{impl} and $self->{include_impl}) {
	my $impl=$self->{impl};
	push @deps, grep { $_ ne $self->{name} }
	  $self->_getFileComponentIncludes($self->{name}."(impl)",$impl);
    }

    my %deps = map { $_ => 1 } @deps; #uniquify
    @{$self->{component_dependants}} = sort keys %deps;

    if ($self->{test}) {
        $self->getTestOnlyDependants();
    }

    return @{$self->{component_dependants}};
}

sub getTestOnlyDependants ($) {
    my $self=shift;

    return @{$self->{test_dependants}} if exists $self->{test_dependants};

    my %deps=map {$_ => 1 } @{$self->{component_dependants}};

    $self->{test_dependants} = [];

    # test driver dependencies, excluding the components' own header
    if (!$self->{test}) {
        if(!(exists $self->{testPath} && -f $self->{testPath})) {
            error ($self->{name} .
                  " has no test driver, can't generate test dependencies for it");
            return ();
        }
        $self->readTestDriver($self->{testPath});
    }

    my $test=$self->{test};
# we want only those test driver dependencies that exceed
# the component's dependencies
    @{$self->{test_dependants}}=sort
        grep { $_ ne $self->{name}
            && !exists $deps{$_}
        }
    $self->_getFileComponentIncludes($self->{name}."(test)",$test);

    if($self->{include_test}) {
        $deps{$_}++ foreach @{$self->{test_dependants}};
        @{$self->{component_dependants}} = sort keys %deps;
    }

    return @{$self->{test_dependants}};
}

# get all direct includes that are not components
sub getIncludes ($) {
    my $self=shift;

    return () unless $self->{intf} and $self->{impl};

    my @deps=();

    # header dependencies
    my $intf=$self->{intf};
    push @deps, $self->_getFileNonComponentIncludes($self->{name}."(intf)",$intf);

    # implementation dependencies, excluding the component's own header
    if ($self->{impl} and $self->{include_impl}) {
	my $impl=$self->{impl};
	push @deps, grep { $_ ne $self->{name} }
	  $self->_getFileNonComponentIncludes($self->{name}."(impl)",$impl);
    }

    # test driver dependencies, excluding the components' own header
    if ($self->{test} and $self->{include_test}) {
	my $test=$self->{test};
	push @deps,  grep { $_ ne $self->{name} }
	  $self->_getFileNonComponentIncludes($self->{name}."(test)",$test);
    }

    my %deps = map { $_ => $_ } @deps; #uniquify
    return sort values %deps;
}

# get all direct dependant packages of this component
sub getPackageDependants ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my %pkgs=map {
        getComponentPackage($_) => 1
    } @deps;
    return sort keys %pkgs;
}

# get all direct dependant groups of this component
sub getGroupDependants ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my %grps;
    foreach (@deps) {
	my $grp=getComponentGroup($_);  #isolated pkgs don't have groups
	$grps{$grp}=1 if defined $grp; #so we have to check
    }
    return sort keys %grps;
}

# get all direct dependant components in the same package
sub getDependantsInPackage ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $package=$self->getPackage();
    return grep { /^${package}_/ } @deps;
}

# get all direct dependant components in the same group
sub getDependantsInGroup ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $group=$self->getGroup();
    return grep { /^$group/ } @deps;
}

# get dependant packages not in this components group
sub getPackageDependantsInGroup ($) {
    my $self=shift;

    my @deps=$self->getPackageDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $group=$self->getGroup();
    return grep { /^$group/ } @deps;
}

# get dependant packages not in this components group
sub getPackageDependantsNotInGroup ($) {
    my $self=shift;

    my @deps=$self->getPackageDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $group=$self->getGroup();
    return grep { $_!~/^$group/ } @deps;
}

# get dependant components not in this package
sub getDependantsNotInPackage ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $package=$self->getPackage();
    return grep { $_!~/^${package}_/ } @deps;
}

# get dependant components not in this package but in this group
sub getDependantsNotInPackageInGroup ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $package=$self->getPackage();
    my $group=$self->getGroup();
    return grep { /^$group/ } grep { $_!~/^${package}_/ } @deps;
}

# get dependant components not in this group
sub getDependantsNotInGroup ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return () if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    my $group=$self->getGroup();
    return grep { $_!~/^$group/ } @deps;
}

#------------------------------------------------------------------------------

sub toString ($) {
    my $self=shift;

    return (ref($self) and exists $self->{name}) ? $self->{name} : undef;
}

#------------------------------------------------------------------------------

sub ttt {
    my $xxx = new BDE::Component("bdes_types");
    $xxx->readInterface("ttt.h");
    my $foo = $xxx->getInterface();
    print "$foo\n";

    my $i = 999;
}

#------------------------------------------------------------------------------

sub test {
    #Util::Message::set_debug(1);
    debug "debug enabled";

    my $rc;
    my $bdem_list=new BDE::Component("bdem_list");

    print "Package: (explicit) ",$bdem_list->toString(),"\n";
    print "Package: (toString) $bdem_list\n";

    print "FileSystem test:\n";
    require BDE::FileSystem;
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    print "  Filesystem located at: $root\n";
    print "  Groups located at: ",$root->getGroupsLocation(),"\n";
    foreach (qw[bdem_list bdet_time bteso_spinningeventmanager zdem_list]) {
	print ">> $_ located at: ",$root->getComponentLocation($_),"\n";
	print ">> $_ base path : ",$root->getComponentBasepath($_),"\n";
	my $comp=new BDE::Component($root->getComponentBasepath($_));
	print ">> $_ language  : ",$comp->getLanguage($_),"\n";
	foreach my $implinc (0,1) {
	    print "** Implementation Dependencies are ",
	      ($implinc?"on":"off"),"\n";
	    $comp->includeImplDependants($implinc);

	    print "  component includes    : ",
	      join(' ',$comp->getDependants()),"\n";
	    print "  - packages            : ",
	      join(' ',$comp->getPackageDependants()),"\n";
	    print "  - groups              : ",
	      join(' ',$comp->getGroupDependants()),"\n";
	    print "  non-component includes: ",
	      join(' ',$comp->getIncludes()),"\n";
	    print "  includes in package   : ",
	      join(' ',$comp->getDependantsInPackage()),"\n";
	    print "  includes in group     : ",
	      join(' ',$comp->getDependantsInGroup()),"\n";
	    print "  packages in group     : ",
	      join(' ',$comp->getPackageDependantsInGroup()),"\n";
	    print "  packages not in group : ",
	      join(' ',$comp->getPackageDependantsNotInGroup()),"\n";
	    print "  components n/i package: ",
	      join(' ',$comp->getDependantsNotInPackage()),"\n";
	    print "  - in group n/i package: ",
	      join(' ',$comp->getDependantsNotInPackageInGroup()),"\n";
	    print "  - not in group        : ",
	      join(' ',$comp->getDependantsNotInGroup()),"\n";
	}
    }
}

#------------------------------------------------------------------------------

1;
