from __future__ import annotations

from typing import (
    Callable,
    Literal,
    Mapping,
    MutableMapping,
    MutableSequence,
    Optional,
    Sequence,
    Set,
)

from dataclasses import dataclass, field

from lib.codeBlockInterval import CodeBlockInterval
from lib.myConstants import MY_INFO_COMMENT_PREFIX


def _getIndent(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


@dataclass
class Testcase:
    number: int
    block: CodeBlockInterval

    @property
    def numSlices(self) -> int:
        raise NotImplementedError


@dataclass
class UnslicedTestcase(Testcase):

    @property
    def numSlices(self) -> int:
        return 1

    def generateCode(
        self,
        xtCppName: str,
        caseNumber: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        appendLineDirective(rv, self.block.startLine)
        if self.number != caseNumber:
            rv.append(f"      case {caseNumber}: {{  // 'case {self.number}' in \"{xtCppName}\"")
            rv += lines[self.block.startIndex + 1 : self.block.stopIndex]
        else:
            rv += lines[self.block.startIndex : self.block.stopIndex]
        return rv


@dataclass
class SlicedTestcase(Testcase):
    intoFirstSliceBlocks: Sequence[CodeBlockInterval]
    intoLastSliceBlocks: Sequence[CodeBlockInterval]

    def createSliceNameMap(self) -> Mapping[str, int]:
        raise NotImplementedError

    def generateCode(
        self,
        sliceIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        raise NotImplementedError(f"{self.__class__.__name__}")

    def generateCodeForBlock(
        self,
        withinBlock: CodeBlockInterval,
        sliceIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        firstSlice: bool = sliceIndex == 0
        lastSlice: bool = sliceIndex == self.numSlices - 1

        # Conditional blocks before slicing begins
        def filterWithinBlock(blocks: Sequence[CodeBlockInterval]):
            return filter(lambda x: x in withinBlock, blocks)

        skippedBlocks: MutableSequence[CodeBlockInterval] = []
        if not firstSlice:
            skippedBlocks += filterWithinBlock(self.intoFirstSliceBlocks)
        if not lastSlice:
            skippedBlocks += filterWithinBlock(self.intoLastSliceBlocks)
        # Compute the code blocks to write out
        lastWrittenIndex = withinBlock.startIndex
        writtenBlocks: MutableSequence[CodeBlockInterval] = []
        for skippedBlock in skippedBlocks:
            writtenBlocks.append(
                CodeBlockInterval(lastWrittenIndex + 1, skippedBlock.startLine - 1)
            )
            lastWrittenIndex = skippedBlock.stopIndex + 1

        for writtenBlock in writtenBlocks:
            appendLineDirective(rv, writtenBlock.startLine)
            rv += lines[writtenBlock.startIndex : writtenBlock.stopIndex]

        if skippedBlocks and not writtenBlocks:
            appendLineDirective(rv, lastWrittenIndex)

        rv += lines[lastWrittenIndex : withinBlock.stopIndex]

        return rv


@dataclass
class TypelistSlicing:
    controlCommentBlock: CodeBlockInterval
    macroDefinitionBlock: CodeBlockInterval
    macroName: str
    slicedTypelist: Sequence[Sequence[str]]

    @property
    def numSlices(self) -> int:
        return len(self.slicedTypelist)

    @property
    def coveredBlock(self) -> CodeBlockInterval:
        return CodeBlockInterval(
            self.controlCommentBlock.startLine, self.macroDefinitionBlock.stopLine
        )

    def createSliceNameMap(self) -> Mapping[str, int]:
        return {}

    def generateCode(
        self,
        typeSliceIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        rv.append(
            f"{_getIndent(lines[self.controlCommentBlock.startIndex])}{MY_INFO_COMMENT_PREFIX}"
            f"sliced typelist '{self.macroName}' slice {typeSliceIndex+1} of {self.numSlices}"
        )
        appendLineDirective(rv, self.macroDefinitionBlock.startLine)
        rv.append(
            f"{_getIndent(lines[self.macroDefinitionBlock.startIndex])}"
            f"#define {self.macroName} {', '.join(self.slicedTypelist[typeSliceIndex])}"
        )
        appendLineDirective(rv, self.macroDefinitionBlock.stopLine)

        return rv


@dataclass
class TypelistSlicedTestcase(SlicedTestcase):
    typeSlices: TypelistSlicing

    @property
    def numSlices(self) -> int:
        return self.typeSlices.numSlices

    def createSliceNameMap(self) -> Mapping[str, int]:
        return self.typeSlices.createSliceNameMap()

    def generateCode(
        self,
        sliceIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.block.startLine + 1, self.typeSlices.coveredBlock.startLine),
            sliceIndex,
            lines,
            appendLineDirective,
        )

        rv += self.typeSlices.generateCode(sliceIndex, lines, appendLineDirective)

        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.typeSlices.coveredBlock.stopLine, self.block.stopLine),
            sliceIndex,
            lines,
            appendLineDirective,
        )

        return rv


@dataclass
class CodeSlice:
    name: str
    activeBlock: CodeBlockInterval
    subSlicing: TypelistSlicing | CodeSlicing | None = field(default=None)

    @property
    def numSlices(self) -> int:
        return 1 if self.subSlicing is None else self.subSlicing.numSlices

    def createSliceNameMap(self) -> Mapping[str, int]:
        rv: MutableMapping[str, int] = {self.name: 1}

        if self.subSlicing is not None:
            subNames = self.subSlicing.createSliceNameMap()
            rv.update((name, sliceNumber + 1) for name, sliceNumber in subNames.items())
        return rv

    def generateCode(
        self,
        innerIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:

        # Code-slice codeBlockIntervals include the comments that start and terminate the block, so
        # when we want to write only the code-slice we have to leave out the first and last line.

        rv: MutableSequence[str] = []
        if self.subSlicing is None:
            appendLineDirective(rv, self.activeBlock.startLine)
            rv += lines[self.activeBlock.startIndex : self.activeBlock.stopIndex]
            return rv  # !!! RETURN

        # When here, we have an inner split, code or type-list
        rv += lines[self.activeBlock.startIndex : self.subSlicing.coveredBlock.startIndex]
        rv += self.subSlicing.generateCode(innerIndex, lines, appendLineDirective)

        lineDirectives = []
        if rv[-1] != appendLineDirective(lineDirectives, self.subSlicing.coveredBlock.stopLine):
            rv.extend(lineDirectives)
        del lineDirectives

        rv += lines[self.subSlicing.coveredBlock.stopIndex : self.activeBlock.stopIndex]

        return rv


@dataclass
class CodeSlicing:
    block: CodeBlockInterval
    codeSlices: Sequence[CodeSlice]

    @property
    def numSlices(self) -> int:
        return sum(slice.numSlices for slice in self.codeSlices)

    @property
    def coveredBlock(self) -> CodeBlockInterval:
        return self.block

    @dataclass
    class _DualIndex:
        mainIndex: int
        subIndex: int

    def _getDualIndex(self, sliceIndex: int) -> _DualIndex:
        codeSliceIndex = 0
        while self.codeSlices[codeSliceIndex].numSlices <= sliceIndex:
            sliceIndex -= self.codeSlices[codeSliceIndex].numSlices
            codeSliceIndex += 1
        return CodeSlicing._DualIndex(codeSliceIndex, sliceIndex)

    def createSliceNameMap(self) -> Mapping[str, int]:
        rv: MutableMapping[str, int] = {}
        offset = 0
        for slice in self.codeSlices:
            subNames = slice.createSliceNameMap()
            for name, sliceNumber in subNames.items():
                if name:
                    rv[name] = sliceNumber + offset
            offset += slice.numSlices
        return rv

    def generateCode(
        self,
        sliceIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        dualIndex = self._getDualIndex(sliceIndex)

        rv = []

        # We align our comment the same way the control-comment was
        rv.append(
            f"{_getIndent(lines[self.block.startIndex])}{MY_INFO_COMMENT_PREFIX}"
            f"code slice {dualIndex.mainIndex+1} of {len(self.codeSlices)}"
        )

        rv += self.codeSlices[dualIndex.mainIndex].generateCode(
            dualIndex.subIndex, lines, appendLineDirective
        )

        appendLineDirective(rv, self.block.stopLine)

        return rv


@dataclass
class CodeSlicedTestcase(SlicedTestcase):
    codeSlicing: CodeSlicing

    @property
    def numSlices(self) -> int:
        return self.codeSlicing.numSlices

    def generateCode(
        self,
        sliceIndex: int,
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv: MutableSequence[str] = []
        rv += self.generateCodeForBlock(
            # block.startLine points to the `case NN: {`, which we skip because we replaced it
            CodeBlockInterval(self.block.startLine + 1, self.codeSlicing.coveredBlock.startLine),
            sliceIndex,
            lines,
            appendLineDirective,
        )
        rv += self.codeSlicing.generateCode(sliceIndex, lines, appendLineDirective)
        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.codeSlicing.coveredBlock.stopLine, self.block.stopLine),
            sliceIndex,
            lines,
            appendLineDirective,
        )

        return rv


@dataclass
class TestPrintLineInfo:
    lineNumber: int
    kind: Literal["printf", "cout"]


@dataclass
class ConditionalCommonCodeBlock:
    activeFor: Set[OriginalTestcase]
    conditionAsWritten: str
    block: CodeBlockInterval

    @property
    def coveredBlock(self) -> CodeBlockInterval:
        return self.block

    def isActive(self, partContent: Sequence[OriginalTestcase]) -> bool:
        for elem in partContent:
            if elem in self.activeFor:
                return True
            if (
                elem.hasSliceNumber
                and OriginalTestcase(elem.testcaseNumber, None) in self.activeFor
            ):
                return True
        return False


@dataclass
class ConditionalCommonCodeBlocks:
    conditionalBlocks: Sequence[ConditionalCommonCodeBlock]

    @property
    def coveredBlock(self) -> CodeBlockInterval:
        assert self.conditionalBlocks
        return CodeBlockInterval(
            self.conditionalBlocks[0].coveredBlock.startLine,
            self.conditionalBlocks[-1].coveredBlock.stopLine,
        )

    def overlapsWithAnyConditional(self, block: CodeBlockInterval) -> bool:
        return any(
            block.overlaps(conditionalBlock.block) for conditionalBlock in self.conditionalBlocks
        )

    def generateCodeForBlock(
        self,
        withinBlock: CodeBlockInterval,
        partContents: Sequence[OriginalTestcase],
        lines: Sequence[str],
        appendLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []

        nextActiveLine: int = withinBlock.startLine
        blocksToWrite: MutableSequence[CodeBlockInterval] = []
        for conditionalBlock in self.conditionalBlocks:
            if conditionalBlock.block not in withinBlock:
                if conditionalBlock.block.overlaps(withinBlock):
                    raise ValueError(
                        f"INTERNAL ERROR: conditional block {conditionalBlock.conditionAsWritten} "
                        f"partially overlaps the requested block-to-write {withinBlock}"
                    )
                continue  # !!! CONTINUE

            if not conditionalBlock.isActive(partContents):
                blocksToWrite.append(
                    CodeBlockInterval(nextActiveLine, conditionalBlock.block.startLine)
                )
                nextActiveLine = conditionalBlock.block.stopLine
        blocksToWrite.append(CodeBlockInterval(nextActiveLine, withinBlock.stopLine))

        for blockToWrite in blocksToWrite:
            appendLineDirective(rv, blockToWrite.startLine)
            rv += lines[blockToWrite.startIndex : blockToWrite.stopIndex]

        return rv


@dataclass
class SimCpp11IncludeConstruct:
    block: CodeBlockInterval  # From #if to #else
    defineLine: int
    includeLine: int
    undefLine: int

    def updateLines(self, partNumber: int, lines: MutableSequence[str]):
        macroEndFind = "_XT_CPP" if partNumber == 1 else f"_{partNumber-1:02}_T_CPP"
        macroEndRepl = f"_{partNumber:02}_T_CPP"

        cpp03EndFind = "_cpp03.xt.cpp" if partNumber == 1 else f"_cpp03.{partNumber-1:02}.t.cpp"
        cpp03EndRepl = f"_cpp03.{partNumber:02}.t.cpp"

        lines[self.defineLine - 1] = lines[self.defineLine - 1].replace(macroEndFind, macroEndRepl)
        lines[self.includeLine - 1] = lines[self.includeLine - 1].replace(
            cpp03EndFind, cpp03EndRepl
        )
        lines[self.undefLine - 1] = lines[self.undefLine - 1].replace(macroEndFind, macroEndRepl)


@dataclass
class SimCpp11Cpp03LinesToUpdate:
    ifdefLine: int
    elseLine: int
    endifLine: int
    invocationLines: Sequence[int]

    def updateLines(self, partNumber: int, lines: MutableSequence[str]):
        macroEndFind = "_XT_CPP" if partNumber == 1 else f"_{partNumber-1:02}_T_CPP"
        macroEndRepl = f"_{partNumber:02}_T_CPP"
        for line in (self.ifdefLine, self.elseLine, self.endifLine):
            lines[line - 1] = lines[line - 1].replace(macroEndFind, macroEndRepl)

        fileEndFind = ".xt.cpp" if partNumber == 1 else f".{partNumber-1:02}.t.cpp"
        for lineNumber in self.invocationLines:
            lines[lineNumber - 1] = lines[lineNumber - 1].replace(
                fileEndFind, f".{partNumber:02}.t.cpp"
            )


SilencedWarningKind = Literal["unused"]


@dataclass
class PartTestcase:
    partNumber: int
    testcaseNumber: int


@dataclass(frozen=True)
class OriginalTestcase:
    testcaseNumber: int
    sliceNumber: Optional[int]

    @property
    def originalTestcaseNumberSortWeight(self) -> int:
        # We order negative test cases after the positive ones.  Since maximum valid positive test
        # case number is 99, we can return negative test case numbers as 101 for -1, 102 for -2,...
        return self.testcaseNumber if self.testcaseNumber > 0 else 100 - self.testcaseNumber

    def __post_init__(self):
        if self.testcaseNumber < 0 and self.sliceNumber is not None:
            raise ValueError(f"Negative test cases cannot have slices: {self!r}")

    @property
    def hasSliceNumber(self) -> bool:
        return self.sliceNumber is not None

    def sliceText(self, width: int) -> str:
        assert width > 0
        return f"{self.sliceNumber:{width}}" if self.hasSliceNumber else " " * width


@dataclass
class TestcaseMapping:
    originalTestcase: OriginalTestcase
    partTestcase: PartTestcase

    @property
    def originalTestcaseNumberSortWeight(self) -> int:
        return self.originalTestcase.originalTestcaseNumberSortWeight

    @property
    def hasSliceNumber(self) -> bool:
        return self.originalTestcase.hasSliceNumber

    @property
    def sliceNumber(self) -> Optional[int]:
        return self.originalTestcase.sliceNumber

    @property
    def originalTestcaseNumber(self) -> int:
        return self.originalTestcase.testcaseNumber

    @property
    def partNumber(self) -> int:
        return self.partTestcase.partNumber

    @property
    def partTestcaseNumber(self) -> int:
        return self.partTestcase.testcaseNumber

    @partTestcaseNumber.setter
    def partTestcaseNumber(self, partNewTestcaseNumber: int) -> None:
        self.partTestcase.testcaseNumber = partNewTestcaseNumber

    def sliceText(self, width: int) -> str:
        return self.originalTestcase.sliceText(width)


@dataclass
class ParseResult:
    useLineDirectives: bool | None
    silencedWarnings: Set[SilencedWarningKind]
    simCpp11: SimCpp11IncludeConstruct | SimCpp11Cpp03LinesToUpdate | None
    parts: Sequence[Sequence[OriginalTestcase]]
    conditionalCommonCodeBlocks: ConditionalCommonCodeBlocks
    testPrintLine: TestPrintLineInfo
    testcases: Sequence[Testcase]
