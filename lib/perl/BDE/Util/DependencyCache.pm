package BDE::Util::DependencyCache;
use strict;

require 5.008;

#use threads;
#use threads::shared;

use BDE::Group;
use BDE::Package;
use BDE::Package::Include;
use BDE::Component;
use BDE::File::Finder;
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::IncludeCache qw(getCachedInclude);
use BDE::Util::Nomenclature qw(
    getCanonicalUOR
    getComponentPackage
    getPackageGroup
    isGroup
    isGroupedPackage
    isIsolatedPackage
    isLegacy
    isNonCompliant
    isPackage
    isThirdParty
);
use Util::File::Basename qw(basename);
use Util::Message qw(message debug debug2 fatal warning get_verbose);
use Symbols qw($NO_FOLLOW_MARKER $NOT_A_COMPONENT DEPFILE_EXTENSION MEMFILE_EXTENSION
               DEFFILE_EXTENSION OPTFILE_EXTENSION CAPFILE_EXTENSION
               PACKAGE_META_SUBDIR GROUP_META_SUBDIR BACKTRACE WANT_PACKAGE_CACHE ENABLED
               DEFAULT_FILESYSTEM_ROOT
               PACKAGE_CACHE_SUBDIR PACKAGE_DC_BASE);

use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw[
    getCachedGroup     getGroupDependencies     getAllGroupDependencies
    getCachedPackage   getPackageDependencies   getAllPackageDependencies
    getCachedComponent getComponentDependencies getAllComponentDependencies
                       getTestOnlyDependencies
                       getFileDependencies      getAllFileDependencies
    getCachedGroupOrIsolatedPackage

    getAllExternalPackageDependencies getAllInternalPackageDependencies
    getAllExternalComponentDependencies getAllInternalComponentDependencies

    getAllComponentFileDependencies getAllFileComponentDependencies

    getElegibleNCPackageDependencies getElegibleInternaNCPackageDependencies
                                     getElegibleExternalNCPackageDependencies

    createFileFinderForComponent createFileFinderForContext

    getBuildOrder getDependencyBuildOrder getMultipleDependencyBuildOrder
    getLinkName getSimpleLinkName
    getDependencyLinkLine getSimpleDependencyLinkLine
    getFileSystemRoot
    getBuildLevels
];

#------------------------------------------------------------------------------

=head1 NAME

BDE::Util::DependencyCache - Calculate and cache dependency information

=head1 SYNOPSIS

    use BDE::Util::DependencyCache qw(:ALL);

    my $root=new BDE::FileSystem("/home/me/myroot");
    BDE::Util::DependencyCache::setFileSystemRoot($root);

    my $group=getCachedGroup("mde");
    my @direct_grpdeps=getGroupDependencies("mde");
    # or:@direct_grpdeps=getCachedGroup("mde")->getDependants();
    my @all_grpdeps=getAllGroupDependencies("mde");

    my $package=getCachedPackage("bdem");
    my @direct_pkgdeps=getPackageDependencies("bdem");
    # or: @direct_pkgdeps=getCachedPackage("bdem")->getDependants();
    my @all_pkgdeps=getAllPackageDependencies("bdem");
    my @internal_pkgdeps=getAllInternalPackageDependencies("bdem");
    my @external_pkgdeps=getAllExternalPackageDependencies("bdem");

    my $component=getCachedComponent("bdet_datetime");
    my @direct_cmpdeps=getComponentDependencies("bdet_datetime");
    # or:@direct_pkgdeps=getCachedComponent("bdet_datetime")->getDependants();
    my @all_cmpdeps=getAllComponentDependencies("bdet_datetime");
    my @all_filedeps=getAllComponentFileDependencies("bdet_datetime");

=head1 DESCRIPTION

This module is a repository for dependency caching routines. It will be
upgraded into a more formal implementation when time permits. See
C<bde_build.pl> and C<bde_depends.pl> for usage examples.

Note that to use this module you I<must> provide a BDE::FileSystem object
to the routine C<BDE::Util::DependencyCache::setFileSystemRoot> before
attempting to retrieve or initialise an object from its cache.

A component or package is not allowed into the cache if its dependencies
are invalid (i.e. cyclic or incomplete). For this reason the routines
C<checkPackageDependencies> and C<checkComponentDependencies> currently
reside here. They will likely move when this module is refactored.

=head2 NOTE

I<The documentation of this module is not yet complete. Consult the source
for full details of subroutines available for export.>

=cut

#------------------------------------------------------------------------------
# Package configuration controls

=head1 CONFIGURATION ROUTINES

These routines configure the cache. They are not available for export.

=head2 setFileSystemRoot($fsroot)

Mandatory - Takes a C<BDE::FileSystem> (or derived class) object that is used
by the cache to carry out all filing system-related operations.

=head2 setNoMetaChecks(0|1)

Optional - If passed a true value, disables some aspects of the cache
verification mechanism related to the validity of components within packages.
This flag should not be set unless you are very clear that you need it. Off
by default

=head2 setFaultTolerant(0|1)

Optional - If passed a true value, disables fatal errors when an invalid
group or package is encountered, or when a package or component exceeds the
declared dependencies of its group or package (respectively). Off by default.

=cut

# FileSystem root - required
my $root=undef;

sub setDefaultRoot { 
    return if defined $root;
    require BDE::FileSystem;
    $root = BDE::FileSystem->new(DEFAULT_FILESYSTEM_ROOT);
}

sub setFileSystemRoot ($) { $root=$_[0] }
sub getFileSystemRoot () { return $root }

# Disable package level checks when caching components
my $nometa=0;
sub setNoMetaChecks ($)   { $nometa=$_[0]   ? 1 : 0; }

# Permit invalid packages and groups, and invalid dependencies
my $tolerant=0;
sub setFaultTolerant ($)  { $tolerant=$_[0] ? 1 : 0; }

#------------------------------------------------------------------------------

=head1 DEPENDENCY ANALYSIS FUNCTIONS

[[...]]

=head2 checkPackageDependencies($package)

[...]

=cut

sub checkPackageDependencies ($) {
    my $pkg=shift;

    fatal "No package" unless $pkg;

    #cross-check with group
    my $cgrp=$pkg->getGroup();
    return 1 unless $cgrp; #isolated packages don't have groups to conform to

    my %agdeps=map {$_=>1} $cgrp,getCachedGroup($cgrp)->getDependants();
    #print "cPD: g_allowed($pkg)=",_p_href(\%agdeps),"\n";
    foreach my $cgdep ($pkg->getGroupDependants()) {
	unless (exists $agdeps{$cgdep}) {
	    fatal "$pkg dependency on $cgdep is not declared in "
	          ."$cgrp dependency file";
	    return undef;
	}
    }

    my %agmems=map {$_=>1} $cgrp,getCachedGroup($cgrp)->getMembers();
    #print "cPD: g_p_allowed($pkg)=",_p_href(\%agmems),"\n";
    foreach my $cgmem ($pkg->getPackageDependants()) {
	unless (exists $agmems{$cgmem}) {
	    fatal "$pkg dependency $cgmem is not declared as "
	          ."a member of $cgrp";
	    return undef;
	}
    }

    return 1;
}

=head2 checkComponentDependencies($component)

[...]

=cut

sub checkComponentDependencies ($) {
    my $cmp=shift;

    fatal "No component" unless $cmp;

    #cross-check with package and group
    my $cpkg=getCachedPackage($cmp->getPackage);

    fatal "$cmp is not declared as a member of $cpkg"
        unless grep { /^$cmp$/ } ($cpkg->getMembers);

    if (isIsolatedPackage $cpkg) {
	my %agdeps=map {$_=>1} $cpkg,$cpkg->getDependants();
	#print "cCD(i): g_allowed($cmp)=",_p_href(\%agdeps),"\n";
	foreach my $cgdep ($cmp->getGroupDependants()) {
	    unless (exists $agdeps{$cgdep}) {
		unless ($tolerant) {
		    my $extraMsg="";
		    $extraMsg=" (did you forget '// not a component'?)"
		         if $cgdep eq "bre";
		    fatal "$cmp dependency on group $cgdep ".
		      "is not declared in $cpkg dependency file".
		      $extraMsg;
		      ;
		}
		return undef;
	    }
        }

    } else {

	my $cgrp=getCachedGroup($cmp->getGroup);

	my %apdeps=map {$_=>1} $cpkg,$cpkg->getDependants();
	#print "cCD(g): p_allowed($cmp)=",_p_href(%apdeps),"\n";
	foreach my $cpdep ($cmp->getPackageDependantsInGroup()) {
	    unless (exists $apdeps{$cpdep}) {
		unless ($tolerant) {
		    fatal "$cmp dependency on package $cpdep ".
		      "is not declared in $cpkg dependency file";
		}
		return undef;
	    }	
	}

	my %agdeps=map {$_=>1} $cgrp,$cgrp->getDependants();
	#print "cCD(g): g_allowed($cmp)=",_p_href(\%agdeps),"\n";
	foreach my $cgdep ($cmp->getGroupDependants()) {
	    unless (exists $agdeps{$cgdep}) {
		unless ($tolerant) {
		    fatal "$cmp dependency on group $cgdep ".
		      "is not declared by $cgrp dependency file";
		}
		return undef;
	    }
	}
    }

    return 1;
}

# debugging routines
sub _p_aref ($) {
    return "<undef>" if not defined $_[0];
    fatal "Not an array ref: $_[0]" unless ref($_[0]) eq "ARRAY";
    return join(' ',sort @{$_[0]});
}
sub _p_href ($) {
    return "<undef>" if not defined $_[0];
    fatal "Not a hash ref: $_[0]" unless ref($_[0]) eq "HASH";
    return join(' ',sort keys %{$_[0]});
}


=head1 CACHE FUNCTIONS

[[...]]

=head2 getCachedGroupOrIsolatedPackage($uor_name)

[...]

=cut

sub getCachedGroupOrIsolatedPackage ($) {
    my $unit;

    if (isGroup($_[0])) {
	$unit=getCachedGroup($_[0]);
    } elsif (isIsolatedPackage($_[0])) {
	$unit=getCachedPackage($_[0]);
    } else {
	fatal "$_[0] is not a group or isolated package";
    }

    return $unit;
}

=head2 getCachedGroup($group_name)

