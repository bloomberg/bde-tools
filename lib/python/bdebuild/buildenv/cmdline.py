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

    usage = """eval $(bde_build_env.py [set|list|unset]
                     [-c COMPILER] 
                     [-t UFID]
                     [-b BUILD_DIR]
                     [-i INSTALL_DIR])

set  : set environment variables (default)
unset: unset environment variables

list : list available compilers in the following order:
    1. Compilers found in the user configuration file ($HOME/.bdecompilerconfig)
    2. Compilers found in the system configuration file ($BDE_ROOT/etc/bdecompilerconfig)
    3. gcc and clang compilers detected on $PATH"""

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
        (('b', 'build-dir'),
         {'type': 'string',
          'default': None,
          'help': 'build directory'})
    ]
    options += optionsutil.get_ufid_cmdline_options()
    cmdlineutil.add_options(parser, options)

    return parser
