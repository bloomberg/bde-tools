import re
import os


class RawOptions(object):
    class Option:
        '''Empty class representing an option read directly from on disk.
           Attributes get dynamically added.'''

        def __repr__(self):
            return '%s %s %s %s %s' % (self.modifier,
                                       self.platform,
                                       self.config,
                                       self.key,
                                       self.value)

    def __init__(self):
        self.options = []

        # Store all lines in an array. Each element of the array contains a
        # pair of (line, option), where line is a string and a option is a
        # RawOption.Option if the line represents an option rule, or None
        # otherwise.
        self.all_lines = []

    # Option parsing regular expressions
    OPT_LINE_RE = re.compile(r'''^
                                 (?P<mod>!!|--|\+\+)?       # modifier
                                 \s*
                                 (?P<plat>\S+)              # platform
                                 \s+
                                 (?P<conf>\S+)              # configuration
                                 \s+
                                 (?P<key>\S+)               # key name
                                 \s*=\s*
                                 (?P<val>.*?)               # value
                                 (?P<cont>\\)?              # line continuation
                                 $''',
                             re.VERBOSE)

    OPT_COMMENT_OR_EMTPY_RE = re.compile(r'^\s*([#].*)?$')

    OPT_CONTINUE_RE = re.compile(r'^(?P<val>.*?)(?P<cont>\\)?$')

    OPT_INLINE_COMMAND_RE = re.compile(r'\\"`([^`]+)`\\"')

    def read_handle(self, handle):
        continuation = False
        got_line = False

        for line in handle:
            if not continuation:
                option = RawOptions.Option()
                m = RawOptions.OPT_LINE_RE.match(line)
                if RawOptions.OPT_COMMENT_OR_EMTPY_RE.match(line):
                    got_line = False
                    self.all_lines.append((line.rstrip(), None))
                else:
                    m = RawOptions.OPT_LINE_RE.match(line)
                    if m:
                        got_line = True
                        option.modifier = m.group('mod')
                        option.platform = m.group('plat')
                        option.config = m.group('conf')
                        option.key = m.group('key')
                        option.value = m.group('val')
                        continuation = not m.group('cont') is None
                    else:
                        assert False, '"%s" is not valid!' % line
            else:
                # previous line continues

                m = RawOptions.OPT_CONTINUE_RE.match(line)
                assert(m)
                assert(got_line)

                option.value += m.group('val')
                continuation = not m.group('cont') is None

            if got_line and not continuation:
                option.value = option.value.strip()
                self.options.append(option)
                self.all_lines.append((line, option))

    def read(self, opts_file):
        '''Read the opts file, extract build options and store them.'''

        try:
            with open(opts_file) as opts_handle:
                self.read_handle(opts_handle)
        except IOError:
            # skip if the option file can't be found
            # (IOError - 2.x/3.x, FileNotFoundError - 3.x)
            # print >>sys.stderr, "Warning: can't read %s" % opts_file
            pass


# The defualt compiler is set by an option with the key 'BDE_COMPILER_FLAG'. If
# this option exist any uplid having the value 'def' in its compiler field is
# equivalent to the value of the said option.
DEFAULT_COMPILER = None


