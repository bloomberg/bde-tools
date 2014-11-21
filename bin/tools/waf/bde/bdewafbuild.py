import os
import os.path
import sys
import tempfile

import bdeunittest
from waflib.TaskGen import feature, after_method, before_method
from waflib import Errors, Utils, Options, Task, Logs
from waflib.Build import BuildContext


class BdeWafBuild(object):

    def __init__(self, ctx):
        self.ctx = ctx
        self.libtype_features = []

        self.ufid = self.ctx.env['ufid']
        self.external_libs = self.ctx.env['external_libs']
        self.group_dep = self.ctx.env['group_dep']
        self.group_mem = self.ctx.env['group_mem']
        self.group_doc = self.ctx.env['group_doc']
        self.group_ver = self.ctx.env['group_ver']

        self.export_groups = self.ctx.env['export_groups']

        self.sa_package_locs = self.ctx.env['sa_package_locs']
        self.third_party_locs = self.ctx.env['third_party_locs']
        self.soname_override = self.ctx.env['soname_override']
        self.group_locs = self.ctx.env['group_locs']

        self.package_dep = self.ctx.env['package_dep']
        self.package_mem = self.ctx.env['package_mem']
        self.package_pub = self.ctx.env['package_pub']
        self.package_dums = self.ctx.env['package_dums']

        self.package_type = self.ctx.env['package_type']
        self.component_type = self.ctx.env['component_type']

        self.libtype_features = self.ctx.env['libtype_features']
        self.custom_envs = self.ctx.env['custom_envs']

        self.run_tests = self.ctx.options.test == 'run'
        self.build_tests = self.run_tests or self.ctx.options.test == 'build'

        self.lib_suffix = self.ctx.env['lib_suffix']
        self.install_flat_include = self.ctx.env['install_flat_include']
        self.install_lib_dir = self.ctx.env['install_lib_dir']
        self.pc_extra_include_dirs = self.ctx.env['pc_extra_include_dirs']

        # Get the path of run_unit_tests.py. Assume the directory containing
        # this script is <repo_root>/bin/tools/waf/bde and run_unit_tests.py is
        # located in the directory <repo_root>/bin/tools.

        upd = os.path.dirname
        test_runner_path = os.path.join(
            upd(upd(upd(os.path.realpath(__file__)))),
            'run_unit_tests.py')

        self.ctx.options.testcmd = \
            '%s %s %%s --verbosity %s --timeout %s' % (
                sys.executable,
                test_runner_path,
                self.ctx.options.test_verbosity,
                self.ctx.options.test_timeout)

    def _build_package_impl(self, package_name, package_node, group_node,
                            components, internal_deps, external_deps,
                            install_path):

        cflags = self.ctx.env[package_name + '_cflags']
        cxxflags = self.ctx.env[package_name + '_cxxflags']
        cincludes = self.ctx.env[package_name + '_cincludes']
        cxxincludes = self.ctx.env[package_name + '_cxxincludes']
        libs = self.ctx.env[package_name + '_libs']
        stlibs = self.ctx.env[package_name + '_stlibs']
        libpaths = self.ctx.env[package_name + '_libpaths']
        linkflags = self.ctx.env[package_name + '_linkflags']

        if package_name in self.package_pub:
            # Some files necessary for compilation are missing from the pub
            # files For example, bsl+stdhdrs/sys/time.h As a work-around,
            # simply export all files listed in the pub files and any missing
            # 'h' or 'SUNWCCh' files

            install_headers = package_node.ant_glob('**/*.h')
            install_headers.extend(package_node.ant_glob('**/*.SUNWCCh'))

            pub_header_names = self.package_pub[package_name]
            pub_headers = [package_node.make_node(h) for h in pub_header_names]

            install_header_paths = [h.abspath() for h in install_headers]

            for ph in pub_headers:
                if not ph.abspath() in install_header_paths:
                    install_headers.append(ph)
        else:
            header_names = [c + '.h' for c in components]
            install_headers = [package_node.make_node(h) for h in header_names]

        path_headers = {}
        for h in install_headers:
            path = os.path.dirname(h.path_from(package_node))
            if path not in path_headers:
                path_headers[path] = []

            path_headers[path].append(h)

        for path in path_headers:
            if self.install_flat_include:
                self.ctx.install_files(os.path.join('${PREFIX}',
                                                    'include', path),
                                       path_headers[path])
            else:
                self.ctx.install_files(os.path.join('${PREFIX}',
                                                    'include',
                                                    group_node.name, path),
                                       path_headers[path])

        dum_task_gens = []
        if package_name in self.package_dums:

            self.ctx(name=package_name + '.dums',
                     path=package_node,
                     rule='cp ${SRC} ${TGT}',
                     source=package_node.make_node(['package',
                                                   package_name + '.dums']),
                     target=package_name + '_dums.c'
                     )

            self.ctx(name=package_name + '_dums',
                     path=package_node,
                     source=[package_name + '_dums.c'],
                     features=['c'],
                     cflags=cflags,
                     cincludes=cincludes,
                     depends_on=package_name + '.dums',
                     )
            dum_task_gens.append(package_name + '_dums')

        package_type = self.package_type[package_name]
        other_type = 'c' if package_type == 'cpp' else 'cpp'
        package_type_props = {
            'cpp': {
                'src_ext': '.cpp',
                'features': ['cxx']
            },
            'c': {
                'src_ext': '.c',
                'features': ['c']
            }
        }
        ptp = package_type_props
        lib_src_ext = ptp[package_type]['src_ext']

        if components:
            lib_components = [c for c in components if
                              self.component_type[c] == package_type]
            other_components = [c for c in components if
                                self.component_type[c] == other_type]
            lib_src_files = [c + lib_src_ext for c in lib_components]

        else:
            # packages whose name contains a '+' are special in that their
            # 'mem' files are empty and they do not contain typical bde-style
            # components.  These packages contain either only headers, or
            # contain 'cpp' files that do not have corresponding '.h' nad
            # '.t.cpp' files.

            # These header-only packages should always have a dummy.cpp file.
            lib_components = []
            other_components = []
            lib_src_files = [x.name for x in
                             package_node.ant_glob('*' + lib_src_ext)]

        if not lib_src_files:
            self.ctx.fatal('package %s does not contain any components'
                           % package_name)

        self.ctx(name=package_name + '_lib',
                 target = package_name,
                 path   = package_node,
                 source = lib_src_files,

                 features = ptp[package_type]['features'] + self.libtype_features,

                 cflags          = cflags,
                 cincludes       = cincludes,
                 cxxflags        = cxxflags,
                 cxxincludes     = cxxincludes,
                 linkflags       = linkflags,
                 includes        = [package_node],
                 export_includes = [package_node],
                 use             = internal_deps,
                 uselib          = external_deps,
                 lib             = libs,
                 stlib           = stlibs,
                 cust_libpaths   = libpaths,
                 install_path    = install_path,
                 )

        if self.build_tests:
            test_features = ['cxxprogram']
            if self.run_tests:
                test_features = test_features + ['test']

            for c in lib_components:
                self.ctx(
                    name          = c + '.t',
                    path          = package_node,
                    source        = c + '.t' + lib_src_ext,
                    target        = c + '.t',
                    features      = ptp[package_type]['features'] + test_features,
                    cflags        = cflags,
                    cincludes     = cincludes,
                    cxxflags      = cxxflags,
                    cxxincludes   = cxxincludes,
                    linkflags     = linkflags,
                    lib           = libs,
                    stlib         = stlibs,
                    cust_libpaths = libpaths,
                    includes      = [package_node],
                    use           = [package_name + '_lib'] + dum_task_gens,
                    uselib        = external_deps
                    )

            for c in other_components:
                self.ctx(
                    name          = c + '.t',
                    path          = package_node,
                    source        = c + '.t' + ptp[other_type]['src_ext'],
                    target        = c + '.t',
                    features      = ptp[other_type]['features'] + test_features,
                    cflags        = cflags,
                    cincludes     = cincludes,
                    cxxflags      = cxxflags,
                    cxxincludes   = cxxincludes,
                    linkflags     = linkflags,
                    lib           = libs,
                    stlib         = stlibs,
                    cust_libpaths = libpaths,
                    includes      = [package_node],
                    use           = [package_name + '_lib'] + dum_task_gens,
                    uselib        = external_deps
                    )

        else:
            # Create the same number of task generators to ensure that the
            # generators created with or without tests have the same idx
            for c in components:
                self.ctx(
                    name = c + '.t',
                    path = package_node
                )

        self.ctx(name       = package_name + '_tst',
                 depends_on = [c + '.t' for c in components]
                 )

        self.ctx(name       = package_name,
                 depends_on = [package_name + '_lib', package_name + '_tst']
                 )

    def _build_third_party(self, package_name):
        self.ctx.recurse(package_name)

    def _build_sa_package(self, package_name):

        # Standard alone packages are architecturally at the same level as
        # package groups, but have the same physical structure as regular
        # packages.  I.e., they can depend directly on other package groups and
        # consititute a UOR (a library) that is on the same hierarchical level
        # as a package group.  Therefore, the metadata for standard alone
        # packages are stored together with package groups.

        package_node = self.ctx.path.make_node(
            self.sa_package_locs[package_name]).make_node(package_name)
        deps = set(self.group_dep[package_name])
        internal_deps = deps - self.external_libs
        internal_deps = [g + '_lib' for g in internal_deps]
        external_deps = deps & self.external_libs
        # waf uses all uppercase words to identify pkgconfig based dependencies
        external_deps = [l.upper() for l in external_deps]

        components = self.group_mem[package_name]

        if package_name in self.export_groups:
            install_path = os.path.join('${PREFIX}', self.install_lib_dir)
            self._make_pc_group(package_name, internal_deps, external_deps)
        else:
            install_path = None

        self._build_package_impl(package_name, package_node, package_node,
                                 components, internal_deps, external_deps,
                                 install_path)

    def _build_normal_package(self, package_name, group_node,
                              group_internal_deps, group_external_deps):
        package_node = group_node.make_node(package_name)
        deps = [p + '_lib' for p in self.package_dep[package_name]]
        deps.extend([g + '_lib' for g in group_internal_deps])
        components = self.package_mem[package_name]

        self._build_package_impl(package_name, package_node, group_node,
                                 components, deps, group_external_deps, None)

    def _build_group(self, group_name):
        group_node = self.ctx.path.make_node(
            self.group_locs[group_name]).make_node(group_name)
        deps = set(self.group_dep[group_name])
        internal_deps = deps - self.external_libs
        external_deps = deps & self.external_libs

        # waf uses all uppercase words to identify pkgconfig based dependencies
        external_deps = [l.upper() for l in external_deps]
        packages = self.group_mem[group_name]

        linkflags = self.ctx.env[group_name + '_linkflags']
        libs = self.ctx.env[group_name + '_libs']
        stlibs = self.ctx.env[group_name + '_stlibs']
        libpaths = self.ctx.env[group_name + '_libpaths']

        for p in packages:
            self._build_normal_package(p, group_node, internal_deps,
                                       external_deps)

        if group_name in self.export_groups:
            install_path = os.path.join('${PREFIX}', self.install_lib_dir)
            self._make_pc_group(group_name, internal_deps, external_deps)
        else:
            install_path = None

        self.ctx(name            = group_name + '_lib',
                 path            = group_node,
                 target          = group_name + self.lib_suffix,
                 features        = ['cxx'] + self.libtype_features,
                 linkflags       = linkflags,
                 lib             = libs,
                 stlib           = stlibs,
                 cust_libpaths   = libpaths,
                 source          = [p + '_lib' for p in packages],
                 use             = [g + '_lib' for g in internal_deps],
                 uselib          = external_deps,
                 install_path    = install_path,
                 export_includes = packages,
                 bdevnum         = '.'.join(self.group_ver[group_name]) if group_name in self.group_ver else None,
                 bdesoname       = self.soname_override[group_name] if group_name in self.soname_override else None
                 )

        depends_on = [group_name + '_lib'] + [p + '_tst' for p in packages]
        if group_name in self.export_groups:
            depends_on.append(group_name + '.pc')

        self.ctx(name       = group_name,
                 depends_on = depends_on)

    def _make_pc_group(self, group_name, internal_deps, external_deps):

        vc_node = self.ctx.path.make_node('vc')

        if self.install_flat_include:
            install_include_dir = "include"
        else:
            install_include_dir = "include/%s" % group_name

        self.ctx(name                  = group_name + '.pc',
                 features              = ['bdepc'],
                 path                  = vc_node,
                 version               = '.'.join(self.group_ver[group_name]),
                 target                = group_name + self.lib_suffix + '.pc',
                 doc                   = self.group_doc[group_name],
                 dep                   = self.group_dep[group_name],
                 group_name            = group_name,
                 lib_suffix            = self.lib_suffix,
                 install_lib_dir       = self.install_lib_dir,
                 install_include_dir   = install_include_dir,
                 pc_extra_include_dirs = self.pc_extra_include_dirs
                 )

        self.ctx.install_files(os.path.join('${PREFIX}', self.install_lib_dir,
                                            'pkgconfig'),
                               [os.path.join(vc_node.relpath(),
                                             group_name +
                                             self.lib_suffix + '.pc')])

    def build(self):
        for class_name in ('cxx', 'cxxprogram', 'cxxshlib', 'cxxstlib',
                           'c', 'cprogram', 'cshlib', 'cstlib'):
            activate_custom_exec_command(class_name)

        self.ctx.env['env'] = os.environ.copy()
        self.ctx.env['env'].update(self.custom_envs)

        for g in self.group_dep:
            if g in self.sa_package_locs:
                self._build_sa_package(g)
            elif g in self.third_party_locs:
                self._build_third_party(g)
            else:
                self._build_group(g)

        if self.run_tests:
            self.ctx.add_post_fun(bdeunittest.summary)


