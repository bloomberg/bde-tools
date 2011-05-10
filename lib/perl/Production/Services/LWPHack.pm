package Production::Services::LWPHack;

use strict;
use warnings;

use Net::HTTP::Methods;
use Errno;

no warnings 'redefine';

##############################################################
# This -- courtesy to Dan Sugalski -- is evil, dirty         #
# and ingenious: LWP::UserAgent barfs when receiving         #
# responses with more than 128 header lines. This            #
# limit is set deep down in Net::HTTP::Methods and,          #
# even though there is a way of overriding this limit        #
# when using this module directly, we cannot tell            #
# LWP::UserAgent to do so for us. So the only solution       #
# that would not require changes to these libraries          #
# directly is to redefine Net::HTTP::Methods::http_configure #
# where this limit is set.                                   #
##############################################################
*Net::HTTP::Methods::http_configure = sub {
    my($self, $cnf) = @_;

    die "Listen option not allowed" if $cnf->{Listen};
    my $explict_host = (exists $cnf->{Host});
    my $host = delete $cnf->{Host};
    my $peer = $cnf->{PeerAddr} || $cnf->{PeerHost};
    if ($host) {
	$cnf->{PeerAddr} = $host unless $peer;
    }
    elsif (!$explict_host) {
	$host = $peer;
	$host =~ s/:.*//;
    }
    $cnf->{PeerPort} = $self->http_default_port unless $cnf->{PeerPort};
    $cnf->{Proto} = 'tcp';

    my $keep_alive = delete $cnf->{KeepAlive};
    my $http_version = delete $cnf->{HTTPVersion};
    $http_version = "1.1" unless defined $http_version;
    my $peer_http_version = delete $cnf->{PeerHTTPVersion};
    $peer_http_version = "1.0" unless defined $peer_http_version;
    my $send_te = delete $cnf->{SendTE};
    my $max_line_length = delete $cnf->{MaxLineLength};
    $max_line_length = 4*1024 unless defined $max_line_length;
    my $max_header_lines = delete $cnf->{MaxHeaderLines};
    $max_header_lines = 1<<16 unless defined $max_header_lines;

    return undef unless $self->http_connect($cnf);

    if ($host && $host !~ /:/) {
	my $p = $self->peerport;
	$host .= ":$p" if $p != $self->http_default_port;
    }
    $self->host($host);
    $self->keep_alive($keep_alive);
    $self->send_te($send_te);
    $self->http_version($http_version);
    $self->peer_http_version($peer_http_version);
    $self->max_line_length($max_line_length);
    $self->max_header_lines($max_header_lines);

    ${*$self}{'http_buf'} = "";

    return $self;
};

use LWP::Protocol::http;

no warnings 'redefine';

sub safe_syswrite {
    my ($socket, $buf, $len, $offset) = @_;

    my $total = $len;
    while ($len) {
        my $n = $socket->syswrite($buf, $len, $offset);
        if (not defined $n) {
            select(undef, undef, undef, 0.1), next if $!{EAGAIN};
            die "ERROR: $!";
        }
        $offset += $n; $len -= $n;
    }

    return $total;
}

