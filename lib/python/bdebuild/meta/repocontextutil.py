"""Utilties that operate on RepoContext objects.
"""

from bdebuild.meta import repounits


def get_uor_map(repo_context):
    uors = {}

    for uor in (u for u in repo_context.units.values() if u.type_ in
                repounits.UnitTypeCategory.UOR_CAT):
        uors[uor.name] = uor

    return uors


def get_uor_digraph(repo_context):
    """Return a directed graph of the UORs.
    """
    uors = get_uor_map(repo_context)
    uor_digraph = {}
    for uor in uors.values():
        if hasattr(uor, 'dep'):
            dep = uor.dep
        else:
            dep = []
        uor_digraph[uor.name] = dep

    return uor_digraph


def get_package_digraph(repo_context, package_group):
    """Return a directed graph of the packages in a package group.
    """
    assert(package_group.type_ == repounits.UnitType.GROUP)
    package_dgraph = {}
    for name in package_group.mem:
        package = repo_context.units[name]
        assert(package.type_ in repounits.UnitTypeCategory.PACKAGE_INNER_CAT)
        package_dgraph[name] = package.dep

    return package_dgraph

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
