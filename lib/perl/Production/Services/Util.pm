package Production::Services::Util;

use strict;
use base qw/Exporter/;
use LWP::UserAgent;
use HTTP::Request;

use Production::Symbols qw/$SCM_HOST $SCM_GET_UNIX_LOGIN_BY_UUID
                                     $SCM_GET_UUID_BY_UNIX_LOGIN
                                     $SCM_SEND_MANAGER_COMMIT_MSG
                           $HEADER_ID
                           $HEADER_CREATOR
                           $HEADER_CREATION_TIME
                           $HEADER_SEND_TO
                           $HEADER_SUBJECT
                           $HEADER_REASON
                           $HEADER_TICKET
                           $HEADER_DIFF_MACHINE
                           $HEADER_DIFF_PATH
                           $SCM_HOSTNAME
                           $SCM_PORT
                           $SCM_VERSION/;
use Change::Symbols qw /$CS_DIFFREPORT_DIR/;
use Change::Util    qw/hashCSID2dir/;
our @EXPORT_OK = qw/getUUIDFromUnixName getUnixNameFromUUID
                    sendManagerCommitMSG createTemplate 
                    parseResponse /;

sub getUUIDFromUnixName ($) {
    my $unixname = shift;

    my $agent = LWP::UserAgent->new;
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$SCM_GET_UUID_BY_UNIX_LOGIN");
    $req->header($HEADER_CREATOR => $unixname);

    my $res = $agent->request($req);

    if ($res->code == 250) {
        chomp(my $login = $res->content);
        return $login;
    } else {
        return (0, $res->content);
    }
}

sub getUnixNameFromUUID ($) {
    my $uuid = shift;

    my $agent = LWP::UserAgent->new;
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$SCM_GET_UNIX_LOGIN_BY_UUID");
    $req->header($HEADER_CREATOR => $uuid);

    my $res = $agent->request($req);

    if ($res->code == 250) {
        chomp(my $login = $res->content);
        $login =~ s/\s+$//;     # the little BAS sucker space-pads the unix name
        return $login;
    } else {
        return (0, $res->content);
    }
}

sub sendManagerCommitMSG($) {
    my $cs = shift;

    my $agent = LWP::UserAgent->new;
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$SCM_SEND_MANAGER_COMMIT_MSG");

    my $hostname = `hostname`;
    chomp $hostname;

    my $subject = "Commit Message "."from ".$cs->getUser;
    $req->header($HEADER_ID=>$cs->getID,
		 $HEADER_CREATOR=>$cs->getUser,
		 $HEADER_CREATION_TIME=>$cs->getTime,
		 $HEADER_TICKET=>$cs->getTicket,
		 $HEADER_SUBJECT=> $subject,		
		 $HEADER_DIFF_MACHINE=>$hostname,
		 $HEADER_DIFF_PATH=>"$CS_DIFFREPORT_DIR/".hashCSID2dir($cs->getID).'/'.$cs->getID.'.diff.html');

    my $message=$cs->getMessage;
    if($message =~ /^Change-Set-[-A-Za-z]+: /) {
	$message = (split /\n\n/, $message, 2)[1];
    }

    $req->content($message);
    
    my $res = $agent->request($req);
    if($res->code != 250) {
	return (0, $res->content);
    }
    
    return 1;
}

sub parseResponse {
    my $str = shift;

    my ($cols, @lines) = split /\n/, $str;

    my @cols;
    my %header;
    for (split /\t/, $cols) {
        my ($col, $name, $width) = split /\|/;
        $header{$col} = [$name, $width];
        push @cols, $col;
    }

    my @files;
    for (@lines) {
        my %rec;
        @rec{@cols} = split /\t/;
        push @files, \%rec;
    }

    return (\%header, @files);
}

sub createTemplate {
    my %header  = %{ +shift };
    my $delimiter    = shift;
    my $fmt = shift;

    my @fields;
    for (split /,/, $fmt) {
        next if not $_;
        warn "$_: No such field\n" and next if not exists $header{$_};
        push @fields, $_;
    }
    exit 0 if not @fields;

    my $templ;
    for (@fields) {
        my $width = $header{$_}[1];
        $width = '' if $delimiter ne "\t";
	if($_ eq $fields[scalar @fields -1]) {
	    $templ .= "%s$delimiter";
	} else {
	    $templ .= "%-${width}s$delimiter";
	}
    }

    $templ =~ s/\Q$delimiter\E$//;
    $templ .= "\n";

    my $head = sprintf $templ, map $_->[0], @header{@fields};
    $head = uc($head);

    my $vdel = '-' x (length($head) - 1);
    substr $vdel, $_ - 1, 1, '+' for offsetsof($head, '|');

    return ($head, $templ, $vdel, @fields);    
}

sub offsetsof {
    my ($str, $pat) = @_;
    my @offset;
    push @offset, pos $str while $str =~ /(\Q$pat\E)/g;
    return @offset;
}

1;
__END__

=head1 NAME

Production::Services::Util - Auxiliary functions to support other production requests.

=head1 SYNOPSIS

    use Production::Services::Util qw/getUUIDFromUnixName
                                      getUnixNameFromUUID/;

    my $uuid = getUUIDFromUnixName('tvon');
    my $name = getUnixNameFromUUID($uuid);

    print "$name with UUID $uuid\n";

=head1 FUNCTIONS

=head2 getUUIDFromUnixName ($username)

Translates the name I<$username> into its corresponding UUID if possible.

Returns the UUID in case of success. Otherwise a two-element list, with
the first element false and the second being the error message.

=head2 getUnixNameFromUUID ($uuid)

Given a UUID, returns the Unix login name if possible.

Returns the login name in case of success. Otherwise a two-element list, with
the first element false and the second being the error message.

=head1 NOTE

The functions in this module are safe to be called client-wise from the dev
machines as well as from SCM production machines.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
