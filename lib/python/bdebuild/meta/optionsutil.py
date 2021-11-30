"""Utilities on options related types.
"""

import os

from bdebuild.common import logutil
from bdebuild.common import sysutil
from bdebuild.common import blderror

from bdebuild.meta import optionsparser
from bdebuild.meta import optiontypes


def get_default_option_rules():
    """Return the default option rules.

    Returns:
        list of OptionRule.

    Raises:
        MissingFileError: If default.opts can not be found.
    """
    default_opts_path = os.path.join(
        sysutil.repo_root_path(), "etc", "default.opts"
    )
    bde_root = os.environ.get("BDE_ROOT")

    found_default_opts = False
    found_default_internal_opts = False
    if not os.path.isfile(default_opts_path):
        logutil.warn(
            "Cannot find default.opts at %s. "
            "Trying to use $BDE_ROOT/etc/default.opts instead."
            % default_opts_path
        )
        if bde_root:
            default_opts_path = os.path.join(bde_root, "etc", "default.opts")
            if os.path.isfile(default_opts_path):
                found_default_opts = True
    else:
        found_default_opts = True

    if not found_default_opts:
        raise blderror.MissingFileError("Cannot find default.opts.")

    option_rules = optionsparser.parse_option_rules_file(default_opts_path)

    if bde_root:
        default_internal_opts_path = os.path.join(
            bde_root, "etc", "default_internal.opts"
        )

        if os.path.isfile(default_internal_opts_path):
            found_default_internal_opts = True
            option_rules += optionsparser.parse_option_rules_file(
                default_internal_opts_path
            )
        else:
            logutil.warn(
                'The BDE_ROOT environment variable is set to "%s", '
                'but $BDE_ROOT/etc/default_internal.opts ("%s") does '
                "not exist." % (bde_root, default_internal_opts_path)
            )

    logutil.msg("Using default option rules from", default_opts_path)
    if found_default_internal_opts:
        logutil.msg(
            "Using default option rules from", default_internal_opts_path
        )

    return option_rules


def get_ufid_cmdline_options():
    """Return a list of command line options to specify the ufid."""

    return [
        (
            ("abi-bits",),
            {
                "type": "choice",
                "default": "64" if sysutil.is_64bit_system() else "32",
                "choices": ("32", "64"),
                "help": "ABI bits (32/64) [default: %default]",
            },
        ),
        (
            ("build-type",),
            {
                "type": "choice",
                "default": "Debug",
                "choices": ("Debug", "Release", "RelWithDebInfo"),
                "help": "the type of build to produce (Debug/Release/RelWithDebInfo)"
                "[default: %default]",
            },
        ),
        (
            ("library-type",),
            {
                "type": "choice",
                "default": "static",
                "choices": ("static", "shared"),
                "help": "the type of libraries to build (shared/static)"
                "[default: %default]",
            },
        ),
        (
            ("noexception",),
            {
                "action": "store_true",
                "default": False,
                "help": "disable exception support",
            },
        ),
        (
            ("assert_level",),
            {
                "type": "choice",
                "default": None,
                "choices": (None, "aopt", "adbg", "asafe", "anone"),
                "help": "define the macros BSLS_ASSERT_LEVEL_ASSERT_OPT,\n"
                "BSLS_ASSERT_LEVEL_ASSERT, BSLS_ASSERT_LEVEL_ASSERT_SAFE,\n"
                "BSLS_ASSERT_LEVEL_NONE respectively as described\n"
                "in the component-level documentation of bsls_assert\n"
                '("aopt", "adbg", "asafe", "anone")',
            },
        ),
        (
            ("review_level",),
            {
                "type": "choice",
                "default": None,
                "choices": (None, "ropt", "rdbg", "rsafe", "rnone"),
                "help": "define the macros BSLS_REVIEW_LEVEL_REVIEW_OPT,\n"
                "BSLS_REVIEW_LEVEL_REVIEW, BSLS_REVIEW_LEVEL_REVIEW_SAFE,\n"
                "BSLS_REVIEW_LEVEL_NONE respectively as described\n"
                "in the component-level documentation of bsls_assert\n"
                '("ropt", "rdbg", "rsafe", "rnone")',
            },
        ),
        (
            ("sanitizer",),
            {
                "type": "choice",
                "default": None,
                "choices": (None, "asan", "msan", "tsan", "ubsan"),
                "help": "enable address, memory, thread or undefined behaviour\n"
                "sanitizer\n"
                '("asan", "msan", "tsan", "ubsan")',
            },
        ),
        (
            ("fuzz",),
            {
                "action": "store_true",
                "default": False,
                "help": "Build with fuzz testing (requires test driver change)",
            },
        ),
        (
            ("safe",),
            {
                "action": "store_true",
                "default": False,
                "help": 'define the macro "BDE_BUILD_TARGET_SAFE" as described in '
                "the component-level documentation of bsls_assert",
            },
        ),
        (
            ("safe2",),
            {
                "action": "store_true",
                "default": False,
                "help": 'define the macro "BDE_BUILD_TARGET_SAFE_2" as described in '
                "the component-level documentation of bsls_assert",
            },
        ),
        (
            ("cpp-std",),
            {
                "type": "choice",
                "default": None,
                "choices": (None, "03", "11", "14", "17"),
                "help": 'use a C++11 standard version ("03"/"11"/"14"/"17") '
                "[default value depends on compiler]",
            },
        ),
        (
            ("t", "ufid"),
            {
                "type": "string",
                "default": None,
                "help": "the Unified Platform ID (UFID) identifying the build "
                "configuration (e.g., dbg_mt_exc). "
                "Note that specifying a UFID will overwrite other build "
                "configuration options such as --library_type",
            },
        ),
    ]


