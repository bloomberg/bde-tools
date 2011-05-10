BEGIN {
    $ENV{ PRODUCTION_SCM_CSDB_PREFIX } = 'Csq';
}

use strict;
use warnings;

use FindBin;
use Test::More;

use Change::Symbols                 qw/STATUS_WAITING STATUS_ACTIVE STATUS_COMPLETE $USER 
                                       DEPENDENCY_TYPE_ROLLBACK DEPENDENCY_TYPE_CONTINGENT/;
use Production::Services;
use Production::Services::ChangeSet qw/createChangeSetDbRecord 
                                       getChangeSetDbRecord
                                       getChangeSetStatus
                                       alterChangeSetDbRecordStatus
                                       alterMultiChangeSetStatus
                                       getChangeSetHistory
                                       addDependencyToChangeSet
                                       alterMultiChangeSetStatus/;
use Change::Set;

use constant {
    ORIGINAL_CS => 0,
    CLONED_CS   => 1,
};

our $TESTS;

local $/ = '';
my $svc = Production::Services->new;

# test creation
BEGIN { $TESTS += 6 }
my %cs; my @csids;
while (<DATA>) {
    my $cs = Change::Set->new($_);
    my $clone = $cs->clone;
    my $newid = Change::Set->generateChangeSetID;
    $cs{ $newid }->[ORIGINAL_CS] = $cs;
    push @csids, $newid;
    $clone->setID($newid);
    $clone->setUser($USER);

    ok(createChangeSetDbRecord($svc, $clone), "creating copy of " . $cs->getID);
}

# test bare retrieval
BEGIN { $TESTS += 6 }
for (keys %cs) {
    my $rec = getChangeSetDbRecord($svc, $_);
    ok($rec, "retrieved equivalent for " . $cs{$_}->[0]->getID);
    $cs{$_}->[CLONED_CS] = $rec;
}

# compare
BEGIN { $TESTS += 6 * 2 }
for (keys %cs) {
    compare($cs{$_}->[ORIGINAL_CS], $cs{$_}->[CLONED_CS]);
}

# 5th change set has two testers/tasks. Make sure we got them both.
BEGIN { $TESTS += 2 }
my $i = $csids[4];
my @testers = $cs{$i}->[CLONED_CS]->getTesters;
my @tasks = $cs{$i}->[CLONED_CS]->getTasks;
ok(@testers == 2, "change set with two testers correctly generated and retrieved for $i");
ok(@tasks == 2, "change set with two tasks correctly generated and retrieved for $i");

# status retrieval
BEGIN { $TESTS += 6 }
while (my ($csid, $css) = each %cs) {
    my $status = getChangeSetStatus($svc, $csid);
    ok($status eq $css->[ORIGINAL_CS]->getStatus, 
       "initial status ok for clone is the same as " . $css->[ORIGINAL_CS]->getID);
}

# change status to N for all change sets with single requests and query success
BEGIN { $TESTS += 6 * 2}
while (my ($csid, $css) = each %cs) {
    ok(alterChangeSetDbRecordStatus($svc, $css->[CLONED_CS], STATUS_WAITING),
       "Changing status to N for $csid");
    ok(getChangeSetStatus($svc, $csid) eq STATUS_WAITING,
       "Checking that status of $csid is N")
}

# excercising alterMultiChangeSetDbRecordStatus
BEGIN { $TESTS += 6 + 1 }
ok(alterMultiChangeSetStatus($svc, STATUS_ACTIVE, [ keys %cs ]),
   "Checking multi-csid status update for " . join(' ', keys %cs));
while (my ($csid, $css) = each %cs) {
    ok(getChangeSetStatus($svc, $csid) eq STATUS_ACTIVE,
       "Checking that multi-update succeeded for $csid");
}

