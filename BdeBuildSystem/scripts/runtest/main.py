from __future__ import print_function

import contextlib
import optparse
import os
import shutil
import subprocess
import sys
import tempfile

from . import options as run_options
from . import context
from . import policy
from . import log
from . import runner


def main():
    """Start the test runner with options specified by commandline arguments.

    Create a context from the command line arguments and start up the test
    driver ``Runner``.  Exit with a return code 0 on success and 1 on failure.

    Creates a unique directory for tempfiles, and cleans it up as long as
    "BDE_KEEP_TMPFILES" is not in the environment or the '--keeptmp' option was
    not used.
    """

    # We're going to create our own tmpdir, and then repoint 'TMPDIR' to it.
    # At exit time, we'll clean it up.
    temp_directory = tempfile.mkdtemp()
    os.environ["TMPDIR"] = temp_directory

    option_parser = get_cmdline_options()
    options, args = option_parser.parse_args()

    if len(args) < 1:
        print(option_parser.format_help())
        sys.exit(1)

    if options.parallel_runtests < 1:
        print("--parallel-runtests must be at least 1", file=sys.stderr)
        sys.exit(1)

    if options.parallel_runtests > 1 and options.junit:
        print(
            "--junit cannot be combined with --parallel-runtests",
            file=sys.stderr,
        )
        sys.exit(1)

    exit_code = 0

    if options.parallel_runtests > 1:
        if not run_parallel_runtests(
            options.parallel_runtests, temp_directory, options.verbosity > 0
        ):
            exit_code = 1
    else:
        ctx = make_context_from_options(options, args)

        test_runner = runner.Runner(ctx)

        if not test_runner.start():
            exit_code = 1

    # Clean up our TMPDIR.
    if not (options.keeptmp or "BDE_KEEP_TMPFILES" in os.environ):
        shutil.rmtree(temp_directory)
    else:
        print("Not deleting temp files - they are in %s" % temp_directory)

    sys.exit(exit_code)


def run_parallel_runtests(num_runs, temp_directory, is_verbose):
    """Run ``num_runs`` copies of this test runner concurrently.

    Each copy gets the same command line, with ``--parallel-runtests 1``
    appended so it runs the test driver itself.  The output of each copy is
    captured to a file.  Once all copies finish, the output of each failed
    copy is printed, in order.  Passing copies are printed only if
    ``is_verbose`` is True.

    Args:
        num_runs (int): Number of copies to run.
        temp_directory (str): Directory for the captured output.
        is_verbose (bool): Whether to print the output of passing copies.

    Returns:
        True if every copy succeeded.
    """
    child_args = (
        [sys.executable, os.path.abspath(sys.argv[0])]
        + sys.argv[1:]
        + ["--parallel-runtests", "1"]
    )

    runs = []
    for i in range(num_runs):
        out_path = os.path.join(temp_directory, "runtest_%d.out" % (i + 1))
        out_file = open(out_path, "wb")
        process = subprocess.Popen(
            child_args, stdout=out_file, stderr=subprocess.STDOUT
        )
        runs.append((process, out_file, out_path))

    num_failed = 0
    for i, (process, out_file, out_path) in enumerate(runs):
        rc = process.wait()
        out_file.close()
        if rc != 0:
            num_failed += 1
        elif not is_verbose:
            continue

        print(
            "===== bde_runtest run %d of %d: %s (rc=%d) ====="
            % (i + 1, num_runs, "FAILED" if rc else "PASSED", rc)
        )
        sys.stdout.flush()
        with open(out_path, "rb") as f:
            shutil.copyfileobj(f, getattr(sys.stdout, "buffer", sys.stdout))
        sys.stdout.flush()

    print("%d of %d bde_runtest runs failed" % (num_failed, num_runs))
    return num_failed == 0


def get_cmdline_options():
    """Get the command line options.

    Returns:
        OptionsParser
    """

    usage = "usage: %prog [options] test_driver_path"
    parser = optparse.OptionParser(usage)
    parser.add_option(
        "--junit", type=str, help="output to the specified junit xml file"
    )
    parser.add_option(
        "--jobs", "-j", type="int", default=2, help="number of jobs to use"
    )
    parser.add_option(
        "--parallel-runtests",
        "-J",
        type="int",
        default=1,
        help="number of identical test runner processes to run "
        "concurrently, each using --jobs jobs [default: %default]",
    )
    parser.add_option(
        "--debug",
        "-d",
        action="store_true",
        help="Print additional trace statements.",
    )
    parser.add_option(
        "--verbosity",
        "-v",
        type="int",
        default=0,
        help="verbosity of the test driver -- "
        'pass a sequence of "v" characters having '
        "a length of the value of this argument to "
        "the test driver being executed.",
    )
    parser.add_option(
        "--valgrind",
        action="store_true",
        help="enable valgrind when running the test driver",
    )
    parser.add_option(
        "--keeptmp",
        action="store_true",
        help="Keep the temporary directory instead of cleaning "
        'it (can also be enabled by setting "BDE_KEEP_TMPFILES" '
        "in environment)",
    )
    parser.add_option(
        "--valgrind-tool",
        type="choice",
        default="memcheck",
        choices=("memcheck", "helgrind", "drd"),
        help="use valgrind tool: memchk, helgrind, or drd "
        "[default: %default]",
    )
    parser.add_option(
        "--timeout",
        type="int",
        default=600,
        help="timeout the test driver after a specified " "period in seconds",
    )
    parser.add_option(
        "--filter-host-type",
        choices=("VM", "Physical"),
        default=None,
        help='(default: "HOST" environment variable)',
    )
    parser.add_option(
        "--filter-abi-bits",
        choices=("32", "64"),
        default=None,
        help='(default: "ABI_BITS" environment variable)',
    )
    parser.add_option(
        "--log-errors-only",
        action="store_true",
        help="Do not log test cases that completed without errors (default: log all test cases)",
    )
    return parser


def make_context_from_options(options, args):
    test_driver_path = args[0]
    if not os.path.isfile(test_driver_path):
        print("%s does not exist" % test_driver_path, file=sys.stderr)
        sys.exit(1)

    upd = os.path.dirname
    lib_path = upd(os.path.realpath(__file__))
    policy_path = os.path.join(lib_path, "test_filter.py")

    if options.valgrind:
        valgrind_tool = options.valgrind_tool
    else:
        valgrind_tool = None

    test_options = run_options.Options(
        test_path=test_driver_path,
        is_debug=options.debug,
        verbosity=options.verbosity,
        num_jobs=options.jobs,
        timeout=options.timeout,
        junit_file_path=options.junit,
        policy_path=policy_path,
        valgrind_tool=valgrind_tool,
        filter_host_type=options.filter_host_type,
        filter_abi_bits=options.filter_abi_bits,
        log_errors_only=options.log_errors_only
    )
    test_logger = log.Log(test_options)
    test_policy = policy.Policy(test_options)
    return context.Context(
        options=test_options, log=test_logger, policy=test_policy
    )


if __name__ == "__main__":
    main()

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
