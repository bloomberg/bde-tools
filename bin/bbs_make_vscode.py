import os
import subprocess
import sys

def quotedCMakeArgValue(value):
    if value in ["0", "OFF", "NO", "FALSE", "N"]:
        return "false"
    if value in ["1", "ON", "YES", "TRUE", "Y"]:
        return "true"
    return f'"{value}"'


# If BDE_TOOLS_DIR is not specified, try finding it via 'which' and default
# to '/bb/bde/bbshr/bde-tools'
bdeToolsDir = os.getenv("BDE_TOOLS_DIR")

if not bdeToolsDir:
    try:
        whichBuildEnv = subprocess.run(
            ["which", "bbs_build"], stdout=subprocess.PIPE, text=True
        ).stdout
        bdeToolsDir = os.path.dirname(os.path.dirname(whichBuildEnv))
    except:
        bdeToolsDir = "/bb/bde/bbshr/bde-tools"

bdeCmakeBuildDir = os.getenv("BDE_CMAKE_BUILD_DIR")

if not bdeCmakeBuildDir:
    print("Please set the BBS build environment using 'bbs_build_env'.")
    sys.exit(1)

bdeCmakeBuildDir = (
    bdeCmakeBuildDir.replace("opt_", "").replace("dbg_", "")
    + "-vscode-${buildType}"
)

# Parse CMake flags
cmake_flags_list = subprocess.run(
    [
        os.path.join(bdeToolsDir, "bin", "bbs_build"),
        "configure",
        "--dump-cmake-flags",
    ],
    capture_output=True,
).stdout.decode()

cmake_flags = {}
for arg in cmake_flags_list.split():
    key, value = arg.split("=")

    # Remove -D and the type
    key = key.replace("-D", "").split(":")[0]

    if key == "CMAKE_BUILD_TYPE":
        continue

    cmake_flags[key] = value

cmake_flags_string = ",\n".join(
    (
        f'        "{key}": {quotedCMakeArgValue(value)}'
        for key, value in cmake_flags.items()
    )
)

print(f"Generating .vscode folder...")
print(f"  BDE tools directory: {bdeToolsDir}")
print(f"  Build directory:     {bdeCmakeBuildDir}")

os.makedirs(".vscode", exist_ok=True)

with open(".vscode/settings.json", "wt") as settings:
    settings.write(
        f"""
{{
    "cmake.configureOnOpen": true,
    "cmake.buildDirectory": "${{workspaceFolder}}/{bdeCmakeBuildDir}",
    "cmake.generator": "Ninja",
    "cmake.parallelJobs": 0,
    "cmake.configureSettings": {{
{cmake_flags_string}
    }},
    "cmake.ctestArgs": ["-L", "^${{command:cmake.buildTargetName}}$"],
    "C_Cpp.default.configurationProvider": "ms-vscode.cmake-tools",
    "files.associations": {{
        "*.ipp": "cpp"
    }},
    "terminal.integrated.defaultProfile.linux": "bash",
    "files.exclude": {{
        "**/.git": true,
        "**/_build": true
    }}
}}
"""
    )

with open(".vscode/c_cpp_properties.json", "wt") as settings:
    settings.write(
        f"""
{{
    "configurations": [
        {{
            "name": "CMake",
            "configurationProvider": "ms-vscode.cmake-tools"
        }}
    ],
    "version": 4
}}
"""
    )

with open(".vscode/launch.json", "wt") as settings:
    settings.write(
        f"""
{{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {{
            "name": "(gdb) Launch",
            "type": "cppdbg",
            "request": "launch",
            "program": "${{command:cmake.launchTargetPath}}",
            "args": ["${{input:args}}"],
            "stopAtEntry": true,
            "cwd": "${{command:cmake.getLaunchTargetDirectory}}",
            "environment": [],
            "externalConsole": false,
            "MIMode": "gdb",
            "setupCommands": [
                {{
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }}
            ]
        }},
        {{
            "name": "(UDB) Launch",
            "type": "cppdbg",
            "request": "launch",
            "program": "${{command:cmake.launchTargetPath}}",
            "args": ["${{input:args}}"],
            "stopAtEntry": true,
            "cwd": "${{command:cmake.getLaunchTargetDirectory}}",
            "environment": [],
            "externalConsole": false,
            "MIMode": "gdb",
            "setupCommands": [
                {{
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }}
            ],
            "miDebuggerPath": "udb",
            "miDebuggerArgs": "--max-event-log-size 4G",
            "logging": {{
                "trace": false,
                "traceResponse": false,
                "engineLogging": false
            }},
            "udb": "live",
            "timezone": ""
        }},
    ],
    "inputs": [
        {{
            "id": "args",
            "type":"promptString",
            "description": "Program Args",
            "default": "0"
        }}
    ]
}}
"""
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
