# vim:set ts=8 sts=4 noet:

package SCM::Info::StagedBy;

use warnings;
use strict;

use CGI     qw/param start_html end_html Tr td meta/;
use HTTP::Date;
use POSIX   qw//;

use base qw/SCM::Info/;

use SCM::Symbols	qw/$SCM_QUEUE
			   $SCM_DIR_PREQUEUE $SCM_DIR_QUEUE
			   $SCM_DIR_PENDING $SCM_DIR_DONE
                           $SCM_DIR_INPROG $SCM_DIR_SWEPT
                           SCM_CSDB SCM_CSDB_DRIVER/;
use Change::Symbols	qw/STATUS_NAME STATUS_ROLLEDBACK 
			   MOVE_IMMEDIATE
			   DEPENDENCY_TYPE_DEPENDENT
			   DEPENDENCY_TYPE_CONTINGENT
			   FILE_IS_UNCHANGED FILE_IS_REVERTED/;
use SCM::Queue::Util	qw/get_staged_jobs get_job_by_csid/;

use SCM::CSDB::Status;
use SCM::CSDB::ChangeSet;

# There has been dissent on using single-letter abbreviation
# for the movetype or the full name, therefore put them in 
# some pseudeo-constant
my $MOVEHEAD = 'Move';
my $MOVE = 'move';
my $BUGF = 'bugf';
my $EMOV = 'emov';
my $STPR = 'stpr';

my @params = qw/date user csid movetype status sweep dep file lib
                group days refresh queue_column col
                cols filters mintsp mincsid maxtsp robo
		bigcs/;

sub init {
    my ($self) = @_;
   
    for (@params) {
	my $p = param($_);
	$self->{$_} = defined $p ? $p : ''
    }

    $self->{dataoffset} = 2;
    $self->{bigcs} ||= 20;

    $self->init_csdb;
}

sub handle {
    my ($self) = @_;

    if ($self->presentation eq 'user') {
	return $self->user;
    }

    my @maps;
    for (qw/move emov bugf/) {
        my $file = File::Spec->catfile($SCM_QUEUE, 
                                       $SCM_DIR_DONE, 
                                       "FILELIST.$_");
        push @maps, committed_file_to_hash($file);
    }

    my @jobs;
    for my $job (sort reverse_by_id get_staged_jobs()) {
        
        next if not defined $job;
        next if $self->filter_this($job);

        push @jobs, $job;
    }

    $self->content_type;

    return $self->robo_view(\@maps, @jobs) if $self->{robo};

    if ($self->presentation eq 'html') {
        $self->html(\@jobs, \@maps);
    } elsif ($self->presentation eq 'user') {
        $self->user(\@jobs, \@maps);
    }
}

sub filter_this {
    my ($self, $job) = @_;

    # The following filters apply to whole jobs/changesets
    return 1 if $job->cs->isBregMove or
		$job->cs->isStructuralChangeSet;
    return 1 if $self->{group} and
                $job->cs->getGroup !~ /$self->{group}/i;
    return 1 if $self->{queue} and 
                dir2stage($job->dir) ne $self->{queue};
    return 1 if $self->{date} and 
                dir2stage($job->dir) !~ /$self->{date}/i;
    return 1 if $self->{user} and 
                $job->cs->getUser !~ /$self->{user}/i;
    return 1 if $self->{csid} and 
                $job->id !~ /$self->{csid}/i;
    return 1 if $self->{movetype} and 
                $job->cs->getMoveType !~ /$self->{movetype}/;
    return 1 if $self->{status} and 
                get_status($job) !~ $self->{status};
    return 1 if $self->{mincsid} and
                $job->id lt $self->{mincsid};
    return 1 if $self->{mintsp} and
                $job->cs->getTsp < $self->{mintsp};
    return 1 if $self->{maxtsp} and
                $job->cs->getTsp > $self->{maxtsp};

    return 0;
}