[...]

=cut

{ my %grps; # group object cache

  sub getCachedGroup ($) {
      my $grp=shift;

      fatal "No group" unless $grp;

      unless (exists $grps{$grp}) {
	  my $locn=$root->getGroupLocation($grp);
	  if ($tolerant) {
	      $grps{$grp}=eval { BDE::Group->new($locn) or undef };
	  } else {
	      $grps{$grp} = new BDE::Group($locn);
	  }
	  debug "Found and cached group $grp at $locn"
	    if $grps{$grp} && Util::Message::get_debug();

      }

      return $grps{$grp};
  }
}

=head2 getCachedPackage($package_name)

[...]

=cut

my %pkgs;  # package object cache;  moved out of the following block for package-level visibility for deflation

{
  sub getCachedPackage ($) {
      my $pkg=shift;

      fatal "No package" unless $pkg;

      unless (exists $pkgs{$pkg}) {
	  if (isGroupedPackage $pkg) {
	      my $grp=getPackageGroup $pkg;
	      my $cgrp=getCachedGroup($grp);
	      fatal "$pkg should belong to $grp, ".
		"but $grp is not a package group" unless $cgrp;
	      fatal "$pkg is not declared as a member of $cgrp ".
		"@{[$cgrp->getMembers()]})"
		  unless grep { /^\Q$pkg\E$/ } ($cgrp->getMembers);
	  }

          my $locn;
	  if ($tolerant) {
	      $pkgs{$pkg}=eval {
                  $locn=$root->getPackageLocation($pkg);
                  BDE::Package->new($locn) or undef
              };
	  } else {
              $locn=$root->getPackageLocation($pkg);
	      $pkgs{$pkg} = new BDE::Package($locn);
	  }
	  return undef unless $pkgs{$pkg};

	  debug "Found and cached package $pkg at $locn"
	    if $pkgs{$pkg} && Util::Message::get_debug();

	  #$pkgs{$pkg}->share();

	  return undef unless checkPackageDependencies($pkgs{$pkg});
      }

      return $pkgs{$pkg};
  }
}

=head2 getCachedComponent($component_name)

[...]

=cut


{ my %cmps;   # component object cache

  sub getCachedComponent ($) {
      my $cmp=shift;

      fatal "No component" unless $cmp;

      unless (exists $cmps{$cmp}) {
          unless ($nometa) {
              my $cpkg=getCachedPackage(getComponentPackage $cmp);
              fatal "$cmp is not declared as a member of $cpkg"
                unless grep { /^$cmp$/ } ($cpkg->getMembers);
          }

	  my $locn=$root->getComponentBasepath($cmp);
	  if ($tolerant) {
	      $cmps{$cmp}=eval { BDE::Component->new($locn) or undef };
	  } else {
	      $cmps{$cmp}= new BDE::Component($locn);
	  }
	  debug2 "Found and cached component $cmp at $locn"
	    if (Util::Message::get_debug() >= 2);

	  unless ($nometa) {
	      return undef unless $cmps{$cmp} and
		checkComponentDependencies($cmps{$cmp});
	  }
      }

      fatal "No such component '$cmp'" unless $cmps{$cmp};
      return $cmps{$cmp};
  }
}

#------------------------------------------------------------------------------
# Predeclaration of prototypes of recursive routines

sub _getAllGroupDependencies      ($$);
sub _getAllPackageDependencies    ($$);
sub _getAllComponentDependencies ($$$);
sub _getAllFileDependencies      ($$$);

#------------------------------------------------------------------------------

=head1 GROUP (& ISOLATED PACKAGE) DEPENDENCIES

[[...]]

=head2 getGroupDependencies($group_name)

[...]

=head2 getAllGroupDependencies($group_name)

[...]

=cut

# get dependencies for a specified group, from cache if already calculated
sub getGroupDependencies($) {
    return getCachedGroup($_[0])->getDependants();
}

{ my %agd; # group dependency cache

  sub getAllGroupDependencies ($) {
      my $grp=shift;
#      undef %agd;

      fatal "No group" unless $grp;

      return _getAllGroupDependencies($grp,[]);
  }

  # get all dependencies for a specificed group, checking for cycles
  sub _getAllGroupDependencies($$) {
      my ($grp,$trace)=@_;
      $grp=getCanonicalUOR($grp)
	if isLegacy($grp) || isThirdParty($grp); #legacy isolated pkg

      my %seen;
      if (exists $agd{$grp}) {
	return wantarray
	  ? sort keys %{$agd{$grp}}
	  : scalar keys %{$agd{$grp}};
      }

      # Not cached. Go get it.
      my (@curdeps, @newdeps, @totaldeps);
      my $obj = getCachedGroupOrIsolatedPackage($grp);
      @curdeps = $obj->getDependants();
      while (@curdeps) {
	undef @newdeps;
	foreach my $dep (@curdeps) {
	  next if $seen{$dep};
	  $seen{$dep} = 1;
	  push @totaldeps, $dep;
	  my $obj = getCachedGroupOrIsolatedPackage($dep);
	  push @newdeps, $obj->getDependants();
	}
	@curdeps = @newdeps;
      }
      $agd{$grp} = \%seen;

      return wantarray ? sort keys %seen : scalar keys %seen;

      my $top_level = scalar(@$trace) == 0;
      push @$trace,$grp;

      if (exists $agd{$grp}) {
	  if (ref $agd{$grp}) {
	      pop @$trace;
	      return wantarray
		? sort keys %{$agd{$grp}}
		: scalar keys %{$agd{$grp}};
	  } else {
	      # got a scalar - already in-progress but not finished = cycle!
	      my @mytrace=@$trace;
	      shift @mytrace until $mytrace[0] eq $grp;

              # detect weak dependency in cycle
	      my $weakdep = 0;
	      my $obj = getCachedGroupOrIsolatedPackage($grp);
	      foreach my $dep (@mytrace,$grp) {
		  $weakdep = 1, last if $obj && ($obj->isWeakDependant($dep)
						 || $obj->isCoDependant($dep));
		  $obj = getCachedGroupOrIsolatedPackage($dep);
	      }

	      #<<<TODO legacy check should go away once WeakDep check in beta
	      my $all_legacy=1;
	      foreach my $dep (@mytrace,$grp) {
		  $all_legacy=0, last
		    unless isLegacy($dep) || isThirdParty($dep);
	      }
	      if ($weakdep || $all_legacy) {
                  if (get_verbose) {
		      warning (($weakdep ? "Weak" : "Legacy").
			       " cyclic dependency detected in $grp (".
			       join(" -> ",@mytrace).")");
                  }
		  pop @$trace;
 		  $agd{$grp} = {};
		  return;
	      } else {
		  fatal "Cyclic dependency detected in $grp (".
		    join(" -> ",@mytrace).")";
	      }
	  }
      } else {
	  $agd{$grp}="working"; # place a scalar to indicate in-progress
      }

      $grp = getCachedGroupOrIsolatedPackage($grp);
      return () unless $grp;

      my %deps=map { $_ => 1 } $grp->getDependants();

      foreach my $dep (keys %deps) {
	  fatal "Group $dep depends on itself" if $dep eq $grp;
	  unless (exists $agd{$dep} and ref($agd{$dep})) {
	      _getAllGroupDependencies($dep,$trace)
	  };

	  foreach (keys %{$agd{$dep}}) {
	      $deps{$_}=$_ unless $_ eq $grp; #don't include self if cyclic
	  }
      }

      $agd{$grp}=\%deps;
      my $pop=pop @$trace;

      if ($pop ne $grp) {
	  fatal "Trace mismatch: entered with '$grp', exiting with '$pop': ".
	    join(' -> ',@$trace)." -> $pop";
      }
      return wantarray ? sort keys %deps : scalar keys %deps;
  }
}

#------------------------------------------------------------------------------

=head1 PACKAGE DEPENDENCIES

=head2 getPackageDependencies($package_name)

Get the declared direct dependencies for the specified package, creating and
caching a L<BDE::Package> object for the package first if necessary. Returns
the result of calling L<BDE::Package/getDependants> on the cached package
object.

=head2 getAllPackageDependencies($package_name)

Get all direct and indirect dependencies for the specified package, both
within the package group and externally, caching the result for reuse.

As a convenience, if an isolated package name is passed to this function then
a call will be made to L<"getAllGroupDependencies"> above, and the result of
that function returned to the caller.

=head2 getAllExternalPackageDependencies($package_name)

As L<"getAllPackageDependencies">, but return only dependencies I<external> to
the package group in which the package resides.

=head2 getAllInternalPackageDependnecies($package_name)

As L<"getAllPackageDependencies">, but return only dependencies I<internal> to
the package group in which the package resides.

=cut

# get dependencies for a specified package, from cache if already calculated
sub getPackageDependencies($) {
    return getCachedPackage($_[0])->getDependants();
}

my %apd; # package dependency cache;  moved out of the following block for package-level visibility for deflation

