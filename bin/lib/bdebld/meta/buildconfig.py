"""Represent the build configuration.
"""

import pprint

from bdebld.common import mixins


class BuildConfig(mixins.BasicEqualityMixin, mixins.BasicSerializeMixin):
    """Repo configuration to be persisted.

    This differs from RepoContext by storing only the evaluated build flags
    instead of all of the option rules.

    Attributes:
        root_path (str): Path to the root of the repository.
        uplid (Uplid): Platform ID.
        ufid (Ufid): Configuration flag ID.
        default_flags (BuildFlags): Build flags used by default, which can be
            passed to third_party packages.
        custom_envs (dict of str to str): Environment variables that should be
            set when running build commands.
        soname_overrides (dict of str to str): Override the soname for
            certain UORs.
        external_deps (set of str): External dependencies.
        package_groups (dict of str to PackageGroupBuildConfig): Package
            groups build configuration.
        stdalone_packages (dict of str to StdalonePackageBuildConfig):
            Stand-alone packages build configuration.
        inner_packages (dict of str to InnerPackageBuildConfig): Package
            build configuration.
        third_party_dirs (dict of str to ThirdPartyDir): Third-party
            directories.
    """

    def __init__(self, root_path, uplid, ufid):
        self.root_path = root_path
        self.uplid = uplid
        self.ufid = ufid
        self.default_flags = None
        self.custom_envs = {}
        self.soname_overrides = {}
        self.external_dep = None
        self.package_groups = {}
        self.stdalone_packages = {}
        self.inner_packages = {}
        self.third_party_dirs = {}

    def __repr__(self):
        return pprint.pformat(vars(self))


class BuildFlags(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    def __init__(self):
        self.export_flags = None
        self.export_libs = None
        self.libs = None
        self.stlibs = None
        self.libpaths = None
        self.linkflags = None
        self.cflags = None
        self.cxxflags = None
        self.cincludes = None
        self.cxxincludes = None
        self.test_cxxflags = None


class PackageGroupBuildConfig(mixins.BasicEqualityMixin):
    def __init__(self):
        self.name = None
        self.path = None
        self.doc = None
        self.version = None
        self.dep = set()
        self.external_dep = set()
        self.flags = None
        self.mem = set()

    def __repr__(self):
        return pprint.pformat(vars(self))


class PackageBase(mixins.BasicEqualityMixin):
    def __init__(self):
        self.name = None
        self.path = None
        self.dep = set()
        self.flags = None
        self.type_ = None
        self.has_dums = False

    def __repr__(self):
        return pprint.pformat(vars(self))


class PlusPackageBuildConfig(PackageBase):
    def __init__(self):
        self.headers = set()
        self.cpp_sources = set()
        self.cpp_tests = set()
        self.c_tests = set()


class InnerPackageBuildConfig(PackageBase):
    def __init__(self):
        self.components = set()


class StdalonePackageBuildConfig(PackageBase):
    def __init__(self):
        self.doc = None
        self.version = None
        self.external_dep = set()
        self.components = set()


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
