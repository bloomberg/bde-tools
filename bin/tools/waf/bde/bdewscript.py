# This file is used to preserve backwards compatbility with an older version of
# the wscript.

import os
import sys

import waflib.Logs

top = '.'
out = 'build'


def _get_tools_path(ctx):
    upd = os.path.dirname
    base = upd(upd(upd(upd(os.path.realpath(__file__)))))
    return [os.path.join(base, 'lib'),
            os.path.join(base, 'lib', 'legacy')]


def options(ctx):
    waflib.Logs.warn(
        'The wscript in your repo is out of date and refers to a deprecated '
        'library location.  Please copy the new one from etc/wscript of the '
        'bde-tools repo.')
    ctx.load('bdebld.waf.wscript', tooldir=_get_tools_path(ctx))


def configure(ctx):
    ctx.load('bdebld.waf.wscript', tooldir=_get_tools_path(ctx))


def build(ctx):
    sys.path += _get_tools_path(ctx)
    ctx.load('bdebld.waf.wscript', tooldir=_get_tools_path(ctx))
