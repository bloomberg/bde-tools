from dataclasses import dataclass
import re
from typing import Callable, NoReturn


@dataclass
class ParsedComponentName:
    groupPart: str
    packagePart: str
    componentPart: str


def _defaultErrorFunc(s: str) -> NoReturn:
    raise NotImplementedError


_VERIFY_REGEX = re.compile(
    "(?P<pkg>(?P<grp>[a-z]{3})[a-z]{1,3})_(?P<cmp>[a-z][a-z0-9]+)(?:_[a-z][a-z0-9]+)*",
    re.IGNORECASE,
)


def parseComponentName(
    candidate: str, *, errorFunc: Callable[[str], NoReturn] = _defaultErrorFunc
) -> ParsedComponentName:

    matched = _VERIFY_REGEX.fullmatch(candidate)
    if not matched:
        errTxt = f"'{candidate}' does not appear to be a component file name."
        if errorFunc == _defaultErrorFunc:
            raise ValueError(errTxt)
        else:
            errorFunc(errTxt)

    return ParsedComponentName(matched["grp"], matched["pkg"], matched["cmp"])
