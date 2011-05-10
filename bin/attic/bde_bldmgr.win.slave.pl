#!/usr/bin/perl -w
use strict;

# Windows slave script for bde_builder - should not be directly invoked
#
# Outputs result string in form:
#   FAILED:opt[.../make.log.opt],dbg[.../make.log.dbg]|SUCCEEDED:dbg_exc

use File::Basename;
use File::Path;
use File::Copy;
use Getopt::Long;
use POSIX qw(uname);
use IO::Handle;
use FindBin qw($Bin);

umask 002;

STDOUT->autoflush(1);

my $prog = basename($0);
#<<<win
my $bindir = "$FindBin::Bin";
#>>>win

my %opts;

unless (GetOptions(\%opts,qw[
    architecture=s
    debug+
    express
    group=s
    flags=s
    root=s
    verbose+
    logdir=s
])) {
    die "Usage: $prog [-a <arch>] [-d] [-e] [-f <flags>] [-r <root>] [-v] [-l <logdir>] -g <group|package>\n";
}

my $arch    = $opts{architecture};
my $express = $opts{express} || 0;
my $root    = $opts{root} || $ENV{BDE_ROOT};
my $element = $opts{group};
my $flags   = $opts{flags} || '';
my $verbose = $opts{verbose} || 0;
my $debug   = $opts{debug} || 0;
my $logdir  = $opts{logdir};

my ($return_string,$err_targets,$ok_targets);

#>>>win
chdir($root);
system("cleartool update");
#<<<win

my @lt = localtime();
my $dtag = ($lt[5] + 1900) . ($lt[4] + 1) . "$lt[3]-$lt[2]$lt[1]$lt[0]";

unless ($logdir) {
    $logdir=$bindir;
    $logdir =~ s{/[^/]+/?$}{/logs};
}

if (! -d $logdir) {
    mkpath($logdir, 0, 0777) or die "cannot make '$logdir': $!\n";
}
my $logarch = $arch || lc((uname)[0]);
$logarch =~ s/\s+/_/g;
my $slavelog = "$logdir/$prog.$element.$logarch.$dtag.log";

open(SLAVELOG, "> $slavelog") or die "cannot open build output file: $!";
SLAVELOG->autoflush(1);
print SLAVELOG "** $prog STARTING **\n";
print "** $prog starting\n" if $verbose;

for my $target (@ARGV) {
    my $cmd = "$bindir/bde_build.pl -r $root -t $target ";
    $cmd .= "-a $arch " if defined $arch;
    $cmd .= "-e " if $express;
    $cmd .= "$flags $element 2>&1";
    print SLAVELOG "** COMMAND BEING RUN: $cmd\n";
    print "-- running command: $cmd\n" if $verbose>1;
    my $output = `$cmd`;

    if ($? != 0) {
	$err_targets .= "," if $err_targets;
	if ($output =~ /\(see (.*)\)/m) {
	    #>>>win
	    my $logfile = $1;
	    my $logfile_share = $logdir . "/" . basename($logfile);
	    copy($logfile, $logfile_share);
	    $err_targets .= "$target\[see $logfile_share]";
	    #<<<win
	} elsif ($output =~ /^(ERROR:.*)/m) {
	    $err_targets .= "$target\[$1]";
	} else {
	    $err_targets .= "$target\[see $slavelog]";
	}
    } else {
	$ok_targets .= "," if $ok_targets;
	$ok_targets .= "$target";
    }

    print SLAVELOG "$output";

    if ($verbose>2) {
	$output=~s|^|<< |omg;
	print $output;
    }
}

close SLAVELOG;

$err_targets and $return_string = "FAILED:$err_targets";

if ($ok_targets) {
    $return_string .= "|" if $err_targets;
    $return_string .= "SUCCEEDED:$ok_targets";
}

print $return_string;
