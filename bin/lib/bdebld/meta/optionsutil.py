"""Utilities on options related types.
"""

import os

from bdebld.meta import optionsparser
from bdebld.meta import logutil


def get_default_option_rules():
    """Return the default option rules.

    Returns:
       list of OptionRule.
    """
    upd = os.path.dirname
    tools_repo_root = upd(upd(upd(upd(upd(os.path.realpath(__file__))))))
    default_opts_path = os.path.join(tools_repo_root, 'etc', 'default.opts')
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
        raise ValueError('Cannot find default.opts')

    with open(default_opts_path) as f:
        parser = optionsparser.OptionsParser(f)
        parser.parse()

        option_rules = parser.option_rules

    if bde_root:
        default_internal_opts_path = os.path.join(bde_root, 'etc',
                                                  'default_internal.opts')

        if os.path.isfile(default_internal_opts_path):
            found_default_internal_opts = True
            with open(default_internal_opts_path) as f:
                parser = optionsparser.OptionsParser(f)
                parser.parse()

                option_rules += parser.option_rules
        else:
            logutil.warn('The BDE_ROOT environment variable is set, '
                         'but $BDE_ROOT/etc/default_internal.opts does '
                         'not exist.')

    default_paths = default_opts_path
    if found_default_internal_opts:
        default_paths += ',' + default_internal_opts_path

    logutil.warn('Using default option rules from: ' + default_paths)

    return option_rules


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

    def _is_int(str_):
        try:
            int(str_)
            return True
        except ValueError:
            return False

    index = 0
    while index < len(build_ver):
        build_subv = build_ver[index]
        mask_subv = mask_ver[index]

        if (not _is_int(build_subv) or not _is_int(mask_subv)):
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