@feature('c')
@after_method('propagate_uselib_vars')
@before_method('apply_incpaths')
def append_custom_cincludes(self):
    if hasattr(self, 'cincludes'):
        self.env.INCLUDES.extend(self.cincludes)

    if hasattr(self, 'cust_libpaths'):
        self.env.STLIBPATH.extend(self.cust_libpaths)


@feature('cxx')
@after_method('propagate_uselib_vars')
@before_method('apply_incpaths')
def append_custom_cxxincludes(self):
    if hasattr(self, 'cxxincludes'):
        self.env.INCLUDES.extend(self.cxxincludes)

    if hasattr(self, 'cust_libpaths'):
        self.env.STLIBPATH.extend(self.cust_libpaths)


@feature('*')
@before_method('process_rule')
def post_the_other(self):
    """
    Support manual dependency specification with the 'depends_on' attribute
    """
    deps = getattr(self, 'depends_on', [])
    for name in self.to_list(deps):
        other = self.bld.get_tgen_by_name(name)
        other.post()


@feature('cshlib', 'cxxshlib', 'dshlib', 'fcshlib', 'bdevnum')
@after_method('apply_link', 'propagate_uselib_vars')
def apply_bdevnum(self):
    if (not getattr(self, 'bdevnum', '') or
       os.name != 'posix' or
       self.env.DEST_BINFMT not in ('elf', 'mac-o')):
        return

    link = self.link_task
    nums = self.bdevnum.split('.')
    node = link.outputs[0]

    libname = node.name
    if libname.endswith('.dylib'):
        name3 = libname.replace('.dylib', '.%s.dylib' % self.bdevnum)
        name2 = libname.replace('.dylib',
                                '.%s.dylib' % (nums[0] + '.' + nums[1]))
    else:
        name3 = libname + '.' + self.bdevnum
        name2 = libname + '.' + nums[0] + '.' + nums[1]

    # add the so name for the ld linker - to disable, just unset env.SONAME_ST
    if self.env.SONAME_ST:
        if getattr(self, 'bdesoname', None):
            v = self.env.SONAME_ST % self.bdesoname
        else:
            v = self.env.SONAME_ST % name2
        self.env.append_value('LINKFLAGS', v.split())

    # the following task is just to enable execution from the build dir :-/

    if self.env.DEST_OS != 'openbsd':
        self.create_task('vnum', node, [node.parent.find_or_declare(name2),
                                        node.parent.find_or_declare(name3)])

    if getattr(self, 'install_task', None):
        self.install_task.hasrun = Task.SKIP_ME
        bld = self.bld
        path = self.install_task.dest
        if self.env.DEST_OS == 'openbsd':
            libname = self.link_task.outputs[0].name
            t1 = bld.install_as('%s%s%s' % (path, os.sep, libname), node,
                                env=self.env, chmod=self.link_task.chmod)
            self.vnum_install_task = (t1,)
        else:
            t1 = bld.install_as(path + os.sep + name3, node, env=self.env,
                                chmod=self.link_task.chmod)
            t2 = bld.symlink_as(path + os.sep + name2, name3)
            t3 = bld.symlink_as(path + os.sep + libname, name3)
            self.vnum_install_task = (t1, t2, t3)

    if '-dynamiclib' in self.env['LINKFLAGS']:
        # this requires after(propagate_uselib_vars)
        try:
            inst_to = self.install_path
        except AttributeError:
            inst_to = self.link_task.__class__.inst_to
        if inst_to:
            p = Utils.subst_vars(inst_to, self.env)
            path = os.path.join(p, self.link_task.outputs[0].name)
            self.env.append_value('LINKFLAGS', ['-install_name', path])


