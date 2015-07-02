import json
import os

from bdebuild.common import blderror
from bdebuild.common import logutil
from bdebuild.meta import repolayout
from bdebuild.meta import repoloadutil


def get_repo_layout(repo_root_path):
    """Get the directory layout of a repository.

    Args:
        repo_root_path (str): Path to the root of the repository.

    Returns:
        repo_layout (RepoLayout), config_file (str)

        config_file is the the path to the configuration file from which the
        configuration is derived. The value is 'None' if the default
        configuration is used.

    Raises:
        IOError: An error occured while accessing the configuration file.
        InvalidConfigFileError: Invalid configuration file.
    """
    layout_config_path = os.path.join(repo_root_path, '.bdelayoutconfig')
    if not os.path.isfile(layout_config_path):
        repo_layout = repolayout.RepoLayout()
        if repoloadutil.is_package_group_path(repo_root_path):
            # API has repositories where the root of the repo contains just one
            # package group. We want to support this instrisically.
            repo_layout.group_dirs = []
            repo_layout.app_package_dirs = []
            repo_layout.stand_alone_package_dirs = []
            repo_layout.third_party_package_dirs = []
            repo_layout.group_abs_dirs = ['.']
        elif os.path.isdir(os.path.join(repo_root_path, 'src')):
            # Attempt to automatically support repos using the "src" directory
            # instead of the repo root to store typical directories such as
            # "groups" and "adapters". If this simple heuristic fails for a
            # repo, use ".bdelayoutconfig" to customize its layout manually.
            repo_layout.group_dirs = ['src/groups', 'src/enterprise',
                                      'src/wrappers']
            repo_layout.app_package_dirs = ['src/applications']
            repo_layout.stand_alone_package_dirs = ['src/adapters',
                                                    'src/standalones']
            repo_layout.third_party_package_dirs = ['src/third-party']
            repo_layout.group_abs_dirs = []
        else:
            repo_layout.group_dirs = ['groups', 'enterprise', 'wrappers']
            repo_layout.app_package_dirs = ['applications']
            repo_layout.stand_alone_package_dirs = ['adapters', 'standalones']
            repo_layout.third_party_package_dirs = ['third-party']
            repo_layout.group_abs_dirs = []

        return repo_layout, None

    with open(layout_config_path) as f:
        repo_layout = parse_repo_layout_from_json(f)
        return repo_layout, layout_config_path


def write_repo_layout_to_json(file_, repo_layout):
    """Write a repo layout to a file in JSON format.

    Args:
        file_ (File): The destination file.
        repo_layout (RepoLayout): The repo layout.

    Returns:
        None

    Raises:
        IOError: Error writing the file.
    """
    json.dump(repo_layout.__dict__, file_)


def parse_repo_layout_from_json(file_):
    """Parse the repo layout from a JSON file.

    Args:
        file_ (File): The source file.

    Returns:
        RepoLayout

    Raises:
        InvalidConfigFileError: The configuration file is invalid.
    """
    def ascii_encode_dict(data):
        new_data = {}
        for key, value in data.items():
            new_data[key] = [i.encode('ascii') for i in value]

        return new_data

    try:
        loaded_dict = json.load(file_, object_hook=ascii_encode_dict)
    except ValueError as e:
        raise blderror.InvalidConfigFileError('Invalid .bdelayoutconfig: %s' %
                                              e.message)

    repo_layout = repolayout.RepoLayout()

    for key in loaded_dict:
        if key in repo_layout.__dict__:
            setattr(repo_layout, key, loaded_dict[key])
        else:
            logutil.warn('Invalid field in .bdelayoutconfig: %s.' %
                         key)

    return repo_layout

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
