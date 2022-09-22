import os
import sys

from pathlib import Path

def add_lib_path():
    p = Path(__file__).parent.parent.parent / "lib" / "python"
    sys.path = [p.as_posix()] + sys.path
