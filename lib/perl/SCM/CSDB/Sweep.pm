# vim:set ts=8 sts=4 noet:

package SCM::CSDB::Sweep;

use strict;
use warnings;

use Change::Symbols qw/STATUS_ACTIVE STATUS_INPROGRESS/;

use base qw/SCM::CSDB::Status/;

our $SQL = $SCM::CSDB::Status::SQL;

sub getChangeSetsForSweep {
    my ($self, $csids) = @_;

    my @would_change;

    for (@$csids) {
	my $s = eval {
	    $self->getChangeSetStatus($_)
	};
	next if $@ or not defined $s;
	next if $s ne STATUS_ACTIVE;
	push @would_change, $_;
    }

    return @would_change;
}

sub markChangeSetsForSweep {
    my ($self, $csids, %args) = @_;

    # they need to be in status A
    my @oldstatus = (STATUS_ACTIVE)     x @$csids;
    my @newstatus = (STATUS_INPROGRESS) x @$csids;
    my @uuid = (0) x @$csids;    # always robocop

    my $txn = $self->_enter_txn(\%args);

    my $count = $self->execute_array('update_status_from', 
                                      { csid       => $csids,
                                        uuid       => \@uuid,
                                        oldstatus  => \@oldstatus,
                                        newstatus  => \@newstatus, },
                                      ArrayTupleStatus => \my @status,
                                      );

    # Inspect ArrayTupleStatus to find out
    # which CSs actually had their status changed
    my @changed;
    $status[$_] > 0 and push @changed, $csids->[$_] for 0 .. $#status;

    require SCM::CSDB::History;
    $count = SCM::CSDB::History->new(dbh => $self->dbh)
                               ->insertStatusHistory(\@changed, %args);

    $txn->commit if $txn;
    return @changed;
}

1;
