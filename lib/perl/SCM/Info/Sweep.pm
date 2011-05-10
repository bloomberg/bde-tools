# vim:set ts=8 sts=4 noet:

package SCM::Info::Sweep;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;
use File::Basename;

use base qw/SCM::Info/;

use SCM::Symbols	    qw/$SCM_SWEEPINFO_DATA
			       SCM_CSDB SCM_CSDB_DRIVER/;
use Change::Symbols	    qw/FILE_IS_UNCHANGED FILE_IS_CHANGED FILE_IS_NEW FILE_IS_REVERTED/;
use SCM::CSDB::ChangeSet;
use SCM::Util		    qw/get_eclipse_reports parse_eclipse_report/;

my @params = qw/sweep/;

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;

    $self->content_type;

    my $sorter = $self->script('sortable', -offset	=> 1,
					   -movenames	=> [ qw/move bugf emov stpr/ ]);

    my $style = $self->css( th => { text_align => 'center', },
			    td => { font_size  => '95%',
				    text_align => 'center',
				    padding    => '2px', },
			    '.full' => { background_color => '#32cd32', },
			    '.part' => { background_color => '#ffcccc', },
			    '.none' => { text_decoration  => 'line-through', },
			    );

    print start_html(-title     => "Historic sweep reports",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code   => [ $style ], },
                     -script    => [ 
				     { -language => 'JAVASCRIPT',
				       -code	 => "var COLUMN_MOVETYPE;\nfunction colorize(){}", },
                                     { -language => 'JAVASCRIPT',  
                                       -code     => $sorter, },
                                   ],
    );

    my $reports = $self->overview;

    $self->sweep_report($reports) if @$reports;

    print end_html;
}

sub overview {
    my $self = shift;
    my ($reports, $err) = get_eclipse_reports($self->{lastn});

    return $self->error("Could not find any sweep reports", $err)
	if $err;

    print <<EOFORM;
<h2 align="center">Available sweep reports</h2>
<form action="info">

<p align="center">
    <input type="hidden" name="command" value="Sweep"/>
    <input type="hidden" name="presentation" value="html"/>
    <select name="sweep">
EOFORM
   
    my $selected = $self->current_report($reports); 
    for (@$reports) {
	my ($path, $movetype, $date) = @$_;
	my $base = basename($path);
	my $sel = $base eq $selected ? ' selected="selected"' : '';
	print <<EOENTRY;
	<option value="$base"$sel>$date - $movetype</option>
EOENTRY
    }

    print <<EOFORM;
    </select>
    <input type="submit" value="Go"/>
</form>
<hr/>
EOFORM

    return $reports;
}

sub sweep_report {
    my ($self, $reports) = @_;
    
    my $rep = $self->current_report($reports); 

    my ($year, $month) = $rep =~ /eclipsed_log\..{4}\.(\d\d\d\d)(\d\d)/
	or return $self->error("$rep does not seem to be a valid sweep report");

    my $path = "$SCM_SWEEPINFO_DATA/$year/$month/$rep";

    # do we have a cached html view?
    if (open my $fh, '<', "$path.phtml") {
	print while <$fh>;
	return;
    }

    # nope, we have to work harder
    my $parsed = parse_eclipse_report($path);
    my $active = $parsed->{active};

    my $fh;
    open $fh, '>', "$path.phtml"
	or do {
	    warn "Could not open $path.phtml for writing: $!";
	    $fh = \*STDERR;
	};

    # gather change set records from DB
    my $csdb = SCM::CSDB::ChangeSet->new(database => SCM_CSDB, driver => SCM_CSDB_DRIVER);
    my %cs;

    for my $csid (keys %$active) {
	$cs{$csid} = eval {
	    $csdb->getChangeSetDbRecord($csid);
	};
    }

    my ($movetype, $date) = @$parsed{qw/movetype date/};
    $self->dprint(\*STDOUT, $fh, <<EOHEADER);
<h3 align="center">Sweep ($movetype) on $date</h3>
<table align="left" class="sortable" id="csids" rules="all" border="1">
<thead>
    <tr>
	<th>CSID</th>
	<th title="Number of files (changed/unchanged)">F</th>
	<th title="Number of files swept">S</th>
	<th title="Ratio of files swept">S/F</th>
    </tr>
</thead>
<tbody>
EOHEADER
    
    for my $csid (sort keys %cs) {
	my $class;
	next if not defined $cs{$csid};

	my $numunchanged    = $cs{$csid}->getFiles(FILE_IS_UNCHANGED);
	my $numchanged	    = $cs{$csid}->getFiles(FILE_IS_CHANGED, FILE_IS_NEW, FILE_IS_REVERTED);
	my $ratio = sprintf "%.2f", $active->{$csid} / ($numchanged + $numunchanged);
	my $title;

	if ($ratio == 1) {
	    $class = 'full';
	    $title = 'fully swept';
	} elsif ($ratio == 0) {
	    $class = 'none';
	    $title = 'fully eclipsed';
	} else {
	    $class = 'part';
	    $title = 'partially swept';
	}
	$self->dprint(\*STDOUT, $fh, <<EOROW);
    <tr>
	<td class="$class" title="$title">$csid</td>
	<td>$numchanged / $numunchanged</td>
	<td>$active->{$csid}</td>
	<td>$ratio</td>
    </tr>
EOROW
    }

    $self->dprint(\*STDOUT, $fh, <<EOTABLE);
</tbody>
</table>
<table align="right" class="sortable" id="files" rules="all" border="1">
<thead>
    <tr>
	<th>File</th>
	<th>Active</th>
	<th>Eclipsed</th>
    </tr>
</thead>
<tbody>
EOTABLE
    
    for my $file (sort keys %{ $parsed->{files} }) {
	my $rec = $parsed->{files}{$file};
	my $base = basename($file);
	my ($acsid, $atype) = @{ $parsed->{files}{$file}{A} };
	my $active = "<a href=\"info?command=MyCS&presentation=html&csid=$acsid&close_button=1\"" .
		     " target=\"_blank\">$acsid</]a>";
	my @eclipse = @{ $rec->{E} || [] };
	$self->dprint(\*STDOUT, $fh, <<EOROW);
    <tr>
	<td style="text-align:left" valign="top">$base<br>($atype)</td>
	<td style="text-align:left" valign="top">$active</td>
	<td style="text-align:left" valign="top">@{[ join '<br>' => map "$_->[0] ($_->[1])", @eclipse ]}</td>
    </tr>
EOROW
    }
    
    $self->dprint(\*STDOUT, $fh, <<EOTABLE);
</tbody>
</table>
EOTABLE

}

sub current_report {
    my ($self, $reports) = @_;
    return $self->{sweep} || basename($reports->[0][0]);
}

sub dprint {
    my ($self, $fh1, $fh2, $string) = @_;

    print $_ $string for $fh1, $fh2;
}

sub error {
    print <<EOERROR;
<h2 style="padding-top:30px; text-align:center; color:red">
    $_[1]
</h2>
EOERROR
}

1;
