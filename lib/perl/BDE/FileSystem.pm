package BDE::FileSystem;
use strict;

use base 'BDE::Object';
use overload '""' => "toString", fallback => 1;

use Compat::File::Spec;
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent isIndexed isIndexedType isApplication
    isIsolatedPackage isGroupedPackage isIsolatedWrapper
    getPackageType getGroupType getTypeDir getType
    getLegacyLeafPath getThirdPartyLeafPath getApplicationLeafPath
);
use Util::File::Basename qw(basename dirname);
use Util::Message qw(verbose verbose2 fatal warning);
use Util::Retry qw(:all);
use Symbols qw[
    PACKAGE_META_SUBDIR GROUP_META_SUBDIR     APPLICATION_META_SUBDIR
    DEPFILE_EXTENSION   MEMFILE_EXTENSION     LCKFILE_EXTENSION
    IS_BASE             GROUPS_DIR            $BASE_TYPENAME
    IS_ADAPTER          ADAPTERS_DIR          $ADAPTER_TYPENAME
    IS_FUNCTION         FUNCTIONS_DIR         $FUNCTION_TYPENAME
    IS_APPLICATION      APPLICATIONS_DIR      $APPLICATION_TYPENAME
    IS_DEPARTMENT       DEPARTMENTS_DIR       $DEPARTMENT_TYPENAME
    IS_WRAPPER          WRAPPERS_DIR          $WRAPPER_TYPENAME
    IS_ENTERPRISE       ENTERPRISES_DIR       $ENTERPRISE_TYPENAME
    IS_THIRDPARTY       THIRDPARTY_DIR        $THIRDPARTY_TYPENAME
    IS_LEGACY           LEGACY_DIR            $LEGACY_TYPENAME
    INDEX_DIR           PATH                  CONSTANT_PATH
    FILESYSTEM_NO_LOCAL FILESYSTEM_NO_ROOT
    FILESYSTEM_NO_PATH  FILESYSTEM_NO_DEFAULT
    FILESYSTEM_NO_SEARCH
    FILESYSTEM_FLAT     FILESYSTEM_VERY_FLAT
    FILESYSTEM_CACHE    FILESYSTEM_NO_CACHE
    ENABLED             TOOLS_ETCDIR          LEGACY_PATH
];

#==============================================================================

=head1 NAME

BDE::FileSystem - Core support for BDE directory structure and pathnames.

=head1 SYNOPSIS

     my $root=new BDE::FileSystem("/path/to/local/root");
     $root->setSearchMode(FILESYSTEM_NO_LOCAL);
     print $root->getGroupLocation("bde");

=head1 DESCRIPTION

C<BDE::FileSystem> provides support for identifying, locating, constructing
and searching BDE-compliant directory layouts. It understands the logical
layout of the source tree and is capable of searching for requested groups,
packages, or components if they cannot be found locally.

=head1 ENVIRONMENT VARIABLES

C<BDE::FileSystem> makes use of several symbols that may be overridden in the
environment using one of the following environment variables:

    BDE_ROOT - local BDE directory root
    BDE_PATH - colon-separated list of other roots to search

See L<Symbols> for the default values of these symbols.

=cut

#==============================================================================

=head1 CONSTRUCTOR AND CONSTRUCTOR SUPPPORT METHODS

=head2 new($path)

Construct a new filesystem object with its root set to the specified path.

=head2 fromString($path)

Constructor support, invoked by C<"new">. Initialise a new filesystem object
from the supplied path, which is converted to an absolute path. Calls
L<"setRootLocation">, below, to install the path. To install a relative path
L<"setRootLocation"> must be called directly.

=cut

sub fromString ($$) {
    my ($self,$root)=@_;

    $self->setRootLocation(_abs_path($root));
    $self->{path} ||= PATH;

    return $self;
}

#------------------------------------------------------------------------------

=head1 SEARCH MODES AND METHODS

All search modes are enabled by default, and are disabled by setting the
appropriate search mode flag. The following search mode flags are supported.

    FILESYSTEM_NO_LOCAL   - do not look relative to the CWD.
    FILESYSTEM_NO_ROOT    - do not look in the local source root (BDE_ROOT)
    FILESYSTEM_NO_PATH    - do not look in the search path (BDE_PATH)

The following flags are convenience combinations of the above modes:

    FILESYSTEM_LOCAL_ONLY - no root + no path
    FILESYSTEM_ROOT_ONLY  - no local + no path
    FILESYSTEM_PATH_ONLY  - no local + no root
    FILESYSTEM_NO_SEARCH  - no local + no root + no path

The following flags modify the above search modes:

    FILESYSTEM_NO_CACHE   - do not cache results searches
    FILESYSTEM_FLAT       - source trees are flattened (one level only)
    FILESYSTEM_NO_CONTEXT - no membership files expected for package or groups
    FILESYSTEM_VERY_FLAT  - flat + no context

By default, if a search is unsuccessful, a default path to the default root
is returned. To disable this and return an error instead, set:

    FILESYSTEM_NO_DEFAULT - do not return a default path if not found

=head2 getSearchMode()

Return the current search mode as a composite bitfield (i.e. an integer).

    my $mode=$root->getSearchMode();

The return value may be logically ANDed to test for specific flags.

=cut

sub getSearchMode ($) {
    my $self=shift;

    unless (exists $self->{searchmode}) {
	$self->{searchmode} = 0;
    }

    return $self->{searchmode};
}

=head2 setSearchMode($bitfield)

Set the search mode. The supplied argument should be a composite of bitfield
flags in the C<FILESYSTEM_*> family.

   $root->setSearchMode(FILESYSTEM_NO_LOCAL | FILESYSTEM_NO_ROOT);

The search mode determines where the filesystem object will look for requested
entities (groups, packages, components) when using L<"getGroupLocation">,
L<"getPackageLocation">, L<"getComponentLocation">, or
L<"getComponentBasepath">.

By default all search locations are enabled.

=cut

sub setSearchMode ($$) {
    my ($self,$mode)=@_;

    $self->{searchmode}=$mode;
}

#------------------------------------------------------------------------------

=head1 PACKAGE GROUP METHODS

=head2 getGroupLocation($group [,$mode])

Return the location of the specified group, using the optional search mode if
supplied, or the preset search mode (see L<"setSearchMode">) otherwise.

    my $grplocn=$root->getGroupLocation("bae");

If the group is not found and FILESYSTEM_NO_DEFAULT is not set, an exception
is thrown. If an appropriate category directory is found under the local root,
and FILESYSTEM_NO_DEFAULT is not set, the path of where the group I<would> be
located, as determined by C<getDefaultGroupLocation>, is returned. If the
catergory directory is missing, an exception is thrown.

By default search results are cached, but caching may be controlled by setting
the environment variable BDE_FILESYSTEM_CACHE to C<ON> or C<OFF> or passing
the FILESYSTEM_NO_CACHE mode flag.

=cut

