#!/usr/bin/env python3.9
# -*- coding: utf-8 -*-
"""
sim_cpp11_features.py - Python version of sim_cpp11_features.pl

This program converts a file with specially delimited regions of C++11 code
and generates a C++03 version of that code that emulates the C++11 features.

Currently, this program emulates two constructs:
  - Variadic templates are emulated by creating multiple copies of the
    template code, starting with zero template arguments and adding an
    argument with each repetition (up to 10 arguments by default).
  - Forwarding references in function arguments are emulated by surrounding
    the argument declaration in a BSLS_COMPILERFEATURES_FORWARD_REF macro
    invocation and replacing std::forward calls with
    BSLS_COMPILERFEATURES_FORWARD.

Both emulations are approximate, at best, but experience has found them to be
extremely useful.
"""

import argparse
import os
import re
import sys
from datetime import datetime
from typing import Optional, List, Tuple, Dict

# ============================================================================
#                             GLOBAL STATE
# ============================================================================

# Debug settings
debug_level = 0
trace_ctrls: Dict[str, int] = {}

# Configuration globals
clean = False
inplace = False
verify_no_change = False
self_test = False
default_max_args = 10
file_max_args = default_max_args
max_args = file_max_args
max_args_opt = 0  # Command-line specified max args
max_column = 79  # Maximum allowed output line length
command_line = ""
timestamp_prefix = "Generated on "
timestamp_comment = ""
variadic_limit_base = ""
variadic_limit = ""
bottom_copyright = ""  # Copyright text extracted from input file (bottom style)
top_copyright = ""  # Copyright text extracted from input file (top style)

# Set of class templates that have been forward declared already
class_template_forward_declared: Dict[str, bool] = {}

# 80 spaces for constructing indentations
SPACES = " " * 80

# Dummy character to fill in for string literal contents in stripped code buffers
DUMMY_CHAR = "."  # For debug mode; use "\xb7" (centered dot) for production

# ============================================================================
#                           INPUT CONTEXT
# ============================================================================

# Input file as a single string
input_text = ""
input_end = 0
shrouded_input = ""
input_pos = 0

# Input context stack
input_stack: List[Tuple[str, int, str, int]] = []

# cppSearch state
cpp_match: List[Optional[str]] = []
cpp_match_all: Optional[str] = None
cpp_match_start: List[int] = []
cpp_match_end: List[int] = []

# Matching brackets
MATCHING_BRACKETS = {"[": "]", "{": "}", "(": ")", "<": ">"}

# ============================================================================
#                           UTILITY FUNCTIONS
# ============================================================================


def fatal(message: str) -> None:
    """Print error message and exit."""
    print(f"!! {message}", file=sys.stderr)
    print("Fatal error", file=sys.stderr)
    sys.exit(1)


def usage(message: str) -> None:
    """Print usage message and exit."""
    print(f"""{message}
Usage: sim_cpp11_features.pl [ --output=<filename> ]
                             [ --var-args=<max-args> ]
                             [ --debug=<level> ]
                             [ --trace=<subroutine>:<level> ]
                             [ --[no-]inplace ]
                             [ --verify-no-change ]
                             [ --clean ]
                             [ --test ]
                             {{ <input-file>... | - }}""")
    sys.exit(1)


def debug_print(message: str) -> None:
    """Print debug message if debug level is >= 1."""
    if debug_level >= 1:
        print(f"## {message}", file=sys.stderr)


def get_trace_level(trace_label: str) -> int:
    """Return the larger of the level for the specified trace label or debug level."""
    trace_level = trace_ctrls.get(trace_label, 0)
    return max(trace_level, debug_level)


def trace(trace_label: str, message: str, *args) -> None:
    """Trace message at level 1."""
    trace_level = get_trace_level(trace_label)
    if trace_level >= 1:
        formatted = message % args if args else message
        print(f"{trace_label} ## {formatted}", file=sys.stderr)


def trace2(trace_label: str, message: str, *args) -> None:
    """Trace message at level 2."""
    trace_level = get_trace_level(trace_label)
    if trace_level >= 2:
        formatted = message % args if args else message
        print(f"{trace_label} ### {formatted}", file=sys.stderr)


# ============================================================================
#                      COMMENT AND STRING HANDLING
# ============================================================================

# Regular expression to find a comment or string literal
COMMENT_AND_STRING_RE = re.compile(
    r"""(?:
        (//(?:[^\\\n]+|\\.|\\\n)*$)    |  # C++-style comment
        (/\*(?:[^*]+|\*[^*/])*\*/)     |  # C-style comment
        ("(?:[^"\\\n]+|\\.|\\\n)*["\n]) | # string literal
        ('(?:[^'\\\n]+|\\.|\\\n)*['\n])   # character literal
    )""",
    re.MULTILINE | re.VERBOSE,
)


def comment_to_whitespace(comment: str, option: str = "single-ws") -> str:
    """
    Return a string of whitespace to replace the specified comment string.

    Options:
      "single-ws"  Result contains a single whitespace character.
      "keep-nl"    Result contains the same number of newlines as 'comment'.
      "keep-len"   Result is the same length as 'comment' with newlines preserved.
    """
    last = comment[-1] if comment else ""

    if option == "single-ws":
        return "\n" if last == "\n" else " "
    elif option == "keep-nl":
        result = re.sub(r"[^\n]", "", comment)
        return result if result else " "
    elif option == "keep-len":
        return re.sub(r"[^\n]", " ", comment)
    else:
        fatal(f"Illegal option {option}")
        return ""


def shroud_comments_and_strings(text: str) -> str:
    """
    Return the result of 'shrouding' comments, string literals, and character
    literals in the specified string so that they contain no C++ tokens that
    might confuse a regular expression search.
    """
    result = text
    pos = 0

    while True:
        match = COMMENT_AND_STRING_RE.search(result, pos)
        if not match:
            break

        start, end = match.start(), match.end()
        comment = match.group(1) or match.group(2)
        literal = match.group(3) or match.group(4)

        if comment:
            replacement = comment_to_whitespace(comment, "keep-len")
        elif literal:
            first = result[start]
            last = result[end - 1]
            replacement = DUMMY_CHAR * len(literal)
            replacement = first + replacement[1:-1] + last
        else:
            raise RuntimeError("Shouldn't get here")

        result = result[:start] + replacement + result[end:]
        pos = start + len(replacement)

    return result


def strip_comments(text: str, option: str = "single-ws") -> str:
    """
    Strip comments from the specified text, replacing them with whitespace.

    Options:
      "single-ws"  Replace each comment with a single whitespace character.
      "keep-nl"    Replace each comment with whitespace containing same newlines.
      "keep-len"   Replace each comment with whitespace of the same length.
    """
    result = text
    pos = 0

    # Pattern to match comments with optional surrounding horizontal whitespace
    pattern = re.compile(
        r"[ \t]*" + COMMENT_AND_STRING_RE.pattern + r"[ \t]*\n?", re.MULTILINE | re.VERBOSE
    )

    while True:
        match = pattern.search(result, pos)
        if not match:
            break

        start, end = match.start(), match.end()
        last = result[-1] if result else ""

        if match.group(1) or match.group(2):
            comment = match.group(0)
            if (
                option == "single-ws"
                and last == "\n"
                and (start == 0 or result[start - 1] == "\n")
            ):
                # Comment takes one or more whole lines. Replace with nothing.
                comment = ""
            else:
                comment = comment_to_whitespace(comment, option)
            result = result[:start] + comment + result[end:]
            pos = start + len(comment)
        else:
            pos = end

    return result


# ============================================================================
#                           INPUT MANAGEMENT
# ============================================================================


def set_input(instr: str) -> None:
    """Sets the input string and resets/populates the shrouded input string."""
    global input_text, input_end, input_pos, shrouded_input

    input_text = instr.replace("\r\n", "\n")  # Normalize newlines
    if input_text and input_text[-1] != "\n":
        input_text += "\n"
    input_end = len(input_text)
    input_pos = 0
    shrouded_input = shroud_comments_and_strings(input_text)


def push_input(instr: str) -> None:
    """Like set_input but preserves the previous input context."""
    global input_stack
    input_stack.append((input_text, input_end, shrouded_input, input_pos))
    set_input(instr)


def pop_input() -> str:
    """Restore the input context from the top of the context stack."""
    global input_text, input_end, shrouded_input, input_pos

    if not input_stack:
        raise RuntimeError("Empty input stack")

    ret = input_text
    input_text, input_end, shrouded_input, input_pos = input_stack.pop()
    return ret


# ============================================================================
#                           C++ CODE SEARCHES
# ============================================================================


def cpp_search(pattern: str, pos: int = 0, endpos: Optional[int] = None) -> bool:
    """
    Search the input string for the specified pattern.
    Skip matches within comments, string literals, and character literals.

    Sets global variables cpp_match, cpp_match_all, cpp_match_start, cpp_match_end.
    Returns True on success, False on failure.
    """
    global cpp_match, cpp_match_all, cpp_match_start, cpp_match_end, input_pos

    if endpos is None:
        endpos = input_end

    # Handle \G anchor (match at position) by using match instead of search
    anchored = False
    if isinstance(pattern, str) and pattern.startswith(r"\G"):
        pattern = pattern[2:]  # Remove \G prefix
        anchored = True

    # Compile pattern if it's a string
    if isinstance(pattern, str):
        regex = re.compile(pattern, re.MULTILINE)
    else:
        regex = pattern

    if anchored:
        match = regex.match(shrouded_input, pos, endpos)
    else:
        match = regex.search(shrouded_input, pos, endpos)
    if match and match.end() <= endpos:
        cpp_match_start = [match.start()] + [match.start(i) for i in range(1, regex.groups + 1)]
        cpp_match_end = [match.end()] + [match.end(i) for i in range(1, regex.groups + 1)]

        # Get actual text from original input (not shrouded)
        cpp_match_all = input_text[cpp_match_start[0] : cpp_match_end[0]]
        cpp_match = [cpp_match_all]

        for i in range(1, len(cpp_match_start)):
            if cpp_match_start[i] is not None and cpp_match_start[i] >= 0:
                cpp_match.append(input_text[cpp_match_start[i] : cpp_match_end[i]])
            else:
                cpp_match.append(None)

        input_pos = cpp_match_end[0]
        return True

    # No match found
    cpp_match = []
    cpp_match_all = None
    cpp_match_start = []
    cpp_match_end = []
    return False


def cpp_substitute(start: int, length: int, subst: str) -> None:
    """
    Replace the substring in input beginning at the specified start position.
    Adjust all of the cppSearch state accordingly.
    """
    global input_text, shrouded_input, input_end, cpp_match_start, cpp_match_end, input_pos

    end = start + length
    length_change = len(subst) - length

    input_text = input_text[:start] + subst + input_text[end:]
    shrouded_input = (
        shrouded_input[:start] + shroud_comments_and_strings(subst) + shrouded_input[end:]
    )

    # Adjust match positions
    for i in range(len(cpp_match_start)):
        if cpp_match_start[i] is not None and cpp_match_start[i] >= end:
            cpp_match_start[i] += length_change

    for i in range(len(cpp_match_end)):
        if cpp_match_end[i] is not None and cpp_match_end[i] >= end:
            cpp_match_end[i] += length_change

    if input_pos >= end:
        input_pos += length_change

    input_end += length_change


