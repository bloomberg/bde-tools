"""
BBS Build MCP Server

MCP server wrapping bbs_build for structured build/test integration.
Direct integration with bbs.env library for proper environment setup.
Zero external dependencies — uses inline JSON-RPC protocol handling.
"""

import sys

if sys.version_info < (3, 7):  # dataclasses, subprocess capture_output/text
    sys.exit(
        "bbs_build_mcp requires Python 3.7 or later, found %d.%d"
        % sys.version_info[:2]
    )

import os
import subprocess
import json
import re
import shutil
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote
from typing import List, Dict, Optional
from dataclasses import dataclass, field

import logging

logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stderr)
log = logging.getLogger("bbs-build-mcp")


def _run_streaming(
    cmd: List[str], env: Dict[str, str], cwd: Optional[str] = None
) -> "subprocess.CompletedProcess":
    """Run `cmd` like `subprocess.run(capture_output=True, text=True)`, but
    also mirror its output live to our stderr, which MCP clients show as
    server logs (VS Code's MCP output panel, `claude mcp logs`).
    """
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        # Test drivers can print bytes that are not valid UTF-8. A strict
        # decode raised in a pump thread, which then stopped draining its
        # pipe: the child blocked once the pipe filled, and this call never
        # returned. backslashreplace keeps the byte values, as \xNN.
        errors="backslashreplace",
        bufsize=1,
        # bbs_build is Python; without this it block-buffers into the pipe.
        env=dict(env, PYTHONUNBUFFERED="1"),
        cwd=cwd,
    )
    lock = threading.Lock()

    def pump(stream, sink):
        for line in stream:
            sink.append(line)
            with lock:
                sys.stderr.write(line)
                sys.stderr.flush()
        stream.close()

    out, err = [], []
    err_thread = threading.Thread(target=pump, args=(proc.stderr, err))
    err_thread.start()
    pump(proc.stdout, out)
    err_thread.join()
    rc = proc.wait()
    return subprocess.CompletedProcess(cmd, rc, "".join(out), "".join(err))


@dataclass
class BuildResult:
    success: bool
    duration_seconds: float
    stdout: str
    stderr: str
    errors: int = 0
    warnings: int = 0
    error_details: List[Dict] = field(default_factory=list)
    total_tests: int = 0
    passed_tests: int = 0
    skipped_tests: int = 0
    failed_tests: List[str] = field(default_factory=list)


