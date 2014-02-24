#!/usr/bin/env python

import os
import sys
import subprocess
from optparse import OptionParser

def pathList(path):     # return a list of paths from a ':' separated string
    """
    Return a list containing the set of paths encoded in the specified 'path'
    environment variable style string (':' separated on UNIX, ';' on windows).
    """
    return path.split(os.pathsep)

def getBranch(path):    # print the git status at the specified 'path'
    """
    Return the current branch for the git repository at the specified 'path'.
    """
    os.chdir(path)
    return subprocess.check_output(
                        ["git", "rev-parse", "--abbrev-ref", "HEAD"]).rstrip()

def getStatus(path):
    """
    Returns the current status of the specified 'path'.
    """
    os.chdir(path)
    return subprocess.check_output(
                        ["git", "status", "-s"]).rstrip()

def getDiff(path):
    """
    Returns the current diff for the specified 'path'.
    """
    os.chdir(path)
    return subprocess.check_output(
                        ["git", "diff"]).rstrip()

def checkoutBranch(path, branch):
    """
    Perform a 'git checkout' for the specified 'branch' in the specified
    'path'.
    """
    os.chdir(path)
    subprocess.check_call(["git", "checkout", branch]);

def checkoutBranchAndPull(path, branch, forceCheckout):
    """
    Perform a 'git checkout' for the specified 'branch' in the specified
    'path'.   If 'forceCheckout' is 'false', throw an exception if there are
    uncommitted changes in the repository.
    """
    os.chdir(path)
    if (not forceCheckout):
        try:
            subprocess.check_call(
                ["git", "diff-files", "--quiet", "--ignore-submodules"])
        except subprocess.CalledProcessError:
            print "##### {0} repo state is not clean - aborting".format(path)
            raise

    subprocess.check_call(["git", "checkout", branch]);
    subprocess.check_call(["git", "pull", "--ff-only"])


USAGE = "Usage: %prog [options] [path]*"
DESCRIPTION = """
For each of the listed paths: 'git checkout' the specified branch (or 'master'
if no branch is supplied), and perform a 'git pull'.  If no paths are
provided, the checkout and pull will be peformed on the list of repositories
in the 'BDE_PATH' environment variable'.
""".strip()

EPILOG = """
Note that this script will abort if one of the git repositories contains
uncommitted changes (unless the --force option is used) and attempt to return
any modified repositories to their original branches.
""".strip()

def main():
    parser = OptionParser(usage = USAGE,
                          description = DESCRIPTION,
                          epilog = EPILOG);
    parser.add_option("-b",
                      "--branch",
                      action="store",
                      dest="branch",
                      type="string",
                      default="master" ,
                      help="the branch name to checkout")
    parser.add_option("-f",
                      "--force",
                      action="store_true",
                      dest="force",
                      default=False ,
                      help="force a checkout (even with uncommitted changes)")
    parser.add_option("-s",
                      "--status",
                      action="store_true",
                      dest="status",
                      default=False ,
        help="Print status for selected repos rather than performing checkout")
    parser.add_option("-d",
                      "--diff",
                      action="store_true",
                      dest="diff",
                      default=False ,
        help="Print diffs for selected repos rather than performing checkout")

    (options, args) = parser.parse_args()

    if (len(args) == 0):
        paths = pathList(os.environ['BDE_PATH'])
    else:
        paths = map(lambda directory: os.path.join(os.getcwd(), directory),
                    args)  #append

    initialBranch = {}
    for path in paths:
        branch = getBranch(path)
        if not (options.status or options.diff):
            print "{0:30}: {1}".format(path, branch.rstrip())
            sys.stdout.flush()
        initialBranch[path]=branch

    if options.status:
        for path in paths:
            status = getStatus(path)
            if len(status):
                print "{0:30}: branch {1:30}".format(path, initialBranch[path])
                for line in status.rstrip('\n').split('\n'):
                    print "#\t{0}".format(line)
            else:
                print "{0:30}: branch {1:30} ** STATUS IS CLEAN **".\
                                              format(path, initialBranch[path])
            sys.stdout.flush()

        exit(0)

    if options.diff:
        for path in paths:
            status = getDiff(path)
            if len(status):
                print "####### {0:30}: branch {1:30}".format(path, initialBranch[path])
                for line in status.rstrip('\n').split('\n'):
                    print line
            else:
                print "{0:30}: branch {1:30} ** DIFF IS CLEAN **".\
                                              format(path, initialBranch[path])
            sys.stdout.flush()

        exit(0)


    donePaths = []
    for path in paths:
        try:
            print "\n{0}\n===========================".format(path)
            sys.stdout.flush()
            checkoutBranchAndPull(path, options.branch, options.force)
            donePaths.append(path)
        except subprocess.CalledProcessError:
            # Unwind all the 'donePaths' elements back to their 'initialBranch'.
            for unwindPath in donePaths:
                print "\nUNWINDING {0} back to {1}".format(unwindPath,
                                                     initialBranch[unwindPath])
                print "=============================================="
                sys.stdout.flush()
                checkoutBranch(unwindPath,
                               initialBranch[unwindPath])
            exit(1)

if __name__ == "__main__":
    main()
