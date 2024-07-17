from __future__ import annotations

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
    SilencedWarningKind,
    SimCpp11Cpp03LinesToUpdate,
    SimCpp11IncludeConstruct,
    Testcase,
    TestPrintLineInfo,
    UnslicedTestcase,
    TopCodeSlicedTestcase,
    TypelistSlicedTestcase,
    MultipliedSlicesTestcase,
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

    def makeSlicedTypelist(self, fn: str) -> Sequence[Sequence[str]]:
        numTypes = len(self.typelist)
        sliceSize = numTypes // self.numSlices
        if sliceSize < 1:
            raise ParseError(
                f"{fn!r}:{self.controlCommentBlock}: Too large number of slices "
                f"({self.numSlices}), length of the type list is {numTypes}"
            )
        remainder = numTypes - (sliceSize * self.numSlices)
        slicedTypelist: Sequence[Sequence[str]] = []
        start: int = 0
        while start < len(self.typelist):
            numInSlice = sliceSize + 1 if remainder > 0 else sliceSize
            remainder -= 1
            slicedTypelist.append(self.typelist[start : start + numInSlice])
            start += numInSlice

        return slicedTypelist


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


def _createSliceNameMap(
    parseResults: Sequence[_TestcaseParseResult],
) -> Mapping[int, Mapping[str, int]]:
    rv: MutableMapping[int, Mapping[str, int]] = {}
    for parseResult in parseResults:
        if parseResult.codeSlicing is None:
            rv[parseResult.testcaseNumber] = {}
        else:
            rv[parseResult.testcaseNumber] = parseResult.codeSlicing.createSliceNameMap()
    return rv


_MY_SIMCPP11_IF_RE = re.compile(r"\s*#\s*if\s+BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES")


def _parseSimCpp11Include(
    fn: str, qualifiedComponentName: str, lines: Sequence[str]
) -> SimCpp11IncludeConstruct | None:
    idx = next((idx for idx, line in enumerate(lines) if re.match(_MY_SIMCPP11_IF_RE, line)), None)
    if idx is None:
        return None  # !!! RETURN !!!
    ifDefLine = idx + 1

    defineRe = rf"\s*#\s*define\s+COMPILING_{qualifiedComponentName.upper()}_X?T_CPP"
    idx = next(
        (idx for idx, line in enumerate(lines[ifDefLine:]) if re.match(defineRe, line)), None
    )
    if idx is None:
        raise ParseError(
            f"{fn!r}:{ifDefLine}: Cannot find "
            f"`#define COMPILING_{qualifiedComponentName.upper()}_XT_CPP`"
        )
    defineLine = ifDefLine + idx + 1

    includeRe = rf"\s*#\s*include\s+<{qualifiedComponentName.lower()}_cpp03.xt.cpp>"
    idx = next(
        (idx for idx, line in enumerate(lines[defineLine:]) if re.match(includeRe, line)), None
    )
    if idx is None:
        raise ParseError(
            f"{fn!r}:{defineLine}: Cannot find "
            f"`#include <{qualifiedComponentName.lower()}_cpp03.xt.cpp>`"
        )
    includeLine = defineLine + idx + 1

    undefRe = rf"\s*#\s*undef\s+COMPILING_{qualifiedComponentName.upper()}_X?T_CPP"
    idx = next(
        (idx for idx, line in enumerate(lines[includeLine:]) if re.match(undefRe, line)), None
    )
    if idx is None:
        raise ParseError(
            f"{fn!r}:{includeLine}: Cannot find "
            f"`#undef COMPILING_{qualifiedComponentName.upper()}_XT_CPP`"
        )
    undefLine = includeLine + idx + 1

    elseLine = undefLine + 1

    if len(lines) < elseLine:
        raise ParseError(f"{fn!r}:{undefLine}: Premature end of file, expected `#else`")
    if not re.match(r"\s*#\s*else", lines[elseLine - 1]):
        raise ParseError(f"{fn!r}:{idx + 2}: Expected `#else`, found {lines[elseLine - 1]!r}")

    return SimCpp11IncludeConstruct(
        CodeBlockInterval(ifDefLine, elseLine + 1), defineLine, includeLine, undefLine
    )


def _parseSimCpp11Cpp03(
    fn: str, qualifiedComponentName: str, lines: Sequence[str]
) -> SimCpp11Cpp03LinesToUpdate:
    assert qualifiedComponentName.endswith("_cpp03")

    qualifiedComponentName = removesuffix(qualifiedComponentName, "_cpp03")

    ifdefLineContent = f"#ifdef COMPILING_{qualifiedComponentName.upper()}_XT_CPP"
    idx = next((idx for idx, line in enumerate(lines) if line.strip() == ifdefLineContent), None)
    if idx is None:
        raise ParseError(f"{fn!r}: Cannot find {ifdefLineContent!r} in _cpp03 file")
    ifDefLine = idx + 1

    elseLineContent = f"#else // if ! defined(COMPILING_{qualifiedComponentName.upper()}_XT_CPP)"
    idx = next(
        (idx for idx, line in enumerate(lines[ifDefLine:]) if line.strip() == elseLineContent),
        None,
    )
    if idx is None:
        raise ParseError(f"{fn!r}: Cannot find {elseLineContent!r} in _cpp03 file")
    elseLine = ifDefLine + idx + 1

    endifLineContent = f"#endif // defined(COMPILING_{qualifiedComponentName.upper()}_XT_CPP)"
    idx = next(
        (idx for idx, line in enumerate(lines[elseLine:]) if line.strip() == endifLineContent),
        None,
    )
    if idx is None:
        raise ParseError(f"{fn!r}: Cannot find {endifLineContent!r} in _cpp03 file")
    endifLine = elseLine + idx + 1

    invocationLines: MutableSequence[int] = []
    for lineNumber, line in enumerate(lines, 1):
        line = line.strip()
        if line.startswith("// Command line: sim_cpp11_features.pl ") and line.endswith(".xt.cpp"):
            invocationLines.append(lineNumber)

    return SimCpp11Cpp03LinesToUpdate(ifDefLine, elseLine, endifLine, invocationLines)


