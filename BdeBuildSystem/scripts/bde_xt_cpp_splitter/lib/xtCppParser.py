from __future__ import annotations

from pathlib import Path
import re
from typing import (
    Callable,
    Generator,
    Iterable,
    Mapping,
    MutableMapping,
    MutableSequence,
    MutableSet,
    Sequence,
    Set,
    Tuple,
    TypeVar,
)

from dataclasses import dataclass

from lib.extensionsForPy38 import removeprefix, removesuffix
from lib.codeBlockInterval import CodeBlockInterval
from lib.bdeConstants import BDE_MAX_LINE_LENGTH
from lib.resolveTypelistMacro import resolveTypelistMacroValue

from lib.xtCppSupportedControlComments import (
    SET_OF_SUPPORTED_SILENCED_WARNINGS,
    getUnsupportedControlCommentFrom,
)

from lib.myConstants import MY_CONTROL_COMMENT_PREFIX

from lib.xtCppParseResults import (
    CodeSlicing,
    ConditionalCommonCodeBlock,
    ConditionalCommonCodeBlocks,
    OriginalTestcase,
    SilencedWarningKind,
    SimCpp11Cpp03LinesToUpdate,
    SimCpp11IncludeConstruct,
    Testcase,
    TestPrintLineInfo,
    UnslicedTestcase,
    CodeSlicedTestcase,
    TypelistSlicedTestcase,
    CodeSlice,
    TypelistSlicing,
    ParseResult,
)

_END_OF_FILE_LINE = (
    "// ----------------------------- END-OF-FILE ----------------------------------"
)
assert len(_END_OF_FILE_LINE) == BDE_MAX_LINE_LENGTH

_THIN_FULL_DIVIDER = (
    "// ----------------------------------------------------------------------------"
)
assert len(_THIN_FULL_DIVIDER) == BDE_MAX_LINE_LENGTH


class ParseError(ValueError):
    pass


@dataclass
class _TypelistParseResult:
    controlCommentBlock: CodeBlockInterval
    macroName: str
    originalMacroBlock: CodeBlockInterval
    numSlices: int
    typelist: Sequence[str]

    def makeSlicedTypelist(self, xtCppName: str) -> Sequence[Sequence[str]]:
        numTypes = len(self.typelist)
        sliceSize, remainder = divmod(numTypes, self.numSlices)
        if sliceSize < 1:
            raise ParseError(
                f"{xtCppName}:{self.controlCommentBlock}: Too large number of slices "
                f"({self.numSlices}), length of the type list is {numTypes}"
            )

        def sliceStart(i):
            return i * sliceSize + min(i, remainder)

        return [self.typelist[sliceStart(i) : sliceStart(i + 1)] for i in range(self.numSlices)]


@dataclass
class _TestcaseParseResult:
    testcaseNumber: int
    block: CodeBlockInterval

    typelistParseResult: _TypelistParseResult | None
    codeSlicing: CodeSlicing | None
    intoFirstSliceBlocks: Sequence[CodeBlockInterval]
    intoLastSliceBlocks: Sequence[CodeBlockInterval]

    @property
    def wholeSlicedCodeBlock(self) -> CodeBlockInterval:
        if self.codeSlicing is None:
            raise ValueError(
                f"'wholeSlicedCodeBlock': No code slices in test case {self.testcaseNumber}"
            )

        return self.codeSlicing.block


T = TypeVar("T")


def _findIndexIf(cond: Callable[[T], bool], seq: Sequence[T], fromIndex: int = 0) -> int | None:
    return next(
        (idx for idx, element in enumerate(seq[fromIndex:], fromIndex) if cond(element)), None
    )


def _equalTo(what: str) -> Callable[[str], bool]:
    def _boundEqualTo(line: str) -> bool:
        nonlocal what
        return line.rstrip() == what

    return _boundEqualTo


def _createSliceNameMap(
    parseResults: Sequence[_TestcaseParseResult],
) -> Mapping[int, Mapping[str, int]]:
    def sliceNameMap(result):
        return result.codeSlicing.createSliceNameMap() if result.codeSlicing else {}

    return {parseResult.testcaseNumber: sliceNameMap(parseResult) for parseResult in parseResults}


_MY_SIMCPP11_IF_RE = re.compile(r"\s*#\s*if\s+BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES")


def _parseSimCpp11Include(
    xtCppName: str, qualifiedComponentName: str, lines: Sequence[str]
) -> SimCpp11IncludeConstruct | None:
    matches: Callable[[re.Pattern[str] | str], Callable[[str], bool]] = (
        lambda regex: lambda text: re.match(regex, text) is not None
    )

    idx = _findIndexIf(matches(_MY_SIMCPP11_IF_RE), lines)
    if idx is None:
        return None  # !!! RETURN !!!
    ifDefLine = idx + 1

    defineRe = rf"\s*#\s*define\s+COMPILING_{qualifiedComponentName.upper()}_X?T_CPP"
    idx = _findIndexIf(matches(defineRe), lines, ifDefLine)
    if idx is None:
        raise ParseError(
            f"{xtCppName}:{ifDefLine}: Cannot find "
            f"`#define COMPILING_{qualifiedComponentName.upper()}_XT_CPP`"
        )
    defineLine = idx + 1

    includeRe = rf"\s*#\s*include\s+<{qualifiedComponentName.lower()}_cpp03.xt.cpp>"
    idx = _findIndexIf(matches(includeRe), lines, defineLine)
    if idx is None:
        raise ParseError(
            f"{xtCppName}:{defineLine}: Cannot find "
            f"`#include <{qualifiedComponentName.lower()}_cpp03.xt.cpp>`"
        )
    includeLine = idx + 1

    undefRe = rf"\s*#\s*undef\s+COMPILING_{qualifiedComponentName.upper()}_X?T_CPP"
    idx = _findIndexIf(matches(undefRe), lines, includeLine)
    if idx is None:
        raise ParseError(
            f"{xtCppName}:{includeLine}: Cannot find "
            f"`#undef COMPILING_{qualifiedComponentName.upper()}_XT_CPP`"
        )
    undefLine = idx + 1
    elseLine = undefLine + 1

    # Skip any empty or clang-format command lines.
    while re.match(r"^($|[\t ]*// clang-format.*)", lines[elseLine - 1]):
        elseLine = elseLine + 1

    if len(lines) < elseLine:
        raise ParseError(f"{xtCppName}:{undefLine}: Premature end of file, expected `#else`")
    if not re.match(r"\s*#\s*else", lines[elseLine - 1]):
        raise ParseError(f"{xtCppName}:{idx + 2}: Expected `#else`, found '{lines[elseLine - 1]}'")

    return SimCpp11IncludeConstruct(
        CodeBlockInterval(ifDefLine, elseLine + 1), defineLine, includeLine, undefLine
    )


