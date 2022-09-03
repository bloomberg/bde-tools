#!/usr/bin/env python3.8


import argparse
import collections
import errno
import json
import multiprocessing
import os
import platform
import re
import shutil
import subprocess
import sys

PLATFORM_SYSTEM = platform.system()


def is_gnu_windows_shell():
    return PLATFORM_SYSTEM.startswith(
        "CYGWIN_NT"
    ) or PLATFORM_SYSTEM.startswith("MSYS_NT")


GNU_WINDOWS_HOST = is_gnu_windows_shell()

WINDOWS_HOST = "Windows" == PLATFORM_SYSTEM

LINUX_HOST = "Linux" == PLATFORM_SYSTEM

SUNOS_HOST = "SunOS" == PLATFORM_SYSTEM

AIX_HOST = "AIX" == PLATFORM_SYSTEM

APPLE_HOST = "Darwin" == PLATFORM_SYSTEM


def static_vars(**kwargs):
    def decorate(func):
        for k in kwargs:
            setattr(func, k, kwargs[k])
        return func

    return decorate


@static_vars(memoized=None)
def get_host_bits():

    if get_host_bits.memoized:
        return get_host_bits.memoized

    # If Python itself is 64 bits, we are
    if sys.maxsize > 2 ** 32:
        get_host_bits.memoized = 64
    elif WINDOWS_HOST or GNU_WINDOWS_HOST or LINUX_HOST:
        machine = platform.machine().lower()
        print("Machine: {}".format(machine))
        get_host_bits.memoized = (
            64 if machine in ["amd64", "x86_64", "arm64"] else 32
        )

    elif APPLE_HOST:  # All supported host Apple operating systems are 64 bit
        get_host_bits.memoized = 64
    else:
        pp = platform.platform()
        re64 = re.compile(r"(-|^)64bit(-|$)", re.IGNORECASE)

        if SUNOS_HOST or AIX_HOST:
            get_host_bits.memoized = 64 if re64.search(pp) else 32

        elif re64.search(pp):
            # We assume unknown OS will have good `platform.platform()`
            get_host_bits.memoized = 64

        else:
            sys.stderr.write(
                "WARNING: Could not determine host bitness, will use 32.\n"
            )
            get_host_bits.memoized = 32
    return get_host_bits.memoized


if WINDOWS_HOST:
    try:
        import winreg  # Python 3
    except ImportError:
        import winreg as winreg  # Python 2


def find_installdir(version):
    vswhere_path = os.path.join(
        os.path.dirname(os.path.realpath(__file__)), "vswhere.exe"
    )
    output = subprocess.check_output(
        [vswhere_path, "-prerelease", "-legacy", "-format", "json"]
    )
    compilers = json.loads(output.decode("ascii", errors="ignore"))
    for cl in compilers:
        if cl["installationVersion"].startswith(str(version)):
            return cl["installationPath"]
    return None


def find_vcvars(version):
    installdir = find_installdir(version)
    if not installdir:
        raise FileNotFoundError("Could not find MSVC {}.".format(version))

    batpath = os.path.join(installdir, "VC")
    if version >= 15:
        batpath = os.path.join(batpath, "Auxiliary", "Build")
    batpath = os.path.join(batpath, "vcvarsall.bat")

    if os.path.isfile(batpath):
        return batpath
    else:
        raise FileNotFoundError(batpath)


def get_msvc_env(version, bitness):
    result = {}

    bat_file = find_vcvars(version)
    if get_host_bits() == 64:
        arch = "amd64" if bitness == 64 else "amd64_x86"
    else:
        arch = "x86" if bitness == 32 else "x86_amd64"
    process = subprocess.Popen(
        [bat_file, arch, "&&", "set"], stdout=subprocess.PIPE, shell=True
    )
    (out, err) = process.communicate()

    if sys.version_info > (3, 0):
        out = out.decode("ascii", errors="ignore")

    for line in out.split("\n"):
        if "=" not in line:
            continue
        line = line.strip()
        key, value = line.split("=", 1)
        result[key] = value

    return result


####################################################################


def enum(*sequential, **named):
    enums = dict(list(zip(sequential, list(range(len(sequential))))), **named)
    return type("Enum", (), enums)


def replace_path_sep(path, sep="/"):
    if not path:
        return path
    return path.replace(os.path.sep, sep)


def value_or_env(value, envVariableName, humanReadableName, required=False):
    """Get value which is either provided or from a fallback
    environment location
    """
    ret = value if value else os.getenv(envVariableName)
    if required and not ret:
        raise RuntimeError(
            "{} was not specified using either a command-line\n"
            "argument or environment variable {}".format(
                humanReadableName, envVariableName
            )
        )
    return ret


