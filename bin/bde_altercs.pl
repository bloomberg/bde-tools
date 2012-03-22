#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:${FindBin::Bin}:/usr/local/bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Symbol ();
use File::Copy qw(copy);
use Getopt::Long;

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
);
use Change::Symbols qw(
    DBPATH DBLOCKFILE USER STAGE_PRODUCTION_ROOT
    STATUS_SUBMITTED STATUS_WAITING STATUS_ACTIVE COMPCHECK_DIR
    DEPENDENCY_TYPE_SIBLING CHECKIN_ROOT
    MOVE_REGULAR MOVE_BUGFIX MOVE_EMERGENCY MOVE_IMMEDIATE
    CSCHECKIN_STAGED
);

use Change::DB;
use Change::AccessControl qw(isInvalidContext isPrivilegedMode);
use Change::Util::Interface qw(installScripts removeScripts removeAllFiles
			       setForBugFix installFilesTo);
use Util::File::NFSLock ();
use Util::Message qw(debug fatal warning error alert verbose verbose_alert open_log);

use Production::Services;
use Production::Services::ChangeSet;
use Change::Plugin::Approval::TSMV;

my $copy_to_cbld = 0;# Compatibility -- should disappear in future.

open_log();
verbose("Commandline: ", join(' ', $0, @ARGV));

#==============================================================================

=head1 NAME

csalter - Privileged tool to alter change set attributes such as the status

=head1 SYNOPSIS

  State transitions:

    $ csalter 426D09B61BE3E94D P

    $ csalter --status P 426D09B61BE3E94D 426D09B71BE3E94D 426D09B81BE3E94D

    $ csalter 426D09B61BE3E94D A=P

    $ csalter --status A=P 426D09B61BE3E94D

    $ csalter --force_status --status C 426D09B61BE3E94D

    $ csalter -f que.c.checkin.sh A=P

    $ csalter --files que.c.checkin.sh --state P --fromstate A

  Adding a declared dependency:

    $ csalter 426D09B61BE3E94D 44B29E1207E17F01B5=CONTINGENT

  Bulk state transitions:

    $ csalter --all A=P

    $ csalter --allexcept 426D09B61BE3E94D 426D09B71BE3E94D P=C

    $ csalter --allexcept -f *.checkin.sh1 P=C

    $ csalter C=L --input biglistofcsids.txt

    $ ls *.checkin.sh1 | csalter P=C --allexcept --input --files

    $ ls *.checkin.sh1 | csalter P=C -xfi  #same as above, short option names

  Installation/Removal:

    $ csalter --bugf 426D09B61BE3E94D           # set for bug fix

    $ csalter --install 426D09B71BE3E94D N=A    # administrator 'approval'

    $ csalter --stage 426D09B71BE3E94D		# administrator 'checkin'

    $ csalter --remove 426D09B71BE3E94D         # 'suspend' changeset

    $ csalter --unstage 426D09B71BE3E94D A=R    # administrator 'rollback'


  Internal Maintenance:

    $ csalter --lock_message "Maintenance.  Please wait 10 mins and try again"

    $ csalter --lock_remove

    $ csalter --lock_create

    $ csalter --rewrite

  TSMV Maintenance:
    $ csalter --attach_tsmv 44324 426D09B61BE3E94D
    $ csalter --attach_tsmv 44324 426D09B61BE3E94D S=N
    $ csalter --detach_tsmv 426D09B61BE3E94D
    $ csalter --detach_tsmv 426D09B61BE3E94D A=R

=head1 DESCRIPTION

This tool allows certain attributes of change sets to be altered after they
have been entered into the change set database. One or more change set IDs
must be supplied, or, if the C<--files> option is used, one or more files in
which change set IDs are looked for.

The status may be changed arbitrarily, or a transition from a previous state
given. In the latter case, the new state will be set only if the old state
corresponds to the specified prior state.

The C<--all> or C<-a> option allows all changesets in the database to be
transitioned to a specified state. This mode is intended to be used with a
from status transition rather than an unrestricted transition.

B<I<This tool requires administrator privileges to run. It cannot be used,
nor is it intended for use, by users.>>

