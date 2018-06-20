#!/usr/bin/env python

import subprocess
import sys
import os
import argparse

try:
    p = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (out, err) = p.communicate()
except Exception as e:
    print('Execution failure: %s' % str(e))
    sys.exit(-1)

msg = ''
if out:
    out = out.decode(sys.stdout.encoding or 'iso8859-1')
    out = '\n'.join([l for l in out.split('\n') if not l.startswith('Note: including file:')])
    msg = msg + out

if err:
    err = err.decode(sys.stderr.encoding or 'iso8859-1')
    msg = msg + err

if msg:
    parser = argparse.ArgumentParser()
    parser.add_argument('-o')
    parser.add_argument('-c')
    (args, unparsed) = parser.parse_known_args(sys.argv[2:])

    src_str = None
    for opt in [args.c, args.o]:
        if opt:
            src_str = opt
            break

    if not src_str:
        linkOutArg = '/out:'
        for arg in unparsed:
            if arg.startswith(linkOutArg):
                src_str = arg[len(linkOutArg):]
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
            msg.strip() == src_str or
            msg.strip().startswith('Creating library ')):
        sys.exit(p.returncode)

    if p.returncode == 0:
        status_str = 'WARNING'
    else:
        if 'bde_runtest' in sys.argv[2]:
            status_str = 'TEST'
        else:
            status_str = 'ERROR'

    sys.stderr.write('[{} ({})] <<<<<<<<<<\n{}>>>>>>>>>>\n'.format(src_str, status_str, msg))

sys.exit(p.returncode)