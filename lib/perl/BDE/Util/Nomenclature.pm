package BDE::Util::Nomenclature;
use strict;

use base 'Exporter';

use Util::Test qw(ASSERT);

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    isGroup
    isPackage
    isComponent
    isSubordinateComponent
    isComponentHeader
    isBase
    isAdapter
    isApplication
    isApplicationMain
    isFunction
    isFunctionEntry
    isWrapper
    isEnterprise
    isIsolatedWrapper
    isGroupedWrapper
    isWrappedGroup
    isDepartment
    isCompliant
    isNonCompliant
    isIndexed
    isIndexedType
    getPackageGroup
    getComponentPackage
    getComponentGroup
    getGroupType
    getPackageType
    isIsolatedPackage
    isGroupedPackage
    getComponentType
    getType
    getTypeName
    getTypeFromName
    getTypeDir
    getFullTypeDir
    getTypeFromDir
    getAllTypes
    getAllTypeNames
    getAllTypeDirs
    isValidDependency
    isTest
    isLegacy
    getFullLegacyName
    getShortLegacyName
    getLegacyLeafPath
    isThirdParty
    getFullThirdPartyName
    getShortThirdPartyName
    getThirdPartyLeafPath
    isUntaggedApplication
    getFullUntaggedApplicationName
    getShortUntaggedApplicationName
    getApplicationLeafPath
    isNonCompliantUOR
    getCanonicalUOR
    getSubdirsRelativeToUOR
    getRootRelativePath
    getRootRelativeUOR
    getRootDevEnvUOR
    isUORsegment
];

use Util::Message qw(fatal);
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::RuntimeFlags qw(getNoMetaMode);
use Symbols qw[
    IS_BASE        BASE_TYPENAME        GROUPS_DIR
    IS_ADAPTER     ADAPTER_TYPENAME     ADAPTERS_DIR
    IS_FUNCTION    FUNCTION_TYPENAME    FUNCTIONS_DIR
    IS_APPLICATION APPLICATION_TYPENAME APPLICATIONS_DIR
    IS_DEPARTMENT  DEPARTMENT_TYPENAME  DEPARTMENTS_DIR
    IS_WRAPPER     WRAPPER_TYPENAME     WRAPPERS_DIR
    IS_ENTERPRISE  ENTERPRISE_TYPENAME  ENTERPRISES_DIR
    IS_THIRDPARTY  THIRDPARTY_TYPENAME  THIRDPARTY_DIR    THIRDPARTY_SUPPORT
    IS_LEGACY      LEGACY_TYPENAME      LEGACY_DIR        LEGACY_SUPPORT
    CONSTANT_PATH  INDEX_DIR            ENABLED
    PACKAGE_META_SUBDIR GROUP_META_SUBDIR
    FILESYSTEM_NO_ROOT FILESYSTEM_NO_PATH
];

# Primitive elements of regexps

my $PFX    = "(?:a_[el]_|z_[ap]_|z_a_[el]_|z_[el]_|[afmpszel]_)?";
my $GRPPFX = "(?:z_[el]_|[elz]_)?";
my $PKGPFX = "(?:a_[el]_|z_[ap]_|z_a_[el]_|[afmpsz]_)";
# valid prefixes.

my $LTR    = "[a-z]";      # a 'letter'
my $LTRNUM = "[a-z0-9]";   # letter or number
my $NCCHR  = "[~+]";       # valid 'nc' markers
my $PKGLN  = "{3,7}";      # package length range, -1 (i.e. {3,9} means 4-10)

#==============================================================================

=head1 NAME

BDE::Util::Nomenclature - identification and verification of names

=head1 SYNOPSIS

  use BDE::Util::Nomenclature qw(isPackage getPackageGroup);

  my $package="foobar";
  my $is_package=isPackage($package);
  my $group=getPackageGroup($package);

=head1 DESCRIPTION

This module provides utility functions that evaluate the validity of a name as
a group, package, component, compliant package, or non-compliant package. It
also understands the difference between the different categories of software
and how to discriminate between them. Finally, it possesses the base knowlege
of allowable dependencies between software categories, based purely on their
name.

This module is the core repository of all knowledge concerning names and
should always be used by any code that requires the answer to any question of
this kind.

=cut

#==============================================================================
# Level determination

=head2 isGroup($group)

Return true if the supplied name is a valid group name, or false otherwise.

=cut

sub isGroup ($) {
    return (defined $_[0]
	    ? $_[0]=~/^${GRPPFX}${LTR}${LTRNUM}{2}$/o && !_legacy_lookup($_[0])
	    : fatal "Undefined group");
}

=head2 isPackage($package)

Return true if the supplied name is a valid package name, or false otherwise.

=cut

{ my %packageCache;

  sub isPackage($) {
      fatal "Undefined package" unless defined $_[0];

      return $packageCache{$_[0]} if exists $packageCache{$_[0]};

      return ($packageCache{$_[0]}=0) if isGroup($_[0]);

      ## seed legacy, third-party, and untagged-app cache
      if (_legacy_lookup($_[0])) {
          # application (pseudopackage) without m_ prefix
          return ($packageCache{$_[0]}=7) if isUntaggedApplication($_[0]);
          # third-party package
          return ($packageCache{$_[0]}=6) if isThirdParty($_[0]);
          # legacy package
          return ($packageCache{$_[0]}=5) if isLegacy($_[0]);
      }
      # application (pseudopackage) (not just apps, includes a_xxx, p_xxx, ...)
      # (f_xx is technically invalid, but not worth being pedantic about)
      return ($packageCache{$_[0]}=4) if $_[0] =~ /^${PKGPFX}${LTR}${LTRNUM}+$/o;
      # compliant package
      return ($packageCache{$_[0]}=1) if $_[0] =~ /^${PFX}${LTR}${LTRNUM}${PKGLN}$/;
      # compatibility package (compliant)
      return ($packageCache{$_[0]}=2) if $_[0] =~
        /^${PFX}${LTR}${LTRNUM}{2}=${LTRNUM}${LTRNUM}*$/o;
      # non-compliant package
      return ($packageCache{$_[0]}=3) if $_[0] =~
        /^${PFX}${LTR}${LTRNUM}{2}${NCCHR}${LTRNUM}${LTRNUM}*$/o;
      # not a package at all
      return ($packageCache{$_[0]}=0);
  }
}

=head2 isComponent($component)

Return true if the supplied name is a valid component name, or false otherwise.

=cut

sub isComponent ($) {
    fatal "Undefined component" unless defined $_[0];
    ##<<<TODO: add support for components of untagged (no m_*) applications
    # subbordinate component
    return 5 if $_[0] =~
      /^${PFX}${LTR}${LTRNUM}${PKGLN}_${LTR}${LTRNUM}*_${LTR}${LTRNUM}*$/o;
    # application/adapter component - name must be at least 2 long, no max
    return 4 if $_[0] =~
      /^${PFX}${LTR}${LTRNUM}+_${LTR}${LTRNUM}*(_${LTR}${LTRNUM}*)?$/o
	&& $_[0] =~ /^[apm]_/; # a_ p_ m_
    # compliant component
    return 1 if $_[0] =~
      /^${PFX}${LTR}${LTRNUM}${PKGLN}_${LTR}${LTRNUM}*(_${LTR}${LTRNUM}*)*$/o;
    # compatibility component (compliant)
    return 2 if $_[0] =~
      /^${PFX}${LTR}${LTRNUM}{2}=${LTRNUM}${LTRNUM}*_${LTR}${LTRNUM}*(_${LTR}${LTRNUM}*)*$/o;
    # non-compliant component
    return 3 if $_[0] =~
      /^${PFX}${LTR}${LTRNUM}{2}${NCCHR}${LTRNUM}${LTRNUM}*_${LTR}${LTRNUM}*(_${LTR}${LTRNUM}*)*$/o;
    # not a package at all
    return 0;
}

