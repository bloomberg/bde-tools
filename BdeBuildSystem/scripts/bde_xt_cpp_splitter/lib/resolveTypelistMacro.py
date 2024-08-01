from __future__ import annotations

from pathlib import Path
import re
from typing import Sequence, Tuple
import functools

from lib.extensionsForPy38 import removeprefix
from lib.findMacroDefinition import findMacroDefinition


def _resplitMacroValue(theList: str) -> str:
    """Replace comma separators with $ without destroying function types and template instances"""

    result = ""
    remainingParens = 0
    for part in theList.split(","):
        result += part.strip()

        remainingParens += part.count("(")
        closedParens = part.count(")")
        if remainingParens != closedParens:
            result += ", "
        else:
            result += "$"
        remainingParens -= closedParens
        assert remainingParens >= 0
    return result[:-1]


@functools.lru_cache
def _getListForMacro(macroName: str, xtCppFull: Path, groupsDirs: Tuple[Path, ...]) -> str:
    return _resplitMacroValue(findMacroDefinition(macroName, xtCppFull, groupsDirs))


_MACRO_LOOKING_RE = re.compile("[A-Z][_A-Z0-9][_A-Z0-9]+")  # min 3 characters


def _isMacroLookingName(name: str) -> bool:
    return bool(re.fullmatch(_MACRO_LOOKING_RE, name))


@functools.lru_cache
def _resolveTypelist(theList: str, xtCppFull: Path, groupsDirs: Tuple[Path, ...]) -> str:
    typeList = ""
    for name in theList.split("$"):
        if _isMacroLookingName(name):
            typeList += "$" + _resolveTypelist(
                _getListForMacro(name, xtCppFull, groupsDirs), xtCppFull, groupsDirs
            )
        else:
            typeList += "$" + name

    return removeprefix(typeList, "$")


@functools.lru_cache
def resolveTypelistMacro(macroName: str, xtCppFull: Path, groupsDirs: str) -> Sequence[str]:
    return _resolveTypelist(macroName, xtCppFull, groupsDirs).split("$")


@functools.lru_cache
def resolveTypelistMacroValue(
    macroValue: str, xtCppFull: Path, groupsDirs: Tuple[Path, ...]
) -> Sequence[str]:
    return _resolveTypelist(_resplitMacroValue(macroValue), xtCppFull, groupsDirs).split("$")
