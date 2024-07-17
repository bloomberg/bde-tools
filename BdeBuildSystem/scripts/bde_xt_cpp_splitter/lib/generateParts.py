from __future__ import annotations

import datetime
import glob
import json
import logging
import os
import sys
from typing import Callable, Mapping, MutableMapping, MutableSequence, Sequence, Set, Tuple

from lib.codeBlockInterval import CodeBlockInterval
from lib.xtCppParseResults import (
    ParseResult,
    SilencedWarningKind,
    SlicedTestcase,
    Testcase,
    UnslicedTestcase,
)
from lib.sourceFileOpen import sourceFileOpen
from lib.myConstants import MY_INFO_COMMENT_PREFIX


def _collectXteFiles(fp, qualifiedComponentName) -> Sequence[str]:
    inputDirectory: str = os.path.dirname(fp)
    singleXtsCpp = os.path.join(inputDirectory, f"{qualifiedComponentName}.xte.cpp")

    rv: MutableSequence[str] = []
    if os.path.exists(singleXtsCpp):
        logging.debug(f"Found extra standalone translation unit {singleXtsCpp!r}")
        rv.append(singleXtsCpp)

    for name in glob.glob(os.path.join(inputDirectory, f"{qualifiedComponentName}.xte.*.cpp")):
        logging.debug(f"Found extra standalone translation unit {name!r}")
        rv.append(name)

    if not rv:
        logging.debug("No extra standalone translation units were found.")

    return rv


def _generateXteParts(
    fp: str, useLineDirectives: bool, xtsFiles: Sequence[str]
) -> MutableSequence[MutableSequence[str]]:
    rv = []
    for filepath in xtsFiles:
        with sourceFileOpen(filepath, "r") as xtsFile:
            lines = xtsFile.read().splitlines()

            if not lines:
                raise ValueError(f"File {filepath!r} appears to be empty")

            if not lines[0].startswith(f"// {os.path.basename(filepath) }") or not lines[
                0
            ].endswith(" -*-C++-*-"):
                raise ValueError(
                    f"File {filepath!r} Does not start with the expected C++ prologue line: "
                    f"{lines[0]!r}"
                )
            rv.append(
                [
                    "",
                    f"{MY_INFO_COMMENT_PREFIX}Standalone translation unit "
                    f"{os.path.basename(filepath)!r}",
                    "",
                ]
            )
            if useLineDirectives:
                rv[-1].append(f'#line 2 "{fp}"')

            rv[-1] += lines[1:]

    return rv


def _generatedToOriginalTestcaseMapping(
    parts: Sequence[Sequence[int | Tuple[int, int]]],
) -> Sequence[Mapping[int, int]]:
    """Map part-number+generated-test-case-number -> original--test-case-number.

    Negative cases are mapped to themselves.

    Positive cases are numbered 1..N in each test driver part.
    """

    rv: MutableSequence[MutableMapping[int, int]] = []

    for contents in parts:
        rv.append({})
        positiveCases = sorted([elem[0] if isinstance(elem, tuple) else elem for elem in contents])
        partCaseNum: int = 1
        for origCaseNum in positiveCases:
            if origCaseNum > 0:
                rv[-1][origCaseNum] = partCaseNum
                partCaseNum += 1
    return rv


def _generateCommandLineArgToOriginalMapping(
    parts: Sequence[Sequence[int | Tuple[int, int]]],
) -> Sequence[Mapping[int, Tuple[int, int]]]:
    """Map part-number+generated-test-case-number -> original--test-case-number.

    Negative cases are mapped to themselves.

    Positive cases are numbered 1..N in each test driver part.
    """

    rv: MutableSequence[MutableMapping[int, Tuple[int, int]]] = []

    for contents in parts:
        rv.append({})
        positiveCases = sorted(
            contents, key=lambda elem: elem[0] if isinstance(elem, tuple) else elem
        )
        partCaseNum: int = 1
        for elem in positiveCases:
            origCaseNum = elem[0] if isinstance(elem, tuple) else elem
            if origCaseNum > 0:
                rv[-1][partCaseNum] = elem if isinstance(elem, tuple) else (elem, 0)
                partCaseNum += 1
    return rv