=head2 isSubordinateComponent($component)

Return true if the supplied name is a valid subordinate component name, or false otherwise.

=cut

sub isSubordinateComponent ($) {
    return isComponent($_[0]) == 5;
}

=head2 isComponentHeader($header)

A specialisation of L<"isComponent">, strip a C<.h> or C<.hpp> extension from
the supplied filename, if present, and then pass the result to
L<"isComponent">.

=cut

sub isComponentHeader ($) {
    my $file=shift;
    return 0 unless $file=~s/\.(h|hpp|inc)$//;
    return isComponent($file);
}

#------------------------------------------------------------------------------
# Species determination

#TODO: Revisit precise nature of these regexs. They should match a component,
#package or group name so that we can say things like:
# if (isComponent($foo) and isFuncton($foo)) { #it's a function component...
#note that Adapters, Applications and Functions don't have groups.

=head2 isBase($base)

Return true of the supplied name is a valid base name, or false otherwise.

=cut

sub isBase ($) {
    fatal "Undefined base" unless defined $_[0];
    return 1 if $_[0] =~ /^${LTR}${LTRNUM}{2}${LTRNUM}?/;
}

=head2 isAdapter($adapter)

Return true if the supplied name is a valid adapter name (a_) or a valid
isolated package name (p_), or false otherwise.

=cut

sub isAdapter ($) {
    fatal "Undefined adapter" unless defined $_[0];
    return 1 if $_[0] =~ /^${PFX}${LTR}${LTRNUM}+/ #check valid prefix
      and $_[0]=~/^[ap]_/; #...but only the adapters qualify
    return 0;
}

=head2 isApplication($application)

Return true if the supplied name is a valid application name, or false
otherwise.

=cut

sub isApplication ($) {
    fatal "Undefined application" unless defined $_[0];
    return 1 if $_[0] =~ /^m_${LTR}(?:${LTRNUM}|$)/;
    return 1 if isUntaggedApplication($_[0]);
    return 0;
}

=head2 isFunction($function)

Return true if the supplied name is a valid function name (f_) or a valid
baslet (s_), or false otherwise.

=cut

sub isFunction($) {
    fatal "Undefined function" unless defined $_[0];
    return 1 if $_[0] =~ /^[fs]_${LTR}${LTRNUM}+/; # f_ s_
    return 0;
}

=head2 isFunctionEntry($entry)

Return true if the supplied name is a valid function entry name, or false
otherwise.

=cut

sub isFunctionEntry ($) {
    fatal "Undefined function" unless defined $_[0];
    return 1 if $_[0] =~ /^[fs]_${LTR}${LTRNUM}+_entry/; # f_ s_
    return 0;
}

=head2 isWrapper($wrapper)

Return true if the supplied name is a valid wrapper name, or false otherwise.

=cut

sub isWrapper ($) {
    fatal "Undefined wrapper" unless defined $_[0];
    return 1 if $_[0] =~ /^${PFX}${LTR}${LTRNUM}+/ #check valid prefix
      and $_[0]=~/^z_/; #...but only the wrappers qualify
    return 0;
}

=head2 isIsolatedWrapper($wrapper)

Returns true if the supplied name is a valid wrapper name for an isolated
package wrapper (i.e. a 'z_a_' wrapper or similar), or false otherwise.

=cut

sub isIsolatedWrapper ($) {
    fatal "Undefined wrapper" unless defined $_[0];
    $_[0] =~ /^z_(.*)$/;
    my $wrapped=$1;
    return isIsolatedPackage($wrapped);
}

=head2 isGroupedWrapper($wrapper)

Returns true if the supplied name is a valid wrapper name for a grouped
package wrapper I<or> a group wrapper, or false otherwise.

=cut

sub isGroupedWrapper ($) {
    fatal "Undefined wrapper" unless defined $_[0];
    $_[0] =~ /^z_(.*)$/;
    my $wrapped=$1;
    return isGroupedPackage($wrapped) || isGroup($wrapped);
}

=head2 isDepartment($department)

Return true if the supplied name is a valid department name, or false
otherwise. In this context 'department' means an application library with
relaxed rules, as opposed to a 'BDE-level' base library.

=cut

sub isDepartment($) {
    fatal "Undefined department" unless defined $_[0];
    return 1 if $_[0] =~ /^l_${LTR}${LTRNUM}+/;
    return 0;
}


=head2 isEnterprise($enterprise)

Return true if the supplied name is a valid enterprise name, or false
otherwise.

=cut

sub isEnterprise($) {
    fatal "Undefined enterprise" unless defined $_[0];
    return 1 if $_[0] =~ /^e_${LTR}${LTRNUM}+/;
    return 0;
}

#------------------------------------------------------------------------------

=head2 isApplicationMain($filename)

Return true if the supplied name is a valid application main filename, or
false otherwise.

=cut

sub isApplicationMain ($) {
    fatal "Undefined application main" unless defined $_[0];
    return 0 if !isApplication($_[0]);
    return 0 if $_[0] !~ /\.m\.(cpp|c)/;
    return 1;
}

=head2 isTest($filename)

Return true if the supplied name is a valid test name, or false otherwise.

=cut

sub isTest ($) {
    fatal "Undefined test" unless defined $_[0];
    return 1 if $_[0] =~ /\.t\.(cpp|c)/;
    return 0;
}

#------------------------------------------------------------------------------
# BDE compliance

=head2 isNonCompliant($package)

Return 1 if the supplied package name is non-compliant, indicating a
pseudo-package rather than a BDE-conformant package. Return 0 if
the package name indicates a standard package or is not a package name.

=cut

sub isNonCompliant ($) {
    return !isCompliant($_[0]);
}

=head2 isCompliant($package)

Return 1 if the supplied package name is compliant, indicating a
BDE-conformant package rather than a pseudo-package. Return 0 if
the package name indicates a pseudo-package or is not a package name.

=cut

sub isCompliant ($)    {
    fatal "Undefined package" unless defined $_[0];
    return 1 if $_[0] eq "blpapi";
    my $package_type=isPackage($_[0]);
    return 1 if $package_type != 3 and $package_type != 5
	    and $package_type != 6 and $package_type != 7;
    return 0;
}

#------------------------------------------------------------------------------
# Indexed classes

=head2 isIndexed($package)

Return 1 if the supplied name or numerical type is an indexed entity (i.e
located in a subdirectory of the main class directory and linked across to 
from an 'index' directory). Return 0 if the supplied name indicates a
non-indexed class. See C<isIndexedType>.

=cut

sub isIndexed($) {
    my $type=shift;

    $type=getType($type) if $type=~/\D/;

    return isIndexedType($type);
}

=head2 isIndexedType($package)

