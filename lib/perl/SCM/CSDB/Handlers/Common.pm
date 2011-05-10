package SCM::CSDB::Handlers::Common;

use strict;
use warnings;

use base qw/Exporter/;

our @EXPORT_OK = qw/read_request write_response/;

sub dprint {
    print STDERR @_;
    print @_;
}

sub read_request {
    local $/ = "\r\n";
    my $content_length;
    my $string;
    while (<STDIN>) {
        $string .= $_;
        /^content-length:\s*(\d+)/i 
            and $content_length = $1, last;

        # Some requests have no content-length:
        # When we hit an empty line, we therefore
        # bail out and set content-length to zero.
        m#^$/$# 
            and $content_length = 0, last;
    }

    if ($content_length) {
        $string .= <STDIN>; # body-separator
        read(\*STDIN, $string, $content_length, length $string);
    }

    require HTTP::Request;
    require Production::Services::LWPHack;

    my $req = HTTP::Request->parse($string);

    my %head;
    for my $h ($req->header_field_names) {
        next if $h !~ /^change-set/i;
        $head{lc($h)} = [ $req->header($h) ];
    }
    my $body = $req->content;
    my ($handler) = $req->uri =~ m#.*/(.*)#;

    return ($handler, 
            SCM::CSDB::Access::Common::Req->new(\%head, $body, $string));
}

sub write_response {
    my %args = @_;

    print STDERR "RESPONSE>>>>>>\n";

    # status-line
    if (not exists $args{ -status }) {
        dprint "HTTP/1.1 500 Internal server error\r\n";
    } else {
        dprint "HTTP/1.1 @{ $args{ -status } }\r\n";
    }

    # header
    print "Content-Type: text/plain\r\n";
    while (my ($field, $val) = each %{$args{-header} || {}}) {
        if (ref($val) eq 'ARRAY') {
            dprint "$field: $_\r\n" for @$val;
        } else {
            dprint "$field: $val\r\n";
        }
    }
    dprint "Content-Length: @{[length $args{-body}]}\r\n"
        if exists $args{-body};

    # body
    dprint "\r\n";
    dprint $args{-body} if $args{-body};

    print STDERR "\n<<<<<<RESPONSE\n";
}

package SCM::CSDB::Access::Common::Req;

sub new {
    my ($class, $head, $body, $str) = @_;

    bless {
        -str    => $str,
        -head   => $head,
        -body   => $body,
    } => $class;
}

sub head {
    my ($self, $field) = @_;

    my @val = @{ $self->{-head}{lc($field)} || [] };

    return @val if wantarray;
    return $val[0];
}

sub body {
    my $self = shift;
    return $self->{-body};
}

sub as_string {
    my $self = shift;
    return $self->{-str};
}

1;
