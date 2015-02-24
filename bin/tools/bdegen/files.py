"""
Bloomberg Python Package - files.py

Common functions for working with files and paths.
"""

__all__ = ["createfile",
           "createdir",
           "parentdir",
           "readlines",
           "concatfiles",
           "run"]


def createfile(filepath, overwrite=False):
    """ Creates an empty file.  Optionally can wipe out existing file. """
    import os.path
    if overwrite or not os.path.exists(filepath):
        newfile = open(filepath, "w")
        newfile.close()


def createdir(path):
    """ Create the specified directory by creating all intermediate
        directories as necessary. """
    import os
    if not os.path.isdir(path):
        createdir(os.path.dirname(path))
        os.mkdir(path)


def parentdir(path):
    """ Returns the parent directory of the given directory or file.
        Ex:  parentdir("C:\work\abc.txt") = C:\
        Ex:  parentdir("C:\work\program\") = C:\work   """
    import os
    path = os.path.normpath(os.path.abspath(path))
    return os.path.dirname(path)


def readlines(filepath, stripnewlines=True, stripblanklines=True):
    """ Reads all lines from a file into a list while optionally
        stripping off trailing newlines and getting rid of blank lines. """
    lines = open(filepath, "r").readlines()
    result = []
    for line in lines:
        if stripnewlines and line.endswith("\n"):
            line = line[:-1]
        if not stripblanklines or len(line) > 0:
            result.append(line)
    return result


def readtext(filepath):
    """ Reads all the text from a file and returns the string """
    with open(filepath, "r") as infile:
        return infile.read()


def writeline(filepath, line, addnewline=False):
    """ Writes out 'line' to 'filepath'.  Add a '\n' to end of the string if
        'addnewlines' is True
    """
    suffix = addnewline and "\n" or ""
    with open(filepath, "w") as outfile:
        outfile.write(line + suffix)


def writelines(filepath, lines, addnewlines=True, newlineonlastitem=False):
    """ Writes a list of strings 'lines' to 'filepath'.  Add a '\n' to end
        of each item in 'lines' if 'addnewlines' is True.  If True, then
        'newlineonlastitem' determines whether the last item gets one added.
    """
    suffix = addnewlines and "\n" or ""
    lastsuffix = (addnewlines and newlineonlastitem) and "\n" or ""
    with open(filepath, "w") as outfile:
        for line in lines:
            if line == lines[-1]:
                outfile.write(line + lastsuffix)
            else:
                outfile.write(line + suffix)


def concatfiles(outfile, *infiles):
    """ Concatenate the contents of each 'infiles' and write into 'outfile'
        one right after the other. """
    with open(outfile, "w") as fout:
        for filename in infiles:
            with open(filename, "r") as fin:
                fout.writelines(fin.readlines())


def getexecutingpath():
    """ Return the full path of the script currently executing """
    import os
    import sys
    return os.path.realpath(
        os.path.abspath(os.path.join(os.getcwd(), sys.argv[0])))


def run(cmd):
    """ Run a process with arguments. Return the status and output. """
    import subprocess
    proc = subprocess.Popen(cmd,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            shell=True)
    out, err = proc.communicate()
    if out is None:
        out = ""
    if err is None:
        err = ""
    return int(proc.returncode), out, err

__copyright__ = """
Copyright (C) Bloomberg L.P., 2010
All Rights Reserved.
Property of Bloomberg L.P. (BLP)
This software is made available solely pursuant to the
terms of a BLP license agreement which governs its use.
"""
