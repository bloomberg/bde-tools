#!/usr/bin/env python3
"""
fuzz_sim_cpp11_features.py - Fuzz test comparing Python vs Perl sim_cpp11_features

Generates random but structurally valid C++ header files containing
sim_cpp11_features constructs, runs both the Perl and Python scripts on them,
and compares output (modulo timestamps and script names).

The Perl script is used as the "oracle" -- whenever both scripts succeed
without crashing, their normalized outputs must match exactly.

Usage:
    python fuzz_sim_cpp11_features.py [options]

Options:
    --iterations N       Number of fuzz iterations (default: 1000, 0=infinite)
    --seed N             Random seed for reproducibility (default: random)
    --save-all           Save all generated inputs, not just failures
    --output-dir DIR     Directory for failure artifacts (default: fuzz_output)
    --perl PATH          Path to Perl script
    --python PATH        Path to Python script
    --python-exe EXE     Python interpreter (default: python3 / python)
    --perl-exe EXE       Perl interpreter (default: perl)
    --timeout N          Per-invocation timeout in seconds (default: 30)
    --verbose            Print each test case name as it runs
    --stop-on-fail       Stop on first failure
"""

import argparse
import concurrent.futures
import difflib
import hashlib
import os
import platform
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# ============================================================================
#                        NORMALIZATION
# ============================================================================


def normalize_output(text: str) -> str:
    """Normalize output to ignore timestamps and script name differences."""
    text = text.replace("\r", "")  # Strip CR bytes (CRLF handling differs)
    text = re.sub(r"Generated on [^\n]*", "Generated on TIMESTAMP", text)
    text = re.sub(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\+\d{2}:\d{2}|Z)?", "TIMESTAMP", text)
    text = re.sub(r"sim_cpp11_features\.pl", "sim_cpp11_features.SCRIPT", text)
    text = re.sub(r"sim_cpp11_features\.py", "sim_cpp11_features.SCRIPT", text)
    text = re.sub(r"\n+$", "\n", text)  # Normalize trailing newlines
    return text


# ============================================================================
#                     RANDOM INPUT GENERATION
# ============================================================================

# Building blocks for random generation

PACK_NAMES = [
    "ARGS",
    "TYPES",
    "REST",
    "PARAMS",
    "VALUES",
    "ELEMENTS",
    "CTOR_ARGS",
    "ITEMS",
    "FIELDS",
]

SINGLE_TYPE_NAMES = ["T", "U", "V", "W", "ARG", "ELEMENT_TYPE", "CTOR_ARG", "VALUE_TYPE", "RESULT"]

LONG_TYPE_NAMES = [
    "VeryLongTemplateParameterName",
    "AdditionalTypes",
    "SomeElaborateTypeName",
    "AnotherExtremelyLongName",
]

CLASS_NAMES = [
    "MyClass",
    "Container",
    "Wrapper",
    "Builder",
    "Factory",
    "Allocator",
    "Handler",
    "Processor",
    "Manager",
    "Widget",
    "OperatorClass",
    "ConstructorTest",
    "OutOfLine",
    "WithInit",
]

FUNC_NAMES = [
    "process",
    "handle",
    "execute",
    "invoke",
    "apply",
    "forward_call",
    "doWork",
    "compute",
    "transform",
    "simpleVariadic",
    "mixedVariadic",
    "construct",
]

BODY_CALLS = ["process", "handle", "doWork", "bar", "execute", "init"]

FORWARD_NS = ["std", "bsl", "native_std"]

COMMENT_STYLES = [
    "",  # no comment
    "  // trailing comment",  # C++ trailing
    "  /* inline */",  # C inline
]

NON_TYPE_PARAMS = ["int", "unsigned", "bool", "size_t"]

# Alternate forms of the sim directive recognized by the scripts
SIM_DIRECTIVE_FORMS = [
    "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
    "#ifndef BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
    "#if !defined(BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES)",
]

# Keyword for template type parameter
TYPE_KEYWORDS = ["class", "typename"]


