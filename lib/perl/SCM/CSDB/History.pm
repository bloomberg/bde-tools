# vim:set ts=8 sts=4 noet:

package SCM::CSDB::History;

use base qw/SCM::CSDB/;

our $SQL = {
  get_cs_history => 
    q{ select h.status_tsp, r.ref_code_value, h.update_by_uuid
       from   chg_set_stat_his as h, change_set as c, ref_code as r
       where  c.change_set_name = %csid%            and
	      h.change_set_id   = c.change_set_id   and
	      h.status_cd       = r.ref_cd 
    },

  insert_status_history =>
    q{insert into chg_set_stat_his
	     (change_set_id, status_tsp, status_cd, update_by_uuid)
      select change_set_id, update_tsp, status_cd, update_by_uuid
      from   change_set 
      where  change_set_name = %csid%
    },
};

sub insertStatusHistory {
    my ($self, $csids, %args) = @_;
    return $self->execute_array('insert_status_history', { csid => $csids });
}

sub getChangeSetHistory {
    my ($self, $csid, $resolve_uuid, %args) = @_;
    my $res = $self->select_all('get_cs_history', { csid => $csid });

    # This state B (Being added state) only exists in the database
    shift @$res if $res->[0][1] eq 'B';

    # strip time of second fraction
    $_ and $_->[0] =~ s/\.\d+$// for @$res;

    if ($resolve_uuid) {
        require SCM::UUID;
        my $resolver = SCM::UUID->new;
        for (grep $_->[2], @$res) { # grep out UUID == 0
            my ($err, $unix) = $resolver->uuid2unix($_->[-1]);
            push @$_, $unix if not $err; 
        }
    }
    return $res;
}

1;

=head1 NAME

SCM::CSBD::History - Change set history-related CSDB requests

=head1 SYNOPSIS

    use SCM::CSDB::History;

    my $hcsdb = SCM::CSDB::History->new;
    # -OR-
    my $hcsdb = SCM::CSDB::History->new(dbh => $csdb->dbh);

    my $hist = $hcsdb->getChangeSetHistory($csid, 'resolve');

=head1 METHODS

=head2 new

=head2 new(dbh => DBI::dbh-object)

(Inherited) Creates a new SCM::CSDB::History instance. If called with no arguments,
creates a new DB connection. If you already have an open database handle lying around
somewhere, use the second version to reuse the connection.

=head2 getChangeSetHistory($csid, [$resolve])

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

Alan Grow E<lt>agrow@bloomberg.netE<gt>
