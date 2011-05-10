# This tests  SCM::CSDB::Repository 

use strict;
use warnings;

use FindBin;
use Test::More;

use SCM::Symbols    qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::ChangeSet;
use SCM::CSDB::Repository;

our $TESTS;

my @DB ;

my $rdb = SCM::CSDB::Repository->new(@DB);

my (@csids, %cs);
BEGIN {
    @DB = (database => SCM_CSDB, driver => SCM_CSDB_DRIVER);
    @csids = qw/4582F59408701101B5 4582F599013AD201B5 45B150D5030B0301B5/; 
    my $cdb = SCM::CSDB::ChangeSet->new(@DB);
    $cs{$_} = $cdb->getChangeSetDbRecord($_) for @csids;
    $TESTS += map $_->getFiles, values %cs; 
}
for my $csid (@csids) {
    for my $f ($cs{$csid}->getFiles) {
        ok($f->getType eq $rdb->getFileTypeForCSID($f, $csid), 
           "$f: Filetype returned by DB query identical to filetype in $csid");
    }
}

BEGIN {
    plan tests => $TESTS;
}
