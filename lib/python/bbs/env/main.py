import platform
import json
import re
import subprocess
import sys
import os

from pathlib import Path

from bbs.common import blderror
from bbs.common import sysutil
from bbs.ufid import ufid as Ufid
from bbs.uplid import uplid as Uplid
from bbs.env import profile_utils
from bbs.env import cmdline

def main():
    try:
        program()
    except blderror.BldError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
    except IOError as e:
        print(e, file=sys.stderr)
        sys.exit(1)


def program():
    platform_str = sysutil.unversioned_platform()

    if platform_str not in (
        "win32",
        "cygwin",
        "linux",
        "aix",
        "sunos",
        "darwin",
        "freebsd",
    ):
        print(f"Unsupported platform: {platform_str}", file=sys.stderr)
        sys.exit(1)

    parser = cmdline.get_args_parser()

    args = parser.parse_args()

    if args.command not in ("set", "unset", "list"):
        print(f"Invalid command: {args.command}", file=sys.stderr)
        parser.print_help()
        sys.exit(1)

    if args.command == "unset":
        unset_command()
        sys.exit(0)

    build_profiles = profile_utils.get_build_profiles()

    if args.command == "list":
        list_build_profiles(build_profiles)
        sys.exit(0)

    profile = None

    if build_profiles:
        if args.profile is None:
            profile = build_profile[0]
        elif sysutil.is_int_string(args.profile):
            idx = int(args.profile)
            if idx < len(build_profiles):
                profile = build_profiles[idx]
        else:
            for p in build_profiles:
                if p.name.startswith(args.profile):
                    profile = p
                    break

    if not profile:
        print(f"Invalid compiler profile: {args.profile}", file=sys.stderr)
        list_build_profiles(build_profiles)
        sys.exit(1)

    ufid = populate_ufid(args.ufid, profile)
    if ufid:
        print_envs(args, ufid, profile)
    else:
        sys.exit(1)

def unset_command():
    print("unset CXX")
    print("unset CC")
    print("unset BDE_CMAKE_UPLID")
    print("unset BDE_CMAKE_UFID")
    print("unset BDE_CMAKE_BUILD_DIR")
    print("unset BDE_CMAKE_TOOLCHAIN")
    print("unset PREFIX")
    print("unset PKG_CONFIG_PATH")
    print("unset BBS_ENV_MARKER")


def find_installdir(version):
    vswhere_path = Path(__file__).resolve().parents[4] / "bin" / "vswhere.exe"
    output = subprocess.check_output(
        [vswhere_path, "-prerelease", "-legacy", "-products", "*", "-format", "json"]
    )
    compilers = json.loads(output.decode("ascii", errors="ignore"))
    for cl in compilers:
        if cl["installationVersion"].startswith(version):
            return cl["installationPath"]
    return None