class BbsBuildExecutor:
    """Wraps bbs_build CLI via subprocess"""

    # Relative location of the tools we invoke, under a refroot or under /.
    BBS_BUILD_SUBPATH = "opt/bb/libexec/bde-tools/bin/bbs_build"
    CTEST_SUBPATH = "opt/bb/bin/ctest"

    def __init__(
        self,
        cli_refroot: Optional[Path] = None,
        cli_build_dir: Optional[Path] = None,
        ufid: Optional[str] = None,
        test_timeout: int = 600,
        ignore_bbs_env: bool = False,
    ):
        # None means "not given on the command line": the inherited
        # environment is consulted before falling back to the defaults.
        self.cli_refroot = cli_refroot
        self.cli_build_dir = cli_build_dir
        self.cli_ufid = ufid
        self.test_timeout = test_timeout
        self.ignore_bbs_env = ignore_bbs_env
        self._env = None
        self._refroot_warning = None
        # These are set by set_project_root()
        self.project_root = None
        self.refroot = None
        self.build_dir = None
        self.bbs_build = None
        self.refroot_candidates = []

    @property
    def in_bbs_env(self) -> bool:
        """True when we adopt the bbs environment we were launched from.

        BBS_ENV_MARKER is what 'bbs_build_env' emits alongside
        BDE_CMAKE_UPLID/UFID/BUILD_DIR/TOOLCHAIN/INSTALL_DIR, and what
        'bbs_build' itself requires; when it is set we adopt that
        configuration rather than deriving a competing one, unless the
        caller opted out with --ignore-bbs-env.
        """
        return not self.ignore_bbs_env and bool(os.getenv("BBS_ENV_MARKER"))

    def _expand_ufid(self, ufid: str) -> Optional[str]:
        """Expand a UFID the way bbs_build_env would, or None if we cannot.

        "dbg" becomes e.g. "dbg_64_cpp23" once the build profile's defaults
        are applied, so a raw string comparison against BDE_CMAKE_UFID says
        "different" for two spellings of the same configuration.
        """
        try:
            from bbs.env import main as env_main
            from bbs.env import profile_utils

            profiles = profile_utils.get_build_profiles()
            expanded = env_main.populate_ufid(
                ufid, profiles[0] if profiles else None
            )
            return str(expanded) if expanded else None
        except Exception:  # profile lookup is best-effort here
            return None

    def _ufid_conflict(self, env: Dict[str, str]) -> Optional[str]:
        """Describe an unusable --ufid, or None.

        Locations may be overridden while adopting an inherited
        environment - --refroot and --build-dir name where things live and
        do not contradict it. The build configuration may not: a --ufid
        that differs from the inherited BDE_CMAKE_UFID asks for a second
        configuration in a build directory that belongs to the first.

        A --ufid naming the configuration we already inherited is not a
        conflict. That is the common case, because .mcp.json files carry
        `--ufid dbg` whether or not the session happens to start inside a
        bbs shell.
        """
        if not self.cli_ufid:
            return None
        inherited = env.get("BDE_CMAKE_UFID")
        expanded = self._expand_ufid(self.cli_ufid)
        if inherited and inherited in (expanded, self.cli_ufid):
            return None
        return (
            f"--ufid {self.cli_ufid}"
            + (f" (expands to {expanded})" if expanded else "")
            + f" conflicts with the inherited bbs environment "
            f"(BDE_CMAKE_UFID={inherited or '<unset>'}): the inherited "
            "BDE_CMAKE_BUILD_DIR belongs to that UFID, so building another "
            "one there would clobber it.\nAdd --ignore-bbs-env to derive "
            "the environment from --ufid, or drop --ufid to use the "
            "inherited configuration."
        )

    @property
    def ufid(self) -> str:
        """Build configuration to derive. Not consulted when the inherited
        environment is adopted, which supplies BDE_CMAKE_UFID itself."""
        return self.cli_ufid or "dbg"

    def set_project_root(self, project_root: Path):
        """Switch to a new project root, re-resolving relative paths.

        All or nothing: if resolution fails the executor is left on the
        project it was already serving. Committing the root first and
        resolving afterwards used to leave project_root and the process
        cwd on the new project while build_dir, bbs_build and the cached
        environment still belonged to the old one - so a build reported
        against the new project compiled into the old project's tree.
        """
        previous_root = self.project_root
        try:
            previous_cwd = os.getcwd()
        except FileNotFoundError:
            # The project we were serving has been deleted from under us -
            # routinely, when it was a worktree that has since been removed.
            # That must not stop us moving somewhere that does exist; there
            # is just nothing to roll back to.
            previous_cwd = None
        os.chdir(project_root)
        try:
            self.resolve(Path(os.getcwd()))
        except Exception:
            try:
                if previous_cwd is not None:
                    os.chdir(previous_cwd)
                    if previous_root is not None:
                        self.resolve(previous_root)
            except Exception as rollback_failed:
                # Report the original cause, not the rollback.
                log.error("Could not restore %s: %s", previous_root, rollback_failed)
            raise

    def resolve(self, project_root: Path):
        """(Re-)derive everything that hangs off the project root.

        Also called when nothing moved: an installed refroot, or tools
        that have appeared since startup, are only noticed by running
        this again.
        """
        self.project_root = project_root
        self._refroot_warning = self._resolve_dirs(project_root)
        self.bbs_build = self._find_tool("bbs_build", self.BBS_BUILD_SUBPATH)
        self._env = None

    def _resolve_dirs(self, project_root: Path) -> Optional[str]:
        """Resolve build_dir and refroot; return a warning string or None.

        Both follow the precedence 'bbs_build' itself uses (see
        'value_or_env' in bbs_build.py): an explicit command-line value
        first, then the environment, then a derived default.

        Deriving the build dir prefers /build/<unique> over a local _build
        when /build is writable, creating a _build symlink in project_root
        for tooling compatibility. Refroot falls back to
        /workarea/rr/<unique> when the local one is absent (berg requires
        the refroot to live under /workarea).
        """
        unique = "-".join(quote(p, safe="") for p in project_root.parts[1:])
        env_build_dir = os.getenv("BDE_CMAKE_BUILD_DIR")

        local_build = project_root / "_build"

        # Whether the build directory came from the launching shell rather
        # than from this server. If it did, the server does not own it and
        # will not delete it - see the force refusal in the configure tool.
        self.build_dir_inherited = False

        if self.cli_build_dir is not None:
            # Explicit --build-dir wins outright, relative or absolute; we
            # do not redirect it through /build.
            self.build_dir = (
                self.cli_build_dir
                if self.cli_build_dir.is_absolute()
                else (project_root / self.cli_build_dir).resolve()
            )
            log.info("Build dir: %s (--build-dir)", self.build_dir)
        elif self.in_bbs_env and env_build_dir:
            # Already fully resolved by bbs_build_env (it carries the
            # <uplid>-<ufid> suffix), so take it verbatim and skip the
            # /build indirection: the shell that launched us owns it.
            self.build_dir = Path(env_build_dir)
            self.build_dir_inherited = True
            log.info("Build dir: %s (from BDE_CMAKE_BUILD_DIR)", self.build_dir)
        elif local_build.is_dir() and not local_build.is_symlink():
            # A real _build tree already in the project root: keep using it
            # rather than silently moving the build elsewhere. A _build
            # *symlink* is this code's own bookkeeping for the /build case
            # below, so it deliberately does not match here.
            self.build_dir = local_build.resolve()
            log.info("Build dir: %s (existing _build)", self.build_dir)
        elif Path("/build").is_dir() and os.access("/build", os.W_OK):
            # Default: keep artifacts off the workspace backup path. This is
            # the one case where the server picks a location the user did
            # not name, so leave a _build symlink pointing at it - CMake and
            # IDEs keep working, and the user can still run ninja or ctest
            # against _build without having to work out where the build
            # went. The other branches all build somewhere the user or their
            # IDE chose, so nothing needs signposting.
            self.build_dir = Path("/build") / unique
            if local_build.is_symlink():
                if os.readlink(local_build) != str(self.build_dir):
                    local_build.unlink()
                    local_build.symlink_to(self.build_dir)
            elif not local_build.exists():
                local_build.symlink_to(self.build_dir)
            log.info("Build dir: %s (via /build)", self.build_dir)
        else:
            self.build_dir = local_build.resolve()
            log.info("Build dir: %s", self.build_dir)

        # Resolve refroot: --refroot → $DISTRIBUTION_REFROOT → _refroot →
        # /workarea/rr/<unique> (berg-compatible, outside project dirs).
        # DISTRIBUTION_REFROOT is not part of the bbs environment -
        # bbs_build_env only reads it - so it is honored independently of
        # BBS_ENV_MARKER and of --ignore-bbs-env.
        explicit = self.cli_refroot
        if explicit is None:
            # $DISTRIBUTION_REFROOT names a refroot just as --refroot does,
            # with one exception: "" and "/" both mean "no refroot, use the
            # system /opt/bb", and a Bloomberg dev space exports
            # DISTRIBUTION_REFROOT=/ by default. Those are the machine's
            # default rather than anyone's choice, so they fall through to
            # auto-detection below - taking them as naming a refroot would
            # disable detection for every project on the box. Any other
            # value was set deliberately, so it is honored as-is.
            env_refroot = (os.getenv("DISTRIBUTION_REFROOT") or "").strip()
            if env_refroot and Path(env_refroot) != Path("/"):
                explicit = Path(env_refroot)

        if explicit is not None:
            # Named, so honored as given - including an explicit "/" - and
            # required to exist; the caller reports it when it does not.
            self.refroot = (
                explicit
                if explicit.is_absolute()
                else (project_root / explicit).resolve()
            )
            self.refroot_candidates = [self.refroot]
            return None

        self.refroot_candidates = list(
            dict.fromkeys(
                [project_root / "_refroot", Path("/workarea/rr") / unique]
            )
        )
        for candidate in self.refroot_candidates:
            if candidate.exists():
                self.refroot = candidate.resolve()
                return None

        # No refroot anywhere. Leave it unspecified, which means "/" - the
        # same default bbs_build applies via `options.refroot or "/"`, so
        # the prefix resolves to /opt/bb. Warn, because for a project that
        # expects a refroot this usually means 'berg export-deps' has not
        # been run.
        self.refroot = None
        searched = ", ".join(str(p) for p in self.refroot_candidates)
        return (
            f"No refroot found (searched {searched}); defaulting the refroot "
            "to /. Run `berg export-deps` if this project needs one, or pass "
            "refroot=<path> to configure."
        )

    def unusable_refroot(self, refroot: Path) -> Optional[str]:
        """Why `refroot` cannot be used, or None.

        A refroot has to provide bbs_build, not merely exist: a project
        that runs this server builds with bbs_build and depends on it
        (typically `Build-Depends: bde-internal-tools`), so a real refroot
        for it ships one. Checking only existence lets a plausible-looking
        directory be accepted and then fail on every subsequent call.
        """
        if not refroot.is_dir():
            return f"Refroot does not exist: {refroot}"
        if not (refroot / self.BBS_BUILD_SUBPATH).is_file():
            return (
                f"Not a refroot: {refroot}\n"
                f"It provides no {self.BBS_BUILD_SUBPATH}."
            )
        return None

    def effective_refroot(self) -> Path:
        """The refroot this build uses.

        An unresolved refroot means "/", the same default bbs_build applies
        via `options.refroot or "/"`. Reported on every tool response so a
        caller never has to work it out from logs or raw output.
        """
        return self.refroot if self.refroot is not None else Path("/")

    def resolved_build_dir(self) -> Path:
        """The directory the build actually happens in.

        self.build_dir is a base, as --build-dir and bbs_build_env's
        ./_build are: deriving appends <uplid>-<ufid> beneath it. Clients
        looking for compile_commands.json, logs or the ctest tree need the
        resolved path, so responses report this rather than the base.
        Sets the environment up if that has not happened yet, so a failure
        reported before anything ran still names the same directory a
        success would. Falls back to the base only when the environment
        cannot be resolved at all, which is itself being reported.
        """
        if not (self._env and self._env.get("BDE_CMAKE_BUILD_DIR")):
            try:
                self._setup_environment()
            except Exception:
                return self.build_dir
        return Path(self._env["BDE_CMAKE_BUILD_DIR"])

    def _tool_bases(self) -> List[Path]:
        """Refroots searched for build tools, most specific first.

        An unspecified refroot means "/", matching bbs_build's own
        `options.refroot or "/"`. Deduplicated, so an explicit refroot of
        "/" is not searched - and reported - twice.
        """
        bases = [] if self.refroot is None else [self.refroot]
        bases.append(Path("/"))
        return list(dict.fromkeys(bases))

    def _find_tool(self, name: str, subpath: str) -> Optional[Path]:
        """Locate a build tool under each candidate refroot (an
        unspecified refroot meaning "/", so <refroot>/opt/bb/... resolves to
        /opt/bb/...), then on PATH for platforms that have no /opt/bb.

        Returns None if the tool is nowhere to be found; callers report the
        searched locations via _tool_not_found_message().
        """
        for base in self._tool_bases():
            candidate = base / subpath
            if candidate.is_file():
                return candidate
        found = shutil.which(name)
        return Path(found) if found else None

    def _tool_not_found_message(self, name: str, subpath: str) -> str:
        """Explain where we looked for a tool, and for a refroot."""
        tried = "\n".join(f"  {base / subpath}" for base in self._tool_bases())
        message = f"{name} not found. Tried:\n{tried}\n  {name} on PATH\n"
        if self.refroot is None and self.refroot_candidates:
            locations = "\n".join(f"  {p}" for p in self.refroot_candidates)
            message += (
                "No refroot was found either. Install one to one of:\n"
                f"{locations}\n"
                "or pass refroot=<path> to configure if one already exists "
                "elsewhere."
            )
        return message

    def _setup_environment(self):
        """Set up the build environment.

        When we were launched from a populated bbs environment, adopt it
        verbatim: re-deriving UPLID/UFID/build dir here would silently
        disagree with the shell (or IDE) that started us. Otherwise derive
        them with the bbs.env library, the way bbs_build_env would.
        """
        if self._env is not None:
            return

        if self.refroot is not None and not self.refroot.exists():
            raise RuntimeError(
                f"Refroot directory does not exist: {self.refroot}\n"
                "Run the project's setup script to create the refroot first."
            )

        if self.in_bbs_env:
            env = os.environ.copy()
            if not env.get("BDE_CMAKE_BUILD_DIR"):
                raise RuntimeError(
                    "BBS_ENV_MARKER is set but BDE_CMAKE_BUILD_DIR is not: "
                    "the inherited bbs environment is incomplete.\n"
                    "Re-run `eval $(bbs_build_env ...)`, or pass "
                    "--ignore-bbs-env to derive the environment instead."
                )
            conflict = self._ufid_conflict(env)
            if conflict:
                raise RuntimeError(conflict)
            # DISTRIBUTION_REFROOT is not part of the bbs environment, so
            # publish whichever refroot we resolved (which may have come
            # from --refroot or auto-detection rather than from the env).
            if self.refroot is not None:
                env["DISTRIBUTION_REFROOT"] = str(self.refroot)
            # An explicit --build-dir still wins over the inherited one. It
            # is a base, as in derived mode, so it takes the same
            # <uplid>-<ufid> suffix - here from the inherited values.
            if self.cli_build_dir is not None:
                uplid = env.get("BDE_CMAKE_UPLID")
                ufid = env.get("BDE_CMAKE_UFID")
                build_path = self.build_dir
                if uplid and ufid:
                    build_path = build_path / f"{uplid}-{ufid}"
                env["BDE_CMAKE_BUILD_DIR"] = str(build_path.resolve())
            self._env = env
            return

        # Import bbs modules (available via PYTHONPATH set by the wrapper)
        from bbs.env import main as env_main
        from bbs.env import profile_utils
        from bbs.common import sysutil
        from bbs.uplid import uplid as Uplid

        env = os.environ.copy()

        # Get available build profiles and use the first one
        build_profiles = profile_utils.get_build_profiles()
        profile = build_profiles[0] if build_profiles else None

        # Build UPLID matching bbs_build_env output (includes profile name)
        os_type, os_name, cpu_type, os_ver = sysutil.get_os_info()
        uplid = str(
            Uplid.Uplid(
                os_type,
                os_name,
                cpu_type,
                os_ver,
                profile.name if profile else "default",
            )
        )

        # Use bbs.env to populate UFID
        ufid_obj = env_main.populate_ufid(self.ufid, profile)
        if not ufid_obj:
            raise RuntimeError(f"Failed to populate UFID: {self.ufid}")

        ufid = str(ufid_obj)

        env["BBS_ENV_MARKER"] = "ON"
        env["BDE_CMAKE_UPLID"] = uplid
        env["BDE_CMAKE_UFID"] = ufid

        # Set build directory (always append uplid-ufid suffix)
        build_path = self.build_dir / f"{uplid}-{ufid}"
        env["BDE_CMAKE_BUILD_DIR"] = str(build_path.resolve())

        # Set DISTRIBUTION_REFROOT so the BBToolchain cmake file picks it
        # up via $ENV{DISTRIBUTION_REFROOT} and correctly sets compiler
        # paths, PKG_CONFIG_SYSROOT_DIR, and system prefix paths. Left
        # unset when the refroot is unspecified, so cmake defaults it to /.
        if self.refroot is not None:
            env["DISTRIBUTION_REFROOT"] = str(self.refroot)

        # Set toolchain from build profile. bbs_build passes this as
        # -DCMAKE_TOOLCHAIN_FILE to cmake. The toolchain file includes
        # setup_refroot_pkgconfig.cmake which sets PKG_CONFIG_SYSROOT_DIR
        # from DISTRIBUTION_REFROOT - required for correct include paths
        # when using a non-system refroot.
        if profile and profile.toolchain:
            env["BDE_CMAKE_TOOLCHAIN"] = str(Path(profile.toolchain))

        self._env = env

    def _refroot_args(self) -> List[str]:
        """Return --refroot args for bbs_build commands, or none when the
        refroot is unspecified - bbs_build then defaults it to / itself."""
        if self.refroot is None:
            return []
        return ["--refroot", str(self.refroot)]

    def configure(self, force: bool = False) -> BuildResult:
        """Execute bbs_build configure.

        If force is True, delete the build subdirectory under build_dir
        (e.g. <build_dir>/unix-linux-x86_64-...) to clear stale CMake
        caches before running configure.
        """
        if force:
            self._setup_environment()
            build_dir = Path(self._env["BDE_CMAKE_BUILD_DIR"])
            if build_dir.exists():
                shutil.rmtree(build_dir)

        args = ["configure"] + self._refroot_args()
        return self._execute(args)

    def build(
        self,
        targets: Optional[List[str]] = None,
        verbose: bool = False,
        with_tests: bool = False,
        dependers_of: Optional[List[str]] = None,
        run_tests: bool = False,
        timeout: Optional[int] = None,
    ) -> BuildResult:
        """Execute bbs_build build"""
        args = ["build"]
        if targets:
            args.extend(["--targets", ",".join(targets)])
        if dependers_of:
            args.extend(["--dependers-of", ",".join(dependers_of)])
        if run_tests:
            # bbs_build runs ctest itself, with its own --timeout default.
            # Pass ours, so --test-timeout and a per-call timeout mean the
            # same thing here as they do for the 'test' tool.
            args.extend(["--tests", "run", "--timeout",
                         str(timeout if timeout is not None else self.test_timeout)])
        elif with_tests:
            args.extend(["--tests", "build"])
        if verbose:
            args.append("--verbose")

        result = self._execute(args)

        # Parse build output
        output = result.stdout + result.stderr
        all_errors = self._extract_errors(output)
        result.errors = len(all_errors)
        result.error_details = all_errors[:10]
        result.warnings = self._count_warnings(output)

        if run_tests:
            test_results = self._parse_ctest_output(result.stdout)
            result.total_tests = test_results["total"]
            result.passed_tests = test_results["passed"]
            result.skipped_tests = test_results["skipped"]
            result.failed_tests = test_results["failed_tests"]

        return result

    def run_tests(
        self,
        targets: Optional[List[str]] = None,
        regex: Optional[str] = None,
        timeout: Optional[int] = None,
    ) -> BuildResult:
        """Run already-built tests using ctest directly (no rebuild)."""
        self._setup_environment()
        build_dir = Path(self._env["BDE_CMAKE_BUILD_DIR"])

        if not build_dir.exists():
            return BuildResult(
                success=False,
                duration_seconds=0,
                stdout="",
                stderr=f"Build directory does not exist: {build_dir}\n"
                "Run 'build' first to compile the project.",
            )

        ctest = self._find_tool("ctest", self.CTEST_SUBPATH)
        if ctest is None:
            return BuildResult(
                success=False,
                duration_seconds=0,
                stdout="",
                stderr=self._tool_not_found_message("ctest", self.CTEST_SUBPATH),
            )
        ctest = str(ctest)
        # The JUnit file is a transport for one parse and nothing else reads
        # it, so give each run a private path and take it away afterwards.
        # Writing a fixed name into the build tree meant a run that died
        # before ctest rewrote the file parsed the *previous* run's results
        # and reported them as its own.
        junit_dir = Path(tempfile.mkdtemp(prefix="bbs_build_mcp-ctest-"))
        junit_file = junit_dir / "test_results.xml"
        test_timeout = timeout or self.test_timeout

        cmd = [
            ctest,
            "--output-on-failure",
            "--no-label-summary",
            f"-j{os.cpu_count()}",
            "--timeout",
            str(test_timeout),
            "--output-junit",
            str(junit_file),
        ]

        if regex:
            cmd.extend(["-R", regex])
        if targets:
            labels = [t[:-2] if t.endswith(".t") else t for t in targets]
            # -L takes a regex, so a name has to be escaped before being
            # anchored into one. BDE package groups really do contain
            # metacharacters - bsl+stdhdrs, bdl+decnumber - and unescaped
            # "^bsl+stdhdrs$" means "bs, one or more l, stdhdrs", which
            # matches nothing and reads back as "no such test".
            label_pattern = "|".join(f"^{re.escape(lab)}$" for lab in labels)
            cmd.extend(["-L", label_pattern])

        start = time.time()
        try:
            proc = _run_streaming(cmd, self._env, cwd=str(build_dir))

            result = BuildResult(
                success=proc.returncode == 0,
                duration_seconds=time.time() - start,
                stdout=proc.stdout,
                stderr=proc.stderr,
            )

            # Parse JUnit XML if available, fall back to text parsing
            if junit_file.exists():
                test_results = self._parse_junit_xml(junit_file)
            else:
                test_results = self._parse_ctest_output(proc.stdout)

            result.total_tests = test_results["total"]
            result.passed_tests = test_results["passed"]
            result.skipped_tests = test_results["skipped"]
            result.failed_tests = test_results["failed_tests"]

            return result
        except FileNotFoundError as e:
            return BuildResult(
                success=False,
                duration_seconds=time.time() - start,
                stdout="",
                stderr=f"Error: {e}",
            )
        finally:
            shutil.rmtree(junit_dir, ignore_errors=True)

    def _execute(self, args: List[str]) -> BuildResult:
        """Execute bbs_build command"""
        self._setup_environment()

        if self.bbs_build is None:
            return BuildResult(
                success=False,
                duration_seconds=0,
                stdout="",
                stderr=self._tool_not_found_message(
                    "bbs_build", self.BBS_BUILD_SUBPATH
                ),
            )

        cmd = [str(self.bbs_build)] + args

        start = time.time()

        try:
            proc = _run_streaming(cmd, self._env)

            return BuildResult(
                success=proc.returncode == 0,
                duration_seconds=time.time() - start,
                stdout=proc.stdout,
                stderr=proc.stderr,
            )
        except FileNotFoundError as e:
            return BuildResult(
                success=False,
                duration_seconds=time.time() - start,
                stdout="",
                stderr=f"Error: {e}",
            )

    def _count_warnings(self, output: str) -> int:
        return len(re.findall(r"warning:", output, re.IGNORECASE))

    # Compiler diagnostic: file:line:col: error|warning|note: message
    #
    # "fatal error" covers the single most common failure there is - a
    # header that cannot be found - under both compilers, which word the
    # message differently but mark it identically:
    #   gcc:   foo.cpp:1:10: fatal error: nosuch.h: No such file or directory
    #   clang: foo.cpp:1:10: fatal error: 'nosuch.h' file not found
    _DIAG_RE = re.compile(
        r"^(\S+):(\d+):(\d+): (?:fatal |internal compiler )?"
        r"(error|warning|note): (.+)$"
    )
    # A tool speaking for itself, with no file:line:col to anchor to. Both
    # drivers and the compiler proper do this, so match the shape rather
    # than a list of names:
    #   clang++: error: no such file or directory: 'nope.cpp'
    #   clang++: error: linker command failed with exit code 1
    #   cc1plus: fatal error: nope.cpp: No such file or directory
    #   collect2: error: ld returned 1 exit status
    _TOOL_ERROR_RE = re.compile(r"^([\w.+-]+): (?:fatal )?error: (.+)$")
    _TRAILER_RE = re.compile(
        r"^(?:compilation terminated\.|\d+ (?:error|warning)s? generated\.)$"
    )
    # Linker errors come in several formats:
    #   Single-line:  /usr/bin/ld: foo.o: undefined reference to `Bar::baz()'
    #   Two-line:     /path/to/ld: foo.o: in function `Foo()':
    #                 /path/file.cpp:30: undefined reference to `bar()'
    #   Also:         /path/file.cpp:30: multiple definition of `bar'
    #   collect2:     collect2: error: ld returned 1 exit status
    _LINKER_RE = re.compile(
        r"^(\S*ld\S*): (\S+): (undefined reference to .+|multiple definition of .+)$"
    )
    # The location is a source line only when the object carries debug
    # info. Otherwise ld names a section offset, which is what an -O build
    # without -g actually prints:
    #   undef.cpp:(.text+0x5): undefined reference to `nowhere()'
    _LINKER_UNDEF_RE = re.compile(
        r"^(\S+):(?:(\d+)|\(([^)]*)\)): "
        r"(undefined reference to .+|multiple definition of .+)$"
    )
    _LINKER_CONTEXT_RE = re.compile(r"^(\S*ld\S*): (\S+): in function .+:$")

    @staticmethod
    def _linker_error(match) -> Dict:
        """An undefined reference, with a line number only if ld gave one."""
        error = {"file": match.group(1), "message": match.group(4)}
        if match.group(2):
            error["line"] = int(match.group(2))
        return error

    def _extract_errors(self, output: str) -> List[Dict]:
        """Extract compiler and linker errors with multiline context.

        Compiler errors (file:line:col: error:) are captured with their
        continuation lines (caret diagnostics, notes, macro expansions).

        Linker errors (undefined reference, multiple definition, collect2)
        are captured with a linker-specific format.
        """
        errors = []
        lines = output.splitlines()
        i = 0
        while i < len(lines):
            # Check for compiler error
            m = self._DIAG_RE.match(lines[i])
            if m and m.group(4) == "error":
                file, line, col, msg = (
                    m.group(1),
                    m.group(2),
                    m.group(3),
                    m.group(5),
                )
                # Collect continuation lines
                cont = []
                i += 1
                while i < len(lines):
                    # Stop at blank line, next error/warning, or cmake progress
                    if not lines[i].strip() or lines[i].startswith("["):
                        break
                    # Each compiler's end-of-run trailer belongs to the run,
                    # not to the last diagnostic: "compilation terminated."
                    # from gcc, "3 errors generated." from clang.
                    if self._TRAILER_RE.match(lines[i]):
                        break
                    next_m = self._DIAG_RE.match(lines[i])
                    if next_m and next_m.group(4) in ("error", "warning"):
                        break
                    if (
                        self._LINKER_RE.match(lines[i])
                        or self._LINKER_UNDEF_RE.match(lines[i])
                        or self._LINKER_CONTEXT_RE.match(lines[i])
                        or self._TOOL_ERROR_RE.match(lines[i])
                    ):
                        break
                    cont.append(lines[i])
                    i += 1
                full_msg = "\n".join([msg] + cont) if cont else msg
                errors.append(
                    {
                        "file": file,
                        "line": int(line),
                        "column": int(col),
                        "message": full_msg,
                    }
                )
                continue

            # Check for single-line linker error: ld: obj.o: undefined reference
            lm = self._LINKER_RE.match(lines[i])
            if lm:
                errors.append(
                    {
                        "file": lm.group(2),
                        "message": lm.group(3),
                    }
                )
                i += 1
                continue

            # Check for ld context line followed by file:line: undefined reference
            lcm = self._LINKER_CONTEXT_RE.match(lines[i])
            if lcm and i + 1 < len(lines):
                um = self._LINKER_UNDEF_RE.match(lines[i + 1])
                if um:
                    errors.append(self._linker_error(um))
                    i += 2
                    continue

            # Check for standalone file:line: undefined reference
            um = self._LINKER_UNDEF_RE.match(lines[i])
            if um:
                errors.append(self._linker_error(um))
                i += 1
                continue

            # A tool speaking for itself: the drivers, cc1plus, collect2.
            tm = self._TOOL_ERROR_RE.match(lines[i])
            if tm:
                errors.append({"message": f"{tm.group(1)}: {tm.group(2)}"})
                i += 1
                continue

            i += 1
        return errors

    # ctest's own summary of what it considers failed:
    #
    #     The following tests FAILED:
    #             2 - beta_with_a_much_longer_name (Failed)
    #             7 - some_other (Not Run)
    #
    # Authoritative, and unlike the per-test lines it tolerates a test name
    # containing spaces and needs no judgement about which markers count.
    _CTEST_FAILED_HEADER = "The following tests FAILED:"
    _CTEST_FAILED_ITEM_RE = re.compile(r"^\s+\d+\s+-\s+(.+?)\s+\([^()]*\)\s*$")

    # Fallback: the per-test lines. The name is padded with dots out to a
    # fixed column, so the run of dots varies with the longest name in the
    # suite - matching a fixed three of them, as this once did, only ever
    # worked for the longest name.
    #
    #     2/4 Test #2: beta_with_a_much_longer_name .....***Failed  0.00 sec
    #     3/4 Test #3: c_mid_name .......................***Failed  0.00 sec
    _CTEST_TEST_LINE_RE = re.compile(
        r"^\s*\d+/\d+\s+Test\s+#\d+:\s+(.+?)\s+\.*\*\*\*(Failed|Timeout"
        r"|Not Run|Exception)",
        re.M,
    )

    # Tests ctest counted towards "tests passed" without running them:
    #
    #     The following tests did not run:
    #             2 - skipme (Skipped)
    #             5 - off (Disabled)
    _CTEST_NOT_RUN_HEADER = "The following tests did not run:"

    def _ctest_block_names(self, output: str, header: str) -> List[str]:
        """Names listed under one of ctest's end-of-run summary blocks."""
        lines = output.splitlines()
        for i, line in enumerate(lines):
            if line.strip() != header:
                continue
            names = []
            for item in lines[i + 1 :]:
                found = self._CTEST_FAILED_ITEM_RE.match(item)
                if not found:
                    break
                names.append(found.group(1))
            return names
        return []

    def _failed_test_names(self, output: str) -> List[str]:
        """Names ctest reported as failing, in the order it listed them."""
        lines = output.splitlines()
        for i, line in enumerate(lines):
            if line.strip() != self._CTEST_FAILED_HEADER:
                continue
            names = []
            for item in lines[i + 1 :]:
                found = self._CTEST_FAILED_ITEM_RE.match(item)
                if not found:
                    break
                names.append(found.group(1))
            if names:
                return names

        # No summary block - a run cut short, or an output mode without it.
        return [name for name, _ in self._CTEST_TEST_LINE_RE.findall(output)]

    def _parse_ctest_output(self, output: str) -> Dict:
        # ctest omits the failure clause when everything passed:
        #     50% tests passed, 2 tests failed out of 4
        #     100% tests passed out of 1
        # Requiring the clause read every clean run as zero tests.
        match = re.search(
            r"(\d+)% tests passed(?:, (\d+) tests failed)? out of (\d+)", output
        )
        if match:
            failed = int(match.group(2) or 0)
            total = int(match.group(3))
            passed = total - failed
        else:
            total = passed = 0

        failed_tests = self._failed_test_names(output)

        # ctest's "N% tests passed" counts skipped and disabled tests as
        # passed; they are only told apart in the "did not run" block. A
        # test that did not run did not pass, as in the JUnit parser.
        skipped = len(self._ctest_block_names(output, self._CTEST_NOT_RUN_HEADER))
        passed = max(passed - skipped, 0)

        return {
            "total": total,
            "passed": passed,
            "skipped": skipped,
            "failed_tests": failed_tests,
        }

    def _parse_junit_xml(self, junit_file: Path) -> Dict:
        """Parse ctest JUnit XML output for test results."""
        try:
            tree = ET.parse(junit_file)
            root = tree.getroot()
            total = int(root.attrib.get("tests", 0))
            failures = int(root.attrib.get("failures", 0))
            # A test that did not run did not pass. ctest reports these
            # separately from failures, and "total - failures" quietly
            # counted every one of them as a pass - a suite that skipped
            # half its tests read as a clean run.
            skipped = int(root.attrib.get("skipped", 0))
            disabled = int(root.attrib.get("disabled", 0))
            errors = int(root.attrib.get("errors", 0))
            passed = total - failures - skipped - disabled - errors

            failed_tests = []
            for testcase in root.iter("testcase"):
                if testcase.find("failure") is not None:
                    failed_tests.append(testcase.attrib.get("name", "unknown"))

            return {
                "total": total,
                "passed": passed,
                "skipped": skipped + disabled,
                "failed_tests": failed_tests,
            }
        except (ET.ParseError, KeyError, ValueError):
            return {"total": 0, "passed": 0, "skipped": 0, "failed_tests": []}


