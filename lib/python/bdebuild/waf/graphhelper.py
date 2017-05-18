import os
import subprocess

from waflib import Build
from waflib import Logs

from bdebuild.meta import buildconfig
from bdebuild.meta import buildconfigutil
from bdebuild.meta import dotutil
from bdebuild.common import sysutil
from bdebuild.meta import cpreproc
from bdebuild.meta import repounits


def add_cmdline_options(opt):
    grp = opt.add_option_group('Graph options')
    grp.add_option('--extract-nodes', type='string', default=None,
                   help='extract the (comma separated list of) nodes from '
                        'graph',
                   dest='extract_nodes')

    grp.add_option('--use-test-only',
                   type='choice', choices=('yes', 'no'), default='yes',
                   help='use includes used for testing only '
                        '(yes/no) [default: %default]',
                   dest='use_test_only')

    grp.add_option('--trans-reduce',
                   type='choice', choices=('yes', 'no'), default='yes',
                   help='whether to perform transitive reduction on graph '
                        '(yes/no) [default: %default]',
                   dest='trans_reduce')

    grp.add_option('--open-graph-with', type='string',
                   default=None,
                   help='open the generated graph with program',
                   dest='open_graph_with')


class GraphContext(Build.BuildContext):
    """draw a dependency graph for the repo, a package group, or a package."""

    cmd = 'graph'

    def get_targets(self):
        """Return an empty target.
        Don't use the default task generation mechansim
        """
        return (None, None)


class GraphHelper(object):
    def __init__(self, ctx):
        self.ctx = ctx
        self.build_config = buildconfig.BuildConfig.from_pickle_str(
            ctx.env['build_config'])

        self.graph_dir_node = self.ctx.bldnode.make_node('_dot_graph')
        self.graph_dir_node.mkdir()

        self.dot_path = sysutil.find_program('dot')
        if self.dot_path:
            self.dot_path = os.path.join(self.dot_path, 'dot')

    def build(self):
        if not self.ctx.targets or self.ctx.targets == '*':
            digraph = buildconfigutil.get_uor_digraph(
                self.build_config)
            self.draw_imp(digraph, 'UORs', '__all__')
            return
        elif self.ctx.targets in self.build_config.package_groups:
            group_name = self.ctx.targets
            digraph = buildconfigutil.get_package_digraph(
                self.build_config, group_name)
            self.draw_imp(digraph, group_name, group_name)
            return

        package = None
        if self.ctx.targets in self.build_config.stdalone_packages:
            package = self.build_config.stdalone_packages[self.ctx.targets]
        elif self.ctx.targets in self.build_config.inner_packages:
            package = self.build_config.inner_packages[self.ctx.targets]

        if not package or package.type_ == repounits.PackageType.PACKAGE_PLUS:
            Logs.warn('Graph target must be either empty, '
                      'a package group, or a package that is not '
                      'a + package.')
            return

        digraph = cpreproc.get_component_digraph(
            package, self.ctx.options.use_test_only == 'yes')
        prefix = package.name + '_'

        def remove_prefix(str_):
            if str_.startswith(prefix):
                return str_[len(prefix):]
            return str_

        # Remove prefix
        digraph_new = {}
        for node in digraph:
            digraph_new[remove_prefix(node)] = [remove_prefix(c) for
                                                c in digraph[node]]

        self.draw_imp(digraph_new, package.name, package.name)

    def draw_imp(self, digraph, graph_name, file_name):

        extract_nodes = self.ctx.options.extract_nodes.split(',') if \
            self.ctx.options.extract_nodes is not None else []

        is_trans_reduce = self.ctx.options.trans_reduce == 'yes'

        dot_text = dotutil.digraph_to_dot(graph_name, digraph, extract_nodes,
                                          is_trans_reduce)
        dot_node = self.graph_dir_node.make_node(file_name + '.dot')
        dg_node = self.graph_dir_node.make_node(file_name + '.png')
        dot_node.write(dot_text)
        cmd = [self.dot_path if self.dot_path else 'dot',
               '-Tpng', dot_node.abspath(), '-o', dg_node.abspath()]

        if not self.dot_path:
            Logs.warn('Can not find the program "dot" in the "PATH" '
                      'environment variable.')
            Logs.warn('Please run the following command manually to '
                      'generate the dependency graph.')
            Logs.warn(' '.join(cmd))
        else:
            rc = subprocess.call(cmd)
            if rc != 0:
                Logs.warn('Failed to run %s' % cmd)
            else:
                Logs.warn('Generated dot file:\n%s' % dot_node.abspath())
                Logs.warn('Generated graph:\n%s' % dg_node.abspath())

                open_with = self.ctx.options.open_graph_with
                if open_with:
                    try:
                        cmd = [open_with, dg_node.abspath()]
                        subprocess.call(cmd)
                    except Exception as e:
                        Logs.warn('Cannot execute command %s. Exception: %s.' %
                                  (cmd, e))

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
