#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Cwd;
use Fcntl qw(:flock);
use Getopt::Long;
use IO::Handle;
use Util::File::Basename qw(basename);
use POSIX qw(uname);

use Remote::Exec;
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);

STDERR->autoflush(1);
STDOUT->autoflush(1);

my $prog = basename $0;
my ($thisPlat) = (uname)[0];
#die "can only run $prog on sun" if $thisPlat ne "SunOS";

#------------------------------------------------------------------------------

# parse options

my %opts;
unless (GetOptions(\%opts, 
		   "help|h|?")) {
  usage();
  exit EXIT_FAILURE;
}
usage(), exit EXIT_SUCCESS if $opts{help};
my $configFile = shift;
my $arg = "@ARGV";
usage(), exit EXIT_FAILURE if ! $configFile;

# read config file, etc.

my $system = readConfigFile($configFile);
my $log = "$FindBin::Bin/../LOGS/$prog";
setLog($log);

# do builds

my @pids;
my %pidPlats;
my $rc;
my @okBuilds;
my @badBuilds;
while (1) {
  my ($platform, $hosts, $rshCmd, $slave) = getNextBuild();
  last if ! $platform;
  if (! $platform or ! $hosts or ! $rshCmd or ! $slave) {
    logMsg("config file corrupt", 2);
    last;
  }
  my $host = shift(@{$hosts});
  my $pid = fork();
  if ($pid == 0) {
    while (1) {
      logMsg("executing $platform $system on $host", 2);
      my $cmd = "$rshCmd ";
      $cmd .= "$host ";
      $cmd .= "$slave ";
      $cmd .= "$arg" if $arg;
      logMsg("remote command: $cmd");
      my $out = `$cmd 2>&1`;
      my $rc = $?;
      my @res = split(/%/, $out) if $out;
      if ($res[0] and $res[0] eq "OK") {
        logMsg("$host $system OK", 2);
        exit 0;
      }
      elsif ($res[0] and $res[0] eq "FAILED") {
        shift @res;
        logMsg("$host $system FAILED:\n\n" . 
               ">" x 70 . "\n@res\n" . "<" x 70 . "\n", 2);
        exit 1;
      }
      else {
        if ($rc ne 0) {
          logMsg("$host $system $rshCmd failed with rc: $rc", 2);
        }
        elsif ($out) {
          logMsg("$host $system returned unexpectedly with " . 
                 "output string: $out", 2);
        }
        else {
          logMsg("$host $system returned unexpectedly with " .
                 "no return value", 2);
        }
        $host = shift(@{$hosts});
        next if $host;
        exit 1;
      }
    }
  }
  push @pids, $pid;
  $pidPlats{$pid} = $platform;
}

# wait for all builds to finish
for my $pid (@pids) {
  waitpid($pid, 0);
  if ($?) {
    push @badBuilds, $pidPlats{$pid};
    $rc = 1;
  }
  else {
    push @okBuilds, $pidPlats{$pid};
  }
}        

# set up error messages and exit 
my $retMsg;
if ($rc) {
  if (@okBuilds) {
    $retMsg .= "$prog $system succeeded on:\n";
    for (@okBuilds) { $retMsg .= "   $_\n"; }
  }
  $retMsg .= "$prog $system failed on:\n";
  for (@badBuilds) { $retMsg .= "   $_\n"; }
  finish(1, $retMsg);
}
$retMsg .= "$prog $system completed for:\n" if @okBuilds;
for (@okBuilds) { $retMsg .= "   $_\n"; }
finish(0, $retMsg);

#------------------------------------------------------------------------------

sub usage() {
    print <<EOF;

usage: $prog <config file> [arg1, arg2...]

EOF
}

#------------------------------------------------------------------------------

sub finish($;$) {    
  my $rc = shift;
  my $str = shift;
  
  if ($rc == 1) {
    logMsg("!! $prog FAILED\n$str", 2);
    sendMail($prog, 1);
  }
  else {
    logMsg("** $prog COMPLETED OK\n", 2);
    logMsg($str) if $str;
    sendMail($prog, 0);
  }
  
  exit 0;
}

#------------------------------------------------------------------------------


__END__


