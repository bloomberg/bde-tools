bbs_build_mcp
=============

MCP (Model Context Protocol) server for BBS build tools. Provides structured
build/test integration for AI coding assistants like Claude Code and GitHub
Copilot in VS Code.

Tools
-----

- **configure** - Configure the build system using CMake
- **build** - Build targets (optionally `dependers_of`, `with_tests`, or
  `run_tests`) with error/warning parsing
- **test** - Run already-built tests via ctest with structured results

All three report `project_root`, `build_dir` and `refroot`, so a caller can
answer "which project, build tree and refroot is this build using?" from any
response, without reading server logs or raw output. An unresolved refroot is
reported as `/`. `build_dir` is the *resolved*
directory — `<base>/<uplid>-<ufid>` — which is where `compile_commands.json`,
build logs and the ctest tree live; `--build-dir` and the `_build` default
name the base it is created under, matching `bbs_build`.

`test` reports a failure when no test matched, rather than a run in which
everything passed: `ctest` exits 0 on "No tests were found!!!", so a typo'd
component would otherwise look like success. Skipped and disabled tests are
reported as `skipped` rather than folded into `passed` — a test that did not
run did not pass.

`build(run_tests=true)` builds and runs the tests in one `bbs_build build
--tests run` step and adds the same `total`/`passed`/`skipped`/`failed`
fields to its response. Combined with `dependers_of=[<component>]` it
validates a change against every component that depends on it.
As with `test`, a run in which no test ran is reported as a failure rather
than a pass.
Its per-test timeout is the server's `--test-timeout`, or `timeout=` per call,
as for `test`. `dependers_of` selects its own targets, so it cannot be
combined with `targets`.

Output of `bbs_build` and `ctest` is mirrored live to the server's stderr,
which MCP clients show as server logs (VS Code: *MCP: List Servers* →
`bbs-build` → *Show Output*), so
long builds show progress while they run.

The server is stateful: `configure` sets the active project root, and
subsequent `build` and `test` calls operate on that same root. To switch
projects, call `configure(project_root=<path>)` again — this re-runs CMake
configuration for the new root before building. Switching roots is refused
when the server inherited a bbs environment (see *Build environment*), since
`BDE_CMAKE_BUILD_DIR` then names one specific project.

Setup for Claude Code
---------------------

Add a `.mcp.json` file to your project root. No `--refroot` or `--build-dir`
args are needed in most cases — the server locates them automatically (see
*Build directory* and *Refroot* below).

```json
{
  "mcpServers": {
    "bbs-build": {
      "command": "<path-to-bde-tools>/contrib/mcp/bbs_build_mcp",
      "args": ["--ufid", "dbg"]
    }
  }
}
```

Restart Claude Code after creating or modifying `.mcp.json`.

Setup for VS Code
-----------------

VS Code reads `.vscode/mcp.json`. Rather than authoring it by hand, let
`bbs_make_vscode` generate it along with the rest of the VS Code project:

```sh
eval $(bbs_build_env -u dbg_64 -p gcc-14)
bbs_make_vscode
code .
```

The generated `.vscode/mcp.json` launches the server with the same
`BBS_ENV_MARKER` / `BDE_CMAKE_*` / `DISTRIBUTION_REFROOT` values the CMake
Tools kit uses, so the server adopts that environment (see *Build
environment*) and builds exactly the configuration the IDE is using.
`bbs_make_vscode` also writes `.vscode/bbs-build.instructions.md`, which
steers Copilot Chat toward the MCP tools instead of raw `cmake`/`ninja`, and
recommends the `GitHub.copilot` and `GitHub.copilot-chat` extensions.

To switch UFID, run the *Set up BDE environment* task (which reruns
`bbs_build_env` and `bbs_make_vscode`), then restart the server (*MCP: List
Servers* → `bbs-build` → *Restart Server*) if VS Code does not do so itself.

Build environment
-----------------

If the server is launched from a shell that has already been set up with
`bbs_build_env` — that is, `BBS_ENV_MARKER` is set — it adopts that
environment verbatim: `BDE_CMAKE_UPLID`, `BDE_CMAKE_UFID`,
`BDE_CMAKE_BUILD_DIR`, `BDE_CMAKE_TOOLCHAIN`, `BDE_CMAKE_INSTALL_DIR`, `CC`
and `CXX` are used as-is, and no UPLID/UFID derivation happens. This is what
lets an IDE (or any `eval $(bbs_build_env ...)` shell) launch the server and
be certain it builds the same configuration the rest of the session uses.