def is_version_higher(v1, v2):
    return tuple(map(int, v1.split("."))) >= tuple(map(int, v2.split(".")))


def get_default_cpp_std(compiler_type, compiler_version):
    """Determine the default C++ standard for a particular compiler.

    Args:
        compiler_type (str): Compiler type.
        compiler_version (str): Compile version.

    Returns:
        One of the choices for the option "cpp-std", "17", "14", "11" or "03".
    """
    if (
        compiler_type == "gcc"
        and is_version_higher(compiler_version, "7.3")
        or compiler_type == "clang"
        and is_version_higher(compiler_version, "7")
    ):
        return "17"

    if (
        compiler_type == "gcc"
        and is_version_higher(compiler_version, "5.3")
        or compiler_type == "clang"
        and is_version_higher(compiler_version, "6")
    ):
        return "14"

    if (
        compiler_type == "gcc"
        and is_version_higher(compiler_version, "4.8")
        or compiler_type == "clang"
        and is_version_higher(compiler_version, "3.6")
    ):
        return "11"

    return "03"


def make_ufid_from_cmdline_options(opts):
    """Create an Ufid from the specified command-line options.

    Args:
        opts (dict): The specified command-line options.

    Returns:
        An Ufid object.

    Raises:
        InvalidUfidError on invalid UFID.
    """

    if opts.ufid:
        ufid = optiontypes.Ufid.from_str(opts.ufid)
        if not optiontypes.Ufid.is_valid(ufid.flags):
            raise blderror.InvalidUfidError(
                'The UFID, "%s", is invalid.  Each part of a UFID must be '
                "in the following list of valid flags: %s."
                % (
                    opts.ufid,
                    ", ".join(sorted(optiontypes.Ufid.VALID_FLAGS.keys())),
                )
            )
        return ufid

    ufid_map = {
        "abi_bits": {"64": ["64"]},
        "build_type": {
            "Debug": ["dbg"],
            "Release": ["opt"],
            "RelWithDebInfo": ["opt", "dbg"],
        },
        "safe": {True: ["safe"]},
        "safe2": {True: ["safe2"]},
        "assert_level": {
            "aopt": ["aopt"],
            "adbg": ["adbg"],
            "asafe": ["asafe"],
            "anone": ["anone"],
        },
        "review_level": {
            "ropt": ["ropt"],
            "rdbg": ["rdbg"],
            "rsafe": ["rsafe"],
            "rnone": ["rnone"],
        },
        "sanitizer": {
            "asan": ["asan"],
            "msan": ["msan"],
            "tsan": ["tsan"],
            "ubsan": ["ubsan"],
        },
        "fuzz": {True: ["fuzz"]},
        "cpp_std": {
            "03": ["cpp03"],
            "11": ["cpp11"],
            "14": ["cpp14"],
            "17": ["cpp17"],
            "20": ["cpp20"],
        },
        "noexception": {False: ["exc"]},
        "library_type": {"shared": ["shr"]},
    }

    # always use mt
    flags = ["mt"]
    for opt in ufid_map:
        attr = getattr(opts, opt, None)
        if attr is not None:
            if attr in ufid_map[opt]:
                flags.extend(ufid_map[opt][attr])

    return optiontypes.Ufid(flags)


def match_ufid(ufid, mask):
    """Determine if option-rule ufid mask match a uplid configuration.

    Args:
         ufid (Ufid): The build configuration being used.
         mask (Ufid): The configuration mask in a build rule.
    """
    return mask.flags.issubset(ufid.flags)


def match_uplid(uplid, mask):
    """Determine if option-rule uplid mask match a uplid configuration.

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

    if not _match_uplid_str(uplid.comp_type, mask.comp_type):
        return False

    if not all(
        _match_uplid_ver(getattr(uplid, part), getattr(mask, part))
        for part in ("os_ver", "comp_ver")
    ):
        return False

    return True


def _match_uplid_str(uplid, mask):
    return mask == "*" or uplid == "*" or uplid.lower() == mask.lower()


def _match_uplid_ver(uplid, mask):
    if mask == "*" or uplid == "*":
        return True

    return sysutil.match_version_strs(uplid, mask)


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
