"""
Tests for the bbs_build_mcp resolution rules.

Covers how the build directory, the refroot, and the build environment are
resolved from the three possible sources - an explicit command-line
argument, the inherited environment, and a derived default - plus the tool
lookup that hangs off the resolved refroot.

Run with:  python3 -m unittest bbs.mcp.test_bbs_build_mcp
(from lib/python, or with lib/python on PYTHONPATH)
"""

import logging
import os
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from bbs.mcp.bbs_build_mcp import BbsBuildExecutor

# What `bbs_build_env` exports. DISTRIBUTION_REFROOT is deliberately absent:
# bbs_build_env only ever reads it.
BBS_VARS = (
    "BBS_ENV_MARKER",
    "BDE_CMAKE_UPLID",
    "BDE_CMAKE_UFID",
    "BDE_CMAKE_BUILD_DIR",
    "BDE_CMAKE_TOOLCHAIN",
    "BDE_CMAKE_INSTALL_DIR",
    "DISTRIBUTION_REFROOT",
)

UPLID = "unix-linux-x86_64-5.14.0-BBToolchain64"
UFID = "opt_64"


class ResolutionTestCase(unittest.TestCase):
    """Builds a scratch project tree and neutralizes the ambient bbs env."""

    def setUp(self):
        # The server logs its resolution decisions at INFO; keep that out of
        # the test output.
        logging.disable(logging.CRITICAL)
        self.addCleanup(logging.disable, logging.NOTSET)

        self.tmp = Path(tempfile.mkdtemp(prefix="bbs_mcp_test_"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

        self.project = self.tmp / "proj"
        self.project.mkdir()
        (self.project / "CMakeLists.txt").touch()

        # Restore both the environment and the cwd: set_project_root chdirs.
        self._saved_env = {k: os.environ.get(k) for k in BBS_VARS}
        self._saved_cwd = os.getcwd()
        self.addCleanup(self._restore)
        for key in BBS_VARS:
            os.environ.pop(key, None)

    def _restore(self):
        os.chdir(self._saved_cwd)
        for key, value in self._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def inherit_bbs_env(self, build_dir=None):
        """Simulate `eval $(bbs_build_env ...)`."""
        os.environ["BBS_ENV_MARKER"] = "ON"
        os.environ["BDE_CMAKE_UPLID"] = UPLID
        os.environ["BDE_CMAKE_UFID"] = UFID
        os.environ["BDE_CMAKE_BUILD_DIR"] = str(
            build_dir or self.tmp / "ide_build" / f"{UPLID}-{UFID}"
        )

    def make_refroot(self, path):
        """Create a refroot holding the tools the server looks for."""
        path = Path(path)
        for subpath in (
            BbsBuildExecutor.BBS_BUILD_SUBPATH,
            BbsBuildExecutor.CTEST_SUBPATH,
        ):
            tool = path / subpath
            tool.parent.mkdir(parents=True, exist_ok=True)
            tool.write_text("#!/bin/sh\n")
            tool.chmod(0o755)
        return path

    def executor(self, **kwargs):
        ex = BbsBuildExecutor(**kwargs)
        ex.set_project_root(self.project)
        return ex

    @staticmethod
    def global_build_available():
        return Path("/build").is_dir() and os.access("/build", os.W_OK)


class TestBuildDirResolution(ResolutionTestCase):
    """--build-dir > $BDE_CMAKE_BUILD_DIR > existing _build > /build > _build"""

    def test_cli_relative_wins_over_everything(self):
        # Regression: a relative --build-dir used to be discarded whenever
        # /build was writable, so only an absolute one had any effect.
        self.inherit_bbs_env()
        ex = self.executor(cli_build_dir=Path("mybuild"))
        self.assertEqual(ex.build_dir, self.project / "mybuild")

    def test_cli_absolute_wins(self):
        self.inherit_bbs_env()
        target = self.tmp / "elsewhere"
        ex = self.executor(cli_build_dir=target)
        self.assertEqual(ex.build_dir, target)

    def test_inherited_build_dir_used_verbatim(self):
        # It already carries the <uplid>-<ufid> suffix.
        inherited = self.tmp / "ide_build" / f"{UPLID}-{UFID}"
        self.inherit_bbs_env(build_dir=inherited)
        self.assertEqual(self.executor().build_dir, inherited)

    def test_inherited_build_dir_ignored_when_opted_out(self):
        self.inherit_bbs_env()
        ex = self.executor(ignore_bbs_env=True)
        self.assertNotEqual(ex.build_dir, Path(os.environ["BDE_CMAKE_BUILD_DIR"]))

    def test_cli_build_dir_takes_the_uplid_ufid_suffix_when_inheriting(self):
        # --build-dir is a base in both modes, so it gets the same
        # <uplid>-<ufid> suffix - here from the inherited values.
        self.inherit_bbs_env()
        ex = self.executor(cli_build_dir=Path("mybuild"))
        ex._setup_environment()
        self.assertEqual(
            ex._env["BDE_CMAKE_BUILD_DIR"],
            str(self.project / "mybuild" / f"{UPLID}-{UFID}"),
        )

    def test_existing_real_build_dir_beats_global_build(self):
        (self.project / "_build").mkdir()
        self.assertEqual(self.executor().build_dir, self.project / "_build")

    def test_build_symlink_does_not_count_as_existing(self):
        # The symlink is this code's own bookkeeping for the /build case;
        # treating it as a pre-existing _build would pin the build dir to
        # the symlink and stop the target from ever being refreshed.
        (self.project / "_build").symlink_to(self.tmp / "somewhere")
        ex = self.executor()
        self.assertNotEqual(ex.build_dir, self.project / "_build")

    def test_falls_back_to_local_build(self):
        ex = self.executor()
        if self.global_build_available():
            self.assertEqual(ex.build_dir.parent, Path("/build"))
        else:
            self.assertEqual(ex.build_dir, self.project / "_build")

    def test_global_build_is_signposted_by_a_symlink(self):
        # /build/<project> is the one location the server picks without
        # being told to, so it leaves a _build symlink: the user can still
        # point ninja or ctest at _build without knowing where it went.
        if not self.global_build_available():
            self.skipTest("/build is not writable here")
        ex = self.executor()
        symlink = self.project / "_build"
        self.assertTrue(symlink.is_symlink())
        self.assertEqual(os.readlink(symlink), str(ex.build_dir))

    def test_stale_symlink_is_repointed(self):
        if not self.global_build_available():
            self.skipTest("/build is not writable here")
        symlink = self.project / "_build"
        symlink.symlink_to(self.tmp / "stale")
        ex = self.executor()
        self.assertEqual(os.readlink(symlink), str(ex.build_dir))

    def test_no_symlink_planted_for_an_explicit_build_dir(self):
        # The user named the location, so there is nothing to signpost - and
        # planting a symlink they did not ask for would be surprising.
        self.executor(cli_build_dir=Path("mybuild"))
        self.assertFalse((self.project / "_build").exists())

    def test_no_symlink_planted_for_an_inherited_build_dir(self):
        self.inherit_bbs_env()
        self.executor()
        self.assertFalse((self.project / "_build").exists())


class TestRefrootResolution(ResolutionTestCase):
    """--refroot > $DISTRIBUTION_REFROOT > <root>/_refroot > /workarea/rr"""

    def test_cli_refroot_wins(self):
        chosen = self.make_refroot(self.tmp / "cli_rr")
        self.make_refroot(self.project / "_refroot")
        os.environ["DISTRIBUTION_REFROOT"] = str(self.tmp / "env_rr")
        self.assertEqual(self.executor(cli_refroot=chosen).refroot, chosen)

    def test_env_refroot_beats_local(self):
        chosen = self.make_refroot(self.tmp / "env_rr")
        self.make_refroot(self.project / "_refroot")
        os.environ["DISTRIBUTION_REFROOT"] = str(chosen)
        self.assertEqual(self.executor().refroot, chosen)

    def test_env_refroot_survives_ignore_bbs_env(self):
        # DISTRIBUTION_REFROOT is not part of the bbs environment, so
        # --ignore-bbs-env must not suppress it.
        chosen = self.make_refroot(self.tmp / "env_rr")
        os.environ["DISTRIBUTION_REFROOT"] = str(chosen)
        self.assertEqual(self.executor(ignore_bbs_env=True).refroot, chosen)

    def test_local_refroot_detected(self):
        chosen = self.make_refroot(self.project / "_refroot")
        self.assertEqual(self.executor().refroot, chosen)

    def test_root_valued_env_refroot_does_not_disable_detection(self):
        # A Bloomberg dev space exports DISTRIBUTION_REFROOT=/ by default.
        # "/" means "no refroot, use the system /opt/bb", so it must not be
        # taken as naming one - that would skip _refroot for every project.
        chosen = self.make_refroot(self.project / "_refroot")
        for value in ("/", "", "  "):
            with self.subTest(value=repr(value)):
                os.environ["DISTRIBUTION_REFROOT"] = value
                self.assertEqual(self.executor().refroot, chosen)

    def test_root_valued_env_refroot_still_falls_back(self):
        os.environ["DISTRIBUTION_REFROOT"] = "/"
        ex = self.executor()
        self.assertIsNone(ex.refroot)
        self.assertIn("defaulting the refroot to /", ex._refroot_warning)

    def test_deliberate_env_refroot_is_not_stepped_over(self):
        # Only "" and "/" are treated as the machine default. Any other
        # value was set by someone, so a broken one is surfaced rather than
        # silently replaced by whatever detection happens to find.
        self.make_refroot(self.project / "_refroot")
        missing = self.tmp / "gone"
        os.environ["DISTRIBUTION_REFROOT"] = str(missing)
        ex = self.executor()
        self.assertEqual(ex.refroot, missing)
        self.assertFalse(ex.refroot.exists())

    def test_missing_cli_refroot_is_not_stepped_over(self):
        # Unlike the ambient variable, --refroot was chosen for this run:
        # it is reported rather than silently replaced by detection.
        self.make_refroot(self.project / "_refroot")
        missing = self.tmp / "gone"
        ex = self.executor(cli_refroot=missing)
        self.assertEqual(ex.refroot, missing)
        self.assertFalse(ex.refroot.exists())

    def test_explicit_cli_root_refroot_is_honored(self):
        # Unlike the ambient default, --refroot / is a deliberate choice.
        self.make_refroot(self.project / "_refroot")
        ex = self.executor(cli_refroot=Path("/"))
        self.assertEqual(ex.refroot, Path("/"))

    def test_unresolved_refroot_defaults_to_root(self):
        # Left unspecified, meaning "/" - the same default bbs_build applies
        # via `options.refroot or "/"`.
        ex = self.executor()
        self.assertIsNone(ex.refroot)
        self.assertEqual(ex._refroot_args(), [])
        self.assertEqual(ex._tool_bases(), [Path("/")])
        self.assertIn("defaulting the refroot to /", ex._refroot_warning)

    def test_refroot_passed_to_bbs_build_when_present(self):
        chosen = self.make_refroot(self.project / "_refroot")
        self.assertEqual(
            self.executor()._refroot_args(), ["--refroot", str(chosen)]
        )


class TestToolLookup(ResolutionTestCase):
    """<refroot>/opt/bb/... per candidate refroot, then PATH."""

    def test_tools_found_in_refroot(self):
        refroot = self.make_refroot(self.project / "_refroot")
        ex = self.executor()
        self.assertEqual(
            ex.bbs_build, refroot / BbsBuildExecutor.BBS_BUILD_SUBPATH
        )
        self.assertEqual(
            ex._find_tool("ctest", BbsBuildExecutor.CTEST_SUBPATH),
            refroot / BbsBuildExecutor.CTEST_SUBPATH,
        )

    def test_falls_back_to_path(self):
        # No refroot, and /opt/bb has no such tool: PATH is the last resort,
        # which is what platforms without /opt/bb rely on.
        ex = self.executor()
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        tool = bin_dir / "totally_not_a_real_tool"
        tool.write_text("#!/bin/sh\n")
        tool.chmod(0o755)
        os.environ["PATH"] = f"{bin_dir}{os.pathsep}{os.environ['PATH']}"
        self.addCleanup(
            os.environ.__setitem__,
            "PATH",
            os.environ["PATH"].split(os.pathsep, 1)[1],
        )
        self.assertEqual(
            ex._find_tool("totally_not_a_real_tool", "opt/bb/bin/nope"),
            tool,
        )

    def test_missing_tool_reports_every_location_tried(self):
        ex = self.executor()
        message = ex._tool_not_found_message("bbs_build", "opt/bb/bin/nope")
        self.assertIn("/opt/bb/bin/nope", message)
        self.assertIn("on PATH", message)
        # ... and the refroots we would have accepted.
        self.assertIn(str(self.project / "_refroot"), message)


class TestEnvironmentAdoption(ResolutionTestCase):
    """BBS_ENV_MARKER decides whether we adopt or derive."""

    def test_adopts_inherited_configuration(self):
        self.inherit_bbs_env()
        ex = self.executor()
        self.assertTrue(ex.in_bbs_env)
        ex._setup_environment()
        self.assertEqual(ex._env["BDE_CMAKE_UFID"], UFID)
        self.assertEqual(ex._env["BDE_CMAKE_UPLID"], UPLID)
        self.assertEqual(
            ex._env["BDE_CMAKE_BUILD_DIR"], os.environ["BDE_CMAKE_BUILD_DIR"]
        )

    def test_matching_ufid_is_not_a_conflict(self):
        # .mcp.json files carry `--ufid dbg` whether or not the session
        # starts inside a bbs shell, so a --ufid naming the configuration
        # we already inherited must simply be adopted.
        self.inherit_bbs_env()
        ex = self.executor(ufid=UFID)
        ex._setup_environment()
        self.assertEqual(ex._env["BDE_CMAKE_UFID"], UFID)

    def test_differing_ufid_conflicts_at_call_time(self):
        # A genuinely different UFID still refuses - but as a reportable
        # error from the call, not by killing the server at startup.
        self.inherit_bbs_env()
        ex = self.executor(ufid="opt_dbg_totally_different")
        with self.assertRaises(RuntimeError) as caught:
            ex._setup_environment()
        self.assertIn("--ignore-bbs-env", str(caught.exception))

    def test_conflicting_ufid_still_starts_the_server(self):
        # Regression: this used to be parser.error() -> exit 2, so a
        # .mcp.json with --ufid left no working server and no visible
        # reason. Construction and root resolution must both survive.
        self.inherit_bbs_env()
        ex = self.executor(ufid="opt_dbg_totally_different")
        self.assertIsNotNone(ex.project_root)
        self.assertIsNotNone(ex.build_dir)

    def test_ufid_allowed_alongside_ignore_bbs_env(self):
        self.inherit_bbs_env()
        ex = self.executor(ufid="dbg_64", ignore_bbs_env=True)
        ex._setup_environment()
        self.assertTrue(ex._env["BDE_CMAKE_UFID"].startswith("dbg_64"))

    def test_ufid_alone_is_fine_without_an_inherited_environment(self):
        ex = self.executor(ufid="dbg_64")
        ex._setup_environment()
        self.assertTrue(ex._env["BDE_CMAKE_UFID"].startswith("dbg_64"))

    def test_locations_may_be_overridden_while_inheriting(self):
        # --refroot and --build-dir name where things live; unlike --ufid
        # they do not contradict the inherited configuration.
        self.inherit_bbs_env()
        refroot = self.make_refroot(self.tmp / "rr")
        ex = self.executor(cli_refroot=refroot, cli_build_dir=Path("mybuild"))
        ex._setup_environment()
        self.assertEqual(ex._env["DISTRIBUTION_REFROOT"], str(refroot))

    def test_ignore_bbs_env_selects_derivation(self):
        self.inherit_bbs_env()
        self.assertFalse(self.executor(ignore_bbs_env=True).in_bbs_env)

    def test_no_marker_means_derivation(self):
        os.environ["BDE_CMAKE_UFID"] = UFID
        self.assertFalse(self.executor().in_bbs_env)

    def test_incomplete_inherited_env_is_rejected(self):
        os.environ["BBS_ENV_MARKER"] = "ON"
        ex = self.executor()
        with self.assertRaises(RuntimeError) as caught:
            ex._setup_environment()
        self.assertIn("BDE_CMAKE_BUILD_DIR", str(caught.exception))

    def test_refroot_published_into_adopted_env(self):
        # DISTRIBUTION_REFROOT is not something bbs_build_env sets, so the
        # refroot we resolved has to be published for the cmake toolchain.
        refroot = self.make_refroot(self.project / "_refroot")
        self.inherit_bbs_env()
        ex = self.executor()
        ex._setup_environment()
        self.assertEqual(ex._env["DISTRIBUTION_REFROOT"], str(refroot))

    def test_no_refroot_leaves_variable_unset(self):
        self.inherit_bbs_env()
        ex = self.executor()
        ex._setup_environment()
        self.assertNotIn("DISTRIBUTION_REFROOT", ex._env)

    def test_inherited_build_dir_is_marked_as_not_ours(self):
        self.inherit_bbs_env()
        self.assertTrue(self.executor().build_dir_inherited)

    def test_derived_build_dir_is_ours(self):
        self.assertFalse(self.executor().build_dir_inherited)

    def test_explicit_build_dir_is_ours_even_while_inheriting(self):
        # --build-dir is the user naming a directory at launch, so the
        # server owns it however the rest of the environment arrived.
        self.inherit_bbs_env()
        ex = self.executor(cli_build_dir=Path("mybuild"))
        self.assertFalse(ex.build_dir_inherited)


class TestForceRefusal(ResolutionTestCase):
    """force=true deletes a tree, so it is refused when we do not own it."""

    def setUp(self):
        super().setUp()
        import bbs.mcp.bbs_build_mcp as module

        self.module = module
        self._saved = module.executor
        self.addCleanup(setattr, module, "executor", self._saved)

    def test_force_is_refused_for_an_inherited_build_dir(self):
        self.inherit_bbs_env()
        ex = self.executor()
        self.module.executor = ex
        inherited = Path(os.environ["BDE_CMAKE_BUILD_DIR"])
        inherited.mkdir(parents=True, exist_ok=True)
        (inherited / "CMakeCache.txt").write_text("stale\n")

        response = self.module._handle_tool_call("configure", {"force": True})

        self.assertEqual(response["status"], "failed")
        self.assertIn("BDE_CMAKE_BUILD_DIR", response["message"])
        self.assertIn("--ignore-bbs-env", response["message"])
        # The point of the refusal: the tree is still there.
        self.assertTrue((inherited / "CMakeCache.txt").is_file())

    def test_refusal_names_the_directory_to_remove(self):
        self.inherit_bbs_env()
        ex = self.executor()
        self.module.executor = ex
        response = self.module._handle_tool_call("configure", {"force": True})
        self.assertIn(str(ex.resolved_build_dir()), response["message"])

    def test_refusal_keeps_the_standard_failure_shape(self):
        self.inherit_bbs_env()
        self.module.executor = self.executor()
        response = self.module._handle_tool_call("configure", {"force": True})
        for key in ("status", "project_root", "build_dir", "refroot", "message"):
            self.assertIn(key, response)

    def test_force_is_allowed_when_we_own_the_build_dir(self):
        # Not inheriting, so the server chose the directory and may clear
        # it. bbs_build is absent, so this fails - but after the deletion,
        # for a different reason than the refusal.
        ex = self.executor(cli_build_dir=self.tmp / "bd")
        ex.bbs_build = None
        self.module.executor = ex
        response = self.module._handle_tool_call("configure", {"force": True})
        self.assertEqual(response["status"], "failed")
        self.assertNotIn("Refusing force=true", response.get("message", ""))


class TestFailureDiagnostics(ResolutionTestCase):
    """A failed call must say why, not just that it failed."""

    def setUp(self):
        super().setUp()
        import bbs.mcp.bbs_build_mcp as module

        self.module = module
        # No refroot is resolvable, and the build dir does not exist, so
        # every tool fails inside the executor rather than in the child.
        self.executor_obj = self.executor(cli_build_dir=self.tmp / "bd")
        # Forced, so the outcome does not depend on whether the host
        # happens to have bde-tools installed under /opt/bb.
        self.executor_obj.bbs_build = None
        self._saved = module.executor
        module.executor = self.executor_obj
        self.addCleanup(setattr, module, "executor", self._saved)

    def test_configure_reports_why_it_failed(self):
        # Regression: the response was just {"status": "failed",
        # "message": "Configuration failed"} - the executor's explanation
        # went to stderr, which the handler dropped.
        response = self.module._handle_tool_call("configure", {})
        self.assertEqual(response["status"], "failed")
        self.assertTrue(response.get("error_details"), response)
        self.assertIn("bbs_build not found", response["error_details"][0]["message"])

    def test_build_reports_why_it_failed(self):
        response = self.module._handle_tool_call("build", {})
        self.assertEqual(response["status"], "failed")
        self.assertIn("bbs_build not found", response["error_details"][0]["message"])

    def test_test_reports_why_it_failed(self):
        response = self.module._handle_tool_call("test", {})
        self.assertEqual(response["status"], "failed")
        self.assertTrue(response.get("error_details"), response)

    def test_configure_supports_capture_output(self):
        response = self.module._handle_tool_call(
            "configure", {"capture_output": 10}
        )
        self.assertIn("raw_output", response)

    def test_configure_declares_capture_output(self):
        self.assertIn(
            "capture_output",
            self.module.TOOLS["configure"]["inputSchema"]["properties"],
        )

    def test_rejected_refroot_override_does_not_persist(self):
        # A stored-then-rejected override stays in place, so every later
        # call fails identically with no hint that an earlier argument is
        # to blame. Validate before committing.
        good = self.make_refroot(self.project / "_refroot")
        ex = self.executor()
        self.module.executor = ex
        before = ex.refroot
        self.assertEqual(before, good)

        response = self.module._handle_tool_call(
            "configure", {"refroot": str(self.tmp / "gone")}
        )
        self.assertEqual(response["status"], "failed")
        self.assertEqual(ex.refroot, before)

    def test_preflight_failure_has_the_same_shape(self):
        # Anything parsing these should not have to special-case the
        # pre-run rejections.
        ex = self.executor()
        self.module.executor = ex
        preflight = self.module._handle_tool_call(
            "configure", {"refroot": str(self.tmp / "gone")}
        )
        for key in ("status", "duration_seconds", "project_root", "build_dir",
                    "message"):
            self.assertIn(key, preflight)

    def test_bad_project_root_keeps_the_failure_shape(self):
        # os.chdir() would otherwise raise and escape as a bare errno via
        # the generic handler, in a shape unlike every other failure.
        ex = self.executor()
        self.module.executor = ex
        response = self.module._handle_tool_call(
            "configure", {"project_root": str(self.tmp / "nope")}
        )
        self.assertEqual(response["status"], "failed")
        for key in ("duration_seconds", "project_root", "build_dir", "message"):
            self.assertIn(key, response)
        self.assertIn("Check the path exists", response["message"])

    def test_reported_build_dir_is_the_resolved_one(self):
        # Clients look here for compile_commands.json and the ctest tree,
        # which live under <base>/<uplid>-<ufid>, not the base.
        self.inherit_bbs_env()
        ex = self.executor()
        ex._setup_environment()
        self.assertEqual(
            ex.resolved_build_dir(), Path(os.environ["BDE_CMAKE_BUILD_DIR"])
        )

    def test_resolved_build_dir_is_stable_before_any_call_succeeds(self):
        # A failure reported on a fresh server must name the same directory
        # a success would, rather than the base -- otherwise the same call
        # answers "where did it build" differently depending on history.
        self.make_refroot(self.project / "_refroot")
        ex = self.executor(cli_build_dir=self.tmp / "bd")
        fresh = ex.resolved_build_dir()
        ex._setup_environment()
        self.assertEqual(fresh, ex.resolved_build_dir())
        self.assertNotEqual(fresh, self.tmp / "bd")

    def test_resolved_build_dir_falls_back_when_unresolvable(self):
        # Nothing to resolve with: report the base rather than raising from
        # a reporting helper.
        ex = self.executor(cli_refroot=self.tmp / "gone", cli_build_dir=self.tmp / "bd")
        self.assertEqual(ex.resolved_build_dir(), self.tmp / "bd")

    def test_targets_built_is_gone(self):
        # "Built target" is Make's phrasing; Ninja is the default generator
        # here, so the field silently read 0 on every build.
        self.assertFalse(hasattr(self.module.BuildResult, "targets_built"))

    def test_every_response_names_the_refroot(self):
        # "Which refroot is this build using?" must be answerable from any
        # response, without reading logs or raw output.
        refroot = self.make_refroot(self.project / "_refroot")
        ex = self.executor()
        ex.bbs_build = None  # make every call fail deterministically
        self.module.executor = ex
        for tool in ("configure", "build", "test"):
            with self.subTest(tool=tool):
                response = self.module._handle_tool_call(tool, {})
                self.assertEqual(response.get("refroot"), str(refroot))

    def test_refroot_reported_as_root_when_unresolved(self):
        ex = self.executor()
        self.assertIsNone(ex.refroot)
        self.assertEqual(ex.effective_refroot(), Path("/"))

    def test_existing_non_refroot_override_does_not_persist(self):
        # /tmp exists but ships no bbs_build. Committing it made every
        # later plain configure fail identically, recoverable only by
        # passing another refroot= -- so validate usability, not existence.
        good = self.make_refroot(self.project / "_refroot")
        not_a_refroot = self.tmp / "plausible"
        (not_a_refroot / "opt" / "bb" / "lib").mkdir(parents=True)
        ex = self.executor()
        self.module.executor = ex

        response = self.module._handle_tool_call(
            "configure", {"refroot": str(not_a_refroot)}
        )
        self.assertEqual(response["status"], "failed")
        self.assertIn("Not a refroot", response["message"])
        self.assertEqual(ex.refroot, good)
        self.assertEqual(ex.bbs_build, good / ex.BBS_BUILD_SUBPATH)

    def test_usable_refroot_override_is_accepted(self):
        other = self.make_refroot(self.tmp / "other_rr")
        self.make_refroot(self.project / "_refroot")
        ex = self.executor()
        self.module.executor = ex
        self.module._handle_tool_call("configure", {"refroot": str(other)})
        self.assertEqual(ex.refroot, other)

    def test_preflight_failure_names_the_refroot(self):
        ex = self.executor()
        self.module.executor = ex
        response = self.module._handle_tool_call(
            "configure", {"refroot": str(self.tmp / "gone")}
        )
        self.assertIn("refroot", response)

    def test_tool_bases_are_deduplicated(self):
        # An explicit --refroot / must not be searched, or reported, twice.
        ex = self.executor(cli_refroot=Path("/"))
        self.assertEqual(ex._tool_bases(), [Path("/")])
        message = ex._tool_not_found_message("bbs_build", ex.BBS_BUILD_SUBPATH)
        self.assertEqual(message.count("/opt/bb/libexec"), 1)


class TestFailureShapeOnException(ResolutionTestCase):
    """A describable failure keeps the standard shape, in all three tools."""

    def setUp(self):
        super().setUp()
        import bbs.mcp.bbs_build_mcp as module

        self.module = module
        self._saved = module.executor
        self.addCleanup(setattr, module, "executor", self._saved)
        # A --ufid that contradicts the inherited environment: the
        # executor raises from _setup_environment, which build and test
        # reach with no pre-flight of their own.
        self.inherit_bbs_env()
        self.module.executor = self.executor(ufid="opt_dbg_totally_different")

    def test_build_reports_the_standard_shape(self):
        response = self.module._handle_tool_call("build", {})
        self.assertEqual(response["status"], "failed")
        for key in ("project_root", "build_dir", "refroot", "message"):
            self.assertIn(key, response)

    def test_test_reports_the_standard_shape(self):
        response = self.module._handle_tool_call("test", {})
        self.assertEqual(response["status"], "failed")
        for key in ("project_root", "build_dir", "refroot", "message"):
            self.assertIn(key, response)

    def test_the_message_explains_the_conflict(self):
        response = self.module._handle_tool_call("build", {})
        self.assertIn("--ignore-bbs-env", response["message"])

    def test_an_unknown_tool_still_raises(self):
        # A defect here must stay distinguishable from a build that would
        # not start, so it is not swallowed into a failure payload.
        with self.assertRaises(ValueError):
            self.module._handle_tool_call("no_such_tool", {})


class TestSkippedTests(unittest.TestCase):
    """A test that did not run did not pass."""

    def setUp(self):
        self.executor = BbsBuildExecutor.__new__(BbsBuildExecutor)
        self.tmp = Path(tempfile.mkdtemp(prefix="bbs_mcp_junit_"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def junit(self, **attrs):
        path = self.tmp / "j.xml"
        pairs = " ".join('%s="%s"' % kv for kv in attrs.items())
        path.write_text(
            '<?xml version="1.0"?>\n<testsuite name="x" %s></testsuite>\n' % pairs
        )
        return path

    def test_skipped_is_not_counted_as_passed(self):
        # Real ctest 4.4.2 shape: three tests, one skipped, one failed.
        parsed = self.executor._parse_junit_xml(
            self.junit(tests=3, failures=1, skipped=1, disabled=0, errors=0)
        )
        self.assertEqual(parsed["total"], 3)
        self.assertEqual(parsed["passed"], 1)
        self.assertEqual(parsed["skipped"], 1)

    def test_disabled_is_not_counted_as_passed(self):
        parsed = self.executor._parse_junit_xml(
            self.junit(tests=4, failures=0, skipped=0, disabled=2, errors=0)
        )
        self.assertEqual(parsed["passed"], 2)
        self.assertEqual(parsed["skipped"], 2)

    def test_errors_are_not_counted_as_passed(self):
        parsed = self.executor._parse_junit_xml(
            self.junit(tests=2, failures=0, skipped=0, disabled=0, errors=1)
        )
        self.assertEqual(parsed["passed"], 1)

    def test_a_clean_run_is_all_passed(self):
        parsed = self.executor._parse_junit_xml(
            self.junit(tests=5, failures=0, skipped=0, disabled=0, errors=0)
        )
        self.assertEqual(parsed["passed"], 5)
        self.assertEqual(parsed["skipped"], 0)

    def test_both_parsers_agree_in_shape(self):
        from_xml = self.executor._parse_junit_xml(self.junit(tests=1, failures=0))
        from_text = self.executor._parse_ctest_output(
            "100% tests passed out of 1\n"
        )
        self.assertEqual(set(from_xml), set(from_text))


class TestJsonRpcProtocol(unittest.TestCase):
    """Notifications get no reply; unparseable input gets one."""

    def setUp(self):
        import bbs.mcp.bbs_build_mcp as module

        self.module = module

    def test_a_notification_is_not_answered(self):
        self.assertIsNone(
            self.module._handle_request(
                {"jsonrpc": "2.0", "method": "notifications/cancelled",
                 "params": {"requestId": 1}}
            )
        )

    def test_initialized_is_still_not_answered(self):
        self.assertIsNone(
            self.module._handle_request(
                {"jsonrpc": "2.0", "method": "notifications/initialized"}
            )
        )

    def test_a_request_without_an_id_is_not_answered(self):
        self.assertIsNone(
            self.module._handle_request({"jsonrpc": "2.0", "method": "tools/list"})
        )

    def test_an_unknown_method_with_an_id_is_answered(self):
        response = self.module._handle_request(
            {"jsonrpc": "2.0", "id": 7, "method": "no/such"}
        )
        self.assertEqual(response["id"], 7)
        self.assertEqual(response["error"]["code"], -32601)


class TestReResolution(ResolutionTestCase):
    """configure re-derives, and a rejected switch changes nothing."""

    def setUp(self):
        super().setUp()
        import bbs.mcp.bbs_build_mcp as module

        self.module = module
        self._saved = module.executor
        self.addCleanup(setattr, module, "executor", self._saved)

    def test_configure_notices_a_refroot_installed_after_startup(self):
        # The server tells the user to run `berg export-deps`. Before this,
        # doing so changed nothing until the session was restarted: every
        # later configure repeated the original "no refroot found".
        ex = self.executor()
        self.module.executor = ex
        self.assertIsNone(ex.refroot)

        installed = self.make_refroot(self.project / "_refroot")
        self.module._handle_tool_call("configure", {})

        self.assertEqual(ex.refroot, installed)

    def test_configure_notices_tools_installed_after_startup(self):
        ex = self.executor()
        self.module.executor = ex
        self.assertIsNone(ex.bbs_build)

        self.make_refroot(self.project / "_refroot")
        self.module._handle_tool_call("configure", {})

        self.assertIsNotNone(ex.bbs_build)

    def test_a_rejected_project_root_changes_nothing(self):
        # Committing the root before resolving left project_root and the
        # cwd on the new project while build_dir and the cached env still
        # belonged to the old one - a build reported against one project
        # compiling into another's tree.
        self.make_refroot(self.project / "_refroot")
        ex = self.executor()
        other = self.tmp / "other"
        other.mkdir()
        before = (ex.project_root, ex.build_dir, ex.refroot, os.getcwd())

        original = ex._resolve_dirs

        def fails_for_other(root):
            if root == other.resolve():
                raise OSError(30, "Read-only file system")
            return original(root)

        ex._resolve_dirs = fails_for_other
        with self.assertRaises(OSError):
            ex.set_project_root(other)

        self.assertEqual(
            (ex.project_root, ex.build_dir, ex.refroot, os.getcwd()), before
        )

    def test_switching_away_from_a_deleted_project_works(self):
        # Regression: the server's cwd is its project root, and a worktree
        # gets removed once its issue is done. getcwd() then raises ENOENT,
        # which the atomic switch hit before touching the new path - so the
        # server could never change projects again, and reported the error
        # against the *new* path, which existed.
        doomed = self.tmp / "issue-1261"
        doomed.mkdir()
        ex = BbsBuildExecutor()
        ex.set_project_root(doomed)
        shutil.rmtree(doomed)

        ex.set_project_root(self.project)

        self.assertEqual(ex.project_root, self.project.resolve())
        self.assertEqual(Path(os.getcwd()), self.project.resolve())

    def test_switch_failure_from_a_deleted_project_still_raises_cleanly(self):
        # With nothing to roll back to, a bad target is still reported as
        # the target's problem.
        doomed = self.tmp / "issue-1261"
        doomed.mkdir()
        ex = BbsBuildExecutor()
        ex.set_project_root(doomed)
        shutil.rmtree(doomed)

        with self.assertRaises(FileNotFoundError) as caught:
            ex.set_project_root(self.tmp / "never-existed")
        self.assertIn("never-existed", caught.exception.filename)

    def test_a_relative_refroot_override_is_resolved(self):
        # Stored raw it was exported as a relative DISTRIBUTION_REFROOT,
        # which cmake reads with the build directory as its cwd.
        self.make_refroot(self.project / "rr")
        ex = self.executor()
        self.module.executor = ex

        response = self.module._handle_tool_call("configure", {"refroot": "rr"})

        self.assertEqual(response["refroot"], str(self.project / "rr"))
        ex._setup_environment()
        self.assertEqual(
            ex._env["DISTRIBUTION_REFROOT"], str(self.project / "rr")
        )

    def test_a_refroot_override_survives_re_resolution(self):
        self.make_refroot(self.project / "rr")
        self.make_refroot(self.project / "_refroot")
        ex = self.executor()
        self.module.executor = ex

        self.module._handle_tool_call("configure", {"refroot": "rr"})
        self.assertEqual(ex.refroot, self.project / "rr")

        # A later plain configure re-derives; the override must outrank
        # the _refroot it would otherwise auto-detect.
        self.module._handle_tool_call("configure", {})
        self.assertEqual(ex.refroot, self.project / "rr")

    def test_a_refroot_override_survives_a_project_switch(self):
        # The schema promises "for this and subsequent operations".
        chosen = self.make_refroot(self.tmp / "shared_rr")
        other = self.tmp / "other"
        other.mkdir()
        ex = self.executor()
        self.module.executor = ex

        self.module._handle_tool_call("configure", {"refroot": str(chosen)})
        self.module._handle_tool_call("configure", {"project_root": str(other)})

        self.assertEqual(ex.refroot, chosen)


class TestDiagnosticParsing(unittest.TestCase):
    """Compiler and linker diagnostics, from gcc and from clang.

    Every fixture is literal output captured from gcc 13.3.1 and
    clang 21.1.2 on Linux. The two word the same failure differently, so
    the patterns key on the markers they share rather than on wording.

    Apple's linker is deliberately not covered: its format could not be
    checked against a real toolchain here. Those failures still reach the
    caller through the stderr fallback in _add_failure_details.
    """

    def setUp(self):
        self.executor = BbsBuildExecutor.__new__(BbsBuildExecutor)

    def test_gcc_missing_header(self):
        errors = self.executor._extract_errors(
            "/t/missing.cpp:1:10: fatal error: nosuch.h: No such file or directory\n"
            "    1 | #include <nosuch.h>\n"
            "      |          ^~~~~~~~~~\n"
            "compilation terminated.\n"
        )
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0]["file"], "/t/missing.cpp")
        self.assertEqual(errors[0]["line"], 1)
        self.assertIn("No such file", errors[0]["message"])
        # The run's trailer is not part of the diagnostic.
        self.assertNotIn("compilation terminated", errors[0]["message"])

    def test_clang_missing_header(self):
        errors = self.executor._extract_errors(
            "/t/missing.cpp:1:10: fatal error: 'nosuch.h' file not found\n"
            "    1 | #include <nosuch.h>\n"
            "      |          ^~~~~~~~~~\n"
            "1 error generated.\n"
        )
        self.assertEqual(len(errors), 1)
        self.assertIn("file not found", errors[0]["message"])
        self.assertNotIn("error generated", errors[0]["message"])

    def test_gcc_syntax_error(self):
        errors = self.executor._extract_errors(
            "/t/syntax.cpp: In function ‘int main()’:\n"
            "/t/syntax.cpp:1:24: error: expected ‘;’ before ‘}’ token\n"
        )
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0]["column"], 24)

    def test_clang_syntax_error(self):
        errors = self.executor._extract_errors(
            "/t/syntax.cpp:1:23: error: expected ';' at end of declaration\n"
        )
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0]["column"], 23)

    def test_gcc_undefined_reference(self):
        # The location is a section offset, not a line: that is what ld
        # prints for an object without debug info, and the old pattern
        # required digits, so the symbol was lost and only collect2's
        # content-free summary survived.
        errors = self.executor._extract_errors(
            "/opt/rh/x/ld: /tmp/cc.o: in function `main':\n"
            "undef.cpp:(.text+0x5): undefined reference to `nowhere()'\n"
            "collect2: error: ld returned 1 exit status\n"
        )
        messages = [e["message"] for e in errors]
        self.assertIn("undefined reference to `nowhere()'", messages)
        self.assertNotIn("line", errors[0])

    def test_clang_undefined_reference(self):
        errors = self.executor._extract_errors(
            "/opt/rh/x/bin/ld: /tmp/undef.o: in function `main':\n"
            "undef.cpp:(.text+0x10): undefined reference to `nowhere()'\n"
            "clang++: error: linker command failed with exit code 1\n"
        )
        messages = [e["message"] for e in errors]
        self.assertIn("undefined reference to `nowhere()'", messages)
        # clang's driver summary, where gcc uses collect2.
        self.assertTrue(any("linker command failed" in m for m in messages))

    def test_undefined_reference_keeps_a_real_line_number(self):
        errors = self.executor._extract_errors(
            "undef.cpp:30: undefined reference to `nowhere()'\n"
        )
        self.assertEqual(errors[0]["line"], 30)

    def test_gcc_driver_error(self):
        errors = self.executor._extract_errors(
            "cc1plus: fatal error: /t/nope.cpp: No such file or directory\n"
            "compilation terminated.\n"
        )
        self.assertEqual(len(errors), 1)
        self.assertIn("cc1plus", errors[0]["message"])

    def test_clang_driver_error(self):
        errors = self.executor._extract_errors(
            "clang++: error: no such file or directory: '/t/nope.cpp'\n"
            "clang++: error: no input files\n"
        )
        self.assertEqual(len(errors), 2)

    def test_a_tool_prefix_is_not_confused_with_a_file(self):
        # "foo.cpp:1:10: error:" must stay a compiler diagnostic, not be
        # read as a tool named "foo.cpp:1:10".
        errors = self.executor._extract_errors(
            "foo.cpp:1:10: error: boom\n"
        )
        self.assertEqual(errors[0]["file"], "foo.cpp")
        self.assertEqual(errors[0]["line"], 1)

    def test_warnings_are_not_counted_as_errors(self):
        errors = self.executor._extract_errors(
            "/t/a.cpp:4:9: warning: unused variable 'x' [-Wunused-variable]\n"
        )
        self.assertEqual(errors, [])

    def test_two_diagnostics_are_not_merged(self):
        errors = self.executor._extract_errors(
            "a.cpp:1:1: error: first\n"
            "b.cpp:2:2: error: second\n"
        )
        self.assertEqual(len(errors), 2)