def _tail(text: str, num_lines: int) -> List[str]:
    """Return the last num_lines lines of text as a list."""
    return text.splitlines()[-num_lines:]


def _extract_error_lines(output: str) -> List[Dict]:
    """Extract error blocks from build/test output.

    Used as a fallback when structured error parsing (file:line:col) finds
    nothing. Captures the error indicator line plus any continuation lines
    (indented or non-diagnostic) that follow it.
    """
    keywords = ("error:", "error[", "fatal:", "failed", "undefined reference")
    lines = output.splitlines()
    results = []
    i = 0
    while i < len(lines):
        lower = lines[i].lower()
        if any(kw in lower for kw in keywords):
            # Capture this line plus continuation lines
            block = [lines[i].strip()]
            i += 1
            while i < len(lines):
                next_line = lines[i]
                # Stop at blank lines, next diagnostic header, or cmake lines
                if (
                    not next_line.strip()
                    or re.match(r"\S+:\d+:\d+: (error|warning):", next_line)
                    or next_line.startswith("[")
                ):
                    break
                block.append(next_line.strip())
                i += 1
            message = "\n".join(block)
            if message not in [r["message"] for r in results]:
                results.append({"message": message})
            if len(results) >= 20:
                break
        else:
            i += 1
    return results


# Global executor instance
executor = None


