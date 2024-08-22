from __future__ import annotations

import datetime
import itertools
import json
import logging
from pathlib import Path
import sys
from typing import (
    Any,
    Callable,
    Generator,
    Mapping,
    MutableMapping,
    MutableSequence,
    Sequence,
    Set,
    Tuple,
)

from lib.codeBlockInterval import CodeBlockInterval
from lib.xtCppParseResults import (
    OriginalTestcase,
    ParseResult,
    PartTestcase,
    SilencedWarningKind,
    SlicedTestcase,
    Testcase,
    TestcaseMapping,
    UnslicedTestcase,
)
from lib.myConstants import MY_INFO_COMMENT_PREFIX
from lib.mappingTables import generateTestCaseMappingTableForPart


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
    def _generateXtePart(useLineDirectives: bool, filepath: Path) -> MutableSequence[str]:
        lines = filepath.read_text(encoding="ascii", errors="surrogateescape").splitlines()
        if not lines:
            raise ValueError(f"File '{filepath}' appears to be empty")
        if not lines[0].startswith(f"// {filepath.name} ") or not lines[0].endswith(" -*-C++-*-"):
            raise ValueError(
                f"File '{filepath}' Does not start with the expected C++ prologue line: "
                f"'{lines[0]}'"
            )

        rv = ["", f"{MY_INFO_COMMENT_PREFIX}Standalone translation unit {filepath.name}", ""]
        if useLineDirectives:
            rv.append(f'#line 2 "{json.dumps(str(filepath))[1:-1]}"')
        return rv + lines[1:]

    return [_generateXtePart(useLineDirectives, filepath) for filepath in xtsFiles]


def _generatedToOriginalTestcaseMapping(
    parts: Sequence[Sequence[OriginalTestcase]],
) -> Sequence[Mapping[int, int]]:
    """Map part-number+generated-test-case-number -> original--test-case-number.

    Negative cases are mapped to themselves.

    Positive cases are numbered 1..N in each test driver part.
    """

    def _partMapping(contents: Sequence[OriginalTestcase]) -> Mapping[int, int]:
        mapping: Mapping[int, int] = {}
        partCaseIt = itertools.count(1)

        for origCase in sorted(elem.testcaseNumber for elem in contents):
            mapping[origCase] = next(partCaseIt) if origCase > 0 else origCase

        return mapping

    return [_partMapping(contents) for contents in parts]


def _generateCommandLineArgToOriginalMapping(
    parts: Sequence[Sequence[OriginalTestcase]],
) -> Sequence[Mapping[int, OriginalTestcase]]:
    """Map part-number+generated-test-case-number -> original--test-case-number.

    Negative cases are mapped to themselves.

    Positive cases are numbered 1..N in each test driver part.
    """

    rv: MutableSequence[MutableMapping[int, OriginalTestcase]] = []

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

    def _partMapping(contents: Sequence[OriginalTestcase]) -> Mapping[int, OriginalTestcase]:
        mapping: Mapping[int, OriginalTestcase] = {}
        partCaseIt = itertools.count(1)

        for origCase in sorted(contents, key=lambda x: x.testcaseNumber):
            mapping[
                next(partCaseIt) if origCase.testcaseNumber > 0 else origCase.testcaseNumber
            ] = origCase

        return mapping

    return [_partMapping(contents) for contents in parts]


def generateTestcasesToPartsMapping(parseResults: ParseResult) -> Sequence[TestcaseMapping]:
    """Original test case number to part+case-number or [part+case-number+slice-number]"""

    partToOrigMap = _generatedToOriginalTestcaseMapping(parseResults.parts)

    def getGeneratedCaseNumber(partNum: int, origCaseNum: int) -> int:
        part = partToOrigMap[partNum - 1]
        generated = part.get(origCaseNum)
        if generated is None:
            raise ValueError(
                f"INTERNAL ERROR: Could not find generated case number for "
                f"{origCaseNum} in part {partNum}.\n{part=}\n{parseResults.parts=}"
            )
        return generated

    positiveMappings: MutableSequence[TestcaseMapping] = []
    negativeMappings: MutableSequence[TestcaseMapping] = []

    for partNum, part in enumerate(parseResults.parts, 1):
        for elem in part:
            mapping = TestcaseMapping(elem, PartTestcase(partNum, elem.testcaseNumber))
            if elem.testcaseNumber > 0:
                mapping.partTestcaseNumber = getGeneratedCaseNumber(partNum, elem.testcaseNumber)
                positiveMappings.append(mapping)
            else:
                negativeMappings.append(mapping)

    return positiveMappings + negativeMappings


def _generateSilencingOfWarnings(silencedWarnings: Set[SilencedWarningKind]) -> Sequence[str]:
    if not silencedWarnings:
        return []

    rv: MutableSequence[str] = ["#include <bsls_platform.h>"]

    if "UNUSED" in silencedWarnings:
        rv += [
            "#ifdef BSLS_PLATFORM_HAS_PRAGMA_GCC_DIAGNOSTIC",
            '    #pragma GCC diagnostic ignored "-Wunused"',
            '    #pragma GCC diagnostic ignored "-Wunused-function"',
            '    #pragma GCC diagnostic ignored "-Wunused-variable"',
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
    appendLineDirective: Callable[[MutableSequence[str], int], str],
) -> Sequence[str]:
    rv: MutableSequence[str] = []
    appendLineDirective(rv, testcase.block.startLine)
    rv.append(
        f"      case {newCaseNum}: {{  // 'case {testcase.number}' slice {sliceNumber} in \"{xtCppName}\""
    )

    rv += testcase.generateCode(sliceNumber - 1, lines, appendLineDirective)
    return rv


