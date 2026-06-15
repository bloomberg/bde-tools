#!/usr/bin/env python3
"""
mutfuzz_sim_cpp11_features.py - Mutation fuzz test comparing Python vs Perl

Unlike the grammar-based fuzzer (fuzz_sim_cpp11_features.py), this fuzzer
starts from a corpus of real BDE headers and applies random mutations to them.
Both scripts are run on the mutated input and their behavior is compared.

Seed corpus: real BDE headers that have _cpp03-generated companions, plus
outputs from the grammar-based fuzzer if available.

Mutation strategies (structure-aware, not pure bit-flipping):
  - delete_line:     Remove a random line
  - duplicate_line:  Duplicate a random line in-place
  - swap_lines:      Swap two adjacent lines
  - insert_blank:    Insert a blank line at a random position
  - corrupt_pp:      Flip bytes in a preprocessor directive
  - truncate:        Truncate file at a random byte offset
  - flip_byte:       Flip a single random byte
  - delete_block:    Delete a contiguous block of 2-10 lines
  - shuffle_block:   Shuffle a contiguous block of 2-5 lines
  - mangle_include:  Corrupt an #include directive
  - strip_copyright: Remove the copyright block at the end
  - inject_var_args: Add/modify a $var-args comment on an #if line
  - toggle_negation: Toggle ! in #if !BSLS_COMPILERFEATURES_SIMULATE...
  - double_region:   Duplicate a #if !SIM...#endif region
  - crlf_inject:     Convert some \\n to \\r\\n

Usage:
    python mutfuzz_sim_cpp11_features.py [options]

Options:
    --iterations N       Number of fuzz iterations (default: 1000)
    --seed N             Random seed for reproducibility
    --corpus-dir DIR     Directory containing seed corpus files
    --auto-corpus        Auto-discover BDE headers with _cpp03 companions
    --bde-root DIR       Root of BDE repo (for auto-corpus discovery)
    --output-dir DIR     Directory for failure artifacts
    --mutations N        Number of mutations per iteration (default: 1-5)
    --timeout N          Per-invocation timeout in seconds (default: 30)
    --verbose            Print each test case
    --stop-on-fail       Stop on first failure
    --workers N          Number of parallel workers
"""

import argparse
import concurrent.futures
import difflib
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Reuse infrastructure from the grammar-based fuzzer
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)
from fuzz_sim_cpp11_features import (
    FuzzRunner,
    find_perl_exe,
    find_python_exe,
    normalize_output,
    save_failure,
)

# ============================================================================
#                        CORPUS DISCOVERY
# ============================================================================


def discover_bde_corpus(bde_root: str) -> list:
    """Find BDE headers that have _cpp03 companions (real sim_cpp11_features
    inputs)."""
    corpus = []
    groups_dir = os.path.join(bde_root, "groups")
    if not os.path.isdir(groups_dir):
        return corpus

    for cpp03_path in Path(groups_dir).rglob("*_cpp03.h"):
        master = str(cpp03_path).replace("_cpp03.h", ".h")
        if os.path.isfile(master):
            corpus.append(master)

    return sorted(corpus)


def load_corpus(paths: list, max_file_size: int = 500_000) -> list:
    """Load corpus files into memory, skipping files that are too large."""
    corpus = []
    for path in paths:
        try:
            size = os.path.getsize(path)
            if size > max_file_size:
                continue
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            corpus.append((os.path.basename(path), content))
        except Exception:
            continue
    return corpus


# ============================================================================
#                       MUTATION OPERATORS
# ============================================================================


def mutate_delete_line(rng: random.Random, content: str) -> str:
    """Delete a random line."""
    lines = content.split("\n")
    if len(lines) <= 1:
        return content
    idx = rng.randint(0, len(lines) - 1)
    lines.pop(idx)
    return "\n".join(lines)


