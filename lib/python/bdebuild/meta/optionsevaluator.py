"""Evaluate option rules.
"""

import os
import re
import copy

from bdebuild.meta import optiontypes
from bdebuild.meta import optionsutil
from bdebuild.common import sysutil
from bdebuild.common import logutil


class OptionsEvaluator(object):
    """Evaluates a list of option rules.

    Attributes:
        results (dict of str to str): Evaluated key value map.
    """

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
            self.options = copy.deepcopy(initial_options)
        else:
            self.options = {}
        self.results = {}

    def _match_rule(self, option_rule):
        """Determine if an option rule matches with the build configuration.
        """

        if not optionsutil.match_uplid(self._uplid, option_rule.uplid):
            return False
        if not optionsutil.match_ufid(self._ufid, option_rule.ufid):
            return False

        return True

    _OPT_INLINE_COMMAND_RE = re.compile(r'\\"`([^`]+)`\\"')
    _OPT_INLINE_COMMAND_RE2 = re.compile(r'\$\(shell([^\)]+)\)')
    _OPT_INLINE_SUBST_RE = re.compile(
        r'\$\(subst ([^,]+),([^,]*),([^\)]+)\)')

    def _store_option_rule(self, rule, debug_keys=[]):
        """Store the key and value of an option rule.
        """
        match = self._match_rule(rule)

        if rule.key in debug_keys:
            if match:
                logutil.info('Accept: %s' % rule)
            else:
                logutil.warn('Ignore: %s' % rule)
        if not match:
            return

        # `subst` was a hack to remove a flag from the list of compiler flags
        # when building test drivers.  This is no longer needed and will be
        # removed from opts files in BDE. It is explicitly ignored here for
        # backward compatibliity.
        if self._OPT_INLINE_SUBST_RE.match(rule.value):
            if rule.key in debug_keys:
                logutil.warn('Skipping rule: %s' % rule)
            return

        # `shell` returns output of a terminal command. It is used as part of a
        # hack to build bde-bb.
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

        if key not in self.options:
            self.options[key] = value
        else:
            orig = self.options[key]
            if rule.command == optiontypes.OptionCommand.ADD:
                if orig:
                    self.options[key] = orig + ' ' + value
                else:
                    self.options[key] = value
            elif rule.command == optiontypes.OptionCommand.INSERT:
                if orig:
                    self.options[key] = value + ' ' + orig
                else:
                    self.options[key] = value
            elif rule.command == optiontypes.OptionCommand.APPEND:
                self.options[key] = orig + value
            elif rule.command == optiontypes.OptionCommand.PREPEND:
                self.options[key] = value + orig
            elif rule.command == optiontypes.OptionCommand.OVERRIDE:
                self.options[key] = value

        if rule.key in debug_keys:
            logutil.info('Update: %s -> %s\n' % (rule.key,
                                                 self.options[rule.key]))

    def store_option_rules(self, option_rules, debug_keys=[]):
        """Store the keys and values of a list of option rules for evaluation.
        """
        for rule in option_rules:
            self._store_option_rule(rule, debug_keys)

    def clear(self):
        """Clear all stored key values.
        """
        self.options.clear()
        self.results.clear()

    def evaluate(self, debug_keys=[]):
        """Evaluate stored options.
        """

        def evaluate_key(key):
            if key in self.results:
                return self.results[key]
            elif key in self.options:
                result = re.sub(
                    r'(\$\((\w+)\))',
                    lambda m: evaluate_key(m.group(2)),
                    self.options[key])

                self.results[key] = result
                return self.results[key]
            elif key in os.environ:
                logutil.warn(
                    'Using the environment variable "%s" as an option key' %
                    key)
                self.results[key] = os.environ[key]
                return self.results[key]
            return ''

        for key in self.options:
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
