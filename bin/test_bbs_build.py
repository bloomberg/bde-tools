"""
Tests for how `bbs_build build` handles failures, with and without
`--keep-going`.

`build` runs `cmake --build` and `ctest` as subprocesses.  These tests replace
them (and the CMake cache, the platform helpers, and the depender lookup) with
mocks, so they check which commands run and whether the build fails, without a
build tree.

Run with:  python3 -m unittest test_bbs_build
(from bin)
"""

import argparse
import subprocess
import unittest
from unittest import mock

import bbs_build

# In `BuildTestBase.failing`, stands for every `cmake --build`.
ANY_BUILD = "*"


def make_options(**overrides):
    """
    Return the options for a `bbs_build build` of all targets, running tests
    with `--keep-going`, updated by the specified `overrides`.
    """
    options = argparse.Namespace(
        build_dir="/build",
        config=None,
        verbose=False,
        keep_going=True,
        dependers_of=None,
        tests="run",
        no_missing_target_warning=False,
        targets=None,
        timeout=0,
        xml_report=False,
    )
    for name, value in overrides.items():
        setattr(options, name, value)
    return options


class BuildTestBase(unittest.TestCase):
    """
    Mock what `build` calls: the CMake cache (a Ninja tree), the platform
    helpers, the depender lookup, and `subprocess.run`.

    The fake `subprocess.run` answers `ninja -t targets` with `self.known`.
    It records every other command in `self.commands` by name: the first
    `--target` of a build ("all" if none), or "ctest".  A command whose name
    is in `self.failing` exits 1; one whose name is in `self.raising` raises
    the exception it maps to.
    """

    generator = "Ninja"

    def setUp(self):
        cache_info = mock.Mock(
            generator=self.generator, multiconfig=False, build_type="Debug"
        )
        patches = [
            mock.patch.object(bbs_build, "CacheInfo", return_value=cache_info),
            mock.patch.object(bbs_build, "Platform"),
            mock.patch.object(
                bbs_build,
                "get_dependers",
                return_value=["bsls_a.t", "bsls_b.t"],
            ),
            mock.patch.object(
                bbs_build.subprocess, "run", side_effect=self.fake_run
            ),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

        self.known = "all: phony\n"
        self.failing = set()
        self.raising = {}
        self.commands = []

    def fake_run(self, command, **kwargs):
        if command[-2:] == ["-t", "targets"]:
            return subprocess.CompletedProcess(command, 0, stdout=self.known)

        if command[0] == "ctest":
            name = "ctest"
        elif "--target" in command:
            name = command[command.index("--target") + 1]
        else:
            name = "all"
        self.commands.append(name)

        if name in self.raising:
            raise self.raising[name]
        failed = name in self.failing or (
            name != "ctest" and ANY_BUILD in self.failing
        )
        return subprocess.CompletedProcess(command, 1 if failed else 0)


class BuildTestCase(BuildTestBase):
    """With Ninja, `bbs_build` knows which targets exist."""

    def test_dependers_of_keep_going_runs_tests(self):
        """With `--dependers-of`, a failed build still runs the tests, then fails."""
        self.failing = {ANY_BUILD}
        with self.assertRaisesRegex(RuntimeError, "dependers"):
            bbs_build.build(make_options(dependers_of=["bsls_a"]))
        self.assertEqual(["bsls_a.t", "ctest"], self.commands)

    def test_dependers_of_without_keep_going(self):
        """Without `--keep-going`, a failed build stops before the tests."""
        self.failing = {ANY_BUILD}
        with self.assertRaisesRegex(RuntimeError, "dependers"):
            bbs_build.build(
                make_options(dependers_of=["bsls_a"], keep_going=False)
            )
        self.assertEqual(["bsls_a.t"], self.commands)

    def test_keep_going_build_failure(self):
        """A failed build runs the tests, then fails."""
        self.failing = {"all"}
        with self.assertRaisesRegex(RuntimeError, "'all'"):
            bbs_build.build(make_options())
        self.assertEqual(["all", "ctest"], self.commands)

    def test_keep_going_test_failure(self):
        """Failed tests fail the build."""
        self.failing = {"ctest"}
        with self.assertRaisesRegex(RuntimeError, "Tests failed"):
            bbs_build.build(make_options())

    def test_test_failure_without_keep_going(self):
        """Without `--keep-going`, failed tests fail the build."""
        self.failing = {"ctest"}
        with self.assertRaisesRegex(RuntimeError, "Tests failed"):
            bbs_build.build(make_options(keep_going=False))

    def test_keep_going_target_failure(self):
        """A target that fails to build fails the build, even if its test driver builds."""
        self.known = "bsls: phony\nbsls.t: phony\n"
        self.failing = {"bsls"}
        with self.assertRaisesRegex(RuntimeError, "'bsls'"):
            bbs_build.build(make_options(targets=["bsls"]))
        self.assertEqual(["bsls", "bsls.t", "ctest"], self.commands)

    def test_keep_going_both_targets_fail(self):
        """A failed target and test driver are each reported once."""
        self.known = "bsls: phony\nbsls.t: phony\n"
        self.failing = {ANY_BUILD}
        with self.assertRaises(RuntimeError) as context:
            bbs_build.build(make_options(targets=["bsls"]))
        message = str(context.exception)
        self.assertIn("'bsls'", message)
        self.assertIn("'bsls.t'", message)
        self.assertNotIn("does not exist", message)

    def test_target_failure_without_keep_going(self):
        """
        Without `--keep-going`, a known target that fails to build fails the
        build, even with `--test`, and nothing else runs.
        """
        self.known = "bsls: phony\nbsls.t: phony\n"
        self.failing = {"bsls"}
        with self.assertRaisesRegex(RuntimeError, "'bsls'"):
            bbs_build.build(make_options(targets=["bsls"], keep_going=False))
        self.assertEqual(["bsls"], self.commands)

    def test_all_failure_without_keep_going(self):
        """Without `--keep-going`, a failed `all` stops before the tests."""
        self.failing = {"all"}
        with self.assertRaisesRegex(RuntimeError, "'all'"):
            bbs_build.build(make_options(keep_going=False))
        self.assertEqual(["all"], self.commands)

    def test_keep_going_unknown_target(self):
        """A target that does not exist fails the build."""
        with self.assertRaisesRegex(
            RuntimeError, "'nosuchtarget' does not exist"
        ):
            bbs_build.build(make_options(targets=["nosuchtarget"]))
        self.assertEqual(["ctest"], self.commands)

    def test_test_target_only(self):
        """A `.t` target builds only the test driver."""
        self.known = "bsls.t: phony\n"
        bbs_build.build(make_options(targets=["bsls.t"]))
        self.assertEqual(["bsls.t", "ctest"], self.commands)

    def test_keep_going_success(self):
        bbs_build.build(make_options())
        self.assertEqual(["all", "ctest"], self.commands)

    def test_keep_going_interrupted_build(self):
        """With `--keep-going`, Ctrl-C during the build stops before ctest."""
        self.raising = {"all": KeyboardInterrupt()}
        with self.assertRaises(KeyboardInterrupt):
            bbs_build.build(make_options())
        self.assertEqual(["all"], self.commands)

    def test_keep_going_interrupted_tests(self):
        """With `--keep-going`, Ctrl-C during ctest is not a test failure."""
        self.raising = {"ctest": KeyboardInterrupt()}
        with self.assertRaises(KeyboardInterrupt):
            bbs_build.build(make_options())

    def test_keep_going_missing_cmake(self):
        """With `--keep-going`, a missing `cmake` is not a build failure."""
        self.raising = {"all": FileNotFoundError("cmake")}
        with self.assertRaises(FileNotFoundError):
            bbs_build.build(make_options(tests=None))
        self.assertEqual(["all"], self.commands)


class MakefilesBuildTestCase(BuildTestBase):
    """
    With generators other than Ninja, `bbs_build` cannot list the known
    targets, so a missing target and a failed one look the same.
    """

    generator = "Unix Makefiles"

    def test_keep_going_all_failure(self):
        """A failed `all` fails the build, even if `all.t` builds."""
        self.failing = {"all"}
        with self.assertRaisesRegex(RuntimeError, "'all'"):
            bbs_build.build(make_options())
        self.assertEqual(["all", "all.t", "ctest"], self.commands)

    def test_keep_going_all_failure_build_tests(self):
        """With `--test build`, a failed `all` fails the build."""
        self.failing = {"all"}
        with self.assertRaisesRegex(RuntimeError, "'all'"):
            bbs_build.build(make_options(tests="build"))

    def test_keep_going_all_failure_no_tests(self):
        """Without `--test`, a failed `all` fails the build."""
        self.failing = {"all"}
        with self.assertRaisesRegex(RuntimeError, "'all'"):
            bbs_build.build(make_options(tests=None))

    def test_keep_going_missing_target_with_tests(self):
        """
        A named target that fails while its test driver builds is taken as
        missing: with `--test`, an application target may not exist.
        """
        self.failing = {"bsls"}
        bbs_build.build(make_options(targets=["bsls"]))
        self.assertEqual(["bsls", "bsls.t", "ctest"], self.commands)

    def test_all_failure_without_keep_going(self):
        """
        Without `--keep-going`, a failed `all` fails the build, even if
        `all.t` would build, and the tests do not run.
        """
        self.failing = {"all"}
        with self.assertRaisesRegex(RuntimeError, "'all'"):
            bbs_build.build(make_options(keep_going=False))
        self.assertEqual(["all"], self.commands)

    def test_missing_target_without_keep_going(self):
        """
        Without `--keep-going`, a named target that fails while its test
        driver builds is still taken as missing.
        """
        self.failing = {"bsls"}
        bbs_build.build(make_options(targets=["bsls"], keep_going=False))
        self.assertEqual(["bsls", "bsls.t", "ctest"], self.commands)

    def test_keep_going_test_target_failure(self):
        """A test target that fails to build fails the build."""
        self.failing = {"bsls.t"}
        with self.assertRaisesRegex(RuntimeError, "'bsls.t'"):
            bbs_build.build(make_options(targets=["bsls"]))

    def test_test_target_only(self):
        """A `.t` target builds only the test driver."""
        bbs_build.build(make_options(targets=["bsls.t"]))
        self.assertEqual(["bsls.t", "ctest"], self.commands)

    def test_keep_going_success(self):
        bbs_build.build(make_options())
        self.assertEqual(["all", "all.t", "ctest"], self.commands)


if __name__ == "__main__":
    unittest.main()
