from __future__ import annotations

import argparse
import logging
import os

from dataclasses import dataclass
from pathlib import Path
from enum import Enum
from typing import Tuple

from lib.generateParts import generateTestcasesToPartsMapping
from lib import (
    parseComponentName,
    generatePartsFromXtCpp,
    parseXtCpp,
    XtCppParseError,
    writeOutputForXtCpp,
)
from lib.myConstants import MY_CONTROL_COMMENT_PREFIX


__version__: str = "0.0.1"
__prog__: str = Path(__file__).stem

class FileType(Enum):
    FILE = 0
    DIRECTORY = 1

def _verifyTypeAndAccess(path: Path, type : FileType, access : int):
    typeCheckFn = Path.is_file if type == FileType.FILE else Path.is_dir
    if not typeCheckFn(path):
        raise argparse.ArgumentTypeError(f"'{path}' is not a {type.name.lower()}")

    def _verifyAccess(mode : int, message: str):
        if access & mode and not os.access(path, mode):
            raise argparse.ArgumentTypeError(f"'{path}' is not {message}")

    _verifyAccess(os.R_OK, "readable")
    _verifyAccess(os.W_OK, "writable")


def _verifyOutputDirectoryArg(outputDirectoryPath: str) -> str:
    _verifyTypeAndAccess(Path(outputDirectoryPath), FileType.DIRECTORY, os.R_OK | os.W_OK)
    return outputDirectoryPath


def _verifyGroupsDirectoryArg(groupsDirectoryPath: str) -> str:
    _verifyTypeAndAccess(Path(groupsDirectoryPath), FileType.DIRECTORY, os.R_OK)
    return groupsDirectoryPath


def _verifyStampPathArg(stampFileName: str) -> str:
    stampPath = Path(stampFileName)

    if os.path.dirname(stampPath):
        _verifyTypeAndAccess(stampPath.parent, FileType.DIRECTORY, os.R_OK | os.W_OK)

    if stampPath.exists():
        _verifyTypeAndAccess(stampPath, FileType.FILE, os.R_OK | os.W_OK)

    return stampFileName


def _applyMacrosToMdText(mdName: str, mdText: str) -> str:
    myName = Path(__file__).resolve().stem
    macros = {
        "{|SCRIPT-NAME|}": f"{myName}",
        "{|CONTROL-COMMENT-PREFIX|}": MY_CONTROL_COMMENT_PREFIX,
        "{|HELP-NAME|}": mdName,
    }

    for macro, replaced in macros.items():
        mdText = mdText.replace(macro, replaced)

    return mdText


_MY_HELP_NOTE = (
    "# **NOTE**: Use `{|SCRIPT-NAME|} --force-colors --help {|HELP-NAME|} | less -r` to display "
    "as a scrollable, color-rendered document."
)


def _getHelpMdText(name: str) -> str:
    syntaxHelp = Path(__file__).resolve().with_name(f"{name}.t.md")
    return _applyMacrosToMdText(name, syntaxHelp.read_text())


def _getInteractiveHelpMdText(name: str) -> str:
    text = _getHelpMdText(name)
    note = _applyMacrosToMdText(name, _MY_HELP_NOTE)
    return f"{note}\n\n{text}\n\n{note}\n"


_MY_HELP_DUMP_NOTE = "<!-- Use `{|SCRIPT-NAME|} -o <outdir> --dump-help` to recreate this file -->"


def _getHelpDumpMdText(name: str) -> str:
    text = _getHelpMdText(name)
    note = _applyMacrosToMdText(name, _MY_HELP_DUMP_NOTE)
    return f"{note}\n\n{text}\n\n{note}\n"


_HELP_TEMPLATES = ["usage-guide", "syntax-ebnf"]


class _HelpAction(argparse.Action):

    def __call__(self, parser, namespace, values, option_string=None):
        if values is None:
            parser.print_help()
        else:
            assert isinstance(values, str)
            mdText = _getInteractiveHelpMdText(values)

            try:
                from rich.console import Console as RichConsole
                from rich.markdown import Markdown as RichMarkdown

                console = RichConsole(
                    force_terminal=namespace.force_colors,
                    legacy_windows=not namespace.force_colors,
                    safe_box=not namespace.force_colors,
                    tab_size=4,
                    emoji=True,
                    highlight=False,
                )
                console.width = min(console.width, 80)
                console.print(
                    RichMarkdown(mdText, style="github"),
                    highlight=False,
                    markup=False,
                )
            except ImportError:
                print(mdText)
        exit(0)


