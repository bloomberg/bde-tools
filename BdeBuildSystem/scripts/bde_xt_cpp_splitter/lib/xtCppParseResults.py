from __future__ import annotations

from typing import (
    Callable,
    Literal,
    Mapping,
    MutableMapping,
    MutableSequence,
    Sequence,
    Set,
    Tuple,
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
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        writeLineDirective(rv, self.block.start)
        if self.number != caseNumber:
            rv.append(f"      case {caseNumber}: {{  // 'case {self.number}' in \"{xtCppName}\"")
            rv += lines[self.block.start : self.block.stop - 1]
        else:
            rv += lines[self.block.start - 1 : self.block.stop - 1]
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
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        raise NotImplementedError(f"{self.__class__.__name__}")

    def generateCodeForBlock(
        self,
        withinBlock: CodeBlockInterval,
        sliceNumber: int,
        lines: Sequence[str],
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        firstSlice: bool = sliceNumber == 1
        lastSlice: bool = sliceNumber == self.numSlices

        # Conditional blocks before slicing begins
        skippedBlocks = []
        if not firstSlice:
            skippedBlocks += [
                conditionalBlock
                for conditionalBlock in self.intoFirstSliceBlocks
                if conditionalBlock in withinBlock
            ]
        if not lastSlice:
            skippedBlocks += [
                conditionalBlock
                for conditionalBlock in self.intoLastSliceBlocks
                if conditionalBlock in withinBlock
            ]

        # We really need the blocks to write out
        lastWrittenIndex = withinBlock.start - 1
        writtenBlocks = []
        for skippedBlock in skippedBlocks:
            writtenBlocks.append(CodeBlockInterval(lastWrittenIndex + 1, skippedBlock.start - 1))
            lastWrittenIndex = skippedBlock.stop

        for writtenBlock in writtenBlocks:
            writeLineDirective(rv, writtenBlock.start)
            rv += lines[writtenBlock.start - 1 : writtenBlock.stop - 1]

        if skippedBlocks and not writtenBlocks:
            writeLineDirective(rv, lastWrittenIndex)

        rv += lines[lastWrittenIndex : withinBlock.stop - 1]

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
        return CodeBlockInterval(self.controlCommentBlock.start, self.macroDefinitionBlock.stop)

    def createSliceNameMap(self) -> Mapping[str, int]:
        return {}

    def generateCode(
        self,
        typeSliceIndex: int,
        lines: Sequence[str],
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        rv.append(
            f"{_getIndent(lines[self.controlCommentBlock.start - 1])}{MY_INFO_COMMENT_PREFIX}"
            f"sliced typelist '{self.macroName}' slice {typeSliceIndex+1} of {self.numSlices}"
        )
        writeLineDirective(rv, self.macroDefinitionBlock.start)
        rv.append(
            f"{_getIndent(lines[self.macroDefinitionBlock.start - 1])}"
            f"#define {self.macroName} {', '.join(self.slicedTypelist[typeSliceIndex])}"
        )
        writeLineDirective(rv, self.macroDefinitionBlock.stop)

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
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []
        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.block.start + 1, self.typeSlices.coveredBlock.start),
            sliceIndex,
            lines,
            writeLineDirective,
        )

        rv += self.typeSlices.generateCode(sliceIndex - 1, lines, writeLineDirective)

        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.typeSlices.coveredBlock.stop, self.block.stop),
            sliceIndex,
            lines,
            writeLineDirective,
        )

        return rv


@dataclass
class CodeSlice:
    name: str
    activeBlock: CodeBlockInterval
    subSlicing: TypelistSlicing | CodeSlicing | None = field(default=None)

    @property
    def numSlices(self) -> int:
        if self.subSlicing is None:
            return 1
        return self.subSlicing.numSlices

    def createSliceNameMap(self) -> Mapping[str, int]:
        rv: MutableMapping[str, int] = {self.name: 1}

        if self.subSlicing is not None:
            subNames = self.subSlicing.createSliceNameMap()
            for name, sliceNumber in subNames.items():
                rv[name] = sliceNumber + 1

        return rv

    def generateCode(
        self,
        innerIndex: int,
        lines: Sequence[str],
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv: MutableSequence[str] = []
        if self.subSlicing is None:
            writeLineDirective(rv, self.activeBlock.start)
            rv += lines[self.activeBlock.start : self.activeBlock.stop - 2]
            return rv  # !!! RETURN

        # When here, we have an inner type-list split
        rv += lines[self.activeBlock.start : self.subSlicing.coveredBlock.start - 1]
        rv += self.subSlicing.generateCode(innerIndex, lines, writeLineDirective)
        if rv[-1] != writeLineDirective([], self.subSlicing.coveredBlock.stop):
            writeLineDirective(rv, self.subSlicing.coveredBlock.stop)
        rv += lines[self.subSlicing.coveredBlock.stop - 1 : self.activeBlock.stop - 2]

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

    def _getDualIndex(self, sliceIndex: int) -> Tuple[int, int]:
        codeSliceIndex = 0
        while self.codeSlices[codeSliceIndex].numSlices <= sliceIndex:
            sliceIndex -= self.codeSlices[codeSliceIndex].numSlices
            codeSliceIndex += 1
        return codeSliceIndex, sliceIndex

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
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        codeSliceIndex, innerIndex = self._getDualIndex(sliceIndex)
        rv = []
        rv.append(
            f"{_getIndent(lines[self.block.start - 1])}{MY_INFO_COMMENT_PREFIX}"
            f"code slice {codeSliceIndex+1} of {len(self.codeSlices)}"
        )
        rv += self.codeSlices[codeSliceIndex].generateCode(innerIndex, lines, writeLineDirective)
        writeLineDirective(rv, self.block.stop)
        return rv


@dataclass
class TopCodeSlicedTestcase(SlicedTestcase):
    codeSlicing: CodeSlicing

    @property
    def numSlices(self) -> int:
        return self.codeSlicing.numSlices

    def generateCode(
        self,
        sliceIndex: int,
        lines: Sequence[str],
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv: MutableSequence[str] = []
        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.block.start + 1, self.codeSlicing.coveredBlock.start),
            sliceIndex,
            lines,
            writeLineDirective,
        )
        rv += self.codeSlicing.generateCode(sliceIndex, lines, writeLineDirective)
        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.codeSlicing.coveredBlock.stop, self.block.stop),
            sliceIndex,
            lines,
            writeLineDirective,
        )

        return rv