@feature('cstlib', 'cshlib', 'cxxstlib', 'cxxshlib', 'fcstlib', 'fcshlib')
@before_method('process_source')
def reuse_lib_objects(self):
    """
    Find sources that are libs; if any are found, extract their object lists
    and build this lib from the same objects. If this occurs, skip the normal
    process_source step.
    """
    tmp_source = []
    saw_target = False
    task_sources = []

    for source in self.to_list(self.source):
        try:
            y = self.bld.get_tgen_by_name(source)
            saw_target = True
            task_sources.append(y)
        except Errors.WafError:
            tmp_source.append(source)
            continue

    if saw_target and tmp_source:
        raise Errors.WafError('Cannot mix tasks and source files in shlib %s' %
                              self.name)

    if saw_target:
        self.compiled_tasks = []
        for tg in task_sources:
            tg.post()
            for tsk in getattr(tg, 'compiled_tasks', []):
                self.compiled_tasks.append(tsk)

    self.source = tmp_source


# Patch ccroot.propagate_uselib_vars so that libraries can be repeated.
# This is required to support cyclic dependencies and bde-bb.
def propagate_uselib_vars(self):
    """
    Process uselib variables for adding flags. For example, the following
    target::

        def build(bld):
            bld.env.AFLAGS_aaa = ['bar']
            from waflib.Tools.ccroot import USELIB_VARS
            USELIB_VARS['aaa'] = set('AFLAGS')

            tg = bld(features='aaa', aflags='test')

    The *aflags* attribute will be processed and this method will set::

            tg.env.AFLAGS = ['bar', 'test']
    """

    _vars = self.get_uselib_vars()
    env = self.env

    for x in _vars:
        y = x.lower()
        env.append_value(x, self.to_list(getattr(self, y, [])))

    for x in self.features:
        for var in _vars:
            compvar = '%s_%s' % (var, x)
            env.append_value(var, env[compvar])

    for x in self.to_list(getattr(self, 'uselib', [])):
        for v in _vars:
            env.append_value(v, env[v + '_' + x])

