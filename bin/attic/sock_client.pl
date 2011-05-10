#!/usr/local/bin/perl -w
use strict;
use IO::Socket;

use constant DEFAULT_PORT => 9000;
use constant EXIT_SUCCESS => 0;
use constant EXIT_FAILURE => 1;

#------------------------------------------------------------------------------

=head1 SYNOPSIS

  $ sock_client.pl <host[:port]> <command> [<arg>[,<arg>...]]

=head1 DESCRIPTION

This is a simple remote invokation utility that opens a socket to the specified
host and port and sends the command and arguments as a space separated string.
Any response from the remove host is printed to standard output.

=head1 NOTES

The default port number is 9000.

=head1 MAINTAINER

  Peter Wainwright <pwainwright@bloomberg.net>

=head1 SEE ALSO

  L<sock_server.pl>, L<bde_bldmgr>

=cut

#------------------------------------------------------------------------------

sub usage () {
    print <<_USAGE_END;
Usage: sock_client.pl <host> <cmd>
_USAGE_END
}

#------------------------------------------------------------------------------

MAIN: {
    usage() and exit EXIT_FAILURE unless scalar(@ARGV)>=2;

    my ($remote_host,@command) = @ARGV;
    my $remote_port=DEFAULT_PORT;
    if ($remote_host=~s/:(\d+)$//) {
	$remote_port=$1;
    }

    my $sock = new IO::Socket::INET->new(
	 PeerAddr => $remote_host,
	 PeerPort => 9000,
	 Proto    => 'tcp',
	 Type     => SOCK_STREAM
    );

    unless ($sock) {
	print STDERR "!! Failed to initiate connection: $!\n";
	exit EXIT_FAILURE;
    }

    # request
    print $sock join(' ',@command),"\n";
    $sock->flush();

    # response
    print while <$sock>;

    $sock->close();
    exit EXIT_SUCCESS;
}

#------------------------------------------------------------------------------
