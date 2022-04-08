#!/usr/bin/env python3.8

import sys

line_count = 0
max_count = 5000

for line in sys.stdin:
    if line_count > max_count:
        break

    sys.stdout.write(line)
    line_count += 1

if line_count > max_count:
    print("###############################\n")
    print("#### OUTPUT LIMIT EXCEEDED ####\n")
    print("###############################\n")

    # get rid of any remaining input, without causing SIGPIPE upstream
    for line in sys.stdin:
        pass
