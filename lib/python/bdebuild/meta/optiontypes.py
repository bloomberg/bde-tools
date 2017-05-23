"""Build options types.

This module defines types that represent various aspects of options in a
BDE-style repository.

"""

from bdebuild.common import blderror
from bdebuild.common import mixins


class OptionCommand(object):
    """This class enumerates over the types of option commands.

    Enumerators:
        ADD: Add to end of value, with a leading space. (default)
        INSERT: Add to start of value, with a following space.
        APPEND: Add to end of value directly, no leading space.
        PREPEND: Add to start of value directly, no following space.
        OVERRIDE: Completely replace the prior value.
    """
    ADD = 0
    INSERT = 1
    APPEND = 2
    PREPEND = 3
    OVERRIDE = 4

    COMMAND_STR_MAP = {
        ADD: '++',
        INSERT: '--',
        APPEND: '>>',
        PREPEND: '<<',
        OVERRIDE: '!!'
    }
    STR_COMMAND_MAP = {}
    for k, v in COMMAND_STR_MAP.items():
        STR_COMMAND_MAP[v] = k

    @classmethod
    def to_str(cls, command):
        """Convert an option command to its string representation.
        """
        if command not in cls.COMMAND_STR_MAP:
            raise LookupError()

        return cls.COMMAND_STR_MAP[command]

    @classmethod
    def from_str(cls, str_):
        """Convert a string back to an option command.
        """

        if str_ not in cls.STR_COMMAND_MAP:
            raise LookupError()

        return cls.STR_COMMAND_MAP[str_]


class OptionRule(mixins.BasicEqualityMixin):
    """This class represents an option rule.

    The option file format consists of a set of option rules.  The option rules
    can be evaluated to get a set of key and value pairs that are typically
    used to determine the compiler and linker flags used to build a package.

    Attributes:
        command (OptionCommand): Command of the rule.
        uplid (Uplid): Wild card UPLID to be matched.
        ufid (Ufid): UFID to be matched.
        key (str): Name of the variable to which the rule applies.
        value (str): The value contributed by the rule.
    """

    def __init__(self, command=None, uplid=None, ufid=None, key=None,
                 value=None):
        """Initialize the object with the specified arguments.

        Args:
            command (OptionCommand): Command of the rule.
            uplid (Uplid): Wild card UPLID to be matched.
            ufid (Ufid): UFID to be matched
            key (str): Name of the variable to which the rule applies.
            value (str): The value contributed by the rule.
        """
        self.command = command
        self.uplid = uplid
        self.ufid = ufid
        self.key = key
        self.value = value

    def __repr__(self):
        return '%s %s %s %s %s' % (OptionCommand.to_str(self.command),
                                   self.uplid,
                                   self.ufid, self.key, self.value)


class Ufid(mixins.BasicEqualityMixin):
    """This class represents an Unified Flag ID.

    The UFID is used to identify the build configuration used.

    Attributes:
        flags (set of str): Set of string flags.
    """

    # The following variables are copied from bde_build.pl to preserve the
    # display order of flags.
    FRONT = 0
    MIDDLE = 50
    BACK = 100
    VALID_FLAGS = {
        'dbg': (FRONT + 1, 'Build with debugging information'),
        'opt': (FRONT, 'Build optimized'),
        'exc': (MIDDLE, 'Exception support'),
        'mt': (MIDDLE + 1, 'Multithread support'),
        'ndebug': (MIDDLE + 2, 'Build with NDEBUG defined'),
        '64': (BACK - 5, 'Build for 64-bit architecture'),
        'safe2': (BACK - 4,
                  'Build safe2 (paranoid and binary-incompatible) libraries'),
        'safe': (BACK - 3, 'Build safe (paranoid) libraries'),
        'shr': (BACK - 2, 'Build dynamic libraries'),
        'pic': (BACK - 1, 'Build static PIC libraries'),
        'stlport': (BACK, 'Build with STLPort on Sun'),
        'cpp11': (BACK + 12, 'Build with support for C++11 (C++0x) features'),
        'cpp14': (BACK + 13, 'Build with support for C++14 features')
    }

    def __init__(self, flags=[]):
        """Initialize the object with the specified flags.

        Args:
            flags (list of str): Flags to add.
        """

        self.flags = set()

        for f in flags:
            self.flags.add(f)

    @classmethod
    def from_str(cls, config_str):
        flags = []

        # Properly handle the case when config_str == '_'.
        for f in config_str.split('_'):
            if f:
                flags.append(f)
        return cls(flags)

    @classmethod
    def is_valid(cls, flags):
        """Determine whether a set of flags is valid.

        Args:
            flags (list of str): flags to validate

        Returns:
            True if flags are valid
        """

        return all(f in cls.VALID_FLAGS for f in flags)

    def __repr__(self):
        if len(self.flags) == 0:
            return '_'

        def get_rank(key):
            if key in self.VALID_FLAGS:
                return self.VALID_FLAGS[key][0]
            else:
                return self.BACK - 100

        sorted_flags = sorted(self.flags,
                              key=get_rank)
        return '_'.join(sorted_flags)


class Uplid(mixins.BasicEqualityMixin):
    """This class represents an Universal Platform ID.

    Uplids are used to identify the platform and toolchain used for a build.
    """

    VALID_OS_TYPES = ('*', 'unix', 'windows')
    VALID_OS_NAMES = ('*', 'linux', 'darwin', 'aix', 'sunos', 'windows_nt')
    VALID_COMP_TYPES = ('*', 'gcc', 'clang', 'xlc', 'cc', 'cl')

    def __init__(self, os_type='*', os_name='*', cpu_type='*', os_ver='*',
                 comp_type='*', comp_ver='*'):
        self.os_type = os_type
        self.os_name = os_name
        self.cpu_type = cpu_type
        self.os_ver = os_ver
        self.comp_type = comp_type
        self.comp_ver = comp_ver

    @classmethod
    def is_valid(cls, uplid):
        """Determine whether a UPLID is valid.

        Args:
            uplid (Uplid): Uplid to validate.

        Returns:
            True if valid
        """

        if uplid.os_type not in cls.VALID_OS_TYPES:
            return False
        if uplid.os_name not in cls.VALID_OS_NAMES:
            return False
        if uplid.comp_type not in cls.VALID_COMP_TYPES:
            return False
        return True

    @classmethod
    def from_str(cls, platform_str):
        """Parse uplid from a string.

        Args:
            platform_str: Uplid string.

        Raises:
            InvalidUplidError
        """
        parts = platform_str.split('-')

        if len(parts) > 6:
            raise blderror.InvalidUplidError('Invalid UPLID string: %s'
                                             % platform_str)

        parts = ['*' if p == '' else p for p in parts]
        parts.extend(['*'] * (6 - len(parts)))
        (os_type,
         os_name,
         cpu_type,
         os_ver,
         comp_type,
         comp_ver) = (p.lower() for p in parts)

        uplid = cls(os_type, os_name, cpu_type, os_ver, comp_type, comp_ver)
        return uplid

    def __repr__(self):
        return '-'.join([self.os_type, self.os_name, self.cpu_type,
                         self.os_ver, self.comp_type, self.comp_ver])

# -----------------------------------------------------------------------------
# Copyright 2015 Bloomberg Finance L.P.
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
# ----------------------------- END-OF-FILE -----------------------------------
