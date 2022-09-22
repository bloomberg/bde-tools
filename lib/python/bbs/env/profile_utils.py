"""Configure the available compilers.
"""
import json
import re
import os
import string
import sys
import subprocess

from pathlib import Path

from bbs.common import blderror
from bbs.common import msvcversions
from bbs.common import sysutil
from bbs.uplid import uplid as Uplid

class BuildProfile():
    """Information pertaining to a build profile.
       This object describes a BDE equivalent of the cmake presets
       which is roughly the compiler + toolchain pair.
       Note that build profile can define only a [named] toolchain
       ( and the toolchain will define path to a compiler ) 

    Attributes:
        name (str): Build profile name
        compiler_type (str): Type of the compiler ("gcc", "clang") 
        c_path (str): Path to the C compiler executable.
        cxx_path (str): Path to the C++ compiler executable.
        version (str): Version number of the compiler.
        toolchain (str): Path to the cmake toolchain file.
        properties(dict): Properties of the the toolchain.
        flags (str, optional): Arguments to pass to the compiler.
        desc (str, optional): Custom description, by default, the description()
            method returns type_ + '-' + version.
    """

    def __init__(
        self,
        name,
        compiler_type = None,
        c_path = None,
        cxx_path = None,
        version = None,
        toolchain = None,
        properties = None,
        desc = None,
    ):
        self.name = name
        self.compiler_type = compiler_type
        self.version = version
        self.c_path = c_path
        self.cxx_path = cxx_path
        self.toolchain = toolchain
        self.properties = properties
        self.desc = desc

    def key(self):
        return self.name

    def description(self):
        if self.desc:
            return self.desc
        else:
            return self.key()


def get_system_profile_path():
    """Return the path to the compiler configuration file.

    This is $BDE_ROOT/bbs_build_profiles

    Returns:
       Path to the system config file if it exists or None
    """

    bde_root = os.environ.get("BDE_ROOT")

    if bde_root:
        config_path = Path(bde_root).joinpath("etc/bbs_build_profiles")
        if config_path.exists() and os.access(config_path, os.R_OK):
            print(f"Using system configuration: {config_path}", file=sys.stderr)
            return config_path

    return None


def get_user_profile_path():
    """Return the path to the user compiler configuration file.

    This is ~/.bbs_build_profiles if it exists or None.

    Returns:
       Path to the user config file.

    """
    config_path = Path.home() / ".bbs_build_profiles"

    if config_path.exists() and os.access(config_path, os.R_OK):
        print(f"Using user configuration: {config_path}", file=sys.stderr)
        return config_path

    return None


def find_toolchain_file(toolchain):
    """ Make best effort to find existing toolchain file.
    """

    if toolchain:

        # Checking absolute/relative path to the toolchain
        p = Path(toolchain + ".cmake")
        if p.exists():
            return p.resolve()

        p = Path(toolchain)
        if p.exists():
            return p.resolve()

        # Checking bbs toolchains
        toolchain_locations = []

        refroot = os.getenv("DISTRIBUTION_REFROOT", "/")

        toolchain_locations.append(Path(refroot).resolve())
        toolchain_locations.append(Path(refroot).resolve().joinpath("opt/bb/cmake/change/BdeBuildSystem/toolchains", sysutil.unversioned_platform()))
        toolchain_locations.append(Path(sys.argv[0]).resolve().parent.parent.joinpath("BdeBuildSystem/toolchains", sysutil.unversioned_platform()))
        toolchain_locations.append(Path.cwd().resolve())

        for folder in toolchain_locations:
            p = folder.joinpath(toolchain + ".cmake")
            if p.exists():
                return p.resolve()

            p = folder.joinpath(toolchain)
            if p.exists():
                return p.resolve()

    return None