sub html {
    my ($self, $jobs, $maps) = @_;

    my ($columns, $filters) = ('') x 2;
    if ($self->{cols}) {
        my @cols = split //, $self->{cols};
        for (0 .. $#cols) {
            $columns .= <<EOCOLS;
    document.columns['C$_'].checked = $cols[$_];
    toggleColumn(document.columns['C$_']);
EOCOLS
        }
        $columns = <<EOCOLS;
    /* auto-generated based on 'cols' paramter */
$columns
EOCOLS
    }
    
    if ($self->{filters}) {
        my @filternames = qw/queue date user csid movetype status
                         sweep dependency file library/;
        my @filters = $self->{filters} =~ /\$\d=([^\$]*)/g;
        for (0 .. $#filters) {
            (my $value = $filters[$_]) =~ s/\\/\\\\/g;
            $value =~ s/'/\\'/;
            $filters .= <<EOFILTERS;
    document.Filters['$filternames[$_]'].value = LAST[$_] = '$value';
EOFILTERS
        }
        $filters = <<EOFILTERS;
    /* auto-generated based on 'filters' parameter */
$filters
    filterBy();
EOFILTERS
    }

    my $static_parms = $self->params(
	    qw/date user csid movetype status sweep dep file lib
                group days refresh col mintsp mincsid maxtsp robo bigcs/
    );

    my $script = <<EOJSCRIPT;

var STATIC_PARMS = '$static_parms';

var COLUMN_QUEUE    = 0;
var COLUMN_DATE     = 1;
var COLUMN_USER     = 2;
var COLUMN_CSID     = 3;
var COLUMN_MOVETYPE = 4;
var COLUMN_STATUS   = 5;
var COLUMN_SWEEP    = 6;
var COLUMN_DEP      = 7;
var COLUMN_FILE     = 8;
var COLUMN_LIBRARY  = 9;

/* The property 'innerText' only works IExplorer
   and not Firefox even though I believe it should.
   We therefore use innerHTML which seems to make
   both happy. */

function IT (elem) {
    if (elem.childNodes[0].nodeType == 3) {
        return elem.innerHTML;
    }
    return IT(elem.childNodes[0]);
}

var TABLE;
var LAST = new Array();
function doInit() {
    TABLE = document.getElementById('staged_by');
    colorize();
    @{[ !$self->{queue_column}  ? q#
    /* If anyone is interested in seeing this column,
       call this script with queue_column=1 */
/*    for (var i = 0; i < TABLE.rows.length; i++) {
        TABLE.rows[i].cells[COLUMN_QUEUE].style.display='none'; # : '' ]}
	LAST[i] = '';
      }
*/
    
    var columns = document.columns;
    var row = TABLE.rows[0];
    for (var i = COLUMN_QUEUE; i <= COLUMN_LIBRARY; i++)
        if (row.cells[i].style.display == 'none')
            columns['C'+i].checked = 0;
        else
            columns['C'+i].checked = 1;

$columns
$filters
}

function colorize() {
    var j = 0;
    var bod = TABLE.tBodies[0];
    for (var i = 0; i < bod.rows.length; i++) {
	if (bod.rows[i].style.display == 'none')
	    continue;
        bod.rows[i].bgColor = j++ % 2 ? '#e6e6fa' : '#fffff0';
    }
}

var COLS = new Object ();
COLS['queue']       = COLUMN_QUEUE;
COLS['date']        = COLUMN_DATE;
COLS['user']        = COLUMN_USER;
COLS['csid']        = COLUMN_CSID;
COLS['movetype']    = COLUMN_MOVETYPE;
COLS['status']      = COLUMN_STATUS;
COLS['sweep']       = COLUMN_SWEEP;
COLS['dependency']  = COLUMN_DEP;
COLS['file']        = COLUMN_FILE;
COLS['library']     = COLUMN_LIBRARY;

function showAll() {
    for (var i = COLUMN_QUEUE; i <= COLUMN_LIBRARY; ++i) 
        LAST[i] = '';

    for (var i = $self->{dataoffset}; i < TABLE.rows.length; i++)
        TABLE.rows[i].style.display = '';

    var fields = new Array('queue', 'date', 'user', 'csid', 'movetype', 
                           'status', 'sweep', 'file', 'library');
    for (var i in fields)
        document.Filters[i].value = '';
}

function checkChange(el) {
    var idx = el.parentNode.cellIndex;
    if (el.value == LAST[idx])
        return;
    LAST[idx] = el.value;
    filterBy();
}

function rowMatches(row) {
    for (c in COLS) {
        var idx = COLS[c];
        LAST[idx] = document.Filters[c].value;
        if (!document.Filters[c].value)
            continue;
        var re = new RegExp(document.Filters[c].value, 'i');
        if (!IT(row.cells[COLS[c]]).match(re))
            return false;
    }
    return true;
}

function filterBy() {
    for (var i = 0; i < TABLE.tBodies[0].rows.length; i++)
        if (rowMatches(TABLE.tBodies[0].rows[i]))
            TABLE.tBodies[0].rows[i].style.display = '';
        else
            TABLE.tBodies[0].rows[i].style.display = 'none';
    colorize();
}

function checkPress(el, e) {
    var keycode;
    if (window.event)
        keycode = window.event.keyCode;
    else if (e)
        keycode = e.which;
    else
        return;
   
    var idx = el.parentNode.cellIndex;
    if (keycode != 13 || el.value == LAST[idx])
        return;

    LAST[idx] = el.value;
    filterBy();
}

function toggleColumn(el) {
    var st = el.checked ? '' : 'none';
    var col = el.name.charAt(1);
    for (var i = 0; i < TABLE.rows.length; i++) 
        TABLE.rows[i].cells[col].style.display = st;
}

function doSummary() {

    var addr = "@{[ "info?command=StageSummary&" . 
                    $self->params(qw/presentation/) ]}&close_button=1&refresh=10";

    window.open(addr, "Summary", "menubar=no,width=600,height=400");
}

function doRefresh() {
    var cols = 'cols=';
    var filters = 'filters=';

    /* serialize visibility of columns */
    for (var i = COLUMN_QUEUE; i <= COLUMN_LIBRARY; ++i) {
        if (document.getElementsByName('C' + i)[0].checked) 
            cols += 1;
        else
            cols += 0;
    }

    /* serialize filters */
    for (var i = COLUMN_QUEUE; i <= COLUMN_LIBRARY; ++i)
        filters += '\$' + i + '=' + escape(LAST[i]);

    var url = 'info?command=StagedBy';
    url += "&presentation=html&" + STATIC_PARMS + '&' 
				 + cols + '&' 
				 + filters;
    location.href = url;
}

function doExcerpt(col) {

    var url = 'info?command=StagedBy&presentation=html&robo=1';
    url += '&col=' + col;

    /* build filter params */
    for (var i in COLS)
        url += '&' + i + '=' + escape(document.Filters[i].value);

    window.open(url, "roboview", "menubar=no,width=300,height=600,scrollbars=yes");
}

var helpwin;
function doHelp(anchor) {
   
    if (!helpwin || helpwin.closed) {
	var url = 'info?command=Help&presentation=html' +
		  '&page=StagedBy' + anchor;
	helpwin = window.open(url, 'help', 
			      "toolbar=no,height=600,width=500,scrollbars=yes");
	return false;
    }
    
    return true;
}

EOJSCRIPT

    my $sorter = $self->script('sortable', -offset    => $self->{dataoffset},
                                           -movenames => [ $MOVE, $BUGF, $EMOV,
                                                           $STPR ]);

    print start_html(-title     => 'Staged files',
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code   => $self->css, },
                     -script    => [ 
                                     { -language => 'JAVASCRIPT',
                                       -code     => $script, }, 
                                     { -language => 'JAVASCRIPT',  
                                       - code    => $sorter, },
                                   ],
                     -onLoad    => 'doInit()',
                     $self->refresh,
    );

    my $host = $self->host;

    my $help = "info?command=Help&presentation=html&page=StagedBy";

    print <<EOTABLE;
    <a name="top"><h2 align="center">Staged files on $host</h2></a>
    <h4 align="center">(per @{[scalar localtime]})</h4>
    <form name="columns">
    <fieldset>
    <legend>Visible columns</legend>
    <table align="center" width="80%">
    <tr>
        <td>
            <label for="C0">Queue stage:</label>
            <input type="checkbox" name="C0" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C1">Date:</label>
            <input type="checkbox" name="C1" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C2">User:</label>
            <input type="checkbox" name="C2" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C3">CSID:</label>
            <input type="checkbox" name="C3" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C4">Movetype:</label>
            <input type="checkbox" name="C4" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C5">Status:</label>
            <input type="checkbox" name="C5" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C6">In build:</label>
            <input type="checkbox" name="C6" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C7">Dependencies:</label>
            <input type="checkbox" name="C7" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C8">File:</label>
            <input type="checkbox" name="C8" onclick="toggleColumn(this)">
        </td>
        <td>
            <label for="C9">Library:</label>
            <input type="checkbox" name="C9" onclick="toggleColumn(this)">
        </td>
    </tr>
    </table>
    </fieldset>
    </form>
    <table align="center">
    <colgroup>
	<col width="35%">
	<col>
	<col>
	<col>
	<col>
	<col width="35%">
    </colgroup>
    <form>
        <tr>
	    <td align="left" style="font-size:small">
		Click on column header to sort table
	    </td>
            <td><input type="button" value="Filter" onclick="filterBy()"></td>
            <td><input type="button" value="Show all" onclick="showAll()"></td>
            <td><input type="button" value="Summary" onclick="doSummary()"></td>
            <td><input type="button" value="Refresh" onclick="doRefresh()"></td>
	    <td align="right">
		<a href="$help#help" style="text-decoration:none;font-size:x-large"
		   onClick="return doHelp('#help');">?</a>
	    </td>
        </tr>
    </form>
    </table>

    <table id="staged_by" width="100%" rules="all">
	<thead>
        <tr>
            <th title="Queue stage" nowrap="nowrap" align="center">
		<a href="#" onclick="ts_resortTable(this,0);return false;">
		<span class="sortarrow"></span>Q</a>
	    </th>
            <th align="center">
		<a href="#" onclick="ts_resortTable(this,1);return false;">
		<span class="sortarrow"></span>Date</a>
	    </th>
            <th align="center">
		<a href="#" onclick="ts_resortTable(this,2);return false;">
		<span class="sortarrow"></span>User</a>
	    </th>
            <th align="center">
		<a href="#" onclick="ts_resortTable(this,3);return false;">
		<span class="sortarrow"></span>CSID</a>
	    </th>
	    <th align="center">
		<a href="#" onclick="ts_resortTable(this,4);return false;">
		<span class="sortarrow"></span>$MOVEHEAD</a>
	    </th>    
	    <th align="center" title="Status">
		<a href="#" onclick="ts_resortTable(this,5);return false;">
		<span class="sortarrow"></span>S</a>
	    </th>
            <th align="center" title="Included in next build">
		<a href="#" onclick="ts_resortTable(this,6);return false;">
		<span class="sortarrow"></span>B</a>
	    </th>
            <th align="center" title="Status of least advanced dependency">
		<a href="#" onclick="ts_resortTable(this,7);return false;">
		<span class="sortarrow"></span>D</a>
	    </th>
	    <th align="center">
		<a href="#" onclick="ts_resortTable(this,8);return false;">
		<span class="sortarrow"></span>File</a>
	    </th>
            <th align="center">
		<a href="#" onclick="ts_resortTable(this,9);return false;">
		<span class="sortarrow"></span>Library</a>
	    </th>
        </tr>
        <tr>
        <form name="Filters">
            <th>
                <select name="queue" size="1" onchange="checkChange(this)">
                    <option value=""></option>
                    <option value="P">P</option>
                    <option value="Q">Q</option>
                    <option value="N">N</option>
                    <option value="C">C</option>
                </select>
            </th>
            <th>
                <input type="text" name="date" size="8"
                       onkeypress="checkPress(this, event)">
            </th>
            <th>
                <input type="text" name="user" size="8"
                       onkeypress="checkPress(this, event)">
            </th>
            <th nowrap="nowrap">
                <input type="text" name="csid" 
                       onkeypress="checkPress(this, event)">
                <a href="javascript:doExcerpt('csid')"
                   style="text-decoration:underline; font-size:smaller"
                   title="Unique list of CSIDs">L</a>
            </th>
            <th>
                <select name="movetype" size="1" onchange="checkChange(this)">
                    <option value=""></option>
                    <option value="$MOVE">$MOVE</option>
                    <option value="$BUGF">$BUGF</option>
                    <option value="$EMOV">$EMOV</option>
                    <option value="$STPR">$STPR</option>
                </select>
            </th>
            <th>
                <select name="status" size="1" onchange="checkChange(this)">
                    <option value=""></option>
                    <option value="S">S</option>
                    <option value="N">N</option>
                    <option value="A">A</option>
                    <option value="P">P</option>
                    <option value="C">C</option>
                </select>
            </th>
            <th>
                <select name="sweep" size="1" onchange="checkChange(this)">
                    <option value=""></option>
                    <option value="Y">Y</option>
		    <option value="E">E</option>
                    <option value="-">-</option>
                </select>
            </th>
            <th>
                <select name="dependency" size="1" onchange="checkChange(this)">
                    <option value=""></option>
                    <option value="-">-</option>
                    <option value="N">N</option>
                    <option value="A">A</option>
                    <option value="P">P</option>
                    <option value="C">C</option>
                </select>
            </th>
            <th nowrap="nowrap">
                <input type="text" name="file" size="25"
                       onkeypress="checkPress(this, event)">
                <a href="javascript:doExcerpt('file')"
                   style="text-decoration:underline; font-size:smaller"
                   title="Unique list of files">L</a>
            </th>
            <th nowrap="nowrap">
                <input type="text" name="library"
                       onkeypress="checkPress(this, event)">
                <a href="javascript:doExcerpt('lib')"
                   style="text-decoration:underline; font-size:smaller"
                   title="Unique list of libraries">L</a>
            </th>
        </form>
        </tr>
	</thead>
	<tbody>
