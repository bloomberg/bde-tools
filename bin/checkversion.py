import sys

def checkversion():
    if sys.version_info[0] == 3 and sys.version_info[1] < 8:
        raise Exception("Must be using at least Python 3.8")