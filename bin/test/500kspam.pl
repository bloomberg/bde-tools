#!/opt/bb/bin/perl

use warnings;
use strict;

$ENV{SPAMLIMIT}//=500000;

if (@ARGV and $ARGV[0] > 6) {
    exit -1;
}

foreach (1..$ENV{SPAMLIMIT}) {
    print qq{Error ../../bde/groups/bsl/bslstl/bslstl_priorityqueue.t.cpp(1353): !"'TestComparator' should never be move-constructed"    (failed)\n};
}

if (@ARGV and $ARGV[0] > 3) {
    exit 0+$ARGV[0];
}