EOTABLE
    
    for my $job (@$jobs) {

        my $csid = $job->id;
        my $dep_td = $self->td_dep($job);

	my $num_files = () = $job->cs->getFiles;
	my %bigfile ;
	%bigfile = (-style => 'background-color:#ffcccc',
		    -title => "Big change set: >$self->{bigcs} files")
	    if $num_files > $self->{bigcs};

        for my $file ($job->cs->getFiles) {
	    
            my $sweep   = file2sweep($file, $csid, $maps);
            next if $self->{sweep} and $sweep ne $self->{sweep};

            my $leaf    = $file->getLeafName;
            next if $self->{file} and $leaf !~ /$self->{file}/;

            my $lib     = $file->getLibrary;
            next if $self->{lib} and $lib !~ /$self->{lib}/;

            my $dest    = $file->getDestination; $dest =~ s#^root/##;

            my $link = "<a href=\"info?command=LookAt&presentation=html&" . 
                       "lroot=$dest&csid=$csid&close_button=1\" " . 
                       "target=\"_blank\">$leaf</a>";
            my $csidlk = "<a href=\"info?command=MyCS&presentation=html&" . 
                         "csid=$csid&close_button=1\" target=\"_blank\">$csid</a>";

	    my ($color, %title) = '';
	    if ($file->isNew) {
		$color = 'background-color:#FFCCCC';
		%title = (-title => 'File is new');
	    } elsif ($file->getType eq FILE_IS_UNCHANGED) {
		$color = 'background-color:#EEE8AA';
		%title = (-title => 'File is unchanged');
	    } elsif ($file->getType eq FILE_IS_REVERTED) {
		$color = 'background-color:#FF3333';
		%title = (-title => 'File is reverted');
	    }

            print Tr( td_stage($job), td_date($job),
                      td($job->cs->getUser),
		      td({ %bigfile }, $csidlk),
                      td_move($job->cs->getMoveType), td_status($job->status),
                      td_sweep($file, $csid, $maps, $job->cs->getMoveType), $dep_td,
                      td({ -style => "white-space:nowrap;$color",
			   %title }, $link),
		      td({ -style => 'white-space:nowrap;' }, $lib),
            ), "\n";  
        }
    }
    print <<EOTABLE;
    </tbody>
    <tfoot>
    <tr>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
	<th>&nbsp;</th>
    </tr>
    </tfoot>
