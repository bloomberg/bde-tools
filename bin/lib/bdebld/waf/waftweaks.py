"""Customization to waf's core.

This module contains custom task generator methods and replacement
implementations of existing methods in waf.
"""

import os
import sys
import tempfile

from waflib import Build
from waflib import Configure
from waflib import Errors
from waflib import Logs
from waflib import Options
from waflib import Task
from waflib import TaskGen
from waflib import Utils


class PreConfigure(Configure.ConfigurationContext):
    cmd = 'configure'

    def __init__(self, **kw):
        build_dir = os.getenv('BDE_WAF_BUILD_DIR')
        print build_dir
        if build_dir:
            Options.options.out = build_dir
            self.fout_dir = build_dir
            Logs.debug('config: build dir: ' + build_dir)

        super(PreConfigure, self).__init__(**kw)


@TaskGen.feature('c')
@TaskGen.after_method('propagate_uselib_vars')
@TaskGen.before_method('apply_incpaths')
def append_custom_cincludes(self):
    if hasattr(self, 'cincludes'):
        self.env.INCLUDES.extend(self.cincludes)

    if hasattr(self, 'cust_libpaths'):
        self.env.STLIBPATH.extend(self.cust_libpaths)


@TaskGen.feature('cxx')
@TaskGen.after_method('propagate_uselib_vars')
@TaskGen.before_method('apply_incpaths')
def append_custom_cxxincludes(self):
    if hasattr(self, 'cxxincludes'):
        self.env.INCLUDES.extend(self.cxxincludes)

    if hasattr(self, 'cust_libpaths'):
        self.env.STLIBPATH.extend(self.cust_libpaths)


def activate_custom_exec_command(class_name):
    """Patch exec_command method of a task to support BDE customizations.

    Args:
       class_name (str): Name of the Task class.
    """
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
    """This is a copy of waflib.Tools.msvc.exec_response_command.
    """
    try:
        tmp = None
        if (sys.platform.startswith('win') and isinstance(cmd, list) and
                len(' '.join(cmd)) >= 8192):
            # unquoted program name, otherwise exec_command will fail
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
    """Replacement for 'Context.exec_command' containing BDE customizations.

    The following customizations have been made:

    - Running the 'waf build' command in verbose mode will now print a
      executable command line instead of a python list. This simplifies the
      debugging process.

    - Error or warning will be decorated with the name of the source file(s)
      from which the problems originate.

    For information on the input parameters, see the documentation for
    waflib.Context.exec_command.
    """

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
        out = out.decode(sys.stdout.encoding or 'iso8859-1')
        err = err.decode(sys.stdout.encoding or 'iso8859-1')
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
        color = Logs.colors.YELLOW if ret == 0 else Logs.colors.RED

        Logs.info('[%s (%s)] <<<<<<<<<<\n%s>>>>>>>>>>' %
                  (src_str, status_str, msg),
                  extra={'stream': sys.stderr, 'c1': color})

    return ret


@TaskGen.feature('*')
@TaskGen.before_method('process_rule')
def post_the_other(self):
    """Allow manual dependency specification with the 'depends_on' attribute.
    """
    deps = getattr(self, 'depends_on', [])
    for name in self.to_list(deps):
        other = self.bld.get_tgen_by_name(name)
        other.post()


@TaskGen.feature('cstlib', 'cshlib', 'cxxstlib', 'cxxshlib', 'fcstlib',
                 'fcshlib')
@TaskGen.before_method('process_source')
def reuse_lib_objects(self):
    """Use the object files in existing libraries as source.

    Find sources that are libs; if any are found, extract their object lists
    and build this lib from the same objects. If this occurs, skip the normal
    process_source step.

    This is defined so that package libraries can be specified as the source of
    task generator of package groups.  Otherwise, each source file will be
    built twice.

    Args:
        self (TaskGen): This TaskGen object.
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


class ListContext(Build.BuildContext):
    """Lists the targets to execute.

    Override the ListContext from waflib.Build to hide internal build targets.
    """
    cmd = 'list'

    def execute(self):
        """ See :py:func:`waflib.Context.Context.execute`.
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


