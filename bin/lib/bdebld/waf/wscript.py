# This file is used to preserve backwards compatbility with an older version of
# wscript.

import os
import sys

import waflib.Logs

top = '.'
out = 'build'


def _get_tools_path(ctx):
    upd = os.path.dirname
    python_libdir = os.path.join(
        upd(upd(upd(upd(upd(os.path.realpath(__file__)))))), 'lib', 'python')
    return [python_libdir, os.path.join(python_libdir, 'bdebuild', 'legacy')]


def options(ctx):
    waflib.Logs.warn(
        'The wscript that you are using is out of date.  '
        'Please copy the new version from bde-tools/etc/wscript.')
    ctx.load('bdebuild.waf.wscript', tooldir=_get_tools_path(ctx))


def configure(ctx):
    ctx.load('bdebuild.waf.wscript', tooldir=_get_tools_path(ctx))


def build(ctx):
    sys.path += _get_tools_path(ctx)
    ctx.load('bdebuild.waf.wscript', tooldir=_get_tools_path(ctx))
