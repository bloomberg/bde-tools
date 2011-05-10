# vim:set ts=8 sts=4 sw=4 noet:

package SCM::Request;

use warnings;
use strict;

use HTTP::Request;
use HTTP::Headers;
use LWP::UserAgent;
use Production::Services::LWPHack;

use Production::Symbols     qw/$SCM_HOST $SCM_GET_UUID_BY_UNIX_LOGIN
                               $SCM_ADD_DEPENDENCY
                               $HEADER_CREATOR $HEADER_ID $HEADER_ID_DEP/;
use Change::Symbols         qw/$DEPENDENCY_TYPE_NONE $DEPENDENCY_TYPE_ROLLBACK
                               $DEPENDENCY_TYPE_CONTINGENT $DEPENDENCY_TYPE_DEPENDENT/;
use Util::Message           qw/error/;

use constant DUMMY => 'DUMMY';

sub unix_name_to_uuid {
    my ($class, $login) = @_;

    if (not defined $login) {
        error "Unix login name needs to be defined";
        return;
    }

    my $header = HTTP::Headers->new(
            $HEADER_CREATOR => $login,
    );

    $header->header('Content-Length' => length DUMMY);

    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_GET_UUID_BY_UNIX_LOGIN", 
            $header, DUMMY);

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    (my $content = $response->content) =~ s/\s+$//;
    return (0, $content) if $response->code != 250;

    return $content;
}

my %DEP2STRING = (
    $DEPENDENCY_TYPE_NONE       => 'NONE',
    $DEPENDENCY_TYPE_ROLLBACK   => 'ROLLBACK',
    $DEPENDENCY_TYPE_CONTINGENT => 'CONTINGENT',
    $DEPENDENCY_TYPE_DEPENDENT  => 'DEPENDENT',
);

sub add_dependency_to_cs {
    my ($class, $csid, $depends_on, $type) = @_;

    my $depstring = $DEP2STRING{ $type }
        or do {
            error "$type: Invalid dependency type";
            return;
        };

    my $header = HTTP::Headers->new(
            $HEADER_ID          => $csid,
            $HEADER_ID_DEP      => "$depends_on $depstring",
            'Content-Length'    => length DUMMY,
    );

    my $req = HTTP::Request->new(
                POST => "$SCM_HOST/$SCM_ADD_DEPENDENCY",
                $header, DUMMY);

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return 1 if $response->code == 250;

    return (0, $response->content);
}

1;

__END__

=head1 NAME

SCM::Request - Make non-csdb related requests.

=head1 SYNOPSIS

    use Util::Message qw/error/;
    use SCM::Request;
    my ($uuid, $error) = SCM::Request->unix_name_to_uuid('tvon');

    if ($error) {
        error "Problem with request: $error";
    }

    print "Login name 'tvon' translated to $uuid";

=head1 DESCRIPTION

This module should be used to make requests that are not CSDB related and therefore
go through BAS.

=head1 METHODS

=head2 unix_name_to_uuid($login)

Translates the Unix name I<$login> to a Bloomberg UUID.

Returns a two-element list in case of an error in which case the second element is the error
that occured. Otherwise, returns the UUID.

=head2 add_dependency_to_cs($csid, $depends_on, $type)

Adds the dependency of type I<$type> on change set I<$depends_on> to the change
set with ID I<$csid>.

Returns a two-element list in case of an error in whihc case the second element is the error 
that occured. Otherwise, returns a true value.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
