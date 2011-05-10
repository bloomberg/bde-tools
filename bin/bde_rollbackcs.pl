#!/bbs/opt/bin/perl -w
use strict;

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
use Getopt::Long;

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE 
);
use Change::Symbols qw(
    STAGE_PRODUCTION_ROOT

    STATUS_SUBMITTED STATUS_ACTIVE STATUS_ROLLEDBACK 
    STATUS_WAITING 

    COMPCHECK_DIR
    USER 
    MOVE_EMERGENCY MOVE_BUGFIX MOVE_REGULAR

    DEPENDENCY_TYPE_ROLLBACK DEPENDENCY_TYPE_SIBLING
);

use Change::AccessControl qw(isInvalidContext isAdminUser);
use Change::Util::Interface qw(removeAllFiles
			       isSweepLocked);
use Change::Util::InterfaceSCM qw(postChangeSetSCM enqueueChangeSetSCM);

use Term::Interact;
use Util::Message qw(message debug fatal warning error alert);

use Production::Services;
use Production::Services::ChangeSet     qw/getChangeSetDbRecord 
                                           addDependencyToChangeSet
                                           getChangeSetStatus/;
use Production::Services::Ticket;
use Production::Symbols qw(HEADER_REFERENCE 
                           SCM_SERVER_ENABLED
                           SCM_BRANCHING_ENABLED SCM_CHECKINROOT_ENABLED);

#==============================================================================

=head1 NAME

csrollback - Roll back or reinstate a previously created change set

=head1 SYNOPSIS

Roll back a current change set:

    $ csrollback 428E32AD001476E94D

=head1 DESCRIPTION

This tool allows submitted change sets to be rolled back. Multiple change sets
may be specified if required. If a specified change set is not present, a
warning is generated.

=head2 Rolling Back a Change Set

This is the default mode, and may also be explicitly requested with the
C<--rollback> or C<-R> option. C<csrollback> allows you to roll back change
sets that are in state submitted (S), waiting for approval (N) and active (A).

When a change set roll-back is requested, and the change set is present in the
database, a new change set is generated containing the file versions which were
present before the change set being rolled back was checked in. The change set
to be rolled back has its status changed to C<R>.

If rolling back a changeset whose cscheckin command specified --autoco, the
changeset's files will remain checked out (locked) by the user who issued
the cscheckin command.

=head2 Reinstating a Previously Rolled-Back Change Set

For reinstanting a previously rolled-back change set, please use C<cscheckin
--reinstate $CSID>.

=head2 Rolling Back EMOVs and BUGFs

The introduction of movetypes as branches has some consequences for roll-backs,
too. On checking in an EMOV, a BUGF and MOVE change set with the same file content
has been  generated and submitted. Rolling back this EMOV will subsequently
result in rolling back these C<sibling> change sets of lower movetype, too.
Likewise for BUGF, which results in an additional MOVE change set.

The rule is that when you roll back a  change set being part of a sibling set,
the siblings of lower movetype will automatically be rolled back as well.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = "csrollback"; #basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [[--rollback] | --reinstate] <csid> [<csid>...]
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting

Rollback/Reinstate Mode:

  --rollback    | --undo | -U     rollback (undo) active change set (default)
  --reinstate   | --redo | -R     reinstate previously rolled-back change set

See 'perldoc $prog' for more information.

_USAGE_END
}