def cpp_find_matching_pp_directive(pos: int, what: str = "else|elif|endif") -> bool:
    """
    Find the position of the next directive at the same nesting level
    that is part of the same #if...#endif construct.

    Returns True if match found, False otherwise.
    """
    trace("cppFindMatchingPPDirective", "pos = %d, what = %s", pos, what)

    depth = 1
    while cpp_search(r"^[ \t]*\#[ \t]*(\w+).*\n", pos):
        pos = cpp_match_end[0]
        pp_directive = cpp_match[1] or ""

        if depth == 1:
            if re.match(f"^({what})$", pp_directive):
                trace("cppFindMatchingPPDirective", "Found match '%s' at %d", pp_directive, pos)
                return True
            elif pp_directive == "endif":
                trace("cppFindMatchingPPDirective", "No match")
                return False

        if pp_directive.startswith("if"):  # match #if, #ifdef, #ifndef
            depth += 1
        if pp_directive == "endif":
            depth -= 1

    if depth != 1:
        fatal(f"Unmatched #if at position {pos}")

    trace("cppFindMatchingPPDirective", "No match")
    return False


def line_and_column(pos: int) -> Tuple[int, int]:
    """Return the input line number and column number at the specified pos."""
    fragment = input_text[:pos]

    # Count newlines
    line_num = fragment.count("\n") + 1

    # Count characters after last newline
    last_newline = fragment.rfind("\n")
    col_num = pos - last_newline if last_newline >= 0 else pos + 1

    return (line_num, col_num)


def display_pos(pos: int) -> str:
    """Error-handling routine to print the line at the specified pos with a caret."""
    if pos == input_end:
        return "\n^\n"

    line_num, col = line_and_column(pos)

    # Find the line containing pos
    line_start = input_text.rfind("\n", 0, pos) + 1
    line_end = input_text.find("\n", pos)
    if line_end < 0:
        line_end = input_end

    line = input_text[line_start : line_end + 1]
    col_in_line = pos - line_start

    return line + (" " * col_in_line) + "^\n"


def bracket_depth(init_depth: Optional[int], input_line: str, brackets: str) -> Optional[int]:
    """
    Returns the bracket nesting depth at the end of input_line given a
    starting depth of init_depth.
    """
    open_brackets = ""
    close_brackets = ""

    for bracket in brackets:
        open_brackets += bracket
        close_brackets += MATCHING_BRACKETS.get(bracket, "")

    all_brackets = open_brackets + close_brackets
    close_brackets_re = re.compile(f"[{re.escape(close_brackets)}]")

    parens = re.findall(f"[{re.escape(all_brackets)}]", input_line)

    if not parens:
        return init_depth

    depth = init_depth if init_depth is not None else 0

    for paren in parens:
        if close_brackets_re.match(paren):
            depth -= 1
        else:
            depth += 1

    return depth


def find_matching_brace(brace: str, pos: int) -> int:
    """
    Find the specified brace in input starting at pos, then return the
    position immediately after the matching end brace.
    """
    start_pos = pos

    open_braces = "[({"
    close_braces = "})]"
    if brace == "<":
        open_braces += "<"
        close_braces += ">"
    all_braces = open_braces + close_braces
    # Need to escape [ and ] for regex character class
    all_braces_escaped = all_braces.replace("[", "\\[").replace("]", "\\]")
    all_braces_re = f"[{all_braces_escaped}]"

    matching_brace_stack: List[str] = []
    done = False

    while not done:
        if not cpp_search(all_braces_re, pos):
            break

        brace_pos = cpp_match_start[0]
        pos = cpp_match_end[0]
        found_brace = input_text[brace_pos]

        matching_brace = MATCHING_BRACKETS.get(found_brace)

        if matching_brace:
            # Found an open brace
            if not matching_brace_stack and found_brace != brace:
                # Fail: No match.
                return start_pos

            matching_brace_stack.append(matching_brace)
        else:
            # Found closing brace. Pop matching brace off the stack.
            # Pop any unmatched '<' off the stack
            while (
                matching_brace_stack
                and matching_brace_stack[-1] != found_brace
                and matching_brace_stack[-1] == ">"
            ):
                matching_brace_stack.pop()

            if matching_brace_stack and matching_brace_stack[-1] == found_brace:
                matching_brace_stack.pop()
            elif found_brace == ">":
                # Ignore unmatched '>'
                continue
            else:
                fatal(
                    f"Mismatched brace '{found_brace}'; "
                    f"expecting '{matching_brace_stack[-1]}' at line "
                    f"{line_and_column(brace_pos)[0]}\n{display_pos(brace_pos)}"
                )

            done = not matching_brace_stack

    return pos


# ============================================================================
#                      TEMPLATE PARAMETER HANDLING
# ============================================================================

# List of types that can appear in template parameter lists
PACK_TYPES = [
    "class",
    "typename",
    "bool",
    "short",
    "unsigned short",
    "int",
    "unsigned",
    "unsigned int",
    "long",
    "unsigned long",
    "std::size_t",
    "bsl::size_t",
    "size_t",
    "std::ptrdiff_t",
    "bsl::ptrdiff_t",
    "ptrdiff_t",
]
PACK_TYPES_STR = "|".join(re.escape(t) for t in PACK_TYPES)

# Generated parameter counter
next_gen_param = 0


def gen_name(prefix: str) -> str:
    """Return a unique generated name using the supplied prefix argument."""
    global next_gen_param
    result = f"{prefix}{next_gen_param}"
    next_gen_param += 1
    return result


def get_template_params(pos: int) -> List[List[str]]:
    """
    Given an input string where the substring at pos starts with a template
    parameter list, return a list of [type, name, default] triples.
    """
    packs = []

    pattern = (
        rf"([<,]\s*)({PACK_TYPES_STR})\s*(\.\.\.)?(?:\s*([A-Za-z_]\w*))?(\s*=\s*[^>,]*)?(\s*[>,])"
    )

    while cpp_search(pattern, pos):
        pack_type = cpp_match[2] or ""
        if cpp_match[3]:
            pack_type += cpp_match[3]
        pack_name = cpp_match[4] or gen_name("__Param__")
        pack_dflt = cpp_match[5] or ""
        packs.append([pack_type, pack_name, pack_dflt])
        pos = cpp_match_start[6]  # Include closing delimiter in next search
        if ">" in (cpp_match[6] or ""):
            break

    if get_trace_level("getTemplateParams") > 0:
        pack_str = "[\n"
        for pack in packs:
            pack_str += f"  [ {pack[0]}, {pack[1]}, {pack[2]} ]\n"
        pack_str += "]"
        trace("getTemplateParams", "packs = %s", pack_str)

    return packs


# ============================================================================
#                      TEMPLATE TRANSFORMATIONS
# ============================================================================


def noop_template_transform(
    template_begin: int, template_head_end: int, template_end: int, is_variadic: bool = False
) -> str:
    """Return the template substring with comments stripped."""
    return strip_comments(input_text[template_begin:template_end])


def replace_and_fit_on_line(
    working_buffer: str, pack_start: int, pack_len: int, replacement: str
) -> str:
    """
    Replaces [pack_start, pack_end) with replacement, re-indenting as necessary
    so that longest line in replacement fits within max_column.
    """
    global input_text, shrouded_input, input_end

    pack_end = pack_start + pack_len

    trace("replaceAndFitOnLine", "START workingBuffer = [%s]", working_buffer)

    # pre_pack is the text on same line preceding the current pack
    pre_pack_match = re.search(
        r"^(.*)(?=.{" + str(len(working_buffer) - pack_start) + r"}$)", working_buffer, re.DOTALL
    )
    if pre_pack_match:
        # Find start of current line
        line_start = working_buffer.rfind("\n", 0, pack_start) + 1
        pre_pack = working_buffer[line_start:pack_start]
    else:
        pre_pack = ""
    column = len(pre_pack)

    # post_pack is the text on the same line following the current pack
    newline_pos = working_buffer.find("\n", pack_end)
    if newline_pos < 0:
        post_pack = working_buffer[pack_end:]
    else:
        post_pack = working_buffer[pack_end:newline_pos]

    # Truncate post_pack at the start of the next pack, if any
    pack_marker = re.search(r"__PACK_[VT][0-9]+[RF]__", post_pack)
    if pack_marker:
        post_pack = post_pack[: pack_marker.start()]

    post_len = len(post_pack)

    # Compute length of longest line of replacement
    last_replacement_width = 0
    max_replacement_width = 0
    for line in re.split(r"\n[ \t]*", replacement):
        last_replacement_width = len(line)
        max_replacement_width = max(max_replacement_width, last_replacement_width)

    # Calculate slack
    slack = 0
    if 0 <= post_len <= 3:
        slack = post_len
    elif re.match(r"^[ \t]*,", post_pack):
        slack = 1

    # Adjust max_replacement_width to take slack into account
    if last_replacement_width + slack > max_replacement_width:
        max_replacement_width = last_replacement_width + slack

    # Compute indentation
    target_col = column
    if column + max_replacement_width > max_column:
        target_col = max_column - max_replacement_width
    if target_col < 0:
        target_col = 0

    indentation = SPACES[:target_col]

    if replacement and target_col < column:
        overage = column - target_col
        trailing_ws_match = re.search(r"([ \t]*)$", pre_pack)
        spaces_at_end_of_prepack = len(trailing_ws_match.group(1)) if trailing_ws_match else 0

        if overage <= spaces_at_end_of_prepack:
            pack_start -= overage
        else:
            replacement = "\n" + replacement
            pack_start -= spaces_at_end_of_prepack

    # Insert indentation after every newline in replacement
    replacement = re.sub(r"\n[ \t]*", "\n" + indentation, replacement)

    if target_col + last_replacement_width + post_len > max_column:
        # post_pack will not fit on the same line as the last line
        # Remove any leading commas from post_pack
        comma_match = re.match(r"^([ \t]*(,?)[ \t]*)", post_pack)
        if comma_match:
            removed_len = len(comma_match.group(1))
            comma = comma_match.group(2)
            pack_end += removed_len
        else:
            comma = ""

        if target_col + post_len > max_column:
            # Even at the same indentation as the previous line, it
            # still doesn't fit.  Reduce indentation as needed.
            # Note: mirrors Perl's substr($spaces, 0, $maxColumn - $postLen).
            # Python's negative slice handles the same semantics:
            # positive N -> first N chars; negative N -> all but last |N|.
            indentation = SPACES[: max_column - post_len]

        replacement = replacement.rstrip()
        replacement += comma + "\n"
        replacement += indentation

    pack_len = pack_end - pack_start

    if working_buffer is shrouded_input or id(working_buffer) == id(shrouded_input):
        cpp_substitute(pack_start, pack_len, replacement)
        trace("replaceAndFitOnLine", "RETURN SHROUDED = [%s]", shrouded_input)
        return shrouded_input
    else:
        working_buffer = (
            working_buffer[:pack_start] + replacement + working_buffer[pack_start + pack_len :]
        )
        trace("replaceAndFitOnLine", "RETURN WORKING = [%s]", working_buffer)
        return working_buffer


def replace_forwarding(
    template_begin: int, template_head_end: int, template_end: int, is_variadic: bool = False
) -> str:
    """
    Replace uses of perfect forwarding within the specified input with
    special macros.
    """
    buffer = strip_comments(input_text[template_begin:template_end])

    push_input(buffer)
    trace("replaceForwarding", "Stripped input = [%s]", buffer)

    typenames = []
    pos = 0
    while cpp_search(r"[<,]\s*(?:typename|class)(?:\s*\.\.\.)?\s*([A-Za-z_]\w*)\s*[>,]", pos):
        pos = cpp_match_end[1]
        typenames.append(cpp_match[1])

    for typename in typenames:
        pos = 0
        # Replace T&& with BSLS_COMPILERFEATURES_FORWARD_REF(T)
        pattern = rf"\b({typename}\s*&&)((?:[ \t]*\.\.\.)?\s*[A-Za-z_]\w*)?"
        while cpp_search(pattern, pos):
            argname = cpp_match[2] or ""
            argname = re.sub(r"\s+", " ", argname)

            repl_start = cpp_match_start[1]
            repl_end = cpp_match_end[2] if cpp_match[2] else cpp_match_end[1]

            replace_and_fit_on_line(
                shrouded_input,
                repl_start,
                repl_end - repl_start,
                f"BSLS_COMPILERFEATURES_FORWARD_REF({typename})" + argname,
            )

            if pos >= repl_end:
                fatal("No forward progress; endless loop")
            pos = repl_end

        pos = 0
        # Replace std::forward<T>(expr) with BSLS_COMPILERFEATURES_FORWARD(T, expr)
        pattern = rf"\b(bsl|std|native_std)\s*::\s*forward\s*<\s*{typename}\s*>\s*\("
        while cpp_search(pattern, pos):
            replace_and_fit_on_line(
                shrouded_input,
                cpp_match_start[0],
                cpp_match_end[0] - cpp_match_start[0],
                f"BSLS_COMPILERFEATURES_FORWARD({typename}, ",
            )
            pos = cpp_match_end[0]

    trace("replaceForwarding", "Result = [%s]", input_text)

    buffer = pop_input()
    return buffer


