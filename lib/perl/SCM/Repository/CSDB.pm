# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Repository::CSDB;

use strict;
use warnings;

use base qw/SCM::Repository/;

use Util::Exception qw/exception/;

use Change::Symbols	    qw/FILE_IS_UNCHANGED
			       STATUS_ROLLEDBACK STATUS_REINSTATED/;
use SCM::Symbols	    qw/SCM_CSDB SCM_CSDB_DRIVER/;
use SCM::CSDB::Repository;

sub csid_history {
  my $self = shift;
  my ($branch, $path, %arg) = @_;

  return 0, "Expected: branch (movetype)." if !$branch;

  return $self->SUPERL::csid_history(@_)
    if not defined $path;

  my (@csids, %crawl);

  $crawl{path} = $path if defined $path;

  if ($arg{startcsid}) {
    $crawl{startrev} = $self->_get_rev_from_csid($arg{startcsid}) or
      return 0, "CSID not found: $arg{startcsid}.";
  }

  $crawl{startrev} ||= $self->_headrev;

  if ($arg{endcsid}) {
    $crawl{endrev} = $self->_get_rev_from_csid($arg{endcsid}) or
      return 0, "CSID not found: $arg{endcsid}.";
  }

  my $rdb = SCM::CSDB::Repository->new(database => SCM_CSDB,
				       driver	=> SCM_CSDB_DRIVER);
  my $sdb = SCM::CSDB::Status->new(dbh => $rdb->dbh);

  $crawl{cb_visit} = sub {
    my ($rev) = @_;
    my $csid = $self->_get_csid_from_rev($rev);

    return 1 if !$csid; # keep going, no csid associated with this rev
    return 0 if defined $arg{limit} && @csids >= $arg{limit};

    if (exists $arg{visit}) {
      my $visit = $arg{visit}->($csid);
      return $visit if !$visit;
    }

    my $status = $sdb->getChangeSetStatus($csid);
    return 1 if $status eq STATUS_ROLLEDBACK ||
		$status eq STATUS_REINSTATED;
	    
    my $type = $rdb->getFileTypeForCSID($path, $csid);
    return 1 if !defined $type or $type eq FILE_IS_UNCHANGED;

    unshift @csids, $csid;
    return 1; # keep going
  };

  $self->_cs_crawlback($branch, %crawl);

  return \@csids, 0;
}

1;

=head1 NAME

SCM::Repository::CSDB - A database-driven repository object

=head1 SYNOPSIS

    use SCM::Symbols            qw/SCM_REPOSITORY/;
    use SCM::Repository::CSDB;

    my $rep = SCM::Repository::CSDB->new(repository_path => SCM_REPOSITORY);

    # same as SCM::Repository

=head1 DESCRIPTION

This subclass of C<SCM::Repository> makes use of the changeset DB in order to 
carry out certain operations either more efficiently or more correctly.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

Alan Grow E<lt>agrow@bloomberg.netE<gt>
