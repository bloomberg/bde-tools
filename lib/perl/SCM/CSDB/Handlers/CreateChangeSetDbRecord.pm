package SCM::CSDB::Handlers::CreateChangeSetDbRecord;

use strict;
use warnings;

use Change::Set;
use Change::File;
use Change::Symbols     qw( MOVE_EMERGENCY  STATUS_SUBMITTED );
use Production::Symbols qw( /^HEADER_/ /^\$HEADER_/ );
use SCM::Symbols        qw( SCM_CSDB SCM_CSDB_DRIVER );

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::ChangeSet;

sub handle_request {
    my $req = shift;

    warn "CreateChangeSetDbRecord>>>>>\n";
    warn $req->as_string, "\n";

    my $csid        = $req->head(HEADER_ID);
    my $user        = $req->head(HEADER_CREATOR);
    my $user_uuid   = $req->head(HEADER_UPDATER);
    my $when        = $req->head(HEADER_CREATION_TIME);
    my $stage       = $req->head(HEADER_STAGE);
    my $move        = $req->head(HEADER_MOVE_TYPE);
    my $ticket      = $req->head(HEADER_TICKET);
    my $status      = $req->head(HEADER_STATUS) || STATUS_SUBMITTED;
    my $ref         = $req->head(HEADER_REFERENCE);
    my $branch      = $req->head(HEADER_BRANCH);

    # dependencies
    my %deps;
    for ($req->head(HEADER_DEPENDENCIES)) {
        my ($on, $type) = split;
        $deps{$on} = $type;
    }

    # files
    my @files = map Change::File->new($_), $req->head(HEADER_FILE);

    # emov properties
    my @test        = $req->head(HEADER_TESTER);
    my @test_uuid   = $req->head(HEADER_TESTER_UUID);
    my @appr        = $req->head(HEADER_APPROVER);
    my @appr_uuid   = $req->head(HEADER_APPROVER_UUID);
    my @task        = $req->head(HEADER_TASK);
    my @funcs       = $req->head(HEADER_FUNCTION);

    my %ref;
    for (split /,/, $ref || '') {
        my ($type, $val) = split /\|/;
        $ref{$type} = $val;
    }

    # add approver to references:
    # there can always only be one
    $ref{emapprover} = $appr_uuid[0];

    
    my $msg = $req->body;

    # create Change::Set object
    my $cs = Change::Set->new({
                csid        => $csid,   user    => $user,       when    => $when,
                stage       => $stage,  move    => $move,       ticket  => $ticket,
                message     => $msg,    status  => $status,     depends => \%deps,
                reference   => \%ref,   functions => \@funcs,   tasks   => \@task,
		testers     => \@test,   branch => $branch,
    });
    $cs->addFiles(@files);

    # create username to UUID mapping
    my %uuid;
    $uuid{$user} = $user_uuid;
    @uuid{@test} = @test_uuid;
    @uuid{@appr} = @appr_uuid;

    my $db = SCM::CSDB::ChangeSet->new(database => SCM_CSDB, 
                                       driver   => SCM_CSDB_DRIVER);
    my $count = $db->createChangeSetDbRecord($cs, \%uuid);

    warn "rows affected: $count\n";

    write_response(
            -status => [ qw/250 OK/ ],
    );

    warn "<<<<<CreateChangeSetDbRecord\n";
}

1;
