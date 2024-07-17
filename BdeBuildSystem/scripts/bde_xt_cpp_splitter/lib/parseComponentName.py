import re
from typing import Callable, NoReturn, Tuple

_VERIFY_REGEX = re.compile(
    "(?P<pkg>(?P<grp>[a-z]{3})[a-z]{1,3})_(?P<cmp>[a-zA-Z][A-Za-z0-9]+)(?:_[a-zA-Z][A-Za-z0-9]+)*"
)


def _defaultErrorFunc(s: str) -> NoReturn:
    raise NotImplementedError


def parseComponentName(
    candidate: str, *, errorFunc: Callable[[str], NoReturn] = _defaultErrorFunc
) -> Tuple[str, str, str]:
    candidate = candidate.lower()

    matched = _VERIFY_REGEX.fullmatch(candidate)
    if not matched:
        errTxt = f"{candidate!r} does not appear to be a component file name."
        if errorFunc == _defaultErrorFunc:
            raise ValueError(errTxt)
        else:
            errorFunc(errTxt)

    return matched["grp"], matched["pkg"], matched["cmp"]
