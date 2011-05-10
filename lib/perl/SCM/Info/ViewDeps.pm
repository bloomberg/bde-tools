# vim:set ts=8 sts=4 noet:

package SCM::Info::ViewDeps;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;
use List::Util qw/sum/;

use base qw/SCM::Info/;

use SCM::Symbols            qw/$SCM_QUEUE
                               $SCM_DIR_PREQUEUE $SCM_DIR_QUEUE 
                               $SCM_DIR_PENDING $SCM_DIR_DONE 
                               $SCM_DIR_SWEPT $SCM_DIR_INPROG
                               SCM_CSDB SCM_CSDB_DRIVER/;
use Change::Symbols         qw/DEPENDENCY_TYPE_NONE
                               DEPENDENCY_TYPE_CONTINGENT
                               DEPENDENCY_TYPE_DEPENDENT
                               DEPENDENCY_TYPE_SIBLING
                               STATUS_NAME/;
use SCM::Queue::Util        qw/get_job_by_csid/;

use SCM::CSDB::Status;
use SCM::CSDB::ChangeSet;

my @params = qw/csid close_button refresh/;

my ($csq_status, $csq_cs);

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;

    $csq_status = SCM::CSDB::Status->new(database => SCM_CSDB,
					 driver	  => SCM_CSDB_DRIVER);
    $csq_cs = SCM::CSDB::ChangeSet->new(dbh => $csq_status->dbh);
}

sub handle {
    my ($self) = @_;

    $self->content_type;

    my $style = <<EOCSS;
h2 {
    font-family:courier;
}
caption {
    font-size:100%;
}
table {
    border-collapse:collapse;
}
th {
    font-family:sans-serif;
    text-align:center;
    font-size:120%;
    padding:10px;
    background-color:yellow;
    color:red;
}
td {
    font-size:90%;
    font-family:Arial,Helvetica;
    font-weight:550;
    padding:5px;
}
EOCSS

    print start_html(-title     => "Dependencies for $self->{csid}",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code => $style, },
                     $self->refresh,
    );

    print $self->close_button(-text_align => 'center', -padding_top => '20px')
        if $self->{close_button};

    $self->dependencies;

    print end_html;

}

sub dependencies {
    my ($self) = @_;

    my $dep = $csq_cs->getChangeSetDependencies($self->{csid});

    print <<EODEPS;
    <h2 align="center">Dependency summary for $self->{csid}</h2>
    <table align="center" border="0" frame="void">
        <tr>
            <td valign="top"><!-- DEPENDENCY_TYPE_CONTINGENT -->
@{[ $self->deptable($dep, DEPENDENCY_TYPE_CONTINGENT, 'left') ]}
            </td>
            <td valign="top"><!-- DEPENDENCY_TYPE_DEPENDENT -->
@{[ $self->deptable($dep, DEPENDENCY_TYPE_DEPENDENT, 'right') ]}
            </td>
        </tr>
        <tr>
            <td valign="top"><!-- DEPENDENCY_TYPE_NONE -->
@{[ $self->deptable($dep, DEPENDENCY_TYPE_NONE, 'left') ]}
            </td>
            <td valign="top"><!-- DEPENDENCY_TYPE_SIBLING -->
@{[ $self->deptable($dep, DEPENDENCY_TYPE_SIBLING, 'right') ]}
            </td>
        </tr>
    </table>
EODEPS

}

my %caption = (
        DEPENDENCY_TYPE_NONE()          => 'Independent of',
        DEPENDENCY_TYPE_DEPENDENT()     => 'Dependent on',
        DEPENDENCY_TYPE_CONTINGENT()    => 'Contingencies',
        DEPENDENCY_TYPE_SIBLING()       => 'Siblings',
);

sub deptable {
    my ($self, $dep, $type, $align) = @_;

    my @deps;
    while (my ($csid, $t) = each %$dep) {
        push @deps, $csid if $t eq $type;
    }

    my $table = <<EOTABLE;
            <table align="$align" border="1" rules="all">
            <caption align="top" class="explanation">
                $caption{$type}
            </caption>
	    <thead>
            <tr>
                <th>CSID</th>
                <th>Status</th>
                <th nowrap="1">Queue stage</th>
            </tr>
	    </thead>
	    <tbody>
EOTABLE

    if (not @deps) {
        $table .= <<EOTABLE
            <tr>
                <td colspan="3" align="center">No dependencies</td>
            </tr>
	    </tbody>
EOTABLE
    } else {
        for my $csid (@deps) {
            my $job = get_job_by_csid($csid);
            my $csidlk = $self->td_csid($csid);
            my $status = $self->td_status($job);
            my $qstage = $self->td_stage($job);
            $table .= <<EOTABLE
            <tr>
                $csidlk
                $status
                $qstage
            </tr>
EOTABLE
        }
    }

    $table .= <<EOTABLE;
	    </tbody>
	</table>
EOTABLE
    return $table;
}

sub dir2stage {
    for (shift) {
        m#^$SCM_QUEUE/$SCM_DIR_PREQUEUE#    and return 0;
        m#^$SCM_QUEUE/$SCM_DIR_QUEUE#       and return 1;
        m#^$SCM_QUEUE/$SCM_DIR_PENDING#     and return 2;
        m#^$SCM_QUEUE/$SCM_DIR_INPROG#      and return 3;
        m#^$SCM_QUEUE/$SCM_DIR_DONE#        and return 4;
	m#^$SCM_QUEUE/$SCM_DIR_SWEPT#	    and return 5;
    }
}
my @stages = (
    'Prequeued', 'Queued', 
    'Pending', 'In Progress', 
    'Committed', 'Swept'
);

sub td_csid {
    my ($self, $csid) = @_;
    my $url = "info?command=MyCS&presentation=html&" . 
              "csid=$csid&close_button=1";
    return td("<a href=\"$url\" target=\"_blank\">$csid</a>");
}

sub td_status {
    my ($self, $job) = @_;
    my $stage = dir2stage($job->dir);
    my $status;
    if ($stage > 2) {
        $status = $job->status;
    } else {
        $status = $csq_status->getChangeSetStatus($job->id);
    }
    return td("$status - " . STATUS_NAME($status));
}

sub td_stage {
    my ($self, $job) = @_;
    my $stage = dir2stage($job->dir);
    return td("$stage - $stages[$stage]");
}


sub styles {
    qw/html/;
}

1;