def mark_pack_expansions() -> List[str]:
    """
    Replace every parameter pack and pack expansion in input with markers.
    Return a list of pack expansion patterns.
    """
    global input_text, shrouded_input

    trace("markPackExpansions", "ORIGINAL = [%s]", input_text)

    type_names: Dict[str, bool] = {}
    pack_idents = []
    pack_expansions = []
    pack_num = 0

    # Mark packs in template headers
    pattern = rf"([<,]\s*)({PACK_TYPES_STR})\s*\.\.\.(?:\s*([A-Za-z_]\w*))?(\s*[>,])"
    while cpp_search(pattern, 0):
        pack_r = f"__PACK_V{pack_num}R__"

        pack_type = cpp_match[2] or ""
        separator = cpp_match[4] or ""
        param_pack_name = cpp_match[3] or gen_name("_Tp__")

        if re.search(r"(class|typename)", pack_type):
            pack_r = pack_r.replace("__PACK_V", "__PACK_T")
            type_names[param_pack_name] = True

        replacement = (cpp_match[1] or "") + pack_r + separator

        pack_idents.append(param_pack_name)
        pack_expansions.append(f"{pack_type} {param_pack_name}")

        input_text = (
            input_text[: cpp_match_start[0]] + replacement + input_text[cpp_match_end[0] :]
        )

        # Replace sizeof... (pack) with __PACKSIZE_#__
        pack_size = f"__PACKSIZE_{pack_num}__"
        input_text = re.sub(
            rf"\bsizeof\s*\.\.\.\s*\(\s*{param_pack_name}\s*\)", pack_size, input_text
        )
        set_input(input_text)

        pack_num = len(pack_expansions)

    if pack_num == 0:
        fatal("Expected only variadic templates")

    # Mark packs in template bodies
    B = "({<,;:"  # Beginning delimiters
    E = ";,>{}):"  # End delimiters
    pattern = rf"([{re.escape(B)}]\s*)([^{re.escape(B)}]+)\.\.\.(?:\s*([A-Za-z_]\w*))?(\s*[{re.escape(E)}])"

    while cpp_search(pattern, 0):
        trace2("markPackExpansions", "found pack = %s", cpp_match_all)
        pack_r = f"__PACK_V{pack_num}R__"

        fb = cpp_match[1] or ""  # Found beginning delimiter
        pattern_text = cpp_match[2] or ""
        if pattern_text in type_names:
            pack_r = pack_r.replace("__PACK_V", "__PACK_T")
        replacement = fb + pack_r + (cpp_match[4] or "")
        pack_ident = ""
        if cpp_match[3]:
            pack_ident = cpp_match[3]
            pattern_text += " " + pack_ident
            pack_idents.append(pack_ident)

        input_text = (
            input_text[: cpp_match_start[0]] + replacement + input_text[cpp_match_end[0] :]
        )

        # Scan backwards until pattern is fully-balanced
        while True:
            match = re.search(rf"(::\s*){pack_r}", input_text)
            if match:
                # Add leading '::' to pattern and loop
                pattern_text = match.group(1) + pattern_text
                input_text = re.sub(rf"::\s*{pack_r}", pack_r, input_text, count=1)

                # Now search for start of pattern again
                sub_match = re.search(
                    rf"([{re.escape(B)}]\s*)([^{re.escape(B)}]+\s*){pack_r}", input_text
                )
                if sub_match:
                    input_text = (
                        input_text[: sub_match.start()]
                        + sub_match.group(1)
                        + pack_r
                        + input_text[sub_match.end() :]
                    )
                    fb = sub_match.group(1) or ""
                    pattern_text = (sub_match.group(2) or "") + pattern_text
            elif bracket_depth(0, pattern_text, "[{(<") != 0:
                # Brackets were not matched
                fb_escaped = re.escape(fb)
                sub_match = re.search(
                    rf"([{re.escape(B)}]\s*)([^{re.escape(B)}]+{fb_escaped}\s*){pack_r}",
                    input_text,
                )
                if sub_match:
                    input_text = (
                        input_text[: sub_match.start()]
                        + sub_match.group(1)
                        + pack_r
                        + input_text[sub_match.end() :]
                    )
                    fb = sub_match.group(1) or ""
                    pattern_text = (sub_match.group(2) or "") + pattern_text
                else:
                    break
            else:
                break

        pack_size = f"__PACKSIZE_{pack_num}__"
        if pack_ident:
            input_text = re.sub(
                rf"\bsizeof\s*\.\.\.\s*\(\s*{pack_ident}\s*\)", pack_size, input_text
            )
        set_input(input_text)

        pack_expansions.append(pattern_text)
        pack_num = len(pack_expansions)

    # Replace identifiers with _@ suffix
    for i, pattern in enumerate(pack_expansions):
        for ident in pack_idents:
            pack_expansions[i] = re.sub(rf"\b{ident}\b", f"{ident}_@", pack_expansions[i])

    trace("markPackExpansion", "AFTER XFORM = [\n%s\n]", input_text)
    trace("markPackExpansion", 'EXPANSIONS =\n    "%s', '"\n    "'.join(pack_expansions))

    return pack_expansions


def repeat_packs(buffer: str, max_args_val: int, pack_expansions: List[str]) -> str:
    """
    Create multiple copies of buffer, replacing each __PACK_V#R__ or __PACK_T#R__
    pattern with an expansion of the parameter packs.
    """
    applied_pack_expansions = []
    output = ""

    # If max_args_val is 2 digits, pad counts
    digit_pad = "0" if max_args_val > 9 else ""
    space_pad = " " if max_args_val > 9 else ""

    for rep_count in range(max_args_val + 1):
        working_buffer = buffer

        working_buffer = f"#if {variadic_limit} >= {rep_count}\n" + working_buffer

        rep_string = ("" if rep_count > 9 else space_pad) + str(rep_count)
        rep_id_string = ("" if rep_count > 9 else digit_pad) + str(rep_count)

        # Replace __PACKSIZE_#__ with the expansion length
        working_buffer = re.sub(r"__PACKSIZE_[0-9]+__", f"{rep_string}u", working_buffer)

        for expand_num in range(len(pack_expansions)):
            match = re.search(rf"__PACK_([VT]){expand_num}([RF])__(.*)", working_buffer, re.DOTALL)
            if not match:
                fatal(f"Can't find pack {expand_num} in working buffer")
                return ""  # Unreachable, but helps mypy

            # The marker is __PACK_TnR__ - start of first capture group ([VT]) minus 7
            # gives us the start of the entire marker (__PACK_)
            pack_start = match.start(1) - 7
            pack_type = match.group(1) or ""  # 'T' for type, 'V' for value
            is_fill = (match.group(2) or "") == "F"
            pack_end = match.start(3)  # Position of trailing content
            pack_len = pack_end - pack_start

            fill_count_str = ("" if (max_args_val - rep_count) > 9 else space_pad) + str(
                max_args_val - rep_count
            )
            FILL = f"BSLS_COMPILERFEATURES_FILL{pack_type}({fill_count_str})"

            expansion_term = pack_expansions[expand_num]
            replacement = ""

            if rep_count == 0:
                # Look for comma/colon before the pack
                pre_delim = ""
                pre_match = re.search(r"([ \t]*[,:]\s*)$", working_buffer[:pack_start])
                if pre_match:
                    pre_delim = pre_match.group(1)

                # Look for comma after the pack
                post_delim = ""
                post_match = re.match(r"(\s*,\s*)", working_buffer[pack_end:])
                if post_match:
                    post_delim = post_match.group(1)

                if not is_fill:
                    if post_delim:
                        # There is a comma after the pack and pack expansion
                        # is empty. Remove comma after pack.
                        pack_len += len(post_delim)
                    elif pre_delim:
                        # There is a comma or colon before the pack and no
                        # comma after the pack and the pack expansion is
                        # empty. Remove comma or colon before the pack.
                        pack_len += len(pre_delim)
                        pack_start = pack_start - len(pre_delim)

                applied_pack_expansions.append("")
            else:
                # Replace @ with expansion number
                expansion_term = expansion_term.replace("@", rep_id_string)

            if rep_count > 0:
                applied_expansion = applied_pack_expansions[expand_num]
                if rep_count > 1:
                    applied_expansion += ",\n"
                applied_expansion += expansion_term
                replacement = applied_expansion
                applied_pack_expansions[expand_num] = applied_expansion

            if is_fill:
                if replacement:
                    replacement += ",\n"
                replacement += FILL

            working_buffer = replace_and_fit_on_line(
                working_buffer, pack_start, pack_len, replacement
            )

        working_buffer += f"#endif  // {variadic_limit} >= {rep_count}\n"
        output += working_buffer + "\n"

    return output


def transform_variadic_function(
    template_begin: int, template_head_end: int, template_end: int, is_variadic: bool = False
) -> str:
    """Transform a variadic function template."""
    global input_text

    buffer = strip_comments(input_text[template_begin:template_end])

    if not is_variadic:
        return buffer

    push_input(buffer)
    pack_expansions = mark_pack_expansions()

    # Look for out-of-line definitions of member functions or static member
    # variables of variadic classes
    pos = 0
    pattern = r"template\s*<[^{;]+__PACK_[TV][0-9]+(R)__\s*>\s*::"
    while cpp_search(pattern, pos):
        # Change R to F
        start = cpp_match_start[1]
        input_text_list = list(input_text)
        input_text_list[start] = "F"
        input_text = "".join(input_text_list)
        set_input(input_text)
        pos = cpp_match_end[0]

    buffer = input_text
    pop_input()

    # Expand parameter packs
    buffer = repeat_packs(buffer, max_args, pack_expansions)

    # Remove empty "template <>" prefixes
    buffer = re.sub(r"\btemplate\s*<\s*>\s*", "", buffer)

    return buffer


