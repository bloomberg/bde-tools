"""Implement waf build operations.
"""

import os

from waflib import Logs

from bdebuild.meta import buildconfig
from bdebuild.meta import installconfig
from bdebuild.meta import buildconfigutil
from bdebuild.meta import graphutil
from bdebuild.meta import repounits

from bdebuild.waf import waftweaks  # NOQA


class BuildHelper(object):
    """Helper class to build a BDE-style repository.

    Attributes:
       ctx (BuildContext): The waf build context.
       build_config (BuildConfig): Build configuration of the repo.
       install_config (InstallConfig): Install configuration of the repo.
       uor_diagraph (dict of str to list): UOR depdency graph.
       third_party_lib_targets (set of str): Names of third party "_lib" task
           generators.
       libtype_features (list of str): Features to build a library
           (static or dynamic).
       is_run_tests (bool): Whether to run test drivers.
       is_build_tests (bool): Whether to build test drivers.
       global_taskgen_idx (int): The index to use for all task generators.
    """

    def __init__(self, ctx):
        for class_name in ('cxx', 'cxxprogram', 'cxxshlib', 'cxxstlib',
                           'c', 'cprogram', 'cshlib', 'cstlib'):
            waftweaks.activate_custom_exec_command(class_name)

        self.ctx = ctx

        # Use the same index for all task generators.  Since we don't ever
        # build the same source file using two different build options, this is
        # safe to do.  Doing so saves us from having to manually make task
        # generators for builds with and without test drivers to have the same
        # index.
        self.global_taskgen_idx = 1
        self.build_config = buildconfig.BuildConfig.from_pickle_str(
            self.ctx.env['build_config'])
        self.install_config = installconfig.InstallConfig.from_pickle_str(
            self.ctx.env['install_config'])

        self.uor_digraph = buildconfigutil.get_uor_digraph(self.build_config)

        if self.ctx.cmd in ('install', 'uninstall'):
            self.install_config.setup_install_uors(
                self.ctx.targets, self.ctx.options.install_dep == 'yes',
                self.uor_digraph)

            all_parts = ("lib", "bin", "h", "pc")
            install_part = self.ctx.options.install_parts

            for attr in ("is_install_" + part for part in all_parts):
                setattr(self.install_config, attr, True)
            if install_part != "all":
                for attr in ("is_install_" + part for part in all_parts
                             if part != install_part):
                    setattr(self.install_config, attr, False)

            # Reset targets to include everything to fix {DRQS 103254585}.
            # Without this and with --targets specified, headers and pc files
            # are not installed.  (Probably because we're managing to not
            # associate the installation requests with their correct targets.)
            self.ctx.targets = '*'

            Logs.info('Waf: Installing UORs: %s' %
                      ','.join(sorted(self.install_config.install_uors)))

        self.third_party_lib_targets = set(
            [d + '_lib' for d in self.build_config.third_party_dirs.keys()])

        if 'shr' in self.build_config.ufid.flags:
            self.libtype_features = ['cxxshlib']
        else:
            self.libtype_features = ['cxxstlib']

        self.is_run_tests = self.ctx.options.test in ('run', 'changed')
        self.is_build_tests = self.is_run_tests or \
            self.ctx.options.test == 'build'

        self.ctx.env['env'] = os.environ.copy()
        self.ctx.env['env'].update(self.build_config.custom_envs)

        if self.build_config.uplid.os_type == 'windows':
            # Use forward slash for paths on windows to be compatible with
            # pykg-config.py.
            self.ctx.env['PREFIX'] = self.ctx.env['PREFIX'].replace('\\', '/')

        if (any(t.endswith('.t') for t in self.ctx.targets.split(',')) and
                not self.is_build_tests):
            msg = """Did you forget to use the option '--test build'?
You must use the option '--test build' to build test drivers and the option
'--test run' to run test drivers.  For example, to build the test driver for
the bdlt_date component:

$ waf build --target bdlt_date.t --test build"""
            Logs.warn(msg)

        self.export_third_party_flags()

    def build(self):

        # Create task generators in topological order so that the actual task
        # build order would appear to be meaningful.  Note that ordering this
        # not necessary and the build would work for any order of task
        # generators.

        ordered_uor_names = graphutil.topological_sort(self.uor_digraph)

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

    def build_package_group(self, group):
        relpath = os.path.relpath(group.path, self.build_config.root_path)
        group_node = self.ctx.path.make_node(relpath)
        flags = group.flags
        internal_dep = [d + '_lib' for d in sorted(group.dep)]
        external_dep = [l.upper() for l in sorted(group.external_dep)]

        lib_install_path = self.install_config.get_lib_install_path(group.name)

        # Create task generators in topological order so that the actual task
        # build order would appear to be meaningful.
        ordered_package_names = graphutil.topological_sort(
            buildconfigutil.get_package_digraph(self.build_config, group.name))

        for package_name in ordered_package_names:
            package = self.build_config.inner_packages[package_name]
            self.build_inner_package(package, group)

        if group.name in self.build_config.soname_overrides:
            custom_soname = self.build_config.soname_overrides[group.name]
        else:
            custom_soname = None

        self.gen_pc_file(group)
        self.ctx(name=group.name + '_lib',
                 path=group_node,
                 target=self.install_config.get_target_name(group.name),
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
                 install_path=lib_install_path,
                 bdevnum=group.version,
                 bdesoname=custom_soname,
                 depends_on=[group.name + '_pc'],
                 idx=self.global_taskgen_idx
                 )

        self.ctx(
            name=group.name,
            depends_on=[group.name + '_lib'] +
            [p + '_tst' for p in ordered_package_names]
        )

    def build_stdalone_package(self, package):
        internal_dep = [d + '_lib' for d in sorted(package.dep)]
        external_dep = [l.upper() for l in sorted(package.external_dep)]

        lib_install_path = self.install_config.get_lib_install_path(
            package.name)
        h_install_path = self.install_config.get_h_install_path(
            package.name)

        self.gen_pc_file(package)
        self.build_package_impl(package, internal_dep, external_dep,
                                lib_install_path, h_install_path,
                                [package.name + '_pc'])

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
                target=self.install_config.get_target_name(package.app_main),
                source=[package.app_main + '.m.cpp'],
                features=['cxx', 'cxxprogram'],
                cflags=flags.cflags,
                cincludes=flags.cincludes,
                cxxflags=flags.cxxflags,
                cxxincludes=flags.cxxincludes,
                linkflags=flags.linkflags,
                includes=[package_node],
                lib=flags.libs,
                stlib=flags.stlibs,
                cust_libpaths=flags.libpaths,
                use=[package.name + '_lib'] + dums_tg_dep,
                uselib=external_dep,
                install_path=self.install_config.get_bin_install_path(
                    package.app_main),
                idx=self.global_taskgen_idx
            )
            depends_on.append(package.name + '_app')

        self.ctx(
            name=package.name,
            depends_on=depends_on
        )

    def build_inner_package(self, package, group):
        internal_dep = [d + '_lib' for d in sorted(package.dep | group.dep)]
        external_dep = [l.upper() for l in sorted(group.external_dep)]

        h_install_path = self.install_config.get_h_install_path(group.name,
                                                                False,
                                                                package.name)

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
            install_path=lib_install_path,
            idx=self.global_taskgen_idx,
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

        if h_install_path:
            for d in header_dirs:
                self.ctx.install_files(os.path.join(h_install_path, d),
                                       [os.path.join(relpath, d, h) for h in
                                        header_dirs[d]])

    def build_package_impl(self, package, internal_dep, external_dep,
                           lib_install_path, h_install_path,
                           extra_taskgen_dep=None):
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
                source=dums_node,
                idx=self.global_taskgen_idx,
            )
            self.ctx(
                name=package.name + '_dums_build',
                path=package_node,
                source=[package.name + '_dums.c'],
                features=['c'],
                cflags=flags.cflags,
                cincludes=flags.cincludes,
                depends_on=package.name + '_dums_cp',
                idx=self.global_taskgen_idx,
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
            install_path=lib_install_path,
            depends_on=extra_taskgen_dep,
            idx=self.global_taskgen_idx
        )

        if self.is_build_tests:
            test_features = []
            if self.is_run_tests:
                test_features = ['test']

            test_dep = [package.name + '_lib'] + dums_tg_dep

            if 'shr' in self.build_config.ufid.flags:
                # We need to include third-party dependencies manually for test
                # drivers because some third-party libraries are always built
                # as static libraries, even if the shared library build
                # configuration is being used.  Sometimes, a test driver
                # depends on more symbols from the third-party library than the
                # component of the test driver, such as
                # 'bdldfp_decimalimputil_inteldfp'.

                third_party_dep = sorted(set(internal_dep) &
                                         self.third_party_lib_targets)
                test_dep += third_party_dep

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
                        cflags=flags.test_cflags,
                        cincludes=flags.test_cincludes,
                        cxxflags=flags.test_cxxflags,
                        cxxincludes=flags.test_cxxincludes,
                        linkflags=flags.linkflags,
                        includes=[package_node],
                        lib=flags.libs,
                        stlib=flags.stlibs,
                        cust_libpaths=flags.libpaths,
                        use=test_dep,
                        uselib=external_dep,
                        idx=self.global_taskgen_idx
                    )

            self.ctx(
                name=package.name + '_tst',
                depends_on=[c.name + '.t' for c in package.components
                            if c.has_test_driver]
            )
        else:
            self.ctx(name=package.name + '_tst')

        if h_install_path:
            self.ctx.install_files(
                h_install_path, [os.path.join(relpath, c.name + '.h')
                                 for c in package.components])

    def build_thirdparty_dirs(self, third_party):
        relpath = os.path.relpath(third_party.path,
                                  self.build_config.root_path)
        self.ctx.recurse(relpath)

    def gen_pc_file(self, uor):
        # The reason for using "vc" as the output directory storing .pc files
        # is to preserve backward compatibility with an older version of this
        # tool.

        pc_node = self.ctx.path.make_node('vc')

        pc_install_path = self.install_config.get_pc_install_path(uor.name)
        pc_libdir = self.install_config.get_pc_libdir(uor.name)
        pc_includedir = self.install_config.get_pc_includedir(uor.name)
        pc_extra_includes = self.install_config.get_pc_extra_includes(uor.name)
        pc_libname = self.install_config.get_target_name(uor.name)

        dep = sorted(uor.dep | uor.external_dep)

        self.ctx(
            name=uor.name + '_pc',
            features=['bdepc'],
            path=pc_node,
            target=pc_libname + '.pc',
            version=uor.version,
            doc=uor.doc,
            url='https://github.com/bloomberg',
            libname=pc_libname,
            dep=[d + self.install_config.lib_suffix for d in dep],
            libdir=pc_libdir,
            includedir=pc_includedir,
            export_libs=uor.flags.export_libs,
            extra_includes=pc_extra_includes,
            export_flags=uor.flags.export_flags,
            install_path=pc_install_path
        )

    def export_third_party_flags(self):
        """Export build flags that may be used by third-party directories.

        Third-party directories should be built using the same build
        configuration as BDE units.
        """

        def filter_cflags(cflags):
            # Since we don't own the source code for third-party directories,
            # do not enable warnings for them.
            filtered_cflags = []
            for f in cflags:
                if not f.startswith('-W') and not f.startswith("/W"):
                    filtered_cflags.append(f)
            return filtered_cflags

        for tp in self.build_config.third_party_dirs:
            key = 'bde_thirdparty_%s_config' % tp

            cflags = filter_cflags(self.build_config.default_flags.cflags)
            cxxflags = filter_cflags(self.build_config.default_flags.cxxflags)

            if (self.build_config.uplid.os_type == 'windows' and
                # By default, Visual Studio uses a single pdb file for all
                # object files compiled from a particular directory named
                # vc<vs_version>.pdb.  We want to use a separate pdb file for
                # each third-party package.  Similar logic for using separate
                # pdb files for libraries built from package groups and
                # standalone package is done in the module
                # meta.buildconfigfactory.
                    self.build_config.uplid.comp_type == 'cl'):
                tp_unit = self.build_config.third_party_dirs[tp]
                pdb_option = '/Fd%s\\%s.pdb' % (
                    os.path.relpath(tp_unit.path, self.build_config.root_path),
                    tp_unit.name)
                cflags += [pdb_option]
                cxxflags += [pdb_option]

            self.ctx.env[key] = {
                'cflags': cflags,
                'cxxflags': cxxflags,
                'lib_target': self.install_config.get_target_name(tp),
                'lib_install_path':
                self.install_config.get_lib_install_path(tp),
                'h_install_path':
                self.install_config.get_h_install_path(tp, True),
                'pc_install_path':
                self.install_config.get_pc_install_path(tp),
                'pc_libdir':
                self.install_config.get_pc_libdir(tp),
                'pc_includedir':
                self.install_config.get_pc_includedir(tp, True),
            }

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