def populate_ufid(ufid_str, profile):
    platform_str = sysutil.unversioned_platform()

    ufid = Ufid.Ufid.from_str(ufid_str)

    if profile is None:
        profile = profile_utils.BuildProfile()

    properties = profile.properties

    if properties is None:
        properties = dict()

    # Populating build types
    full_ufid_flags = []
    if ufid.is_set("opt") or ufid.is_set("dbg"):
        if ufid.is_set("opt"):
            full_ufid_flags.append("opt")
        if ufid.is_set("dbg"):
            full_ufid_flags.append("dbg")
    else:
        full_ufid_flags.append("opt")
        full_ufid_flags.append("dbg")

    # Validating and populating ufid bitness
    bitness = properties.get("bitness")
    if bitness is None:
        if ufid.is_set("64"):
            full_ufid_flags.append("64")
        elif ufid.is_set("32"):
            full_ufid_flags.append("32")
        else:
            if sysutil.is_64bit_system():
                full_ufid_flags.append("64")
            else:
                full_ufid_flags.append("32")
    else:
        if bitness == 32 and ufid.is_set("64") or \
           bitness == 64 and ufid.is_set("32"):
            print(f"ERROR: Ufid flag {bitness} cannot be used with profile {profile.name}", file=sys.stderr)
            return None
        elif bitness == 64 or bitness == 32:
            full_ufid_flags.append(str(bitness))
        else:
            print(f"ERROR: Invalid value of toolchains bitness flag: {bitness} in profile {profile.name}", file=sys.stderr)
            return None

    # Validating and populating true/false flags
    for flag in ["noexc", "pic", "safe"]:
        value = properties.get(flag)
        if value is None:
            if ufid.is_set(flag):
                full_ufid_flags.append(flag)
        else:
            if value:
                full_ufid_flags.append(flag)
            else:
                if ufid.is_set(flag):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None

    # Sanitizers
    sanitizers = ["asan", "tsan", "msan", "ubsan", "fuzz"]
    sanitizer = properties.get("sanitizer")
    if sanitizer is None:
        for flag in sanitizers:
            if ufid.is_set(flag):
                full_ufid_flags.append(flag)
    else:
        if str(sanitizer).lower() == "false":
            for flag in sanitizers:
                if ufid.is_set(flag):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None
        else:
            for flag in sanitizers:
                if ufid.is_set(flag) and flag != str(sanitizer):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None

    # Assert and review levels
    assert_levels = ["aopt", "adbg", "asafe", "anone"]
    assert_level = properties.get("assert_level")
    if assert_level is None:
        for flag in assert_levels:
            if ufid.is_set(flag):
                full_ufid_flags.append(flag)
    else:
        if str(assert_level).lower() == "false":
            for flag in assert_levels:
                if ufid.is_set(flag):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None
        else:
            for flag in assert_levels:
                if ufid.is_set(flag) and flag != str(assert_level):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None

    review_levels = ["ropt", "rdbg", "rsafe", "rnone"]
    review_level = properties.get("review_level")
    if review_level is None:
        for flag in review_levels:
            if ufid.is_set(flag):
                full_ufid_flags.append(flag)
    else:
        if str(review_level).lower() == "false":
            for flag in assert_levels:
                if ufid.is_set(flag):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None
        else:
            for flag in review_levels:
                if ufid.is_set(flag) and flag != str(review_level):
                    print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                    return None

    # Validating and populating CXX standards flags
    cxx_standards = ["cpp03", "cpp11", "cpp14", "cpp17", "cpp20", "cpp23", "cpp26" ]
    value = properties.get("standard")
    if value is None:
        for flag in cxx_standards:
            if ufid.is_set(flag):
                full_ufid_flags.append(flag)
    else:
        for flag in cxx_standards:
            if ufid.is_set(flag) and flag != str(value):
                print(f"ERROR: Ufid flag {flag} cannot be used with profile {profile.name}", file=sys.stderr)
                return None

        full_ufid_flags.append(str(value))

    return Ufid.Ufid(full_ufid_flags)

def print_envs(args, ufid, profile):
    os_type, os_name, cpu_type, os_ver = sysutil.get_os_info()

    uplid = Uplid.Uplid(os_type, os_name, cpu_type, os_ver, profile.name if profile else "default")

    print(f"Effective ufid: {ufid}", file=sys.stderr)
    if (profile):
        print(f"Using build profile: {profile.name}", file=sys.stderr)

    print(f"export BBS_ENV_MARKER=ON")
    print(f"export BDE_CMAKE_UPLID={uplid}")
    print(f"export BDE_CMAKE_UFID={ufid}")

    if args.build_dir:
        build_path = Path(args.build_dir).resolve()
    else:
        build_path = Path.cwd() / "_build" / f"{uplid}-{ufid}"
    print(f'export BDE_CMAKE_BUILD_DIR="{build_path}"')

    if os_type == "windows":
        print(f"export CXX=cl")
        print(f"export CC=cl")

    if profile:
        if profile.c_path and profile.cxx_path:
            print(f"export CC={profile.c_path}")
            print(f"export CXX={profile.cxx_path}")

        if (profile.toolchain):
            print(f'export BDE_CMAKE_TOOLCHAIN="{Path(profile.toolchain)}"')
        else:
            print(f'unset BDE_CMAKE_TOOLCHAIN')

    install_dir = args.install_dir if args.install_dir else "_install"

    resolved_install_dir = Path(install_dir).resolve()
    print(f"Using install directory: {resolved_install_dir}", file=sys.stderr)
    print(f'export BDE_CMAKE_INSTALL_DIR="{resolved_install_dir}"')


def list_build_profiles(profiles):
    print("Available profiles:", file=sys.stderr)

    for idx, p in enumerate(profiles):
        print(f" {idx}: {p.name}" + (" (default)" if idx == 0 else ""), file=sys.stderr)
        if p.compiler_type:
            print(f"    Compiler type: {p.compiler_type}", file=sys.stderr)
        if p.c_path:
            print(f"    C compiler:    {p.c_path}", file=sys.stderr)
        if p.cxx_path:
            print(f"    CXX compiler:  {p.cxx_path}", file=sys.stderr)
        if p.toolchain:
            print(f"    Toolchain:     {p.toolchain}", file=sys.stderr)
        if p.properties:
            print(f"    Properties:    {p.properties}", file=sys.stderr)
        if p.description():
            print(f"    Description:   {p.description()}\n", file=sys.stderr)
