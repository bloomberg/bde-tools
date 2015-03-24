"""Waf entry point.

Functions - Waf Command
-----------------------
option() - all commands
configure() - waf configure
build() - waf build
"""

import sys

from waflib import Utils

from bdebld.meta import sysutil

from bdebld.waf import cmdlineutil
from bdebld.waf import configurehelper
from bdebld.waf import configureutil
from bdebld.waf import buildhelper
from bdebld.waf import graphhelper


def options(ctx):
    # check version numbers here because options() is called before any other
    # command-handling function
    if sys.hexversion < 0x2060000:
        ctx.fatal('Pyhon 2.6 and above is required to build BDE using waf.')

    ctx.load('bdebld.waf.bdeunittest')

    from waflib.Tools.compiler_c import c_compiler
    c_compiler['win32'] = ['msvc']
    c_compiler['linux'] = ['gcc']
    c_compiler['darwin'] = ['gcc']
    ctx.load('compiler_c')

    from waflib.Tools.compiler_cxx import cxx_compiler
    cxx_compiler['win32'] = ['msvc']
    cxx_compiler['linux'] = ['g++']
    cxx_compiler['darwin'] = ['g++']
    ctx.load('compiler_cxx')

    ctx.load('msvs')
    ctx.load('xcode')

    cmdlineutil.add_cmdline_options(ctx)
    graphhelper.add_cmdline_options(ctx)


def configure(ctx):
    ctx.load('bdebld.waf.bdeunittest')

    ufid = configureutil.make_ufid(ctx)

    waf_platform = Utils.unversioned_sys_platform()
    if waf_platform == 'win32':
        if '64' in ufid.flags:
            ctx.options.msvc_targets = 'x64'
        else:
            ctx.options.msvc_targets = 'x86'

    if 'CXX' in ctx.environ and 'CC' not in ctx.environ:
        ctx.environ['CC'] = sysutil.get_other_compiler(
            ctx.environ['CXX'], sysutil.CompilerType.CXX)
    elif 'CC' in ctx.environ and 'CXX' not in ctx.environ:
        ctx.environ['CXX'] = sysutil.get_other_compiler(
            ctx.environ['CC'], sysutil.CompilerType.C)

    ctx.load('compiler_c')
    ctx.load('compiler_cxx')
    cc_ver = ctx.env.CC_VERSION
    cc_name = ctx.env.COMPILER_CC
    cxx_ver = ctx.env.CC_VERSION
    cxx_name = ctx.env.COMPILER_CXX

    if cxx_name in sysutil.CXX_C_COMP_MAP:
        exp_c_name = sysutil.CXX_C_COMP_MAP[cxx_name]
        if exp_c_name != cc_name:
            ctx.fatal('C compiler and C++ compiler must match. '
                      'Expected c compiler: %s' % exp_c_name)
        if cc_ver != cxx_ver:
            ctx.fatal('C compiler and C++ compiler must be the same version. '
                      'C compiler version: %s, '
                      'C++ compiler version: %s' % (cc_ver, cxx_ver))

    uplid = configureutil.make_uplid(ctx)

    helper = configurehelper.ConfigureHelper(ctx, ufid, uplid)
    helper.configure()


def build(ctx):
    if ctx.cmd == "msvs" or ctx.cmd == "msvs2008":
        if ctx.options.test:
            ctx.waf_command = 'waf.bat --test=%s' % ctx.options.test

        ctx.projects_dir = ctx.srcnode.make_node('.depproj')
        ctx.projects_dir.mkdir()

    if ctx.cmd == 'graph':
        helper = graphhelper.GraphHelper(ctx)
        helper.draw()
        return

    if ctx.cmd == 'build':
        print('Waf: using %d jobs (change with -j)' % ctx.options.jobs)

    helper = buildhelper.BuildHelper(ctx)
    helper.build()

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
