import argparse
import json
import os
import re
import sys

from pathlib import Path


def get_dependers(targets, output_targets, no_missing_target_warning=False):
    json_path = locate_compile_commands_json()
    if not json_path:
        return None

    compile_commands = read_compile_commands_json(json_path)
    if not compile_commands:
        return None

    component_files = read_valid_components(compile_commands)
    if not component_files:
        return None
    add_bsl_bslhdrs(compile_commands, component_files)

    dependers, test_dependers = get_all_dependers(component_files)

    dependers_of_targets = get_dependers_of_targets(
        targets, dependers, test_dependers, output_targets, component_files,
        no_missing_target_warning
    )
    return sorted(dependers_of_targets)


def locate_compile_commands_json():
    if os.environ.get("BDE_CMAKE_BUILD_DIR"):
        json_path = os.path.join(
            os.getcwd(),
            os.environ.get("BDE_CMAKE_BUILD_DIR"),
            "compile_commands.json",
        )
        if not os.path.exists(json_path):
            print("'compile_commands.json' not found")
            return None
        return json_path

    print("'BDE_CMAKE_BUILD_DIR' not set")
    return None


def read_compile_commands_json(json_path: str):
    with open(json_path, "r") as f:
        return json.load(f)


def read_valid_components(compile_commands):
    components = {}
    for command in compile_commands:
        cpp_path = Path(command["file"])
        component_name = cpp_path.name.partition(".")[0]

        if component_name in components:
            continue

        fullExt = lambda name: "".join(Path(name).suffixes)

        components[component_name] = {
            fullExt(path): str(path.absolute())
            for path in cpp_path.parent.glob(f"{component_name}.*")
            if path.suffix in [".h", ".hpp", ".c", ".cpp"] and path.is_file()
        }

    return components


def add_bsl_bslhdrs(compile_commands, component_files):
    # Add all headers in 'bsl+bslhdrs' package to 'component_files' as if they
    # are valid components

    bsl_bslhdrs_path = None
    for command in compile_commands:
        for switch in command["command"].split():
            # The include path switch is /I or -I for all compilers (msvc, gcc, clang, xlC, sun CC)
            if len(switch) > 2 and switch[1] == 'I' and switch.endswith("bsl+bslhdrs"):
                bsl_bslhdrs_path = Path(switch[2:])
                if not bsl_bslhdrs_path.is_dir():
                    continue
                else:
                    break
        if bsl_bslhdrs_path:
            break

    if not bsl_bslhdrs_path:
        return

    # add all the headers in 'bsl+bslhdrs' to 'component_files'
    for h_file in bsl_bslhdrs_path.glob("*.h"):
        if h_file.is_file():
            component_name = h_file.stem
            if component_name in component_files:
                continue
            component_files[component_name] = {".h": str(h_file)}
    return


def get_all_dependers(component_files):
    dependers = {}
    test_dependers = {}
    for component_name, component_filenames in component_files.items():
        for ext, file in component_filenames.items():
            includes = {
                include
                for include in get_includes(file)
                if include in component_files
            }
            deps = dependers if ".t" not in ext else test_dependers
            for include in includes:
                deps.setdefault(include, set()).add(component_name)
    return dependers, test_dependers


def get_includes(file_name):
    if not file_name:
        return set()

    with open(file_name) as f:
        return re.findall(
            r"^#include [<\"]([\w]*).h[p]*[>\"]", f.read(), flags=re.MULTILINE
        )


def get_dependers_of_targets(
    targets, dependers, test_dependers, output_targets, component_files,
    no_missing_target_warning
):

    def is_valid_target(target):
        # If 'target' is a 'bsl_bslhdrs' header, return True if and only if it
        # is specified without '.t'.'''
        component_name = target[:-2] if target.endswith('.t') else target
        if component_name in component_files.keys() and \
            list(component_files[component_name].keys()) == [".h"]:
                return '.t' not in target
        return component_name in dependers.keys()

    dependers_of_targets = set()
    for target in targets:
        if not is_valid_target(target):
            if not no_missing_target_warning:
                sys.stderr.write(f"Error: Target {target} is unknown.\n")
            continue
        if target.endswith('.t'):
            if output_targets:
                dependers_of_targets.add(target)
            continue
        dependers_of_targets.update(
            get_dependers_of_target(
                target,
                dependers,
                test_dependers,
                output_targets,
                component_files,
            )
        )
    return dependers_of_targets


def get_dependers_of_target(
    target, dependers, test_dependers, output_targets, component_files
):
    # breadth-first traversal
    dependers_of_target = {target}
    components_to_search = [target]

    while components_to_search:
        component = components_to_search.pop(0)

        for client in dependers.get(component, set()):
            if client not in dependers_of_target:
                components_to_search.append(client)

        dependers_of_target.update(dependers.get(component, set()))
        if output_targets:
            dependers_of_target.update(test_dependers.get(component, set()))

    # remove any 'bsl+bslhdrs' "component" added
    dependers_of_target = [depender for depender in dependers_of_target
                           if depender not in component_files.keys() or
                           list(component_files[depender].keys()) != [".h"]]

    if not output_targets:
        return dependers_of_target

    result = set()

    for component in dependers_of_target:
        extensions = component_files[component].keys()
        if not extensions.isdisjoint({".m.c", ".m.cpp"}):
            result.add(component)
        if not extensions.isdisjoint({".t.c", ".t.cpp"}):
            result.add(component + ".t")

    return result


def main():
    try:
        parser = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]))

        parser.add_argument(
            "targets",
            type=lambda x: x.split(","),
            help="Comma-separated list of targets whose dependent components "
            "need to be collected.",
        )

        parser.add_argument(
            "-t",
            "--output-targets",
            action="store_true",
            help="Return a list of dependent targets (applications and test "
            "drivers) instead of components",
        )

        parser.add_argument(
            "--no-missing-target-warning",
            action="store_true",
            help="Suppress warnings when invalid targets are given."
        )

        args = parser.parse_args()

        dependers = get_dependers(args.targets, args.output_targets,
                                  args.no_missing_target_warning)

        # combine dependencies into a comma separated list in string and print
        if dependers:
            print(",".join(dependers))
        else:
            raise RuntimeError("No dependers found")

    except Exception as e:
        print("Error: {}".format(e), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()


# -----------------------------------------------------------------------------
# Copyright 2023 Bloomberg Finance L.P.
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