# testing history retrieval
BEGIN { $TESTS += 6 * 6 }
while (my ($csid, $css) = each %cs) {
    my $hist = getChangeSetHistory($svc, $csid, 'resolve');
    ok($hist->[0][1] eq $css->[ORIGINAL_CS]->getStatus, 
       "Initial status the same for $csid and " . $css->[ORIGINAL_CS]->getID);
    ok($hist->[0][3] eq $USER, 
       "Initial updater is $USER for $csid");
    ok($hist->[1][1] eq STATUS_WAITING,
       "Second status for $csid is N");
    ok($hist->[1][3] eq $USER,
       "Updater for second status is $USER for $csid");
    ok($hist->[2][1] eq STATUS_ACTIVE,
       "Final status for $csid is A");
    ok($hist->[2][3] eq $USER,
       "Updater for final status is $USER for $csid"); 
}

# testing dependency adding
BEGIN { $TESTS += 6 * 4 }
my $depends_on_rb = '45803CAC04E18B01B5';
my $depends_on_cn = '45803B2E0052DD01B5';
while (my ($csid, $css) = each %cs) {
    ok(addDependencyToChangeSet($svc, $csid, $depends_on_rb, DEPENDENCY_TYPE_ROLLBACK),
       "adding DEPENDENCY_TYPE_ROLLBACK to $csid");
    ok(addDependencyToChangeSet($svc, $csid, $depends_on_cn, DEPENDENCY_TYPE_CONTINGENT),
       "adding DEPENDENCY_TYPE_CONTINGENT to $csid");
    my $rec = getChangeSetDbRecord($svc, $csid);
    is_deeply([ $rec->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK) ],
              [ $depends_on_rb ],
              "DEPENDENCY_TYPE_ROLLBACK on $depends_on_rb present in $csid");
    is_deeply([ $rec->getDependenciesByType(DEPENDENCY_TYPE_CONTINGENT) ],
              [ $depends_on_cn ],
              "DEPENDENCY_TYPE_CONTINGENT on $depends_on_cn present in $csid");
}

# test that change set number 6 has a TSMV reference
BEGIN { $TESTS += 1 }
{
    my $id = $csids[5];
    my $rec = getChangeSetDbRecord($svc, $id);
    ok($rec->getReferences eq 'TSMV44249',
       "Checking that TSMV reference was generated in the DB correctly");
}

# test alterMultiChangeSetStatus as robocop
BEGIN { $TESTS += 6 + 1 }
ok(alterMultiChangeSetStatus($svc, STATUS_COMPLETE, [ keys %cs ], 'robocop'),
   "Checking alterMultiChangeSetStatus as user robocop");
while (my ($csid, $css) = each %cs) {
    ok(getChangeSetStatus($svc, $csid) eq STATUS_COMPLETE,
       "Check that $csid has status C");
}

sub compare {
    my ($cs1, $cs2) = @_;

    my $csid = $cs1->getID;

    my @files1 = $cs1->getFiles;
    my @files2 = $cs2->getFiles;
    ok(@files1 == @files2, "num files identical for $csid");
    is_deeply([ map $_->getDestination, @files1 ], 
              [ map $_->getDestination, @files2 ], "files have same destination for $csid");
}

BEGIN {
    plan tests => $TESTS;
}

