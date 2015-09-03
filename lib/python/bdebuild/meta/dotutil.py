"""Utilities to work with Graphviz's dot format.
"""

import collections

from bdebuild.common import logutil
from bdebuild.meta import graphutil


ExtractedTriplet = collections.namedtuple(
    'ExtractedTriplet', ['name', 'parents', 'children'])


def digraph_to_dot(name, digraph, extract_nodes=[], trans_reduce=False):
    """Generate dot source for for a directed graph.

    Args:
         name (str): Name of the graph.
         digraph (dict): The graph to draw.
         extract_nodes (list, optional): The nodes to remove from the graph.
         trans_reduce: Whether to transitively reduce the graph.

    Returns:
         A string containing the dot source.
    """
    digraph, etps = _extract_nodes(digraph, extract_nodes)
    levels = graphutil.levelize(digraph)

    if trans_reduce:
        digraph = graphutil.transitive_reduce(digraph)

    desc = 'digraph %s {\n' % name
    desc += 'ranksep=0.6; size = "75,75";\n'
    desc += 'bgcolor=grey70;'
    desc += 'style=filled;\n'
    desc += 'color=lightgrey;\n'
    desc += 'subgraph {\n'
    desc += '\tnode [shape=circle, style=filled, fontsize=11];\n'
    desc += '\t' + ' -> '.join(
        reversed([str(l) for l in range(len(levels) + 1)][1:])) + ';\n'
    desc += '}\n'

    desc += 'node [shape=box,style=filled,color=goldenrod3];\n'
    index = 0
    while index < len(levels):
        node_list = ['"' + node + '";' for node in levels[index]]
        desc += '{ rank = same; %d; %s }\n' % (index + 1, ' '.join(node_list))
        index += 1

    for node in digraph:
        children = digraph[node]
        for c in children:
            desc += '\t"%s" -> "%s";\n' % (node, c)

    for etp in etps:
        if etp.parents:
            parent_str = '"_' + ','.join(etp.parents) + '_" ->'
        else:
            parent_str = ''
        if etp.children:
            child_str = '-> "_' + ','.join(etp.children) + '_"'
        else:
            child_str = ''
        desc += 'subgraph cluster {\n'
        desc += ' %s "%s" %s;' % (
            parent_str,  etp.name, child_str)
        desc += '}\n'

    desc += '}\n'

    return desc



def _extract_nodes(digraph, extract_nodes):
    extract_nodes = set(extract_nodes)
    existing_nodes = set(digraph.keys())
    invalid_nodes = extract_nodes - existing_nodes
    if len(invalid_nodes) > 0:
        logutil.warn('Trying to extract invalid nodes: %s' %
                     ','.join(list(invalid_nodes)))

    extract_nodes = extract_nodes & existing_nodes

    etps = []
    for ne in extract_nodes:
        parents = []
        childern = digraph[ne]
        for nn in digraph:
            if ne in digraph[nn]:
                parents.append(nn)

        etp = ExtractedTriplet(ne, parents, childern)
        etps.append(etp)

    digraph_new = {}
    for nn in digraph:
        if nn not in extract_nodes:
            digraph_new[nn] = list(set(digraph[nn]) - extract_nodes)

    return digraph_new, etps


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
