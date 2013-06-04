#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(strftime);

if(@ARGV!=1) {
    print STDERR "USAGE: $0 baseFilenameToLogTo\n";
    exit(1);
}

my $baseFilename=shift;
$baseFilename.="." . strftime("%Y%m%d-%H%M%S",localtime);

open(OUTPUT,">$baseFilename") or die "Can't open $baseFilename, error $!";

select OUTPUT;
$|++;

while(<STDIN>) {
    printf OUTPUT "%s: %s",(strftime("%H:%M:%S",localtime)),$_;
}

close(OUTPUT);