def _verifySupportedControlComments(fn: str, lines: Sequence[str]) -> None:
    for lineNumber, line in enumerate(lines, 1):
        if theComment := getUnsupportedControlCommentFrom(line):
            raise ParseError(f"{fn}:{lineNumber}: Unsupported control comment: {theComment!r}")


_MY_LINE_DIRECTIVES_PREFIX = MY_CONTROL_COMMENT_PREFIX + "LINE DIRECTIVES: "


def _getLineDirectivesControl(fn: str, lines: Sequence[str]) -> bool | None:
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
                    f"{fn}:{lineNumber}: LINE DIRECTIVES setting must be ON or OFF, not "
                    f"{setting!r} in {line!r}"
                )
    return None


_MY_SILENCED_WARNINGS_PREFIX = MY_CONTROL_COMMENT_PREFIX + "SILENCE WARNINGS: "


def _getSilencedWarnings(fn: str, lines: Sequence[str]) -> Set[SilencedWarningKind]:
    rv: MutableSet[SilencedWarningKind] = set()
    for lineNumber, line in enumerate(lines, 1):
        line = line.strip()
        if line.startswith(_MY_SILENCED_WARNINGS_PREFIX):
            warnings = removeprefix(line, _MY_SILENCED_WARNINGS_PREFIX)
            warnings = (warning.strip() for warning in warnings.split(","))
            for warning in warnings:
                if warning not in SET_OF_SUPPORTED_SILENCED_WARNINGS:
                    raise ParseError(
                        f"{fn}:{lineNumber}: Unknown warning name: {warning!r} in {line!r}"
                    )
                assert warning in SET_OF_SUPPORTED_SILENCED_WARNINGS
                rv.add(warning)  # type: ignore
    return rv


def _isTestcaseInt(txt: str) -> bool:
    return txt.isdigit() or (txt.startswith("-") and txt[1:].isdigit())


def _isSliceNumInt(txt: str) -> bool:
    return txt.isdigit()


def _verifyFoundPositiveTestCases(
    fn: str, testcasesNumbers: Iterable[_TestcaseParseResult]
) -> None:
    positiveTestcaseNumbers = sorted(
        [pr.testcaseNumber for pr in testcasesNumbers if pr.testcaseNumber > 0]
    )
    if not positiveTestcaseNumbers:
        raise ParseError(f"{fn!r}: Unable to find any test cases in 'main'")

    allCases = list(range(1, positiveTestcaseNumbers[-1] + 1))
    for testcaseNumber in positiveTestcaseNumbers:
        if testcaseNumber not in allCases:
            raise ParseError(f"{fn!r}: Duplicate test-case number {testcaseNumber}")
        allCases.remove(testcaseNumber)

    if allCases:
        raise ParseError(f"{fn!r}: There are missing test-case numbers {allCases}")


def _findMainStart(fn: str, lines: Sequence[str]) -> int:
    """Find 'int main(int argc, char *argv[])', ensure there is only one, other sanity checks."""

    try:
        idx = lines.index("int main(int argc, char *argv[])")
    except ValueError:
        raise ParseError(f"{fn!r}: Could not find definition 'int main(int argc, char *argv[])'")

    try:
        idx2 = lines[idx + 1 :].index("int main(int argc, char *argv[])")
        raise ParseError(
            f"{fn!r}:{idx+idx2+2}: Found a second 'int main(int argc, char *argv[])')"
        )
    except ValueError:
        pass

    return idx


def _reverseEnumerate(seq: Sequence) -> Generator:
    for i in range(len(seq) - 1, -1, -1):
        yield (i, seq[i])


def _findMainEnd(fn: str, offset: int, fromMainLines: Sequence[str]) -> int:
    """Find main closing brace, ensure there is only one, other sanity checks."""

    additionalOffset: int = 0
    found = ""

    # Find the real end of main
    while True:
        try:
            idx = fromMainLines.index("}")
            found += f"\nFOUND: {idx=}, {offset=}, {offset+additionalOffset+idx=}"
        except ValueError:
            raise ParseError(f"{fn!r}:{offset}: Could not find closing brace for 'main'")

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

    idx2 = -1
    try:
        idx2 = fromMainLines[idx + 1 :].index("}")
    except ValueError:
        pass

    if idx2 != -1:
        raise ParseError(
            f"{fn!r}:{offset + idx + 1}: Found a second closing brace for 'main' on line "
            f"{offset + idx  + idx2 + 1}"
        )

    return additionalOffset + idx


def _findMainBlock(fn: str, lines: Sequence[str]) -> Tuple[int, CodeBlockInterval]:
    """Find main function plus some sanity checks."""
    start = _findMainStart(fn, lines)
    return start, CodeBlockInterval(
        start + 1, start + 1 + _findMainEnd(fn, start + 1, lines[start + 1 :]) + 2
    )


_PRINTF_TEST_PRINT_RE = re.compile(
    r'    (?:std::)?printf\s*\(\s*"TEST "\s+__FILE__\s*" CASE %d\\n"\s*,\s*test\);\s*'
)

