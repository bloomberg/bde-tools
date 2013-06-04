#!/usr/bin/env perl

use strict;
use warnings;

use Cwd;
use FindBin;
$FindBin::Bin ||= getcwd || die "getcwd failed: $!";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use File::stat;
use Compat::File::Spec;
use Getopt::Long;
use IO::Handle;
use IO::Select;
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(usleep);

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE
    EXIT_OVERMAX EXIT_TIMEOUT EXIT_SIZEOUT EXIT_NONEXEC
);
use Util::Message qw(
    alert message verbose verbose2 verbose_alert error debug fatal
    open_log close_log get_logging set_logging
    set_quiet set_debug set_verbose get_verbose
    log_input log_output set_inlog_verbosity get_inlog_verbosity
);
use Util::Retry qw(retry_open retry_open3);
use Util::File::Basename qw(basename);
use Util::File::Attribute qw(is_newer);

#------------------------------------------------------------------------

use constant DEFAULT_JOBS    => 4;
use constant DEFAULT_TIMEOUT => 300;
use constant DEFAULT_SIZEOUT => 1024*1024;
use constant MAX_INDEX       => 500;

use constant TEST_OK         => 0;
use constant TEST_OVER       => 1;
use constant TEST_ERROR      => 2;
use constant TEST_TIMEOUT    => 3;
use constant TEST_SIZEOUT    => 4;
use constant TEST_ABNORM     => 5;

#------------------------------------------------------------------------------

$|=1; # buffer-ye-not
my $prog = basename($0);

#------------------------------------------------------------------------------

=head1 SYNOPSIS

  all.pl [-s|-[p|j] <jobs>] [-t <s>] [-z <b>] [-m <testmax>] [-d] [-v] <cmd> [<arg> ...]]

=head1 DESCRIPTION

This script runs all the tests for a specified test driver and returns a
non-zero exit status if any of them should fail or timeout. Tests are run in
parallel unless the C<--serial> option is specified (or C<--parallel> is
specified with a value of C<1>). Additional information about each test can be
displayed with the C<--verbose> and/or C<--debug> options.

=head1 OPTIONS

The following options are supported:

=head2 --help

Display brief usage information and exit.

=head2 --debug

Display additional information about created child processes.

=head2 --jobs|--parallel [<jobs>]

Execute tests in parallel. This is the default. An optional number of jobs may
be supplied to determine how many tests will be executed at any one time. If no
number is specified the default is C<10>.

C<--jobs> is in line with other tools that support the use of C<-j> for
invoking parallel operation. C<--parallel> is provided as an alias for
C<--jobs>. Incompatible with L<--serial>.

=head2 --logfile <logfile>

Write test results to the specified log file. The log file contains verbose
format output, identical to regular verbose mode, but unaffected by the
setting of C<--verbose>. Debug messages are also written to the log if
C<--debug> is specified.

=head2 --quiet

Do not echo output to the screen. If no log file is specified, only the
exit status provides an indication of the result.

=head2 --reuse

If a log file has been specified, compare the log file timestamp to that of
the test program and echo it in place of running the executable if the
timestamps indicate it is newer.

=head2 --serial

Execute tests serially, rather than in parallel. Incompatible with
L<--jobs>/L<--parallel>. Equivalent to specifying C<--jobs 1>

=head2 --sizeout <bytes>

Sets an output size limit per test. Tests that exceed this limit in terms of
the output they produce will be aborted.

In the event of the limit being reached no further tests will be performed,
although parallel tests will complete. Returns error code C<125> to the caller
unless a parallel test times out, in which case the timeout dominates.

=head2 --timeout <seconds>

Sets a timeout period after which a given test will be aborted.

In the event of a timeout no further tests will be performed, although parallel
tests will complete. Returns error code C<126> to the caller.

=head2 --maxindex <testmax>

Sets a test case number after which further tests will be abandoned (default 500).

If the limit is exceeded, returns error code C<127> to the caller.

=head2 --verbose

Display the output from each test is displayed, successful or not.

=head1 EXIT STATUS

The following exit statuses are returned:

=over 4

=item   0 - Success: all tests completed OK

=item   1 - Error: one or more tests failed

=item 125 - Output size limit exceeded: a test produced too much output

