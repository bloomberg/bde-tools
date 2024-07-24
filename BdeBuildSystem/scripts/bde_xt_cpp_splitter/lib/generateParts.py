from __future__ import annotations

import datetime
import json
import logging
from pathlib import Path
import sys
from typing import Callable, Mapping, MutableMapping, MutableSequence, Sequence, Set

from lib.codeBlockInterval import CodeBlockInterval
from lib.xtCppParseResults import (
    OriginalTestcaseNumbers,
    ParseResult,
    SilencedWarningKind,
    SlicedMapping,
    SlicedTestcase,
    Testcase,
    UnslicedMapping,
    UnslicedTestcase,
)
from lib.myConstants import MY_INFO_COMMENT_PREFIX


def _collectXteFiles(xtCppPath: Path, qualifiedComponentName) -> Sequence[Path]:
    inputDirectory: Path = xtCppPath.parent
    singleXtsCpp = inputDirectory / f"{qualifiedComponentName}.xte.cpp"

    rv: MutableSequence[Path] = []
    if singleXtsCpp.exists():
        logging.debug(f"Found extra standalone translation unit '{singleXtsCpp}'")
        rv.append(singleXtsCpp)

    for name in inputDirectory.glob(f"{qualifiedComponentName}.xte.*.cpp"):
        logging.debug(f"Found extra standalone translation unit '{name}'")
        rv.append(name)

    if not rv:
        logging.debug("No extra standalone translation units were found.")

    return rv


def _generateXteParts(
    useLineDirectives: bool, xtsFiles: Sequence[Path]
) -> MutableSequence[MutableSequence[str]]:
    rv = []
    for filepath in xtsFiles:
        lines = filepath.read_text(encoding="ascii", errors="surrogateescape").splitlines()

        if not lines:
            raise ValueError(f"File '{filepath}' appears to be empty")

        if not lines[0].startswith(f"// {filepath.name} ") or not lines[0].endswith(" -*-C++-*-"):
            raise ValueError(
                f"File '{filepath}' Does not start with the expected C++ prologue line: "
                f"'{lines[0]}'"
            )
        rv.append(["", f"{MY_INFO_COMMENT_PREFIX}Standalone translation unit {filepath.name}", ""])
        if useLineDirectives:
            rv[-1].append(f'#line 2 "{json.dumps(str(filepath))[1:-1]}"')

        rv[-1] += lines[1:]

    return rv


def _generatedToOriginalTestcaseMapping(
    parts: Sequence[Sequence[OriginalTestcaseNumbers]],
) -> Sequence[Mapping[int, int]]:
    """Map part-number+generated-test-case-number -> original--test-case-number.

    Negative cases are mapped to themselves.

    Positive cases are numbered 1..N in each test driver part.
    """

    rv: MutableSequence[MutableMapping[int, int]] = []

    for contents in parts:
        rv.append({})
        sortedCases = sorted(elem.testcaseNumber for elem in contents)
        partCaseNum: int = 1
        for origCaseNum in sortedCases:
            if origCaseNum > 0:
                rv[-1][origCaseNum] = partCaseNum
                partCaseNum += 1
            else:
                rv[-1][origCaseNum] = origCaseNum
    return rv


def _generateCommandLineArgToOriginalMapping(
    parts: Sequence[Sequence[OriginalTestcaseNumbers]],
) -> Sequence[Mapping[int, OriginalTestcaseNumbers]]:
    """Map part-number+generated-test-case-number -> original--test-case-number.

    Negative cases are mapped to themselves.

    Positive cases are numbered 1..N in each test driver part.
    """

    rv: MutableSequence[MutableMapping[int, OriginalTestcaseNumbers]] = []

    for contents in parts:
        rv.append({})
        sortedCases = sorted(contents, key=lambda elem: elem.testcaseNumber)
        partCaseNum: int = 1
        for elem in sortedCases:
            origCaseNum = elem.testcaseNumber
            if origCaseNum > 0:
                rv[-1][partCaseNum] = elem
                partCaseNum += 1
            else:
                rv[-1][elem.testcaseNumber] = elem
    return rv


