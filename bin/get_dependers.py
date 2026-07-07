import argparse
from enum import Enum
import json
import os
from pathlib import Path
import re
import sys
from typing import Dict, List, Optional, Set, Tuple


class Component:
    '''A class to represent a component, its dependers and dependees.'''
    def __init__(self, component_name: str,
                 file_path: Optional[Path] = None,
                 cmake_target_name: Optional[str] = None) -> None:
        '''Initializes a Component object with the specified name.  If
        'file_path' is provided, finds all files in the component directory
        that belong to the same component, and finds all components that this
        component depends upon.  If 'file_path' is None, the component is
        synthetic (it has no source files of its own and no dependees); this
        form is used to represent third-party CMake targets that aggregate
        many source files which do not follow the BDE component-naming
        convention (e.g. 'inteldfp' which compiles 'bid128.c',
        'bid128_scalb.c', ...).  Optionally records the 'cmake_target_name'
        (the CMake build target that compiles this component's source).'''
        self.name = component_name
        self.cmake_target_name = cmake_target_name

        self.header_path = self.source_path = self.application_path = None
        self.test_driver_paths = []

        # 'dependee_names'   -- basenames captured from '#include "foo.h"' /
        #                       '#include <foo.h>'.
        # 'dependee_prefixes' -- the optional directory prefix captured from
        #                       '#include <prefix/foo.h>' (e.g. 'inteldfp'
        #                       from '#include <inteldfp/bid_functions.h>').
        #                       Used to attach edges from BDE components to
        #                       synthetic third-party CMake targets whose
        #                       installed headers live under that prefix.
        self.dependee_names = set()
        self.test_dependee_names = set()
        self.dependee_prefixes = set()
        self.test_dependee_prefixes = set()

        self.depender_names = set()
        self.test_depender_names = set()

        if file_path is not None:
            self.update_file_paths(file_path)
            self.update_dependee_names()

    def update_file_paths(self, file_path: Path) -> None:
        '''Finds all files in the component directory that belong to the
        current component, i.e., header, source, application, and test
        drivers.'''
        for path in file_path.parent.glob(f"{self.name}.*"):
            if not path.is_file():
                continue
            suffixes = path.suffixes
            suffix_count = len(suffixes)
            if suffix_count == 1: # header and source
                if suffixes[0] in [".h", ".hpp"]:
                    self.header_path = path
                elif suffixes[0] in [".c", ".cpp"]:
                    self.source_path = path
            elif suffix_count == 2: # application and test driver
                if suffixes[0] == ".m" and suffixes[1] in [".c", ".cpp"]:
                    self.application_path = path
                elif suffixes[0] in [".t", ".xt", ".g"] and suffixes[1] in [".c", ".cpp"]:
                    self.test_driver_paths = [path]
            elif suffix_count == 3: # split test drivers
                if suffixes[1] == ".t" and suffixes[2] in [".c", ".cpp"]:
                    self.test_driver_paths.append(path)

    def update_dependee_names(self) -> None:
        '''Finds all components that this component depends upon.'''
        def get_dependee_names(
                files: List[Path]) -> Tuple[Set[str], Set[str]]:
            '''Returns '(basenames, prefixes)' for components included by
            any of the given files.  'basenames' are captured from
            '#include "foo.h"' / '#include <foo.h>'; 'prefixes' are the
            optional directory components in '#include <prefix/foo.h>'.'''
            dependee_names = set()
            dependee_prefixes = set()
            for file in files:
                with file.open() as f:
                    matches = re.findall(
                        r'^\s*#\s*include\s+[<"](?:([\w]+)/)?([\w]+)'
                        r'\.h[p]*[>"]',
                        f.read(),
                        flags=re.MULTILINE)
                for prefix, name in matches:
                    dependee_names.add(name)
                    if prefix:
                        dependee_prefixes.add(prefix)
            return dependee_names, dependee_prefixes

        self.dependee_names, self.dependee_prefixes = get_dependee_names(
            [path for path in [self.header_path, self.source_path,
                               self.application_path] if path])
        self.test_dependee_names, self.test_dependee_prefixes = \
            get_dependee_names(self.test_driver_paths)

    def add_depender_name(self, depender_name: str,
                          is_test_depender: bool = False) -> None:
        '''Adds a component that depends on this component.  If
        'is_test_depender' is True, adds it as a test depender.'''
        if is_test_depender:
            self.test_depender_names.add(depender_name)
        else:
            self.depender_names.add(depender_name)

    def is_header_only(self) -> bool:
        '''Returns True if this component is a header in 'bsl+bslhdrs'.'''
        return self.header_path is not None and \
            self.source_path is None and \
            self.application_path is None and \
            not self.test_depender_names

    def __eq__(self, other) -> bool:
        '''Returns True iff the names of the two components are the same.'''
        if other is None or not isinstance(other, self.__class__):
            return False
        return self.name == other.name

    def __hash__(self) -> int:
        '''Returns the hash of the object.'''
        return hash(self.name)


