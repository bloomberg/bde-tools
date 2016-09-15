package Symbols;

# ----------------------------------------------------------------------------
# Copyright 2016 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE ----------------------------------

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

1;


__DATA__

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
PCFILE_EXTENSION        => .pc
MAKEFILE_NAME           => Makefile

DEFAULT_OPTFILE         => default.opts

# Source category directories

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
IS_PKGCONFIG            => 512

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

# Default values for filesystem

CONSTANT_PATH           => "/public/src"

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

# Master switch to disable legacy support (if necessary)
LEGACY_SUPPORT		=> "$ENABLED"

# Master switch to disable third-party support (if necessary)
THIRDPARTY_SUPPORT	=> "$ENABLED"

