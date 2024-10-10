from pylibinit import addlibpath

addlibpath.add_lib_path()

from bbs.ufid.ufid import Ufid

import argparse
import collections
import errno
import json
import os
import platform
import shutil
import subprocess
import sys
import multiprocessing

from pathlib import Path

from get_dependers import get_dependers

####################################################################
# MSVC environment setup routines
if "Windows" == platform.system():
    try:
        import winreg  # Python 3
    except ImportError:
        import _winreg as winreg  # Python 2


def find_installdir(version):
    vswhere_path = Path(__file__).parent / "vswhere.exe"

    output = subprocess.check_output(
        [
            vswhere_path,
            "-prerelease",
            "-legacy",
            "-products",
            "*",
            "-format",
            "json",
        ]
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
    host_arch = platform.machine().lower() # typically amd64 or arm64
    if "arm" in host_arch:
        target_arch = "arm" if bitness == 32 else "arm64"
    else:
        target_arch = "x86" if bitness == 32 else "amd64"

    arch_arg = host_arch if host_arch == target_arch else f"{host_arch}_{target_arch}"

    process = subprocess.Popen(
        [bat_file, arch_arg, "&&", "set"], stdout=subprocess.PIPE, shell=True
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
    enums = dict(zip(sequential, range(len(sequential))), **named)
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
            f"{humanReadableName} was not specified using either a command-line\n"
            f"argument or environment variable {envVariableName}"
        )
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

        self.prefix = replace_path_sep(
            value_or_env(args.prefix, "PREFIX", "Installation prefix")
        )

        if not self.prefix:
            self.prefix = "/opt/bb"

        self.dpkg_version = value_or_env(
            args.dpkg_version, "DPKG_VERSION", "Dpkg version"
        )

        self.clean = args.clean
        self.toolchain = value_or_env(
            args.toolchain, "BDE_CMAKE_TOOLCHAIN", "CMake toolchain file"
        )

        self.refroot = replace_path_sep(
            value_or_env(
                args.refroot, "DISTRIBUTION_REFROOT", "Distribution refroot"
            )
        )

        # Find the bbs cmake modules
        p = Path(__file__).parent.parent / "BdeBuildSystem"
        if not p.is_dir():
            p = Path(self.refroot) if self.refroot else Path("/")
            p = p / "opt" / "bb" / "share" / "cmake" / "BdeBuildSystem"
            if not p.is_dir():
                raise RuntimeError(
                    "Cannot find BdeBuildSystem cmake modules\n"
                )
        self.bbs_module_path = p.resolve()

        # Get the compiler from UPLID
        uplid = os.getenv("BDE_CMAKE_UPLID")
        uplid_comp = None
        if uplid:
            uplid_comp = "-".join(uplid.split("-")[-2:])

        self.compiler = args.compiler if args.compiler else uplid_comp
        self.test_regex = args.regex
        self.wafstyleout = args.wafstyleout
        self.cpp11_verify_no_change = args.cpp11_verify_no_change
        self.recover_sanitizer = args.recover_sanitizer
        self.dump_cmake_flags = args.dump_cmake_flags

        self.generator = args.generator
        self.config = args.config

        self.targets = args.targets
        self.dependers_of = args.dependers_of
        self.no_missing_target_warning = args.no_missing_target_warning
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
    }

    @staticmethod
    def generator(options):
        if "msvc" == options.generator:
            if options.compiler not in Platform.msvcVersionMap:
                raise RuntimeError(f"Unknown compiler '{options.compiler}'")

            msvcInfo = Platform.msvcVersionMap[options.compiler]
            generator = [
                "Visual Studio {} {}".format(msvcInfo.version, msvcInfo.year)
            ]

            is64 = options.ufid and "64" in options.ufid
            if msvcInfo.version < 16:
                if is64:
                    generator[0] += " Win64"
            else:
                generator += ["-A", "x64" if is64 else "Win32"]
            return generator
        else:
            return [options.generator]

    @staticmethod
    def generator_env(options):
        host_platform = platform.system()
        if options.generator != "msvc" and "Windows" == host_platform:
            return get_msvc_env(
                Platform.msvcVersionMap[options.compiler].version,
                64 if options.ufid and "64" in options.ufid else 32,
            )
        else:
            return os.environ

    @staticmethod
    def generator_choices():
        choices = ["Ninja", "Ninja Multi-Config", "Unix Makefiles"]
        if "Windows" == platform.system():
            choices.append("msvc")
        return choices

    @staticmethod
    def cmake_verbosity(verbose):
        verbosity = ["ERROR", "WARNING", "STATUS", "VERBOSE", "TRACE"]
        return verbosity[max(0, min(len(verbosity) - 1, verbose))]

    @staticmethod
    def generator_jobs_arg(options):
        formatStrings = {}
        if options.generator == "msvc":
            formatStrings[JobsOptions.Type.ALL_AVAILABLE] = "/maxcpucount"
            formatStrings[JobsOptions.Type.FIXED] = "/maxcpucount:{}"
        elif options.generator == "Unix Makefiles":
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