Return 1 if the supplied numerical type is an indexed entity. Return 0 if the
supplied name indicates a non-indexed class.

=cut

sub isIndexedType($) {
    my $type=shift;


    return undef unless $type;
    return 1 if $type==IS_DEPARTMENT or $type==IS_FUNCTION;
    return 0;
}

#------------------------------------------------------------------------------
# Derivation

=head2 getPackageGroup($package)

Return the three-letter group name from the supplied package name, or C<undef>
if the supplied name is not a valid package name.

=cut

{ my %gpg_Cache;

  sub getPackageGroup ($) {
      my $package=shift;

      fatal "Undefined package" unless defined $package;

      if(exists $gpg_Cache{$package}) {
          return $gpg_Cache{$package};
      }

      unless(isPackage($package)) {
          $gpg_Cache{$package}=undef;
          return undef;
      }

      # unused?  Comment out for now
      #my $pkgtype=getPackageType($package);
      if(isIsolatedPackage($package)) {
          $gpg_Cache{$package}=undef;
          return undef;
      }

      if($package=~/^(${GRPPFX}${LTR}${LTRNUM}{2})/o) {
          $gpg_Cache{$package}=$1;
          return $1;
      }

      $gpg_Cache{$package}=undef;
      return undef; #should never reach here
  }
}

=head2 getComponentPackage($package)

Return the three-letter group name from the supplied package name, or C<undef>
if the supplied name is not a valid component name.

=cut

sub getComponentPackage ($) {
    fatal "Undefined component" unless defined $_[0];
    return "blpapi" if substr($_[0], 0, 6) eq "blpapi";
    return undef unless isComponent($_[0]);
    $_[0]=~/^(${PFX}[^_]+)/ and return $1;
    return undef; #should never reach here
}

=head2 getComponentGroup($package)

Return the three-letter group name from the supplied package name, or C<undef>
if the supplied name is not a valid component name.

=cut

sub getComponentGroup ($) {
    my $component=shift;

    fatal "Undefined component" unless defined $component;
    return undef unless isComponent($component);
    my $package=getComponentPackage($component);
    return undef if isIsolatedPackage($package);
    $component=~/^(${GRPPFX}${LTR}${LTRNUM}{2})/o and return $1;

    return undef; #should never reach here
}

#------------------------------------------------------------------------------
# Identification


=head2 getGroupType($group)

Return the numeric code corresponding to the type of group supplied:
base, departmental, wrapper. Returns undef if the supplied name is not a
valid package name.

=cut

sub getGroupType ($) {
    my $group=shift;

    return undef unless isGroup($group);

    return IS_BASE if $group!~/^${LTR}_/;
    my $prefix=substr $group,0,1;

    SWITCH: foreach ($prefix) { # z_ l_ e_
	/z/ and return IS_WRAPPER;
	/l/ and return IS_DEPARTMENT;
        /e/ and return IS_ENTERPRISE;
    }

    fatal("Unimplemented group type $group");
    return undef;
}

=head2 getPackageType($package)

Return the numeric code corresponding to the type of package supplied:
base, departmental, wrapper, adapter, function or application. Returns undef
if the supplied name is not a valid package name.

=cut

sub getPackageType ($) {
    my $package=shift;

    return undef unless isPackage($package);

    ## (isLegacy, isThirdParty, isUntaggedApplication must be after isPackage)
    return IS_LEGACY if isLegacy($package);
    return IS_THIRDPARTY if isThirdParty($package);
    return IS_APPLICATION if isUntaggedApplication($package);

    return IS_BASE if $package!~/^${LTR}_/;
    my $prefix=substr $package,0,1;

    SWITCH: foreach ($prefix) { # a_ p_ m_ z_ l_ f_ s_ e_
	/a/ and return IS_ADAPTER;
	/p/ and return IS_ADAPTER;
	/m/ and return IS_APPLICATION;
	/z/ and return IS_WRAPPER;
	/l/ and return IS_DEPARTMENT;
	/f/ and return IS_FUNCTION;
	/s/ and return IS_FUNCTION;
        /e/ and return IS_ENTERPRISE;
    }

    fatal("Unimplemented package type $package");
    return undef;
}

=head2 isIsolatedPackage($package)

