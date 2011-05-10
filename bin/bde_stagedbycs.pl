#!/bbs/opt/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use Getopt::Long    qw/:config no_ignore_case/;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Util::Message              qw/fatal set_debug set_verbose debug/;
use Production::Symbols        qw/$SCM_HOST/;
use Change::Symbols            qw/$USER STATUS_WAITING/;
use Production::Services::Util qw/createTemplate parseResponse/; 

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
    --group     | -g <group>    Only list files of group
    --age       | -a <days>     Only list files older than <days> days
    --pending   | -p	        Only list files waiting for approval
    --status    | -S <status>   Only list files of status 
    --move      | -m <movetype> Only list files of movetype
    --file      | -f <file>     Only list <file>
    --lib       | -l <lib>      Only list files of <lib>
    --sweep     | -s            Only list files eligible for sweep
    --no-sweep  | -n            Only list files not eligible for sweep
    
Search options:

    --regex     | -r            <movetype>, <user>, <group>, <status>, <file> and <lib>
                                are Perl regular expressions

Output options:

    --uniq      | -U            Only print unique lines
    --format    | -O <format>   Print according to <format>
    --delimiter | -D <delim>    Use <delim> as field delimiter (defaults to tab)

  <format> is a comma-separated list of one or more of the following:
    qstage date user csid move status build dep file lib
    
EOUSAGE
}

sub getoptions {
    my %opts;

    Getopt::Long::Configure('bundling');
    unless (GetOptions(\%opts, qw[
        user|u=s
        group|g=s
        age|a=s
        status|S=s
        move|m=s
        file|f=s
        lib|l=s
        csid|c=s
        dep|e=s
        sweep|s
        no-sweep|n
        pending|p
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

    fatal("--sweep and --no-sweep are mutually exclusive")
        if $opts{sweep} and $opts{'no-sweep'};

    Util::Message::set_debug($opts{debug} || 0);
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;

}

sub preproc_args {
    my $opts = shift;

    $opts->{user} = $ARGV[0] if @ARGV and not defined $opts->{user};
    if (defined $opts->{user} and not defined $opts->{regex}) {
        $opts->{user} =~ s/^me$/$USER/;
        $opts->{user} = '^' . quotemeta($opts->{user}) . '$';
    }

    # escape regexes in case of 'regex'
    if (not $opts->{regex}) {
        $opts->{move} = movetype($opts->{move});
        for (qw/csid group file lib move status/) {
            next if not defined $opts->{$_};
            $opts->{$_} = '^' . quotemeta($opts->{$_}) . '$';
        }
    }

    if ($opts->{pending}) {
        $opts->{status} = STATUS_WAITING;
    }

    if ($opts->{sweep}) {
        $opts->{sweep} = 'Y';
    } elsif ($opts->{'no-sweep'}) {
        $opts->{sweep} = '-';
    }

    $opts->{age} = time - $opts->{age} * 24 * 60 * 60
        if $opts->{age};

    for (qw/user group csid file lib move status/) {
        next if not defined $opts->{$_};
        $opts->{$_} = URI::Escape::uri_escape($opts->{$_});
    }

    $opts->{delimiter} ||= "\t";
    $opts->{format}    ||= 'user,csid,move,status,build,file';
}

sub movetype {
    my $move = shift;
    return if not defined $move;
    return 
    { move => 'move',
        bugf => 'bugf',  bfix => 'bugf',
        emov => 'emov',
        stpr => 'stpr',
    }->{$move} || do {
        warn "$move: Invalid movetype\n"; 
        usage(1);
    };
}

#------------------------------------------------------------------------------

MAIN: {

    my $opts = getoptions();

    preproc_args($opts);

    my $params = '';
    $params .= "&user=$opts->{user}"          if $opts->{user};
    $params .= "&group=$opts->{group}"        if $opts->{group};
    $params .= "&maxtsp=$opts->{age}"         if $opts->{age};
    $params .= "&status=$opts->{status}"      if $opts->{status};
    $params .= "&movetype=$opts->{move}"      if $opts->{move};
    $params .= "&file=$opts->{file}"          if $opts->{file};
    $params .= "&lib=$opts->{lib}"            if $opts->{lib};
    $params .= "&sweep=$opts->{sweep}"        if $opts->{sweep};

    my $url = "$SCM_HOST/cgi-bin/info?command=StagedBy&presentation=user$params";

    debug("Retrieving via $url");

    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => $url);

    my $res = $ua->request($req);

    if ($res->is_success) {
        my ($header, @files)            = parseResponse($res->content);
        my ($head, $tmpl, $vdel, @f)    = createTemplate($header,
							  $opts->{delimiter}, 
							  $opts->{format});
        print $head;

        if ($opts->{uniq}) {
            my %seen;
            print grep !$seen{$_}++, map sprintf($tmpl, @$_{@f}), @files;
        } else {
            printf $tmpl, @$_{@f} for @files;
        }
    } else {
        fatal "Could not get information about staged material: " .
              $res->content;
    }
}
