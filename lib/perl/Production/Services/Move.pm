package Production::Services::Move;
use strict;

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(
   isBetaDay
   isValidApprover
   isValidEmergencyApprover
   isValidImmediateApprover
   isValidProgressApprover
   isValidTester
   getLockdownStatus
   getEmoveLinkType
);

use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;

use Change::Set;

use Change::Symbols qw(
    STAGE_PREALPHA STATUS_ACTIVE MOVE_REGULAR USER
);
use Production::Symbols qw(
    PRQS_TYPE_EMERGENCY PRQS_TYPE_IMMEDIATE PRQS_TYPE_CODEREVIEW 
    PRQS_TYPE_PROGRESS

    HEADER_APPROVER
    HEADER_CREATION_TIME
    HEADER_CREATOR
    HEADER_FILE
    HEADER_FUNCTION
    HEADER_ID
    HEADER_MOVE_TYPE
    HEADER_STAGE
    HEADER_STATUS
    HEADER_TASK
    HEADER_LIBRARY
    HEADER_TESTER
    HEADER_TICKET
    HEADER_PRQS_TYPE
    $SCM_HOST
    HTTP_METHOD

    $BAS_IS_BETA_DAY
    $BAS_IS_VALID_APPROVER
    $BAS_ARE_VALID_TESTERS
    $BAS_GET_LOCK_DOWN_STATUS
    $BAS_GET_EMOVE_LINK_TYPE
);

#==============================================================================

=head1 NAME

Production::Services::Move - Access to release cycle production services from development

=head1 SYNOPSIS

    use Production::Services;
    use Production::Services::Move qw(isBetaDay isValidApprover
                                      isValidTester getLockdownStatus);

    my $svc=new Production::Services;

    my $isbeta = isBetaDay($svc, @tasks [, @libraries]);
    my $canapprove = isValidApprover($svc, $user);
    my $cantest = isValidTester($svc, $user);
    my $lockdownStatus = getLockdownStatus($svc);

=head1 DESCRIPTION

C<Production::Services::Move> provides routines to query production systems
for information releated to the production release cycle.


=cut

#==============================================================================

=head1 ROUTINES

The following routines are available for export:

=head2 isBetaDay($svc, @tasks [,@libraries])

Given a L<"Production::Services"> object, an array of tasks and an (optional)
array of list of libraries, C<isBetaDay> returns 1 if it is a beta day, 0 if
it is not a beta day, and C<undef> if an error occured.

Note that the tasks and libraries arguments must be arrays; lists or array
references are not valid.

=cut

sub isBetaDay($\@;\@) {
    my ($svc, $tasks, $libs) = @_;
    $tasks ||= [];
    $libs  ||= [];

    # Dummy out unused headers related to change set
    my $headers = HTTP::Headers->new(HEADER_CREATOR,
                                     USER,
                                     HEADER_CREATION_TIME,
                                     scalar localtime);

    for my $task (@$tasks) {
        $headers->push_header(HEADER_TASK, $task);
    }

    for my $lib (@$libs) {
        # Dummy: create a change set file header for each library
        my $filestr = "library=$lib:target=$lib:from=.:to=.:type=CHANGED";
        $headers->push_header(HEADER_FILE, $filestr);
    }

    my $request = HTTP::Request->new(HTTP_METHOD,
                                     "$SCM_HOST/$BAS_IS_BETA_DAY",
                                     $headers, "dummy\n");
    $request->protocol("HTTP/1.1");

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if (!$response->is_success) {
        $svc->setError("Error getting beta day status: " . $response->content);
        return undef;
    }

    my ($is_beta_day) = $response->content =~ /^(no|yes)/;
    if (!defined $is_beta_day) {
        $svc->setError("Error getting beta day status: invalid response");
        return undef;
    }

    return ($is_beta_day eq "no" ? 0 : 1);
}

=head2 getEmoveLinkType($svc, $stage, @tasks, @libraries)

Given a L<"Production::Services"> object. a stage, an array of tasks and an
array of libraries, C<getEmoveLinktype> returns either 'stage' or 'source' to
indicate which libraries an emove should be linked against, or C<undef> if an
error occurs.

=cut

sub getEmoveLinkType($$\@\@) {
    my ($svc, $stage, $tasks, $libs) = @_;
    $tasks ||= [];
    $libs  ||= [];

    my $headers = HTTP::Headers->new();

    for my $task (@$tasks) {
        $headers->push_header(HEADER_TASK, $task);
    }

    for my $lib (@$libs) {
        $headers->push_header(HEADER_LIBRARY, $lib);
    }

    $headers->push_header(HEADER_STAGE, $stage);

    my $request = HTTP::Request->new(HTTP_METHOD,
                                     "$SCM_HOST/$BAS_GET_EMOVE_LINK_TYPE",
                                     $headers, "dummy\n");
    $request->protocol("HTTP/1.1");

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if (!$response->is_success) {
        $svc->setError("Error getting link type: " . $response->content);
        return undef;
    }

    my ($link_type) = $response->content =~ /(Stage|Source)/i;

    if (!defined $link_type) {
        $svc->setError("Error getting link type: invalid response");
        return undef;
    }

    return (lc $link_type eq "stage" ? 'stage' : 'source');
}