# ==================== MCP PROTOCOL ====================

TOOLS = {
    "configure": {
        "description": (
            "Configure the build system using bbs_build. "
            "Use force=true to delete the build subdirectory and clear stale CMake caches before configuring. "
            "If no refroot is found at the auto-detected locations, the refroot defaults to / and the "
            "response carries a warning; pass refroot=<path> to use an existing refroot."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "force": {
                    "type": "boolean",
                    "description": "Delete the build directory before "
                    "configuring, to clear stale CMake caches. Refused when "
                    "the build directory was inherited from the bbs "
                    "environment, since the server does not own it.",
                },
                "project_root": {
                    "type": "string",
                    "description": "Project root directory (overrides startup default for this and subsequent operations). Rejected when the server inherited a bbs environment, which pins the build directory to one project.",
                },
                "refroot": {
                    "type": "string",
                    "description": "Override refroot path for this and subsequent operations (skips auto-detection; must be an existing directory)",
                },
                "capture_output": {
                    "type": "integer",
                    "description": "Include last N lines of raw output in response",
                },
            },
        },
    },
    "build": {
        "description": "Build the project using bbs_build. Operates on the project root set by the most recent configure call.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "targets": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Specific targets to build",
                },
                "dependers_of": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Build all dependers of these targets (--dependers-of). Cannot be combined with targets",
                },
                "with_tests": {
                    "type": "boolean",
                    "description": "Build test binaries without running them (--tests build)",
                },
                "run_tests": {
                    "type": "boolean",
                    "description": "Build and run test binaries (--tests run)",
                },
                "timeout": {
                    "type": "integer",
                    "description": "Per-test timeout in seconds when run_tests is set (overrides server default)",
                },
                "verbose": {
                    "type": "boolean",
                    "description": "Enable verbose output",
                },
                "capture_output": {
                    "type": "integer",
                    "description": "Include last N lines of raw output in response",
                },
            },
        },
    },
    "test": {
        "description": "Run already-built tests using ctest (no rebuild). Use 'build' first to compile. Operates on the project root set by the most recent configure call.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "targets": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Specific targets to test (matched as ctest labels via -L)",
                },
                "regex": {
                    "type": "string",
                    "description": "Test name pattern to match (passed to ctest -R)",
                },
                "capture_output": {
                    "type": "integer",
                    "description": "Include last N lines of raw output in response",
                },
                "timeout": {
                    "type": "integer",
                    "description": "Per-test timeout in seconds (overrides server default)",
                },
            },
        },
    },
}


