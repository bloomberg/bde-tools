#!/usr/bin/env python3

from checkversion import checkversion
checkversion()

import os
import subprocess
import sys


# If BDE_TOOLS_DIR is not specified, try finding it via 'which' and default
# to '/bb/bde/bbshr/bde-tools'
bdeToolsDir = os.getenv("BDE_TOOLS_DIR")

if not bdeToolsDir:
    try:
        whichBuildEnv = subprocess.run(
            ["which", "bde_build_env.py"], stdout=subprocess.PIPE, text=True
        ).stdout
        bdeToolsDir = os.path.dirname(os.path.dirname(whichBuildEnv))
    except:
        bdeToolsDir = "/bb/bde/bbshr/bde-tools"

bdeCmakeBuildDir = os.getenv("BDE_CMAKE_BUILD_DIR")
bdeCmakeToolchain = os.getenv("BDE_CMAKE_TOOLCHAIN")
bdeCmakeUfid = os.getenv("BDE_CMAKE_UFID")

if not bdeCmakeBuildDir or not bdeCmakeToolchain or not bdeCmakeUfid:
    print("Please set the BDE build environment using 'bde_build_env.py'.")
    sys.exit(1)

print(f"Generating .vscode folder...")
print(f"  BDE tools directory: {bdeToolsDir}")
print(f"  Build directory:     {bdeCmakeBuildDir}")
print(f"  Toolchain:           {bdeCmakeToolchain}")
print(f"  UFID:                {bdeCmakeUfid}")

os.makedirs(".vscode", exist_ok=True)

with open(".vscode/settings.json", "wt") as settings:
    settings.write(
        f"""
{{
    "cmake.configureOnOpen": false,
    "cmake.buildDirectory": "${{workspaceFolder}}/{bdeCmakeBuildDir}",
    "cmake.generator": "Ninja",
    "cmake.parallelJobs": 0,
    "cmake.configureSettings": {{
        "CMAKE_MODULE_PATH": "{bdeToolsDir}/cmake",
        "CMAKE_EXPORT_COMPILE_COMMANDS": true,
        "CMAKE_TOOLCHAIN_FILE": "{bdeToolsDir}/cmake/{bdeCmakeToolchain}.cmake",
        "BUILD_BITNESS": "64",
        "UFID": "{bdeCmakeUfid}"
    }},
    "cmake.ctestArgs": ["-L", "${{command:cmake.buildTargetName}}"],
    "C_Cpp.default.configurationProvider": "ms-vscode.cmake-tools",
    "files.associations": {{
        "*.ipp": "cpp"
    }},
    "terminal.integrated.defaultProfile.linux": "bash"
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
            "compileCommands": "${{workspaceFolder}}/{bdeCmakeBuildDir}/compile_commands.json",
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
