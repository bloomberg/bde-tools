#!/bbs/opt/bin/perl -w
use strict;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:$FindBin::Bin:/usr/local/bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Getopt::Long;

use Util::File::Basename qw(basename);
use Util::Message qw(error debug warning);
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);

use Change::Symbols qw(STAGE_BETA);
use Change::Identity qw(identifyProductionName);
use Production::Services;
use Production::Services::Move qw(isBetaDay);

# Testing note: This utility can be tested in developement by setting the
# override PRODUCTION_HOST to sundev9

#==============================================================================

=head1 NAME

isbetaday.pl - Read beta status for supplied libraries and tasks

=head1 SYNOPSIS

    isbetaday.pl lib1 lib2 task1.tsk task2.tsk task3.tsk
    isbetaday.pl  -l lib1,lib2 -E task1,task2 -E task3

=head1 DESCRIPTION

C<isbetaday.pl> makes a production service query to determine, given the
specified tasks and libraries, whether an emergency move of these libraries
is eligible for a beta-only move.

Libraries and Tasks can be provided either as option values to the C<-l> or
C<-E> options respectively, or as a list of as unqualified arguments. To
differentiate libraries and tasks when supplied as unqualified arguments,
task names should have C<.tsk> appended. All other arguments will be considered
libraries. At least one task name, supplied either as an argument
(with C<.tsk> suffix) or as a value to the C<-E> option (C<.tsk> suffix
optional) must be supplied.

Both the C<--libs>/C<-l> and C<--tasks>/C<-E> options accept comma-separated
lists of values. Both options may also be specified multiple times with
cumulative effect.

In pretty mode, the default when run interactively, or enabled with C<--pretty>
or C<-P>, a message is printed to standard output for human consumption. In
machine mode, the default when run non-interactively, or enabled with
C<--machine> or C<-M>, no message is printed.

On success, a zero exit status is returned if beta-status is not in effect,
or a positive exit status if it is. If an error occurs, an error is issued
to standard out and a negative exit status is returned.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] <task>|-E <task> [<libraries/tasks>]
                         [-l <librariess>] [-E <tasks>]
  --debug        | -d              enable debug reporting
  --help         | -h              usage information (this text)
  --verbose      | -v              enable verbose reporting

Query options:

  --tasks        | -E <list>     task or comma-separated list of tasks
  --lib[rarie]s  | -l <list>     library or comma-separated list of libraries

Display options:

  --pretty       | -P            list changes in human-parseable output
                                 (default if run interactively)
  --machine      | -M            list changes in machine-parseable output
                                 (default if run non-interactively)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        machine|M
        pretty|P
	libs|libraries|l=s@
        tasks|E=s@
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{libs};

   # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	exit EXIT_FAILURE;
    }
    unless ($opts{pretty} or $opts{machine}) {
	if (-t STDOUT) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#==============================================================================

MAIN: {
    my $opts=getoptions();

    my @arglist=@ARGV;
    my @list=map { split /,/,$_ } @arglist; #allow CSV

    my @libs=();
    my @tsks=();
    #search for all names with ".tsk"
    @libs = grep {$_ !~ /\.tsk$/} @list;
    @tsks = grep {$_ =~ s/\.tsk$// and $_} @list;

    my @morelibs=();
    @morelibs=@{ $opts->{libs} } if $opts->{libs};
    @morelibs=map { split /,/,$_ } @morelibs;
    push @libs, @morelibs;

    # 2 - any gtk library
    my $gtk=0;
    foreach my $target (@libs) {
        my $prdlib=identifyProductionName($target,STAGE_BETA);
	defined $prdlib  or  next;
 	$gtk=1, last if $prdlib=~/^gtk/;
    }
    if ($gtk) {
	unless (grep(/\bgtk\b/i => @libs)) {
	    warning "GTK library detected -- added 'gtk' to tasks";
	    push(@libs,'gtk');
	}
    }

    my @moretasks=();
    @moretasks=@{ $opts->{tasks} } if $opts->{tasks};
    @moretasks=map { s/\.tsk$//; $_ } map { split /,/,$_ } @moretasks;

    push @tsks, @moretasks;

    debug "Tasks: @tsks\n";
    debug "Libraries: @libs\n";

    my $svc=new Production::Services();
    my $isbeta=isBetaDay($svc,@tsks,@libs);

    unless (defined $isbeta) {
        error "Error occured reading beta status";
	error $svc->getError() if $svc->getError();
        exit -1;
    }

    if ($opts->{pretty}) {
	local $"=',';
	print "EMOVs for tasks @tsks and libraries @libs are ";
	print ($isbeta ? "elegible for beta" : "production only");
        print "\n";
    }

    exit ($isbeta ? 1 : 0);
}
