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
use Getopt::Long;
use Term::Interact;

use Util::File::Basename qw(basename);
use Util::Message qw(error debug warning fatal);
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);

use Change::DB;
use Production::Symbols qw(SCM_PRLSPD_ENABLED);
use Production::Services;
use Production::Services::Ticket qw(addTicketLog);

use Change::Symbols qw(DBPATH);

#==============================================================================

=head1 NAME

bde_addticketlog.pl - adding a log entry to a ticket(DRQS, TREQ, TSMV supported now)

=head1 SYNOPSIS
    bde_addticketlog.pl changeset_id note
    bde_addticketlog.pl changeset_id note <DRQS>
    bde_addticketlog.pl changeset_id note <DRQSxxxxxx>
    bde_addticketlog.pl changeset_id note <TSMV>
    bde_addticketlog.pl changeset_id note <TSMVxxxxxx>

=head1 DESCRIPTION

C<bde_addticketlog.pl> makes a production service query to add log entry to
specified ticket.

C<bde_addticketlog.pl> support to add log to DRQS or TSMV, if no ticket is
provided, and the ticket of the change set is DRQS, it will add a note to 
the drqs ticket. if provide DRQS number and which is different with the ticket in the change set, it will be overrided with the ticket in the change set. if provide TSMV number and which is different with the ticket in the change set, it will be overrided with the change set TSMV ticket.. if provide TSMV option,
but no TSMV ticket associated with the change set, it will be ignored.
 
On success, a zero exit status is returned if all the supplied user IDs are
valid testees. If any of the users are not valid, a positive exit status
is returned. If an error occurs, an error is issued to standard out and a
negative exit status is returned.

=cut

#==============================================================================
sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | <csid> <note> [-d] [-v] [-T]
  --debug       | -d            enable debug reporting
  --help        | -h            usage information (this text)  
  --verbose     | -v            enable verbose reporting
  --ticket      | -T            ticket (drqs, treq or tsmv)

See 'perldoc $prog' for more information.

_USAGE_END
}

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        verbose|v+	
	ticket|tickets|T=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage(), exit EXIT_FAILURE if @ARGV<2;

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}


MAIN: {   
    my $opts=getoptions();
        
    my ($ticket, $changeset, $response);
    
    my $csid = $ARGV[0];
       $csid =~ /^(.*)$/ and $csid = $1; #untaint
       $csid=uc($csid);

    my $note = $ARGV[1];
    my $svc=new Production::Services();

    if (SCM_PRLSPD_ENABLED) {
      my $changeset = Production::Services::ChangeSet::getChangeSetDbRecord(
			  $svc, $csid);

    } else {
      my $changedb = new Change::DB('<'.DBPATH);
      fatal("Unable to access ${\DBPATH}: $!")
	  unless defined $changedb;
	  
      $changeset=$changedb->getChangeSet($csid);	
    }

    fatal("Change set $csid not found in database")
      unless defined $changeset;
       
    # current policy does not allow to add log to treq
    if($opts->{ticket}) {
	if($opts->{ticket}=~ /^DRQS/) {

	    if($changeset->getTicket() =~ /DRQS/) {	   
		 if($opts->{ticket}=~ /^DRQS\d+/ && 
		    $opts->{ticket} ne $changeset->getTicket() ){		 
		    warning "Drqs number supplied in command line is different ".
		            "with change set -ignored.";
	         }

	         $response = addTicketLog($svc, $csid, $changeset->getTicket(), 
			        	     $changeset->getUser(), $note);
	    } else {
	        error "Change set ticket is Treq, No log added!";
	        exit(EXIT_FAILURE);
	    }	 

	} elsif ($opts->{ticket}=~ /^TSMV/) {		  
	    if($changeset->getMessage() =~ /Change-Set-Reference: TSMV(\d+)/ ) {	
		my $tsmv = "TSMV".$1;
		
		   if($opts->{ticket} =~ /^TSMV\d+$/ &&
		      $opts->{ticket} ne $tsmv) {
		       warning "TSMV number supplied in command line is different ".
			   "with change set -ignored.";  
		   }
		
                   $response = addTicketLog($svc, $csid,
				     $tsmv, 
				     $changeset->getUser(), $note); 
	     } else {
		 error "No TSMV ticket for the change set, no log added!";
		 exit(EXIT_FAILURE);
	     }	      
	   
	} else {
	    error "Invalid ticket type($opts->{ticket}) to add log";
	    exit(EXIT_FAILURE);
	}
    } elsif($changeset->getTicket() =~ /DRQS/) {
	$response = addTicketLog($svc, $csid, $changeset->getTicket(), 
				 $changeset->getUser(), $note);	
    } else {
	error "Change set ticket is TREQ, no log added!";
	exit(EXIT_FAILURE);	
    }

    unless (defined $response)
    {
	error $svc->getError();
	exit(EXIT_FAILURE);
    }

    print "Add log successfully!\n";

    exit(EXIT_SUCCESS);
}

#==============================================================================

=head1 AUTHOR

Ellen Chen (qchen1@bloomberg.net)

=head1 SEE ALSO

L<bde_addticketlog.pl>

=cut
