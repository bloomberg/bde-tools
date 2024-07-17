from __future__ import annotations

import argparse
import logging
import os

from dataclasses import dataclass

from lib.generateParts import generateTestcasesToPartsMapping
from lib import (
    sourceFileOpen,
    parseComponentName,
    generatePartsFromXtCpp,
    parseXtCpp,
    XtCppParseError,
    writeOutputForXtCpp,
)
from lib.myConstants import MY_CONTROL_COMMENT_PREFIX


__version__: str = "0.0.1"
__prog__: str = os.path.basename(__file__).split(".", maxsplit=1)[0]


def _verifyOutputDirectoryArg(outputDirectoryPath: str) -> str:
    if not os.path.isdir(outputDirectoryPath):
        raise argparse.ArgumentTypeError(f"{outputDirectoryPath!r} is not a directory")

    if not os.access(outputDirectoryPath, os.R_OK):
        raise argparse.ArgumentTypeError(f"{outputDirectoryPath!r} is not readable")

    if not os.access(outputDirectoryPath, os.W_OK):
        raise argparse.ArgumentTypeError(f"{outputDirectoryPath!r} is not writable")

    return outputDirectoryPath


def _verifyGroupsDirectoryArg(groupsDirectoryPath: str) -> str:
    if not os.path.isdir(groupsDirectoryPath):
        raise argparse.ArgumentTypeError(f"{groupsDirectoryPath!r} is not a directory")

    if not os.access(groupsDirectoryPath, os.R_OK):
        raise argparse.ArgumentTypeError(f"{groupsDirectoryPath!r} is not readable")

    return groupsDirectoryPath


def _verifyStampPathArg(stampFileName: str) -> str:
    dirname, filename = os.path.split(stampFileName)

    if dirname:
        if not os.path.isdir(dirname):
            raise argparse.ArgumentTypeError(f"{dirname!r} is not a directory")

        if not os.access(dirname, os.R_OK):
            raise argparse.ArgumentTypeError(f"{dirname!r} is not readable")

        if not os.access(dirname, os.W_OK):
            raise argparse.ArgumentTypeError(f"{dirname!r} is not writable")

    if os.path.exists(stampFileName):
        if not os.path.isfile(stampFileName):
            raise argparse.ArgumentTypeError(f"{stampFileName!r} is not a file")

        if not os.access(stampFileName, os.R_OK):
            raise argparse.ArgumentTypeError(f"{stampFileName!r} is not readable")

        if not os.access(stampFileName, os.W_OK):
            raise argparse.ArgumentTypeError(f"{stampFileName!r} is not writable")

    return stampFileName


def _applyMacrosToMdText(mdName: str, mdText: str) -> str:
    myName = os.path.splitext(os.path.basename(os.path.realpath(__file__)))[0]
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
    syntaxHelp = os.path.join(os.path.dirname(os.path.realpath(__file__)), f"{name}.t.md")
    with open(syntaxHelp, "rt") as helpMdFile:
        return _applyMacrosToMdText(name, helpMdFile.read())


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


class _HelpAction(argparse._HelpAction):
    def __init__(
        self,
        option_strings,
        dest,
        nargs=None,
        const=None,
        default=None,
        type=None,
        choices=None,
        required=False,
        help=None,
        metavar=None,
    ):
        super().__init__(option_strings)
        self.nargs = "?"
        self.choices = _HELP_TEMPLATES
        if help is not None:
            self.help = help

    def __call__(self, parser, namespace, values, option_string=None):
        if values is None:
            parser.print_help()
        else:
            assert isinstance(values, str)
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
            if console.width > 80:
                console.width = 80
            console.print(
                RichMarkdown(_getInteractiveHelpMdText(values), style="github"),
                highlight=False,
                markup=False,
            )
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
        myName = os.path.splitext(os.path.basename(os.path.realpath(__file__)))[0]
        for mdName in _HELP_TEMPLATES:
            mdText = _getHelpDumpMdText(mdName)
            mdOutName = f"{myName}-{mdName}.md"
            outName = os.path.join(namespace.outdir, mdOutName)
            print(f"    Writing {outName}...")
            with open(outName, "wt") as outFile:
                outFile.write(mdText)
        print("Done.")

        exit(0)


