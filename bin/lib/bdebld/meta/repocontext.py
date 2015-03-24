"""Aggregate Repository structure and metadata
"""


class RepoContext(object):
    """This class represents the structure of a repository.

    Attributes:
        package_groups (dict of str to PackageGroup): Map of names to package
            groups.
        packages (dict of str to Package): Map of names to packages.
        third_party_packages (dict of str to ThirdPartyPackage): Map of names
            to third party packages.
    """

    def __init__(self):
        self.root_path = None
        self.package_groups = {}
        self.packages = {}
        self.third_party_packages = {}


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
