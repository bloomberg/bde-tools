# vim:set ts=8 sts=4 noet:

package SCM::Info::MyCS;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;
use File::Basename;

use base qw/SCM::Info/;

use SCM::Symbols                    qw/SCM_CSDB SCM_CSDB_DRIVER
				       SCM_QUEUE SCM_DIR_DONE
				       $SCM_DIFF_PATH/;
use Change::Symbols                 qw/STATUS_NAME
                                       DEPENDENCY_TYPE_NONE
                                       DEPENDENCY_TYPE_ROLLBACK
                                       DEPENDENCY_TYPE_CONTINGENT
                                       DEPENDENCY_TYPE_DEPENDENT
                                       DEPENDENCY_TYPE_SIBLING/;
use SCM::Util			    qw/csdate2datetime/;
use SCM::Queue::Util                qw/csid_to_cs/;

use SCM::CSDB::Status;
use SCM::CSDB::ChangeSet;
use SCM::CSDB::History;

my @params = qw/csid close_button/;

my $csq_status	= SCM::CSDB::Status->new(database => SCM_CSDB,
       	     			        driver   => SCM_CSDB_DRIVER);
my $csq_cs	= SCM::CSDB::ChangeSet->new(dbh => $csq_status->dbh);
my $csq_hist	= SCM::CSDB::History->new(dbh => $csq_status->dbh);

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;

    $self->content_type;
    my $script = <<EOSCRIPT;
var COLUMN_MOVETYPE = -1;
var TABLE;
function doInit() {
    TABLE = document.getElementById('files').tBodies[0];
    colorize();
}
function colorize() {
    for (var i = 0; i < TABLE.rows.length; i++)
        TABLE.rows[i].bgColor = i % 2 ? '#e6e6fa' : '#fffff0';
}
EOSCRIPT
    my $sorter = $self->script('sortable', -offset => 1, 
                                           -movenames => [qw/move bugf emov stpr/]);

    my $style = $self->css( 
	    'td.title'	    => { background_color   => 'yellow',
				 font_family	    => 'sans-serif',
				 font_size	    => '110%', 
				 color		    => 'red', },
	    'td'	    => { font_size	    => '95%',
				 padding	    => '10px', },
	    'td.heading'    => { font_weight	    => 'bold', },
    );

    print start_html(-title     => "MyCS: $self->{csid}",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code =>  $style, },
                     -script    => [ 
                                     { -language => 'JAVASCRIPT',
                                       -code     => $script, }, 
                                     { -language => 'JAVASCRIPT',  
                                       -code     => $sorter, },
                                   ],
                     -onLoad    => 'doInit()',
    );

    my $cs = get_record($self->{csid});
    
    print $self->close_button(-text_align => 'center', -padding_top => '20px') 
        if $self->{close_button};

    print <<EOHTML;
    <h2 align="center">Details for Change Set with CSID $self->{csid}</h2>
EOHTML

    if (defined $cs) {
        $self->cs_details($cs);
    } else {
        print <<EOHTML;
    <p style="text-align:center">Change Set does not exist</p>
EOHTML
    }


    print end_html;

}

sub cs_details {
    my ($self, $cs) = @_;

    my $csid = $cs->getID;
    my $unix = $cs->getUser;
    my $move = $cs->getMoveType;
    my $stat = $cs->getStatus;	my $statname = $cs->getStatusName;
    my $stag = $cs->getStage;
    my $time = csdate2datetime($cs->getTime);
    my $tick = $cs->getTicket; $tick =~ s/([A-Z]+)(.*)/$1 $2/;
    my $mesg = $cs->getMessage; 
    
    for ($mesg) {
        s#^\s+##;
        s#\s+$##;
        s#\n#<br/>#g;
    }


    my $hist = $csq_hist->getChangeSetHistory($csid, 'resolve');
    my $update = '';
    if ($hist and @$hist) {
	$update = $hist->[-1][0];
    }

    my $diff = '';
#    if (-e "$SCM_DIFF_PATH/$self->{csid}.diff.html") {
#    $diff = "&nbsp;&nbsp;(<a href=\"info?command=Diff&presentation=html&csid=$self->{csid}\" " .
#	    "target=\"_blank\">View diff report</a>)";
#    }
    
    print <<EOTABLE;
    <table align="center" width="%100" border="1" rules="all">
        <tr>
            <td class="title">CSID</td><td>$csid $diff</td>
            <td class="title">Status</td><td>$stat - $statname</td>
        </tr>
        <tr>
            <td class="title">Creation time</td><td>$time</td>
            <td class="title">Unix Login</td><td>$unix</td>
        </tr>
        <tr>
            <td class="title">Update time</td><td>$update</td>
            <td class="title">Move type</td><td>$move</td>
        </tr>
        <tr>
            <td class="title">Associated ticket</td><td>$tick</td>
            <td class="title">Stage</td><td>$stag</td>
        <tr rowspan="2">
            <td class="title" valign="top">Description</td>
            <td colspan="3" valign="top">$mesg</td>
        </tr>
    </table>
    <p style="padding-top:20px"></p>
EOTABLE

    my $status_table    = $self->status_table($hist);
    my $dep_table       = $self->dep_table($csid);

    print <<EOTABLE;
    <table align="center" width="%100" border="0">
    <tr> <td valing="top">

    <!-- START OF STATUS-TABLE -->
$status_table
    <!-- END OF STATUS-TABLE -->

    </td> <td valign="top">

    <!-- START OF DEP-TABLE -->
$dep_table
    <!-- END OF DEP-TABLE -->
    
    </td></tr>

    </table>
    <p style="padding-top:20px"></p>
    <table class="sortable" id="files" align="center" 
           width="%100" border="1" rules="all">
	<thead>
        <tr>
            <th>File</th>
            <th>Source</th>
            <th>Destination</th>
            <th>Library</th>
            <th>Status</th>
	    <th>Sweep</th>
        </tr>
	</thead>
	<tbody>
EOTABLE

    for my $cf (sort by_lib_or_name $cs->getFiles) {
        my $fname   = basename($cf->getDestination);
        (my $lroot = $cf->getDestination) =~ s#^root/##;

        my $flink = "<a href=\"info?command=LookAt&presentation=html&" .
                    "lroot=$lroot&csid=$csid&close_button=1\" " . 
                    "target=\"_blank\">$fname</a>";

        my $src     = $cf->getSource;
        my $dest    = $cf->getDestination;
        my $lib     = $cf->getLibrary;
        my $status  = ucfirst lc $cf->getType;
	my $sweep   = sweep_eligible($cs, $cf->getDestination);
        print <<EOROW;
        <tr>
            <td>$flink</td>
            <td>$src</td>
            <td>$dest</td>
            <td>$lib</td>
            <td align="center">$status</td>
	    <td align="center">$sweep</td>
        </tr>
EOROW
    }
    print "        </tbody>\n    </table>\n";
}

