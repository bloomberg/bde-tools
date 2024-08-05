from lib.parseComponentName import parseComponentName

from lib.xtCppParser import parse as parseXtCpp
from lib.xtCppParser import ParseError as XtCppParseError

from lib.generateParts import generateParts as generatePartsFromXtCpp

from lib.writeOutputForXtCpp import writeOutputForXtCpp

from lib.sourceFileOpen import sourceFileOpen

from lib.codeBlockInterval import CodeBlockInterval, LineNumber

from lib.extensionsForPy38 import removeprefix, removesuffix

from lib.bdeConstants import (
    BDE_CPP_FILE_TAG,
    BDE_HORIZONTAL_LINE_CHARACTERS,
    BDE_INDENT_SIZE,
    BDE_MAX_LINE_LENGTH,
)

__all__ = [
    "parseComponentName",
    "generatePartsFromXtCpp",
    "writeOutputForXtCpp",
    "parseXtCpp",
    "XtCppParseError",
    "sourceFileOpen",
    "CodeBlockInterval",
    "LineNumber",
    "removeprefix",
    "removesuffix",
    "BDE_CPP_FILE_TAG",
    "BDE_HORIZONTAL_LINE_CHARACTERS",
    "BDE_INDENT_SIZE",
    "BDE_MAX_LINE_LENGTH",
]