def transform_variadic_class(
    template_begin: int, template_head_end: int, template_end: int, is_variadic: bool = False
) -> str:
    """Transform a variadic class template."""
    if not is_variadic:
        return noop_template_transform(template_begin, template_head_end, template_end)

    trace("transformVariadicClass", "TEMPLATE = [%s]", input_text[template_begin:template_end])

    template_params = get_template_params(template_begin)

    cpp_search(r"\G\s*(class|struct|union)\s*([A-Za-z_]\w*)\b(.)?", template_head_end)
    class_or_struct = cpp_match[1]
    class_name = cpp_match[2]
    is_specialization = cpp_match[3] == "<" if cpp_match[3] else False
    is_forward_decl = cpp_match[3] == ";" if cpp_match[3] else False
    class_hdr_end = cpp_match_end[2]

    if is_specialization:
        class_hdr_end = find_matching_brace("<", cpp_match_start[3]) + 1
        buffer = input_text[template_begin:class_hdr_end]
    else:
        # Modify class declaration to look like a template specialization
        buffer = "template <"
        indent = "          "
        col = len(buffer)
        sep = ""
        for param in template_params:
            param_str = f"{param[0]} {param[1]}"
            if col + len(sep) + len(param_str) > max_column:
                sep = sep.rstrip()
                buffer += sep + "\n" + indent + param_str
                col = len(indent) + len(param_str)
            else:
                buffer += sep + param_str
                col += len(sep) + len(param_str)
            sep = ", "
        buffer += ">"

        buffer += input_text[template_head_end:class_hdr_end]

        # Put all of the parameters as if they were specialized
        sep = "<"
        for param in template_params:
            buffer += sep
            buffer += param[1]
            if "..." in param[0]:
                buffer += "..."
            sep = ", "
        buffer += ">"

    trace2("transformVariadicClass", "specialization buffer=[%s]", buffer)

    buffer += transform_forwarding(input_text[class_hdr_end:template_end])

    push_input(buffer)
    pack_expansions = mark_pack_expansions()
    buffer = input_text
    pop_input()

    output = ""

    # Generate forward-reference for the primary template
    class_name_key = class_name or ""
    if not is_specialization and class_name_key not in class_template_forward_declared:
        class_template_forward_declared[class_name_key] = True
        output += "template <"
        indent = "          "
        indent_comma = "        , "
        sep = ""
        for param in template_params:
            param_type, param_name, param_dflt = param
            if "..." in param_type:
                param_type = param_type.replace("...", "")
                param_nil = (
                    "BSLS_COMPILERFEATURES_NILT"
                    if re.search(r"(class|struct|union)", param_type)
                    else "BSLS_COMPILERFEATURES_NILV"
                )
                for i in range(max_args):
                    output += f"\n#if {variadic_limit} >= {i}\n"
                    sep = re.sub(r"^,\n *$", indent_comma, sep)
                    output += sep
                    sep = indent_comma
                    output += f"{param_type} {param_name}_{i} = {param_nil}"
                    output += f"\n#endif  // {variadic_limit} >= {i}\n"
                output += sep + f"{param_type} = {param_nil}"
            else:
                output += sep
                sep = ",\n" + indent
                output += f"{param_type} {param_name}{param_dflt}"
        output += f">\n{class_or_struct} {class_name};\n\n"

    if not is_forward_decl:
        output += repeat_packs(buffer, max_args, pack_expansions)

    trace("transformVariadicClass", "OUTPUT = [%s]", output)
    return output


def transform_templates(buffer: str, transform_function, transform_class) -> str:
    """
    Transforms the specified buffer, calling the specified transform functions
    on each template found.
    """
    trace("transformTemplates", "buffer = [%s]", buffer)

    # Line and column at start of this segment
    line_num, _ = line_and_column(input_pos)

    push_input(buffer)
    output = ""

    pos = 0
    while pos < input_end:
        # Find start of a template
        if not cpp_search(r"[ \t]*\btemplate\s*<", pos):
            break
        template_begin = cpp_match_start[0]

        # Copy everything before the template to output
        output += strip_comments(input_text[pos:template_begin])

        # Find end of template parameter list
        pos = find_matching_brace("<", template_begin)

        while cpp_search(r"\G\s*template\s*<", pos):
            # Template member of a template class, defined outside of the class
            pos = find_matching_brace("<", pos)

        template_head_end = pos

        # For debugging only
        template_head_line = line_and_column(pos)[0] + line_num
        trace2("transformTemplates", "Template header ends at line %d", template_head_line)

        # If the next word is "class", "struct", or "union", this is a class template
        is_class = cpp_search(r"\G\s*(?:class|struct|union)\s*[A-Za-z_]\w*\b", pos)

        # Find end of template
        if not cpp_search(r"[{;]", pos):
            fatal("Cannot find end of template")
        template_end = cpp_match_end[0]

        if cpp_match_all == "{":
            template_end = find_matching_brace("{", template_end - 1)
            if is_class:
                # Class template must be terminated by a semicolon
                if not cpp_search(r";", template_end):
                    fatal("Missing semicolon")
                template_end = cpp_match_end[0]

        # Include trailing end-of-line in template definition
        if cpp_search(r"\G[ \t]*\n", template_end):
            template_end = cpp_match_end[0]

        # Check within the template header for a variadic parameter
        is_variadic = cpp_search(
            rf"\b({PACK_TYPES_STR})\s*\.\.\.", template_begin, template_head_end
        )

        if is_class:
            output += transform_class(template_begin, template_head_end, template_end, is_variadic)
        else:
            output += transform_function(
                template_begin, template_head_end, template_end, is_variadic
            )

        pos = template_end

    output += strip_comments(input_text[pos:])

    pop_input()
    trace("transformTemplates", "output = [%s]", output)
    return output


def transform_forwarding(buffer: str) -> str:
    """Transform all uses of perfect forwarding in top-level function templates."""
    return transform_templates(buffer, replace_forwarding, noop_template_transform)


def transform_variadics(buffer: str) -> str:
    """Transform all top-level variadic templates into C++03-compatible code."""
    return transform_templates(buffer, transform_variadic_function, transform_variadic_class)


# ============================================================================
#                      SIMULATION REGION MANAGEMENT
# ============================================================================

SIM_CPP11_MACRO = "BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES"


def get_args_from_pp_line(pp_line: str) -> Tuple[int, str]:
    """
    Extract script arguments from a preprocessor directive.
    Returns (local_max_args, args_comment).
    """
    global max_args, file_max_args

    new_max_args = 0
    local_max_args = 0

    # Look for // $var-args=n
    match = re.search(r"/[/*].*\$var-args=(\d+)", pp_line)
    if match:
        new_max_args = int(match.group(1))

    # Look for // $local-var-args=n
    match = re.search(r"/[/*].*\$local-var-args=(\d+)", pp_line)
    if match:
        local_max_args = int(match.group(1))

    args_comment = ""
    if local_max_args:
        args_comment += f" $local-var-args={local_max_args}"

    # max_args_opt overrides new_max_args if both are specified
    max_args = max_args_opt or new_max_args or max_args
    if new_max_args or max_args != file_max_args:
        args_comment += f" $var-args={max_args}"
        file_max_args = max_args
    if args_comment:
        args_comment = " //" + args_comment

    return (local_max_args, args_comment)


def find_sim_cpp11_directive(pos: int) -> str:
    """
    Find a C++11 simulation #if directive.
    Returns "ifdef" or "ifndef" or "" if not found.
    """
    search_str = rf"^[ \t]*\#[ \t]*(if[ \t]*(!)?|ifdef|ifndef)[ \t]*(defined)?\(?[ \t]*\(?{SIM_CPP11_MACRO}\b.*\n"

    if cpp_search(search_str, pos):
        if cpp_match[1] == "ifndef" or (cpp_match[2] and cpp_match[2] == "!"):
            return "ifndef"
        else:
            return "ifdef"
    else:
        return ""


def find_cpp03_region_markers() -> Tuple[int, ...]:
    """
    Search the current input to find the #include <filename_cpp03.ext> pattern.
    Returns a tuple of 5 integers or empty tuple if not found.
    """
    if not cpp_search(r'^[ \t]*\#[ \t]*include[ \t]*[<"].*_cpp03(\.[^">]*)?[">]'):
        return ()

    include_start = cpp_match_start[0]
    include_directive = cpp_match[0]

    trace("findCpp03RegionMarkers", "Found #include at %d\n", include_start)

    error = f"Not within '#if {SIM_CPP11_MACRO}':\n{include_directive}"

    if find_sim_cpp11_directive(0) != "ifdef":
        fatal(error)

    if_start = cpp_match_start[0]

    if not (
        cpp_find_matching_pp_directive(cpp_match_end[0], "include")
        and cpp_match_start[0] == include_start
    ):
        fatal(error)

    if not (
        cpp_find_matching_pp_directive(cpp_match_end[0], "else")
        and cpp_match_start[0] > include_start
    ):
        fatal(error)

    else_end = cpp_match_end[0]

    if not cpp_find_matching_pp_directive(cpp_match_end[0], "endif"):
        fatal(f"Cannot find #endif after\n  {include_directive}")

    endif_start = cpp_match_start[0]
    endif_end = cpp_match_end[0]

    return (if_start, include_start, else_end, endif_start, endif_end)


def transform_file(initial_data: str, gen_master: bool) -> str:
    """Transform the initial_data from annotated C++11 into C++03."""
    global variadic_limit, max_args, file_max_args

    gen_expansion = inplace or not gen_master
    set_input(initial_data)

    trace(
        "transformFile",
        "Inputlen = %d, masterGen = %d, expansionGen = %d",
        input_end,
        gen_master,
        gen_expansion,
    )

    generated_code_begin = "// {{{ BEGIN GENERATED CODE"
    if gen_master:
        generated_code_begin += (
            "\n// The following section is automatically generated." "  **DO NOT EDIT**"
        )

    generated_code_end = "// }}} END GENERATED CODE"

    output = ""
    pos = 0

    sim_variadics_macro = "BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES"

    start_verbatim = pos
    region_count = 0

    # Iterate over regions delimited by simulation markers
    while True:
        if_type = find_sim_cpp11_directive(pos)
        if not if_type:
            break

        pos = cpp_match_end[0]

        if if_type != "ifndef":
            continue

        variadic_limit = variadic_limit_base + "_" + chr(ord("A") + region_count)
        region_count += 1

        # Output code before the #if
        end_verbatim = cpp_match_start[0]
        output += input_text[start_verbatim:end_verbatim]

        start_cpp11_segment = pos

        local_max_args, args_comment = get_args_from_pp_line(cpp_match[0] or "")

        # Find matching #else, #elif, or #endif
        if not cpp_find_matching_pp_directive(pos):
            fatal(f"Unmatched #if:\n{display_pos(end_verbatim)}")

        pp_directive = cpp_match[1]
        end_cpp11_segment = cpp_match_start[0]
        pos = cpp_match_end[0]

        if pp_directive != "endif":
            # Consume and discard input until matching #endif
            cpp_find_matching_pp_directive(pos, "endif")
            pos = cpp_match_end[0]

        start_verbatim = pos

        cpp11_segment = input_text[start_cpp11_segment:end_cpp11_segment]

        within_if = False
        if gen_master:
            output += f"#if !{SIM_CPP11_MACRO}{args_comment}\n"
            within_if = True
            output += cpp11_segment

        if clean:
            output += "#else\n"
            output += generated_code_begin + "\n"
            output += "#   error sim_cpp11_features.pl has not been run\n"
            output += generated_code_end + "\n"
            output += "#endif\n"
            within_if = False
        elif gen_expansion:
            # Temporarily change max_args
            saved_max_args = max_args
            max_args = local_max_args or max_args

            # Apply the forwarding workaround
            forwarding_workaround = transform_forwarding(cpp11_segment)
            # Chomp (remove single trailing newline, like Perl's chomp)
            if forwarding_workaround.endswith("\n"):
                forwarding_workaround = forwarding_workaround[:-1]

            # Apply the variadic template simulation
            variadic_simulation = transform_variadics(forwarding_workaround)
            # Chomp (remove single trailing newline)
            if variadic_simulation.endswith("\n"):
                variadic_simulation = variadic_simulation[:-1]

            # Restore max_args
            max_args = file_max_args

            # Generate output - check if variadic simulation differs from forwarding
            gen_variadics = variadic_simulation != forwarding_workaround

            if gen_variadics:
                output += "#elif" if within_if else "#if"
                output += f" {sim_variadics_macro}\n"
                within_if = True

                output += f"""{generated_code_begin}
// Command line: {command_line}
#ifndef {variadic_limit_base}
#define {variadic_limit_base} {saved_max_args}
#endif
#ifndef {variadic_limit}
#define {variadic_limit} {variadic_limit_base}
#endif
"""
                output += variadic_simulation + "\n"
                output += f"""#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
{forwarding_workaround}
{generated_code_end}
"""
            else:
                if within_if:
                    output += "#else\n"
                output += f"""{generated_code_begin}
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
{forwarding_workaround}
{generated_code_end}
"""

        if within_if:
            output += "#endif\n"

    # If there were no expansion regions found, return empty string
    if region_count == 0:
        return ""

    # Output remaining part of output file
    output += input_text[start_verbatim:input_end]
    return output


