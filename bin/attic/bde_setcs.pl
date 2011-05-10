#!/usr/local/bin/perl

use strict;

use File::Basename;
use Getopt::Long;
use IO::File;
use POSIX qw(tmpnam);
use Cwd;
use FindBin qw($Bin);

# constants
use constant EXIT_ERROR => 1;
use constant EXIT_SUCCESS => 0;
# unbuffer the output
my $oldfh = select(STDERR); $| = 1;
select(STDOUT); $| = 1; select($oldfh);


my $prog = basename($0);
my $bin = "$FindBin::Bin";
my %opts;

unless (GetOptions(\%opts,
                   "default|d",
                   "view|vw=s",
		   "help|h|?")) {
    usage(), exit(EXIT_ERROR);
}

usage(), exit(EXIT_SUCCESS) if $opts{help};
usage(), exit(EXIT_ERROR) unless $opts{view};
my $view = $opts{view};
my $default = $opts{default};
usage(), exit(EXIT_ERROR) if ! $default and @ARGV != 1;
usage(), exit(EXIT_ERROR) if $default and @ARGV != 0;
my $label = $ARGV[0] if @ARGV == 1;

chdir $view or die "could not chdir to $view";

my $cmd = "$bin/uplid.pl -b";
my $platform = `$cmd`;
die "cannot uplid.pl" if $?;

my $tmpcs;
my $fh;

do {
  $tmpcs = tmpnam();
} until $fh = IO::File->new($tmpcs, O_RDWR|O_CREAT|O_EXCL);

END { if ($tmpcs) { unlink($tmpcs) or die "couldn't unlink $tmpcs: $!";} }

if (! $default) {
print $fh <<EOF;
element * $label
element * CHECKEDOUT
element * .../bb/LATEST
element * /main/LATEST
EOF
}
else {
print $fh <<EOF;
element * CHECKEDOUT
element * .../bb/LATEST
element * /main/LATEST
EOF
}

print $fh "load \\infrastructure\n" if $platform eq "win";

close($fh) or die "could not close $tmpcs: $!";

# assume PATH set on windows
my $CLEARTOOL = ($platform eq "win") ? "cleartool" : "/usr/atria/bin/cleartool";
system("$CLEARTOOL setcs $tmpcs");
die "cleartool setcs $tmpcs failed: $?" if $?;

exit 0;


sub usage() {
  print STDERR "usage: $prog -v <view> <label>\n";
}
