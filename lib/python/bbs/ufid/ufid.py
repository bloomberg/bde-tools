"""UFID object

"""

from bbs.common import blderror

class Ufid():
    """This class represents an Unified Flag ID.

    The UFID is used to identify the build configuration used.

    Attributes:
        flags (set of str): Set of string flags.
    """

    # The following variables are copied from bde_build.pl to preserve the
    # display order of flags.

    build_with_convert = 'Set review level to "{}"'
    build_with_assert = 'Set assert level to "{}"'

    FRONT = 0
    MIDDLE = 50
    BACK = 100

    VALID_FLAGS = {
        "opt": (FRONT + 0, "Build optimized"),
        "dbg": (FRONT + 1, "Build with debugging information"),
        "noexc": (MIDDLE + 0, "Exceptions are disabled"),
        "nomt": (MIDDLE + 1, "Multithreading is disabled"),
        "32": (MIDDLE + 2, "Build for 32-bit architecture"),
        "64": (MIDDLE + 3, "Build for 64-bit architecture"),
        "safe": (MIDDLE + 5, "Build safe (paranoid) libraries"),
        "safe2": (
            MIDDLE + 6,
            "Build safe2 (paranoid and binary-incompatible) libraries",
        ),
        "aopt": (MIDDLE + 10, build_with_assert.format("OPT")),
        "adbg": (MIDDLE + 11, build_with_assert.format("DEBUG")),
        "asafe": (MIDDLE + 12, build_with_assert.format("SAFE")),
        "anone": (MIDDLE + 13, build_with_assert.format("NONE")),
        "ropt": (MIDDLE + 20, build_with_convert.format("OPT")),
        "rdbg": (MIDDLE + 21, build_with_convert.format("DEBUG")),
        "rsafe": (MIDDLE + 22, build_with_convert.format("SAFE")),
        "rnone": (MIDDLE + 23, build_with_convert.format("NONE")),
        "asan": (MIDDLE + 30, "Enable address sanitizer"),
        "msan": (MIDDLE + 31, "Enable memory sanitizer"),
        "tsan": (MIDDLE + 32, "Enable thread sanitizer"),
        "ubsan": (MIDDLE + 33, "Enable undefined behavior sanitizer"),
        "fuzz": (MIDDLE + 34, "Enable fuzz testing"),
        "stlport": (BACK + 0, "Build with STLPort on Sun"),
        "pic": (BACK + 1, "Build static PIC libraries"),
        "cpp03": (BACK + 10, "Build with support for C++03 features"),
        "cpp11": (BACK + 11, "Build with support for C++11 features"),
        "cpp14": (BACK + 12, "Build with support for C++14 features"),
        "cpp17": (BACK + 13, "Build with support for C++17 features"),
        "cpp20": (BACK + 14, "Build with support for C++20 features"),
        "cpp23": (BACK + 15, "Build with support for C++23 features"),
        "cpp26": (BACK + 16, "Build with support for C++26 features"),
    }

    def __init__(self, flags=[]):
        """Initialize the object with the specified flags.

        Args:
            flags (list of str): Flags to add.
        """

        self.flags = set()

        for f in flags:
            if f in self.VALID_FLAGS:
                self.flags.add(f)
            else:
                raise blderror.InvalidUfidError(f"Invalid flag {f} in ufid")

        if len(self.flags.intersection({ "32", "64"})) > 1:
            raise blderror.InvalidUfidError("Multiple bitness in ufid")

        if len(self.flags.intersection({ "cpp03", "cpp11", "cpp14", "cpp17", "cpp20", "cpp23", "cpp26"})) > 1:
            raise blderror.InvalidUfidError("Multiple cpp standards in ufid")

    @classmethod
    def from_str(cls, config_str):
        flags = []

        # Properly handle the case when config_str == '_'.
        for f in config_str.split("_"):
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

    def is_set(self, flag):
        return True if flag in self.flags else False

    def __repr__(self):
        if len(self.flags) == 0:
            return "_"

        def get_rank(key):
            if key in self.VALID_FLAGS:
                return self.VALID_FLAGS[key][0]
            else:
                return self.BACK - 100

        sorted_flags = sorted(self.flags, key=get_rank)
        return "_".join(sorted_flags)


def make_ufid_from_cmdline(args):
    """Create an Ufid from the specified command-line arguments.

    Args:
        args (dict): The specified command-line options.

    Returns:
        An Ufid object.

    Raises:
        InvalidUfidError on invalid UFID.
    """

    if args.ufid:
        ufid = Ufid.from_str(args.ufid)
        if not Ufid.is_valid(ufid.flags):
            raise blderror.InvalidUfidError(
                'The UFID, "%s", is invalid.  Each part of a UFID must be '
                'in the following list of valid flags: %s.'
                % (
                    args.ufid,
                    ", ".join(sorted(Ufid.VALID_FLAGS.keys())),
                )
            )
        return ufid
    else:
        raise blderror.InvalidUfidError('No UFID specified.')

# -----------------------------------------------------------------------------
# Copyright 2022 Bloomberg Finance L.P.
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