def _parseSimCpp11Cpp03(
    xtCppName: str, qualifiedComponentName: str, lines: Sequence[str]
) -> SimCpp11Cpp03LinesToUpdate:
    assert qualifiedComponentName.endswith("_cpp03")

    qualifiedComponentName = removesuffix(qualifiedComponentName, "_cpp03")

    ifdefLineContent = f"#ifdef COMPILING_{qualifiedComponentName.upper()}_XT_CPP"
    idx = _findIndexIf(_equalTo(ifdefLineContent), lines)
    if idx is None:
        raise ParseError(f"{xtCppName}: Cannot find '{ifdefLineContent}' in _cpp03 file")
    ifDefLine = idx + 1

    elseLineContent = f"#else // if ! defined(COMPILING_{qualifiedComponentName.upper()}_XT_CPP)"
    idx = _findIndexIf(_equalTo(elseLineContent), lines, ifDefLine)
    if idx is None:
        raise ParseError(f"{xtCppName}: Cannot find '{elseLineContent}' in _cpp03 file")
    elseLine = idx + 1

    endifLineContent = f"#endif // defined(COMPILING_{qualifiedComponentName.upper()}_XT_CPP)"
    idx = _findIndexIf(_equalTo(endifLineContent), lines, elseLine)
    if idx is None:
        raise ParseError(f"{xtCppName}: Cannot find '{endifLineContent}' in _cpp03 file")
    endifLine = idx + 1

    invocationLines: MutableSequence[int] = []
    for lineNumber, line in enumerate(lines, 1):
        line = line.strip()
        if line.startswith("// Command line: sim_cpp11_features.pl ") and line.endswith(".xt.cpp"):
            invocationLines.append(lineNumber)

    return SimCpp11Cpp03LinesToUpdate(ifDefLine, elseLine, endifLine, invocationLines)


def _verifySupportedControlComments(xtCppName: str, lines: Sequence[str]) -> None:
    for lineNumber, line in enumerate(lines, 1):
        if theComment := getUnsupportedControlCommentFrom(line):
            raise ParseError(
                f"{xtCppName}:{lineNumber}: Unsupported control comment: '{theComment}'"
            )


_MY_LINE_DIRECTIVES_PREFIX = MY_CONTROL_COMMENT_PREFIX + "LINE DIRECTIVES: "


def _getLineDirectivesControl(xtCppName: str, lines: Sequence[str]) -> bool | None:
    for lineNumber, line in enumerate(lines, 1):
        line = line.strip()
        if line.startswith(_MY_LINE_DIRECTIVES_PREFIX):
            setting = removeprefix(line, _MY_LINE_DIRECTIVES_PREFIX).lstrip()
            if setting == "ON":
                return True
            elif setting == "OFF":
                return False
            else:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: LINE DIRECTIVES setting must be ON or OFF, not "
                    f"'{setting}' in '{line}'"
                )
    return None


_MY_SILENCED_WARNINGS_PREFIX = MY_CONTROL_COMMENT_PREFIX + "SILENCE WARNINGS: "


def _getSilencedWarnings(xtCppName: str, lines: Sequence[str]) -> Set[SilencedWarningKind]:
    rv: MutableSet[SilencedWarningKind] = set()
    for lineNumber, line in enumerate(lines, 1):
        line = line.strip()
        if line.startswith(_MY_SILENCED_WARNINGS_PREFIX):
            warnings = removeprefix(line, _MY_SILENCED_WARNINGS_PREFIX)
            warnings = (warning.strip() for warning in warnings.split(","))
            for warning in warnings:
                if warning not in SET_OF_SUPPORTED_SILENCED_WARNINGS:
                    raise ParseError(
                        f"{xtCppName}:{lineNumber}: Unknown warning name: '{warning}' in '{line}'"
                    )
                rv.add(warning)  # type: ignore
    return rv


def _isTestcaseInt(txt: str) -> bool:
    return txt.isdigit() or (txt.startswith("-") and txt[1:].isdigit())


def _verifyFoundPositiveTestCases(
    xtCppName: str, testcasesNumbers: Iterable[_TestcaseParseResult]
) -> None:
    positiveTestcaseNumbers = [
        pr.testcaseNumber for pr in testcasesNumbers if pr.testcaseNumber > 0
    ]

    if not positiveTestcaseNumbers:
        raise ParseError(f"{xtCppName}: Unable to find any test cases in 'main'")

    allCases = set(range(1, max(positiveTestcaseNumbers) + 1))
    for testcaseNumber in positiveTestcaseNumbers:
        if testcaseNumber not in allCases:
            raise ParseError(f"{xtCppName}: Duplicate test-case number {testcaseNumber}")
        allCases.remove(testcaseNumber)

    if allCases:
        raise ParseError(f"{xtCppName}: There are missing test-case numbers {allCases}")


def _findMainStart(xtCppName: str, lines: Sequence[str]) -> int:
    """Find 'int main(int argc, char *argv[])', ensure there is only one, other sanity checks."""

    if (idx := _findIndexIf(_equalTo("int main(int argc, char *argv[])"), lines)) is None:
        raise ParseError(
            f"{xtCppName}: Could not find definition 'int main(int argc, char *argv[])'"
        )

    if (
        idx2 := _findIndexIf(_equalTo("int main(int argc, char *argv[])"), lines, idx + 1)
    ) is not None:
        raise ParseError(
            f"{xtCppName}:{idx2+1}: Found a second 'int main(int argc, char *argv[])').  "
            f"First main was found at {idx+1}."
        )

    return idx


def _reverseEnumerate(seq: Sequence) -> Generator:
    for i in range(len(seq) - 1, -1, -1):
        yield (i, seq[i])