def wrapper():
    description = """
                  bbs_build is a CMake/CTest wrapper that  provides a simpler
                  interface for the CMake/CTest invocation.
                  """
    parser = argparse.ArgumentParser(prog="bbs_build",
                                     description=description)
    parser.add_argument(
        "cmd", nargs="+", choices=["configure", "build", "install"]
    )

    parser.add_argument(
        "--build_dir",
        help = '''
               Path to the build directory. If not specified,
               the build system generates the name using the
               current platform, compiler, and ufid. The generated
               build directory looks like this:
               "./_build/unix-linux-x86_64-2.6.32-gcc-11.0.0-opt_64_cpp20"
               '''
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
        help ="Produce verbose output (including compiler " "command lines).",
    )

    parser.add_argument(
        "--prefix",
        default = "/opt/bb",
        help = '''
               The path prefix in which to look for
               dependencies for this build. If "--refroot" is
               specified, this prefix is relative to the
               refroot (default="/opt/bb").
               '''
    )

    group = parser.add_argument_group(
        "configure", 'Options for the "configure" command'
    )
    group.add_argument(
        "-u",
        "--ufid",
        help = '''
               Unified Flag IDentifier (e.g. "opt_dbg_64_cpp20"). See
               bde-tools documentation.
               '''
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
        'Currently supported versions are: '
        '"msvc-2022", "msvc-2019", and "msvc-2017".  Latest '
        "installed version will be default.",
    )

    group.add_argument(
        "--regex", help="Regular expression for filtering test drivers"
    )

    group.add_argument("--dpkg_version", help="Version string for .pc files")

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

    group.add_argument(
        "--recover-sanitizer",
        action="store_true",
        default=False,
        help="Try to recover after sanitizer error(s) and continue",
    )

    group.add_argument(
        "--dump-cmake-flags",
        action="store_true",
        default=False,
        help="Dump CMake flags and exit.",
    )

    genChoices = Platform.generator_choices()
    if len(genChoices) > 1:
        group.add_argument(
            "-G",
            choices=genChoices,
            dest="generator",
            help="Select the build system for compilation.",
            default="Ninja",
        )

    group = parser.add_argument_group(
        "build", 'Options for the "build" command'
    )

    target_group = group.add_mutually_exclusive_group()

    target_group.add_argument(
        "--targets",
        type=lambda x: x.split(","),
        help='''Comma-separated list of build system targets.
                The build system targets include the targets for
                libraries and test drivers for
                package groups ("bsl"/"bsl.t"), packages ("bslma"/"bslma.t"),
                and individual component ("bslma_allocator.t") as well as
                non-build targets to perform various operations such as
                cycle checks ("check_cycles"/"bsl.check_cycles") and cleanup
                ("clean"). Supplying a target of "help" will list all of the
                available targets.
            ''',
    )

    target_group.add_argument(
        "--dependers-of",
        type=lambda x: x.split(","),
        help="Comma-separated list of targets whose dependers need to be "
        "built.",
    )

    group.add_argument(
        "--no-missing-target-warning",
        action="store_true",
        help="Suppress warnings for invalid targets.",
    )

    group.add_argument(
        "--config",
        choices=["Debug", "RelWithDebInfo", "Release"],
        help="Select the build type. If not provided, the build "
        "type used on 'configure' stage will be used.",
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

    if not os.getenv("BBS_ENV_MARKER"):
        raise RuntimeError(
            f"BBS_ENV_MARKER is not set in the environment!\n"
            f"Make sure you use bbs_build_env.py or set it manually."
        )
    options = Options(args)

    if "configure" in args.cmd:
        configure(options)
    elif options.cpp11_verify_no_change:
        raise RuntimeError(
            f"'cpp11-verify-no-change' option is only intended for use with 'configure'"
        )

    if "build" in args.cmd:
        build(options)

    if "install" in args.cmd:
        install(options)
    return


def remove_builddir(path):
    real_path = Path(path)
    cmake_cache = real_path.joinpath("CMakeCache.txt")

    if real_path.is_dir() and cmake_cache.exists():
        try:
            shutil.rmtree(real_path)
        except shutil.Error as exception:
            raise


def mkdir_if_not_present(path):
    real_path = Path(path)
    try:
        os.makedirs(real_path)
    except OSError as exception:
        if exception.errno != errno.EEXIST:
            raise


def ufid_to_cmake_flags(ufid_str):
    cmake_flags = []

    ufid = Ufid.from_str(ufid_str)

    if not Ufid.is_valid(ufid.flags):
        raise RuntimeError("Invalid ufid is specified: " + ufid_str)

    if ufid.is_set("dbg"):
        if ufid.is_set("opt"):
            cmake_flags.append("-DCMAKE_BUILD_TYPE=RelWithDebInfo")
        else:
            cmake_flags.append("-DCMAKE_BUILD_TYPE=Debug")
    else:
        if ufid.is_set("opt"):
            cmake_flags.append("-DCMAKE_BUILD_TYPE=Release")
        else:
            cmake_flags.append("-DCMAKE_BUILD_TYPE=Debug")

    if ufid.is_set("pic"):
        cmake_flags.append("-DCMAKE_POSITION_INDEPENDENT_CODE=1")

    if ufid.is_set("noexc"):
        cmake_flags.append("-DBDE_BUILD_TARGET_NO_EXC=1")

    if ufid.is_set("nomt"):
        cmake_flags.append("-DBDE_BUILD_TARGET_NO_MT=1")

    if ufid.is_set("64"):
        cmake_flags.append("-DBDE_BUILD_TARGET_64=1")
    else:
        cmake_flags.append("-DBDE_BUILD_TARGET_32=1")

    if ufid.is_set("safe"):
        cmake_flags.append("-DBDE_BUILD_TARGET_SAFE=1")

    if ufid.is_set("safe2"):
        cmake_flags.append("-DBDE_BUILD_TARGET_SAFE2=1")

    if ufid.is_set("stlport"):
        cmake_flags.append("-DBDE_BUILD_TARGET_STLPORT=1")

    if ufid.is_set("asan"):
        cmake_flags.append("-DBDE_BUILD_TARGET_ASAN=1")

    if ufid.is_set("msan"):
        cmake_flags.append("-DBDE_BUILD_TARGET_MSAN=1")

    if ufid.is_set("tsan"):
        cmake_flags.append("-DBDE_BUILD_TARGET_TSAN=1")

    if ufid.is_set("ubsan"):
        cmake_flags.append("-DBDE_BUILD_TARGET_UBSAN=1")

    if ufid.is_set("fuzz"):
        cmake_flags.append("-DBDE_BUILD_TARGET_FUZZ=1")

    if ufid.is_set("aopt"):
        cmake_flags.append("-DBDE_BUILD_TARGET_ASSERT_LEVEL=AOPT")
    if ufid.is_set("adbg"):
        cmake_flags.append("-DBDE_BUILD_TARGET_ASSERT_LEVEL=ADBG")
    if ufid.is_set("asafe"):
        cmake_flags.append("-DBDE_BUILD_TARGET_ASSERT_LEVEL=ASAFE")
    if ufid.is_set("anone"):
        cmake_flags.append("-DBDE_BUILD_TARGET_ASSERT_LEVEL=ANONE")

    if ufid.is_set("ropt"):
        cmake_flags.append("-DBDE_BUILD_TARGET_REVIEW_LEVEL=ROPT")
    if ufid.is_set("rdbg"):
        cmake_flags.append("-DBDE_BUILD_TARGET_REVIEW_LEVEL=RDBG")
    if ufid.is_set("rsafe"):
        cmake_flags.append("-DBDE_BUILD_TARGET_REVIEW_LEVEL=RSAFE")
    if ufid.is_set("rnone"):
        cmake_flags.append("-DBDE_BUILD_TARGET_REVIEW_LEVEL=RNONE")

    if ufid.is_set("cpp03"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP03=1")

    if ufid.is_set("cpp11"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP11=1")

    if ufid.is_set("cpp14"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP14=1")

    if ufid.is_set("cpp17"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP17=1")

    if ufid.is_set("cpp20"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP20=1")

    if ufid.is_set("cpp23"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP23=1")

    if ufid.is_set("cpp26"):
        cmake_flags.append("-DBDE_BUILD_TARGET_CPP26=1")

    return cmake_flags


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

    flags = ufid_to_cmake_flags(options.ufid) + [
        "-DBdeBuildSystem_ROOT:PATH=" + str(options.bbs_module_path),
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
        "-DBBS_BUILD_SYSTEM=ON",
        "-DBBS_USE_WAFSTYLEOUT=" + ("ON" if options.wafstyleout else "OFF"),
        "-DBBS_CPP11_VERIFY_NO_CHANGE="
        + ("ON" if options.cpp11_verify_no_change else "OFF"),
        "-DCMAKE_INSTALL_PREFIX=" + options.prefix,
        "-DCMAKE_INSTALL_LIBDIR="
        + (
            "lib64"
            if ("64" in options.ufid and "Darwin" != host_platform)
            else "lib"
        ),
        "-DBDE_RECOVER_SANITIZER="
        + ("ON" if options.recover_sanitizer else "OFF"),
    ]

    if options.test_regex:
        flags.append("-DBDE_TEST_REGEX:STRING=" + options.test_regex)

    if options.dpkg_version:
        flags.append("-DBB_BUILDID_PKG_VERSION=" + options.dpkg_version)

    if options.toolchain:
        p = Path(options.toolchain)
        if p.is_file():
            flags.append("-DCMAKE_TOOLCHAIN_FILE=" + str(p))
        else:
            p = options.bbs_module_path / (options.toolchain + ".cmake")
            if p.is_file():
                flags.append("-DCMAKE_TOOLCHAIN_FILE=" + str(p))
            else:
                raise RuntimeError(
                    "Invalid toolchain file is specified: " + options.toolchain
                )

    # Use of '+' is mandatory here.
    cmakePrefixPath = os.path.join(
        str(options.refroot or "/") + "/" + str(options.prefix or "")
    )
    flags.append("-DCMAKE_PREFIX_PATH:PATH=" + cmakePrefixPath)

    if options.refroot:
        flags.append("-DDISTRIBUTION_REFROOT:PATH=" + options.refroot)

    if options.dump_cmake_flags:
        print(*flags, sep="\n")
        return

    configure_cmd = (
        ["cmake", os.getcwd(), "-G"]
        + Platform.generator(options)
        + flags
        + ["--log-level=" + Platform.cmake_verbosity(options.verbose)]
    )

    if options.generator in ["msvc", "Ninja Multi-Config"]:
        # CMAKE_BUILD_TYPE will be unused by CMake, but used later by bbs_build
        # build
        configure_cmd.append("--no-warn-unused-cli")

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
                if self.generator.startswith("Visual Studio"):
                    self.generator = "msvc"
            elif line.startswith("CMAKE_CONFIGURATION_TYPES:"):
                self.multiconfig = True
            elif line.startswith("CMAKE_BUILD_TYPE:"):
                self.build_type = line.strip().split("=")[1]


def build_targets(target_list, build_dir, extra_args, environ):
    build_cmd = ["cmake", "--build", build_dir]
    if target_list:
        build_cmd += ["--target"] + target_list

    # filter out empty extra_args or Ninja wont like it
    build_cmd += [arg for arg in extra_args if arg]

    subprocess.check_call(build_cmd, env=environ)


def buildType(options, cache_info):
    """
    Return the build type derived from the combination of the specified
    'options' and 'cache_info'.
    """

    if options.config and not cache_info.multiconfig:
        raise RuntimeError(
            f"'--config' option is not allowed for the '{cache_info.generator}' generator"
        )

    return options.config if options.config else cache_info.build_type


def build(options):
    """Build"""
    cache_info = CacheInfo(options.build_dir)
    options.generator = cache_info.generator
    env = Platform.generator_env(options)

    build_type = buildType(options, cache_info)

    extra_args = []
    if cache_info.multiconfig:
        extra_args += ["--config", build_type]
    extra_args += [
        "--",
        Platform.generator_jobs_arg(options),
    ]

    if options.verbose and options.generator.startswith("Ninja"):
        extra_args += ["-v"]

    if options.keep_going:
        if options.generator.startswith("Ninja"):
            extra_args += ["-k", "100"]
        elif options.generator == "Unix Makefiles":
            extra_args += ["-k"]

    target_list = []
    if options.dependers_of:
        # If '--dependers-of' is specified on command line, then only build
        # the dependers of the specified components.  If '--test' was
        # specified, build the test driver dependers.  Otherwise, build the
        # packages that the dependers belong to.
        target_list = get_dependers(options.dependers_of, options.tests,
                                    options.no_missing_target_warning)

        if target_list:
            print("Dependers found: " + " ".join(target_list))

            if not options.tests:

                def get_package_name(component):
                    parts = component.split("_")
                    # Take care of standalones, adapters, etc.
                    return (
                        f"{parts[0]}_{parts[1]}"
                        if len(parts[0]) == 1
                        else parts[0]
                    )

                target_list = list(
                    {get_package_name(depender) for depender in target_list}
                )
                print("Building " + " ".join(target_list))

            build_targets(target_list, options.build_dir, extra_args, env)
        else:
            # When no --test is specified, and --dependers-of is only passed
            # "<component>.t" as arguments, there is nothing that really needs
            # to be built.
            if not options.tests:
                print("Nothing to be built for dependers of tests only.")
                return
            else:
                raise RuntimeError("No dependers found")
    else:
        target_list = options.targets if options.targets else ["all"]
        for target in target_list:
            main_target = None
            test_target = None

            if target.endswith(".t"):
                # If 'target.t' is specified on command line, then only build
                # the test target
                main_target = None
                test_target = target
            else:
                # 'target' without '.t' was specified.  If '--test' was
                # specified, still try to build 'target' (e.g., for matrix
                # build to try building application targets)
                main_target = target
                test_target = target + ".t" if options.tests else None

            if main_target:
                build_list = [main_target]
                if main_target == "all":
                    build_list = []

                try:
                    build_targets(
                        build_list, options.build_dir, extra_args, env
                    )
                except:
                    # Continue if the 'target' without '.t' was specified, and
                    # '--test' was specified since the main target might not
                    # exist
                    if not options.tests and not options.keep_going:
                        raise

            if test_target:
                try:
                    build_targets(
                        [test_target], options.build_dir, extra_args, env
                    )
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
            test_cmd += ["-C", build_type]

        if options.timeout > 0:
            test_cmd += ["--timeout", str(options.timeout)]

        if options.xml_report:
            test_cmd += ["--no-compress-output", "-T", "Test"]

        # Test labels in cmake do not end with '.t'.
        strip_dottd = lambda x: x[:-2] if x.endswith(".t") else x
        test_list = [strip_dottd(x) for x in target_list]
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
        build_type = buildType(options, cache_info)
        install_cmd += ["-DCMAKE_INSTALL_CONFIG_NAME=" + build_type]

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