{
  sub getAllPackageDependencies ($) {
      my $pkg=shift;

      fatal "No package" unless $pkg;

      return _getAllPackageDependencies($pkg,[]);
  }

  # get all dependencies for a specified package, checking for cycles
  sub _getAllPackageDependencies($$) {
      my ($pkg,$trace)=@_;

      return _getAllGroupDependencies($pkg,$trace) if isIsolatedPackage($pkg);

      push @$trace,$pkg;

      if (exists $apd{$pkg}) {
	  if (ref $apd{$pkg}) {
	      pop @$trace;
	      return wantarray
		? sort keys %{$apd{$pkg}}
		: scalar keys %{$apd{$pkg}};
	  } else {
	      # got a scalar - already in-progress but not finished = cycle!
	      # (should we copy @$trace as in _getAllGroupDependencies()?)
	      shift @$trace until $trace->[0] eq $pkg;

              # detect weak dependency in cycle
	      my $weakdep = 0;
	      my $obj = getCachedPackage($pkg);
	      foreach my $dep (@$trace,$pkg) {
		  $weakdep = 1, last if $obj && ($obj->isWeakDependant($dep)
						 || $obj->isCoDependant($dep));
		  $obj = getCachedPackage($dep);
	      }

	      if ($weakdep) {
                  if (get_verbose) {
		      warning "Weak cyclic dependency detected in $pkg (".
		        join(" -> ",@$trace).")";
                  }
		  pop @$trace;
		  $apd{$pkg} = {};  return ();
	      } else {
		  fatal "Cyclic dependency detected in $pkg (".
		    join(" -> ",@$trace).")";
	      }
	  }
      } else {
	  $apd{$pkg}="working"; # place a scalar to indicate in-progress
      }

      my %deps=map {
	  $_ => 1
      } getCachedPackage($pkg)->getPackageDependants();

      $pkg=getCachedPackage($pkg);

      #print "gAPD: $pkg initial => ",_p_href(\%deps),"\n";

      foreach my $dep (keys %deps) {
	  #print "gAPD: $pkg checks $dep\n";
	  fatal "Package $dep depends on itself" if $dep eq $pkg;
	  unless (exists $apd{$dep} and ref($apd{$dep})) {
	      _getAllPackageDependencies($dep,$trace);
	  }

	  #print "gAPD: $pkg:APD:$dep => ",_p_href($apd{$dep}),"\n";
	  $deps{$_}=$_ foreach keys %{$apd{$dep}};
	  #print "gAPD: $pkg after $dep <= ",_p_href(\%deps),"\n";
      }
      #print "gAPD: $pkg final <= ",_p_href(\%deps),"\n";

      $apd{$pkg}=\%deps;
      my $pop=pop @$trace;
      if ($pop ne $pkg) {
	  fatal "Trace mismatch: entered with '$pkg', exiting with '$pop': ".
	    join(' -> ',@$trace)." -> $pop";
      }

      return wantarray ? sort keys %deps : scalar keys %deps;
  }
}

# return all package dependencies outside the same group, or an empty list if
# the passed package is not a groupable package
sub getAllExternalPackageDependencies ($) {
    my $pkg=getCachedPackage($_[0]);

    if (my $grp=$pkg->getGroup()) {
	my @deps=getAllPackageDependencies($pkg);
	return grep { $_!~/^${grp}/ } @deps;
    }

    return ();
}

# return all package dependencies in the same group, or an empty list if
# the passed package is not a groupable package
sub getAllInternalPackageDependencies ($) {
    my $pkg=getCachedPackage($_[0]);

    if (my $grp=$pkg->getGroup()) {
	my @deps=getAllPackageDependencies($pkg);
	return grep { /^${grp}/ } @deps;
    }

    return ();
}

#------------------------------------------------------------------------------

#<<<TODO: inherit from BDE::Util::Symbols and define as constants

my $INTF_ONLY = 0; # only trace and return intf dependencies
                   # used in recursive calls from INTF_IMPL mode
my $INTF_IMPL = 1; # add the impl for the requested component only
                   # used to derive header dependency lines for makefiles
my $FULL_DEPS = 2; # trace intf and impl for all components
                   # used to derive link-time object dependencies

=head1 COMPONENT DEPENDENCIES

=head2 getComponentDependencies

Get the declared direct dependencies for the specified component, creating and
caching a L<BDE::Component> object for the component first if necessary.
Returns the result of calling L<BDE::Component/getDependants> on the cached
component object.

=cut

# get direct dependencies for specified component, from cache
sub getComponentDependencies($) {
    return getCachedComponent($_[0])->getDependants();
}

# get test-driver only dependencies for specified component, from cache
sub getTestOnlyDependencies($) {
    return getCachedComponent($_[0])->getTestOnlyDependants();
}

=head2 getAllComponentDependencies($component,$searchtype)

Return all component dependencies of the specified component. The search
type, if specified, is one of the following:

  Interface Only           (0) - only trace and return interface dependencies only
  Interface+Implementation (1) - add component's implementation to search
  Full Dependencies        (2) - also add dependent components' implementations
                                 to search

The default search mode is Interface+Implementation, which returns compile-time
dependency information for the specified component, by tracing the interface
dependencies of both the interface and implementation of the component.

The Interface Only mode is used primarily for dependent components of a component
that was searched in Interface+Implementation mode. See above.

The Full Dependencies mode is used to derive the link-time object file dependencies,
if the component under interrogation were to be linked with the objects of its
dependent components rather than a package- or group-level library. Non-compliant
packages implementation files are I<not> returned, and Non-compliant packages are
presumed to have their package-level libraries used in the putative link line
created from the return value of this routine.

=cut

my %aiocd; # component interface-only dependency cache

my %aiicd; # component interface+implementation dependency cache

my %afdcd; # full dependency cache

my %acfd;  # component non-compliant includes dependency cache

# get all dependencies for a specified component
{
  sub getAllComponentDependencies ($;$) {
      my ($cmp,$type)=@_;

      $type = $INTF_IMPL unless defined $type;
      fatal "No component" unless $cmp;

      my $pkg = $cmp->getPackage;

# (GPS: disabled: see comments below __END__ block towards bottom of file)
#     if ($wantPersPkgCaches) {
#	  unless (exists $persPkgCacheVisited{$pkg}) {
#	      ##  package cache inflation never attempted before
#	      validatePkgCache($pkg);
#	  }
#      }

      return _getAllComponentDependencies($cmp,$type,[]);
  }

  # get all dependencies for a specificed component, checking for cycles
  sub _getAllComponentDependencies($$$) {
      my ($cmp,$type,$trace)=@_;
      $type = $INTF_IMPL unless defined $type;
      push @$trace,$cmp;

      # are we returning the combined dependencies or the header only?
      my $rescd = ($type==$INTF_ONLY) ? \%aiocd
	: (($type==$INTF_IMPL) ? \%aiicd : \%afdcd);

      if (exists $rescd->{$cmp}) {
	  if (ref $rescd->{$cmp}) {
	      pop @$trace;
	      return wantarray			  # typed - just interface
		? sort keys %{$rescd->{$cmp}}
		: scalar keys %{$rescd->{$cmp}};
	  } else {
	      # got a scalar - already in-progress but not finished = cycle!
	      shift @$trace until $trace->[0] eq $cmp;
	      fatal "Cyclic dependency detected in $cmp (".
		join(" -> ",@$trace).")";
	  }
      } else {
	  $rescd->{$cmp}="working"; # place a scalar to indicate in-progress
      }

      # component dependants
      $cmp=getCachedComponent($cmp);
      return () unless $cmp;
      $cmp->includeImplDependants($type==$INTF_ONLY ? 0 : 1);
      my %deps=map { $_ => 1 } $cmp->getDependants();

      ### Remote dependants via non-compliant package includes ##
      my %fdeps=();
      if (my @incs=$cmp->getIncludes()) {
	  if (my $finder=createFileFinderForComponent($root,$cmp)) {
	      foreach my $inc (@incs) {
		  my $incobj=$finder->find($inc);

		  next unless $incobj; #not found - system header or other
#fatal "$cmp nofind $inc in @{[ $finder->getSearchPath ]} !" unless $incobj;

		  $fdeps{$incobj}=$incobj;
		  if (my @fileincs=_getAllFileDependencies($incobj,$trace,$finder)) {
		      $fdeps{$_}=$_ foreach @fileincs;
		      $deps{$_}=$_ foreach map {
			  /^(.*)\.\w+$/ && $1
		      } grep { not $_->isNotAComponent() } @fileincs;
		  }
	      }
	  }
      }
      ### End: non-compliant package includes ##

      my $rtype=($type==$INTF_IMPL)?$INTF_ONLY:$type;
      my $rrescd = ($rtype==$INTF_ONLY) ? \%aiocd
	: (($rtype==$INTF_IMPL) ? \%aiicd : \%afdcd);

      foreach my $dep (keys %deps) {
	  fatal "Component $dep depends on itself" if $dep eq $cmp;
	  unless (exists $rrescd->{$dep}
		  and ref($rrescd->{$dep})) {
	      _getAllComponentDependencies($dep,$rtype,$trace);
	  }

	  $deps{$_}=$_ foreach keys %{$rrescd->{$dep}};
          my @cdeps=getAllComponentFileDependencies($dep);
	  $fdeps{$_}=$_ foreach @cdeps;
      }

      my $pop=pop @$trace;
      if ($pop ne $cmp) {
	  fatal "Trace mismatch: entered with '$cmp', exiting with '$pop': ".
	    join(' -> ',@$trace)." -> $pop";
      }

      $rescd->{$cmp}=\%deps; #store component result in the appropriate cache
      $acfd{$cmp}=\%fdeps;  #cache files result

      return wantarray ? sort keys %deps : scalar keys %deps;
  }

=head2 getAllComponentFileDependencies($component [,$searchtype])

Return all dependencies of the specified component that are not themselves
components -- i.e. header files belonging to non-standard packages. The search
type is as for L<"getAllComponentDependencies"> above, and defaults to 1.

=cut

  # return all component dependencies that aren't components
  sub getAllComponentFileDependencies ($;$) {
      my ($cmp,$full)=@_;

      getAllComponentDependencies($cmp,$full) unless exists $acfd{$cmp};

      if (exists $acfd{$cmp}) {
	  my @files=sort grep { $_->isNotAComponent() } values %{$acfd{$cmp}};

	  return @files;
      }

      return ();
  }
}

=head2 getAllExternalComponentDependencies($component [,$searchtype])

Wrapper for L<"getAllComponentDependencies"> that returns only those components
that are external to the package in which the specified component exists. The search
type is as for L<"getAllComponentDependencies"> above, and defaults to 1.

=cut

# return all component dependencies outside the same package
sub getAllExternalComponentDependencies ($;$) {
    my ($cmp,$type)=@_;
    $cmp=getCachedComponent($cmp);

    my $pkg=$cmp->getPackage();
    my @deps=getAllComponentDependencies($cmp,$type);

    @deps = grep { $_!~/^${pkg}_/ } @deps;
    return @deps;
}

=head2 getAllInternalComponentDependencies($component [,$searchtype])

Wrapper for L<"getAllComponentDependencies"> that returns only those components
that are internal to the package in which the specified component exists. The search
type is as for L<"getAllComponentDependencies"> above, and defaults to 1.

=cut

# return all component dependencies in the same package
sub getAllInternalComponentDependencies ($;$) {
    my ($cmp,$type)=@_;
    $cmp=getCachedComponent($cmp);

    my $pkg=$cmp->getPackage();
    my @deps=getAllComponentDependencies($cmp,$type);

    @deps = grep { /^${pkg}_/ } @deps;
    return @deps;
}