def _findMainEnd(xtCppName: str, offset: int, fromMainLines: Sequence[str]) -> int:
    """Find main closing brace, ensure there is only one, other sanity checks."""

    additionalOffset: int = 0
    found = ""

    # Find the real end of main
    while True:
        if (idx := _findIndexIf(_equalTo("}"), fromMainLines)) is None:
            raise ParseError(f"{xtCppName}:{offset}: Could not find closing brace for 'main'")

        found += f"\nFOUND: {idx=}, {offset=}, {offset+additionalOffset+idx=}"

        # If the closing brace is in a usage example block we have to look for another
        idxPrev, linePrev = next(
            (
                (i, line)
                for i, line in _reverseEnumerate(fromMainLines[:idx])
                if line.startswith("//")
                or (line.startswith("      case ") and line.rstrip().endswith("{"))
            ),
            (-1, ""),
        )

        if idxPrev == -1:  # This is really the end
            break  ## !!! BREAK  !!!

        if linePrev.startswith("      case ") and linePrev.rstrip().endswith(
            "{"
        ):  # Not usage code
            break  ## !!! BREAK  !!!

        if linePrev.startswith("//") and linePrev.rstrip() != "//..":  # Not usage example code
            break  ## !!! BREAK  !!!

        # We have found a closing brace in a usage example, need to skip it
        additionalOffset += idx + 1
        fromMainLines = fromMainLines[idx + 1 :]

    # In an _cpp03.xt.cpp we also have an empty main
    for line in fromMainLines[idx + 1 :]:
        if not line.strip():
            continue  # !!! CONTINUE !!!

        if line.startswith("#else // if ! defined(COMPILING_"):
            return idx  # !!! RETURN !!!

    if (idx2 := _findIndexIf(_equalTo("}"), fromMainLines, idx + 1)) is not None:
        raise ParseError(
            f"{xtCppName}:{offset + idx + 1}: Found a second closing brace for 'main' on line "
            f"{offset + idx  + idx2 + 1}"
        )

    return additionalOffset + idx


def _findMainBlock(xtCppName: str, lines: Sequence[str]) -> CodeBlockInterval:
    """Find main function plus some sanity checks."""
    start = _findMainStart(xtCppName, lines)
    return CodeBlockInterval.CreateFromIndex(
        start, start + _findMainEnd(xtCppName, start + 1, lines[start + 1 :]) + 2
    )


_PRINTF_TEST_PRINT_RE = re.compile(
    r'    (?:std::)?printf\s*\(\s*"TEST "\s+__FILE__\s*" CASE %d\\n"\s*,\s*test\);\s*'
)

_COUT_TEST_PRINT_RE = re.compile(
    r'    (?:std::)?cout\s*<<\s*"TEST "'
    r"(?:(?:\s*<<\s*__FILE__)|(?:\s+__FILE__))\s*(?:<<\s*)?"
    r'" CASE "\s*<<\s*test\s*<<\s*(?:(?:"\\n")|(?:(?:std::)?endl));\s*'
)


def _findTestPrintLine(xtCppName: str, offset: int, mainLines: Sequence[str]) -> TestPrintLineInfo:
    for offset, line in enumerate(mainLines, offset):

        if re.fullmatch(_PRINTF_TEST_PRINT_RE, line):
            return TestPrintLineInfo(offset + 1, "printf")

        if re.fullmatch(_COUT_TEST_PRINT_RE, line):
            return TestPrintLineInfo(offset + 1, "cout")

        if line.startswith("    switch (test)"):
            break

    raise ParseError(f"{xtCppName}:{offset}: Could not find the printf or cout line for 'test'")


@dataclass
class _TestSwitchCaseLines:
    offset: int
    lines: Sequence[str]


def _extractTestSwitchCaseLines(
    xtCppName: str, offset: int, mainLines: Sequence[str]
) -> _TestSwitchCaseLines:
    """Get the part that only has the case +/-N: { ~~~ } break; elements"""

    if (
        idx := _findIndexIf(
            _equalTo("    switch (test) { case 0:  // Zero is always the leading case."), mainLines
        )
    ) is None:
        if (idx := _findIndexIf(_equalTo("    switch (test) { case 0:"), mainLines)) is None:
            raise ParseError(f"{xtCppName}: Could not find 'switch(test) {{ case 0:' in 'main'")

    if sum(line.startswith("    switch (test) { case 0:") for line in mainLines) > 1:
        raise ParseError(f"{xtCppName}: More than one 'switch(test) {{ case 0:' present in 'main'")

    if (idx2 := _findIndexIf(_equalTo("      default: {"), mainLines, idx + 1)) is None:
        raise ParseError(f"{xtCppName}:{offset  + idx + 2} Could not find 'default: {{' in 'main'")

    if mainLines[idx + 1 :].count("      default: {") != 1:
        raise ParseError(f"{xtCppName}: More than one 'default: {{' present in 'main'")

    return _TestSwitchCaseLines(offset + idx + 1, mainLines[idx + 1 : idx2])


@dataclass
class _CodeSliceInfo:
    sliceName: str  # Empty string when there is no name
    block: CodeBlockInterval


@dataclass
class _CodeSlicingParsingState:
    sliceName: str  # Empty if no name
    startLine: int
    sliceBlocks: MutableSequence[_CodeSliceInfo]
    subSlices: MutableMapping[int, _TypelistParseResult | CodeSlicing]


_MACRO_NAME_RE = re.compile(r"(?:(?:u_)|[_A-Z])[_A-Z0-9][_A-Z0-9]+")


