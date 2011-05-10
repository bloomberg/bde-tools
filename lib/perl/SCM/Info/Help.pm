# vim:set ts=8 sts=4 noet:

package SCM::Info::Help;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;

use base qw/SCM::Info/;

my @params = qw/page/;

my %help = (
	StagedBy => <<EOHELP,
<h2 style="font-family:Arial,Helvetica">Help</h2>
<p style="font-family:Arial,Helvetica;font-size:85%">
    This page is the webversion of the <i>stagedby</i> command-line tool. It
    displays the same information but provides some features that go beyond
    its command-line equivalent.
</p>

<table align="left" rules="box">
<tr>
    <th class="helpleft" valign="top" nowrap="nowrap">Sorting</th>
    <td class="helpright">
	The column header name is clickable and clicking it will sort
	the table based on this column. Clicking the column a second
	time will reverse the order. Be aware that this can be slow when
	the table contains many rows as reordering means rearranging the 
	internal DOM tree.
    </td>
</tr>
<tr>
    <th class="helpleft" valign="top" nowrap="nowrap">Disabling columns</th>
    <td class="helpright">
	On top of the table you will find a box <i>Visible columns</i> which 
	lets you select which columns to display. When loading the page for
	the first time, all columns but <i>Queue stage</i> will be visible.
    </td>
</tr>
<tr>
    <th class="helpleft" valign="top" nowrap="nowrap">Refresh</th>
    <td class="helpright">
	The <i>Refresh</i> button near the top of the page does not do a simple
	reload of the page. Instead, it preservs your filtering and selection
	of visible columns. This allows you to establish a table-view and refresh
	without having to reinstante this view by providing the filters etc.<br>
	This refresh does not retain any sorting, however.
    </td>
<tr>
    <th class="helpleft" valign="top" nowrap="nowrap">Filtering</th>
    <td class="helpright">
	The page allows you to filter the table based on one or more columns.
	Certain columns have drop-down menus where making a selection will
	instantly disable all rows not matching the value.
	Values in the text-fields are always treated as case-insensitive
	regular expressions. If for example you want to see only C-headers,
	a suitable pattern would be "\\.h\$".<br>
	If you provide a filter for more than one column, the patterns are
	ANDed so only rows matching all search criteria are shown.
    </td>
</tr>
<tr>
    <th class="helpleft">&nbsp;</th>
    <td class="helpright">&nbsp;</td>
</tr>
<tr>
    <th class="helpleft" nowrap="nowrap">Column</th>
    <th class="helpright">Explanation</th>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_q">Q (Queue stage)</a>
    </td>
    <td valign="top">
	The SCM queue has four distinct stages:<br>
	<ul>
	    <li>0 - Prequeued signified with <b>P</b></li>
	    <li>1 - Queued signified with <b>Q</b></li>
	    <li>2 - Pending signified with <b>P</b></li>
	    <li>3 - Committed signified with <b>N</b></li>
	</ul>
	A submission is in stage <b>P</b> immediately after a successful
	cscheckin run. In this stage, the SCM systems adds dependencies to
	change sets in case of file-overlap (see <a href="#helpcol_d">the
	Dependency column</a>) and handles parts of the rollback procedure.
	Staged <b>Q</b> will one day run the compile-tests but currently does
	nothing useful. <b>P</b> is the stage in which a submission is waiting
	to be committed to the SCM repository.  The final stage <b>C</b> is the
	after-commit stage in which your change set is waiting to be swept.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_date">Date</a>
    </td>
    <td valign="top">
	This is the date when your change set was created by cscheckin on the
	client-side. It reaches the SCM box later, namely when the
	compile-tests have passed.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_user">User</a>
    </td>
    <td valign="top">
	The UNIX username of the creator of the change set.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_csid">CSID</a>
    </td>
    <td valign="top">
	The change set ID of the submission. This links to a side offering
	similar information as the Bloomberg Terminal function MYCS. The link
	opens in a new window.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_move">Move</a>
    </td>
    <td valign="top">
	The movetype of the submission. Note the cunning use of colors: <font
	style="background-color:#32cd32">stpr</font>, <font
	style="background-color:#ff3333">emov</font>, <font
	style="background-color:#ffcccc">bugf</font> and move to make the
	different movetypes stand out easily.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_s">S (Status)</a>
    </td>
    <td valign="top">
	The status of the change set in the change set database. When the
	status changes, this may not be instantly reflected in the table.
	After a minute or so, the table should have caught up however.
	The following statuses can show up:
	<ul>
	    <li>S - Submitted</li>
	    <li>N - Waiting for approval</li>
	    <li>A - Approved</li>
	    <li>P - In progress</li>
	    <li>C - Completed</li>
	    <li>R - Rolled back</li>
	</ul>
	Although change sets in status <b>R</b> and <b>C</b> are never sweepable
	and are strightly speaking not staged anymore, they play an important
	role in the calculation of files and change sets eligible for sweep.
	Once they can no longer contribute to a sweep, they disappear from the
	table.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_b">B (Eligible for build)</a>
    </td>
    <td valign="top">
	This column indicates if that file is eligible to be included in the
	next sweep of that movetype. Since the SCM system is supporting
	multiple checkins, a given file could show up multiple times in the
	staged area, however only one version ends up being swept. The
	calculation of what is a legitimate sweep candidate considers status of
	the corresponding change set as well as possible rollbacks of other
	change sets containing this file.<br>
	Note that a <b>Y</b> in this column does not necessarily mean that this
	file is in fact going to be in the next sweep. For example, emovs are
	selected for sweep on a case-by-case basis. This column does not consider
	the deadlines for the various movetypes either.<br>
	A value of <b>E</b> means that this particular file is eclipsed by a file
	of another change set. The link points to this change set. Eclipsed means
	that this file is provided by another, newer change set.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_d">D (Dependencies)</a>
    </td>
    <td valign="top">
	This column shows the change set status of the least advanced
	contingent dependency. Contingent dependencies are a way to ensure that
	two change sets with an overlapping set of files are committed to the
	SCM repository in the same order as they were created:<br>When
	<b>CS1</b> is staged with status <b>N</b> (waiting for approval) and a
	second change set <b>CS2</b> is submitted that has at least one file
	also present in <b>CS1</b>, then <b>CS2</b> has a dependency on
	<b>CS1</b>.  Even when <b>CS2</b> is approved, it will remain staged
	until <b>CS1</b> is approved and committed, or until <b>CS1</b> is
	rolled back.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_file">File</a>
    </td>
    <td valign="top">
	The basename of one file of a change set. The link, opening in a new
	window, shows you the content of this file as it is in the change
	set. A file with a <font style="background-color:#ffcccc">light red
	background</font> is a new file and a <font
	style="background-color:#eee8aa">pale-golden background</font>
	indicates an unchanged file.
    </td>
</tr>
<tr>
    <td class="helpleft" valign="top" nowrap="nowrap">
	<a name="helpcol_library">Library</a>
    </td>
    <td valign="top">
	The name of the library in which this file resides.
    </td>
</tr>
</table>

EOHELP
);

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;


    $self->content_type;

    my $style = $self->css(
	    '.helpleft'	=> {
		padding_right	    => '40px',
		margin_top	    => '20px',
		background_color    => 'white',
		text_align	    => 'left',
	    },
	    '.helpright' => {
		background_color    => 'white',
		margin_top	    => '20px',
		text_align	    => 'left',
	    },
    );

    print start_html(-title     => "SCM service availability",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code  => $style, },
                     $self->refresh,
    );

    print '<a name="help">';
    print $self->close_button(-margin_bottom => '20px', -text_align => 'center');
    print '</a>';

    my $page = $self->{page};

    if (not $page) {
	$self->error("Need help for what?");
    } elsif (not exists $help{$page}) {
	$self->error("No help available on $page");
    } else {
	print $help{$page};
    }

    print end_html;

}

sub error {
    print <<EOERROR;
<h2 style="padding-top:30px; text-align:center; color:red">
    $_[1]
</h2>
EOERROR
}


1;
