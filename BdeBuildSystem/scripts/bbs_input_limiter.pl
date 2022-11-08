#!/usr/bin/env perl


# This used to be a python script.  However, since we want to pass through
# all bytes unchanged regardless of encoding, it's simpler to reimplement this
# in perl.

use warnings;
use strict;

my $max_count = 5000;

$|++;

while (<>) {
    print;

    last if 0 == --$max_count;
}

if ($max_count <= 0) {
     print("###############################\n");
     print("#### OUTPUT LIMIT EXCEEDED ####\n");
     print("###############################\n");
 
     # get rid of any remaining input, without causing SIGPIPE upstream
     while (<>) {
         # noop
     }
}


# Old python impl:
# import sys
# 
# line_count = 0
# max_count = 5000
# 
# for line in sys.stdin:
#     if line_count > max_count:
#         break
# 
#     sys.stdout.write(line)
#     line_count += 1
# 
# if line_count > max_count:
#     print("###############################\n")
#     print("#### OUTPUT LIMIT EXCEEDED ####\n")
#     print("###############################\n")
# 
#     # get rid of any remaining input, without causing SIGPIPE upstream
#     for line in sys.stdin:
#         pass
# 


