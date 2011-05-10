package Change::Plugin::Approval::TSMV;
use strict;

use base 'Change::Plugin::Base';

use Util::Message qw(message fatal warning error);
use Symbols qw(EXIT_FAILURE);
use Change::Symbols qw(USER CSCHECKIN_TOOL);

use Production::Services;
use Production::Services::Ticket;

use constant TSMV_FILELIMIT => 99; # 100 - 1 for the CSID

#==============================================================================

=head1 NAME

Change::Plugin::Approval::TSMV - Plugin for TSMV approval

=head1 SYNOPSIS

  $ cscheckin -LApproval::TSMV --tsmv <ticketno> ...

=head1 DESCRIPTION

This plugin implements TSMV integration within C<cscheckin>. It may be manually
loaded to enable use of the command line extensions, and is otherwise
automatically loaded  when the approval type for a change set is determined to
be C<tsmv>, as determined through the L<Change::Approve> module.

The following process alterations are made by this plugin:

=over 4

=item * If manually loaded, the C<--tsmv> command line option is enabled.
        This takes an integer TSMV ticket number as its argument. (If the
        plugin is autoloaded on demand, the command line option will not
        available.)

=item * The C<--reference> command line option is disallowed, as TSMV overrides
        its use with C<--tsmv>.

=item * If the C<--tsmv> option is not used, it is prompted for interactively
        if in interactive mode, and the tool will abort if in non-interactive
        mode.

=item * If the ticket number supplied is not found in the TSMV database,
        or is otherwise inapplicable for use, the tool will abort.

=item * If the ticket number supplied is valid and the ticket number was
        supplied through an interactive prompt, then the description of the
        ticket is displayed and a Y/N confirmation prompt issued.

=item * The TSMV ticket description is used as the change set message. If
        C<--message> is used, the ticket description is prepended to the
        supplied message.

=item * When the change set is created, the TSMV ticket number is passed as
        the reference in the form 'TSMV<ticket no>'.

=back

The TSMV plugin is activated when an approval type of C<tsmv> is applicable
to a change set. It is an automatic plugin, and so does not need to be
manually loaded (i.e. with the C<--plugin> or C<-L> option of C<cscheckin>.)
However, the C<--tsmv> command-line options I<will not> be available unless
the plugin is explicitly requested. An attempt to load the plugin when C<tsmv>
approval is not applicable will cause C<cscheckin> to abort.

See L<"Change::Approve"> and the C<change.approve> configuration file for more
information.

=cut

#==============================================================================

{ my $svc=new Production::Services;

  sub getValidTSMVSummary ($$) {
      my ($tsmvid,$creator)=@_;

      my $desc=Production::Services::Ticket::getValidTSMVSummary(
          $svc,$tsmvid,$creator
      );
      error $svc->getError() unless $desc;

      return $desc;
  }

  sub populateTSMV ($$) {
      my ($tsmvid,$changeset)=@_;

      my $rc=Production::Services::Ticket::populateTSMV(
          $svc,$tsmvid,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  # not currently used as there is no 'rollback' plugin (yet)
  sub rollbackTSMV ($$) {
      my ($tsmvid,$changeset)=@_;

      my $rc=Production::Services::Ticket::rollbackTSMV(
          $svc,$tsmvid,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

}

#------------------------------------------------------------------------------

sub plugin_ismanual { return 0; } # this is an auto-loaded plugin

sub getSupportedTools($) {
    my ($plugin)=@_;
    my @tools = (CSCHECKIN_TOOL);
    return @tools;
}

#---

sub plugin_usage ($) {
    return "  --tsmv             <ticket>   associated TSMV ticket number"
}

sub plugin_options ($) {
    return qw[tsmv=i];
}

#---

sub plugin_initialize ($$) {
    my ($plugin,$opts)=@_;

    # TSMV uses the CS reference to store its ticket number
    if ($opts->{reference}) {
	fatal "--reference may not be used with TSMV tickets. Use --tsmv";
	return 0;
    }
    $opts->{Werror}=1; # Turn ON gcc -Wall option (treat warnings as errors) 

    return 1;
}

sub plugin_pre_find_filter ($$) {
    my ($plugin,$changeset)=@_;

    if (scalar($changeset->getFiles) > TSMV_FILELIMIT) {
	warning "There are more than ".TSMV_FILELIMIT.
	  " files in this changeset";
	warning "The TSMV screen will not show all the files";
    }

    return 1;
}

{ my $tsmv_ticket;

  sub plugin_early_interaction ($$$) {
      my ($plugin,$opts,$term)=@_;

      # gather any unspecified info required - TSMV ticket
      my $ticket=$opts->{tsmv};     
      my $desc="";
      my $ticknum="";
      my $ticktype="";

      if ($ticket) {
	  $desc=getValidTSMVSummary($ticket,USER);
	  unless ($desc) {
	      error("TSMV ticket $ticket was not found or is not valid");
	      exit EXIT_FAILURE;
	  }	
	  if ($desc =~ s/^(DRQS|TREQ):(\d+):// ) {
	      ($ticktype, $ticknum) = ($1, $2);
	  }	
      } elsif ($term->isInteractive) {
	  print "This change set is controlled by TSMV approval.\n";
	  print "Please enter an existing TSMV ticket number, e.g. '30615'.\n";
	  do {
	      $ticket=$term->promptForSingle("TSMV Ticket: ",q[^\d{5,}$]);
	      $desc=getValidTSMVSummary($ticket,USER);	    
	      unless ($desc) {
		  error("TSMV ticket $ticket was not found or is not valid");
		  exit EXIT_FAILURE;
	      }	

	      if ($desc =~ s/^(DRQS|TREQ):(\d+):// ) {
		  ($ticktype, $ticknum) = ($1, $2);
	      }	
	     
	      if ($desc) {
		  print "TSMV $ticket: $desc\n";
		  my $y=$term->promptForYN("Is this ".
					       "the correct ticket (y/n)? ");
		  $ticket=undef unless $y;
	      } else {
		  error("TSMV ticket $ticket is not valid");
		  exit EXIT_FAILURE;
	      }
	  } until ($ticket);
      } else {
	  error("No TSMV ticket supplied and not interactive");
	  exit EXIT_FAILURE;
      }

      $tsmv_ticket = "TSMV$ticket";
      $opts->{reference}{tsmv} = $ticket;

      if($ticknum && $ticktype){
	  if($opts->{treq} && $ticknum != $opts->{treq}) {
	      warning "Treq Number supplied in command line $opts->{treq} ".
		  "is different with TSMV -ignored"; 
	  }
	  
	  if($opts->{drqs} && $ticknum != $opts->{drqs}) {
	      warning "Drqs Number supplied in command line $opts->{drqs} ".
		  "is different with TSMV -ignored"; 
	  }

      	  if($ticktype eq 'TREQ') {      	   
	      $opts->{treq}=$ticknum;	    
	  } else {	    
	      $opts->{drqs}=$ticknum; 
	  }
      }

      if ($opts->{message}) {
	  $opts->{message}=$desc."\n".$opts->{message};
      } else {
	  $opts->{message}=$desc;
      }
}

  sub plugin_post_change_success ($$) {
      my ($plugin,$changeset)=@_;

      return populateTSMV($tsmv_ticket,$changeset);
  }
}

#==============================================================================

1;

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Change::Approve>, L<Production::Services::Ticket>

=cut
