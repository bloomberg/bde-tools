# This is a fork of waf_unit_test.py supporting BDE-style unit tests.

import os
import sys

from waflib import Utils
from waflib import Task
from waflib import Logs
from waflib import Options
from waflib import TaskGen

testlock = Utils.threading.Lock()


@TaskGen.feature('test')
@TaskGen.after_method('apply_link')
def make_test(self):
    """
    Create the unit test task. There can be only one unit test task by task
    generator.

    """
    if getattr(self, 'link_task', None):
        self.create_task('utest', self.link_task.outputs)


class utest(Task.Task):
    """
    Execute a unit test
    """
    color = 'PINK'
    after = ['vnum', 'inst']
    vars = []

    def runnable_status(self):
        """
        Always execute the task if `waf --test run` was used or no
        tests otherwise.
        """

        run_test = Options.options.test == 'run'
        if not run_test:
            return Task.SKIP_ME

        ret = super(utest, self).runnable_status()
        if ret == Task.SKIP_ME:
            if run_test:
                return Task.RUN_ME

        return ret

    def run(self):
        """
        Execute the test. The execution is always successful, but the results
        are stored on ``self.generator.bld.utest_results`` for postprocessing.
        """

        filename = self.inputs[0].abspath()
        self.ut_exec = getattr(self.generator, 'ut_exec', [filename])
        if getattr(self.generator, 'ut_fun', None):
            # FIXME waf 1.8 - add a return statement here?
            self.generator.ut_fun(self)

        try:
            fu = getattr(self.generator.bld, 'all_test_paths')
        except AttributeError:
            # this operation may be performed by at most #maxjobs
            fu = os.environ.copy()

            lst = []
            for g in self.generator.bld.groups:
                for tg in g:
                    if getattr(tg, 'link_task', None):
                        s = tg.link_task.outputs[0].parent.abspath()
                        if s not in lst:
                            lst.append(s)

            def add_path(dct, path, var):
                dct[var] = os.pathsep.join(Utils.to_list(path) +
                                           [os.environ.get(var, '')])

            if Utils.is_win32:
                add_path(fu, lst, 'PATH')
            elif Utils.unversioned_sys_platform() == 'darwin':
                add_path(fu, lst, 'DYLD_LIBRARY_PATH')
                add_path(fu, lst, 'LD_LIBRARY_PATH')
            else:
                add_path(fu, lst, 'LD_LIBRARY_PATH')
            self.generator.bld.all_test_paths = fu

        cwd = (getattr(self.generator, 'ut_cwd', '') or
               self.inputs[0].parent.abspath())

        testcmd = getattr(Options.options, 'testcmd', False)
        if testcmd:
            ut_exec = self.ut_exec[0]
            self.ut_exec = (testcmd % ut_exec).split(' ')
            if Options.options.test_junit:
                self.ut_exec += ['--junit=%s-junit.xml' % ut_exec]
            if Options.options.valgrind:
                self.ut_exec += ['--valgrind', '--valgrind-tool=%s' %
                                 Options.options.valgrind_tool]

        proc = Utils.subprocess.Popen(self.ut_exec, cwd=cwd, env=fu,
                                      stderr=Utils.subprocess.STDOUT,
                                      stdout=Utils.subprocess.PIPE)
        stdout = proc.communicate()[0]
        if stdout:
            stdout = stdout.decode(sys.stdout.encoding or 'iso8859-1')

        tup = (filename, proc.returncode, stdout)
        self.generator.utest_result = tup

        testlock.acquire()
        try:
            bld = self.generator.bld
            Logs.debug("ut: %r", tup)
            try:
                bld.utest_results.append(tup)
            except AttributeError:
                bld.utest_results = [tup]
        finally:
            testlock.release()


def summary(bld):
    """
    Display an execution summary::

        def build(bld):
            bld(features='cxx cxxprogram test', source='main.c', target='app')
            from waflib.Tools import waf_unit_test
            bld.add_post_fun(waf_unit_test.summary)
    """
    lst = getattr(bld, 'utest_results', [])
    from waflib import Logs
    Logs.pprint('CYAN', 'Test Summary')

    total = len(lst)
    tfail = len([x for x in lst if x[1]])

    Logs.pprint('CYAN', '  tests that pass %d/%d' % (total-tfail, total))
    for (f, code, out) in lst:
        if not code:
            if bld.options.show_test_out:
                Logs.pprint('CYAN', '[%s (TEST)] <<<<<<<<<<' % f)
                Logs.pprint('CYAN', out)
                Logs.pprint('CYAN', '>>>>>>>>>>')
            else:
                Logs.pprint('CYAN', '[%s (TEST)]' % f)

    Logs.pprint('CYAN', '  tests that fail %d/%d' % (tfail, total))
    for (f, code, out) in lst:
        if code:
            Logs.pprint('CYAN', '[%s (TEST)] <<<<<<<<<<' % f)
            Logs.pprint('CYAN', out)
            Logs.pprint('CYAN', '>>>>>>>>>>')

    if tfail > 0:
        bld.fatal("Some tests failed. (%s)" % (str(bld.log_timer)))


def options(opt):
    """
    Provide the command-line options.
    """

    grp = opt.get_option_group('build and install options')

    grp.add_option('--test', type='choice',
                   choices=('none', 'build', 'run'),
                   default='none',
                   help="'none': don't build or run tests" +
                   ", 'build': build tests but don't run them" +
                   ", 'run': build and run tests [default: %default]",
                   dest='test')

    grp.add_option('--test-v', type='int', default=0,
                   help='verbosity level of test output [default: %default]',
                   dest='test_verbosity')

    grp.add_option('--show-test-out', action='store_true', default=False,
                   help='show output of tests even if they pass '
                        '[default: %default]',
                   dest='show_test_out')

    grp.add_option('--test-timeout', type='int', default=200,
                   help='test driver timeout [default: %default]',
                   dest='test_timeout')

    grp.add_option('--test-junit', action='store_true', default=False,
                   help='create jUnit-style test results files for '
                        'test drivers that are executed',
                   dest='test_junit')

    grp.add_option('--valgrind', action='store_true', default=False,
                   help='enable valgrind when running the test driver',
                   dest='valgrind')

    grp.add_option('--valgrind-tool', type='choice', default='memcheck',
                   choices=('memcheck', 'helgrind', 'drd'),
                   help='use valgrind tool: memchk, helgrind, or drd '
                   '[default: %default]',
                   dest='valgrind_tool')

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
