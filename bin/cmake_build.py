#!/usr/bin/env python

from __future__ import print_function

import argparse
import errno
import os
import platform
import subprocess
import sys
import multiprocessing

####################################################################
# MSVC environment setup routines
if "Windows" == platform.system():
    try:
        import winreg # Python 3
    except ImportError:
        import _winreg as winreg # Python 2

def find_installdir(version):
    regLocation = '''SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\VS7'''
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, regLocation) as key:
        value, _ = winreg.QueryValueEx(key, version)
        return value

def find_vcvars(version):
    installdir = find_installdir(version)
    batpath = os.path.join(installdir, "VC")
    if float(version) >= 15:
        batpath = os.path.join(batpath, "Auxiliary", "Build")
    batpath = os.path.join(batpath, "vcvarsall.bat")

    if os.path.isfile(batpath):
        return batpath
    else:
        raise FileNotFoundError(batpath)

def get_msvc_env(version, bitness):
    result = {}

    bat_file = find_vcvars(version)
    arch = 'x86' if bitness == 32 else 'x86_amd64'
    process = subprocess.Popen([bat_file, arch, "&&", "set"],
                        stdout=subprocess.PIPE,
                        shell=True)
    (out, err) = process.communicate()

    if (sys.version_info > (3, 0)):
        out = out.decode('ascii')

    for line in out.split("\n"):
        if '=' not in line:
            continue
        line = line.strip()
        key, value = line.split('=', 1)
        result[key] = value

    return result
####################################################################

def enum(*sequential, **named):
    enums = dict(zip(sequential, range(len(sequential))), **named)
    return type('Enum', (), enums)

def replace_path_sep(path, sep = '/'):
    if not path:
        return path
    return path.replace(os.path.sep, sep)

def value_or_env(value, envVariableName, humanReadableName, required=False):
    ''' Get value which is either provided or from a fallback
        environment location
    '''
    ret = value if value else os.getenv(envVariableName)
    if required and not ret:
        raise RuntimeError(
            "{} was not specified using either a command-line\n"
            "argument or environment variable {}".format(humanReadableName,
                                                         envVariableName)
        )
    return ret

def cmake_module_path_or_env(value, envVariableName):
    ''' Evaluate the cmake modules path that provided ether in the command
    line, environment variable or guessed
    '''
    ret = value if value else os.getenv(envVariableName)
    if not ret:
        upd = os.path.dirname
        ret = os.path.join(upd(upd(os.path.realpath(__file__))), 'cmake')

    return ret

class JobsOptions:
    Type = enum('ALL_AVAILABLE', 'FIXED')
    def __init__(self, parsedArgs):
        if not parsedArgs:
            self.type = JobsOptions.Type.ALL_AVAILABLE
            self.count = None
        else:
            self.type = JobsOptions.Type.FIXED
            self.count = parsedArgs

class Options:
    def __init__(self, args):
        # Common flags that can appear in any command.
        self.build_dir = \
            replace_path_sep( \
                value_or_env(args.build_dir,
                             'BDE_CMAKE_BUILD_DIR',
                             'Build directory',
                             required=True))

        self.ufid = value_or_env(args.ufid,
                                 'BDE_CMAKE_UFID',
                                 'UFID',
                                 required = 'configure' in args.cmd)

        self.cmake_module_path = \
            replace_path_sep( \
                cmake_module_path_or_env(args.cmake_module_path,
                                         'CMAKE_MODULE_PATH'))
        self.prefix = \
            replace_path_sep( \
                value_or_env(args.prefix,
                             'PREFIX',
                             'Installation prefix'))

        self.dpkg_build = args.dpkg_build
        self.toolchain = value_or_env(args.toolchain,
                                      'BDE_CMAKE_TOOLCHAIN',
                                      'CMake toolchain file')

        self.refroot = \
            replace_path_sep( \
                value_or_env(args.refroot,
                             'DISTRIBUTION_REFROOT',
                             'Distribution refroot'))

        # Get the compiler from UPLID
        uplid = os.getenv('BDE_CMAKE_UPLID')
        uplid_comp = None
        if uplid:
            uplid_comp = '-'.join(uplid.split('-')[-2:])

        self.compiler = args.compiler if args.compiler else uplid_comp

        self.generator = args.generator if hasattr(args, 'generator') else None

        self.targets = args.targets
        self.tests = args.tests
        self.jobs = JobsOptions(args.jobs)
        self.timeout = args.timeout
        self.verbose = args.verbose

        self.install_dir = replace_path_sep(args.install_dir)

        self.install_prefix = \
            replace_path_sep( \
                value_or_env(args.install_prefix,
                             'PREFIX',
                             'Installation prefix',
                             required = 'install' in args.cmd))

        self.component = args.component

