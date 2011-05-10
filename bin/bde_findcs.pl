#!/bbs/opt/bin/perl -w

use strict;

use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Symbols                         qw/EXIT_FAILURE EXIT_SUCCESS/;
use Util::Message                   qw/error fatal/;
use Production::Services;
use Production::Services::CsInfo    qw/getCsInfo/;
use Production::Services::Util      qw/createTemplate parseResponse/;

sub usage {
    require File::Basename;
    my $prog = File::Basename::basename($0);

    print STDERR <<EOUSAGE
$prog [opts]    
    --verbose   | -v            Print verbose messages
    --debug     | -d            Print debugging information
    --help      | -h            This help screen

    Query options:

    --user      | -u <user>     Only list files of user ('me' for current user)
    --file      | -f <file>     Only list <file>
    --lib       | -l <lib>      Only list files of <lib>
    --status    | -S <status>   Only list change set of status
    --move      | -m <movetype> Only list change set of movetype
    --start     | -s <startdate>Only list change set after start date(yyyy-mm-dd)
    --end       | -e <enddate>  Only list change set before end date(yyyy-mm-dd)
    --csid      | -c <csid>     Only list change set of csid
    --regex     | -r            Use regex for pattern match

    Output options:

    --uniq      | -U            Only print unique lines
    --format    | -O <format>   Print according to <format>
    --delimiter | -D <delim>    Use <delim> as field delimiter (defaults to ta

EOUSAGE
}

sub getoptions {
    my %opts;

      Getopt::Long::Configure('bundling');
    unless (GetOptions(\%opts, qw[
        user|u=s       
	status|S=s
        move|m=s
        file|f=s
        lib|l=s
        csid|c=s
	start|s=s
	end|e=s
        regex|r
        delimiter|D=s
        format|O=s
        uniq|U
        debug|d+
        verbose|v+
        help|h
    ])) {
        usage();
        exit 1;
    }

    usage(), exit 0 if $opts{help};

    Util::Message::set_debug($opts{debug} || 0);
    Util::Message::set_verbose($opts{verbose} || 0);

    $opts{delimiter} ||="\t";
    $opts{format}    ||='user,csid,move,status,file';

    return \%opts;
}

MAIN: {
    my $opts=getoptions();

    my $svc=new Production::Services; 
    my $start=$opts->{start}    if $opts->{start};
    my $end=$opts->{end}        if $opts->{end};   

    if (defined $start && $start !~ /\d\d\d\d-\d\d-\d\d/ ) {
       error("please provide start date in format yyyy-mm-dd");
       exit EXIT_FAILURE;
    };

    if (defined $end && $end !~ /\d\d\d\d-\d\d-\d\d/ ) {
       error("please provide end date in format yyyy-mm-dd");
       exit EXIT_FAILURE;
    };

    my $results=getCsInfo($svc, $opts);
    unless ($results) {
      error("No record found");
      exit EXIT_FAILURE;
    }

    my ($header, @files) = parseResponse($results);
    my ($head, $tmpl, $vdel, @f) = createTemplate($header,
						  $opts->{delimiter}, 
                                                  $opts->{format});
    print $head;

    if ($opts->{uniq}) {
       my %seen;
       print grep !$seen{$_}++, map sprintf($tmpl, @$_{@f}), @files;
    } else {
       printf $tmpl, @$_{@f} for @files;
    }
}
