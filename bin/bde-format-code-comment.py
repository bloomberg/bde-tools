import shutil
import subprocess
import sys
import argparse
import re
import os

g_bdeFormatExecutable = shutil.which("bde-format")
if g_bdeFormatExecutable is None:
    print(
        (
            "bde-format not found.  "
            "Please provide a valid executable or ensure that 'bde-format' is in PATH.\n"
        )
    )
    sys.exit(1)


def doBdeFormat(args, input) -> str:
    """
    Use 'bde-format' to format the specified 'str' according to the BDE
    formatting rules.
    """
    format = subprocess.Popen(
        [g_bdeFormatExecutable] + args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        encoding="utf8",
    )
    input = input.replace(os.linesep, "\n")

    out, _ = format.communicate(input=input)
    return out


doLog = False


class Log:
    def __init__(self):
        if doLog:
            self.file = open("log", "wb")

    def writeln(self, text):
        if doLog:
            self.file.write((text + os.linesep).encode())


def main():
    args = sys.argv[1:]
    text = sys.stdin.buffer.read().decode()

    log = Log()
    log.writeln(str(args))
    log.writeln(text)

    for i, arg in enumerate(args):
        if arg.startswith("-offset"):
            offset_arg = i
            offset = int(arg[len("-offset=") :])
        if arg.startswith("-style"):
            style_arg = i
        if arg.startswith("-fallback-style"):
            args[i] = "-fallback-style=BDE"

    code_block_span = [
        text.rfind("//..", 0, offset),
        text.find("//..", offset),
    ]
    code_offset = (
        code_block_span[0]
        - text.rfind(os.linesep, 0, code_block_span[0])
        - len(os.linesep)
    )

    # If we're not in a code-block comment, just format

    if code_block_span[0] == -1 or code_block_span[1] == -1:
        print(doBdeFormat(args, text))
        sys.exit(0)

    for l in text[code_block_span[0] : code_block_span[1] + 4].split(
        os.linesep
    ):
        if not l.strip().startswith("//"):
            print(doBdeFormat(args, text))
            sys.exit(0)

    # Check if we're outside a balanced '//..' set

    if len(re.findall("(//\.\.)", text[: code_block_span[0]])) % 2 == 1:
        print(doBdeFormat(args, text))
        sys.exit(0)

    code_block_span[0] = code_block_span[0] + 4

    code_block = text[code_block_span[0] : code_block_span[1]]
    uncommented = re.sub(
        "^" + " " * code_offset + "//",
        " " * (code_offset + 2),
        code_block,
        flags=re.MULTILINE,
    )

    min_spaces = 80
    for l in uncommented.split(os.linesep):
        stripped = l.lstrip()
        if len(stripped) != 0:
            spaces = len(l) - len(stripped)
            min_spaces = min(min_spaces, spaces)

    tab_level = int(min_spaces / 4)

    pre = os.linesep + "void f() {" * tab_level
    post = "}" * tab_level + os.linesep

    offset = offset + len(pre)
    args[offset_arg] = f"-offset={offset}"
    args[style_arg] = "-style"
    args.insert(style_arg + 1, "{BasedOnStyle: BDE, ColumnLimit: 79}")

    text_subbed = (
        text[: code_block_span[0]]
        + pre
        + uncommented
        + post
        + text[code_block_span[1] :]
    )
    log.writeln(text_subbed)

    min_offset = code_block_span[0] + len(pre)
    max_offset = min_offset + len(uncommented)

    out = doBdeFormat(args, text_subbed)
    log.writeln(out)

    result = []
    for l in out.splitlines():
        linesep = "&#10;" if l.find("&#13;") == -1 else "&#13;&#10;"

        l = re.sub(f"{linesep}[ ]{{{code_offset + 2}}}", linesep, l)
        l = l.replace(linesep, linesep + " " * code_offset + "//")
        match = re.search("offset='(\d+)'", l)
        if match:
            offset = int(match.group(1))
            if offset < min_offset or offset >= max_offset:
                continue
            offset = offset - len(pre)
            result.append(
                l[: match.start(1)] + str(offset) + l[match.end(1) :]
            )
        else:
            result.append(l)

    log.writeln(os.linesep.join(result))

    print("\n".join(result))


if __name__ == "__main__":
    main()
