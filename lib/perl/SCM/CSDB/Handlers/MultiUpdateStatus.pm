package SCM::CSDB::Handlers::MultiUpdateStatus;

use warnings;
use strict;

use POSIX qw();

use Production::Symbols qw/HEADER_ID HEADER_UPDATER HEADER_NEW_STATUS HEADER_CREATOR/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::Status;

sub handle_request {
    my $req = shift;

    warn "MultiUpdateStatus>>>>>\n";
    warn $req->as_string, "\n";

    my @csids       = $req->head(HEADER_ID); 
    my $newstatus   = $req->head(HEADER_NEW_STATUS); 

    my ($uuid, $unixname, $uuid_err);       
    if (not $uuid = $req->head(HEADER_UPDATER)) {
        # look at HEADER_CREATOR which contains the unixname
        require SCM::UUID;
        $unixname = $req->head(HEADER_CREATOR) || '';
        my $resolver = SCM::UUID->new;
        ($uuid_err, $uuid) = $resolver->unix2uuid($unixname);
    }

    # still no UUID?
    if (not defined $uuid) {
        write_response( -status => [ qw/450 Invalid Updater/ ],
                        -body   => "$unixname: Invalid updater\nerror: $uuid_err" );
        warn "<<<<<MultiUpdateStatus\n";
        return;
    }

    my $db = SCM::CSDB::Status->new(database => SCM_CSDB, 
                                    driver   => SCM_CSDB_DRIVER);

    my $cnt = $db->alterMultiChangeSetStatus(\@csids,
                                             uuid       => $uuid,
                                             newstatus  => $newstatus,);

    if (not defined $cnt) {
        write_response( -status => [ qw/550 Internal error/ ],
                        -body   => "Status update failed (csids maybe not in the database?)" );
        warn "<<<<<MultiUpdateStatus\n";
        return;
    }

    warn "count of affected CSIDs: $cnt\n";

    write_response( -status => [ qw/250 OK/ ],);

    warn "<<<<<MultiUpdateStatus\n";
}

1;