class TargetType(Enum):
    '''An Enum class to represent various target types.'''
    COMPONENT = 1
    TEST_DRIVER = 2
    INVALID = 3


class Target:
    '''A class to represent a target and its dependers.'''
    def __init__(self, target_name: str, components: Dict[str, Component],
                 output_targets: bool) -> None:
        '''Initializes a Target object with the specified target_name.
        Determines the type of the target, i.e., a component, a test driver or
        an invalid target using the given 'components'.  If the target is
        neither a valid component name nor a valid test driver name, the target
        is marked as invalid.'''
        split_name = target_name.split(".")
        component_name = split_name[0]

        self.component : Optional[Component] = None
        self.name = target_name
        self.depender_names = set()

        suffixes = split_name[1:]
        suffix_count = len(suffixes)

        if suffix_count == 0 and component_name in components.keys():
            self.target_type = TargetType.COMPONENT
            self.component = components[component_name]
            self.update_depender_names(components, output_targets)
        elif suffix_count >= 1 and suffixes[-1] == "t" and \
            component_name in components.keys() and \
            len(components[component_name].test_driver_paths) > 0:
            self.target_type = TargetType.TEST_DRIVER
            # test drivers don't have dependers
        else:
            # unrecognized file extensions or invalid component name
            self.target_type = TargetType.INVALID

    def update_depender_names(self, components: Dict[str, Component],
                            output_targets: bool) -> None:
        '''Finds a list of components that depend on the target.'''
        # breadth-first traversal of all dependers
        if self.component is None:
            return
        depender_names = {self.component.name}
        test_depender_names = set()
        component_names_to_search = [self.component.name]

        while component_names_to_search:
            component_name = component_names_to_search.pop(0)

            cpp03_name = component_name + '_cpp03'
            if cpp03_name in components and cpp03_name not in component_names_to_search:
                depender_names.update([cpp03_name])

            component = components[component_name]
            component_names_to_search.extend(
                component.depender_names - depender_names)
            depender_names.update(component.depender_names)
            if output_targets:
                # Corner case: When C is added as a test depender, the search
                # doesn't add C's dependers to A's dependers
                # A <- B <- C <- D
                # A <T- C
                test_depender_names.update(component.test_depender_names)
        depender_names.update(test_depender_names)

        # remove any 'bsl+bslhdrs' "component" added
        depender_names = {depender_name for depender_name in depender_names
                          if not components[depender_name].is_header_only()}
        if not output_targets:
            self.depender_names = depender_names
            return

        self.depender_names = set()
        for depender_name in depender_names:
            component = components[depender_name]
            if component.application_path:
                self.depender_names.add(component.name)
            if component.test_driver_paths:
                self.depender_names.add(component.name + ".t")


def get_dependers(targets: List[str], output_targets: bool,
                  no_missing_target_warning: bool = False,
                  buildDir: Optional[str] = None) -> List[str]:
    '''Returns a list of components that depend on the specified targets.  If
    'output_targets' is True, returns a list of targets.  If
    'no_missing_target_warning' is True, suppresses warnings when some targets
    are invalid.  If no dependers are found, returns an empty list.'''
    compile_commands_json_path = locate_compile_commands_json(buildDir)
    if not compile_commands_json_path:
        return []

    components, thirdparty_aliases = parse_compile_commands_json(
        compile_commands_json_path)
    if not components:
        return []

    update_depender_names(components)

    depender_names = set()
    for target_name in targets:
        # If the user passed a third-party source basename (e.g.
        # 'bid128_scalb'), resolve it to the CMake target that aggregates it
        # ('inteldfp') so the depender walk starts from the right node.
        resolved_name = thirdparty_aliases.get(target_name, target_name)
        target = Target(resolved_name, components, output_targets)
        if target.target_type == TargetType.INVALID:
            if not no_missing_target_warning:
                sys.stderr.write(f"Error: Invalid target: {target_name}\n")
        elif target.target_type == TargetType.TEST_DRIVER:
            if output_targets:
                depender_names.add(target.name)
        else:
            depender_names.update(target.depender_names)

    return sorted(depender_names)


