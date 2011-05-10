package SCM::CSDB::Handlers::CreateDependentCS;

use strict;
use warnings;

use Production::Symbols qw/HEADER_ID HEADER_ID_DEP/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::ChangeSet;

sub handle_request {
    my $req = shift;

    warn "CreateDependentCS>>>>>\n";
    warn $req->as_string, "\n";

    my $csid        = $req->head(HEADER_ID);
    my ($on, $type) = split / /, $req->head(HEADER_ID_DEP);

    my $db = SCM::CSDB::ChangeSet->new(database => SCM_CSDB, 
                                       driver   => SCM_CSDB_DRIVER);

    my $count = $db->addDependencyToChangeSet($csid, $on, $type);

    warn "rows affected: $count\n";

    write_response(
            -status => [ qw/250 OK/ ],
    );

    warn "<<<<<CreateDependentCS\n";
}

1;