class TestCtestOutputParsing(unittest.TestCase):
    """Parsing of real `ctest` text output.

    The fixture below is literal output from ctest 4.4.2, kept verbatim
    (tabs and dot padding included) because both bugs it pins were in
    whitespace the code guessed at.
    """

    REAL = (
        "Test project /tmp/fixture/b\n"
        "    Start 1: a_short\n"
        "1/4 Test #1: a_short ..........................   Passed    0.00 sec\n"
        "    Start 2: beta_with_a_much_longer_name\n"
        "2/4 Test #2: beta_with_a_much_longer_name .....***Failed    0.01 sec\n"
        "    Start 3: c_mid_name\n"
        "3/4 Test #3: c_mid_name .......................***Failed    0.00 sec\n"
        "    Start 4: bsl+stdhdrs\n"
        "4/4 Test #4: bsl+stdhdrs ......................   Passed    0.00 sec\n"
        "\n"
        "50% tests passed, 2 tests failed out of 4\n"
        "\n"
        "Total Test time (real) =   0.02 sec\n"
        "\n"
        "The following tests FAILED:\n"
        "\t  2 - beta_with_a_much_longer_name (Failed)\n"
        "\t  3 - c_mid_name (Failed)\n"
        "Errors while running CTest\n"
    )

    def setUp(self):
        self.executor = BbsBuildExecutor.__new__(BbsBuildExecutor)

    def test_failed_names_are_extracted(self):
        # Regression: the old pattern required exactly three dots of
        # padding, so it only ever matched the longest name in a suite -
        # usually none of them. total/passed parsed fine, so the response
        # said "2 failed" with an empty failed_tests.
        parsed = self.executor._parse_ctest_output(self.REAL)
        self.assertEqual(parsed["total"], 4)
        self.assertEqual(parsed["passed"], 2)
        self.assertEqual(
            parsed["failed_tests"],
            ["beta_with_a_much_longer_name", "c_mid_name"],
        )

    def test_failed_count_agrees_with_the_names(self):
        # The response reports len(failed_tests) as "failed", so the two
        # numbers have to come out consistent.
        parsed = self.executor._parse_ctest_output(self.REAL)
        self.assertEqual(
            len(parsed["failed_tests"]), parsed["total"] - parsed["passed"]
        )

    def test_names_survive_without_the_summary_block(self):
        # A run cut short prints per-test lines but no summary block.
        cut = self.REAL.split("The following tests FAILED:")[0]
        parsed = self.executor._parse_ctest_output(cut)
        self.assertEqual(
            parsed["failed_tests"],
            ["beta_with_a_much_longer_name", "c_mid_name"],
        )

    def test_a_name_containing_spaces_is_read_whole(self):
        names = self.executor._failed_test_names(
            "The following tests FAILED:\n\t  2 - my test with spaces (Failed)\n"
        )
        self.assertEqual(names, ["my test with spaces"])

    def test_non_failure_markers_are_counted(self):
        # Not Run and Timeout are failures to ctest; Passed is not.
        out = (
            "1/2 Test #1: gone ....***Not Run    0.00 sec\n"
            "2/2 Test #2: slow ....***Timeout   10.00 sec\n"
            "3/3 Test #3: fine ....   Passed     0.00 sec\n"
        )
        self.assertEqual(self.executor._failed_test_names(out), ["gone", "slow"])

    # Literal ctest 4.4.2 output: one pass, one SKIP_REGULAR_EXPRESSION
    # skip, one failure.
    WITH_SKIP = (
        "1/3 Test #1: ok ...............................   Passed    0.00 sec\n"
        "2/3 Test #2: skipme ...........................***Skipped   0.00 sec\n"
        "3/3 Test #3: bad ..............................***Failed    0.00 sec\n"
        "\n"
        "67% tests passed, 1 tests failed out of 3\n"
        "\n"
        "Total Test time (real) =   0.01 sec\n"
        "\n"
        "The following tests did not run:\n"
        "\t  2 - skipme (Skipped)\n"
        "\n"
        "The following tests FAILED:\n"
        "\t  3 - bad (Failed)\n"
        "Errors while running CTest\n"
    )

    def test_skipped_is_not_counted_as_passed(self):
        # ctest's "67% tests passed" counts the skip as a pass; only the
        # "did not run" block tells them apart. Reported passed: 2 before.
        parsed = self.executor._parse_ctest_output(self.WITH_SKIP)
        self.assertEqual(parsed["total"], 3)
        self.assertEqual(parsed["passed"], 1)
        self.assertEqual(parsed["skipped"], 1)
        self.assertEqual(parsed["failed_tests"], ["bad"])

    def test_a_skip_is_not_a_failure(self):
        parsed = self.executor._parse_ctest_output(self.WITH_SKIP)
        self.assertNotIn("skipme", parsed["failed_tests"])

    def test_an_all_pass_summary_is_counted(self):
        # Literal ctest 4.4.2: with no failures the summary has no
        # ", N tests failed" clause. Requiring it parsed every clean run
        # as total 0, which build(run_tests=true) then reported as "no
        # tests ran".
        parsed = self.executor._parse_ctest_output(
            "1/1 Test #1: a ................................   Passed    0.00 sec\n"
            "\n100% tests passed out of 1\n"
        )
        self.assertEqual((parsed["total"], parsed["passed"]), (1, 1))
        self.assertEqual(parsed["failed_tests"], [])

    def test_a_clean_run_reports_nothing_failed(self):
        clean = (
            "1/1 Test #1: a_short ....   Passed    0.00 sec\n"
            "\n100% tests passed out of 1\n"
        )
        parsed = self.executor._parse_ctest_output(clean)
        self.assertEqual(parsed["failed_tests"], [])
        self.assertEqual(parsed["passed"], 1)


