# Find cycles within a package.
#
# Usage:
#   check_cycles.py <list of .h and .cpp files>

import sys
import re
import time
from pathlib import Path

def normalize_cycle(cycle):
    """Takes the 'cycle' list and normalize it such that it starts with the lowest-valued node name."""
    if not cycle:
        return []

    # Find the index of the lowest-valued string in the list
    lowest_string_index = cycle.index(min(cycle))

    cycle_start = cycle[lowest_string_index]
    cycle = cycle[lowest_string_index:] + cycle[:lowest_string_index]
    cycle.append(cycle_start)
    return cycle

def find_cycles(graph):
    def dfs(node, visited, recStack, path):
        visited[node] = True
        recStack[node] = True
        path.append(node)

        for neighbor in graph.get(node, []):
            if neighbor == node or graph.get(neighbor, []) == []:
                continue  # Ignore single-node cycles
            elif recStack.get(neighbor, False):  # Cycle found
                cycle_start = path.index(neighbor)
                cycle = normalize_cycle(path[cycle_start:])
                cycles.add(tuple(cycle))
            elif not visited.get(neighbor, False):
                dfs(neighbor, visited, recStack, path)

        path.pop()
        recStack[node] = False

    cycles = set()
    visited = {}
    recStack = {}

    for node in graph.keys():
        if not visited.get(node, False):
            dfs(node, visited, recStack, [])

    return cycles

def build_dependency_graph(file_list):
    include_pattern = re.compile(r'^\s*#\s*include\s*["<](\w+)(?:\.fwd)?\.h[">]\s*(// for testing only)?',
                                 re.MULTILINE)

    test_graph = {}
    impl_graph = {}

    for entry in file_list:
        file_path = Path(entry).absolute()
        if file_path.exists() and file_path.is_file():
            with file_path.open() as file:
                file_content = file.read()
                is_test = file_path.stem.endswith(".t")
                # double suffix to strip slit TDs
                component_name = file_path.with_suffix("").with_suffix("").stem

                impl_deps = set()
                test_deps = set()
                for fname,comment in include_pattern.findall(file_content):
                    if is_test or comment:
                        test_deps.add(fname)
                    else:
                        impl_deps.add(fname)

                if component_name not in impl_graph:
                    impl_graph[component_name] = set()
                if component_name not in test_graph:
                    test_graph[component_name] = set()

                impl_graph[component_name].update(impl_deps)

                test_graph[component_name].update(impl_deps, test_deps)

    return (test_graph, impl_graph)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description='Find cycles within a package.')
    parser.add_argument('files', nargs='*', help='List of .h and .cpp files')
    parser.add_argument('--file-list', help='File containing list of source files (one per line)')
    args = parser.parse_args()
    
    file_list = args.files
    if args.file_list:
        with open(args.file_list, 'r') as f:
            file_list.extend([line.strip() for line in f if line.strip()])
    
    print("Parsing source files ...")
    test_graph, impl_graph = build_dependency_graph(file_list)

    testdeps = set()
    soletestdeps = set()
    pairdeps = set()

    print("Checking cycles ...")
    cycles_found = find_cycles(test_graph)

    if cycles_found:
        print("Cycles found:")
        for cycle in sorted(list(cycles_found)):

            testinducers = set()
            disp=[]
            for i in range(0,len(cycle)-1):
                disp.append(cycle[i])
                if cycle[i+1] in impl_graph[cycle[i]]:
                    disp.append("->")
                else:
                    testinducers.add(  (cycle[i], cycle[i+1]) )
                    disp.append("-T>")
            disp.append(cycle[-1])

            if not testinducers:
                disp.append("  <<< IMPLEMENTATION CYCLE >>")

            else:
                if len(testinducers) == 1:
                    soletestdeps.update(testinducers)
                if len(testinducers) == len(cycle)-1:
                    pairdeps.update(testinducers)
                testdeps.update(testinducers)

            print(" ".join(disp))
    else:
        print("No cycles found in the dependency graph.")


    if testdeps or soletestdeps or pairdeps:

        for a,b in soletestdeps:
            # anything that is the sole link in another cycle shouldn't be shown as a pair
            if (a,b) in pairdeps:
                pairdeps.remove( (a,b) )
            if (b,a) in pairdeps:
                pairdeps.remove( (b,a) )

        # remove anything to be shown as a pair or sole dep from the full list
        testdeps = testdeps.difference(soletestdeps)
        testdeps = testdeps.difference(pairdeps)


        soletestdeps = sorted(list(soletestdeps))
        pairdeps = sorted(list(pairdeps))
        testdeps = sorted(list(testdeps))

        if soletestdeps:
            print("")
            print("  Test-only dependencies that cause cycles (must fix):")
            for a,b in soletestdeps:
                print("    %s -T> %s" % (a,b,))

        if pairdeps:
            print("")
            print("  Mutually test-only dependent components (must fix one side):")
            for a,b in pairdeps:
                if a < b:
                    print("    %s -T> %s -T> %s" % (a,b,a) )

        if testdeps:
            print("")
            print("  Test-only dependencies within cycles:")
            for a,b in testdeps:
                print("    %s -T> %s" % (a,b,))

    if cycles_found:
        sys.exit(1)