def cmake_module_path_or_env(value, envVariableName):
    """Evaluate the cmake modules path that provided either in the command
    line, environment variable or guessed
    """
    ret = value if value else os.getenv(envVariableName)
    if not ret:
        upd = os.path.dirname
        ret = os.path.join(upd(upd(os.path.realpath(__file__))), "cmake")

    return ret


class JobsOptions:
    Type = enum("ALL_AVAILABLE", "FIXED")

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
        self.build_dir = replace_path_sep(
            value_or_env(
                args.build_dir,
                "BDE_CMAKE_BUILD_DIR",
                "Build directory",
                required=True,
            )
        )

        self.ufid = value_or_env(
            args.ufid,
            "BDE_CMAKE_UFID",
            "UFID",
            required="configure" in args.cmd,
        )

        self.cmake_module_path = replace_path_sep(
            cmake_module_path_or_env(
                args.cmake_module_path, "CMAKE_MODULE_PATH"
            )
        )
        self.prefix = replace_path_sep(
            value_or_env(args.prefix, "PREFIX", "Installation prefix")
        )

        if not self.prefix:
            self.prefix = "/opt/bb"

        self.dpkg_build = args.dpkg_build
        self.clean = args.clean
        self.toolchain = value_or_env(
            args.toolchain, "BDE_CMAKE_TOOLCHAIN", "CMake toolchain file"
        )

        self.refroot = replace_path_sep(
            value_or_env(
                args.refroot, "DISTRIBUTION_REFROOT", "Distribution refroot"
            )
        )

        # Get the compiler from UPLID
        uplid = os.getenv("BDE_CMAKE_UPLID")
        uplid_comp = None
        if uplid:
            uplid_comp = "-".join(uplid.split("-")[-2:])

        self.compiler = args.compiler if args.compiler else uplid_comp
        self.test_regex = args.regex
        self.wafstyleout = args.wafstyleout
        self.cpp11_verify_no_change = args.cpp11_verify_no_change

        self.generator = args.generator if hasattr(args, "generator") else None

        self.targets = args.targets
        self.tests = args.tests
        self.jobs = JobsOptions(args.jobs)
        self.timeout = args.timeout
        self.xml_report = args.xml_report
        self.keep_going = args.keep_going
        self.verbose = args.verbose

        self.install_dir = replace_path_sep(
            value_or_env(
                args.install_dir,
                "BDE_CMAKE_INSTALL_DIR",
                "Install directory",
                required="install" in args.cmd,
            )
        )

        self.component = args.component


class Platform:
    MsvcVersion = collections.namedtuple("MsvcVersion", ["year", "version"])

    msvcVersionMap = {
        "msvc-2022": MsvcVersion(2022, 17),
        "msvc-2019": MsvcVersion(2019, 16),
        "msvc-2017": MsvcVersion(2017, 15),
        "msvc-2015": MsvcVersion(2015, 14),
        "msvc-2013": MsvcVersion(2013, 12),
    }

    @staticmethod
    def generator(options):
        host_platform = platform.system()
        if WINDOWS_HOST:
            if not options.generator or options.generator == "Ninja":
                return ["Ninja"]

            if options.compiler in Platform.msvcVersionMap:
                msvcInfo = Platform.msvcVersionMap[options.compiler]
                generator = [
                    "Visual Studio {} {}".format(
                        msvcInfo.version, msvcInfo.year
                    )
                ]

                is64 = options.ufid and "64" in options.ufid
                if msvcInfo.version < 16:
                    if is64:
                        generator[0] += " Win64"
                else:
                    generator += ["-A", "x64" if is64 else "Win32"]
                return generator

        return [options.generator] if options.generator else ["Ninja"]

    @staticmethod
    def generator_env(options):
        if WINDOWS_HOST and "Ninja" == Platform.generator(options)[0]:
            return get_msvc_env(
                Platform.msvcVersionMap[options.compiler].version,
                64 if options.ufid and "64" in options.ufid else 32,
            )
        else:
            return os.environ

    @staticmethod
    def generator_choices():
        if WINDOWS_HOST:
            return ["msvc", "Ninja"]
        else:
            return ["Ninja", "Unix Makefiles"]

    @staticmethod
    def cmake_verbosity(verbose):
        if 0 == verbose:
            return "QUIET"
        else:
            if 1 == verbose:
                return "NORMAL"
            else:
                if 2 == verbose:
                    return "VERBOSE"
        return "VERY_VERBOSE"

    @staticmethod
    def generator_jobs_arg(gen, options):
        formatStrings = {}
        if gen.startswith("Visual Studio"):
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = "/maxcpucount"
            formatStrings[JobsOptions.Type.FIXED] = "/maxcpucount:{}"
        elif "Makefiles" in gen:
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = "-j"
            formatStrings[JobsOptions.Type.FIXED] = "-j{}"
        else:
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = ""
            formatStrings[JobsOptions.Type.FIXED] = "-j{}"
        return formatStrings[options.jobs.type].format(options.jobs.count)

    @staticmethod
    def ctest_jobs_arg(options):
        if options.jobs.type == JobsOptions.Type.FIXED:
            return "-j{}".format(options.jobs.count)
        elif options.jobs.type == JobsOptions.Type.ALL_AVAILABLE:
            return "-j{}".format(multiprocessing.cpu_count())

        raise RuntimeError()

    @staticmethod
    def allBuildTarget(options):
        gen = Platform.generator(options)
        if gen[0].startswith("Visual Studio"):
            return "ALL_BUILD"
        else:
            return "all"