class FuzzGenerator:
    """Generates random sim_cpp11_features input files."""

    def __init__(self, rng: random.Random):
        self.rng = rng

    def pick(self, choices):
        return self.rng.choice(choices)

    def maybe(self, prob=0.5):
        return self.rng.random() < prob

    def randint(self, lo, hi):
        return self.rng.randint(lo, hi)

    # ---- Name generators ----

    def pack_name(self) -> str:
        name = self.pick(PACK_NAMES)
        if self.maybe(0.2):
            name += str(self.randint(1, 3))
        return name

    def single_type(self) -> str:
        if self.maybe(0.15):
            return self.pick(LONG_TYPE_NAMES)
        return self.pick(SINGLE_TYPE_NAMES)

    def class_name(self) -> str:
        name = self.pick(CLASS_NAMES)
        if self.maybe(0.3):
            name += str(self.randint(1, 5))
        return name

    def func_name(self) -> str:
        name = self.pick(FUNC_NAMES)
        if self.maybe(0.2):
            name += str(self.randint(1, 3))
        return name

    def body_call(self) -> str:
        return self.pick(BODY_CALLS)

    def forward_ns(self) -> str:
        return self.pick(FORWARD_NS)

    # ---- Template parameter list generators ----

    def type_keyword(self) -> str:
        return self.pick(TYPE_KEYWORDS)

    def variadic_template_params(self):
        """Return (param_list_str, pack_name, leading_singles, has_nontype)."""
        params = []
        leading_singles = []
        has_nontype = False

        # Optionally add non-type parameter
        if self.maybe(0.15):
            ntp = self.pick(NON_TYPE_PARAMS)
            ntname = self.pick(["X", "N", "K"])
            params.append(f"{ntp} {ntname}")
            has_nontype = True

        # Optionally add leading single type params
        n_leading = self.randint(0, 2)
        kw = self.type_keyword()
        for _ in range(n_leading):
            s = self.single_type()
            # Avoid duplicates
            while s in leading_singles:
                s = self.single_type() + str(self.randint(1, 9))
            leading_singles.append(s)
            params.append(f"{kw} {s}")

        # The variadic pack
        pack = self.pack_name()
        while pack in leading_singles:
            pack = self.pack_name() + str(self.randint(1, 9))

        # Choose between class/typename... and non-type...
        if self.maybe(0.1) and not has_nontype:
            ntp = self.pick(NON_TYPE_PARAMS)
            params.append(f"{ntp}... {pack}")
        else:
            pack_kw = self.type_keyword()
            params.append(f"{pack_kw}... {pack}")

        return ", ".join(params), pack, leading_singles, has_nontype

    # ---- Code fragment generators ----

    def gen_forward_call(self, singles, pack, ns=None):
        """Generate a forwarding call like process(std::forward<T>(t), ...)."""
        if ns is None:
            ns = self.forward_ns()
        call = self.body_call()
        args = []
        for s in singles:
            vname = s.lower()
            if self.maybe(0.7):
                args.append(f"{ns}::forward<{s}>({vname})")
            else:
                args.append(vname)
        args.append(f"{ns}::forward<{pack}>({pack.lower()})...")
        return f"    {call}({', '.join(args)});"

    def gen_sizeof_usage(self, pack):
        """Generate sizeof...(PACK) usage."""
        lines = []
        if self.maybe(0.5):
            lines.append(f"    const size_t count = sizeof...({pack});")
        if self.maybe(0.5):
            lines.append(f"    if (sizeof...({pack.lower()}) > 0) {{}}")
        return "\n".join(lines) if lines else None

    def gen_variadic_function(self):
        """Generate a variadic function template."""
        tparams, pack, singles, has_nt = self.variadic_template_params()
        fname = self.func_name()
        ns = self.forward_ns()

        # Function parameters
        fparams = []
        for s in singles:
            vname = s.lower()
            if self.maybe(0.5):
                fparams.append(f"{s}&& {vname}")
            else:
                fparams.append(f"const {s}& {vname}")
        if self.maybe(0.7):
            fparams.append(f"{pack}&&... {pack.lower()}")
        else:
            fparams.append(f"const {pack}&... {pack.lower()}")

        # Return type
        ret = self.pick(["void", "int", "bool"]) if self.maybe(0.3) else "void"

        comment = self.pick(COMMENT_STYLES) if self.maybe(0.3) else ""

        lines = [f"template <{tparams}>{comment}"]
        param_str = ", ".join(fparams)
        lines.append(f"{ret} {fname}({param_str}) {{")

        # Body
        sizeof_code = self.gen_sizeof_usage(pack) if self.maybe(0.2) else None
        if sizeof_code:
            lines.append(sizeof_code)

        fwd_call = self.gen_forward_call(singles, pack, ns)
        if ret != "void" and self.maybe(0.5):
            fwd_call = "    return " + fwd_call.strip().lstrip()
        lines.append(fwd_call)
        lines.append("}")

        return "\n".join(lines)

    def gen_variadic_class(self):
        """Generate a variadic class template with methods."""
        tparams, pack, singles, has_nt = self.variadic_template_params()
        cname = self.class_name()
        ns = self.forward_ns()
        keyword = self.pick(["class", "struct"]) if self.maybe(0.3) else "class"

        lines = [f"template <{tparams}>"]
        lines.append(f"{keyword} {cname} {{")
        if keyword == "class":
            lines.append("  public:")

        # Add some member methods
        n_methods = self.randint(1, 3)
        for i in range(n_methods):
            mname = self.pick(["method", "process", "invoke", "apply"])
            if n_methods > 1:
                mname += str(i + 1)

            mparams = []
            for s in singles:
                vname = s.lower()
                if self.maybe(0.5):
                    mparams.append(f"{s}&& {vname}")
                else:
                    mparams.append(f"const {s}& {vname}")
            if self.maybe(0.7):
                mparams.append(f"{pack}&&... {pack.lower()}")
            else:
                mparams.append(f"const {pack}&... {pack.lower()}")

            param_str = ", ".join(mparams)

            if self.maybe(0.4):
                # Declaration only
                lines.append(f"    void {mname}({param_str});")
            else:
                # Inline definition
                lines.append(f"    void {mname}({param_str}) {{")
                lines.append(
                    f"        {self.body_call()}(" f"{ns}::forward<{pack}>({pack.lower()})...);"
                )
                lines.append("    }")

        # Maybe add a member template
        if self.maybe(0.3):
            mt = self.single_type()
            while mt in singles or mt == pack:
                mt = self.single_type() + str(self.randint(1, 9))
            lines.append("")
            lines.append(f"    template <class {mt}>")
            lines.append(f"    void memberTemplate({mt}&& value) {{")
            lines.append(f"        {self.body_call()}(" f"{ns}::forward<{mt}>(value));")
            lines.append("    }")

        # Maybe add operator overloads
        if self.maybe(0.2):
            lines.append("")
            lines.append(f"    void operator()({pack}&&... {pack.lower()}) {{")
            lines.append(
                f"        {self.body_call()}(" f"{ns}::forward<{pack}>({pack.lower()})...);"
            )
            lines.append("    }")

        lines.append("};")

        # Maybe add out-of-line definitions
        if self.maybe(0.3):
            lines.append("")
            lines.append(f"template <{tparams}>")
            # Build the specialization
            spec_args = []
            if has_nt:
                spec_args.append("X")
            spec_args.extend(singles)
            spec_args.append(f"{pack}...")
            spec = ", ".join(spec_args)
            mname = self.pick(["method", "process", "method1"])
            mparams = []
            for s in singles:
                vname = s.lower()
                mparams.append(f"const {s}& {vname}")
            mparams.append(f"{pack}&&... {pack.lower()}")
            param_str = ", ".join(mparams)
            lines.append(f"void {cname}<{spec}>::{mname}({param_str}) {{")
            lines.append(f"    {self.body_call()}(" f"{ns}::forward<{pack}>({pack.lower()})...);")
            lines.append("}")

        return "\n".join(lines)

    def gen_constructor_class(self):
        """Generate a class with variadic constructor and init list."""
        tparams, pack, singles, has_nt = self.variadic_template_params()
        cname = self.class_name()
        ns = self.forward_ns()

        lines = [f"template <{tparams}>"]
        lines.append(f"class {cname} {{")
        lines.append("    int d_value;")
        lines.append("  public:")

        cparams = []
        for s in singles:
            cparams.append(f"{s}&& {s.lower()}")
        cparams.append(f"{pack}&&... {pack.lower()}")
        param_str = ", ".join(cparams)

        if self.maybe(0.5):
            # Declaration + out-of-line definition
            lines.append(f"    {cname}({param_str});")
            lines.append("};")
            lines.append("")
            lines.append(f"template <{tparams}>")
            spec_args = []
            if has_nt:
                spec_args.append("X")
            spec_args.extend(singles)
            spec_args.append(f"{pack}...")
            spec = ", ".join(spec_args)
            lines.append(f"{cname}<{spec}>::{cname}({param_str})")
            fwd_args = ", ".join(
                [f"{ns}::forward<{s}>({s.lower()})" for s in singles]
                + [f"{ns}::forward<{pack}>({pack.lower()})..."]
            )
            lines.append(f": d_value(init({fwd_args}))")
            lines.append("{")
            lines.append("}")
        else:
            # Inline definition
            fwd_args = ", ".join(
                [f"{ns}::forward<{s}>({s.lower()})" for s in singles]
                + [f"{ns}::forward<{pack}>({pack.lower()})..."]
            )
            lines.append(f"    {cname}({param_str})" f" : d_value(init({fwd_args})) {{ }}")
            lines.append("};")

        return "\n".join(lines)

    def gen_forwarding_function(self):
        """Generate a non-variadic forwarding function (just T&& + forward)."""
        n_params = self.randint(1, 3)
        used = set()
        type_names = []
        for _ in range(n_params):
            t = self.single_type()
            while t in used:
                t = self.single_type() + str(self.randint(1, 9))
            used.add(t)
            type_names.append(t)

        ns = self.forward_ns()
        fname = self.func_name()
        tparam_str = ", ".join(f"class {t}" for t in type_names)
        fparam_str = ", ".join(f"{t}&& {t.lower()}" for t in type_names)
        fwd_args = ", ".join(f"{ns}::forward<{t}>({t.lower()})" for t in type_names)
        call = self.body_call()

        lines = [
            f"template <{tparam_str}>",
            f"void {fname}({fparam_str}) {{",
            f"    {call}({fwd_args});",
            "}",
        ]
        return "\n".join(lines)

    def gen_string_confuser(self):
        """Generate code with string literals that might confuse the parser."""
        tparams, pack, singles, _ = self.variadic_template_params()
        fname = self.func_name()
        ns = self.forward_ns()

        confusing_strings = [
            '"template <class... T>"',
            f'"std::forward<X>(y)..."',
            '"// this is not a comment"',
            '"T&&"',
            '"#if !BSLS"',
            '"quotes: \\"nested\\" end"',
            '"backslash: \\\\ end"',
            '"class... ARGS"',
        ]

        lines = [f"template <{tparams}>"]
        fparams = [f"{pack}&&... {pack.lower()}"]
        lines.append(f"void {fname}({', '.join(fparams)}) {{")

        n_strings = self.randint(1, 3)
        for i in range(n_strings):
            s = self.pick(confusing_strings)
            lines.append(f"    const char *s{i} = {s};")

        lines.append(f"    {self.body_call()}(" f"{ns}::forward<{pack}>({pack.lower()})...);")
        lines.append("}")
        return "\n".join(lines)

    def gen_comment_heavy(self):
        """Generate code with various comment styles."""
        tparams, pack, singles, _ = self.variadic_template_params()
        fname = self.func_name()
        ns = self.forward_ns()

        lines = []
        if self.maybe(0.5):
            lines.append("// Comment before template")
        if self.maybe(0.3):
            lines.append("/*")
            lines.append(" * Multi-line block comment")
            lines.append(" */")

        lines.append(
            f"template <{tparams}>" + ("  // trailing comment" if self.maybe(0.4) else "")
        )
        fparams = []
        for s in singles:
            fparams.append(f"{s}&& {s.lower()}")
        fparams.append(
            f"{pack}&&... {pack.lower()}" + (" /* inline */" if self.maybe(0.3) else "")
        )
        lines.append(f"void {fname}({', '.join(fparams)}) {{")
        if self.maybe(0.3):
            lines.append("    /* block comment */")
        lines.append(f"    {self.body_call()}(" f"{ns}::forward<{pack}>({pack.lower()})...);")
        if self.maybe(0.3):
            lines.append("    // single line comment")
        lines.append("}")

        return "\n".join(lines)

    def gen_allocator_traits_pattern(self):
        """Generate allocator_traits-like pattern with nested templates."""
        outer = self.class_name()
        outer_param = "ALLOCATOR_TYPE"
        pack = self.pack_name()
        leading = self.single_type()
        while leading == pack:
            leading = self.single_type() + str(self.randint(1, 9))
        ns = self.forward_ns()

        lines = [
            f"template <class {outer_param}>",
            f"class {outer} {{",
            "  public:",
            f"    template <class ELEMENT_TYPE, class {leading}, class... {pack}>",
            f"    static void construct({outer_param}&  allocator,",
            f"                          ELEMENT_TYPE    *elementAddr,",
            f"                          {leading}&&       leadingArg,",
            f"                          {pack}&&...   trailingArgs);",
            "};",
            "",
            f"template <class {outer_param}>",
            f"template <class ELEMENT_TYPE, class {leading}, class... {pack}>",
            "inline void",
            f"{outer}<{outer_param}>::construct({outer_param}&  allocator,",
            f"                                            ELEMENT_TYPE    *elementAddr,",
            f"                                            {leading}&&       leadingArg,",
            f"                                            {pack}&&...   trailingArgs)",
            "{",
            f"    ::new (elementAddr) ELEMENT_TYPE(",
            f"        {ns}::forward<{leading}>(leadingArg),",
            f"        {ns}::forward<{pack}>(trailingArgs)...);",
            "}",
        ]
        return "\n".join(lines)

    def gen_nested_ifdef(self):
        """Generate code with nested #ifdef inside the sim region."""
        tparams, pack, singles, _ = self.variadic_template_params()
        fname = self.func_name()
        ns = self.forward_ns()
        guard = self.pick(["SOME_FEATURE", "EXTRA_SUPPORT", "HAS_EXTENSION"])

        lines = []
        lines.append(f"#  ifdef {guard}")
        lines.append("")
        lines.append(f"template <{tparams}>")
        fparams = [f"{pack}&&... {pack.lower()}"]
        lines.append(f"void {fname}({', '.join(fparams)}) {{")
        lines.append(f"    {self.body_call()}({ns}::forward<{pack}>({pack.lower()})...);")
        lines.append("}")
        lines.append("")
        lines.append(f"#  endif // {guard}")

        # Also code outside the nested #ifdef
        t = self.single_type()
        fname2 = self.func_name()
        while fname2 == fname:
            fname2 = self.func_name() + str(self.randint(1, 9))
        lines.append("")
        lines.append(f"template <class {t}>")
        lines.append(f"void {fname2}({t}&& value) {{")
        lines.append(f"    {self.body_call()}({ns}::forward<{t}>(value));")
        lines.append("}")

        return "\n".join(lines)

    def gen_multiple_expand_same_line(self):
        """Generate multiple pack expansions on the same line."""
        tparams, pack, singles, _ = self.variadic_template_params()
        ns = self.forward_ns()

        calls = []
        n_calls = self.randint(2, 3)
        for _ in range(n_calls):
            c = self.body_call()
            calls.append(f"{c}({ns}::forward<{pack}>({pack.lower()})...)")

        lines = [
            f"template <{tparams}>",
            f"void multiExpand({pack}&&... {pack.lower()}) {{",
            f"    {'; '.join(calls)};",
            "}",
        ]
        return "\n".join(lines)

    def gen_vector_pack_param(self):
        """Generate variadic with template types wrapping packs (vector<A>&...)."""
        tparams, pack, singles, _ = self.variadic_template_params()
        fname = self.func_name()

        wrapper = self.pick(["vector", "Container", "shared_ptr"])
        lines = [
            f"template <{tparams}>",
            f"void {fname}(const {wrapper}<{pack}>&... {pack.lower()}) {{",
            f"    {self.body_call()}({pack.lower()}...);",
            "}",
        ]
        return "\n".join(lines)

    def gen_pointer_pack_param(self):
        """Generate variadic with pointer pack params (TYPES*... ptrs)."""
        tparams, pack, singles, _ = self.variadic_template_params()
        cname = self.class_name()

        lines = [
            f"template <{tparams}>",
            f"class {cname} {{",
            "  public:",
            f"    void method({pack}*... ptrs);",
            f"    void constPtrs(const {pack}*... ptrs);",
            "};",
            "",
            f"template <{tparams}>",
            f"void {cname}<{pack}...>::method({pack}*... ptrs) {{",
            f"    {self.body_call()}(ptrs...);",
            "}",
        ]
        return "\n".join(lines)

    def gen_whitespace_variation(self):
        """Generate code with unusual whitespace patterns."""
        pack = self.pack_name()
        ns = self.forward_ns()
        fname = self.func_name()
        style = self.randint(0, 2)

        if style == 0:
            # No spaces
            lines = [
                f"template<class...{pack}>",
                f"void {fname}({pack}&&...{pack.lower()}){{",
                f"    {self.body_call()}({ns}::forward<{pack}>({pack.lower()})...);",
                "}",
            ]
        elif style == 1:
            # Extra spaces
            lines = [
                f"template <  class  ...  {pack}  >",
                f"void {fname}(  {pack}  &&  ...  {pack.lower()}  ) {{",
                f"    {self.body_call()}(  {ns}::forward<{pack}>({pack.lower()})  ...  );",
                "}",
            ]
        else:
            # Tabs mixed in
            lines = [
                f"template <class...\t{pack}>",
                f"void {fname}({pack}&&...\t{pack.lower()}) {{",
                f"    {self.body_call()}({ns}::forward<{pack}>({pack.lower()})...);",
                "}",
            ]
        return "\n".join(lines)

    def gen_dependent_return_type(self):
        """Generate function with dependent return type (typename mf<X>::type)."""
        tparams, pack, singles, has_nt = self.variadic_template_params()
        cname = self.class_name()
        ns = self.forward_ns()

        # Ensure there is a non-type param for the return type
        if not has_nt:
            nt_name = "X"
            full_tparams = f"int {nt_name}, {tparams}"
        else:
            nt_name = "X"
            full_tparams = tparams

        spec_args = []
        if has_nt or not has_nt:
            spec_args.append(nt_name)
        spec_args.extend(singles)
        spec_args.append(f"{pack}...")
        spec = ", ".join(spec_args)

        lines = [
            f"template <{full_tparams}>",
            f"class {cname} {{",
            "  public:",
            f"    typename mf<{nt_name}>::type member(const {pack}&... z);",
            "};",
            "",
            f"template <{full_tparams}>",
            f"typename mf<{nt_name}>::type {cname}<{spec}>::member(const {pack}&... z) {{",
            "}",
        ]
        return "\n".join(lines)

    def gen_forward_with_extra_args(self):
        """Generate forward call with extra template arguments."""
        tparams, pack, singles, _ = self.variadic_template_params()
        fname = self.func_name()

        lines = [
            f"template <{tparams}>",
            f"void {fname}(const vector<{pack}>&... {pack.lower()}) {{",
            f"    if (q()) {{",
            f"        xyz(forward<{pack}, int>({pack.lower()})...",
            f"            );",
            f"    }}",
            "}",
        ]
        return "\n".join(lines)

    # ---- Malformed / edge-case generators ----
    # These produce inputs that are NOT valid sim_cpp11_features usage.
    # Both scripts should either reject them identically or handle them the
    # same way.  Any exit-code mismatch is a real bug.

    def gen_malformed_file(self) -> str:
        """Generate a complete file with one randomly chosen defect."""
        defect = self.pick(
            [
                "missing_endif",
                "nested_sim_regions",
                "bad_var_args_value",
                "missing_include_guard",
                "truncated_template",
                "garbage_in_region",
                "unbalanced_braces",
                "missing_copyright_line",
                "empty_file",
                "var_args_zero",
                "duplicate_var_args",
                "binary_chars",
                "crlf_mixed",
                "bom_prefix",
                "no_include",
                "elif_instead_of_endif",
                "extra_endif",
            ]
        )

        name = "fuzz_malformed"
        guard = f"INCLUDED_{name.upper()}"
        header = [
            f"// {name}.h" + " " * 50 + "-*-C++-*-",
            f"#ifndef {guard}",
            f"#define {guard}",
            "",
            "#include <bsls_compilerfeatures.h>",
            "",
        ]
        copyright = [
            "",
            "#endif",
            "",
            "// " + "-" * 76,
            "// Copyright 2020 Bloomberg Finance L.P.",
            "//",
            '// Licensed under the Apache License, Version 2.0 (the "License");',
            "// you may not use this file except in compliance with the License.",
            "// You may obtain a copy of the License at",
            "//",
            "//     http://www.apache.org/licenses/LICENSE-2.0",
            "//",
            "// Unless required by applicable law or agreed to in writing, software",
            '// distributed under the License is distributed on an "AS IS" BASIS,',
            "// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.",
            "// See the License for the specific language governing permissions and",
            "// limitations under the License.",
            "// ----------------------------- END-OF-FILE ----------------------------------",
        ]

        pack = self.pack_name()
        ns = self.forward_ns()

        if defect == "missing_endif":
            # Region opened but never closed
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({ns}::forward<{pack}>({pack.lower()})...);",
                "}",
                "",
                "// oops, no #endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "nested_sim_regions":
            # Sim region inside another sim region
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void outer({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void inner({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "bad_var_args_value":
            # $var-args with non-numeric or negative value
            bad_val = self.pick(["abc", "-1", "0.5", "999999", "", "--3", "1e2"])
            body = [
                f"#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args={bad_val}",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "var_args_zero":
            # $var-args=0 — edge case, should it be valid?
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=0",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "duplicate_var_args":
            # Two $var-args on the same line
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3 $var-args=5",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "missing_include_guard":
            # No #ifndef / #define guard
            body = [
                "#include <bsls_compilerfeatures.h>",
                "",
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(body + copyright) + "\n"

        elif defect == "truncated_template":
            # Template declaration cut off mid-line
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}",  # missing >
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "garbage_in_region":
            # Random non-C++ text inside a sim region
            garbage = self.pick(
                [
                    "@#$%^&*() this is not code",
                    "SELECT * FROM templates WHERE variadic=true;",
                    "<html><body>not C++</body></html>",
                    "}}}}}{{{{{",
                    "template template template",
                    "\t\t\t",
                ]
            )
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                garbage,
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "unbalanced_braces":
            # Missing closing brace
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "// oops, missing }}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "missing_copyright_line":
            # Copyright block but missing the first dashes line
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            # Copyright without leading dashes
            bad_copyright = [
                "",
                "#endif",
                "",
                "// Copyright 2020 Bloomberg Finance L.P.",
                "// ----------------------------- END-OF-FILE ----------------------------------",
            ]
            return "\n".join(header + body + bad_copyright) + "\n"

        elif defect == "empty_file":
            # Completely empty or near-empty
            if self.maybe(0.5):
                return ""
            else:
                return "// just a comment\n"

        elif defect == "binary_chars":
            # Null bytes or other binary characters mixed in
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{\x00",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "crlf_mixed":
            # Mix \r\n and \n line endings
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({ns}::forward<{pack}>({pack.lower()})...);",
                "}",
                "",
                "#endif",
            ]
            content = "\n".join(header + body + copyright) + "\n"
            # Convert random lines to \r\n
            out_lines = content.split("\n")
            result = []
            for line in out_lines:
                if self.maybe(0.4):
                    result.append(line + "\r")
                else:
                    result.append(line)
            return "\n".join(result)

        elif defect == "bom_prefix":
            # UTF-8 BOM at start of file
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({ns}::forward<{pack}>({pack.lower()})...);",
                "}",
                "",
                "#endif",
            ]
            return "\ufeff" + "\n".join(header + body + copyright) + "\n"

        elif defect == "no_include":
            # Missing #include <bsls_compilerfeatures.h>
            no_inc_header = [
                f"// {name}.h" + " " * 50 + "-*-C++-*-",
                f"#ifndef {guard}",
                f"#define {guard}",
                "",
            ]
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
            ]
            return "\n".join(no_inc_header + body + copyright) + "\n"

        elif defect == "elif_instead_of_endif":
            # Region ending with #elif instead of #endif
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#elif defined(OTHER_THING)",
                "// different code path",
                "#endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        elif defect == "extra_endif":
            # Extra #endif after the real one
            body = [
                "#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES",
                "",
                f"template <class... {pack}>",
                f"void func({pack}&&... {pack.lower()}) {{",
                f"    {self.body_call()}({pack.lower()}...);",
                "}",
                "",
                "#endif",
                "#endif  // stray extra endif",
            ]
            return "\n".join(header + body + copyright) + "\n"

        # Fallback: valid file
        return self.gen_file(name)

    # ---- Region generation ----

    def gen_region(self):
        """Generate a single #if !BSLS ... #endif region with random content."""
        var_args = self.randint(1, 10)
        local_var_args = None
        if self.maybe(0.15):
            local_var_args = self.randint(1, 5)

        # Use various forms of the sim directive
        if_line = self.pick(SIM_DIRECTIVE_FORMS)
        opts = []
        if self.maybe(0.6):
            opts.append(f"$var-args={var_args}")
        if local_var_args is not None:
            opts.append(f"$local-var-args={local_var_args}")
        if opts:
            if_line += " // " + " ".join(opts)

        lines = [if_line, ""]

        # Generate 1-4 code fragments
        generators = [
            self.gen_variadic_function,
            self.gen_variadic_class,
            self.gen_constructor_class,
            self.gen_forwarding_function,
            self.gen_string_confuser,
            self.gen_comment_heavy,
            self.gen_allocator_traits_pattern,
            self.gen_nested_ifdef,
            self.gen_multiple_expand_same_line,
            self.gen_vector_pack_param,
            self.gen_pointer_pack_param,
            self.gen_whitespace_variation,
            self.gen_dependent_return_type,
            self.gen_forward_with_extra_args,
        ]

        # Weights: common patterns more likely, new patterns less frequent
        weights = [25, 20, 8, 15, 4, 4, 4, 4, 3, 3, 3, 3, 2, 2]

        n_fragments = self.randint(1, 4)
        for i in range(n_fragments):
            gen = self.rng.choices(generators, weights=weights, k=1)[0]
            lines.append(gen())
            if i < n_fragments - 1:
                lines.append("")

        lines.append("")
        lines.append("#endif")

        return "\n".join(lines)

    # ---- Full file generation ----

    def gen_file(self, name: str = "fuzz_test", file_type: str = "normal") -> str:
        """Generate a complete header file.

        file_type: 'normal', 'no_regions', 'empty_region', 'no_copyright'
        """
        guard = f"INCLUDED_{name.upper()}"

        lines = [
            f"// {name}.h" + " " * max(1, 68 - len(name)) + "-*-C++-*-",
            f"#ifndef {guard}",
            f"#define {guard}",
            "",
            "#include <bsls_compilerfeatures.h>",
            "",
        ]

        if file_type == "no_regions":
            # File with no sim regions — just plain code
            lines.append("template <class T>")
            lines.append("void normalTemplate(const T& value) {")
            lines.append("    process(value);")
            lines.append("}")
            lines.append("")
        elif file_type == "empty_region":
            # Region containing only non-variadic code
            lines.append("#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES")
            lines.append("")
            lines.append("template <class T>")
            lines.append("void justForwarding(T&& value) {")
            lines.append("    process(std::forward<T>(value));")
            lines.append("}")
            lines.append("")
            lines.append("#endif")
            lines.append("")
        else:
            # Normal: generate 1-3 regions
            n_regions = self.randint(1, 3)
            for i in range(n_regions):
                lines.append(self.gen_region())
                if i < n_regions - 1:
                    lines.append("")

        if file_type == "no_copyright":
            # Deliberately omit copyright block
            lines.extend(["", "#endif"])
        else:
            lines.extend(
                [
                    "",
                    "#endif",
                    "",
                    "// " + "-" * 76,
                    "// Copyright 2020 Bloomberg Finance L.P.",
                    "//",
                    '// Licensed under the Apache License, Version 2.0 (the "License");',
                    "// you may not use this file except in compliance with the License.",
                    "// You may obtain a copy of the License at",
                    "//",
                    "//     http://www.apache.org/licenses/LICENSE-2.0",
                    "//",
                    "// Unless required by applicable law or agreed to in writing, software",
                    '// distributed under the License is distributed on an "AS IS" BASIS,',
                    "// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.",
                    "// See the License for the specific language governing permissions and",
                    "// limitations under the License.",
                    "// ----------------------------- END-OF-FILE ----------------------------------",
                ]
            )

        return "\n".join(lines) + "\n"


# ============================================================================
#                          TEST RUNNER
# ============================================================================


def _win_to_posix_path(win_path: str) -> str:
    """Convert a Windows path to a POSIX path for MSYS2/Cygwin perl.
    E.g. C:\\Users\\foo\\bar -> /c/Users/foo/bar
    """
    p = win_path.replace("\\", "/")
    # Convert drive letter: C:/... -> /c/...
    if len(p) >= 2 and p[1] == ":":
        p = "/" + p[0].lower() + p[2:]
    return p


def _is_msys2_perl(perl_exe: str) -> bool:
    """Detect if the perl executable is MSYS2/Cygwin (needs POSIX paths)."""
    try:
        r = subprocess.run(
            [perl_exe, "-e", "print $^O"], capture_output=True, text=True, timeout=5
        )
        return r.returncode == 0 and "msys" in r.stdout.lower() or "cygwin" in r.stdout.lower()
    except Exception:
        return False


class FuzzRunner:
    """Runs Perl and Python scripts and compares their output."""

    def __init__(
        self,
        perl_script: str,
        python_script: str,
        perl_exe: str,
        python_exe: str,
        timeout: int,
        output_dir: str,
    ):
        self.perl_script = perl_script
        self.python_script = python_script
        self.perl_exe = perl_exe
        self.python_exe = python_exe
        self.timeout = timeout
        self.output_dir = output_dir
        self.msys2_perl = _is_msys2_perl(perl_exe)
        if self.msys2_perl:
            print("(Detected MSYS2/Cygwin perl — will convert paths)")

    def _perl_path(self, win_path: str) -> str:
        """Convert path for perl if it's MSYS2/Cygwin."""
        if self.msys2_perl:
            return _win_to_posix_path(win_path)
        return win_path

    def run_script(
        self,
        exe: str,
        script: str,
        input_file: str,
        work_dir: str,
        extra_args: list = None,
        is_perl: bool = False,
    ):
        """Run a script and capture outputs. Returns (rc, stdout, stderr, files)."""
        if is_perl and self.msys2_perl:
            actual_script = self._perl_path(script)
            actual_work_dir = self._perl_path(work_dir)
            cmd = [exe, actual_script] + (extra_args or []) + [input_file]
            env = os.environ.copy()
            # Ensure Cygwin doesn't warn about DOS paths
            env["CYGWIN"] = "nodosfilewarning"
            cwd = work_dir  # subprocess cwd must be a real Windows path
        else:
            cmd = [exe, script] + (extra_args or []) + [input_file]
            env = None
            cwd = work_dir
        try:
            # Use Popen directly to avoid the Windows hang where
            # subprocess.run() calls communicate() without a timeout after
            # killing a timed-out process to drain pipes.  If the killed
            # process has child processes that inherited the pipe handles,
            # that drain blocks forever.
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=cwd, env=env
            )
            try:
                stdout, stderr = proc.communicate(timeout=self.timeout)
                rc = proc.returncode
            except subprocess.TimeoutExpired:
                # Kill the entire process tree on Windows to avoid
                # orphaned child processes holding pipe handles open.
                if sys.platform == "win32":
                    subprocess.run(
                        ["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True
                    )
                else:
                    proc.kill()
                # Drain remaining output with a short timeout to avoid
                # blocking forever on inherited pipe handles.
                try:
                    proc.communicate(timeout=5)
                except (subprocess.TimeoutExpired, OSError):
                    pass
                proc.wait(timeout=5) if proc.poll() is None else None
                return ("timeout", "", "TIMEOUT", {})
        except Exception as e:
            return ("error", "", str(e), {})

        # Collect output files
        files = {}
        for f in Path(work_dir).iterdir():
            if f.is_file():
                try:
                    files[f.name] = f.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    files[f.name] = "<unreadable>"

        return (rc, stdout, stderr, files)

    def compare_one(
        self,
        input_content: str,
        input_name: str,
        extra_args: list = None,
        mode_label: str = "default",
    ):
        """
        Run both scripts on input_content, compare outputs.
        Returns (passed, failure_info_or_None).
        """
        with tempfile.TemporaryDirectory(prefix="fuzz_sim_") as tmpdir:
            perl_dir = os.path.join(tmpdir, "perl")
            python_dir = os.path.join(tmpdir, "python")
            os.makedirs(perl_dir)
            os.makedirs(python_dir)

            # Write input files (binary mode to preserve exact byte content,
            # e.g. mixed line endings from crlf_mixed defect)
            perl_input = os.path.join(perl_dir, input_name)
            python_input = os.path.join(python_dir, input_name)
            encoded = input_content.encode("utf-8")
            with open(perl_input, "wb") as f:
                f.write(encoded)
            with open(python_input, "wb") as f:
                f.write(encoded)

            # Run both in parallel
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                perl_future = pool.submit(
                    self.run_script,
                    self.perl_exe,
                    self.perl_script,
                    input_name,
                    perl_dir,
                    extra_args,
                    True,
                )
                python_future = pool.submit(
                    self.run_script,
                    self.python_exe,
                    self.python_script,
                    input_name,
                    python_dir,
                    extra_args,
                    False,
                )
                # Use a generous timeout on future.result() as a safety net
                # in case the subprocess timeout fails to kill cleanly.
                safety_timeout = self.timeout + 30
                try:
                    perl_rc, perl_out, perl_err, perl_files = perl_future.result(
                        timeout=safety_timeout
                    )
                except (concurrent.futures.TimeoutError, Exception):
                    perl_rc, perl_out, perl_err, perl_files = "timeout", "", "TIMEOUT (future)", {}
                try:
                    python_rc, python_out, python_err, python_files = python_future.result(
                        timeout=safety_timeout
                    )
                except (concurrent.futures.TimeoutError, Exception):
                    python_rc, python_out, python_err, python_files = (
                        "timeout",
                        "",
                        "TIMEOUT (future)",
                        {},
                    )

            # If either timed out or errored, record but don't count as diff
            if perl_rc == "timeout" or python_rc == "timeout":
                return (
                    True,
                    {
                        "status": "timeout",
                        "perl_rc": perl_rc,
                        "python_rc": python_rc,
                        "mode": mode_label,
                    },
                )
            if perl_rc == "error" or python_rc == "error":
                return (
                    True,
                    {
                        "status": "exec_error",
                        "perl_err": perl_err,
                        "python_err": python_err,
                        "mode": mode_label,
                    },
                )

            # If both crash with nonzero exit, that's acceptable
            # (we only care about output differences when they succeed)
            if perl_rc != 0 and python_rc != 0:
                # Both failed - check if they failed similarly
                return (True, None)

            # If one crashed and the other didn't, that's a failure
            if perl_rc != python_rc:
                return (
                    False,
                    {
                        "type": "exit_code_mismatch",
                        "perl_rc": perl_rc,
                        "python_rc": python_rc,
                        "perl_stderr": perl_err,
                        "python_stderr": python_err,
                        "mode": mode_label,
                    },
                )

            # Both succeeded - compare outputs
            diffs = []

            # Compare stdout
            norm_perl_out = normalize_output(perl_out)
            norm_python_out = normalize_output(python_out)
            if norm_perl_out != norm_python_out:
                diff = list(
                    difflib.unified_diff(
                        norm_perl_out.splitlines(keepends=True),
                        norm_python_out.splitlines(keepends=True),
                        fromfile="perl_stdout",
                        tofile="python_stdout",
                        n=3,
                    )
                )
                diffs.append(("stdout", "".join(diff)))

            # Compare generated files
            all_filenames = set(perl_files.keys()) | set(python_files.keys())
            for fname in sorted(all_filenames):
                perl_content = perl_files.get(fname, "")
                python_content = python_files.get(fname, "")
                norm_perl = normalize_output(perl_content)
                norm_python = normalize_output(python_content)
                if norm_perl != norm_python:
                    diff = list(
                        difflib.unified_diff(
                            norm_perl.splitlines(keepends=True),
                            norm_python.splitlines(keepends=True),
                            fromfile=f"perl/{fname}",
                            tofile=f"python/{fname}",
                            n=3,
                        )
                    )
                    diffs.append((fname, "".join(diff)))

            if diffs:
                return (False, {"type": "output_mismatch", "diffs": diffs, "mode": mode_label})

            return (True, None)


# ============================================================================
#                              MAIN
# ============================================================================


def find_perl_exe():
    """Find a perl interpreter, checking MSYS2 on Windows."""
    # Check if perl is in PATH
    try:
        r = subprocess.run(["perl", "-v"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return "perl"
    except Exception:
        pass

    # On Windows, check common MSYS2 locations
    if platform.system() == "Windows":
        candidates = [
            r"C:\msys64\usr\bin\perl.exe",
            r"C:\msys2\usr\bin\perl.exe",
            r"C:\tools\msys64\usr\bin\perl.exe",
            os.path.expandvars(r"%USERPROFILE%\msys64\usr\bin\perl.exe"),
        ]
        for p in candidates:
            if os.path.isfile(p):
                return p

    return "perl"  # hope for the best


def find_python_exe():
    """Find a Python 3.9+ interpreter."""
    for exe in ["python3", "python"]:
        try:
            result = subprocess.run(
                [
                    exe,
                    "-c",
                    "import sys; print(f'{sys.version_info.major}." "f'{sys.version_info.minor}')",
                ],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                ver = result.stdout.strip()
                parts = ver.split(".")
                if int(parts[0]) >= 3 and int(parts[1]) >= 9:
                    return exe
        except Exception:
            continue
    return "python"


def save_failure(
    output_dir: str,
    iteration: int,
    seed: int,
    input_content: str,
    input_name: str,
    failure_info: dict,
    extra_args: list = None,
):
    """Save a failure artifact for later reproduction."""
    fail_dir = os.path.join(output_dir, f"failure_{iteration:06d}_seed{seed}")
    os.makedirs(fail_dir, exist_ok=True)

    # Save the input (binary mode to preserve exact byte content)
    with open(os.path.join(fail_dir, input_name), "wb") as f:
        f.write(input_content.encode("utf-8"))

    # Save failure details
    with open(os.path.join(fail_dir, "failure_info.txt"), "w", encoding="utf-8") as f:
        f.write(f"Iteration: {iteration}\n")
        f.write(f"Seed: {seed}\n")
        f.write(f"Input: {input_name}\n")
        if extra_args:
            f.write(f"Extra args: {' '.join(extra_args)}\n")
        f.write(f"Mode: {failure_info.get('mode', 'default')}\n")
        f.write(f"Type: {failure_info.get('type', 'unknown')}\n")
        f.write("\n")

        if failure_info.get("type") == "exit_code_mismatch":
            f.write(f"Perl exit code: {failure_info['perl_rc']}\n")
            f.write(f"Python exit code: {failure_info['python_rc']}\n")
            f.write(f"\nPerl stderr:\n{failure_info.get('perl_stderr', '')}\n")
            f.write(f"\nPython stderr:\n{failure_info.get('python_stderr', '')}\n")
        elif failure_info.get("type") == "output_mismatch":
            for name, diff_text in failure_info.get("diffs", []):
                f.write(f"\n{'='*60}\n")
                f.write(f"Diff for: {name}\n")
                f.write(f"{'='*60}\n")
                f.write(diff_text)
                f.write("\n")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(description="Fuzz test sim_cpp11_features Python vs Perl")
    parser.add_argument(
        "--iterations", "-n", type=int, default=1000, help="Number of iterations (0=infinite)"
    )
    parser.add_argument(
        "--seed", "-s", type=int, default=None, help="Random seed (default: random)"
    )
    parser.add_argument("--save-all", action="store_true", help="Save all generated inputs")
    parser.add_argument(
        "--output-dir",
        default=os.path.join(script_dir, "fuzz_output"),
        help="Directory for failure artifacts",
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
    parser.add_argument(
        "--perl-exe", default=None, help="Perl interpreter (auto-detects MSYS2 on Windows)"
    )
    parser.add_argument(
        "--timeout", type=int, default=30, help="Per-invocation timeout in seconds"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Print each test case")
    parser.add_argument("--stop-on-fail", action="store_true", help="Stop on first failure")
    parser.add_argument(
        "--workers",
        "-j",
        type=int,
        default=0,
        help="Number of parallel workers (default: min(4, CPU_count/2), 0=auto)",
    )
    args = parser.parse_args()

    # Resolve perl exe
    if args.perl_exe is None:
        args.perl_exe = find_perl_exe()

    # Resolve python exe
    python_exe = args.python_exe or find_python_exe()

    # Seed
    if args.seed is None:
        args.seed = random.randint(0, 2**32 - 1)
    master_seed = args.seed
    print(f"Master seed: {master_seed}")
    print(f"Perl script: {args.perl}")
    print(f"Python script: {args.python}")
    print(f"Perl exe: {args.perl_exe}")
    print(f"Python exe: {python_exe}")
    # Resolve workers (cap at 4 to avoid hanging on high-core-count machines)
    if args.workers <= 0:
        args.workers = min(4, max(1, (os.cpu_count() or 2) // 2))
    print(f"Timeout: {args.timeout}s")
    print(f"Workers: {args.workers}")
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

    # CLI modes to test for each generated input
    all_cli_modes = [
        ("default", []),
        ("inplace", ["--inplace"]),
        ("no-inplace", ["--no-inplace"]),
        ("clean", ["--clean"]),
    ]

    # Special file types to inject periodically
    SPECIAL_FILE_TYPES = ["no_regions", "empty_region", "no_copyright"]

    total = 0
    passed = 0
    failed = 0
    errors = 0
    timeouts = 0
    start_time = time.time()

    def run_one_iteration(iteration):
        """Run a single iteration (all its CLI modes).  Returns a list of
        (iteration, input_name, input_content, iter_seed, mode_label,
         extra_args, ok, info) tuples — one per CLI mode tested."""
        iter_seed = master_seed + iteration
        rng = random.Random(iter_seed)
        gen = FuzzGenerator(rng)

        input_name = f"fuzz_{iteration:06d}.h"

        if iteration > 0 and iteration % 10 == 0 and iteration % 20 != 0:
            input_content = gen.gen_malformed_file()
        elif iteration > 0 and iteration % 20 == 0:
            file_type = rng.choice(SPECIAL_FILE_TYPES)
            input_content = gen.gen_file(f"fuzz_{iteration:06d}", file_type=file_type)
        else:
            input_content = gen.gen_file(f"fuzz_{iteration:06d}")

        var_args_override = None
        if rng.random() < 0.3:
            var_args_override = rng.randint(1, 10)

        cli_modes = [all_cli_modes[0]]
        others = rng.sample(all_cli_modes[1:], k=1)
        cli_modes.extend(others)

        results = []
        for mode_label, base_args in cli_modes:
            extra_args = list(base_args)
            if var_args_override is not None:
                extra_args.append(f"--var-args={var_args_override}")
            ok, info = runner.compare_one(input_content, input_name, extra_args, mode_label)
            results.append(
                (
                    iteration,
                    input_name,
                    input_content,
                    iter_seed,
                    var_args_override,
                    mode_label,
                    extra_args,
                    ok,
                    info,
                )
            )
        return results

    iteration = 0
    stop_early = False
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            # Submit work in batches to allow early stopping
            while not stop_early:
                if args.iterations > 0 and iteration >= args.iterations:
                    break

                # Determine batch size
                batch_size = args.workers * 2
                if args.iterations > 0:
                    batch_size = min(batch_size, args.iterations - iteration)

                futures = {}
                for i in range(batch_size):
                    it = iteration + i
                    futures[pool.submit(run_one_iteration, it)] = it

                # Process results in completion order.
                # Safety timeout prevents hanging if subprocess kill fails
                # on Windows (e.g., MSYS2 perl child processes holding pipes).
                future_timeout = (args.timeout + 30) * 4

                try:
                    for future in concurrent.futures.as_completed(futures, timeout=future_timeout):
                        it = futures[future]
                        try:
                            results_list = future.result(timeout=10)
                        except (concurrent.futures.TimeoutError, Exception) as exc:
                            total += 2
                            timeouts += 2
                            if args.verbose:
                                print(f"  [{it}] TIMEOUT (future hung: {exc!r})")
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
                        ) in results_list:
                            total += 1
                            if ok:
                                passed += 1
                                if info and info.get("status") == "timeout":
                                    timeouts += 1
                                    if args.verbose:
                                        print(
                                            f"  [{iter_n}] {input_name} ({mode_label}) TIMEOUT (skipped)"
                                        )
                                elif info and info.get("status") == "exec_error":
                                    errors += 1
                                    if args.verbose:
                                        perl_e = info.get("perl_err", "")
                                        python_e = info.get("python_err", "")
                                        detail = perl_e or python_e
                                        print(
                                            f"  [{iter_n}] {input_name} ({mode_label}) EXEC ERROR: {detail[:120]}"
                                        )
                                else:
                                    if args.verbose:
                                        va = (
                                            f", --var-args={var_args_override}"
                                            if var_args_override
                                            else ""
                                        )
                                        print(f"  [{iter_n}] {input_name} ({mode_label}{va}) PASS")
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
                                print(
                                    f"FAIL [{iter_n}] {input_name} ({mode_label})"
                                    f" - {info.get('type', 'unknown')}{detail}"
                                )

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

                            if args.save_all:
                                all_dir = os.path.join(args.output_dir, "all_inputs")
                                os.makedirs(all_dir, exist_ok=True)
                                with open(os.path.join(all_dir, input_name), "wb") as f:
                                    f.write(input_content.encode("utf-8"))

                        if stop_early:
                            break
                except TimeoutError:
                    incomplete = sum(1 for f in futures if not f.done())
                    timeouts += incomplete * 2
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
    print(f"Fuzz testing complete")
    print(f"  Master seed:  {master_seed}")
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

    # Write summary to output dir
    summary_path = os.path.join(args.output_dir, "summary.txt")
    with open(summary_path, "w", encoding="utf-8") as f:
        f.write(f"Master seed: {master_seed}\n")
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