def mutate_duplicate_line(rng: random.Random, content: str) -> str:
    """Duplicate a random line."""
    lines = content.split("\n")
    if not lines:
        return content
    idx = rng.randint(0, len(lines) - 1)
    lines.insert(idx, lines[idx])
    return "\n".join(lines)


def mutate_swap_lines(rng: random.Random, content: str) -> str:
    """Swap two adjacent lines."""
    lines = content.split("\n")
    if len(lines) <= 1:
        return content
    idx = rng.randint(0, len(lines) - 2)
    lines[idx], lines[idx + 1] = lines[idx + 1], lines[idx]
    return "\n".join(lines)


def mutate_insert_blank(rng: random.Random, content: str) -> str:
    """Insert a blank line at a random position."""
    lines = content.split("\n")
    idx = rng.randint(0, len(lines))
    lines.insert(idx, "")
    return "\n".join(lines)


def mutate_corrupt_pp(rng: random.Random, content: str) -> str:
    """Flip a byte inside a preprocessor directive line."""
    lines = content.split("\n")
    pp_indices = [i for i, l in enumerate(lines) if l.lstrip().startswith("#")]
    if not pp_indices:
        return content
    idx = rng.choice(pp_indices)
    line = lines[idx]
    if len(line) < 2:
        return content
    pos = rng.randint(0, len(line) - 1)
    chars = list(line)
    chars[pos] = chr(ord(chars[pos]) ^ rng.randint(1, 127))
    lines[idx] = "".join(chars)
    return "\n".join(lines)


