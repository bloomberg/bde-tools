import logging
import sys
import threading
import time
import xml.etree.ElementTree as ET


class _TextRecorder(object):
    """Record test result to stdout.
    """

    def __init__(self, opts, logger):
        self._opts = opts
        self._logger = logger

    def start(self, case):
        self._logger.debug('CASE %2d: START' % case)

    def success(self, case, rc, out):
        if self._opts.is_verbose:
            self._logger.info('CASE %2d: SUCCESS (rc %s)\n%s' %
                              (case, rc, out))
        else:
            self._logger.info('CASE %2d: SUCCESS' % case)

    def failure(self, case, rc, out):
        self._logger.info('CASE %2d: (rc %s)\n%s' % (case, rc, out))

    def skip(self, case):
        self._logger.info('CASE %2d: SKIP' % case)

    def timeout(self, case):
        self._logger.info('CASE %2d: TIMEOUT (timeout was set to %ds)' %
                          (case, self._opts.timeout))

    def flush(self):
        pass


class _JunitRecorder(object):
    """Record test results to Junit xml.
    """

    def __init__(self, opts):
        self._opts = opts
        # test results format:
        # { 1: {'start': <start_time>, 'end': <end_time>, 'rc': <return code>,
        #         'out': <out> } }
        self._results = {}
        self._skipped = []
        self._timedout = []
        self._start_times = {}
        self._lock = threading.Lock()

    def start(self, case):
        with self._lock:
            # Note that some test cases that do not exist are started due to
            # the nature of threaded test case runs.  These extra cases are
            # ignored.
            self._start_times[case] = time.time()

    def success(self, case, rc, out):
        with self._lock:
            self._results[case] = {'start': self._start_times[case],
                                   'end': time.time(),
                                   'rc': rc,
                                   'out': out}

    def failure(self, case, rc, out):
        with self._lock:
            self._results[case] = {'start': self._start_times[case],
                                   'end': time.time(),
                                   'rc': rc,
                                   'out': out}

    def timeout(self, case):
        with self._lock:
            self._timedout.append(case)

    def skip(self, case):
        with self._lock:
            self._skipped.append(case)

    def _write_out_xml(self):
        # Some helpful information on the Junit format:
        # http://stackoverflow.com/questions/4922867/
        # junit-xml-format-specification-that-hudson-supports
        suite = ET.Element('testsuite')
        ET.SubElement(suite, 'properties')
        suite.set('name', self._opts.component_name)

        properties = suite.find('properties')
        verbosityProperty = ET.SubElement(properties, 'property')
        verbosityProperty.set('name', 'verbosity')
        verbosityProperty.set('value', '%d' % self._opts.verbosity)

        timeoutProperty = ET.SubElement(properties, 'property')
        timeoutProperty.set('name', 'timeout')
        timeoutProperty.set('value', '%d' % self._opts.timeout)

        cases = sorted(self._skipped + self._results.keys())

        for case in cases:
            testcase = ET.SubElement(suite, 'testcase')
            testcase.set('name', '%d' % case)
            if case in self._results:
                case_result = self._results[case]
                delta = case_result['end'] - case_result['start']
                testcase.set('time', '%.6f' % delta)
                systemout = ET.SubElement(testcase, 'system-out')
                systemout.text = case_result['out']
                if case_result['rc'] == 0:
                    testcase.set('status', 'passed')
                else:
                    testcase.set('status', 'failed')
                    failure = ET.SubElement(testcase, 'failure')
                    if case in self._timedout:
                        failure.set('type', 'timeout')
                    else:
                        failure.set('type', 'test failure')
                    failure.set('message', 'rc: %d' % case_result['rc'])
            else:
                ET.SubElement(testcase, 'skipped')

        tree = ET.ElementTree(suite)
        tree.write(self._opts.junit_file_path)

    def flush(self):
        with self._lock:
            self._write_out_xml()


class Log(object):
    """This class represents a mechanism to record the status of the test run.

    An object of this type can be used to record when a test case started,
    succeeded, or failed.  If the options passed into the initializer has the
    ``junit_file_path`` attribute set, the object records the status to the
    junit xml file pointed to by that attribute; otherwise, the object writes
    the status messages directly to stdout.

    """

    def __init__(self, opts):
        """Initialize the object with specified options.

        Args:
            opts (Options): Test runner options.
        """
        self._opts = opts
        self._configure_logger()
        if self._opts.junit_file_path:
            self._recorder = _JunitRecorder(self._opts)
        else:
            self._recorder = _TextRecorder(self._opts, self._logger)

    def _configure_logger(self):
        self._logger = logging.getLogger()
        datefmt = '%H:%M:%S'
        if self._opts.is_debug:
            level = logging.DEBUG
            format_ = '[%(asctime)s] [%(threadName)s] %(message)s'
        else:
            level = logging.INFO
            format_ = '[%(asctime)s] %(message)s'

        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(format_, datefmt)
        handler.setFormatter(formatter)
        self._logger.addHandler(handler)
        self._logger.setLevel(level)

    def record_start(self, case):
        self._recorder.start(case)

    def record_skip(self, case):
        self._recorder.skip(case)

    def record_timeout(self, case):
        self._recorder.timeout(case)

    def record_success(self, case, rc, out):
        self._recorder.success(case, rc, out)

    def record_failure(self, case, rc, out):
        self._recorder.failure(case, rc, out)

    def record_exception(self, case, e):
        self._logger.info('CASE %2d: PYTHON EXCEPTION (%s)' % str(e))

    def info(self, msg):
        self._logger.info(msg)

    def info_case(self, case, msg):
        self._logger.info('CASE %2d: %s' % (case, msg))

    def debug(self, msg):
        self._logger.debug(msg)

    def debug_case(self, case, msg):
        self._logger.debug('CASE %2d: %s' % (case, msg))

    def flush(self):
        self._recorder.flush()