def locate_compile_commands_json(buildDir : Optional[str]) -> Optional[Path]:
    '''Locates the 'compile_commands.json' file in the build directory and
    returns its absolute path.  If 'BDE_CMAKE_BUILD_DIR' is not set or the file
    is not found, prints an error and returns None.'''
    bde_cmake_build_dir = os.environ.get("BDE_CMAKE_BUILD_DIR") if buildDir is None else buildDir
    if bde_cmake_build_dir:
        json_path = Path.cwd() / bde_cmake_build_dir / "compile_commands.json"
        if not json_path.exists():
            sys.stderr.write("'compile_commands.json' is not found. "
                  "Did you forget to run 'configure'?\n")
            return None
        return json_path
    sys.stderr.write("'BDE_CMAKE_BUILD_DIR' is not set. "
                  "Did you forget to run 'eval'?\n")
    return None


def _extract_cmake_target_name(output_field: str) -> Optional[str]:
    '''Extracts the CMake build target name from the 'output' field of a
    'compile_commands.json' entry.  CMake writes object-file paths of the form
    '.../CMakeFiles/<target>.dir/...' using forward slashes on every platform
    (Windows, Linux, macOS, Solaris).  Returns 'None' if no such segment is
    found (e.g. for custom generators).'''
    if not output_field:
        return None
    # Normalize backslashes just in case some generator emits them.
    parts = output_field.replace("\\", "/").split("/")
    try:
        idx = parts.index("CMakeFiles")
    except ValueError:
        return None
    if idx + 1 >= len(parts):
        return None
    target_dir = parts[idx + 1]
    if not target_dir.endswith(".dir"):
        return None
    return target_dir[:-len(".dir")]


def _is_thirdparty_source(path: Path) -> bool:
    '''Returns True iff 'path' lives under a 'thirdparty' directory.  Used to
    decide whether a source file follows the BDE component-naming convention
    (and therefore deserves its own 'Component') or whether it is a vendored
    library source that should be folded into its CMake target.'''
    return "thirdparty" in path.as_posix().split("/")


def _thirdparty_library_root(path: Path) -> Optional[Path]:
    '''Given a path under a 'thirdparty' directory, returns the third-party
    library root, i.e., 'thirdparty/<libname>'.  Returns 'None' if 'path' is
    not under a 'thirdparty' directory or the library name segment is
    missing.'''
    parts = path.as_posix().split("/")
    try:
        idx = parts.index("thirdparty")
    except ValueError:
        return None
    if idx + 1 >= len(parts):
        return None
    return Path("/".join(parts[: idx + 2]))