Return true if the supplied package name is an isolated package (that is, it
does not reside in a package group. Return false if the supplied package name
is a grouped package and undef if the supplied argument is not a package.

=cut

sub isIsolatedPackage ($) {
    my $package=shift;

    return undef unless isPackage($package);

    my $pkgtype=getPackageType($package);
    return 1 if $pkgtype==IS_APPLICATION or
      $pkgtype==IS_FUNCTION or $pkgtype==IS_ADAPTER or
      $pkgtype==IS_LEGACY   or $pkgtype==IS_THIRDPARTY
	or ($pkgtype==IS_WRAPPER                       #remove z_ from $package
	    and &isIsolatedPackage(substr("".$package,2)) #suppress prototype here
	   );

    return 0;
}

=head2 isGroupedPackage($package)

Return true if the supplied package name is a grouped package, false if the
supplied package name is an isolated package, and undef if the supplied
argument is not a package.

=cut

sub isGroupedPackage ($) {
    my $package=shift;

    my $is_isolated=isIsolatedPackage($package);
    return undef unless defined $is_isolated;
    return $is_isolated ? 0 : 1;
}

=head2 getComponentType($component)

Return the numeric code corresponding to the type of package to which the
supplied component belongs. See L<"getPackageType"> for more information.

=cut

sub getComponentType ($) {
    my $component=shift;

    return undef unless isComponent($component);

    my $package=getComponentPackage($component);
    return getPackageType($package);
}

=head2 getType($grouporpackageorcomponent)

Return the numeric code corresponding to the type of group, package, or
component supplied. See L<"getPackageType"> for more information.

=cut

sub getType ($) {
    my $item=shift;

    return getGroupType($item)
      || getPackageType($item)
	|| getComponentType($item);
}

=head2 getTypeName($type)

Return the textual type name for the specified numeric type.

=head2 getTypeFromName($typename)

Return the numeric type of the specified textual type name.

=head2 getTypeDir($type)

Return the type subdirectory for the specifified numeric type.

=head2 getFullTypeDir($type)

Returns the full type subdirectory for the specified numeric type. This differs from
L<"getTypeDir($type)"> in that it will check that the type is indexed, in which case 
the subdirectory has an additional C<index/> component.

=head2 getTypeFromDir($dirname)

Return the numeric type of the specified type subdirectory.

=head2 getAllTypes()

Return a list of all known numeric types.

=head2 getAllTypeNames()

Return a list of all known textual type names.

=head2 getAllTypeDirs()

Return a list of all known type subdirectory names.

=cut

{ my %types=(
    IS_BASE()        => BASE_TYPENAME(),
    IS_ADAPTER()     => ADAPTER_TYPENAME(),
    IS_FUNCTION()    => FUNCTION_TYPENAME(),
    IS_APPLICATION() => APPLICATION_TYPENAME(),
    IS_DEPARTMENT()  => DEPARTMENT_TYPENAME(),
    IS_WRAPPER()     => WRAPPER_TYPENAME(),
    IS_ENTERPRISE()  => ENTERPRISE_TYPENAME(),
    IS_THIRDPARTY()  => THIRDPARTY_TYPENAME(),
    IS_LEGACY()      => LEGACY_TYPENAME(),
  );
  my %typenames = reverse %types; #reverse-map a hash

  sub getTypeName ($) {
      if (exists $types{$_[0]}) {
	  return $types{$_[0]};
      }

      return undef;
  }

  sub getTypeFromName ($) {
      if (exists $typenames{$_[0]}) {
	  return $typenames{$_[0]};
      }

      return undef;
  }

  sub getAllTypes ()     { return sort keys %types; }
  sub getAllTypeNames () { return sort keys %typenames; }
}

{ my %dirs=(
    IS_BASE()        => GROUPS_DIR(),
    IS_ADAPTER()     => ADAPTERS_DIR(),
    IS_FUNCTION()    => FUNCTIONS_DIR(),
    IS_APPLICATION() => APPLICATIONS_DIR(),
    IS_DEPARTMENT()  => DEPARTMENTS_DIR(),
    IS_WRAPPER()     => WRAPPERS_DIR(),
    IS_ENTERPRISE()  => ENTERPRISES_DIR(),
    IS_THIRDPARTY()  => THIRDPARTY_DIR(),
    IS_LEGACY()      => LEGACY_DIR(),
  );
  my %dirnames = reverse %dirs; # reverse-map a hash

  sub getTypeDir ($) {
      if (exists $dirs{$_[0]}) {
	  return $dirs{$_[0]};
      }

      return undef;
  }

  sub getFullTypeDir ($) {
      my $type = shift;
      my $dir = getTypeDir($type);
      $dir .= $FS.INDEX_DIR if isIndexed($type);
      return $dir;
  }

  # this subroutine is somewhat questionable...
  sub getTypeFromDir ($) {
      if (exists $dirnames{$_[0]}) {
	  return $dirnames{$_[0]};
      }

      return undef;
  }

  sub getAllTypeDirs () { return sort keys %dirnames; }
}

#------------------------------------------------------------------------------
# Type dependency checks

=head2 isValidDependency($GPC1, $GPC2)

Determine if $GPC1 can depend on $GPC2, where I<GPC> denotes a group,
package or component name.  We perform the check in terms of the seven
categories described in the I<Bloomberg Enterprise Software Architecture>,
i.e., we determine if the category to which $GPC1 belongs can depend
on that of $GPC2.

If the dependency is allowed the subroutine returns 1 or 2, otherwise it
returns 0.  If $GPC1 and/or $GPC2 is not a valid group, package or
component name, or it is not found to belong to one of the categories,
then 'undef' is returned.

Note that dependencies are checked at the 'logical' level, whereas the
client might also need to consider the I<physical> rules in place, e.g.,
applications can depend only on department libraries within the same
business unit.  Such checks are beyond the scope of this subroutine.
However, in this case the return code is 2.

The following matrix demonstrates these dependencies via the possible
return values ('u' denotes 'undef').

  b      =  core library
  l_     =  department library
  e_     =  enterprise library
  f_     =  function (also s_, baslet)
  a_     =  adapter/isolated package (also p_)
  z_     =  wrapper
  m_     =  application
  X      =  other

                                 $GPC2

  $GPC1         b     e_    l_   f/s_  a/p_   z_    m_    X
             +-----+-----+-----+-----+-----+-----+-----+-----+
   b         |  1  |  1  |  1  |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   e_        |  1  |  1  |  1  |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   l_        |  1  |  1  |  1* |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   f_        |  1  |  1  |  1* |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   a_        |  1  |  1  |  1  |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   z_        |  1  |  1  |  1  |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   m_        |  1  |  1  |  1  |  0  |  1  |  0  |  0  |  1  |
             +-----+-----+-----+-----+-----+-----+-----+-----+
   X         |  u  |  u  |  u  |  u  |  u  |  u  |  u  |  u  |
             +-----+-----+-----+-----+-----+-----+-----+-----+

* - valid if $GPC2 is in $GPC1 - separate return code is used

=cut

sub isValidDependency($$;$) {
    my $GPC1 = shift;
    my $GPC2 = shift;

    return 1 if getNoMetaMode();
    return if !defined($GPC1) or !defined($GPC2) or $GPC1 eq "" or $GPC2 eq "";

    # check if components are in same package which is always ok
    return 1 if isComponent($GPC1) and isComponent($GPC2) and
        getComponentPackage($GPC1) eq getComponentPackage($GPC2);

    # getType relies on get<GPC>Type, which in turn performs is<GPC> - so
    # no need to do these tests separately.
    my $type1 = getType($GPC1);
    my $type2 = getType($GPC2);

    # unknown type
    return 0 if !$type1;   # unknown type for "depender" is error
    return 1 if !$type2; # unknown type for "dependee" is assumed to be ok

    return 1 if $type2 eq IS_BASE or 
      $type2 eq IS_ENTERPRISE or 
        $type2 eq IS_ADAPTER;

    return 1 if $type2 eq IS_DEPARTMENT and
      ($type1 eq IS_BASE       or
       $type1 eq IS_ENTERPRISE or
       $type1 eq IS_ADAPTER    or
       $type1 eq IS_WRAPPER    or
       $type1 eq IS_APPLICATION);

    return 2 if $type2 eq IS_DEPARTMENT and
      ($type1 eq IS_DEPARTMENT or
       $type1 eq IS_FUNCTION);

    return 0 if $type2 eq IS_FUNCTION or 
      $type2 eq IS_WRAPPER or 
        $type2 eq IS_APPLICATION;

    if ($type1 eq IS_WRAPPER) {
        my $t = $GPC1;
        $t =~ s/^z_//;
        return 1 if $t eq $GPC2;
        return 0;
    }
}

#==============================================================================

sub testIsValidDependency() {

my @DATA = (

#             <------------- INPUT -------------->  <---- OUTPUT ---->
#    line           name1             name2           rc1       rc2
#===========  =================  =================  ========  ========

#{a=>__LINE__, b=>            "", c=>            "", d=>undef, e=>undef   },
#{a=>__LINE__, b=>           "x", c=>            "", d=>undef, e=>undef   },
#{a=>__LINE__, b=>           "x", c=>           "x", d=>undef, e=>undef   },

# base -> other, base, e_, l_, f_, a_, z_, m_

{a=>__LINE__, b=>         "bde", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>        "bdes", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>   "bdes_test", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>         "bde", c=>         "bde", d=>1,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>        "bdes", d=>1,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>   "bdes_test", d=>1,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>        "bdes", d=>1,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>   "bdes_test", d=>1,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>   "bdes_test", d=>1,     e=>1       },

{a=>__LINE__, b=>         "bde", c=>       "e_aaa", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>     "e_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>"e_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>       "e_aaa", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>     "e_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>"e_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>       "e_aaa", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>     "e_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>"e_aaabb_cccc", d=>0,     e=>1       },

{a=>__LINE__, b=>         "bde", c=>       "l_aaa", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>     "l_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>"l_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>       "l_aaa", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>     "l_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>"l_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>       "l_aaa", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>     "l_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>"l_aaabb_cccc", d=>0,     e=>1       },

{a=>__LINE__, b=>         "bde", c=>     "f_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>"f_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>     "f_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>"f_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>     "f_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>"f_aaabb_cccc", d=>0,     e=>1       },

{a=>__LINE__, b=>         "bde", c=>     "a_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>"a_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>     "a_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>"a_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>     "a_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>"a_aaabb_cccc", d=>0,     e=>1       },

{a=>__LINE__, b=>         "bde", c=>       "z_bde", d=>0,     e=>0       },
{a=>__LINE__, b=>         "bde", c=>     "z_bdema", d=>0,     e=>0       },
{a=>__LINE__, b=>         "bde", c=>"z_bdema_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>        "bdes", c=>       "z_bde", d=>0,     e=>0       },
{a=>__LINE__, b=>        "bdes", c=>     "z_bdema", d=>0,     e=>0       },
{a=>__LINE__, b=>        "bdes", c=>"z_bdema_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>   "bdes_test", c=>       "z_bde", d=>0,     e=>0       },
{a=>__LINE__, b=>   "bdes_test", c=>     "z_bdema", d=>0,     e=>0       },
{a=>__LINE__, b=>   "bdes_test", c=>"z_bdema_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>         "bde", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>         "bde", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>        "bdes", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>   "bdes_test", c=>"m_aaabb_cccc", d=>0,     e=>1       },

# e_ -> other, l_, f_, a_, z_, m_

{a=>__LINE__, b=>       "e_aaa", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>     "e_aaabb", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>       "e_aaa", c=>       "e_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>     "e_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>"e_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>       "e_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>     "e_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>"e_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>       "e_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>     "e_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>"e_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "e_aaa", c=>       "l_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>     "l_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>"l_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>       "l_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>     "l_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>"l_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>       "l_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>     "l_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>"l_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "e_aaa", c=>     "f_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>"f_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>     "f_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>"f_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>     "f_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>"f_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "e_aaa", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>"a_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>"a_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>"a_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "e_aaa", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "e_aaa", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "e_aaabb", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>"z_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "e_aaa", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>       "e_aaa", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>     "e_aaabb", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>     "e_aaabb", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>"e_aaabb_cccc", c=>"m_aaabb_cccc", d=>0,     e=>1       },

# l_ -> other, l_, f_, a_, z_, m_

{a=>__LINE__, b=>       "l_aaa", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>     "l_aaabb", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>       "l_aaa", c=>     "l_aaabb", d=>1,     e=>1       },
{a=>__LINE__, b=>       "l_aaa", c=>"l_aaabb_cccc", d=>1,     e=>1       },
{a=>__LINE__, b=>     "l_aaabb", c=>     "l_aaabb", d=>1,     e=>1       },
{a=>__LINE__, b=>     "l_aaabb", c=>"l_aaabb_cccc", d=>1,     e=>1       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>     "l_aaabb", d=>1,     e=>1       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>"l_aaabb_cccc", d=>1,     e=>1       },

{a=>__LINE__, b=>       "l_aaa", c=>     "f_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>       "l_aaa", c=>"f_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>     "l_aaabb", c=>     "f_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>     "l_aaabb", c=>"f_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>     "f_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>"f_aaabb_cccc", d=>0,     e=>1       },

{a=>__LINE__, b=>       "l_aaa", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "l_aaa", c=>"a_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "l_aaabb", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "l_aaabb", c=>"a_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>"a_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "l_aaa", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>       "l_aaa", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "l_aaa", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "l_aaabb", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>     "l_aaabb", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "l_aaabb", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>"z_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "l_aaa", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>       "l_aaa", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>     "l_aaabb", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>     "l_aaabb", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>"l_aaabb_cccc", c=>"m_aaabb_cccc", d=>0,     e=>1       },

# f_ -> other, f_, a_, z_, m_

{a=>__LINE__, b=>     "f_aaabb", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>     "f_aaabb", c=>     "f_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "f_aaabb", c=>"f_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>     "f_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>"f_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>     "f_aaabb", c=>     "a_aaabb", d=>1,     e=>0       },
{a=>__LINE__, b=>     "f_aaabb", c=>"a_aaabb_cccc", d=>1,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>     "a_aaabb", d=>1,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>"a_aaabb_cccc", d=>1,     e=>0       },

{a=>__LINE__, b=>     "f_aaabb", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>     "f_aaabb", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "f_aaabb", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>"z_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>     "f_aaabb", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "f_aaabb", c=>"m_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"f_aaabb_cccc", c=>"m_aaabb_cccc", d=>0,     e=>0       },

# a_ -> other,  a_, z_, m_

{a=>__LINE__, b=>     "a_aaabb", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>     "a_aaabb", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "a_aaabb", c=>"a_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>     "a_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>"a_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>     "a_aaabb", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>     "a_aaabb", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "a_aaabb", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>       "z_aaa", d=>0,     e=>0       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>"z_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>     "a_aaabb", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>     "a_aaabb", c=>"m_aaabb_cccc", d=>0,     e=>1       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>     "m_aaabb", d=>0,     e=>1       },
{a=>__LINE__, b=>"a_aaabb_cccc", c=>"m_aaabb_cccc", d=>0,     e=>1       },

# z_ -> other, z_, m_

{a=>__LINE__, b=>       "z_aaa", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>     "z_aaabb", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>"z_aaabb_cccc", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>       "z_aaa", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "z_aaa", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "z_aaabb", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "z_aaabb", c=>"z_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"z_aaabb_cccc", c=>     "z_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"z_aaabb_cccc", c=>"z_aaabb_cccc", d=>0,     e=>0       },

{a=>__LINE__, b=>       "z_aaa", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>       "z_aaa", c=>"m_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>     "z_aaabb", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "z_aaabb", c=>"m_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"z_aaabb_cccc", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"z_aaabb_cccc", c=>"m_aaabb_cccc", d=>0,     e=>0       },

# m_ -> other,  m_

{a=>__LINE__, b=>     "m_aaabb", c=>           "x", d=>undef, e=>undef   },
{a=>__LINE__, b=>"m_aaabb_cccc", c=>           "x", d=>undef, e=>undef   },

{a=>__LINE__, b=>     "m_aaabb", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>     "m_aaabb", c=>"m_aaabb_cccc", d=>0,     e=>0       },
{a=>__LINE__, b=>"m_aaabb_cccc", c=>     "m_aaabb", d=>0,     e=>0       },
{a=>__LINE__, b=>"m_aaabb_cccc", c=>"m_aaabb_cccc", d=>0,     e=>0       },

);

  for my $entry (@DATA) {
    my $line  = ${$entry}{a};
    my $name1 = ${$entry}{b};
    my $name2 = ${$entry}{c};
    my $rc1   = ${$entry}{d};
    my $rc2   = ${$entry}{e};

    ASSERT(__LINE__ . ".$line", isValidDependency($name1, $name2), $rc1);
    ASSERT(__LINE__ . ".$line", isValidDependency($name2, $name1), $rc2);
  }
}

#==============================================================================
# Multi-dir UOR helper functions

=head2 isUORsegment($package)

Return true if the supplied path is part of a multi-directory UOR.

More precisely, return true if the last segment of the absolute path
is part of a multi-directory unit-of-release (UOR) name.

=cut

sub isUORsegment ($) {
    return -f $_[0].$FS.".not-package";
}

sub _mr_isUORsegment ($) {
    return _mr_stat($_[0].$FS.".not-package");
}


# rather than stat'ing for the entity we do a readdir of the containing
# directory, that way if we look for another item in the same directory we can
# simply do a cache lookup instead of a stat, this assumes that things are not
# added or removed from the directory once we've cached it

{
    my %readdir_cache;

    sub _mr_stat ($) {    # return true for positive assertion (found path)
        my ($ent) = @_;

        #### !!!! <<<FIXME: circular dependency with DependencyCache !!!!
        require BDE::Util::DependencyCache;
        my @_mr_paths;
        my $root = BDE::Util::DependencyCache::getFileSystemRoot();

        if (defined $root) {
            my $searchmode = $root->getSearchMode();

            unless ($searchmode & FILESYSTEM_NO_ROOT) {
                push @_mr_paths, $root->getRootLocation;
            }
            unless ($searchmode & FILESYSTEM_NO_PATH) {
                push @_mr_paths, split ':', $root->getPath;
            }
        }

        if (!@_mr_paths) {
            push @_mr_paths, split ':', CONSTANT_PATH;
        }

        require File::Basename;
        my $base = File::Basename::basename($ent);

        foreach my $mr (@_mr_paths) {
            my $path = $mr . $FS . $ent;
            my $dir  = File::Basename::dirname($path);
            if ( !$readdir_cache{$dir} ) {
                if ( opendir my $D, $dir ) {
                    $readdir_cache{$dir} = { map { $_ => 1 } readdir $D };
                    closedir $D;
                } else {
                    $readdir_cache{$dir} = {};
                }
            }

            if ($readdir_cache{$dir}{$base}) {
                return $path;
            }
        }
        return undef;
    }

}

#==============================================================================
# Legacy nomenclature support

=head2 isLegacy($package)

Return true if the supplied name is a legacy package, or false otherwise.

=head2 getFullLegacyName($package)

Return the relative path of the package, relative to robocop's tree (/bbsrc)
(undef if package is not found)

=head2 getLegacyLeafPath($package)

Return relative path to where to find a given legacy package when multirooting.
Path is relative to the development root.

The complete path will typically result in a target that is a symlink to the
canonical location (absolute path to) robocop's tree (/bbsrc), but can be a
local snapshot of the package as long as the result from reading the symlink
(and removing the absolute path to the robocop root) remains the same.  This
can be done by having a symlink with a relative path to a location within the
legacy leaf of the development root (e.g. <root>/legacy/...)

C<getLegacyLeafPath()> is an abstration that centralizes how the subdirectory
structure of the C<LEGACY_DIR> of the development root is organized.
For example, if there are many items in the top level of the legacy directory,
subdirectories can be created hashed on the first two characters of the
library name.  All consumers of this routine are isolated from such changes.

=cut

{   ## Legacy, Third-Party, and Untagged-Application (code enclosure block)

    ## Note, where Legacy supports relative symlink pointing to canonical root
    ## location, Third-Party and Untagged-Application support subdirs under
    ## the UOR in addition to multi-dir UORs

    my %legacy;

    sub getLegacyLeafPath ($) {
	return LEGACY_DIR.$FS.$_[0];
    }

    sub isLegacy ($) {
	my $lib = shift;
	return 0 unless (LEGACY_SUPPORT eq ENABLED && length($lib) != 0);
	if (!exists $legacy{$lib}) {
	    my $relpath = getLegacyLeafPath($lib);
	    my $path = _mr_stat($relpath);
	    if ($path && !_mr_isUORsegment($relpath)) {
		if (index($lib,$FS) != -1) {
		    ## If $lib contains $FS, find UOR by walking
		    ## up path and removing trailing subdirs
		    my $prefix_len = length(getLegacyLeafPath(""));
		    my $t = getLegacyLeafPath($lib);
		    my $index = rindex($t,$FS);
		    while ($index > $prefix_len
			   && !_mr_isUORsegment(substr($t,0,$index))) {
			$t = substr($t,0,$index);
			$index = rindex($t,$FS);
		    }
		    $relpath = $t;
		    $legacy{substr($t,$prefix_len)} = $t;
		}
		# if a relative symlink, link points to canonical root location
		# (nested links are not supported)
		my $linkpath = readlink($path) if (-l $path);
		if ($linkpath && substr($linkpath,0,length($FS)) ne $FS) {
		    ## File::Spec::Unix::canonpath() is too correct for use here
		    ## We are assuming no nested symlinks, that $path must
		    ## contain a slash ('/'), and that link stays within tree
		    $linkpath = substr($relpath,0,rindex($relpath,'/')) #dirname
			      . $FS.$linkpath;
		    do { } while ($linkpath =~ s|[^/]+?/\.\./||); #(skips /..$)
		    $linkpath = substr($linkpath,length(getLegacyLeafPath("")));
		    $relpath = getLegacyLeafPath($linkpath);
		    $legacy{$linkpath} = $relpath;
		}
		$legacy{$lib} = $relpath;
	    }
	    else {
		$legacy{$lib} = undef;
	    }
	}
	return defined $legacy{$lib};
    }

    sub getFullLegacyName ($) {
	return isLegacy($_[0]) ? $legacy{$_[0]} : undef;
    }

    sub getShortLegacyName ($) {
	return isLegacy($_[0])
	  ? substr($legacy{$_[0]},rindex($legacy{$_[0]},$FS)+1)  # basename
	  : undef;
    }

#==============================================================================
# Third-Party nomenclature support

=head2 isThirdParty($package)

Return true if the supplied name is a third-party package, or false otherwise.

=head2 getFullThirdPartyName($package)

Return the relative path of the package, relative to robocop's tree (/bbsrc)
(undef if package is not found)

=head2 getThirdPartyLeafPath($package)

Return relative path to where to find a given third-party package when
multirooting.  Path is relative to the development root.

The complete path will typically result in a target that is a symlink to the
canonical location (absolute path to) robocop's tree (/bbsrc), but can be a
local snapshot of the package as long as the result from reading the symlink
(and removing the absolute path to the robocop root) remains the same.  This
can be done by having a symlink with a relative path to a location within the
third-party leaf of the development root (e.g. <root>/thirdparty/...)

C<getThirdPartyLeafPath()> is an abstration that centralizes how the subdir
structure of the C<THIRDPARTY_DIR> of the development root is organized.
For example, if there are many items in the top level of the third-party dir,
subdirectories can be created hashed on the first two characters of the
library name.  All consumers of this routine are isolated from such changes.

=cut

    my %thirdparty;

    sub getThirdPartyLeafPath ($) {
	return THIRDPARTY_DIR.$FS.$_[0];
    }

    sub isThirdParty ($) {
	my $lib = shift;
	return 0 unless (THIRDPARTY_SUPPORT eq ENABLED && length($lib) != 0);
	if (!exists $thirdparty{$lib}) {
	    $thirdparty{$lib} = getThirdPartyLeafPath($lib);
	    if (!_mr_stat($thirdparty{$lib})
		|| _mr_isUORsegment($thirdparty{$lib})) {
		$thirdparty{$lib} = undef;
	    }
	    elsif (index($lib,$FS) != -1) {
		## If $lib contains $FS, find UOR by walking
		## up path and removing trailing subdirs
		my $prefix_len = length(getThirdPartyLeafPath(""));
		my $t = $thirdparty{$lib};
		my $index = rindex($t,$FS);
		while ($index > $prefix_len
		       && !_mr_isUORsegment(substr($t,0,$index))) {
		    $t = substr($t,0,$index);
		    $index = rindex($t,$FS);
		}
		$thirdparty{$lib} = $t;
		$thirdparty{substr($t,$prefix_len)} = $t;
	    }
	}
	return defined $thirdparty{$lib};
    }

    sub getFullThirdPartyName ($) {
	return isThirdParty($_[0]) ? $thirdparty{$_[0]} : undef;
    }

    sub getShortThirdPartyName ($) {
	return isThirdParty($_[0])
	  ? substr($thirdparty{$_[0]},rindex($thirdparty{$_[0]},$FS)+1)#basename
	  : undef;
    }

#==============================================================================
# Application (untagged) nomenclature support

=head2 isUntaggedApplication($package)

Return true if the supplied name is an untagged application package,
or false otherwise.

=head2 getFullUntaggedApplicationName($package)

Return the relative path of the package, relative to robocop's tree (/bbsrc)
(undef if package is not found)

=head2 getApplicationLeafPath($package)

Return relative path to where to find a given application package when
multirooting.  Path is relative to the development root.

The complete path will typically result in a target that is a symlink to the
canonical location (absolute path to) robocop's tree (/bbsrc), but can be a
local snapshot of the package as long as the result from reading the symlink
(and removing the absolute path to the robocop root) remains the same.  This
can be done by having a symlink with a relative path to a location within the
application leaf of the development root (e.g. <root>/application/...)

C<getApplicationLeafPath()> is an abstration that centralizes how the subdir
structure of the C<APPLICATIONS_DIR> of the development root is organized.
For example, if there are many items in the top level of the application dir,
subdirectories can be created hashed on the first two characters of the
library name.  All consumers of this routine are isolated from such changes.

=cut

    my %application;

    sub getApplicationLeafPath ($) {
	return APPLICATIONS_DIR.$FS.$_[0];
    }

    sub isUntaggedApplication ($) {
	my $lib = shift;
	return 0 unless (LEGACY_SUPPORT eq ENABLED && length($lib) != 0);
	return 0 if (substr($lib,0,2) eq "m_");
	if (!exists $application{$lib}) {
	    $application{$lib} = getApplicationLeafPath($lib);
	    if (!_mr_stat($application{$lib})
		|| _mr_isUORsegment($application{$lib})) {
		$application{$lib} = undef;
	    }
	    elsif (index($lib,$FS) != -1) {
		## If $lib contains $FS, find UOR by walking
		## up path and removing trailing subdirs
		my $prefix_len = length(getApplicationLeafPath(""));
		my $t = $application{$lib};
		my $index = rindex($t,$FS);
		while ($index > $prefix_len
		       && !_mr_isUORsegment(substr($t,0,$index))) {
		    $t = substr($t,0,$index);
		    $index = rindex($t,$FS);
		}
		$application{$lib} = $t;
		$application{substr($t,$prefix_len)} = $t;
	    }
	}
	return defined $application{$lib};
    }

    sub getFullUntaggedApplicationName ($) {
	return isUntaggedApplication($_[0]) ? $application{$_[0]} : undef;
    }

    sub getShortUntaggedApplicationName ($) {
	return isUntaggedApplication($_[0])		#basename
	  ? substr($application{$_[0]},rindex($application{$_[0]},$FS)+1)
	  : undef;
    }

#==============================================================================

    sub _isPreExisting ($) {_isExistingGroup($_[0])||_isExistingPackage($_[0])}

    my %existing_group;
    sub _isExistingGroup ($) {
	return 0 unless (LEGACY_SUPPORT eq ENABLED && length($_[0]) != 0
			 && isGroup($_[0]));
	my $lib = shift;
	if (!exists $existing_group{$lib}) {
	    my $type = getType($lib);
	    my $rootrelpath =
	      getTypeDir($type).$FS.(isIndexed($type)?INDEX_DIR.$FS:"").$lib;
	    $existing_group{$lib} =
	      (_mr_stat($rootrelpath.$FS.GROUP_META_SUBDIR)
	       && !_mr_isUORsegment($rootrelpath))
		? $rootrelpath
		: undef;
	}
	return defined $existing_group{$lib};
    }

    my %existing_pkg;
    sub _isExistingPackage ($) {
	return 0 unless (LEGACY_SUPPORT eq ENABLED && length($_[0]) != 0
			 && isPackage($_[0]));
	my $lib = shift;
	if (!exists $existing_pkg{$lib}) {
	    my $type = getType($lib);
	    my $rootrelpath =
	      getTypeDir($type).$FS.(isIndexed($type)?INDEX_DIR.$FS:"").$lib;
	    $existing_pkg{$lib} =
	      (_mr_stat($rootrelpath.$FS.PACKAGE_META_SUBDIR)
	       && !_mr_isUORsegment($rootrelpath))
		? $rootrelpath
		: undef;
	}
	return defined $existing_pkg{$lib};
    }


    sub _get_legacy_hash ($) {
	if (isLegacy($_[0])) {
	    return \%legacy;
	}
	elsif (isThirdParty($_[0])) {
	    return \%thirdparty;
	}
	elsif (isUntaggedApplication($_[0])) {
	    return \%application;
	}
	else {
	    return;
	}
    }

    sub _legacy_lookup ($) {
	return _get_legacy_hash($_[0])
	  if ($legacy{$_[0]} || $thirdparty{$_[0]} || $application{$_[0]});
	  ## (ugly shortcut)

	my $hash;
	my $lib = $_[0];
	my $idx = 1; # (non-zero start value)
	while (!($hash = _get_legacy_hash($lib)) && $idx > 0) {
	    $idx = index($lib,$FS)+1;
	    substr($lib,0,$idx,'');
	}
	return 0 unless ($idx > 0);

	# (go back and fill in longer portions of hash
	#  (in which lib was found) that were marked undef)
	my $fullname = $hash->{$lib};
	my $frag = $_[0];
	while ($frag ne $lib) {
	    $hash->{$frag} = $fullname;
	    $idx = index($frag,$FS)+1;
	    substr($frag,0,$idx,'');
	}
	return $hash;
    }

    sub isNonCompliantUOR ($) {
	return _legacy_lookup($_[0]) ? 1 : 0;
    }

    # Retrieve path info about a compliant UOR from (longer) path containing it.
    # Given the requirement that directories must exist in the source tree,
    # find the first UOR in the path string (moving left to right) where all
    # subsequent subdirs after the UOR (in the given path) exist under the UOR
    # in one of the (multirooted) source roots.  Note that directory existence
    # requirement means that paths provided as arguments should not include the
    # filename (which might not exist yet in the multirooted paths if the file
    # is a new file that has yet to be committed).  Since this requirement has
    # been enforced for legacy paths for years, there is unlikely to be any
    # impact to cscheckin or to production build scripts by adding this new
    # requirement on compliant UORs.  Some dev environments may have to
    # configure their roots.  SCM machines long ago implemented alternative
    # to requiring the now-defunct lroot symlink tree.  (Historically, the
    # Nomenclature module did not have a dependency on the filesystem --
    # it operated purely on BDE naming convention, hence "nomenclature" module.
    # The need to absorb Bloomberg existing codebase necessitated the reliance
    # on the filesystem until such time as a better alternative -- for example,
    # a manifest -- is implemented.)
    my %_compliant_cache;
    sub _compliant_lookup ($$) {
	# $_[0] = (longer) path containing compliant UOR
	# $_[1] = return selector: 0 (UOR) | 1 (rootreluor) | 2 (rootrelpath)
	return $_compliant_cache{$_[0]}->[$_[1]]
	  if exists $_compliant_cache{$_[0]};
	my($elt,$type,$rootprefix,$rootrelpath);
	my @elts = split /$FSRE/o, $_[0];
	while (@elts) {
	    $elt = shift @elts;
	    next unless ($elt ne "" && _isPreExisting($elt));

	    $type = getType($elt);
	    $rootprefix =
	      getTypeDir($type).$FS.(isIndexed($type)?INDEX_DIR.$FS:"");
	    $rootrelpath = $rootprefix.join($FS,$elt,@elts);
	    next unless (_mr_stat($rootrelpath));

	    $_compliant_cache{$_[0]} = [ $elt, $rootprefix.$elt, $rootrelpath ];
	    return $_compliant_cache{$_[0]}->[$_[1]];
	}
	return undef;
    }

    ##<<<TODO these routines overlap with some concepts from FileSystem.pm
    ## and are not necessarily the most efficient.  Some of these might be
    ## stored in an object, or attributes to the caches, rather than in
    ## separate hashes
    my %canonical;
    sub getCanonicalUOR ($) {
	return $canonical{$_[0]} if $canonical{$_[0]};
	my $uor;

	if (_legacy_lookup($_[0])) {  # must check if legacy before compliant

	    $uor = getRootRelativeUOR($_[0]) || return;

	    # (might use get{Legacy,ThirdParty,UntaggedApplication}LeafPath(""))
	    if (isLegacy($_[0])) {
		$uor = substr($uor,length(LEGACY_DIR)+length($FS));
	    } elsif (isThirdParty($_[0])) {
		$uor = substr($uor,length(THIRDPARTY_DIR)+length($FS));
	    } elsif (isUntaggedApplication($_[0])) {
		$uor = substr($uor,length(APPLICATIONS_DIR)+length($FS));
	    } else {
		fatal("Unimplemented legacy type for $_[0]");
	    }
	}
	else {
	    $uor = _compliant_lookup($_[0], 0);
	}

	$canonical{$uor} = $uor if $uor;
	return $canonical{$_[0]} = $uor;
    }

    sub getSubdirsRelativeToUOR ($) {
	my $relpath = getRootRelativePath($_[0]);
	my $relpath_len = $relpath ? length($relpath) : 0;
	my $reluor = getRootRelativeUOR($_[0]);
	my $reluor_len = $reluor ? length($reluor) : 0;
	# (relpath or reluor as undef means filesystem lookup failure)
	# (should we warn? throw an exception?)
	return substr($relpath, ($relpath_len > $reluor_len)
				   ? $reluor_len + length($FS)
				   : $reluor_len);
    }

    sub getRootRelativePath ($) {
	my $hash = _legacy_lookup($_[0]);

	# return root relative path for compliant entity
	# (after first checking that entity is not legacy)
	return _compliant_lookup($_[0], 2) unless ($hash);

	## legacy, thirdparty, untagged application

	## Note: requires UOR to be present in path -- no rename in mapping
	## and must be -first- occurrence when indexing from front of path
	## (for third-party and applications)
	#(might use get{Legacy,ThirdParty,UntaggedApplication}LeafPath(""))
	my $pre = isLegacy($_[0])
	  ? LEGACY_DIR
	  : isUntaggedApplication($_[0])
	      ? APPLICATIONS_DIR
	      : THIRDPARTY_DIR;
	my $uor = substr($$hash{$_[0]},length($pre)+length($FS));
	my $subdirs = ($_[0] =~ m%(?:^|/)\Q$uor\E(/.*|$)% ? $1 : "");
	## (if string is not found, fallback and just return UOR,
	##  but that silently eliminates path segments after the UOR)
	return $hash->{$_[0]}.$subdirs;
    }

    my %uor;
    sub getRootRelativeUOR ($) {
	return $uor{$_[0]} if exists($uor{$_[0]});

	my $hash = _legacy_lookup($_[0]);

	# return root relative UOR for compliant entity
	# (after first checking that entity is not legacy)
	return ($uor{$_[0]} = _compliant_lookup($_[0], 1)) unless ($hash);

	## legacy, thirdparty, untagged application

	my $idx = 1;  # (non-zero start value)
	my $path = $hash->{$_[0]};
	my $d;
	while ((!($d = _mr_stat($path.$FS.PACKAGE_META_SUBDIR)) || !-d $d)
	       && ($idx = rindex($path,$FS)) > 0) {
	    substr($path,$idx,length($path),''); #dirname
	}
	return ($uor{$_[0]} = $path) unless $idx <= 0;

	# (might use get{Legacy,ThirdParty,UntaggedApplication}LeafPath(""))
	if (isLegacy($_[0])) {
	    $path=LEGACY_DIR;
	}
	elsif (isThirdParty($_[0])) {
	    $path=THIRDPARTY_DIR;
	}
	elsif (isUntaggedApplication($_[0])) {
	    $path=APPLICATIONS_DIR;
	}
	else {
	    fatal("Unimplemented legacy type for $_[0]");
	}

	# walk down to first location that is not part of a multi-dir UOR
	my @frags = split /$FSRE/o,substr($hash->{$_[0]},
					  length($path)+length($FS));
	do {
	    return ($uor{$_[0]}=undef) unless (@frags);#should not happen;fatal?
	    $path .= $FS.(shift @frags);
	} while (_mr_isUORsegment($path));
	return ($uor{$_[0]} = (($d=_mr_stat($path)) && -d $d) ? $path : undef);
    }

    sub getRootDevEnvUOR ($) {
	my $hash = _legacy_lookup($_[0]);

	## !!! ??? how is this different from getCanonicalUOR() ??? !!!
	##         (it's not different; look at logs to find why created)
	##         (this is used only by Change::Identity.pm and the usage
	##          there can likely be changed to use getCanonicalUOR())
	##         (much of Change::Identity is probably redundant with
	##          code in this module, with the addition that _identify()
	##          keeps a cache of $uor/$subdirs and this module keeps
	##          caches of $uor, $rootreluor, $rootrelpath (src tree paths))

	# return UOR for compliant entity
	# (after first checking that entity is not legacy)
	return _compliant_lookup($_[0], 0) unless ($hash);

	## legacy, thirdparty, untagged application

	# (might use get{Legacy,ThirdParty,UntaggedApplication}LeafPath(""))
	if (isLegacy($_[0])) {
	    return substr($hash->{$_[0]},length(LEGACY_DIR)+length($FS));
	}
	elsif (isThirdParty($_[0])) {
	    return substr($hash->{$_[0]},length(THIRDPARTY_DIR)+length($FS));
	}
	elsif (isUntaggedApplication($_[0])) {
	    return substr($hash->{$_[0]},length(APPLICATIONS_DIR)+length($FS));
	}
	else {
	    fatal("Unimplemented legacy type for $_[0]");
	}
    }

}   ## Legacy, Third-Party, and Untagged-Application (code enclosure block)


#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)
Ralph Gibbons (rgibbons1@bloomberg.net)
Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<BDE::FileSystem>

=cut

1;