Otherwise the server derives UPLID/UFID itself with the `bbs.env` library,
exactly as `bbs_build_env` would, using `--ufid` (default `dbg`).

An explicit command-line argument always wins over the environment, which
wins over the derived default — the same precedence `bbs_build` applies via
`value_or_env`. Pass `--ignore-bbs-env` to ignore `BBS_ENV_MARKER` and the
`BDE_CMAKE_*` variables entirely; that is the escape hatch for a shell holding
a stale or unrelated bbs environment.

While an inherited environment is being adopted, *locations* may be
overridden but the *configuration* may not:

- `--refroot` / `configure(refroot=...)` and `--build-dir` are accepted. They
  name where things live and do not contradict the inherited configuration.
- `--ufid` is accepted when it names the configuration already inherited —
  `.mcp.json` files carry `--ufid dbg` whether or not the session happens to
  start inside a bbs shell, so that must simply work. A `--ufid` that expands
  to something *different* is refused, because the inherited
  `BDE_CMAKE_BUILD_DIR` belongs to the inherited UFID and building another one
  there would clobber it; add `--ignore-bbs-env` to derive the whole
  environment from `--ufid` instead. The refusal is reported by the failing
  call, not by refusing to start.
- `configure(project_root=...)` is refused for the same reason: the inherited
  build directory names one specific project.
- `configure(force=true)` is refused, because force deletes the build tree
  outright. The launching shell chose that directory and the server did not,
  so removing it stays a deliberate act by the user — the refusal names the
  `rm -rf` to run. Relaunching with `--ignore-bbs-env` makes the server derive
  the build directory, and then it will clear it on request.

`DISTRIBUTION_REFROOT` is deliberately not covered by any of the above; it is
handled separately, see *DISTRIBUTION_REFROOT* below.

Build directory
---------------

The build directory is resolved in this order:

1. `--build-dir`, if given — used as-is, relative to the project root when
   not absolute, and never redirected through `/build`
2. `$BDE_CMAKE_BUILD_DIR`, when a bbs environment is being adopted — used
   verbatim, since it already carries the `<uplid>-<ufid>` suffix
3. an existing `_build` *directory* in the project root — a build tree that
   is already there keeps being used, rather than the build silently moving
   elsewhere. A `_build` *symlink* deliberately does not match here; see
   *The `_build` symlink* below.
4. `/build/<project-path>` — e.g. `/build/workarea-myrepo` — when `/build`
   exists and is writable
5. `<project-root>/_build`

Case 4 keeps build artifacts off the workspace backup path, preventing large
`_build` trees from causing the project directory to be excluded from backups.
It is also the only case where the server picks a directory nobody named, so
it signposts it — see below. The other cases all build where you, your IDE, or
an earlier run already chose, and plant no symlink.

The `_build` symlink
--------------------

When case 4 applies, the server maintains a `_build` symlink in the project
root pointing at the directory it chose. CMake and IDEs keep working, and you
can run `ninja` or `ctest` against `_build` without working out where the
build went.

The symlink is a signpost the server owns, not an input. It is derived from
the project path on every run, and a `_build` symlink pointing somewhere else
is repointed — including one you created yourself. Keeping the derivation
authoritative is what lets the signpost stay true after the build directory
moves; the alternative, following the link, would mean the server could never
correct a stale one it wrote earlier.

So do not use a `_build` symlink to choose where the build goes. Pass
`--build-dir` instead: it wins outright, is never redirected through `/build`,
and plants no symlink. An existing `_build` *directory* is also left alone
and built in, per case 3 above.

Refroot
-------

The server searches for a refroot in this order:

1. `--refroot` (or `configure(refroot=...)`), if given
2. `$DISTRIBUTION_REFROOT`, if set
3. `<project-root>/_refroot`
4. `/workarea/rr/<project-path>`  e.g. `/workarea/rr/workarea-myrepo`

`/workarea/rr/` is berg-compatible (berg requires output paths under
`/workarea`) and sits outside individual project directories, so it does not
inflate per-project backup sizes.

`--refroot` is chosen for the run, so it is honored as given and must exist;
`configure` fails naming it rather than quietly searching on. A
`configure(refroot=...)` override is checked before it is adopted — it has to
be a directory that actually provides `bbs_build`, not merely exist, so a
rejected one cannot leave the server stuck on it.