_COUT_TEST_PRINT_RE = re.compile(
    r'    (?:std::)?cout\s*<<\s*"TEST "'
    r"(?:(?:\s*<<\s*__FILE__)|(?:\s+__FILE__))\s*(?:<<\s*)?"
    r'" CASE "\s*<<\s*test\s*<<\s*(?:(?:"\\n")|(?:(?:std::)?endl));\s*'
)


def _findTestPrintLine(fn: str, offset: int, mainLines: Sequence[str]) -> TestPrintLineInfo:
    for offset, line in enumerate(mainLines, offset):
        if not line.startswith("    "):  ## SKIP unindented lines
            continue  # !!! CONTINUE

        if '"TEST "' not in line or "__FILE__" not in line or "test" not in line:
            continue  # !!! CONTINUE

        if re.fullmatch(_PRINTF_TEST_PRINT_RE, line):
            return TestPrintLineInfo(offset + 1, "printf")

        if re.fullmatch(_COUT_TEST_PRINT_RE, line):
            return TestPrintLineInfo(offset + 1, "cout")

        if line.startswith("    switch (test)"):
            break

    raise ParseError(f"{fn}:{offset}: Could not find the printf or cout line for 'test'")


def _extractTestcasesOnlyBlock(
    fn: str, offset: int, mainLines: Sequence[str]
) -> Tuple[int, Sequence[str]]:
    """Get the part that only has the case +/-N: { ~~~ } break; elements"""

    try:
        idx = mainLines.index("    switch (test) { case 0:  // Zero is always the leading case.")
    except ValueError:
        try:
            idx = mainLines.index("    switch (test) { case 0:")
        except ValueError:
            raise ParseError(f"{fn!r}: Could not find 'switch(test) {{ case 0:' in 'main'")

    if len([line for line in mainLines if line.startswith("    switch (test) { case 0:")]) > 1:
        raise ParseError(f"{fn!r}: More than one 'switch(test) {{ case 0:' present in 'main'")

    try:
        idx2 = mainLines[idx + 1 :].index("      default: {")
    except ValueError:
        raise ParseError(f"{fn!r}:{offset  + idx + 2} Could not find 'default: {{' in 'main'")

    if mainLines[idx + 1 :].count("      default: {") != 1:
        raise ParseError(f"{fn!r}: More than one 'default: {{' present in 'main'")

    return offset + idx + 1, mainLines[idx + 1 : idx + idx2 + 1]


@dataclass
class _CodeSliceParsingState:
    name: str
    startLine: int
    sliceBlocks: MutableSequence[Tuple[str, CodeBlockInterval]]
    subSlices: MutableMapping[int, _TypelistParseResult | CodeSlicing]


_MACRO_NAME_RE = re.compile(r"(?:(?:u_)|[_A-Z])[_A-Z0-9][_A-Z0-9]+")


