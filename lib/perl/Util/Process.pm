package Util::Process;
use strict;

use Util::Message qw(debug alert error fatal);
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);

#==============================================================================

=head1 NAME

Util::Process - Utility functions for managing forked processes

=head1 DESCRIPTION

This utility module provides routines that carry out tasks related to forked
processes (capturing output, forking and reaping exit statuses, et al.).

=head1 EXPORTS

Each routine rescribed under L<"ROUTINES"> below may be exported on demand.

=cut

#==============================================================================

use Exporter;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

my @proc_ops=qw[
    parallelise
    capture
];

@ISA = qw(Exporter);
@EXPORT_OK = (@proc_ops);

%EXPORT_TAGS = (
    all => \@EXPORT_OK,
   proc => \@proc_ops
);

#------------------------------------------------------------------------------

=head1 ROUTINES

This module provides the following routines:

=head2 parallelise($coderef,$paramaref,$concurrency,$msg)

A simple parallelisation engine. C<$coderef> is a subroutine that is to be
executed in parallel using L<fork>. C<$paramaref> is an array reference to
an array of arrays; each child array constitutes a set of arguments that
are passed to the subroutine specified by C<$coderef>. C<$concurrency> tells
the engine how many of these sets are permitted to run at the same time.
Finally, C<$msg> allows a name for describing the whole process to be defined
for output in debug messages.

I<Note: A more advanced engine that takes dependencies into account can be
found in L<Task::Manager>.>

=cut

sub _reap ($) {
    my $pids=shift;
    my $args;

    debug "waiting for one of ".join(' ',sort keys %$pids);
    my $pid=waitpid(-1,0);
    my $rc = $?;
    foreach ( @{$pids->{$pid}} ) { $_='undef' unless defined $_ };
    debug "returned from $pid (".
          join(' ',@{$pids->{$pid}}).") ".($rc?"FAILED ($rc)":"OK");
    if (exists $pids->{$pid}) {
        $args=delete $pids->{$pid};
    } else {
        fatal "reaped unexpected child process $pid";
    }

    return wantarray?($pid,$rc,$args):$rc;
}

sub parallelise(&$$;$) {
    my ($code, $param_aref, $concurrency, $msg) = @_;

    fatal "parallise arg 2 not an array ref"
      unless ref($param_aref) and ref($param_aref) eq 'ARRAY';

    my %pids;
    my $jobs       = scalar(@$param_aref);
    my $queued     = $jobs;
    my $running    = 0;
    my $failed     = 0;
    my @failures   = ();
    my $succeeded  = 0;
    my $start_time = time;

    $concurrency=$jobs unless $concurrency>0;

    $msg ||= "";
    my $xmsg = $msg?"$msg - ":"";
    alert("${xmsg}starting $jobs job".(($jobs==1)?"":"s"));

    while (my $args=pop @$param_aref) {

        my $pid = fork;
        unless ($pid) {
            fatal "fork failed: $!" if !defined $pid;
            exit EXIT_FAILURE if $code->(@$args);
            exit EXIT_SUCCESS;
        }

        $running++;
        $queued--;
        $pids{$pid}=$args;
        debug "job $pid ".(join ' ',map { defined($_)?$_:"undef" } @$args).
	      " started ($running running, $queued queued,".
              " $succeeded succeeded, $failed failed)";

        while ($running >= $concurrency) {
            my ($pid,$rc,$args)=_reap(\%pids);
            if ($rc) {
                $failed++;
            } else {
                $succeeded++;
            };
            $running--;
            debug "job $pid @$args ".($rc?"FAILED":"finished OK").
                  " ($running running, $queued queued, ".
                  "$succeeded succeeded, $failed failed)";
	    push @failures, "@$args" if $rc;
        }
    }

    # cleanup outstanding processes
    while (%pids) {
        my ($pid,$rc,$args)=_reap(\%pids);
        if ($rc) {
            $failed++;
        } else {
            $succeeded++;
        };
        $running--;
        debug "job $pid @$args ".($rc?"FAILED":"finished OK").
              " ($running running, $queued queued, ".
              "$succeeded succeeded, $failed failed)";
	push @failures, "@$args" if $rc;
    }

    if ($failed) {
        $msg=~s/^Building?\s+?//g;
	error("Build failed for $_") foreach @failures;
        fatal "Build failed ($failed out of $jobs) in $msg";
    }
    my $duration=time-$start_time;
    alert "${xmsg}finished $jobs job".(($jobs==1)?"":"s").
          " in $duration seconds";
}

#------------------------------------------------------------------------------

=head2 capture($coderef,@args)

C<capture> takes the code reference passed as its first argument and executes
it as a subprocess after first redirecting its standard output to a pipe. The
parent process reads the output from the pipe, collates it, and returns it to
the caller. Any additional arguments are passed as arguments to the passed code
reference. Example:

    my $output=capture(sub { print "Hello $_[0]" }, "World");

=cut

sub capture ($;@) {
    my $cref=shift;

    my $result="";
    pipe READ, WRITE;
    unless (fork) {
	no warnings 'once';
	close READ;
	open (OLDOUT,">&STDOUT");
	open (STDOUT,">&WRITE");
	&$cref(@_);
	open (STDOUT,">&OLDOUT");
	close WRITE;
	exit 0;
    } else {
	close WRITE;
	local $/=undef;
	$result.=<READ>;
	close READ;
    }

    return $result;
}

#==============================================================================

sub test {
    my $output=capture(sub { print "Hello $_[0]" }, "World");
    print "Captured: $output\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Task::Manager>

=cut

1;