from waflib.TaskGen import task_gen
from waflib.Tools import ccroot
setattr(task_gen, ccroot.propagate_uselib_vars.__name__, propagate_uselib_vars)

def activate_custom_exec_command(class_name):
    '''
    Monkey patch 'exec_command' method for the specified 'class_name' to
    support decorations around compiler/linker errors and warnings.
    '''
    cls = Task.classes.get(class_name, None)

    if not cls:
        return None

    derived_class = type(class_name, (cls,), {})

    def exec_command(self, *k, **kw):
        if self.env['CC_NAME'] == 'msvc':
            return super(derived_class, self).exec_command(*k, **kw)
        else:
            return self.bde_exec_command(*k, **kw)

    derived_class.exec_command = exec_command
    derived_class.bde_exec_command = bde_exec_command
    derived_class.exec_response_command = bde_msvc_exec_response_command


def bde_msvc_exec_response_command(task, cmd, **kw):
    try:
        tmp = None
        if (sys.platform.startswith('win') and isinstance(cmd, list) and
            len(' '.join(cmd)) >= 8192):
            #unquoted program name, otherwise exec_command will fail
            program = cmd[0]
            cmd = [task.quote_response_command(x) for x in cmd]
            (fd, tmp) = tempfile.mkstemp()
            os.write(fd, '\r\n'.join(i.replace('\\', '\\\\') for i
                                     in cmd[1:]).encode())
            os.close(fd)
            cmd = [program, '@' + tmp]
        # no return here, that's on purpose
        ret = bde_exec_command(task, cmd, **kw)
    finally:
        if tmp:
            try:
                os.remove(tmp)
            except OSError:
                 # anti-virus and indexers can keep the files open -_-
                pass
    return ret