def _add_failure_details(response, result):
    """Explain a failure in the tool response.

    `_extract_error_lines` only recognises compiler-shaped output, so it
    finds nothing in the server's own diagnostics ("bbs_build not found",
    "Build directory does not exist"). Those arrive on stderr, so prefer
    it verbatim and fall back to scraping stdout.
    """
    if result.success:
        return
    if result.stderr.strip():
        response["error_details"] = [{"message": result.stderr.strip()}]
        response["errors"] = 1
        return
    details = _extract_error_lines(result.stdout)
    if details:
        response["error_details"] = details
        response["errors"] = len(details)


_REFROOT_HINT = (
    "Install one with `berg export-deps -o <path>` (give it a real path, "
    "not a symlink), or pass refroot=<path> to configure if one already "
    "exists elsewhere."
)


def _missing_refroot_message(refroot) -> str:
    return f"Refroot does not exist: {refroot}\n{_REFROOT_HINT}"


def _tool_failure(message: str) -> Dict:
    """A failure detected before, or instead of, running anything.

    Same shape as a post-run failure, so a caller parsing these does not
    have to special-case them.
    """
    return {
        "status": "failed",
        "duration_seconds": 0,
        "project_root": str(executor.project_root),
        "build_dir": str(executor.resolved_build_dir()),
        "refroot": str(executor.effective_refroot()),
        "message": message,
    }


