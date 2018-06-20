"""Handle command line options.
"""

import optparse

from bdebuild.meta import optionsutil
from bdebuild.common import cmdlineutil


def get_option_parser():
    """Return option parser for command line options and arguments.

    Returns:
        OptionParser
    """

    usage = """eval $(bde_build_env.py [set|list|unset] [-i INSTALL_DIR]
                     [-c COMPILER] [-t UFID])

set:   set environment variables (default)
list:  list available compilers
unset: unset environment variables"""

    parser = optparse.OptionParser(usage=usage)

    options = [
        (('c', 'compiler'),
         {'type': 'string',
          'default': None,
          'help': 'compiler'}),
        (('i', 'install-dir'),
         {'type': 'string',
          'default': None,
          'help': 'install directory'}),
        (('debug-opt-keys',),
         {'type': 'string',
          'default': None,
          'help': 'debug rules in the opts files for the specified '
                  '(comma separated) list of opts keys'})
    ]
    options += optionsutil.get_ufid_cmdline_options()
    cmdlineutil.add_options(parser, options)

    return parser
