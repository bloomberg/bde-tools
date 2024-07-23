from __future__ import annotations

from pathlib import Path
import re
from typing import Mapping, MutableMapping, Sequence, Tuple
import functools

from lib.sourceFileOpen import sourceFileOpen


class CppMacroError(ValueError):
    pass


@functools.lru_cache
def _readMemFile(file: Path) -> Sequence[str]:
    lines = [
        line.partition("#")[0].strip()
        for line in file.read_text(encoding="ascii", errors="surrogateescape").splitlines()
    ]
    return [line for line in lines if line and "+" not in line]


@functools.lru_cache
def _getComponentMacroPrefixes(groupsDirs: Tuple[Path, ...]) -> Mapping[str, Path]:
    prefixToPath: MutableMapping[str, Path] = {}

    for groupsDir in groupsDirs:
        for groupDir in groupsDir.iterdir():
            groupName = groupDir.stem
            if not groupDir.is_dir():
                continue  # !!! CONTINUE

            groupMemFilename = groupDir / "group" / f"{groupName}.mem"

            packageList = _readMemFile(groupMemFilename)

            for packageName in packageList:
                pkgDir = groupDir / packageName
                pkgMemFilename = pkgDir / "package" / f"{packageName}.mem"
                componentList = _readMemFile(pkgMemFilename)
                for component in componentList:
                    prefixToPath[component.upper() + "_"] = pkgDir / f"{component}.h"

    return prefixToPath


@functools.lru_cache(maxsize=8)
def _readFileForMacros(filename: Path) -> str:
    with sourceFileOpen(filename, "r") as headerFile:
        return headerFile.read().replace("\\\n", " ")


@functools.lru_cache
def _findMacroDefInFile(macroName: str, filename: Path) -> str | None:
    content = _readFileForMacros(filename)
    defs = re.findall(rf".*^\s*#\s*define\s+{macroName}\b(.*)", content, flags=re.MULTILINE)
    if not defs:
        return None
    elif len(defs) > 1:
        raise CppMacroError(f"More than one definition found for '{macroName}' in '{filename}'")

    return defs[0].strip()


@functools.lru_cache
def _findMacroDefInComponents(macroName: str, groupsDirs: Tuple[Path, ...]) -> str | None:
    if macroName.startswith("_"):
        return None

    split = macroName.split("_", maxsplit=2)
    if len(split) != 3:
        return None

    prefix = macroName[: -len(split[-1])]

    if prefix not in _getComponentMacroPrefixes(groupsDirs):
        return None

    if [c for c in macroName if c != "_" and not c.isupper() and not c.isdigit()]:
        return None

    return _findMacroDefInFile(macroName, _getComponentMacroPrefixes(groupsDirs)[prefix])


@functools.lru_cache
def findMacroDefinition(macroName: str, xtCppFull: Path, groupsDirs: Tuple[Path, ...]) -> str:
    inXtCpp = _findMacroDefInFile(macroName, xtCppFull)
    inComps = _findMacroDefInComponents(macroName, groupsDirs)

    if inXtCpp is None and inComps is None:
        raise CppMacroError(f"Unable to find definition for '{macroName}'")
    elif inXtCpp is not None and inComps is not None:
        raise CppMacroError(
            f"Two definitions found for '{macroName}' in both the test driver and a header"
        )
    elif inXtCpp is not None:
        return inXtCpp  # !!! RETURN

    assert inComps is not None
    return inComps  # !!! RETURN