def generateTestcasesToPartsMapping(
    parseResults: ParseResult,
) -> Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]]:
    """Original test case number to part+case-number or [part+case-number+slice-number]"""

    rv: MutableSequence[Tuple[int, int] | MutableSequence[Tuple[int, int, int]]] = []

    # First fill positive test cases as if they were all unsliced going into part 100 as case 100,
    # so we do not need to use a map (in the next loop)
    for testcase in parseResults.testcases:
        if testcase.number > 0:
            rv.append((100, 100))

    partToOrigMap = _generatedToOriginalTestcaseMapping(parseResults.parts)

    def getGeneratedCaseNumber(partNum: int, origCaseNum: int) -> int:
        part = partToOrigMap[partNum - 1]
        for newCaseNum, elem in enumerate(part, 1):
            if elem == origCaseNum:
                return newCaseNum
        raise ValueError(
            f"INTERNAL ERROR: Could not find generated case number for "
            f"{origCaseNum} in part {partNum}.\n{part=}\n{parseResults.parts=}"
        )

    for partNum, part in enumerate(parseResults.parts, 1):
        for elem in part:
            if isinstance(elem, int):
                if elem > 0:
                    rv[elem - 1] = (partNum, getGeneratedCaseNumber(partNum, elem))
            else:  # Sliced test case
                assert isinstance(
                    elem, tuple
                ), f"{elem!r} is not a tuple, but {elem.__class__.__name__!r}"
                caseNum = elem[0]
                if isinstance(rv[caseNum - 1], tuple):
                    rv[caseNum - 1] = []
                sliceList = rv[caseNum - 1]
                assert not isinstance(sliceList, tuple)
                sliceList.append((partNum, elem[1], getGeneratedCaseNumber(partNum, caseNum)))

    # Add negative cases
    for partNum, part in enumerate(parseResults.parts, 1):
        for elem in part:
            if isinstance(elem, int):
                if elem < 0:
                    rv.append((partNum, elem))

    return rv


