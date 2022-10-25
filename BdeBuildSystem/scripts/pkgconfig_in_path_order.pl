#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions qw<catfile>;

# Given a library list, return a list grouped by the pkg-config paths
my @pkg_config_path = split(/:/, $ENV{'PKG_CONFIG_PATH'});
my @libs;

# Initialize the grouped list of libraries
my $group = 0;
foreach my $path (@pkg_config_path) {
    $libs[$group++] = [];
}

foreach my $lib (@ARGV) {
    $group = 0;
    # Loop over the different pkg-config paths
    foreach my $path (@pkg_config_path) {
        # if the pkg-config file exists, add it to the group
        if (-e catfile($path, "$lib.pc")) {
            last;
        }
        $group++;
    }
    push @{$libs[$group]}, $lib;
}

# Return the reordered list of libraries
print join ";", map { @$_ } @libs;
