package SCM::CSDB::Handlers::GetCsInfo;

use strict;
use warnings;

use Production::Symbols qw/HEADER_FILE HEADER_CREATOR
                           HEADER_LIBRARY HEADER_REGEX
                           HEADER_START HEADER_END
                           HEADER_STATUS HEADER_ID
                           HEADER_MOVE_TYPE/;
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;
use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::CsInfo;

sub handle_request {
    my $req=shift;

    warn "GetCsInfo>>>>>>>>>";
    warn $req->as_string, "\n";
    
    my $user  = $req->head(HEADER_CREATOR);
    my $file  = $req->head(HEADER_FILE);
    my $lib   = $req->head(HEADER_LIBRARY);
    my $status= $req->head(HEADER_STATUS);
    my $move  = $req->head(HEADER_MOVE_TYPE);
    my $csid  = $req->head(HEADER_ID);
    my $regex = $req->head(HEADER_REGEX);
    my $start = $req->head(HEADER_START);
    my $end   = $req->head(HEADER_END);

    my $db = SCM::CSDB::CsInfo->new(database => SCM_CSDB, 
                                       driver   => SCM_CSDB_DRIVER);
    my $recs = $db->getCsInfo(file   => $file,
			      lib    => $lib,
			      user   => $user,
			      status => $status,
			      move   => $move,
			      csid   => $csid,
			      start  => $start,
			      end    => $end,
			      regex  => $regex);

    warn "exception is $@\n" if $@;
    
    warn "<<<<< result from db is ", scalar @$recs, "\n";

    if (scalar @$recs == 0) {
	write_response(
	   -status => [ qw/450 Not Found/ ],
	    -body => "No Record Found",
	);
    } else {
	my $result;
	$result=join"\t", qw/date|Date|12 user|User|8  
	                     csid|CSID|18 move|Move|4 
			     status|Status|1 file|File|40 
			     lib|Library|20/;
	$result.="\n";
    
	for (@$recs) {
	    for my $elem (@$_) {
		if ($elem =~/^\d\d\d\d-\d\d-\d\d/){
		    my @date =split / /, $elem;
		    $result.=$date[0];
		} else {
		    $result.=$elem;
		}
		$result.="\t";
	    }
	    $result.= "\n";
	}
	
	write_response(
		       -status => [ qw/250 OK/ ],
		       -body => $result,
		       );
    }

    warn "<<<<<GetCsInfo\n";
    
}

1;
