from __future__ import annotations

import itertools
import logging
import os
import pathlib
import re
from typing import MutableSequence, Sequence, TextIO, Tuple

from lib.sourceFileOpen import sourceFileOpen


def _generateTestCaseMappingTable(
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    rv += [
        r"// +=============================+",
        r"// |   TEST CASE MAPPING TABLE   |",
        r"// +=============================+",
        r"// | Original Test Case Number   |",
        r"// |     +-----------------------+",
        r"// |     | Slice Number          |",
        r"// |     |    +------------------+",
        r"// |     |    | Part Number      |",
        r"// |     |    |    +-------------+",
        r"// |     |    |    | Case Number |",
        r"// |     |    |    | in Part     |",
        r"// +=====+====+====+=====+=======+",
    ]
    tableContent = []
    for caseNum, caseNumMap in enumerate(testcasesToPartsMapping, 1):
        if isinstance(caseNumMap, tuple):
            inPartCaseNum = caseNumMap[1]
            assert isinstance(inPartCaseNum, int)
            if inPartCaseNum > 0:
                tableContent.append(
                    f"// | {caseNum:3} |    | {caseNumMap[0]:02} | {inPartCaseNum:3} |"
                )
            else:
                tableContent.append(  # Negative case numbers are not changed
                    f"// | {inPartCaseNum:3} |    | {caseNumMap[0]:02} | {inPartCaseNum:3} |"
                )
        else:
            for partNum, sliceNum, caseInPart in caseNumMap:
                tableContent.append(
                    f"// | {caseNum:3} | {sliceNum:2} | {partNum:02} | {caseInPart:3} |"
                )
    rv += "\n// +-----+----+----+-----+\n".join(tableContent).split("\n")
    rv.append("// +=====+====+====+=====+")

    return rv


def _generatePartMappingTable(
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
    numParts: int,
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    rv += [
        r"// +============================+",
        r"// |     PART MAPPING TABLE     |",
        r"// +============================+",
        r"// | Part Number                |",
        r"// |    +-----------------------+",
        r"// |    | Original Case Number  |",
        r"// |    |     +-----------------+",
        r"// |    |     | Slice Number    |",
        r"// |    |     |    +------------+",
        r"// |    |     |    | Part Case  |",
        r"// |    |     |    | Number     |",
        r"// +====+=====+====+=====+======+",
    ]
    for forPart in range(1, numParts + 1):
        partContent = []
        for caseNum, caseNumMap in enumerate(testcasesToPartsMapping, 1):
            if isinstance(caseNumMap, tuple):
                if caseNumMap[0] != forPart:
                    continue  # !! CONTINUE !!
                inPartCaseNum = caseNumMap[1]
                assert isinstance(inPartCaseNum, int)
                if inPartCaseNum > 0:
                    partContent.append(
                        f"// | {caseNumMap[0]:02} | {caseNum:3} |    | {inPartCaseNum:3} |"
                    )
                else:
                    partContent.append(  # Negative case numbers are not changed
                        f"// | {caseNumMap[0]:02} | {inPartCaseNum:3} |    | {inPartCaseNum:3} |"
                    )
            else:
                for partNum, sliceNum, caseInPart in caseNumMap:
                    if partNum != forPart:
                        continue  # !! CONTINUE !!
                    partContent.append(
                        f"// | {partNum:02} | {caseNum:3} | {sliceNum:2} | {caseInPart:3} |"
                    )
        rv += "\n// +----+-----+----+-----+\n".join(partContent).split("\n")
        rv.append("// +====+-----+----+-----+")

    return rv


def _makePartFilename(partNumber: int, qualifiedComponentName: str) -> str:
    return f"{qualifiedComponentName}.{partNumber:02}.t.cpp"


def _makePartPath(partNumber: int, outputDirectory: str, qualifiedComponentName: str) -> str:
    return os.path.normpath(
        os.path.join(outputDirectory, _makePartFilename(partNumber, qualifiedComponentName))
    )


def _makePartCpp03Path(partPath: str) -> str:
    return re.sub(r"(\.[0-9][0-9]\.t\.cpp)", "_cpp03\1", partPath)


def _writeStampFileIfNeededAndDeleteExtraFiles(
    stampPath: str, outputDirectory: str, qualifiedComponentName: str, numParts: int
) -> None:
    content = []
    for partNumber in range(1, numParts + 1):
        content.append(_makePartFilename(partNumber, qualifiedComponentName))

    # Verify if stamp file content is unchanged
    if os.path.isfile(stampPath):
        with sourceFileOpen(stampPath, "r") as stampFile:
            existingContent = stampFile.read().splitlines()
            if len(existingContent) == len(content) and all(
                needLine == existLine for needLine, existLine in zip(content, existingContent)
            ):
                logging.info(f"Stamp file '{stampPath}' exists with the proper content.")
                return  # !!! RETURN

            # Delete .NN.t.cpp amd _cpp03.NN.t.cpp files we do not need anymore
            for filename in existingContent:
                filepath = os.path.join(outputDirectory, filename)
                if filename not in content and os.path.exists(filepath):
                    logging.info(f"Deleting {filepath!r}")
                    os.unlink(filepath)
                    cpp03path = _makePartCpp03Path(filepath)
                    if os.path.exists(cpp03path):
                        logging.info(f"Deleting {cpp03path!r}")
                        os.unlink(cpp03path)

    logging.info(f"Writing stamp file '{stampPath}'.")
    with sourceFileOpen(stampPath, "w") as stampFile:
        for line in content:
            stampFile.write(line)
            stampFile.write("\n")


def _isTimestampLine(line: str):
    return line.startswith("// This file was was generated on") and line.rstrip().endswith(
        " UTC by:"
    )


_MY_TIMESTAMP_REGEX = re.compile(
    r"// This file was was generated on \d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d.\d\d\d\d\d\d UTC by:"
)
_MY_TIMESTAMP_BLANK = "// This file was was generated on YYYY-MM-DDTHH:MM:SS.ssssss UTC by:"


def _writePartFile(
    partNumber: int, outputDirectory: str, qualifiedComponentName: str, lines: Sequence[str]
):
    outName = _makePartFilename(partNumber, qualifiedComponentName)
    outPath = _makePartPath(partNumber, outputDirectory, qualifiedComponentName)

    cppFlag = "-*-C++-*-"
    spaces = 79 - (4 + len(outName) + len(cppFlag))
    prologue = f"// {outName} {' ' * spaces}{cppFlag}\n"
    del cppFlag, spaces

    if pathlib.Path(outPath).exists():
        needToWrite: bool = False
        with sourceFileOpen(outPath, "r") as infile:
            if infile.readline() != prologue:
                needToWrite = True
            else:
                for needLine, existLine in itertools.zip_longest(lines, infile):
                    if needLine is None or existLine is None:
                        needToWrite = True
                        break
                    elif _isTimestampLine(needLine) and _isTimestampLine(existLine):
                        continue  # !!! CONTINUE
                    elif needLine.rstrip() != existLine.rstrip():
                        needToWrite = True
                        break
        if not needToWrite:
            logging.info(f"Part file {outPath!r} exists with the proper content.")
            return  # !!! RETURN

    logging.info(f"Writing part file {outPath}.")
    with sourceFileOpen(outPath, "w") as outfile:
        outfile.write(prologue)
        outfile.write("\n".join(lines) + "\n")


def _writePartFilesIfNeeded(
    outputDirectory: str, qualifiedComponentName: str, partsContents: Sequence[Sequence[str]]
) -> None:
    for partNumber, lines in enumerate(partsContents, 1):
        _writePartFile(partNumber, outputDirectory, qualifiedComponentName, lines)


def _writeMapping(
    mappingFile: TextIO,
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
    numParts: int,
):
    content = []
    content += _generateTestCaseMappingTable(testcasesToPartsMapping)
    content += ["", ""]
    content += _generatePartMappingTable(testcasesToPartsMapping, numParts)
    for line in content:
        mappingFile.write(line)
        mappingFile.write("\n")


def writeOutputForXtCpp(
    stampPath: str,
    outputDirectory: str,
    qualifiedComponentName: str,
    partsContents: Sequence[Sequence[str]],
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
) -> None:
    lockfileName = os.path.join(outputDirectory, f"{qualifiedComponentName}.xt.cpp.mapping")
    with sourceFileOpen(lockfileName, "w") as mappingAndLockFile:
        _writePartFilesIfNeeded(outputDirectory, qualifiedComponentName, partsContents)
        _writeStampFileIfNeededAndDeleteExtraFiles(
            stampPath, outputDirectory, qualifiedComponentName, len(partsContents)
        )
        _writeMapping(mappingAndLockFile, testcasesToPartsMapping, len(partsContents))
