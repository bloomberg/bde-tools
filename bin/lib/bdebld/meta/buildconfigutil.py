"""Utilties that operate on BuildConfig objects.
"""

from bdebld.meta import repounits


def get_uor_dict(build_config):
    uors = {}
    uors.update(build_config.stdalone_packages)
    uors.update(build_config.package_groups)
    uors.update(build_config.third_party_dirs)
    return uors


def count_components_in_package(package_bc):
    if package_bc.type_ == repounits.PackageType.PACKAGE_PLUS:
        return len(package_bc.cpp_sources)
    else:
        return len(package_bc.components)


def get_uor_digraph(build_config):
    """Return a directed graph of the UORs.
    """
    uors = get_uor_dict(build_config)
    uor_digraph = {}
    for uor in uors.values():
        if hasattr(uor, 'dep'):
            dep = uor.dep
        else:
            dep = []
        uor_digraph[uor.name] = dep

    return uor_digraph


def get_package_digraph(build_config, package_group_name):
    """Return a directed graph of the packages in a package group.
    """
    group = build_config.package_groups[package_group_name]
    package_dgraph = {}
    for name in group.mem:
        package = build_config.inner_packages[name]
        package_dgraph[name] = package.dep & group.mem

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