def generateTestcasesToPartsMapping(
    parseResults: ParseResult,
) -> Sequence[UnslicedMapping | Sequence[SlicedMapping]]:
    """Original test case number to part+case-number or [part+case-number+slice-number]"""

    rv: MutableSequence[UnslicedMapping | MutableSequence[SlicedMapping]] = []

    # First fill positive test cases as if they were all unsliced going into part 100 as case 100,
    # so we do not need to use a map (in the next loop)
    for testcase in parseResults.testcases:
        if testcase.number > 0:
            rv.append(UnslicedMapping(100, 100))

    partToOrigMap = _generatedToOriginalTestcaseMapping(parseResults.parts)

    def getGeneratedCaseNumber(partNum: int, origCaseNum: int) -> int:
        part = partToOrigMap[partNum - 1]
        for original, generated in part.items():
            if original == origCaseNum:
                return generated
        raise ValueError(
            f"INTERNAL ERROR: Could not find generated case number for "
            f"{origCaseNum} in part {partNum}.\n{part=}\n{parseResults.parts=}"
        )

    for partNum, part in enumerate(parseResults.parts, 1):
        for elem in part:
            if elem.testcaseNumber > 0:
                if not elem.hasSliceNumber:
                    rv[elem.testcaseNumber - 1] = UnslicedMapping(
                        partNum, getGeneratedCaseNumber(partNum, elem.testcaseNumber)
                    )
                else:  # Sliced test case
                    if isinstance(rv[elem.testcaseNumber - 1], UnslicedMapping):
                        rv[elem.testcaseNumber - 1] = []
                    sliceList = rv[elem.testcaseNumber - 1]
                    assert not isinstance(sliceList, UnslicedMapping)
                    assert elem.sliceNumber is not None
                    sliceList.append(
                        SlicedMapping(
                            partNum,
                            getGeneratedCaseNumber(partNum, elem.testcaseNumber),
                            elem.sliceNumber,
                        )
                    )

    # Add negative cases
    for partNum, part in enumerate(parseResults.parts, 1):
        for elem in part:
            if elem.testcaseNumber < 0:
                rv.append(UnslicedMapping(partNum, elem.testcaseNumber))

    return rv


