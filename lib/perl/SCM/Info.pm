# vim:set ts=8 sts=4 noet:

package SCM::Info;

use warnings;
use strict;

use CGI qw//;
use File::Basename;

BEGIN {
    $ENV{PATH} = '/bin:/usr/bin';
}

my %DEFAULT_CSS = (
    h2		=> {
	font_family	    => 'courier',
    },
    table	=> {
	border_collapse	    => 'collapse',
    },
    th		=> {
	font_family	    => 'sans-serif',
	background_color    => 'yellow',
    },
    'th a:link'	=> {
	font_family	    => 'sans-serif',
	padding		    => '15px',
	color		    => '#ff0000',
	text_decoration	    => 'none',
    },
    'th a:visited' => {
	font_family	    => 'sans-serif',
	padding		    => '10px',
	color		    => '#ff0000',
	text_decoration	    => 'none',
    },
    'a.anchor'	=> {
	font_size	    => 'x-small',
	text_decoration	    => 'underline',
    },
    td		=> {
	font_size	    => '75%',
	font_family	    => [ qw/Arial Helvetica/ ],
	font_weight	    => 500,
	padding		    => '2px',
    },
    'td.title'	=> {
	color		    => '#ff0000',
    },
    '.move' => {
	text_align	    => 'center',
    },
    '.bugf' => {
	background_color    => '#ffcccc',
	text_align	    => 'center',
    },
    '.emov' => {
	background_color    => '#ff3333',
	text_align	    => 'center',
    },
    '.stpr' => {
	background_color    => '#32cd32',
	text_align	    => 'center',
    },
    '#top'  => {
	border_top_width    => '1px',
	border_top_style    => 'solid',
    },
);

sub new {
    my ($class) = @_;

    my ($cmd) = CGI::param('command') =~ /^(\w+)$/;
    
    eval "require SCM::Info::$cmd";
        
    if ($@) {
        print CGI::header(-status => "400 Bad request ($cmd: no such command)");
        die "$cmd: No such request: $@";
    }
    
    chomp(my $host = `hostname`);
    my ($url, $css, $js);
    if ($host =~ /^sundev13/) {
        ($url, $css, $js) = qw(http://sundev13.bloomberg.com:32375/dev
                               /dev/css /dev/scripts);
    } else {
        my $thingie = $ENV{SERVER_PORT} == 28275 ? '/scm2' : '';
                      
        ($url, $css, $js) = ("http://sundev13.bloomberg.com:32375$thingie",
                             "$thingie/css", "$thingie/scripts");
    }

    my $self = bless {
        presentation    => CGI::param('presentation')   || 'user',
        refresh         => CGI::param('refresh')        || 0,
        command         => $cmd,
        host            => $host,
        url             => $url,
        css             => $css,
        js              => $js,
    } => "SCM::Info::$cmd";

    $self->init;
    $self->check_presentation or do {
        print CGI::header(-status => "400 Bad request (invalid style)");
        die $self->presentation, ": Invalid style";
    };

    return $self;
}

sub init {
}

sub check_presentation {
    my ($self) = @_;

    $self->presentation eq $_ and return 1 for $self->styles;

    return 0;
}

sub styles {
    qw/user html/;
}

sub content_type {
    my ($self, @add) = @_;

    my $content_type;
    for ($self->presentation) {
        /html/  and $content_type = 'text/html'     and last;
        /xml/   and $content_type = 'text/xml'      and last;
        /post/  and $content_type = 'text/html'     and last;
        /user/  and $content_type = 'text/plain'    and last;
	/csv/	and $content_type = 'text/csv'	    and last;
    }

    print CGI::header(-type          => $content_type, 
                      -cache_control => 'no-cache, must-revalidate',
                      -pragma        => 'no-cache',
                      -expires       => scalar localtime(time - 3600),
                      @add);
}

sub close_button {
    my ($self, %args) = @_;

    my $style;
    while (my ($parm, $val) = each %args) {
        $parm =~ s/^-//;
        $parm =~ tr/_/-/;
        $style .= "$parm:$val;";
    }

    my $div = '';
    $div = "<div style=\"$style\">" if $style;

    return <<EOBUTT;
$div
    <input type="button" value="Close" onclick="javascript:window.close()">
@{[$div ? '</div>' : '']}
EOBUTT
}

sub script {
    my ($self, $type, %args) = @_;
    
    $type = "js_$type";

    die "N$type: No such javascript component"
        if not $self->can($type);

    return $self->$type(%args);
}