sub status_table {
    my ($self, $hist) = @_;

    my $table = <<EOTABLE;
    <table class="sortable" id="hist" align="left" 
           border="1" rules="rows">
    <caption align="top">Status history</caption>
    <thead>
    <tr>
        <th>Date</th>
        <th>Status</th>
        <th>User</th>
    </tr>
    </thead>
    <tbody>
EOTABLE

    $table .= Tr(td([map $_ || '', @$_[0,1,3]])) for @$hist;
    $table .= <<EOTABLE;
	</td>
    </tbody>
    </table>
EOTABLE
    
    return $table;

}

sub dep_table {
    my ($self, $csid) = @_;

    my $table = <<EOTABLE;
    <table class="sortable" id="dep" align="right"
           border="1" rules="row">
    <caption align="top">Dependencies</caption>
    <thead>
    <tr>
        <th>CSID</th>
        <th>Type</th>
	<th>Status</th>
    </tr>
    </thead>
    <tbody>
EOTABLE

    my $deps = $csq_cs->getChangeSetDependencies($csid);
    if (not %$deps) {
        $table .= <<EOTABLE;
    <tr>
        <td colspan="3" align="center" nowrap="1">No dependencies</td>
    </tr>
    </tbody>
EOTABLE
    } else {
        for (sort keys %$deps) {
            $table .= Tr($self->td_dep($_, $deps)) . "\n";
        }
    }
    $table .= <<EOTABLE;
	</td>
    </tr>
    </tbody>
    </table>
EOTABLE
    return $table;
}

my %dependencies = (
        DEPENDENCY_TYPE_NONE()          => 'independent',
        DEPENDENCY_TYPE_ROLLBACK()      => 'rollback',
        DEPENDENCY_TYPE_CONTINGENT()    => 'contingent',
        DEPENDENCY_TYPE_DEPENDENT()     => 'dependent',
        DEPENDENCY_TYPE_SIBLING()       => 'sibling',
);

sub td_dep {
    my ($self, $csid, $deps) = @_;

    my $link	= "<a href=\"info?command=MyCS&presentation=html&" . 
		   "csid=$csid&close_button=1\" target=\"_blank\">$csid</a>";
    my $status	= $csq_status->getChangeSetStatus($csid);
    my $status_name = STATUS_NAME($status);

    return td({ -align  => 'center',
                -nowrap => 1, },
              [ $link, "$deps->{$csid} - $dependencies{$deps->{$csid}}", 
		"$status - $status_name" ]);
}

sub styles {
    qw/html/;
}

sub get_record {
    my $csid = shift;

    my $cs = csid_to_cs($csid);

    if (defined $cs) {
	my $status = $csq_status->getChangeSetStatus($csid);
	$cs->setStatus($status);
	return $cs;
    }

    $cs = $csq_cs->getChangeSetDbRecord($cs->getID);

    return $cs;
}

{
    my %sweep;
    sub sweep_eligible {
	my ($cs, $lroot) = @_;
	my $move = $cs->getMoveType;

	if (not %sweep) {
	    my $file = File::Spec->catfile(SCM_QUEUE, SCM_DIR_DONE,
					   "FILELIST.$move");
	    open my $fh, '<', $file
		or return 'N/A';
	    local *_;
	    while (<$fh>) {
		chomp;
		my ($csid, $file) = split;
		$sweep{$file} = $csid;
	    }
	}

	return ($sweep{$lroot} || '') eq $cs->getID ? 'Y' : '-';
    }
}

sub datetime2date {
    my $dt = shift;
    require HTTP::Date;
    my $time = HTTP::Date::str2time($dt);
    return scalar localtime($time);
}

sub by_lib_or_name {
    $a->getLibrary cmp $b->getLibrary ||
    basename($a->getDestination) cmp basename($b->getDestination);
}

1;
