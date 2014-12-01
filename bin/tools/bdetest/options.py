import os

class Options(object):
    """This class represents a set of options for the test runner.

    Attributes:
        test_path: path to the test driver
        policy_path: path to ``test_filter.py``
        component_name: name of the component for the test driver
        is_debug: print additional debug options
        junit_file_path: output junit xml file instead of stdout
        is_verbose: whether to print all test case outputs (by default, only
                    failed test cases are printed)
        verbosity: verbosity level
        num_jobs: number of threads to use to run test cases
        timeout: time driver timeout
        filter_abi_bits: override abi_bits filter for test policy
        filter_host_type: override host_type filter for test policy

    """
    def __init__(self, **kw):
        self.test_path = kw['test_path']
        self.component_name = os.path.basename(
            self.test_path).partition('.')[0]
        self.policy_path = kw['policy_path']
        self.junit_file_path = kw['junit_file_path']
        self.is_debug = kw['is_debug']
        self.verbosity = kw['verbosity']
        self.is_verbose = self.verbosity > 0
        self.num_jobs = kw['num_jobs']
        self.timeout = kw['timeout']
        self.filter_abi_bits = kw['filter_abi_bits']
        self.filter_host_type = kw['filter_host_type']