def run_command(cmd, cwd=None):
    p = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd
    )
    (out, err) = p.communicate()
    ret = p.returncode

    if ret:
        print("{}".format(out), file=sys.stdout)
        print("{}".format(err), file=sys.stderr)

    return ret


def wrapper():
    parser = argparse.ArgumentParser(prog=os.path.basename(sys.argv[0]))
    parser.add_argument(
        "cmd", nargs="+", choices=["configure", "build", "install"]
    )

    parser.add_argument(
        "--build_dir",
        help="Path to the build directory. If not specified, "
        "the build system generates the name using the "
        "current platform, compiler, and ufid. The generated "
        "build directory looks like this: "
        '"./_build/unix-linux-x86_64-2.6.32-gcc-5.4.0-opt_exc_mt_cpp11"',
    )

    parser.add_argument(
        "--no_force_group_writes",
        action="store_true",
        help="Do not use umask to allow group writes."
        "The default is to allow group writes to simplify group build area"
        "cleanups.",
    )

    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=0,
        help="Specify number of jobs to run in parallel.",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="Produce verbose output (including compiler " "command lines).",
    )

    parser.add_argument(
        "--prefix",
        default="/opt/bb",
        help="The path prefix in which to look for "
        'dependencies for this build. If "--refroot" is '
        "specified, this prefix is relative to the "
        'refroot (default="/opt/bb").',
    )

    group = parser.add_argument_group(
        "configure", 'Options for the "configure" command'
    )
    group.add_argument(
        "-u",
        "--ufid",
        help='Unified Flag IDentifier (e.g. "opt_exc_mt"). See '
        "bde-tools documentation.",
    )

    group.add_argument(
        "--cmake-module-path",
        help="Path to the Cmake modules defining the BDE build " "system.",
    )

    group.add_argument(
        "--dpkg-build",
        action="store_true",
        help="Use the production compiler and install layout "
        "used by  Bloomberg's dpkg builds.",
    )

    group.add_argument("--toolchain", help="Path to the CMake toolchain file.")

    group.add_argument(
        "--clean",
        action="store_true",
        help="Clean target directory before configure.",
    )

    group.add_argument(
        "--refroot", help='Path to the distribution refroot (default="/")'
    )

    group.add_argument(
        "--compiler",
        help="Specify version of MSVC (Windows only). "
        'Currently supported versions are: "msvc-2019", '
        '"msvc-2017", "msvc-2015", and "msvc-2013".  Latest '
        "installed version will be default.",
    )

    group.add_argument(
        "--regex", help="Regular expression for filtering test drivers"
    )

    group.add_argument(
        "--wafstyleout",
        action="store_true",
        help='Generate build output in "waf-style" for parsing '
        "by automated build tools.",
    )

    group.add_argument(
        "--cpp11-verify-no-change",
        action="store_true",
        default=False,
        help="Verify that none of the generated _cpp03 "
        "components change when the generator is run (i.e., "
        "the components are up-to-date).",
    )

    genChoices = Platform.generator_choices()
    if len(genChoices) > 1:
        group.add_argument(
            "-G",
            choices=genChoices,
            dest="generator",
            help="Select the build system for compilation.",
        )

    group = parser.add_argument_group(
        "build", 'Options for the "build" command'
    )

    group.add_argument(
        "--targets",
        type=lambda x: x.split(","),
        help="Comma-separated list of build targets (e.g. "
        '"bsl", "bslma", or "bslma_testallocator").',
    )

    group.add_argument(
        "--tests",
        choices=["build", "run"],
        help="Select whether to build or run the tests. Tests "
        "are not built by default.",
    )

    group.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Timeout for single test driver in seconds " "(default:600).",
    )

    group.add_argument(
        "-k",
        "--keep-going",
        action="store_true",
        help="Keep going after an error.",
    )

    group.add_argument(
        "--xml-report",
        action="store_true",
        help="Generate XML report when running tests.",
    )

    group = parser.add_argument_group(
        "install", 'Options for the "install" command'
    )

    group.add_argument(
        "--install_dir", help="Specify the installation directory."
    )

    group.add_argument(
        "--component",
        help="The name of the component. The build system "
        "creates following components for a package group or "
        'standalone package "X": "X", "X-headers", "X-meta", '
        '"X-pkgconfig", which install the library, headers, '
        "metadata, and pkg-config files respectively.  See "
        "bde-tools documentation for more details.",
    )

    args = parser.parse_args()
    options = Options(args)

    # Allow group writes to simplify cleanup of common build areas
    if not args.no_force_group_writes:
        os.umask(0o002)

    if "configure" in args.cmd:
        configure(options)

    if "build" in args.cmd:
        build(options)

    if "install" in args.cmd:
        install(options)
    return


