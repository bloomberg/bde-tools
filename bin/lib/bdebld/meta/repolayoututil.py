import json
import os

from bdebld.common import logutil
from bdebld.meta import repolayout
from bdebld.meta import repoloadutil


def get_repo_layout(repo_root_path):
    """Get the directory layout of a repository.

    Args:
        repo_root_path (str): Path to the root of the repository.

    Returns:
        RepoLayout

    Raises:
        IOError
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
        else:
            repo_layout.group_dirs = ['groups', 'enterprise', 'wrappers']
            repo_layout.app_package_dirs = ['applications']
            repo_layout.stand_alone_package_dirs = ['adapters']
            repo_layout.third_party_package_dirs = ['third-party']
            repo_layout.group_abs_dirs = []

        return repo_layout

    logutil.warn('Using layout configuration from: ' + layout_config_path)
    with open(layout_config_path) as f:
        return parse_repo_layout_from_json(f)


def write_repo_layout_to_json(file_, repo_layout):
    """Write a repo layout to a file in JSON format.

    Args:
        file_ (File): The destination file.
        repo_layout (RepoLayout): The repo layout.

    Returns:
        None

    Raises:
        IOError
    """
    json.dump(repo_layout.__dict__, file_)


def parse_repo_layout_from_json(file_):
    """Parse the repo layout from a JSON file.

    Args:
        file_ (File): The source file.

    Returns:
        RepoLayout

    Raises:
        ValueError
    """
    def ascii_encode_dict(data):
        new_data = {}
        for key, value in data.items():
            new_data[key] = [i.encode('ascii') for i in value]

        return new_data

    loaded_dict = json.load(file_, object_hook=ascii_encode_dict)
    repo_layout = repolayout.RepoLayout()

    for key in loaded_dict:
        if key in repo_layout.__dict__:
            setattr(repo_layout, key, loaded_dict[key])
        else:
            logutil.warn('Invalid keys in repo_options config file: %s.' %
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
