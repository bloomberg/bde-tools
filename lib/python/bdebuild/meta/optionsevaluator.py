"""Evaluate option rules.
"""

import re
import copy

from bdebuild.meta import optiontypes
from bdebuild.meta import optionsutil
from bdebuild.common import sysutil
from bdebuild.common import logutil

# The default compiler is set by an option with the key 'BDE_COMPILER_FLAG'. If
# this option exist any uplid having the value 'def' in its compiler field is
# equivalent to the value of the said option.  Having this as a global variable
# is the simplest workaround that I could think of.
DEFAULT_COMPILER = None


class OptionsEvaluator(object):
    """Evaluates a list of option rules.

    Attributes:
        results (dict of str to str): Evaluated key value map.
    """

    _OPT_INLINE_COMMAND_RE = re.compile(r'\\"`([^`]+)`\\"')
    _OPT_INLINE_COMMAND_RE2 = re.compile(r'\$\(shell([^\)]+)\)')

    def __init__(self, uplid, ufid, initial_options=None):
        """Initialize the object with a build configuration.

        Args:
            uplid (Uplid): Uplid of the build configuration.
            ufid (Ufid): Ufid of the build configuration.
            initial_options (dict): Initital options.
        """
        self._uplid = uplid
        self._ufid = ufid
        if initial_options:
            self.results = copy.deepcopy(initial_options)
        else:
            self.results = {}

    def _match_rule(self, option_rule):
        """Determine if an option rule matches with the build configuration.
        """

        # These keys are used to preserve backwards compatibility with
        # bde_build.pl and should be ignored.
        ignore_keys = ('XLC_INTERNAL_PREFIX1',
                       'XLC_INTERNAL_PREFIX2',
                       'AIX_GCC_PREFIX',
                       'SUN_CC_INTERNAL_PREFIX',
                       'SUN_GCC_INTERNAL_PREFIX',
                       'LINUX_GCC_PREFIX',
                       'WINDOWS_CC_PREFIX',
                       'RETRY_ON_SIGNAL')

        if option_rule.key in ignore_keys:
            return False

        global DEFAULT_COMPILER
        if not optionsutil.match_uplid(self._uplid, option_rule.uplid,
                                       DEFAULT_COMPILER):
            return False
        if not optionsutil.match_ufid(self._ufid, option_rule.ufid):
            return False

        return True

    def _store_option_rule(self, rule, debug_keys=[]):
        """Store the key and value of an option rule.
        """
        match = self._match_rule(rule)

        if rule.key in debug_keys:
            if match:
                logutil.info('Accept: %s' % rule)
            else:
                logutil.warn('Ingore: %s' % rule)
        if not match:
            return

        mc = self._OPT_INLINE_COMMAND_RE.search(rule.value)
        if mc:
            v = rule.value
            out = sysutil.shell_command(mc.group(1)).rstrip()
            rule.value = '%s"%s"%s' % (v[:mc.start(1) - 3], out,
                                       v[mc.end(1) + 3:])

        mc2 = self._OPT_INLINE_COMMAND_RE2.match(rule.value)
        if mc2:
            out = sysutil.shell_command(mc2.group(1)).rstrip()
            rule.value = out

        key = rule.key
        value = rule.value

        if key == 'BDE_COMPILER_FLAG':
            global DEFAULT_COMPILER
            DEFAULT_COMPILER = value

        if key not in self.results:
            self.results[key] = value
        else:
            orig = self.results[key]
            if rule.command == optiontypes.OptionCommand.ADD:
                if orig:
                    self.results[key] = orig + ' ' + value
                else:
                    self.results[key] = value
            elif rule.command == optiontypes.OptionCommand.INSERT:
                if orig:
                    self.results[key] = value + ' ' + orig
                else:
                    self.results[key] = value
            elif rule.command == optiontypes.OptionCommand.APPEND:
                self.results[key] = orig + value
            elif rule.command == optiontypes.OptionCommand.PREPEND:
                self.results[key] = value + orig
            elif rule.command == optiontypes.OptionCommand.OVERRIDE:
                self.results[key] = value

        if rule.key in debug_keys:
            logutil.info('Update: %s -> %s\n' % (rule.key,
                                                 self.results[rule.key]))

    def store_option_rules(self, option_rules, debug_keys=[]):
        """Store the keys and values of a list of option rules for evaluation.
        """
        for rule in option_rules:
            self._store_option_rule(rule, debug_keys)

    def clear(self):
        """Clear all stored key values.
        """
        self.results.clear()

    def evaluate(self, debug_keys=[]):
        """Evaluate stored options.
        """

        def evaluate_key(key):
            if key in self.results:
                self.results[key] = re.sub(
                    r'(\$\((\w+)\))',
                    lambda m: evaluate_key(m.group(2)),
                    self.results[key])
                return self.results[key]
            else:
                return ''

        for key in self.results:
            self.results[key] = evaluate_key(key)
            if key in debug_keys:
                logutil.info('%s: %s' % (key, self.results[key]))

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