def _handle_tool_call(name, arguments):
    """Handle a tools/call request, return the response content.

    Conditions the server knows how to describe - a --ufid conflict, an
    incomplete inherited environment, an unusable path - are reported in
    the standard failure shape rather than as a bare {"error": ...} from
    the protocol layer, which would drop project_root, build_dir and
    refroot and so break the promise that any response says which build
    it is talking about. Only 'build' and 'test' were affected, having no
    pre-flight of their own.

    Anything else propagates: an unexpected exception is a defect here,
    and should stay distinguishable from a build that would not start.
    """
    try:
        return _dispatch_tool_call(name, arguments)
    except (RuntimeError, OSError) as exc:
        return _tool_failure(str(exc))


def _dispatch_tool_call(name, arguments):
    if name == "configure":
        new_root = arguments.get("project_root")
        if new_root:
            if executor.in_bbs_env:
                # The inherited BDE_CMAKE_BUILD_DIR is an absolute path
                # naming one specific project; honoring a root switch would
                # build the new project into the old project's tree.
                return _tool_failure(
                    "project_root cannot be changed while inheriting a "
                    "bbs environment (BDE_CMAKE_BUILD_DIR="
                    f"{os.getenv('BDE_CMAKE_BUILD_DIR')}).\n"
                    "Restart the server from a clean shell, or with "
                    "--ignore-bbs-env to derive the build directory from "
                    "the project root."
                )
            try:
                executor.set_project_root(Path(new_root))
            except OSError as exc:
                # set_project_root chdirs; a bad path would otherwise
                # surface as a bare errno through the generic handler,
                # in a shape unlike every other failure here.
                # Name the path that actually failed. Resolution touches
                # more than new_root (the _build symlink, /build), and
                # blaming new_root for someone else's ENOENT sends the
                # caller off checking a directory that is fine.
                culprit = exc.filename or new_root
                return _tool_failure(
                    f"Cannot use project_root {new_root}: {exc.strerror}"
                    + (f" ({culprit})" if str(culprit) != str(new_root) else "")
                    + ".\nCheck the path exists and is a directory."
                )

        new_refroot = arguments.get("refroot")
        if new_refroot:
            # Resolve exactly as --refroot is resolved. Stored raw, a
            # relative override was exported as a relative
            # DISTRIBUTION_REFROOT, which the cmake toolchain then read
            # with the *build* directory as its cwd.
            candidate = Path(new_refroot)
            if not candidate.is_absolute():
                candidate = (executor.project_root / candidate).resolve()
            # Validate before committing. An override that is stored and
            # then rejected stays in place, so every later call fails the
            # same way with nothing to say a previous call caused it.
            unusable = executor.unusable_refroot(candidate)
            if unusable:
                return _tool_failure(
                    f"{unusable}\n{_REFROOT_HINT}"
                )
            # Held as if it had been given on the command line, so it
            # survives re-resolution and a later project_root switch.
            executor.cli_refroot = candidate

        # Re-derive before doing anything. Startup resolution is a snapshot:
        # a refroot installed since - often in response to this server's own
        # "run berg export-deps" message - would otherwise stay invisible
        # until the session was restarted.
        executor.resolve(executor.project_root)

        if executor.refroot is not None and not executor.refroot.exists():
            return _tool_failure(
                _missing_refroot_message(executor.refroot)
            )

        if arguments.get("force") and executor.build_dir_inherited:
            # force deletes the build tree outright. When the directory came
            # from $BDE_CMAKE_BUILD_DIR the launching shell chose it, not
            # this server, and the value is whatever that shell happened to
            # hold - so a wrong or over-broad one would be removed on the
            # say-so of the model rather than the user. Refuse and let the
            # user do it deliberately.
            return _tool_failure(
                "Refusing force=true: the build directory was inherited from "
                "the bbs environment ($BDE_CMAKE_BUILD_DIR), so this server "
                "did not choose it and will not delete it.\n"
                "Remove it yourself if that is what you want:\n"
                f"    rm -rf {executor.resolved_build_dir()}\n"
                "Or relaunch the server with --ignore-bbs-env, which makes "
                "it derive - and own - the build directory."
            )

        result = executor.configure(force=arguments.get("force", False))

        response = {
            "status": "success" if result.success else "failed",
            "duration_seconds": result.duration_seconds,
            "project_root": str(executor.project_root),
            "build_dir": str(executor.resolved_build_dir()),
            "refroot": str(executor.effective_refroot()),
            "message": "Configuration complete"
            if result.success
            else "Configuration failed",
        }

        # Surface the refroot-less warning per call: the startup log is not
        # visible to the caller.
        if executor._refroot_warning:
            response["warning"] = executor._refroot_warning

        _add_failure_details(response, result)

        capture = arguments.get("capture_output")
        if capture:
            response["raw_output"] = _tail(result.stdout + result.stderr, capture)

    elif name == "build":
        if arguments.get("targets") and arguments.get("dependers_of"):
            # bbs_build declares these mutually exclusive and exits with an
            # argparse usage error; say so plainly instead.
            return _tool_failure(
                "targets and dependers_of cannot be combined: dependers_of "
                "selects its own targets (everything that depends on the "
                "components named). Pass one or the other."
            )
        result = executor.build(
            targets=arguments.get("targets"),
            verbose=arguments.get("verbose", False),
            with_tests=arguments.get("with_tests", False),
            dependers_of=arguments.get("dependers_of"),
            run_tests=arguments.get("run_tests", False),
            timeout=arguments.get("timeout"),
        )

        response = {
            "status": "success" if result.success else "failed",
            "project_root": str(executor.project_root),
            "build_dir": str(executor.resolved_build_dir()),
            "refroot": str(executor.effective_refroot()),
            "errors": result.errors,
            "warnings": result.warnings,
            "duration_seconds": result.duration_seconds,
            "error_details": result.error_details,
        }

        if arguments.get("run_tests"):
            response["total"] = result.total_tests
            response["passed"] = result.passed_tests
            response["skipped"] = result.skipped_tests
            response["failed"] = len(result.failed_tests)
            response["failed_tests"] = result.failed_tests
            # Same false pass the 'test' tool guards against: bbs_build runs
            # ctest, which exits 0 on "No tests were found!!!", so a build
            # whose targets have no tests would report a clean run.
            if result.success and result.total_tests == 0:
                selector = [
                    f"{key}={arguments[key]}"
                    for key in ("targets", "dependers_of")
                    if arguments.get(key)
                ]
                response["status"] = "failed"
                response["message"] = (
                    "Build succeeded, but no tests ran"
                    + (f" for {' and '.join(selector)}" if selector else "")
                    + ". Check the target names; a target with no test "
                    "driver has nothing to run."
                )

        if not result.success and not result.error_details:
            _add_failure_details(response, result)

        capture = arguments.get("capture_output")
        if capture:
            response["raw_output"] = _tail(result.stdout + result.stderr, capture)

    elif name == "test":
        result = executor.run_tests(
            targets=arguments.get("targets"),
            regex=arguments.get("regex"),
            timeout=arguments.get("timeout"),
        )

        # ctest exits 0 when a filter matches nothing ("No tests were
        # found!!!"), which would otherwise be reported as a run in which
        # everything passed - so a typo'd component reads as success.
        # Running no tests is not passing.
        ran_nothing = result.success and result.total_tests == 0

        response = {
            "status": "failed" if ran_nothing or not result.success else "success",
            "project_root": str(executor.project_root),
            "build_dir": str(executor.resolved_build_dir()),
            "refroot": str(executor.effective_refroot()),
            "total": result.total_tests,
            "passed": result.passed_tests,
            "skipped": result.skipped_tests,
            "failed": len(result.failed_tests),
            "failed_tests": result.failed_tests,
            "duration_seconds": result.duration_seconds,
        }

        if ran_nothing:
            selector = []
            if arguments.get("targets"):
                selector.append(f"targets={arguments['targets']}")
            if arguments.get("regex"):
                selector.append(f"regex={arguments['regex']!r}")
            response["message"] = (
                "No tests ran"
                + (f" matching {' and '.join(selector)}" if selector else "")
                + ". Check the name, or build the test drivers first with "
                "build(with_tests=true)."
            )
        elif not result.success:
            # Not just when nothing ran: a run that failed *and* reported
            # tallies still has to say why - a crashed or aborted ctest is
            # the case where the reason matters most.
            _add_failure_details(response, result)

        capture = arguments.get("capture_output")
        if capture:
            response["raw_output"] = _tail(result.stdout + result.stderr, capture)

    else:
        raise ValueError(f"Unknown tool: {name}")

    return response