#------------------------------------------------------------------------------

## NOTE: There's no distinction between interface and implementation
## dependencies for files because we do not link test drivers with lists of
## dependent object (.o) files for NC packages (they just link against the lib)

=head2 getAllFileDependencies($file,$package|$finder)

Return all dependencies of the specified file, using either the passed package
(isolated or grouped) or a L<BDE::File::Finder> object previously set up with
the valid search locations. See L<"createFileFinderForContext"> and related
functions below for more on creating file finder instances.

=cut

my %afd; # file dependency cache

{
  sub getAllFileDependencies ($$) {
      my ($file,$finder_or_package)=@_;
      return _getAllFileDependencies($file,[],$finder_or_package);
  }

  # get all dependencies for a specificed file, checking for cycles
  sub _getAllFileDependencies ($$$) {
      my ($file,$trace,$finder_or_package)=@_;

      my $finder=$finder_or_package;
      unless (ref $finder_or_package) {
	  $finder=createFileFinderForContext($root,$finder);
	  # implement and replace with createFileFinderForFile
      }

      push @$trace,$file;

      if (exists $afd{$file}) {
	  if (ref $afd{$file}) {
	      pop @$trace;
	      return wantarray
		? sort values %{$afd{$file}}
		: scalar values %{$afd{$file}};
	  } else {
	      # got a scalar - already in-progress but not finished = cycle!
	      my @subtrace=@$trace; # retain trace as file cycles are non-fatal
	      shift @subtrace until $subtrace[0] eq $file;
	      if (Util::Message::get_debug) {
		  # this typically means an include of something in the system
		  # so we don't warn about it unless debug is on
		  warning "Cyclic dependency detected in $file (".
		    join(" -> ",@subtrace).")";
	      }
	      $afd{$file} = {};
	      pop @$trace;
	      return (); #return an empty list so algorithm can complete
	  }
      } else {
	  $afd{$file}="working"; # place a scalar to indicate in-progress
      }

      my %deps=();
      my $fi=getCachedInclude($file,$finder);

      unless (defined $fi) {
	  delete $afd{$file};
	  pop @$trace;
	  return (); #file doesn't exist or is out of scope
      }
      # if the inc was in a subdir, add subdir to the
      # list of places to scan for nested includes
      if ($fi->getFullname()=~m|(.*)/[^/]+$|) {
	  my $subdir=$1;
	  $finder->addPackageSearchPath($fi->getPackage(),$subdir);
      }

      foreach my $dep ($fi->getIncludes()) {
	  $deps{$dep}=$dep;

	  if (not $dep->isNotAComponent) {

              my $component=$dep; $component=~s/\.h$//;
	      my $pkg=getComponentPackage($component);

	      # transition into component-based search
	      foreach my $cdep (_getAllComponentDependencies
				$component,$INTF_IMPL,$trace) {
		  my $cdeph=$cdep.".h"; #<<<TODO: use comp->lang later
		  my $cpkg=getComponentPackage($cdep);
		  $deps{$cdeph}=new BDE::Package::Include({
	              fullname => $cdeph, package => $cpkg, name => $cdeph,
                      realname => $root->getPackageLocation($cpkg).$FS.$cdeph
	          });
              }

	  } else {

	      #fatal "File $dep depends on itself"
	      #  if $dep->getFullname eq $fi->getFullname;
	      #<<<TODO:actually should be realname when that's properly known

	      unless (exists $afd{$dep} and ref($afd{$dep})) {
		  _getAllFileDependencies($dep,$trace,$finder);
	      }

	      if (exists $afd{$dep}) {
		  # the file exists and is located somewhere we care about
		  $deps{$dep}=getCachedInclude($dep,$finder);
		  $deps{$_}=$_ foreach values %{$afd{$dep}};
	      }
	  }
      }

      $afd{$file}=\%deps;
      my $pop=pop @$trace;
      if ($pop ne $file) {
	  fatal "Trace mismatch: entered with '$file', exiting with '$pop': ".
	    join(' -> ',@$trace)." -> $pop";
      }
      return wantarray ? sort values %deps : scalar keys %deps;
  }
}

=head2 getAllFileComponentDependencies($file,$finder)

Return all dependencies of an arbitrary file which are components. Note that
a BDE::File::Finder object needs to be passed in order to establish the
valid locations the file to be found.

See also L<"getAllFileDependencies">, which this routines is a wrapper for.

=cut

sub getAllFileComponentDependencies ($$) {
    my ($file,$finder)=@_;

    my @results=getAllFileDependencies($file,$finder);

    @results=map {
	/^(.*)\.\w+$/ && $1
    } grep {
	not $_->isNotAComponent()
    } @results;

    return @results;
}

#------------------------------------------------------------------------------
# These next two sections are not completely solid yet; they have been created
# as part of a refactoring process to clarify and make more accessible the
# file dependency tracking algoritm. See also 'bde_filedepends.pl'

# return elegible NC packages in the same group as the specificed package
{ my %deps;

  sub getElegibleInternalNCPackageDependencies {
      my $pkg=shift;

      return @{$deps{$pkg}} if exists $deps{$pkg};

      my @deps=grep {
	  isNonCompliant($_)
      } getAllInternalPackageDependencies($pkg);

      $deps{$pkg}=\@deps;
      return @deps;
  }
}

{ my %deps;

  # return elegible NC packages in other units of release, for the
  # specified package (isolated or grouped) or group
  sub getElegibleExternalNCPackageDependencies {
      my $pkg=shift;

      return @{$deps{$pkg}} if exists $deps{$pkg};

      my @depgroups;
      if (isGroup $pkg) {
	  @depgroups=getAllGroupDependencies($pkg);
      } else {
	  @depgroups=getAllGroupDependencies(
              $pkg->isIsolated ? $pkg : $pkg->getGroup
	  );
      }

      my @ncpackages;
      foreach my $grp (@depgroups) {
	  if ($grp=getCachedGroup $grp) {
	      push @ncpackages, $grp->getNonCompliantMembers();
	  }
      }

      $deps{$pkg}=\@ncpackages;
      return @ncpackages;
  }

  # get all elegible NC packages, in the same group or external to it
  sub getElegibleNCPackageDependencies {
      my $pkg=shift; # group, gpkg or ipkg

      return @{$deps{$pkg}} if exists $deps{$pkg};

      my @ncpackages;
      if (isGroupedPackage $pkg) {
	  @ncpackages=getElegibleInternalNCPackageDependencies($pkg);
      }
      push @ncpackages, getElegibleExternalNCPackageDependencies($pkg);

      $deps{$pkg}=\@ncpackages;
      return @ncpackages;
  }
}

#-----

# create a file finder for all elegible NC packages given the specified
# contexts (groups or packages). Given a single package, this is a little
# like createFileFinderForComponent, except that it can work for files.
{ my %finders;

  sub createFileFinderForContext ($@) {
      my ($root,@contexts)=@_;

      my $key=join("~",$root,@contexts);
      return $finders{$key} if exists $finders{$key};

      my $finder=new BDE::File::Finder($root);

      foreach my $from (@contexts) {
	  $from=getPackageGroup($from) if isGroupedPackage($from);
	  my @ncpackages;

	  if (isGroup $from) {
	      # for groups
	      @ncpackages=getCachedGroup($from)->getNonCompliantMembers();
	  }
	  # all other NC packages 'outside'.
	  push @ncpackages, getElegibleNCPackageDependencies($from);

	  $finder->addPackageSearchPath($_) foreach @ncpackages;
	  @ncpackages = map  { getCachedPackage($_) } @ncpackages;

	  foreach my $ncp (@ncpackages) {
	      foreach my $inc ($ncp->getIncludes) {
		  if ($inc->getFullname() =~ m|^(.*)$FSRE[^$FSRE]+$|) {
		      $finder->addPackageSearchPath($ncp,$1);
		  }
	      }
	  }
      }

      $finders{$key}=$finder;
      return $finder;
  }

  # create a file finder for the specified NC packages given the specified
  # includes. The distinction between this and the routine above is that
  # this one only adds an NC package to the mix if one of the includes
  # specified is actually found there. So uninvolved NC packages aren't
  # added to the finder. Use by the compnent-oriented creator below.
  sub createFileFinderForIncludes ($\@\@) {
      my ($root,$ncpackages,$incs)=@_;
      my @incs=@$incs; my @ncpackages=@$ncpackages;

      my $key=join("~",$root,@incs,@ncpackages);
      return $finders{$key} if exists $finders{$key};

      my $finder=new BDE::File::Finder($root);
      $finder->addPackageSearchPath($_) foreach @ncpackages;

      my %seen=();
      foreach my $ncp (@ncpackages) {
	  foreach my $inc ($ncp->getIncludes) {
	      if ($inc->getFullname() =~ m|^(.*)$FSRE[^$FSRE]+$|) {
		  my $subdir=$1;
		  next if $seen{$subdir};
		  $finder->addPackageSearchPath($ncp,$subdir);
	      }
	  }
      }

    # This logic attempts to determine additional dirs not configured
    # in the .pub file referenced by a pathed include. It is not clear
    # currently if this is a valid or useful thing.
    #
    #INC: foreach my $inc (@incs) {                    # >> unresolved INC in
    #  print "cFFFI:@ncpackages>@incs\n";
    #  foreach my $ncp (@ncpackages) {
    #      if (my $incobj=$ncp->getInclude($inc)) { # << resolved INC back
    #               if ($incobj->getFullname() =~ m|^(.*)$FSRE[^$FSRE]+$|) {
    #                   $finder->addPackageSearchPath($ncp,$1);
    #               }
    #
    #		next INC; #found, go to next inc
    #	    }
    #	}
    #}

      $finders{$key}=$finder;
      return $finder;
  }

  # create a file finder to locate indirect file dependencies of the
  # specified component.
  sub createFileFinderForComponent ($$) {
      my ($root,$cmp)=@_;

      my $key=join("~",$root,$cmp);
      return $finders{$key} if exists $finders{$key};

      my $finder=undef;

      if (my @incs=$cmp->getIncludes()) {
	  my $pkg=getCachedPackage($cmp->getPackage());

	  if (my @ncpackages=getElegibleNCPackageDependencies($pkg)) {
	      @ncpackages = map { getCachedPackage($_) } @ncpackages;

	      $finder=createFileFinderForIncludes($root,@ncpackages,@incs);

	      #print "cFFFC: PATH: @{[ $finder->getSearchPath ]}\n";
	  }
      }

      $finders{$key}=$finder;
      return $finder;
  }
} #end %finders closure

