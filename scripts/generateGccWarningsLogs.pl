#!/usr/bin/env perl

use strict;
use warnings;

use POSIX qw(strftime);

my $GCC_VER = "4.7.2";

if(@ARGV<2) {
    print STDERR "USAGE: $0 buildtype logpath [recipients]\n";
    exit 1;
}

my ($buildtype, $logpath)=@ARGV;

my $recipients = "";

if(@ARGV==3) {
        $recipients = $ARGV[2];
}

my $date=strftime("%Y%m%d",localtime);

open(GREP,"grep '\.h:.* warning:' $logpath/*$date*-SunOS-*-gcc-${GCC_VER}*|")
        or die "Unable to open pipe from grep, error $!";

my (%list, %s);

my $warningCount=0;

while(<GREP>) {
    #next if /TEST-/;

    next if /warning: +'RCSId.*' defined but not used/i;

    next if /anonymous variadic macros were introduced in C99/;

    s/.*COMPILE:  [0-9]+://;
    s{^/.+/}{};
    s{^\..*/}{};

    my $simpleLine=$_;
    $simpleLine=~s/`/'/g;

    if(/^(..[^_]+)_/) {
        if(!$s{$simpleLine}++) {
            push @{$list{$1}},$_;
            ++$warningCount;
        }
    }
}

close(GREP);

my $warninglog="/home/bdebuild/logs/gcc-header-warnings-in-$buildtype.".strftime("%Y%m%d-%H%M%S",localtime);
my $plural=($warningCount==1)?"":"s";

my $subject=qq{*** $warningCount gcc ${GCC_VER} warning$plural in $buildtype today ***************};

open(LOG,">$warninglog") or die "Unable to open $warninglog, error $!";

if(!keys %list) {
    print LOG "No warnings in $buildtype, woohoo!!\n";
    $subject = qq{NO gcc Warnings in $buildtype today.  None!};
}
else {
    print LOG "SUMMARY:\n";

    foreach(sort keys %list){
        my $count = scalar @{$list{$_}};
        printf LOG "%-20s %5d warning%s\n",$_,$count,($count==1)?"":"s";
    }

    foreach(sort keys %list){
        print LOG "\n\n======== $_ ==============\n";
        print LOG @{$list{$_}};
    }
}

close(LOG);

if(!length $recipients) {
    open(RECIPIENTS,"</home/bdebuild/gcc-warnings-$buildtype-recipients") or do {
        warn "No recipients file in /home/bdebuild/gcc-warnings-$buildtype-recipients, error $!";
        exit 1;
    };

    $recipients=<RECIPIENTS>;
    chomp $recipients;
    $recipients=quotemeta($recipients);
    close(RECIPIENTS);
}

# change to a 0 while testing to just type out results to screen
if (1) {
    system qq{ssh -2 -x sundev2 /bb/bin/ratmail -s '"$subject"' $warninglog $recipients};
}
else {
    system qq{cat $warninglog};
}