def _parseOneTestcase(
    fn: str,
    testcaseNumber: int,
    testcaseBlock: CodeBlockInterval,
    caseLines: Sequence[str],
    resolveTypelist=Callable[[str], Sequence[str]],
) -> _TestcaseParseResult:
    intoFirstSliceBlocks: MutableSequence[CodeBlockInterval] = []
    intoLastSliceBlocks: MutableSequence[CodeBlockInterval] = []

    topCodeSlicing: CodeSlicing | None = None

    codeSliceNamesToLine: MutableMapping[str, int] = {}

    codeSliceStack: MutableSequence[_CodeSliceParsingState] = []

    currentCodeSliceName: str = ""
    currentCodeSliceStart: int = 0
    currentCodeSliceBlocks: MutableSequence[Tuple[str, CodeBlockInterval]] = []
    currentCodeSliceNumberToSubSlice: MutableMapping[int, _TypelistParseResult | CodeSlicing] = {}

    def parseCodeSliceName(prefix: str) -> str:
        nonlocal parsed, fn, lineNumber, codeSliceNamesToLine

        maybeName = removeprefix(parsed, prefix).strip()
        if maybeName:
            if len(maybeName) < 2:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Code slice names must be at least 2 characters.  "
                    f"{maybeName!r}"
                )
            if not maybeName[0].isascii():
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Code slice names must start with an ASCII letter.  "
                    f"{maybeName!r}"
                )
            if not all(char == "_" or char.isascii() or char.isdigit() for char in maybeName[1:]):
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Invalid character in code slice name {maybeName!r}."
                    "  Allowed characters are ASCII letters and digits and underscore '_'."
                )
            if maybeName in codeSliceNamesToLine:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Code slice name {maybeName!r} is already in use on line"
                    f" {codeSliceNamesToLine[maybeName]}."
                )
            codeSliceNamesToLine[maybeName] = lineNumber

        return maybeName

    def beginCodeSlicing(sliceName: str, lineNumber: int) -> None:
        nonlocal codeSliceStack, currentCodeSliceName
        nonlocal currentCodeSliceStart, currentCodeSliceBlocks, currentCodeSliceNumberToSubSlice

        if topTypelistSlicing is not None and sliceName:
            raise ParseError(
                f"{fn!r}:{lineNumber}: Code slices cannot be named when a type list slicing "
                "is present on the same  level because the name would not map to a single "
                f"slice.  Please remove {sliceName!r}"
            )

        if currentCodeSliceStart:
            if len(currentCodeSliceBlocks) - 1 in currentCodeSliceNumberToSubSlice:
                raise ParseError(
                    f'{fn!r}:{lineNumber}: Only one code slicing per is supported at a "level" '
                    f"{line!r}.  Test cases may have only one top code slicing, and each code "
                    "slice may have only one code slicing or a typelist slicing in it."
                )
            codeSliceStack.append(
                _CodeSliceParsingState(
                    currentCodeSliceName,
                    currentCodeSliceStart,
                    currentCodeSliceBlocks,
                    currentCodeSliceNumberToSubSlice,
                )
            )

        currentCodeSliceName = sliceName
        currentCodeSliceStart = lineNumber
        currentCodeSliceBlocks = []
        currentCodeSliceNumberToSubSlice = {}

    def endCodeSlicing(lineNumber: int) -> None:
        nonlocal topCodeSlicing, currentCodeSliceName
        nonlocal currentCodeSliceStart, currentCodeSliceBlocks, currentCodeSliceNumberToSubSlice

        if currentCodeSliceStart == 0:
            raise ParseError(
                f"{fn!r}:{lineNumber}: CODE SLICING END outside of CODE SLICING BEGIN {line!r}"
            )
        if len(currentCodeSliceBlocks) == 0:
            raise ParseError(
                f"{fn!r}:{lineNumber}: CODE SLICING END after just one slice (no BREAK seen) "
                f"{line!r}"
            )

        currentCodeSliceBlocks.append(
            (
                currentCodeSliceName,
                CodeBlockInterval(currentCodeSliceBlocks[-1][1].stop - 1, lineNumber + 1),
            )
        )

        wholeBlock = CodeBlockInterval(currentCodeSliceBlocks[0][1].start, lineNumber + 1)
        slices: MutableSequence[CodeSlice] = []
        for sliceIndex, sliceTuple in enumerate(currentCodeSliceBlocks, 0):
            theSlice = CodeSlice(*sliceTuple)

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
                    subSliceState.makeSlicedTypelist(fn),
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
        currentCodeSliceName = outerState.name
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

    for lineNumber, line in enumerate(caseLines, testcaseBlock.start):
        parsed = line.strip()
        # Skip empty lines
        if not parsed:
            continue  # !!! CONTINUE

        if testcaseNumber < 0 and parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}"):
            raise ParseError(f"{fn!r}:{lineNumber}: Negative test cases cannot be sliced {line!r}")

        # While parsing a SLICE TYPELIST command, looking for the #define
        if currentTypelistNumberOfSlices != 0 and currentTypelistStart == 0:
            if parsed.startswith(MY_CONTROL_COMMENT_PREFIX):
                raise ParseError(
                    f"{fn!r}:{lineNumber}: No control comments allowed between the type-list "
                    f"macro definition and the SLICE TYPELIST comment {line!r}"
                )
            elif parsed.startswith("/*"):  ## Skip comments
                raise ParseError(
                    f"{fn!r}:{lineNumber}: No multi-line comments allowed between the type-list "
                    f"macro definition and the SLICE TYPELIST comment {line!r}"
                )
            elif parsed.startswith("//"):  ## Skip comments
                continue  # !!! CONTINUE
            elif not parsed.startswith("#"):
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Only line-comments allowed between the type-list "
                    f"macro definition and the SLICE TYPELIST comment {line!r}"
                )

            parsed = parsed[1:].lstrip()  # Drop the '#'
            if not parsed.startswith("define"):
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Expected #define after SLICE TYPELIST command {line!r}"
                )
            parsed = removeprefix(parsed, "define")
            if not parsed:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Premature end of line after #define {line!r}"
                )
            if parsed[0] not in " \t":
                raise ParseError(f"{fn!r}:{lineNumber}: No whitespace after #define {line!r}")

            parsed = parsed.lstrip()
            currentTypelistMacroName, parsed = parsed.split(" ", maxsplit=1)
            if not currentTypelistMacroName:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Could not parse macro name in #define {line!r}"
                )
            if not currentTypelistMacroName:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Could not parse macro name in #define {line!r}"
                )

            if not re.fullmatch(_MACRO_NAME_RE, currentTypelistMacroName):
                raise ParseError(
                    f"{fn!r}:{lineNumber}: {currentTypelistMacroName!r} does not appear to be a "
                    f"macro name in #define {line!r}"
                )

            currentTypelistStart = lineNumber

        if currentTypelistNumberOfSlices != 0 and currentTypelistStart != 0:
            currentTypelistMacroValue += parsed
            if not parsed.endswith("\\"):  # No line continuation
                typelist = resolveTypelist(currentTypelistMacroValue)
                if not typelist:
                    raise ParseError(
                        f"{fn!r}:{lineNumber}: {currentTypelistMacroName!r} results in an empty "
                        "type-list."
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
                    f'{fn!r}:{lineNumber}: Only one code slicing per is supported at a "level" '
                    f"{line!r}.  Test cases may have only one top code slicing, and each code "
                    "slice may have only one code slicing or a typelist slicing in it."
                )
            beginCodeSlicing(
                parseCodeSliceName(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BEGIN"), lineNumber
            )
        elif parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BREAK"):
            if currentCodeSliceStart == 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: SLICING BREAK outside of CODE SLICING BEGIN {line!r}"
                )

            if topTypelistSlicing is not None and currentCodeSliceName:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Code slices cannot be named when a type list slicing "
                    "is present on the same  level because the name would not map to a single "
                    f"slice.  Please remove {currentCodeSliceName!r}"
                )

            currentCodeSliceBlocks.append(
                (currentCodeSliceName, CodeBlockInterval(currentCodeSliceStart, lineNumber + 1))
            )
            currentCodeSliceStart = lineNumber
            currentCodeSliceName = parseCodeSliceName(
                f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING BREAK"
            )
        elif parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}CODE SLICING END"):
            endCodeSlicing(lineNumber)
        elif parsed.startswith(f"{MY_CONTROL_COMMENT_PREFIX}SLICING TYPELIST"):
            if 0 in currentCodeSliceNumberToSubSlice:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Multiple type-lists must be all be under separate "
                    "code slices. {line!r}"
                )
            # Get the number of slices
            parsed = removeprefix(parsed, f"{MY_CONTROL_COMMENT_PREFIX}SLICING TYPELIST").lstrip()
            if not parsed.startswith("/"):
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Missing '/' following SLICING TYPELIST {line!r}"
                )
            parsed = parsed[1:].lstrip()
            if not parsed.isdigit():
                raise ParseError(f"{fn!r}:{lineNumber}: Number of slices is not a number {line!r}")
            currentTypelistNumberOfSlices = int(parsed)
            if currentTypelistNumberOfSlices < 1:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Number of slices ({currentTypelistNumberOfSlices}) must be "
                    f"larger than 0 {line!r}"
                )
            elif currentTypelistNumberOfSlices > 89:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Too large number of slices ({currentTypelistNumberOfSlices}) "
                    f"{line!r}"
                )
            currentTypelistCommentLine = lineNumber
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO FIRST SLICE BEGIN":
            if intoFirstSliceStart != 0 or intoLastSliceStart != 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: INTO FIRST/LAST SLICE blocks cannot be nested {line!r}"
                )
            intoFirstSliceStart = lineNumber + 1
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO FIRST SLICE END":
            if intoLastSliceStart != 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: INTO LAST SLICE BEGIN ends with FIRST?? {line!r}"
                )
            if intoFirstSliceStart == 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: There is no open INTO FIRST SLICE BEGIN block {line!r}"
                )

            intoFirstSliceBlocks.append(CodeBlockInterval(intoFirstSliceStart, lineNumber))
            intoFirstSliceStart = 0
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO LAST SLICE BEGIN":
            if intoFirstSliceStart != 0 or intoLastSliceStart != 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: INTO FIRST/LAST SLICE blocks cannot be nested {line!r}"
                )
            intoLastSliceStart = lineNumber + 1
        elif parsed == f"{MY_CONTROL_COMMENT_PREFIX}INTO LAST SLICE END":
            if intoFirstSliceStart != 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: INTO FIRST SLICE BEGIN ends with LAST?? {line!r}"
                )
            if intoLastSliceStart == 0:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: There is no open INTO LAST SLICE BEGIN block {line!r}"
                )

            intoLastSliceBlocks.append(CodeBlockInterval(intoLastSliceStart, lineNumber))
            intoLastSliceStart = 0
        elif parsed.startswith(MY_CONTROL_COMMENT_PREFIX):
            raise ParseError(f"{fn!r}:{lineNumber}: Unknown control comment in test case {line!r}")
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
            f"{fn!r}:{testcaseBlock.start}: There are INTO LAST/FIRST SLICE comments present, but "
            f"test-case {testcaseNumber} has no slices"
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
    fn: str, offset: int, casesLines: Sequence[str], resolveTypelist=Callable[[str], Sequence[str]]
) -> Sequence[_TestcaseParseResult]:
    """Find all test cases from 'case +/-N: { to } break;"""
    tescaseBlocks: Sequence[Tuple[int, CodeBlockInterval]] = []

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
                f"{fn!r}:{offset}: Expected a 'case +/-N:' line, found {casesLines[0]!r}"
            )

        num = removeprefix(casesLines[0], "      case ").split(":", maxsplit=1)[0].strip()

        if not _isTestcaseInt(num):
            raise ParseError(f"{fn!r}: Unexpected number {num} in {casesLines[0]!r}")

        num = int(num)
        if num == 0 or abs(num) > 99:
            raise ParseError(
                f"{fn!r}:{offset}: Testcase number is out of range {num} in {casesLines[0]!r}"
            )

        tcStart = offset

        casesLines = casesLines[1:]
        offset += 1
        while not casesLines[0].startswith("      } break;"):
            if casesLines[0].startswith("      case "):
                raise ParseError(
                    f"{fn!r}:{offset}: Unexpected 'case' line in test case {num} in "
                    f"{casesLines[0]!r}"
                )
            casesLines = casesLines[1:]
            offset += 1

        tescaseBlocks.append((num, CodeBlockInterval(tcStart + 1, offset + 2)))

        casesLines = casesLines[1:]
        offset += 1

    parsedTestcases: Sequence[_TestcaseParseResult] = []
    casesLines = theLines
    for testcaseNumber, block in tescaseBlocks:
        parsedTestcases.append(
            _parseOneTestcase(
                fn,
                testcaseNumber,
                block,
                casesLines[block.start - startOffset - 1 : block.stop - startOffset - 1],
                resolveTypelist,
            )
        )
    return parsedTestcases


