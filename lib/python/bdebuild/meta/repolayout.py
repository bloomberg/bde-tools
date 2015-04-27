"""Repository layout.
"""

from bdebuild.common import mixins


class RepoLayout(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """This class represents the way a repository's directories are layed out.

    Attributes:
        app_dirs (list of str): Directories each containing multiple
            application packages.
        group_dirs (list of str): Directories each containing multiple package
            groups.
        third_party_package_dirs (list of str): Directories each containing
            multiple third party directories.
        stand_alone_package_dirs (list of str): Directories each containing
            multiple stand-alone packages.
        group_abs_dirs (list of str): Directories each pointing to the root of
            a package group.
    """

    def __init__(self):
        self.group_dirs = []
        self.stand_alone_package_dirs = []
        self.third_party_package_dirs = []
        self.app_package_dirs = []
        self.group_abs_dirs = []

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
