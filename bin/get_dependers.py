import argparse
import json
import os
import re
import sys


def get_dependent_test_drivers(targets):
    json_path = locate_compile_commands_json()
    if not json_path:
        return None

    compile_commands = read_compile_commands_json(json_path)
    if not compile_commands:
        return None

    components = read_valid_components(compile_commands)
    if not components:
        return None

    clients, test_clients = get_component_dependencies(components)

    dependent_components = get_dependent_components_for_targets(targets, clients, test_clients)
    if not dependent_components:
        return None

    return [target + '.t' for target in dependent_components]


def locate_compile_commands_json():
    if os.environ.get('BDE_CMAKE_BUILD_DIR'):
        json_path = os.path.join(os.getcwd(),
                            os.environ.get('BDE_CMAKE_BUILD_DIR'),
                            'compile_commands.json')
        if not os.path.exists(json_path):
            print("'compile_commands.json' not found")
            return None
        return json_path

    print("'BDE_CMAKE_BUILD_DIR' not set")
    return None


def read_compile_commands_json(json_path: str):
    with open(json_path, 'r') as f:
        return json.load(f)


def read_valid_components(compile_commands):
    components = {}
    for command in compile_commands:
        cpp_path = command['file']
        cpp_name = os.path.basename(cpp_path)
        component_name = cpp_name.split('.')[0]
        dirname = os.path.dirname(cpp_path)

        if component_name in components:
          continue

        fullNameLambda = lambda ext: os.path.join(dirname, component_name + ext)
        paths = {
            ext: fullNameLambda(ext)
            for ext in ['.h', '.hpp', '.c', '.cpp', '.t.c', '.t.cpp']
            if os.path.isfile(fullNameLambda(ext))
        }

        hasHeader = not paths.keys().isdisjoint({'.h', '.hpp'})
        hasSource = not paths.keys().isdisjoint({'.c', '.cpp'})
        hasTest = not paths.keys().isdisjoint({'.t.c', '.t.cpp'})

        if hasHeader and hasSource and hasTest:
            components[component_name] = paths

    return components


def get_component_dependencies(components):
    dependencies = {}
    test_dependencies = {}
    for component_name, component_files in components.items():
        for ext, file in component_files.items():
            includes = {
                include
                for include in get_includes(file)
                if include != component_name and include in components
            }
            deps = dependencies if ".t" not in ext else test_dependencies
            for include in includes:
                deps.setdefault(include, set()).add(component_name)
    return dependencies, test_dependencies


def get_includes(file_name):
    if not file_name:
        return set()
    with open(file_name) as f:
        return re.findall(r'#include [<\"]([\w]*).h[p]*[>\"]', f.read())


def get_dependent_components_for_targets(targets, dependencies, test_dependencies):
    dependent_components = set()
    for target in targets:
        if target not in dependencies.keys():
            continue
        dependent_components.update(
            get_dependent_components_for_target(target, dependencies, test_dependencies))
    return dependent_components


def get_dependent_components_for_target(target, dependencies, test_dependencies):
    # breadth-first traversal
    target_dependencies = {target}
    target_test_dependencies = {target}
    components_to_search = [target]
    while components_to_search:
        component = components_to_search.pop(0)

        for client in dependencies.get(component, set()):
            if client not in target_dependencies:
                target_dependencies.add(client)
                components_to_search.append(client)

        target_test_dependencies.update(test_dependencies.get(component, set()))

    return set.union(target_dependencies, target_test_dependencies)


def main():
    argc = len(sys.argv)
    if argc <= 1:
        print(f'usage: get_dependers target1 target2 ...')
        sys.exit(1)
    targets = sys.argv[1:]

    dependencies = get_dependent_test_drivers(targets)
    # combine dependencies into a comma separated list in string and print
    if dependencies:
        print(','.join(dependencies))
    else:
        print('No dependers found')


if __name__ == '__main__':
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