def _parseOneTestcase(
    xtCppName: str,
    testcaseNumber: int,
    testcaseBlock: CodeBlockInterval,
    caseLines: Sequence[str],
    resolveTypelist=Callable[[str], Sequence[str]],
) -> _TestcaseParseResult:
    intoFirstSliceBlocks: MutableSequence[CodeBlockInterval] = []
    intoLastSliceBlocks: MutableSequence[CodeBlockInterval] = []

    topCodeSlicing: CodeSlicing | None = None

    codeSliceNamesToLine: MutableMapping[str, int] = {}

    codeSliceStack: MutableSequence[_CodeSlicingParsingState] = []

    currentCodeSliceName: str = ""
    currentCodeSliceStart: int = 0
    currentCodeSliceBlocks: MutableSequence[_CodeSliceInfo] = []
    currentCodeSliceNumberToSubSlice: MutableMapping[int, _TypelistParseResult | CodeSlicing] = {}

    def parseCodeSliceName(prefix: str) -> str:
        nonlocal parsed, xtCppName, lineNumber, codeSliceNamesToLine

        maybeName = removeprefix(parsed, prefix).strip()
        if maybeName:
            if len(maybeName) < 2:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Code slice names must be at least 2 characters.  "
                    f"'{maybeName}'"
                )
            if not maybeName[0].isascii():
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Code slice names must start with an ASCII "
                    f"letter.  '{maybeName}'"
                )
            if not all(char == "_" or char.isascii() or char.isdigit() for char in maybeName[1:]):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Invalid character in code slice name "
                    f"'{maybeName}'.  Allowed characters are ASCII letters and digits and "
                    "underscore '_'."
                )
            if maybeName in codeSliceNamesToLine:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Code slice name '{maybeName}' is already in use "
                    f"on line {codeSliceNamesToLine[maybeName]}."
                )
            codeSliceNamesToLine[maybeName] = lineNumber

        return maybeName

    def beginCodeSlicing() -> None:
        nonlocal codeSliceStack, currentCodeSliceName, lineNumber
        nonlocal currentCodeSliceStart, currentCodeSliceBlocks, currentCodeSliceNumberToSubSlice

        if topTypelistSlicing is not None:
            raise ParseError(
                f"{xtCppName}:{lineNumber}: Code slicing cannot be used when type list slicing is "
                "present on the same level."
            )

        if currentCodeSliceStart:
            if len(currentCodeSliceBlocks) - 1 in currentCodeSliceNumberToSubSlice:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Only one code slicing per is supported at a "
                    f"\"level\" '{line}'.  Test cases may have only one top code slicing, and "
                    "each code slice may have only one code slicing or a typelist slicing in it."
                )
            codeSliceStack.append(
                _CodeSlicingParsingState(
                    currentCodeSliceName,
                    currentCodeSliceStart,
                    currentCodeSliceBlocks,
                    currentCodeSliceNumberToSubSlice,
                )
            )

        currentCodeSliceName = parseCodeSliceName(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BEGIN")
        currentCodeSliceStart = lineNumber + 1  # We "skip" the control-comment
        currentCodeSliceBlocks = []
        currentCodeSliceNumberToSubSlice = {}

    def endCodeSlicing() -> None:
        nonlocal topCodeSlicing, currentCodeSliceName, lineNumber
        nonlocal currentCodeSliceStart, currentCodeSliceBlocks, currentCodeSliceNumberToSubSlice

        if currentCodeSliceStart == 0:
            raise ParseError(
                f"{xtCppName}:{lineNumber}: CODE SLICING END outside of CODE SLICING BEGIN "
                f"'{line}'"
            )
        if len(currentCodeSliceBlocks) == 0:
            raise ParseError(
                f"{xtCppName}:{lineNumber}: CODE SLICING END after just one slice (no BREAK seen) "
                f"'{line}'"
            )

        currentCodeSliceBlocks.append(
            _CodeSliceInfo(
                currentCodeSliceName,
                CodeBlockInterval(currentCodeSliceBlocks[-1].block.stopLine + 1, lineNumber),
            )  # stopLine points at the BREAK control comment, so we need to add 1 to skip it
            # lineNumber points to the END comment, which we don't include
        )

        # sub-blocks do not contain the control-comments, but for sanity of the code-generating the
        # complete block (whose "printing" belongs to this slicing) includes the control-comments,
        # hence the -1 and +1 to extend the complete block over all lines.
        wholeBlock = CodeBlockInterval(
            currentCodeSliceBlocks[0].block.startLine - 1, lineNumber + 1
        )
        slices: MutableSequence[CodeSlice] = []
        for sliceIndex, sliceInfo in enumerate(currentCodeSliceBlocks, 0):
            theSlice = CodeSlice(sliceInfo.sliceName, sliceInfo.block)

            # No sub-slicing
            if sliceIndex not in currentCodeSliceNumberToSubSlice:
                slices.append(theSlice)
                continue  # !!! CONTINUE !!!

            subSliceState = currentCodeSliceNumberToSubSlice[sliceIndex]
            if isinstance(subSliceState, _TypelistParseResult):
                theSlice.subSlicing = TypelistSlicing(
                    subSliceState.controlCommentBlock,
                    subSliceState.originalMacroBlock,
                    subSliceState.macroName,
                    subSliceState.makeSlicedTypelist(xtCppName),
                )
            else:
                assert isinstance(subSliceState, CodeSlicing)
                theSlice.subSlicing = subSliceState
            slices.append(theSlice)

        finishedCodeSlicing = CodeSlicing(wholeBlock, slices)

        if not codeSliceStack:
            topCodeSlicing = finishedCodeSlicing
            currentCodeSliceName = ""
            currentCodeSliceStart = 0
            currentCodeSliceBlocks = []
            currentCodeSliceNumberToSubSlice = {}
            return  # !!! RETURN !!!

        outerState = codeSliceStack.pop()
        currentCodeSliceName = outerState.sliceName
        currentCodeSliceStart = outerState.startLine
        currentCodeSliceBlocks = outerState.sliceBlocks
        currentCodeSliceNumberToSubSlice = outerState.subSlices
        currentCodeSliceNumberToSubSlice[len(currentCodeSliceBlocks)] = finishedCodeSlicing

    topTypelistSlicing: _TypelistParseResult | None = None

    currentTypelistCommentLine: int = 0
    currentTypelistStart: int = 0
    currentTypelistNumberOfSlices: int = 0
    currentTypelistMacroName: str = ""
    currentTypelistMacroValue: str = ""

    intoFirstSliceStart: int = 0
    intoLastSliceStart: int = 0

    for lineNumber, line in enumerate(caseLines, testcaseBlock.startLine):
        parsed = line.strip()
        # Skip empty lines
        if not parsed:
            continue  # !!! CONTINUE

        if testcaseNumber < 0 and parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}"):
            raise ParseError(
                f"{xtCppName}:{lineNumber}: Negative test cases cannot be sliced '{line}'"
            )

        # While parsing a SLICE TYPELIST command, looking for the #define
        if currentTypelistNumberOfSlices != 0 and currentTypelistStart == 0:
            if parsed.startswith(MY_CONTROL_COMMENT_PREFIX):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: No control comments allowed between the type-list "
                    f"macro definition and the SLICE TYPELIST comment '{line}'"
                )
            elif parsed.startswith("/*"):  ## Skip comments
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: No multi-line comments allowed between the "
                    f"type-list macro definition and the SLICE TYPELIST comment '{line}'"
                )
            elif parsed.startswith("//"):  ## Skip comments
                continue  # !!! CONTINUE
            elif not parsed.startswith("#"):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Only line-comments allowed between the type-list "
                    f"macro definition and the SLICE TYPELIST comment '{line}'"
                )

            parsed = parsed[1:].lstrip()  # Drop the '#'
            if not parsed.startswith("define"):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Expected #define after SLICE TYPELIST command "
                    f"'{line}'"
                )
            parsed = removeprefix(parsed, "define")
            if not parsed:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Premature end of line after #define '{line}'"
                )
            if parsed[0] not in " \t":
                raise ParseError(f"{xtCppName}:{lineNumber}: No whitespace after #define '{line}'")

            parsed = parsed.lstrip()
            currentTypelistMacroName, parsed = parsed.split(" ", maxsplit=1)
            if not currentTypelistMacroName:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Could not parse macro name in #define '{line}'"
                )

            if not re.fullmatch(_MACRO_NAME_RE, currentTypelistMacroName):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: '{currentTypelistMacroName}' does not appear to "
                    f"be a macro name in #define '{line}'"
                )

            currentTypelistStart = lineNumber

        if currentTypelistNumberOfSlices != 0 and currentTypelistStart != 0:
            currentTypelistMacroValue += parsed
            if not parsed.endswith("\\"):  # No line continuation
                typelist = resolveTypelist(currentTypelistMacroValue)
                if not typelist:
                    raise ParseError(
                        f"{xtCppName}:{lineNumber}: '{currentTypelistMacroName}' results in an "
                        "empty type-list."
                    )

                theFinishedTypelistSlicing = _TypelistParseResult(
                    CodeBlockInterval(currentTypelistCommentLine),
                    currentTypelistMacroName,
                    CodeBlockInterval(currentTypelistStart, lineNumber + 1),
                    currentTypelistNumberOfSlices,
                    typelist,
                )

                if currentCodeSliceStart == 0:
                    topTypelistSlicing = theFinishedTypelistSlicing
                else:
                    currentCodeSliceNumberToSubSlice[len(currentCodeSliceBlocks)] = (
                        theFinishedTypelistSlicing
                    )

                currentTypelistStart = 0
                currentTypelistNumberOfSlices = 0
                currentTypelistMacroName = ""
                currentTypelistMacroValue = ""
            else:
                currentTypelistMacroValue = currentTypelistMacroValue[:-1].rstrip() + " "

        # Handling commands
        if parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BEGIN"):
            if topCodeSlicing is not None:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Only one code slicing per is supported at a "
                    f"\"level\" '{line}'.  Test cases may have only one top code slicing, and "
                    "each code slice may have only one code slicing or a typelist slicing in it."
                )
            beginCodeSlicing()
        elif parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BREAK"):
            if currentCodeSliceStart == 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: SLICING BREAK outside of CODE SLICING BEGIN "
                    f"'{line}'"
                )

            if topTypelistSlicing is not None and currentCodeSliceName:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Code slices cannot be named when a type list "
                    "slicing is present on the same  level because the name would not map to a "
                    f"single slice.  Please remove '{currentCodeSliceName}'."
                )

            currentCodeSliceBlocks.append(
                _CodeSliceInfo(
                    currentCodeSliceName, CodeBlockInterval(currentCodeSliceStart, lineNumber)
                )  # lineNumber is at the BREAK comment, which we do not include
            )
            currentCodeSliceStart = lineNumber + 1  # We "skip" the control comment
            currentCodeSliceName = parseCodeSliceName(
                f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BREAK"
            )
        elif parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING END"):
            endCodeSlicing()
        elif parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}SLICING TYPELIST"):
            if 0 in currentCodeSliceNumberToSubSlice:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Multiple type-lists must be all be under separate "
                    f"code slices. '{line}'"
                )
            # Get the number of slices
            parsed = removeprefix(parsed, f"{MY_CONTROL_COMMENT_PREFIX}SLICING TYPELIST").lstrip()
            if not parsed.startswith("/"):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Missing '/' following SLICING TYPELIST '{line}'"
                )
            parsed = parsed[1:].lstrip()
            if not parsed.isdigit():
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Number of slices is not a number '{line}'"
                )
            currentTypelistNumberOfSlices = int(parsed)
            if currentTypelistNumberOfSlices < 1:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Number of slices "
                    f"({currentTypelistNumberOfSlices}) must be larger than 0 '{line}'"
                )
            elif currentTypelistNumberOfSlices > 99:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Too large number of slices "
                    f"({currentTypelistNumberOfSlices}) '{line}'"
                )
            currentTypelistCommentLine = lineNumber
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO FIRST SLICE BEGIN":
            if intoFirstSliceStart != 0 or intoLastSliceStart != 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: INTO FIRST/LAST SLICE blocks cannot be nested "
                    f"'{line}'"
                )
            intoFirstSliceStart = lineNumber + 1
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO FIRST SLICE END":
            if intoLastSliceStart != 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: INTO LAST SLICE BEGIN ends with FIRST?? '{line}'"
                )
            if intoFirstSliceStart == 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: There is no open INTO FIRST SLICE BEGIN block "
                    f"'{line}'"
                )

            intoFirstSliceBlocks.append(CodeBlockInterval(intoFirstSliceStart, lineNumber))
            intoFirstSliceStart = 0
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO LAST SLICE BEGIN":
            if intoFirstSliceStart != 0 or intoLastSliceStart != 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: INTO FIRST/LAST SLICE blocks cannot be nested "
                    f"'{line}'"
                )
            intoLastSliceStart = lineNumber + 1
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO LAST SLICE END":
            if intoFirstSliceStart != 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: INTO FIRST SLICE BEGIN ends with LAST?? '{line}'"
                )
            if intoLastSliceStart == 0:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: There is no open INTO LAST SLICE BEGIN block "
                    f"'{line}'"
                )

            intoLastSliceBlocks.append(CodeBlockInterval(intoLastSliceStart, lineNumber))
            intoLastSliceStart = 0
        elif parsed.startswith(MY_CONTROL_COMMENT_PREFIX):
            raise ParseError(
                f"{xtCppName}:{lineNumber}: Unknown control comment in test case '{line}'"
            )
        elif f"{MY_CONTROL_COMMENT_PREFIX}INTO FIRST SLICE" in parsed:
            intoFirstSliceBlocks.append(CodeBlockInterval(lineNumber))

        elif f"{MY_CONTROL_COMMENT_PREFIX}INTO LAST SLICE" in parsed:
            intoLastSliceBlocks.append(CodeBlockInterval(lineNumber))

    if (
        topCodeSlicing is None
        and topTypelistSlicing is None
        and (intoFirstSliceBlocks or intoLastSliceBlocks)
    ):
        raise ParseError(
            f"{xtCppName}:{testcaseBlock.startLine}: There are INTO LAST/FIRST SLICE comments "
            f"present, but test-case {testcaseNumber} has no slices"
        )

    return _TestcaseParseResult(
        testcaseNumber,
        testcaseBlock,
        topTypelistSlicing,
        topCodeSlicing,
        intoFirstSliceBlocks,
        intoLastSliceBlocks,
    )