__DATA__
C:455762ED0190C5E8E7:created="Sun Nov 12 13:08:27 2006":user=shalstea:ticket=TREQ568914:stage=prea:move=move:message="\nDeploy upgrade of sw for OVML\n":depends=:reference=TSMV274647:ctime=1165271703:group=general
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketisduplicate.cpp:to=/bbsrc/checkin/lgysec_moneymarketisduplicate.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_pyinfo.h:to=/bbsrc/checkin/lgysec_pyinfo.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_packseries.h:to=/bbsrc/checkin/lgysec_packseries.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_functiondeclarations.cpp:to=/bbsrc/checkin/lgysec_functiondeclarations.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_securityftrn.h:to=/bbsrc/checkin/lgysec_securityftrn.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_legacyhelper.h:to=/bbsrc/checkin/lgysec_legacyhelper.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketecpbucket.h:to=/bbsrc/checkin/lgysec_moneymarketecpbucket.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketcommondata.cpp:to=/bbsrc/checkin/lgysec_moneymarketcommondata.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_accmmkt.h:to=/bbsrc/checkin/lgysec_accmmkt.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_xtramva.cpp:to=/bbsrc/checkin/lgysec_xtramva.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_secinfo.h:to=/bbsrc/checkin/lgysec_secinfo.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketisduplicate.h:to=/bbsrc/checkin/lgysec_moneymarketisduplicate.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketecpbucket.cpp:to=/bbsrc/checkin/lgysec_moneymarketecpbucket.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketcommondata.h:to=/bbsrc/checkin/lgysec_moneymarketcommondata.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_parsekyn.cpp:to=/bbsrc/checkin/lgysec_parsekyn.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketdb2vals.cpp:to=/bbsrc/checkin/lgysec_moneymarketdb2vals.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_ident.h:to=/bbsrc/checkin/lgysec_ident.h:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_securityftrn.cpp:to=/bbsrc/checkin/lgysec_securityftrn.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_moneymarketcreatesecondary.cpp:to=/bbsrc/checkin/lgysec_moneymarketcreatesecondary.cpp:type=UNCHANGED:production=lgy
library=lgy:target=lgy/lgysec:from=/bbcm/ts/ticketing/TicketingAPIroot/cs_tmp/src/lgy/lgysec/lgysec_packseries.cpp:to=/bbsrc/checkin/lgysec_packseries.cpp:type=UNCHANGED:production=lgy

C:455C82640ACBE200EF:created="Thu Nov 16 10:23:20 2006":user=zschwart:ticket=TREQ574570:stage=prea:move=stpr:message="Change-Set-Approver: ssorense\n\nNew offline to generate xml feed for Global Permissioning in POMS.\n":depends=:reference=TSMV275002:ctime=1165271759:group=general
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_main.h:to=/bbsrc/checkin/m_bclxml_main.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_scheme.h:to=/bbsrc/checkin/m_bclxml_scheme.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_filter.h:to=/bbsrc/checkin/m_bclxml_filter.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_admin_database.h:to=/bbsrc/checkin/m_bclxml_admin_database.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_scheme.cpp:to=/bbsrc/checkin/m_bclxml_scheme.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_permission.cpp:to=/bbsrc/checkin/m_bclxml_permission.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_permission.h:to=/bbsrc/checkin/m_bclxml_permission.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_main.cpp:to=/bbsrc/checkin/m_bclxml_main.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_filter.cpp:to=/bbsrc/checkin/m_bclxml_filter.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_user_group.h:to=/bbsrc/checkin/m_bclxml_user_group.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_ambiguitydefaults.cpp:to=/bbsrc/checkin/m_bclxml_ambiguitydefaults.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_user_group.cpp:to=/bbsrc/checkin/m_bclxml_user_group.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/gpfeed_dum.c:to=/bbsrc/checkin/gpfeed_dum.c:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_converter.cpp:to=/bbsrc/checkin/m_bclxml_converter.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_admin_database.cpp:to=/bbsrc/checkin/m_bclxml_admin_database.cpp:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_ambiguitydefaults.h:to=/bbsrc/checkin/m_bclxml_ambiguitydefaults.h:type=NEW:production=tradsys/util/m_bclxml
library=tradsys/util/m_bclxml:target=tradsys/util/m_bclxml:from=/home9/zschwart/cscheckin1/tradsys/util/m_bclxml/m_bclxml_converter.h:to=/bbsrc/checkin/m_bclxml_converter.h:type=NEW:production=tradsys/util/m_bclxml

