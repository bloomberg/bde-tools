# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Repository::Blame;

use strict;
use warnings;

use base qw/SCM::Repository/;

use SVN::Client;

use Util::Exception qw/exception/;

sub blame {
  my ($self, $branch, $lroot, $fh, $from, $to) = @_;

  my $startrev  = $from ? $self->csid2rev($from) : $self->_get_branch_birthrev($branch);
  my $endrev    = $to ? $self->csid2rev($to) : $self->_headrev;

  $fh ||= \*STDOUT;

  my $pool = SVN::Pool->new_default(undef);
  my $ctx = SVN::Client->new;

  my $callback = sub {
    my ($line_no, $rev, $author, $date, $line) = @_;
    my $csid = eval {
      $self->_get_csid_from_rev($rev); 
    } || '       ???        ';
    $author = sprintf "%8s", $author;
    print $fh "$csid  $author  $line\n";
  };

  $lroot =~ s#^root/##;
  my $bpath = $self->_resolve_branch($branch)
    or return undef, exception("$branch: Invalid branch", 1);
  my $path = 'file://' . $self->_repospath . "/branches/$bpath/$lroot";

  $ctx->blame($path, $startrev, $endrev, $callback);

  return 1;
}

1;

=head1 NAME

SCM::Repository::Blame - A class creating blame reports

=head1 SYNOPSIS

    use SCM::Symbols            qw/SCM_REPOSITORY/;
    use SCM::Repository::Blame;

    my $blame = SCM::Repository::Blame->new(repository_path => SCM_REPOSITORY);

    $blame->blame($move, $lroot);

=head1 METHODS

=head1 blame($movetype, $lroot, [ $fh ], [ $fromcsid ], [ $tocsid ])

Writes a blame report for the file I<$lroot> to I<$fh> which defaults to STDOUT.
It starts at I<$fromcsid> (defaulting to the first CSID in the repository) up
to I<$endcsid>, defaulting to the head CSID.

Returns a true value if successfult, otherwise a two element list with the first
element being false and the second element a <Util::Exception> object.

=head1 BUGS

The I<$movetype> argument to C<blame> is currently being ignored. The blame report
will contain mixed movetype CSIDs.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

Alan Grow E<lt>agrow@bloomberg.netE<gt>
