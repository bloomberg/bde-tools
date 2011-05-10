# This tests both SCM::CSDB::Status as well as SCM::CSDB::History

use strict;
use warnings;

use FindBin;
use Test::More;

use Change::Symbols qw(USER /^STATUS_/);
use SCM::Symbols    qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::UUID;
use SCM::CSDB::ChangeSet;
use SCM::CSDB::Status;
use Change::Set;

our $TESTS;

my @DB = (database => SCM_CSDB, driver => SCM_CSDB_DRIVER);
my @STATUS; 

BEGIN {
    @STATUS = (STATUS_WAITING, STATUS_ACTIVE, STATUS_INPROGRESS, 
               STATUS_COMPLETE, STATUS_ROLLEDBACK, STATUS_REINSTATED);
}


my ($cs) = load_cs();
my ($csid, $err) = create_in_db($cs); Change::Set->generateChangeSetID;
die "Could not create change set in database: $err"
    if not $csid;
my $uuid = user2uuid();

my $db = SCM::CSDB::Status->new(@DB);

# ------------------------- 
# Test basic status changes
# -------------------------
BEGIN { $TESTS += @STATUS * 2 }
for my $status (@STATUS) {
    ok($db->alterChangeSetDbRecordStatus($csid, newstatus => $status,
                                                uuid      => $uuid), 
       "altering $csid to status $status (uuid=$uuid)");
    ok($db->getChangeSetStatus($csid) eq $status, 
       "checking status($csid) == $status");
}

# -------------------
# Test status history
# -------------------
BEGIN { $TESTS += (@STATUS+1) * 3 }
my $hdb = SCM::CSDB::History->new(@DB);
my $hist = $hdb->getChangeSetHistory($csid, 'resolve');
unshift @STATUS, STATUS_SUBMITTED;
for (0 .. $#STATUS) {
    ok($hist->[$_][1] eq $STATUS[$_], 
       "status for item $_ in history for $csid is $STATUS[$_]");
    ok($hist->[$_][2] == $uuid,
       "uuid for item $_ in history for $csid is $uuid");
    ok($hist->[$_][3] eq USER,
       "resolved user for item $_ in history for $csid is " . USER);
}

# ----------------------------------------
# Changing to undef status should be fatal
# ----------------------------------------
BEGIN { $TESTS += 1 }
eval {
    $db->alterChangeSetDbRecordStatus($csid, newstatus => undef, uuid => $uuid)
};
ok($@ =~ /^'newstatus' param missing or undef/, "Undefined newstatus disallowed");

sub create_in_db {
    my $cs = shift;
    my $csid = Change::Set->generateChangeSetID;
    $cs->setID($csid);
    $cs->setStatus(STATUS_SUBMITTED);

    my $csdb = SCM::CSDB::ChangeSet->new(@DB);
    eval {
        $csdb->createChangeSetDbRecord($cs)
    } or return (0, $@);

    return $csid;
}

sub user2uuid {
    my $res = SCM::UUID->new;
    my ($err, $uuid) = $res->unix2uuid(USER);
    return 0 if $err;
    return $uuid;
}

{
    my @cs;
    sub load_cs {
        if (not @cs) {
            local $/ = '';
            push @cs, Change::Set->new($_) while <DATA>;
        }
        return map $_->clone, @cs;
    }
}
BEGIN {
    plan tests => $TESTS;
}

__DATA__
A:455E1A8B05450701B5:created="Fri Nov 17 15:24:46 2006":user=tvon:ticket=DRQS2134567:stage=prea:move=move:message="\ntest test test\n":depends=:reference=:ctime=1165325723:group=general
library=test:target=test:from=/home13/tvon/nonsense.c:to=/home/tvon/cstest/checkin/nonsense.c:type=NEW:production=test
library=test:target=test:from=/home13/tvon/strtok1.c:to=/home/tvon/cstest/checkin/strtok1.c:type=UNCHANGED:production=test