class TestCtestLabelPattern(ResolutionTestCase):
    """Target names become a ctest -L regex, so they must be escaped."""

    def label_args(self, targets):
        refroot = self.make_refroot(self.tmp / "rr")
        ctest = refroot / BbsBuildExecutor.CTEST_SUBPATH
        # Record argv instead of testing, so the -L pattern can be read back
        # exactly as ctest would have received it.
        ctest.write_text(
            "#!/bin/sh\n"
            'for a in "$@"; do echo "$a"; done > ' + str(self.tmp / "argv") + "\n"
            "exit 0\n"
        )
        ctest.chmod(0o755)
        ex = self.executor(cli_refroot=refroot, cli_build_dir=self.tmp / "bd")
        ex._setup_environment()
        Path(ex._env["BDE_CMAKE_BUILD_DIR"]).mkdir(parents=True, exist_ok=True)
        ex.run_tests(targets=targets)
        argv = (self.tmp / "argv").read_text().splitlines()
        return argv[argv.index("-L") + 1]

    def test_metacharacters_in_a_target_are_escaped(self):
        # "^bsl+stdhdrs$" is the regex "bs, one or more l, stdhdrs" - it
        # matches no label, and ctest answers "No tests were found!!!",
        # which the server reports as a bad test name.
        pattern = self.label_args(["bsl+stdhdrs.t"])
        self.assertEqual(pattern, r"^bsl\+stdhdrs$")
        self.assertTrue(re.match(pattern, "bsl+stdhdrs"))

    def test_plain_names_are_still_anchored(self):
        self.assertEqual(self.label_args(["my_component.t"]), "^my_component$")

    def test_several_targets_are_alternated(self):
        pattern = self.label_args(["a+b.t", "c.t"])
        self.assertEqual(pattern, r"^a\+b$|^c$")


