package Production::Services::Ticket;

use strict;

use base qw/Exporter/;
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(
    addTicketLog
    getValidTSMVSummary
    populateTSMV
    rollbackTSMV
    isValidTicket
    getPrqsStatus
    updatePrqsStatus
    attach_csid_to_bbmv
    bbmv_is_mandatory
    is_valid_bbmv
);


use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use LWP::UserAgent;

use Change::Symbols	qw/USER/;
use Production::Symbols qw/HEADER_CREATOR	HEADER_ID	HEADER_MOVE_TYPE
			   HEADER_STATUS	HEADER_TICKET	HEADER_PRQS_NUMBER
			   HEADER_PRQS_STATUS	HEADER_PRQS_UPDATER
			   SCM_HOST   
			   HTTP_METHOD HTTP_VERSION
			   BAS_ADD_TICKET_NOTE		BAS_IS_VALID_TICKET
			   BAS_GET_VALID_TSMV_SUMMARY	BAS_POPULATE_TSMV
			   BAS_ROLLBACK_TSMV		BAS_UPDATE_PRQS_STATUS
			   BAS_GET_PRQS_STATUS		BAS_ATTACH_CSID_TO_BBMV
			   BAS_IS_ENABLED_FOR_BBMV	BAS_IS_VALID_BBMV_TICKET/;

#==============================================================================

=head1 NAME

Production::Services::Ticket - Access to ticketing production services from
development

=head1 SYNOPSIS

    use Production::Services;
    use Production::Services::Ticket qw(
        getValidTSMVSummary populateTSMV rollbackTSMV
    );

    my $svc=new Production::Services;

    my $summary = getValidTSMVSummary($svc, $tsmvId, $creator);
    populateTSMV($svc, $tsmvId, $changeset)

    # All of the above functions set the error status
    print "Status = ", $svc->getError || "SUCCESS";

=head1 DESCRIPTION

C<Production::Ticket> provides a set of global functions for accessing
production-side ticket manipulation services from development-side Perl
scripts.

=cut

#==============================================================================
#get prqs ticket status
sub getPrqsStatus($) {
    my $prqs_number=shift;
    
    my $headers = HTTP::Headers->new(HEADER_PRQS_NUMBER, $prqs_number);
    my $request = HTTP::Request->new(HTTP_METHOD, 
				     SCM_HOST."/".BAS_GET_PRQS_STATUS,
				     $headers);
    $request->protocol(HTTP_VERSION);

    my $agent = LWP::UserAgent->new;
    my $response = $agent->request($request);
    if($response->code == 250) {
	my ($status, $type) = split /\s+/, $response->content;
	return ([$status, $type]);
    }else {
	return (0, $response->content);
    }
}

#==============================================================================
#update prqs ticket status
sub updatePrqsStatus($$$) {
    my ($prqs, $status, $user)=@_;
    my $headers = HTTP::Headers->new(HEADER_PRQS_NUMBER, $prqs,
				     HEADER_PRQS_STATUS, $status,
				     HEADER_PRQS_UPDATER, $user);
    my $request = HTTP::Request->new(HTTP_METHOD, 
				  SCM_HOST."/".BAS_UPDATE_PRQS_STATUS,
				  $headers);

    $request->protocol(HTTP_VERSION);
    my $agent = LWP::UserAgent->new;

    my $response = $agent->request($request);
    if($response->code != 250) {
	return (0, $response->content);
    }
    
    return 1;
}
#==============================================================================

# Normalize TSMV ticket ID (generally by prepending the string "TSMV").
sub normalizeTSMVId($) {
    my ($ticket) = @_;
    $ticket =~ s/^TSMV//i;
    return "TSMV".$ticket;
}

#=============================================================================

=head2 addTicketLog($svc, $ticketType, $ticketNum, $note)

Add the specified C<$note> string to the log of the specified
ticket.  The C<$note> string may contain embedded newlines.

I<Not currently implemented.>

=cut

#=============================================================================