#------------------------------------------------------------------------------

=head2 getBuildOrder(@items)

Return the supplied list of package groups or packages in a canonical order
that is suitable to build (or otherwise process them) serially. First, the
number of dependents is calculated to find the dependency ranking; units with
lower rankings are put to the front of the list. If two units have equal
dependency ranking, the shorter name comes first. If the names are of equal
length, alphabetical ordering is used to break the tie.

Only those units that are passed in are ordered. To generate an ordered list
of all dependencies, use L<"getDependencyBuildOrder"> below.

The results of this call are cached and reused in further calls for speed.
To clear the cache, use L<"clearBuildOrder"> below.

=head2 getBuildLevels(@items)

Return a hash containing the supplied list of packages and package groups as
the keys, and the computed level number as the value. This uses the same
internal logic as L<"getBuildOrder"> but provides access to the results of the
level calculation.

The level is computed by adding 1 to the level of the highest dependency.
Only strong dependencies are considered. If a strong cycle is detected,
all entities in the cycle are given the level of the highest dependency
not involved in the cycle, plus the number of entities in the cycle.

If a grouped package is supplied, it is biased by 10000.

Note that while it can be called on its own, this routine is often used after
L<"getDependencyBuildOrder"> (below) to retrive a list of entities as the
result of the dependency caclulation, in order to retrieve the levels of all
dependencies relative to the unit of release of inquiry.

=head2 clearBuildOrder()

Clear the cached build order and build level calculations so they will
be recomputed on the next call. This should only be necessary if the
dependencies of a cached L<BDE::Package> or L<BDE::Group> are altered
during execution.

=head2 getDependencyBuildOrder($item)

Extract the list of dependencies for the specified package or package group
and then invoke L<"getBuildOrder"> on the result. The ordered list of
dependencies of the specified unit of release is returned. The package or
package group specified is not included in the return value (but is of course
implicitly above all its dependencies).

=head2 getMultipleDependencyBuildOrder(@items)

As L<"getDependencyBuildOrder">, except that a composite build order is
returned based on the combination of all the build orders ofthe packages or
package groups specified. Note that by the nature of the query, the return
value is likely to contain entries that are not applicable to every item
originally specified. The package or package groups specified are not included
in the return value, unless they themselves are derived as a dependency of
another specified item.

=cut

{ my %order; my %level;

  sub clearBuildOrder () {
      %order=(); %level=();
  }

  sub _computeBuildLevel (@) {
      my @items=@_;
      my %skip;

      foreach my $item (@items) {
	  next if exists $order{$item};

	  unless (isGroup($item) or isPackage($item)) {
	      if ($tolerant) {
		  $skip{$item} = 1;
		  $order{$item} = 1; $level{$item} = 1;
		  warning("Not a group or package: $item"),next;
	      } else {
		  fatal("Not a group or package: $item");
	      }
	  }
	  unless (isPackage($item)?getCachedPackage($item)
		  :getCachedGroup($item)) {
	      if ($tolerant) {
		  $skip{$item} = 1;
		  $order{$item} = 1; $level{$item} = 1;
		  warning("Cound not find $item"),next;
	      } else {
		  fatal("Could not find $item");
	      }
	  }

	  $order{$item} = 1 +
	    ((isPackage($item)
	      ? (isGroupedPackage($item)
		 ? scalar getAllPackageDependencies(getCachedPackage($item))
		 : scalar getAllGroupDependencies(getCachedPackage($item)))
	      : scalar getAllGroupDependencies(getCachedGroup($item))) || 0);
	  $order{$item} += 10000 if isGroupedPackage($item);

      }

      my @ordered=sort {
	  ($order{$a} <=> $order{$b}) or
	    (length($a) <=> length($b)) or
	      ($a cmp $b)
      } grep {!$skip{$_}} @items;

      foreach my $item (@ordered) {
	  next if exists $level{$item};
	  my $high=0;
	  my $uor=isPackage($item)?
	    getCachedPackage($item):getCachedGroup($item);

	  my @cycle;
	  foreach my $dep ($uor->getStrongDependants) {
	      if (defined $level{$dep}) {
		  # defined - it's a lower library
		  $high=$level{$dep} if $level{$dep}>$high;
	      } else {
		  # it's part of a local cycle, make a note so all items can
		  # be assigned the same level once the highest dep is known
		  push @cycle, $dep;
	      }
	  }
	  $level{$item}=$high+1; # level ignoring cycles
	  if (@cycle) {
	      # if a cycle exists, all libs in it are at that level
	      $level{$item}+=scalar(@cycle);
	      $level{$_}=$level{$item} foreach @cycle;
	  }
	  # this works because all libraries in the cycle are a) not assigned
	  # a level yet ($item is just the first lib in the cycle to be
	  # looked at), and b) appear in the direct dependencies of $item.
	  # Because of the order calculation already done, lower cycles have
	  # already been handled before higher ones are considered. A lower
	  # cycle can't see a higher cycle since it's not in the indirect
	  # dependencies (because it's higher).

	  debug "$item: $order{$item} (level $level{$item}\n"
	    if Util::Message::get_debug()>=4;
      }
  }

  sub getBuildOrder (@) {
      my @items=@_;

      _computeBuildLevel(@items); #populate %order

      # the sort order prefers the shorter name if the order is otherwise
      # a tie. This means that base libraries will always come first.
      return sort {
	  ($order{$a} <=> $order{$b}) or
	    (length($a) <=> length($b)) or
	      ($a cmp $b)
      } @items;
  }

  sub getBuildLevels (@) {
      my @items=@_;

      _computeBuildLevel(@items); #populate %order

      my %levels=map { $_ => $level{$_} } @items;

      return wantarray? %levels : \%levels;
  }
}

sub getDependencyBuildOrder ($) {
    my $item=shift;

    my @deps;
    if (isPackage $item) {
	if (isGroupedPackage $item) {
	    push @deps,getAllPackageDependencies(getCachedPackage($item));
	} else {
	    push @deps,getAllGroupDependencies(getCachedPackage($item));
	}
    } elsif (isGroup $item) {
	push @deps,getAllGroupDependencies(getCachedGroup($item));
    } else {
	fatal "Not a package or package group: $item";
    }

    return getBuildOrder(@deps);
}

sub getMultipleDependencyBuildOrder (@) {
    my @items=@_;

    my %deps;
    foreach my $item (@items) {
	if (isPackage $item) {
	    if (isGroupedPackage $item) {
		$deps{$_}=1
		  foreach getAllPackageDependencies(getCachedPackage($item));
	    } else {
		$deps{$_}=1
		  foreach getAllGroupDependencies(getCachedPackage($item));
	    }
	} elsif (isGroup $item) {
	    $deps{$_}=1
	      foreach getAllGroupDependencies(getCachedGroup($item));
	} else {
	    fatal "Not a package or package group: $item";
	}
    }

    return getBuildOrder(keys %deps);
}

#<<<TODO: here mostly for conveninece, used by Build::Option::Factory. move.
sub getLinkName ($$$$;$) {
    my ($prefix,$item,$ufid,$postfix,$assumeregion)=@_;

    my $unit=isPackage($item)?getCachedPackage($item):getCachedGroup($item);
    unless ($unit) {
	return $prefix.$item.".".($ufid || "dbg_exc_mt").$postfix if $assumeregion;
	fatal "$item is not a recognizable unit of release";
    }

    my $base=basename($item); # the UOR might contain a '/' but the
                              # library name cannot.

    if ($unit->isPrebuilt) {
        return $prefix.$base.$postfix;
    } elsif ($unit->isMetadataOnly) {
	return "";
    } else {
        return $prefix.$base.".".($ufid || "dbg_exc_mt").$postfix;
    }
}

sub getSimpleLinkName ($;$$) {
    my ($item,$ufid,$assumeregion)=@_;
    return getLinkName("-l",$item,$ufid,"",$assumeregion);
}

sub getDependencyLinkLine ($$;$$$) {
    my ($prefix,$item,$ufid,$postfix,$assumeregion)=@_;

    my @deps=getDependencyBuildOrder($item);
    @deps=map { getLinkName($prefix,$_,$ufid,$postfix,$assumeregion) } @deps;
    return wantarray ? @deps : "@deps";
}

