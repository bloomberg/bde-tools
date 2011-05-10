use strict;
use warnings;

use Test::More;
use Data::Dumper;

use SCM::Symbols    qw/SCM_CSDB_DRIVER/;
use Change::Symbols qw/$MOVE_REGULAR $MOVE_BUGFIX $MOVE_EMERGENCY/;

use SCM::CSDB::Branching;

my $TESTS;
my ($informix, $database);
my %sql;

my $bdb = SCM::CSDB::Branching->new(database => $database, driver => SCM_CSDB_DRIVER);

BEGIN { $TESTS += 5 }
# this is the kind of mapping you find on a Tuesday/Wednesday
is_deeply({ $bdb->getBranchMapping }, { move => 3, bugf => 2, emov => 1 }, 'branch mapping ok Tuesday');
is($bdb->getBranchNameFromAlias($MOVE_REGULAR), 3, 'move is 3');
is($bdb->getBranchNameFromAlias($MOVE_BUGFIX), 2, 'bugf is 2');
is($bdb->getBranchNameFromAlias($MOVE_EMERGENCY), 1, 'emov is 1');
is_deeply( [ $bdb->getBranchLineage(3) ], [ [ 1, '1969-01-01 00:00:00', '1970-01-01 00:00:00' ],
                                            [ 2, '1970-01-01 00:00:00', '1971-01-01 00:00:00' ] ],
                                          'branch lineage for 3 ok');

# now we advance to Friday: bugf and move map to the same branch
# old emov branch ends
BEGIN { $TESTS += 6  }
ok($bdb->updateBranchMapping($MOVE_EMERGENCY => 2, '1973-01-01 00:00:00'), 
   'update branch mapping: emov => 2');
is($bdb->getBranchNameFromAlias($MOVE_EMERGENCY), 2, 'emov is 2');
ok($bdb->updateBranchMapping($MOVE_BUGFIX => 3, '1973-01-01 00:00:00'), 
   'update branch mapping: bugf => 1');
is($bdb->getBranchNameFromAlias($MOVE_BUGFIX), 3, 'bugf is 2');
is_deeply({ $bdb->getBranchMapping }, { move => 3, bugf => 3, emov => 2 }, 'branch mapping ok Friday');
ok($bdb->endBranchSegment($MOVE_EMERGENCY, 1, '1973-01-01 00:00:00'), 
   'abandoning old emov branch (1)');

# Monday: new child branch created. 
# move points to new child branch. bugf remains.
BEGIN { $TESTS += 4 }
ok($bdb->createNewChildBranch(3, '1972-01-01 00:00:00'), 'create new branch 4');
ok($bdb->updateBranchMapping($MOVE_REGULAR => 4, '1974-01-01 00:00:00'));
is_deeply({ $bdb->getBranchMapping }, { move => 4, bugf => 3, emov => 2 }, 'branch mapping ok: Monday');
is_deeply([ $bdb->getBranchLineage(4) ], [ [ 1, '1969-01-01 00:00:00', '1970-01-01 00:00:00' ],
                                           [ 2, '1970-01-01 00:00:00', '1971-01-01 00:00:00' ],
                                           [ 3, '1971-01-01 00:00:00', '1972-01-01 00:00:00' ] ]);

BEGIN {
    %sql = (
        create_tables => q{
            create table branch (
                branch_id serial primary key,
                parent_id integer references branch(branch_id),
                start_time datetime year to second not null
            );

            create table branch_map (
                map_id serial primary key,
                branch_alias varchar(254) not null,
                branch_id integer references branch(branch_id),
                start_time datetime year to second not null,
                end_time datetime year to second
            );
            
            insert into branch 
                        (parent_id, start_time)
            values (null, datetime(1969-01-01 00:00:00) year to second);

            insert into branch
                        (parent_id, start_time)
            values (1, datetime(1970-01-01 00:00:00) year to second);

            insert into branch
                        (parent_id, start_time)
            values (2, datetime(1971-01-01 00:00:00) year to second);

            insert into branch_map (branch_alias, branch_id, start_time)
            values ('emov', 1, datetime(1970-07-01 00:00:00) year to second);

            insert into branch_map (branch_alias, branch_id, start_time)
            values ('bugf', 2, datetime(1971-01-01 00:00:00) year to second);

            insert into branch_map (branch_alias, branch_id, start_time)
            values ('move', 3, datetime(1971-01-01 00:00:00) year to second);
        },
        clean_up => q{
            drop table branch_map;
            drop table branch;
        },
    );
    $informix = '/bb/bin/informix.misc2';
    $database = 'changesetdb@devarch_sec_tcp';
    open SQLCMD, '|-', ". $informix && sqlcmd -d $database" 
        or die "Can't open pipe to sqlcmd: $!";
    print SQLCMD $sql{ create_tables };
    close SQLCMD 
        or die "Can't close pipe to sqlcmd: $! . $?";

    plan tests => $TESTS;
}

END {
    open SQLCMD, '|-', ". $informix && sqlcmd -d $database" 
        or die "Can't open pipe to sqlcmd: $!";
    print SQLCMD $sql{ clean_up };
    close SQLCMD 
        or die "Can't close pipe to sqlcmd: $! . $?";
}