def _convertTestcaseParseResults(
    fn: str, parseResults: Sequence[_TestcaseParseResult]
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
                        testcaseParseResult.typelistParseResult.makeSlicedTypelist(fn),
                    ),
                )
            )

        # Just code-slicing on top level
        elif (
            testcaseParseResult.codeSlicing is not None
            and testcaseParseResult.typelistParseResult is None
        ):
            rv.append(
                TopCodeSlicedTestcase(
                    testcaseParseResult.testcaseNumber,
                    testcaseParseResult.block,
                    testcaseParseResult.intoFirstSliceBlocks,
                    testcaseParseResult.intoLastSliceBlocks,
                    testcaseParseResult.codeSlicing,
                )
            )

        # Most complex, has typelist slicing followed by code-slicing at the top level
        elif (
            testcaseParseResult.codeSlicing is not None
            and testcaseParseResult.typelistParseResult is not None
        ):
            rv.append(
                MultipliedSlicesTestcase(
                    testcaseParseResult.testcaseNumber,
                    testcaseParseResult.block,
                    testcaseParseResult.intoFirstSliceBlocks,
                    testcaseParseResult.intoLastSliceBlocks,
                    TypelistSlicing(
                        testcaseParseResult.typelistParseResult.controlCommentBlock,
                        testcaseParseResult.typelistParseResult.originalMacroBlock,
                        testcaseParseResult.typelistParseResult.macroName,
                        testcaseParseResult.typelistParseResult.makeSlicedTypelist(fn),
                    ),
                    testcaseParseResult.codeSlicing,
                )
            )
        else:
            assert (
                False
            ), "Internal error.  This should never happen.  Really, look at the if-elif above."

    return rv


