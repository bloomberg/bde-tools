from __future__ import annotations

import itertools
import logging
from pathlib import Path
import re
from typing import Sequence, TextIO

from lib.mappingTables import generatePartMappingTable, generateTestCaseMappingTable
from lib.sourceFileOpen import sourceFileOpen
from lib.xtCppParseResults import TestcaseMapping


def _makePartFilename(partNumber: int, qualifiedComponentName: str) -> str:
    return f"{qualifiedComponentName}.{partNumber:02}.t.cpp"


def _makePartPath(partNumber: int, outputDirectory: Path, qualifiedComponentName: str) -> Path:
    return (outputDirectory / _makePartFilename(partNumber, qualifiedComponentName)).resolve()


def _makePartCpp03Path(partPath: Path) -> Path:
    newName = re.sub(r"(\.\d{2}\.t\.cpp)", "_cpp03\1", partPath.name)
    return partPath.with_name(newName)


def _writeStampFileIfNeededAndDeleteExtraFiles(
    stampPath: Path, outputDirectory: Path, qualifiedComponentName: str, numParts: int
) -> None:
    content = [_makePartFilename(part + 1, qualifiedComponentName) for part in range(numParts)]

    # Verify if stamp file content is unchanged
    if stampPath.is_file():
        with sourceFileOpen(stampPath, "r") as stampFile:
            existingContent = stampFile.read().splitlines()
            if len(existingContent) == len(content) and all(
                needLine == existLine for needLine, existLine in zip(content, existingContent)
            ):
                logging.info(f"Stamp file '{stampPath}' exists with the proper content.")
                return  # !!! RETURN

            # Delete .NN.t.cpp amd _cpp03.NN.t.cpp files we do not need anymore
            def loggedUnlink(path: Path) -> None:
                if not path.exists():
                    return  # !!! RETURN !!!
                logging.info(f"Deleting '{path}'")
                path.unlink()

            for filename in set(existingContent).difference(content):
                filepath = outputDirectory / filename
                loggedUnlink(filepath)
                loggedUnlink(_makePartCpp03Path(filepath))

    logging.info(f"Writing stamp file '{stampPath}'.")
    with sourceFileOpen(stampPath, "w") as stampFile:
        stampFile.writelines(line + "\n" for line in content)


def _isTimestampLine(line: str):
    return line.startswith("// This file was was generated on") and line.rstrip().endswith(
        " UTC by:"
    )


def _isPartContentSame(prologue: str, lines: Sequence[str], outPath: Path) -> bool:
    if not outPath.exists():
        return False
    with sourceFileOpen(outPath, "r") as infile:
        if infile.readline() != prologue:
            return False
        for needLine, existLine in itertools.zip_longest(lines, infile):
            if needLine is None or existLine is None:
                return False
            elif _isTimestampLine(needLine) and _isTimestampLine(existLine):
                continue  # !!! CONTINUE
            elif needLine.rstrip() != existLine.rstrip():
                return False

    return True


def _writePartFile(
    partNumber: int, outputDirectory: Path, qualifiedComponentName: str, lines: Sequence[str]
):
    outPath = _makePartPath(partNumber, outputDirectory, qualifiedComponentName)

    cppFlag = "-*-C++-*-"
    spaces = 79 - (4 + len(outPath.name) + len(cppFlag))
    prologue = f"// {outPath.name} {' ' * spaces}{cppFlag}\n"
    del cppFlag, spaces

    if not _isPartContentSame(prologue, lines, outPath):
        logging.info(f"Writing part file {outPath}.")
        with sourceFileOpen(outPath, "w") as outfile:
            outfile.write(prologue)
            outfile.writelines(line + "\n" for line in lines)
    else:
        logging.info(f"Part file {outPath!r} exists with the proper content.")


def _writePartFilesIfNeeded(
    outputDirectory: Path, qualifiedComponentName: str, partsContents: Sequence[Sequence[str]]
) -> None:
    for partNumber, lines in enumerate(partsContents, 1):
        _writePartFile(partNumber, outputDirectory, qualifiedComponentName, lines)


def _writeMapping(
    mappingFile: TextIO, testcasesToPartsMapping: Sequence[TestcaseMapping], numParts: int
):
    mappingFile.writelines(
        line + "\n"
        for line in itertools.chain(
            generateTestCaseMappingTable(testcasesToPartsMapping),
            ["", ""],
            generatePartMappingTable(testcasesToPartsMapping, numParts),
        )
    )


def writeOutputForXtCpp(
    stampPath: Path,
    outputDirectory: Path,
    qualifiedComponentName: str,
    partsContents: Sequence[Sequence[str]],
    testcasesToPartsMapping: Sequence[TestcaseMapping],
) -> None:
    lockfileName = outputDirectory / f"{qualifiedComponentName}.xt.cpp.mapping"
    with sourceFileOpen(lockfileName, "w") as mappingAndLockFile:
        _writePartFilesIfNeeded(outputDirectory, qualifiedComponentName, partsContents)
        _writeStampFileIfNeededAndDeleteExtraFiles(
            stampPath, outputDirectory, qualifiedComponentName, len(partsContents)
        )
        _writeMapping(mappingAndLockFile, testcasesToPartsMapping, len(partsContents))
