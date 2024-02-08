import subprocess
import sys
import os
import argparse
import platform


def unicodeWrite(out, str):
    try:
        out.write(str)
    except UnicodeEncodeError:
        bytes = str.encode(out.encoding or "ascii", "replace")
        if hasattr(sys.stdout, "buffer"):
            out.buffer.write(bytes)
        else:
            out.write(bytes.decode(out.encoding or "ascii", "replace"))


def limitListLines(stringAsList, limit, name):
    if len(stringAsList) > limit:
        string = "\n".join(stringAsList[:limit])
        banner = "#" * 67
        string += f"\n{banner}\n"                                    + \
                  f"####### Too many {name} lines "                  + \
                  f"({len(stringAsList)}) - truncating to {limit}\n" + \
                  f"{banner}##\n"
    else:
        string = "\n".join(stringAsList)

    return string


def limitLines(string, limit, name):
    lines = string.split(os.linesep)

    return limitListLines(lines, limit, name)


try:
    p = subprocess.Popen(
        sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    (out, err) = p.communicate()
except Exception as e:
    print(("Execution failure: %s" % str(e)))
    sys.exit(-1)

includes = ""
msg = ""
if out:
    out = out.decode(sys.stdout.encoding or "ascii", "replace")
    outlines = out.split(os.linesep)

    includes = (
        "\n".join(
            [l for l in outlines if l.startswith("Note: including file:")]
        )
        + "\n"
    )
    outlines = [
        l for l in outlines if not l.startswith("Note: including file:")
    ]

    out = limitListLines(outlines, 5000, "output")

    msg = msg + out

unicodeWrite(
    sys.stdout, includes
)  # Ninja relies on result of /showIncludes when compiling with cl

if err:
    err = err.decode(sys.stderr.encoding or "ascii", "replace")

    err = limitLines(err, 5000, "error")

    msg = msg + err

if msg:
    parser = argparse.ArgumentParser()
    parser.add_argument("-o")
    parser.add_argument("-c")
    (args, unparsed) = parser.parse_known_args(sys.argv[2:])

    src_str = None
    for opt in [args.c, args.o]:
        if opt:
            src_str = opt
            break

    if not src_str:
        linkOutArg = "/out:"
        for arg in unparsed:
            if arg.startswith(linkOutArg):
                src_str = arg[len(linkOutArg) :]
                break

    if not src_str:
        src_str = sys.argv[-1]

    try:
        src_str = os.path.basename(src_str)
    except:
        pass

    # The Visual Studio compiler always prints name of the input source
    # file when compiling and "Creating library <file>.lib and object
    # <file>.exp" when linking an executable. We try to ignore those
    # outputs using a heuristic.
    if p.returncode == 0 and (
        msg.strip() == src_str or msg.strip().startswith("Creating library ")
    ):
        sys.exit(p.returncode)

    if p.returncode == 0:
        marker_str = "WARNING"
    else:
        # Use just "_runtest" here to match either the bde or bbs versions
        if any("_runtest" in arg for arg in sys.argv):
            marker_str = "TEST"
        else:
            marker_str = "ERROR"

    # This logic handles unicode in the output.
    status_str = "{}[{} ({})] <<<<<<<<<<\n{}>>>>>>>>>>\n".format(
        "\n" if platform.system() == "Windows" else "",
        src_str,
        marker_str,
        msg,
    )

    unicodeWrite(sys.stderr, status_str)

sys.exit(p.returncode)
