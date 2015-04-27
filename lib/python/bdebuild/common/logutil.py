"""Logging facilities.
"""

from __future__ import print_function

import sys

def warn(msg, **kw):
    to_log(msg)
    _warn_nolog(msg, **kw)

def info(msg, **kw):
    to_log(msg)
    _info_nolog(msg, **kw)

def _warn_nolog(msg, **kw):
    print(msg, file=sys.stderr)

def _info_nolog(msg, **kw):
    print(msg)

def to_log(msg):
    pass

def fatal(msg, **kw):
    print(msg, file=sys.stderr)
    sys.exit(1)


def msg(start, end, **kw):
    print('%s: %s' % (start, end))


def start_msg(msg, **kw):
    print(msg + ': ')


def end_msg(msg, **kw):
    print(msg)

# -----------------------------------------------------------------------------
# Copyright 2015 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE -----------------------------------