def remove_builddir(path):
    real_path = os.path.realpath(path)
    cmake_cache = os.path.join(real_path, "CMakeCache.txt")

    if os.path.isdir(real_path) and os.path.exists(cmake_cache):
        try:
            shutil.rmtree(real_path)
        except shutil.Error as exception:
            raise


def mkdir_if_not_present(path):
    try:
        os.makedirs(path)
    except OSError as exception:
        if exception.errno != errno.EEXIST:
            raise


def configure(options):
    """Create build directory and generate build system."""
    if options.clean:
        remove_builddir(options.build_dir)

    mkdir_if_not_present(options.build_dir)
    # todo - detect generator change

    # Important: CMAKE_INSTALL_LIBDIR is passed here to accomodate
    # default installation layout.
    # Update: Darwin/MacOS uses lib for default 64 bit installs.
    host_platform = platform.system()
    configure_cmd = (
        ["cmake", os.getcwd(), "-G"]
        + Platform.generator(options)
        + [
            "-DCMAKE_MODULE_PATH:PATH=" + options.cmake_module_path,
            "-DUFID:STRING=" + options.ufid,
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
            "-DBDE_LOG_LEVEL=" + Platform.cmake_verbosity(options.verbose),
            "-DBUILD_BITNESS=" + ("64" if "64" in options.ufid else "32"),
            "-DBDE_USE_WAFSTYLEOUT="
            + ("ON" if options.wafstyleout else "OFF"),
            "-DBDE_CPP11_VERIFY_NO_CHANGE="
            + ("ON" if options.cpp11_verify_no_change else "OFF"),
            "-DCMAKE_INSTALL_PREFIX=" + options.prefix,
            "-DCMAKE_INSTALL_LIBDIR="
            + (
                "lib64"
                if ("64" in options.ufid and "Darwin" != host_platform)
                else "lib"
            ),
            "-DBDE_TEST_REGEX:STRING="
            + (options.test_regex if options.test_regex else ""),
        ]
    )

    if options.dpkg_build:
        configure_cmd.append(
            "-DCMAKE_TOOLCHAIN_FILE="
            + os.path.join(
                options.cmake_module_path, "toolchains/dpkg/production.cmake"
            )
        )
    else:
        if options.toolchain:
            if os.path.isfile(options.toolchain):
                configure_cmd.append(
                    "-DCMAKE_TOOLCHAIN_FILE=" + options.toolchain
                )
            elif os.path.isfile(
                os.path.join(
                    options.cmake_module_path, options.toolchain + ".cmake"
                )
            ):
                configure_cmd.append(
                    "-DCMAKE_TOOLCHAIN_FILE="
                    + os.path.join(
                        options.cmake_module_path, options.toolchain + ".cmake"
                    )
                )
            else:
                raise RuntimeError(
                    "Invalid toolchain file is specified: " + options.toolchain
                )

    # Use of '+' is mandatory here.
    cmakePrefixPath = os.path.join(
        str(options.refroot or "/") + "/" + str(options.prefix or "")
    )
    configure_cmd.append("-DCMAKE_PREFIX_PATH:PATH=" + cmakePrefixPath)

    if options.refroot:
        configure_cmd.append("-DDISTRIBUTION_REFROOT:PATH=" + options.refroot)

    print("Configuration cmd:")
    print(" ".join(configure_cmd))
    subprocess.check_call(
        configure_cmd,
        cwd=options.build_dir,
        env=Platform.generator_env(options),
    )