=head1 NOTES

=head2 Supported Transition Types

At this time only status transitions are supported. Transitions of stage and
move type will be supported in future. Other attributes such as the time or
the user I<may> also be supported if a requirement is identified. However, the
reason text or the files may never be changed and cannot be altered with this
tool.

=head2 Installation and Removal of Staging Files

As C<csadmin> is a tool for administering change sets, it can also be used
to add or remove the staging scripts on demand. No check is made that the
new state is appropriate for the presence (or otherwise) of the staging
scripts, therefore the C<--install>, C<--stage>, C<--remove> and 
C<--unstage> options should be used with care.

In particular, the following operations mirror conventional process steps but
bypass normal constraints, assuming that the specified changeset has been
submitted but not yet swept:

=over 4

=item * The command C<csalter --install E<lt>CSIDE<gt> N=A> performs the
        equivalent transition to an approval.

=item * The command C<csalter --stage E<lt>CSIDE<gt>> performs the
        equivalent transition to a checkin.

=item * The command C<csalter --unstage E<lt>CSIDE<gt> A=R> performs the
        equivalent transition to a rollback.

=back

These options are also used by approval mechanisms to move a change set from
waiting for approval to active.

=head2 Setting a Change Set for Bug Fix

The C<--bugf> or C<-b> option will cause C<csalter> to write the details for
any specified change sets to the 'bug fix' processing lists. This will cause
a regular change set to be processed as a bug fix by the next bug fix (or
regular) sweep.

At this time the move type of the changeset is not updated to reflect its
altered processing status; this will be addressed in time.

=head2 Attach or Detach a Change Set to a TSMV Ticket

The C<--attach_tsmv> option will cause C<csalter> to populate the specified
change set to the TSMV ticket. Please note this will not add the TSMV
ticket number into the change set record and it will not update the status
of the change set if user does not specify which status it should be updated
to.

The C<--detach_tsmv> option will cause C<csalter> to rollback the specified
change set from the TSMV ticket. If the specified change set does not associate
with a TSMV ticket, it will fail to rollback. Please note this option will not
update the change set record if user does not specify which status it should
be updated to.

=head2 Applying operations to siblings of a change set

The concept of a sibling refers to change sets that have been generated 
as part of a split operation for higher-priority change sets. An EMOV
change sets will result in two identical change sets with move type
BUGF and MOVE. Subsequently, a BUGF change set will result in one 
additional MOVE change set.

When specifying the C<--sibling> or C<-S> switch, the requested operation
will be applied not only to the given change sets but also to all of their
siblings if any. This switch is most useful for changing the status of a
change set from C<Waiting> (N) to C<Active> (A): When an EMOV change set
is approved, this approval should be applied to its siblings to. Therefore:

    $ csalter -S 44AC01200DA91001B5 N=A

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = "csalter"; #basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-s [<state>=]<state>] [-f] -a | [-x] <csid> [<csid>...]
  --all         | -a              change all change sets (with matching status
                                  if a 'from' status is specified)
  --allexcept   | -x              change all change sets *except* those
                                  specified on the command line (or via -f)
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --status      | -s [<F>=]<T>    status to change to, and optionally required
                                  prior status to change from
  --force_status                  force the status change requested
  --verbose     | -v              enable verbose reporting

Derivation of Change Set ID arguments:

  --files       | -f              interpret arguments as files, not CSIDs
  --input       | -i [<file>]     read additional list of CSIDs (or files,
                                  with -f) from standard input, or a file if
                                  specified.

Staging installation/removal (not with --all or --allexcept):

  --install     | -I              create staging scripts
  --stage			  install staging files and scripts
  --remove      | -R              remove staging scripts
  --unstage     | -U              remove sources, scripts, and reason files
  --bugf | --bf | -b              mark as bug fix

Production Services Interaction:

  --development | -P              update development-side database only
  --production  | -p              update production-side database only

Internal Maintenance:

  --lock_message <message>        set message people see when waiting for lock
  --lock_remove <stale_lock_file> remove lock
  --lock_create                   create lock (e.g. temporarily disable others)
  --rewrite     | -r              rewrite entry in database from the audit file

