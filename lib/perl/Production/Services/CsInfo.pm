package Production::Services::CsInfo;

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK=qw/getCsInfo/;

use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;

use Production::Symbols qw(
    HEADER_CREATOR
    HEADER_FILE
    HEADER_ID
    HEADER_MOVE_TYPE
    HEADER_BRANCH
    HEADER_STAGE
    HEADER_STATUS
    HEADER_GLOB
    HEADER_LIBRARY
    HEADER_START
    HEADER_END
    HEADER_STATUS
    HEADER_ID

    CSDB_GET_CS_INFO
    SCM_HOST
    HTTP_METHOD
);


sub getCsInfo {
    my ($svc, $arg)=@_;
    
    my $start=$arg->{start}                  if $arg->{start};
    my $end=$arg->{end}                      if $arg->{end}; 
    my @user=@{$arg->{user}}                 if $arg->{user};
    my @lib=@{$arg->{lib}}                   if $arg->{lib};
    my @file=@{$arg->{file}}                 if $arg->{file};    
    my @status=@{$arg->{status}}             if $arg->{status};
    my @move=@{$arg->{move}}                 if $arg->{move};
    my @branch=@{$arg->{branch}}             if $arg->{branch};
    my @csid=@{$arg->{csid}}                 if $arg->{csid};
    my $glob=$arg->{glob}                    if $arg->{wild};             
    
    my $headers=HTTP::Headers->new(HEADER_START, $start,
				   HEADER_END, $end);
    
    map {$headers->push_header(HEADER_CREATOR, $_)} @{$arg->{user}};
    map {$headers->push_header(HEADER_FILE, $_)} @file;
    map {$headers->push_header(HEADER_LIBRARY, $_)} @lib;
    map {$headers->push_header(HEADER_STATUS, $_)} @status;
    map {$headers->push_header(HEADER_MOVE_TYPE, $_)} @move;
    map {$headers->push_header(HEADER_BRANCH, $_)} @branch;
    map {$headers->push_header(HEADER_ID, $_)} @csid;
    $headers->push_header(HEADER_GLOB, $glob);

    my $request=HTTP::Request->new(HTTP_METHOD,
				  SCM_HOST . "/". CSDB_GET_CS_INFO,
				  $headers, "dummy\n");
    $request->protocol("HTTP/1.1");

    $svc->sendRequest($request);
    my $response=$svc->readResponse;
    
    if($response->is_success) {
	return $response->content;
    } else {
	$svc->setError("Error getting cs info: ".$response->content);
	return undef;
    }

}

1;