def _parseBlockCondition(
    fn: str,
    lineNumber: int,
    condition: str,
    testcaseNumberSet: Set[int],
    sliceNameMap: Mapping[int, Mapping[str, int]],
) -> Set[int | Tuple[int, int]]:

    rv: MutableSet[int | Tuple[int, int]] = set()
    testCaseSpecs: Iterable[str] = (spec.strip() for spec in condition.split(","))
    for spec in testCaseSpecs:
        if ".." in spec:
            if spec.count("..") > 1:
                f"{fn!r}:{lineNumber}: Syntax error in {spec!r} in  too many '..'"
            start, stop = spec.split("..")
            start = start.strip()
            stop = stop.strip()
            if not start or not stop:
                raise ParseError(f"{fn!r}:{lineNumber}: Syntax error in {spec!r}")

            if not _isTestcaseInt(start):
                raise ParseError(f"{fn!r}:{lineNumber}: Not a number {start!r} in {spec!r}")
            start = int(start)
            if start == 0 or abs(start) > 99:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Invalid test case number {start} in {spec!r}"
                )

            if start not in testcaseNumberSet:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Testcase number {start} in {spec!r} does not exist.  "
                    f"Available numbers are: {testcaseNumberSet}"
                )

            if not _isTestcaseInt(stop):
                raise ParseError(f"{fn!r}:{lineNumber}: Not a number {stop!r} in {spec!r}")
            stop = int(stop)
            if stop == 0 or abs(stop) > 99:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Invalid test case number {stop} in {spec!r}"
                )

            if stop not in testcaseNumberSet:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Testcase number {stop} in {spec!r} does not exist.  "
                    f"Available numbers are: {testcaseNumberSet}"
                )

            if start > 0:
                numbersInRange = [
                    caseNumber
                    for caseNumber in testcaseNumberSet
                    if caseNumber >= start and caseNumber <= stop
                ]
            else:
                numbersInRange = [
                    caseNumber
                    for caseNumber in testcaseNumberSet
                    if caseNumber <= start and caseNumber >= stop
                ]

            if len(numbersInRange) < 2:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: {spec!r} range results in too few testcases "
                    f"{numbersInRange}"
                )

            # NOTE This algorithm allows "holes" in the range
            rv.update(numbersInRange)
        elif "." in spec:
            if spec.count(".") > 1:
                f"{fn!r}:{lineNumber}: Syntax error in {spec!r} in  too many '.'"
            caseNumStr, sliceName = spec.split(".")
            caseNumStr = caseNumStr.strip()
            sliceName = sliceName.strip()
            if not caseNumStr or not sliceName:
                raise ParseError(f"{fn!r}:{lineNumber}: Syntax error in {spec!r}")

            if not _isTestcaseInt(caseNumStr):
                raise ParseError(f"{fn!r}:{lineNumber}: Not a number {caseNumStr!r} in {spec!r}")
            caseNum = int(caseNumStr)
            if caseNum == 0 or abs(caseNum) > 99:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Invalid test case number {caseNum} in {spec!r}"
                )

            if caseNum not in testcaseNumberSet:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Testcase number {caseNum} in {spec!r} does not exist.  "
                    f"Available numbers are: {testcaseNumberSet}"
                )

            if sliceName not in sliceNameMap[caseNum]:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Not a slice name {sliceName!r} in {spec!r}.  "
                    f"Available names are {sliceNameMap[caseNum]}"
                )
            sliceNum = sliceNameMap[caseNum][sliceName]
            rv.add((caseNum, sliceNum))

        else:
            if not _isTestcaseInt(spec):
                raise ParseError(f"{fn!r}:{lineNumber}: Not a number {spec!r}")
            caseNum = int(spec)
            if caseNum == 0 or abs(caseNum) > 99:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Invalid test case number {caseNum} in {spec!r}"
                )

            if caseNum not in testcaseNumberSet:
                raise ParseError(
                    f"{fn!r}:{lineNumber}: Testcase number {caseNum} does not exit.  Available "
                    f"numbers are {testcaseNumberSet}"
                )
            rv.add(caseNum)

    if not rv:
        raise ParseError(
            f"{fn!r}:{lineNumber}: Syntax error, no test cases in specification: {condition!r}"
        )

    return rv


@dataclass
class _OpenConditionalBlock:
    startLineNumber: int
    conditionAsWritten: str
    compiledCondition: Set[int | Tuple[int, int]]


_MY_FOR_PREFIX = f"{MY_CONTROL_COMMENT_PREFIX}FOR "