class Options(object):

    '''Parser for the BDE build opts files.'''

    OPT_INLINE_COMMAND_RE = re.compile(r'\\"`([^`]+)`\\"')
    OPT_INLINE_COMMAND_RE2 = re.compile(r'\$\(shell([^\)]+)\)')

    class Option:
        '''Empty class representing the option value.
        Attributes get dynamically added.'''
        pass

    def __init__(self, option_mask):
        self.options = {}
        self.option_mask = option_mask

    def want_option(self, option):
        '''Find out if option matches the current platform.'''

        ignore_keys = ('XLC_INTERNAL_PREFIX1',
                       'XLC_INTERNAL_PREFIX2',
                       'AIX_GCC_PREFIX',
                       'SUN_CC_INTERNAL_PREFIX',
                       'SUN_GCC_INTERNAL_PREFIX',
                       'LINUX_GCC_PREFIX',
                       'WINDOWS_CC_PREFIX',
                       'RETRY_ON_SIGNAL')

        if option.key in ignore_keys:
            return False

        option_mask = OptionMask(Uplid.from_platform_str(option.platform),
                                 Ufid.from_config_str(option.config))
        return option_mask.match(self.option_mask)

    def _store_raw_option(self, option, ctx, debug_opt_keys=None):
        '''Store the option value.'''

        want_option = self.want_option(option)

        if want_option:
            mc = Options.OPT_INLINE_COMMAND_RE.search(option.value)
            if mc:
                v = option.value
                cmd_out = ctx.cmd_and_log(mc.group(1)).rstrip()
                option.value = '%s"%s"%s' % (v[:mc.start(1) - 3],
                                             cmd_out,
                                             v[mc.end(1) + 3:])

            mc2 = Options.OPT_INLINE_COMMAND_RE2.match(option.value)
            if mc2:
                cmd_out = ctx.cmd_and_log(mc2.group(1)).rstrip()
                option.value = cmd_out

            if option.modifier == '--':
                # prepend
                if option.key in self.options:
                    self.options[option.key] = option.value \
                        + ' ' + self.options[option.key]
                else:
                    self.options[option.key] = option.value
            elif option.modifier == '!!':

                if option.key == 'BDE_COMPILER_FLAG':
                    global DEFAULT_COMPILER
                    DEFAULT_COMPILER = option.value

                # override
                self.options[option.key] = option.value
            else:                         # option.modifier in ('', '++')
                # append
                if option.key in self.options and self.options[option.key]:
                    self.options[option.key] += ' ' + option.value
                else:
                    self.options[option.key] = option.value

        if debug_opt_keys:
            if option.key in debug_opt_keys:
                print "%s: %s" % (("Accept" if want_option else "Ignore"),
                                  option)
                if want_option:
                    print "*New value: %s\n" % self.options[option.key]

    def read(self, raw_options, ctx, debug_opt_keys=None):
        for raw_option in raw_options:
            self._store_raw_option(raw_option, ctx, debug_opt_keys)

    def evaluate(self):
        '''Evaluate stored options.'''
        for opt in self.options.keys():
            self.options[opt] = self.evaluate_option(opt)

    def evaluate_option(self, opt):
        if opt in self.options:
            self.options[opt] = re.sub(r'(\$\((\w+)\))',
                                       lambda m:
                                           self.evaluate_option(m.group(2)),
                                       self.options[opt])
            return self.options[opt]
        else:
            return ''


class Ufid(object):
    # The order specified by the first element in the tuples in the VALID_FLAGS
    # dictionary must result in the following literal dpkg production ufids
    # when applied to the appropriate combinations of flags:
    #     opt_exc_mt
    #     opt_exc_mt_64
    #     opt_exc_mt
    #     opt_exc_mt_safe
    #     dbg_exc_mt
    #     dbg_exc_mt_safe
    #     opt_dbg_exc_mt
    #     opt_dbg_exc_mt_safe
    #     opt_exc_mt_64
    #     opt_exc_mt_64_safe
    #     dbg_exc_mt_64
    #     dbg_exc_mt_64_safe
    #     opt_dbg_exc_mt_64
    #     opt_dbg_exc_mt_64_safe
    #     opt_exc_mt_64_pic
    #     dbg_exc_mt_64_pic
    #     opt_exc_mt_shr
    #     opt_exc_mt_64_shr

    FRONT  = 0
    MIDDLE = 50
    BACK   = 100
    # allowed UFID flags: flag -> flag's sort order and description
    VALID_FLAGS = {
        'dbg':     (FRONT  + 1, 'Build with debugging information'           ),
        'opt':     (FRONT,      'Build optimized'                            ),
        'exc':     (MIDDLE,     'Exception support'                          ),
        'mt':      (MIDDLE + 1, 'Multithread support'                        ),
        'ndebug':  (MIDDLE + 2, 'Build with NDEBUG defined'                  ),
        '64':      (BACK   - 5, 'Build for 64-bit architecture'              ),
        'safe2':   (BACK   - 4,
                  'Build safe2 (paranoid and binary-incompatible) libraries' ),
        'safe':    (BACK   - 3, 'Build safe (paranoid) libraries'            ),
        'shr':     (BACK   - 2, 'Build dynamic libraries'                    ),
        'pic':     (BACK   - 1, 'Build static PIC libraries'                 ),
        # 'rtd':     (BACK   + 5, 'Build with dynamic MSVC runtime'          ),
        # 'ins':     (BACK   + 0, 'Build with Insure++'                      ),
        # 'pure':    (BACK   + 1, 'Build with Purify (no windows)'           ),
        # 'pure':    (BACK   + 2, 'Build with Purify (windows)'              ),
        # 'purecov': (BACK   + 3, 'Build with Pure Coverage'                 ),
        # 'qnt':     (BACK   + 4, 'Build with Quantify'                      ),
        # 'win':     (BACK   +11, 'Use GUI for instrumenting tools'          ),
        # 'stlport': (BACK   + 6, 'Build with STLPort on Sun'                ),
        'cpp11':   (BACK   +12,
                             'Build with support for C++11 (C++0x) features' ),
    }

    def __init__(self, flags):
        self.ufid = set()

        for f in flags:
            self.add_flag(f)

    def add_flag(self, flag):
        self.ufid.add(flag)

    @classmethod
    def is_valid(cls, ufid):
        return all(f in cls.VALID_FLAGS for f in ufid)

    @classmethod
    def from_config_str(cls, config_str):

        flags = []
        for f in config_str.split('_'):
            if f:
                flags.append(f)

        return Ufid(flags)

    def match(self, other):
        # is other a superset of this ufid
        return self.ufid <= other.ufid

    def __str__(self):
        flags = [flag for flag in self.ufid]
        flags.sort(key=lambda f: self.VALID_FLAGS[f][0])
        return '_'.join(flags)


