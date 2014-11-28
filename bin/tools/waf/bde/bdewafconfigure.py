import copy
import os
import re

from bdeoptions import Options, OptionMask, RawOptions
from waflib import Utils, Logs


class BdeWafConfigure(object):

    def __init__(self, ctx):
        self.ctx = ctx

        self.external_libs = set()
        self.export_groups = []
        self.group_dep = {}
        self.group_mem = {}
        self.group_defs = {}
        self.group_opts = {}
        self.group_doc = {}
        self.group_cap = {}
        self.group_ver = {}

        # Stores the subdirectory under which the stand-alone package is stored
        # e.g. { 'a_comdb2': 'adapters' } = package 'a_comdb2' is stored under
        # 'adapters' meta-data of stand-alone packages are stored with package
        # groups
        self.sa_package_locs = {}
        self.third_party_locs = {}

        self.soname_override = {}

        # Stores the subdirectory under which the package group is stored.
        # Almost all package groups currently reside under the 'groups'
        # directory, with a few exceptions such as 'e_ipc', which resides under
        # the 'enterprise' directory.
        self.group_locs = {}

        self.package_dep = {}
        self.package_mem = {}
        self.package_pub = {}
        self.package_opts = {}
        self.package_cap = {}
        self.package_dums = []

        self.component_type = {}  # c or cpp
        self.package_type = {}  # c or cpp

        self.unsupported_groups = set()
        self.unsupported_packages = set()

        self.group_options = {}
        self.group_export_options = {}
        self.package_options = {}
        self.custom_envs = {}

        self.lib_suffix = self.ctx.options.lib_suffix
        self.pc_extra_include_dirs = []

    def configure(self, uplid, ufid):
        self.ctx.msg('os_type', uplid.uplid['os_type'])
        self.ctx.msg('os_name', uplid.uplid['os_name'])
        self.ctx.msg('cpu_type', uplid.uplid['cpu_type'])
        self.ctx.msg('os_ver', uplid.uplid['os_ver'])
        self.ctx.msg('comp_type', uplid.uplid['comp_type'])
        self.ctx.msg('comp_ver', uplid.uplid['comp_ver'])
        self.ctx.msg('uplid', uplid)
        self.ctx.msg('ufid', ufid)
        self.ctx.msg('prefix', self.ctx.options.prefix)

        self._load_metadata()
        self._configure_external_libs(ufid)
        self._configure_options(uplid)
        self._save()

    REMOVE_COMMENT_RE = re.compile(r'^([^#]*)(#.*)?$')

    @staticmethod
    def _get_meta(node, metadir, metatype):
        metafile = node.make_node([metadir, node.name + '.' + metatype])
        entries = []
        txt = metafile.read()
        for line in txt.splitlines():
            entries.extend(
                BdeWafConfigure.REMOVE_COMMENT_RE.match(line).group(1).split())

        return entries

    def _get_raw_options(self, node, metadir, metatype):
        metafile = node.make_node([metadir, node.name + '.' + metatype])
        raw_options = RawOptions()
        raw_options.read(metafile.abspath())

        return raw_options.options

    def _parse_group_doc(self, group_node):
        '''
        parse the doc of a package group and return (name, description) to be
        used in the .pc file
        '''
        name = group_node.name
        doc_node = group_node.make_node(['doc', name + '.txt'])

        try:
            doc = Utils.readf(doc_node.abspath())

            purpose = None
            mnemonic = None
            for line in doc.split('\n'):
                if line.startswith('@PURPOSE'):
                    purpose = line.split(':')[1].strip()

                elif line.startswith('@MNEMONIC'):
                    mnemonic = line.split(':')[1].strip()

                if purpose and mnemonic:
                    return (mnemonic, purpose)
        except:
            pass

        return (name, 'N/A')

    def _load_metadata(self):
        self.ctx.start_msg('Loading BDE metadata')

        groups_nodes = [x.parent.parent for x in
                        self.ctx.path.ant_glob('groups/*/group/*.mem')]
        enterprise_nodes = [x.parent.parent for x in
                            self.ctx.path.ant_glob('enterprise/*/group/*.mem')]
        wrapper_group_nodes = [x.parent.parent for x in
                               self.ctx.path.ant_glob(
                                   'wrappers/*/group/*.mem')]
        third_party_nodes = [x.parent for x in
                             self.ctx.path.ant_glob('third-party/*/wscript')]

        group_nodes = groups_nodes + enterprise_nodes + wrapper_group_nodes

        for g in group_nodes:
            self.group_dep[g.name] = self._get_meta(g, 'group', 'dep')
            self.group_mem[g.name] = self._get_meta(g, 'group', 'mem')
            self.group_defs[g.name] = self._get_raw_options(g, 'group', 'defs')
            self.group_opts[g.name] = self._get_raw_options(g, 'group', 'opts')
            self.group_cap[g.name] = self._get_raw_options(g, 'group', 'cap')
            self.group_doc[g.name] = self._parse_group_doc(g)
            if g.name + 'scm' in g.listdir():
                self.export_groups.append(g.name)

            self.group_locs[g.name] = g.parent.name

        # Stand-alone packages behaves like package groups with a single
        # package.
        adapter_nodes = [x.parent.parent for x in
                         self.ctx.path.ant_glob('adapters/*/package/*.mem')]
        wrapper_package_nodes = [x.parent.parent for x in
                                 self.ctx.path.ant_glob(
                                     'wrappers/*/package/*.mem')]
        sa_package_nodes = adapter_nodes + wrapper_package_nodes

        for s in sa_package_nodes:
            # Assume that std-alone packages are not headers only and do not
            # have 'pub' files.
            self.group_dep[s.name] = self._get_meta(s, 'package', 'dep')
            self.group_mem[s.name] = self._get_meta(s, 'package', 'mem')
            self.group_defs[s.name] = self._get_raw_options(s, 'package',
                                                            'defs')
            self.group_opts[s.name] = self._get_raw_options(s, 'package',
                                                            'opts')
            self.group_cap[s.name] = self._get_raw_options(s, 'package', 'cap')
            self.group_doc[s.name] = self._parse_group_doc(s)

            dums_file = s.make_node('package').find_node(s.name + '.dums')
            if dums_file:
                self.package_dums.append(s.name)

            self.export_groups.append(s.name)
            self.sa_package_locs[s.name] = s.parent.name

        # Third party repos, similar to standard along packages, are
        # hierarchically on the same level as package groups.  They also do not
        # have any dependency on bde libraries.
        for t in third_party_nodes:
            third_party_name = "third-party/" + t.name
            self.third_party_locs[third_party_name] = third_party_name
            self.group_dep[third_party_name] = []

        for g in self.group_dep:
            for dep in self.group_dep[g]:
                if (dep not in self.group_dep and
                        dep not in self.third_party_locs):
                    self.external_libs.add(dep)

        for group_node in group_nodes:
            for package_name in self.group_mem[group_node.name]:
                package_node = group_node.make_node(package_name)
                self.package_dep[package_name] = \
                    self._get_meta(package_node, 'package', 'dep')
                self.package_mem[package_name] = \
                    self._get_meta(package_node, 'package', 'mem')
                self.package_opts[package_name] = \
                    self._get_raw_options(package_node, 'package', 'opts')
                self.package_cap[package_name] = \
                    self._get_raw_options(package_node, 'package', 'cap')

                # only header-only packages typically have 'pub' files
                try:
                    self.package_pub[package_name] = \
                        self._get_meta(package_node, 'package', 'pub')
                except:
                    pass

                dums_file = \
                    package_node.make_node('package').find_node(
                        package_node.name + '.dums')
                if dums_file:
                    self.package_dums.append(package_node.name)

        self._load_package_and_component_types()
        self._load_group_vers()
        self._load_soname_override()
        self._load_pc_extra_include_dirs()

        self.ctx.end_msg('ok')

    def _load_package_and_component_types(self):

        def load_package_types(package_name, component_names, package_node):
            if 0 == len(component_names):
                cpp_nodes = package_node.ant_glob('*.cpp')
                self.package_type[package_name] = ('cpp' if 0 < len(cpp_nodes)
                                                   else 'c')
                return

            cpp_count = 0
            c_count = 0
            for c in component_names:
                if package_node.find_node('%s.cpp' % c):
                    self.component_type[c] = 'cpp'
                    cpp_count += 1
                else:
                    # assume that only c or cpp components exist
                    self.component_type[c] = 'c'
                    c_count += 1

            self.package_type[package_name] = ('cpp' if
                                               c_count <= cpp_count else 'c')

        for g in self.group_mem:
            if g not in self.sa_package_locs:
                group_node = self.ctx.path.make_node(
                    self.group_locs[g]).make_node(g)
                for p in self.group_mem[g]:
                    package_node = group_node.make_node(p)
                    load_package_types(p, self.package_mem[p], package_node)
            else:
                package_node = self.ctx.path.make_node(
                    self.sa_package_locs[g]).make_node(g)
                load_package_types(g, self.group_mem[g], package_node)

    def _levelize_group_dependencies(self, group):
        from collections import defaultdict
        level_map = defaultdict(set)

        def _levelize_groups_impl(group):
            if group not in self.group_dep or not self.group_dep[group]:
                level_map[1].add(group)
                return 1

            level = 1 + max(_levelize_groups_impl(child) for
                            child in self.group_dep[group])
            level_map[level].add(group)
            return level

        map(lambda x: _levelize_groups_impl(x), self.group_dep[group])

        levels = []
        for level in sorted(level_map.keys()):
            levels.append(level_map[level])

        return levels

    def _evaluate_group_options(self, group):

        def patch_options_common(options):
            '''
            patch options to mimic hardcoded behaviors in bde_build common to
            packages and package groups
            '''

            # By default, Visual Studio uses a single pdb file for all object
            # files compiled from a particular directory named
            # vc<vs_version>.pdb.  We want to use a separate pdb file for each
            # package group and standard alone package.
            if (self.option_mask.uplid.uplid['os_type'] == 'windows' and
                    self.option_mask.uplid.uplid['comp_type'] == 'cl'):
                loc = self.group_locs[group] if group in self.group_locs else \
                    self.sa_package_locs[group]

                options['BDE_CXXFLAGS'] += " /Fd%s\\%s\\%s.pdb" % (
                    loc, group, group)
                options['BDE_CFLAGS'] += " /Fd%s\\%s\\%s.pdb" % (
                    loc, group, group)

        defs = copy.deepcopy(self.default_opts)

        # %s_LOCN is hard coded in bde_build
        group_node = self.ctx.path.make_node(
            [(self.group_locs[group] if group in
              self.group_locs else
              self.sa_package_locs[group]),
             group])
        defs.options['%s_LOCN' % group.upper()] = group_node.abspath()

        levels = self._levelize_group_dependencies(group)

        for level in levels:
            for group_dependency in sorted(level):
                if (group_dependency not in self.external_libs and
                        group_dependency not in self.third_party_locs):
                    defs.read(self.group_defs[group_dependency], self.ctx)
                    defs.read(self.group_cap[group_dependency], self.ctx)

        defs.read(self.group_defs[group], self.ctx)
        defs.read(self.group_cap[group], self.ctx)
        opts = copy.deepcopy(defs)
        opts.read(self.group_opts[group], self.ctx)

        defs.evaluate()

        if defs.options.get('CAPABILITY') == 'NEVER':
            self.unsupported_groups.add(group)
            if group not in self.sa_package_locs:
                self.unsupported_packages |= set(self.group_mem[group])
            return 'skipped (unsupported)'

        self.group_export_options[group] = defs.options

        unsupported_packages = set()
        if group not in self.sa_package_locs:
            for package in self.group_mem[group]:
                p_opts = copy.deepcopy(opts)

                package_node = group_node.make_node(package)

                p_opts.read(self.package_opts[package], self.ctx)

                # Ideally, we should also read the capability files of the
                # packages on which this depends, but since bde_build.pl
                # doesn't do this, we don't need to do it for now.
                p_opts.read(self.package_cap[package], self.ctx)

                # '%s_LOCN' and 'BDE_CXXINCLUDES' are hard coded in bde_build
                p_opts.options['%s_LOCN' %
                               package.upper().replace('+', '_')] = \
                    package_node.abspath()
                p_opts.options['BDE_CXXINCLUDES'] = '$(BDE_CXXINCLUDE)'
                patch_options_common(p_opts.options)

                p_opts.evaluate()

                if p_opts.options.get('CAPABILITY') == 'NEVER':
                    unsupported_packages.add(package)
                else:
                    self.package_options[package] = p_opts.options

        # BDE_CXXINCLUDES is hard coded in bde_build
        opts.options['BDE_CXXINCLUDES'] = '$(BDE_CXXINCLUDE)'

        opts.evaluate()
        self.group_options[group] = opts.options
        patch_options_common(opts.options)

        if unsupported_packages:
            self.unsupported_packages |= unsupported_packages
            return ('ok, with some skipped (%s)' %
                    ','.join(unsupported_packages))

        return 'ok'

    def _configure_external_libs(self, ufid):
        self.ufid = copy.deepcopy(ufid)

        pkgconfig_args = ['--libs', '--cflags']
        shared_flag = 'shr' in self.ufid.ufid

        if shared_flag:
            self.ufid.ufid.remove('shr')
            self.libtype_features = ['cxxshlib']
        else:
            pkgconfig_args.append('--static')
            self.libtype_features = ['cxxstlib']

        # If the static build is chosen (the default), waf assumes that all
        # libraries queried from pkg-config are to be built statically, which
        # is not true for some libraries. We work around this issue by manually
        # changing the affected libraries to be linked dynamically instead.
        dl_overrides = ['pthread', 'rt', 'nsl', 'socket']

        # If lib_suffix is set, we expect the pkgconfig files being depended on
        # to have the same suffix as well. Since the .dep files will not have
        # the suffix, we will remove the suffix from the names of the options
        # loaded into the waf environment.
        rename_keys = ['defines', 'includes', 'libpath', 'stlib', 'lib']
        for lib in self.external_libs:
            actual_lib = lib + str(self.lib_suffix or '')
            self.ctx.check_cfg(package=actual_lib,
                               args=pkgconfig_args,
                               errmsg="Make sure the path indicated by "
                                      "environment variable 'PKG_CONFIG_PATH' "
                                      "contains '%s.pc'" % actual_lib)
            if self.lib_suffix:
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

            # check_cfg always stores the libpath as dynamic library path
            # instead of static even if the configuration option is set to
            # static.
            if not shared_flag:
                slp_key = ('stlibpath_' + lib).upper()
                dlp_key = ('libpath_' + lib).upper()
                if dlp_key in self.ctx.env:
                    self.ctx.env[slp_key] = self.ctx.env[dlp_key]
                    del self.ctx.env[dlp_key]

        if self.lib_suffix:
            defines_old = self.ctx.env['DEFINES']
            defines_new = []
            for d in defines_old:
                index = d.find('%s=1' % self.lib_suffix.upper())
                if index >= 0:
                    defines_new.append('%s=1' % d[0:index])
                else:
                    defines_new.append(d)

            self.ctx.env['DEFINES'] = defines_new

    def _configure_options(self, uplid):

        self.uplid = uplid
        self.option_mask = OptionMask(self.uplid, self.ufid)

        # Get the path of default.opts. Assume the directory containing this
        # script is <repo_root>/bin/tools/waf/bde and default.opts is located
        # in the directory <repo_root>/etc.
        upd = os.path.dirname

        bde_root = os.environ.get('BDE_ROOT')
        repo_root = upd(upd(upd(upd(upd(os.path.realpath(__file__))))))
        default_opts_path = os.path.join(repo_root, 'etc', 'default.opts')

        default_opts_flag = os.path.isfile(default_opts_path)
        if not default_opts_flag and bde_root:
            default_opts_path = os.path.join(bde_root, 'etc', 'default.opts')
            default_opts_flag = os.path.isfile(default_opts_path)

        if not default_opts_flag:
            self.ctx.fatal("Can not find default.opts from the /etc directory "
                           "of the waf executable, nor the BDE_ROOT "
                           "environment variable.")

        raw_options = RawOptions()
        raw_options.read(default_opts_path)

        # At BB, default_internal.opts contains some variables that is required
        # for building bde-bb.
        if bde_root:
            default_internal_opts_path = os.path.join(bde_root, 'etc',
                                                      'default_internal.opts')
            raw_options.read(default_internal_opts_path)

        debug_opt_keys = self.ctx.options.debug_opt_keys
        if debug_opt_keys:
            debug_opt_keys = debug_opt_keys.split(',')

        self.default_opts = Options(self.option_mask)
        self.default_opts.read(raw_options.options, self.ctx,
                               debug_opt_keys=debug_opt_keys)

        for g in self.group_dep:
            self.ctx.start_msg("Evaluating options for '%s'" % g)
            if g in self.third_party_locs:
                self.ctx.recurse(g)
                self.ctx.end_msg("ok")
            else:
                status_msg = self._evaluate_group_options(g)
                self.ctx.end_msg(status_msg)

        tmp_opts = copy.deepcopy(self.default_opts)
        tmp_opts.evaluate()

        env_variables = ('SET_TMPDIR', 'XLC_LIBPATH')
        setenv_re = re.compile(r'^([^=]+)=(.*)$')
        for e in env_variables:
            if e in tmp_opts.options:
                m = setenv_re.match(tmp_opts.options[e])
                self.custom_envs[m.group(1)] = m.group(2)

    def _parse_ldflags(self, ldflags):
        """
        parse the linker flags into the following components:
        stlib, libs, libpaths, flags
        """

        stlibs = []
        libs = []
        libpaths = []
        flags = []

        shlib_marker = self.ctx.env['SHLIB_MARKER']
        stlib_marker = self.ctx.env['STLIB_MARKER']

        libs_exp = re.compile(
            self.ctx.env['LIB_ST'].replace('%s', r'([^ =]+)'))

        libpath_exp = re.compile(
            self.ctx.env['LIBPATH_ST'].replace('%s', r'([^ =]+)'))

        # default to shlibs
        isshlib_flag = True

        for flag in ldflags:
            if flag == shlib_marker:
                isshlib_flag = True
                continue

            if flag == stlib_marker:
                isshlib_flag = False
                continue

            m = libpath_exp.match(flag)
            if m:
                libpaths.append(m.group(1))
                continue

            m = libs_exp.match(flag)
            if m:
                lib = m.group(1)
                if isshlib_flag:
                    libs.append(lib)
                else:
                    stlibs.append(lib)
                continue

            flags.append(flag)

        return (stlibs, libs, libpaths, flags)

    def _parse_cflags(self, cflags):
        includes = []
        flags = []

        inc_exp = re.compile(
            self.ctx.env['CPPPATH_ST'].replace('%s', r'([^ =]+)'))

        for flag in cflags:
            m = inc_exp.match(flag)
            if m:
                includes.append(m.group(1))
                continue

            flags.append(flag)

        return (includes, flags)

    def _get_export_cxxflags(self, cxxflags):
        "only defines is required to be in export flags"
        export_flags = []
        for flag in cxxflags:
            st = flag[:2]
            if st == '-D' or (self.ctx.env.CXX_NAME == 'msvc' and st == '/D'):
                export_flags.append(flag)

        return export_flags

    def _save_group_options(self, group):
        export_options = self.group_export_options[group]
        options = self.group_options[group]

        # First value in the list is the compiler or linker, and so we ignore
        # it to just take the parameters.

        (stlibs, libs, libpaths, linkflags) = self._parse_ldflags(
            options['CXXLINK'].split()[1:] +
            options['COMPONENT_BDEBUILD_LDFLAGS'].split())

        self.ctx.env[group + '_export_libs'] = libs
        self.ctx.env[group + '_export_cxxflags'] = self._get_export_cxxflags(
            export_options['COMPONENT_BDEBUILD_CXXFLAGS'].split())

        self.ctx.env[group + '_libs'] = libs
        self.ctx.env[group + '_stlibs'] = stlibs
        self.ctx.env[group + '_libpaths'] = libpaths
        self.ctx.env[group + '_linkflags'] = linkflags

        if group in self.sa_package_locs:
            (cxxincludes, cxxflags) = self._parse_cflags(
                options['CXX'].split()[1:] +
                options['COMPONENT_BDEBUILD_CXXFLAGS'].split())
            (cincludes, cflags) = self._parse_cflags(
                options['CC'].split()[1:] +
                options['COMPONENT_BDEBUILD_CXXFLAGS'].split())

            self.ctx.env[group + '_cxxflags'] = cxxflags
            self.ctx.env[group + '_cxxincludes'] = cxxincludes
            self.ctx.env[group + '_cflags'] = cflags
            self.ctx.env[group + '_cincludes'] = cincludes

    def _save_package_options(self, package):
        options = self.package_options[package]

        (stlibs, libs, libpaths, linkflags) = self._parse_ldflags(
            options['CXXLINK'].split()[1:] +
            options['COMPONENT_BDEBUILD_LDFLAGS'].split())

        (cxxincludes, cxxflags) = self._parse_cflags(
            options['CXX'].split()[1:] +
            options['COMPONENT_BDEBUILD_CXXFLAGS'].split())
        (cincludes, cflags) = self._parse_cflags(
            options['CC'].split()[1:] +
            options['COMPONENT_BDEBUILD_CFLAGS'].split())

        self.ctx.env[package + '_cxxflags'] = cxxflags
        self.ctx.env[package + '_cxxincludes'] = cxxincludes
        self.ctx.env[package + '_cflags'] = cflags
        self.ctx.env[package + '_cincludes'] = cincludes
        self.ctx.env[package + '_libs'] = libs
        self.ctx.env[package + '_stlibs'] = stlibs
        self.ctx.env[package + '_libpaths'] = libpaths
        self.ctx.env[package + '_linkflags'] = linkflags

    def _save_third_party_options(self):
        # Store options from default.opts for use by the third party packages.

        self.default_opts.evaluate()
        tmp_opts = copy.deepcopy(self.default_opts)
        tmp_opts.evaluate()
        options = tmp_opts.options

        (cincludes, cflags) = self._parse_cflags(
            options['CC'].split()[1:] +
            options['COMPONENT_BDEBUILD_CXXFLAGS'].split())

        self.ctx.env['BDE_THIRD_PARTY_CFLAGS'] = cflags

    def _load_group_vers(self):
        # This is a big hack to get the version numbers for package groups and
        # sa-packages
        for group_name in self.export_groups:
            try:
                self.group_ver[group_name] = self._get_group_ver(group_name)
            except BaseException:
                Logs.warn("Could not identify the version number for %s." %
                          group_name)
                self.group_ver[group_name] = ("-1", "-1", "-1")

        for group_name in self.export_groups:
            if self.group_ver[group_name][0] == 'BDE_VERSION_MAJOR':
                if 'bde' in self.group_ver:
                    self.group_ver[group_name] = self.group_ver['bde']
                else:
                    self.group_ver[group_name] = self.group_ver['bsi']

    def _get_group_ver(self, group_name):
        if group_name in ('a_bdema',):
            version = ('BDE_VERSION_MAJOR', 'BDE_VERSION_MINOR',
                       'BDE_VERSION_PATCH')
        elif group_name in ('bap', 'zde', 'e_ipc'):
            version = self._get_group_ver2(group_name)

        elif (group_name.startswith('a_') and
              group_name not in ('a_xercesc', 'a_bteso')):
            version = self._get_group_ver3(group_name)
        else:
            version = self._get_group_ver1(group_name)

        if (version[0] is None or
           version[1] is None or
           version[2] is None):
            raise Exception
        return version

    def _get_group_ver1(self, group_name):
        if group_name not in self.sa_package_locs:
            group_node = self.ctx.path.make_node(
                [self.group_locs[group_name], group_name])

            versiontag_node = group_node.find_node(
                '%sscm/%sscm_versiontag.h' % (group_name, group_name))

            if group_name == 'bde':
                version_node = group_node.find_node(
                    '%sscm/%sscm_patchversion.h' % (group_name, group_name))
            else:
                version_node = group_node.find_node(
                    '%sscm/%sscm_version.cpp' % (group_name, group_name))
        else:
            package_node = self.ctx.path.make_node(
                [self.sa_package_locs[group_name], group_name])
            versiontag_node = package_node.find_node(
                '%s_versiontag.h' % group_name)
            version_node = package_node.find_node(
                '%s_version.cpp' % group_name)

        versiontag_source = versiontag_node.read()
        version_source = version_node.read()
        major_ver_re = re.compile(
            r'''^\s*#define\s+%s_VERSION_MAJOR\s+(\S+)\s*$''' %
            group_name.upper(), re.MULTILINE)

        minor_ver_re = \
            re.compile(r'''^\s*#define\s+%s_VERSION_MINOR\s+(\S+)\s*$''' %
                       group_name.upper(), re.MULTILINE)

        if group_name == 'bde':
            patch_ver_re = re.compile(
                r'''^\s*#define\s+%sSCM_PATCHVERSION_PATCH\s+(\S+)\s*$''' %
                group_name.upper(), re.MULTILINE)
        else:
            patch_ver_re = re.compile(
                r'''^\s*#define\s+%s_VERSION_PATCH\s+(\S+)\s*$''' %
                group_name.upper(), re.MULTILINE)

        (major_ver, minor_ver, patch_ver) = (None, None, None)

        m = major_ver_re.search(versiontag_source)
        if m:
            major_ver = m.group(1)

        m = minor_ver_re.search(versiontag_source)
        if m:
            minor_ver = m.group(1)

        m = patch_ver_re.search(version_source)
        if m:
            patch_ver = m.group(1)

        return (major_ver, minor_ver, patch_ver)

    def _get_group_ver2(self, group_name):

        if group_name not in self.sa_package_locs:
            group_node = self.ctx.path.make_node(
                [self.group_locs[group_name], group_name])

            version_node = group_node.find_node(
                '%sscm/%sscm_version.cpp' % (group_name, group_name))

            if not version_node:
                version_node = group_node.find_node(
                    '%sscm/%sscm_version.c' % (group_name, group_name))
        else:
            package_node = self.ctx.path.make_node(
                [self.sa_package_locs[group_name], group_name])

            version_node = package_node.find_node(
                '%s_version.cpp' % group_name)

        source = version_node.read()

        if group_name.startswith('e_'):
            type_name = 'ENT'
            lib_name = group_name[2:].upper()
        else:
            type_name = 'LIB'
            lib_name = group_name.upper()

        exp = (
            r'''BLP_%s_BDE_%s_(?P<major>\d+)\.(?P<minor>\d+).(?P<patch>\d+)'''
            % (type_name, lib_name)
        )
        version_re = re.compile(exp)

        (major_ver, minor_ver, patch_ver) = (None, None, None)

        m = version_re.search(source)
        if m:
            major_ver = m.group('major')
            minor_ver = m.group('minor')
            patch_ver = m.group('patch')

        return (major_ver, minor_ver, patch_ver)

    def _get_group_ver3(self, group_name):
        package_node = self.ctx.path.make_node(
            [self.sa_package_locs[group_name], group_name])

        version_node = package_node.find_node('%s_version.cpp' % group_name)

        source = version_node.read()
        exp = r'''(?P<major>\d+)\.(?P<minor>\d+).(?P<patch>\d+)'''
        version_re = re.compile(exp, re.MULTILINE)

        (major_ver, minor_ver, patch_ver) = (None, None, None)

        m = version_re.search(source)
        if m:
            major_ver = m.group('major')
            minor_ver = m.group('minor')
            patch_ver = m.group('patch')

        return (major_ver, minor_ver, patch_ver)

    def _load_soname_override(self):
        for group_name in self.export_groups:
            soname = os.environ.get('BDE_%s_SONAME' % group_name.upper())
            if soname:
                self.soname_override[group_name] = soname

    def _load_pc_extra_include_dirs(self):
        include_dirs = os.environ.get('PC_EXTRA_INCLUDE_DIRS')
        if include_dirs:
            self.pc_extra_include_dirs = include_dirs.split(':')

    def _save(self):
        self.ctx.start_msg('Saving configuration')
        self.ctx.env['ufid'] = self.option_mask.ufid.ufid

        # For visual studio, waf explicitly includes the system header files by
        # setting the 'INCLUDES' variable. BSL_OVERRIDE_STD mode requires that
        # the system header files, which contains the standard library, be
        # overridden with custom versions in bsl, so we workaround the issue by
        # moving the system includes to 'INCLUDE_BSL' if it exists. This
        # solution is not perfect, because it doesn't support package groups
        # that doesn't depend on bsl -- this is not a problem for BDE
        # libraries.

        if (self.option_mask.uplid.uplid['os_type'] == 'windows' and
           'INCLUDES_BSL' in self.ctx.env):

            # Assume that 'INCLUDES' containly system header only.

            self.ctx.env['INCLUDES_BSL'].extend(self.ctx.env['INCLUDES'])
            del self.ctx.env['INCLUDES']

        if self.option_mask.uplid.uplid['comp_type'] == 'xlc':

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
            if '64' in self.option_mask.ufid.ufid:
                self.ctx.env['ARFLAGS'] = ['-rcs', '-X64']

        if (self.option_mask.uplid.uplid['os_name'] == 'sunos' and
           self.option_mask.uplid.uplid['comp_type'] == 'cc'):

            # Work around bug in waf's sun CC plugin to allow for properly
            # adding SONAMES. TODO: submit patch
            self.ctx.env['SONAME_ST'] = '-h %s'
            self.ctx.env['DEST_BINFMT'] = 'elf'

            # Sun C++ linker  doesn't link in the Std library by default
            if 'cxxshlib' in self.libtype_features:
                if 'LINKFLAGS' not in self.ctx.env:
                    self.ctx.env['LINKFLAGS'] = []
                self.ctx.env['LINKFLAGS'].extend(['-zdefs', '-lCstd', '-lCrun',
                                                  '-lc', '-lm', '-lsunmath',
                                                  '-lpthread'])

        # Remove unsupported package groups and packages.  We don't need to do
        # dependency analysis because the unsupported sets already contain all
        # transitively unsupported nodes.

        for g in self.unsupported_groups:
            if g in self.export_groups:
                self.export_groups.remove(g)
            self.group_dep.pop(g, None)
            self.group_mem.pop(g, None)
            self.group_doc.pop(g, None)
            self.sa_package_locs.pop(g, None)
            self.group_locs.pop(g, None)

        for p in self.unsupported_packages:
            self.package_dep.pop(p, None)
            self.package_mem.pop(p, None)
            self.package_pub.pop(p, None)

        for g in self.group_mem:
            self.group_mem[g] = list(set(self.group_mem[g]) -
                                     self.unsupported_packages)

        self.ctx.env['external_libs'] = self.external_libs
        self.ctx.env['export_groups'] = self.export_groups
        self.ctx.env['group_dep'] = self.group_dep
        self.ctx.env['group_mem'] = self.group_mem
        self.ctx.env['group_doc'] = self.group_doc
        self.ctx.env['group_ver'] = self.group_ver

        self.ctx.env['sa_package_locs'] = self.sa_package_locs
        self.ctx.env['third_party_locs'] = self.third_party_locs
        self.ctx.env['soname_override'] = self.soname_override

        self.ctx.env['group_locs'] = self.group_locs

        self.ctx.env['package_dep'] = self.package_dep
        self.ctx.env['package_mem'] = self.package_mem
        self.ctx.env['package_pub'] = self.package_pub
        self.ctx.env['package_dums'] = self.package_dums
        self.ctx.env['libtype_features'] = self.libtype_features
        self.ctx.env['prefix'] = self.ctx.options.prefix
        self.ctx.env['custom_envs'] = self.custom_envs

        self.ctx.env['package_type'] = self.package_type
        self.ctx.env['component_type'] = self.component_type

        self.ctx.env['lib_suffix'] = self.lib_suffix
        self.ctx.env['install_flat_include'] = \
            self.ctx.options.install_flat_include
        self.ctx.env['install_lib_dir'] = self.ctx.options.install_lib_dir
        self.ctx.env['pc_extra_include_dirs'] = self.pc_extra_include_dirs

        for g in self.group_dep:
            if g not in self.third_party_locs:
                self._save_group_options(g)

        for p in self.package_dep:
            self._save_package_options(p)

        self._save_third_party_options()

        self.ctx.end_msg('ok')


# ----------------------------------------------------------------------------
# Copyright (C) 2013-2014 Bloomberg Finance L.P.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
# ----------------------------- END-OF-FILE ----------------------------------
