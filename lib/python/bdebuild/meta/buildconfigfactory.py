"""Evaluating build configurations for a BDE-style repository.
"""

import os
import copy
import re

from bdebuild.meta import buildconfig
from bdebuild.meta import graphutil
from bdebuild.meta import optionsevaluator
from bdebuild.common import logutil
from bdebuild.meta import repounits
from bdebuild.meta import repocontextutil


def make_build_config(repo_context, build_flags_parser, uplid, ufid,
                      default_rules, debug_keys=[]):
    """Create a build configuration for repository.

    Args:
        repo_context (RepoContext): Repository structure and metadata.
        build_flags_parser (BuildFlagsParser): Parser for build flags.
        uplid (Uplid): Build platform id.
        ufid (Ufid): Build flags id.
        default_rules (list of OptionRule): Option rules that is the base of
            all UORs.
        debug_keys (list of str): Print some debug information for some
            option keys.
    """

    build_config = buildconfig.BuildConfig(repo_context.root_path, uplid,
                                           ufid)

    for unit in repo_context.units.values():
        if unit.type_ == repounits.UnitType.THIRD_PARTY_DIR:
            build_config.third_party_dirs[unit.name] = unit

    uor_dep_graph = repocontextutil.get_uor_digraph(repo_context)
    uor_map = repocontextutil.get_uor_map(repo_context)

    build_config.external_dep = graphutil.find_external_nodes(uor_dep_graph)

    # BDE_CXXINCLUDES is hard coded in bde_build
    initial_options = {
        'BDE_CXXINCLUDES': '$(BDE_CXXINCLUDE)'
    }

    # Waf already knows about the flags necessary for building shared objects,
    # so don't get the necessary flags from opts files.  We don't have to the
    # operation below once we remove the the option rules for 'shr' in the
    # default option files.

    effective_ufid = copy.deepcopy(build_config.ufid)
    effective_ufid.flags.discard('shr')
    def_oe = optionsevaluator.OptionsEvaluator(build_config.uplid,
                                               effective_ufid,
                                               initial_options)

    def_oe.store_option_rules(default_rules, debug_keys)

    def_oe_copy = copy.deepcopy(def_oe)
    def_oe_copy.evaluate()
    build_config.default_flags = get_build_flags_from_opts(
        build_flags_parser, def_oe_copy.results, def_oe_copy.results)

    # These custom environment variables comes from default_internal.opts and
    # needs to be set when building dpkg.
    env_variables = ('SET_TMPDIR', 'XLC_LIBPATH')
    setenv_re = re.compile(r'^([^=]+)=(.*)$')
    for e in env_variables:
        if e in def_oe_copy.results:
            m = setenv_re.match(def_oe_copy.results[e])
            if m:
                build_config.custom_envs[m.group(1)] = m.group(2)

    def set_unit_loc(oe, unit):
        oe.results['%s_LOCN' %
                   unit.name.upper().replace('+', '_')] = unit.path

    def load_uor(uor):
        # Preserve the existing behavior of loading defs, opts and cap files as
        # bde_build:
        #
        # - Exported options of an UOR: read the defs files of its dependencies
        #   follow by itself. The files of the dependencies should be read in
        #   topological order, if the order of certain dependencies are
        #   ambiguous, order them first by dependency levels, and then by their
        #   name.
        #
        # - Internal options of an UOR: read the defs files in the same way,
        #   followed by its own opts file.

        dep_levels = graphutil.levelize(uor_dep_graph,
                                        uor_dep_graph[uor.name])

        oe = copy.deepcopy(def_oe)
        # We load options in levelized order instead of any topological order
        # to preserve the behavior with bde_build (older version of the build
        # tool).  Note that we cannot cache intermediate results because later
        # option rules may change the results from the preivous rule.

        if uor.type_ == repounits.UnitType.GROUP:
            uor_bc = buildconfig.PackageGroupBuildConfig()
        elif uor.type_ in repounits.UnitTypeCategory.PACKAGE_STAND_ALONE_CAT:
            uor_bc = buildconfig.StdalonePackageBuildConfig()
        else:
            assert(False)

        for level in dep_levels:
            for dep_name in sorted(level):
                if dep_name in build_config.external_dep:
                    uor_bc.external_dep.add(dep_name)
                elif dep_name not in build_config.third_party_dirs:
                    dep_uor = uor_map[dep_name]
                    oe.store_option_rules(dep_uor.cap)
                    oe.store_option_rules(dep_uor.defs)

        if (build_config.uplid.os_type == 'windows' and
                build_config.uplid.comp_type == 'cl'):
            # By default, Visual Studio uses a single pdb file for all object
            # files compiled from a particular directory named
            # vc<vs_version>.pdb.  We want to use a separate pdb file for each
            # package group and standard alone package.
            #
            # BDE_CXXFLAGS and BDE_CFLAGS are defined by default.opts, so the
            # code below is a bit hackish.
            pdb_option = ' /Fd%s\\%s.pdb' % (
                os.path.relpath(uor.path, build_config.root_path), uor.name)
            oe.options['BDE_CXXFLAGS'] += pdb_option
            oe.options['BDE_CFLAGS'] += pdb_option

        uor_bc.name = uor.name
        uor_bc.path = uor.path
        uor_bc.doc = uor.doc
        uor_bc.version = uor.version
        uor_bc.dep = uor.dep - build_config.external_dep
        uor_bc.external_dep.union(uor.dep & build_config.external_dep)

        # Store options from dependencies, options for exports, and internal
        # options separately

        dep_oe = copy.deepcopy(oe)
        dep_oe.evaluate()
        oe.store_option_rules(uor.cap)
        oe.store_option_rules(uor.defs)
        set_unit_loc(oe, uor)
        export_oe = copy.deepcopy(oe)
        int_oe = copy.deepcopy(oe)
        export_oe.evaluate()
        if export_oe.results.get('CAPABILITY') == 'NEVER':
            logutil.warn('Skipped non-supported UOR %s' % uor.name)
            return

        int_oe.store_option_rules(uor.opts)

        # Copy unevaluted internal options to be used by packages within
        # package groups.
        int_oe_copy = copy.deepcopy(int_oe)
        if debug_keys:
            logutil.info('--Evaluating %s' % uor.name)
        int_oe.evaluate(debug_keys)

        # Remove export flags of an uor's dependencies from its own export
        # flags.  This implementation is not very optimal, but it's gets the
        # job done.
        dep_flags = get_build_flags_from_opts(build_flags_parser,
                                              dep_oe.results, dep_oe.results)

        if uor.name == 'bsl':
            # Include flags such as "-lpthread" in bsl.pc, because
            # historically, some of the applications built on top of BDE
            # requires this.
            exclude_exportflags = []
            exclude_exportlibs = []
        else:
            exclude_exportflags = dep_flags.export_flags
            exclude_exportlibs = dep_flags.export_libs

        uor_bc.flags = get_build_flags_from_opts(
            build_flags_parser, int_oe.results, export_oe.results,
            exclude_exportflags, exclude_exportlibs)

        if uor.type_ == repounits.UnitType.GROUP:
            load_package_group(uor, uor_bc, int_oe_copy)
        elif uor.type_ in repounits.UnitTypeCategory.PACKAGE_STAND_ALONE_CAT:
            load_sa_package(uor, uor_bc)
        else:
            assert(False)

    def load_sa_package(package, package_bc):
        package_bc.components = package.components
        package_bc.type_ = package.type_
        package_bc.has_dums = package.has_dums
        package_bc.app_main = package.app_main
        build_config.stdalone_packages[package_bc.name] = package_bc

    def load_package_group(group, group_bc, oe):
        skipped_packages = set()
        for package_name in group.mem:
            is_skipped = not load_normal_package(package_name, oe)
            if is_skipped:
                skipped_packages.add(package_name)

        group_bc.mem = group.mem - skipped_packages
        build_config.package_groups[group_bc.name] = group_bc

    def load_normal_package(package_name, oe):
        package = repo_context.units[package_name]
        int_oe = copy.deepcopy(oe)
        int_oe.store_option_rules(package.opts)
        int_oe.store_option_rules(package.cap)
        set_unit_loc(int_oe, package)

        if debug_keys:
            logutil.info('--Evaluating %s' % package_name)
        int_oe.evaluate(debug_keys)

        if int_oe.results.get('CAPABILITY') == 'NEVER':
            logutil.warn('Skipped non-supported package %s' % package_name)
            return False

        if package.type_ == repounits.PackageType.PACKAGE_PLUS:
            package_bc = buildconfig.PlusPackageBuildConfig()
        else:
            package_bc = buildconfig.InnerPackageBuildConfig()

        package_bc.name = package.name
        package_bc.path = package.path
        package_bc.dep = package.dep
        package_bc.type_ = package.type_
        package_bc.flags = get_build_flags_from_opts(build_flags_parser,
                                                     int_oe.results)
        package_bc.has_dums = package.has_dums

        if package.type_ == repounits.PackageType.PACKAGE_PLUS:
            package_bc.headers = package.pt_extras.headers
            package_bc.cpp_sources = package.pt_extras.cpp_sources
            package_bc.cpp_tests = package.pt_extras.cpp_tests
            package_bc.c_tests = package.pt_extras.c_tests
        else:
            package_bc.components = package.components

        build_config.inner_packages[package_name] = package_bc
        return True

    for unit in repo_context.units.values():
        if (unit.type_ in repounits.UnitTypeCategory.UOR_CAT and
                unit.type_ != repounits.UnitType.THIRD_PARTY_DIR):
            load_uor(unit)

    # Sometimes we want to override the default SONAME used for a shared
    # object.  This can be done by setting a environment variable.
    # E.g., we can set 'BDE_BSL_SONAME' to 'robo20150101bsl' to set the
    # SONAME of the shared object built for the package group 'bsl'.

    for name in uor_map:
        soname = os.environ.get('BDE_%s_SONAME' % name.upper())
        if soname:
            build_config.soname_overrides[name] = soname

    return build_config


