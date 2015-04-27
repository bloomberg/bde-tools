"""Verify the structure of a repository.
"""

from bdebuild.common import logutil

from bdebuild.meta import cpreproc
from bdebuild.meta import graphutil
from bdebuild.meta import repocontextutil
from bdebuild.meta import repounits


class RepoContextVerifier(object):
    """Detect problems in a repository's structure.

    Currently this type supports only the detection of cycles.

    Attributes:
        is_success (bool): True if no problems are found after calling
             ``verify()``.
    """

    def __init__(self, repo_context):
        """Initialize this object.

        Args:
            repo_context (RepoContext): Repo structure.
        """
        self.repo_context = repo_context
        self.is_success = True

    def verify(self):
        self.verify_uors()
        self.verify_groups()
        self.verify_packages()

    def verify_uors(self):
        logutil.start_msg('Verifying UORs')
        digraph = repocontextutil.get_uor_digraph(self.repo_context)
        self._verify_cycles_impl(digraph)

    def verify_groups(self):
        for group in (u for u in self.repo_context.units.values() if
                      u.type_ == repounits.UnitType.GROUP):
            logutil.start_msg('Verifying %s' % group.name)
            digraph = repocontextutil.get_package_digraph(self.repo_context,
                                                          group)
            self._verify_cycles_impl(digraph)

    def verify_packages(self):
        for package in (u for u in self.repo_context.units.values() if
                        u.type_ in repounits.UnitTypeCategory.PACKAGE_CAT):
            logutil.start_msg('Verifying %s' % package.name)
            digraph = cpreproc.get_component_digraph(package)
            self._verify_cycles_impl(digraph)

    def _verify_cycles_impl(self, digraph):
        cycles = graphutil.find_cycles(digraph)
        if len(cycles) == 0:
            logutil.end_msg('ok')
        else:
            logutil.end_msg('found cycle(s)', color='RED')
            for cycle in cycles:
                logutil.warn('CYCLE: ' + ','.join(cycle))
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
