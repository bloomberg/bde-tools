"""Implement waf.build operations.
"""

import os
import sys

from waflib import Logs

from bdebld.meta import buildconfig
from bdebld.meta import buildconfigutil
from bdebld.meta import graphutil
from bdebld.meta import repounits

from bdebld.common import sysutil

from bdebld.waf import waftweaks  # NOQA
from bdebld.waf import bdeunittest


class BuildHelper(object):
    def __init__(self, ctx):
        for class_name in ('cxx', 'cxxprogram', 'cxxshlib', 'cxxstlib',
                           'c', 'cprogram', 'cshlib', 'cstlib'):
            waftweaks.activate_custom_exec_command(class_name)

        self.ctx = ctx
        self.build_config = buildconfig.BuildConfig.from_pickle_str(
            self.ctx.env['build_config'])

        self.install_flat_include = self.ctx.env['install_flat_include']
        self.install_lib_dir = self.ctx.env['install_lib_dir']
        self.lib_suffix = self.ctx.env['lib_suffix']
        self.pc_extra_include_dirs = self.ctx.env['pc_extra_include_dirs']
        self.soname_overrides = self.ctx.env['soname_overrides']

        if 'shr' in self.build_config.ufid.flags:
            self.libtype_features = ['cxxshlib']
        else:
            self.libtype_features = ['cxxstlib']

        self.is_run_tests = self.ctx.options.test == 'run'
        self.is_build_tests = self.is_run_tests or \
            self.ctx.options.test == 'build'

        test_runner_path = os.path.join(
            sysutil.repo_root_path(), 'bin', 'bde_runtest.py')

        self.ctx.options.testcmd = \
            '%s %s %%s --verbosity %s --timeout %s' % (
                sys.executable,
                test_runner_path,
                self.ctx.options.test_verbosity,
                self.ctx.options.test_timeout)

        self.export_third_party_flags()

        self.ctx.env['env'] = os.environ.copy()
        self.ctx.env['env'].update(self.build_config.custom_envs)

        if self.build_config.uplid.os_type == 'windows':
            # Use forward slash for paths on windows to be compatible with
            # pykg-config.py.
            prefix = self.ctx.env['PREFIX']
            self.ctx.env['PREFIX'] = prefix.replace('\\', '/')

        self.targets = self.ctx.targets.split(',')

        if (any(t.endswith('.t') for t in self.targets) and
                not self.is_build_tests):
            msg = """Did you forget to use the option '--test build'?
You must use the option '--test build' to build test drivers and the option
'--test run' to run test drivers.  For example, to build the test driver for
the bdlt_date component:

  $ waf build --target bdlt_date.t --test build"""
            Logs.warn(msg)

    def build(self):
        # Create task generators in topological order so that the actual task
        # build order would appear to be meaningful.  Note that ordering this
        # not necessary and the build would work for any order of task
        # generators.

        ordered_uor_names = graphutil.topological_sort(
            buildconfigutil.get_uor_digraph(self.build_config))

        for uor_name in ordered_uor_names:
            if uor_name in self.build_config.package_groups:
                group = self.build_config.package_groups[uor_name]
                self.build_package_group(group)

            if uor_name in self.build_config.stdalone_packages:
                package = self.build_config.stdalone_packages[uor_name]
                self.build_stdalone_package(package)

            if uor_name in self.build_config.third_party_dirs:
                tp = self.build_config.third_party_dirs[uor_name]
                self.build_thirdparty_dirs(tp)

        if self.is_run_tests:
            self.ctx.add_post_fun(bdeunittest.summary)

    def build_package_group(self, group):
        relpath = os.path.relpath(group.path, self.build_config.root_path)
        group_node = self.ctx.path.make_node(relpath)
        flags = group.flags
        internal_dep = [d + '_lib' for d in sorted(group.dep)]
        external_dep = [l.upper() for l in sorted(group.external_dep)]
        install_path = os.path.join('${PREFIX}', self.install_lib_dir)

        # Create task generators in topological order so that the actual task
        # build order would appear to be meaningful.

        ordered_package_names = graphutil.topological_sort(
            buildconfigutil.get_package_digraph(self.build_config, group.name))

        for package_name in ordered_package_names:
            package = self.build_config.inner_packages[package_name]
            self.build_inner_package(package, group)

        if group.name in self.soname_overrides:
            custom_soname = self.soname_overrides[group.name]
        else:
            custom_soname = None

        self.ctx(name=group.name + '_lib',
                 path=group_node,
                 target=group.name + self.lib_suffix,
                 features=['cxx'] + self.libtype_features,
                 linkflags=flags.linkflags,
                 lib=flags.libs,
                 stlib=flags.stlibs,
                 cust_libpaths=flags.libpaths,
                 source=[p + '_lib' for p in ordered_package_names],
                 use=internal_dep,
                 uselib=external_dep,
                 export_includes=[group_node.make_node(p) for p in
                                  ordered_package_names],
                 install_path=install_path,
                 bdevnum=group.version,
                 bdesoname=custom_soname
                 )

        self.gen_pc_file(group)

        self.ctx(
            name=group.name,
            depends_on=[group.name + '_lib', group.name + '.pc'] +
            [p + '_tst' for p in ordered_package_names]
        )

    def build_stdalone_package(self, package):
        internal_dep = [d + '_lib' for d in sorted(package.dep)]
        external_dep = [l.upper() for l in sorted(package.external_dep)]
        lib_install_path = os.path.join('${PREFIX}', self.install_lib_dir)

        if self.install_flat_include:
            h_install_path = os.path.join('${PREFIX}', 'include')
        else:
            h_install_path = os.path.join('${PREFIX}', 'include', package.name)

        self.build_package_impl(package, internal_dep, external_dep,
                                lib_install_path, h_install_path)

        depends_on = [
            package.name + '_lib',
            package.name + '_tst'
        ]
        if package.type_ == repounits.PackageType.PACKAGE_APPLICATION:
            relpath = os.path.relpath(package.path,
                                      self.build_config.root_path)
            package_node = self.ctx.path.make_node(relpath)
            flags = package.flags
            if package.has_dums:
                dums_tg_dep = [package.name + '_dums_build']
            else:
                dums_tg_dep = []

            self.ctx(
                name=package.name + '_app',
                path=package_node,
                target=package.name,
                source=[package.name + '.m.cpp'],
                features=['cxx', 'cxxprogram'],
                cflags=flags.cflags,
                cincludes=flags.cincludes,
                cxxflags=flags.cxxflags,
                cxxincludes=flags.cxxincludes,
                linkflags=flags.linkflags,
                includes=[package_node],
                lib=flags.libs,
                stlib=flags.stlibs,
                use=[package.name + '_lib'] + dums_tg_dep,
                uselib=external_dep
            )
            depends_on.append(package.name + '_app')

        self.ctx(
            name=package.name,
            depends_on=depends_on
        )

    def build_inner_package(self, package, group):
        internal_dep = [d + '_lib' for d in sorted(package.dep | group.dep)]
        external_dep = [l.upper() for l in sorted(group.external_dep)]

        if self.install_flat_include:
            h_install_path = os.path.join('${PREFIX}', 'include')
        else:
            h_install_path = os.path.join('${PREFIX}', 'include', group.name)

        if package.type_ == repounits.PackageType.PACKAGE_PLUS:
            self.build_plus_package_impl(package, internal_dep, external_dep,
                                         None, h_install_path)
        else:
            self.build_package_impl(package, internal_dep, external_dep,
                                    None, h_install_path)

        self.ctx(
            name=package.name,
            depends_on=[
                package.name + '_lib',
                package.name + '_tst'
            ]
        )

    def build_plus_package_impl(self, package, internal_dep, external_dep,
                                lib_install_path, h_install_path):
        relpath = os.path.relpath(package.path, self.build_config.root_path)
        package_node = self.ctx.path.make_node(relpath)
        flags = package.flags

        self.ctx(
            name=package.name + '_lib',
            path=package_node,
            target=package.name,
            source=sorted(package.cpp_sources),
            features=['cxx'] + self.libtype_features,
            cflags=flags.cflags,
            cincludes=flags.cincludes,
            cxxflags=flags.cxxflags,
            cxxincludes=flags.cxxincludes,
            linkflags=flags.linkflags,
            lib=flags.libs,
            stlib=flags.stlibs,
            includes=[package_node],
            export_includes=[package_node],
            use=internal_dep,
            uselib=external_dep,
            install_path=lib_install_path
        )

        self.ctx(
            name=package.name + '_tst',
        )

        # The relative directory instructure of headers must be preserved when
        # they are installed.

        header_dirs = {}  # dir -> name
        for h in package.headers:
            (head, tail) = os.path.split(h)
            if head not in header_dirs:
                header_dirs[head] = []
            header_dirs[head].append(tail)

        for d in header_dirs:
            self.ctx.install_files(os.path.join(h_install_path, d),
                                   [os.path.join(relpath, d, h) for h in
                                    header_dirs[d]])

    def build_package_impl(self, package, internal_dep, external_dep,
                           lib_install_path, h_install_path):
        relpath = os.path.relpath(package.path, self.build_config.root_path)
        package_node = self.ctx.path.make_node(relpath)
        flags = package.flags

        package_features = []
        if any(comp.type_ == repounits.ComponentType.C for comp in
               package.components):
            package_features.append('c')
        if any(comp.type_ == repounits.ComponentType.CXX for comp in
               package.components):
            package_features.append('cxx')

        dums_tg_dep = []
        if package.has_dums:
            dums_node = package_node.make_node(['package',
                                                package.name + '.dums'])
            self.ctx(
                name=package.name + '_dums_cp',
                path=package_node,
                target=package.name + '_dums.c',
                rule='cp ${SRC} ${TGT}',
                source=dums_node
            )
            self.ctx(
                name=package.name + '_dums_build',
                path=package_node,
                source=[package.name + '_dums.c'],
                features=['c'],
                cflags=flags.cflags,
                cincludes=flags.cincludes,
                depends_on=package.name + '_dums_cp',
            )
            dums_tg_dep = [package.name + '_dums_build']

        self.ctx(
            name=package.name + '_lib',
            path=package_node,
            target=package.name,
            source=[c.source() for c in package.components],
            features=package_features + self.libtype_features,
            cflags=flags.cflags,
            cincludes=flags.cincludes,
            cxxflags=flags.cxxflags,
            cxxincludes=flags.cxxincludes,
            linkflags=flags.linkflags,
            lib=flags.libs,
            stlib=flags.stlibs,
            includes=[package_node],
            export_includes=[package_node],
            use=internal_dep,
            uselib=external_dep,
            install_path=lib_install_path
        )

        if self.is_build_tests:
            test_features = []
            if self.is_run_tests:
                test_features = ['test']

            for c in package.components:
                if c.type_ == repounits.ComponentType.CXX:
                    comp_test_features = ['cxx', 'cxxprogram'] + test_features
                else:
                    comp_test_features = ['c', 'cprogram'] + test_features

                if c.has_test_driver:
                    self.ctx(
                        name=c.name + '.t',
                        path=package_node,
                        target=c.name + '.t',
                        source=[c.test_driver()],
                        features=comp_test_features,
                        cflags=flags.cflags,
                        cincludes=flags.cincludes,
                        cxxflags=flags.cxxflags,
                        cxxincludes=flags.cxxincludes,
                        linkflags=flags.linkflags,
                        includes=[package_node],
                        lib=flags.libs,
                        stlib=flags.stlibs,
                        cust_libpaths=flags.libpaths,
                        use=[package.name + '_lib'] + internal_dep + \
                            dums_tg_dep,
                        uselib=external_dep
                    )
                else:
                    self.ctx(
                        name=c.name + '.t',
                        path=package_node
                    )
        else:
            # Create the same number of task generators to ensure that the
            # generators created with or without tests have the same idx
            for c in package.components:
                self.ctx(
                    name=c.name + '.t',
                    path=package_node
                )

        self.ctx(
            name=package.name + '_tst',
            depends_on=[c.name + '.t' for c in package.components]
        )

        self.ctx.install_files(
            h_install_path,
            [os.path.join(relpath, c.name + '.h') for c in package.components])

    def build_thirdparty_dirs(self, third_party):
        relpath = os.path.relpath(third_party.path,
                                  self.build_config.root_path)
        self.ctx.recurse(relpath)

    def gen_pc_file(self, uor):
        # The reason for using "vc" as the output directory storing .pc files
        # is to preserve backward compatibility with an older version of this
        # tool.
        pc_node = self.ctx.path.make_node('vc')

        if self.install_flat_include:
            install_include_dir = "include"
        else:
            install_include_dir = "include/%s" % uor.name

        install_path = os.path.join('${PREFIX}', self.install_lib_dir,
                                    'pkgconfig')

        dep = sorted(uor.dep | uor.external_dep)

        self.ctx(
            name=uor.name + '.pc',
            features=['bdepc'],
            path=pc_node,
            target=uor.name + self.lib_suffix + '.pc',
            version=uor.version,
            doc=uor.doc,
            url='https://github.com/bloomberg',
            dep=dep,
            lib_name=uor.name,
            lib_suffix=self.lib_suffix,
            export_libs=uor.flags.export_libs,
            export_flags=uor.flags.export_flags,
            install_lib_dir=self.install_lib_dir,
            install_include_dir=install_include_dir,
            pc_extra_include_dirs=self.pc_extra_include_dirs,
            install_path=install_path
        )

    def export_third_party_flags(self):
        """Export build flags that may be used by third-party directories.

        Third-party directories should be built using the same build
        configuration as BDE units.

        This function exports the following variables to the build context
        environment that should be used by the wscript inside of third-party
        directories:

        - ``BDE_THIRD_PARTY_CFLAGS``
        - ``BDE_THIRD_PARTY_CXXFLAGS``
        """

        def filter_cflags(cflags):
            # Since we don't own the source code from third-party packages, do
            # not enable warnings for them.
            filtered_cflags = []
            for f in cflags:
                if not f.startswith('-W') and not f.startswith("/W"):
                    filtered_cflags.append(f)
            return filtered_cflags

        self.ctx.env['BDE_THIRD_PARTY_CFLAGS'] = \
            filter_cflags(self.build_config.default_flags.cflags)

        self.ctx.env['BDE_THIRD_PARTY_CXXFLAGS'] = \
            filter_cflags(self.build_config.default_flags.cxxflags)

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
