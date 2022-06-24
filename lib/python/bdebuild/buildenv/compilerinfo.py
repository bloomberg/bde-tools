"""Configure the available compilers.
"""

from __future__ import print_function

import json
import re
import os
import string
import sys
import subprocess

from bdebuild.common import blderror
from bdebuild.common import mixins

from bdebuild.meta import optiontypes
from bdebuild.meta import optionsutil


class CompilerInfo(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """Information pertaining to a compiler.

    Attributes:
        type_ (str): Type of the compiler.
        version (str): Version number of the compiler.
        c_path (str): Path to the C compiler executable.
        cxx_path (str): Path to the C++ compiler executable.
        toolchain (str): Path to the cmake toolchain file.
        flags (str, optional): Arguments to pass to the compiler.
        desc (str, optional): Custom description, by default, the description()
            method returns type_ + '-' + version.
    """

    def __init__(
        self,
        type_,
        version,
        c_path,
        cxx_path,
        toolchain=None,
        flags=None,
        desc=None,
    ):
        self.type_ = type_
        self.version = version
        self.c_path = c_path
        self.cxx_path = cxx_path
        self.toolchain = toolchain
        self.flags = flags
        self.desc = desc

    def key(self):
        return self.type_ + "-" + self.version

    def description(self):
        if self.desc:
            return self.desc
        else:
            return self.key()


def get_system_config_path():
    """Return the path to the compiler configuration file.

    This is $BDE_ROOT/bdecompilerconfig.

    Returns:
       Path to the system config file if it exists or None
    """
    path = None

    bde_root = os.environ.get("BDE_ROOT")

    if bde_root:
        config_path = os.path.join(bde_root, "etc", "bdecompilerconfig")
        if os.path.isfile(config_path) and os.access(config_path, os.R_OK):
            path = config_path
            print("Using system configuration: %s" % path, file=sys.stderr)

    return path


def get_user_config_path():
    """Return the path to the user compiler configuration file.

    This is ~/.bdecompilerconfig if it exists or None.

    Returns:
       Path to the user config file.

    """
    config_path = os.path.join(os.path.expanduser("~"), ".bdecompilerconfig")

    path = None

    if os.path.isfile(config_path) and os.access(config_path, os.R_OK):
        path = config_path
        print("Using user configuration: %s" % path, file=sys.stderr)

    return path


def get_compilerinfos(hostname, uplid, file_):
    """Get the list of applicable compilers from a compiler config file.

    Args:
        hostname (str): Hostname of the machine to be matched.
        uplid (str): UPLID of the machine to be matched.
        file_ (File): The compiler configuration file.

    Returns:
        list of matched CompilerInfo objects.
    """

    loaded_value = json.load(file_)
    matched_obj = None
    for obj in loaded_value:
        if "hostname" in obj:
            m = re.match(obj["hostname"], hostname)
            if not m:
                continue

        uplid_mask = optiontypes.Uplid.from_str(obj["uplid"])
        if not optionsutil.match_uplid(uplid, uplid_mask):
            continue

        matched_obj = obj
        break

    if not matched_obj:
        return []

    infos = []

    for compiler in matched_obj["compilers"]:
        type_ = compiler["type"]
        version = compiler["version"]
        c_path = compiler["c_path"]
        cxx_path = compiler["cxx_path"]
        if "toolchain" in compiler:
            toolchain = compiler["toolchain"]
        else:
            toolchain = None

        if "flags" in compiler:
            flags = compiler["flags"]
        else:
            flags = None
        info = CompilerInfo(type_, version, c_path, cxx_path, toolchain, flags)
        infos.append(info)

    return infos


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


def get_compiler_version(compiler_type, cxx_path):
    version = None
    if "gcc" == compiler_type:
        version = get_command_output(
            [cxx_path, "-dumpfullversion", "-dumpversion"]
        )

    if "clang" == compiler_type:
        version = get_command_output([cxx_path, "--version"])
        m = re.search("version\s+([0-9\.]+)", version)
        version = m.group(1) if m else "0.0.0"

    return version


def detect_installed_compilers(uplid):
    """Find installed system compilers. This function is expected to work
       primarily on Linux/Darwin in OSS environment.

    Args:
        uplid (str): UPLID of the machine to be matched.

    Returns:
        list of matched CompilerInfo objects.
    """

    default_config = """ [ { "uplid": "unix-linux-",
                           "compilers": [
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc",
                                   "cxx_name":  "g++",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-6",
                                   "cxx_name":  "g++-6",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-7",
                                   "cxx_name":  "g++-7",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-8",
                                   "cxx_name":  "g++-8",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-9",
                                   "cxx_name":  "g++-9",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-10",
                                   "cxx_name":  "g++-10",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-11",
                                   "cxx_name":  "g++-11",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang",
                                   "cxx_name":  "clang++",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-7",
                                   "cxx_name":  "clang++-7",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-8",
                                   "cxx_name":  "clang++-8",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-9",
                                   "cxx_name":  "clang++-9",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-10",
                                   "cxx_name":  "clang++-10",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-11",
                                   "cxx_name":  "clang++-11",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-12",
                                   "cxx_name":  "clang++-12",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-13",
                                   "cxx_name":  "clang++-13",
                                   "toolchain": "clang-default"
                               }
                            ]
                          },
                          { "uplid": "unix-sunos-",
                            "compilers": [
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc",
                                   "cxx_name":  "g++",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-5",
                                   "cxx_name":  "g++-5",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-6",
                                   "cxx_name":  "g++-6",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-7",
                                   "cxx_name":  "g++-7",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-8",
                                   "cxx_name":  "g++-8",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-9",
                                   "cxx_name":  "g++-9",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-10",
                                   "cxx_name":  "g++-10",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-11",
                                   "cxx_name":  "g++-11",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang",
                                   "cxx_name":  "clang++",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-9",
                                   "cxx_name":  "clang++-9",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-10",
                                   "cxx_name":  "clang++-10",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-11",
                                   "cxx_name":  "clang++-11",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-12",
                                   "cxx_name":  "clang++-12",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-13",
                                   "cxx_name":  "clang++-13",
                                   "toolchain": "clang-default"
                               }
                            ]
                          },
                          { "uplid": "unix-aix-",
                            "compilers": [
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc",
                                   "cxx_name":  "g++",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-5",
                                   "cxx_name":  "g++-5",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-6",
                                   "cxx_name":  "g++-6",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-7",
                                   "cxx_name":  "g++-7",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-8",
                                   "cxx_name":  "g++-8",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-9",
                                   "cxx_name":  "g++-9",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-10",
                                   "cxx_name":  "g++-10",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-11",
                                   "cxx_name":  "g++-11",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang",
                                   "cxx_name":  "clang++",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-9",
                                   "cxx_name":  "clang++-9",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-10",
                                   "cxx_name":  "clang++-10",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-11",
                                   "cxx_name":  "clang++-11",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-12",
                                   "cxx_name":  "clang++-12",
                                   "toolchain": "clang-default"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang-13",
                                   "cxx_name":  "clang++-13",
                                   "toolchain": "clang-default"
                               }
                            ]
                          },
                          { "uplid": "unix-darwin-",
                            "compilers": [
                               {
                                  "type":      "clang",
                                  "c_name":    "clang",
                                  "cxx_name":  "clang++",
                                  "toolchain": "clang-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-9",
                                   "cxx_name":  "g++-9",
                                   "toolchain": "gcc-default"
                               },
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc-10",
                                   "cxx_name":  "g++-10",
                                   "toolchain": "gcc-default"
                               }
                            ]
                          }
                        ]
    """

    loaded_value = json.loads(default_config)
    matched_obj = None
    for obj in loaded_value:
        uplid_mask = optiontypes.Uplid.from_str(obj["uplid"])
        if not optionsutil.match_uplid(uplid, uplid_mask):
            continue

        matched_obj = obj
        break

    if not matched_obj:
        return []

    infos = []

    for compiler in matched_obj["compilers"]:
        c_path = get_command_output(["which", compiler["c_name"]])
        cxx_path = get_command_output(["which", compiler["cxx_name"]])

        if (
            c_path
            and os.path.exists(c_path)
            and cxx_path
            and os.path.isfile(cxx_path)
        ):
            version = get_compiler_version(compiler["type"], cxx_path)

            if not version:
                continue

            if "toolchain" in compiler:
                toolchain = compiler["toolchain"]
            else:
                toolchain = None

            info = CompilerInfo(
                compiler["type"], version, c_path, cxx_path, toolchain, None
            )
            infos.append(info)

    return infos


# -----------------------------------------------------------------------------
# Copyright 2018 Bloomberg Finance L.P.
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
