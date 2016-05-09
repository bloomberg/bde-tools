"""Implement waf.configure operations.
"""

import copy
import os
import sys

from waflib import Logs

from bdebuild.common import sysutil
from bdebuild.meta import buildconfigfactory
from bdebuild.meta import buildconfigutil
from bdebuild.meta import buildflagsparser
from bdebuild.meta import installconfig
from bdebuild.meta import optionsutil
from bdebuild.meta import optionsparser
from bdebuild.meta import optiontypes
from bdebuild.meta import repocontextloader
from bdebuild.meta import repocontextverifier


class ConfigureHelper(object):

    def __init__(self, ctx, ufid, effective_uplid, actual_uplid):
        self.ctx = ctx
        self.ufid = ufid
        self.uplid = effective_uplid
        self.actual_uplid = actual_uplid
        optionsparser.is_verbose = self.ctx.options.verify

    def configure(self):
        self.ctx.msg('Prefix', self.ctx.env['PREFIX'])
        if self.uplid == self.actual_uplid:
            self.ctx.msg('Uplid', self.uplid)
        else:
            self.ctx.msg('Uplid - effective (this is *used*):',
                         str(self.uplid) + ' (from BDE_WAF_UPLID)',
                         color='YELLOW')
            self.ctx.msg('Uplid - actual (this is *not* used):',
                         self.actual_uplid, color='YELLOW')

        if os.getenv('BDE_WAF_UFID'):
            self.ctx.msg('Ufid',
                         str(self.ufid) + ' (from BDE_WAF_UFID)')
        else:
            self.ctx.msg('Ufid', self.ufid)

        if self.ctx.options.verbose >= 1:
            self.ctx.msg('OS type', self.uplid.os_type)
            self.ctx.msg('OS name', self.uplid.os_name)
            self.ctx.msg('CPU type', self.uplid.cpu_type)
            self.ctx.msg('OS version', self.uplid.os_ver)
            self.ctx.msg('Compiler type', self.uplid.comp_type)
            self.ctx.msg('Compiler version', self.uplid.comp_ver)

        loader = repocontextloader.RepoContextLoader(self.ctx.path.abspath())
        loader.load()

        self.repo_context = loader.repo_context

        if self.ctx.options.verify:
            self._verify()

        build_flags_parser = buildflagsparser.BuildFlagsParser(
            self.ctx.env['SHLIB_MARKER'],
            self.ctx.env['STLIB_MARKER'],
            self.ctx.env['LIB_ST'].replace('.', '\.').replace(
                '%s', r'([^ =]+)$'),
            self.ctx.env['LIBPATH_ST'].replace('.', '\.').replace(
                '%s', r'([^ =]+)'),
            self.ctx.env['CPPPATH_ST'].replace('.', '\.').replace(
                '%s', r'([^ =]+)'),
            '/D' if self.uplid.comp_type == 'cl' else '-D')

        default_rules = optionsutil.get_default_option_rules()

        # Enable -Werror for building .cpp files (but not .t.cpp) if --werror
        # is enabled.
        if self.ctx.options.werror == 'cpp':
            default_rules.append(optiontypes.OptionRule(
                optiontypes.OptionCommand.ADD,
                optiontypes.Uplid.from_str('*-*-*-*-gcc-*'),
                optiontypes.Ufid(),
                'COMPONENT_BDEBUILD_CXXFLAGS',
                '-Werror'))
            default_rules.append(optiontypes.OptionRule(
                optiontypes.OptionCommand.ADD,
                optiontypes.Uplid.from_str('*-*-*-*-clang-*'),
                optiontypes.Ufid(),
                'COMPONENT_BDEBUILD_CXXFLAGS',
                '-Werror'))

        debug_opt_keys = self.ctx.options.debug_opt_keys.split(',') if \
            self.ctx.options.debug_opt_keys is not None else []
        self.build_config = buildconfigfactory.make_build_config(
            self.repo_context, build_flags_parser, self.uplid, self.ufid,
            default_rules, debug_opt_keys)

        def print_list(label, l):
            if len(l):
                self.ctx.msg(label, ' '.join([str(i) for i in l]))

        print_list('Configured package groups',
                   sorted(self.build_config.package_groups))
        print_list('Configured stand-alone packages',
                   sorted(self.build_config.stdalone_packages))
        print_list('Configured third-party packages',
                   sorted(self.build_config.third_party_dirs))
        print_list('Loading external dependencies',
                   sorted(self.build_config.external_dep))
        self._configure_external_libs()

        if self.build_config.soname_overrides:
            for uor_name in self.build_config.soname_overrides:
                self.ctx.msg('Override SONAME for %s' % uor_name,
                             self.build_config.soname_overrides[uor_name])

        self.install_config = installconfig.InstallConfig(
            self.ufid,
            self.ctx.options.use_dpkg_install,
            self.ctx.options.use_flat_include_dir,
            self.ctx.options.libdir,
            self.ctx.options.bindir,
            self.ctx.options.lib_suffix)

        # The .pc files should be UFID neutral when installed to the DPKG
        # environment in Bloomberg.  I.e., a single .pc file supports multiple
        # UFID-specific types of a library.  By default, the installed .pc file
        # points to the release library.  A client can select a different
        # library type (e.g., dbg_mt_exc_safe) by prepending an -L linker flag
        # pointing to that particular type.  Here, we remove exported macro
        # definitions that are specific to any single UFID library type.
        if (self.ctx.options.use_dpkg_install and
                'bsl' in self.build_config.package_groups):
            pg = self.build_config.package_groups['bsl']
            remove_flags = []
            for f in pg.flags.export_flags:
                if (f.find('BDE_BUILD_TARGET') != -1 or
                        f.find('NDEBUG') != -1):
                    remove_flags.append(f)
            for f in remove_flags:
                pg.flags.export_flags.remove(f)

        self.ctx.msg('Use flat include directory',
                     'yes' if self.install_config.is_flat_include else 'no')
        self.ctx.msg('Lib install directory', self.install_config.lib_dir)
        self.ctx.msg('Pkg-config install directory',
                     self.install_config.pc_dir)
        if self.install_config.lib_suffix:
            self.ctx.msg('Lib name suffix', self.install_config.lib_suffix)

        num_uors = len(self.build_config.package_groups) + \
            len(self.build_config.stdalone_packages) + \
            len(self.build_config.third_party_dirs)
        num_inner_packages = len(self.build_config.inner_packages)
        num_components = 0
        for c in map(buildconfigutil.count_components_in_package,
                     list(self.build_config.inner_packages.values()) +
                     list(self.build_config.stdalone_packages.values())):
            num_components += c

        print_list('# UORs, inner packages, and components',
                   (num_uors, num_inner_packages, num_components))

        if self.ctx.options.verbose >= 2:
            self.ctx.msg('Build configuration details', self.build_config)

        self._save()

    def _verify(self):
        self.ctx.msg('Performing additional checks', '')
        verifier = repocontextverifier.RepoContextVerifier(self.repo_context)

        verifier.verify()
        if not verifier.is_success:
            self.ctx.fatal('Repo verification failed.')

    def _configure_distribution_refroot(self):
        # When the DISTRIBUTION_REFROOT environment variable is set, then
        # configure waf to consume external libraries from the refroot.  This
        # is mainly used with the DPKG environment at Bloomberg.
        if 'DISTRIBUTION_REFROOT' in os.environ:
            distribution_refroot = os.environ['DISTRIBUTION_REFROOT']
            self.ctx.msg('Using DISTRIBUTION_REFROOT', distribution_refroot)
            prefix = os.path.join(distribution_refroot, 'opt', 'bb')
            lib_path = os.path.join(prefix,
                                    '64' in self.ufid.flags
                                    and 'lib64' or 'lib')
            pkg_config_path = os.path.join(lib_path, 'pkgconfig')
            if 'PKG_CONFIG_PATH' in os.environ:
                pkg_config_path += ':' + os.environ['PKG_CONFIG_PATH']
            os.environ['PKG_CONFIG_PATH'] = pkg_config_path
            ufid_copy = copy.deepcopy(self.ufid)
            ufid_copy.flags.discard('64')
            extra_link_flag = self.ctx.env['LIBPATH_ST'] % os.path.join(
                lib_path, str(ufid_copy))
            if 'LINKFLAGS' in self.ctx.env:
                self.ctx.env['LINKFLAGS'].append(extra_link_flag)
            else:
                self.ctx.env['LINKFLAGS'] = [extra_link_flag]

            self.ctx.env['PKG_CONFIG_DEFINES'] = dict(prefix=prefix)

    def _configure_external_libs(self):

        if len(self.build_config.external_dep) == 0:
            return

        self._configure_distribution_refroot()
        try:
            self.ctx.find_program('pkg-config', var='PKGCONFIG')
        except self.ctx.errors.ConfigurationError:
            Logs.warn('Could not find pkg-config on the PATH.  Using the'
                      'built-in python based pkg-config (pykg-config) '
                      'instead.')
            self.ctx.env['PKGCONFIG'] = [sys.executable, os.path.join(
                sysutil.repo_root_path(), 'bin', 'tools', 'pykg-config',
                'pykg-config.py')]
            self.ctx.find_program('pkg-config', var='PKGCONFIG')

        pkgconfig_args = ['--libs', '--cflags']

        if 'shr' not in self.ufid.flags:
            pkgconfig_args.append('--static')

        # If the static build is chosen (the default), waf assumes that all
        # libraries queried from pkg-config are to be built statically, which
        # is not true for some libraries. We work around this issue by manually
        # changing the affected libraries to be linked dynamically instead.
        dl_overrides = ['pthread', 'rt', 'nsl', 'socket']

        # If lib_suffix is set, we expect the pkgconfig files being depended on
        # to have the same suffix as well. Since the .dep files will not have
        # the suffix, we will remove the suffix from the names of the options
        # loaded into the waf environment.
        rename_keys = ['defines', 'includes', 'lib', 'libpath', 'stlib',
                       'stlibpath']
        lib_suffix = self.ctx.options.lib_suffix
        for lib in sorted(self.build_config.external_dep):
            actual_lib = lib + str(lib_suffix or '')
            help_str = """failed to find the library using pkg-config
Maybe "%s.pc" is missing from "PKG_CONFIG_PATH"? Inspect config.log in the
build output directory for details.""" % \
                actual_lib
            self.ctx.check_cfg(
                package=actual_lib,
                args=pkgconfig_args,
                errmsg=help_str)

            if lib_suffix:
                for k in rename_keys:
                    key_old = (k + '_' + actual_lib).upper()
                    key_new = (k + '_' + lib).upper()
                    self.ctx.env[key_new] = self.ctx.env[key_old]
                    del self.ctx.env[key_old]

            sl_key = ('stlib_' + lib).upper()
            dl_key = ('lib_' + lib).upper()

            # preserve the order of libraries
            for l in dl_overrides:
                if l in self.ctx.env[sl_key]:
                    if dl_key not in self.ctx.env:
                        self.ctx.env[dl_key] = []

                    self.ctx.env[sl_key].remove(l)
                    self.ctx.env[dl_key].append(l)

        if lib_suffix:
            defines_old = self.ctx.env['DEFINES']
            defines_new = []
            for d in defines_old:
                index = d.find('%s=1' % lib_suffix.upper())
                if index >= 0:
                    defines_new.append('%s=1' % d[0:index])
                else:
                    defines_new.append(d)

            self.ctx.env['DEFINES'] = defines_new

    def _save(self):
        self.ctx.env['build_config'] = self.build_config.to_pickle_str()
        self.ctx.env['install_config'] = self.install_config.to_pickle_str()
        self._save_custom_waf_internals()

    def _save_custom_waf_internals(self):
        """Modify and save modifications to waf's internal variables.
        """

        # bde_setwafenv.py sometimes adds additional compiler flags for a
        # particular compular via the 'BDE_WAF_COMP_FLAGS' environment
        # variable.  This is mostly done to support special compiler flags such
        # as '-qpath' for the IBM Xlc compiler that can be partially patched.
        extra_cflags = (os.environ.get('BDE_WAF_COMP_FLAGS') or '').split()
        extra_cxxflags = list(extra_cflags)

        flags_map = {
            'CFLAGS': extra_cflags,
            'CXXFLAGS': extra_cxxflags
        }

        for var, flags in flags_map.items():
            if flags:
                if var in self.ctx.env:
                    self.ctx.env[var] = flags + self.ctx.env[var]
                else:
                    self.ctx.env[var] = flags

        if self.uplid.os_type == 'windows':

            # /MT is the default for cl.exe compiler, but /MD is the default
            # for the MSVC compiler. We explicitly define the flags for both
            # static and dynamic runtime types for the sack of clarity.
            if self.ctx.options.msvc_runtime_type == 'dynamic':
                rt_flag = '/MD'
            else:
                rt_flag = '/MT'

            if 'dbg' in self.ufid.flags:
                rt_flag += 'd'

            self.ctx.env.append_value('CFLAGS', [rt_flag])
            self.ctx.env.append_value('CXXFLAGS', [rt_flag])

            if 'INCLUDES_BSL' in self.ctx.env:
                # For visual studio, waf explicitly includes the system header
                # files by setting the 'INCLUDES' variable. BSL_OVERRIDE_STD
                # mode requires that the system header files, which contains
                # the standard library, be overridden with custom versions in
                # bsl, so we workaround the issue by moving the system includes
                # to 'INCLUDE_BSL' if it exists. This solution is not perfect,
                # because it doesn't support package groups that doesn't depend
                # on bsl -- this is not a problem for BDE libraries.

                # Assume that 'INCLUDES' containly system header only.
                self.ctx.env['INCLUDES_BSL'].extend(self.ctx.env['INCLUDES'])
                del self.ctx.env['INCLUDES']

        if self.uplid.comp_type == 'xlc':

            # The default xlc linker options for linking shared objects for waf
            # are '-brtl' and '-bexpfull', bde_build does not use '-bexpfull',
            # change the options to preserve binary compatibility.

            self.ctx.env['LINKFLAGS_cxxshlib'] = ['-G', '-brtl']
            self.ctx.env['LINKFLAGS_cshlib'] = ['-G', '-brtl']

            # The envrionment variables SHLIB_MARKER and STLIB_MARKERS are used
            # by the '_parse_ldflags' function to determine wheter a library is
            # to be linked staticcally or dyanmically.  These are not set by
            # waf xlc plugin.
            self.ctx.env['SHLIB_MARKER'] = '-bdynamic'
            self.ctx.env['STLIB_MARKER'] = '-bstatic'

            # ar on aix only processes 32-bit object files by default
            if '64' in self.ufid.flags:
                self.ctx.env['ARFLAGS'] = ['-rcs', '-X64']

        if (self.uplid.os_name == 'sunos' and self.uplid.comp_type == 'cc'):

            # Work around bug in waf's sun CC plugin to allow for properly
            # adding SONAMES. TODO: submit patch
            self.ctx.env['SONAME_ST'] = '-h %s'
            self.ctx.env['DEST_BINFMT'] = 'elf'

            # Sun C++ linker  doesn't link in the Std library by default
            if 'shr' in self.ufid.flags:
                if 'LINKFLAGS' not in self.ctx.env:
                    self.ctx.env['LINKFLAGS'] = []
                self.ctx.env['LINKFLAGS'].extend(['-zdefs', '-lCstd', '-lCrun',
                                                  '-lc', '-lm', '-lsunmath',
                                                  '-lpthread'])

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