def _parseTestcases(
    xtCppName: str,
    offset: int,
    casesLines: Sequence[str],
    resolveTypelist=Callable[[str], Sequence[str]],
) -> Sequence[_TestcaseParseResult]:
    """Find all test cases from 'case +/-N: { to } break;"""

    @dataclass
    class _TempParsedTestcase:
        testcaseNumber: int
        block: CodeBlockInterval

    testcaseBlocks: Sequence[_TempParsedTestcase] = []

    startOffset = offset
    theLines = casesLines

    while casesLines:
        # Skip empty lines
        while not casesLines[0].strip():
            casesLines = casesLines[1:]
            offset += 1
            if not casesLines:
                break
        if not casesLines:
            break

        if not casesLines[0].startswith("      case ") or not re.fullmatch(
            r"      case -?[1-9]?[0-9]: {", casesLines[0]
        ):
            raise ParseError(
                f"{xtCppName}:{offset}: Expected a 'case +/-N:' line, found '{casesLines[0]}'"
            )

        num = removeprefix(casesLines[0], "      case ").split(":", maxsplit=1)[0].strip()

        if not _isTestcaseInt(num):
            raise ParseError(f"{xtCppName}: Not a number '{num}' in '{casesLines[0]}'")

        num = int(num)
        if num == 0 or abs(num) > 99:
            raise ParseError(
                f"{xtCppName}:{offset}: Testcase number is out of range {num} in '{casesLines[0]}'"
            )

        tcStart = offset

        casesLines = casesLines[1:]
        offset += 1
        while not casesLines[0].startswith("      } break;"):
            if casesLines[0].startswith("      case "):
                raise ParseError(
                    f"{xtCppName}:{offset}: Unexpected 'case' line in test case {num} in "
                    f"'{casesLines[0]}'"
                )
            casesLines = casesLines[1:]
            offset += 1

        testcaseBlocks.append(_TempParsedTestcase(num, CodeBlockInterval(tcStart + 1, offset + 2)))

        casesLines = casesLines[1:]
        offset += 1

    parsedTestcases = [
        _parseOneTestcase(
            xtCppName,
            tmpParsed.testcaseNumber,
            tmpParsed.block,
            theLines[
                tmpParsed.block.startIndex - startOffset : tmpParsed.block.stopIndex - startOffset
            ],
            resolveTypelist,
        )
        for tmpParsed in testcaseBlocks
    ]

    return parsedTestcases


