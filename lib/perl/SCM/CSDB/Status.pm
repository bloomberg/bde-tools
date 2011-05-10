# vim:set ts=8 sts=4 noet:

package SCM::CSDB::Status;

use strict;
use warnings;

use base qw/SCM::CSDB/;

our $SQL = {
  query_status =>
    q{ select ref_code.ref_code_value as status
	      from change_set, ref_code
       where  change_set.status_cd = ref_code.ref_cd and
	      change_set.change_set_name = %csid%
    },

  update_status_from =>
    q{ update change_set set
	     status_cd			= (select ref_cd from ref_code as r
					   where r.ref_code_value = %newstatus%),
	     update_by_uuid		= %uuid%,
	     update_tsp			= current year to fraction(5)
       where change_set.change_set_name = %csid% and
	     change_set.status_cd       = (select ref_cd from ref_code as r
					   where r.ref_code_value = %oldstatus%)
    },

  update_status =>
    q{ update change_set set
	     status_cd			= (select ref_cd from ref_code as r
					   where r.ref_code_value = %newstatus%),
	     update_by_uuid		= %uuid%,
	     update_tsp			= current year to fraction(5)
       where change_set.change_set_name = %csid%
    },
};

sub getChangeSetStatus {
    my ($self, $csid, %args) = @_;
    my $row = $self->select_one('query_status', { csid => $csid });
    return defined $row ? $row->{status} : undef;
}

sub alterChangeSetDbRecordStatus {
    my ($self, $csid, %args) = @_;

    my $txn = $self->_enter_txn(\%args);

    my $count = $self->_alter_status($csid, %args) or return undef;

    $txn->commit if $txn;

    return $count;
}

sub alterMultiChangeSetStatusByStatus {
    my ($self, %args) = @_;

    $self->throw("'oldstatus' param missing or undef for alterMulti")
        if not defined $args{newstatus};
    $self->throw("'newstatus' param missing or undef for alterMulti")
        if not defined $args{newstatus};
    $self->throw("'uuid' param missing or undef for alterMulti")
        if not defined $args{uuid};

    my %except;
    @except{ @{$args{except}} } = () if $args{except};

    my $txn = $self->_enter_txn(\%args);

    my @csids = $self->getCsidsByStatus($args{oldstatus}); 

    my @csid	    = grep !exists $except{$_}, @csids;
    my @oldstatus   = ($args{oldstatus}) x @csid;
    my @newstatus   = ($args{newstatus}) x @csid;
    my @uuid	    = ($args{uuid} || 0) x @csid;

    my $count = $self->execute_array('update_status_from', { csid      => \@csid,
                                                             oldstatus => \@oldstatus,
                                                             newstatus => \@newstatus,
                                                             uuid      => \@uuid }, ); 

    require SCM::CSDB::History;
    SCM::CSDB::History->new(dbh => $self->dbh)
		      ->insertStatusHistory(\@csid, %args);

    $txn->commit if $txn;

    return @csid;
}

sub alterMultiChangeSetStatusFrom {
    my ($self, $csids, %args) = @_;

    my $txn = $self->_enter_txn(\%args);

    my @csids = $self->getCsidsByStatus($args{oldstatus}); 
    $self->_alter_status_from($_, %args) for @$csids;

    $txn->commit if $txn;

    return @$csids;
}

sub alterMultiChangeSetStatus {
    my ($self, $csids, %args) = @_;

    my $txn = $self->_enter_txn(\%args);

    $self->_alter_status($_, %args) or return undef 
        for @$csids;

    $txn->commit if $txn;

    return @$csids;
}

sub getCsidsByStatus {
    my ($self, $status, %args) = @_;
    return map $_->[0],
           @{ $self->select_all('get_csids_by_status', { status => $status }) };
}

# ---------------------------------------------------------------
# Methods to carry out the back-end operations of changing status
# ---------------------------------------------------------------

sub _alter_status {
    my ($self, $csid, %args) = @_;

    # This is to prevent the disaster of adding NULL status_cd into
    # the database which prevent MYCS and almost all other DB-fetching
    # applications to retrieve the change set.
    $self->throw("'newstatus' param missing or undef for _alterStatus")
        if not defined $args{newstatus};
    $self->throw("'uuid' param missing or undef for _alterStatus")
        if not defined $args{uuid};

    my $count = $self->execute('update_status', { csid => $csid, %args }) == 1
        or return undef;

    require SCM::CSDB::History;
    SCM::CSDB::History->new(dbh => $self->dbh)
		      ->insertStatusHistory($csid);
}

sub _alter_status_from {
    my ($self, $csid, %args) = @_;

    $self->throw("'newstatus' param missing or undef for _alterStatus")
        if not defined $args{newstatus};
    $self->throw("'uuid' param missing or undef for _alterStatus")
        if not defined $args{uuid};

    $self->_execute('update_status_from', { csid => $csid, %args }) == 1
        or return undef;

    require SCM::CSDB::History;
    SCM::CSDB::History->new(dbh => $self->dbh)
		      ->insertStatusHistory($csid);
}

1;
=head1 NAME

SCM::CSDB::Status - Status-related CSDB queries

=head1 SYNOPSIS

    use SCM::CSDB::Status;

    my $scsdb = SCM::CSDB::Status->new;
    # -OR-
    my $scsdb = SCM::CSDB::Status->new(dbh => $csdb->dbh);

    my $status = $scsdb->getChangeSetStatus($csid);

=head1 METHODS

=head2 new

=head2 new(dbh => DBI::dbh-object)

(Inherited) Creates a new SCM::CSDB::Status instance. If called with no arguments,
creates a new DB connection. If you already have an open database handle lying around
somewhere, use the second version to reuse the connection.

=head2 getChangeSetStatus($csid)

Returns the status of the change set with the ID I<$csid>. Returns C<undef> if
the change set could not be found.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

Alan Grow E<lt>agrow@bloomberg.netE<gt>