class BuildToolTestCase(ResolutionTestCase):
    """Drives the build tool against a fake bbs_build. Holds no tests."""

    def setUp(self):
        super().setUp()
        import bbs.mcp.bbs_build_mcp as module

        self.module = module
        self._saved = module.executor
        self.addCleanup(setattr, module, "executor", self._saved)

    def with_bbs_build(self, script):
        """An executor whose bbs_build runs `script` instead of building."""
        refroot = self.make_refroot(self.tmp / "rr")
        tool = refroot / BbsBuildExecutor.BBS_BUILD_SUBPATH
        tool.write_text(script)
        tool.chmod(0o755)
        ex = self.executor(cli_refroot=refroot, cli_build_dir=self.tmp / "bd")
        self.module.executor = ex
        return ex


class TestBuildRunTests(BuildToolTestCase):
    """build(run_tests=true): bbs_build runs ctest, and we read its output."""

    def test_no_tests_run_is_not_a_pass(self):
        # ctest exits 0 on "No tests were found!!!"; reported as success
        # with total: 0 before.
        self.with_bbs_build(
            '#!/bin/sh\necho "No tests were found!!!"\nexit 0\n'
        )
        response = self.module._handle_tool_call(
            "build", {"targets": ["nosuch.t"], "run_tests": True}
        )
        self.assertEqual(response["status"], "failed")
        self.assertEqual(response["total"], 0)
        self.assertIn("no tests ran", response["message"])
        self.assertIn("nosuch.t", response["message"])

    def test_a_real_run_is_reported(self):
        self.with_bbs_build(
            "#!/bin/sh\n"
            'echo "1/1 Test #1: a ....   Passed    0.00 sec"\n'
            'echo "100% tests passed out of 1"\n'
            "exit 0\n"
        )
        response = self.module._handle_tool_call(
            "build", {"targets": ["a.t"], "run_tests": True}
        )
        self.assertEqual(response["status"], "success")
        self.assertEqual((response["total"], response["passed"]), (1, 1))

    def test_failures_are_named(self):
        self.with_bbs_build(
            "#!/bin/sh\n"
            'echo "1/1 Test #1: a ....***Failed    0.00 sec"\n'
            'echo "0% tests passed, 1 tests failed out of 1"\n'
            "exit 8\n"
        )
        response = self.module._handle_tool_call(
            "build", {"targets": ["a.t"], "run_tests": True}
        )
        self.assertEqual(response["status"], "failed")
        self.assertEqual(response["failed_tests"], ["a"])

    def test_a_plain_build_is_not_held_to_running_tests(self):
        self.with_bbs_build("#!/bin/sh\nexit 0\n")
        response = self.module._handle_tool_call("build", {"targets": ["a"]})
        self.assertEqual(response["status"], "success")
        self.assertNotIn("total", response)

    def test_dependers_of_and_run_tests_reach_bbs_build(self):
        argv = self.tmp / "argv"
        self.with_bbs_build(
            '#!/bin/sh\nfor a in "$@"; do echo "$a"; done > ' + str(argv) + "\n"
            'echo "100% tests passed out of 1"\nexit 0\n'
        )
        self.module._handle_tool_call(
            "build", {"dependers_of": ["bdlt_date"], "run_tests": True}
        )
        args = argv.read_text().split()
        self.assertEqual(args[args.index("--dependers-of") + 1], "bdlt_date")
        self.assertEqual(args[args.index("--tests") + 1], "run")