class Platform:
    msvcVersionMap = {
        'cl-18.00': (12, 2013),
        'cl-19.00': (14, 2015),
        'cl-19.10': (15, 2017),
    }

    @staticmethod
    def generator(options):
        host_platform = platform.system()
        if 'Windows' == host_platform:
            if not options.generator or options.generator == 'Ninja':
                return 'Ninja'

            if options.compiler in Platform.msvcVersionMap:
                bitness = ' Win64' if options.ufid and '64' in options.ufid else ''
                return 'Visual Studio {0[0]} {0[1]}{1}'.format(
                    Platform.msvcVersionMap[options.compiler], bitness)

        return options.generator if options.generator else 'Ninja'

    @staticmethod
    def generator_env(options):
        host_platform = platform.system()
        if 'Ninja' == Platform.generator(options) and 'Windows' == host_platform:
            return get_msvc_env(
                '{}.0'.format(Platform.msvcVersionMap[options.compiler][0]),
                64 if options.ufid and '64' in options.ufid else 32)
        else:
            return os.environ

    @staticmethod
    def generator_choices():
        host_platform = platform.system()
        if 'Windows' == host_platform:
            return ['msvc', 'Ninja']
        else:
            return ['Ninja', 'Unix Makefiles']

    @staticmethod
    def cmake_verbosity(verbose):
        if (0 == verbose):
            return 'QUIET'
        else:
            if (1 == verbose):
                return 'NORMAL'
            else:
                if (2 == verbose):
                    return 'VERBOSE'
        return 'VERY_VERBOSE'

    @staticmethod
    def generator_jobs_arg(gen, options):
        formatStrings = {}
        if gen.startswith('Visual Studio'):
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = '/maxcpucount'
            formatStrings[JobsOptions.Type.FIXED] = '/maxcpucount:{}'
        elif 'Makefiles' in gen:
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = '-j'
            formatStrings[JobsOptions.Type.FIXED] = '-j{}'
        else:
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = ''
            formatStrings[JobsOptions.Type.FIXED] = '-j{}'
        return formatStrings[options.jobs.type].format(options.jobs.count)

    @staticmethod
    def ctest_jobs_arg(options):
        if options.jobs.type == JobsOptions.Type.FIXED:
            return '-j{}'.format(options.jobs.count)
        elif options.jobs.type == JobsOptions.Type.ALL_AVAILABLE:
            return '-j{}'.format(multiprocessing.cpu_count())

        raise RuntimeError()

    @staticmethod
    def allBuildTarget(options):
        gen = Platform.generator(options)
        if gen.startswith('Visual Studio'):
            return 'ALL_BUILD'
        else:
            return 'all'

def run_command(cmd, cwd=None):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd)
    (out, err) = p.communicate()
    ret = p.returncode

    if ret:
        print("{}".format(out), file=sys.stdout)
        print("{}".format(err), file=sys.stderr)

    return ret


def wrapper():
    parser = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]))
    parser.add_argument('cmd', nargs='+', choices=['configure', 'build', 'install'])

    parser.add_argument('--build_dir')
    parser.add_argument('-j', '--jobs', type=int, default=0)
    parser.add_argument('-v', '--verbose', action='count', default=0)

    group = parser.add_argument_group('configure', 'Configuration options')
    group.add_argument('-u', '--ufid')
    group.add_argument('--cmake-module-path', help='Path to the Cmake modules with BDE build system')
    group.add_argument('--dpkg-build', action='store_true', help='Flag set for dpkg builds')
    group.add_argument('--toolchain', help='Path to the CMake toolchain file')
    group.add_argument('--refroot', help='Path to the distribution refroot')
    group.add_argument('--prefix', help='Prefix within distribution refroot')
    group.add_argument('--compiler', help='Compiler to use')

    genChoices = Platform.generator_choices()
    if len(genChoices) > 1:
        group.add_argument('-G', choices=genChoices, dest='generator')

    group = parser.add_argument_group('build', 'Build options')
    group.add_argument('--targets', nargs='+')
    group.add_argument('--tests', choices=['build', 'run'])

    group = parser.add_argument_group('test', 'Test options')
    group.add_argument('--timeout', type=int, default=120)

    group = parser.add_argument_group('install', 'Installation options')
    group.add_argument('--install_dir', help='Top level installation directory')
    group.add_argument('--install_prefix', help='Prefix withing installation directory')
    group.add_argument('--component')

    args = parser.parse_args()
    options = Options(args)

    if 'configure' in args.cmd:
        configure(options)

    if 'build' in args.cmd:
        build(options)

    if 'install' in args.cmd:
        install(options)
    return


def mkdir_if_not_present(path):
    try:
        os.makedirs(path)
    except OSError as exception:
        if exception.errno != errno.EEXIST:
            raise