def _parseConditionalBlocks(
    fn: str,
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
                    f"{fn}:{lineNumber}: FOR command must end with BEGIN or END {line!r}"
                )

            parsed = removeprefix(line, _MY_FOR_PREFIX).lstrip()
            subCommand = "BEGIN" if parsed.endswith(" BEGIN") else "END"
            parsed = removesuffix(parsed, subCommand).rstrip()
            if subCommand == "BEGIN":
                condition = _parseBlockCondition(
                    fn, lineNumber, parsed, testcaseNumberSet, sliceNameMap
                )
                openBlocks.append(_OpenConditionalBlock(lineNumber, parsed, condition))
            else:
                lastOpenBlock = openBlocks.pop()
                if lastOpenBlock.conditionAsWritten != parsed:
                    raise ParseError(
                        f"{fn}:{lineNumber}: FOR cond END command *must* use the exact same "
                        "condition string as the the FOR cond BEGIN command on line "
                        f"{lastOpenBlock.startLineNumber} did.  "
                        f"BEGIN: {lastOpenBlock.conditionAsWritten!r} != END: {parsed!r}"
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
                    f"{fn}:{lineNumber}: FOR condition (test case / slice list) is missing: "
                    f"{line!r}"
                )
            condition = _parseBlockCondition(
                fn, lineNumber, parsed, testcaseNumberSet, sliceNameMap
            )
            rv.append(
                ConditionalCommonCodeBlock(
                    condition, parsed, CodeBlockInterval(lineNumber, lineNumber + 1)
                )
            )

    if openBlocks:
        openConditionalBlocksList = "\n".join(
            [
                f"    {fn}:{block.startLineNumber}: {lines[block.startLineNumber-1]}"
                for block in openBlocks
            ]
        )
        raise ParseError(
            f"{fn}: The following conditional blocks have no END:\n" f"{openConditionalBlocksList}"
        )

    return ConditionalCommonCodeBlocks(rv)


_MY_PARTS_DEFINITION_HEADING = f"{MY_CONTROL_COMMENT_PREFIX}PARTS (syntax version 1.0.0)"


def _parsePartsDefinitionTable(
    fn: str, lines: Sequence[str], testcaseToNumSlices: MutableMapping[int, int]
) -> Sequence[Sequence[int | Tuple[int, int]]]:
    try:
        idx = lines.index(_MY_PARTS_DEFINITION_HEADING)
    except ValueError:
        raise ParseError(f"{fn!r}: Cannot find PARTS definition") from None

    partDefinitions: MutableSequence[MutableSequence[int | Tuple[int, int]]] = []

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
                f"{fn!r}:{idx+1}: PARTS definition lines must start with {_PART_LINE_PREFIX!r} "
                f"{line!r}"
            )

        partDefinitions.append([])

        line = removeprefix(line, _PART_LINE_PREFIX).lstrip()
        contentDefinitions = (elem.strip() for elem in line.split(","))
        for contentDef in contentDefinitions:
            if ".." in contentDef:
                if contentDef.count("..") > 1:
                    f"{fn!r}:{idx+1}: Syntax error in {contentDef!r} in {line!r}, too many '..'"
                startStopList = contentDef.split("..")
                if len(startStopList) != 2:
                    raise ParseError(f"{fn!r}:{idx+1}: Syntax error in {contentDef!r} in {line!r}")
                start, stop = startStopList[0].strip(), startStopList[1].strip()
                del startStopList
                if not start or not stop:
                    raise ParseError(f"{fn!r}:{idx+1}: Syntax error in {contentDef!r} in {line!r}")

                if not _isTestcaseInt(start):
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Not a number {start!r} in {contentDef!r} in {line!r}"
                    )
                start = int(start)
                if start == 0 or abs(start) > 99:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Invalid test case number {start} in {contentDef!r} in "
                        f"{line!r}"
                    )

                if start not in testcaseToNumSlices:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Testcase number {start} in {contentDef!r} is not "
                        f"available.  Available numbers are {unslicedCases}"
                    )
                if start not in unslicedCases:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Slice test case {start} in {contentDef!r} cannot be "
                        f"used in a range.  Available numbers are {unslicedCases}"
                    )

                if stop == "END":
                    stop = 100 if start > 0 else -100
                else:
                    if not _isTestcaseInt(stop):
                        raise ParseError(
                            f"{fn!r}:{idx+1}: Not a number {stop!r} in {contentDef!r} in {line!r}"
                        )
                    stop = int(stop)
                    if stop == 0 or abs(stop) > 99:
                        raise ParseError(
                            f"{fn!r}:{idx+1}: Invalid test case number {stop} in {contentDef!r} "
                            f"in {line!r}"
                        )

                    if stop not in testcaseToNumSlices:
                        raise ParseError(
                            f"{fn!r}:{idx+1}: Testcase number {stop} in {contentDef!r} is not "
                            f"available.  Available numbers are {unslicedCases}"
                        )
                    if stop not in unslicedCases:
                        raise ParseError(
                            f"{fn!r}:{idx+1}: Sliced test case {stop} in {contentDef!r} cannot be "
                            f"used in a range.  Available numbers are {unslicedCases}"
                        )

                if start > 0:
                    numbersInRange = [
                        caseNumber
                        for caseNumber in testcaseToNumSlices.keys()
                        if caseNumber >= start and caseNumber <= stop
                    ]
                else:
                    numbersInRange = [
                        caseNumber
                        for caseNumber in testcaseToNumSlices.keys()
                        if caseNumber <= start and caseNumber >= stop
                    ]

                slicedCases = [
                    caseNumber
                    for caseNumber in numbersInRange
                    if testcaseToNumSlices[caseNumber] > 1
                ]

                if slicedCases:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: {contentDef!r} the following sliced cases would fall "
                        f"into the range {slicedCases}.  Sliced test cases cannot be part of a "
                        "range, they have to be added using the caseNumber.SLICES form to create"
                        "a part for each slice."
                    )

                if len(numbersInRange) < 2:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: {contentDef!r} range results in too few testcases "
                        f"{numbersInRange}"
                    )

                # NOTE This algorithm allows "holes" in the range
                for num in numbersInRange:
                    partDefinitions[-1].append(num)
                    testcaseToNumSlices.pop(num)
                    unslicedCases.remove(num)
            elif "." in contentDef:
                numStr, tail = contentDef.split(".")
                if tail != "SLICES":
                    if tail == "END":
                        raise ParseError(
                            f"{fn!r}:{idx+1}: Use '{numStr}..END' not '.END'.  Single '.' is for "
                            f"test case slices only: {contentDef!r}"
                        )
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Expected '{numStr}.SLICES' in {contentDef!r}"
                    )
                if not _isTestcaseInt(numStr):
                    raise ParseError(f"{fn!r}:{idx+1}: Not a number {numStr!r} in {contentDef!r}")
                num = int(numStr)
                if num == 0 or abs(num) > 99:
                    raise ParseError(f"{fn!r}:{idx+1}: Invalid test case number {num} in {line!r}")

                if num not in testcaseToNumSlices:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Testcase number {num} in {contentDef!r} is not "
                        f"available.  Available numbers are {unslicedCases}"
                    )
                if num in unslicedCases:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Testcase {num} in {contentDef!r} is not sliced, do not "
                        f"use the 'caseNumber.SLICES' form"
                    )
                for sliceNumber in range(1, testcaseToNumSlices[num]):
                    partDefinitions[-1].append((num, sliceNumber))
                    partDefinitions.append([])

                partDefinitions[-1].append((num, testcaseToNumSlices[num]))
                testcaseToNumSlices.pop(num)

            else:
                if not _isTestcaseInt(contentDef):
                    raise ParseError(f"{fn!r}:{idx+1}: Not a number {contentDef!r} in {line!r}")
                num = int(contentDef)
                if num == 0 or abs(num) > 99:
                    raise ParseError(f"{fn!r}:{idx+1}: Invalid test case number {num} in {line!r}")

                if num not in testcaseToNumSlices:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Testcase number {num} in {contentDef!r} is not "
                        f"available.  Available numbers are {unslicedCases}"
                    )
                if num not in unslicedCases:
                    raise ParseError(
                        f"{fn!r}:{idx+1}: Testcase {num} in {contentDef!r} is sliced with "
                        f"{testcaseToNumSlices[num]} slices.  Sliced test cases have to be added "
                        f"using the caseNumber.SLICES form to create a part for each slice.  "
                        "Available not-sliced test case numbers are {unslicedCases}"
                    )

                partDefinitions[-1].append(num)
                testcaseToNumSlices.pop(num)
                unslicedCases.remove(num)

        if not partDefinitions[-1]:
            raise ParseError(
                f"{fn!r}:{idx+1}: Syntax error, no test cases in part #{len(partDefinitions)}: "
                f"{line!r}"
            )

        idx += 1

    if not partDefinitions:
        raise ParseError(
            f"{fn!r}:{idx+1}: Syntax error, no part definitions found in PARTS descriptor."
        )
    if testcaseToNumSlices:
        raise ParseError(
            f"{fn!r}:{idx+1}: Not all test cases have been assigned to a part, remaining are "
            f"{testcaseToNumSlices.keys()}"
        )
    return partDefinitions


