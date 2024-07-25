from __future__ import annotations

from dataclasses import dataclass
from typing import overload

LineNumber = int


# @dataclass(slots=True)
@dataclass(order=False, init=False)
class CodeBlockInterval:
    "A half open range of line numbers [1..N)."

    _start: LineNumber
    _stop: LineNumber

    @classmethod
    def CreateFromIndex(cls, startArg: int, stopArg: int = -1):
        return CodeBlockInterval(startArg + 1, stopArg if stopArg == -1 else stopArg - 1)

    def __init__(self, startArg: LineNumber, stopArg: LineNumber = -1):
        if stopArg == -1:
            stopArg = startArg

        assert startArg > 0
        assert stopArg > 0
        assert startArg <= stopArg

        self._start = startArg
        self._stop = stopArg

    @property
    def startLine(self) -> LineNumber:
        return self._start

    @property
    def stopLine(self) -> LineNumber:
        return self._stop

    @stopLine.setter
    def stopLine(self, newStop: LineNumber) -> None:
        assert newStop >= self._start
        self._stop = newStop

    @property
    def startIndex(self) -> int:
        return self._start - 1

    @property
    def stopIndex(self) -> int:
        return self._stop - 1

    @stopIndex.setter
    def stopIndex(self, newStopIndex: int) -> None:
        self.stopLine = newStopIndex + 1

    def extendBy(self, numberOfLines: LineNumber) -> None:
        assert numberOfLines >= 0
        self._stop += numberOfLines

    def __len__(self):
        return self._stop - self._start

    def __nonzero__(self) -> bool:
        return self._stop != self._start

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
        if isinstance(other, CodeBlockInterval):
            return other._start in self and other._stop in self
        elif isinstance(other, LineNumber):
            return other >= self._start and other < self._stop
        else:
            raise ValueError(f"Cannot look up {type(other)} in a CodeBlockInterval.")

    def overlaps(self, other: CodeBlockInterval) -> bool:
        "Predicate that answer the question if two blocks share a common block or line."
        return self._start < other._stop and other._start < self._stop

    def isBefore(self, other: CodeBlockInterval) -> bool:
        "Predicate that answer the question is this block before the specified other."
        return self._stop <= other._start
