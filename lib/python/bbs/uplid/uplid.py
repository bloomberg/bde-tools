"""Uplid - Universal platform ID

This module defines UPLID type
"""

from dataclasses import dataclass
from bbs.common import blderror

VALID_OS_TYPES = ("*", "unix", "windows")
VALID_OS_NAMES = ("*", "linux", "darwin", "aix", "sunos", "windows")
VALID_COMP_TYPES = ("*", "gcc", "clang", "xlc", "cc", "cl", "msvc")

@dataclass
class Uplid:
    """This class represents an Universal Platform ID.

    Uplids are used to identify the platform and toolchain used for a build.
    """

    os_type: str = "*"
    os_name: str = "*"
    cpu_type: str = "*"
    os_vers: str = "*"
    profile: str = ""

    @classmethod
    def is_valid(cls, uplid):
        """Determine whether a UPLID is valid.

        Args:
            uplid (Uplid): Uplid to validate.

        Returns:
            True if valid
        """

        if uplid.os_type not in VALID_OS_TYPES:
            return False
        if uplid.os_name not in VALID_OS_NAMES:
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
        parts = platform_str.split("-")

        if len(parts) > 5:
            raise blderror.InvalidUplidError(
                f"Invalid UPLID string: {platform_str}"
            )

        parts = ["*" if p == "" else p for p in parts]
        parts.extend(["*"] * (5 - len(parts)))
        (os_type, os_name, cpu_type, os_ver, profile) = (
            p.lower() for p in parts
        )

        uplid = cls(os_type, os_name, cpu_type, os_ver, profile)
        return uplid

    def __repr__(self):
        return "-".join([self.os_type,
                         self.os_name,
                         self.cpu_type,
                         self.os_vers,
                         self.profile
                         ])

def _match_uplid_str(uplid, mask):
    return mask == "*" or uplid == "*" or uplid.lower() == mask.lower()


def _match_uplid_ver(uplid, mask):
    if mask == "*" or uplid == "*":
        return True

    return sysutil.match_version_strs(uplid, mask)

def match_uplid(uplid, mask):
    """Determine if uplid mask match a uplid configuration.

    The mask matches the uplid configuration if:

    1 Each string part of the uplid mask is either '*' or is the same as that
      of the uplid configuration.

    2 Each version part of the uplid mask is greater than or equal to the
      version of the uplid configuration.

    Args:
        uplid (Uplid): The id of the current plaform.
        mask (Uplid): The platform mask of an option rule.
    """

    if not all(
        _match_uplid_str(getattr(uplid, part), getattr(mask, part))
        for part in ("os_type", "os_name", "cpu_type")
    ):
        return False

    if not _match_uplid_str(uplid.profile, mask.profile):
        return False

    return True

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