def _convertTestcaseParseResults(
    xtCppName: str, parseResults: Sequence[_TestcaseParseResult]
) -> Sequence[Testcase]:
    rv: Sequence[Testcase] = []
    for testcaseParseResult in parseResults:

        # No slicing on this test case
        if (
            testcaseParseResult.codeSlicing is None
            and testcaseParseResult.typelistParseResult is None
        ):
            assert not testcaseParseResult.intoFirstSliceBlocks
            assert not testcaseParseResult.intoLastSliceBlocks

            rv.append(
                UnslicedTestcase(testcaseParseResult.testcaseNumber, testcaseParseResult.block)
            )

        # Just one top type-list slicing
        elif (
            testcaseParseResult.codeSlicing is None
            and testcaseParseResult.typelistParseResult is not None
        ):
            rv.append(
                TypelistSlicedTestcase(
                    testcaseParseResult.testcaseNumber,
                    testcaseParseResult.block,
                    testcaseParseResult.intoFirstSliceBlocks,
                    testcaseParseResult.intoLastSliceBlocks,
                    TypelistSlicing(
                        testcaseParseResult.typelistParseResult.controlCommentBlock,
                        testcaseParseResult.typelistParseResult.originalMacroBlock,
                        testcaseParseResult.typelistParseResult.macroName,
                        testcaseParseResult.typelistParseResult.makeSlicedTypelist(xtCppName),
                    ),
                )
            )

        # Just code-slicing on top level
        elif (
            testcaseParseResult.codeSlicing is not None
            and testcaseParseResult.typelistParseResult is None
        ):
            rv.append(
                CodeSlicedTestcase(
                    testcaseParseResult.testcaseNumber,
                    testcaseParseResult.block,
                    testcaseParseResult.intoFirstSliceBlocks,
                    testcaseParseResult.intoLastSliceBlocks,
                    testcaseParseResult.codeSlicing,
                )
            )

        else:
            assert (
                False
            ), "Internal error.  This should never happen.  Really, look at the if-elif above."

    return rv


def _parseTestcaseRange(
    xtCppName: str,
    lineNumber: int,
    spec: str,
    testcaseNumberSet: Set[int] | Mapping[int, int],
    *,
    allowTheWordEnd: bool = False,
) -> Tuple[int, int]:
    if spec.count("..") > 1:
        f"{xtCppName}:{lineNumber}: Syntax error in '{spec}' in  too many '..'"

    start, stop = spec.split("..")
    start = start.strip()
    stop = stop.strip()
    if not start or not stop:
        raise ParseError(f"{xtCppName}:{lineNumber}: Syntax error in '{spec}'")

    if not _isTestcaseInt(start):
        raise ParseError(f"{xtCppName}:{lineNumber}: Not a number '{start}' in '{spec}'")

    start = int(start)
    if start == 0 or abs(start) > 99:
        raise ParseError(f"{xtCppName}:{lineNumber}: Invalid test case number {start} in '{spec}'")

    if start not in testcaseNumberSet:
        raise ParseError(
            f"{xtCppName}:{lineNumber}: Testcase number {start} in '{spec}' does not "
            f"exist.  Available numbers are: {testcaseNumberSet}"
        )

    if allowTheWordEnd and stop == "END":
        stop = 100 if start > 0 else -100
    else:
        if not _isTestcaseInt(stop):
            raise ParseError(f"{xtCppName}:{lineNumber}: Not a number '{stop}' in '{spec}'")
        stop = int(stop)
        if stop == 0 or abs(stop) > 99:
            raise ParseError(
                f"{xtCppName}:{lineNumber}: Invalid test case number {stop} in '{spec}'"
            )

        if stop not in testcaseNumberSet:
            raise ParseError(
                f"{xtCppName}:{lineNumber}: Testcase number {stop} in '{spec}' does not "
                f"exist.  Available numbers are: {testcaseNumberSet}"
            )

    return start, stop


