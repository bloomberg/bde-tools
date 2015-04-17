"""Graph related operations on a BDE-style repository.

Note that for simplicity, graph arguments are represented using a python
dictionary, with each key being a node in the graph and and the value the list
the nodes that are reachable from the node of the key.
"""

import copy


def levelize(graph, root_nodes=None):
    """Levelize a directed graph.

    Args:
        graph(map of str to list): A directed graph.
        root_nodes(list of str, optional): Use these as the top level nodes. If
            not specified, then the root nodes of the graph will be used.

    Returns:
        A list of sets, with the nth element representing the node in the n + 1
        level.
    """

    node_levels = {}

    def visit(node, stack):
        if node in stack:
            raise ValueError("Cycle detected: %s" %
                             ' -> '.join(stack + [node]))

        if node in node_levels:
            return node_levels[node]

        if node not in graph or not graph[node]:
            # This node is a leaf node.
            node_levels[node] = 1
            return 1

        stack.append(node)
        level = 1 + max(visit(child, stack) for child in graph[node])
        stack.pop()

        node_levels[node] = level
        return level

    if root_nodes is None:
        root_nodes = find_root_nodes(graph)

    if len(root_nodes) == 0:
        return []

    max_level = max(visit(n, []) for n in root_nodes)

    levels = []
    for l in range(max_level):
        levels.append(set())

    for n in node_levels:
        levels[node_levels[n] - 1].add(n)

    return levels


def topological_sort(digraph, root_nodes=None):
    """Return a topologically sorted list of nodes in a directed graph.

    Args:
        digraph (map of str to list): The directed graph to use.
        dep_nodes (list, optional): The root dependencies.
    """

    visited = set()
    ordered = []

    def visit(node, stack):
        if node in visited:
            return

        if node in stack:
            raise ValueError("Cycle detected: %s" %
                             ' -> '.join(stack + [node]))

        if node in digraph:
            stack.append(node)
            for c in sorted(digraph[node]):
                visit(c, stack)
            stack.pop()

        visited.add(node)
        ordered.append(node)

    if root_nodes is None:
        root_nodes = find_root_nodes(digraph)

    for node in sorted(root_nodes):
        visit(node, [])

    return ordered


def find_cycles(graph):
    """Return the strongly connected components of a graph.

    Find all cycles in the graph using Tarjan's algorithm.

    Args:
        graph (map of str to list): directed graph

    Returns:
       A list of strongly connected components forming cycles.
       E.g.,
       [
           ['a', 'b']
           ['c']  # self cycle
       ]
    """

    class NodeStats(object):
        def __init__(self):
            self.on_stack = False
            self.index = None
            self.low_link = None

    index = [0]  # nested function can't rebind a nonlocal name
    stack = []
    node_stats_map = {}  # map of str to NodeStats
    cycles = []

    def visit(node):
        ns = NodeStats()
        ns.on_stack = True
        ns.index = index[0]
        ns.low_link = index[0]
        index[0] += 1
        stack.append(node)
        node_stats_map[node] = ns

        if node in graph:
            for child in graph[node]:
                if child not in node_stats_map:
                    visit(child)
                    cs = node_stats_map[child]
                    ns.low_link = min(ns.low_link, cs.low_link)
                else:
                    cs = node_stats_map[child]
                    if cs.on_stack:
                        ns.low_link = min(ns.low_link, cs.index)

        if ns.low_link == ns.index:
            nn = stack.pop()
            node_stats_map[nn].on_stack = False
            cycle = [nn]
            while (nn != node):
                nn = stack.pop()
                node_stats_map[nn].on_stack = False
                cycle.insert(0, nn)

            # SCC of length 1 is only a cycle if the node points to itself
            if len(cycle) > 1 or (node in graph and node in graph[node]):
                cycles.append(cycle)

    for n in sorted(graph):
        if n not in node_stats_map:
            visit(n)

    return cycles


def find_external_nodes(digraph):
    """Return a set of external nodes in a directed graph.

    External nodes are node that are referenced as a dependency not defined as
    a key in the graph dictionary.
    """
    external_nodes = set()
    for ni in digraph:
        for nj in digraph[ni]:
            if nj not in digraph:
                external_nodes.add(nj)

    return external_nodes


def find_root_nodes(digraph):
    """Return a set of nodes having no incoming edges in a directed graph.

    Args:
         digraph (dict): The directed graph.

    Returns:
         A list of root nodes.
    """
    root_nodes = set()
    for ni in digraph:
        if all(ni not in digraph[nj] for nj in digraph):
            root_nodes.add(ni)
    return root_nodes


def transitive_reduce(digraph):
    """Transitively reduce a directed graph.

    Args:
        digraph (dict): The directed graph to reduce.

    Returns:
        New graph.
    """
    digraph_new = copy.deepcopy(digraph)
    for x in digraph:
        for y in digraph:
            for z in digraph:
                if (y in digraph[x]) and (z in digraph[y]):
                    try:
                        digraph_new[x].remove(z)
                    except:
                        pass
    return digraph_new

# -----------------------------------------------------------------------------
# Copyright 2015 Bloomberg Finance L.P.
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