# ============================================================================
#                      GENERATED CODE SNIPPETS
# ============================================================================


def _make_banner_line(filename: str) -> str:
    """Build a '// filename ... -*-C++-*-' banner line padded to 79 columns."""
    prefix = "// "
    marker = "-*-C++-*-"
    spaces_needed = 79 - len(prefix) - len(filename) - len(marker)
    if spaces_needed < 1:
        spaces_needed = 1
    return f"{prefix}{filename}{' ' * spaces_needed}{marker}"


def get_cpp03_header_prefix(subs: Dict[str, str]) -> str:
    """Generate C++03 header file prefix."""
    # Calculate spacing to align -*-C++-*- marker to approximately column 79
    # The header line format is: // filename    spaces    -*-C++-*-
    filename = subs["out"]
    # Standard BDE header has 79 chars, "-*-C++-*-" is 9 chars
    # "// " prefix is 3 chars, we want the line to be about 79 chars
    total_len = 79
    marker = "-*-C++-*-"
    prefix = "// "
    spaces_needed = total_len - len(prefix) - len(filename) - len(marker)
    if spaces_needed < 1:
        spaces_needed = 1
    header_line = f"{prefix}{filename}{' ' * spaces_needed}{marker}"
    return f"""{subs['topCopyright']}{header_line}

// Automatically generated file.  **DO NOT EDIT**

#ifndef INCLUDED_{subs['COMPONENT']}_CPP03
#define INCLUDED_{subs['COMPONENT']}_CPP03

//@PURPOSE: Provide C++03 implementation for {subs['in']}
//
//@CLASSES: See {subs['in']} for list of classes
//
//@SEE_ALSO: {subs['component']}
//
//@DESCRIPTION:  This component is the C++03 translation of a C++11 component,
// generated by the 'sim_cpp11_features.pl' program.  If the original header
// contains any specially delimited regions of C++11 code, then this generated
// file contains the C++03 equivalent, i.e., with variadic templates expanded
// and rvalue-references replaced by 'bslmf::MovableRef' objects.  The header
// code in this file is designed to be '#include'd into the original header
// when compiling with a C++03 compiler.  If there are no specially delimited
// regions of C++11 code, then this header contains no code and is not
// '#include'd in the original header.
//
// {subs['timestampComment']}
// Command line: {subs['commandLine']}

#ifdef COMPILING_{subs['CPP11_SOURCEFILE']}

"""


def get_cpp03_header_suffix(subs: Dict[str, str]) -> str:
    """Generate C++03 header file suffix."""
    return f"""
#else // if ! defined(DEFINED_{subs['COMPONENT']}_H)
# error Not valid except when included from {subs['component']}.h
#endif // ! defined(COMPILING_{subs['CPP11_SOURCEFILE']})

#endif // ! defined(INCLUDED_{subs['COMPONENT']}_CPP03)
{subs['bottomCopyright']}
"""


def get_cpp03_cpp_code_prefix(subs: Dict[str, str]) -> str:
    """Generate C++03 .cpp file prefix."""
    header_line = _make_banner_line(subs["out"])
    return f"""{subs['topCopyright']}{header_line}

// Automatically generated file.  **DO NOT EDIT**

// {subs['timestampComment']}
// Command line: {subs['commandLine']}

#define INCLUDED_{subs['COMPONENT']}_CPP03  // Disable inclusion
#include <{subs['component']}_cpp03.h>      // Pro-forma #include

// Empty file except when compiling {subs['component']}.cpp
#ifdef COMPILING_{subs['CPP11_SOURCEFILE']}

"""


def get_cpp03_cpp_code_suffix(subs: Dict[str, str]) -> str:
    """Generate C++03 .cpp file suffix."""
    return f"""
#endif // defined(COMPILING_{subs['CPP11_SOURCEFILE']})
{subs['bottomCopyright']}
"""


def get_cpp03_test_driver_prefix(subs: Dict[str, str]) -> str:
    """Generate C++03 test driver prefix."""
    header_line = _make_banner_line(subs["out"])
    return f"""{subs['topCopyright']}{header_line}

// Automatically generated file.  **DO NOT EDIT**

//=============================================================================
//                             TEST PLAN
//-----------------------------------------------------------------------------
// This component is the C++03 translation of a C++11 component, generated by
// the 'sim_cpp11_features.pl' program.  If the original test driver contains
// any specially delimited regions of C++11 code, then this generated file
// contains the C++03 equivalent, i.e., with variadic templates expanded and
// rvalue-references replaced by 'bslmf::MovableRef' objects.  The test driver
// code in this file is designed to be '#include'd into the original test
// driver when compiling with a C++03 compiler.  If there are no specially
// delimited regions of C++11 code, then this test driver is a minimal 'main'
// program that tests nothing and is not '#include'd in the original.
//
// {subs['timestampComment']}
// Command line: {subs['commandLine']}

// Expanded test driver only when compiling {subs['component']}.cpp
#ifdef COMPILING_{subs['CPP11_SOURCEFILE']}

"""


def get_cpp03_test_driver_suffix(subs: Dict[str, str]) -> str:
    """Generate C++03 test driver suffix."""
    return f"""
#else // if ! defined(COMPILING_{subs['CPP11_SOURCEFILE']})

// Trivial program when not compiling {subs['component']}.t.cpp
int main() {{
    return -1;
}}

#endif // defined(COMPILING_{subs['CPP11_SOURCEFILE']})
{subs['bottomCopyright']}
"""


def get_master_prefix(subs: Dict[str, str]) -> str:
    """Generate master file prefix."""
    return f"""#if {SIM_CPP11_MACRO}
// clang-format off
// Include version that can be compiled with C++03
// {subs['timestampComment']}
// Command line: {subs['commandLine']}

# define COMPILING_{subs['CPP11_SOURCEFILE']}
# include <{subs['cpp03']}>
# undef COMPILING_{subs['CPP11_SOURCEFILE']}

// clang-format on
#else

"""


def get_master_suffix(subs: Dict[str, str]) -> str:
    """Generate master file suffix."""
    return """
#endif // End C++11 code
"""


def filename_to_boilerplate(output_filename: str) -> Tuple[str, str]:
    """
    Given a filename, return the prefix and suffix boilerplate text
    for generating that file.
    """
    output_filename = os.path.basename(output_filename)

    trace("filenameToBoilerplate", "outputFilename = %s", output_filename)

    component = output_filename
    # Extract ext (group 2) before stripping; use (\..*)? to capture compound
    # extensions like .xt.cpp (matching the Perl original)
    m = re.search(r"(_cpp03)?(\..*)?\Z", component)
    ext = m.group(2) if m and m.group(2) else ""
    component = re.sub(r"(_cpp03)?(\..*)?\Z", "", component, count=1)
    component = re.sub(r"[^A-Za-z0-9_]", "_", component)

    OUT = output_filename.upper()
    OUT = re.sub(r"[^A-Za-z0-9_]", "_", OUT)

    CPP11_SOURCEFILE = component.upper() + ext.upper()
    CPP11_SOURCEFILE = re.sub(r"[^A-Za-z0-9_]", "_", CPP11_SOURCEFILE)

    subs = {
        "in": component + ext,
        "out": output_filename,
        "OUT": OUT,
        "ext": ext,
        "cpp03": component + "_cpp03" + ext,
        "CPP11_SOURCEFILE": CPP11_SOURCEFILE,
        "component": component,
        "COMPONENT": component.upper(),
        "commandLine": command_line,
        "timestampComment": timestamp_comment,
        "bottomCopyright": bottom_copyright,
        "topCopyright": top_copyright,
    }

    # Determine which boilerplate to use based on filename pattern
    # Check each pattern and trace the check (matching Perl behavior)
    patterns = [
        (r"_cpp03\.xt\.cpp$", get_cpp03_test_driver_prefix, get_cpp03_test_driver_suffix),
        (r"_cpp03\.[0-9]+\.t\.cpp$", get_cpp03_test_driver_prefix, get_cpp03_test_driver_suffix),
        (r"_cpp03\.t\.cpp$", get_cpp03_test_driver_prefix, get_cpp03_test_driver_suffix),
        (r"_cpp03\.cpp$", get_cpp03_cpp_code_prefix, get_cpp03_cpp_code_suffix),
        (r"_cpp03\.h$", get_cpp03_header_prefix, get_cpp03_header_suffix),
        (r"_cpp03$", get_cpp03_header_prefix, get_cpp03_header_suffix),
        (r"", get_master_prefix, get_master_suffix),  # Default case (matches everything)
    ]

    for pattern, prefix_fn, suffix_fn in patterns:
        trace("filenameToBoilerplate", "ext = (?^:%s), filename = %s", pattern, output_filename)
        if pattern == "" or re.search(pattern, output_filename):
            return (prefix_fn(subs), suffix_fn(subs))

    # Should never reach here, but satisfy type checker
    return (get_master_prefix(subs), get_master_suffix(subs))


# ============================================================================
#                           FILE OPERATIONS
# ============================================================================


def segment_filedata(file_data: str) -> Tuple[str, str, str, bool]:
    """
    Split the file_data string into three segments:
      Prologue: Segment of code before the beginning of simulation directive
      Unexpanded Code: Segment of code containing C++11 code to be expanded
      Epilogue: Segment of code after any simulation directive

    Returns a tuple (prologue, unexpanded_code, epilogue, includes_bsl_compilerfeatures).
    """
    includes_bsl_compilerfeatures = False

    push_input(file_data)
    markers = find_cpp03_region_markers()

    if markers:
        if_start, include_start, else_end, endif_start, endif_end = markers
        includes_bsl_compilerfeatures = True
    else:
        # Find the end of the last #include directive
        last_include = 0
        while cpp_search(r'^[ \t]*\#[ \t]*include[ \t]*[<"](.*)[">].*$', last_include):
            if cpp_match[1] == "bsls_compilerfeatures.h":
                includes_bsl_compilerfeatures = True

            last_include = cpp_match_end[0] + 1

            # Special case: bsls_ident.h
            if cpp_match[1] == "bsls_ident.h":
                if cpp_search(r"^[ \t]*BSLS_IDENT(.*).*$", last_include):
                    last_include = cpp_match_end[0] + 1

        if_start = else_end = last_include
        endif_start = endif_end = input_end

        # Find first non-whitespace, non-comment character after #include
        first_real_code = input_end
        if cpp_search(r"\S", last_include):
            first_real_code = cpp_match_start[0]

        # Find the #endif (if any) enclosing the last #include
        if cpp_find_matching_pp_directive(last_include, "endif"):
            if cpp_match_start[0] > first_real_code:
                endif_start = endif_end = cpp_match_start[0]
            else:
                # Move insertion point to after #endif
                if_start = else_end = cpp_match_end[0]

                # Search again for the #endif we actually care about
                if cpp_find_matching_pp_directive(else_end, "endif"):
                    endif_start = endif_end = cpp_match_start[0]

        if endif_start == input_end:
            # Move insertion position to be before closing comments/whitespace
            # Use \Z (end-of-string) instead of $ because cpp_search uses
            # re.MULTILINE where $ matches at any line boundary.
            start_search = max(0, input_end - 1000)
            if cpp_search(r"\n\s*\Z", start_search):
                endif_start = endif_end = cpp_match_start[0] + 1

    pop_input()

    trace(
        "segmentFiledata",
        "ifStart = %d, elseEnd = %d, endifStart = %d",
        if_start,
        else_end,
        endif_start,
    )

    prologue = file_data[:if_start]
    unexpanded_code = file_data[else_end:endif_start]
    epilogue = file_data[endif_end:]

    if unexpanded_code:
        # Adjust newlines around the segments
        # Use count=1 to avoid double matching in Python 3.12+
        prologue = re.sub(r"\n*$", "\n\n", prologue, count=1)
        unexpanded_code = re.sub(r"^\n*", "", unexpanded_code, count=1)
        unexpanded_code = re.sub(r"\n*$", "\n", unexpanded_code, count=1)
        epilogue = re.sub(r"^\n*", "\n", epilogue, count=1)

    # Remove newlines from otherwise-empty prologue or epilogue
    if prologue == "\n\n":
        prologue = ""
    if epilogue == "\n":
        epilogue = ""

    trace(
        "segmentFiledata",
        "prologue size = %d, code size = %d, epilog size = %d",
        len(prologue),
        len(unexpanded_code),
        len(epilogue),
    )

    return (prologue, unexpanded_code, epilogue, includes_bsl_compilerfeatures)


