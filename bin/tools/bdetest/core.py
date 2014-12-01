from __future__ import print_function

import argparse
import os
import sys

from .context import Context
from .options import Options
from .runner import Runner
from .log import Log
from .policy import Policy


def main():
    """Start the test runner with options specified by commandline arguments.

    Create a context from the command line arguments and start up the test
    driver ``Runner``.  Exit with a return code 0 on success and 1 on failure.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--junit', type=str,
                        help='output to the specified junit xml file')
    parser.add_argument('--jobs', '-j', type=int, default=4,
                        help='number of jobs to use')
    parser.add_argument('--debug', '-d', action='store_true',
                        help='Print additional trace statements.')
    parser.add_argument('--verbosity', '-v', type=int, default=0,
                        help='verbosity of the test driver -- '
                             'pass a sequence of "v" characters having '
                             'a length of the value of this argument to '
                             'the test driver being executed.')
    parser.add_argument('--valgrind', action='store_true',
                        help='enable valgrind when running the test driver')
    parser.add_argument('--timeout', type=int, default=120,
                        help='timeout the test driver after a specified '
                             'period in seconds')
    parser.add_argument('--filter-host-type', choices=('VM', 'Physical'),
                        default=None,
                        help='(default: "HOST" environment variable)')
    parser.add_argument('--filter-abi-bits', choices=('32', '64'),
                        default=None,
                        help='(default: "ABI_BITS" environment variable)')
    parser.add_argument('path',
                        metavar='TEST_DRIVER_PATH',
                        type=str, nargs=1,
                        help='the path to the BDE-style test driver')

    args = parser.parse_args()
    ctx = _get_context_from_args(args)

    runner = Runner(ctx)
    if runner.start():
        sys.exit(0)
    else:
        sys.exit(1)


def _get_context_from_args(args):
    test_driver_path = args.path[0]
    if not os.path.isfile(test_driver_path):
        print("%s does not exist" % test_driver_path, file=sys.stderr)
        sys.exit(1)

    policy_path = os.path.join(
        os.path.dirname(os.path.abspath(sys.argv[0])), 'test_filter.py')

    options = Options(test_path=test_driver_path,
                      is_debug=args.debug,
                      verbosity=args.verbosity,
                      num_jobs=args.jobs,
                      timeout=args.timeout,
                      junit_file_path=args.junit,
                      policy_path=policy_path,
                      filter_host_type=args.filter_host_type,
                      filter_abi_bits=args.filter_abi_bits)
    log = Log(options)
    policy = Policy(options)
    return Context(options=options, log=log, policy=policy)