R:44B431B10D331CE406:created="Tue Jul 11 19:18:51 2006":user=gmorin:ticket=DRQS7225424:stage=prod:move=emov:message="Change-Set-Approver: abasov  \nChange-Set-Tester: abasov  \n\nAdded support for configuring thread parameters\n":depends=:reference=:ctime=1165271996:group=general
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_basconfig.cpp:to=/bbsrc/checkin/bascfg_basconfig.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_metricscomponent.cpp:to=/bbsrc/checkin/bascfg_metricscomponent.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_soapactionmap.cpp:to=/bbsrc/checkin/bascfg_soapactionmap.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_soapinterface.h:to=/bbsrc/checkin/bascfg_soapinterface.h:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_fastsendinterfacemode.cpp:to=/bbsrc/checkin/bascfg_fastsendinterfacemode.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_fastsendinterface.cpp:to=/bbsrc/checkin/bascfg_fastsendinterface.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_requestenvironment.cpp:to=/bbsrc/checkin/bascfg_requestenvironment.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_loggingconfig.cpp:to=/bbsrc/checkin/bascfg_loggingconfig.cpp:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_tcpinterface.h:to=/bbsrc/checkin/bascfg_tcpinterface.h:type=UNCHANGED:production=bas
library=bas:target=bas/bascfg:from=/bb/data/tmp/gmorin/bas/bascfg/bascfg_threadpoolconfig.cpp:to=/bbsrc/checkin/bascfg_threadpoolconfig.cpp:type=CHANGED:production=bas

C:456B852203029EE359:created="Mon Nov 27 19:40:16 2006":user=mschmit:ticket=TREQ628300:stage=prea:move=bugf:message="\nIRD Bulk Checkin\n":depends=:reference=:ctime=1165272099:group=general
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_valuationdetailgrid.h:to=/bbsrc/checkin/irgpas_valuationdetailgrid.h:type=CHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_screenset.cpp:to=/bbsrc/checkin/irgpas_screenset.cpp:type=CHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_riskscreen.h:to=/bbsrc/checkin/irgpas_riskscreen.h:type=CHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_calculatorgrid.cpp:to=/bbsrc/checkin/irgpas_calculatorgrid.cpp:type=UNCHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_zspreadgrid.h:to=/bbsrc/checkin/irgpas_zspreadgrid.h:type=CHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_zspreadgrid.cpp:to=/bbsrc/checkin/irgpas_zspreadgrid.cpp:type=CHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_guifactory.cpp:to=/bbsrc/checkin/irgpas_guifactory.cpp:type=CHANGED:production=irg
library=irg:target=irg/irgpas:from=/bbshr/ird/robo/t628300-1124/irg/irgpas/irgpas_cfinfogrid.cpp:to=/bbsrc/checkin/irgpas_cfinfogrid.cpp:type=CHANGED:production=irg

C:45780D5505EEB80144:created="Thu Dec  7 07:47:20 2006":user=rfayez2:ticket=DRQS7792659:stage=prod:move=emov:message="Change-Set-Approver: eeshel  \nChange-Set-Function: BLP\nChange-Set-Task: ibig\nChange-Set-Task: gtk\nChange-Set-Tester: isusilo \nChange-Set-Tester: rfayez2 \n\nInserted traces to investigate beta crashes.\n":depends=:reference=:ctime=1165505279:group=general
library=gtkapp:target=gtkapp:from=/home9/rfayez2/checkin/gtk/gtkapp/gridbox.c:to=/bbsrc/checkin/gridbox.c:type=CHANGED:production=gtk/gtkapp
library=gtkapp:target=gtkapp:from=/home9/rfayez2/checkin/gtk/gtkapp/grid_utils.c:to=/bbsrc/checkin/grid_utils.c:type=CHANGED:production=gtk/gtkapp

R:453E53200D4131E8F8:created="Tue Oct 24 13:53:43 2006":user=qchen:ticket=DRQS7090898:stage=prea:move=move:message="\ntesting tsmv\n":depends=453CD42F058EF8E8F8|C,453CCFA6028127E8F8|C:reference=TSMV44249:ctime=1166210240:group=general
library=acclib:target=acclib:from=/home/qchen/cstest/test/q1.c:to=/home/qchen/cstest/checkin/q1.c:type=NEW:production=acclib
