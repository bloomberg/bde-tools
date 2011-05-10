# vim:set ts=8 sts=4 sw=4 noet:

package SCM::Message;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Headers;
use LWP::UserAgent;
use List::Util		qw/shuffle/;
use Production::Services::LWPHack;

use Production::Symbols qw/$SCM_HOST $SCM_SEND_COMMIT_MESSAGE
                           $SCM_SEND_GENERIC_MESSAGE $HEADER_SUBJECT
                           $HEADER_ID $HEADER_SEND_FROM $HEADER_SEND_TO
                           $HEADER_DIFF_PATH $HEADER_DIFF_MACHINE/;
use SCM::Symbols        qw/$SCM_DIFF_PATH/;

use Util::Message       qw/error/;
use Change::Util        qw/hashCSID2dir/;
use Change::Symbols     qw/$CS_DIFFREPORT_DIR/;

sub send {
    my ($class, %args) = @_;

    if (not defined $args{-body}) {
        error "Refused to send empty message";
        return;
    }

    if (not defined $args{-to}) {
        error "Cannot send message without recipient";
        return;
    }

    my $header = HTTP::Headers->new;

    $header->header('Change-Set-Subject' => $args{-subject})
        if defined $args{-subject};
    $header->header('Change-Set-From' => $args{-from} || $ENV{USER});

    $header->header('Content-Length' => length $args{-body});

    my @recipients = ref($args{-to}) ? @{ $args{-to} } : $args{-to};

    for (@recipients) {
        $header->header('Change-Set-To' => $_);
        my $req = HTTP::Request->new(
                POST => "$SCM_HOST/$SCM_SEND_GENERIC_MESSAGE", 
                $header, $args{-body});
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($req);
        return 0 if $response->code != 250;
    }
    return 1;
}

sub send_cs_response {
    my ($class, %args) = @_;

    if (not exists $args{ -csid }) {
        error "Cannot send message without change set ID specified";
        return;
    } 
    if (not exists $args{ -creator }) {
        error "Cannot send message without creator specified";
        return;
    }
    if (not exists $args{ -time }) {
        error "Cannot send message without creation time specified";
        return;
    }
    if (not exists $args{ -body }) {
        error "Cannot send message without body";
        return;
    }

    
    my $header = HTTP::Headers->new(
            'Change-Set-ID'             => $args{-csid},
            'Change-Set-Creator'        => $args{-creator},
            'Change-Set-Creation-Time'  => $args{-time},
    );

    $header->header('Change-Set-To' => $ENV{SCM_TEST_RECIPIENT}) 
        if defined $ENV{SCM_TEST_RECIPIENT};

    $header->header('Change-Set-Subject' => $args{-subject})
        if defined $args{-subject};
    $header->header('Change-Set-From' => $args{-from} || $ENV{USER});

    # header fields for diff report
    chomp(my $hostname = `hostname`);
    $header->header('Change-Set-Diff-Machine' => $hostname);
    $header->header('Change-Set-Diff-Path' => "$SCM_DIFF_PATH/$args{-csid}.diff.html");

    $header->header('Content-Length' => length $args{-body});

    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_SEND_COMMIT_MESSAGE", 
            $header, $args{-body});
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return 1 if $response->code == 250;
}

sub send_func_attach {
    my ($class, %args) = @_;
    

    if(not exists $args{from}) {
	error "Cannot send message without sender specified";
	return 0;
    }

    if(not exists $args{to}) {
	error "Cannot send message without recipient specified";
	return 0;
    }

    my $header = HTTP::Headers->new(	         
		  $HEADER_SEND_FROM    => $args{from},
		  $HEADER_SEND_TO      => $args{to},
		  $HEADER_SUBJECT      => $args{subject},		 
		  );

    $header->header('Change-Set-Attach-Function' => $args{attach_function})
	if defined $args{attach_function};


    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_SEND_GENERIC_MESSAGE", 
            $header, $args{body});

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return 1 if $response->code == 250;
    
}

