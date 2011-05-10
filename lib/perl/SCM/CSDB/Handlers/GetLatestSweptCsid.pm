package SCM::CSDB::Handlers::GetLatestSweptCsid;

use warnings;
use strict;

use Production::Symbols qw/HEADER_FILE/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::FileHistory;

sub handle_request {
    my $req = shift;

    warn "GetLatestSweptCsid>>>>>\n";
    warn $req->as_string, "\n";

    my $file   = $req->head(HEADER_FILE);
    my $db = SCM::CSDB::FileHistory->new(database => SCM_CSDB,
					 driver   => SCM_CSDB_DRIVER);

    my $rec = $db->getLatestSweptCsid($file);

    my (@status, $body);

    if(not defined $rec) {
        @status = (450, 'Not found');
        $body   = "No csid found for $file";
    } else {
        @status = qw/250 OK/;
        $body   = join ' ' => @{ $rec }{qw/creator movetype csid/};
    }

    write_response(
            -status => \@status,
            -body   => $body,
    );
    warn "<<<<<GetLatestSweptCsid\n";
}

1;
