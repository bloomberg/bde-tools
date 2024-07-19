from __future__ import annotations

from typing import TextIO


def sourceFileOpen(file_path, mode: str) -> TextIO:
    "Open a C++ source file as text with the proper (ASCII) encoding settings."
    return open(file_path, mode, encoding="ascii", errors="surrogateescape")  # type: ignore