# LWP::Protocol::http
*LWP::Protocol::http::request = sub {
    my($self, $request, $proxy, $arg, $size, $timeout) = @_;
    LWP::Debug::trace('()');

    my $CRLF = "\015\012";

    $size ||= 4096;

    # check method
    my $method = $request->method;
    unless ($method =~ /^[A-Za-z0-9_!\#\$%&\'*+\-.^\`|~]+$/) {  # HTTP token
	return new HTTP::Response &HTTP::Status::RC_BAD_REQUEST,
				  'Library does not allow method ' .
				  "$method for 'http:' URLs";
    }

    my $url = $request->url;
    my($host, $port, $fullpath);

    # Check if we're proxy'ing
    if (defined $proxy) {
	# $proxy is an URL to an HTTP server which will proxy this request
	$host = $proxy->host;
	$port = $proxy->port;
	$fullpath = $method eq "CONNECT" ?
                       ($url->host . ":" . $url->port) :
                       $url->as_string;
    }
    else {
	$host = $url->host;
	$port = $url->port;
	$fullpath = $url->path_query;
	$fullpath = "/$fullpath" unless $fullpath =~ m,^/,;
    }

    # connect to remote site
    my $socket = $self->_new_socket($host, $port, $timeout);
    $self->_check_sock($request, $socket);

    my @h;
    my $request_headers = $request->headers->clone;
    $self->_fixup_header($request_headers, $url, $proxy);

    $request_headers->scan(sub {
			       my($k, $v) = @_;
			       $k =~ s/^://;
			       $v =~ s/\n/ /g;
			       push(@h, $k, $v);
			   });

    my $content_ref = $request->content_ref;
    $content_ref = $$content_ref if ref($$content_ref);
    my $chunked;
    my $has_content;

    if (ref($content_ref) eq 'CODE') {
	my $clen = $request_headers->header('Content-Length');
	$has_content++ if $clen;
	unless (defined $clen) {
	    push(@h, "Transfer-Encoding" => "chunked");
	    $has_content++;
	    $chunked++;
	}
    }
    else {
	# Set (or override) Content-Length header
	my $clen = $request_headers->header('Content-Length');
	if (defined($$content_ref) && length($$content_ref)) {
	    $has_content = length($$content_ref);
	    if (!defined($clen) || $clen ne $has_content) {
		if (defined $clen) {
		    warn "Content-Length header value was wrong, fixed";
		    hlist_remove(\@h, 'Content-Length');
		}
		push(@h, 'Content-Length' => $has_content);
	    }
	}
	elsif ($clen) {
	    warn "Content-Length set when there is no content, fixed";
	    hlist_remove(\@h, 'Content-Length');
	}
    }

    my $write_wait = 0;
    $write_wait = 2
	if ($request_headers->header("Expect") || "") =~ /100-continue/;

    my $req_buf = $socket->format_request($method, $fullpath, @h);
    #print "------\n$req_buf\n------\n";

    if (!$has_content || $write_wait || $has_content > 8*1024) {
	# XXX need to watch out for write timeouts
	my $offset = 0;
	my $len = length($req_buf);
        safe_syswrite($socket, $req_buf, length($req_buf), $offset);
	#LWP::Debug::conns($req_buf);
	$req_buf = "";
    }

    my($code, $mess, @junk);
    my $drop_connection;

    if ($has_content) {
	my $eof;
	my $wbuf;
	my $woffset = 0;
	if (ref($content_ref) eq 'CODE') {
	    my $buf = &$content_ref();
	    $buf = "" unless defined($buf);
	    $buf = sprintf "%x%s%s%s", length($buf), $CRLF, $buf, $CRLF
		if $chunked;
	    substr($buf, 0, 0) = $req_buf if $req_buf;
	    $wbuf = \$buf;
	}
	else {
	    if ($req_buf) {
		my $buf = $req_buf . $$content_ref;
		$wbuf = \$buf;
	    }
	    else {
		$wbuf = $content_ref;
	    }
	    $eof = 1;
	}

	my $fbits = '';
	vec($fbits, fileno($socket), 1) = 1;

	while ($woffset < length($$wbuf)) {

	    my $time_before;
	    my $sel_timeout = $timeout;
	    if ($write_wait) {
		$time_before = time;
		$sel_timeout = $write_wait if $write_wait < $sel_timeout;
	    }

	    my $rbits = $fbits;
	    my $wbits = $write_wait ? undef : $fbits;
	    my $nfound = select($rbits, $wbits, undef, $sel_timeout);
	    unless (defined $nfound) {
		die "select failed: $!";
	    }

	    if ($write_wait) {
		$write_wait -= time - $time_before;
		$write_wait = 0 if $write_wait < 0;
	    }

	    if (defined($rbits) && $rbits =~ /[^\0]/) {
		# readable
		my $buf = $socket->_rbuf;
		my $n = $socket->sysread($buf, 1024, length($buf));
		unless ($n) {
		    die "EOF";
		}
		$socket->_rbuf($buf);
		if ($buf =~ /\015?\012\015?\012/) {
		    # a whole response present
		    ($code, $mess, @h) = $socket->read_response_headers(laxed => 1,
									junk_out => \@junk,
								       );
		    if ($code eq "100") {
			$write_wait = 0;
			undef($code);
		    }
		    else {
			$drop_connection++;
			last;
			# XXX should perhaps try to abort write in a nice way too
		    }
		}
	    }
	    if (defined($wbits) && $wbits =~ /[^\0]/) {
                
                my $n = safe_syswrite($socket, $$wbuf, length($$wbuf), $woffset);
                #my $n = $socket->syswrite($$wbuf, length($$wbuf), $woffset);
		unless ($n) {
		    die "syswrite: $!" unless defined $n;
		    die "syswrite: no bytes written";
		}
		$woffset += $n;

		if (!$eof && $woffset >= length($$wbuf)) {
		    # need to refill buffer from $content_ref code
		    my $buf = &$content_ref();
		    $buf = "" unless defined($buf);
		    $eof++ unless length($buf);
		    $buf = sprintf "%x%s%s%s", length($buf), $CRLF, $buf, $CRLF
			if $chunked;
		    $wbuf = \$buf;
		    $woffset = 0;
		}
	    }
	}
    }

    ($code, $mess, @h) = $socket->read_response_headers(laxed => 1, junk_out => \@junk)
	unless $code;
    ($code, $mess, @h) = $socket->read_response_headers(laxed => 1, junk_out => \@junk)
	if $code eq "100";

    my $response = HTTP::Response->new($code, $mess);
    my $peer_http_version = $socket->peer_http_version;
    $response->protocol("HTTP/$peer_http_version");
    while (@h) {
	my($k, $v) = splice(@h, 0, 2);
	$response->push_header($k, $v);
    }
    $response->push_header("Client-Junk" => \@junk) if @junk;

    $response->request($request);
    $self->_get_sock_info($response, $socket);

    if ($method eq "CONNECT") {
	$response->{client_socket} = $socket;  # so it can be picked up
	return $response;
    }

    if (my @te = $response->remove_header('Transfer-Encoding')) {
	$response->push_header('Client-Transfer-Encoding', \@te);
    }
    $response->push_header('Client-Response-Num', $socket->increment_response_count);

    my $complete;
    $response = $self->collect($arg, $response, sub {
	my $buf = ""; #prevent use of uninitialized value in SSLeay.xs
	my $n;
      READ:
	{
	    $n = $socket->read_entity_body($buf, $size);
	    die "Can't read entity body: $!" unless defined $n;
	    redo READ if $n == -1;
	}
	$complete++ if !$n;
        return \$buf;
    } );
    $drop_connection++ unless $complete;

    @h = $socket->get_trailers;
    while (@h) {
	my($k, $v) = splice(@h, 0, 2);
	$response->push_header($k, $v);
    }

    # keep-alive support
    unless ($drop_connection) {
	if (my $conn_cache = $self->{ua}{conn_cache}) {
	    my %connection = map { (lc($_) => 1) }
		             split(/\s*,\s*/, ($response->header("Connection") || ""));
	    if (($peer_http_version eq "1.1" && !$connection{close}) ||
		$connection{"keep-alive"})
	    {
		LWP::Debug::debug("Keep the http connection to $host:$port");
		$conn_cache->deposit("http", "$host:$port", $socket);
	    }
	}
    }

    $response;
};

use HTTP::Message;

sub HTTP::Message::parse {
    my($class, $str) = @_;

    my @hdr;
    while (1) {
	if ($str =~ s/^([^\s:]+)[ \t]*: ?(.*)\n?//) {
            my ($field, $val) = ($1, $2);
            my @val = split /, /, $val;
            s/\r\z// for @val;
            if (@val == 1) {
	        push(@hdr, $field, $val[0]);
            } else {
                push(@hdr, $field, \@val);
            }
	}
	elsif (@hdr && $str =~ s/^([ \t].*)\n?//) {
	    $hdr[-1] .= "\n$1";
	    $hdr[-1] =~ s/\r\z//;
	}
	else {
	    $str =~ s/^\r?\n//;
	    last;
	}
    }
    
    HTTP::Message::new($class, \@hdr, $str);
}

1;
