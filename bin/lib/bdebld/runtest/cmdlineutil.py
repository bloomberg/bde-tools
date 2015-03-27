from __future__ import print_function

import optparse
import os
import sys

from bdebld.runtest import context
from bdebld.runtest import policy
from bdebld.runtest import log
import bdebld.runtest.options


def get_cmdline_options():
    """Get the command line options.

    Returns:
        OptionsParser
    """

    parser = optparse.OptionParser()
    parser.add_option('--junit', type=str,
                      help='output to the specified junit xml file')
    parser.add_option('--jobs', '-j', type="int", default=4,
                      help='number of jobs to use')
    parser.add_option('--debug', '-d', action='store_true',
                      help='Print additional trace statements.')
    parser.add_option('--verbosity', '-v', type='int', default=0,
                      help='verbosity of the test driver -- '
                      'pass a sequence of "v" characters having '
                      'a length of the value of this argument to '
                      'the test driver being executed.')
    parser.add_option('--valgrind', action='store_true',
                      help='enable valgrind when running the test driver')
    parser.add_option('--valgrind-tool', type='choice', default='memcheck',
                      choices=('memcheck', 'helgrind', 'drd'),
                      help='use valgrind tool: memchk, helgrind, or drd '
                           '[default: %default]')
    parser.add_option('--timeout', type="int", default=120,
                      help='timeout the test driver after a specified '
                      'period in seconds')
    parser.add_option('--filter-host-type', choices=('VM', 'Physical'),
                      default=None,
                      help='(default: "HOST" environment variable)')
    parser.add_option('--filter-abi-bits', choices=('32', '64'),
                      default=None,
                      help='(default: "ABI_BITS" environment variable)')

    return parser


def make_context_from_options(options, args):
    test_driver_path = args[0]
    if not os.path.isfile(test_driver_path):
        print("%s does not exist" % test_driver_path, file=sys.stderr)
        sys.exit(1)

    upd = os.path.dirname
    lib_path = upd(os.path.realpath(__file__))
    policy_path = os.path.join(lib_path, 'test_filter.py')

    if options.valgrind:
        valgrind_tool = options.valgrind_tool
    else:
        valgrind_tool = None

    test_options = bdebld.runtest.options.Options(
        test_path=test_driver_path,
        is_debug=options.debug,
        verbosity=options.verbosity,
        num_jobs=options.jobs,
        timeout=options.timeout,
        junit_file_path=options.junit,
        policy_path=policy_path,
        valgrind_tool=valgrind_tool,
        filter_host_type=options.filter_host_type,
        filter_abi_bits=options.filter_abi_bits)
    test_logger = log.Log(test_options)
    test_policy = policy.Policy(test_options)
    return context.Context(options=test_options, log=test_logger,
                           policy=test_policy)