@dataclass
class ParsedSourcePathArg:
    full: str
    directory: str
    filename: str
    suffixes: str
    qualifiedComponentName: str
    group: str
    package: str
    componentName: str


class _XtCppPathArgAction(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        if not isinstance(values, str):
            parser.error(f"Unexpected command line argument type: {values!r}")

        if not os.path.isfile(values):
            parser.error(f"{values!r} is not a file")

        if not os.access(values, os.R_OK):
            parser.error(f"{values!r} is not readable")

        dirPart, filePart = os.path.split(values)
        qualifiedComponentName, suffixes = filePart.split(".", maxsplit=1)

        if suffixes.lower() != "xt.cpp":
            parser.error(f"{filePart!r} does not have the xt.cpp test driver suffix")

        result = ParsedSourcePathArg(
            values,
            dirPart,
            filePart,
            suffixes,
            qualifiedComponentName,
            *parseComponentName(qualifiedComponentName, errorFunc=parser.error),
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
        choices=["syntax"],
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
    xtCppFull: str
    xtCppFilename: str
    xtCppComponent: str
    outDirectory: str
    stampFilePath: str
    groupsDirsPath: str
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

        xtCppPath: ParsedSourcePathArg = args.xtCppPath
        self.xtCppFull = xtCppPath.full
        self.xtCppFilename = xtCppPath.filename
        self.xtCppComponent = xtCppPath.qualifiedComponentName

        self.outDirectory = args.outdir

        self.stampFilePath = args.stampfile if args.stampfile else f"{self.xtCppFilename}.stamp"

        # If there is no path in the stamp file argument put it into the output directory
        if not os.path.dirname(self.stampFilePath):
            self.stampFilePath = os.path.join(self.outDirectory, self.stampFilePath)

        # Add the 'groups' directory from the input file to the groups search path, if the path
        # actually ends in .../groups/grp/grppkg (like .../groups/bsl/bslstl)
        groupDir, package = os.path.split(args.xtCppPath.directory)
        if groupDir:
            if not package:  # There was a path separator at the end of `directory``
                groupDir, package = os.path.split(args.xtCppPath.directory[:-1])

            if package:
                groupsDir, group = os.path.split(groupDir)
                if os.path.basename(groupsDir) == "groups" and group == args.xtCppPath.group:
                    args.groups_directory.append(groupsDir)

        self.groupsDirsPath = os.path.pathsep.join(args.groups_directory)

        lineDirectivesStr = (
            self.useLineDirectives if self.useLineDirectives is not None else "Not Set"
        )
        logging.info(
            "Effective Command Line Arguments:\n"
            f"    Log level         : {self.loglevel!r}\n"
            f"    Input xt.cpp file : {self.xtCppFull!r}\n"
            f"    Output directory  : {self.outDirectory!r}\n"
            f"    Stamp file        : {self.stampFilePath!r}\n"
            f"    Groups search path: {self.groupsDirsPath!r}\n"
            f"    Line directives   : {lineDirectivesStr}"
        )


def loadXtCpp(xtCppFilename: str) -> list[str]:
    logging.info(f"Reading {xtCppFilename!r}.")
    with sourceFileOpen(xtCppFilename, "r") as xtcppFile:
        return xtcppFile.read().splitlines()


# ===== MAIN =====
def main():
    args = ParsedArgs()

    xtCppLines = loadXtCpp(args.xtCppFull)
    logging.info(f"Read {len(xtCppLines)} lines.")

    parseResult = parseXtCpp(
        args.xtCppFull, args.xtCppFilename, args.xtCppComponent, xtCppLines, args.groupsDirsPath
    )
    logging.info(f"Parsing success for {args.xtCppFull!r}.")

    testcasesToPartsMapping = generateTestcasesToPartsMapping(parseResult)
    partsContents = generatePartsFromXtCpp(
        args.xtCppFull,
        args.xtCppFilename,
        args.xtCppComponent,
        parseResult,
        testcasesToPartsMapping,
        xtCppLines,
        args.useLineDirectives,
    )
    logging.info(f"Parts contents generated for {args.xtCppFull!r}.")
    writeOutputForXtCpp(
        args.stampFilePath,
        args.outDirectory,
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
