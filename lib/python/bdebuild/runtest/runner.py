import os
import signal
import subprocess
import sys
import threading
import time


class _Status(object):
    """Status of the test run.

    Attributes:
        is_done (bool): True when all the all test cases have been run or when
                        test has been terminated.
        is_success (bool): Whether all test cases have passed.
    """

    def __init__(self, ctx, status_cond):
        self._status_cond = status_cond
        self._case_num = 0
        self._ctx = ctx
        self.is_done = False
        self.is_success = True

    def next_test_case(self):
        with self._status_cond:
            if self.is_done:
                return -1
            else:
                next_case_num = self._case_num + 1
                while self._ctx.policy.is_skip_case(next_case_num):
                    self._ctx.log.record_skip(next_case_num)
                    next_case_num += 1

                self._case_num = next_case_num
                return self._case_num

    def set_failure(self):
        self.is_success = False

    def notify_done(self):
        self._status_cond.acquire()
        try:
            self.is_done = True
            self._status_cond.notify()
        finally:
            self._status_cond.release()


class _Worker(threading.Thread):
    """Worker thread to run test cases."""

    def __init__(self, ctx, status):
        """Initialize a test runner object.

        Args:
            ctx (Context): Runner context.
            status (Status): Runner status.
        """
        threading.Thread.__init__(self)
        self._ctx = ctx
        self._status = status
        self._proc = None
        self._case = 0

    def _platform_needs_limited_output(self):
        """Determine whether this platform is one of those needing limited
        output size to avoid hangs. {DRQS 164928733<GO>}
        """
        platform = sys.platform

        if platform.find("sun", 0) != -1:
            return True

        if platform.find("aix", 0) != -1:
            return True

        return False

    def _get_full_test_run_cmd(self):
        """Get list of command and arguments for current test case."""
        options = self._ctx.options

        cmd = []
        if options.valgrind_tool:
            cmd += [
                "valgrind",
                "--error-exitcode=1",
                "--tool=%s" % options.valgrind_tool,
            ]
            if options.valgrind_tool == "memcheck":
                cmd += ["--leak-check=full"]

        cmd += [options.test_path, str(self._case)]

        if self._ctx.options.verbosity > 0:
            cmd.extend(["v" for n in range(options.verbosity)])

        return cmd

    def _get_limited_test_run_cmd(self):
        """Get string of command and arguments for current test case, piping
        the output to 'bde_input_limiter.py' to limit it to 5000 lines.
        """
        limiter_command = (
            os.path.dirname(os.path.realpath(sys.argv[0]))
            + os.sep
            + "bde_input_limiter.py"
        )

        cmd = self._get_full_test_run_cmd()
        cmd = " ".join(cmd)
        cmd = "bash -c 'set -o pipefail; " + cmd
        cmd += " | " + limiter_command + "'"

        self._ctx.log.debug_case(self._case, "COMMAND %s" % cmd)

        return cmd

    def _get_test_run_cmd(self):
        """Return a tuple containing the command to run (either as a list or
        as a string) and a boolean flag indicating whether the command
        is in string form or not.
        """
        if self._platform_needs_limited_output():
            return (self._get_limited_test_run_cmd(), True)
        else:
            return (self._get_full_test_run_cmd(), False)

    def run(self):
        while True:
            self._case = self._status.next_test_case()

            if self._case <= 0:
                return

            (cmd, use_shell) = self._get_test_run_cmd()
            self._ctx.log.record_start(self._case)
            try:
                self._proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    shell=use_shell,
                )
                (out, err) = self._proc.communicate()
                rc = self._proc.returncode
            except Exception as e:
                self._status.set_failure()
                self._ctx.log.record_exception(self._case, e)
                self._status.notify_done()
                return

            def decode_text(txt):
                if txt:
                    if not isinstance(out, str):
                        return txt.decode(sys.stdout.encoding or "iso8859-1")
                return txt if txt else ""

            # BDE uses the -1 return code to indicate that no more tests are
            # left to run:
            #
            #   * On Linux, -1 becomes 255, because return codes are always
            #     unsigned.
            #
            #   * On Windows, -1 stay as -1 for python 2, and 4294967295
            #     (INT32_MAX) for python 3.
            #
            #   * On Cygwin, -1 becomes 127!
            #
            # To handle malformed test drivers, stop when there are more
            # than 499 test cases.
            if (
                rc == 255
                or rc == -1
                or rc == 127
                or rc == 4294967295
                or self._case > 499
            ):
                self._ctx.log.debug_case(self._case, "DOES NOT EXIST")
                self._status.notify_done()
                return
            elif rc == 0:
                self._ctx.log.record_success(self._case, rc, decode_text(out))
            else:
                self._ctx.log.record_failure(self._case, rc, decode_text(out))
                self._status.set_failure()