sub getSimpleDependencyLinkLine ($;$$) {
    my ($item,$ufid,$assumeregion)=@_;
    return getDependencyLinkLine("-l",$item,$ufid,"",$assumeregion);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::Group>, L<BDE::Package>, L<BDE::Component>, L<BDE::FileSystem>

=cut

1;


__END__


## GPS: All of the following has been disabled until further notice.
##	It was written by contractor and never activated.
##	There are severe security flaws in the world-writable design of this.
##
##	Note that setFileSystemRoot() is redefined below.
##	To use the below, will need to replace the setFileSystemRoot() at top
##	See also disabled block of code in getAllComponentDependencies() above
##
##	Note, at some point in the past and upon request, the contractor had
##	switched to using Storable instead of Data::Dumper.  Not sure where
##	that code is.


#------------------------------------------------------------------------------

=head1 PERSISTENT CACHE FUNCTIONS

use File::Temp qw(tempfile tempdir);

use File::stat;
use Digest::MD5;

my $MD5fileSuffix;

# Additions
#@EXPORT_OK=qw[
#    deflateAllPackageCaches
#    disablePersistentPackageCache
#    setCacheNeedsUpdate
#    clearCacheNeedsUpdate
#    cacheNeedsUpdate
#];

##  --------------------------------------------------------
##               function  ::  setMD5fileSuffix
##  --------------------------------------------------------
##
##  sig  ::  void  --->  void
##
##  calculate MD5 of BDE root+path to identify the persistent cache
##  that should be used

sub setMD5fileSuffix
{
  $MD5fileSuffix = "." . Digest::MD5::md5_hex($root->getRootLocation() . ":" . $root->getPath());
}

sub setFileSystemRoot ($) { $root=$_[0]; setMD5fileSuffix(); }

#  should persistent caches be used?
my $wantPersPkgCaches = (WANT_PACKAGE_CACHE eq ENABLED) ? 1 : 0;

#  keep track of which package-level cache needs deflation?
my %pkgsNeedDeflation = ();

#  do not attempt any cache deflation
my $noCacheDeflation = 0;

#  have we tried to inflate a package cache before?
my %persPkgCacheVisited = ();

# hash for persistent hash registration
my %persPkgHashes = ();
my %persCompHashes = ();
my %persFileHashes = ();

# hash used at inflation & deflation time
my %reversePkgKeyedCache = ();

#------------------------------------------------------------------------------
# Predeclaration of prototypes of persistent cache related routines

sub  _registerPersHash  ($$$);
sub  validatePkgCache   ($;$);
#------------------------------------------------------------------------------

_registerPersHash(\%persPkgHashes,'pkgs',\%pkgs);
_registerPersHash(\%persPkgHashes,'apd',\%apd);
_registerPersHash(\%persFileHashes,'afd',\%afd);
_registerPersHash(\%persCompHashes,'aiocd',\%aiocd);
_registerPersHash(\%persCompHashes,'aiicd',\%aiicd);
_registerPersHash(\%persCompHashes,'afdcd',\%afdcd);
_registerPersHash(\%persCompHashes,'acfd', \%acfd);

#------------------------------------------------------------------------------

[[...]]

=head2 deflateAllPackageCaches()  --->  void

[...]

=cut


##  caches for inflation/deflation
my %pkgCacheMetadata = ();
my %pkgCache          = ();


##  --------------------------------------------------------
##                function  ::  getMetadataRelativePath
##  --------------------------------------------------------

sub getMetadataRelativePath ($$) {
    my($uor,$ext) = @_;

    return $FS.(isGroup($uor) ? GROUP_META_SUBDIR : PACKAGE_META_SUBDIR).
           $FS.basename($uor).$ext;
}



##  --------------------------------------------------------
##                function  ::  _trimSpaces
##  --------------------------------------------------------
##
##  sig  ::  (instr:str)  --->  str
##
##  remove leading and trailing spaces functionally instead of
##  destructively

sub _trimSpaces ($) {
    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}



##  --------------------------------------------------------
##           function  ::  _fileExistsTestAndWarn
##  --------------------------------------------------------
##
##  sig  ::  (fileLocn:str,errMsg)  --->  bool
##
##  test whether a file or directory exists or not;  If not,
##  issue the warning and return the result accordingly

sub _fileExistsTestAndWarn ($$) {
    my ($fileLocn,$errMsg) = @_;

    unless (-e $fileLocn) {
        warning "$errMsg";
        return 0;
    }

    return 1;
}



##  --------------------------------------------------------
##              function  ::  _registerPersHash
##  --------------------------------------------------------
##
##  sig  ::  (persHashRef:ref,hashName:string,hashRef:ref)  --->  void
##
##  persistent hashes registration

sub _registerPersHash ($$$) {
    my ($persHashRef,$hashName,$hashRef) = @_;
    $persHashRef->{$hashName} = $hashRef;
}



##  --------------------------------------------------------
##        function  ::  disablePersistentPackageCache
##  --------------------------------------------------------
##
##  sig  ::  void  --->  void
##
##  should persistent package cache be used or not?

sub disablePersistentPackageCache () {
    $wantPersPkgCaches = 0;
}




##  --------------------------------------------------------
##             function  ::  validatePkgCache
##  --------------------------------------------------------
##
##  sig  ::  (pkg:Package,[pkgCacheLocn:str])  --->  bool
##
##  Inflate all persistent package hashes if the package's cache
##  and the caches of all its dependents are valid.
##  If any of them is not valid, remove the package's cache if it
##  exists.  If the package cache does not exist, it is effectively
##  a NOOP.
##  The 2nd optional parameter is used to indicate alternative persistent
##  package cache location.

sub validatePkgCache($;$) {
    my ($pkg,$pkgCacheLocn) = @_;
    $pkg = BDE::Package->new($pkg);
    my $allDepCachesValid = 1;
    my $pkgRoot = $root->getPackageLocation($pkg);

    ##  note the visit of the current package
    $persPkgCacheVisited{$pkg} = undef;

    $pkgCacheLocn = $pkgRoot . $FS . PACKAGE_META_SUBDIR . $FS .
      PACKAGE_CACHE_SUBDIR . $FS . PACKAGE_DC_BASE . $MD5fileSuffix
	unless defined $pkgCacheLocn;

    my @directPkgDeps = getPackageDependencies($pkg);

    ##  validate direct dependents
    foreach my $directPkgDep (@directPkgDeps) {
        ##  is the dependent a group?
        if (isGroup($directPkgDep)) {
            my $pkgGrp = BDE::Group->new($directPkgDep);
            my $grpMemFileLocn = $root->getGroupMemFilename($pkgGrp);
            my @grpPkgs = $pkgGrp->readMembers($grpMemFileLocn);
            foreach my $depGrpPkg (@grpPkgs) {
 	        unless (exists $persPkgCacheVisited{$depGrpPkg}) {
		    ##  package cache inflation never attempted before for this direct dep
		    unless (validatePkgCache($depGrpPkg)) {
			$allDepCachesValid = 0;
                    }
                }
            }
	} else {
 	    unless (exists $persPkgCacheVisited{$directPkgDep}) {
		##  package cache inflation never attempted before for this direct dep
		unless (validatePkgCache($directPkgDep)) {
		    $allDepCachesValid = 0;
		}
	    }
        }
    }

    ##  validate current package's own metadata to determine if cache is valid or not
    if (($allDepCachesValid) && (_isPkgCacheMetadataValid($pkg,$pkgCacheLocn))) {
	debug "inflation for [$pkg] begins  ....................";
        return _restoreAllPkgHashes($pkg);
    }

    # If the control flow reaches this point, this cache is no longer valid.
    # Remove the persistent package cache and no inflation will take place.
    unlink $pkgCacheLocn;

    ##  indicate if the package inflation has been attempted but to no avail
    ##  leave the value of persPkgCacheVisited{$pkg} to undef, unchanged
    return 0;
}


{ my $cacheNeedsUpdate=1;

  sub setCacheNeedsUpdate () {
      $cacheNeedsUpdate=1;
  }

  sub clearCacheNeedsUpdate {
      $cacheNeedsUpdate=0;
  }

  sub cacheNeedsUpdate () {
      return $cacheNeedsUpdate;
  }
}

sub deflateCache (;$) {
    unless ($noCacheDeflation) { return deflateAllPackageCaches($_[0]); }
    # add other specific caching mechanisms here later, if any
}



##  --------------------------------------------------------
##             function  ::  deflateAllPackageCaches
##  --------------------------------------------------------
##
##  sig  ::  ($force:bool,$altPkgCacheDir:str)  --->  bool
##
##  deflate all pertinent caches to persistent store
##
##  The 1st optional parameter is used to indicate whether a forced deflation
##  is requested.  The 2nd optional parameter is used to indicate alternative
##  persistent package cache location.

sub deflateAllPackageCaches (;$$) {
    my ($force,$altPkgCacheDir) = @_;

    unless ($force or cacheNeedsUpdate) {
	debug "cache does not need update, skipped";
	return 1;
    }

    debug "package cache deflation process begins ......";

    %reversePkgKeyedCache = ();

    ##  transform content of package-keyed hashes into reversePkgKeyedCache
    while (my ($hashName,$hashRef) = each %persPkgHashes) {
	while (my ($pkgName,$pkgValue) = each %$hashRef) {
	    $reversePkgKeyedCache{$pkgName}{pkg}{$hashName} = $pkgValue;
	}
    }

    ##  transform content of component-keyed hashes into reversePkgKeyedCache
    while (my ($hashName,$hashRef) = each %persCompHashes) {
	while (my ($compName,$compValue) = each %$hashRef) {
	    my $pkg = getComponentPackage $compName;
	    $reversePkgKeyedCache{$pkg}{comp}{$hashName}{$compName} = $compValue;
	  }
      }

    ##  transform content of file-keyed hashes into the reversePkgKeyedCache
    while (my ($hashName,$hashRef) = each %persFileHashes) {
	while (my ($fileName,$fileValue) = each %$hashRef) {
	  #      my $incObj = new BDE::Package::Include({ fullname => $fileName });
	  #      my $pkg = $incObj->getPackage();    print "fileName  ::  [$fileName]    ------    pkg  ::  [[[$incOpkg]]]\n";
	  #      $reversePkgKeyedCache{$pkg}{file}{$hashName}{$fileName} = $fileValue;
      }
    }

    ##  deflate both the reverse cache hash and pkg cache metadata hash
    while (my ($pkgName,$pkgValue) = each %reversePkgKeyedCache) {
	my $pkgRoot = $root->getPackageLocation($pkgName);
	my $pkgPkgDir = $pkgRoot . $FS . PACKAGE_META_SUBDIR;

        return 0 unless _fileExistsTestAndWarn($pkgPkgDir,"package dir [$pkgPkgDir] does not exist for persistent data serialization");

        unless (-w $pkgPkgDir) {
            warning "package dir [$pkgPkgDir] not writable for persistent data serialization";
            return 0;
        }

        my $pkgCacheDir = undef;

        ##  if the user passes in an alternative cache dir, make sure it is writable
        if (defined $altPkgCacheDir) {
	    unless (-w $altPkgCacheDir) {
		warning "cache directory :: [$altPkgCacheDir] not writable\n";
		return 0;   # deflation failed
	    }

            $pkgCacheDir = $altPkgCacheDir;
	} else {
            $pkgCacheDir = $pkgPkgDir . $FS . PACKAGE_CACHE_SUBDIR;
        }

	##  initialize the package-specific cache meta data to be empty since it will
	##  only be used very briefly here;  this hash is very shortly-lived and transient
	%pkgCacheMetadata = ();

	unless (-e $pkgCacheDir) {
            my $oldUmask = umask;
            my $rc = 1;
            umask 002;

            unless (mkdir("$pkgCacheDir")) {
                warning "cannot mkdir package cache dir [$pkgCacheDir] :: $!";
                $rc = 0;
            }

            umask $oldUmask;
            return $rc unless $rc;
        }

	my $pkgCacheFile = $pkgCacheDir . $FS . PACKAGE_DC_BASE . $MD5fileSuffix;
	my $BDErootPath = $pkgRoot . ":" . $root->getPath();

	return 0 unless _buildPkgCacheMetadataHash($pkgName);

	require Data::Dumper;
	$Data::Dumper::Purity = 1;

	##  write to temp file then mv to achieve writing to cache atomically thanks to Unix kernel
	my ($TMP_CACHE_FH,$tmpCacheFileName) = tempfile("tmpCacheXXXXX", DIR => $pkgCacheDir);
        print $TMP_CACHE_FH "###  BDE root:path  ::  $BDErootPath\n";   ##  so we know which build this cache is for
	print $TMP_CACHE_FH Data::Dumper->Dump([\%pkgCacheMetadata,$pkgValue],["*pkgCacheMetadata","*pkgCache"]);
	close $TMP_CACHE_FH;
	rename $tmpCacheFileName,$pkgCacheFile;

        unless (chmod 0664, $pkgCacheFile) {
            warning "cannot chmod the package cache file :: [$pkgCacheFile]  :  $!";
            return 0;
        }
    }

    clearCacheNeedsUpdate();
    return 1;
}





##  --------------------------------------------------------
##                function  ::  _inflatePkgCache
##  --------------------------------------------------------
##
##  sig  ::  ($pkg:Package,$pkgCacheFile:str)  --->  bool
##
##  This function is invoked by _isPkgCacheMetadataValid in order to validate
##  a persistent package cache.
##
##  The $pkg is a required parameter for "reversing" the package cache dump.
##  After inflation, 2 hashes will come into existence:
##  * pkgCacheMetadata
##  * pkgCache
##
##  Note that the cache values will only be populated into the global hash(es)
##  when validation of the cache's metadata is successful.

sub _inflatePkgCache ($;$)
{
  my ($pkg,$pkgCacheFile) = @_;

  ##  hash comes into existence after slurping below
  %pkgCache = ();
  %pkgCacheMetadata = ();

  local $/ = undef;

  unless (defined $pkgCacheFile)
  {
    my $pkgRoot = $root->getPackageLocation($pkg);
    $pkgCacheFile = $pkgRoot . $FS . PACKAGE_META_SUBDIR . $FS . PACKAGE_CACHE_SUBDIR . $FS . PACKAGE_DC_BASE . $MD5fileSuffix;

  }

  my $PKG_CACHE_FILE = new IO::File;

  unless (open($PKG_CACHE_FILE, "< $pkgCacheFile")) {
      warning "cannot open package cache file :: [$pkgCacheFile] : $!";
      return 0;
  }

  eval <$PKG_CACHE_FILE>;     ##  slurping the entire cache file

  if ($@) {
      warning "cannot inflate the persistent package cache of [$pkgCacheFile]: $@" if $@;
      close $PKG_CACHE_FILE;
      return 0;
  }

  close $PKG_CACHE_FILE;
  return 1;
}



##  --------------------------------------------------------
##              function  ::  _restoreAllPkgHashes
##  --------------------------------------------------------
##
##  sig  ::  ($pkg:str)  --->  bool
##
##  If the pkgCacheMetadata hash validatation is successful, then we continue
##  to inflate all the package hashes from the persistent store by
##  "reversing" the "pkgCache".   If validation fails, no (key,value) pairs
##  population to the global hashes will happen.

sub _restoreAllPkgHashes ($) {
    my $pkg = shift;

    ##  restore the package-key-ed hashes
    my $pkgCachePkgHashRef = $pkgCache{pkg};

    for my $hashName (keys %$pkgCachePkgHashRef) {
	$persPkgHashes{$hashName}->{$pkg} = $pkgCachePkgHashRef->{$hashName};
    }

    ##  restore all the component-key-ed hashes
    my $pkgCacheCompHashRef = $pkgCache{comp};

    for my $hashName (keys %$pkgCacheCompHashRef) {
	while (my ($compName,$compValue) =
	       each %{$pkgCacheCompHashRef->{$hashName}}) {
	    $persCompHashes{$hashName}->{$compName} = $compValue;
	}
    }

    ##  restore all the file-key-ed hashes
    #  my $pkgCacheFileHashRef = $pkgCache{file};

    #  for my $hashName (keys %$pkgCacheFileHashRef) {
    #    while (my ($fileName,$fileValue) = each %{$pkgCacheFileHashRef->{$hashName}})
    #      { $persFileHashes{$hashName}->{$fileName} = $fileValue; }
    #  }
    #
    $persPkgCacheVisited{$pkg} = 1;
    debug "inflation for [$pkg] ends  ......................";
    return 1;
}



##  --------------------------------------------------------
##           function  ::  _buildPkgCacheMetadataHash
##  --------------------------------------------------------
##
##  sig  ::  ($pkg:Package)  --->  bool
##
##  Store the fingerprint of all components and the following metadata files
##  so we can later verify if a persistent cache is valid or not at inflation time
##
##     group    ::  .dep  .mem  .defs  .opts  .cap   (if componentized)
##     package  ::  .dep  .mem  .defs  .opts
##
##  The caller of this function is deflateAllPkgCaches before cache deflation.

sub _buildPkgCacheMetadataHash ($)
{
  my $pkg = shift;
  $pkg = BDE::Package->new($pkg);
  my $pkgRoot = $root->getPackageLocation($pkg);
  my $isIsoPkg = isIsolatedPackage $pkg;
  my $grp = ($isIsoPkg) ? "" : (BDE::Package->new($pkg))->getGroup;
  my $grpRoot = ($isIsoPkg) ? "" : $root->getGroupLocation($grp);

  my %componentFilesFingerprint = ();
  my $pkgMetadataLocn = $pkgRoot . $FS . PACKAGE_META_SUBDIR;
  my $grpMetadataLocn = ($isIsoPkg) ? "" : $grpRoot . $FS . GROUP_META_SUBDIR;

  my $statRes;

  ##  store the fingerprints of mandatory metadata files

  ##  .mem file
  my $pkgMemFile = $root->getPackageMemFilename($pkg);
  return 0 unless _fileExistsTestAndWarn($pkgMemFile,"package .mem file [$pkgMemFile] missing");

  unless ($statRes = stat($pkgMemFile)) {
      warning "cannot stat package .mem file [$pkgMemFile]";
      return 0;
  }

  $pkgCacheMetadata{mem} = $statRes->mtime . "+++" . $statRes->size;

  ##  .dep file
  my $pkgDepFile = $root->getPackageDepFilename($pkg);
  return 0 unless _fileExistsTestAndWarn($pkgDepFile,"package .dep file [$pkgDepFile] missing");

  unless ($statRes = stat($pkgDepFile)) {
      warning "cannot stat package .dep file [$pkgDepFile]";
      return 0;
  }

  $pkgCacheMetadata{dep} = $statRes->mtime . "+++" . $statRes->size;

  if (!$isIsoPkg)
  {
    ##  group .mem file
    my $grpMemFile = $root->getGroupMemFilename($grp);
    return 0 unless _fileExistsTestAndWarn($grpMemFile,"group .mem file [$grpMemFile] missing");
    unless ($statRes = stat($grpMemFile)) {
        warning "cannot stat group .mem file [$grpMemFile]";
        return 0;
    }
    $pkgCacheMetadata{groupmem} = $statRes->mtime . "+++" . $statRes->size;

    ##  group .dep file
    my $grpDepFile = $root->getGroupDepFilename($grp);
    return 0 unless _fileExistsTestAndWarn($grpDepFile,"group .dep file [$grpDepFile] missing");
    unless ($statRes = stat($grpDepFile)) {
        warning "cannot stat group .dep file [$grpDepFile]";
        return 0;
    }
    $pkgCacheMetadata{groupdep} = $statRes->mtime . "+++" . $statRes->size;
  }

  ##  store the fingerprints of optional metadata files

  ##  .defs file
  my $pkgDefsFile = $pkgRoot.getMetadataRelativePath($pkg,DEFFILE_EXTENSION);

  if (-e $pkgDefsFile)
  {
    unless ($statRes = stat($pkgDefsFile)) {
        warning "cannot stat packge .defs file [$pkgDefsFile]";
        return 0;
    }

    $pkgCacheMetadata{defs} = $statRes->mtime . "+++" . $statRes->size;
  }
  else
  {
    $pkgCacheMetadata{defs} = "";
  }

  ##  .opts file
  my $pkgOptsFile = $pkgRoot.getMetadataRelativePath($pkg,OPTFILE_EXTENSION);

  if (-e $pkgOptsFile)
  {
    unless ($statRes = stat($pkgOptsFile)) {
        warning "cannot stat packge .opts file [$pkgOptsFile]";
        return 0;
    }

    $pkgCacheMetadata{opts} = $statRes->mtime . "+++" . $statRes->size;
  }
  else
  {
    $pkgCacheMetadata{opts} = "";
  }

  ##  group .defs & .opts files
  if (!$isIsoPkg)
  {
    ##  group .defs
    my $grpDefsFile = $grpRoot.getMetadataRelativePath($grp,DEFFILE_EXTENSION);

    if (-e $grpDefsFile)
    {
      unless ($statRes = stat($grpDefsFile)) {
          warning "cannot stat group .defs file [$grpDefsFile]";
          return 0;
      }

      $pkgCacheMetadata{groupdefs} = $statRes->mtime . "+++" . $statRes->size;
    }
    else
    {
      $pkgCacheMetadata{groupdefs} = "";
    }

    ##  group .opts
    my $grpOptsFile = $grpRoot . getMetadataRelativePath($grp,OPTFILE_EXTENSION);

    if (-e $grpOptsFile)
    {
      unless ($statRes = stat($grpOptsFile)) {
          warning "cannot stat group .opts file [$grpOptsFile]";
          return 0;
      }

      $pkgCacheMetadata{groupopts} = $statRes->mtime . "+++" . $statRes->size;
    }
    else
    {
      $pkgCacheMetadata{groupopts} = "";
    }
  }

  ##  group .cap file
  if (!$isIsoPkg)
  {
    my $grpCapFile = $grpRoot . getMetadataRelativePath($grp,CAPFILE_EXTENSION);

    if (-e $grpCapFile)
    {
      unless ($statRes = stat($grpCapFile)) {
          warning "cannot stat group .cap file [$grpCapFile]";
          return 0;
      }

      $pkgCacheMetadata{groupcap} = $statRes->mtime . "+++" . $statRes->size;
    }
    else
    {
      $pkgCacheMetadata{groupcap} = "";
    }
  }

  ## store the mtime+++size fingerprint of all component files in the .mem files
  my $MEMFILE = new IO::File;

  unless (open($MEMFILE,"$pkgMemFile")) {
      warning "cannot open package .mem file [$pkgMemFile]";
      return 0;
  }

  my @pkgMemComps = $pkg->readMembers($pkgMemFile);

  foreach my $pkgMemComp (@pkgMemComps)
  {
    my $compImplFileName = $root->getComponentImplFilename($pkgMemComp);
    my $compIntfFileName = $root->getComponentIntfFilename($pkgMemComp);
    my $compTestFileName = $root->getComponentTestFilename($pkgMemComp);

    my @existingMemCompLocns = grep { defined } ($compImplFileName,$compIntfFileName,$compTestFileName);

    foreach my $pkgMemCompLocn (@existingMemCompLocns)
    {
      $statRes = stat($pkgMemCompLocn);
      $statRes ||= stat($pkgMemCompLocn.",v");

      unless ($statRes) {
	 next if $pkgMemCompLocn eq $compTestFileName;  # test driver optional
         warning "cannot stat component [$pkgMemCompLocn]";
         return 0;
      }

      $componentFilesFingerprint{$pkgMemCompLocn} = $statRes->mtime . "+++" . $statRes->size;
    }
  }

  $pkgCacheMetadata{componentFilesFingerprint} = \%componentFilesFingerprint;
  return 1;
}



##  --------------------------------------------------------
##           function  ::  _isPkgCacheMetadataValid
##  --------------------------------------------------------
##
##  sig  ::  ($pkg:Package,$pkgCacheLocn:str)  --->  bool
##
##  verify the validity of the persistent cache based on the file size
##  and timestamps of the component files listed in the .mem file,
##  along with the following package/group metadata
##
##  Metadata files involved in the validation:
##     group    ::  .opts  .mem  .defs  .dep  .cap
##     package  ::  .opts  .mem  .defs  .dep
##
##  It invokes the cache inflation function first to obtain the info of the previous snapshot.

sub _isPkgCacheMetadataValid ($$)
{
  my ($pkg,$pkgCacheLocn) = @_;
  $pkg = BDE::Package->new($pkg);
  my $pkgRoot = $root->getPackageLocation($pkg);
  my $isIsoPkg = isIsolatedPackage $pkg;
  my $grp = ($isIsoPkg) ? "" : (BDE::Package->new($pkg))->getGroup;
  my $grpRoot = ($isIsoPkg) ? "" : $root->getGroupLocation($grp);
  my $grpMetadataLocn = ($isIsoPkg) ? "" : $grpRoot . $FS . GROUP_META_SUBDIR;

  my %componentFilesFingerprint = ();
  my $pkgMetadataLocn = $pkgRoot . $FS . PACKAGE_META_SUBDIR;

  ##  certain legacy source or ClearCase locations are not writable so the
  ##  cache may have been deflated somewhere else
  $pkgCacheLocn = $pkgRoot . $FS . PACKAGE_META_SUBDIR . $FS . PACKAGE_CACHE_SUBDIR . $FS . PACKAGE_DC_BASE . $MD5fileSuffix
    unless defined $pkgCacheLocn;

  my $statRes;

  ##  the persistent cache file does not exist
  unless (-e $pkgCacheLocn) { return 0; }

  ##  two caches pkgCacheMetadata & pkgCache come into existence after inflation
  return 0 unless (_inflatePkgCache($pkg,$pkgCacheLocn));

  ##  -----------------------------------------------
  ##  check for consistency of package/group metadata
  ##  -----------------------------------------------

  ##  package .mem
  my $pkgMemFile = $root->getPackageMemFilename($pkg);
  return 0 unless _fileExistsTestAndWarn($pkgMemFile,"package .mem file [$pkgMemFile] missing");

  unless ($statRes = stat($pkgMemFile)) {
      warning "cannot stat package .mem file [$pkgMemFile]";
      return 0;
  }

  if ($pkgCacheMetadata{mem} ne ($statRes->mtime . "+++" . $statRes->size)) { return 0; }

  ##  package .dep
  my $pkgDepFile = $root->getPackageDepFilename($pkg);
  return 0 unless _fileExistsTestAndWarn($pkgDepFile,"package .dep file [$pkgDepFile] missing");

  unless ($statRes = stat($pkgDepFile)) {
      warning "cannot stat package .dep file [$pkgDepFile]";
      return 0;
  }

  if ($pkgCacheMetadata{dep} ne ($statRes->mtime . "+++" . $statRes->size)) { return 0; }

  if (!$isIsoPkg)
  {
    ##  group .mem
    my $grpMemFile = $root->getGroupMemFilename($grp);
    return 0 unless _fileExistsTestAndWarn($grpMemFile,"group .mem file [$grpMemFile] missing");
    unless ($statRes = stat($grpMemFile)) {
        warning "cannot stat group .mem file [$grpMemFile]";
        return 0;
    }
    if ($pkgCacheMetadata{groupmem} ne ($statRes->mtime . "+++" . $statRes->size)) { return 0; }

    ##  group .dep
    my $grpDepFile = $root->getGroupDepFilename($grp);
    return 0 unless _fileExistsTestAndWarn($grpDepFile,"group .dep file [$grpDepFile] missing");
    unless ($statRes = stat($grpDepFile)) {
        warning "cannot stat group .dep file [$grpDepFile]";
        return 0;
    }
    if ($pkgCacheMetadata{groupdep} ne ($statRes->mtime . "+++" . $statRes->size)) { return 0; }
  }

  ##  package .defs file
  my $pkgDefsFile = $pkgRoot.getMetadataRelativePath($pkg,DEFFILE_EXTENSION);

  if (-e $pkgDefsFile)
  {
    unless ($statRes = stat($pkgDefsFile)) {
        warning "cannot stat packge .defs file [$pkgDefsFile]";
        return 0;
    }

    if ($pkgCacheMetadata{defs} ne ($statRes->mtime . "+++" . $statRes->size)) { return 0; }
  }
  elsif ($pkgCacheMetadata{defs} ne "") {
     return 0;
  }

  ##  package .opts file
  my $pkgOptsFile = $pkgRoot.getMetadataRelativePath($pkg,OPTFILE_EXTENSION);

  if (-e $pkgOptsFile)
  {
    unless ($statRes = stat($pkgOptsFile)) {
        warning "cannot stat packge .opts file [$pkgOptsFile]";
        return 0;
    }

    if ($pkgCacheMetadata{opts} ne ($statRes->mtime . "+++" . $statRes->size))
      { return 0; }
  }
  elsif ($pkgCacheMetadata{opts} ne "")
    { return 0; }

  ##  group .defs, .opts, and .cap files
  if (!$isIsoPkg)
  {
    ##  group .defs
    my $grpDefsFile = $grpRoot . getMetadataRelativePath($grp,DEFFILE_EXTENSION);

    if (-e $grpDefsFile)
    {
      unless ($statRes = stat($grpDefsFile)) {
          warning "cannot stat group .defs file [$grpDefsFile]";
          return 0;
      }

      if ($pkgCacheMetadata{groupdefs} ne ($statRes->mtime . "+++" . $statRes->size))
        { return 0; }
    }
    elsif ($pkgCacheMetadata{groupdefs} ne "")
      { return 0; }

    ##  group .opts
    my $grpOptsFile = $grpRoot . getMetadataRelativePath($grp,OPTFILE_EXTENSION);

    if (-e $grpOptsFile)
    {
      unless ($statRes = stat($grpOptsFile)) {
          warning "cannot stat group .opts file [$grpOptsFile]";
          return 0;
      }

      if ($pkgCacheMetadata{groupopts} ne ($statRes->mtime . "+++" . $statRes->size))
        { return 0; }
    }
    elsif ($pkgCacheMetadata{groupopts} ne "")
      { return 0; }

    ##  group .cap file
    my $grpCapFile = $grpRoot . getMetadataRelativePath($grp,CAPFILE_EXTENSION);

    if (-e $grpCapFile)
    {
      unless ($statRes = stat($grpCapFile)) {
          warning "cannot stat group .cap file [$grpCapFile]";
          return 0;
      }

      if ($pkgCacheMetadata{groupcap} ne ($statRes->mtime . "+++" . $statRes->size))
        { return 0; }
    }
    elsif ($pkgCacheMetadata{groupcap} ne "")
      { return 0; }
  }

  ##  has any one of the .mem component files changed?
  my $MEMFILE = new IO::File;

  unless (open($MEMFILE,"$pkgMemFile")) {
      warning "cannot open package .mem file [$pkgMemFile]";
      return 0;
  }

  my @pkgMemComps = $pkg->readMembers($pkgMemFile);

  foreach my $pkgMemComp (@pkgMemComps)
  {
    my $compImplFileName = $root->getComponentImplFilename($pkgMemComp);
    my $compIntfFileName = $root->getComponentIntfFilename($pkgMemComp);
    my $compTestFileName = $root->getComponentTestFilename($pkgMemComp);

    my @existingMemCompLocns = grep { defined } ($compImplFileName,$compIntfFileName,$compTestFileName);

    foreach my $pkgMemCompLocn (@existingMemCompLocns)
    {
      $statRes = stat($pkgMemCompLocn);
      $statRes ||= stat($pkgMemCompLocn.",v");

      unless ($statRes) {
	 next if $pkgMemCompLocn eq $compTestFileName;  # test driver optional
	 warning "cannot stat component [$pkgMemCompLocn]";
         return 0;
      }

      return 0 unless     ## if there is a mismatch in timestamp or size, return false immediately
        $pkgCacheMetadata{componentFilesFingerprint}{$pkgMemCompLocn} eq
          ($statRes->mtime . "+++" . $statRes->size);
    }
  }

  return 1;
}

END {
    if ($wantPersPkgCaches and cacheNeedsUpdate) {
	deflateCache();
    }
}

