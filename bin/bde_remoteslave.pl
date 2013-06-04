#!/usr/bin/env perl

use strict;
use warnings;

use Cwd;
use Getopt::Long;
use POSIX qw(uname);

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Remote::Exec;
use File::Basename;

use Symbols qw(EXIT_FAILURE EXIT_SUCCESS);

#------------------------------------------------------------------------------

my $prog = basename $0;
my $oldfh = select(STDERR); $| = 1;
select(STDOUT); $| = 1; select($oldfh);
my $plat = (uname)[0];

# process args
my %opts;
my $usage = "usage: $prog <target>";
die $usage if ! defined($ARGV[0]) or defined($ARGV[1]);

my $fulldir = $ARGV[0];
my $pkg = basename($fulldir);

my $log = "$FindBin::Bin/../LOGS/$prog.$pkg.$plat." . (getpwuid($<))[0];
setLog($log);

my $output;
my $execStr;

# read in envfile
my $envFile = $prog;
$envFile =~ s-\.pl--;
$envFile = "$FindBin::Bin/../etc/$envFile.env";
readEnvfile($envFile) or finish(1, "cannot read envfile $envFile");

# setup
chdir($fulldir) or finish(1, "cannot chdir to $fulldir");
mkdirp($plat) or finish(1, "cannot mkdirp $plat");
chdir($plat) or finish(1, "cannot chdir to $plat");
mkdirp($pkg) or finish(1, "cannot mkdirp $pkg");
chdir($pkg) or finish(1, "cannot chdir to $pkg");
$output = `cp ../../*.h .;cp ../../*.cpp .;cp -r ../../package .`;
if ($?) {
  logMsg("$output", 2);
  finish(1, "could not copy files");
}

# verify
$execStr = "bde_verify.pl $pkg";
$output = `$execStr 2>&1`;
finish(1, "$output\n SEE LOGFILE $log") if $?;

# build
$execStr = "bde_build.pl -e $pkg ";
$output = `$execStr 2>&1`;
finish(1, "$output\n SEE LOGFILE $log") if $?;
finish(0);
#------------------------------------------------------------------------------

sub finish($;$) {    
  my $rc = shift;
  my $str = shift;

  if ($rc == 1) {
    logMsg($str, 2);
    sendMail("$plat $prog", 1);
    print "FAILED%$str";
  }
  else {
    logMsg("$plat $prog COMPLETED ok", 2);
    sendMail("$plat $prog", 0); 
    print "OK%";
 }
  
  exit 0;
}