def parse_compile_commands_json(
        json_path: Path) -> Tuple[Dict[str, Component], Dict[str, str]]:
    '''Parses 'compile_commands.json' and returns '(components,
    thirdparty_aliases)'.

    'components' maps component name to 'Component'.  BDE components are
    keyed by their source basename; third-party CMake targets are
    represented by a single synthetic 'Component' keyed by the target name
    (e.g. 'inteldfp') -- the individual third-party source basenames are
    NOT keys in 'components'.

    'thirdparty_aliases' maps each third-party source basename (e.g.
    'bid128_scalb') to the CMake target that aggregates it ('inteldfp'), so
    callers can resolve user-supplied source names to depender-walk
    starting points.'''
    with json_path.open() as f:
        compile_commands = json.load(f)
    if not compile_commands:
        return {}, {}

    # Parse all components
    components: Dict[str, Component] = {}
    thirdparty_aliases: Dict[str, str] = {}
    # Library roots observed in 'compile_commands.json'.  After the main
    # loop, each root is globbed for header files so that header-only
    # basenames (e.g. 'bid_internal' from
    # 'thirdparty/inteldfp/.../bid_internal.h') also resolve to the right
    # synthetic component.
    thirdparty_roots: Set[Path] = set()
    for command in compile_commands:
        cpp_path = Path(command["file"])
        component_name = cpp_path.name.partition(".")[0]
        cmake_target_name = _extract_cmake_target_name(
            command.get("output", ""))

        if _is_thirdparty_source(cpp_path):
            # Third-party sources rarely match BDE component naming, and
            # the same library directory may compile under several CMake
            # targets (e.g. 'thirdparty/inteldfp/' produces both the
            # 'inteldfp' library and the 'bid_float128_objs' OBJECT
            # library that gets linked into it).  Use the library
            # directory name (e.g. 'inteldfp') as the canonical synthetic
            # component, since that is also the prefix BDE consumers use
            # in '#include <inteldfp/...>'.  Building the canonical CMake
            # target rebuilds any nested OBJECT libraries transitively.
            lib_root = _thirdparty_library_root(cpp_path)
            if lib_root is None:
                continue
            canonical = lib_root.name
            thirdparty_aliases[component_name] = canonical
            if cmake_target_name and cmake_target_name != canonical:
                thirdparty_aliases.setdefault(cmake_target_name, canonical)
            if canonical not in components:
                components[canonical] = Component(
                    canonical,
                    file_path=None,
                    cmake_target_name=canonical)
            thirdparty_roots.add(lib_root)
            continue

        if component_name in components:
            continue
        components[component_name] = Component(
            component_name, cpp_path, cmake_target_name)

    # Alias header basenames (e.g. 'bid_internal', 'bid_functions') under
    # each third-party library root to the canonical synthetic component,
    # so that header-only files (which never appear in
    # 'compile_commands.json') can also be passed as targets.
    for lib_root in thirdparty_roots:
        if not lib_root.is_dir():
            continue
        canonical = lib_root.name
        for pattern in ("*.h", "*.hpp"):
            for header in lib_root.rglob(pattern):
                thirdparty_aliases.setdefault(header.stem, canonical)

    # Add all headers in 'bsl+bslhdrs' package to 'components' as if they were
    # valid components
    bsl_bslhdrs_path = None
    for command in compile_commands:
        for switch in command["command"].split():
            # The include path switch is /I or -I for all compilers (msvc, gcc,
            # clang, xlC, sun CC)
            if len(switch) > 2 and switch[1] == 'I' and \
                switch.endswith("bsl+bslhdrs"):
                bsl_bslhdrs_path = Path(switch[2:])
                if not bsl_bslhdrs_path.is_dir():
                    bsl_bslhdrs_path = None
                    continue
                else:
                    break
        if bsl_bslhdrs_path:
            break
    if not bsl_bslhdrs_path:
        return components, thirdparty_aliases

    # add all the headers in 'bsl+bslhdrs' to 'component_files'
    for h_file in bsl_bslhdrs_path.glob("*.h"):
        if h_file.is_file():
            component_name = h_file.stem
            if component_name in components:
                continue
            components[component_name] = Component(component_name, h_file)
    return components, thirdparty_aliases


def update_depender_names(components: Dict[str, Component]) -> None:
    '''Finds all dependers from dependees.'''
    component_keys = components.keys()
    for component_name, component in components.items():
        for dependee_name in component.dependee_names & component_keys:
            components[dependee_name].add_depender_name(component_name)
        # '#include <prefix/foo.h>' edges -- attach the depender to the
        # synthetic third-party CMake target named 'prefix' if one exists.
        for prefix in component.dependee_prefixes & component_keys:
            components[prefix].add_depender_name(component_name)
        for test_dependee_name in \
            component.test_dependee_names & component_keys:
            components[test_dependee_name].add_depender_name(
                component_name, True)
        for test_prefix in component.test_dependee_prefixes & component_keys:
            components[test_prefix].add_depender_name(
                component_name, True)


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

        parser.add_argument(
            "--build_dir",
            help = '''
                Path to the build directory. If not specified,
                the use one specified in BDE_CMAKE_BUILD_DIR environment
                variable.
                '''
        )

        args = parser.parse_args()

        dependers = get_dependers(args.targets, args.output_targets,
                                  args.no_missing_target_warning,
                                  args.build_dir)

        # combine dependencies into a comma separated list in string and print
        if dependers:
            print(",".join(dependers))
        else:
            raise RuntimeError("No dependers found")

    except Exception as e:
        sys.stderr.write("Error: {}\n".format(e))
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
