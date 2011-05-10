# vim:set ts=8 sts=4 noet:

package SCM::Info::Status;

use warnings;
use strict;

use CGI qw/param start_html end_html Tr td/;
use HTML::Entities;
use File::Temp  qw/tempdir/;
use SCM::Symbols qw/$SCM_ROOT/;

use base qw/SCM::Info/;

my @params = qw//;

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;
}

sub handle {
    my ($self) = @_;

    my @services = map { ($_, "$_/log") } qw(basd basrouter httpd csproxy csqd rpcd
                                             prequeued precommitd testd commitd sweepd statd
					     laymark );

    my $info = $self->get_info(@services);

    $self->content_type;

    return $self->user($info, @services)
        if $self->presentation eq 'user';

    my $style = $self->css(
	    'th' => {
		padding		    => '10px',
	    },
	    '.up' => {
		background_color    => '#32cd32',
		font_weight	    => 'bold',
		font		    => 'courier',
		padding		    => '10px',
	    },
	    '.down' => {
		background_color    => 'red',
		font_weight	    => 'bold',
		font		    => 'courier',
		padding		    => '10px',
	    },
	    '.na' => {
		background_color    => 'gray',
		font_weight	    => 'bold',
		font		    => 'courier',
		padding		    => '10px',
	    }
    );

    print start_html(-title     => "SCM service availability",
                     -author    => 'tvonparseval@bloomberg.net',
                     -style     => { -code => $style, },
                     $self->refresh,
    );


    my $host = $self->host;

    print <<EOHEAD;
    <h2 align="center">Status of SCM services</h2>
    <h3 style="color:red;" align="center">Master is $host</h3>
EOHEAD

    for (qw/scm1 scm2/) {
        my $i = $info->{$_};
        my $align = $_ eq 'scm1' ? 'left' : 'right';
        print <<EOTH;
    <table border="1" rules="all" align="$align">
    <caption align="top">$_</caption>
    <tr>
        <th>Service</th>
        <th>Status</th>
        <th>Up/down for...</th>
        <th>pid</th>
    </tr>
EOTH
        for (@services) {
	    $i->{$_}[0] ||= 'na';
	    $_ ||= 0 for @{ $i->{$_} }[1,2];
            print <<EOROW;
    <tr>
        <td align="center" class="$i->{$_}[0]">$_</td>
        <td align="center">$i->{$_}[0]</td>
        <td align="center">$i->{$_}[1] seconds</td>
        <td align="center">$i->{$_}[2]</td>
    </tr>
EOROW
        }
        
        print <<EOTABLE;
    </table>
EOTABLE
    }

    print end_html;

}

sub user {
    my ($self, $info, @services) = @_;

    my $home = $self->host eq 'sundev13' ? '/home/cstools' 
                                         : '/bb/cstools';
                                            
    my $script = "$home/admin/scm_status";

    system $script;
    return;

    # The below would be more readable
    print "Master: ", $self->host, "\n";;
    for (qw/scm1 scm2/) {
        print "$_:\n";
        my $i = $info->{$_};
        for (@services) {
            printf "%13s  %4s  %10i seconds  %5i\n", $_, @{ $i->{$_} };
        }
    }
}


sub get_info {
    my ($self, @services) = @_;

    my $home = $self->host eq 'sundev13' ? '/home/cstools' 
                                         : '/bb/cstools';
                                            
    my $script = "$home/admin/scm_status";

    my @lines = `$script`;
   
    my $servicere = join '|', @services;
    my %info; my $curhost;
    for (@lines) {

        $curhost = $1 and next 
            if /^(scm1|scm2):/;
        next 
            if not defined $curhost;

        my ($name, $status) = m#^.*/($servicere): (.*)#
            or next;

        my ($updown) = $status =~ /^(up|down)/;
        my ($dur) = $status =~ /(\d+) seconds/;
        my ($pid) = $updown eq 'down' ? 0
                                      : $status =~ /pid (\d+)/;
        $info{$curhost}{$name} = [ $updown, $dur, $pid ];
    }
    return \%info;
}

sub error {
    my ($self, $error) = @_;

    print <<EOERROR;
    <h2 align="center">Error generating diff report</h2>
    <p style="text-alignment:center">$error</p>
EOERROR
}

sub styles {
    qw/html user/;
}

1;