def _handle_request(request):
    """Handle a single JSON-RPC request, return the response dict or None."""
    method = request.get("method", "")
    params = request.get("params", {})
    req_id = request.get("id")

    # A notification carries no id and must never be answered. Only
    # notifications/initialized was special-cased, so the standard
    # notifications/cancelled drew an "Unknown method" reply - a protocol
    # violation, and one an MCP host can log as an error.
    if method.startswith("notifications/") or "id" not in request:
        return None

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "bbs-build", "version": "1.0.0"},
            },
        }

    if method == "notifications/initialized":
        return None

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "tools": [
                    {
                        "name": n,
                        "description": t["description"],
                        "inputSchema": t["inputSchema"],
                    }
                    for n, t in TOOLS.items()
                ]
            },
        }

    if method == "tools/call":
        tool_name = params.get("name")
        tool_args = params.get("arguments", {})
        try:
            response = _handle_tool_call(tool_name, tool_args)
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {"type": "text", "text": json.dumps(response, indent=2)}
                    ],
                    "isError": False,
                },
            }
        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({"error": str(e)}, indent=2),
                        }
                    ],
                    "isError": True,
                },
            }

    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": -32601, "message": f"Unknown method: {method}"},
    }


def main():
    import argparse

    parser = argparse.ArgumentParser(description="BBS Build MCP Server")
    parser.add_argument(
        "--project-root", help="Project root directory (will chdir to this)"
    )
    parser.add_argument(
        "--ufid",
        help="Build configuration (default: dbg). Examples: dbg, opt, "
        "opt_dbg, opt_exc_mt. When a bbs environment is inherited this "
        "must name the same configuration, or be paired with "
        "--ignore-bbs-env.",
    )
    parser.add_argument(
        "--build-dir",
        help="Build directory base; absolute, or relative to the project "
        "root. Default: $BDE_CMAKE_BUILD_DIR when a bbs environment is "
        "adopted, else an existing _build, else /build/<project>, else "
        "<root>/_build.",
    )
    parser.add_argument(
        "--refroot",
        help="Refroot; absolute or relative to the project root. Default: "
        "$DISTRIBUTION_REFROOT, else _refroot, else /workarea/rr/<project>, "
        "else /. Overridden at runtime via configure(refroot=...).",
    )
    parser.add_argument(
        "--test-timeout",
        type=int,
        default=600,
        help="Default per-test timeout in seconds (default: 600)",
    )
    parser.add_argument(
        "--ignore-bbs-env",
        action="store_true",
        help="Ignore BBS_ENV_MARKER and the BDE_CMAKE_* variables in the "
        "environment; always derive. Use when the shell holds a stale or "
        "unrelated bbs environment, or to build a --ufid other than the "
        "inherited one. Does not affect DISTRIBUTION_REFROOT.",
    )
    args = parser.parse_args()

    project_root = Path(args.project_root or ".")

    # Initialize global executor
    global executor
    executor = BbsBuildExecutor(
        Path(args.refroot) if args.refroot else None,
        Path(args.build_dir) if args.build_dir else None,
        args.ufid,
        args.test_timeout,
        ignore_bbs_env=args.ignore_bbs_env,
    )


    executor.set_project_root(project_root.resolve())

    log.info("BBS Build MCP Server started")
    log.info("Project root: %s", executor.project_root)
    log.info("Build dir: %s", executor.build_dir)
    log.info("Build command: %s", executor.bbs_build or "<not found>")
    if executor.in_bbs_env:
        log.info(
            "Environment: inherited (BBS_ENV_MARKER set), UPLID=%s UFID=%s",
            os.getenv("BDE_CMAKE_UPLID", "<unset>"),
            os.getenv("BDE_CMAKE_UFID", "<unset>"),
        )
    else:
        # Say why, when there was an inherited environment to adopt.
        reason = " (--ignore-bbs-env)" if os.getenv("BBS_ENV_MARKER") else ""
        log.info("Environment: derived%s, UFID=%s", reason, executor.ufid)
    log.info("Refroot: %s", executor.refroot or "<unspecified>, defaults to /")
    if executor._refroot_warning:
        log.warning("%s", executor._refroot_warning)

    # Stdin/stdout JSON-RPC loop
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
            except ValueError as exc:
                # A truncated or corrupt line used to be logged to stderr
                # and otherwise ignored, leaving a client that had sent an
                # id waiting for a reply that never came.
                sys.stdout.write(
                    json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": None,
                            "error": {
                                "code": -32700,
                                "message": f"Parse error: {exc}",
                            },
                        }
                    )
                    + "\n"
                )
                sys.stdout.flush()
                continue
            response = _handle_request(request)
            if response is not None:
                sys.stdout.write(json.dumps(response) + "\n")
                sys.stdout.flush()
        except KeyboardInterrupt:
            break
        except Exception as e:
            log.error("Server error: %s", e)


if __name__ == "__main__":
    main()

# -----------------------------------------------------------------------------
# Copyright 2026 Bloomberg Finance L.P.
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
