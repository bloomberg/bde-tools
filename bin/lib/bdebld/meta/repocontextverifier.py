"""Verify the structure of a repository.
"""

from bdebld.common import logutil

from bdebld.meta import cpreproc
from bdebld.meta import graphutil
from bdebld.meta import repocontextutil
from bdebld.meta import repounits


class RepoContextVerifier(object):
    """Detect problems in a repository's structure.

    Currently this type supports only the detection of cycles.

    Attributes:
        is_success (bool): True if no problems are found after calling
             ``verify()``.
    """

    def __init__(self, repo_context,
                 log_start=lambda _: None,
                 log_end=lambda _: None):
        """Initialize this object.

        Args:
            repo_context (RepoContext): Repo structure.
            log_start (func): Record log message start.
            log_end (func): Record log message end.
        """
        self.repo_context = repo_context
        self.is_success = True
        self.log_start = log_start
        self.log_end = log_end

    def verify(self):
        self.verify_uors()
        self.verify_groups()
        self.verify_packages()

    def verify_uors(self):
        self.log_start('Verifying UORs')
        digraph = repocontextutil.get_uor_digraph(self.repo_context)
        self._verify_cycles_impl(digraph)

    def verify_groups(self):
        for group in (u for u in self.repo_context.units.values() if
                      u.type_ == repounits.UnitType.GROUP):
            self.log_start('Verifying %s' % group.name)
            digraph = repocontextutil.get_package_digraph(self.repo_context,
                                                          group)
            self._verify_cycles_impl(digraph)

    def verify_packages(self):
        for package in (u for u in self.repo_context.units.values() if
                        u.type_ in repounits.UnitTypeCategory.PACKAGE_CAT):
            self.log_start('Verifying %s' % package.name)
            digraph = cpreproc.get_component_digraph(package)
            self._verify_cycles_impl(digraph)

    def _verify_cycles_impl(self, digraph):
        cycles = graphutil.find_cycles(digraph)
        if len(cycles) == 0:
            self.log_end('ok')
        else:
            self.log_end('found cycle(s)', color='RED')
            for cycle in cycles:
                logutil.info('CYCLE: ' + ','.join(cycle))
            self.is_success = False

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