class Uplid(object):
    def __init__(self, os_type, os_name, cpu_type, os_ver, comp_type,
                 comp_ver):
        self.uplid = {
            'os_type': os_type,
            'os_name':  os_name,
            'cpu_type': cpu_type,
            'os_ver':   os_ver,
            'comp_type': comp_type,
            'comp_ver': comp_ver
            }

    @classmethod
    def from_platform_str(cls, platform_str):

        parts = platform_str.split('-')
        parts.extend([''] * (6 - len(parts)))
        (os_type,
         os_name,
         cpu_type,
         os_ver,
         comp_type,
         comp_ver) = (p.lower() for p in parts)

        uplid = cls(os_type, os_name, cpu_type, os_ver, comp_type, comp_ver)

        return uplid

    def __eq__(self, other):
        return (isinstance(other, self.__class__) and
                self.uplid == other.uplid)

    def __ne__(self, other):
        return not self.__eq__(other)

    def __str__(self):
        attrs = ['os_type', 'os_name', 'cpu_type', 'os_ver', 'comp_type',
                 'comp_ver']
        return '-'.join([self.uplid[a] for a in attrs])

    def match(self, other):
        if not match_str(self.uplid['os_type'], other.uplid['os_type']):
            return False
        if not match_str(self.uplid['os_name'], other.uplid['os_name']):
            return False
        if not match_str(self.uplid['cpu_type'], other.uplid['cpu_type']):
            return False
        if not match_ver(self.uplid['os_ver'], other.uplid['os_ver']):
            return False

        if not match_str(self.uplid['comp_type'], other.uplid['comp_type']):
            global DEFAULT_COMPILER
            if not (self.uplid['comp_type'] == 'def' and
                    DEFAULT_COMPILER == other.uplid['comp_type']):
                return False

        if not match_ver(self.uplid['comp_ver'], other.uplid['comp_ver']):
            return False
        return True


class OptionMask(object):
    def __init__(self, uplid, ufid):
        self.uplid = uplid
        self.ufid = ufid

    def match(self, other):
        return self.uplid.match(other.uplid) and self.ufid.match(other.ufid)


def match_str(a, b):
    if not a or a == '*' or not b or b == '*':
        return True
    return a == b


def match_ver(a, b):
    if not a or a == '*' or not b or b == '*':
        return True  # allow any version

    aver = a.split('.')
    bver = b.split('.') if b else []

    bver.extend(['0'] * (len(aver) - len(bver)))  # extend bver with zeros
    assert(len(aver) <= len(bver))

    vers = list(zip(aver, bver))
    # major = vers.pop(0)  # major version needs to match exactly

    # if not match_subver(*major, exact = True):
    #     return False

    for subv in vers:
        if match_subver_less(*subv):
            return True

        if not match_subver(*subv):
            return False

    return True


def match_subver(a, b, exact=False):
    if a == '*':
        return True

    if not exact and a.isdigit() and b.isdigit():
        return int(a) <= int(b)

    # string or exact match
    return a == b


def match_subver_less(a, b):
    return a.isdigit() and b.isdigit() and int(a) < int(b)


def get_linux_osinfo(ctx):
    os_type = 'unix'
    os_name = 'linux'
    os_ver = os.uname()[2]
    # os_ver can contain a '-flavor' part, strip it
    os_ver = os_ver.split('-', 1)[0]

    return (os_type, os_name, os_ver)


def get_aix_osinfo(ctx):
    os_type = 'unix'
    os_name = 'aix'
    uname = os.uname()
    os_ver = '%s.%s' % (uname[3], uname[2])

    return (os_type, os_name, os_ver)


def get_sunos_osinfo(ctx):
    os_type = 'unix'
    os_name = 'sunos'
    uname = os.uname()
    os_ver = uname[2]

    return (os_type, os_name, os_ver)


def get_darwin_osinfo(ctx):
    os_type = 'unix'
    os_name = 'darwin'
    os_ver = os.uname()[2]
    # os_ver can contain a '-flavor' part, strip it
    os_ver = os_ver.split('-', 1)[0]

    return (os_type, os_name, os_ver)


def get_windows_osinfo(ctx):
    os_type = 'windows'
    os_name = 'windows_nt'
    import platform
    uname = platform.uname()
    os_ver = '.'.join(uname[3].split('.')[0:2])

    return (os_type, os_name, os_ver)

# ----------------------------------------------------------------------------
# Copyright (C) 2013-2014 Bloomberg Finance L.P.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
# ----------------------------- END-OF-FILE ----------------------------------
