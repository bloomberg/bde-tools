"""Command-line utilties.
"""

import sys
import platform

from bdebld.meta import options


def make_ufid_from_cmdline_options(opts):
    """Create an Ufid from the specified command-line options.

    Args:
        options (dict): The specified command-line options.

    Returns:
        An Ufid object.
    """

    ufid_map = {
        'abi_bits': {'64': '64'},
        'build_type': {'debug': 'dbg', 'release': 'opt'},
        'assert_level': {'safe': 'safe', 'safe2': 'safe2'},
        'cpp11': {True: 'cpp11'},
        'noexception': {False: 'exc'},
        'library_type': {'shared': 'shr'}
        }

    flags = []
    for opt in ufid_map:
        attr = getattr(opts, opt, None)
        if attr is not None:
            if attr in ufid_map[opt]:
                flags.append(ufid_map[opt][attr])

    # always use mt
    flags.append('mt')

    return options.Ufid(flags)


def add_cmdline_options(ctx):
    """Add custom command-line options to an option context.

    Args:
        ctx (OptionContext): The option context.

    Returns:
        None
    """

    def is_64bit_system():
        """Return whether the system is 64-bit capable.

        We approximate the return value by first checking whether we are
        running the 64-bit python interpreter.  If so, then we are done.
        Otherwise, we match the current machine type with a set of known 64-bit
        machine types.
        """

        if sys.maxsize > 2**32:
            return True

        return platform.machine().lower()  \
            in ('amd64', 'x86_64', 'sun4v', 'ppc64')

    configure_opts = (
        (('a', 'abi-bits'),
         {'type': 'choice',
          'default': '64' if is_64bit_system() else '32',
          'choices': ('32', '64'),
          'help': '32 or 64 [default: %default]'}),
        (('b', 'build-type'),
         {'type': 'choice',
          'default': 'debug',
          'choices': ('release', 'debug'),
          'help': "the type of build to produce: 'debug' or 'release' "
                  "[default: %default]"}),
        (('t', 'library-type'),
         {'type': 'choice',
          'default': 'static',
          'choices': ('static', 'shared'),
          'help': "the type of libraries to build: 'shared' or 'static' "
                  "[default: %default]"}),
        (('assert-level',),
         {'type': 'choice',
          'default': 'none',
          'choices': ('none', 'safe', 'safe2'),
          'help': "bsls_assert level: 'none', 'safe' or 'safe2' "
                  "[default: %default]"}),
        (('noexception',),
         {'action': 'store_true',
          'default': False,
          'help': 'disable exception support'}),
        (('cpp11',),
         {'action': 'store_true',
          'default': False,
          'help': 'enable C++11 support'}),
        (('verify',),
         {'action': 'store_true',
          'default': False,
          'help': 'Perform additional checks to verify '
                  'repository structure.'}),
        (('t', 'ufid'),
         {'type': 'string',
          'default': None,
          'help': 'the Unified Platform ID (UFID) identifying the build '
                  'configuration (e.g., dbg_mt_exc). '
                  'See https://github.com/bloomberg/bde-tools/wiki/'
                  'BDE-Style-Repository#ufid for a list of valid ufids. '
                  'Note that specifying a UFID will overwrite other build '
                  'configuration options such as --library_type.'}),
        (('debug-opt-keys',),
         {'type': 'string',
          'default': None,
          'help': 'debug rules in the opts files for the specified '
                  '(comma separated) list of opts keys'}),
        (('lib-suffix',),
         {'type': 'string',
          'default': '',
          'help': 'add a suffix to the names of the package group library '
                  'files being built'}),
        (('install-flat-include',),
         {'action': 'store_true',
          'default': False,
          'help': 'install all headers into $PREFIX/include instead of '
                  '$PREFIX/include/<package_group>'}),
        (('install-lib-dir',),
         {'type': 'string',
          'default': 'lib',
          'help': 'the name of the directory under $PREFIX where '
                  'library files are installed [default: %default]'}),
        )

    configure_group = ctx.get_option_group('configure options')

    def add_opts(grp, opts):
        for opt in opts:
            opt_strings = ['-' + a if len(a) == 1 else '--' + a
                           for a in opt[0]]
            grp.add_option(*opt_strings, **opt[1])

    add_opts(configure_group, configure_opts)

    # Set the upper bound of the default number of jobs to 24
    jobs = ctx.parser.get_option('-j').default
    if jobs > 24:
        jobs = 24
        ctx.parser.remove_option('-j')
        ctx.parser.add_option('-j', '--jobs',
                              dest='jobs',
                              default=jobs,
                              type='int',
                              help='amount of parallel jobs (%r)' % jobs)

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
