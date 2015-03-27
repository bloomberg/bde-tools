from __future__ import print_function

import sys

from bdebld.runtest import runner
from bdebld.runtest import cmdlineutil


def main():
    """Start the test runner with options specified by commandline arguments.

    Create a context from the command line arguments and start up the test
    driver ``Runner``.  Exit with a return code 0 on success and 1 on failure.
    """

    option_parser = cmdlineutil.get_cmdline_options()
    options, args = option_parser.parse_args()

    if len(args) < 1:
        print("Test driver path is required as the last argument.",
              file=sys.stderr)
        sys.exit(1)

    ctx = cmdlineutil.make_context_from_options(options, args)

    test_runner = runner.Runner(ctx)
    if test_runner.start():
        sys.exit(0)
    else:
        sys.exit(1)

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
