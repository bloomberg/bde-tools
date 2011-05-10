package SCM::CSDB::Handlers::MultiUpdateStatusByStatus;

use warnings;
use strict;

use POSIX qw();

use Production::Symbols qw/$HEADER_STATUS $HEADER_UPDATER $HEADER_NEW_STATUS/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::Status;

sub handle_request {
    my $req = shift;

    warn "MultiUpdateStatusByStatus>>>>>\n";
    warn $req->as_string, "\n";

    my $oldstatus   = $req->head($HEADER_STATUS); 
    my $uuid        = $req->head($HEADER_UPDATER);
    my $newstatus   = $req->head($HEADER_NEW_STATUS);
    my @except      = split /\n/, $req->body;

    my $db = SCM::CSDB::Status->new(database => SCM_CSDB, 
                                    driver   => SCM_CSDB_DRIVER);

    my @csid = $db->alterMultiChangeSetStatusByStatus(
            oldstatus   => $oldstatus, 
            uuid        => $uuid,
            newstatus   => $newstatus,
            except      => \@except,
    );

    warn "count of affected rows: ", scalar @csid, "\n";

    write_response( -status => [ qw/250 OK/ ],
                    -body   => join "\n", @csid, );
    warn "<<<<<MultiUpdateStatusByStatus\n";
}

1;
