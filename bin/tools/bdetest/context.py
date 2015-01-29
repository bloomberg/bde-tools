from __future__ import print_function


class Context(object):
    """This class represents a test runner context.

    Context holds global references that are used by main and worker threads of
    the test runner.

    Attributes:
        options (Options): Test runner options.
        log (Log): Logging mechanism.
        policy (Policy): Test runner policy mechanism.

    """
    def __init__(self, **kw):
        self.options = kw['options']
        self.log = kw['log']
        self.policy = kw['policy']
