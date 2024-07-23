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

    def __init__(self, startArg: LineNumber, stopArg: LineNumber = -1):
        if stopArg == -1:
            stopArg = startArg

        if startArg < 1 or stopArg < 1:
            raise ValueError(
                f"'{type(self)}' Line numbers must be positive: {startArg}, {stopArg=}"
            )
        if startArg > stopArg:
            raise ValueError(
                f"'{type(self)}' Stop cannot be smaller than start: {startArg=}, {stopArg}"
            )

        self._start = startArg
        self._stop = stopArg

    @property
    def start(self):
        return self._start

    @property
    def stop(self):
        return self._stop

    @stop.setter
    def stop(self, newStop: LineNumber) -> None:
        if newStop < self._start:
            raise ValueError(
                f"'{type(self)}.stop' ({newStop}) cannot be smaller than start ({self._start})"
            )
        self._stop = newStop

    def extendBy(self, numberOfLines: LineNumber) -> None:
        if numberOfLines < 0:
            raise ValueError(
                f"Extending by {numberOfLines} (negative) number of lines is not supported."
            )
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