`$DISTRIBUTION_REFROOT` names a refroot in the same way, with one exception:
`""` and `/` both mean "no refroot, use the system `/opt/bb`", and a Bloomberg
dev space exports `DISTRIBUTION_REFROOT=/` by default. Those are the machine's
default rather than anyone's choice, so they fall through to auto-detection —
taking them as naming a refroot would disable detection for every project on
the box. Any other value was set deliberately, so it is honored as-is and must
exist, exactly like `--refroot`; an explicit `--refroot /` is likewise
deliberate and still honored.

If nothing names a refroot and none is auto-detected, the refroot defaults
to `/` — the same default `bbs_build` applies via `options.refroot or "/"`.
No `-DDISTRIBUTION_REFROOT` is passed, and the prefix resolves to `/opt/bb`.
The `configure` response then carries a `warning`, since for a project that
expects a refroot this usually means `berg export-deps` has not been run.

DISTRIBUTION_REFROOT
--------------------

The server both reads and writes this variable.

As **input** it is the second entry in the refroot search chain above, so a
shell or IDE that already exports it needs no `--refroot`. It is not part of
the bbs environment — `bbs_build_env` never exports it, it only reads it — so
it is honored independently of `BBS_ENV_MARKER` and is unaffected by
`--ignore-bbs-env`.

**Locating tools.** The resolved refroot is the base the server looks under
for the binaries it runs:

```
<refroot>/opt/bb/libexec/bde-tools/bin/bbs_build
<refroot>/opt/bb/bin/ctest
```

Each candidate refroot is tried in turn — an unspecified refroot meaning `/`,
so those resolve to `/opt/bb/...` — and if none hits, the tool is looked up on
`PATH`, which covers platforms with no `/opt/bb` at all. When a tool is found
nowhere, the error lists every location searched.

Note this is the refroot's own copy of `bbs_build`, which may be a different
bde-tools version than the one this MCP server ships in.

**Passing it on.** Whichever refroot was resolved, from any source, is
exported into the environment `bbs_build` runs in, and passed explicitly as
`--refroot` on configure. `bbs_build` turns that into
`-DDISTRIBUTION_REFROOT` and `CMAKE_PREFIX_PATH=<refroot>/opt/bb`, and the BBS
toolchain file reads `$ENV{DISTRIBUTION_REFROOT}` to set compiler paths,
`PKG_CONFIG_SYSROOT_DIR`, and system prefix paths. When no refroot is
resolved the variable is left unset and `bbs_build` applies its own `/`
default.

Options
-------

```
bbs_build_mcp [OPTIONS]

  --project-root DIR     Project root directory (will chdir to this)
  --refroot PATH         Refroot; absolute or relative to the project root.
                         Default: $DISTRIBUTION_REFROOT, else _refroot, else
                         /workarea/rr/<project>, else /.
                         Overridden at runtime via configure(refroot=...).
  --build-dir DIR        Build directory base; absolute, or relative to
                         the project root. Default: $BDE_CMAKE_BUILD_DIR
                         when a bbs environment is adopted, else an existing
                         _build, else /build/<project>, else <root>/_build.
  --ufid UFID            Build configuration (default: dbg)
                         Examples: dbg, opt, opt_dbg, opt_exc_mt
                         When a bbs environment is inherited this must
                         name the same configuration, or be paired with
                         --ignore-bbs-env.
  --test-timeout SECS    Per-test timeout in seconds (default: 600)
  --ignore-bbs-env       Ignore BBS_ENV_MARKER and the BDE_CMAKE_* variables
                         in the environment; always derive. Use when the
                         shell holds a stale or unrelated bbs environment, or
                         to build a --ufid other than the inherited one.
                         Does not affect DISTRIBUTION_REFROOT.
```

Tests
-----

```
cd lib/python && python3 -m unittest bbs.mcp.test_bbs_build_mcp
```

`test_bbs_build_mcp.py` covers the build directory and refroot resolution
rules above, tool lookup, adoption of an inherited bbs environment, and the
failure-reporting paths. Standard-library `unittest`, so it needs nothing
the server itself does not already need.

Requirements
------------

- Python 3.7+ (auto-detected by the wrapper script)
- bde-tools (this package)
- No external Python dependencies