class CacheInfo:
    def __init__(self, build_dir):
        self.generator = None
        self.multiconfig = False
        self.build_type = None

        cacheFileName = os.path.join(build_dir, "CMakeCache.txt")
        if not os.path.isfile(cacheFileName):
            raise RuntimeError(
                "The project build configuration not found in " + build_dir
            )

        for line in open(cacheFileName):
            if line.startswith("CMAKE_GENERATOR:"):
                self.generator = line.strip().split("=")[1]
            elif line.startswith("CMAKE_CONFIGURATION_TYPES:"):
                self.multiconfig = True
            elif line.startswith("CMAKE_BUILD_TYPE:"):
                self.build_type = line.strip().split("=")[1]


def build_target(target, build_dir, extra_args, environ):
    build_cmd = ["cmake", "--build", build_dir]
    if target:
        build_cmd += ["--target", target]

    # filter out empty extra_args or Ninja wont like it
    build_cmd += [arg for arg in extra_args if arg]

    subprocess.check_call(build_cmd, env=environ)


def build(options):
    """Build"""
    cache_info = CacheInfo(options.build_dir)
    options.generator = cache_info.generator
    env = Platform.generator_env(options)
    extra_args = []
    if cache_info.multiconfig:
        extra_args += ["--config", cache_info.build_type]
    extra_args += [
        "--",
        Platform.generator_jobs_arg(options.generator, options),
    ]

    if options.verbose and options.generator == "Ninja":
        extra_args += ["-v"]

    if options.keep_going:
        if options.generator == "Ninja":
            extra_args += ["-k", "100"]
        elif options.generator == "Unix Makefiles":
            extra_args += ["-k"]

    target_list = options.targets if options.targets else ["all"]
    for target in target_list:
        main_target = None
        test_target = None

        if target.endswith(".t"):
            # If 'target.t' is specified on command line, then only build the
            # test target
            main_target = None
            test_target = target
        else:
            # 'target' without '.t' was specified.  If '--test' was specified,
            # still try to build 'target' (e.g., for matrix build to try
            # building application targets)
            main_target = target
            test_target = target + ".t" if options.tests else None

        if main_target:
            if main_target == "all":
                main_target = None
            try:
                build_target(main_target, options.build_dir, extra_args, env)
            except:
                # Continue if the 'target' without '.t' was specified, and
                # '--test' was specified since the main target might not exist
                if not options.tests and not options.keep_going:
                    raise

        if test_target:
            try:
                build_target(test_target, options.build_dir, extra_args, env)
            except:
                if not options.keep_going:
                    raise

    if "run" == options.tests:
        test_cmd = [
            "ctest",
            "--output-on-failure",
            "--no-label-summary",
            Platform.ctest_jobs_arg(options),
        ]
        if cache_info.multiconfig:
            test_cmd += ["-C", cache_info.build_type]

        if options.timeout > 0:
            test_cmd += ["--timeout", str(options.timeout)]

        if options.xml_report:
            test_cmd += ["--no-compress-output", "-T", "Test"]

        # Test labels in cmake do not end with '.t'.
        strip_dott = lambda x: x[:-2] if x.endswith(".t") else x
        test_list = [strip_dott(x) for x in target_list]
        if "all" not in test_list:
            test_pattern = "|".join(["^" + t + "$" for t in test_list])
            test_cmd += ["-L", test_pattern]

        try:
            subprocess.check_call(test_cmd, cwd=options.build_dir)
        except:
            if not options.keep_going:
                raise


def install(options):
    """Install"""
    if not options.install_dir:
        raise RuntimeError("The project install requires install_dir")

    if not options.prefix:
        options.prefix = "/"

    install_cmd = ["cmake", "-DCMAKE_INSTALL_PREFIX=" + options.prefix]
    if options.component:
        install_cmd += ["-DCOMPONENT=" + options.component]

    cache_info = CacheInfo(options.build_dir)
    if cache_info.multiconfig:
        install_cmd += ["-DCMAKE_INSTALL_CONFIG_NAME=" + cache_info.build_type]

    install_cmd += ["-P", "cmake_install.cmake"]

    environ = os.environ
    environ["DESTDIR"] = os.path.abspath(options.install_dir)

    print("Install cmd:")
    print(" ".join(install_cmd))

    subprocess.check_call(install_cmd, cwd=options.build_dir, env=environ)


if __name__ == "__main__":
    try:
        wrapper()
    except Exception as e:
        print("Error: {}".format(e), file=sys.stderr)
        sys.exit(1)