@dataclass
class MultipliedSlicesTestcase(SlicedTestcase):
    typeSlicing: TypelistSlicing
    codeSlicing: CodeSlicing

    @property
    def numSlices(self) -> int:
        return self.codeSlicing.numSlices * self.typeSlicing.numSlices

    def generateCode(
        self,
        sliceIndex: int,
        lines: Sequence[str],
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        codeSliceIndex = sliceIndex % self.codeSlicing.numSlices
        typeSliceIndex = sliceIndex // self.codeSlicing.numSlices

        rv: MutableSequence[str] = []
        assert self.typeSlicing.coveredBlock.start < self.codeSlicing.coveredBlock.start - 1
        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.block.start + 1, self.typeSlicing.coveredBlock.start),
            sliceIndex,
            lines,
            writeLineDirective,
        )
        rv += self.typeSlicing.generateCode(typeSliceIndex, lines, writeLineDirective)

        rv += self.generateCodeForBlock(
            CodeBlockInterval(
                self.typeSlicing.coveredBlock.stop, self.codeSlicing.coveredBlock.start
            ),
            sliceIndex,
            lines,
            writeLineDirective,
        )

        rv += self.codeSlicing.generateCode(codeSliceIndex, lines, writeLineDirective)

        rv += self.generateCodeForBlock(
            CodeBlockInterval(self.codeSlicing.coveredBlock.start, self.block.stop),
            sliceIndex,
            lines,
            writeLineDirective,
        )

        return rv


@dataclass
class TestPrintLineInfo:
    lineNumber: int
    kind: Literal["printf", "cout"]


@dataclass
class ConditionalCommonCodeBlock:
    activeFor: Set[int | Tuple[int, int]]  # (n, 100) - all test case, (n, 1-99) - just a slice
    conditionAsWritten: str
    block: CodeBlockInterval

    @property
    def coveredBlock(self) -> CodeBlockInterval:
        return self.block

    def isActive(self, partContent: Sequence[int | Tuple[int, int]]) -> bool:
        for elem in partContent:
            if elem in self.activeFor:
                return True
            if isinstance(elem, tuple) and elem[0] in self.activeFor:
                return True
        return False


@dataclass
class ConditionalCommonCodeBlocks:
    conditionalBlocks: Sequence[ConditionalCommonCodeBlock]

    @property
    def coveredBlock(self) -> CodeBlockInterval:
        assert self.conditionalBlocks
        return CodeBlockInterval(
            self.conditionalBlocks[0].coveredBlock.start,
            self.conditionalBlocks[-1].coveredBlock.stop,
        )

    def overlapsWithAnyConditional(self, block: CodeBlockInterval) -> bool:
        return any(
            block.overlaps(conditionalBlock.block) for conditionalBlock in self.conditionalBlocks
        )

    def generateCodeForBlock(
        self,
        withinBlock: CodeBlockInterval,
        partContents: Sequence[int | Tuple[int, int]],
        lines: Sequence[str],
        writeLineDirective: Callable[[MutableSequence[str], int], str],
    ) -> Sequence[str]:
        rv = []

        nextActiveLine: int = withinBlock.start
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
                    CodeBlockInterval(nextActiveLine, conditionalBlock.block.start)
                )
                nextActiveLine = conditionalBlock.block.stop
        blocksToWrite.append(CodeBlockInterval(nextActiveLine, withinBlock.stop))

        for blockToWrite in blocksToWrite:
            writeLineDirective(rv, blockToWrite.start)
            rv += lines[blockToWrite.start - 1 : blockToWrite.stop - 1]

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
        lines[self.ifdefLine - 1] = lines[self.ifdefLine - 1].replace(macroEndFind, macroEndRepl)
        lines[self.elseLine - 1] = lines[self.elseLine - 1].replace(macroEndFind, macroEndRepl)
        lines[self.endifLine - 1] = lines[self.endifLine - 1].replace(macroEndFind, macroEndRepl)

        fileEndFind = ".xt.cpp" if partNumber == 1 else f".{partNumber-1:02}.t.cpp"
        for lineNumber in self.invocationLines:
            lines[lineNumber - 1] = lines[lineNumber - 1].replace(
                fileEndFind, f".{partNumber:02}.t.cpp"
            )


SilencedWarningKind = Literal["unused"]


@dataclass
class ParseResult:
    useLineDirectives: bool | None
    silencedWarnings: Set[SilencedWarningKind]
    simCpp11: SimCpp11IncludeConstruct | SimCpp11Cpp03LinesToUpdate | None
    parts: Sequence[Sequence[int | Tuple[int, int]]]
    conditionalCommonCodeBlocks: ConditionalCommonCodeBlocks
    testPrintLine: TestPrintLineInfo
    testcases: Sequence[Testcase]

    def generateBeforeTestPrintCode(self) -> Sequence[str]:
        """Return the next block"""
        rv = []

        return rv
