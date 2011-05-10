# vim:set ts=8 sts=4 noet:

package SCM::Info::LookAt;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;
use File::Basename;
use HTML::Entities;
use File::Spec;
use File::Temp  qw/tempdir/;

use base qw/SCM::Info/;

use SCM::Repository;
use SCM::Symbols            qw/SCM_REPOSITORY SCM_QUEUE SCM_DIR_DATA
                               SCM_CSDB SCM_CSDB_DRIVER/;
use SCM::Queue::Util        qw/csid_to_cs/;
use Change::Util::Bundle    qw/unbundleChangeSet/;
use Change::Util            qw/hashCSID2dir/;

my @params = qw/csid lroot staged branch close_button diff_button/;

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;

    $self->content_type;

    print start_html(-title     => "MyCS: $self->{csid}",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code => $self->css, },
    );

    $self->prepare_file;
    $self->buttons;
    $self->render_file;

    print end_html;

}

sub prepare_file {
    my ($self) = @_;

    if ($self->{branch}) {
        $self->{content} = $self->content_for_branch;
    } elsif ($self->{csid}) {
        $self->{content} = $self->content_for_csid;
    }
}


sub render_file {
    my ($self) = @_;

    my $content = $self->{content};

    encode_entities($content);

    print <<EOHTML;
<pre><code>
$content
</code></pre>
EOHTML
}

sub buttons {
    my ($self) = @_;
    
    print "<div style=\"text-align:center; padding-top:20px\">\n";

    print $self->close_button 
        if $self->{close_button};

    print $self->diff_button
        if $self->{diff_button};

    print "</div>";
}

sub diff_button {
    my ($self) = @_;

    return if not $self->{csid};
    
    my $move = $self->{cs}->getMoveType;
    my $new  = $self->{cs}->getID;

    my $repo = SCM::Repository->new(repository_path => SCM_REPOSITORY);
    my ($csids, $err) = $repo->csid_history($move, $self->{lroot}, limit => 2);

    my $old = @$csids == 2 ? $csids->[1] : 0;
    my $url = $self->base_url . "?command=Diff&presentation=html" .
                                "&new=$new&old=$old&lroot=$self->{lroot}";
    my $onclick = "javascript:window.open('$url', '__blank')";

    return <<EOBUTTON;
    <input type="button" value="Diff" onclick="$onclick">
EOBUTTON
}

sub styles {
    qw/html/;
}

sub content_for_branch {
    my ($self) = @_;

    my $repo = SCM::Repository->new(repository_path => SCM_REPOSITORY);

    my $lroot   = $self->{lroot};
    my $move    = $self->{branch};

    my ($err, $head, $fhs);

    ($head, $err) = $repo->list_commits($move, undef, 1);
    return $self->error("Failed to retrieve last CSID on branch $move", $err)
        if $err;

    open my $fh, '>', \my $buf;

    ($fhs, $err) = $repo->export($move, $head->[0], { $lroot => $fh });
    return $self->error("Failed to retrieve file content for $lroot", $err)
        if $err;
    
    return $buf;
}

sub content_for_csid {
    my ($self) = @_;

    my $repo = SCM::Repository->new(repository_path => SCM_REPOSITORY);

    my $lroot   = $self->{lroot};
    my $csid    = $self->{csid};

    my $buf;

    my $bundle = File::Spec->catfile(SCM_QUEUE, SCM_DIR_DATA, 
                                     hashCSID2dir($csid), $csid);
    if (-e $bundle) {{
        # unpack bundle
        my $tempdir = tempdir(CLEANUP => 1);
        my $cs = Change::Set->new;
        unbundleChangeSet($cs, $bundle, $tempdir);
        open my $f, '<', "$tempdir/root/$lroot"
            or last;
        $self->{cs} = $cs;
        $buf = do { local $/; <$f> };
    }}

    return $buf if $buf;
    
    $self->{cs} = cs_from_csdb($csid, my $err);

    return $self->error("Could not find CS $csid", $err)
        if not defined $self->{cs};

    my $move = $self->{cs}->getMoveType;

    my ($head, $fhs);

    open my $fh, '>', \$buf;

    ($fhs, $err) = $repo->export($move, $csid, { $lroot => $fh });
    return $self->error("Failed to retrieve file content for $lroot", $err)
        if $err;

    return $buf;
}

sub error {
    my ($self, $msg, $err) = @_;

    print <<EOERROR;
<p style="color:red">
    $msg
</p>
<p>The error message was:<br/>$err</p>
EOERROR
    
    return;
}

sub cs_from_csdb {
    my $csid = shift;

    require SCM::CSDB::ChangeSet;

    my $csq = SCM::CSDB::ChangeSet->new(database => SCM_CSDB,
                                        driver   => SCM_CSDB_DRIVER);
    my $cs = $csq->getChangeSetDbRecord($csid);
    $_[1] = "$csid: No such change set" if not defined $cs;
    return $cs;
}