class TestBuildOptionHandling(BuildToolTestCase):
    """What build() passes on to bbs_build, and what it refuses."""

    def recorded_args(self, arguments, **executor_kwargs):
        argv = self.tmp / "argv"
        ex = self.with_bbs_build(
            '#!/bin/sh\nfor a in "$@"; do echo "$a"; done > ' + str(argv) + "\n"
            'echo "100% tests passed out of 1"\nexit 0\n'
        )
        for key, value in executor_kwargs.items():
            setattr(ex, key, value)
        response = self.module._handle_tool_call("build", arguments)
        args = argv.read_text().split() if argv.exists() else None
        return response, args

    def test_targets_and_dependers_of_are_refused(self):
        # bbs_build declares them mutually exclusive and exits with an
        # argparse usage error; refuse up front, with a plain explanation.
        response, args = self.recorded_args(
            {"targets": ["a.t"], "dependers_of": ["b"], "run_tests": True}
        )
        self.assertEqual(response["status"], "failed")
        self.assertIn("cannot be combined", response["message"])
        self.assertIsNone(args, "bbs_build must not be run at all")
        for key in ("project_root", "build_dir", "refroot"):
            self.assertIn(key, response)

    def test_run_tests_forwards_the_server_timeout(self):
        _, args = self.recorded_args(
            {"targets": ["a.t"], "run_tests": True}, test_timeout=900
        )
        self.assertEqual(args[args.index("--timeout") + 1], "900")

    def test_a_per_call_timeout_overrides_it(self):
        _, args = self.recorded_args(
            {"targets": ["a.t"], "run_tests": True, "timeout": 300},
            test_timeout=900,
        )
        self.assertEqual(args[args.index("--timeout") + 1], "300")

    def test_a_zero_timeout_is_passed_through(self):
        # 0 means "no timeout" to bbs_build; it must not become the default.
        _, args = self.recorded_args(
            {"targets": ["a.t"], "run_tests": True, "timeout": 0}
        )
        self.assertEqual(args[args.index("--timeout") + 1], "0")

    def test_no_timeout_without_run_tests(self):
        _, args = self.recorded_args({"targets": ["a.t"], "with_tests": True})
        self.assertNotIn("--timeout", args)