class Runner(object):
    """Run test cases in parallel.

    This class should be created in the main thread.
    """

    def __init__(self, ctx):
        """Initialize a test runner object.

        Args:
            ctx (Context): Runner context.
        """
        self._ctx = ctx
        self._status_cond = threading.Condition()
        self._status = _Status(self._ctx, self._status_cond)
        self._workers = [
            _Worker(self._ctx, self._status)
            for j in range(self._ctx.options.num_jobs)
        ]

    def _count_live_workers(self, context):
        # Extra "or False" converts any "None" entries to "False".
        filtered_workers = [
            (
                (
                    worker is not None
                    and worker.is_alive()
                    and worker._proc
                    and worker._case > 0
                )
                or False
            )
            for worker in self._workers
        ]

        count = sum(filtered_workers)

        self._ctx.log.debug(
            "There are %d live workers in context '%s'" % (count, context)
        )

        return count

    def _terminate(self, log_func):
        """Terminate any subprocess spawned by worker threads.

        Args:
            log_func (func): Logging function.
        """
        self._status.set_failure()
        self._status.notify_done()
        # While there are live workers, try to kill them.  We do this in a loop
        # to alleviate any race conditions.
        while self._count_live_workers("TIMEOUT") > 0:
            for worker in self._workers:
                # The following technique to kill processes is not thread safe,
                # but it is acceptable considering that a race condition will
                # most like mean that the test process was already terminated.
                #
                # The outer loop should alleviate any thread-safety issues
                # where a thread is skipped and NOT terminated.
                try:
                    if worker.is_alive() and worker._proc and worker._case > 0:
                        worker._proc.kill()
                        log_func(worker._case, worker._proc.pid)
                except:
                    pass
            time.sleep(1)

    def start(self):
        """Start running test cases in parallel.

        This method runs the test cases using a number of worker threads
        configured using options specified in the context.  The context
        specifies the number of threads to use, the way outputs are logged, and
        the test cases to skip.  The worker threads look up the next test case
        to run through a shared status object protected by a condition
        variable.  The runner (main) thread waits until the condition variable
        is signaled before returning.

        A Timer object is used to support timining out the worker threads after
        a period of time specified in the context.  On timeout or SIG_INT, the
        subprocesses own by the worker thread will be terminated.

        Returns:
            True if all test cases passed, and False otherwise.
        """

        for worker in self._workers:
            worker.start()

        def timeout_handler():
            self._ctx.log.debug(
                "TIMED OUT AFTER %ss" % self._ctx.options.timeout
            )
            self._terminate(self._ctx.log.record_timeout)

        def sigint_handler(signal, frame):
            self._ctx.log.info("CAUGHT SIG_INT")
            self._terminate(lambda: None)

        timer = threading.Timer(self._ctx.options.timeout, timeout_handler)
        timer.start()
        self._ctx.log.debug("TIMER STARTED")

        signal.signal(signal.SIGINT, sigint_handler)

        self._status_cond.acquire()
        try:
            if not self._status.is_done:
                self._status_cond.wait()
        finally:
            self._status_cond.release()

        for worker in self._workers:
            worker.join()

        timer.cancel()

        self._ctx.log.flush()

        return self._status.is_success


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
