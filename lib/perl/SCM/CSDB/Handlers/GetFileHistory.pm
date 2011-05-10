package SCM::CSDB::Handlers::GetFileHistory;

use warnings;
use strict;

use Production::Symbols qw/HEADER_FILE/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::FileHistory;

sub handle_request {
    my $req = shift;

    warn "GetFileHistory>>>>>\n";
    warn $req->as_string, "\n";

    my $file   = $req->head(HEADER_FILE);
    my $db = SCM::CSDB::FileHistory->new(database => SCM_CSDB,
					 driver   => SCM_CSDB_DRIVER);

    my $result = $db->getFileHistory($file);
    if(@$result == 0) {
	write_response(
	        -status => [qw /450 Not Found/],   
		-body   => "No csid history found for $file\n",
	);
    } else {
	my $body;
	
	for (@$result) {
	    $body .= join ',' => map { s/\s+$//; $_ } @$_;
	    $body .= "\n";
	}

	write_response(
	        -status => [qw /250 OK/ ],		
		-body => $body,
	);
    }
    warn "<<<<<GetFileHistory\n";
}

1;