sub js_sortable {
    my ($self, %args) = @_;

    #my $rowoffset = $args{ -offset } || 1;
    my $clickrow  = $args{ -clickrow } || 0;
    my ($move, $bugf, $emov, $stpr) = @{ $args{ -movenames } };

    return <<EOSCRIPT;
addEvent(window, "load", sortables_init);
var SORT_COLUMN_INDEX;

function sortables_init() {
    /* Find all tables with class sortable and make them sortable */
    if (!document.getElementsByTagName) 
        return;
    tbls = document.getElementsByTagName("table");
    for (ti = 0; ti < tbls.length; ti++) {
        thisTbl = tbls[ti];
        if ((' ' + thisTbl.className + ' ').indexOf("sortable") != -1 && 
            (thisTbl.id)) {
            /* initTable(thisTbl.id); */
            ts_makeSortable(thisTbl);
        }
    }
}

function ts_makeSortable(table) {
    if (table.tHead && table.tHead.rows && table.tHead.rows.length > 0) {
        var firstRow = table.tHead.rows[$clickrow];
    }
    if (!firstRow) 
        return;
    
    /* We have a first row: assume it's the header, 
       and make its contents clickable links */
    for (var i = 0; i < firstRow.cells.length; i++) {
        var cell = firstRow.cells[i];
        var txt = ts_getInnerText(cell);
        cell.innerHTML = '<a href="#" class="sortheader" ' + 
                         'onclick="ts_resortTable(this, ' + i +
                         ');return false;">' + txt +
                         '<span class="sortarrow">&nbsp;&nbsp;&nbsp;</span></a>';
    }
}

function ts_getInnerText(el) {
	if (typeof el == "string" || typeof el == "undefined") 
            return el;

        /* Not needed but it is faster */
	if (el.innerText) 
            return el.innerText;	

	var str = "";
	
	var cs = el.childNodes;
	var l = cs.length;
        for (var i = 0; i < l; i++) {
            switch (cs[i].nodeType) {
                case 1: /* ELEMENT_NODE */
                    str += ts_getInnerText(cs[i]);
                    break;
                case 3:	/* TEXT_NODE */
                    str += cs[i].nodeValue;
                    break;
            }
        }
	return str;
}

function ts_resortTable(lnk,clid) {
    /* get the span */
    var span;
    for (var ci = 0; ci < lnk.childNodes.length; ci++) {
        if (lnk.childNodes[ci].tagName && 
            lnk.childNodes[ci].tagName.toLowerCase() == 'span') 
            span = lnk.childNodes[ci];
    }
    var spantext = ts_getInnerText(span);
    var td = lnk.parentNode;
    var column = clid || td.cellIndex;
    var body = getParentBody(td,'TABLE');

    /* Work out a type for the column */
    if (body.rows.length <= 1) 
        return;

    if (column == COLUMN_MOVETYPE) 
        sortfn = ts_sort_movetype;
    else {
        var itm = ts_getInnerText(body.rows[0].cells[column]);
        sortfn = ts_sort_caseinsensitive;
        if (itm.match(/^\\d\\d[\\/-]\\d\\d[\\/-]\\d\\d\\d\\d\$/)) 
            sortfn = ts_sort_date;
        if (itm.match(/^\\d\\d[\\/-]\\d\\d[\\/-]\\d\\d\$/)) 
            sortfn = ts_sort_date;
        if (itm.match(/^[£\$]/)) sortfn = 
            ts_sort_currency;
        if (itm.match(/^[\\d\\.]+\$/)) 
            sortfn = ts_sort_numeric;
    }

    SORT_COLUMN_INDEX = column;
    var firstRow = new Array();
    var newRows = new Array();
    for (i = 0; i < body.rows[0].length; i++)
        firstRow[i] = body.rows[0][i]; 

    for (j = 0; j < body.rows.length; j++) 
        newRows[j] = body.rows[j];

    newRows.sort(sortfn);

    if (span.getAttribute("sortdir") == 'down') {
        newRows.reverse();
        span.setAttribute('sortdir','up');
    } else {
        span.setAttribute('sortdir','down');
    }
    
    /* We appendChild rows that already exist to the tbody, 
       so it moves them rather than creating new ones */
    
    /* don't do sortbottom rows */
    for (i = 0; i < newRows.length; i++) { 
        if (!newRows[i].className ||
            (newRows[i].className &&
             (newRows[i].className.indexOf('sortbottom') == -1)))
        body.appendChild(newRows[i]);
    }

    /* do sortbottom rows only */
    for (i = 0; i < newRows.length; i++) { 
        if (newRows[i].className && 
            newRows[i].className.indexOf('sortbottom') != -1) 
            body.appendChild(newRows[i]);
    }
    
    colorize();
}

function getParentBody(el, pTagName) {
	if (el == null) 
            return null;
	else if (el.nodeType == 1 && 
                 el.tagName.toLowerCase() == pTagName.toLowerCase())	
                /* Gecko bug, supposed to be uppercase */
            return el.tBodies[0];
        else
            return getParentBody(el.parentNode, pTagName);
}

function ts_sort_movetype(a,b) {
    aa = ts_getInnerText(a.cells[COLUMN_MOVETYPE]);
    bb = ts_getInnerText(b.cells[COLUMN_MOVETYPE]);
    
    var movetype = new Object();
    movetype['$stpr'] = 0;
    movetype['$move'] = 1;
    movetype['$bugf'] = 2;
    movetype['$emov'] = 3;

    return movetype[aa] - movetype[bb];
}

function ts_sort_date(a,b) {
    /* y2k notes: two digit years less than 50 are treated as 20XX,
     * greater than 50 are treated as 19XX */
    aa = ts_getInnerText(a.cells[SORT_COLUMN_INDEX]);
    bb = ts_getInnerText(b.cells[SORT_COLUMN_INDEX]);

    if (aa.length == 10) {
        dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
    } else {
        yr = aa.substr(6,2);
        if (parseInt(yr) < 50) { 
            yr = '20' + yr; 
        } else { 
            yr = '19' + yr; 
        }
        dt1 = yr + aa.substr(3,2) + aa.substr(0,2);
    }

    if (bb.length == 10) {
        dt2 = bb.substr(6,4) + bb.substr(3,2) + bb.substr(0,2);
    } else {
        yr = bb.substr(6,2);
        if (parseInt(yr) < 50) { 
            yr = '20' + yr; 
        } else { 
            yr = '19' + yr; 
        }
        dt2 = yr + bb.substr(3,2) + bb.substr(0,2);
    }

    if (dt1 == dt2) 
        return 0;
    if (dt1 < dt2) 
        return -1;
    return 1;
}

function ts_sort_currency(a,b) { 
    aa = ts_getInnerText(a.cells[SORT_COLUMN_INDEX]).replace(/[^0-9.]/g,'');
    bb = ts_getInnerText(b.cells[SORT_COLUMN_INDEX]).replace(/[^0-9.]/g,'');
    return parseFloat(aa) - parseFloat(bb);
}

function ts_sort_numeric(a,b) { 
    aa = parseFloat(ts_getInnerText(a.cells[SORT_COLUMN_INDEX]));
    if (isNaN(aa)) 
        aa = 0;
    bb = parseFloat(ts_getInnerText(b.cells[SORT_COLUMN_INDEX])); 
    if (isNaN(bb)) 
        bb = 0;
    return aa-bb;
}

function ts_sort_caseinsensitive(a,b) {
    aa = ts_getInnerText(a.cells[SORT_COLUMN_INDEX]).toLowerCase();
    bb = ts_getInnerText(b.cells[SORT_COLUMN_INDEX]).toLowerCase();
    if (aa == bb) 
        return 0;
    if (aa < bb) 
        return -1;
    return 1;
}

function ts_sort_default(a,b) {
    aa = ts_getInnerText(a.cells[SORT_COLUMN_INDEX]);
    bb = ts_getInnerText(b.cells[SORT_COLUMN_INDEX]);
    if (aa == bb) 
        return 0;
    if (aa < bb) 
        return -1;
    return 1;
}


function addEvent(elm, evType, fn, useCapture) {
    /* addEvent and removeEvent
     * cross-browser event handling for IE5+,  NS6 and Mozilla
     * By Scott Andrew */
    if (elm.addEventListener){
        elm.addEventListener(evType, fn, useCapture);
        return true;
    } else if (elm.attachEvent){
        var r = elm.attachEvent("on"+evType, fn);
        return r;
    } else {
        alert("Handler could not be removed");
    }
} 
EOSCRIPT
}
sub host {
    shift->{host};
}

