# vim:set ts=8 sts=4 sw=4 noet:

package SCM::Info::StageSummary;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;
use List::Util qw/sum/;

use base qw/SCM::Info/;

use SCM::Symbols            qw/SCM_QUEUE SCM_DIR_DATA
                               $SCM_DIR_PREQUEUE
                               $SCM_QUEUE $SCM_DIR_QUEUE $SCM_DIR_PENDING
                               $SCM_DIR_DONE $SCM_DIR_INPROG/;
use SCM::Queue::Util        qw/get_staged_jobs get_sweep_targets/;

my @params = qw/close_button refresh/;

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;

    $self->content_type;

    my $style = <<EOCSS;

td {
    font-size:100%;
    font-family:Arial,Helvetica;
    font-weight:550;
    padding:10px;
}

td.heading {
    font-weight:bold;
}

EOCSS

    print start_html(-title     => "Staged files summary",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code  => [ $self->css, $style, ], },
                     $self->refresh,
    );

    print $self->close_button(-text_align => 'center', -padding_top => '20px') 
        if $self->{close_button};

    $self->summary;

    print end_html;

}

sub summary {
    my ($self) = @_;

    my %files;
    my %unique;
    my %sweep;
    my %stage;

    my %movetype;

    for my $job (get_staged_jobs()) {
        my $move = $job->cs->getMoveType;
        $movetype{$job->id} = $move;
        $stage{stage($job->dir)}++;
        for my $f ($job->cs->getFiles) {
            $unique{$move}{$f} = 1;
            $files{$move}++;
        }
    }

    for my $move (qw/move bugf emov/) {
        $sweep{$move}++ for get_sweep_targets($move);
    }

    $stage{$_} ||= 0 for qw/P N Q C/;

    print <<EOSUMMARY;
    <h2 align="center">Summary for staged files</h2>
    <table align="center" border="1" frame="void">
        <tr>
            <td></td>
            <td class="heading">Files</td>
            <td style="font-weight:bold">Unique<br/>files</td>
            <td style="font-weight:bold">Sweep<br/>targets</td>
            <td style="background-color:#000000">&nbsp;</td>
            <td colspan="4" align="center" 
                style="font-weight:bold">Queue stage</td>
        </tr>
        <tr>
            <td class="move" style="font-weight:bold">Move</td>
            <td align="center">$files{move}</td>
            <td align="center">@{[scalar keys %{$unique{move}}]}</td>
            <td align="center">$sweep{move}</td>
            <td style="background-color:#000000"></td>
            <td style="font-weight:bold">P</td>
            <td style="font-weight:bold">Q</td>
            <td style="font-weight:bold">N</td>
            <td style="font-weight:bold">C</td>
        </tr>
        <tr>
            <td class="bugf" style="font-weight:bold">Bugf</td>
            <td class="bugf" align="center">$files{bugf}</td>
            <td class="bugf" align="center">@{[scalar keys %{$unique{bugf}}]}</td>
            <td class="bugf" align="center">$sweep{bugf}</td>
            <td style="background-color:#000000"></td>
            <td align="center">$stage{P}</td>
            <td align="center">$stage{Q}</td>
            <td align="center">$stage{N}</td>
            <td align="center">$stage{C}</td>
        </tr>
        <tr>
            <td class="emov" style="font-weight:bold">Emov</td>
            <td class="emov" align="center">$files{emov}</td>
            <td class="emov" align="center">@{[scalar keys %{$unique{emov}}]}</td>
            <td class="emov" align="center">$sweep{emov}</td>
            <td style="background-color:#000000"></td>
        </tr>
        <tr>
            <td class="stpr" style="font-weight:bold">Stpr</td>
            <td class="stpr" align="center">$files{stpr}</td>
            <td class="stpr" align="center">@{[scalar keys %{$unique{stpr}}]}</td>
            <td class="stpr" align="center">N/A</td>
            <td style="background-color:#000000"></td>
        </tr>
        <tr>
            <td></td>
            <td align="center">@{[sum values %files]}</td>
            <td align="center">@{[sum map values %{$unique{$_}}, keys %unique]}</td>
            <td align="center">@{[sum values %sweep]}</td>
            <td style="background-color:#000000"></td>
        </tr>
    </table>
EOSUMMARY

}

sub stage {
    my $dir = shift;
    for ($dir) {
        m#^$SCM_QUEUE/$SCM_DIR_PREQUEUE#    and return 'P';
        m#^$SCM_QUEUE/$SCM_DIR_INPROG#      and return 'P';
        m#^$SCM_QUEUE/$SCM_DIR_QUEUE#       and return 'Q';
        m#^$SCM_QUEUE/$SCM_DIR_PENDING#     and return 'N';
        m#^$SCM_QUEUE/$SCM_DIR_DONE#        and return 'C';
    }
}

sub styles {
    qw/html/;
}

1;