@TaskGen.feature('bdepc')
@TaskGen.before_method('process_rule')
def make_pc(self):
    """Create the 'bdepc' task to generate a pkg-config file.
    """
    tsk = self.create_task('bdepc', None,
                           self.path.find_or_declare(self.target))

    if getattr(self, 'install_path', None):
        self.bld.install_files(self.install_path, tsk.outputs)


class bdepc(Task.Task):
    """This task writes a pkg-config file having configurable properties.
    """

    PKGCONFIG_TEMPLATE = '''prefix=%s
libdir=${prefix}/%s
includedir=${prefix}/%s

Name: %s
Description: %s
URL: %s
Version: %s
Requires:
Requires.private: %s
Libs: -L${libdir} -l%s %s
Libs.private:
Cflags: -I${includedir} %s %s
'''
    # Replacement parameters: prefix, lib_dir, include_dir, description,
    # version, requires.private, name, libs, cflags

    def signature(self):
        """Return a signature that uniquely identifies the generated pc file.

        If the signature changes, waf will rerun this task to regenerate the pc
        file.
        """
        gen = self.generator
        self.hcode = gen.bld.env['PREFIX'] + \
            gen.install_lib_dir + \
            gen.install_include_dir + \
            str(gen.doc) + \
            str(gen.doc) + \
            gen.url + \
            str(gen.version) + \
            str(gen.dep) + \
            gen.lib_name + \
            gen.lib_suffix + \
            str(gen.pc_extra_include_dirs) + \
            str(gen.export_libs) + \
            str(gen.export_flags)

        ret = super(bdepc, self).signature()
        return ret

    def run(self):
        gen = self.generator
        install_lib_dir = gen.install_lib_dir
        install_include_dir = gen.install_include_dir
        doc = gen.doc
        url = gen.url
        if gen.version:
            version = '.'.join(gen.version)
        else:
            version = ''
        dep = gen.dep
        lib_name = gen.lib_name
        lib_suffix = gen.lib_suffix
        extra_include_dirs_str = \
            ' '.join(['-I%s' % d for d in
                      gen.pc_extra_include_dirs])
        export_libs = [gen.bld.env['LIB_ST'] % l for l in gen.export_libs]
        export_flags = gen.export_flags

        pc_source = self.PKGCONFIG_TEMPLATE % (
            gen.bld.env['PREFIX'],
            install_lib_dir,
            install_include_dir,
            doc.mnemonic,
            doc.description,
            url,
            version,
            ' '.join([d + lib_suffix for d in dep]),
            lib_name + lib_suffix,
            ' '.join(export_libs),
            extra_include_dirs_str,
            ' '.join(export_flags)
        )

        self.outputs[0].write(pc_source)


@TaskGen.feature('cshlib', 'cxxshlib', 'dshlib', 'fcshlib', 'bdevnum')
@TaskGen.after_method('apply_link', 'propagate_uselib_vars')
def apply_bdevnum(self):
    """Enforce bde version number on shared objects.

    This method is similar to the waflib.Tools.ccroot.apply_vnum, except that
    the so_name includes the minor version number as well as the major version
    number.
    """
    if (not getattr(self, 'bdevnum', '') or
       os.name != 'posix' or
       self.env.DEST_BINFMT not in ('elf', 'mac-o')):
        return

    link = self.link_task
    nums = list(self.bdevnum)
    nums_str = '.'.join(nums)
    node = link.outputs[0]

    libname = node.name
    if libname.endswith('.dylib'):
        name3 = libname.replace('.dylib', '.%s.dylib' % nums_str)
        name2 = libname.replace('.dylib',
                                '.%s.dylib' % (nums[0] + '.' + nums[1]))
    else:
        name3 = libname + '.' + nums_str
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
