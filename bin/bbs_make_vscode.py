import os
import subprocess
import sys
import shutil
import pathlib
from string import Template


def quotedCMakeArgValue(value):
    if value in ["0", "OFF", "NO", "FALSE", "N"]:
        return "false"
    if value in ["1", "ON", "YES", "TRUE", "Y"]:
        return "true"
    return '"{}"'.format(value.replace("\\", "/"))

def removeBuildType(ufid: str):
    return "_".join([x for x in ufid.split("_") if not x in ["opt", "dbg"]])

binDir = pathlib.Path(__file__).parent
bdeToolsDir = binDir.parent

isGitBash = shutil.which("cygpath") is not None

if not isGitBash:
    bbsBuildExecutable = [binDir / "bbs_build"]
else:
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

buildDir = f"_build/{uplid}-{removeBuildType(ufid)}-vscode-${{buildType}}"

# Parse CMake flags
cmakeFlagsList = subprocess.run(
    [
        *bbsBuildExecutable,
        "configure",
        "--dump-cmake-flags",
    ],
    capture_output=True,
).stdout.decode()

cmakeFlags = {}
for arg in cmakeFlagsList.split():
    key, value = arg.split("=")

    # Remove -D and the type
    key = key.replace("-D", "").split(":")[0]

    if key == "CMAKE_BUILD_TYPE":
        continue

    cmakeFlags[key] = value

cmakeFlagsString = ",\n".join(
    (
        f'        "{key}": {quotedCMakeArgValue(value)}'
        for key, value in cmakeFlags.items()
    )
)

print(f"Generating .vscode folder...")
print(f"  BDE tools directory: {bdeToolsDir}")
print(f"  Build directory:     {buildDir}")

os.makedirs(".vscode", exist_ok=True)

templatesPath = binDir / "vscode_templates"

# settings.json
settingsTemplate = Template((templatesPath / "settings.json.in").read_text())
pathlib.Path(".vscode/settings.json").write_text(
    settingsTemplate.substitute(
        buildDir=buildDir, cmakeFlags=cmakeFlagsString
    )
)

# c_cpp_properties.json
shutil.copy(templatesPath / "c_cpp_properties.json", ".vscode")

# launch.json
if not isGitBash:
    launchConfigs = ",\n".join(
        [
            (templatesPath / "gdb_launch.json").read_text(),
            (templatesPath / "udb_launch.json").read_text(),
        ]
    )
else:
    launchConfigs = (templatesPath / "cppvsdbg_launch.json").read_text()

launchTemplate = Template((templatesPath / "launch.json.in").read_text())
pathlib.Path(".vscode/launch.json").write_text(
    launchTemplate.substitute(launchConfigs=launchConfigs)
)

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
