import os

class Options(object):
    """This class represents a set of options for the test runner.

    Attributes:
        test_path (str): Path to the test driver.
        policy_path (str): Path to ``test_filter.py``.
        component_name (str): Name of the component for the test driver.
        is_debug (bool): Whether to print additional debug options.
        junit_file_path (str): If the vlaue is not None, output junit xml file
            instead of stdout.
        is_verbose (bool): Whether to print all test case outputs (by default,
            only failed test cases are printed).
        verbosity (int): Verbosity level, use 1 and higher for verbose.
        num_jobs (int): Number of threads to use to run test cases.
        timeout (int): Test driver timeout in seconds.
        filter_abi_bits (str): Override abi_bits filter for test policy.
        filter_host_type (str): Override host_type filter for test policy.

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