def _collapseLineDirectives(partLines: MutableSequence[str]) -> None:
    isLine: Callable[[str], bool] = lambda s: s.strip().startswith("#line ")
    isNonLine: Callable[[Tuple[int, str]], bool] = lambda tup: not isLine(tup[1])
    isEmpty: Callable[[Tuple[int, str]], bool] = lambda tup: not tup[1].strip()
    enumerateSlice: Callable[[Sequence[Any], int], enumerate[Any]] = lambda seq, idx: enumerate(
        seq[idx:], idx
    )
    try:
        curIndex = 0
        while True:
            # Find next `#line` directive
            lineIdx, _ = next(itertools.dropwhile(isNonLine, enumerateSlice(partLines, curIndex)))
            while True:
                # Find next non-empty line
                nextIdx, line = next(
                    itertools.dropwhile(isEmpty, enumerateSlice(partLines, lineIdx + 1))
                )
                if isLine(line):
                    # If it's another `#line` directive, remove the previous
                    # one along with whitespace between them.
                    del partLines[lineIdx:nextIdx]
                else:
                    curIndex = nextIdx + 1
                    break
    except StopIteration:
        return


def _generateParts(
    escapedXtCppPath: str,
    xtCppPath: Path,
    xtCppName: str,
    qualifiedComponentName: str,
    parseResults: ParseResult,
    testcasesToPartsMapping: Sequence[TestcaseMapping],
    lines: MutableSequence[str],
    appendLineDirective: Callable[[MutableSequence[str], int], str],
) -> MutableSequence[MutableSequence[str]]:

    origToPartMappings = _generatedToOriginalTestcaseMapping(parseResults.parts)
    partToOrigMappings = _generateCommandLineArgToOriginalMapping(parseResults.parts)

    firstTestcasesLine = min(tc.block.startLine for tc in parseResults.testcases)
    stopTestcasesLine = max(tc.block.stopLine for tc in parseResults.testcases)

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

        partLines += generateTestCaseMappingTableForPart(testcasesToPartsMapping, len(results) + 1)
        partLines.append("")  # Add an empty line after the table

        if not qualifiedComponentName.endswith("_cpp03"):

            def generateCases() -> Generator[str, None, None]:  # type: ignore
                nonlocal partToOrigMapping

                for newNum, caseAndSlice in partToOrigMapping.items():
                    if caseAndSlice.testcaseNumber < 0:
                        # Negative test cases are handled by the `default` in the `switch`
                        continue  # !!! CONTINUE !!!

                    sliceNum = (
                        caseAndSlice.sliceNumber if caseAndSlice.sliceNumber is not None else 0
                    )
                    yield f"      case {newNum}: {{"
                    yield f"        origCase = {caseAndSlice.testcaseNumber};"
                    yield f"        origSlice = {sliceNum};"
                    yield "      } break;"

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
                    "        return;                                                       "
                    "// RETURN",
                    "    }",
                    "",
                    "    // First see if the case number exists in this test driver",
                    "",
                    "    int origCase, origSlice;",
                    "    switch(test) {",
                ]

                partLines += generateCases()

                partLines += [
                    "      default: {",
                    f'        printf("TEST {qualifiedComponentName}.{partNumber:02}.t CASE %d\\n"'
                    ", test);",
                    "        return;                                                       "
                    "// RETURN",
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
                    "        return;                                                       "
                    "// RETURN",
                    "    }",
                    "",
                    "    // First see if the case number exists in this test driver",
                    "",
                    "    int origCase, origSlice;",
                    "    switch(test) {",
                ]

                partLines += generateCases()

                partLines += [
                    "      default: {",
                    f'        cout << "TEST {qualifiedComponentName}.{partNumber:02}.t CASE "',
                    "              << test << endl;",
                    "        return;                                                       "
                    "// RETURN",
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
            appendLineDirective,
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
                    xtCppName,
                    origToPartMapping[content.testcaseNumber],
                    lines,
                    appendLineDirective,
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
                appendLineDirective,
            )
        del positiveCases

        negativeCases = [
            content.testcaseNumber for content in partContents if content.testcaseNumber < 0
        ]

        for content in negativeCases:
            theCase = testcases[content]
            assert isinstance(theCase, UnslicedTestcase)
            partLines += theCase.generateCode(
                xtCppName, theCase.number, lines, appendLineDirective
            )

        partLines += parseResults.conditionalCommonCodeBlocks.generateCodeForBlock(
            CodeBlockInterval(stopTestcasesLine, len(lines) + 1),
            partContents,
            lines,
            appendLineDirective,
        )

        if appendLineDirective([], 1) != "":
            _collapseLineDirectives(partLines)

        results.append(partLines)

    return results


def generateParts(
    xtCppPath: Path,
    xtCppName: str,
    qualifiedComponentName: str,
    parseResults: ParseResult,
    testcasesToPartsMapping: Sequence[TestcaseMapping],
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

        def appendLineDirective(ls: MutableSequence[str], lineNumber: int) -> str:
            ls.append(f'#line {lineNumber} "{escapedXtCppPath}"')
            return ls[-1]

    else:

        def appendLineDirective(ls: MutableSequence[str], lineNumber: int) -> str:
            return ""

    parts = _generateParts(
        escapedXtCppPath,
        xtCppPath,
        xtCppName,
        qualifiedComponentName,
        parseResults,
        testcasesToPartsMapping,
        lines,
        appendLineDirective,
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
