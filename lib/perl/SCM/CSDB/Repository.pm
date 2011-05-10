# vim:set ts=8 sts=4 noet:

package SCM::CSDB::Repository;

use strict;
use warnings;

use base qw/SCM::CSDB/;

our $SQL = {
  file_status_in_change_set =>
    q{ select r.ref_code_value as type
       from   ref_code as r, change_set as c, change_set_file as f
       where  c.change_set_name = %csid%		and
	      f.change_set_id	= c.change_set_id	and
	      f.file_name	= %file%		and
	      r.ref_cd		= f.file_change_type
    },
};

sub getFileTypeForCSID {
    my ($self, $file, $csid) = @_;

    my $base;
    if (UNIVERSAL::isa($file, 'Change::File')) {
	$base = $file->getLeafName;
    } else {
	require File::Basename;
	$base = File::Basename::basename($file);
    }

    my $rec = $self->select_one('file_status_in_change_set', { csid => $csid,
							       file => $base });
    
    return if not defined $rec;

    return $rec->{type};
}

1;
=head1 NAME

SCM::CSDB::Repository - Support class for a database-driven repository

=head1 SYNOPSIS

    use SCM::CSDB::Repository;

    my $rcsdb = SCM::CSDB::Status->new;
    # -OR-
    my $rcsdb = SCM::CSDB::Status->new(dbh => $csdb->dbh);

    my $type = $rcsdb->getFileTypeForCSID($filename, $csid);

=head1 METHODS

=head2 new

=head2 new(dbh => DBI::dbh-object)

(Inherited) Creates a new SCM::CSDB::Status instance. If called with no arguments,
creates a new DB connection. If you already have an open database handle lying around
somewhere, use the second version to reuse the connection.

=head2 getFileTypeForCSID($filename, $csid)

Returns the filetype (CHANGED, UNCHANGED, etc.) the given I<$file> has in the change
set I<$csid>.

Returns undef on failure.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

Alan Grow E<lt>agrow@bloomberg.netE<gt>