{ my %locs;

  sub clearGroupLocationCache { %locs=(); }

  sub getGroupLocation ($$;$) {
      my ($self,$group,$nolocal)=@_;
      return undef unless isGroup($group);
      my $verbose = Util::Message::get_verbose();

      $nolocal = $self->getSearchMode() unless defined $nolocal;

      # if we have already looked according to $nolocal criteria...
      unless (($nolocal & FILESYSTEM_NO_CACHE) or
	      FILESYSTEM_CACHE ne ENABLED) {
	  if (exists $locs{$group}{$nolocal}) {
	      return $locs{$group}{$nolocal};
	  }
      }

      my $group_type = getGroupType($group);

      my @paths=();
      unless (($nolocal & FILESYSTEM_NO_SEARCH) == FILESYSTEM_NO_SEARCH) {

	  unless ($nolocal & FILESYSTEM_NO_LOCAL) {
	      if ($group_type & IS_DEPARTMENT) { # indexed package group
		  push @paths, map {
		      (".${FS}${\INDEX_DIR}${FS}$_",
		       "..${FS}${\INDEX_DIR}${FS}$_",
		       "..${FS}..${FS}${\INDEX_DIR}${FS}$_",
		       "..${FS}..${FS}..${FS}${\INDEX_DIR}${FS}$_")
		  } ($group);
	      }
	      push @paths, map {
		  (".${FS}$_","..${FS}$_","..${FS}..${FS}$_")
	      } ($group);
	  }

	  my $dir=getTypeDir($group_type);
	  $dir.=$FS.INDEX_DIR if isIndexed($group_type);
	  unless ($nolocal & FILESYSTEM_NO_ROOT) {
	      push @paths, map { $_.$FS.$dir.$FS.$group } ($self);
	  }

	  unless ($nolocal & FILESYSTEM_NO_PATH) {
	      push @paths, map {
		  $_.$FS.$dir.$FS.$group
	      } (split ':',$self->getPath);
	  }

	  my $found=undef;
	  foreach my $path (@paths) {
	      my $testpath=$path.
		(($nolocal & FILESYSTEM_FLAT)?"":$FS.GROUP_META_SUBDIR);
	      $found=$path,last if -d $testpath;
	  }

	  if ($found) {
	      $found=_abs_path($found) if $self->isAbsolute;
	      $locs{$group}{$nolocal}=$found; #_abs_path($found);
	      if ($found ne $locs{$group}{$nolocal}) {
		  verbose2 "$found resolved to $locs{$group}{$nolocal}"
		    if ($verbose >= 2);
	      }
	      verbose "$group found at $locs{$group}{$nolocal}"
		if $verbose;
	      return $locs{$group}{$nolocal};
	  }
      }

      if ($nolocal & FILESYSTEM_NO_DEFAULT) {
	  warning "Package group $group could not be found (searched @paths)";
	  return undef;
	  #return $self->throw("Package group $group could not be found ".
	  #		       "(searched @paths)");
      }

      $locs{$group}{$nolocal}=$self->getDefaultGroupLocation($group);
      unless (($nolocal & FILESYSTEM_NO_SEARCH) == FILESYSTEM_NO_SEARCH) {
	  verbose "$group not found, default to $locs{$group}{$nolocal}"
	    if $verbose;
      } else {
	  verbose "$group default to $locs{$group}{$nolocal}"
	    if $verbose;
      }
      return $locs{$group}{$nolocal};
  }

  sub getGroupRoot {
      my ($self,$group,$nolocal)=@_;
      return undef unless isGroup($group);

      my $locn=$self->getGroupLocation($group);

      my $group_type = getGroupType($group);
      my $dir=getTypeDir($group_type);
      $dir.=$FS.INDEX_DIR if isIndexed($group_type);

      $locn =~ s/${FSRE}$dir${FSRE}$group$//;
      return $locn;
  }
}

=head2 getDefaultGroupLocation($group)

Return the default location for the specified group, as determined by the
filesystem root and category directory of the group type. Throws an
exception if the requested group is not valid or the category directory
required is not present in the local root.

=cut

sub getDefaultGroupLocation ($$) {
    my ($self,$group)=@_;

    my $group_type = getGroupType($group);

    my $location;
  SWITCH: foreach ($group_type) {
	# group packages
	$_==IS_BASE and do {
	    $location=$self->getBaseLocation();
	    last;
	};
	$_==IS_DEPARTMENT and do {
	    $location=$self->getDepartmentsLocation();
	    last;
	};
	$_==IS_ENTERPRISE and do {
	    $location=$self->getEnterprisesLocation();
	    last;
	};
	$_==IS_WRAPPER and do {
	    $location=$self->getWrappersLocation();
	    last;
	};
      DEFAULT:
	return $self->throw("Unimplemented group type $group");
    }

    unless ($location) {
	return $self->throw(
	    "No valid location for $group - no ".
	    getTypeDir(getGroupType($group))." directory?"
        );
    }

    #return $location.$FS.$group; # borked.

    ##<<<FIXME: this is bad.  this is borked.  I don't want to commit this. -gps
    ## broken once infrastructure started returning multiple colon-separated
    ## paths for the called routines above.  We want to avoid filesystem
    ## call here.  Should be abstracted in different place.
    my @locations = split ':',$location;
    foreach my $p (@locations) {
	return $p.$FS.$group if -d $p.$FS.$group;
    }
    return $locations[0].$FS.$group;
}

=head2 getGroupDepFilename($group)

Return the full pathname of the dependency file for the specified group.

=cut

sub getGroupDepFilename ($$) {
    my ($self,$group)=@_;

    return undef unless isGroup($group);
    return $self->getGroupLocation($group).
      $FS.GROUP_META_SUBDIR.$FS.basename($group).DEPFILE_EXTENSION;
}

=head2 getGroupMemFilename($group)

Return the full pathname of the membership file for the specified group.

=cut

sub getGroupMemFilename ($$) {
    my ($self,$group)=@_;

    return undef unless isGroup($group);
    return $self->getGroupLocation($group).
      $FS.GROUP_META_SUBDIR.$FS.basename($group).MEMFILE_EXTENSION;
}

=head2 getGroupLckFilename($group)

Return the full pathname of the lock file for the specified group.

=cut

sub getGroupLckFilename ($$) {
    my ($self,$group)=@_;

    return undef unless isGroup($group);
    return $self->getGroupLocation($group).
      $FS.GROUP_META_SUBDIR.$FS.basename($group).LCKFILE_EXTENSION;
}

#------------------------------------------------------------------------------
# Package

=head1 PACKAGE METHODS

=head2 getPackageLocation($package [,$mode])

Return the location of the specified package, using the optional search mode if
supplied, or the preset search mode (see L<"setSearchMode">) otherwise. Both
isolated and grouped packages are handled.

    my $pkglocn=$root->getPackageLocation("bdema");

If the package is not found and C<FILESYSTEM_NO_DEFAULT> is set, an exception
is thrown. If an appropriate category directory is found under the local root,
and C<FILESYSTEM_NO_DEFAULT> is not set, the path of where the package
I<would> be located, as determined by C<getDefaultPackageLocation>, is
returned. If the catergory directory is missing, an exception is thrown.

By default search results are cached, but caching may be controlled by setting
the environment variable C<BDE_FILESYSTEM_CACHE> to C<ON> or C<OFF> or passing
the C<FILESYSTEM_NO_CACHE> mode flag.

=cut

{ my %locs;

  sub clearPackageLocationCache { %locs=(); }

  sub getPackageLocation ($$;$) {
      my ($self,$package,$nolocal)=@_;
      return undef unless isPackage($package);
      my $verbose = Util::Message::get_verbose();

      $nolocal = $self->getSearchMode() unless defined $nolocal;

      # if we have already looked according to $nolocal criteria...
      unless (($nolocal & FILESYSTEM_NO_CACHE) or
	      FILESYSTEM_CACHE ne ENABLED) {
	  if (exists $locs{$package}{$nolocal}) {
	      return $locs{$package}{$nolocal};
	  }
      }

      my $group=$self->getPackageGroup($package);
      my $package_type=getPackageType($package);
      my $isIsolatedPackage=isIsolatedPackage($package);

      my @paths=();
      unless (($nolocal & FILESYSTEM_NO_SEARCH) == FILESYSTEM_NO_SEARCH) {

	  unless ($nolocal & FILESYSTEM_NO_LOCAL) {
	      if ($package_type & IS_FUNCTION) { #isolated indexed pkg
		  push @paths, map {
		      (".${FS}${\INDEX_DIR}${FS}$_",
		       "..${FS}${\INDEX_DIR}${FS}$_",
		       "..${FS}..${FS}${FS}${\INDEX_DIR}$_",
		       "..${FS}..${FS}..${FS}${FS}${\INDEX_DIR}$_")
		  } ($package);
	      }
	      push @paths, map {
		  (".${FS}$_","..${FS}$_","..${FS}..${FS}$_")
	      } ($package,$group?$group.$FS.$package:());
	  }

	  my $dir=getTypeDir($package_type);
	  $dir.=$FS.INDEX_DIR if isIndexed($package_type);
	  my $leafpath= $isIsolatedPackage
	    ? $dir.$FS.$package
	    : $dir.$FS.$group.$FS.$package;
	  my($legacyleafpath,$thirdpartyleafpath,$applicationleafpath);
	  if ($isIsolatedPackage) {
	      $legacyleafpath=getLegacyLeafPath($package);
	      $thirdpartyleafpath=getThirdPartyLeafPath($package);
	      $applicationleafpath=getApplicationLeafPath($package);
	  }

	  # (intentionally avoid using isLegacy() here to allow for the
	  #  possibility that something that is isLegacy() might be found
	  #  in a more-compliant (refactored) place when multirooting)
	  # XXX: When library locations settle down, using isLegacy()
	  #      might be an optimization to avoid unnecessary stat()s.

	  unless ($nolocal & FILESYSTEM_NO_ROOT) {
	      push @paths, map {$_.$FS.$leafpath} (split /:/,$self);
	      push @paths, map {$_.$FS.$legacyleafpath,
				$_.$FS.$thirdpartyleafpath,
				$_.$FS.$applicationleafpath
			       } (split /:/,$self) if $isIsolatedPackage;
	  }

	  unless ($nolocal & FILESYSTEM_NO_PATH) {
	      foreach (split ':',$self->getPath) {
		  push @paths,  $_.$FS.$leafpath;
		  push @paths,  $_.$FS.$legacyleafpath,
				$_.$FS.$thirdpartyleafpath,
				$_.$FS.$applicationleafpath
		    if $isIsolatedPackage;
	      }
	  }

	  my $found=undef;
	  foreach my $path (@paths) {
	      my $testpath=$path.
		(($nolocal & FILESYSTEM_FLAT)?"":$FS.PACKAGE_META_SUBDIR);
	      $found=$path,last if -d $testpath;
	      #<<<TODO: if $isIsolatedPackage, and path contains
	      #         $FS.$legacyleafpath, might test without
	      #         PACKAGE_META_SUBDIR, or provide a warning or, better,
	      #         debug message that that metadata is missing
	  }

	  if ($found) {
	      $found=_abs_path($found) if $self->isAbsolute;
	      $locs{$package}{$nolocal}=$found; #_abs_path($found);
	      if ($found ne $locs{$package}{$nolocal}) {
		  verbose2 "$found resolved to $locs{$package}{$nolocal}"
		    if ($verbose >= 2);
	      }
	      verbose "$package found at $locs{$package}{$nolocal}"
		if $verbose;
	      return $locs{$package}{$nolocal};
	  }
      }

      if ($nolocal & FILESYSTEM_NO_DEFAULT) {
	  warning "Package $package could not be found (searched @paths)";
	  return undef;
	#  return $self->throw("Package $package could not be found ".
	#		      "(searched @paths)");
      }

      $locs{$package}{$nolocal}=
	$self->getDefaultPackageLocation($package,$nolocal);
      unless (($nolocal & FILESYSTEM_NO_SEARCH) == FILESYSTEM_NO_SEARCH) {
	  verbose "$package not found, default to $locs{$package}{$nolocal}"
	    if $verbose;
      } else {
	  verbose "$package default to $locs{$package}{$nolocal}"
	    if $verbose;
      }
      return $locs{$package}{$nolocal};
  }

  sub getPackageRoot {
      my ($self,$package,$nolocal)=@_;
      return undef unless isPackage($package);

      if (my $group=$self->getPackageGroup($package)) {
	  return $self->getGroupRoot($group);
      } else {
	  my $locn=$self->getPackageLocation($package);

	  my $package_type = getPackageType($package);
	  my $dir=getTypeDir($package_type);
	  $dir.=$FS.INDEX_DIR if isIndexed($package_type);

	  $locn =~ s/${FSRE}$dir${FSRE}\Q$package\E$//;
	  return $locn;
      }
  }
}

