package Symbols;
use strict;

use base qw(Common::Symbols);

use vars qw($OVERRIDE_PREFIX);
$OVERRIDE_PREFIX = "BDE_";

#==============================================================================

=head1 NAME

Symbols - sharable non-volatile data values

=head1 SYNOPSIS

    use Symbols qw(ENABLED DISABLED :TYPENAME /^EXIT/);

=head1 DESCRIPTION

This module provides common symbols for use in multiple modules and
applications. For details of how to use it, see L<Common::Symbols>.

=head1 NOTE

This module is now deprecated for additions of new symbols. New symbols
should be added to new derived symbols modules that inherit functionality
from L<Common::Symbols> instead. In time, symbols defined here will likely
migrate to function-specific modules (of which a number already exist).

=cut

#==============================================================================

{ my $release=undef;
  sub release {
      return $release if defined $release;

      if    ($0 =~ m!/bbcm/infrastructure/tools/!) { $release = 'dev'; }
      elsif ($0 =~ m!/bb/csdata/scm/(scm1.*)!) { $release = 'scm1'; }
      elsif ($0 =~ m!/bb/csdata/scm/(scm2.*)!) { $release = 'scm2'; }
      elsif ($0 =~ m!/bb/csdata/scm/!) { $release = 'scm'; }
      elsif ($0 =~ m!^-e!)     { $release = 'dev';   }
      elsif ($0 =~ m!/alpha/!) { $release = 'alpha'; }
      elsif ($0 =~ m!/beta/!)  { $release = 'beta';  }
      elsif ($0 =~ m!/lgood/!) { $release = 'lgood'; }
      elsif ($0 =~ m!/cstest/!){ $release = 'cstest';}
      else                     { $release = 'prod';  }

      return $release;
  }
}