def _generateTestCaseMappingTableForPart(
    testcasesToPartsMapping: Sequence[UnslicedMapping | Sequence[SlicedMapping]], partNum: int
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    rv += [
        r"// +===========================+",
        r"// | THIS PART's MAPPING TABLE |",
        r"// +===========================+",
        r"// | Original Test Case Number |",
        r"// |     +---------------------+",
        r"// |     | Slice Number        |",
        r"// |     |    +----------------+",
        r"// |     |    |  Case Number   |",
        r"// |     |    |  in Part       |",
        r"// +=====+====+=====+==========+",
    ]
    tableContent = []
    for caseNum, caseNumMapping in enumerate(testcasesToPartsMapping, 1):
        if isinstance(caseNumMapping, UnslicedMapping):
            if caseNumMapping.partNumber == partNum:
                inPartCaseNum = caseNumMapping.testcaseNumber
                assert isinstance(inPartCaseNum, int)
                if inPartCaseNum > 0:
                    tableContent.append(f"// | {caseNum:3} |    | {inPartCaseNum:3} |")
                else:  # Negative case numbers are not changed
                    tableContent.append(f"// | {inPartCaseNum:3} |    | {inPartCaseNum:3} |")
        else:
            for slicedMapping in caseNumMapping:
                if slicedMapping.partNumber == partNum:
                    tableContent.append(
                        f"// | {caseNum:3} | {slicedMapping.ofSliceNumber:2} | {slicedMapping.testcaseNumber:3} |"
                    )
    rv += "\n// +-----+----+-----+\n".join(tableContent).split("\n")
    rv += ["// +=====+====+=====+", ""]

    return rv


def _generateSilencingOfWarnings(silencedWarnings: Set[SilencedWarningKind]) -> Sequence[str]:
    if not silencedWarnings:
        return []

    rv: MutableSequence[str] = ["#include <bsls_platform.h>"]

    for warning in silencedWarnings:
        if warning == "UNUSED":
            rv += [
                "#ifdef BSLS_PLATFORM_HAS_PRAGMA_GCC_DIAGNOSTIC",
                '    #pragma GCC diagnostic ignored "-Wunused"',
                '    #pragma GCC diagnostic ignored "-Wunused-function"',
                "#endif",
                "",
            ]
    return rv


def _generateSlicedTestcase(
    escapedXtCppPath: str,
    xtCppName: str,
    testcase: SlicedTestcase,
    newCaseNum: int,
    sliceNumber: int,
    lines: Sequence[str],
    writeLineDirective: Callable[[MutableSequence[str], int], str],
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    writeLineDirective(rv, testcase.block.start)
    rv.append(
        f"      case {newCaseNum}: {{  // 'case {testcase.number}' slice {sliceNumber} in \"{xtCppName}\""
    )

    rv += testcase.generateCode(sliceNumber - 1, lines, writeLineDirective)
    return rv


def _collapseLineDirectives(partLines: MutableSequence[str]) -> None:
    lastEffectiveLineDirectiveSeenAt = -1
    lineIndex = 0
    while lineIndex < len(partLines):
        line = partLines[lineIndex].strip()
        if not line:
            lineIndex += 1
            continue  # !!! CONTINUE !!!

        if line.startswith("#line "):
            if lastEffectiveLineDirectiveSeenAt == -1:
                lastEffectiveLineDirectiveSeenAt = lineIndex
            else:
                # We have a redundant #line, let's overwrite the previous one and drop empty lines
                # between them if there were any
                partLines[lastEffectiveLineDirectiveSeenAt] = line
                del partLines[lastEffectiveLineDirectiveSeenAt + 1 : lineIndex + 1]
                lineIndex -= lineIndex - lastEffectiveLineDirectiveSeenAt
        else:
            # Any non-empty, non-#line line necessitates the previously see #line, so we cannot
            # overwrite/collapse it
            lastEffectiveLineDirectiveSeenAt = -1
        lineIndex += 1


def _generateParts(
    escapedXtCppPath: str,
    xtCppPath: Path,
    xtCppName: str,
    qualifiedComponentName: str,
    parseResults: ParseResult,
    testcasesToPartsMapping: Sequence[UnslicedMapping | Sequence[SlicedMapping]],
    lines: MutableSequence[str],
    writeLineDirective: Callable[[MutableSequence[str], int], str],
) -> MutableSequence[MutableSequence[str]]:

    origToPartMappings = _generatedToOriginalTestcaseMapping(parseResults.parts)
    partToOrigMappings = _generateCommandLineArgToOriginalMapping(parseResults.parts)

    firstTestcasesLine = min(tc.block.start for tc in parseResults.testcases)
    stopTestcasesLine = max(tc.block.stop for tc in parseResults.testcases)

    testcases: Mapping[int, Testcase] = {tc.number: tc for tc in parseResults.testcases}

    results: MutableSequence[MutableSequence[str]] = []
    for partNumber, partContents, origToPartMapping, partToOrigMapping in zip(
        range(1, len(parseResults.parts) + 1),
        parseResults.parts,
        origToPartMappings,
        partToOrigMappings,
    ):
        partLines: MutableSequence[str] = [
            "",
            "// ============================================================================",
            "// This is an AUTOMATICALLY GENERATED TEMPORARY source file.  If you edit it,",
            "// the build system will just overwrite it.  Do not commit it into any source",
            "// repository.  It is not for human consumption and its history is irrelevant.",
            "//",
            f'// See the original source code in: "{xtCppPath}"',
            "//",
            f"// This file was was generated on {datetime.datetime.utcnow().isoformat()} UTC by:",
            f'// "{sys.argv[0]}"',
            "// ============================================================================",
            "",
        ]

        partLines += _generateTestCaseMappingTableForPart(
            testcasesToPartsMapping, len(results) + 1
        )

        if not qualifiedComponentName.endswith("_cpp03"):
            if parseResults.testPrintLine.kind == "printf":
                partLines += [
                    "#include <stdio.h>",
                    "",
                    "namespace {",
                    "void printTestInfo(int test)",
                    "{",
                    "    if (test < 0) {",
                    f'        printf("TEST {escapedXtCppPath} CASE %d RUN AS '
                    f'{qualifiedComponentName}.{partNumber:02}.t CASE %d\\n", test, test);',
                    "        return;                                                       // RETURN",
                    "    }",
                    "",
                    "    // First see if the case number exists in this test driver",
                    "",
                    "    int origCase, origSlice;",
                    "    switch(test) {",
                ]
                for newNum, caseAndSlice in partToOrigMapping.items():
                    if caseAndSlice.testcaseNumber < 0:
                        # Negative test cases are handled by the `default` in the `switch`
                        continue  # !!! CONTINUE !!!

                    sliceNum = (
                        caseAndSlice.sliceNumber if caseAndSlice.sliceNumber is not None else 0
                    )
                    partLines += [
                        f"      case {newNum}: {{",
                        f"        origCase = {caseAndSlice.testcaseNumber};",
                        f"        origSlice = {sliceNum};",
                        "      } break;",
                    ]

                partLines += [
                    "      default: {",
                    f'        printf("TEST {qualifiedComponentName}.{partNumber:02}.t CASE %d\\n", '
                    "test);",
                    "        return;                                                       // RETURN",
                    "      } break;",
                    "    }",
                    "",
                    f'    printf("TEST {escapedXtCppPath} CASE %d ", origCase);',
                    "    if (origSlice > 0) {",
                    '        printf("SLICE %d ", origSlice);',
                    "    }",
                    f'    printf("RUN AS {qualifiedComponentName}.{partNumber:02}.t CASE %d\\n", '
                    "test);",
                    "}",
                    "}  // close unnamed namespace",
                    "",
                ]
            else:  # iostream
                partLines += [
                    "#include <bsl_iostream.h>",
                    "",
                    "namespace {",
                    "void printTestInfo(int test)",
                    "{",
                    "    using std::cout;  using std::endl;",
                    "",
                    "    if (test < 0) {",
                    f'        cout << "TEST {escapedXtCppPath} CASE " << test',
                    f'             << "RUN AS {qualifiedComponentName}.{partNumber:02}.t CASE "',
                    "              << test << endl;",
                    "        return;                                                       // RETURN",
                    "    }",
                    "",
                    "    // First see if the case number exists in this test driver",
                    "",
                    "    int origCase, origSlice;",
                    "    switch(test) {",
                ]
                for newNum, caseAndSlice in partToOrigMapping.items():
                    if caseAndSlice.testcaseNumber < 0:
                        # Negative test cases are handled by the `default` in the `switch`
                        continue  # !!! CONTINUE !!!

                    sliceNum = (
                        caseAndSlice.sliceNumber if caseAndSlice.sliceNumber is not None else 0
                    )
                    partLines += [
                        f"      case {newNum}: {{",
                        f"        origCase = {caseAndSlice.testcaseNumber};",
                        f"        origSlice = {sliceNum};",
                        "      } break;",
                    ]

                partLines += [
                    "      default: {",
                    f'        cout << "TEST {qualifiedComponentName}.{partNumber:02}.t CASE "',
                    "              << test << endl;",
                    "        return;                                                       // RETURN",
                    "      } break;",
                    "    }",
                    "",
                    f'    cout << "TEST {escapedXtCppPath} CASE " << origCase;',
                    "    if (origSlice > 0) {",
                    '        cout << " SLICE " << origSlice;',
                    "    }",
                    f'    cout << " RUN AS {qualifiedComponentName}.{partNumber:02}.t CASE "',
                    "          << test << endl;",
                    "}",
                    "}  // close unnamed namespace",
                    "",
                ]

        if parseResults.silencedWarnings:
            partLines += _generateSilencingOfWarnings(parseResults.silencedWarnings)

        if parseResults.simCpp11:
            parseResults.simCpp11.updateLines(partNumber, lines)

        partLines += parseResults.conditionalCommonCodeBlocks.generateCodeForBlock(
            CodeBlockInterval(2, parseResults.testPrintLine.lineNumber),
            partContents,
            lines,
            writeLineDirective,
        )

        partLines.append("    printTestInfo(test);")

        partLines += lines[parseResults.testPrintLine.lineNumber + 1 : firstTestcasesLine - 1]
        positiveCases = [content for content in partContents if content.testcaseNumber > 0]

        for content in sorted(positiveCases, reverse=True, key=lambda e: e.testcaseNumber):
            if not content.hasSliceNumber:
                # Simple, unsliced test case
                theCase = testcases[content.testcaseNumber]
                assert isinstance(theCase, UnslicedTestcase)
                partLines += theCase.generateCode(
                    xtCppName, origToPartMapping[content.testcaseNumber], lines, writeLineDirective
                )
                continue  # !!! continue

            # There are slices
            theCase = testcases[content.testcaseNumber]
            assert isinstance(theCase, SlicedTestcase)
            assert isinstance(content.sliceNumber, int)
            partLines += _generateSlicedTestcase(
                escapedXtCppPath,
                xtCppName,
                theCase,
                origToPartMapping[content.testcaseNumber],
                content.sliceNumber,
                lines,
                writeLineDirective,
            )
        del positiveCases

        negativeCases = [
            content.testcaseNumber for content in partContents if content.testcaseNumber < 0
        ]

        for content in negativeCases:
            theCase = testcases[content]
            assert isinstance(theCase, UnslicedTestcase)
            partLines += theCase.generateCode(xtCppName, theCase.number, lines, writeLineDirective)

        partLines += parseResults.conditionalCommonCodeBlocks.generateCodeForBlock(
            CodeBlockInterval(stopTestcasesLine, len(lines) + 1),
            partContents,
            lines,
            writeLineDirective,
        )

        if writeLineDirective([], 1) != "":
            _collapseLineDirectives(partLines)

        results.append(partLines)

    return results


def generateParts(
    xtCppPath: Path,
    xtCppName: str,
    qualifiedComponentName: str,
    parseResults: ParseResult,
    testcasesToPartsMapping: Sequence[UnslicedMapping | Sequence[SlicedMapping]],
    lines: MutableSequence[str],
    useLineDirectives: bool | None,
) -> Sequence[Sequence[str]]:

    # In-file setting overwrites the command line argument
    if parseResults.useLineDirectives is not None:
        useLineDirectives = parseResults.useLineDirectives
    if useLineDirectives is None:  # Default is writing the line directives
        useLineDirectives = True

    escapedXtCppPath = json.dumps(str(xtCppPath))[1:-1]  # Using JSON to escape backslashes

    if useLineDirectives:

        def writeLineDirective(ls: MutableSequence[str], lineNumber: int) -> str:
            ls.append(f'#line {lineNumber} "{escapedXtCppPath}"')
            return ls[-1]

    else:

        def writeLineDirective(ls: MutableSequence[str], lineNumber: int) -> str:
            return ""

    parts = _generateParts(
        escapedXtCppPath,
        xtCppPath,
        xtCppName,
        qualifiedComponentName,
        parseResults,
        testcasesToPartsMapping,
        lines,
        writeLineDirective,
    )

    xteFiles = _collectXteFiles(xtCppPath, qualifiedComponentName)
    if len(xteFiles) > 0:
        logging.info(f"Generated {len(parts)} parts from splitting '{xtCppName}'")
        logging.info(f"Found {len(xteFiles)} 'xte' file(s) adding them as additional parts")
        parts += _generateXteParts(useLineDirectives, xteFiles)
        logging.info(f"All together there are {len(parts)} parts for '{qualifiedComponentName}'")
    else:
        logging.info(f"Generated {len(parts)} parts for '{xtCppName}'")

    return parts