=head2 getDefaultPackageLocation($package [,$mode])

Return the default location for the specified package. If the package is a
grouped package, a search is made via L<"getGroupLocation"> first for the group.
If found, a path for the package is generated using the found group. Otherwise,
the filesystem root and category directory of the package type is used as the
basis of the path.

Set the C<FILESYSTEM_NO_SEARCH> flag to prevent the group search and have
the fallback default path returned in all cases.

=cut

sub getDefaultPackageLocation ($$;$) {
    my ($self,$package,$nolocal)=@_;

    my $group=$self->getPackageGroup($package);
    my $package_type=getPackageType($package);

    my $location;
  SWITCH: foreach ($package_type) {
	# isolated packages
	$_==IS_ADAPTER and do {
	    $location=$self->getAdaptersLocation();
	    last;
	};
	$_==IS_APPLICATION and do {
	    $location=$self->getApplicationsLocation();
	    last;
	};
	$_==IS_FUNCTION and do {
	    $location=$self->getFunctionsLocation();
	    last;
	};
	$_==IS_THIRDPARTY and do {
	    $location=$self->getThirdPartyLocation();
	    last;
	};
	$_==IS_LEGACY and do {
	    $location=$self->getLegacyLocation();
	    last;
	};
	# group packages
	$_==IS_BASE and do {
	    $location=$self->getGroupLocation($group,$nolocal) if $group;
	    last;
	};
	$_==IS_DEPARTMENT and do {
	    $location=$self->getGroupLocation($group,$nolocal) if $group;
	    last;
	};
	$_==IS_ENTERPRISE and do {
	    $location=$self->getGroupLocation($group,$nolocal) if $group;
	    last;
	};
	$_==IS_WRAPPER and do {
	    if (isIsolatedWrapper($package)) { # z_a_xyz
		$location=$self->getWrappersLocation();
	    } else {
		$location=$self->getGroupLocation($group,$nolocal) if $group;
	    }
	    last;
	};
      DEFAULT:
	return $self->throw("Unimplemented package type $package");
    }

    unless ($location) {
	#<<<TODO: FIXME  this is here so that if a legacy library exists, but
	# does not have a package/ subdir, we do not throw an error.  This
	# should really be handled by an IS_LEGACY type above, but that
	# requires fixing Nomenclature.pm and everything that uses
	# getPackageType().  The hack checking if getFullLegacyName returns
	# an absolute path is to workaround phantom Big libraries that exist
	# in /bbs/lib, but have no existence elsewhere
#<<<TODO: TESTING if still needed
#	if (isLegacy($package)) {
#	    my $path = getFullLegacyName($package);
#	    return (substr($path,0,1) ne $FS) ? LEGACY_PATH.$FS.$path : $path;
#	}
	return $self->throw(
	   "No valid location for $package - no ".
	   getTypeDir(getPackageType($package))." directory?"
        );
    }

    #return $location.$FS.$package; # borked.

    ##<<<FIXME: this is bad.  this is borked.  I don't want to commit this. -gps
    ## broken once infrastructure started returning multiple colon-separated
    ## paths for the called routines above.  We want to avoid filesystem
    ## call here.  Should be abstracted in different place.
    my @locations = split ':',$location;
    foreach my $p (@locations) {
	return $p.$FS.$package if -d $p.$FS.$package;
    }
    return $locations[0].$FS.$package;

}

=head2 getPackageMemFilename($package)

Return the full pathname of the membership file for the specified package.

=cut

sub getPackageMemFilename ($$) {
    my ($self,$package)=@_;

    return undef unless isPackage($package);
    return $self->getPackageLocation($package).
      $FS.PACKAGE_META_SUBDIR.$FS.basename($package).MEMFILE_EXTENSION;
}

=head2 getPackageDepFilename($package)

Return the full pathname of the dependency file for the specified package.

=cut

sub getPackageDepFilename ($$) {
    my ($self,$package)=@_;

    return undef unless isPackage($package);
    return $self->getPackageLocation($package).
      $FS.PACKAGE_META_SUBDIR.$FS.basename($package).DEPFILE_EXTENSION;
}

=head2 getPackageLckFilename($package)

Return the full pathname of the lock file for the specified package.

=cut

sub getPackageLckFilename ($$) {
    my ($self,$package)=@_;

    return undef unless isIsolatedPackage($package);
    return $self->getPackageLocation($package).
      $FS.PACKAGE_META_SUBDIR.$FS.basename($package).LCKFILE_EXTENSION;
}

#------------------------------------------------------------------------------

=head2 getComponentLocation($component [,$mode])

Return the location of the specified component, using the optional search mode
if supplied, or the preset search mode (see L<"setSearchMode">) otherwise.
C<undef> is returned if the supplied component name is not valid.

    my $cmplocn=$root->getComponentLocation("a_bdema_gmallocallocator");

Since components are located in package directories, the return result of
this method is similar calling L<"getPackageLocation"> on the component's
package. It differs in that a mode containing C<FILESYSTEM_VERY_FLAT> will
always return 'C<.>' (the local directory), and that a mode containing
FILESYSTEM_FLAT will return the group directory for a grouped component rather
than the package directory. (These modes are specialised and are not generally
intended for broad consumption.)

=cut

sub getComponentLocation($$;$) {
    my ($self,$comp,$nolocal)=@_;
    return undef unless isComponent($comp);

    $nolocal = $self->getSearchMode() unless defined $nolocal;

    if($nolocal & FILESYSTEM_VERY_FLAT) {
	return "."; #no contextual intelligence of any kind
    } else {
	if ($self->getComponentGroup($comp) and $nolocal & FILESYSTEM_FLAT) {
	    my $grp=$self->getComponentGroup($comp);
	    return $self->getGroupLocation($grp,$nolocal);
	} else {
	    my $pkg=$self->getComponentPackage($comp);
	    return $self->getPackageLocation($pkg,$nolocal);
	}
    }
}

=head2 getComponentBasepath()