sub addTicketLog($$$$$) {
    my ($svc, $csid, $ticket,$creator, $note) = @_;

    my $headers = HTTP::Headers->new(HEADER_CREATOR, $creator,
				     HEADER_ID,      $csid,
                                     HEADER_TICKET,  $ticket);
    my $request;   
    $request = HTTP::Request->new(HTTP_METHOD,
				  SCM_HOST . "/".BAS_ADD_TICKET_NOTE,
				  $headers, $note);   

    $request->protocol(HTTP_VERSION);  
    $svc->sendRequest($request);
    my $response = $svc->readResponse;
  
    if ($response->is_success) {
	return 1;
    } else {
	$svc->setError($response->content || "<Error adding Ticket Note>");
	return undef;
    }
 
}


#=============================================================================
=header2 isValidTicket($svc, $ticketid)
Check if a given ticket(DRQS, TREQ) is a valid ticket
=cut
#=============================================================================
sub isValidTicket($$)
{    
    my($svc,$ticket)=@_;

    my $headers = HTTP::Headers->new(HEADER_TICKET,    $ticket);

    my $request;
    $request = HTTP::Request->new(HTTP_METHOD, SCM_HOST.
				  "/".BAS_IS_VALID_TICKET,
				  $headers, "");

    $request->protocol(HTTP_VERSION);

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if ($response->is_success && $response->content =~ "yes") {
        return 1;
    } else {
        $svc->setError("Error invalid ticket");
        return undef;
    }
}

#=============================================================================

=head2 getValidTSMVSummary($svc, $tsmvId, $creator)

If C<$tsmvId> and C<$creator> refer to a valid TSMV ticket, then
returns the ticket's summary field.  Otherwise returns an empty
string and sets the eror string.  The return value may contain
embedded newlines.  If a communication error occurs, returns undef
and sets the error string in the $svc object.

=cut

#============================================================================='

sub getValidTSMVSummary($$$) {
    my ($svc, $tsmvId, $creator) = @_;
    $tsmvId = normalizeTSMVId($tsmvId);

    my $headers = HTTP::Headers->new(HEADER_CREATOR,   $creator,
				     HEADER_TICKET,    $tsmvId);

    my $request;
    $request = HTTP::Request->new(HTTP_METHOD, SCM_HOST.
				  "/".BAS_GET_VALID_TSMV_SUMMARY,
				  $headers, "");	
    $request->protocol(HTTP_VERSION);

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if ($response->is_success) {
        return $response->content;
    } else {
        $svc->setError("Error validating TSMV: ".$response->content);
        return undef;
    }
}

#=============================================================================

=head2 populateTSMV($svc, $tsmvId, $changeset)

Poplulate the ticket specified by the C<$tsmvId> with the
C<$changeset>, which may be specified by a hex ID number or by a
C<Change::Set> object reference.  Returns true on success and false
on failure.  After a failure, the caller can read an error message
from using C<$svc->getError>.

=cut

#=============================================================================

sub populateTSMV($$$) {
    my ($svc, $tsmvId, $cs) = @_;
    $tsmvId = normalizeTSMVId($tsmvId);

    my $csid = (ref $cs ? $cs->getID : $cs);
    my $creator;
    $creator = $cs->getUser if ref $cs;

    my $headers = HTTP::Headers->new(HEADER_TICKET,    $tsmvId,			 
                                     HEADER_ID,        $csid);
    $headers->push_header(HEADER_CREATOR, $creator) if defined $creator;

    my $request;
    $request = HTTP::Request->new(HTTP_METHOD,
				  SCM_HOST."/".BAS_POPULATE_TSMV,
				  $headers, "");   
    $request->protocol(HTTP_VERSION);
    
    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if ($response->is_success) {
        return 1;
    } else {
        $svc->setError("Error populating TSMV: ".
		       ($response->content || "<unknown error>"));

        return undef;
    }

    return 1;
}

#=============================================================================

=head2 rollbackTSMV($svc, $tsmvId, $changeset)

Rollback the ticket specified by the C<$tsmvId> that is associated with the
C<$changeset>, which may be specified by a hex ID number or by a
C<Change::Set> object reference.  Returns true on success and false
on failure.  After a failure, the caller can read an error message
from using C<$svc->getError>.

=cut

#=============================================================================

