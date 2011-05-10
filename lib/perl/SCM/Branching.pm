package SCM::Branching;

our $VERSION = '0.01';

use Change::Symbols         qw/$MOVE_REGULAR $MOVE_BUGFIX $MOVE_EMERGENCY/;
use SCM::Symbols            qw/SCM_CSDB SCM_CSDB_DRIVER/;
use SCM::CSDB::Branching;

sub promote_branch {
    my $alias = shift;

    my $db  = SCM::CSDB::Branching->new(database => SCM_CSDB, driver => SCM_CSDB_DRIVER);
    my $txn = $db->txn;
    
    # get current branch mapping
    my $map = $db->getBranchMapping;

    my $branch_id = $map->{$alias}
        or return undef, "Cannot map $alias to any branch";

    if ($alias eq $MOVE_REGULAR) {

        # create a new regular branch
        $db->createNewChildBranch($branch_id + 1);

        # point alias 'move' to this new branch
        $db->updateBranchMapping($MOVE_REGULAR => $branch_id + 1);

        # point alias 'bugf' to old branch
        $db->updateBranchMapping($MOVE_BUGFIX => $branch_id);

    } elsif ($alias eq $MOVE_BUGFIX) {

        # point alias 'emov' to current branch
        $db->updateBranchMapping($MOVE_EMERGENCY => $branch_id);

        # the old emov branch ends
        $db->endBranchSegment($MOVE_EMERGENCY => $branch_id - 1);

    }

    # end old branch segment
    $db->endBranchSegment($alias => $branch_id);

    $txn->commit;

    return $db->getBranchMapping;
}

1;
__END__
=head1 NAME

SCM::Branching - High-level branching functionality

=head1 SYNOPSIS

    use Change::Symbols qw/MOVETYPE_REGULAR/;
    use SCM::Branching  qw/promote_branch/;

    my ($mapping, $err) = promote_branch(MOVE_REGULAR);

    if ($mapping) {
        print "regular branch just promoted to bugfix. New mapping:";
        print Dumper $mapping;
    } else {
        die "Failed to promote regular branch: $err\n";
    }

=head1 FUNCTIONS

=head2 promote_branch(@movetypes)

Does the necessary magic to promote the given I<$movetype> to the next level.

Note that depending on which moveype is promoted, additional things happen: 
For example, the promotion of the regular branch to bugfix implies the birth
of a new regular branch.

All necessary work is carried out inside a transaction. It returns a reference
to the new branch mapping on success. Otherwise, it returns a two element list
with the first element being undef and the second the error.

=head1 AUTHORS

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
