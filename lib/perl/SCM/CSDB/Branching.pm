# vim:set ts=8 sts=4 noet:

package SCM::CSDB::Branching;

use strict;
use warnings;

use base qw/SCM::CSDB/;

our $SQL = {
    get_branch_name => q{
	select branch_id, map_id
	from   branch_map
	where  branch_alias = %alias% and
	       ((datetime(&utc&) year to second between start_time and end_time)
		    or
	       (datetime(&utc&) year to second >= start_time and end_time is null))
	order by map_id
    },
    get_branch_mapping => q{
	select branch_alias, branch_id
	from   branch_map 
	where  (datetime(&utc&) year to second between start_time and end_time)
		    or
	       (datetime(&utc&) year to second >= start_time)
    },
    create_child_branch => q{
	insert into branch 
	       (parent_id, start_time)
	values (%parent%, datetime(&utc&) year to second)
    },
    get_branch_lineage => q{
	select br1.branch_id, br1.start_time, br2.start_time
	from   branch as br1, branch as br2
	where  br1.branch_id = br2.parent_id and
	       br1.branch_id < %branch%
    },
    update_branch_mapping => q{
	insert into branch_map 
	       (branch_alias, branch_id, start_time)
	values (%move%, %branch%, datetime(&utc&) year to second)
    },
    end_branch_segment => q{
	update branch_map set
	       end_time = datetime(&utc&) year to second
	where  branch_id    = %branch%	and
	       branch_alias = %alias%
    },
};

sub getBranchNameFromAlias {
    my ($self, $alias, $utc, %args) = @_;

    $utc ||= POSIX::strftime('%Y-%m-%d %T', localtime);
    my $rows = $self->select_all('get_branch_name', { alias => $alias, 
					  	      utc   => $utc });
    return defined $rows ? $rows->[-1][0] : undef;
}

sub getBranchMapping {
    my ($self, $utc, %args) = @_;

    $utc ||= POSIX::strftime('%Y-%m-%d %T', localtime);

    my $res = $self->select_all('get_branch_mapping', { utc => $utc });
    return if not defined $res;

    # should have three elements
    return map @$_, @$res;
}

sub createNewChildBranch {
    my ($self, $branch, $utc, %args) = @_;

    $utc ||= POSIX::strftime('%Y-%m-%d %T', localtime);
    return $self->execute('create_child_branch', { parent => $branch,
						   utc    => $utc });
}

sub getBranchLineage {
    my ($self, $branch, %args) = @_;

    my $rec = $self->select_all('get_branch_lineage', { branch => $branch });

    return if not defined $rec;
    return @$rec;
}

sub updateBranchMapping {
    my ($self, $alias, $branch, $utc, %args) = @_;

    $utc ||= POSIX::strftime('%Y-%m-%d %T', localtime);

    return $self->execute('update_branch_mapping', { move   => $alias,
						     branch => $branch,
						     utc    => $utc });
}

sub endBranchSegment {
    my ($self, $alias, $branch, $utc, %args) = @_;

    $utc ||= POSIX::strftime('%Y-%m-%d %T', localtime);
    return $self->execute('end_branch_segment', { alias  => $alias,
						  branch => $branch,
						  utc    => $utc, });
}

1;

=head1 NAME

SCM::CSDB::Branching - Branching driven by the changeset DB

=head1 SYNOPSIS

    use SCM::CSDB::Branching;

    my $bcsdb = SCM::CSDB::Status->new;
    # -OR-
    my $bcsdb = SCM::CSDB::Status->new(dbh => $csdb->dbh);

    my $branch_num = $bcsdb->getBranchNameFromAlias('emov', '2007-01-07 13:00:00');

=head1 METHODS

=head2 new

=head2 new(dbh => DBI::dbh-object)

(Inherited) Creates a new SCM::CSDB::Status instance. If called with no arguments,
creates a new DB connection. If you already have an open database handle lying around
somewhere, use the second version to reuse the connection.

=head2 getBranchNameFromAlias($alias, $utc)

Returns the physical branch name (a number E<lt>= 1) for the given branch alias
(movetype) at the given point in time which must be an ISO-8601 formatted
string.

Returns undef if no matching branch name could be found.

=head2 getBranchMapping($utc)

Given a point in time as ISO-8601 formatted string, returns a hash-mapping of
movetype to physical branch map.

Returns an empty list if no mapping could be deduced.

=head2 createNewChildBranch($parent) 

Given a physical branch name (I<$parent>), create a new child branch with the 
current time as start time.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

Alan Grow E<lt>agrow@bloomberg.netE<gt>