Branching and dependencies:

  --dependency  | -D CSID=DEP     add a dependency on CSID of type DEP
  --siblings    | -S              apply operation to all sibling change sets 
                                  when applicable.
                                  (only effective when SCM_BRANCHING_ENABLED
                                   is true)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");

    # plugins and files-from-input
    Getopt::Long::Configure("pass_through");
    GetOptions(\%opts,"input|i:s");
    Getopt::Long::Configure("no_pass_through");
    if (defined $opts{input}) {
	my @lines;
	if ($opts{input}) {
	    open INPUT,$opts{input}
	      or fatal "Unable to open $opts{input}: $!";
	    @lines=<INPUT>;
	    close INPUT;
	} else {
	    @lines=<STDIN>;
	}
	my @input_args=map { chomp; split /\s+/,$_ } @lines;
	unshift @ARGV,@input_args if @input_args;
    }

    unless (GetOptions(\%opts, qw[
        all|a
        allexcept|x
        bugf|bf|isbf|b!
        debug|d+
        dependency|D=s
        files|f!
	force_status
        help|h
        install|I
        stage
	lock_create
	lock_remove=s
	lock_message=s
        development|P
        production|p
        status|s=s
        remove|R
	rewrite|r=s
        unstage|U
	attach_tsmv=s
	detach_tsmv
        verbose|v+
        siblings|S
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    if (exists $opts{lock_create} || exists $opts{lock_remove}
	|| exists $opts{lock_message} || exists $opts{rewrite}) {
	$opts{maint} = 1;
	return \%opts;
    }

    # no arguments (1)
    usage("Nothing to do"),
      exit EXIT_FAILURE
	if @ARGV<1 and not ($opts{all} and $opts{status});

    # install/remove
    if ($opts{install} and $opts{remove}) {
	fatal "--install and --remove options are mutually exclusive";
    }
    if ($opts{stage} and $opts{install}) {
	fatal "--stage and --install options are mutually exclusive";
    }
    if ($opts{stage} and $opts{remove}) {
	fatal "--stage and --remove options are mutually exclusive";
    }
    if ($opts{install} or $opts{remove}  or  $opts{stage}) {
	if ($opts{all} or $opts{allexcept}) {
	    fatal "use of --install or --stage or --remove with --all or --allexcept ".
	      "is not supported";
	}
    }

    if ($opts{attach_tsmv} and exists $opts{detach_tsmv}) {
	fatal "--attach_tsmv and --detach_tsmv are mutually exclusive";
    }

    if (@ARGV) {
	# leading/trailing status/dependency arg
	if (my ($head, $tail) = $ARGV[-1] =~/^([A-Z0-9]+)(=[A-Z0-9]+)?$/) {
	    if ($opts{status}  and  defined $tail) {
		fatal "Trailing status argument '$ARGV[-1]' and explicit ".
		  "status option '$opts{status}' are mutually exclusive";
	    } elsif ($opts{dependency} and defined $tail and $tail =~ /=(S|C|D|R)/) {
                fatal "Trailing dependency argument '$ARGV[-1]' and explicit " .
                      "dependency option '$opts{dependency}' are mutually exclusive";
            } else {
                if ($head =~ /^[A-Z]$/) {
                    $opts{status}=pop @ARGV;
                } elsif ($head =~ /^[A-F0-9]{18}$/ and not defined $opts{dependency}
			    and defined $tail and $tail =~ /=(S|C|D|R)/) {
                    $opts{dependency}=pop @ARGV;
                } 
	    }
	}
	
	if (defined $ARGV[0] && (my ($head, $tail) = $ARGV[0] =~/^([A-Z0-9]+)(=[A-Z0-9]+)?$/)) {
	    if ($opts{status} and $head =~ /^[A-Z]$/) {
		fatal "Leading status argument '$ARGV[0]' and explicit ".
		  "status option '$opts{status}' are mutually exclusive";
	    } elsif ($opts{dependency} and defined $tail) {
		fatal "Leading dependency argument '$ARGV[0]' and explicit ".
		  "dependency option '$opts{dependency}' are mutually exclusive";
            } else {
                if ($head =~ /^[A-Z]$/) {
                    $opts{status}=shift @ARGV;
                } elsif ($head =~ /^[A-F0-9]{18}$/ and defined $tail and $tail =~ /=(S|C|D|R)/) {
                    $opts{dependency}=shift @ARGV;
                }
	    }
	}
    }

    # no (2)/conflicting arguments
    usage("Nothing to do"),
      exit EXIT_FAILURE
	if @ARGV<1 and not ($opts{all} and $opts{status} and $opts{dependency});
    usage("--all conflicts with explicit CSID argments"),
      exit EXIT_FAILURE if @ARGV>0 and $opts{all};

      unless ($opts{production} || $opts{development}) {
	  $opts{production} = 1 && $opts{development} = 1;
      }

    return \%opts;
}

sub scanFiles {
    my @files=@_;

    my %csids;
    foreach my $file (@files) {
	if (-f $file) {
	    open(FILE,$file)
	      or warning("unable to open $file - skipped: $!"), next;
	    my $found=0;
	    while (<FILE>) {
		/(?:CHANGE_SET|CSID):\s*(\w+)\b/ and do {
		    $csids{$1}=1;
		    $found++;
		    verbose "$file lists change set $1";
		    last;
	        };
	    }
	    close $file;
	    warning "$file does not contain any recognizable change set IDs"
	      unless $found;
	} else {
	    warning "$file not found - skipped";
	    next;
	}
    }

    return keys %csids;
}

sub remove_cached_headers ($$) {

    my($changeset,$csid) = @_;
    my $manifestFile = COMPCHECK_DIR."/".$changeset->getMoveType()."/".
        $csid."/"."header.manifest";
    return unless -e $manifestFile;
    
    my $manifestFH = new IO::File;
    open($manifestFH, "<".$manifestFile)
      || warning("cannot open $manifestFile (contact SI Build Team): $!");

    while(my $file=<$manifestFH>) {
        chomp $file;
        next if $file eq "";
        if (!unlink($file) || -e $file) {
            warning "WARNING: $file not deleted. Please contact SI Build Team.";
        }
    }
    close $manifestFH;
}

sub get_siblings ($$) {
    my ($cs, $changedb) = @_;

    my @sibids = $cs->getDependenciesByType(DEPENDENCY_TYPE_SIBLING);
    return if not @sibids;

    my @siblings;
    for (@sibids) {
        my $cs = Production::Services::ChangeSet::getChangeSetDbRecord(
                    getSVC(), $_
        );
        warning "Sibling $_ could not be retrieved", next if not $cs;
        push @siblings, $cs;
    }

    return @siblings;
}

#------------------------------------------------------------------------------
# Production services integration

{ my $svc=new Production::Services;

  sub alterChangeSetDbRecordStatus ($$) {
      my ($changeset,$newstatus)=@_;

      my $rc=Production::Services::ChangeSet::alterChangeSetDbRecordStatus(
          $svc,$changeset,$newstatus
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub alterMultiChangeSetDbRecordStatus($@) {
    my ($newstatus, @changesets)=@_;

    my $rc=Production::Services::ChangeSet::alterMultiChangeSetDbRecordStatus(
        $svc,$newstatus,@changesets);			
    
     error $svc->getError() unless $rc;

      return $rc;
  }

  sub addDependencyToChangeSet($$$) {
      my ($csid, $depends_on, $type)=@_;
      my $rc=Production::Services::ChangeSet::addDependencyToChangeSet(
          $svc,$csid,$depends_on,$type);

      error $svc->getError() unless $rc;

      return $rc;
  }

    sub alterMultiChangeSetStatusByStatus {
        my ($old, $new, @csids) = @_;
        my @changed = 
          Production::Services::ChangeSet::alterMultiChangeSetStatusByStatus(
                  $svc, $old, $new, \@csids
        );
        return @changed;
    }

  sub getSVC() {
      return $svc;
  }

}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    if (my $reason=isInvalidContext) {
	fatal $reason;
    }

    unless (isPrivilegedMode) {
	fatal "This tool cannot be run by an unprivileged user";
    }

    # lock maintenance
    if ($opts->{maint}) {
	if (exists $opts->{lock_message}) {
	    $opts->{lock_message} .= "\n" unless $opts->{lock_message} eq "";
	    my $FH = Symbol::gensym;
	    open($FH,'>'.DBLOCKFILE)
	      && (print $FH $opts->{lock_message})
	      && close($FH)
	      || error("Error writing lock message: $!");
	}
	if ($opts->{lock_remove}) {
	    ## Although removing DBLOCKFILE is allowed here, it should not be
	    ## done except in extreme cases.  The hard links to change.lock
	    ## should be removed and tested before change.lock is removed.
	    if ($opts->{lock_remove} =~ /^(\Q${\DBLOCKFILE}\E[\w.-]*)$/) {
		$opts->{lock_remove} = $1;  # untaint
		unlink($opts->{lock_remove})
		  || fatal("Unable to remove ".$opts->{lock_remove}.": $!");
	    }
	    else {
		fatal("Invalid path or characters in lock file: "
		     .$opts->{lock_remove});
	    }
	}
	if ($opts->{lock_create}) {
	    my $unlock_token =
	      Util::File::NFSLock::safe_nfs_lock(DBLOCKFILE,USER);
	    $unlock_token
	    ? (alert("Created lock file: "),
	       alert("  ".$unlock_token->{locklink}),
	       alert("Lock file must be manually removed when done with "
		    ."maintenance"))
	    : error("Failed to create lock on ".DBLOCKFILE);
	    ##<<<TODO: add a method to NFSLock.pm to disable destructor
	    ## rather than reaching across and doing it magically
	    $unlock_token->{lockpid} = 0 if $unlock_token;
	    exit $unlock_token ? 0 : 1;
	}
    }

    if ($opts->{files}) {
	@ARGV=scanFiles(@ARGV);
	# Continue if allexcept condition is used.
	if(!$opts->{allexcept})
	{
	  fatal "No change set IDs found in supplied file list" unless @ARGV ;
        }
    }

    my ($fromstatus,$tostatus,$depends_on,$dep_type);
    if ($opts->{status}) {
	($fromstatus,$tostatus)=split /=/,$opts->{status};
	$tostatus=$fromstatus,$fromstatus=undef unless defined $tostatus;
    } elsif ($opts->{dependency}) {
        ($depends_on,$dep_type)=split /=/,$opts->{dependency};
    }

    my $changedb=new Change::DB(DBPATH);
    error("Unable to access ${\DBPATH}: $!"), return EXIT_FAILURE
      unless defined $changedb;

    my $caught_signal = 0;
    Util::File::NFSLock::safe_nfs_signal_traps(); #graceful under SIGINT
    my ($intsig,$termsig,$alrmsig,$tstpsig)=($SIG{INT},$SIG{TERM},$SIG{ALRM},$SIG{TSTP});
    ($SIG{INT},$SIG{TERM},$SIG{ALRM},$SIG{HUP},$SIG{TSTP}) =
      ('IGNORE','IGNORE','IGNORE','IGNORE','IGNORE');

    my $result=0;
   
    if (exists $opts->{rewrite}) {
      my $cs = $changedb->getChangeSet($opts->{rewrite})
          or fatal "cannot load change set for $opts->{rewrite}";

      my @css = ($cs);
      push @css, get_siblings($cs, $changedb) if $opts->{siblings};

      if ($opts->{production}) {
	  # set production from log
	  
	  my $svc = Production::Services->new()
	      or  fatal "cannot create Production::Services object";
	  
	  for (@css) {
            Production::Services::ChangeSet::createChangeSetDbRecord($svc,$_)
		or warning "failed to createChangeSetDbRecord for $_: " . 
		    $svc->getError();
	  }
      }

      if ($opts->{development}) {
	  # set dev from log
	  for (@css) {
	      my $err = !$changedb->rewriteChangeSet($_);
	      $err  and  warning "failed to createChangeSetDbRecord for $_"; 
	      $result ||= $err;
	  }
      }

    } # exists $opts->{rewrite}

    elsif ($opts->{all}) {
	fatal "Must supply a status with -all" unless $tostatus;
        if ($opts->{development}) {
	    my $unlock_token = Util::File::NFSLock::safe_nfs_lock
		               (DBLOCKFILE,USER);
	    my @csids=$changedb->transitionAllChangeSetStatuses
		($fromstatus => $tostatus);
       
## GPS: why isn't production updated here, as with $opts->{allexcept} below?
	  Util::File::NFSLock::safe_nfs_unlock($unlock_token);
	    verbose_alert "$_ status altered to $tostatus" foreach @csids;
	}
    } # $opts->{all}
    
    elsif ($opts->{allexcept}) {
	fatal "Must supply a status with -allexcept" unless $tostatus;

        my @csids;

        if ($opts->{production}) {
	    $SIG{INT}=$SIG{TERM}=$SIG{ALRM}=$SIG{HUP}=$SIG{TSTP} = 
		sub { $caught_signal=1 };	    
            @csids = alterMultiChangeSetStatusByStatus(
                        $fromstatus, $tostatus, @ARGV 
            );
	}
        if ($opts->{development}) { 
            # in theory, we should only change @csids as returned from
            # alterMultiChangeSetStatusByStatus above. However, Change::DB
            # offers no sane API for that. The closest approximation would
            # be transitionChangeSetStatus() but this requires looping and
            # is therefore useless here. 
	    my $unlock_token = Util::File::NFSLock::safe_nfs_lock
		               (DBLOCKFILE,USER);
	    $changedb->transitionAllChangeSetStatusesExcept
		($fromstatus => $tostatus, undef, map {uc} @ARGV);	 
	  Util::File::NFSLock::safe_nfs_unlock($unlock_token);
	    verbose_alert "$_ status altered to $tostatus" foreach @csids;
	}

    } # $opts->{allexcept}
    
    else {
	my $root;
	if ($opts->{install}  or  $opts->{stage}) {
	    require BDE::FileSystem;
	    require BDE::Util::DependencyCache;
	    $root=new BDE::FileSystem(STAGE_PRODUCTION_ROOT);
	    BDE::Util::DependencyCache::setFileSystemRoot($root);
	}
	my $changed=0;
	my(%changesets,$changeset,$status,@alter_in_prod);
	my $unlock_token = Util::File::NFSLock::safe_nfs_lock(DBLOCKFILE,USER);
	my %csids;

	map { $csids{uc $_} = 1 } @ARGV;
	my @csids = sort keys %csids;

        my $svc=getSVC();
        foreach (@csids) {
            $changeset = Production::Services::ChangeSet::getChangeSetDbRecord(
                                     $svc, $_);
            $changesets{$_} = $changeset if $changeset;
        }

        my @siblings;
        if ($opts->{siblings}) {
            push @siblings, get_siblings($_, $changedb) for values %changesets;
        }

        for (@siblings) {
            push @csids, $_->getID;
            $changesets{$_->getID} = $_;
        }

        @csids = sort @csids;

	foreach my $csid (@csids) {
	    $changeset=$changesets{$csid};
	    unless ($changeset) {
		$result=1;
		warning "Change set $csid not found in database - ignored";
		next;
	    }
	    debug "found change set '$csid'";

            if ($depends_on) {
                if (!$changedb->addDependencyToChangeSet($csid, $depends_on, $dep_type)) {
                    warning "Failed to add dependency to '$csid'";
                }
                push @alter_in_prod,$changeset;
            }

	    $status=$changeset->getStatus();
	    if ($fromstatus) {
		if ($fromstatus ne $status
		    ##<<<TODO: not sure why S sometimes does not become N,
		    ##         but allow transition to A until we know why
		    && !($fromstatus  eq STATUS_WAITING
			 && $status   eq STATUS_SUBMITTED
			 && $tostatus eq STATUS_ACTIVE)) {
		    warning "Change set $csid has status $status, ".
		      "not $fromstatus - skipped";
		    next;
		}
	    }

	    if ($tostatus) {
		$status = "" if $opts->{force_status};
		if ($status eq $tostatus) {
		    verbose "$csid already has status $tostatus";
		} else {
		    if ($opts->{development}) {
			$changedb->transitionChangeSetStatus
			    ($changeset,$status,$tostatus);
			verbose_alert "$csid status $status altered to ".
			    $tostatus;
		    }

		    push @alter_in_prod,$changeset;
		}
		$changed=1;
	    };

	    if ($opts->{install}) {
		if ($changeset->isImmediateMove() or $changeset->isBregMove()) {
		   installScripts($changeset,$copy_to_cbld);
		   verbose "$csid scripts installed";
		}
		$changed=1;
	    } elsif ($opts->{stage}) {
		# install scripts if STPR or breg-change set
		if ($changeset->isImmediateMove() or $changeset->isBregMove()) {
		   installFilesTo($changeset,CHECKIN_ROOT);
		   installScripts($changeset,$copy_to_cbld);
		}
		my $SCMmove=$changeset->getMoveType();
		my $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_REGULAR;
		if ($SCMmove eq MOVE_BUGFIX) {
		    $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_BUGFIX;
		} elsif ($SCMmove eq MOVE_EMERGENCY) {
		    $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_EMERGENCY;
		} elsif ($SCMmove eq MOVE_IMMEDIATE) {
		    $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_IMMEDIATE;
		}
		installFilesTo($changeset, $SCMdestloc);
		verbose "$csid staged";
		$changed=1;
	    } elsif ($opts->{remove}) {
		if ($changeset->isImmediateMove() or $changeset->isBregMove()) {
		    removeScripts($changeset);
		}
		verbose "$csid scripts removed";
		$changed=1;
	    } elsif ($opts->{unstage}) {
		if ($changeset->isImmediateMove() or $changeset->isBregMove()) {
		    removeAllFiles($changeset);
		}
		remove_cached_headers($changeset, $csid);
		verbose "All $csid files removed";
		$changed=1;
	    }

	    if ($opts->{bugf}) {
                # the bugf switch makes no sense for sibling changesets
                next if $changeset->getDependenciesByType(DEPENDENCY_TYPE_SIBLING);

		setForBugFix($changeset);
		verbose "$csid set for bug fix";
		$changed=1;
		#<<<TODO: also change move type
	    }	    
	    
	    if ($opts->{attach_tsmv}) {
		
		if( scalar (@csids) ==1) {
		  Change::Plugin::Approval::TSMV::populateTSMV($opts->{attach_tsmv}, $csid);
		} else {
		    verbose "Only one changeset can be populated from the TSMV ticket";
		}
	    } elsif (exists $opts->{detach_tsmv}) {
		my $tsmv = $changeset->getReferences();		
		if($tsmv =~ /^TSMV/) {
		    my $rc = Change::Plugin::Approval::TSMV::rollbackTSMV(
			      $tsmv, $changeset);		    
		    
		} else {
		    verbose "No TSMV ticket associated with this changeset"; 
		}
	    }
	    
	}
	Util::File::NFSLock::safe_nfs_unlock($unlock_token);
	$result=1 unless $changed; #if nothing changed, consider it a failure
## GPS: The beginning of robocop sweep sends csids through this block (A=>P)
##	and is probably the bulk of the time that robocop waits.
##	See above for suggestions of running in parallel.
##	? Add alarm around calls to prod?
	if (@alter_in_prod && $opts->{production}) {
	    $SIG{INT}=$SIG{TERM}=$SIG{ALRM}=$SIG{HUP}=$SIG{TSTP}= sub { $caught_signal=1 };
	    
            if ($tostatus) {
                if (scalar(@alter_in_prod) >1) {
                    alterMultiChangeSetDbRecordStatus($tostatus, @alter_in_prod);
                } else {		
                    alterChangeSetDbRecordStatus($alter_in_prod[0],$tostatus);
                }	
            } elsif ($depends_on) {
                addDependencyToChangeSet($_->getID,$depends_on,$dep_type)
                    for @alter_in_prod;
            }
	}
    }

    #($SIG{INT},$SIG{TERM},$SIG{ALRM})=($intsig,$termsig,$alrmsig);

    exit $result;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)
Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_querycs.pl>, L<bde_findcs.pl>

=cut