def mutate_truncate(rng: random.Random, content: str) -> str:
    """Truncate file at a random byte offset."""
    if len(content) <= 10:
        return content
    # Keep at least 10% of the file
    min_keep = max(10, len(content) // 10)
    pos = rng.randint(min_keep, len(content) - 1)
    return content[:pos]


def mutate_flip_byte(rng: random.Random, content: str) -> str:
    """Flip a single random byte."""
    if not content:
        return content
    pos = rng.randint(0, len(content) - 1)
    chars = list(content)
    chars[pos] = chr(ord(chars[pos]) ^ rng.randint(1, 127))
    return "".join(chars)


def mutate_delete_block(rng: random.Random, content: str) -> str:
    """Delete a contiguous block of 2-10 lines."""
    lines = content.split("\n")
    if len(lines) <= 3:
        return content
    block_size = rng.randint(2, min(10, len(lines) - 1))
    start = rng.randint(0, len(lines) - block_size)
    del lines[start : start + block_size]
    return "\n".join(lines)


def mutate_shuffle_block(rng: random.Random, content: str) -> str:
    """Shuffle a contiguous block of 2-5 lines."""
    lines = content.split("\n")
    if len(lines) <= 3:
        return content
    block_size = rng.randint(2, min(5, len(lines) - 1))
    start = rng.randint(0, len(lines) - block_size)
    block = lines[start : start + block_size]
    rng.shuffle(block)
    lines[start : start + block_size] = block
    return "\n".join(lines)


def mutate_mangle_include(rng: random.Random, content: str) -> str:
    """Corrupt an #include directive."""
    lines = content.split("\n")
    inc_indices = [i for i, l in enumerate(lines) if "#include" in l]
    if not inc_indices:
        return content
    idx = rng.choice(inc_indices)
    mutation = rng.choice(["remove_angle", "double_include", "empty_include", "bad_chars"])
    if mutation == "remove_angle":
        lines[idx] = re.sub(r"[<>]", "", lines[idx])
    elif mutation == "double_include":
        lines.insert(idx + 1, lines[idx])
    elif mutation == "empty_include":
        lines[idx] = "#include"
    elif mutation == "bad_chars":
        lines[idx] = lines[idx].replace(".h", ".h@#$")
    return "\n".join(lines)


def mutate_strip_copyright(rng: random.Random, content: str) -> str:
    """Remove the copyright block at the end."""
    # Find the copyright separator
    match = re.search(r"\n// -+\n// Copyright \d+ Bloomberg.*$", content, re.DOTALL)
    if match:
        return content[: match.start()] + "\n"
    return content


def mutate_inject_var_args(rng: random.Random, content: str) -> str:
    """Add or modify a $var-args comment on a #if line."""
    lines = content.split("\n")
    sim_indices = [
        i
        for i, l in enumerate(lines)
        if "BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES" in l and l.lstrip().startswith("#")
    ]
    if not sim_indices:
        return content
    idx = rng.choice(sim_indices)
    val = rng.choice([0, 1, 2, 3, 5, 10, -1, 100])
    # Strip existing $var-args comment
    line = re.sub(r"\s*//\s*\$var-args=\S*", "", lines[idx])
    lines[idx] = f"{line} // $var-args={val}"
    return "\n".join(lines)


def mutate_toggle_negation(rng: random.Random, content: str) -> str:
    """Toggle ! in #if !BSLS_COMPILERFEATURES_SIMULATE... directives."""
    lines = content.split("\n")
    for i, line in enumerate(lines):
        if re.match(r"^\s*#\s*if\s+!?\s*BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES", line):
            if "!" in line:
                lines[i] = line.replace("!", "", 1)
            else:
                lines[i] = re.sub(r"(#\s*if\s+)(BSLS_COMPILERFEATURES_SIMULATE)", r"\1!\2", line)
            break  # Only toggle the first one found
    return "\n".join(lines)


def mutate_double_region(rng: random.Random, content: str) -> str:
    """Duplicate a #if !SIM...#endif region."""
    # Find sim regions
    pattern = re.compile(
        r"(^[ \t]*#\s*if\s+!.*SIMULATE_CPP11_FEATURES.*\n)" r"(.*?)" r"(^[ \t]*#\s*endif\b.*\n)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(content)
    if not match:
        return content
    region = match.group(0)
    insert_pos = match.end()
    return content[:insert_pos] + "\n" + region + content[insert_pos:]


def mutate_crlf_inject(rng: random.Random, content: str) -> str:
    """Convert some \\n to \\r\\n."""
    lines = content.split("\n")
    result = []
    for line in lines:
        if rng.random() < 0.3:
            result.append(line + "\r")
        else:
            result.append(line)
    return "\n".join(result)


# All mutation operators with relative weights
MUTATIONS = [
    (mutate_delete_line, 10),
    (mutate_duplicate_line, 8),
    (mutate_swap_lines, 8),
    (mutate_insert_blank, 5),
    (mutate_corrupt_pp, 12),
    (mutate_truncate, 5),
    (mutate_flip_byte, 10),
    (mutate_delete_block, 6),
    (mutate_shuffle_block, 5),
    (mutate_mangle_include, 8),
    (mutate_strip_copyright, 4),
    (mutate_inject_var_args, 10),
    (mutate_toggle_negation, 8),
    (mutate_double_region, 6),
    (mutate_crlf_inject, 5),
]

MUTATION_FUNCS = [m[0] for m in MUTATIONS]
MUTATION_WEIGHTS = [m[1] for m in MUTATIONS]


def apply_mutations(rng: random.Random, content: str, num_mutations: int) -> tuple:
    """Apply num_mutations random mutations to content.
    Returns (mutated_content, list_of_mutation_names)."""
    applied = []
    for _ in range(num_mutations):
        func = rng.choices(MUTATION_FUNCS, weights=MUTATION_WEIGHTS, k=1)[0]
        content = func(rng, content)
        applied.append(func.__name__.replace("mutate_", ""))
    return content, applied


# ============================================================================
#                           MAIN
# ============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Mutation fuzz test sim_cpp11_features Python vs Perl"
    )
    parser.add_argument(
        "--iterations", "-n", type=int, default=1000, help="Number of iterations (default: 1000)"
    )
    parser.add_argument("--seed", "-s", type=int, default=None, help="Random seed")
    parser.add_argument(
        "--corpus-dir", default=None, help="Directory containing seed corpus files (*.h)"
    )
    parser.add_argument(
        "--auto-corpus",
        action="store_true",
        default=True,
        help="Auto-discover BDE headers with _cpp03 companions",
    )
    parser.add_argument(
        "--bde-root", default=None, help="Root of BDE repo for auto-corpus discovery"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.join(script_dir, "mutfuzz_output"),
        help="Directory for failure artifacts",
    )
    parser.add_argument(
        "--max-mutations", type=int, default=5, help="Maximum mutations per iteration (default: 5)"
    )
    parser.add_argument(
        "--perl",
        default=os.path.join(script_dir, "sim_cpp11_features.pl"),
        help="Path to Perl script",
    )
    parser.add_argument(
        "--python",
        default=os.path.join(script_dir, "sim_cpp11_features.py"),
        help="Path to Python script",
    )
    parser.add_argument("--python-exe", default=None, help="Python interpreter")
    parser.add_argument("--perl-exe", default=None, help="Perl interpreter")
    parser.add_argument(
        "--timeout", type=int, default=30, help="Per-invocation timeout in seconds (default: 30)"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Print each test case")
    parser.add_argument("--stop-on-fail", action="store_true", help="Stop on first failure")
    parser.add_argument(
        "--workers",
        "-j",
        type=int,
        default=0,
        help="Number of parallel workers (default: min(4, CPU_count/2))",
    )
    args = parser.parse_args()

    # Resolve executables
    if args.perl_exe is None:
        args.perl_exe = find_perl_exe()
    python_exe = args.python_exe or find_python_exe()

    # Seed
    if args.seed is None:
        args.seed = random.randint(0, 2**32 - 1)
    master_seed = args.seed

    # Workers
    if args.workers <= 0:
        args.workers = min(4, max(1, (os.cpu_count() or 2) // 2))

    # Build corpus
    corpus = []
    if args.corpus_dir:
        corpus_paths = sorted(str(p) for p in Path(args.corpus_dir).glob("*.h"))
        corpus = load_corpus(corpus_paths)

    if args.auto_corpus:
        # Try to find BDE root
        bde_root = args.bde_root
        if bde_root is None:
            # Check common locations relative to script
            candidates = [
                os.path.join(script_dir, "..", "..", ".."),  # bde-tools -> bde
                os.path.normpath(os.path.join(script_dir, "..", "..", "..", "..", "bde")),
            ]
            # Also check siblings of bde-tools
            bde_tools_root = os.path.normpath(os.path.join(script_dir, "..", "..", ".."))
            parent_of_tools = os.path.dirname(bde_tools_root)
            candidates.append(os.path.join(parent_of_tools, "bde"))

            for c in candidates:
                c = os.path.normpath(c)
                if os.path.isdir(os.path.join(c, "groups")):
                    bde_root = c
                    break

        if bde_root:
            bde_paths = discover_bde_corpus(bde_root)
            bde_corpus = load_corpus(bde_paths)
            # Avoid duplicates
            existing = {name for name, _ in corpus}
            for name, content in bde_corpus:
                if name not in existing:
                    corpus.append((name, content))

    if not corpus:
        print("ERROR: No corpus files found.", file=sys.stderr)
        print(
            "Use --corpus-dir, --bde-root, or ensure BDE repo is " "adjacent to bde-tools.",
            file=sys.stderr,
        )
        return 1

    print(f"Master seed: {master_seed}")
    print(f"Corpus: {len(corpus)} files")
    print(f"Perl script: {args.perl}")
    print(f"Python script: {args.python}")
    print(f"Perl exe: {args.perl_exe}")
    print(f"Python exe: {python_exe}")
    print(f"Timeout: {args.timeout}s")
    print(f"Workers: {args.workers}")
    print(f"Max mutations: {args.max_mutations}")
    print(f"Output dir: {args.output_dir}")
    print()

    os.makedirs(args.output_dir, exist_ok=True)

    runner = FuzzRunner(
        perl_script=args.perl,
        python_script=args.python,
        perl_exe=args.perl_exe,
        python_exe=python_exe,
        timeout=args.timeout,
        output_dir=args.output_dir,
    )

    # CLI modes
    all_cli_modes = [
        ("default", []),
        ("inplace", ["--inplace"]),
        ("no-inplace", ["--no-inplace"]),
        ("clean", ["--clean"]),
    ]

    total = 0
    passed = 0
    failed = 0
    errors = 0
    timeouts = 0
    start_time = time.time()

    def run_one_iteration(iteration):
        """Run a single mutation iteration."""
        iter_seed = master_seed + iteration
        rng = random.Random(iter_seed)

        # Pick a corpus file
        orig_name, orig_content = rng.choice(corpus)
        base_name = re.sub(r"\.h$", "", orig_name)

        # Apply mutations
        num_mutations = rng.randint(1, args.max_mutations)
        mutated, mutation_names = apply_mutations(rng, orig_content, num_mutations)

        input_name = f"mut_{iteration:06d}.h"

        # Pick CLI mode(s)
        cli_modes = [all_cli_modes[0]]
        others = rng.sample(all_cli_modes[1:], k=1)
        cli_modes.extend(others)

        var_args_override = None
        if rng.random() < 0.2:
            var_args_override = rng.randint(1, 10)

        results = []
        for mode_label, base_args in cli_modes:
            extra_args = list(base_args)
            if var_args_override is not None:
                extra_args.append(f"--var-args={var_args_override}")
            ok, info = runner.compare_one(mutated, input_name, extra_args, mode_label)
            results.append(
                (
                    iteration,
                    input_name,
                    mutated,
                    iter_seed,
                    var_args_override,
                    mode_label,
                    extra_args,
                    ok,
                    info,
                    orig_name,
                    mutation_names,
                )
            )
        return results

    iteration = 0
    stop_early = False
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            while not stop_early:
                if args.iterations > 0 and iteration >= args.iterations:
                    break

                batch_size = args.workers * 2
                if args.iterations > 0:
                    batch_size = min(batch_size, args.iterations - iteration)

                futures = {}
                for i in range(batch_size):
                    it = iteration + i
                    futures[pool.submit(run_one_iteration, it)] = it

                # Per-future safety timeout: subprocess timeout + pipe drain
                # + compare overhead.  Prevents the entire run from hanging
                # if a subprocess timeout fails to kill cleanly on Windows.
                future_timeout = (args.timeout + 30) * 4  # 2 modes × 2 scripts

                try:
                    for future in concurrent.futures.as_completed(futures, timeout=future_timeout):
                        try:
                            results_list = future.result(timeout=10)
                        except (concurrent.futures.TimeoutError, Exception) as exc:
                            it_num = futures[future]
                            total += 2  # approximate: 2 modes
                            timeouts += 2
                            if args.verbose:
                                print(f"  [{it_num}] TIMEOUT (future hung: {exc!r})")
                            continue
                        for (
                            iter_n,
                            input_name,
                            input_content,
                            iter_seed,
                            var_args_override,
                            mode_label,
                            extra_args,
                            ok,
                            info,
                            orig_name,
                            mutation_names,
                        ) in results_list:
                            total += 1
                            if ok:
                                passed += 1
                                if info and info.get("status") == "timeout":
                                    timeouts += 1
                                    if args.verbose:
                                        print(
                                            f"  [{iter_n}] {input_name} " f"({mode_label}) TIMEOUT"
                                        )
                                elif info and info.get("status") == "exec_error":
                                    errors += 1
                                    if args.verbose:
                                        detail = info.get("perl_err", info.get("python_err", ""))
                                        print(
                                            f"  [{iter_n}] {input_name} "
                                            f"({mode_label}) ERROR: "
                                            f"{detail[:100]}"
                                        )
                                else:
                                    if args.verbose:
                                        muts = "+".join(mutation_names)
                                        print(
                                            f"  [{iter_n}] {input_name} "
                                            f"({mode_label}) PASS "
                                            f"[{orig_name} <- {muts}]"
                                        )
                            else:
                                failed += 1
                                detail = ""
                                if info.get("type") == "exit_code_mismatch":
                                    detail = (
                                        f" perl={info['perl_rc']}" f" python={info['python_rc']}"
                                    )
                                elif info.get("type") == "output_mismatch":
                                    names = ", ".join(n for n, _ in info.get("diffs", []))
                                    detail = f" diff in: {names}"

                                muts = "+".join(mutation_names)
                                print(
                                    f"FAIL [{iter_n}] {input_name} ({mode_label})"
                                    f" - {info.get('type', 'unknown')}{detail}"
                                    f" [{orig_name} <- {muts}]"
                                )

                                # Enrich failure info with mutation details
                                info["source_file"] = orig_name
                                info["mutations"] = mutation_names

                                save_failure(
                                    args.output_dir,
                                    iter_n,
                                    iter_seed,
                                    input_content,
                                    input_name,
                                    info,
                                    extra_args,
                                )

                                if args.stop_on_fail:
                                    print("\nStopping on first failure.")
                                    stop_early = True

                            if stop_early:
                                break

                        if stop_early:
                            break
                except TimeoutError:
                    # as_completed() timed out waiting for remaining futures.
                    # Count the incomplete futures as timeouts and move on.
                    incomplete = sum(1 for f in futures if not f.done())
                    timeouts += incomplete * 2  # approximate: 2 modes each
                    total += incomplete * 2
                    print(f"  [batch {iteration}] {incomplete} futures timed out, skipping")

                iteration += batch_size

                # Progress report every 100 iterations
                if iteration % 100 < batch_size:
                    elapsed = time.time() - start_time
                    rate = total / elapsed if elapsed > 0 else 0
                    print(
                        f"[{iteration}] {total} tests, {passed} passed, "
                        f"{failed} failed, {errors} errors, "
                        f"{timeouts} timeouts ({rate:.1f} tests/s)"
                    )

    except KeyboardInterrupt:
        print("\n\nInterrupted by user.")

    # Final summary
    elapsed = time.time() - start_time
    rate = total / elapsed if elapsed > 0 else 0
    print()
    print("=" * 60)
    print("Mutation fuzz testing complete")
    print(f"  Master seed:  {master_seed}")
    print(f"  Corpus:       {len(corpus)} files")
    print(f"  Iterations:   {iteration}")
    print(f"  Total tests:  {total}")
    print(f"  Passed:       {passed}")
    print(f"  Failed:       {failed}")
    print(f"  Errors:       {errors}")
    print(f"  Timeouts:     {timeouts}")
    print(f"  Elapsed:      {elapsed:.1f}s ({rate:.1f} tests/s)")
    if failed > 0:
        print(f"  Failures in:  {args.output_dir}")
    print("=" * 60)

    # Write summary
    summary_path = os.path.join(args.output_dir, "summary.txt")
    with open(summary_path, "w", encoding="utf-8") as f:
        f.write(f"Master seed: {master_seed}\n")
        f.write(f"Corpus: {len(corpus)} files\n")
        f.write(f"Iterations: {iteration}\n")
        f.write(f"Total tests: {total}\n")
        f.write(f"Passed: {passed}\n")
        f.write(f"Failed: {failed}\n")
        f.write(f"Errors: {errors}\n")
        f.write(f"Timeouts: {timeouts}\n")
        f.write(f"Elapsed: {elapsed:.1f}s\n")

    return 1 if failed > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