def filter_valid_profiles(uplid, profile_config):
    matched_obj = None

    profiles = []

    for obj in profile_config:
        uplid_mask = Uplid.Uplid.from_str(obj["uplid"])
        if not Uplid.match_uplid(uplid, uplid_mask):
            continue

        matched_obj = obj

        if not matched_obj:
            continue

        for profile in matched_obj["profiles"]:
            name = profile.get("name")
            compiler_type = profile.get("type")
            c_path = profile.get("c_path")
            cxx_path = profile.get("cxx_path")

            version = profile.get("version")

            if not name:
                name = compiler_type
                if version:
                    name += "-" + version


            toolchain = profile.get("toolchain")

            properties = profile.get("properties")

            desc = profile.get("description", "Generic build profile")

            if not toolchain and compiler_type:
                toolchain = compiler_type + "_default"

            toolchain = find_toolchain_file(toolchain)

            if ( not c_path or not cxx_path ) and not toolchain:
                # Invalid entry - no compilers, no toolchain
                continue

            build_profile = BuildProfile(name,
                                         compiler_type,
                                         c_path,
                                         cxx_path,
                                         version,
                                         toolchain,
                                         properties,
                                         desc)
            profiles.append(build_profile)

    return profiles


def get_production_profiles(uplid):
    """Get the list of production toolchains

    Args:
        uplid (str): UPLID of the machine to be matched.

    Returns:
        list of matched profiles
    """

    prod_profiles = """
            [
                {
                    "uplid": "unix-linux",
                    "profiles": [
                        {
                            "name": "BBToolchain64",
                            "description": "Production toolchain for dpkg builds, 64-bit.",
                            "toolchain": "opt/bb/share/plink/BBToolchain64.cmake",
                            "properties": {
                                "noexc": false,
                                "bitness": 64,
                                "standard": "cpp17",
                                "sanitizer": false,
                                "assert_level": "default",
                                "review_level": "default"
                            }
                        },
                        {
                            "name": "BBToolchain32",
                            "description": "Production toolchain for dpkg builds, 32-bit.",
                            "toolchain": "opt/bb/share/plink/BBToolchain32.cmake",
                            "properties": {
                                "noexc": false,
                                "bitness": 32,
                                "standard" : "cpp17",
                                "sanitizer": false,
                                "assert_level": "default",
                                "review_level": "default"
                            }
                        }
                    ]
                },
                {
                    "uplid": "unix-sunos",
                    "profiles": [
                        {
                            "name": "BBToolchain64",
                            "description": "Production toolchain for dpkg builds, 64-bit.",
                            "toolchain": "opt/bb/share/plink/BBToolchain64.cmake",
                            "properties": {
                                "noexc": false,
                                "bitness": 64,
                                "standard": "cpp03",
                                "sanitizer": false,
                                "assert_level": "default",
                                "review_level": "default"
                            }
                        },
                        {
                            "name": "BBToolchain32",
                            "description": "Production toolchain for dpkg builds, 32-bit.",
                            "toolchain": "opt/bb/share/plink/BBToolchain32.cmake",
                            "properties": {
                                "noexc": false,
                                "bitness": 32,
                                "standard" : "cpp03",
                                "sanitizer": false,
                                "assert_level": "default",
                                "review_level": "default"
                            }
                        }
                    ]
                },
                {
                    "uplid": "unix-aix",
                    "profiles": [
                        {
                            "name": "BBToolchain64",
                            "description": "Production toolchain for dpkg builds, 64-bit.",
                            "toolchain": "opt/bb/share/plink/BBToolchain64.cmake",
                            "properties": {
                                "noexc": false,
                                "bitness": 64,
                                "standard": "cpp03",
                                "sanitizer": false,
                                "assert_level": "default",
                                "review_level": "default"
                            }
                        },
                        {
                            "name": "BBToolchain32",
                            "description": "Production toolchain for dpkg builds, 32-bit.",
                            "toolchain": "opt/bb/share/plink/BBToolchain32.cmake",
                            "properties": {
                                "noexc": false,
                                "bitness": 32,
                                "standard" : "cpp03",
                                "sanitizer": false,
                                "assert_level": "default",
                                "review_level": "default"
                            }
                        }
                    ]
                }
            ]
    """

    loaded_value = json.loads(prod_profiles)

    return filter_valid_profiles(uplid, loaded_value)