</table>
EOTABLE

    print end_html();
}

sub user {
    my ($self, $jobs, $maps) = @_;

    print join "\t", qw/qstage|Q|1 date|Date|19 user|User|8 
                        csid|CSID|18 move|Move|4
                        status|S|1 build|B|1 dep|D|1 file|File|40 
                        lib|Library|20/;
    print "\n";

    for my $job (@$jobs) {
        my $qstage          = dir2stage($job->dir);
        my $date            = job2date($job);
        my $user            = $job->cs->getUser;
        my $csid            = $job->id;
        my $move            = $job->cs->getMoveType;
        my $status          = get_status($job);
        my (undef, $dep)    = job2dep($job); 
        $dep ||= '-';
        for my $file ($job->cs->getFiles) {

            my $sweep   = file2sweep($file, $job->id, $maps);
            next if $self->{sweep} and $sweep ne $self->{sweep};

            my $leaf    = $file->getLeafName;
            next if $self->{file} and $leaf !~ /$self->{file}/;

            my $lib     = $file->getLibrary;
            next if $self->{lib} and $lib !~ /$self->{lib}/;
            
            print join "\t", $qstage, $date, $user, $csid,
                             $move, $status, $sweep, $dep,
                             $leaf, $lib;
            print "\n";
        }
    }
}