sub send_diff_report {
    my ($class, %args) = @_;

    if(not exists $args{csid}) {
	error "Cannot send message without change set ID specified";
	return 0;
    }

    if(not exists $args{from}) {
	error "Cannot send message without sender specified";
	return 0;
    }

    if(not exists $args{to}) {
	error "Cannot send message without recipient specified";
	return 0;
    }

    my $diff_host;
    $diff_host = $args{host} or do {
        chomp(my $my_arch=`/usr/bin/uname`);
        
        my $ping_cmd;

        if (( -f "usr/bin/ping") && (-x "/usr/bin/ping")) {
            $ping_cmd = "/usr/bin/ping";
        } else {
            $ping_cmd = "/usr/sbin/ping";
        }

        if ($my_arch eq "AIX") {
            $ping_cmd.=" -c 1";
        }
 
        my @test_hosts = shuffle qw/sundev1 sundev2 sundev9 sundev13 sundev14 sundev31 sundev32
            nyfbldo1 nyfbldo2 nysbldo1 nysbldo1/;
     
        for (@test_hosts) {
            if (system("$ping_cmd $_  >/dev/null 2>&1" ) == 0) {
                $diff_host=$_;
                last;
            }
        }

        if (not defined $diff_host) {
            error "Cannot find a test machine";
            return 0;
        }
    };

    my $file = $args{file} || "$CS_DIFFREPORT_DIR/".hashCSID2dir($args{csid})."/".$args{csid}.".diff.html";
    my $header = HTTP::Headers->new(
                                    $HEADER_ID           => $args{csid},
                                    $HEADER_SEND_FROM    => $args{from},
                                    $HEADER_SEND_TO      => $args{to},
                                    $HEADER_SUBJECT      => "MYCS ".$args{csid}." diff report",
                                    $HEADER_DIFF_MACHINE => $diff_host,
                                    $HEADER_DIFF_PATH    => $file,
                                    );

    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_SEND_GENERIC_MESSAGE", 
            $header, "Diff Report for ".$args{csid}. " is attached");

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return 1 if $response->code == 250;

}


sub send_full_desc {
    my ($class, %args) = @_;

    if(not exists $args{csid}) {
	error "Cannot send message without change set ID specified";
	return 0;
    }

    if(not exists $args{from}) {
	error "Cannot send message without sender specified";
	return 0;
    }

    if(not exists $args{to}) {
	error "Cannot send message without recipient specified";
	return 0;
    }

    
    chomp(my $hostname = `hostname`);

    my $header = HTTP::Headers->new(
	          $HEADER_ID           => $args{csid},
		  $HEADER_SEND_FROM    => $args{from},
		  $HEADER_SEND_TO      => $args{to},
		  $HEADER_SUBJECT      => "MYCS ".$args{csid}." full description",
		  $HEADER_DIFF_MACHINE => $hostname,
		  $HEADER_DIFF_PATH    => "/bb/csdata/scm/scm1_njsbvn1/desc/".$args{csid}.".txt",
		  );

    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_SEND_GENERIC_MESSAGE", 
            $header, "Full Description for ".$args{csid}. " is attached");

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return 1 if $response->code == 250;

}

1;

__END__

=head1 NAME

SCM::Message - Send Bloomberg messages

=head1 SYNOPSIS

    use Message::Util   qw/fatal/;
    use SCM::Message;

    my $from    = "pwainwri";
    my @to      = qw/wbaxter1 agrow/
    my $subject = "You're all fired";
    my $body    = "Just kidding";

    my $ok = SCM::Message->send(
            -from       => $from,
            -to         => \@to,
            -subject    => $subject,
            -body       => $body,
    );

    fatal "Couldn't send message" if not $ok;

=head1 DESCRIPTION

This module offers a very simple interface to sending internal Bloomberg messages.

=head1 METHODS

=head2 SCM::Message->send( %args )

Send a message from one user to one or more recipients. Returns a true value if
the request was succesful.

I<%args> are key value pairs describing the mandatory and optional parameters.
Mandatory paramters:

=over 4

=item -to

The recipient of the message as UNIX username. Additionally, when this
argument is a reference to an array, the elements are considered to be
a list of receipients to which the message is sent.

=item -body

The body of the message.

=back

Optional paramters:

=over 4

=item -from

The sender of the message as UNIX username. Use responsibly. 
If not set, C<$ENV{USER}> is used.

=item -subject

The subject of the message. If not set, defaults to "No subject".

=back

=head2 SCM::Message->send_cs_response( %args )

Send a message in response to a checked in change set. Returns a true value if the request was
succesful.

I<%args> are key value pairs describing the mandatory parameters.

=over 4

=item -csid

The change set ID of the change set in question.

=item -creator

The creator of this change set.

=item -time

The creationg time of this change set.

=item -body

The body of the message.

=back

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

