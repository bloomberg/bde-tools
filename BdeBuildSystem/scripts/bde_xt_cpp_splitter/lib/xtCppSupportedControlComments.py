from __future__ import annotations

import re
from typing import Set

from lib.extensionsForPy38 import removeprefix
from lib.myConstants import MY_CONTROL_COMMENT_PREFIX

SET_OF_SUPPORTED_SILENCED_WARNINGS: Set[str] = {"UNUSED"}

_CASE_NUMBER_RE_STR = r"(-?(?:[1-9])|(?:[1-9][0-9]))"
_CASE_NUMBER_RANGE_RE_STR = rf"({_CASE_NUMBER_RE_STR}\.\.{_CASE_NUMBER_RE_STR})"
_SPLIT_CASE_SLICES_RE_STR = rf"({_CASE_NUMBER_RE_STR}\.SLICES)"
_PART_DEF_RE_STR = (
    rf"({_CASE_NUMBER_RE_STR}|{_SPLIT_CASE_SLICES_RE_STR}|{_CASE_NUMBER_RANGE_RE_STR})"
)
_PART_DEF_LIST_RE_STR = rf"({_PART_DEF_RE_STR}(?:\s*,\s*{_PART_DEF_RE_STR})*)"

_CASE_NAME_RE_STR = r"([a-zA-Z][a-zA-Z0-9_]+)"
_SPLIT_CASE_SLICE_RE_STR = rf"({_CASE_NUMBER_RE_STR}\.{_CASE_NAME_RE_STR})"
_FOR_COND_RE_STR = (
    rf"({_CASE_NUMBER_RE_STR}|{_SPLIT_CASE_SLICE_RE_STR}|{_CASE_NUMBER_RANGE_RE_STR})"
)
_FOR_COND_LIST_RE_STR = rf"({_FOR_COND_RE_STR}(?:\s*,\s*{_FOR_COND_RE_STR})*)"

_SUPPORTED_SILENCED_WARNINGS_RE_STR = "(?:" + "|".join(SET_OF_SUPPORTED_SILENCED_WARNINGS) + ")"
_SUPPORTED_SILENCED_WARNINGS_LIST_RE_STR = (
    rf"{_SUPPORTED_SILENCED_WARNINGS_RE_STR}(?:\s*,\s*{_SUPPORTED_SILENCED_WARNINGS_RE_STR})*"
)

_SUPPORTED_CONTROL_COMMENTS_RE = [
    re.compile(r"LINE DIRECTIVES: (?:ON|OFF)"),
    re.compile(rf"SILENCE WARNINGS: {_SUPPORTED_SILENCED_WARNINGS_LIST_RE_STR}"),
    re.compile(r"PARTS \(syntax version [1-9]\.[0-9]\.[0-9]\)"),
    re.compile(rf"FOR {_FOR_COND_LIST_RE_STR} (?:BEGIN|END)"),
    re.compile(r"INTO (?:FIRST|LAST) SLICE (?:BEGIN|END)"),
    re.compile(r"SLICING TYPELIST\s*/\s*(?:[1-9])|(?:[1-3][0-9])"),
    re.compile(rf"CODE SLICING (?:BEGIN|BREAK)(?: {_CASE_NAME_RE_STR})?"),
    re.compile(r"CODE SLICING END"),
]

_SUPPORTED_END_OF_LINE_CONTROL_COMMENTS_RE = [
    re.compile(rf"FOR {_FOR_COND_LIST_RE_STR}"),
    re.compile(r"INTO (?:FIRST|LAST) SLICE"),
]


def _isUnsupportedControlComment(controlPart: str) -> bool:
    for matcher in _SUPPORTED_CONTROL_COMMENTS_RE:
        if re.fullmatch(matcher, controlPart):
            return False
    return True


def _isUnsupportedEndOfLineControlComment(controlPart: str) -> bool:
    for matcher in _SUPPORTED_END_OF_LINE_CONTROL_COMMENTS_RE:
        if re.fullmatch(matcher, controlPart):
            return False
    return True


def getUnsupportedControlCommentFrom(line: str) -> str:
    """Return the unsupported control comment in the or an empty string."""

    lstripped = line.lstrip()
    if lstripped.startswith(MY_CONTROL_COMMENT_PREFIX):
        return (
            lstripped
            if _isUnsupportedControlComment(removeprefix(lstripped, MY_CONTROL_COMMENT_PREFIX))
            else ""
        )

    if MY_CONTROL_COMMENT_PREFIX in line and not line.index(
        MY_CONTROL_COMMENT_PREFIX
    ) > line.index("//"):
        controlPart = line[
            line.index(MY_CONTROL_COMMENT_PREFIX) + len(MY_CONTROL_COMMENT_PREFIX) :
        ]
        return controlPart if _isUnsupportedEndOfLineControlComment(controlPart) else ""

    return ""