sub robo_view {
    my ($self, $maps, @jobs) = @_;

    my %uniq;

    for my $job (@jobs) {
        for my $file ($job->cs->getFiles) {
            my $sweep   = file2sweep($file, $job->id, $maps);
            next if $self->{sweep} and $sweep ne $self->{sweep};

            my $leaf    = $file->getLeafName;
            next if defined $self->{file} and $leaf !~ /$self->{file}/;

            my $lib     = $file->getLibrary;
            next if defined $self->{lib} and $lib !~ /$self->{lib}/;

            $uniq{csid}{$job->id} = $uniq{file}{$leaf} = $uniq{lib}{$lib} = 1;
        }
    }

    my $col = $self->{col};

    if ($self->presentation eq 'html') {
        print start_html(-title     => 'Staged files',
                         -author    => 'tvonparseval@bloomberg.net',
                         -style     => $self->css . '/style.css',
                         $self->refresh,
        );

        print $self->close_button(-text_align => 'center', 
                                  -padding_bottom => '30px',);

        print <<EOTABLE;
    <table align="left" width="50%" border="0" style="padding-top:20px">
    @{[ map "<tr><td align=\"left\">$_</td></tr>\n", sort keys %{$uniq{$col}} ]}
    </table>
EOTABLE
        
        print end_html();
    }
}