def write_output(output: str, output_filename: str, permissions: int = 0o666) -> None:
    """Create a backup of the output_filename and write output to it."""
    trace("writeOutput", "Writing %d to %s", len(output), output_filename)

    if verify_no_change:
        fatal(f"--verify-no-change error: Would modify {output_filename}")

    if output_filename == "-":
        print(output, end="")
    else:
        # Save a backup of the output file
        if os.path.exists(output_filename):
            backup = output_filename + ".bak"
            if os.path.exists(backup):
                os.remove(backup)
            os.rename(output_filename, backup)

        # Write the file
        with open(output_filename, "w") as f:
            f.write(output)

        # Set permissions
        os.chmod(output_filename, permissions)


def _normalize_for_compare(text: str) -> str:
    """Normalize text for comparison by replacing volatile metadata.

    Replaces timestamps and the old Perl script name so that files generated
    by the former ``sim_cpp11_features.pl`` are considered equivalent to the
    output of the current ``sim_cpp11_features.py``.
    """
    text = re.sub(
        rf"{re.escape(timestamp_prefix)}.*$",
        timestamp_comment,
        text,
        flags=re.MULTILINE,
    )
    text = text.replace("sim_cpp11_features.pl", "sim_cpp11_features.py")
    return text


def write_master(
    input_filename: str, output_filename: str, original_file_data: str, output: str
) -> None:
    """Write the master output file."""
    trace("writeMaster", "outputName = %s, outputLen = %d", output_filename, len(output))

    if (
        _normalize_for_compare(output) != _normalize_for_compare(original_file_data)
        or (not self_test and output_filename != input_filename)
        or output_filename == "-"
    ):
        write_output(output, output_filename)

        if self_test:
            # Dump a copy of the test data to a file
            with open("TEST", "w") as f:
                f.write(original_file_data)

            # Dump test diff
            os.system(f"diff -c TEST {output_filename}")
    else:
        trace("writeMaster", "Master is unchanged. No file written.")


def write_expansion(output_filename: str, output: str) -> None:
    """Write the expansion output file."""
    trace("writeExpansion", "outputName = %s, outputLen = %d", output_filename, len(output))

    if os.path.exists(output_filename):
        with open(output_filename, "r") as f:
            original_file_data = f.read()

        # Normalize volatile metadata so that trivial differences
        # (timestamp, .pl -> .py rename, copyright year) don't trigger
        # a rewrite.
        original_file_data = _normalize_for_compare(original_file_data)
        normalized_output = _normalize_for_compare(output)

        # Replace old copyright with new
        match = re.search(r"^// Copyright \d+(?:-\d+)?", normalized_output, re.MULTILINE)
        if match:
            new_copyright = match.group(0)
            original_file_data = re.sub(
                r"^// Copyright \d+",
                new_copyright,
                original_file_data,
                count=1,
                flags=re.MULTILINE,
            )

        # Don't modify output file if it's identical to previous version
        if normalized_output == original_file_data:
            trace("writeExpansion", "Generated file is unchanged. No file written.")
            return
        else:
            trace("writeExpansion", "Generated file is changed. File written.")

    # Create read-only file with generated output
    write_output(output, output_filename, 0o444)


def process_file(input_filename: str, output_filename: str) -> int:
    """Process the specified input filename to the specified output filename."""
    global file_max_args, max_args, variadic_limit_base
    global class_template_forward_declared, next_gen_param

    trace("processFile", "Inputfile = %s, Outputfile = %s", input_filename, output_filename)

    # Reset important globals

    file_max_args = default_max_args
    max_args = max_args_opt or file_max_args
    class_template_forward_declared = {}
    next_gen_param = 0

    variadic_limit_base = os.path.basename(input_filename)
    variadic_limit_base = re.sub(r"\..*", "", variadic_limit_base)
    variadic_limit_base = variadic_limit_base.upper() + "_VARIADIC_LIMIT"

    if self_test:
        # Read from embedded test data
        file_data = get_test_data()
    else:
        with open(input_filename, "rb") as f:
            file_data = f.read().decode("utf-8")

    file_data = file_data.replace("\r", "")  # Normalize newlines

    # Replace old timestamp with new timestamp
    file_data = re.sub(rf"{timestamp_prefix}.*$", timestamp_comment, file_data, flags=re.MULTILINE)

    # Check for copyright block
    global bottom_copyright, top_copyright
    bottom_copyright = ""
    top_copyright = ""

    bottom_match = re.search(
        r"""(\n?
             //[ ]--+\n
             //[ ]Copyright[ ]\d+[ ]Bloomberg.*\n
             (?://[ ].*\n|//\n)+
             //[ ]-+[ ]END-OF-FILE[ ]-+)\n*$""",
        file_data,
        re.VERBOSE,
    )
    top_match = re.search(
        r"""^\n*
             (
             //[ ]Copyright[ ](?:\d+|\d+-\d+)[ ]Bloomberg.*\n
             //[ ]SPDX-License-Identifier:[ ]Apache-2.0.*\n
             (?://[ ].*\n|//\n)+
             \n?
             )""",
        file_data,
        re.VERBOSE,
    )

    if bottom_match:
        bottom_copyright = bottom_match.group(1)
        debug_print(f"Copyright (bottom of file) is now\n{bottom_copyright}")
    elif top_match:
        top_copyright = top_match.group(1)
        debug_print(f"Copyright (top of file) is now\n{top_copyright}")
    else:
        fatal("No recognizable copyright block")

    # Find the cut points of the file
    prologue, unexpanded_code, epilogue, includes_bsl_compilerfeatures = segment_filedata(
        file_data
    )

    # Generate the main file
    output = transform_file(unexpanded_code, True)

    if not output:
        # There were no expansions in the code
        write_master(
            input_filename, output_filename, file_data, prologue + unexpanded_code + epilogue
        )
    elif inplace:
        write_master(input_filename, output_filename, file_data, prologue + output + epilogue)
    else:
        # Write main file with boilerplate
        boiler_beg, boiler_end = filename_to_boilerplate(output_filename)

        if not includes_bsl_compilerfeatures:
            prologue += "#include <bsls_compilerfeatures.h>\n\n"

        write_master(
            input_filename,
            output_filename,
            file_data,
            prologue + boiler_beg + output + boiler_end + epilogue,
        )

    if not inplace:
        # Generate expansion output file
        output_filename = re.sub(r"([^.])(\.[^/\\]*)?$", r"\1_cpp03\2", output_filename)

        if output:
            output = transform_file(output, False)
        else:
            output = "// No C++03 Expansion\n"

        boiler_beg, boiler_end = filename_to_boilerplate(output_filename)
        write_expansion(output_filename, boiler_beg + output + boiler_end)

    return 0


# ============================================================================
#                           TEST DATA
# ============================================================================