class _HelpDumpAction(argparse.Action):

    def __call__(self, parser, namespace, values, option_string=None):
        assert values is None or values == "md"
        if not hasattr(namespace, "outdir") or namespace.outdir is None:
            parser.error(
                f"{self.option_strings[0]} requires output directory to be specified **first** on "
                "the command line"
            )
        print("Processing help markdown templates:")
        myName = Path(__file__).resolve().stem
        for mdName in _HELP_TEMPLATES:
            mdText = _getHelpDumpMdText(mdName)
            mdOutName = f"{myName}-{mdName}.md"
            outPath = Path(namespace.outdir) / mdOutName
            print(f"    Writing {outPath}...")
            outPath.write_text(mdText)
        print("Done.")

        exit(0)


@dataclass
class ParsedSourcePathArg:
    filePath: Path
    qualifiedComponentName: str
    group: str


class _XtCppPathArgAction(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        if not isinstance(values, str):
            parser.error(f"Unexpected command line argument type: {values!r}")

        filePath = Path(values)

        _verifyTypeAndAccess(filePath, FileType.FILE, os.R_OK)

        qualifiedComponentName, suffixes = filePath.name.split(".", maxsplit=1)

        if suffixes.lower() != "xt.cpp":
            parser.error(f"{filePath} does not have the xt.cpp test driver suffix")

        result = ParsedSourcePathArg(
            filePath,
            qualifiedComponentName,
            parseComponentName(qualifiedComponentName, errorFunc=parser.error)[0],
        )
        setattr(namespace, self.dest, result)


def makeArgParser() -> argparse.ArgumentParser:
    mainArgParser = argparse.ArgumentParser(
        prog=__prog__,
        description="Automate BDE test driver splitting",
        epilog="Use --help with an argument for additional guides, such as --help usage-guide.",
        add_help=False,
    )

    mainArgParser.add_argument(
        "-h",
        "--help",
        choices=_HELP_TEMPLATES,
        nargs='?',
        action=_HelpAction,
        help="Without arguments show this help message and exit.  With arguments show the "
        "specified help document and exit.",
    )

    mainArgParser.add_argument(
        "--dump-help",
        choices=["md"],
        nargs="?",
        action=_HelpDumpAction,
        help="Write extra help markdown files (such as usage-guide) into the specified output "
        "directory and exit.  The output directory must be *before* --dump-help on the command "
        " line",
    )

    mainArgParser.add_argument(
        "--force-colors",
        action="store_true",
        help="Use this before --help <argument>, together with `| less -r`, to get colored "
        "output, and paging.  E.g., `--force-colors --help usage-guide | less -r`",
    )

    mainArgParser.add_argument(
        "-log",
        "--loglevel",
        choices=["debug", "info", "warning", "error", "critical"],
        default="warning",
        help="Sets log level, default is warning.",
    )

    mainArgParser.add_argument(
        "-ver", "--version", action="version", version=f"%(prog)s {__version__}"
    )

    mainArgParser.add_argument(
        "-o",
        "--outdir",
        "--output-directory",
        required=True,
        type=_verifyOutputDirectoryArg,
        help="Write the generated test driver source file into this directory.  Also used with "
        "--dump-help.",
    )

    mainArgParser.add_argument(
        "-s",
        "--stampfile",
        "--stamp-file-name",
        type=_verifyStampPathArg,
        help="Stamp file name for build system, default is input file name and '.stamp', "
        "default directory is the output directory.",
    )

    mainArgParser.add_argument(
        "-i",
        "--groups-directory",
        action="append",
        type=_verifyGroupsDirectoryArg,
        default=[],
        help="The 'groups' directories of repositories that need to be searched for type-list "
        "macro definitions.  If the input file path appears to be on a BDE repository path "
        "(*/groups/abc/abcxyz/) that 'groups' directory is automatically added.",
    )

    mainArgParser.add_argument(
        "--line-directives",
        action="store_true",
        help="Emit line directives into output source files that point back to the input file.",
    )
    mainArgParser.add_argument(
        "--no-line-directives",
        dest="line_directives",
        action="store_false",
        help="Do not emit line directives to output source files.  Useful when looking for "
        "unexpected issues (warnings, errors) in the generated test driver parts.",
    )
    mainArgParser.set_defaults(line_directives=None)

    mainArgParser.add_argument(
        "xtCppPath",
        help="The path to the xt.cpp test driver file used as input.",
        action=_XtCppPathArgAction,
    )

    return mainArgParser


def logCommandlineArguments(args: argparse.Namespace) -> None:
    logging.debug("Original Command Line Arguments:")
    for name, val in args.__dict__.items():
        logging.info(f"    {name} = {val}")


@dataclass(init=False, eq=False, order=False)
class ParsedArgs:
    loglevel: str
    xtCppPath: Path
    xtCppComponent: str
    outDirectory: Path
    stampFilePath: Path
    groupsDirsPath: Tuple[Path, ...]
    useLineDirectives: bool | None

    def __init__(self) -> None:
        args = makeArgParser().parse_args()

        logging.basicConfig(
            format="[%(asctime)s] %(levelname)s [%(name)s.%(funcName)s:%(lineno)d] %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S%z",
            level=args.loglevel.upper(),
        )
        logging.info("Logging is now set up.")

        logCommandlineArguments(args)

        self.loglevel = args.loglevel

        self.useLineDirectives = args.line_directives

        self.xtCppPath = args.xtCppPath.filePath
        self.xtCppComponent = args.xtCppPath.qualifiedComponentName

        self.outDirectory = Path(args.outdir)

        self.stampFilePath = Path(args.stampfile if args.stampfile else f"{self.xtCppPath.name}.stamp")

        # If there is no path in the stamp file argument put it into the output directory
        if not os.path.dirname(self.stampFilePath):
            self.stampFilePath = self.outDirectory / self.stampFilePath

        # Add the 'groups' directory from the input file to the groups search path, if the path
        # actually ends in .../groups/grp/grppkg (like .../groups/bsl/bslstl)
        resolvedPath = self.xtCppPath.resolve()
        packageDir = resolvedPath.parent
        groupDir = packageDir.parent
        groupsDir = groupDir.parent

        if groupsDir.name == "groups" and groupDir.name == args.xtCppPath.group:
            args.groups_directory.append(groupsDir)

        self.groupsDirsPath = tuple(Path(x) for x in args.groups_directory)

        lineDirectivesStr = (
            self.useLineDirectives if self.useLineDirectives is not None else "Not Set"
        )
        logging.info(
            "Effective Command Line Arguments:\n"
            f"    Log level         : {self.loglevel}\n"
            f"    Input xt.cpp file : {self.xtCppPath}\n"
            f"    Output directory  : {self.outDirectory}\n"
            f"    Stamp file        : {self.stampFilePath}\n"
            f"    Groups search path: {", ".join([str(x) for x in self.groupsDirsPath])}\n"
            f"    Line directives   : {lineDirectivesStr}"
        )


def loadXtCpp(xtCppPath: Path) -> list[str]:
    logging.info(f"Reading '{xtCppPath}'.")
    return xtCppPath.read_text().splitlines()


# ===== MAIN =====
def main():
    args = ParsedArgs()

    xtCppLines = loadXtCpp(args.xtCppPath)
    logging.info(f"Read {len(xtCppLines)} lines.")

    parseResult = parseXtCpp(
        str(args.xtCppPath),  # tbd
        args.xtCppPath.name,  # tbd
        args.xtCppComponent,
        xtCppLines,
        os.path.pathsep.join([str(x) for x in args.groupsDirsPath]),  # tbd
    )
    logging.info(f"Parsing success for '{args.xtCppPath}'.")

    testcasesToPartsMapping = generateTestcasesToPartsMapping(parseResult)
    partsContents = generatePartsFromXtCpp(
        str(args.xtCppPath),  # tbd
        args.xtCppPath.name,  # tbd
        args.xtCppComponent,
        parseResult,
        testcasesToPartsMapping,
        xtCppLines,
        args.useLineDirectives,
    )
    logging.info(f"Parts contents generated for '{args.xtCppPath}'.")
    writeOutputForXtCpp(
        str(args.stampFilePath), # tbd
        str(args.outDirectory),  # tbd
        args.xtCppComponent,
        partsContents,
        testcasesToPartsMapping,
    )

    return 0


if __name__ == "__main__":
    try:
        main()
        logging.info("Success")
    except XtCppParseError as e:
        logging.error(e)
        exit(1)
