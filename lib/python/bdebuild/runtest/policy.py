import os
import platform


class Policy(object):
    """Determines and manages the test runner policy.

    This class provides backward compatibility with a mechansim used in the
    previous version of the test runner that excludes certain test cases from
    running based on a set of criteria defined in ``test_filter.py``.  The
    structure the policy file probably should be redesigned.

    TODO redesign test_filter.py
    ----------------------------

      * Use JSON format instead of an python map that has to be evaluated

      * ``test_filter.py`` should be separately associated with each project,
        instead of being centrally located in the test runner directory

      * Think about some performance enhancement filters, such as separating
        the test dirvers into different categories based on the their running
        times.

    """

    def __init__(self, opts):
        """Initialize the object with specified options.

        Args:
            opts (Options): Test runner options.
        """
        self._opts = opts
        self._policy = self._determine_policy()

    def is_skip_case(self, case_number):
        """Return whether a test case should be skipped"""

        if case_number in self._policy:
            return self._policy[case_number] == 'skip'

    def _determine_policy(self):
        def get_policy_table():
            if os.path.isfile(self._opts.policy_path):
                with open(self._opts.policy_path, 'r') as f:
                    # Evaluate the filter dictionary but do not allow the
                    # execution of any methods.
                    policy_table = eval(f.read(), {'__builtins__': None}, {})
                return policy_table
            else:
                return {}

        def get_current_config():
            config = {}

            config['os'] = platform.uname()[0]
            config['host_type'] = (self._opts.filter_host_type or
                                   os.environ.get('HOST', 'Physical'))
            config['abi_bits'] = self._opts.filter_abi_bits

            return config

        def match_policy(config, case_policy):
            for p in case_policy:
                if p in config:
                    if case_policy[p] != config[p]:
                        return False

            return True

        policy_table = get_policy_table()
        config = get_current_config()

        policy = {}

        if self._opts.component_name in policy_table:
            component_policy = policy_table[self._opts.component_name]
            for case_policy in component_policy:
                if match_policy(config, case_policy):
                    policy[case_policy['case']] = case_policy['policy']
        return policy

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