def configure(options):
    """ Create build directory and generate build system.
    """
    mkdir_if_not_present(options.build_dir)
    # todo - detect generator change

    configure_cmd = ['cmake', os.getcwd(),
                     '-G' + Platform.generator(options),
                     '-DCMAKE_MODULE_PATH:PATH=' + options.cmake_module_path,
                     '-DUFID:STRING=' + options.ufid,
                     '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
                     '-DBDE_LOG_LEVEL=' + Platform.cmake_verbosity(options.verbose),
                     '-DBUILD_BITNESS=' + ('64' if '64' in options.ufid else '32')
                    ]
    if options.dpkg_build:
        configure_cmd.append('-DCMAKE_TOOLCHAIN_FILE=' +
            os.path.join(options.cmake_module_path, 'toolchains/dpkg/production.cmake'))
    else:
        if options.toolchain:
            if os.path.isfile(options.toolchain):
                configure_cmd.append('-DCMAKE_TOOLCHAIN_FILE=' + options.toolchain)
            elif os.path.isfile(os.path.join(options.cmake_module_path, options.toolchain + '.cmake')): 
                configure_cmd.append('-DCMAKE_TOOLCHAIN_FILE=' +
                    os.path.join(options.cmake_module_path, options.toolchain + '.cmake'))
            else:
                raise RuntimeError('Invalid toolchain file is specified: ' + options.toolchain )

    # Use of '+' is mandatory here.
    cmakePrefixPath = os.path.join(str(options.refroot or '/') +
                                   '/' +
                                   str(options.prefix or ''))
    configure_cmd.append('-DCMAKE_PREFIX_PATH:PATH=' + cmakePrefixPath)

    if options.refroot:
        configure_cmd.append('-DDISTRIBUTION_REFROOT:PATH=' + options.refroot)

    print('Configuration cmd:')
    print(' '.join(configure_cmd))
    subprocess.check_call(configure_cmd, cwd = options.build_dir,
        env=Platform.generator_env(options))

class CacheInfo:
    def __init__(self, build_dir):
        self.generator = None
        self.multiconfig = False
        self.build_type = None

        cacheFileName = os.path.join(build_dir, 'CMakeCache.txt')
        if not os.path.isfile(cacheFileName):
            raise RuntimeError('The project build configuration not found in ' + build_dir)

        for line in open(cacheFileName):
            if line.startswith('CMAKE_GENERATOR:'):
                self.generator = line.strip().split('=')[1]
            elif line.startswith('CMAKE_CONFIGURATION_TYPES:'):
                self.multiconfig = True
            elif line.startswith('CMAKE_BUILD_TYPE:'):
                self.build_type = line.strip().split('=')[1]


def build_target(target, build_dir, extra_args, environ):
    build_cmd = ['cmake', '--build', build_dir]
    if target:
        build_cmd += ['--target', target]

    # filter out empty extra_args or Ninja wont like it
    build_cmd += [arg for arg in extra_args if arg]

    subprocess.check_call(build_cmd, env=environ)

def build(options):
    """ Build
    """
    cache_info = CacheInfo(options.build_dir)
    options.generator = cache_info.generator
    env = Platform.generator_env(options)
    extra_args = []
    if cache_info.multiconfig:
        extra_args += ['--config', cache_info.build_type]
    extra_args += ['--', Platform.generator_jobs_arg(options.generator, options)]

    if options.verbose and options.generator == 'Ninja':
        extra_args += [ '-v' ]

    target_list = options.targets if options.targets else ['all']
    for target in target_list:
        if options.tests and not target.endswith('.t'):
            full_target = target + '.t'
        else:
            full_target = None if target == 'all' else target
        build_target(full_target, options.build_dir, extra_args, env)

    if 'run' == options.tests:
        test_cmd = ['ctest',
                    '--output-on-failure',
                    '--no-label-summary',
                    Platform.ctest_jobs_arg(options)
                    ]
        if cache_info.multiconfig:
            test_cmd += ['-C', cache_info.build_type]

        if options.timeout > 0:
            test_cmd += ['--timeout', str(options.timeout)]

        if 'all' not in target_list:
            test_pattern = "|".join(['(^)'+t+'($)' for t in options.targets])
            test_cmd += ['-L', test_pattern]

        subprocess.check_call(test_cmd, cwd = options.build_dir)

def install(options):
    """ Install
    """
    if not options.install_dir:
        raise RuntimeError('The project install requires install_dir')

    if not options.install_prefix:
        raise RuntimeError('The project install requires install_prefix')

    install_path = options.install_dir + options.install_prefix

    install_cmd = ['cmake',
                   '-DCMAKE_INSTALL_PREFIX=' + install_path]
    if options.component:
        install_cmd += ['-DCOMPONENT=' + options.component]

    install_cmd += ['-P', 'cmake_install.cmake']

    subprocess.check_call(install_cmd, cwd = options.build_dir)

if __name__ == '__main__':
    try:
        wrapper()
    except Exception as e:
        print("Error: {}".format(e), file=sys.stderr)
        sys.exit(1)