Return the complete pathname to the specified component, including the
component name, less any extension to differentiate between the interface,
implementation, or test driver. C<undef> is returned if the supplied component
name is not valid.

    my $cmpbase=$root->getComponentBasepath("bces_platform");

This method is essentially identical to taking the result of a call to
C<getComponentLocation> and appending a file separator and the component
name to the end.

=cut

sub getComponentBasepath($$;$) {
    my ($self,$comp,$nolocal)=@_;

    return undef unless isComponent($comp);
    return $self->getComponentLocation($comp,$nolocal).$FS.$comp;
}

=head2 getComponentFilename($component [,$ext [,$lang]])

General purpose method to return an appropriate filename for a specified
component sourcefile depending on the extensions supplied. Both extensions are
optional. The first, if specified, provides a type extension which is normally
't' to indicate a test driver, 'm' to indicate a stand-alone main sourcefile,
or undefined to indicate an implementation file.

If a language extension is supplied it is used to construct the filename
without regard to the filing system, and so the returned filename may or
may not actually exist. If a language extension is not supplied the filing
system is searched for candidate extensions. If no candidates are found, or
more than one candidate is found, an exception is thrown.

I<See also L<BDE::Component> for alternative ways to access filename
information based on the known language type of the component object. This
routine presumes simple component names (not objects) and so will always
search the filing system.>

=cut

sub getComponentFilename ($$;$$) {
    my ($self,$comp,$ext,$lang)=@_;

    $ext = $ext ? (($ext=~/^./)?".$ext":$ext) : "";
    $lang = $lang ? (($lang=~/^./)?".$lang":$lang) : "";

    return undef unless isComponent($comp);
    my $base=$self->getComponentBasepath($comp) . $ext;

    if ($lang) {
	return $base.$lang; #explicit language 
    } else {
	my ($cppfile,$cfile);

	my $found=retry_eitherof("$base.cpp","$base.c");
	$found==3 and $self->throw(
	    "both $base.c and $base.cpp exist for $comp"
        );
	$cppfile = "$base.cpp" if $found==1;
	$cfile = "$base.c" if $found==2;

	$cppfile and $cfile and
	  $self->throw("both $base.c and $base.cpp exist for $comp");
	!$cppfile and !$cfile and
	  $self->throw("cannot find $ext.c or $ext.cpp file for $comp");

	return $cppfile ? $cppfile : $cfile;
    }
}

=head2 getComponentImplFilename($component [,$lang])

Return the implementation filename for the specified component. Looks in the
filesytem to determine the implementation type unless the language extension
is supplied as an optional second argument. This method is a convenience
wrapper for C<getComponentFilename> with C<$ext=undef>.

If a language extension I<is> supplied, a filename is returned without regard
to the filing system (and therefore the file in question may not in fact
physically exist). If I<no> extension is supplied and no physical file exists
for any of the candidate language extensions supported, an exception is thrown.

=head2 getComponentTestFilename($component [,$lang])

Return the test driver filename for the specified component. This method
is a convenience wrapper for C<getComponentFilename> with C<$ext='t'>. It
behaves identically to C<getComponentImplFilename> otherwise.

=head2 getComponentMainFilename($component [,$lang])

Return the standalone main filename for the specified component. This method
is a convenience wrapper for C<getComponentFilename> with C<$ext='m'>. It
behaves identically to C<getComponentImplFilename> otherwise.

=cut

sub getComponentImplFilename { $_[0]->getComponentFilename($_[1],"" ,$_[2]); }
sub getComponentTestFilename { $_[0]->getComponentFilename($_[1],"t",$_[2]); }
sub getComponentMainFilename { $_[0]->getComponentFilename($_[1],"m",$_[2]); }

=head2 getComponentIntfFilename($component)

Return the interface filename for the specified component. Does I<not> search
the filesystem. Currently it returns the component basepath with a C<.h>
extension appended to it.

=cut

sub getComponentIntfFilename($$) {
    my $path=$_[0]->getComponentBasepath($_[1]);
    return undef unless $path;
    return $path.".h";
}

sub getComponentRoot ($$) {
    my ($self,$component)=@_;

    return $self->getPackageRoot($self->getComponentPackage($component));
}

#------------------------------------------------------------------------------
# Filesystem Root

=head2 setRootLocation()

Set the filesystem root for this instance. The filesystem root is the absolute
or relative path to the top of the BDE source directory structure. Typically
the symbol C<ROOT> (which in turn may be set by the environment variable
C<BDE_ROOT>) is used to initialise the default path, but this class does not
currently use or enforce this default itself.

This method is called from the constructor via C<fromString> above, but that
method is guaranteed to always pass C<setRootLocation> an absolute path. Call
this method directly to set a relative path.

Calling this method also has the effect of clearing the package and group
location caches maintained by C<getGroupLocation> and C<getPackageLocation>
when search result caching is enabled.

=cut

sub setRootLocation ($$) {
    my ($self,$path)=@_;
    $self->clearGroupLocationCache();
    $self->clearPackageLocationCache();
    $self->{root}=$path;
}

=head2 getRootLocation()

Return the filesystem root for this instance, as set by L<"setRootLocation">
or L<"fromString">.

=cut

sub getRootLocation ($)  { return $_[0]->{root}; }

=head2 getPath()

Get the current path for this instance.

=head2 setPath($colon_separated_paths)

Set the path for this instance. If no path is set, the default path is derived
from the C<PATH> symbol, which is in turnoveridable by the C<BDE_PATH>
environment variable. (To disable the path, alter the search mode with
L<"setSearchMode">.)

=cut

sub getPath {
    my $path = $_[0]->{path};
    return $path || CONSTANT_PATH;
}

sub setPath         ($$) { $_[0]->{path}=$_[1]; }

=head2 isAbsolute()

Returns true if the filesystem root is an absolute path, false if it is a
relative path. An unset root counts as relative.

=cut

sub isAbsolute {
    my $self = shift;
    return ($self->getRootLocation || '') =~ /^(?:\w:)?$FSRE/;
}

#------------------------------------------------------------------------------
# Base

=head1 CATEGORY METHODS

These methods get the location, and get or set the subdirectory under the
filesystem root, for each of the defined software categories. Each category is
essentially similar, apart from the name of the subdirectory. In addition,
functions and departments are indexed, and include a further index subdirectory
that is automatically appended.

=head2 getBaseLocation()