{
  my $confdir=undef;
  sub confdir {
      return $confdir if defined $confdir;

      if    ($0 =~ m!/bb/csdata/scm/!) { $confdir = '/bb/csdata/scm/conf'; }
      elsif ($0 =~ m!(.*/bbcm/infrastructure/tools)/!) {$confdir = "$1/bin/scm/conf"}
      else                     { $confdir = '/bbsrc/bin/cstools/conf';  }
      return $confdir;
  }
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;


__DATA__

# Release detection support
RELEASE                 => "${ \release() }"
CONFDIR                 => "${ \confdir() }"

# Debug support

BACKTRACE               => 0

# Default concurrency

DEFAULT_JOBS            => { defined &DB::DB ? 1 : 4 }

# Exit stati (^EXIT_)

EXIT_SUCCESS            => 0
EXIT_FAILURE            => 1
EXIT_USAGE              => 2
EXIT_OVERMAX            => 127
EXIT_TIMEOUT            => 126
EXIT_SIZEOUT            => 125
EXIT_NONEXEC            => 124

# General-purpose controls

ENABLED                 => ON
DISABLED                => OFF

# Persistent data

PACKAGE_DC_BASE         => dependencyCache
PACKAGE_CACHE_SUBDIR    => cache
WANT_PACKAGE_CACHE	=> "$DISABLED"

# File and directory name elements

PACKAGE_META_SUBDIR     => package
GROUP_META_SUBDIR       => group
APPLICATION_META_SUBDIR => package
DEPFILE_EXTENSION       => .dep
MEMFILE_EXTENSION       => .mem
INCFILE_EXTENSION       => .pub
OPTFILE_EXTENSION       => .opts
REFFILE_EXTENSION       => .refs
DUMFILE_EXTENSION       => .dums
CAPFILE_EXTENSION       => .cap
DEFFILE_EXTENSION       => .defs
LCKFILE_EXTENSION       => .lck
MAKEFILE_NAME           => Makefile

DEFAULT_OPTFILE         => default.opts

# Source category directories

BASES_DIR               => groups
GROUPS_DIR              => groups
ADAPTERS_DIR            => adapters
APPLICATIONS_DIR        => applications
WRAPPERS_DIR            => wrappers
DEPARTMENTS_DIR         => departments
FUNCTIONS_DIR           => functions
ENTERPRISES_DIR         => enterprise
INDEX_DIR               => index
THIRDPARTY_DIR          => thirdparty
LEGACY_DIR		=> legacy

# Tools directories

TOOLS_BINDIR            => bin
TOOLS_ETCDIR            => etc
TOOLS_LIBDIR            => lib/perl

# Type values (^IS_)

IS_BASE                 => 1
IS_ADAPTER              => 2
IS_FUNCTION             => 4
IS_APPLICATION          => 8
IS_DEPARTMENT           => 16
IS_WRAPPER              => 32
IS_ENTERPRISE           => 64
IS_THIRDPARTY           => 128
IS_LEGACY               => 256

# Type names (:TYPENAME)

BASE_TYPENAME           => Base
ADAPTER_TYPENAME        => Adapter
FUNCTION_TYPENAME       => Function
APPLICATION_TYPENAME    => Application
DEPARTMENT_TYPENAME     => Department
WRAPPER_TYPENAME        => Wrapper
ENTERPRISE_TYPENAME     => Enterprise
THIRDPARTY_TYPENAME     => Third-Party
LEGACY_TYPENAME         => Legacy

# Dependency types (:DEPENDENCY)

ALL_DEPENDENCY          => 0
WEAK_DEPENDENCY         => 1
STRONG_DEPENDENCY       => 2
CO_DEPENDENCY           => 3

# Members file markers

IS_METADATA_ONLY        => [METADATA ONLY]
IS_PREBUILT_LEGACY      => [PREBUILT LEGACY]
IS_PREBUILT_THIRDPARTY  => [PREBUILT THIRD PARTY]
IS_RELATIVE_PATHED      => [RELATIVE PATH]
IS_OFFLINE_ONLY         => [OFFLINE ONLY]
IS_GTK_BUILD            => [GTK BUILD]
IS_MANUAL_RELEASE       => [MANUAL RELEASE]
IS_HARD_VALIDATION      => [HARD VALIDATION]
IS_HARD_INBOUND         => [HARD INBOUND VALIDATION]
MAY_DEPEND_ON_ANY       => [MAY DEPEND ON ANY]
IS_NO_NEW_FILES         => [NO NEW FILES]
IS_SCREEN_LIBRARY       => [SCREEN LIBRARY]
IS_BIG_ONLY             => [BIG ONLY]
IS_CLOSED               => [CLOSED]
IS_MECHANIZED           => [MECHANIZED]
IS_UNDEPENDABLE         => [PRIVATE DEPENDENCY]
IS_STP			=> [STRAIGHT THROUGH]
IS_RAPID_BUILD		=> [RAPID BUILD]
IS_DEPENDENCY_BUILD	=> [DEPENDENCY BUILD]
IS_GCC_WARNINGS_ERRORS  => [GCC WARNINGS ARE FATAL]
IS_GTK_OFFLINE_ALLOWED  => [GTK OFFLINE ALLOWED]
IS_64BIT_BUILD          => [64 BIT]

# Default values for filesystem

# Default roots, override with BDE_ROOT and BDE_PATH

#ROOT                    => /bbcm/infrastructure
ROOT                    => /bbsrc/proot
DEFAULT_FILESYSTEM_ROOT => "$ROOT"
USER                    => { $ENV{LOGNAME} or $ENV{USERNAME} or "noname" }
HOME                    => { $ENV{HOME} or $ENV{HOMEPATH} or (getpwnam(Symbols::USER))[7] or "nohome" }
#PATH                    => "/bbcm/infrastructure"
PATH                    => ""
CONSTANT_PATH           => "/bbsrc/source/proot:/bbsrc/stproot"
#CONSTANT_PATH           => "/bb/csdata/branches/trunk:/bb/csdata/branches/stp"
AO_SETUP_PATH           => "/bb/csdata/cache/aotools/aoroot"

# FileSystem search control bitpattern
FILESYSTEM_NO_LOCAL     => 1
FILESYSTEM_NO_ROOT      => 2
FILESYSTEM_NO_PATH      => 4
FILESYSTEM_NO_DEFAULT   => 8
FILESYSTEM_NO_CACHE     => 16

FILESYSTEM_LOCAL_ONLY   => 6
FILESYSTEM_ROOT_ONLY    => 5
FILESYSTEM_PATH_ONLY    => 3
FILESYSTEM_NO_SEARCH    => 7

FILESYSTEM_FLAT         => 256
FILESYSTEM_NO_CONTEXT   => 512
FILESYSTEM_VERY_FLAT    => 768
FILESYSTEM_CACHE        => "$ENABLED"

DEFAULT_OPTIONS_FILE    => "default${OPTFILE_EXTENSION}"

# Paths to authoritative registries

NAME_REGISTRY_LOCN      => "$CONSTANT_PATH/etc/registry/names"
PATH_REGISTRY_LOCN      => "$CONSTANT_PATH/etc/registry/universe"

# Marker for ignored include statements in dependency analysis

NO_FOLLOW_MARKER        => no follow
NOT_A_COMPONENT         => not a component
QUOTE_DELIMITED         => 1
ANGLE_DELIMITED         => 2

# Legacy support

LEGACY_PATH             => /bbsrc
# The real robocop.libs contains componentised libs so we can't use it directly
# LEGACY_DATA           => /bbsrc/tools/data/robocop.libs
# Use a symlink farm, which will scale better than a flat file
# (LEGACY_DIR is appended to this path in typical usage)
LEGACY_DATA             => /bbsrc/lroot
#LEGACY_DATA             => /bbsrc/etc/legacy.libs
#For local testing
#LEGACY_DATA            => /bbcm/infrastructure
# Master switch to disable legacy support (if necessary)
LEGACY_SUPPORT		=> "$ENABLED"

# Master switch to disable third-party support (if necessary)
THIRDPARTY_SUPPORT	=> "$ENABLED"

DEFAULT_CACHE_PATH	=> /bb/csdata/cache

DEFAULT_BRANCH_BASE     => /bb/cstools/branches