def get_build_flags_from_opts(parser, options, export_options=None,
                              exclude_exportflags=None,
                              exclude_exportlibs=None):
    cxx = options['CXX'].split()[1:]
    cc = options['CC'].split()[1:]
    cxxlink = options['CXXLINK'].split()[1:]

    def load_flags(flags, cxxflags, cflags, ldflags, test_cxxflags,
                   test_cflags):
        # test_flags = buildconfig.BuildFlags()

        flags.cxxincludes, flags.cxxflags = parser.partition_cflags(
            cxx + cxxflags)

        flags.cincludes, flags.cflags = parser.partition_cflags(
            cc + cflags)

        flags.stlibs, flags.libs, flags.libpaths, flags.linkflags = \
            parser.partition_linkflags(cxxlink + ldflags)

        flags.test_cxxincludes, flags.test_cxxflags = parser.partition_cflags(
            cxx + test_cxxflags)

        flags.test_cincludes, flags.test_cflags = parser.partition_cflags(
            cc + test_cflags)

    def load_export_flags(flags, cxxflags, ldflags):

        flags.export_flags = parser.get_export_cflags(cxxflags)
        flags.export_libs = parser.partition_linkflags(cxxlink + ldflags)[1]

        if exclude_exportflags:
            flags.export_flags = [f for f in flags.export_flags if f not in
                                  exclude_exportflags]

        if exclude_exportlibs:
            flags.export_libs = [l for l in flags.export_libs if l not in
                                 exclude_exportlibs]

    flags = buildconfig.BuildFlags()

    load_flags(flags,
               options['COMPONENT_BDEBUILD_CXXFLAGS'].split(),
               options['COMPONENT_BDEBUILD_CFLAGS'].split(),
               options['COMPONENT_BDEBUILD_LDFLAGS'].split(),
               options['TESTDRIVER_BDEBUILD_CXXFLAGS'].split(),
               options['TESTDRIVER_BDEBUILD_CFLAGS'].split())
    if export_options:
        load_export_flags(
            flags,
            export_options['COMPONENT_BDEBUILD_CXXFLAGS'].split(),
            export_options['COMPONENT_BDEBUILD_LDFLAGS'].split())

    return flags

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
