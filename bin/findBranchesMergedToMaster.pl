#!/bbs/opt/bin/perl

use warnings;
use strict;

# list of refs we always want to ignore
my %ignoredBranches;


my $branch = "master";

if(@ARGV) {
    $branch = shift;
}
else {
    $ignoredBranches{HEAD} = undef;
    $ignoredBranches{'heads/master'} = undef;
    $ignoredBranches{'remotes/origin/master'} = undef;
}

print "Listing branches merged into $branch\n\n";

# hash of seen abbreviated refids
my %seen;

# hash of abbreviations to full refids
my %abbreviations;


open(my $git_log_pipe,"git log $branch --decorate=full --color=never |")
    or die "Error starting git log pipe: $!";

while(<$git_log_pipe>) {
    chomp;

    s/^commit ([a-f0-9]+) \(// or next;

    my $commitId = $1;

    my $startRefidLen=10;
    my $refidLen=$startRefidLen;

    my $refid = undef;

    # We expect to do the while loop once, which will increment this to 0.  If
    # we run the loop more than once, this value will be true, and a warning
    # should be printed since 2 refs share the same 10 character prefix.
    my $isAmbiguous=-1;

    while(!defined $refid || $seen{$refid}++) {
        $refid = substr($commitId,0,$refidLen++);

        $isAmbiguous++;

        die "$commitId is not unique!" if $refidLen>length($commitId);
    }

    $abbreviations{$refid}=$commitId;

    if($isAmbiguous) {
        print "Note that $refid and ",
              $abbreviations{substr($commitId,0,$startRefidLen)}," are ambiguous\n";
    }

    s/\)$//;

    # strip tags
    s/\s*tag:.*?(,|$)//g;

    while(/\s*(.+?)(,|$)/g) {
        my $branch=$1;
        $branch=~s{refs/}{};
        next if exists $ignoredBranches{$branch};
        print "$refid $branch\n";
    }
}