# --user        | -u <username>  passed user when running setreuid.

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        message|m=s
        user|u=s
        verbose|v+
        rollback|undo|U
        reinstate|redo|R
	recover|r
        norecover|n
        siblings|S
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{list};

    # primary mode
    if ($opts{reinstate} and $opts{rollback}) {
	error "--reinstate and --rollback options are exclusive";
	exit EXIT_FAILURE;
    }
    unless ($opts{reinstate} or $opts{rollback}) {
	$opts{rollback}=1;
    }

    # recover/norecover
    if ($opts{recover} and $opts{norecover}) {
	error "--recover and --norecover options are exclusive";
	exit EXIT_FAILURE;
    }
    if ($opts{recover}) {
	fatal "Use csrecover to recover files";
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

sub userCanRollback ($$) {
    my ($changeset,$user)=@_;

    return 1 if $user eq $changeset->getUser();
    return 1 if isAdminUser($user);
    return 0;
}

#<<<TODO rename 'getReference' and move to Set.pm?
sub getTSMVReference ($) {
    my ($changeset)=@_;
    # This should be fixed when we split out dependencies so they
    # don't use the HEADER_REFERENCE header
    #
    # This is a *hack*, in to handle the case where we've got a
    # change.db record that was created before the reference
    $changeset->getMessage() =~ /${\HEADER_REFERENCE}: (\S+)/;
    my $refheader = $1 || "";
    foreach ($refheader, $changeset->getReferences()) {
      return $_ if /^TSMV/;
    }
    return;
#    my $returnval = join(",", $1,  $changeset->getDependencies());
#    return $returnval;
#    return join(",", $changeset->getDependencies());
#    return $1;
}

#------------------------------------------------------------------------------
# Production services integration

{ my $svc=new Production::Services;

  sub createChangeSetDbRecord ($) {
      my $changeset=shift;

      my $rc=Production::Services::ChangeSet::createChangeSetDbRecord(
          $svc,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub addDependenciesToChangeSet ($) {
      my $cs = shift;

      my $csid = $cs->getID;
      my $deps = $cs->getDependencies;

      while (my ($on, $type) = each %$deps) {
          Production::Services::ChangeSet::addDependencyToChangeSet(
              $svc, $csid, $on, $type)
              or fatal $svc->getError;
      }
  }


  sub alterChangeSetDbRecordStatus ($$) {
      my ($changeset,$newstatus)=@_;

      my $rc=Production::Services::ChangeSet::alterChangeSetDbRecordStatus(
          $svc,$changeset,$newstatus
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

#<<<TODO get from 'rollback' plugin? (see comment in Plugin::Approval::TSMV.pm)
  sub rollbackTSMV ($$) {
      my ($tsmvid,$changeset)=@_;

      my $rc=Production::Services::Ticket::rollbackTSMV(
          $svc,$tsmvid,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub generateRollbackChangeSet {
      my $cs = shift;

      require Change::Set;

      my $user    = USER;
      my $csid    = Change::Set->generateChangeSetID($user);
      my $ticket  = $cs->getTicket;
      my $stage   = $cs->getStage;
      my $move    = $cs->getMoveType;
      my $msg     = "Rollback: " . $cs->getID;
      my $files   = 0;
      my $refs    = [];
      my $depend  = { $cs->getID => DEPENDENCY_TYPE_ROLLBACK };

      my $rb = Change::Set->new({
                csid  => $csid,  user    => $user, ticket  => $ticket,
                stage => $stage, move    => $move, message => $msg,
                files => $files, depends => $depend, reference => $refs,
      });

      return $rb;
  }
}

#------------------------------------------------------------------------------

sub remove_symbol_changes ($$) {
    my($changeset,$csid) = @_;
    my @movetypes = ($changeset->getUser() ne "registry")
      ? ($changeset->getMoveType())
      : (MOVE_EMERGENCY, MOVE_BUGFIX, MOVE_REGULAR);
    my @symbol_files;
    foreach my $movetype (@movetypes) {
	push @symbol_files,
	     map { COMPCHECK_DIR.'/'.$movetype."/symbols/$_.$csid" }
		 qw(added removed);
    }
    my $FH = Symbol::gensym;
    foreach my $file (@symbol_files) {
	## truncate file instead of attempting removal because user "robocop"
	## is part of "sibuild" group, but initgroups() is not run in robogw,
	## and "bldtools" owns the directory containing these files

        if (-e $file) {
	    if (! -f $file) {
	        warning("symbol file $file is not a regular file (contact SI Build Team)");
		next;
	    }
	    if (!open $FH, ">".$file) {
	        warning("Attempt to open symbol file $file failed (contact SI Build Team): $!");
		next;
	    }

	    if (!close $FH) {
	        warning("Attempt to close symbol file $file failed (contact SI Build Team): $!");
		next;
	    }

	    # -f $file && open($FH,'>'.$file) && close $file;  # truncate

	    #next unless (-e $file);
	    #unless (unlink($file) && ! -e $file) {
	    #    warning "Unable to delete $file (will retry): $!";
	    #    unlink($file) && ! -e $file
	    #      || warning "Unable to delete $file (contact SI Build Team): $!";
	    #}
	}
    }
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
	
	if(-e $file && !unlink($file)) {
	    warning "WARNING: $file not deleted. Please contact SI Build Team.";  
	}
	
    }
    close $manifestFH;
}


sub enqueueRollbackToSCM ($) {
    my $rb = shift;

    if (enqueueChangeSetSCM($rb)) {
        message "Rollback change set (ID " . $rb->getID . ") has been enqueued on SCM";
    } else {
        return;
    }

    createChangeSetDbRecord($rb);
    return 1;
}

sub do_rollback {
    my ($rollbackcs, $rolled_back) = @_;

    fatal "Posting rollback changeset to SCM failed"
        if not postChangeSetSCM($rollbackcs);

    my $result = 1;

    if ($rolled_back->isImmediateMove() or
	$rolled_back->isBregMove()) {
	$result = 0 unless removeAllFiles($rolled_back);
    }

    ## Continue with these steps even if removeAllFiles
    ## does not succeed.  Otherwise, development change
    ## set database is out of sync with production.
    ## Also, removeAllFiles() might fail if there are
    ## missing files that were already removed.
    ## This logic still leaves open the possibility of
    ## files in a rolled back change set getting swept,
    ## but lessens syncing issues that result from
    ## robocop manual intervention in /bbsrc/checkin
    ##<<<TODO
    ## (Technically, removeAllFiles() should be done
    ##  *before* rollbackChangeSet(), but removeAllFiles
    ##  needs to be modified to return success if it is
    ##  unable to remoyesve files already removed)

    remove_symbol_changes($rolled_back, $rolled_back->getID);
    remove_cached_headers($rolled_back, $rolled_back->getID);

    alterChangeSetDbRecordStatus($rolled_back, STATUS_ROLLEDBACK);

    if (my $ref = getTSMVReference($rolled_back)) {
        rollbackTSMV($ref, $rolled_back);
    }

    fatal "Enqueueing rollback changeset to SCM failed"
        if not enqueueChangeSetSCM($rollbackcs);

    return $result;
}

{
    my $svc;
    
    sub get_change_set {
        my $csid = shift;

        $svc = Production::Services->new if not defined $svc;
        my $changeset = getChangeSetDbRecord($svc, $csid);
        return $changeset;
    }

    my %move2num = (
        MOVE_REGULAR()      => 0,
        MOVE_BUGFIX()       => 1,
        MOVE_EMERGENCY()    => 2,
    );
    sub create_rollback_change_sets {
        my ($cs) = @_;

        my @siblings;
        for my $sib ($cs->getDependenciesByType(DEPENDENCY_TYPE_SIBLING)) {
            my $sibcs = getChangeSetDbRecord($svc, $sib);
            push @siblings, $sibcs
                if $sibcs->getStatus ne STATUS_ROLLEDBACK &&
                   $move2num{$sibcs->getMoveType} < $move2num{$cs->getMoveType};
        } 

        @siblings = 
            sort { $move2num{$b->getMoveType} <=> $move2num{$a->getMoveType} }
                    @siblings;

        if (@siblings and -t STDIN) {
            my $csid = $cs->getID;
            my $move = $cs->getMoveType;
            print "\n";
            warning("The change set $csid ($move) has sibling change");
            warning("sets of lesser movetype. Those will be rolled back, too.");
            warning("The following change set(s) have been identified as" );
            warning("siblings:");
            for (@siblings) {
                my $csid = $_->getID;
                my $move = $_->getMoveType;
                warning "$csid ($move)";
            }
            if (!promptForYNA(scalar @ARGV)) {
                alert("Aborted by user");
                exit 0;
            }
        } elsif (-t STDIN) {
            my $csid = $cs->getID;
            my $move = $cs->getMoveType;
            warning("You asked to rollback $csid ($move)");
            if (!promptForYN()) {
                alert("Aborted by user");
                exit 0;
            }
        }

        my @css = $cs;
        push @css, @siblings if SCM_BRANCHING_ENABLED;

        my @rb;

        for my $cs (@css) {
            my $csid = $cs->getID;
            my $ticket = $cs->getTicket;

            my $msg = "Rollback: $csid";

            $svc = Production::Services->new    if not defined $svc;

            error("Unable to create Production::Service instance)"), 
                exit EXIT_FAILURE
                if not defined $svc;

            my $rb = generateRollbackChangeSet($cs);
            createChangeSetDbRecord($rb);
            addDependenciesToChangeSet($rb);
            push @rb, [ $cs, $rb ];
        }

        return @rb;
    }

    my $term;
    my $yna = '';
    sub promptForYNA {
        return promptForYN() if shift() < 2;
        return 1 if $yna eq 'a';
        $term = Term::Interact->new if not defined $term;
        $yna = $term->promptForYNA("Proceed [ (y)es / (n)o / yes to (a)ll ]? ");
        return 1 if $yna;
    }
    sub promptForYN {
        $term = Term::Interact->new if not defined $term;
        return $term->promptForYN("Proceed [ (y)es / (n)o ]? ");
    }
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    if (my $reason=isInvalidContext) {
	fatal $reason;
    }
   
    my $root=new BDE::FileSystem(STAGE_PRODUCTION_ROOT);
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    my $platform = `uname -s`;
    chomp($platform);
    if($platform eq "AIX") {
	error "Please run 'csrollback' on SUN machines for now. BUILD team is looking into issues reported on IBM. Thank you.";
	exit EXIT_FAILURE;
    }

    #<<<TODO: replace with mutually agreed NFS lock to prevent possible race
    if (isSweepLocked()) {
	error "Sweep lock is in effect, too late to roll back this change set";
	exit EXIT_FAILURE;
    }

    # Reinstating isn't allowed here.
    if ($opts->{reinstate}) {
      error "$0 --reinstate is deprecated. Please use cscheckin --reinstate <csid> instead\n";
      exit;
    }

    my ($intsig,$termsig,$alrmsig,$tstpsig)=($SIG{INT},$SIG{TERM},$SIG{ALRM},$SIG{TSTP});
    ($SIG{INT},$SIG{TERM},$SIG{ALRM},$SIG{HUP},$SIG{TSTP}) =
      ('IGNORE','IGNORE','IGNORE','IGNORE','IGNORE');

    my $result=0;
    my $csid;

    for (my $i=0; $i<@ARGV; $i++) {
	$csid=uc($ARGV[$i]); #allow case insensitivity

	if (my $changeset = get_change_set($csid)) {
	    my $status = $changeset->getStatus();
            exit $result if not $opts->{rollback};

            if ($status eq STATUS_ACTIVE or 
                $status eq STATUS_SUBMITTED or
                $status eq STATUS_WAITING) {
                if (userCanRollback($changeset,USER)) {
                    if (my @rb = create_rollback_change_sets($changeset)) {
                        my $result;
                        for (@rb) {
                            my ($targ, $rb) = @$_;
                            my $id = $targ->getID;
                            my $move = $targ->getMoveType;
                            warning "Rolling back $id ($move)...";
                            if (do_rollback($rb, $targ)) {
                                alert("$id rolled back");
                            } else {
                                error("Problem rolling back $id");
                            }
                        }
                    } else {
                        $result=3;
                        error "Failed to rollback change set $csid";
                    }
                } else {
                    $result=4;
                    error "User @{[USER]} is not privileged to roll back ".
                      "change set $csid created by ".$changeset->getUser();
                }
            } else {
                $result=2;
                error "Cannot rollback change set $csid ".
                  "with status '$status'";
            }
	} else {
	    $result=1;
	    warning "Change set $csid not found in database - ignored";
	}
    }

    exit ($result);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_querycs.pl>, L<bde_findcs.pl>

=cut
