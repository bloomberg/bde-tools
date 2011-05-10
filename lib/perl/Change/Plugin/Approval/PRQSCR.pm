package Change::Plugin::Approval::PRQSCR;
use strict;

use base 'Change::Plugin::Base';

use Util::Message qw(message fatal warning error);
use Symbols qw(EXIT_FAILURE);
use Change::Symbols qw(USER CSCHECKIN_TOOL);

use Production::Services;
use Production::Services::ChangeSet;
use Production::Services::Move;
use Production::Symbols qw(HEADER_APPROVER);

#==============================================================================

=head1 NAME

Change::Plugin::Approval::PRQSCR - Plugin for PRQS CR approval

=head1 SYNOPSIS

  $ cscheckin -LApproval::PRQSCR --reviewer <user|uuid> ...

=head1 DESCRIPTION

This plugin implements PRCS CR integration within C<cscheckin>. It may be
manually loaded to enable use of the command line extensions, and is otherwise
automatically loaded  when the approval type for a change set is determined to
be C<prqscr>, as determined through the L<Change::Approve> module.

The following process alterations are made by this plugin:

=over 4

=item * If manually loaded, the C<--reviewer> command line option is enabled.
        This takes an unix login name or a UUID as its argument. (If the
        plugin is autoloaded on demand, the command line option will not
        available.)

=item * If the C<--reviewer> option is not used, it is prompted for
        interactively if in interactive mode, and the tool will abort if in
        non-interactive mode.

=back

The PRQSCR plugin is activated when an approval type of C<prqscr> is applicable
to a change set. It is an automatic plugin, and so does not need to be
manually loaded (i.e. with the C<--plugin> or C<-L> option of C<cscheckin>.)
However, the C<--reviewer> command-line options I<will not> be available unless
the plugin is explicitly requested. An attempt to load the plugin when
C<prqscr> approval is not applicable will cause C<cscheckin> to abort.

See L<"Change::Approve"> and the C<change.approve> configuration file for more
information.

=cut

#==============================================================================

{ my $svc=new Production::Services;

  sub createPrqsCodeReviewTicket ($$) {
      my ($changeset, $reviewer)=@_;

      my $rc=Production::Services::ChangeSet::createPrqsCodeReviewTicket(
          $svc, $changeset, $reviewer);
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub isValidReviewer ($) {
      my $approver=shift;
     
      my $rc=
	Production::Services::Move::isValidCodeReviewApprover($svc,$approver);
      error $svc->getError() unless $rc;

      return $rc;
  };
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
    return "  --reviewer          <reviewer> login or UUID of PRQS CR reviewer"
}

sub plugin_options ($) {
    return qw[reviewer=s];
}

#---

{ my $prqscr_reviewer;

  sub plugin_early_interaction ($$$) {
      my ($plugin,$opts,$term)=@_;

      # gather any unspecified info required - PRQS CR ticket
      my $reviewer=$opts->{reviewer};
      my $desc="";

      if ($reviewer) {
	  fatal "Invalid reviewer" unless isValidReviewer($reviewer);
      } elsif ($term->isInteractive) {
	  print "This change set is controlled by PRQS CR approval.\n";
	  print "Enter the login name or UUID for the reviewer.\n";
	  do {
	      $reviewer=$term->promptForSingle("Reviewer: ", q[^\w+$]);
	  } until (isValidReviewer $reviewer);
      } else {
	  error("No PRQS CR reviewer supplied and not interactive");
	  exit EXIT_FAILURE;
      }

      $prqscr_reviewer = $reviewer;
  }

  sub plugin_post_change_success($$$) {
      my ($plugin,$changeset)=@_;

      # create the ticket and note the ticket ID returned
      my $ticket=createPrqsCodeReviewTicket($changeset, $prqscr_reviewer);
      my $csid=$changeset->getID();
      if ($ticket) {
	  $plugin->logEvent($changeset->getID(),"PRQS $ticket (CR) created");
	  message "Created PRQS $ticket (CR) for change set $csid";
      } else {
	  $plugin->logEvent($changeset->getID(),"!! Failed to create PRQS CR");
	  error "Failed to created PRQS CR for change set $csid";
      }

      return $ticket; #a true value, or zero if creation failed.
  }
}

#==============================================================================

1;

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Change::Approve>, L<Production::Services::ChangeSet>

=cut