def get_test_data() -> str:
    """Return the built-in test data."""
    return """// TEST                                                               -*-C++-*-

#include <foo.h>

#ifndef INCLUDED_BSLS_COMPILERFEATURES
#   include <bsls_compilerfeatures.h>
#endif

// Sample input
void f(); // Not a template

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3
#  ifdef NESTED
template <int ...B, class... A>
void foo(C<B...> *c, A&&... a)
    // This function does the foolish thing.  It is a variadic function and is
    // fully documented.  The specified 'c' parameter is a single argument
    // that uses a parameter pack in a deduced context.  The specified 'a' is
    // a variadic argument.
{
    D<A...> d(bsl::forward<A>(a)...);
    bar(sizeof... (A), c, &d);

    # Identical expansion twice in one line:
    f(bsl::forward<A>(a)...); g(bsl::forward<A>(a)...);
}
#  endif // NESTED

template <class T>
int bar(int a, T&& v)
    // Non-variadic function template that uses perfect forwarding.
{
    xyz(a, bsl::forward<T>(v));
}

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Command line: sim_cpp11_features.pl --inplace --test
#ifndef TEST_VARIADIC_LIMIT
#define TEST_VARIADIC_LIMIT 3
#endif
#ifndef TEST_VARIADIC_LIMIT_A
#define TEST_VARIADIC_LIMIT_A TEST_VARIADIC_LIMIT
#endif
#  ifdef NESTED
#if TEST_VARIADIC_LIMIT_A >= 0
void foo(C<> *c)
{
    D<> d();
    bar(0u, c, &d);

    # Identical expansion twice in one line:
    f(); g(
                                              );
}
#endif  // TEST_VARIADIC_LIMIT_A >= 0

#if TEST_VARIADIC_LIMIT_A >= 1
template <int B_1, class A_1>
void foo(C<B_1> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A_1) a_1)
{
    D<A_1> d(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1));
    bar(1u, c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1)); g(
                                             BSLS_COMPILERFEATURES_FORWARD(A_1,
                                             a_1));
}
#endif  // TEST_VARIADIC_LIMIT_A >= 1

#if TEST_VARIADIC_LIMIT_A >= 2
template <int B_1,
          int B_2, class A_1,
                   class A_2>
void foo(C<B_1,
           B_2> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A_1) a_1,
                    BSLS_COMPILERFEATURES_FORWARD_REF(A_2) a_2)
{
    D<A_1,
      A_2> d(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
             BSLS_COMPILERFEATURES_FORWARD(A_2, a_2));
    bar(2u, c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
      BSLS_COMPILERFEATURES_FORWARD(A_2, a_2)); g(
                                             BSLS_COMPILERFEATURES_FORWARD(A_1,
                                             a_1),
                                             BSLS_COMPILERFEATURES_FORWARD(A_2,
                                             a_2));
}
#endif  // TEST_VARIADIC_LIMIT_A >= 2

#if TEST_VARIADIC_LIMIT_A >= 3
template <int B_1,
          int B_2,
          int B_3, class A_1,
                   class A_2,
                   class A_3>
void foo(C<B_1,
           B_2,
           B_3> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A_1) a_1,
                    BSLS_COMPILERFEATURES_FORWARD_REF(A_2) a_2,
                    BSLS_COMPILERFEATURES_FORWARD_REF(A_3) a_3)
{
    D<A_1,
      A_2,
      A_3> d(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
             BSLS_COMPILERFEATURES_FORWARD(A_2, a_2),
             BSLS_COMPILERFEATURES_FORWARD(A_3, a_3));
    bar(3u, c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
      BSLS_COMPILERFEATURES_FORWARD(A_2, a_2),
      BSLS_COMPILERFEATURES_FORWARD(A_3, a_3)); g(
                                             BSLS_COMPILERFEATURES_FORWARD(A_1,
                                             a_1),
                                             BSLS_COMPILERFEATURES_FORWARD(A_2,
                                             a_2),
                                             BSLS_COMPILERFEATURES_FORWARD(A_3,
                                             a_3));
}
#endif  // TEST_VARIADIC_LIMIT_A >= 3

#  endif

template <class T>
int bar(int a, BSLS_COMPILERFEATURES_FORWARD_REF(T) v)
{
    xyz(a, BSLS_COMPILERFEATURES_FORWARD(T, v));
}
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
#  ifdef NESTED
template <int ...B, class... A>
void foo(C<B...> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A)... a)
{
    D<A...> d(BSLS_COMPILERFEATURES_FORWARD(A, a)...);
    bar(sizeof... (A), c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A, a)...); g(
                                              BSLS_COMPILERFEATURES_FORWARD(A,
                                              a)...);
}
#  endif

template <class T>
int bar(int a, BSLS_COMPILERFEATURES_FORWARD_REF(T) v)
{
    xyz(a, BSLS_COMPILERFEATURES_FORWARD(T, v));
}

// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
// The following is a variadic template function
template <typename... A>  // Comments are removed
    void g(const vector<A>&... a)
    {
        if (q()) {
            xyz(forward<A, int>(a)...
                );
        }
    }

template <int X, class ...T>
class C
{
public:
    typename mf<X>::type member(const T&... z);

    template <class U> void member2(U&& v);
};

template <int X, class ...T>
typename mf<X>::type C<X, T...>::member(const T&... z)
{
}

template <int X, class ...T>
    template <class U>
void C<X, T...>::member2(U&& v)
{
    q(std::forward< U >( v ));
}

template <int X, unsigned ...V>
struct D
{
    typename mf<X>::type member();
};

template <int X, unsigned ...V>
typename mf<X>::type D<V...>::member()
{
}

template <class ...T>
    X::X(const T&... args) : v(args)... { }

template <typename T>
    void z(const vector<T>& v);  // No variadics

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Command line: sim_cpp11_features.pl --inplace --test
#ifndef TEST_VARIADIC_LIMIT
#define TEST_VARIADIC_LIMIT 3
#endif
#ifndef TEST_VARIADIC_LIMIT_B
#define TEST_VARIADIC_LIMIT_B TEST_VARIADIC_LIMIT
#endif
#if TEST_VARIADIC_LIMIT_B >= 0
void g()
    {
        if (q()) {
            xyz(
                );
        }
    }
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <typename A_1>
    void g(const vector<A_1>& a_1)
    {
        if (q()) {
            xyz(forward<A_1, int>(a_1)
                );
        }
    }
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <typename A_1,
          typename A_2>
    void g(const vector<A_1>& a_1,
           const vector<A_2>& a_2)
    {
        if (q()) {
            xyz(forward<A_1, int>(a_1),
                forward<A_2, int>(a_2)
                );
        }
    }
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <typename A_1,
          typename A_2,
          typename A_3>
    void g(const vector<A_1>& a_1,
           const vector<A_2>& a_2,
           const vector<A_3>& a_3)
    {
        if (q()) {
            xyz(forward<A_1, int>(a_1),
                forward<A_2, int>(a_2),
                forward<A_3, int>(a_3)
                );
        }
    }
#endif  // TEST_VARIADIC_LIMIT_B >= 3


template <int X
#if TEST_VARIADIC_LIMIT_B >= 0
        , class T_0 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
        , class T_1 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
        , class T_2 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_B >= 2
        , class = BSLS_COMPILERFEATURES_NILT>
class C;

#if TEST_VARIADIC_LIMIT_B >= 0
template <int X>
class C<X>
{
public:
    typename mf<X>::type member();

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <int X, class T_1>
class C<X, T_1>
{
public:
    typename mf<X>::type member(const T_1& z_1);

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <int X, class T_1,
                 class T_2>
class C<X, T_1,
           T_2>
{
public:
    typename mf<X>::type member(const T_1& z_1,
                                const T_2& z_2);

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <int X, class T_1,
                 class T_2,
                 class T_3>
class C<X, T_1,
           T_2,
           T_3>
{
public:
    typename mf<X>::type member(const T_1& z_1,
                                const T_2& z_2,
                                const T_3& z_3);

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};
#endif  // TEST_VARIADIC_LIMIT_B >= 3


#if TEST_VARIADIC_LIMIT_B >= 0
template <int X>
typename mf<X>::type C<X, BSLS_COMPILERFEATURES_FILLT(3)>::member()
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <int X, class T_1>
typename mf<X>::type C<X, T_1,
                          BSLS_COMPILERFEATURES_FILLT(2)>::member(
                                                                const T_1& z_1)
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <int X, class T_1,
                 class T_2>
typename mf<X>::type C<X, T_1,
                          T_2,
                          BSLS_COMPILERFEATURES_FILLT(1)>::member(
                                                                const T_1& z_1,
                                                                const T_2& z_2)
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <int X, class T_1,
                 class T_2,
                 class T_3>
typename mf<X>::type C<X, T_1,
                          T_2,
                          T_3,
                          BSLS_COMPILERFEATURES_FILLT(0)>::member(
                                                                const T_1& z_1,
                                                                const T_2& z_2,
                                                                const T_3& z_3)
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 3


#if TEST_VARIADIC_LIMIT_B >= 0
template <int X>
    template <class U>
void C<X, BSLS_COMPILERFEATURES_FILLT(3)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <int X, class T_1>
    template <class U>
void C<X, T_1,
          BSLS_COMPILERFEATURES_FILLT(2)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <int X, class T_1,
                 class T_2>
    template <class U>
void C<X, T_1,
          T_2,
          BSLS_COMPILERFEATURES_FILLT(1)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <int X, class T_1,
                 class T_2,
                 class T_3>
    template <class U>
void C<X, T_1,
          T_2,
          T_3,
          BSLS_COMPILERFEATURES_FILLT(0)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}
#endif  // TEST_VARIADIC_LIMIT_B >= 3


template <int X
#if TEST_VARIADIC_LIMIT_B >= 0
        , unsigned V_0 = BSLS_COMPILERFEATURES_NILV
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
        , unsigned V_1 = BSLS_COMPILERFEATURES_NILV
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
        , unsigned V_2 = BSLS_COMPILERFEATURES_NILV
#endif  // TEST_VARIADIC_LIMIT_B >= 2
        , unsigned = BSLS_COMPILERFEATURES_NILV>
struct D;

#if TEST_VARIADIC_LIMIT_B >= 0
template <int X>
struct D<X>
{
    typename mf<X>::type member();
};
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <int X, unsigned V_1>
struct D<X, V_1>
{
    typename mf<X>::type member();
};
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <int X, unsigned V_1,
                 unsigned V_2>
struct D<X, V_1,
            V_2>
{
    typename mf<X>::type member();
};
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <int X, unsigned V_1,
                 unsigned V_2,
                 unsigned V_3>
struct D<X, V_1,
            V_2,
            V_3>
{
    typename mf<X>::type member();
};
#endif  // TEST_VARIADIC_LIMIT_B >= 3


#if TEST_VARIADIC_LIMIT_B >= 0
template <int X>
typename mf<X>::type D<BSLS_COMPILERFEATURES_FILLV(3)>::member()
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <int X, unsigned V_1>
typename mf<X>::type D<V_1,
                       BSLS_COMPILERFEATURES_FILLV(2)>::member()
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <int X, unsigned V_1,
                 unsigned V_2>
typename mf<X>::type D<V_1,
                       V_2,
                       BSLS_COMPILERFEATURES_FILLV(1)>::member()
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <int X, unsigned V_1,
                 unsigned V_2,
                 unsigned V_3>
typename mf<X>::type D<V_1,
                       V_2,
                       V_3,
                       BSLS_COMPILERFEATURES_FILLV(0)>::member()
{
}
#endif  // TEST_VARIADIC_LIMIT_B >= 3


#if TEST_VARIADIC_LIMIT_B >= 0
X::X() { }
#endif  // TEST_VARIADIC_LIMIT_B >= 0

#if TEST_VARIADIC_LIMIT_B >= 1
template <class T_1>
    X::X(const T_1& args_1) : v(args_1) { }
#endif  // TEST_VARIADIC_LIMIT_B >= 1

#if TEST_VARIADIC_LIMIT_B >= 2
template <class T_1,
          class T_2>
    X::X(const T_1& args_1,
         const T_2& args_2) : v(args_1),
                              v(args_2) { }
#endif  // TEST_VARIADIC_LIMIT_B >= 2

#if TEST_VARIADIC_LIMIT_B >= 3
template <class T_1,
          class T_2,
          class T_3>
    X::X(const T_1& args_1,
         const T_2& args_2,
         const T_3& args_3) : v(args_1),
                              v(args_2),
                              v(args_3) { }
#endif  // TEST_VARIADIC_LIMIT_B >= 3


template <typename T>
    void z(const vector<T>& v);
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <typename... A>
    void g(const vector<A>&... a)
    {
        if (q()) {
            xyz(forward<A, int>(a)...
                );
        }
    }

template <int X, class ...T>
class C
{
public:
    typename mf<X>::type member(const T&... z);

    template <class U> void member2(U&& v);
};

template <int X, class ...T>
typename mf<X>::type C<X, T...>::member(const T&... z)
{
}

template <int X, class ...T>
    template <class U>
void C<X, T...>::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}

template <int X, unsigned ...V>
struct D
{
    typename mf<X>::type member();
};

template <int X, unsigned ...V>
typename mf<X>::type D<V...>::member()
{
}

template <class ...T>
    X::X(const T&... args) : v(args)... { }

template <typename T>
    void z(const vector<T>& v);

// }}} END GENERATED CODE
#endif

template <class T>
class NonVaridadicClassWithVariadicMember
{
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $local-var-args=4
    template <class... U>
        NonVaridadicClassWithVariadicMember(const U&... u);

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Command line: sim_cpp11_features.pl --inplace --test
#ifndef TEST_VARIADIC_LIMIT
#define TEST_VARIADIC_LIMIT 3
#endif
#ifndef TEST_VARIADIC_LIMIT_C
#define TEST_VARIADIC_LIMIT_C TEST_VARIADIC_LIMIT
#endif
#if TEST_VARIADIC_LIMIT_C >= 0
    NonVaridadicClassWithVariadicMember();
#endif  // TEST_VARIADIC_LIMIT_C >= 0

#if TEST_VARIADIC_LIMIT_C >= 1
    template <class U_1>
        NonVaridadicClassWithVariadicMember(const U_1& u_1);
#endif  // TEST_VARIADIC_LIMIT_C >= 1

#if TEST_VARIADIC_LIMIT_C >= 2
    template <class U_1,
              class U_2>
        NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                            const U_2& u_2);
#endif  // TEST_VARIADIC_LIMIT_C >= 2

#if TEST_VARIADIC_LIMIT_C >= 3
    template <class U_1,
              class U_2,
              class U_3>
        NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                            const U_2& u_2,
                                            const U_3& u_3);
#endif  // TEST_VARIADIC_LIMIT_C >= 3

#if TEST_VARIADIC_LIMIT_C >= 4
    template <class U_1,
              class U_2,
              class U_3,
              class U_4>
        NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                            const U_2& u_2,
                                            const U_3& u_3,
                                            const U_4& u_4);
#endif  // TEST_VARIADIC_LIMIT_C >= 4

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
    template <class... U>
        NonVaridadicClassWithVariadicMember(const U&... u);

// }}} END GENERATED CODE
#endif
};

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
template <class T>
    template <class... U>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U&... u);

template <class... TYPE>
void Cls<TYPE...>::functionWithLongExpansion79Columns(TYPE&&... a, double b);

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Command line: sim_cpp11_features.pl --inplace --test
#ifndef TEST_VARIADIC_LIMIT
#define TEST_VARIADIC_LIMIT 3
#endif
#ifndef TEST_VARIADIC_LIMIT_D
#define TEST_VARIADIC_LIMIT_D TEST_VARIADIC_LIMIT
#endif
#if TEST_VARIADIC_LIMIT_D >= 0
template <class T>
    NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember();
#endif  // TEST_VARIADIC_LIMIT_D >= 0

#if TEST_VARIADIC_LIMIT_D >= 1
template <class T>
    template <class U_1>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U_1& u_1);
#endif  // TEST_VARIADIC_LIMIT_D >= 1

#if TEST_VARIADIC_LIMIT_D >= 2
template <class T>
    template <class U_1,
              class U_2>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                        const U_2& u_2);
#endif  // TEST_VARIADIC_LIMIT_D >= 2

#if TEST_VARIADIC_LIMIT_D >= 3
template <class T>
    template <class U_1,
              class U_2,
              class U_3>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                        const U_2& u_2,
                                        const U_3& u_3);
#endif  // TEST_VARIADIC_LIMIT_D >= 3


#if TEST_VARIADIC_LIMIT_D >= 0
void Cls<BSLS_COMPILERFEATURES_FILLT(3)>::functionWithLongExpansion79Columns(
                                  double b);
#endif  // TEST_VARIADIC_LIMIT_D >= 0

#if TEST_VARIADIC_LIMIT_D >= 1
template <class TYPE_1>
void Cls<TYPE_1,
         BSLS_COMPILERFEATURES_FILLT(2)>::functionWithLongExpansion79Columns(
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_1) a_1,
                                  double b);
#endif  // TEST_VARIADIC_LIMIT_D >= 1

#if TEST_VARIADIC_LIMIT_D >= 2
template <class TYPE_1,
          class TYPE_2>
void Cls<TYPE_1,
         TYPE_2,
         BSLS_COMPILERFEATURES_FILLT(1)>::functionWithLongExpansion79Columns(
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_1) a_1,
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_2) a_2,
                                  double b);
#endif  // TEST_VARIADIC_LIMIT_D >= 2

#if TEST_VARIADIC_LIMIT_D >= 3
template <class TYPE_1,
          class TYPE_2,
          class TYPE_3>
void Cls<TYPE_1,
         TYPE_2,
         TYPE_3,
         BSLS_COMPILERFEATURES_FILLT(0)>::functionWithLongExpansion79Columns(
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_1) a_1,
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_2) a_2,
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_3) a_3,
                                  double b);
#endif  // TEST_VARIADIC_LIMIT_D >= 3

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <class T>
    template <class... U>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U&... u);

template <class... TYPE>
void Cls<TYPE...>::functionWithLongExpansion79Columns(
                                  BSLS_COMPILERFEATURES_FORWARD_REF(TYPE)... a,
                                  double b);

// }}} END GENERATED CODE
#endif

void h();

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class... CTOR_ARGS>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                                            CTOR_ARG&&       ctorArg,
                                            CTOR_ARGS&&...   ctorArgs)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        std::forward<CTOR_ARG>(ctorArg),
        std::forward<CTOR_ARGS>(ctorArgs)...,
        mechanism(allocator, IsBslma()));
}
#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Command line: sim_cpp11_features.pl --inplace --test
#ifndef TEST_VARIADIC_LIMIT
#define TEST_VARIADIC_LIMIT 3
#endif
#ifndef TEST_VARIADIC_LIMIT_E
#define TEST_VARIADIC_LIMIT_E TEST_VARIADIC_LIMIT
#endif
#if TEST_VARIADIC_LIMIT_E >= 0
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        mechanism(allocator, IsBslma()));
}
#endif  // TEST_VARIADIC_LIMIT_E >= 0

#if TEST_VARIADIC_LIMIT_E >= 1
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class CTOR_ARGS_1>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_1) ctorArgs_1)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_1, ctorArgs_1),
        mechanism(allocator, IsBslma()));
}
#endif  // TEST_VARIADIC_LIMIT_E >= 1

#if TEST_VARIADIC_LIMIT_E >= 2
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class CTOR_ARGS_1,
                                              class CTOR_ARGS_2>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_1) ctorArgs_1,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_2) ctorArgs_2)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_1, ctorArgs_1),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_2, ctorArgs_2),
        mechanism(allocator, IsBslma()));
}
#endif  // TEST_VARIADIC_LIMIT_E >= 2

#if TEST_VARIADIC_LIMIT_E >= 3
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class CTOR_ARGS_1,
                                              class CTOR_ARGS_2,
                                              class CTOR_ARGS_3>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_1) ctorArgs_1,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_2) ctorArgs_2,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_3) ctorArgs_3)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_1, ctorArgs_1),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_2, ctorArgs_2),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_3, ctorArgs_3),
        mechanism(allocator, IsBslma()));
}
#endif  // TEST_VARIADIC_LIMIT_E >= 3

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class... CTOR_ARGS>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                      BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS)... ctorArgs)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS, ctorArgs)...,
        mechanism(allocator, IsBslma()));
}
// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
// Function with perfect forwarding but no variadics
template <typename A>
void forwardingFunction(A&& x);
#else
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <typename A>
void forwardingFunction(BSLS_COMPILERFEATURES_FORWARD_REF(A) x);
// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
// Non-template function
void nonTemplateFunction(int x);

// Template function with neither forwarding nor variadics.
template <typename X>
void normalTemplate(const X& v);
#else
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
void nonTemplateFunction(int x);

template <typename X>
void normalTemplate(const X& v);
// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
template <class T,
          class U,
          class... X>
class P
{
};

template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T,
          class... X>
class Q
{
};
#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Command line: sim_cpp11_features.pl --inplace --test
#ifndef TEST_VARIADIC_LIMIT
#define TEST_VARIADIC_LIMIT 3
#endif
#ifndef TEST_VARIADIC_LIMIT_H
#define TEST_VARIADIC_LIMIT_H TEST_VARIADIC_LIMIT
#endif
template <class T,
          class U
#if TEST_VARIADIC_LIMIT_H >= 0
        , class X_0 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_H >= 0

#if TEST_VARIADIC_LIMIT_H >= 1
        , class X_1 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_H >= 1

#if TEST_VARIADIC_LIMIT_H >= 2
        , class X_2 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_H >= 2
        , class = BSLS_COMPILERFEATURES_NILT>
class P;

#if TEST_VARIADIC_LIMIT_H >= 0
template <class T, class U>
class P<T, U>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 0

#if TEST_VARIADIC_LIMIT_H >= 1
template <class T, class U, class X_1>
class P<T, U, X_1>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 1

#if TEST_VARIADIC_LIMIT_H >= 2
template <class T, class U, class X_1,
                            class X_2>
class P<T, U, X_1,
              X_2>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 2

#if TEST_VARIADIC_LIMIT_H >= 3
template <class T, class U, class X_1,
                            class X_2,
                            class X_3>
class P<T, U, X_1,
              X_2,
              X_3>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 3


template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T
#if TEST_VARIADIC_LIMIT_H >= 0
        , class X_0 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_H >= 0

#if TEST_VARIADIC_LIMIT_H >= 1
        , class X_1 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_H >= 1

#if TEST_VARIADIC_LIMIT_H >= 2
        , class X_2 = BSLS_COMPILERFEATURES_NILT
#endif  // TEST_VARIADIC_LIMIT_H >= 2
        , class = BSLS_COMPILERFEATURES_NILT>
class Q;

#if TEST_VARIADIC_LIMIT_H >= 0
template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T>
class Q<A_very_long_template_parameter_name_that_will_force_wrapping, T>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 0

#if TEST_VARIADIC_LIMIT_H >= 1
template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T, class X_1>
class Q<A_very_long_template_parameter_name_that_will_force_wrapping, T, X_1>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 1

#if TEST_VARIADIC_LIMIT_H >= 2
template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T, class X_1,
                   class X_2>
class Q<A_very_long_template_parameter_name_that_will_force_wrapping, T, X_1,
                                                                         X_2>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 2

#if TEST_VARIADIC_LIMIT_H >= 3
template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T, class X_1,
                   class X_2,
                   class X_3>
class Q<A_very_long_template_parameter_name_that_will_force_wrapping, T, X_1,
                                                                         X_2,
                                                                         X_3>
{
};
#endif  // TEST_VARIADIC_LIMIT_H >= 3

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <class T,
          class U,
          class... X>
class P
{
};

template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T,
          class... X>
class Q
{
};
// }}} END GENERATED CODE
#endif
"""