def bde_exec_command(task, cmd, **kw):

    def get_quoted_shell_command(cmd):
        quoted_cmd = ['"%s"' % arg if ' ' in arg else arg for
                      arg in cmd]

        return ' '.join(quoted_cmd)

    bld = task.generator.bld
    kw['shell'] = isinstance(cmd, str)
    kw['cwd'] = bld.variant_dir
    Logs.debug('runner: %r' % get_quoted_shell_command(cmd))
    Logs.debug('runner_real: %r' % cmd)
    Logs.debug('runner_env: kw=%s' % kw)

    if bld.logger:
        bld.logger.info(cmd)

    if 'stdout' not in kw:
        kw['stdout'] = Utils.subprocess.PIPE
    if 'stderr' not in kw:
        kw['stderr'] = Utils.subprocess.PIPE

    try:
        p = Utils.subprocess.Popen(cmd, **kw)
        (out, err) = p.communicate()
        ret = p.returncode
    except Exception as e:
        raise Errors.WafError('Execution failure: %s' % str(e), ex=e)

    if out or err:
        msg = '' + out + err

        # The Visual Studio compiler always prints name of the input source
        # file. We try to ignore those outputs using a heuristic.
        if ret == 0 and msg.strip() == task.inputs[0].name:
            return ret

        if len(task.inputs) > 1:
            src_str = task.outputs[0].name
        else:
            src_str = task.inputs[0].name

        status_str = 'WARNING' if ret == 0 else 'ERROR'
        sys.stdout.write('[%s (%s)] <<<<<<<<<<\n%s>>>>>>>>>>\n' %
                         (src_str, status_str, msg))

    return ret

