import json
import os
import pathlib
import shutil
import subprocess
import sys


def removeBuildType(ufid: str):
    return "_".join([x for x in ufid.split("_") if not x in ["opt", "dbg"]])


def addBuildType(buildType: str, ufid: str):
    return buildType if len(ufid) == 0 else buildType + "_" + ufid


binDir = pathlib.Path(__file__).parent
bdeToolsDir = binDir.parent

isGitBash = shutil.which("cygpath") is not None

if not isGitBash:
    print(f"{pathlib.Path(__file__).name} is for use in Windows GitBash only.")
    sys.exit(1)


# Use the same interpreter that is interpreting this script to run the
# 'bbs_build_env.py' using its Windows path (as opposed to its cygwin path)
bbsBuildExecutable = [
    sys.executable,
    subprocess.run(
        ["cygpath", "-w", binDir / "bbs_build.py"],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip(),
]

uplid = os.getenv("BDE_CMAKE_UPLID")
ufid = os.getenv("BDE_CMAKE_UFID")

if not uplid or not ufid:
    print("Please set the BBS build environment using 'bbs_build_env'.")
    sys.exit(1)

ufid = removeBuildType(ufid)

if not os.path.exists("CMakeLists.txt"):
    print("Error: CMakeLists.txt not found.")
    sys.exit(1)

# Parse CMake flags
cmakeFlagsList = subprocess.run(
    [
        *bbsBuildExecutable,
        "configure",
        "--dump-cmake-flags",
    ]
    + sys.argv[1:],
    capture_output=True,
).stdout.decode()

cmakeFlags = {}
for arg in cmakeFlagsList.split():
    key, value = arg.split("=")

    # Remove -D and the type
    key = key.replace("-D", "").split(":")[0]

    cmakeFlags[key] = value

cmakeFlags.pop("CMAKE_BUILD_TYPE")

print("Generating CMakePresets.json...")

presets = {"version": 4}

arch = "x64" if "BDE_BUILD_TARGET_64" in cmakeFlags else "x86"

presets["configurePresets"] = []
for buildType, cmakeBuildType in {
    "dbg": "Debug",
    "opt": "Release",
    "opt_dbg": "RelWithDebInfo",
}.items():
    buildUfid = addBuildType(buildType, ufid)
    presets["configurePresets"].append(
        {
            "name": buildType,
            "displayName": f"{buildUfid} ({cmakeBuildType})",
            "generator": "Ninja",
            "binaryDir": f"${{sourceDir}}/_build/{uplid}-{buildUfid}",
            "architecture": {"value": arch, "strategy": "external"},
            "cacheVariables": {
                "CMAKE_BUILD_TYPE": cmakeBuildType,
                **cmakeFlags,
            },
        }
    )

pathlib.Path("CMakeUserPresets.json").write_text(json.dumps(presets, indent=4))


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
