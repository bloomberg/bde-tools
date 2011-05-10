package SCM::CSDB::Handlers::GetChangeSetStatus;

use strict;
use warnings;

use Production::Symbols qw/$HEADER_ID $HEADER_STATUS/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::Status;

sub handle_request {
    my $req = shift;

    warn "GetChangeSetStatus>>>>>\n";
    warn $req->as_string, "\n";

    my $db = SCM::CSDB::Status->new(database => SCM_CSDB, 
                                    driver   => SCM_CSDB_DRIVER);

    my $status = $db->getChangeSetStatus($req->head($HEADER_ID));
    warn "status: $status\n";

    write_response(
            -status => [ qw/250 OK/ ],
            -header => { $HEADER_STATUS => $status, },
    );
    warn "<<<<<GetChangeSetStatus\n";
}

1;
