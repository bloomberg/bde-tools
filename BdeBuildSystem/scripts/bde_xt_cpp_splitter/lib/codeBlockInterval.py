from __future__ import annotations

from dataclasses import dataclass
from typing import overload

LineNumber = int


# @dataclass(slots=True)
@dataclass(order=False, init=False)
class CodeBlockInterval:
    """A half open range of line numbers [1..N).

    This class also supports indexes that are 0-based.  Use `CreateFromIndex` to get a code block
    interval object from 0-based numbers.  Indexes are called as such because in a `Sequence` those
    numbers correspond to the lines.  The numbers stored in the object are 1-based just like line
    numbers in an editor.  The latter helps with debugging the script.

    To get the corresponding lines (strings) out of a sequence use `startIndex` and `stopIndex`,
    such as `strList[codeBlockInterval.startIndex : codeBlockInterval.topIndex]`.
    """

    _startLine: LineNumber
    _stopLine: LineNumber

    @classmethod
    def CreateFromIndex(cls, startIndex: int, stopIndex: int = -1) -> CodeBlockInterval:
        """
        CreateFromIndex Create a new CodeBlockInterval from the 0-based (array) index arguments

        Same as the "normal" constructor but the a

        Args:
            startIndex (int): 0 based start index, the first index of the block
            stopIndex (int, optional): 0 based stop index, one-beyond-the-last index of the block

        Returns:
            CodeBlockInterval: made from line numbers corresponding to the index arguments
        """

        return CodeBlockInterval(startIndex + 1, stopIndex if stopIndex == -1 else stopIndex - 1)

    def __init__(self, startLine: LineNumber, stopLine: LineNumber = -1):
        """
        __init__ Initialize a `CodeBlockInterval` using `startLine` and `stopLine`.

        If `stopLine` is `-1` or not specified, create an empty (0-line) `CodeBlockInterval`.

        Note that empty blocks have the same `startLine` and `stopLine` property, so while
        technically `startLine` *is* the first line of the block, it also has zero lines.

        Args:
            startLine (LineNumber): 1-based starting line number, first line of the block
            stopLine (LineNumber, optional): 1-based one-beyond-the-last line of the block
        """

        if stopLine == -1:
            stopLine = startLine

        assert startLine > 0
        assert stopLine > 0
        assert startLine <= stopLine

        self._startLine = startLine
        self._stopLine = stopLine

    @property
    def startLine(self) -> LineNumber:
        """
        startLine 1-based line number of the first line of the block

        In case of an empty block it is the same as `stopLine`.
        """

        return self._startLine

    @property
    def stopLine(self) -> LineNumber:
        """
        stopLine 1-based line number of the one-beyond-the-last line of the block

        In case of an empty block it is the same as `startLine`.
        """

        return self._stopLine

    @stopLine.setter
    def stopLine(self, newStopLine: LineNumber) -> None:
        """Set `stopLine` to the `newStopLine` value if valid; assert otherwise."""

        assert newStopLine >= self._startLine
        self._stopLine = newStopLine

    @property
    def startIndex(self) -> int:
        """
        startIndex 0-based index of the first line of the block, same as `startLine - 1`.

        In case of an empty block it is the same as `stopIndex`.
        """

        return self._startLine - 1

    @property
    def stopIndex(self) -> int:
        """
        stopIndex 1-based index of the one-beyond-the-last line of the block, or `stopIndex - `.

        In case of an empty block it is the same as `startIndex`.
        """

        return self._stopLine - 1

    @stopIndex.setter
    def stopIndex(self, newStopIndex: int) -> None:
        """Set `stopIndex` to the `newStopIndex` value if valid; assert otherwise."""

        self.stopLine = newStopIndex + 1

    def extendBy(self, numberOfLines: LineNumber) -> None:
        """Grow this block by the non-negative `numberOfLines`."""

        assert numberOfLines >= 0
        self._stopLine += numberOfLines

    def __len__(self):
        """The number of lines this block contains."""

        return self._stopLine - self._startLine

    def __nonzero__(self) -> bool:
        """Is this block empty?"""

        return self._stopLine != self._startLine

    # Implementing the `in` operator
    @overload
    def __contains__(self, other: CodeBlockInterval, /) -> bool:
        pass

    @overload
    def __contains__(self, other: LineNumber, /) -> bool:
        pass

    @overload
    def __contains__(self, other: object, /) -> bool:
        pass

    def __contains__(self, other: CodeBlockInterval | LineNumber | object, /) -> bool:
        """Does this block (fully) contain the specified block or line number?"""

        if isinstance(other, CodeBlockInterval):
            return other._startLine in self and other._stopLine in self
        elif isinstance(other, LineNumber):
            return other >= self._startLine and other < self._stopLine
        else:
            raise ValueError(f"Cannot look up {type(other)} in a CodeBlockInterval.")

    def overlaps(self, other: CodeBlockInterval) -> bool:
        """Predicate that answer the question if two blocks share a common block or line."""
        return self._startLine < other._stopLine and other._startLine < self._stopLine

    def isBefore(self, other: CodeBlockInterval) -> bool:
        """Predicate that answer the question is this block before the specified other."""
        return self._stopLine <= other._startLine
