package SCM::CSDB::Handlers::GetChangeSetHistory;

use strict;
use warnings;

use Production::Symbols qw/HEADER_ID $HEADER_HISTORY/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::History;

sub handle_request {
    my $req = shift;

    warn "GetChangeSetHistory>>>>>\n";
    warn $req->as_string, "\n";

    my $db = SCM::CSDB::History->new(database => SCM_CSDB, 
                                     driver   => SCM_CSDB_DRIVER);

    my $history = $db->getChangeSetHistory($req->head(HEADER_ID), 0);
    warn "got row-count: ", scalar @$history, "\n";

    my (@header, $n);
    for (@$history) {
        push @header, "$HEADER_HISTORY-" . $n++, join '#',  @$_;
    }

    write_response(
            -status => [ qw/250 OK/ ],
            -header => { @header },
    );
    warn "<<<<<GetChangeSetHistory\n";
}

1;