def _generateTestCaseMappingTableForPart(
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
    partNum: int,
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
    for caseNum, caseNumMap in enumerate(testcasesToPartsMapping, 1):
        if isinstance(caseNumMap, tuple):
            if caseNumMap[0] == partNum:
                inPartCaseNum = caseNumMap[1]
                assert isinstance(inPartCaseNum, int)
                if inPartCaseNum > 0:
                    tableContent.append(f"// | {caseNum:3} |    | {inPartCaseNum:3} |")
                else:  # Negative case numbers are not changed
                    tableContent.append(f"// | {inPartCaseNum:3} |    | {inPartCaseNum:3} |")
        else:
            for pn, sliceNum, caseInPart in caseNumMap:
                if pn == partNum:
                    tableContent.append(f"// | {caseNum:3} | {sliceNum:2} | {caseInPart:3} |")
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
    lineFp: str,
    fn: str,
    testcase: SlicedTestcase,
    newCaseNum: int,
    sliceNumber: int,
    lines: Sequence[str],
    writeLineDirective: Callable[[MutableSequence[str], int], str],
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    writeLineDirective(rv, testcase.block.start)
    rv.append(
        f"      case {newCaseNum}: {{  // 'case {testcase.number}' slice {sliceNumber} in \"{fn}\""
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
    fp: str,
    fn: str,
    qualifiedComponentName: str,
    parseResults: ParseResult,
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
    lines: MutableSequence[str],
    writeLineDirective: Callable[[MutableSequence[str], int], str],
) -> MutableSequence[MutableSequence[str]]:
    lineFp = json.dumps(fp)[1:-1]  # Using JSON to escape backslashes

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
            f'// See the original source code in: "{fp}"',
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
                    f'        printf("TEST {fp} CASE %d RUN AS '
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
                    partLines.append(f"      case {newNum}: {{")
                    partLines.append(f"        origCase = {caseAndSlice[0]};")
                    partLines.append(f"        origSlice = {caseAndSlice[1]};")
                    partLines.append("      } break;")

                partLines += [
                    "      default: {",
                    f'        printf("TEST {qualifiedComponentName}.{partNumber:02}.t CASE %d\\n", '
                    "test);",
                    "        return;                                                       // RETURN",
                    "      } break;",
                    "    }",
                    "",
                    f'    printf("TEST {fp} CASE %d ", origCase);',
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
                    f'        cout << "TEST {fp} CASE " << test ',
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
                    partLines.append(f"      case {newNum}: {{")
                    partLines.append(f"        origCase = {caseAndSlice[0]};")
                    partLines.append(f"        origSlice = {caseAndSlice[1]};")
                    partLines.append("      } break;")

                partLines += [
                    "      default: {",
                    f'        cout << "TEST {qualifiedComponentName}.{partNumber:02}.t CASE "',
                    "              << test << endl;",
                    "        return;                                                       // RETURN",
                    "      } break;",
                    "    }",
                    "",
                    f'    cout << "TEST {fp} CASE " << origCase;',
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
        positiveCases = [
            content for content in partContents if isinstance(content, tuple) or content > 0
        ]

        for content in sorted(
            positiveCases, reverse=True, key=lambda e: e[0] if isinstance(e, tuple) else e
        ):
            if isinstance(content, int):
                # Simple, unsliced test case
                theCase = testcases[content]
                assert isinstance(theCase, UnslicedTestcase)
                partLines += theCase.generateCode(
                    fn, origToPartMapping[content], lines, writeLineDirective
                )
                continue  # !!! continue

            # There are slices
            theCase = testcases[content[0]]
            assert isinstance(theCase, SlicedTestcase)
            partLines += _generateSlicedTestcase(
                lineFp,
                fn,
                theCase,
                origToPartMapping[content[0]],
                content[1],
                lines,
                writeLineDirective,
            )
        del positiveCases

        negativeCases = [
            content for content in partContents if isinstance(content, int) and content < 0
        ]

        for content in negativeCases:
            theCase = testcases[content]
            assert isinstance(theCase, UnslicedTestcase)
            partLines += theCase.generateCode(fn, theCase.number, lines, writeLineDirective)

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
    fp: str,
    fn: str,
    qualifiedComponentName: str,
    parseResults: ParseResult,
    testcasesToPartsMapping: Sequence[Tuple[int, int] | Sequence[Tuple[int, int, int]]],
    lines: MutableSequence[str],
    useLineDirectives: bool | None,
) -> Sequence[Sequence[str]]:

    # In-file setting overwrites the command line argument
    if parseResults.useLineDirectives is not None:
        useLineDirectives = parseResults.useLineDirectives
    if useLineDirectives is None:  # Default is writing the line directives
        useLineDirectives = True

    if useLineDirectives:

        def writeLineDirective(ls: MutableSequence[str], lineNumber: int) -> str:
            ls.append(f'#line {lineNumber} "{fp}"')
            return ls[-1]

    else:

        def writeLineDirective(ls: MutableSequence[str], lineNumber: int) -> str:
            return ""

    parts = _generateParts(
        fp,
        fn,
        qualifiedComponentName,
        parseResults,
        testcasesToPartsMapping,
        lines,
        writeLineDirective,
    )

    xteFiles = _collectXteFiles(fp, qualifiedComponentName)
    if len(xteFiles) > 0:
        logging.info(f"Generated {len(parts)} parts from splitting {fn!r}")
        logging.info(f"Found {len(xteFiles)} 'xte' file(s) adding them as additional parts")
        parts += _generateXteParts(fp, useLineDirectives, xteFiles)
        logging.info(f"All together there are {len(parts)} parts for {qualifiedComponentName!r}")
    else:
        logging.info(f"Generated {len(parts)} parts for {fn!r}")

    return parts
