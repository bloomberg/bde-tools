#!/bbs/opt/bin/perl-5.8.8 -w
# !/opt/swt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Cwd;
use Data::Dumper;
use File::Basename;
use File::Find;
use File::Spec;
use IO::File;
use IO::Handle;
use IO::Tee;
use Getopt::Long;
use XML::Simple;

$Data::Dumper::Indent = 1;

my @ts  = localtime();                               # cached across test cases
my @mon = qw( JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC );
my $timestamp = sprintf("%02d%s%d_%02d:%02d:%02d",
                        $ts[3],$mon[$ts[4]],1900+$ts[5],$ts[2],$ts[1],$ts[0]);

#==============================================================================

=head1 NAME

bas_regression.pl - please describe

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

#==============================================================================

sub usage (;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog [-suUF] [-t testdb] [-r generator] [-l logfile] [-I dir]* <testCase>*

  --help       | -h            usage information (this text)
  --update     | -u            update expected results
  --uptodate   | -U            use existing generated data
  --noFail     | -F            ignore errors and continue to the next test
  --silent     | -s            redirect output from bas_codegen.pl to /dev/null
  --testdb     | -t <file>     use specified testdb (default: testdb.xml)
  --run        | -r <script>   run the specified generator script
                               (default: bas_codegen.pl)
  --logfile    | -l <file>     use specified logfile
  --includedir | -I <dir>      search dir for schema files
  --passthrough| -p <options>  pass specified options to script

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions () {

  my %opts = (
              testdb => 'testdb.xml',
              run => 'bas_codegen.pl',
             );

  Getopt::Long::Configure("bundling");
  unless (GetOptions(\%opts, qw[
           help|h
           update|u
           uptodate|U
           noFail|F
           silent|s
           testdb|t=s
           run|r=s
           logfile|l=s
           includedir|I=s@
           debug|d=s
           passthrough|p=s@
          ])) {

    usage();
    exit 1;
  }

  # help
  usage(), exit 0 if $opts{help};

  my @testCases = @ARGV;
  $opts{testCases} = \@testCases if scalar(@ARGV);

  unshift(@{$opts{includedir}}, '.');
  
  $opts{debug} = $opts{debug} || 0;
  $opts{logfile} = 'log' unless defined $opts{logfile};
  $opts{passthrough} = [] unless defined $opts{passthrough};

  return \%opts;
}

#------------------------------------------------------------------------------

sub findFile (\%$) {
  my ($opts, $file) = @_;

  return $file if $file =~ m:^/:;

  my $fullpath = '';
  foreach my $dir (@{$opts->{includedir}}) {
    my $trypath = File::Spec->catfile($dir, $file);
    if (-r $trypath) {
      $fullpath = $trypath;
      last;
    }
  }

  return File::Spec->rel2abs($fullpath);
}

#------------------------------------------------------------------------------

sub generate ($$$$\%) {
  my ($test, $dir, $command, $log, $opts) = @_;

  if (-e "$dir") { system("/bin/rm -rf $dir/*") }
  else           { system("mkdir $dir") }

# unless (chdir $dir) { die "Failed to cd to $dir: $!\n" }
  if ($opts->{update}) {
    $log->print("$timestamp TEST $test: generating files in $dir\n") if $opts->{debug};
    $log->print("     $command\n") if $opts->{debug};
  }

  my $rc = system("$command");

  if (defined $opts->{noFail}) {
    $log->print("$timestamp TEST $test: failed!\n") if 0 != $rc;
  }
  else {
    die "Generator failed!\n" if 0 != $rc;
  }

# my $pwd = File::Basename::dirname($dir);
# unless (chdir $pwd) { die "Failed to cd to $pwd $!\n" }
}

#------------------------------------------------------------------------------

sub findDiffs ($$$$) {
  my ($testDir, $test, $testStatus, $log) = @_;

  use constant SUCCESS => 0;
  use constant FAILURE => 1;

  my $localStatus = 0;
  my $dir = $testDir;
  my @files = ();
  File::Find::find(
      sub { push(@files, File::Basename::basename($File::Find::name))
                unless $File::Find::dir eq $File::Find::name
          },
      "$dir/gen");
  foreach my $file (@files) {
    my $status = SUCCESS;
    if (! -e "$dir/exp/$file") {
      print STDERR "Err: Baseline file 'exp/$file' does not exist\n";
      $status = FAILURE;
    } else {
      # Write uncommented versions of each file to tmp.
      `/bb/bin/uncomment -xm $dir/exp/$file >/tmp/exp.$file.$$`; $status |= $?;
      `/bb/bin/uncomment -xm $dir/gen/$file >/tmp/gen.$file.$$`; $status |= $?;
      die "Could not perform diff\n" if $status;

      open(DIFF, "diff -w -U 1 /tmp/exp.$file.$$ /tmp/gen.$file.$$|");
      my @diff = ();
      {
        local $/ = undef;
        @diff = split(/\n/, <DIFF>);
      }
      close(DIFF);
      if (1 < scalar(@diff)) {
        my $diffText = join("\n", @diff);
        $log->print("$timestamp $file:\n$diffText\n");
        $log->print("-"x79,"\n");
        $status = FAILURE;
      } else {
        #$log->print("No differences encountered\n");
      }
    }

    $localStatus |= $status;
  }

  $testStatus += (0 < $localStatus);

  my $cwd = Cwd::getcwd();
  $log->print("$timestamp TEST $cwd/$test: ",
              ($localStatus ? "FAILED" : "OK"), "\n");
  $log->print("="x79,"\n") if 0 != $localStatus;

  return $testStatus;
}

#------------------------------------------------------------------------------

MAIN: {
  my $opts = getoptions();

  push(@{$opts->{includedir}}, split(/:/, $ENV{BDE_XSDCC_INCLUDE_PATH}))
      if defined $ENV{BDE_XSDCC_INCLUDE_PATH};

  my $BDE_ROOT = $ENV{BDE_ROOT} || '';
  push(@{$opts->{includedir}},
       ("$BDE_ROOT/groups/bde/bdem",
        "$BDE_ROOT/groups/bde/bdeat",
        "$BDE_ROOT/groups/xml/xmlbdem",
        "$BDE_ROOT/groups/bas/basapi",
        "$BDE_ROOT/groups/bas/bascfg",
        "$FindBin::Bin/../etc/xsd",
        "/bbsrc/proot/include/00depbuild",
        "/bbsrc/proot/include/00deployed",
        "/bbsrc/bbinc/Cinclude/bde"
       ));

  my $testdb = XMLin($opts->{testdb},
                     NSExpand => 0,
                     ForceArray=> [
                                   'args',
                                   'test',
                                  ],
                    );
  print Data::Dumper->Dump([$opts], ["opts"])     if 1 < $opts->{debug};
  print Data::Dumper->Dump([$testdb], ["testdb"]) if 1 < $opts->{debug};

  my $generator = $opts->{run} || "bas_codegen.pl";
  my $testBase  = File::Basename::dirname(findFile(%$opts, $opts->{testdb}));
  $testBase = Cwd::abs_path() if '.'  eq $testBase;

  my $logfile    = $opts->{logfile} || "$testBase/log";
  my $testStatus = 0;

  my $io  = new IO::Handle;
  my $log = IO::Tee->new(IO::File->new(">> $logfile"),
                         $io->fdopen(fileno(STDOUT), "w"))
  || die "Cannot open logfile '$logfile': $@\n";

  # Adjust test set according to the optionally specified list of test cases.
  my $testCases = $opts->{testCases} || [ sort keys %{$testdb->{test}} ];
  print Data::Dumper->Dump([$testCases], ["testCases"]) if 1 < $opts->{debug};

  my $pwd = Cwd::getcwd();

  foreach my $testCase (@$testCases) {
    my $test = $testdb->{test}->{$testCase}
        or die "Err: Test '$testCase' is not specified\n";

    my $testDir = "$testBase/$testCase";
    $testDir = "$testBase/$$test{testDir}" if defined $test->{testDir};
    push(@{$opts->{includedir}}, $testBase);
    push(@{$opts->{includedir}}, $testDir);

    # MM
    my $schema = findFile(%$opts, $test->{schema});

    if (defined $test->{schema}) {
      # MM
      #$schema = Cwd::abs_path($test->{schema});
      if (! -e $schema) {
        pop(@{$opts->{includedir}});    # testBase
        pop(@{$opts->{includedir}});    # testDir
        print STDERR "Err: Test schema '$$test{schema}' does not exist\n";
        ++$testStatus;
        next;
      }
    }
    $testDir = File::Basename::basename($testDir);
    unless (-e "$testDir")  { system("/bin/mkdir $testDir") }
#   unless (chdir $testDir) { die "Failed to cd to $pwd/$testDir $!\n" }
#   my $pwd = Cwd::getcwd();

    # Generate output for regression testing, or re-generate the baseline data
    # if the 'update' option is specified.
    unless ($opts->{uptodate}) {
      my $dir = ($opts->{update}) ? "exp" : "gen";

      # MM - Do not redirect output from the generator to the log file.
      #my $command = "$generator -D $testDir/$dir @{$$test{args}} $schema "
      #            . "2>&1 >>$$opts{logfile}";

      my $command;
      if (defined $opts->{silent}) {
        $command = "$generator -D $testDir/$dir @{$$test{args}} $schema "
                 . "2>&1 > /dev/null"; #"> /dev/null 2&>1";
      }
      else {
        $command  = "$generator -D $testDir/$dir @{$$test{args}} $schema";
        $command .= " " . join(' ', @{$opts->{passthrough}});
      }

      generate($testCase, "$testDir/$dir", $command, $log, %$opts);
    }

    # Perform diffs between each generated file, and the corresponding expected
    # output.
    unless ($opts->{update}) {
      $testStatus = findDiffs($testDir, $testCase, $testStatus, $log);
    }

#   unless (chdir $testBase) { die "Failed to cd to $testBase $!\n" }

    pop(@{$opts->{includedir}});    # testBase
    pop(@{$opts->{includedir}});    # testDir
  }

  unless (chdir $pwd) { die "Failed to cd to $pwd $!\n" }

  exit $testStatus;
}

#==============================================================================

=head1 AUTHOR

David Rubin (drubin6@bloomberg.net)

=cut
