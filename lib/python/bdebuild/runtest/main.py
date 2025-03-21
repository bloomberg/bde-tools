from __future__ import print_function

import contextlib
import optparse
import os
import shutil
import sys
import tempfile

import bdebuild.runtest.options

from bdebuild.runtest import context
from bdebuild.runtest import policy
from bdebuild.runtest import log
from bdebuild.runtest import runner


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

    ctx = make_context_from_options(options, args)

    test_runner = runner.Runner(ctx)

    exit_code = 0

    if not test_runner.start():
        exit_code = 1

    # Clean up our TMPDIR.
    if not (options.keeptmp or "BDE_KEEP_TMPFILES" in os.environ):
        shutil.rmtree(temp_directory)
    else:
        print("Not deleting temp files - they are in %s" % temp_directory)

    sys.exit(exit_code)


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
        help="timeout the test driver after a specified period in seconds",
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

    test_options = bdebuild.runtest.options.Options(
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