def _parseBlockCondition(
    xtCppName: str,
    lineNumber: int,
    condition: str,
    testcaseNumberSet: Set[int],
    sliceNameMap: Mapping[int, Mapping[str, int]],
) -> Set[OriginalTestcase]:

    rv: MutableSet[OriginalTestcase] = set()
    testCaseSpecs: Iterable[str] = (spec.strip() for spec in condition.split(","))
    for spec in testCaseSpecs:
        if ".." in spec:
            start, stop = _parseTestcaseRange(xtCppName, lineNumber, spec, testcaseNumberSet)
            if start > 0:
                numbersInRange = [
                    caseNumber for caseNumber in testcaseNumberSet if start <= caseNumber <= stop
                ]
            else:
                numbersInRange = [
                    caseNumber for caseNumber in testcaseNumberSet if start >= caseNumber >= stop
                ]

            if len(numbersInRange) < 2:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: '{spec}' range results in too few testcases "
                    f"{numbersInRange}"
                )

            # NOTE This algorithm allows "holes" in the range
            rv.update(OriginalTestcase(num, None) for num in numbersInRange)
        elif "." in spec:
            if spec.count(".") > 1:
                f"{xtCppName}:{lineNumber}: Syntax error in '{spec}' in  too many '.'"
            caseNumStr, sliceName = spec.split(".")
            caseNumStr = caseNumStr.strip()
            sliceName = sliceName.strip()
            if not caseNumStr or not sliceName:
                raise ParseError(f"{xtCppName}:{lineNumber}: Syntax error in '{spec}'")

            if not _isTestcaseInt(caseNumStr):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Not a number '{caseNumStr}' in '{spec}'"
                )
            caseNum = int(caseNumStr)
            if caseNum == 0 or abs(caseNum) > 99:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Invalid test case number {caseNum} in '{spec}'"
                )

            if caseNum not in testcaseNumberSet:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Testcase number {caseNum} in '{spec}' does not "
                    f"exist.  Available numbers are: {testcaseNumberSet}"
                )

            if sliceName not in sliceNameMap[caseNum]:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Not a slice name '{sliceName}' in '{spec}'.  "
                    f"Available names are {sliceNameMap[caseNum]}"
                )
            sliceNum = sliceNameMap[caseNum][sliceName]
            rv.add(OriginalTestcase(caseNum, sliceNum))

        else:
            if not _isTestcaseInt(spec):
                raise ParseError(f"{xtCppName}:{lineNumber}: Not a number '{spec}'")
            caseNum = int(spec)
            if caseNum == 0 or abs(caseNum) > 99:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Invalid test case number {caseNum} in '{spec}'"
                )

            if caseNum not in testcaseNumberSet:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: Testcase number {caseNum} does not exit.  "
                    f"Available numbers are {testcaseNumberSet}"
                )
            rv.add(OriginalTestcase(caseNum, None))

    if not rv:
        raise ParseError(
            f"{xtCppName}:{lineNumber}: Syntax error, no test cases in specification: "
            f"'{condition}'"
        )

    return rv


@dataclass
class _OpenConditionalBlock:
    startLineNumber: int
    conditionAsWritten: str
    compiledCondition: Set[OriginalTestcase]


_MY_FOR_PREFIX = f"{MY_CONTROL_COMMENT_PREFIX}FOR "


def _parseConditionalBlocks(
    xtCppName: str,
    lines: Sequence[str],
    testcaseNumberSet: Set[int],
    sliceNameMap: Mapping[int, Mapping[str, int]],
) -> ConditionalCommonCodeBlocks:
    rv: MutableSequence[ConditionalCommonCodeBlock] = []

    openBlocks: MutableSequence[_OpenConditionalBlock] = []

    for lineNumber, line in enumerate(lines, 1):
        if line.startswith(_MY_FOR_PREFIX):

            if not (line.endswith(" BEGIN") or line.endswith(" END")):
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: FOR command must end with BEGIN or END '{line}'"
                )

            parsed = removeprefix(line, _MY_FOR_PREFIX).lstrip()
            subCommand = "BEGIN" if parsed.endswith(" BEGIN") else "END"
            parsed = removesuffix(parsed, subCommand).rstrip()
            if subCommand == "BEGIN":
                condition = _parseBlockCondition(
                    xtCppName, lineNumber, parsed, testcaseNumberSet, sliceNameMap
                )
                openBlocks.append(_OpenConditionalBlock(lineNumber, parsed, condition))
            else:
                lastOpenBlock = openBlocks.pop()
                if lastOpenBlock.conditionAsWritten != parsed:
                    raise ParseError(
                        f"{xtCppName}:{lineNumber}: FOR cond END command *must* use the exact "
                        "same condition string as the the FOR cond BEGIN command on line "
                        f"{lastOpenBlock.startLineNumber} did.  "
                        f"BEGIN: '{lastOpenBlock.conditionAsWritten}' != END: '{parsed}'"
                    )
                rv.append(
                    ConditionalCommonCodeBlock(
                        lastOpenBlock.compiledCondition,
                        lastOpenBlock.conditionAsWritten,
                        CodeBlockInterval(lastOpenBlock.startLineNumber, lineNumber + 1),
                    )
                )
        elif _MY_FOR_PREFIX in line:
            parsed = line[line.index(_MY_FOR_PREFIX) + len(_MY_FOR_PREFIX) :].lstrip()
            if not parsed:
                raise ParseError(
                    f"{xtCppName}:{lineNumber}: FOR condition (test case / slice list) is "
                    f"missing: '{line}'"
                )
            condition = _parseBlockCondition(
                xtCppName, lineNumber, parsed, testcaseNumberSet, sliceNameMap
            )
            rv.append(
                ConditionalCommonCodeBlock(
                    condition, parsed, CodeBlockInterval(lineNumber, lineNumber + 1)
                )
            )

    if openBlocks:
        openConditionalBlocksList = "\n".join(
            [
                f"    {xtCppName}:{block.startLineNumber}: {lines[block.startLineNumber-1]}"
                for block in openBlocks
            ]
        )
        raise ParseError(
            f"{xtCppName}: The following conditional blocks have no END:\n"
            f"{openConditionalBlocksList}"
        )

    return ConditionalCommonCodeBlocks(rv)


_MY_PARTS_DEFINITION_HEADING = f"{MY_CONTROL_COMMENT_PREFIX}PARTS (syntax version 1.0.0)"