sub url {
    shift->{url};
}

sub base_url {
    my ($self) = @_;
    my $script = basename $0;
    join '/', $self->url, $script;
}

sub params {
    my ($self, @list) = @_;
    return join '&', map "$_=$self->{$_}", @list;
}

sub css {
    my ($self, %args) = @_;

    my $css;
    while (my ($key, $spec) = each %DEFAULT_CSS) {
	# merge valus from %args into $spec
	my %values = (%$spec, %{ $args{$key} || {} });
	delete $args{$key};
	$css .= "$key {\n";
	while (my ($field, $vals) = each %values) {
	    $field =~ tr/_/-/;
	    my @vals = ref($vals) ? @$vals : $vals;
	    my $str = join ',' => @vals;
	    next if not $str;
	    $css .= "    $field:$str;\n";
	}
	$css .= "}\n";
    }

    # whatever is left in %args are new classes
    while (my ($key, $spec) = each %args) {
	$css .= "$key {\n";
	while (my ($field, $vals) = each %$spec) {
	    $field =~ tr/_/-/;
	    my @vals = ref($vals) ? @$vals : $vals;
	    my $str = join ',' => @vals;
	    next if not $str;
	    $css .= "    $field:$str;\n";
	}
	$css .= "}\n";
    }
    return $css;
}

sub js {
    shift->{js};
}

sub presentation { 
    shift->{presentation}; 
}

sub refresh {
    my ($self) = @_;
    
    return if not $self->{refresh};

    my $url = $self->base_url . '?' . CGI::query_string();
    $url =~ tr/;/&/;

    return 
        -head => CGI::meta({ -http_equiv    => 'refresh',
                             -content       => "$self->{refresh}; URL=$url",});
}

1;
