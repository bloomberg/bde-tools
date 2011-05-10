package Production::Services;
use strict;

use base 'BDE::Object';

use IO::Handle;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use File::stat;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use Production::Services::LWPHack;

use Change::Symbols qw(USER CS_DATA);
use Production::Symbols qw(HOST HOST_LIST HOST_NUMS
                           DEFAULT_SVC_TIMEOUT HTTP_METHOD HTTP_VERSION
			   PROTOCOL SCM_PORT HEADER_HOST
			   SCM_HOST);

use Util::Message qw(debug debug2 debug3 verbose2 verbose3 warning error
                     log_input log_output get_verbose);

#==============================================================================

=head1 NAME

Remote::Production - HTTP access to production services from development

=head1 SYNOPSIS

    using HTTP::Request;
    using Production::Services;
    my $request = HTTP::Request->new(...);

    my $prodSvc = Production::Services->new( [$host] );

    $prodSvc->sendRequest($request);

    my $response = $prodSvc->readResponse( [$timeout] );

    $protSvc->setError("Some error");
    my $error = $prodSvc->getError;

=head1 DESCRIPTION

This module provids the core services needed to talk to the bas server on
a production server. Communication is carried out via HTTP requests and
responses.

=head2 NOTES

This implementation permits only one registered production host. The user
should therefore ensure the production host is available before construcing
an instance to talk to it. Future implementations may permit multiple hosts.

This module is not yet fully documented.

=cut

#==============================================================================
sub trace {
    my ($self, $message) = @_;

    chomp $message;
    # Don't use verbose_debug because it only requires verbose>=1 and debug>=1
    debug3("Calling ".$message) if (get_verbose() > 2);
}

#==============================================================================

=head1 CONSTRUCTOR

=head2 new([$host])

Create a new C<Production::Services> instance

=cut

    my $response;

sub new ($) {
    my ($class)=@_;

    return $class->SUPER::new();
}

sub fromString ($) {
    my ($self) = @_;
  
    $self->{error} = undef;
    $self->{timeout} = DEFAULT_SVC_TIMEOUT;

    return $self;
}

#------------------------------------------------------------------------------
=head2 sendRequest($request)

Send the specified request, specified as a L<"HTTP::Request"> instance, on the
specified channel. An exception is thrown if the request cannot be written.

=cut

# Cannot use LWP to send request because there is no way to make LWP use our
# channel instead of opening its own.
sub sendRequest($$;$) {
    my ($self, $request, $timeout) = @_;
    $self->trace("sendRequest(...)");

    $self->setError(undef);
    $request->content_length(length $request->content);
    $request->protocol(HTTP_VERSION);
    
    my $ua = LWP::UserAgent->new;
    if(defined $timeout) {
	$ua->timeout($timeout);
    }
    debug("sendRequest ".$request->as_string());
    $response = $ua->request($request);      
    
  }

=head2 readResponse( [$timeout] )

Read a response from the channel (after using L<"sendRequest"> above).

=cut

# Cannot use LWP to read and parse response because there is no way to make
# LWP use our channel instead of opening its own.
sub readResponse($;$) {
    my ($self, $timeout) = @_;
    $self->trace("readResponse");
      
    debug("sendRequest ".$response->as_string());
    return $response;    
 
  }

#---

=head2 getError()

Return the error message logged for the last transaction.

=head2 setError ($errormsg)

Set (override, or reset) the error message for the last
transaction. Note that each call to L<"sendRequest"> or
C<"readResponse"> will set the error value to C<undef> on entry, so
it is usually uneccessary to invoke this method externaly.

=cut

sub setError($;$) { $_[0]->{error} = $_[1]; }
sub getError($)   { return $_[0]->{error};  }

#==============================================================================

=head1 AUTHOR

Ellen Chen (qchen1@bloomberg.net)

=head1 SEE ALSO

L<Production::Services::Move>, L<Production::Services::ChangeSet>

=cut

1;

