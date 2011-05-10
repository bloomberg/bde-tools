#!/usr/local/bin/perl

use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Data::Dumper;
use File::Basename;
use File::Find;
use File::stat;
use Getopt::Long;
use IO::File;
use Time::Local;

use constant EXIT_FAILURE       => -1;
use constant EXIT_SUCCESS       =>  0;

my %opts;
my @files;
my $filePattern;
my %logFileDirs;

sub usage(;$) {
   print STDERR <<_USAGE_END;
Usage: baellog_audit.pl -h | [-prv] [-d <dir>]* <days>
where:
  --directory  | -d <dir>       process all files in the specified directory
  --help       | -h             display usage information (this text)
  --output     | -o <path>      output filename
  --print      | -p             display actions, but do not execute
  --recurse    | -r             recurse into subdirectories (requires -d)
  --verbose    | -v             enable verbose mode
                    <days>      remove logs more than <days> number of days old
_USAGE_END
}

sub terminate($)
{
 my  ($status)= @_;
 exit($status);
}

sub timestamp {
  my ($sec, $min, $hr, $dd, $mm, $yyyy) = localtime(time);
  my $now = sprintf "%4d-%02d-%02d %02d:%02d:%02d",
                     $yyyy + 1900, $mm + 1, $dd, $hr, $min, $sec;
  return $now;
}

sub findLogFilename($) {
  my ($configurationFilename) = @_;

  my $inputFile = new IO::File "< $configurationFilename" ||
    die "Failed to open '$configurationFilename'";

  local $/ = undef;
  my $configurationText = <$inputFile>;
  $inputFile->close();

  if ($configurationText =~ m/<LoggingConfig>\s+<Filename>(.+)<\/Filename>/g) {
    print(timestamp() . " Found log filename $1\n")
      if (defined $opts{verbose});
    return $1;
  }

  return undef;
}

sub translateFilenameToRegex($) {
  my ($logFilename) = @_;

  my $regex = $logFilename;

  $regex =~ s/\./\\\./g;
  $regex =~ s/%Y/(\\d{4})/g;
  $regex =~ s/%[MDhms]/(\\d{2})/g;

  return $regex;
}

sub addFile {
  my $file = $File::Find::name;
  push(@files, $file) if ((-f $file) && ($file =~ m/$filePattern/));
}

sub processFileList($\@) {
  my ($days, $files) = @_;

  print(timestamp() .
      " Discovered " . scalar @{$files} . " potential services\n");

  foreach my $file (@{$files}) {
    my ($filename, $directory, $suffix) = fileparse($file, ".tsk");
    my $configurationFilename = $directory . $filename . ".cfg";

    print(timestamp() . " Examining potential service '$file' and " .
            "configuration '$configurationFilename'\n")
        if (defined $opts{verbose});

    if (-f $configurationFilename) {
      print(timestamp() . " Found potential service '$file' and " .
            "configuration '$configurationFilename'\n")
        if (defined $opts{verbose});

      my $logFilename = findLogFilename($configurationFilename);
      if (defined $logFilename) {
        my ($filename, $directory, undef) = fileparse($logFilename);
        my $regex = translateFilenameToRegex($filename);
        my $logDirectory = dirname($logFilename);

        # Not sure how to handle logs placed in the cwd of the task.
        next if ($logDirectory eq ".");

        my $options = "-f";
        $options .= (defined $opts{print}) ? " -p" : "";
        $options .= ($filename =~ m/%/)    ? " -S" : "";

        $logFileDirs{$logDirectory} = undef;

        my $cmd = "baellog_cleanup.pl "
                . "$options -d $logDirectory -e '$regex' $days "
                . ">> /bb/data/baellog_cleanup.log";

        print(timestamp() . " Running: $cmd\n") if (defined $opts{verbose});
        system($cmd);
      }

    }

  }
}

MAIN: {
 Getopt::Long::Configure("bundling");
 $Data::Dumper::Indent = 1;

 my $argv0 = File::Basename::basename $0;  chomp($argv0);
 my $originalCmdline = join(' ', $argv0, @ARGV);

 print(timestamp() . " Started: $originalCmdline.\n");

 unless (GetOptions(\%opts, qw[
   directory|d:s@
   help|h
   print|p
   recurse|r
   verbose|v
 ])) {
   usage();
   terminate(EXIT_FAILURE);
 }

 usage() and terminate(EXIT_SUCCESS) if $opts{help};
 usage() and terminate(EXIT_SUCCESS) if (!defined $opts{directory});
 usage() and terminate(EXIT_SUCCESS) if !@ARGV;

 my $days  = shift @ARGV;

 $filePattern = "(.*)\.tsk\$";

 if (defined $opts{directory}) {
   foreach my $dir (@{$opts{directory}}) {
     print(timestamp() . " Auditing '$dir'\n");

     if (defined $opts{recurse}) {
       File::Find::find({ wanted => \&addFile,
                          follow => 0,
                          no_chdir => 1 }, "$dir");
     }
     else {
       next if (!opendir(DIR, $dir));
       my @dirfiles = ();
       @dirfiles = map  { "$dir/$_" }
                   grep { m/$filePattern/ &&  -f "$dir/$_" } readdir(DIR);

       push @files, @dirfiles;
       closedir DIR;
     }
   }
 }

 processFileList($days, @files);

 print(timestamp() . " Found log files from the following directories:\n");
 foreach my $key (keys %logFileDirs) {
   print(timestamp() . " $key\n");
 }

 print(timestamp() . " Stopped: $originalCmdline\n");

 EXIT_SUCCESS;
}

