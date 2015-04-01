import optparse
import os

from bdebld.meta import optionsutil
from bdebld.common import cmdlineutil


def get_options():

    usage = """eval `bde_setwafenv.py [list|unset] -i <root_install_dir> [-c <compiler> -t <ufid>]

list: list available compilers
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
    options, args = parser.parse_args()

    return options, args