sub rollbackTSMV($$$) {
    my ($svc, $tsmvId, $cs) = @_;
    $tsmvId = normalizeTSMVId($tsmvId);

    my $csid = (ref $cs ? $cs->getID : $cs);
    my $creator;
    $creator = $cs->getUser if ref $cs;

    my $headers = HTTP::Headers->new(HEADER_TICKET,    $tsmvId,
                                     HEADER_ID,        $csid);
    $headers->push_header(HEADER_CREATOR, $creator) if defined $creator;

    my $request;
    $request = HTTP::Request->new(HTTP_METHOD,
				  SCM_HOST."/".BAS_ROLLBACK_TSMV,
				  $headers, "");
    $request->protocol(HTTP_VERSION);

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if ($response->is_success) {
	return 1;
    } else {
	$svc->setError("Error rolling back TSMV: ".
		       ($response->content || "<unknown error>"));
	return undef;
    }

    return 1;
}

#==============================================================================

=head2 attach_csid_to_bbmv($bbmv, $changeset, [$uuid])

Attach I<$changeset> (which optionally is just a CSID) with the BBMV ticket
number I<$bbmv>. The optional third argument I<$uuid> is the UUID of the
programmer. If not set, it uses the creator of I<$changeset>. If this happens
to be a CSID, it uses the current username.

Returns a two element list, the first element being a true value when
successful or false when not. In this case, the second element contains the
error as string.

=cut

sub attach_csid_to_bbmv {
    my ($bbmv, $cs, $uuid) = @_;

    my ($csid, $user); 
    
    if (UNIVERSAL::isa($cs, 'Change::Set')) {
	$csid = $cs->getID;
	$user = $cs->getUser;
    } else {
	$csid = $cs;
	$user = defined $uuid ? $uuid : USER;
    }

    my $headers = HTTP::Headers->new(&HEADER_ID	    => $csid,
				     &HEADER_TICKET => $bbmv,
				     &HEADER_CREATOR=> $user);
    my $req = HTTP::Request->new(HTTP_METHOD, 
				 join('/' => SCM_HOST, BAS_ATTACH_CSID_TO_BBMV),
				 $headers);
    $req->protocol(HTTP_VERSION);

    my $agent = LWP::UserAgent->new;
    my $response = $agent->request($req);

    if ($response->code == 250) {
	return 1;
    } else {
	return 0, $response->content || "<unknown error>";
    }
}

#==============================================================================

=head2 bbmv_is_mandatory($user)

Returns a two-element list with the first element being true when I<$user>
which is either a UNIX username or the UUID is enabled for BBMV. The first
element is 0 when the user is not enabled.

Returns undef as first element when there was an error in which case the
second element contains the error as string.

=cut

sub bbmv_is_mandatory {
    my $user = shift;

    my $headers = HTTP::Headers->new(&HEADER_CREATOR=> $user);
    my $req = HTTP::Request->new(HTTP_METHOD, 
				 join('/' => SCM_HOST, BAS_IS_ENABLED_FOR_BBMV),
				 $headers);
    $req->protocol(HTTP_VERSION);

    my $agent = LWP::UserAgent->new;
    my $response = $agent->request($req);

    if ($response->code == 250) {
	return 1 if $response->content =~ /yes/;
	return 0;
    } else {
	return undef, $response->content || "<unknown error>";
    }
}

#==============================================================================

=head2 is_valid_bbmv($bbmv, $user)

Returns a two-element list with the first element being true when I<$bbmv>
is a valid ticket for I<$user> which is either a UNIX username or the UUID.
The first element is 0 when it's not valid.

Returns undef as first element when there was an error in which case the
second element contains the error as string.

=cut

sub is_valid_bbmv {
    my ($bbmv, $user) = @_;

    my $headers = HTTP::Headers->new(&HEADER_CREATOR => $user,
				     &HEADER_TICKET  => $bbmv);
    my $req = HTTP::Request->new(HTTP_METHOD, 
				 join('/' => SCM_HOST, BAS_IS_VALID_BBMV_TICKET),
				 $headers);
    $req->protocol(HTTP_VERSION);

    my $agent = LWP::UserAgent->new;
    my $response = $agent->request($req);

    if ($response->code == 250) {
	return 1 if $response->content =~ /yes/;
	return 0;
    } else {
	return undef, $response->content || "<unknown error>";
    }
}

1;

=head1 AUTHOR

Pablo Halpern (phalpern@bloomberg.net)

=head1 SEE ALSO

L<Production::Services>, L<Change::Plugin::Approval::TSMV>

=cut
