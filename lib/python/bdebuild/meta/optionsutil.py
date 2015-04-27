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

    Args:
        msg_func (func, optional): function to print status messages

    Returns:
        list of OptionRule.

    Raises:
        MissingFileError: If default.opts can not be found.
    """
    default_opts_path = os.path.join(sysutil.repo_root_path(), 'etc',
                                     'default.opts')
    bde_root = os.environ.get('BDE_ROOT')

    found_default_opts = False
    found_default_internal_opts = False
    if not os.path.isfile(default_opts_path):
        logutil.warn('Cannot find default.opts at %s. '
                     'Trying to use $BDE_ROOT/etc/default.opts instead.' %
                     default_opts_path)
        if bde_root:
            default_opts_path = os.path.join(bde_root, 'etc', 'default.opts')
            if os.path.isfile(default_opts_path):
                found_default_opts = True
    else:
        found_default_opts = True

    if not found_default_opts:
        raise blderror.MissingFileError('Cannot find default.opts.')

    option_rules = optionsparser.parse_option_rules_file(default_opts_path)

    if bde_root:
        default_internal_opts_path = os.path.join(bde_root, 'etc',
                                                  'default_internal.opts')

        if os.path.isfile(default_internal_opts_path):
            found_default_internal_opts = True
            option_rules += optionsparser.parse_option_rules_file(
                default_internal_opts_path)
        else:
            logutil.warn('The BDE_ROOT environment variable is set, '
                         'but $BDE_ROOT/etc/default_internal.opts does '
                         'not exist.')

    logutil.msg("Using default option rules from", default_opts_path)
    if found_default_internal_opts:
        logutil.msg("Using default option rules from",
                    default_internal_opts_path)

    return option_rules


def get_ufid_cmdline_options():
    """Return a list of command line options to specify the ufid.
    """

    return [
        (('abi-bits',),
         {'type': 'choice',
          'default': '64' if sysutil.is_64bit_system() else '32',
          'choices': ('32', '64'),
          'help': 'ABI bits (32/64) [default: %default]'}),
        (('build-type',),
         {'type': 'choice',
          'default': 'debug',
          'choices': ('release', 'debug'),
          'help': 'the type of build to produce (debug/release) '
          "[default: %default]"}),
        (('library-type',),
         {'type': 'choice',
          'default': 'static',
          'choices': ('static', 'shared'),
          'help': 'the type of libraries to build (shared/static) '
          "[default: %default]"}),
        (('assert-level',),
         {'type': 'choice',
          'default': 'none',
          'choices': ('none', 'safe', 'safe2'),
          'help': 'bsls_assert level (none/safe/safe2) '
          "[default: %default]"}),
        (('noexception',),
         {'action': 'store_true',
          'default': False,
          'help': 'disable exception support'}),
        (('cpp11',),
         {'action': 'store_true',
          'default': False,
          'help': 'enable C++11 support'}),
        (('t', 'ufid'),
         {'type': 'string',
          'default': None,
          'help': 'the Unified Platform ID (UFID) identifying the build '
          'configuration (e.g., dbg_mt_exc). '
          'Note that specifying a UFID will overwrite other build '
          'configuration options such as --library_type.'})
    ]


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
                'Invalid UFID specified, each part of a UFID must be '
                'in the following list of valid flags: %s.' %
                ", ".join(
                    sorted(optiontypes.Ufid.VALID_FLAGS.keys())))
        return ufid

    ufid_map = {
        'abi_bits': {'64': '64'},
        'build_type': {'debug': 'dbg', 'release': 'opt'},
        'assert_level': {'safe': 'safe', 'safe2': 'safe2'},
        'cpp11': {True: 'cpp11'},
        'noexception': {False: 'exc'},
        'library_type': {'shared': 'shr'}
        }

    flags = []
    for opt in ufid_map:
        attr = getattr(opts, opt, None)
        if attr is not None:
            if attr in ufid_map[opt]:
                flags.append(ufid_map[opt][attr])

    # always use mt
    flags.append('mt')

    return optiontypes.Ufid(flags)


def match_ufid(ufid, mask):
    """Determine if option-rule ufid mask match a uplid configuration.

    Args:
         ufid (Ufid): The build configuration being used.
         mask (Ufid): The configuration mask in a build rule.
    """
    return mask.flags.issubset(ufid.flags)


def match_uplid(uplid, mask, default_compiler=None):
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

    if not all(_match_uplid_str(getattr(uplid, part), getattr(mask, part)) for
               part in ('os_type', 'os_name', 'cpu_type')):
        return False

    if not _match_uplid_str(uplid.comp_type, mask.comp_type):
        if not (mask.comp_type == 'def' and
                default_compiler == uplid.comp_type):
            return False

    if not all(_match_uplid_ver(getattr(uplid, part), getattr(mask, part)) for
               part in ('os_ver', 'comp_ver')):
        return False

    return True


def _match_uplid_str(uplid, mask):
    return mask == '*' or uplid == '*' or uplid.lower() == mask.lower()


def _match_uplid_ver(uplid, mask):
    if mask == '*' or uplid == '*':
        return True

    build_ver = uplid.split('.')
    mask_ver = mask.split('.')

    mask_ver.extend(['0'] * (len(build_ver) - len(mask_ver)))

    index = 0
    while index < len(build_ver):
        build_subv = build_ver[index]
        mask_subv = mask_ver[index]

        if (not sysutil.is_int_string(build_subv) or
                not sysutil.is_int_string(mask_subv)):
            if build_subv != mask_subv:
                return False
        else:
            if int(mask_subv) < int(build_subv):
                return True
            elif int(mask_subv) > int(build_subv):
                return False

        index += 1

    return len(mask_ver) <= len(build_ver)

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
