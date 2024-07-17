from __future__ import annotations

import os
import re
from typing import Mapping
import functools

from lib.sourceFileOpen import sourceFileOpen


class CppMacroError(ValueError):
    pass


@functools.lru_cache
def _getComponentMacroPrefixes(groupsDirs: str) -> Mapping[str, str]:
    prefixToPath: Mapping[str, str] = {}
    for groupsDir in groupsDirs.split(os.path.pathsep):
        if not groupsDir:
            groupsDir = os.path.curdir
        for groupDir in os.listdir(groupsDir):
            groupName = groupDir
            groupDir = os.path.join(groupsDir, groupDir)
            if not os.path.isdir(os.path.join(groupsDir, groupDir)):
                continue  # !!! CONTINUE

            groupMemFilename = os.path.join(groupDir, "group", f"{groupName}.mem")

            with open(
                groupMemFilename, "r", encoding="ascii", errors="surrogateescape"
            ) as memFile:
                packageList = (
                    line
                    for line in memFile.read().splitlines()
                    if line and not line.lstrip().startswith("#") and "+" not in line
                )
            for packageName in packageList:
                pkgDir = os.path.join(groupDir, packageName)
                pkgMemFilename = os.path.join(pkgDir, "package", f"{packageName}.mem")
                with open(
                    pkgMemFilename, "r", encoding="ascii", errors="surrogateescape"
                ) as memFile:
                    componentList = (
                        line
                        for line in memFile.read().splitlines()
                        if line and not line.lstrip().startswith("#")
                    )
                for component in componentList:
                    prefixToPath[component.upper() + "_"] = os.path.join(pkgDir, f"{component}.h")

    return prefixToPath


@functools.lru_cache(maxsize=8)
def _readFileForMacros(filename: str) -> str:
    with sourceFileOpen(filename, "r") as headerFile:
        return headerFile.read().replace("\\\n", " ")


@functools.lru_cache
def _findMacroDefInComponents(macroName: str, groupsDirs: str) -> str | None:
    if macroName.startswith("_"):
        return None

    split = macroName.split("_", maxsplit=2)
    if len(split) != 3:
        return None

    prefix = "_".join(split[:-1]).upper() + "_"

    if prefix not in _getComponentMacroPrefixes(groupsDirs):
        return None

    if [c for c in macroName if c != "_" and not c.isupper() and not c.isdigit()]:
        return None

    headerContent = _readFileForMacros(_getComponentMacroPrefixes(groupsDirs)[prefix])
    defs = re.findall(rf".*^#\s*define\s+{macroName}\b(.*)", headerContent, flags=re.MULTILINE)
    if not defs:
        return None
    elif len(defs) > 1:
        raise CppMacroError(
            f"More than one definition found for {macroName!r} in "
            f"{_getComponentMacroPrefixes(groupsDirs)[prefix]!r}"
        )

    return defs[0].strip()


@functools.lru_cache
def _findMacroDefInXtCpp(macroName: str, xtCppFull: str) -> str | None:
    content = _readFileForMacros(xtCppFull)
    defs = re.findall(rf".*^\s*#\s*define\s+{macroName}\b(.*)", content, flags=re.MULTILINE)
    if not defs:
        return None
    elif len(defs) > 1:
        raise CppMacroError(f"More than one definition found for {macroName!r} in {xtCppFull!r}")

    return defs[0].strip()


@functools.lru_cache
def findMacroDefinition(macroName: str, xtCppFull: str, groupsDirs: str) -> str:
    inXtCpp = _findMacroDefInXtCpp(macroName, xtCppFull)
    inComps = _findMacroDefInComponents(macroName, groupsDirs)

    if inXtCpp is None and inComps is None:
        raise CppMacroError(f"Unable to find definition for {macroName!r}")
    elif inXtCpp is not None and inComps is not None:
        raise CppMacroError(
            f"Two definitions found for {macroName!r} in both the test driver and a header"
        )
    elif inXtCpp is not None:
        return inXtCpp  # !!! RETURN

    assert inComps is not None
    return inComps  # !!! RETURN
