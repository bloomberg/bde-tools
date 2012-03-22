#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Socket;
use FileHandle;

use Util::Retry qw(retry_open3);

#------------------------------------------------------------------------------

use constant DEFAULT_PORT    => 9000;
use constant DEFAULT_LOGFILE => "P:/bde_build/logs/sock_server.$$.log";
use constant EXIT_SUCCESS    => 0;
use constant EXIT_FAILURE    => 1;

#------------------------------------------------------------------------------

autoflush STDOUT 1;

#------------------------------------------------------------------------------

sub alert (@) {
    print LOG "** ",@_,"\n";
    print "** ",@_,"\n";
}

sub error (@) {
    print LOG "!! ",@_,"\n";
    print "!! ",@_,"\n";
}

sub message (@) {
    print LOG "-- ",@_,"\n";
    print "-- ",@_,"\n";
}

sub logline (@) {
    print LOG "<< ",@_,"\n";
    print "<< ",@_,"\n" if $_[0]=~/[*!]{2}\s/;
}

#------------------------------------------------------------------------------

sub gather_output {
    my ($cmd)=@_;
    my @cmd=split /\s+/,$cmd;
    my $gotoutput=0;

    my ($rdfh,$wrfh)=(new IO::Handle,new IO::Handle);
    my $pid=retry_open3($rdfh,$wrfh,$rdfh,@cmd);
    close $wrfh;

    while (my $line=<$rdfh>) {
        chomp $line;
	$gotoutput ||= 1;
	logline($line);
	print CLIENT "<< ",$line,"\n";
    }

    unless ($gotoutput) {
	message("no output from command");
    }

    # clean up and return exit status
    waitpid $pid,0;
    return $?;
}

#------------------------------------------------------------------------------

MAIN: {
    my $port=DEFAULT_PORT;
    $port=shift @ARGV if @ARGV;

    my $logfile=DEFAULT_LOGFILE;
    $logfile=shift @ARGV if @ARGV;

    open(LOG, ">$logfile") or die "Unable to open $logfile for writing: $!";
    autoflush LOG 1;

    socket(SERVER, AF_INET, SOCK_STREAM, getprotobyname('tcp'));
    autoflush SERVER 1;
    setsockopt(SERVER, SOL_SOCKET, SO_REUSEADDR, 1);
    my $server_addr = sockaddr_in($port, INADDR_ANY);

    alert("server initializing at ", scalar localtime);
    message("logging to $logfile");
    error("bind failed: $!"), exit EXIT_FAILURE
      unless bind(SERVER, $server_addr);
    error("listen failed: $!"), exit EXIT_FAILURE
      unless listen(SERVER, SOMAXCONN);
    message("listening for connections on port $port...");

    my $nrequest=0;
    my $code;
    while ($code=accept(CLIENT, SERVER)) {
	autoflush CLIENT 1;
	my $command = <CLIENT>;
	chomp $command;
	
	$nrequest++;
	alert("request $nrequest received at ", scalar localtime);
	message("command $nrequest: $command");

	# invoke command, send output to STDOUT, LOG, CLIENT
	my $rc = gather_output($command);

	message "command $nrequest exit status $nrequest: ".($rc>>8);
	alert "command $nrequest exited on signal ".($rc & 127) if $rc & 127;
	
	close CLIENT;
    }

    alert("shutting down ($code)");
}