class TestJunitIsPrivateToTheRun(ResolutionTestCase):
    """A failed run must not inherit the previous run's tallies."""

    JUNIT = (
        '<?xml version="1.0"?>\n'
        '<testsuite name="x" tests="42" failures="0" disabled="0" '
        'skipped="0" errors="0"></testsuite>\n'
    )

    def fake_ctest(self, script):
        """A refroot whose ctest runs `script` instead of testing."""
        refroot = self.make_refroot(self.tmp / "rr")
        ctest = refroot / BbsBuildExecutor.CTEST_SUBPATH
        ctest.write_text(script)
        ctest.chmod(0o755)
        return refroot

    def executor_with(self, script):
        refroot = self.fake_ctest(script)
        build_dir = self.tmp / "bd"
        ex = self.executor(cli_refroot=refroot, cli_build_dir=build_dir)
        ex._setup_environment()
        resolved = Path(ex._env["BDE_CMAKE_BUILD_DIR"])
        resolved.mkdir(parents=True, exist_ok=True)
        return ex, resolved

    def test_a_crashed_ctest_does_not_report_stale_results(self):
        # Regression: the JUnit file lived at a fixed path in the build
        # tree, so a ctest that died before rewriting it left the previous
        # run's file to be parsed as this run's result.
        ex, resolved = self.executor_with(
            '#!/bin/sh\necho "ctest: Segmentation fault" >&2\nexit 139\n'
        )
        (resolved / "test_results.xml").write_text(self.JUNIT)

        result = ex.run_tests()

        self.assertFalse(result.success)
        self.assertEqual(result.total_tests, 0)
        self.assertEqual(result.passed_tests, 0)

    def test_no_junit_file_is_left_in_the_build_tree(self):
        ex, resolved = self.executor_with("#!/bin/sh\nexit 0\n")
        ex.run_tests()
        self.assertFalse((resolved / "test_results.xml").exists())

    def test_the_temporary_directory_is_removed(self):
        before = set(Path(tempfile.gettempdir()).glob("bbs_build_mcp-ctest-*"))
        ex, _ = self.executor_with("#!/bin/sh\nexit 0\n")
        ex.run_tests()
        after = set(Path(tempfile.gettempdir()).glob("bbs_build_mcp-ctest-*"))
        self.assertEqual(before, after)

    def test_output_that_is_not_utf8_is_kept_not_fatal(self):
        # Test drivers can print arbitrary bytes. A strict decode raised
        # UnicodeDecodeError and threw the whole run away.
        ex, _ = self.executor_with(
            "#!/bin/sh\n"
            'printf "1/1 Test #1: x ...***Failed\\n  out: \\377\\376\\n"\n'
            'echo "0% tests passed, 1 tests failed out of 1"\n'
            "exit 8\n"
        )
        result = ex.run_tests()
        self.assertFalse(result.success)
        self.assertEqual(result.total_tests, 1)
        # The bytes survive as escapes rather than being dropped.
        self.assertIn("\\xff\\xfe", result.stdout)

    def test_a_failed_run_with_tallies_still_says_why(self):
        # The failure-details gate used to be `total == 0`, so a run that
        # failed while reporting tallies gave no reason at all.
        import bbs.mcp.bbs_build_mcp as module

        ex, _ = self.executor_with(
            '#!/bin/sh\necho "1/1 Test #1: a ...***Failed  0.0 sec"\n'
            'echo "0% tests passed, 1 tests failed out of 1"\n'
            'echo "ctest: aborting" >&2\nexit 8\n'
        )
        saved = module.executor
        module.executor = ex
        self.addCleanup(setattr, module, "executor", saved)

        response = module._handle_tool_call("test", {})

        self.assertEqual(response["status"], "failed")
        self.assertTrue(response.get("error_details"), response)


if __name__ == "__main__":
    unittest.main()

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
