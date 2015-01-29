#!/usr/bin/env python

import os
import sys


def _get_tools_path():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                        'tools')
    return path

tools_path = _get_tools_path()
sys.path = [tools_path] + sys.path

import bdetest.entry


if __name__ == '__main__':
    bdetest.entry.main()