sub styles {
    qw/user html/;
}

sub committed_file_to_hash {
    my $file = shift;

    open FH, '<', $file or return;

    my %files;
    local *_;
    while (<FH>) {
        chomp;
        my ($csid, $lroot) = split /\t/;
        $files{$lroot} = $csid;
    }
    close FH;

    return \%files;
}

{
    my ($csq_status, $csq_cs);
    sub init_csdb {
	$csq_status = SCM::CSDB::Status->new(database  => SCM_CSDB,
			                     driver    => SCM_CSDB_DRIVER);
	$csq_cs = SCM::CSDB::ChangeSet->new(dbh => $csq_status->dbh);
    }

    sub get_status {
        my $job = shift;

        # statuses in the filename of jobs in commited/ 
        # pending/, inprogress/ and done/ are reliable
        return $job->status 
            if  $job->dir =~ m#$SCM_DIR_QUEUE/?$# or
                $job->dir =~ m#$SCM_DIR_PENDING/?$# or
                $job->dir =~ m#$SCM_DIR_INPROG/?$# or
                $job->dir =~ m#$SCM_DIR_DONE/?$#;
        

        my $s = $csq_status->getChangeSetStatus($job->id);
        $job->status($s);

        return $s;
    }

    sub get_deps {
        my $job = shift;

        my $deps = $csq_cs->getChangeSetDependencies($job->id);
        my $re = '(?:' . DEPENDENCY_TYPE_CONTINGENT . '|' . 
                         DEPENDENCY_TYPE_DEPENDENT . ')';
        my @deps;
        while (my ($id, $type) = each %$deps) {
            push @deps, $id if $type =~ /$re/;
        }
        
        return @deps;
    }
}

