# vim:set ts=8 sts=4 noet:

package SCM::Info::Diff;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;

use base qw/SCM::Info/;

use SCM::Symbols qw/$SCM_DIFF_PATH/;

my @params = qw/csid old new lroot/;

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;

    $self->content_type;

    if ($self->{csid}) {
	return 1 if $self->static_diff($self->{csid})
    }

    print start_html(-title     => "DIFF: $self->{old} vs $self->{new}",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => $self->css . '/style.css',
    );

    $self->render_diff;

    print end_html;
}

sub static_diff {
    my ($self, $csid) = @_;

    return if not -e(my $loc = "$SCM_DIFF_PATH/$csid.diff.html");

    open my $diff, '<', $loc
	or return $self->error("Could not open $loc: $!");

    print while <$diff>;

    return 1;
}

sub error {
    my ($self, $error) = @_;

    print <<EOERROR;
    <h2 align="center">Error generating diff report</h2>
    <p style="text-alignment:center">$error</p>
EOERROR
}

sub styles {
    qw/html/;
}

1;