=head2 isValidApprover($svc, $approver [,$type])

Given a L<"Production::Services"> object and a user ID (either a
UUID or a Unix login name), return true of the user is a valid
approver, or false otherwise.  Return undef if an error is returned
from the bas service or if there is a communication failure.

The type should be a valid PRQS ticket type symbol such as
C<PRQS_TYPE_EMERGENCY> or C<PRQS_TYPE_IMMEDIATE>. Alternatively,
use one of the convenience routines below. If no type is supplied,
C<PRQS_TYPE_EMERGENCY> is assumed.

=head2 isValidEmergencyApprover($svc, $approver)

Return true of the user is a valid approver of PRQS EM/LK tickets.

=head2 isValidImmediateApprover($svc, $approver)

Return true if the user is a valid approver of PRQS ST tickets.

=head2 isValidCodeReviewApprover($svc, $approver)

Return true of the user is a valid approver of PRQS CR tickets.

=cut

sub isValidApprover ($$;$) {
    my ($svc, $approver, $type) = @_;
    $type ||= PRQS_TYPE_EMERGENCY;

    my $headers = HTTP::Headers->new(HEADER_CREATOR,   USER,
                                     HEADER_APPROVER,  $approver,
                                     HEADER_PRQS_TYPE, $type);

    my $request = HTTP::Request->new(HTTP_METHOD,
                                     "$SCM_HOST/$BAS_IS_VALID_APPROVER",
                                     $headers, "dummy\n");
    $request->protocol("HTTP/1.1");

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if (!$response->is_success) {
        $svc->setError("Error validating approver: " . $response->content);
        return undef;
    }

    my ($is_valid) = $response->content =~ /^(no|yes)/;
    if (!defined $is_valid) {
        $svc->setError("Error validating approver: invalid response");
        return undef;
    }

    return ($is_valid eq "no" ? 0 : 1);
}

sub isValidEmergencyApprover ($$) {
    return isValidApprover($_[0], $_[1], PRQS_TYPE_EMERGENCY);
}

sub isValidImmediateApprover ($$) {
    return isValidApprover($_[0], $_[1], PRQS_TYPE_IMMEDIATE);
}

sub isValidProgressApprover ($$) {
    return isValidApprover($_[0], $_[1], PRQS_TYPE_PROGRESS);
}

sub isValidCodeReviewApprover ($$) {
    return isValidApprover($_[0], $_[1], PRQS_TYPE_CODEREVIEW);
}

=head2 isValidTester($svc, $tester)

Given a L<"Production::Services"> object and a user ID (either a
UUID or a Unix login name), return true of the user is a valid
tester, or false otherwise.  Return undef if an error is returned
from the bas service or if there is a communication failure.

=cut

sub isValidTester ($$) {
    my ($svc, $tester) = @_;

    my $headers = HTTP::Headers->new(HEADER_CREATOR,   USER,
                                     HEADER_TESTER,    $tester,
                                     HEADER_PRQS_TYPE, PRQS_TYPE_EMERGENCY);

    my $request = HTTP::Request->new(HTTP_METHOD,
                                     "$SCM_HOST/$BAS_ARE_VALID_TESTERS",
                                     $headers, "dummy\n");

    $request->protocol("HTTP/1.1");

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if (!$response->is_success) {
        $svc->setError("Error validating tester: " . $response->content);
        return undef;
    }

    my ($is_valid) = $response->content =~ /^(no|yes)/;
    if (!defined $is_valid) {
        $svc->setError("Error validating tester: invalid response");
        return undef;
    }

    return ($is_valid eq "no" ? 0 : 1);
}

=head2 getLockdownStatus($svc)

Given a L<"Production::Services"> object, return 0 (i.e. false) if
the development true is not in a lockdown state, "full" if a full
lockdown is in effect, and "beta" if a beta lockdown is in effect.
Note that a true return value indicates that checkins are NOT
allowed at the current time.  Return undef if an error is returned
from the bas service or if there is a communication failure.

=cut

sub getLockdownStatus ($) {
    my ($svc) = @_;

    my $request = HTTP::Request->new(HTTP_METHOD,
                                     "$SCM_HOST/$BAS_GET_LOCK_DOWN_STATUS");
    $request->protocol("HTTP/1.1");

    $svc->sendRequest($request);
    my $response = $svc->readResponse;

    if (!$response->is_success) {
        $svc->setError("Error getting lockdown status: " . $response->content);
        return undef;
    }

    my ($state) = $response->content =~ m/^(off|full|beta)/;

    if (!defined $state) {
        $svc->setError("Error getting lockdown status: invalid response");
        return undef;
    }

    # $1 will be undef if response is not one of "off", "full", or "beta"
    return ($state eq "off" ? 0 : $state);
}

#==============================================================================

=head1 AUTHOR

Pablo Halpern (phalpern@bloomberg.net)

=head1 SEE ALSO

L<Production::Services>, L<Production::Services::ChangeSet>

=cut

1;
