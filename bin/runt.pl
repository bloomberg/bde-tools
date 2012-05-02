#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use IO::Handle;
use IO::File;
use File::Basename; 
use POSIX qw(:sys_wait_h);
use Fcntl ':flock';        # import LOCK_* constants

#------------------------------------------------------------------------------
# constants

use constant EXIT_FAILURE    => -1; 
use constant EXIT_SUCCESS    => 0; 

use constant DEFAULT_JOBS    => 4;
use constant DEFAULT_TIMEOUT => 120;
use constant DEFAULT_TESTDRIVER_LOG => "/dev/null";

use constant DEFAULT_SIZEOUT => 10240;
use constant MAX_INDEX       => 500;

use constant TEST_OK         => 0;
use constant TEST_OVER       => -1;
use constant TEST_ERROR      => -2;
use constant TEST_TIMEOUT    => -3;
use constant TEST_SIZEOUT    => -4;
use constant TEST_ABNORM     => -5;
use constant TEST_NOT_FOUND  => -6;

#------------------------------------------------------------------------------
# prototypes
sub usage(;$);
sub terminate($);
sub executeTestCaseChild($$$);
sub executeTestCaseParent($$$$$);
sub executeTestDriver($$$$);
sub sigChildHandler($);
                    
#------------------------------------------------------------------------------
# main program

my $argv0 = File::Basename::basename $0;  chomp($argv0);

# options processing

my %opts;

# allow bundling of single-letter command-line arguments
Getopt::Long::Configure("bundling"); 

unless (GetOptions(\%opts,qw[
    help|h               
    parent|p
    graphical|g
    verbose|v               
    debug|d+
    timeout|t:i
    scriptLogfile|L:s 
    programLogfile|l:s
    case|c=i                       
    iters|i:i
    nofailure|N
    serial|s  
])) {
    usage();
    terminate(EXIT_FAILURE);
}


usage() and terminate(EXIT_SUCCESS) if $opts{help};
usage() and terminate(EXIT_SUCCESS) if !@ARGV;

if ($opts{timeout}) {
    unless ($opts{timeout} > 0) {
        print ("--timeout must be a positive integer");
        terminate(EXIT_FAILURE);
    }
} else {
    $opts{timeout}=DEFAULT_TIMEOUT;
}

if ($opts{iters}) {
    unless ($opts{iters} > 0) {
        print ("--iters must be a positive integer");
        terminate(EXIT_FAILURE);
    }
}
else {
    $opts{iters} = 1;
}

if (!$opts{programLogfile}) {
    $opts{programLogfile} = DEFAULT_TESTDRIVER_LOG;
}

unless (open PLOGFH, '>', $opts{programLogfile}) {
    print STDERR 'Failed to open program log file ',
        $opts{programLogfile}, ' for writing: ', $!, "\n";
    terminate(EXIT_FAILURE);
}

if ($opts{verbose}) {
    print "Parameters: ";
    print join "\n", map { "$_ => $opts{$_}" } keys %opts;
    print "\n";
}

my $OUTPUT_HANDLE = new IO::File;
my $LOCK_HANDLE;
my $program = shift @ARGV;
my $programName = File::Basename::basename $program; chomp($programName);
my $platform = File::Basename::dirname $program; chomp($platform);
$platform = File::Basename::basename $platform;  chomp($platform);

if ($opts{scriptLogfile}) {    
    print ("Opening $opts{scriptLogfile}\n");
    $OUTPUT_HANDLE->open(">>$opts{scriptLogfile}") 
        || die "Can't open $opts{scriptLogfile}:";

    # DGUX has a bug -- advisory locking on NFS-mounted file systems 
    # will hang the process indefinitely.
    if ($platform =~ /dgux/) { 
        my $logFile = File::Basename::basename($opts{scriptLogfile}); chomp($logFile); 
        my $lockFile = "/tmp/$logFile";

        $LOCK_HANDLE= new IO::File;
        $LOCK_HANDLE->open(">>$lockFile") 
            || die "Can't open $lockFile (locking file):";
    }
    else {
        $LOCK_HANDLE = $OUTPUT_HANDLE;
    }
}
else {
    new IO::Handle;
    $OUTPUT_HANDLE->fdopen(fileno(STDOUT), "w");
    $LOCK_HANDLE = $OUTPUT_HANDLE;
}

