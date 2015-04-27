"""Load the structures and metadata of a repository
"""

import os

from bdebuild.common import logutil

from bdebuild.meta import repocontext
from bdebuild.meta import repocontextutil
from bdebuild.meta import repounits
from bdebuild.meta import repoloadutil
from bdebuild.meta import repolayoututil


class RepoContextLoader(object):
    """Load the repository structure and metadata.

    Attributes:
        repo_context (RepoContext): The repo context to be loaded.
    """
    def __init__(self, root_path):
        """Initialize this loader.

        Args:
            root_path (str): Path to the root of the repository.
        """
        self.repo_context = repocontext.RepoContext()
        self.repo_context.root_path = root_path

    def load(self):
        """Load the repo context.

        Raises:
            InvalidConfigFileError:  The layout configuration is invalid.
        """
        root_path = self.repo_context.root_path
        if os.path.isfile(os.path.join(root_path,
                                       '.bdeworkspaceconfig')):
            dirs = next(os.walk(root_path))[1]
            for d in dirs:
                dir_path = os.path.join(root_path, d)
                if repoloadutil.is_bde_repo_path(dir_path):
                    logutil.start_msg('Entering repo')
                    logutil.end_msg(os.path.basename(dir_path), color='YELLOW')
                    self._load_repo(dir_path)
        else:
            self._load_repo(root_path)
        self._load_uor_doc_and_versions()

    def _load_repo(self, repo_path):
        repo_layout, layout_config_path = repolayoututil.get_repo_layout(
            repo_path)
        if layout_config_path:
            logutil.start_msg('Using layout configuration from')
            logutil.end_msg(layout_config_path)
        for gd in repo_layout.group_dirs:
            gd_path = os.path.join(repo_path, gd)
            if os.path.isdir(gd_path):
                self._load_repo_package_groups(gd_path)

        for sad in repo_layout.stand_alone_package_dirs:
            sad_path = os.path.join(repo_path, sad)
            if os.path.isdir(sad_path):
                self._load_repo_stdalone_packages(
                    sad_path, repounits.PackageType.PACKAGE_STAND_ALONE)

        for sad in repo_layout.app_package_dirs:
            sad_path = os.path.join(repo_path, sad)
            if os.path.isdir(sad_path):
                self._load_repo_stdalone_packages(
                    sad_path, repounits.PackageType.PACKAGE_APPLICATION)

        for sad in repo_layout.third_party_package_dirs:
            sad_path = os.path.join(repo_path, sad)
            if os.path.isdir(sad_path):
                self._load_repo_thirdparty_dirs(sad_path)

        for pg in repo_layout.group_abs_dirs:
            if pg == '.':
                pg_path = repo_path
            else:
                pg_path = os.path.join(repo_path, pg)
            if repoloadutil.is_package_group_path(pg_path):
                self._load_repo_one_package_group(pg_path)

    def _load_repo_package_groups(self, path):
        dirs = next(os.walk(path))[1]
        package_group_paths = []
        for d in dirs:
            dir_path = os.path.join(path, d)
            if repoloadutil.is_package_group_path(dir_path):
                package_group_paths.append(dir_path)

        for path in package_group_paths:
            self._load_repo_one_package_group(path)

    def _load_repo_one_package_group(self, path):
        logutil.start_msg('Loading %s' % os.path.basename(path))
        package_group = repoloadutil.load_package_group(path)
        self.repo_context.add_unit(package_group)

        for package_name in package_group.mem:
            package_path = os.path.join(package_group.path, package_name)
            if os.path.basename(package_path).find('+') >= 0:
                package = repoloadutil.load_package(
                    package_path, repounits.PackageType.PACKAGE_PLUS)
            else:
                package = repoloadutil.load_package(
                    package_path, repounits.PackageType.PACKAGE_NORMAL)
            self.repo_context.add_unit(package)
        logutil.end_msg('ok')

    def _load_repo_stdalone_packages(self, path, type_):
        dirs = next(os.walk(path))[1]
        package_paths = []
        for d in dirs:
            dir_path = os.path.join(path, d)
            if repoloadutil.is_package_path(dir_path):
                package_paths.append(dir_path)

        for path in package_paths:
            logutil.start_msg('Loading %s' % os.path.basename(path))
            package = repoloadutil.load_package(path, type_)
            self.repo_context.add_unit(package)
            logutil.end_msg('ok')

    def _load_repo_thirdparty_dirs(self, path):
        dirs = next(os.walk(path))[1]
        tp_paths = []
        for d in dirs:
            dir_path = os.path.join(path, d)
            if repoloadutil.is_third_party_path(dir_path):
                tp_paths.append(dir_path)

        for path in tp_paths:
            third_party = repounits.ThirdPartyDir(path)
            logutil.start_msg('Loading %s' % third_party.name)
            self.repo_context.add_unit(third_party)
            logutil.end_msg('ok')

    def _load_uor_doc_and_versions(self):
        """Load the doc and version metadata for uors.

        Loading version numbers is done after loading other metadata because
        the version of one uor may refer to that of another.
        """

        uor_map = repocontextutil.get_uor_map(self.repo_context)

        for uor in uor_map.values():
            uor.doc = repoloadutil.get_uor_doc(uor)
            uor.version = repoloadutil.get_uor_version(uor, uor_map)


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
