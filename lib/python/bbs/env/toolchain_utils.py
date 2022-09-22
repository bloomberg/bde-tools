"""Configure the available compilers.
"""

import json
import re
import os
import string
import sys
import subprocess

from bbs.common import blderror

class ToolchainInfo():
    """Information pertaining to a compiler.

    Attributes:
        tag (str): Unique short name of the toolchain.
        toolchain (str): Absolute path to the cmake toolchain file.
        description (str): Toolchain desription.
    """

    def __init__(self, tag, path, description):
        self.tag = tag
        self.path = path
        self.description = description

def get_system_toolchain_config():
    """Return the path to the system toolchains config file.

    This is $BDE_ROOT/etc/toolchains.json

    Returns:
       Path to the system config file if it exists or None
    """
    path = None

    bde_root = os.environ.get("BDE_ROOT")

    if bde_root:
        config_path = os.path.join(bde_root, "etc", "toolchains.json")
        if os.path.isfile(config_path) and os.access(config_path, os.R_OK):
            path = config_path
            print(f"Using system configuration: {path}", file=sys.stderr)

    return path


def get_user_toolchain_config():
    """Return the path to the user toolchains config file.

    This is ~/.toolchains.json if it exists or None.

    Returns:
       Path to the user config file.

    """
    config_path = os.path.join(os.path.expanduser("~"), ".toolchains.json")

    path = None

    if os.path.isfile(config_path) and os.access(config_path, os.R_OK):
        path = config_path
        print(f"Using user configuration: {path}", file=sys.stderr)

    return path

def join_absolute_pathes(path1, path2):
    seps = os.sep+os.altsep if os.altsep else os.sep
    return os.path.join(path1,os.path.splitdrive(path2)[1].lstrip(seps))

def get_toolchains_info(uplid, file_):
    """Get the list of applicable toolchains from a toolchain config file.

    Args:
        uplid (str): UPLID of the machine to be matched.
        file_ (File): The compiler configuration file.

    Returns:
        list of matched ToolchainInfo objects.
    """

    toolchains = []

    loaded_value = json.load(file_)
    for obj in loaded_value:
        matched_obj = None
        if "arch" in obj:
            if obj["arch"] == "any":
                matched_obj = obj

        # TODO: Add arch matching logic here

        if not matched_obj:
            continue

        for toolchain in matched_obj["toolchains"]:
            toolchain_path = toolchain["path"]
            if os.path.isfile(toolchain_path) and os.access(toolchain_path, os.R_OK):
                entry = ToolchainInfo(toolchain["tag"],
                                      toolchain_path,
                                      toolchain["description"])
                toolchains.append(entry)
            else:
                refroot = os.environ.get("DISTRIBUTION_REFROOT")
                if refroot:
                    toolchain_path = join_absolute_pathes(refroot, toolchain_path)
                    if os.path.isfile(toolchain_path) and os.access(toolchain_path, os.R_OK):
                        entry = ToolchainInfo(toolchain["tag"],
                                              toolchain_path,
                                              toolchain["description"])
                        toolchains.append(entry)

    return toolchains


def get_command_output(args):
    try:
        output = (
            subprocess.check_output(args, stderr=subprocess.STDOUT)
            .decode("utf8")
            .replace("\n", "")
        )
        return output
    except Exception as e:
        pass
    return None

# -----------------------------------------------------------------------------
# Copyright 2022 Bloomberg Finance L.P.
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
