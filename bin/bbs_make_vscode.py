import os
import subprocess
import sys
import shutil
import pathlib
import json
import shutil
from collections import namedtuple


def backup(path: pathlib.Path):
    try:
        shutil.copy(path, str(path) + ".bak")
    except:
        pass

    return path


binDir = pathlib.Path(__file__).parent
bdeToolsDir = binDir.parent

isGitBash = shutil.which("cygpath") is not None
isWSL = (
    not isGitBash
    and "WSL" in os.uname().release
    and "container" not in os.environ
)

def cygpath(opt, file):
    return subprocess.run(
        ["cygpath", opt, file],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()


if not isGitBash:
    bbsBuildExecutable = [binDir / "bbs_build"]
else:
    # Use the same interpreter that is interpreting this script to run the
    # 'bbs_build_env.py' using its Windows path (as opposed to its cygwin path)
    bbsBuildExecutable = [
        sys.executable,
        cygpath("-w", binDir / "bbs_build.py"),
    ]

    bashExecutable = cygpath("-w", shutil.which("bash"))

buildArea = "${workspaceFolder}"
projectCache = f"{buildArea}/.vscode"

uplid = os.getenv("BDE_CMAKE_UPLID")
ufid = os.getenv("BDE_CMAKE_UFID")
buildDir = os.getenv("BDE_CMAKE_BUILD_DIR")

if not uplid or not ufid or not buildDir:
    print("Please set the BBS build environment using 'bbs_build_env'.")
    sys.exit(1)

if not os.path.exists("CMakeLists.txt"):
    print("Error: CMakeLists.txt not found.")
    sys.exit(1)

# Parse CMake flags and environment
cmakeSettings = json.loads(
    subprocess.run(
        [
            *bbsBuildExecutable,
            "configure",
            "--dump-cmake-flags",
        ]
        + sys.argv[1:],
        capture_output=True,
    ).stdout.decode()
)

# Remove BASH_FUNC_<...>%% environment variables set by VSCode which it then
# gets confused by when we feed it back to settings.json
cmakeSettings["env"] = {
    key: value
    for key, value in cmakeSettings["env"].items()
    if "%%" not in key
}

print(f"Generating .vscode folder...")
print(f"  BDE tools directory: {bdeToolsDir}")
print(f"  Build directory:     {buildDir}")

os.makedirs(".vscode", exist_ok=True)

# Find vscode templates path
templatesLocations = [
    location
    for location in [
        bdeToolsDir / "share" / "templates" / "vscode",
        pathlib.Path(os.getenv("DISTRIBUTION_REFROOT", "/"))
        / "opt"
        / "bb"
        / "libexec"
        / "bde-tools"
        / "templates"
        / "vscode",
    ]
    if location.exists()
]

if not templatesLocations:
    print("Error: vscode templates location not found.")
    sys.exit(1)

templatesPath = templatesLocations[0]

# settings.json
settings = json.loads((templatesPath / "settings.json").read_text())

settings["cmake.copyCompileCommands"] = f"{projectCache}/compile_commands.json"
settings["clangd.arguments"].append(f"--compile-commands-dir={projectCache}")
settings["cmake.buildDirectory"] = buildDir
settings["cmake.configureSettings"] = cmakeSettings["flags"]
settings["cmake.environment"] = cmakeSettings["env"]

# Under WSL, vscode has problems downloading extensions behind proxy.
# Downloading on the host system helps.
if isWSL:
    settings["remote.downloadExtensionsLocally"] = True

platform = {"linux": "linux", "darwin": "osx", "win32": "windows"}[
    sys.platform
]
settings[f"terminal.integrated.env.{platform}"] = {
    key: value
    for key, value in cmakeSettings["env"].items()
    if "BDE" in key or "BBS" in key or key in ["CC", "CXX"]
}


def setCompiler(envVar, cmakeVar):
    compiler = os.getenv(envVar)
    if compiler:
        settings["cmake.configureSettings"][cmakeVar] = compiler


setCompiler("CC", "CMAKE_C_COMPILER")
setCompiler("CXX", "CMAKE_CXX_COMPILER")

backup(pathlib.Path(".vscode/settings.json")).write_text(
    json.dumps(settings, indent=4)
)

# cmake-variants.yaml
pathlib.Path(".vscode/cmake-variants.yaml").write_text(
    f"""\
buildType:
  default: {ufid}
  choices:
    {ufid}:
      short: {ufid}
      buildType: {cmakeSettings["flags"]["CMAKE_BUILD_TYPE"]}
"""
)

# cmake-kits.json
pathlib.Path(".vscode/cmake-kits.json").write_text(
    """\
[
  {
    "name": "bbs_build",
    "compilers": {},
    "isTrusted": true
  }
]
"""
)


# c_cpp_properties.json
backup(pathlib.Path(".vscode/c_cpp_properties.json"))
shutil.copy(templatesPath / "c_cpp_properties.json", ".vscode")

# tasks.json
tasksPath = pathlib.Path(".vscode/tasks.json")
tasks = json.loads(
    (templatesPath / "tasks.json")
    .read_text()
    .replace("$$projectCachePath$$", projectCache)
)

# Under WSL, we need the host code executable to install extensions
# behind proxy.
codepath = "code"
if isWSL:
    codepath = shutil.which("code").replace(" ", "\\ ")
for task in tasks["tasks"]:
    task["command"] = task["command"].replace("$$codepath$$", codepath)

if isGitBash:
    tasks.setdefault("options", dict()).setdefault("shell", dict()).update(
        {
            "executable": bashExecutable,
            "args": ["-l", "-c"],
        }
    )

    for task in tasks["tasks"]:
        if "bbs_build " in task["command"]:
            task.setdefault("options", dict()).setdefault(
                "env", dict()
            ).update(cmakeSettings["env"])

backup(tasksPath).write_text(json.dumps(tasks, indent=4))

# launch.json
Debugger = namedtuple("Debugger", ["extension"])
debuggers = dict(
    filter(
        lambda item: shutil.which(item[0]) is not None,
        {
            "udb": Debugger("undo.udb"),
            "gdb": Debugger(None),
            "lldb": Debugger("llvm-vs-code-extensions.lldb-dap"),
        }.items(),
    )
)

if isGitBash:
    debuggers["cppvsdbg"] = Debugger(None)

commonLaunchArgs = json.loads(
    (templatesPath / "common_launch_args.json")
    .read_text()
    .replace("$$executableSuffix$$", ".exe" if isGitBash else "")
)

installBdePrettyPrinters = False
launchConfigs = []
for debuggerName in debuggers.keys():
    for name, launchArgs in commonLaunchArgs.items():
        configText = (
            templatesPath / f"{debuggerName}_launch.json"
        ).read_text()
        installBdePrettyPrinters = (
            installBdePrettyPrinters
            or "init-bde-pretty-printers" in configText
        )
        config = json.loads(configText)
        config["name"] = config["name"] + name
        config.update(launchArgs)
        launchConfigs.append(config)

launch = json.loads((templatesPath / "launch.json").read_text())
launch["configurations"] = launchConfigs
backup(pathlib.Path(".vscode/launch.json")).write_text(
    json.dumps(launch, indent=4)
)

# extensions.json
extensions = json.loads((templatesPath / "extensions.json").read_text())
extensions["recommendations"].extend(
    [
        debugger.extension
        for debugger in debuggers.values()
        if debugger.extension is not None
    ]
)

backup(pathlib.Path(".vscode/extensions.json")).write_text(
    json.dumps(extensions, indent=4)
)


# mcp.json — configures VS Code's built-in MCP client to launch the
# bbs_build MCP server with the resolved build environment. BBS_ENV_MARKER
# makes the server adopt the BDE_CMAKE_* values verbatim so it matches the
# CMake Tools kit.
bbsBuildMcp = bdeToolsDir / "contrib" / "mcp" / "bbs_build_mcp"
mcp = json.loads((templatesPath / "mcp.json").read_text())
server = mcp["servers"]["bbs-build"]
server["command"] = str(bbsBuildMcp)
# BDE/BBS/CC/CXX vars for the compiler, plus DISTRIBUTION_REFROOT which
# the server reads directly.
mcpEnv = {
    key: value
    for key, value in cmakeSettings["env"].items()
    if (
        "BDE" in key
        or "BBS" in key
        or key in ("CC", "CXX", "DISTRIBUTION_REFROOT")
    )
}
# DISTRIBUTION_REFROOT is passed to cmake as -D... and not part of the
# compiler env; fall back to the CMake flag dump or the current shell.
if "DISTRIBUTION_REFROOT" not in mcpEnv:
    refroot = cmakeSettings["flags"].get(
        "DISTRIBUTION_REFROOT"
    ) or os.getenv("DISTRIBUTION_REFROOT")
    if refroot:
        mcpEnv["DISTRIBUTION_REFROOT"] = refroot
server["env"] = mcpEnv
backup(pathlib.Path(".vscode/mcp.json")).write_text(json.dumps(mcp, indent=4))

# bbs-build.instructions.md — auto-loaded by Copilot Chat from directories
# listed in `chat.instructionsFilesLocations` (set in settings.json). The
# imperative snippet steers the model toward the bbs-build MCP tools
# instead of raw cmake/ninja/bbs_build invocations.
backup(pathlib.Path(".vscode/bbs-build.instructions.md")).write_text(
    """\
---
applyTo: "**"
---
## Build & test in this workspace

This is a BDE / BBS workspace. A `bbs-build` MCP server is configured in
`.vscode/mcp.json`. **Always use the `bbs-build` MCP tools for build,
configure, and test operations. Do not invoke `cmake`, `cmake --build`,
`ninja`, `make`, `bbs_build`, `ctest`, or `bde_runtest` in the terminal
for these purposes** — the MCP tools use the correct UFID / refroot /
build directory and return structured diagnostics.

- Configure the build: use the `configure` tool.
- Compile: use the `build` tool (pass `targets=[...]` for a single
  component; pass `dependers_of=[...]` with `run_tests=true` to validate
  a change against every dependent component).
- Run tests: use the `test` tool (call `build` first with
  `with_tests=true` if the tests are not built yet).

The UFID / build directory is fixed by the IDE's build environment and
must not be overridden per-call.
"""
)


# pretty-printers
gdbinit = f"""\
python
## Import bde pretty printers
import sys

sys.path.append("{binDir.parent / "contrib" / "gdb-printers"}")
import bde_printer

bde_printer.reload()
end
"""

if installBdePrettyPrinters:
    pathlib.Path(".vscode/init-bde-pretty-printers").write_text(gdbinit)


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