$OUTPUT_HANDLE->autoflush(1);


my $numFailed = 0;
my $resultString = "";
my $currentTime = time();

if (! -x $program) {
    $numFailed = -1;
    $resultString = "N/A";
}
else {
    if ($opts{case}) {
        $numFailed = executeTestCaseParent($program, $opts{case},
                                           \*PLOGFH,
                                           $opts{timeout},
                                           $opts{iters});
        if ($numFailed == -1) {
            print $OUTPUT_HANDLE "CASE $opts{case} NOT FOUND. ";
        }
    }
    else {
        $numFailed = executeTestDriver($program, \*PLOGFH,
                                       $opts{timeout},
                                       $opts{iters});
    }
}
$currentTime = time() - $currentTime;

flock $LOCK_HANDLE, LOCK_EX;

if ($opts{parent}) { print $OUTPUT_HANDLE "$platform\n"; }

print $OUTPUT_HANDLE "$programName: $resultString";

if ($numFailed == 0) {
    print $OUTPUT_HANDLE "OK ($currentTime s, $opts{iters} iters)\n";
}
else {
    print $OUTPUT_HANDLE " ($currentTime s, $opts{iters} iters, TO=$opts{timeout} s.)\n";
}

flock $LOCK_HANDLE, LOCK_UN;

terminate($numFailed);

sub usage(;$) {
    my $DEFAULT_JOBS=DEFAULT_JOBS;

    print STDERR <<_USAGE_END;
Usage: runt.pl -h | [-t <s>] [-v] [-g] [-l <scriptLogFile>] 
               -L <programLogFile> <cmd>

  --help     | -h            display usage information (this text)
  --graphical| -g            show progres for each test case in ASCII art
  --scriptLogfile            write this script output to the <logfile> 
      | -L <logfile>             (default: STDOUT)
  --programLogfile           write test driver output to the <logfile> 
      | -l <logfile>             (default: /dev/null)
  --parent   | -p            print parent directory
  --case     | -c <caseNum>  execute only test case <caseNum>
  --iters    | -i <iters>    execute each case <iters> number of times OR
                             until a failure is detected    
  --timeout  | -t <seconds>  time out a test case after the specified period
  --nofailure| -N            always exit with 0  
  --verbose  | -v            enable verbose output


See 'pod2text $0' for more information. -- NOT DONE YET
_USAGE_END
}

sub terminate($) {
    my ($status)=@_; 
    if ($opts{nofailure}) {
        exit(0); # always return success
    }
    else {
        exit($status);
    }
}

sub executeTestCaseChild($$$) {
    my ($program, $testCase, $logFh) = @_; 
    my $command;
    # Perl has an issue with metacharacters in $command. 
    # In fact, a shell will be spawned first in order to 
    # parse the redirect characters. 
    # This may result in a process not being killed properly
    # on time out because a wrong process ID is reported. 
    # To get around this issue, we will open $stdOutLog and 
    # $stdErrLog explicitly and dup STDIN and STDERR to them.
    
    close STDOUT;
    close STDERR;

    open STDOUT, '>&', $logFh;
    open STDERR, '>&', $logFh;

    $command = "$program $testCase";

    # XXX it's ok, we're just referencing a global, nothing
    # to worry about...

    if ($opts{debug}) {
        $command .= ' ' . join(' ', ('0') x $opts{debug});
    }

    if ($opts{verbose}) {        
        print $OUTPUT_HANDLE "Executing $command in $$\n";
    }
    
    exec($command) or print STDOUT "couldn't exec $command: $!";
    exit(-1);
}

sub sigChildHandler($) {
    my $signame = shift;
    if ($opts{verbose}) {
        print $OUTPUT_HANDLE "$signame received.\n";
    }
}