class ListContext(BuildContext):
    """
    lists the targets to execute
    Override the ListContext from waflib.Build to hide internal build targets
    """
    cmd = 'list'

    def execute(self):
        """
        See :py:func:`waflib.Context.Context.execute`.
        """
        self.restore()
        if not self.all_envs:
            self.load_envs()

        self.recurse([self.run_dir])
        self.pre_build()

        # display the time elapsed in the progress bar
        self.timer = Utils.Timer()

        for g in self.groups:
            for tg in g:
                try:
                    f = tg.post
                except AttributeError:
                    pass
                else:
                    f()

        try:
            # force the cache initialization
            self.get_tgen_by_name('')
        except Exception:
            pass
        lst = list(self.task_gen_cache_names.keys())
        lst.sort()

        hidden_suffixes = ['_lib', '_src', '_tst']
        for k in lst:
            if len(k) > 4 and (k[-4:] in hidden_suffixes):
                continue

            Logs.pprint('GREEN', k)


@feature('bdepc')
@before_method('process_rule')
def make_pc(self):
    """Create a task to generate the pkg-config file."""
    self.create_task('bdepc', None, self.path.find_or_declare(self.target))


class bdepc(Task.Task):

    # replacement parameters: prefix, lib_dir, include_dir, description,
    # version, requires.private, name, libs, cflags
    PKGCONFIG_TEMPLATE = '''prefix=%s
libdir=${prefix}/%s
includedir=${prefix}/%s

Name: %s
Description: %s
URL: https://github.com/bloomberg/bde
Version: %s
Requires:
Requires.private: %s
Libs: -L${libdir} -l%s %s
Libs.private:
Cflags: -I${includedir} %s %s
'''

    def signature(self):
        # Make sure that the signatures include the appropriate dependencies,
        # so that the .pc file will be regenerated when needed
        self.hcode = Options.options.prefix + self.generator.lib_suffix + \
            self.generator.install_lib_dir + self.generator.install_include_dir + \
            ','.join(self.generator.pc_extra_include_dirs)
        ret = super(bdepc, self).signature()
        return ret

    def run(self):
        bld = self.generator.bld
        group_name = self.generator.group_name
        version = self.generator.version
        lib_suffix = self.generator.lib_suffix
        install_lib_dir = self.generator.install_lib_dir
        install_include_dir = self.generator.install_include_dir
        extra_include_dirs_str = \
            ' '.join(['-I%s' % d for d in
                      self.generator.pc_extra_include_dirs])

        libs = [bld.env['LIB_ST'] % l for l in
                bld.env[group_name + '_export_libs']]

        pc_source = self.PKGCONFIG_TEMPLATE % (
            Options.options.prefix,
            install_lib_dir,
            install_include_dir,
            self.generator.doc[0],
            self.generator.doc[1],
            version,
            ' '.join([dep + lib_suffix for dep in self.generator.dep]),
            group_name + lib_suffix,
            ' '.join(libs),
            extra_include_dirs_str,
            ' '.join(bld.env[group_name + '_export_cxxflags'])
        )
        self.outputs[0].write(pc_source)


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