def _parsePartsDefinitionTable(
    xtCppName: str, lines: Sequence[str], testcaseToNumSlices: MutableMapping[int, int]
) -> Sequence[Sequence[OriginalTestcase]]:
    try:
        idx = lines.index(_MY_PARTS_DEFINITION_HEADING)
    except ValueError:
        raise ParseError(f"{xtCppName}: Cannot find PARTS definition") from None

    partDefinitions: MutableSequence[MutableSequence[OriginalTestcase]] = []

    unslicedCases = [
        caseNumber for caseNumber, numSlices in testcaseToNumSlices.items() if numSlices == 1
    ]

    idx += 1
    while idx < len(lines) and lines[idx].startswith("//@"):
        line = removeprefix(lines[idx], "//@").lstrip()
        if not line or line[0] == "#":
            idx += 1
            continue  # !!! CONTINUE !!!

        _PART_LINE_PREFIX = "CASES: "
        if not line.startswith(_PART_LINE_PREFIX):
            raise ParseError(
                f"{xtCppName}:{idx+1}: PARTS definition lines must start with "
                f"'{_PART_LINE_PREFIX}' '{line}'"
            )

        partDefinitions.append([])

        line = removeprefix(line, _PART_LINE_PREFIX).lstrip()
        contentDefinitions = (elem.strip() for elem in line.split(","))
        for contentDef in contentDefinitions:
            if ".." in contentDef:
                start, stop = _parseTestcaseRange(
                    xtCppName, idx + 1, contentDef, testcaseToNumSlices, allowTheWordEnd=True
                )

                if start > 0:
                    numbersInRange = [
                        caseNumber
                        for caseNumber in testcaseToNumSlices.keys()
                        if start <= caseNumber <= stop
                    ]
                else:
                    numbersInRange = [
                        caseNumber
                        for caseNumber in testcaseToNumSlices.keys()
                        if start >= caseNumber >= stop
                    ]

                slicedCases = [
                    caseNumber
                    for caseNumber in numbersInRange
                    if testcaseToNumSlices[caseNumber] > 1
                ]

                if slicedCases:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: '{contentDef}' the following sliced cases would "
                        f"fall into the range {slicedCases}.  Sliced test cases cannot be part "
                        "of a range, they have to be added using the caseNumber.SLICES form to "
                        "create a part for each slice."
                    )

                if len(numbersInRange) < 2:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: '{contentDef}' range results in too few testcases "
                        f"{numbersInRange}"
                    )

                # NOTE This algorithm allows "holes" in the range
                for num in numbersInRange:
                    partDefinitions[-1].append(OriginalTestcase(num, None))
                    testcaseToNumSlices.pop(num)
                    unslicedCases.remove(num)
            elif "." in contentDef:
                numStr, tail = contentDef.split(".")
                if tail != "SLICES":
                    if tail == "END":
                        raise ParseError(
                            f"{xtCppName}:{idx+1}: Use '{numStr}..END' not '.END'.  Single '.' is "
                            f"for test case slices only: '{contentDef}'"
                        )
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Expected '{numStr}.SLICES' in '{contentDef}'"
                    )
                if not _isTestcaseInt(numStr):
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Not a number '{numStr}' in '{contentDef}'"
                    )
                num = int(numStr)
                if num == 0 or abs(num) > 99:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Invalid test case number {num} in '{line}'"
                    )

                if num not in testcaseToNumSlices:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Testcase number {num} in '{contentDef}' is not "
                        f"available.  Available numbers are {unslicedCases}"
                    )
                if num in unslicedCases:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Testcase {num} in '{contentDef}' is not sliced, do "
                        f"not use the 'caseNumber.SLICES' form."
                    )
                for sliceNumber in range(1, testcaseToNumSlices[num]):
                    partDefinitions[-1].append(OriginalTestcase(num, sliceNumber))
                    partDefinitions.append([])

                partDefinitions[-1].append(OriginalTestcase(num, testcaseToNumSlices[num]))
                testcaseToNumSlices.pop(num)

            else:
                if not _isTestcaseInt(contentDef):
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Not a number '{contentDef}' in '{line}'"
                    )
                num = int(contentDef)
                if num == 0 or abs(num) > 99:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Invalid test case number {num} in '{line}'"
                    )

                if num not in testcaseToNumSlices:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Testcase number {num} in '{contentDef}' is not "
                        f"available.  Available numbers are {unslicedCases}"
                    )
                if num not in unslicedCases:
                    raise ParseError(
                        f"{xtCppName}:{idx+1}: Testcase {num} in '{contentDef}' is sliced with "
                        f"{testcaseToNumSlices[num]} slices.  Sliced test cases have to be added "
                        f"using the caseNumber.SLICES form to create a part for each slice.  "
                        f"Available not-sliced test case numbers are {unslicedCases}"
                    )

                partDefinitions[-1].append(OriginalTestcase(num, None))
                testcaseToNumSlices.pop(num)
                unslicedCases.remove(num)

        if not partDefinitions[-1]:
            raise ParseError(
                f"{xtCppName}:{idx+1}: Syntax error, no test cases in part "
                f"#{len(partDefinitions)}: '{line}'"
            )

        idx += 1

    if not partDefinitions:
        raise ParseError(
            f"{xtCppName}:{idx+1}: Syntax error, no part definitions found in PARTS descriptor."
        )
    if testcaseToNumSlices:
        raise ParseError(
            f"{xtCppName}:{idx+1}: Not all test cases have been assigned to a part, remaining are "
            f"{testcaseToNumSlices.keys()}"
        )
    return partDefinitions


def parse(
    xtCppFull: Path,
    xtCppName: str,
    qualifiedComponentName: str,
    lines: Sequence[str],
    groupsDirs: Tuple[Path, ...],
) -> ParseResult | None:
    # Verify file starts with prologue comment line with name and language
    prologueReStr = f"// {qualifiedComponentName}" + r"\.(?:t|xt)\.cpp +-\*-C\+\+-\*-"
    prologueMatch = re.fullmatch(prologueReStr, lines[0])
    if not prologueMatch:
        raise ParseError(
            f"{xtCppName}:1: The source does not start with the expected prologue comment line, "
            f"but with '{lines[0]}'"
        )

    if qualifiedComponentName.endswith("_cpp03") and "// No C++03 Expansion" in lines:
        # There is no C++03 expansion, we do not need to generate split output for this file
        return None

    _verifySupportedControlComments(xtCppName, lines)

    mainBlock = _findMainBlock(xtCppName, lines)

    testPrintLineInfo = _findTestPrintLine(
        xtCppName, mainBlock.startIndex, lines[mainBlock.startIndex : mainBlock.stopIndex]
    )

    def resolveTypelist(theListMacroValue: str):
        return resolveTypelistMacroValue(theListMacroValue, xtCppFull, groupsDirs)

    testCasesOnly = _extractTestSwitchCaseLines(
        xtCppName, mainBlock.startIndex, lines[mainBlock.startIndex : mainBlock.stopIndex]
    )
    testcaseParseResults = _parseTestcases(
        xtCppName, testCasesOnly.offset, testCasesOnly.lines, resolveTypelist
    )
    del testCasesOnly, mainBlock

    sliceNameMap = _createSliceNameMap(testcaseParseResults)
    testcaseNumberSet = set(parseResult.testcaseNumber for parseResult in testcaseParseResults)

    testcases = _convertTestcaseParseResults(xtCppName, testcaseParseResults)
    _verifyFoundPositiveTestCases(xtCppName, testcaseParseResults)

    testcaseToNumSlices: MutableMapping[int, int] = {tc.number: tc.numSlices for tc in testcases}
    condBlocks = _parseConditionalBlocks(xtCppName, lines, testcaseNumberSet, sliceNameMap)
    if not qualifiedComponentName.endswith("_cpp03"):
        simCpp11 = _parseSimCpp11Include(xtCppName, qualifiedComponentName, lines)
    else:
        simCpp11 = _parseSimCpp11Cpp03(xtCppName, qualifiedComponentName, lines)

    parts = _parsePartsDefinitionTable(xtCppName, lines, testcaseToNumSlices)
    if len(parts) > 99:
        raise ParseError(f"There are more than 99 parts! N={len(parts)}", parts)

    return ParseResult(
        _getLineDirectivesControl(xtCppName, lines),
        _getSilencedWarnings(xtCppName, lines),
        simCpp11,
        parts,
        condBlocks,
        testPrintLineInfo,
        testcases,
    )