sub executeTestCaseParent($$$$$) {    
    my ($programName, $caseNum, $logFh,
        $timeout, $iterations) = @_;
    my $rc = 0;
    
    my $step;
    my $many;
    my $xtra;
    
    if ($opts{graphical}) {
        my $WIDTH = 79;
        $step = int $iterations / $WIDTH + 1;
        $many = int $iterations / $step;
        $xtra = $WIDTH - $many;    
        if ($opts{verbose}) {
            print $OUTPUT_HANDLE "step = $step, many = $many, ", 
                                 " xtra = $xtra\n";
        }
        print $OUTPUT_HANDLE "|", "=" x ($WIDTH - 2), "|\n";
    }
    
    for my $j (1..$iterations) {
        my $xTimeout = $timeout;
        $SIG{CLD} = \&sigChildHandler;
        my $pid = fork();
        die "Failed to fork: $!\n" unless defined $pid;
        if ($pid) {
            if ($opts{verbose}) {
                print $OUTPUT_HANDLE "Spawned $pid.";
            }
            # $pid is the child's pid.
            # wait for it to complete and fetch the status
            my $kid = -1;
	    my $kidStatus = -1;
            my $stopTime = time() + $timeout;  
   
            while (time() < $stopTime) {
                $kid = waitpid($pid, WNOHANG);
		$kidStatus = $?;
                if ($kid == $pid) { last; }
                select(undef, undef, undef, 0.1); # 100 ms
            }

            if (time() >= $stopTime) {
                if ($opts{verbose}) {
                    print $OUTPUT_HANDLE "Test timed out. Killing $pid.. ";
                }

                my $cnt = kill 9, $pid;
                $kid = waitpid($pid, 0);
                if ($opts{verbose}) {
                   print $OUTPUT_HANDLE "$cnt killed. waitpid returned $kid\n";
                }
                $rc = -2; # timeout
            }
            else {
                if ($opts{verbose}) {
                    print $OUTPUT_HANDLE "$caseNum: pid status $kidStatus\n";
                }
                
                if ("$^O" eq "MSWin32") {
		    $rc = $kidStatus >> 8;
		    if ($rc == 255) {
			$rc = -1;
		    }
		}
		elsif (WIFEXITED($kidStatus)) {
		    my $st = WEXITSTATUS($kidStatus);
		    if ($opts{verbose}) {
			print $OUTPUT_HANDLE "$caseNum exited with $st\n";
		    }
		    $rc = $st;
		    if ($rc == 255)
		    {
			$rc = -1;
		    }
		}
		elsif (WIFSIGNALED($kidStatus)) 
                {
                    my $s = WTERMSIG($kidStatus);
		    if (0 == $s) {
			#this is an IBM quirk - for SIGABRT, WTERMSIG seems
			#to give a value of 0.  Whatever - if not WIFEXITED, 
			#and WIFSIGNALED, there was a problem.  Force rc to
			#-999 in that case.
			if ($opts{verbose}) {
			    print $OUTPUT_HANDLE
				"$caseNum signaled with an unknown code\n";
			}
			$rc = -999;
		    }
		    else {
			if ($opts{verbose}) {
			    print $OUTPUT_HANDLE
				"$caseNum signaled with $s\n";
			}
			$rc = -$s; 
		    }
                }
		else {
		    print $OUTPUT_HANDLE 
			"$caseNum NEITHER EXITED NOR ABORTED: $kidStatus\n";
		}
            }
        } else {
            # child process -- return error code through
            # exit status
            # executeTestCase EXITS the process
            # print "Executing $caseNum: ";
            executeTestCaseChild($programName, $caseNum,
                                 $logFh);

        }
        
        if ($opts{graphical} && 0 == int $j % $step) {
            print $OUTPUT_HANDLE '*';
        }
                
        if ($rc == -1) {  # case not found
            last;
        }
        else {
            if ($rc != 0) {
                if ($rc == -2) {
                    $resultString = $resultString . "$caseNum (TO), ";
                    # $OUTPUT_HANDLE->print("$caseNum (TO), ");
                }
                else {
                    # print $OUTPUT_HANDLE "$caseNum ($rc), ";
                    $resultString = $resultString . "$caseNum ($rc), ";                
                }
                last;
            }
        }

    }
    
    if ($opts{graphical}) {
        print $OUTPUT_HANDLE '*' x $xtra, "\n";
    }
    return $rc;
}

sub executeTestDriver($$$$) {    
    my ($programName, $logFh, $timeout, $iterations) = @_;
    my $numFailures = 0;
    my $rc = 0;
    for my $caseNum (1..1000) {
        $rc = executeTestCaseParent($programName, $caseNum, $logFh,
                                    $timeout, $iterations);
        last unless $rc != -1;
        if ($rc != 0) { $numFailures++; }
    }
    return $numFailures;
}
