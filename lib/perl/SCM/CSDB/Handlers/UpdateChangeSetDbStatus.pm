package SCM::CSDB::Handlers::UpdateChangeSetDbStatus;

use warnings;
use strict;


use POSIX qw();

use Production::Symbols qw/$HEADER_ID $HEADER_CREATOR 
                           $HEADER_NEW_STATUS $HEADER_UPDATER/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Status;
use SCM::CSDB::Handlers::Common qw/write_response/;

sub handle_request {
    my $req = shift;

    warn "GetChangeSetStatus>>>>>\n";
    warn $req->as_string, "\n";

    my $csid        = $req->head($HEADER_ID);
    my $uuid        = $req->head($HEADER_UPDATER);
    my $newstatus   = $req->head($HEADER_NEW_STATUS);

    my $db = SCM::CSDB::Status->new(database => SCM_CSDB, 
                                    driver   => SCM_CSDB_DRIVER);

    my $cnt = $db->alterChangeSetDbRecordStatus(
            $csid,
            uuid        => $uuid,
            newstatus   => $newstatus,
    );

    warn "count of affected CSIDs: $cnt\n";

    write_response( -status => [ qw/250 OK/ ],);

    warn "<<<<<GetChangeSetStatus\n";
}

1;