=item 126 - Timeout: a test failed to complete in the allowed time

=item 127 - Index overflow: the test index incremented past <testmax>.

=back

In the event that more than one test fails in a parallelised test, the returned
exit status is determined by the order of precedence of the statuses the tests
that failed: timeout, size limit, error.

=head1 MAINTAINER

  Peter Wainwright (pwainwright@bloomberg.net)

=cut

#------------------------------------------------------------------------------

sub usage(;$) {
    error $_[0] if @_;

    my $DEFAULT_JOBS=DEFAULT_JOBS;

    print STDERR <<_USAGE_END;
Usage: $prog -h | [-s|-[p|j] <jobs>] [-t <s>] [-z <b>] [-d] [-v] [-q]
                  [-l <logfile> [-r]] <cmd> [<arg> ...]]
  --help      | -h            display usage information (this text)
  --debug     | -d            enable debug output
  --jobs      | -j <jobs>     test in parallel, up to the specified number
                              of jobs at one time (default: $DEFAULT_JOBS)
  --logfile   | -l <logfile>  write test results to specified log file
  --quiet     | -q            disable messages to screen
  --failures  | -f            only output on failure (can't use with -q or -v)
  --reuse     | -r            reuse previous results from log if newer than cmd
  --serial    | -s            test in serial. Equivalent to -j1
  --sizeout   | -z <bytes>    abort a test if output exceeds this size (default: 1 meg)
  --timeout   | -t <seconds>  time out a test after the specified period. (default: 300 seconds)
  --maxindex  | -m <limit>    maximum test case index to try (default: 500)
  --cmdprefix | -p <prefix>   prefix to prepend to each command execution
                              (e.g., --cmdprefix "valgrind --tool=memcheck")
  --verbose   | -v            enable verbose output. May be specified 1-3 times
                              for increased levels of information

See 'pod2text $0' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------
# options processing

my %opts;

Getopt::Long::Configure("bundling");
unless (GetOptions(\%opts,qw[
    help|h
    debug|d+
    quiet|q!
    reuse|r!
    serial|s:i
    sizeout|z=i
    timeout|t=i
    logfile|l=s
    cmdprefix|p=s
    parallel|jobs|j:i
    maxindex|m=i
    verbose|v+
    failures|f
])) {
    usage();
    exit EXIT_FAILURE;
}

usage() and exit EXIT_SUCCESS if $opts{help};
usage() and exit EXIT_FAILURE if !@ARGV;
usage() and exit EXIT_FAILURE if $opts{failures}
                              && ($opts{verbose}||$opts{quiet});

if (exists($opts{serial}) and exists($opts{parallel})) {
    usage("--serial and --jobs are incompatible");
    exit EXIT_FAILURE;
}
$opts{serial}=1 if exists $opts{serial};

unless ($opts{serial}) {
    $opts{parallel}=DEFAULT_JOBS unless defined $opts{parallel};
    unless ($opts{parallel}>=1) {
        usage("number of --jobs must be >= 1");
        exit EXIT_FAILURE;
    }
    $opts{serial}=1 if $opts{parallel}==1;
}

if ($opts{timeout}) {
    $opts{timeout}=int $opts{timeout};
    unless ($opts{timeout} >= 0) {
        usage("--timeout must be positive integer or zero");
        exit EXIT_FAILURE;
    }
} else {
    $opts{timeout}=DEFAULT_TIMEOUT;
}

$opts{maxindex}=MAX_INDEX unless exists $opts{maxindex} && $opts{maxindex};

if ($opts{sizeout}) {
    $opts{sizeout}=int $opts{sizeout};
    unless ($opts{sizeout} >= 0) {
        usage("--sizeout must be positive integer or zero");
        exit EXIT_FAILURE;
    }
} else {
    $opts{sizeout}=DEFAULT_SIZEOUT;
}

if ($opts{reuse}) {
    unless ($opts{logfile}) {
        usage("--reuse requires --logfile");
    }
}

set_debug($opts{debug});
set_quiet($opts{quiet});
set_verbose($opts{verbose});
set_inlog_verbosity(1); #in this case we want to see the output

#------------------------------------------------------------------------------
# run_test_impl - runs one test case
#------------------------------------------------------------------------------

sub run_test_impl($$;@) {
    my ($testName,$testIndex,@args) = @_;

    my $rc=undef;
    my $start_time=time;
    my $output="";

    my ($wrh,$rdh)=(new IO::Handle,new IO::Handle);
    my $pid=retry_open3($rdh,$wrh,$rdh,$testName,$testIndex,@args);
    unless (defined $pid) {
        error("CASE $testIndex FOR ".basename($testName)." FAILED TO FORK/retry_open3");
        return TEST_ABNORM;
    }
    close $wrh;

    # Two different ways to retrieve output: one uses IO::Handle->blocking
    # which is easier but needs a newer IO::Handle. The other uses IO::Select
    # which won't work on Windows with Perl < 5.8.

    if ($rdh->can("blocking")) {
        log_output("$testName $testIndex @args (non-blocking)");

        # non-blocking works only for sufficiently modern IO::Handle
        $rdh->blocking(0);

        # check for child exit or timeout
        while ($opts{timeout}>(time-$start_time)
               and $opts{sizeout} and length($output)<=$opts{sizeout}) {
            my $lines=10;
            my $text;
            while ($text=<$rdh>) {
                $output.=$text;
                chomp $text;
                log_input $text;
                last unless $lines--; #break every 10 to check the size/time
            }
            $rc=$?,last if !defined($text) && waitpid $pid,WNOHANG();
            # in non-blocking mode, $text could be undefined while process is
            # still running, if we would have blocked.  In that case, sleep
            # so we don't spin and waste cpu in this script
            # If text is defined, there might be more to read, so don't sleep
            usleep(100000) unless defined($text);
        }
        close $rdh;

        if ($opts{timeout} <= (time - $start_time)) {
            error("CASE $testIndex FOR ".basename($testName)." TIMED OUT");
            kill 9,$pid;                #try to terminate hung case
            for (0..5) {
                #reap if we can, but don't require it
                last if waitpid $pid,WNOHANG();
                sleep 1;
            }
            return TEST_TIMEOUT;
        }

        # end non-blocking
    } else {
        log_output("$testName $testIndex @args (select)");

        my $select=new IO::Select($rdh);
        my ($text,$remainder)=("","");
        while ($opts{timeout} > (time-$start_time)
               and $opts{sizeout} and length($output)<=$opts{sizeout}) {
            my $reads=10;
            while (my @waiting=$select->can_read(10)) {
                my $read=sysread($rdh,$text,256);
                if ($text) {
                    # shennanigans to output lines correctly
                    if ($remainder) {
                        $text=$remainder.$text;
                        $remainder="";
                    }
                    if ($text=~s/^([^\n]*\n)//s) {
                        $remainder=$text;
                        $text=$1;
                    } else {
                        $remainder=$text;
                        next;
                    }

                    $output.=$text;
                    chomp($text);
                    log_input($text);
                }
                $select->remove($rdh),last if defined($read) and $read==0;
                last unless $reads--; #break every 10 reads to check size/time
            }

            last unless $select->handles(); # no handles left, all done
        }

        if ($remainder) {
            $output.=$remainder;
            chomp $remainder;
            log_input($remainder)
        }

        close $rdh;

        # check for a timeout - a handle still in the select array
        if ($select->handles) {
            kill 9,$pid;
            sleep 5;
            for (0..5) {
                #reap if we can, but don't require it
                last if waitpid $pid,WNOHANG();
                sleep 1;
            }

            error("CASE $testIndex FOR ".basename($testName)." TIMED OUT");
            return TEST_TIMEOUT;
        }

        # gather and process exit status
        waitpid $pid,0;
        $rc=$?;
    }

    # so how did we finish up?
    my $duration=time-$start_time;
    $duration="<1" unless $duration;

    if ($rc) {
        # non-zero exit status == failure or non-existent case
        $rc = $rc>>8 if $rc!=255; # Win32 returns 255 under make...

        if ($rc == -1 or $rc == 255) {
            return TEST_OVER;
        } else {
            message_nolog($output) unless get_verbose(); #already printed
            error("CASE $testIndex FOR ".basename($testName)." FAILED ("
                .$duration."s)");
            return TEST_ERROR;
        }
    } elsif (defined $rc) {
        # even a successful test can exceed its output limit
        if ($opts{sizeout} and $opts{sizeout}<length($output)) {
            error("CASE $testIndex FOR ".basename($testName)." OUTPUT MORE THAN SIZE LIMIT OF $opts{sizeout} BYTES");
            return TEST_SIZEOUT;
        }

        # zero exit status == success
        verbose2("CASE $testIndex FOR ".basename($testName)." SUCCEEDED ("
                .$duration."s)");
        return TEST_OK;
    }

    # this can happen with an undefined $rc
    if ($opts{sizeout} and $opts{sizeout}<length($output)) {
        error("CASE $testIndex FOR ".basename($testName)." OUTPUT MORE THAN SIZE LIMIT OF $opts{sizeout} BYTES");
        return TEST_SIZEOUT;
    }

    # time remaining, but no defined return code? Impossible!
    error("CASE $testIndex FOR ".basename($testName)." EXITED ABNORMALLY WITH 0 RESULT");
    return TEST_ABNORM;
}

#------------------------------------------------------------------------------
# check_temp_dir - check if directory exists, alert if it does not
#------------------------------------------------------------------------------
sub check_temp_dir($) {
    my $d = -d $_[0];
    debug("$_[0] could not be found") unless $d;
    return $d;
}

#------------------------------------------------------------------------------
# run_test - runs one test case w/ file cleanup
#------------------------------------------------------------------------------
sub run_test($$;@) {
    my ($testName,$testIndex,@args) = @_;
    my $dir;
    my $prefix = undef;
    if (exists($ENV{'TMPDIR'}) && check_temp_dir ($dir = $ENV{'TMPDIR'}) ||
        check_temp_dir ($dir = '/bb/data/tmp') ||
        check_temp_dir ($dir = '/tmp'))
    {
        my $name = $testName;
        $name =~ s/^.*[\/\\]//; # remove the directory part
        $prefix = "$dir/test.$$.$name.$testIndex.";
        $ENV{BDE_TEST_TEMPFILE_PREFIX} = $prefix;
    }
    my $rc = run_test_impl($testName,$testIndex,@args);
    if ($prefix) {
        for my $fn (<$prefix*>) {
            error("Cleaning up after test run: $fn\n");
            unlink $fn;
        }
    }
    return $rc;
}


#------------------------------------------------------------------------------

# special case message - log to screen only even when log file exists
sub message_nolog(@) {
    my $logging=get_logging();
    set_logging(0) if $logging;
    message(@_);
    set_logging($logging) if $logging;
}

#------------------------------------------------------------------------------

sub reap ($) {
    my $pids=shift;

    debug("waiting for one of ".join(' ',sort keys %$pids));
    my $pid=waitpid(-1,0);
    my $rc = $?;
    debug("returned from $pid (case $pids->{$pid}) ".
          ($rc?"FAILED ($rc)":"OK"));
    delete $pids->{$pid};

    return $rc >> 8;
}

#------------------------------------------------------------------------------

{
    my $rc = EXIT_SUCCESS;

    # set rc based on previous rc
    sub setrc ($) {
        my $newrc=shift;

        return if $newrc==EXIT_SUCCESS;

        if ($newrc==EXIT_FAILURE) {
            $rc=$newrc if $rc!=EXIT_SIZEOUT and $rc!=EXIT_TIMEOUT;
        } elsif ($newrc==EXIT_SIZEOUT) {
            $rc=$newrc if $rc!=EXIT_TIMEOUT;
        } elsif ($newrc==EXIT_TIMEOUT) {
            $rc=$newrc;
        }
    }

    sub getrc () {
        return $rc;
    }
}

sub set_result ($) {
    my $result=shift;

    if ($result == TEST_OVER) {
        setrc(EXIT_SUCCESS);
        return 1;
    } elsif ($result == TEST_TIMEOUT) {
        setrc(EXIT_TIMEOUT);
    } elsif ($result == TEST_ERROR) {
        setrc(EXIT_FAILURE);
    } elsif ($result == TEST_ABNORM) {
        setrc(EXIT_FAILURE);
    } elsif ($result == TEST_SIZEOUT) {
        setrc(EXIT_SIZEOUT);
    }

    return 0;
}

#------------------------------------------------------------------------------

MAIN: {
    my $testName = shift @ARGV;
    $testName = getcwd() . "/$testName"
      unless Compat::File::Spec->file_name_is_absolute($testName);

    # --reuse option
    if ($opts{reuse} and -f $opts{logfile} and
        is_newer($testName => $opts{logfile})) {
        my $lfh=new IO::Handle;
        open $lfh, $opts{logfile}
        or fatal "Unable to open $opts{logfile}: $!";
        my @loglines=<$lfh>;
        close $lfh or fatal "Unable to close $opts{logfile}: $!";

        chomp @loglines;
        my $lastline=pop @loglines;

        # Determine if the log file was from a clean run and set $reuseStatus
        # to the exit status or undef if not a clean run.  The log from a
        # clean run will end with either "SUCCESS" or "TEST FAILURE" and will
        # not contain any "TIMED OUT" messages.  A truncated log caused by,
        # e.g. a killed test run will not meet these criteria and should not
        # be reused.
        my $reuseStatus;
        if ($lastline=~/^\*\* \Q$prog\E: .* SUCCESSFUL\s*$/) {
            $reuseStatus=EXIT_SUCCESS;
        }
        elsif ($lastline=~/^\*\* \Q$prog\E: .* TEST FAILURE\s*\((\d+)\)\s*$/) {
            $reuseStatus=$1;
            if (grep /^!! \Q$prog\E: CASE .* TIMED OUT\s*$/o,@loglines) {
                # If any test timed out, clear status and re-run test.
                $reuseStatus=undef;
            }
        }

        if (defined($reuseStatus)) {
            # If we got here, we determined that the old log file is from a
            # clean run and is reusable.
            log_input("[reuse] $_") foreach @loglines;
            alert("[reuse] $lastline");
            exit $reuseStatus;
        }
    }

    # normal test procedure
    open_log($opts{logfile}) if $opts{logfile};

    unless (-e $testName) {
        error("$testName does not exist");
        exit EXIT_NONEXEC;
    }
    unless (-x _) {
        error("$testName not executable");
        exit EXIT_NONEXEC;
    }

    if (defined $ENV{TZ}) {
        debug("TZ variable is $ENV{TZ}");
    }
    else {
        debug("TZ variable is unset");
    }

    my $fs=stat($testName);
    verbose_alert("Testing ".basename($testName).' built '.
                  (scalar localtime $fs->mtime));

    my $testIndex = 0;
    my %pids;

    if ($opts{timeout}) {
        verbose2("Timeout set to $opts{timeout} seconds");
    } else {
        verbose2("Timeout disabled");
    }

    if ($opts{sizeout}) {
        verbose2("Output size limit set to $opts{sizeout} bytes");
    } else {
        verbose2("Output size limit disabled");
    }

    if ($opts{serial}) {
        verbose2("Running tests in serial");

        while (++$testIndex <= $opts{maxindex}) {
            my $result=run_test($testName,$testIndex,@ARGV);
            last if set_result($result);
        }
    } else {
        verbose2("Running tests in parallel ($opts{parallel} jobs)");

        my $running=0;
      TEST: while (++$testIndex <= $opts{maxindex}) {

            my $pid=fork;
            die "Failed to fork: $!\n" unless defined $pid;
            if ($pid) {
                $pids{$pid}=$testIndex;
                $running++;
            } else {
                #child
                exit run_test($testName,$testIndex,@ARGV);
            }

            debug("process $pid started for case $testIndex ".
                  "($running running)");

            while ($running >= $opts{parallel}) {
                $running--;
                last TEST if set_result(reap \%pids);
            }
        }

        while (%pids) {
            #reap children even if we EXIT_OVERMAX, it's polite
            set_result(reap \%pids);
        }

        setrc(EXIT_OVERMAX) if $testIndex >= $opts{maxindex};
    }

    my $rc=getrc();
    if ($rc) {
        #the (N) is matched in reuse
        alert(basename($testName)." ABNORMAL TEST FAILURE ($rc)");
    } elsif (!$opts{failures}) {
        alert(basename($testName)." SUCCESSFUL");
    }

    close_log() if $opts{logfile};

    exit $rc;
}

#------------------------------------------------------------------------------