def get_config_profiles(uplid, file_):
    """Get the list of applicable profiles from a profile file.

    Args:
        uplid (str): UPLID of the machine to be matched.
        file_ (File): The compiler configuration file.

    Returns:
        list of matched CompilerInfo objects.
    """

    loaded_value = json.load(file_)
    return filter_valid_profiles(uplid, loaded_value)

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

    default_config = """ [ { "uplid": "unix-",
                           "profiles": [
                               {
                                   "type":      "gcc",
                                   "c_name":    "gcc",
                                   "cxx_name":  "g++"
                               },
                               {
                                   "type":      "clang",
                                   "c_name":    "clang",
                                   "cxx_name":  "clang++"
                               }
                            ]
                          }
                        ]
    """

    loaded_value = json.loads(default_config)
    matched_obj = None
    for obj in loaded_value:
        uplid_mask = Uplid.Uplid.from_str(obj["uplid"])
        if not Uplid.match_uplid(uplid, uplid_mask):
            continue

        matched_obj = obj
        break

    if not matched_obj:
        return []

    profiles = []

    for profile in matched_obj["profiles"]:
        for version in [ "" ] + [ str(n) for n in range(7, 15) ]:
            c_name = profile["c_name"]
            cxx_name = profile["cxx_name"]

            if (version != ""):
                c_name += "-" + version
                cxx_name += "-" + version

            c_path = get_command_output(["which", c_name])
            cxx_path = get_command_output(["which", cxx_name])

            if (
                c_path
                and os.path.exists(c_path)
                and cxx_path
                and os.path.isfile(cxx_path)
            ):
                compiler_version = get_compiler_version(profile["type"], cxx_path)

                if not compiler_version:
                    continue

                compiler_type = profile["type"]
                name = compiler_type + "-" + compiler_version
                toolchain = profile.get("toolchain")

                if not toolchain:
                    toolchain = compiler_type + "-default"

                toolchain = find_toolchain_file(toolchain)

                profiles.append(BuildProfile(name,
                                             compiler_type,
                                             c_path,
                                             cxx_path,
                                             compiler_version,
                                             toolchain,
                                             None))

    return profiles

def find_installdir(version):
    vswhere_path = Path(__file__).parent.parent.parent.parent.parent / "bin" / "vswhere.exe"

    output = subprocess.check_output(
        [vswhere_path, "-prerelease", "-legacy", "-format", "json"]
    )
    compilers = json.loads(output.decode("ascii", errors="ignore"))
    for cl in compilers:
        if cl["installationVersion"].startswith(version):
            return cl["installationPath"]
    return None

def get_build_profiles():
    os_type, os_name, cpu_type, os_ver = sysutil.get_os_info()
    if os_type != "windows":

        uplid = Uplid.Uplid(os_type, os_name, cpu_type, os_ver)

        prod_profiles = get_production_profiles(uplid)

        config_path = get_user_profile_path()
        user_profiles = []
        if config_path:
            with open(config_path, "r") as f:
                user_profiles = get_config_profiles(uplid, f)

        config_path = get_system_profile_path()
        system_profiles = []
        if config_path:
            with open(config_path, "r") as f:
                system_profiles = get_config_profiles(uplid, f)

        return prod_profiles + user_profiles + system_profiles + detect_installed_compilers(uplid)
    else:
        build_profiles = []
        for v in msvcversions.versions:
            if not find_installdir(v.product_version):
                continue

            profile = BuildProfile(
                f"msvc-{v.product_name.split()[-1]}",
                v.product_name.split()[-1],
                None,
                None,
                toolchain=find_toolchain_file("cl-default"),
                desc=f"msvc-{v.product_name.split()[-1]} -- {v.product_name} (Version {v.product_version})"
            )
            build_profiles.append(profile)

        return build_profiles

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