sub dir2stage {
    for (shift) {
        m#^$SCM_QUEUE/$SCM_DIR_PREQUEUE#    and return 'P';
        m#^$SCM_QUEUE/$SCM_DIR_QUEUE#       and return 'Q';
        m#^$SCM_QUEUE/$SCM_DIR_PENDING#     and return 'N';
        m#^$SCM_QUEUE/$SCM_DIR_INPROG#      and return 'N';
        m#^$SCM_QUEUE/$SCM_DIR_DONE#        and return 'C';
    }
}

sub job2date {
    my $job = shift;
    return POSIX::strftime("%Y/%m/%d %H:%M:%S", localtime($job->cs->getTsp));
}

sub file2sweep {
    my ($file, $csid, $maps) = @_;
    my $dest = $file->getDestination;
    return 'Y' if grep $_->{$dest} && $_->{$dest} eq $csid, @$maps;
    return '-';
}

my %title = (
    P   => '0 - Prequeued',
    Q   => '1 - Queued',
    N   => '2 - Pending',
    C   => '3 - Committed',
);

sub td_stage {
    my $job = shift;

    my $stage = dir2stage($job->dir);
    return td({ -align => 'center',  
                -title => $title{$stage},}, 
                $stage);
}

sub td_date {
    my $job = shift;
    return td(job2date($job));
}

sub td_move {
    my $move = shift;

    my @class = $move ne 'move' ? (-class => $move) : ();

    return td({ @class, -align => 'center', }, $move);
}

sub td_status {
    my $status = shift;
    return td({ -align => 'center',
                -title => STATUS_NAME($status),}, 
                $status);
}

my %move2index = qw/move 0 emov 1 bugf 2/;
sub td_sweep {
    my ($file, $csid, $maps, $move) = @_;

    my $lroot = $file->getDestination;
    
    my $idx = $move2index{$move};
    my ($title, $text) = ('Not included in sweep', '-');

    if ($move eq MOVE_IMMEDIATE) {
	$title = 'Included in sweep';
	$text = 'Y';
    } elsif (exists $maps->[$idx]{$lroot}) {
	if ($maps->[$idx]{$lroot} eq $csid) {
	    $title = 'Included in sweep';
	    $text  = 'Y';
	} else {
	    $title = 'Eclipsed by ' . $maps->[$idx]{$lroot};
	    $text  = "<a href=\"info?command=MyCS&presentation=html&csid=$maps->[$idx]{$lroot}" . 
		     "&close_button=1\" target=\"_blank\">E</a>";
	}
    }

    return td({ -align => 'center', 
                -title => $title }, $text);
}

my %status = qw/S 0  N 1  A 2  P 3  C 4  X 5/;
sub td_dep {
    my ($self, $job ) = @_;
    my $csid = $job->id;
    my ($text, $title) = ('-', 'no dependencies');

    my @least = job2dep($job);
    if ($least[0]) {
        $text = "<a href=\"info?command=ViewDeps&presentation=html" . 
                "&csid=$csid&close_button=1\" target=\"_blank\">$least[1]</a>";
        $title = "$least[0] is " . lc(STATUS_NAME($least[-1]));
    } 
    return td({ -align  => 'center',
                -title  => $title }, $text); 

}

sub job2dep {
    my $job = shift;
    if ($job->has_dep) {
        my @least = (0 => 'X');
        for (get_deps($job)) {
            my $j = get_job_by_csid($_) or next;
            my $st = get_status($j);
            @least = ($_ => $st) 
                if $status{$st} < $status{$least[-1]}
        }
        return @least;
    }
}

sub reverse_by_id {
    $b->id cmp $a->id;
}

1;