# ============================================================================
#                           MAIN PROGRAM
# ============================================================================


def get_command_line(filename: str) -> str:
    """Return the minimal command-line options and current filename."""
    ret = os.path.basename(sys.argv[0])

    if inplace:
        ret += " --inplace"
    if clean:
        ret += " --clean"
    if self_test:
        ret += " --test"

    if filename:
        ret += " " + os.path.basename(filename)

    return ret


def main() -> int:
    """Main program entry point."""
    global debug_level, trace_ctrls, clean, inplace, verify_no_change
    global self_test, max_args_opt, command_line, timestamp_comment

    parser = argparse.ArgumentParser(
        description="Convert C++11 code with variadic templates to C++03 equivalent"
    )
    parser.add_argument("--output", "-o", dest="output_option", help="Output filename")
    parser.add_argument("--debug", "-d", type=int, default=0, help="Debug level")
    parser.add_argument("--trace", action="append", default=[], help="Trace labels (label:level)")
    parser.add_argument("--inplace", action="store_true", help="Generate inplace output")
    parser.add_argument(
        "--no-inplace", action="store_true", help="Generate separate output files (default)"
    )
    parser.add_argument(
        "--verify-no-change", action="store_true", help="Verify that nothing has changed"
    )
    parser.add_argument("--clean", action="store_true", help="Remove all C++03 emulation code")
    parser.add_argument("--test", action="store_true", help="Run the tool on built-in test file")
    parser.add_argument(
        "--var-args", type=int, default=0, help="Maximum number of variadic template expansions"
    )
    parser.add_argument("files", nargs="*", help="Input files")

    args = parser.parse_args()

    debug_level = args.debug
    inplace = args.inplace and not args.no_inplace
    verify_no_change = args.verify_no_change
    clean = args.clean
    self_test = args.test
    max_args_opt = args.var_args

    # Process trace labels
    for trace_spec in args.trace:
        for label_spec in trace_spec.split(","):
            parts = label_spec.split(":")
            label = parts[0]
            level = int(parts[1]) if len(parts) > 1 else 1
            trace_ctrls[label] = level

    timestamp = datetime.now().strftime("%a %b %d %H:%M:%S %Y")
    timestamp_comment = timestamp_prefix + timestamp

    # Check for conflicting arguments
    if clean and not inplace:
        print("Option --clean requires --inplace", file=sys.stderr)
        sys.exit(1)

    if self_test and args.files:
        print("Cannot specify filename with --test", file=sys.stderr)
        sys.exit(1)

    if not self_test and not args.files:
        print("Must specify an input file name or -", file=sys.stderr)
        sys.exit(1)

    if len(args.files) > 1 and args.output_option:
        print("Only one input file name may be specified when using --output", file=sys.stderr)
        sys.exit(1)

    if self_test:
        args.files = ["TEST"]
        if not args.output_option:
            args.output_option = "TEST_out"

    ret = 0
    for input_filename in args.files:
        command_line = get_command_line(input_filename)
        output_filename = args.output_option or input_filename

        if output_filename == "-" and not inplace:
            usage("Writing to  standard output ('-') requires option --inplace")

        ret = process_file(input_filename, output_filename)

        if ret:
            break

    return ret


if __name__ == "__main__":
    sys.exit(main())