Return the pathname to the base category directory, as determined by
the filesystem root and the base subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getBaseLocation ($;$) {
    my $self=shift;

    unless ($self->{$BASE_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getBaseSubdir();
	$self->{$BASE_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$BASE_TYPENAME}{root};
}

{
    no warnings 'once';
    *getBasesLocation=\&getBaseLocation;
    *getGroupsLocation=\&getBaseLocation; #legacy, deprecated
}

=head2 getBaseLocations()

In array context, return the list of valid and present base category
directories present under the filesystem root or on the search path.

=cut

sub getBaseLocations() {
    my $self=shift;
    my $subdir=$self->getBaseSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getBasesLocations=\&getBaseLocations;
}

=head2 getBaseSubdir()

Return the current setting for the base subdirectory.

=cut

sub getBaseSubdir ($) {
    my $self=shift;
    $self->setBaseSubdir()
      unless $self->{$BASE_TYPENAME}{subdir};

    return $self->{$BASE_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getBasesSubdir=\&getBaseSubdir;
    *getGroupsSubdir=\&getBaseSubdir; #legacy, deprecated
}

=head2 setBaseSubdir($subdir)

Set the name of the base subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setBaseSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$BASE_TYPENAME}{root};
    $self->{$BASE_TYPENAME}{subdir}=$subdir || GROUPS_DIR;
}

{
    no warnings 'once';
    *setBasesSubdir=\&setBaseSubdir;
    *setGroupsSubdir=\&setBaseSubdir; #legacy, deprecated
}

#------------------------------------------------------------------------------
# Application

=head2 getApplicationLocation()

Return the pathname to the application category directory, as determined by
the filesystem root and the application subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getApplicationLocation ($;$) {
    my $self=shift;

    unless ($self->{$APPLICATION_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getApplicationSubdir();
	$self->{$APPLICATION_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$APPLICATION_TYPENAME}{root};
}

{
    no warnings 'once';
    *getApplicationsLocation=\&getApplicationLocation;
}

=head2 getApplicationLocations()

In array context, return the list of valid and present application category
directories present under the filesystem root or on the search path.

=cut

sub getApplicationLocations() {
    my $self=shift;
    my $subdir=$self->getApplicationSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getApplicationsLocations=\&getApplicationLocations;
}

=head2 getApplicationSubdir()

Return the current setting for the application subdirectory.

=cut

sub getApplicationSubdir ($) {
    my $self=shift;
    $self->setApplicationSubdir()
      unless $self->{$APPLICATION_TYPENAME}{subdir};

    return $self->{$APPLICATION_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getApplicationsSubdir=\&getApplicationSubdir;
}

=head2 setApplicationSubdir($subdir)

Set the name of the application subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setApplicationSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$APPLICATION_TYPENAME}{root};
    $self->{$APPLICATION_TYPENAME}{subdir}=$subdir || APPLICATIONS_DIR;
}

{
    no warnings 'once';
    *setApplicationsSubdir=\&setApplicationSubdir;
}

=head2 getApplicationDepFilename($application)

Return the full pathname of the dependency file for the specified application.

=cut

sub getApplicationDepFilename ($$) {
    my ($self,$application)=@_;

    return undef unless isApplication($application);
    return $self->getApplicationLocation($application).
      $FS.$application.
      $FS.APPLICATION_META_SUBDIR.$FS.basename($application).DEPFILE_EXTENSION;
}

=head2 getApplicationMemFilename($application)

Return the full pathname of the membership file for the specified application.

=cut

sub getApplicationMemFilename ($$) {
    my ($self,$application)=@_;

    return undef unless isApplication($application);
    return $self->getApplicationLocation($application).
      $FS.$application.
      $FS.APPLICATION_META_SUBDIR.$FS.basename($application).MEMFILE_EXTENSION;
}

=head2 getApplicationLckFilename($application)

Return the full pathname of the lock file for the specified application.

=cut

sub getApplicationLckFilename ($$) {
    my ($self,$application)=@_;

    return undef unless isApplication($application);
    return $self->getApplicationLocation($application).
      $FS.$application.
      $FS.APPLICATION_META_SUBDIR.$FS.basename($application).LCKFILE_EXTENSION;
}

#------------------------------------------------------------------------------
# Adapter

=head2 getAdapterLocation()

Return the pathname to the adapter category directory, as determined by
the filesystem root and the adapter subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getAdapterLocation ($;$) {
    my $self=shift;

    unless ($self->{$ADAPTER_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getAdapterSubdir();
	$self->{$ADAPTER_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$ADAPTER_TYPENAME}{root};
}

{
    no warnings 'once';
    *getAdaptersLocation=\&getAdapterLocation;
}

=head2 getAdapterLocations()

In array context, return the list of valid and present adapter category
directories present under the filesystem root or on the search path.

=cut

sub getAdapterLocations() {
    my $self=shift;
    my $subdir=$self->getAdapterSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getAdaptersLocations=\&getAdapterLocations;
}

=head2 getAdapterSubdir()

Return the current setting for the adapter subdirectory.

=cut

sub getAdapterSubdir ($) {
    my $self=shift;
    $self->setAdapterSubdir()
      unless $self->{$ADAPTER_TYPENAME}{subdir};

    return $self->{$ADAPTER_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getAdaptersSubdir=\&getAdapterSubdir;
}

=head2 setAdapterSubdir($subdir)

Set the name of the adapter subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setAdapterSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$ADAPTER_TYPENAME}{root};
    $self->{$ADAPTER_TYPENAME}{subdir}=$subdir || ADAPTERS_DIR;
}

{
    no warnings 'once';
    *setAdaptersSubdir=\&setAdapterSubdir;
}

#------------------------------------------------------------------------------
# Function

=head2 getFunctionLocation()

Return the pathname to the function category directory, as determined by
the filesystem root and the function subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

Functions, a.k.a. I<Biglets>, are an indexed category, so the returned
pathname includes an index subdirectory.

=cut

sub getFunctionLocation ($;$) {
    my $self=shift;

    unless ($self->{$FUNCTION_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getFunctionSubdir();
	$self->{$FUNCTION_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$FUNCTION_TYPENAME}{root};
}

{
    no warnings 'once';
    *getFunctionsLocation=\&getFunctionLocation;
}

=head2 getFunctionLocations()

In array context, return the list of valid and present function category
directories present under the filesystem root or on the search path.

=cut

sub getFunctionLocations() {
    my $self=shift;
    my $subdir=$self->getFunctionSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getFunctionsLocations=\&getFunctionLocations;
}

=head2 getFunctionSubdir()

Return the current setting for the function subdirectory.

=cut

sub getFunctionSubdir ($) {
    my $self=shift;
    $self->setFunctionSubdir()
      unless $self->{$FUNCTION_TYPENAME}{subdir};

    return $self->{$FUNCTION_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getFunctionsSubdir=\&getFunctionSubdir;
}

=head2 setFunctionSubdir($subdir)

Set the name of the function subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed. The index subdirectory is automatically appended.

=cut

sub setFunctionSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$FUNCTION_TYPENAME}{root};
    $self->{$FUNCTION_TYPENAME}{subdir}=$subdir || FUNCTIONS_DIR;
    $self->{$FUNCTION_TYPENAME}{subdir}.=$FS.INDEX_DIR;
}

{
    no warnings 'once';
    *setFunctionsSubdir=\&setFunctionSubdir;
}

#------------------------------------------------------------------------------
# Third-Party

=head2 getThirdPartyLocation()

Return the pathname to the third-party category directory, as determined by
the filesystem root and the third-party subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getThirdPartyLocation ($;$) {
    my $self=shift;

    unless ($self->{$THIRDPARTY_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getThirdPartySubdir();
	$self->{$THIRDPARTY_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$THIRDPARTY_TYPENAME}{root};
}

=head2 getThirdPartyLocations()

In array context, return the list of valid and present third-party category
directories present under the filesystem root or on the search path.

=cut

sub getThirdPartyLocations() {
    my $self=shift;
    my $subdir=$self->getThirdPartySubdir();
    return $self->_genPaths($subdir);
}

=head2 getThirdPartySubdir()

Return the current setting for the third-party subdirectory.

=cut

sub getThirdPartySubdir ($) {
    my $self=shift;
    $self->setThirdPartySubdir()
      unless $self->{$THIRDPARTY_TYPENAME}{subdir};

    return $self->{$THIRDPARTY_TYPENAME}{subdir};
}

=head2 setThirdPartySubdir($subdir)

Set the name of the third-party subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setThirdPartySubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$THIRDPARTY_TYPENAME}{root};
    $self->{$THIRDPARTY_TYPENAME}{subdir}=$subdir || THIRDPARTY_DIR;
}

#------------------------------------------------------------------------------
# Legacy

=head2 getLegacyLocation()

Return the pathname to the legacy category directory, as determined by
the filesystem root and the legacy subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getLegacyLocation ($;$) {
    my $self=shift;

    unless ($self->{$LEGACY_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getLegacySubdir();
	$self->{$LEGACY_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$LEGACY_TYPENAME}{root};
}

=head2 getLegacyLocations()

In array context, return the list of valid and present legacy category
directories present under the filesystem root or on the search path.

=cut

sub getLegacyLocations() {
    my $self=shift;
    my $subdir=$self->getLegacySubdir();
    return $self->_genPaths($subdir);
}

=head2 getLegacySubdir()

Return the current setting for the legacy subdirectory.

=cut

sub getLegacySubdir ($) {
    my $self=shift;
    $self->setLegacySubdir()
      unless $self->{$LEGACY_TYPENAME}{subdir};

    return $self->{$LEGACY_TYPENAME}{subdir};
}

=head2 setLegacySubdir($subdir)

Set the name of the legacy subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setLegacySubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$LEGACY_TYPENAME}{root};
    $self->{$LEGACY_TYPENAME}{subdir}=$subdir || LEGACY_DIR;
}

#------------------------------------------------------------------------------
# Department

=head2 getDepartmentLocation()

Return the pathname to the department category directory, as determined by
the filesystem root and the department subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

Departments, a.k.a. I<Biglets>, are an indexed category, so the returned
pathname includes an index subdirectory.

=cut

sub getDepartmentLocation ($;$) {
    my $self=shift;

    unless ($self->{$DEPARTMENT_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getDepartmentSubdir();
	$self->{$DEPARTMENT_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$DEPARTMENT_TYPENAME}{root};
}

{
    no warnings 'once';
    *getDepartmentsLocation=\&getDepartmentLocation;
}

=head2 getDepartmentLocations()

In array context, return the list of valid and present department category
directories present under the filesystem root or on the search path.

=cut

sub getDepartmentLocations() {
    my $self=shift;
    my $subdir=$self->getDepartmentSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getDepartmentsLocations=\&getDepartmentLocations;
}

=head2 getDepartmentSubdir()

Return the current setting for the department subdirectory.

=cut

sub getDepartmentSubdir ($) {
    my $self=shift;
    $self->setDepartmentSubdir()
      unless $self->{$DEPARTMENT_TYPENAME}{subdir};

    return $self->{$DEPARTMENT_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getDepartmentsSubdir=\&getDepartmentSubdir;
}

=head2 setDepartmentSubdir($subdir)

Set the name of the department subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed. The index subdirectory is automatically appended.

=cut

sub setDepartmentSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$DEPARTMENT_TYPENAME}{root};
    $self->{$DEPARTMENT_TYPENAME}{subdir}=$subdir || DEPARTMENTS_DIR;
    $self->{$DEPARTMENT_TYPENAME}{subdir}.=$FS.INDEX_DIR;
}

{
    no warnings 'once';
    *setDepartmentsSubdir=\&setDepartmentSubdir;
}

#------------------------------------------------------------------------------
# Enterprise

=head2 getEnterpriseLocation()

Return the pathname to the enterprise category directory, as determined by
the filesystem root and the enterprise subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getEnterpriseLocation ($;$) {
    my $self=shift;

    unless ($self->{$ENTERPRISE_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getEnterpriseSubdir();
	$self->{$ENTERPRISE_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$ENTERPRISE_TYPENAME}{root};
}

{
    no warnings 'once';
    *getEnterprisesLocation=\&getEnterpriseLocation;
}

=head2 getEnterpriseLocations()

In array context, return the list of valid and present enterprise category
directories present under the filesystem root or on the search path.

=cut

sub getEnterpriseLocations() {
    my $self=shift;
    my $subdir=$self->getEnterpriseSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getEnterprisesLocations=\&getEnterpriseLocations;
}

=head2 getEnterpriseSubdir()

Return the current setting for the enterprise subdirectory.

=cut

sub getEnterpriseSubdir ($) {
    my $self=shift;
    $self->setEnterpriseSubdir()
      unless $self->{$ENTERPRISE_TYPENAME}{subdir};

    return $self->{$ENTERPRISE_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getEnterprisesSubdir=\&getEnterpriseSubdir;
}

=head2 setEnterpriseSubdir($subdir)

Set the name of the enterprise subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setEnterpriseSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$ENTERPRISE_TYPENAME}{root};
    $self->{$ENTERPRISE_TYPENAME}{subdir}=$subdir || ENTERPRISES_DIR;
}

{
    no warnings 'once';
    *setEnterprisesSubdir=\&setEnterpriseSubdir;
}

#------------------------------------------------------------------------------
# Wrapper

=head2 getWrapperLocation()

Return the pathname to the wrapper category directory, as determined by
the filesystem root and the wrapper subdirectory. If the subdirectory is
not set, the default subdirectory name is used.

=cut

sub getWrapperLocation ($;$) {
    my $self=shift;

    unless ($self->{$WRAPPER_TYPENAME}{root}) {
	my $root=$self->getRootLocation();
	my $subd=$self->getWrapperSubdir();
	$self->{$WRAPPER_TYPENAME}{root}=$root.$FS.$subd;
    }

    return $self->{$WRAPPER_TYPENAME}{root};
}

{
    no warnings 'once';
    *getWrappersLocation=\&getWrapperLocation;
}

=head2 getWrapperLocations()

In array context, return the list of valid and present wrapper category
directories present under the filesystem root or on the search path.

=cut

sub getWrapperLocations() {
    my $self=shift;
    my $subdir=$self->getWrapperSubdir();
    return $self->_genPaths($subdir);
}

{
    no warnings 'once';
    *getWrappersLocations=\&getWrapperLocations;
}

=head2 getWrapperSubdir()

Return the current setting for the wrapper subdirectory.

=cut

sub getWrapperSubdir ($) {
    my $self=shift;
    $self->setWrapperSubdir()
      unless $self->{$WRAPPER_TYPENAME}{subdir};

    return $self->{$WRAPPER_TYPENAME}{subdir};
}

{
    no warnings 'once';
    *getWrappersSubdir=\&getWrapperSubdir;
}

=head2 setWrapperSubdir($subdir)

Set the name of the wrapper subdirectory under the filesystem root. The
subdirectory is reset to the default value if no value or a non-true value
is passed.

=cut

sub setWrapperSubdir ($;$) {
    my ($self,$subdir)=@_;
    delete $self->{$WRAPPER_TYPENAME}{root};
    $self->{$WRAPPER_TYPENAME}{subdir}=$subdir || WRAPPERS_DIR;
}

{
    no warnings 'once';
    *setWrappersSubdir=\&setWrapperSubdir;
}

#------------------------------------------------------------------------------

=head1 CATEGORY TYPE METHODS

These methods provides answers to filesystem questions based on a supplied
numeric type rather through a method named for a specific type (a.k.a.
category. They map to a corresponding category-specific method as described
above according to the numeric category type passed.

=head2 getTypeLocation($type [,$recalc])

Return the category directory location under the local root for the specified
numeric type:

    my $baselocn=$root->getTypeLocation(IS_BASE);

There is no reason to use this method if the category type is known in advance.
It is intended for use where there is a need to retrieve locations for
arbitrary types. An exception is thrown if an illegal type ID is passed.

=cut

# The $recalc parameter is not documented.
sub getTypeLocation ($$) {
    my ($self,$type)=@_;

  SWITCH: foreach ($type) {
	$_==IS_BASE        and return $self->getBaseLocation();
	$_==IS_ADAPTER     and return $self->getAdaptersLocation();
	$_==IS_FUNCTION    and return $self->getFunctionsLocation();
	$_==IS_THIRDPARTY  and return $self->getThirdPartyLocation();
	$_==IS_LEGACY      and return $self->getLegacyLocation();
	$_==IS_APPLICATION and return $self->getApplicationsLocation();
	$_==IS_DEPARTMENT  and return $self->getDepartmentsLocation();
	$_==IS_WRAPPER     and return $self->getWrappersLocation();
	$_==IS_ENTERPRISE  and return $self->getEnterprisesLocation();
    }

    $self->throw("Invalid type $type");
}

=head2 getTypeLocations($type)

Return the category directories under the local root and on the search path
for the specified numeric type.

=cut

sub getTypeLocations ($$) {
    my ($self,$type)=@_;

  SWITCH: foreach ($type) {
	$_==IS_BASE        and return $self->getBaseLocations();
	$_==IS_ADAPTER     and return $self->getAdaptersLocations();
	$_==IS_FUNCTION    and return $self->getFunctionsLocations();
	$_==IS_THIRDPARTY  and return $self->getThirdPartyLocations();
	$_==IS_LEGACY      and return $self->getLegacyLocations();
	$_==IS_APPLICATION and return $self->getApplicationsLocations();
	$_==IS_DEPARTMENT  and return $self->getDepartmentsLocations();
	$_==IS_WRAPPER     and return $self->getWrappersLocations();
	$_==IS_ENTERPRISE  and return $self->getEnterprisesLocations();
    }

    $self->throw("Invalid type $type");
}

=head2 getTypeSubdir($type)

Get the subdirectory name under the root location for the specified type. This
is the same as the directory name returned by C<getTypeDir> unless the
C<setTypeSubdir> method has previously been called.

The appropriate category-specific type method is called to set the subdirectory
as documented above.

=cut

sub getTypeSubdir ($$) {
    my ($self,$type)=@_;
  SWITCH: foreach ($type) {
	$_==IS_BASE        and return $self->getBaseSubdir();
	$_==IS_ADAPTER     and return $self->getAdaptersSubdir();
	$_==IS_FUNCTION    and return $self->getFunctionsSubdir();
	$_==IS_THIRDPARTY  and return $self->getThirdPartySubdir();
	$_==IS_LEGACY      and return $self->getLegacySubdir();
	$_==IS_APPLICATION and return $self->getApplicationsSubdir();
	$_==IS_DEPARTMENT  and return $self->getDepartmentsSubdir();
	$_==IS_WRAPPER     and return $self->getWrappersSubdir();
	$_==IS_ENTERPRISE  and return $self->getEnterprisesSubdir();
    }

    $self->throw("Invalid type $type");
}

=head2 setTypeSubdir($type => $subdir)

Set a new subdirectory name under the root location for the specified type.

    $root->setTypeSubdir(IS_ENTERPRISE => 'corporate');

Indexed category types are I<not> automatically extended to include the index
directory. The L<"isIndexed"> routine and C<INDEX_DIR> symbol may be used to
add the default index subdirectory prior to calling this method, if required.
See also L<"setDepartmentsSubdir"> and L<"setFunctionsSubdir">.

The appropriate category-specific type method is called to set the subdirectory
as documented above.

=cut

sub setTypeSubdir ($$$) {
    my ($self,$type,$subdir)=@_;
  SWITCH: foreach ($type) {
	$_==IS_BASE        and return $self->setGroupsSubdir($subdir);
	$_==IS_ADAPTER     and return $self->setAdaptersSubdir($subdir);
	$_==IS_FUNCTION    and return $self->setFunctionsSubdir($subdir);
	$_==IS_THIRDPARTY  and return $self->setThirdPartySubdir($subdir);
	$_==IS_LEGACY      and return $self->setLegacySubdir($subdir);
	$_==IS_APPLICATION and return $self->setApplicationsSubdir($subdir);
	$_==IS_DEPARTMENT  and return $self->setDepartmentsSubdir($subdir);
	$_==IS_WRAPPER     and return $self->setWrappersSubdir($subdir);
	$_==IS_ENTERPRISE  and return $self->setEnterprisesSubdir($subdir);
    }

    $self->throw("Invalid type $type");
}

#------------------------------------------------------------------------------

=head1 RELATIVE LOCATION METHODS

These methods return relative paths to the requested location, if the
filesystem root is itself relative. If it is absolute, an absolute path is
returned in each case. These routines are typically used in makefile
construction.

Currently all these routines assume that a non-indexed category consists
of a single category subdirertory, and an index category consists of a
catergory subdirectory plus an index subdirectory (i.e. two subdirectories).
This assumption may not however hold true - see below.

=head2 getRootLocationFromType([$type])

Return the location of the filesystem root relative to a unit of release
directory of the specified type. With no type supplied, returns the relative
path from a base group (three levels up).

An optional group name may be specified, in which case the relative path is
adjusted by one additional level if the unit of release is an indexed type.
This assumes one additional level for the index, which may not be true if
one of the C<set*Subdir> methods has been used.

=cut

sub getRootLocationFromType ($;$) {
    my ($self,$type)=@_;

    if ($self->isAbsolute) {
	return $self->getRootLocation();
    } elsif ($type and isIndexedType($type)) {
	return "..${FS}..";
    } else {
	return "..";
    }
}

=head2 getRootLocationFromGroup([$group])

Return the location of the filesystem root relative to a package group. Calls
C<getRootLocationFromType> using the type of the package group passed. See
that method for more information. A base package group is assumed if no
group name is passed.

=cut

sub getRootLocationFromGroup ($;$) {
    my ($self,$group)=@_;

    # this also happens to work for isolated packages but they should
    # really be calling the next method...
    if ($self->isAbsolute) {
	return $self->getRootLocation();
    } else {
	return "..".$FS.
	  $self->getRootLocationFromType($group?(getType $group):undef);
    }
}

=head2 getRootLocationFromPackage([$package]);

Return the location of the filesystem root relative to a package. An
optional package name may be specified, in which case the relative path is
adjusted by one additional C<..> if the package is an indexed package and
reduced by one C<..> if the package is an isolated package. A base grouped
package is assumed if no package name is passed.

=cut

sub getRootLocationFromPackage ($;$) {
    my ($self,$package)=@_;

    if ($self->isAbsolute) {
	return $self->getRootLocation();
    } elsif ($package) {
	if (isIndexed $package) {
	    if (isIsolatedPackage $package) {
		return "..${FS}..${FS}..";
	    } else {
		return "..${FS}..${FS}..${FS}..";
	    }
	} else {
	    if (isIsolatedPackage $package) {
		return "..${FS}..";
	    } else {
		return "..${FS}..${FS}..";
	    }
	}
    } else {
	return "..${FS}..${FS}..";
    }
}

=head2 getRootLocationFromUnit($gop)

Return the location of the filesystem root relative to the supplied group,
grouped package, or isolated package. Calls either C<getRootLocationFromGroup>
or C<getRootLocationFromPackage> as appropriate.

=cut

sub getRootLocationFromGoP ($$) {
    my ($self,$gop)=@_;

    if (isPackage $gop) {
	return $self->getRootLocationFromPackage($gop);
    }
    return $self->getRootLocationFromGroup($gop);
}

=head2 getOtherTypeLocationFromType($fromtype,$totype)

Return the relative path to the category directory for the numeric category
type C<$totype> from the category directory for the numeric category type
C<$fromtype>:

    my $relpath=$root->getOtherTypeLocationFromType(IS_ADAPTER, IS_BASE);

If the I<from> and I<to> types are equal, a direct relative path is returned.
Otherwise, the patch is computed from the relative location of the root,
plus the category subdirectory.

=cut

sub getOtherTypeLocationFromType ($$;$) {
    my ($self,$fromtype,$totype)=@_;
    $totype=$fromtype unless defined $totype;

    if ($self->isAbsolute) {
	return $self->getTypeLocation($totype);
    } else {
	if ($fromtype == $totype) {
	    return ".";
	} else {
	    my $siblingdir=$self->getTypeSubdir($totype);
	    return $self->getRootLocationFromType($fromtype).$FS.$siblingdir;
	}
    }
}

=head2 getTypeLocationFromPackage($group)

Return the location of the category directory relative to the supplied group.

=cut

sub getTypeLocationFromGroup ($$) {
    my ($self,$group)=@_;

    if ($self->isAbsolute) {
	return $self->getGroupLocation($group);
    } else {
	my $type=$group?(getType $group):undef;
	my $path=$self->getOtherTypeLocationFromType($type,$type);
	return ($path eq '.')?"..":"..${FS}$path";
    }
}

=head2 getTypeLocationFromPackage($package)

Return the location of the category directory relative to the supplied package.

=cut

sub getTypeLocationFromPackage ($$) {
    my ($self,$package)=@_;

    if ($self->isAbsolute) {
	return $self->getTypeLocation(getType $package);
    } else {
	my $type=$package?(getType $package):undef;
	my $path=$self->getOtherTypeLocationFromType($type,$type);
	if (isIsolatedPackage $package) {
	    return ($path eq '.')?"..":"..${FS}$path";
	} else {
	    return ($path eq '.')?"..${FS}..":"..${FS}..${FS}$path";
	}
    }
}

=head2 getTypeLocationFromGoP($gop)

Return the location of the category directory relative to the supplied group
or package. Calls either C<getTypeLocationFromGroup> or
C<getTypeLocationFromPackage> as appropriate.

=cut

sub getTypeLocationFromGoP ($$) {
    my ($self,$gop)=@_;

    if (isPackage $gop) {
	return $self->getTypeLocationFromPackage($gop);
    }
    return $self->getTypeLocationFromGroup($gop);
}

# Legacy method
sub getGroupsLocationFromGroup ($) {
    return $_[0]->getOtherTypeLocationFromType(IS_BASE, IS_BASE);
}

=head2 getGopLocationFromGop($from,$to)

Return the relative path of the package or group identified by C<$to> from
the directory of the package or group identified by C<$from>.

=cut

sub getGoPLocationFromGoP ($$;$) {
    my ($self,$fromgop,$togop)=@_;

    if ($self->isAbsolute) {
	if (isGroup $togop) {
	    return $self->getGroupLocation($togop);
	} else {
	    return $self->getPackageLocation($togop);
	}
    }

    # intra-package group
    if ($fromgop eq $togop) {
	return ".";
    } elsif (isGroup($fromgop) and isGroupedPackage($togop)
	     and $self->getPackageGroup($togop) eq $fromgop) {
	return $togop;
    } elsif (isGroup($togop) and isGroupedPackage($fromgop)
	     and $self->getPackageGroup($fromgop) eq $togop) {
	return "..";
    } elsif (isGroupedPackage($fromgop) and isGroupedPackage($togop)
	     and $self->getPackageGroup($fromgop)
	     eq $self->getPackageGroup($togop)) {
	return "..${FS}$togop";
    }

    my $fromtype=getType $fromgop;
    my $totype=getType $togop;

    # get category-to-category path
    my $path=$self->getOtherTypeLocationFromType($fromtype => $totype);

    # adjust 'from category' dir to gop dir
    if (isGroupedPackage $fromgop) {
	$path="..${FS}..${FS}$path";
    } else {
	$path="..${FS}$path";
    }

    # adjust 'to category' dir to gop dir
    if (isGroupedPackage $togop) {
	$path.=$FS.$self->getPackageGroup($togop).$FS.$togop;
    } else {
	$path.=$FS.$togop;
    }

    return $path;
}

#------------------------------------------------------------------------------

=head2 getDepartment($name)

Return the department for the named group, package, or component. Return
C<undef> if the department cannot be determined or departments are not
applicable to the supplied argument.

=cut

sub getDepartment ($$) {
    my ($self,$name)=@_;

    $name=$self->getComponentPackage($name) if isComponent($name);
    $name=$self->getPackageGroup($name) if isGroupedPackage($name);

    return undef unless getType($name) && (IS_DEPARTMENT | IS_FUNCTION);

    my $locn = isGroup($name)
      ? $self->getGroupLocation($name)
      : $self->getPackageLocation($name);

    if (-l $locn) {
	# the department is the parent dir of the true location
	$locn=readlink($locn);
    }
    # else, we are not in an index, assume the true location
    return basename(dirname $locn);
}

#------------------------------------------------------------------------------
# convenience class methods

=head1 NOMENCLATURE METHODS

These methods provide convenient access to nomenclature routines though the
filesystem object.

=head2 getPackageGroup($package)

Return the group for the supplied package. May return C<undef> if the package
does not belong tp a package group (i.e. is isolated).

=head2 getComponentPackage($component)

Return the package for the supplied component.

=head2 getComponentGroup($component)

Return the package group for the supplied component. May return C<undef> if
the component does not belong to a grouped package.

=cut

sub getPackageGroup($$) {
    #Util::Message::fatal "Not a package object" unless ref $_[0];
    Util::Message::fatal("Undefined package") unless defined $_[1];
    return BDE::Util::Nomenclature::getPackageGroup($_[1]);
}

sub getComponentPackage($$) {
    $_[0]->throw("Undefined component") unless defined $_[1];
    return BDE::Util::Nomenclature::getComponentPackage($_[1]);
}

sub getComponentGroup($$) {
    $_[0]->throw("Undefined component") unless defined $_[1];
    return BDE::Util::Nomenclature::getComponentGroup($_[1]);
}

#------------------------------------------------------------------------------

=head1 MISCELLANEOUS METHODS

=head2 toString()

Return the root path, identical to calling L<"getRootLocation">. This is the
method that is called when a filesystem object is evaluated in string context.
It may be overloaded in subclasses to alter stringification behaviour if
desired.

=cut

sub toString($) {
    my $self = shift;
    return $self->getRootLocation || do {
        my ($path) = split /:/, $self->getPath;
        $path;
    };
}

#------------------------------------------------------------------------------

# Portably convert a relative pathname to an absolute one, also converting
# the file system separator character if required.
sub _abs_path ($) {
    my $file=shift;

    $file=Compat::File::Spec->rel2abs($file);

    1 while $file =~ s|/[^/]+/\.\./|/|;
    $file=~s[/][$FS]g if $FS ne '/';

    return $file;
}

sub _genPaths ($) {
    my ($self,$subdir)=@_;

    my $nolocal = $self->getSearchMode();

    my @roots;
    unless ($nolocal & FILESYSTEM_NO_ROOT) {
        push @roots, $self->getRootLocation;
    }
    unless ($nolocal & FILESYSTEM_NO_PATH) {
        push @roots, split ':', $self->getPath;
    }

    my (@paths,%paths);
    foreach (@roots) {
	unless (exists $paths{$_}) {
	    $paths{$_}=1;
	    push @paths,$_;
	}
    }

    if ($subdir) {
	@paths=map { $_.$FS.$subdir } @paths;
    }

    return wantarray ? @paths : \@paths;
}

=head2 getRootLocations()

Return a list of all possible roots, excluding local sandbox directories, but
including the local root and the search path.

=cut

sub getRootLocations ($) {
    return $_[0]->_genPaths(undef);
}

=head2 getEtcLocations()

Return a list of all possible configuration directories (i.e., C<etc>).

=cut

sub getEtcLocations ($) {
    return $_[0]->_genPaths(TOOLS_ETCDIR);
}

#------------------------------------------------------------------------------

sub test {
    eval { use Symbols qw(ROOT); 1; };

    chdir ROOT; #so relative path tests will work

    foreach my $path (ROOT, ".") {
	print "=== Using path='$path' ===\n";
	my $fs=new BDE::FileSystem($path);
	print "New Root (explicit): ",$fs->toString(),"\n";
	print "New Root (toString): $fs\n";
	$fs->setRootLocation($path);
	print "Set Root (toString): $fs\n";

	print "Category locations\n";
	print "  Base           : ",$fs->getBaseLocation(),"\n";
	print "  Applications   : ",$fs->getApplicationsLocation(),"\n";
	print "  Adapters       : ",$fs->getAdaptersLocation(),"\n";
	print "  Functions      : ",$fs->getFunctionsLocation(),"\n";
	print "  Departments    : ",$fs->getDepartmentsLocation(),"\n";
	print "  Wrappers       : ",$fs->getWrappersLocation(),"\n";
	print "  Enterprise     : ",$fs->getEnterprisesLocation(),"\n";
	print "Category subdir\n";
	print "  Get base subdir: ",$fs->getBaseSubdir(),"\n";
	print "  Set base subdir: ",$fs->setBaseSubdir("here"),"\n";
	print "  Get base subdir: ",$fs->getBaseSubdir(),"\n";
	print "  New Base       : ",$fs->getBaseLocation(),"\n";
	print "Membership and dependency files\n";
	print "  Group memfile (foo): ",$fs->getGroupMemFilename("foo"),"\n";
	print "  Group depfile (foo): ",$fs->getGroupDepFilename("foo"),"\n";
	print "  Group depfile (foo): ",$fs->getGroupLckFilename("foo"),"\n";
	print "  Package memfile (foobar): ",
	  $fs->getPackageMemFilename("foobar"),"\n";
	print "  Package depfile (foobar): ",
	  $fs->getPackageDepFilename("foobar"),"\n";
	print "  Package lckfile (foobar): ",
	  $fs->getPackageLckFilename("foobar"),"\n";
	print "  Group memfile (f) should be undef: ",
	  $fs->getGroupMemFilename("f"),"\n";
	print "  Group depfile (f) should be undef: ",
	  $fs->getGroupDepFilename("f"),"\n";
	print "  Group lckfile (f) should be undef: ",
	  $fs->getGroupLckFilename("f"),"\n";
	print "  Package memfile (foo) should be undef ",
	  $fs->getPackageMemFilename("foo"),"\n";
	print "  Package depfile (foo) should be undef: ",
	  $fs->getPackageDepFilename("foo"),"\n";
	print "  Package lckfile (foo): ",
	  $fs->getPackageLckFilename("foo"),"\n";
	print "  Function memfile (f_abcd): ",
	  $fs->getPackageMemFilename("f_abcd"),"\n";
	print "Component paths and filenames\n";
	print "  Component basepath (foobar_baz): ",
	  $fs->getComponentBasepath("foobar_baz"),"\n";
	print "  Component package (foobar_baz): ",
	  $fs->getComponentPackage("foobar_baz"),"\n";
	print "  Component interface (foobar_baz): ",
	  $fs->getComponentIntfFilename("foobar_baz"),"\n";
	print "  Component implementation (foobar_baz): ",
	  $fs->getComponentImplFilename("foobar_baz","cpp"),"\n";
	print "  Component test (foobar_baz): ",
	  $fs->getComponentTestFilename("foobar_baz","cpp"),"\n";
	print "  Component optional main (foobar_baz): ",
	  $fs->getComponentMainFilename("foobar_baz","cpp"),"\n";
	
	# since these components don't actually exist, suppress retry attempts
	print "Non-existent (uninferable) component implementation\n";
	eval {
	    local $Util::Retry::ATTEMPTS = 0;
	    $fs->getComponentImplFilename("foobar_baz");
	} or print "  Unknown/missing component impl (foobar_baz), expected\n";

	print "== Relative path determination ==\n";
	foreach my $u1 (qw[bde bdet l_foo l_foobar a_foobar f_xxfbar]) {
	    print "Root from $u1: ",$fs->getRootLocationFromGoP($u1),"\n";
	    print "Type from $u1: ",$fs->getTypeLocationFromGoP($u1),"\n";
	    foreach my $u2 (qw[bde bdet l_foo l_foobaz a_foobar f_xxgbar]) {
		print sprintf("%25s","$u1 to $u2: "),
		  $fs->getGoPLocationFromGoP($u1,$u2),"\n";
	    }
	}
    }

}

1;

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::FileSystem::Finder>,  L<BDE::FileSystem::MultiFinder>,
L<Build::Option::Finder>, L<BDE::Util::Nomenclature>

=cut