def parse(
    xtCppFull: str, fn: str, qualifiedComponentName: str, lines: Sequence[str], groupsDirs: str
) -> ParseResult:
    # Verify file starts with prologue comment line with name and language
    prologueReStr = f"// {qualifiedComponentName}" + r"\.(?:t|xt)\.cpp +-\*-C\+\+-\*-"
    prologueMatch = re.fullmatch(prologueReStr, lines[0])
    if not prologueMatch:
        raise ParseError(
            f"{fn!r}:1: The source does not start with the expected prologue comment line, "
            f"but with {lines[0]!r}"
        )

    _verifySupportedControlComments(fn, lines)

    offset, mainBlock = _findMainBlock(fn, lines)

    testPrintLineInfo = _findTestPrintLine(fn, offset, lines[offset : mainBlock.stop - 1])

    def resolveTypelist(theListMacroValue: str):
        return resolveTypelistMacroValue(theListMacroValue, xtCppFull, groupsDirs)

    testcaseParseResults = _parseTestcases(
        fn,
        *_extractTestcasesOnlyBlock(fn, offset, lines[offset : mainBlock.stop - 1]),
        resolveTypelist,
    )
    del offset, mainBlock

    sliceNameMap = _createSliceNameMap(testcaseParseResults)
    testcaseNumberSet = set(parseResult.testcaseNumber for parseResult in testcaseParseResults)

    testcases = _convertTestcaseParseResults(fn, testcaseParseResults)
    _verifyFoundPositiveTestCases(fn, testcaseParseResults)

    testcaseToNumSlices: MutableMapping[int, int] = {tc.number: tc.numSlices for tc in testcases}
    condBlocks = _parseConditionalBlocks(fn, lines, testcaseNumberSet, sliceNameMap)
    if not qualifiedComponentName.endswith("_cpp03"):
        simCpp11 = _parseSimCpp11Include(fn, qualifiedComponentName, lines)
    else:
        simCpp11 = _parseSimCpp11Cpp03(fn, qualifiedComponentName, lines)

    parts = _parsePartsDefinitionTable(fn, lines, testcaseToNumSlices)
    if len(parts) > 99:
        raise ParseError(f"There are more than 99 parts! N={len(parts)}", parts)

    return ParseResult(
        _getLineDirectivesControl(fn, lines),
        _getSilencedWarnings(fn, lines),
        simCpp11,
        parts,
        condBlocks,
        testPrintLineInfo,
        testcases,
    )
