# This is a fork of waf_unit_test.py supporting BDE-style unit tests.

import os
import sys
import time

from waflib import Utils
from waflib import Task
from waflib import Logs
from waflib import Options
from waflib import TaskGen

from bdebuild.common import sysutil

testlock = Utils.threading.Lock()
test_runner_path = os.path.join(sysutil.repo_root_path(), 'bin',
                                'bde_runtest.py')


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

    def get_testcmd(self):
        testcmd = [
            sys.executable, test_runner_path,
            '--verbosity=%s' % Options.options.test_v,
            '--timeout=%s' % Options.options.test_timeout,
            '-j%s' % Options.options.test_j,
            self.testdriver_node.abspath()
        ]
        if Options.options.test_junit:
            testcmd += ['--junit=%s-junit.xml' %
                        self.testdriver_node.abspath()]

        if Options.options.valgrind:
            testcmd += [
                '--valgrind',
                '--valgrind-tool=%s' % Options.options.valgrind_tool
            ]
        return testcmd

    def run(self):
        """
        Execute the test. The execution is always successful, but the results
        are stored on ``self.generator.bld.utest_results`` for postprocessing.
        """

        self.testdriver_node = self.inputs[0]
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

        cwd = self.testdriver_node.parent.abspath()
        testcmd = self.get_testcmd()

        start_time = time.time()
        proc = Utils.subprocess.Popen(testcmd, cwd=cwd, env=fu,
                                      stderr=Utils.subprocess.STDOUT,
                                      stdout=Utils.subprocess.PIPE)
        stdout = proc.communicate()[0]
        end_time = time.time()

        if not isinstance(stdout, str):
            stdout = stdout.decode(sys.stdout.encoding or 'iso8859-1')

        tup = (self.testdriver_node, proc.returncode, stdout,
               end_time - start_time)
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

    def get_time(seconds):
        m, s = divmod(seconds, 60)
        if m == 0:
            return '%dms' % (seconds * 1000)
        else:
            return '%02d:%02d' % (m, s)

    lst = getattr(bld, 'utest_results', [])
    from waflib import Logs
    Logs.pprint('CYAN', 'Test Summary')

    total = len(lst)
    tfail = len([x for x in lst if x[1]])

    Logs.pprint('CYAN', '  tests that pass %d/%d' % (total-tfail, total))
    for (f, code, out, t) in lst:
        if not code:
            if bld.options.show_test_out:
                Logs.pprint('GREEN', '[%s (TEST)] <<<<<<<<<<' % f.abspath())
                Logs.pprint('CYAN', out)
                Logs.pprint('GREEN', '>>>>>>>>>>')
            else:
                Logs.pprint('GREEN', '%s (%s)' % (f, get_time(t)))

    Logs.pprint('CYAN', '  tests that fail %d/%d' % (tfail, total))
    for (f, code, out, t) in lst:
        if code:
            Logs.pprint('YELLOW', '[%s (TEST)] <<<<<<<<<<' % f.abspath())
            Logs.pprint('CYAN', out)
            Logs.pprint('YELLOW', '>>>>>>>>>>')

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
                   help="whether to build and run test drivers "
                        "(none/build/run) [default: %default]. "
                        "none: don't build or run tests, "
                        "build: build tests but don't run them, "
                        "run: build and run tests",
                   dest='test')

    grp.add_option('--test-v', type='int', default=0,
                   help='verbosity level of test output [default: %default]',
                   dest='test_v')

    grp.add_option('--test-j', type='int', default=4,
                   help='amount of parallel jobs used by the test runner '
                        '[default: %default]. '
                        'This value is independent and multiplicative with '
                        'the number of jobs used by waf itself, which can be '
                        'beneficial as some the test drivers are highly '
                        'I/O bound.',
                   dest='test_j')

    grp.add_option('--show-test-out', action='store_true', default=False,
                   help='show output of tests even if they pass',
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
                   help='use valgrind tool (memchk/helgrind/drd) '
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
