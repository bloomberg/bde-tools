package Production::Services::ChangeSet;
use strict;

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(
    createChangeSetDbRecord
    getChangeSetDbRecord
    createPrqsTicket
    createPrqsEmergencyTicket
    createPrqsImmediateTicket
    createPrqsCodeReviewTicket
    createPrqsProgressTicket
    alterChangeSetDbRecordStatus
    alterMultiChangeSetDbRecordStatus
    alterMultiChangeSetStatus
    addDependencyToChangeSet
    deleteDependencyFromChangeSet
    getChangeSetStatus
    getChangeSetHistory
    getLatestSweptCsid
    getDepsOfChangeSet
    getChangeSetReferences
);

use HTTP::Request;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use LWP::UserAgent;
use Production::Services::LWPHack;
use POSIX ();

use Change::Set;

use Production::Symbols qw(
    HEADER_APPROVER
    HEADER_CREATION_TIME
    HEADER_CREATOR
    HEADER_FILE
    HEADER_FUNCTION
    HEADER_REFERENCE
    HEADER_ID           $HEADER_ID
    HEADER_MOVE_TYPE
    HEADER_STAGE
    HEADER_STATUS
    HEADER_TASK
    HEADER_TESTER
    HEADER_TICKET
    HEADER_PRQS_TYPE
    $HEADER_ID_DEP
    HEADER_NEW_STATUS
    HEADER_UPDATER
    HEADER_APPROVER_UUID
    HEADER_TESTER_UUID
    $HEADER_HISTORY
    $HEADER_DEPENDENT_TYPE
    HEADER_BRANCH

    PRQS_TYPE_EMERGENCY
    PRQS_TYPE_IMMEDIATE
    $PRQS_TYPE_CODEREVIEW
    PRQS_TYPE_PROGRESS

    LONG_SVC_TIMEOUT
    SCM_HOST $SCM_HOST

    CSDB_UPDATE_CHANGE_SET_DB_STATUS
    CSDB_MULTI_UPDATE_STATUS
    $CSDB_GET_CHANGE_SET_HISTORY
    $CSDB_GET_DEPS_OF_CHANGE_SET
    $CSDB_GET_CHANGE_SET_REFERENCES

    $BAS_CREATE_PRQS_TICKET
    BAS_GET_MULTI_UUID_BY_UNIX_NAME

    $SCM_ADD_DEPENDENCY
    $SCM_DELETE_DEPENDENCY
    $SCM_GET_CS_STATUS
    $SCM_CREATE_CSDB_RECORD
    $SCM_GET_CSDB_RECORD
    $SCM_GET_LATEST_SWEPT_CSID
);

use Change::Identity qw/identifyProductionName/;
use Production::Services::Util qw/getUUIDFromUnixName getUnixNameFromUUID/;
use Util::Message qw(debug error);

use Change::Symbols qw(USER
                      DEPENDENCY_NAME
                      $DEPENDENCY_TYPE_NONE
                      $DEPENDENCY_TYPE_ROLLBACK
                      $DEPENDENCY_TYPE_CONTINGENT
                      $DEPENDENCY_TYPE_DEPENDENT
                      $DEPENDENCY_TYPE_SIBLING);

#==============================================================================

=head1 NAME

Production::Services::ChangeSet - Access to change set production services from
development

=head1 SYNOPSIS

    use Production::Services;
    use Production::Services::ChangeSet qw(createChangeSetDbRecord
                                           createPrqsTicket
                                           createPrqsEmergencyTicket
                                           createPrqsImmediateTicket
                                           alterChangeSetDbRecordStatus);

    my $svc=new Production::Services;

    createChangeSetDbRecord($svc, $changeset);
    alterChangeSetDbRecordStatus($svc,$changeset,$newstatus);
    my $ticketnum = createPrqsTicket($svc,$changeset,$type);
    my $ticketnum = createPrqsEmergencyTicket($svc, $changeset);
    my $ticketnum = createPrqsImmediateTicket($svc, $changeset);

    # All of the above functions set the error status
    print "Status = ", $svc->getError || "SUCCESS";

=head1 DESCRIPTION

C<Production::ChangeSet> provides a set of global functions for accessing
production-side change-set services from development-side Perl scripts.

=cut

#==============================================================================

# Given a change set, return an HTTP::Headers object containing the
# attributes of the change set. Optional headers may be passed in also.
sub changeSetMakeHTTPHeaders($;@) {
    my ($cs,%headers) = @_;

    my $headers;
    if (ref $cs) {
	$headers = HTTP::Headers->new($cs->metadataHash());
	
	for ($cs->getTasks) {
	    $headers->push_header(HEADER_TASK, $_);
	}

	for ($cs->getTesters) {
	    $headers->push_header(HEADER_TESTER, $_);
	}

	for ($cs->getFunctions) {
	    $headers->push_header(HEADER_FUNCTION, $_);
	}		

    } else {
	$headers = HTTP::Headers->new(HEADER_ID,              $cs,
				      HEADER_CREATOR,         USER);
    }


    # add additional passed-in headers
    $headers->header($_ => $headers{$_}) foreach keys %headers;

    if (ref $cs) {
	for my $file ($cs->getFiles) {
	    my $filestr =  "library=" . $file->getLibrary()
	      . ":target=" . $file->getTarget()
		. ":from="   . $file->getSource()
		  . ":to="     . $file->getDestination()
		    . ":type="   . $file->getType();
	    $headers->push_header(HEADER_FILE,$filestr);
	}

	my $message = $cs->getMessage;
	my $reasonheaders;
	if ($message  =~ /^Change-Set-[-A-Za-z]+: / ) {
	    ($reasonheaders, $message) = split(/\n\n/, $message, 2);

	    while ($reasonheaders =~ /^(Change-Set-[-A-Za-z]+): (.*)$/mg ) {
		$headers->push_header($1, $2);
	    }
	}
    }

    return $headers;
}

sub changeSetComposeHTTPRequest($$;@) {
    my ($command,$cs,%headers) = @_;

    my $headers = changeSetMakeHTTPHeaders($cs,%headers);

    my $message="";
    if (ref $cs) {
	$message = $cs->getMessage;
	if ($message  =~ /^Change-Set-[-A-Za-z]+: / ) {
	    $message = (split /\n\n/, $message, 2)[1];
	}
    } # else it's just a CSID

    my $request;
    $request = HTTP::Request->new("POST",
				  SCM_HOST. "/" . $command,
				  $headers, $message."\n");

    return $request;
}

sub changeSetHTTPTransaction($$$;@) {
    my ($prodSvc, $command, $cs, %headers) = @_;

    debug "[production services] invoking $command for $cs";

    my $request = changeSetComposeHTTPRequest($command, $cs, %headers);
    $prodSvc->sendRequest($request);
    my $response = $prodSvc->readResponse;

    debug "[production services] response for $command on $cs:\n", $response->as_string;

    return $response;
}

#------------------------------------------------------------------------------

=head1 ROUTINES

The following routines are available for export:

=head2 createChangeSetDbRecord($svc,$changeset)

Request that the spcified L<Production::Services> instance create a new
change set database record in the production CSDB using the information
in the provided L<Change::Set> object.

On success, returns true. On failure, returns false and records the reason
for the error so that it may be retrieved with
L<Production::Services/getError>.

=cut

sub createChangeSetDbRecord ($$) {
    my ($svc,$cs) = @_;

    my ($updater_uuid, $approverUuid, @testerUuid);
    my $updater = $cs->getUser;
    my $approver = $cs->getApprover;
    my @testers = $cs->getTesters;
	
    my @unixNames;
    if(defined $updater){	
	push @unixNames, $updater;
    }
    
		
    if (defined $approver) {
	if ($approver =~ /^\d+$/){
	    $approverUuid = $approver;
	} else {	   
	    push @unixNames, $approver;
	}	
    }

# two testers are supportted here 
    if(@testers) {
	if ($testers[0] =~ m/^\d+$/) {
	    $testerUuid[0] = $testers[0];
	} else {	  
	    push @unixNames, $testers[0];
	}
	
	
	if(defined $testers[1]){
	    if ( $testers[1] =~ m/^\d+$/) {
		$testerUuid[1] = $testers[1];
	    } else {		
		push @unixNames, $testers[1];
	    }	
	}
    }
    
   
    my @results = getUUIDByUnixName($svc, @unixNames) if (@unixNames);
    foreach my $pair (@results) {
	my @value;
	
	if( defined $updater && $pair =~ /$updater/) {
	    @value = split (/:/, $pair);
	    $updater_uuid = $value[1];
	}
	    
	if(defined $approver && $pair =~ /$approver/) {
	    @value = split (/:/, $pair);
	    $approverUuid = $value[1];
	}
	    
	if(@testers ) {
	    if($pair =~ $testers[0]) {
		@value = split (/:/, $pair);
		$testerUuid[0] = $value[1];
	    } elsif (defined $testers[1] && $pair =~ /$testers[1]/) {
		@value = split (/:/, $pair);
		$testerUuid[1] = $value[1];
	    }
	}
    }
    

    foreach (@testerUuid) {
	$_ ||= 0;
    }
	
    my $ua = LWP::UserAgent->new;
    my $header = changeSetMakeHTTPHeaders($cs,  
					  HEADER_UPDATER() => $updater_uuid || 0,
					  HEADER_APPROVER_UUID() =>$approverUuid || 0,
					  HEADER_TESTER_UUID() => \@testerUuid);

    my $req = HTTP::Request->new(POST => "$SCM_HOST/$SCM_CREATE_CSDB_RECORD", 
				$header, $cs->getMessage);

    debug($req->as_string);

    my $response = $ua->request($req);

    debug($response->as_string);
    
    if ($response->code == 250) {
        return 1;
    } else {
        $svc->setError($response->content || "<Error>");
        return undef;
    }
}

=head2  getChangeSetDbRecord($svc, $changeset)

Request that the spcified L<Production::Services> instance retrieve a 
change set database record in the production CSDB using change set id
in the provided L<Change::Set> object.

On success, returns change set object. On failure, returns undef and 
the reason for the error may be retrieved with
L<Production::Services/getError>.

=cut

my %STRING2DEP = (
        DEPENDENCY_NAME($DEPENDENCY_TYPE_NONE)          => $DEPENDENCY_TYPE_NONE,
        DEPENDENCY_NAME($DEPENDENCY_TYPE_ROLLBACK)      => $DEPENDENCY_TYPE_ROLLBACK,
        DEPENDENCY_NAME($DEPENDENCY_TYPE_CONTINGENT)    => $DEPENDENCY_TYPE_CONTINGENT,
        DEPENDENCY_NAME($DEPENDENCY_TYPE_DEPENDENT)     => $DEPENDENCY_TYPE_DEPENDENT,
        DEPENDENCY_NAME($DEPENDENCY_TYPE_SIBLING)       => $DEPENDENCY_TYPE_SIBLING,
);

sub getChangeSetDbRecord($$;$) {
    my($svc, $cs, $noprodcalc) = @_;
       
    my $ua = LWP::UserAgent->new; 
    my $header = HTTP::Headers->new(
	    $HEADER_ID           => (ref $cs ?$cs->getID:$cs),
	    'Content-Length'     => length 'DUMMY',
	    ); 
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$SCM_GET_CSDB_RECORD",
				         $header, 'DUMMY');
    my $response = $ua->request($req);
    if ($response->code == 250) {
	my ($header, @headerarr, $changeset);	
	my ($csid, $creator, $creation_time,
	    $move_type, $stage_type, $status,
	    $msg, $tkt, $approver, $branch);
	my (@filestrs, @message, %deps, %refs, @funcs, @testers, @tasks);

	$header =$response->as_string;
	$header =~ s/(200 OK)\s+//;
	
	@headerarr = split /\n|\t/, $header;
	
	foreach (0..$#headerarr) {
	    if($headerarr[$_] =~ /Change-Set-ID:\s*(\w+)/) {
		$csid = $1;
	    } elsif($headerarr[$_] =~ /Change-Set-Creator:\s*([-\w]+)/) {
		$creator = $1;
	    } elsif($headerarr[$_] =~ 
		    /Change-Set-Creation-Time:\s*(\S+)\s(\w+\W\w+\W\w+)/){
                my ($date, $time) = ($1, $2);
                my ($year, $month, $day) = split /-/, $date;
                my ($hour, $min, $sec) = split /:/, $time;
                $creation_time = POSIX::strftime("%a %b %e $time $year",
						 $sec, $min, $hour, 
                                                 $day, $month-1, $year - 1900);
	    } elsif($headerarr[$_] =~ /Change-Set-Move-Type:\s*(\w+)/) {
		$move_type = $1;
		$move_type =~ tr/A-Z/a-z/;
	    } elsif($headerarr[$_] =~ /Change-Set-Stage:\s*(\w+)/) {
		$stage_type = lc($1);
	    } elsif($headerarr[$_] =~ /Change-Set-Status:\s*(\w)\s*-/) {
		$status = $1;
	    } elsif($headerarr[$_] =~ /Change-Set-Ticket:\s*(\w+)/) {
		$tkt = $1;
	    } elsif($headerarr[$_] =~ /Change-Set-File:\s*(\S+)/) {
		push @filestrs, $1;	
            } elsif($headerarr[$_] =~ /Change-Set-Reference:\s*(.*)/) {
                my $str = $1;
                for (split /,/, $str) {
                    my ($type, $val) = split /\|/;
                    $refs{$type} = $val;
                }
            } elsif($headerarr[$_] =~ /Change-Set-Dependencies:\s*(.*)/) {
                for (split /,/, $1) {                   
		    my ($csid, $type) = split /\|/, $_;
                    $deps{$csid} = $type;
                }
            } elsif($headerarr[$_] =~ /Change-Set-Function:\s*(.*)/) {
		push @funcs, $1;
	    } elsif($headerarr[$_] =~ /Change-Set-Task:\s*(.*)/) {
		push @tasks, $1;
	    } elsif($headerarr[$_] =~ /Change-Set-Tester:\s*(.*)/) {
		push @testers, $1;
	    } elsif($headerarr[$_] =~ /Change-Set-Approver:\s*(.*)/) {
		$approver = $1;
	    } elsif($headerarr[$_] =~ /Change-Set-Branch: \s*(.*)/) {
		$branch = $1;
	    } elsif($headerarr[$_] =~ /Change-Set-ID-DEP:\s*(\w+) ([A-Z]+)/) {
                $deps{$1} = $STRING2DEP{ $2 };
            }
	}

	$msg = "";
	foreach (00..$#message) {
	    $msg = $msg .$message[$_]."\n";
	}

	if($msg) {
	    $msg = $msg ."\n".$response->content;
	} else {
	    $msg = $response->content;
	}

	while ($msg =~ m/((Change-Set-(?:Tester|Approver):\s+)(\d+)(\n|\z))/) {
	  my ($match,$header,$value,$end) = ($1,$2,$3,$4); 
	  $value = getUnixNameFromUUID($value);
	  $msg =~ s/$match/$header$value$end/ if defined($value);
	}

	$changeset = new Change::Set({csid=>$csid, when=>$creation_time,
				     user=>$creator, ticket=>$tkt, 
				     stage=>$stage_type, move=>$move_type, 
				     message=>$msg, status=>$status,
				     depends=>\%deps, reference=>\%refs,
				     functions=>\@funcs, testers=>\@testers,
				     tasks=>\@tasks, approver=>$approver,
				     branch=>$branch});

	
	
	if(defined $changeset) {	 
	    foreach (0..$#filestrs) {
		my($library, $target, $destination, $source,$type,$prod);

		if($filestrs[$_]
		=~ /library=(\S+):target=(\S+):from=(\S+):to=(\S+):type=(\S+)/) {
		    $library = $1;
		    $target = $2;
		    $source = $3;
		    $destination = $4;		  
		    $type = $5;
                    if ($noprodcalc) {
                        $prod = '';
                    } else {
                        $prod = identifyProductionName($target, $stage_type);
                    }
                    $changeset->addFile($target, $source, $destination,
                                        $type, $library,$prod);	
		}	
	    }
	    return $changeset;
	} else {
	    print "Could not create change set\n";
	    return undef;
	}

       
    } else {
        $svc->setError($response->content || "<Error to Get ChangeSet>");
        return;
    }
}

sub getChangeSetStatus ($$) {
    my ($svc, $csid) = @_;

    my $header = HTTP::Headers->new(
            $HEADER_ID          => $csid,
            'Content-Length'    => length 'DUMMY',
            );

    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_GET_CS_STATUS",
            $header, 'DUMMY');

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    if ($response->code == 250) {
        my ($status) = 
            $response->header('Change-Set-Status') =~ /^(.)/;
        return $status;
    }

    $svc->setError($response->content) if UNIVERSAL::can($svc, "setError");
    return;
}

=head2 getChangeSetHistory($svc, $csid, [$resolve_uuid])

Given the change set ID I<$csid>, returns the status history for
that change set provided it exists in the data base.

Returns a two element list with the second element being an error string
if the history could not be retrieved. Otherwise, returns an array-ref
of references to a three element list, the first element of which
being the date of a status change, the second the new status and the
third the UUID of the user who made the status change.

If I<$resolve_uuid> is true, each status list contains an additional
fourth element being the unix name belonging to the UUID unless
it is zero.

The array-ref history is chronologically sorted from oldest to most
recent change.

=cut

sub getChangeSetHistory ($$;$) {
    my ($svc, $csid, $resolve_uuid) = @_;

    my $header = HTTP::Headers->new($HEADER_ID  => $csid);
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$CSDB_GET_CHANGE_SET_HISTORY",
                                 $header);

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return (0, $response->content) if $response->code != 250;

    my @rec; my $n = 0;
    while (my $h = $response->header("$HEADER_HISTORY-" . $n++)) {
        my ($date, $status, $uuid) = split /#/, $h;
        $date =~ s/\.\d+$//;
        $status =~ s/-.*//;
        push @rec, [ $date, $status, $uuid, $resolve_uuid && $uuid
                                                ?  getUnixNameFromUUID($uuid)
                                                : ()];
    }

    return \@rec;
}

sub getDepsOfChangeSet($$$){
    my ($svc, $csid, $type) = @_;

    my $header = HTTP::Headers->new($HEADER_ID => $csid);
    $header->push_header($HEADER_DEPENDENT_TYPE => $type);
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$CSDB_GET_DEPS_OF_CHANGE_SET",
				 $header);
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);
    
    return (0, $response->content) if $response->code != 250;

    my %csids;
    my @files = grep ((not /^\s*$/) => split /\n/, $response->content);
    
    for (@files) {
	my ($csid, %rest) = split /,/;
	
	$rest{$_} ||= '<placeholder>' for qw/status user timestamp/;
	$rest{'file:<placeholder>'} = '<placeholder>' unless
	    grep /^file:/, keys %rest;
	$csids{$csid} = \%rest;	
    }   

    %csids and return \%csids;
    return 0;
}


sub getChangeSetReferences {
    my ($csid, $type) = @_;
    my $header = HTTP::Headers->new($HEADER_ID => $csid);
    
    my $req = HTTP::Request->new(POST => "$SCM_HOST/$CSDB_GET_CHANGE_SET_REFERENCES",
				 $header);
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    return (0, $response->content) if $response->code != 250;

    my @refs =
        map { s/^\s*//; s/\s*$//; $_ }
        grep /\S/ => 
        split /\n/ => $response->content;

    my @tickets;

    for my $ref (@refs) {
        my ($ref_type, $ref_val) = split /,/, $ref;

        if (defined $type) {
            next unless defined $ref_type;
            next unless uc $type eq uc $ref_type;
        }

        push @tickets, [ uc $ref_type, $ref_val ];
    }
    
    return \@tickets;
}

=head2 alterChangeSetDbRecordStatus($svc,$changeset,$newstatus,[$user])

Request that the specified L<Production::Services> instance alter the status
of the specified L<Change::Set> object in the production change set database.
The change set should already have been entered into the database with
L<"createChangeSetDbRecord"> prior to calling this function.

If the change set instance has a status set already then this status is
checked against the current status of the change set in the production
database, and the transition only permitted if the state agrees.

The optional argument I<$user> specifies the user under which the update
should be recorded.

On success, returns true. On failure, returns false and records the reason
for the error so that it may be retrieved with
L<Production::Services/getError>.

=cut

sub alterChangeSetDbRecordStatus ($$$;$) {
    my ($svc,$cs,$type,$user)=@_;
    
    # set the user to make sure it set correctly 
    if (ref $cs) {
	$cs->setUser($user || USER);
    }
    my $uuid;
     
    my @result = getUUIDByUnixName($svc, $user || USER);	
    my @value = split(/:/, $result[0]) if(@result);
    $uuid = $value[1] if(@value);
    

    my $response;
    $response = changeSetHTTPTransaction($svc,
					 CSDB_UPDATE_CHANGE_SET_DB_STATUS,
					 $cs,
					 HEADER_NEW_STATUS() => $type,
					 HEADER_UPDATER() => ($uuid || 0),
					 );  
    if ($response->is_success) {
        return 1;
    } else {
        $svc->setError($response->content || "<Error>");
        return;
    }
}

sub alterMultiChangeSetDbRecordStatus ($$@) {
    my ($svc,$type, @csids)=@_;
    return alterMultiChangeSetStatus($svc, $type, \@csids);
}

=head2 alterMultiChangeSetStatus($svc,$newstatus,\@changeset,[$user])

Request that the specified L<Production::Services> instance alter the status
of the multiple Change Set IDs in the production change set database to 
the new status.

Prerequisite conditions for L<"alterChangeSetDbRecordStatus"> apply to
L<"alterMultiChangeSetDbRecordStatu"> as well.

On success, returns true. If any of change set fail to update to the new status,
returns false and records the reason for the error so that it may be retrieved
with L<Production::Services/getError>.

I<$user> is an optional value specifying the user which should perform
the update.

=cut

sub alterMultiChangeSetStatus {
    my ($svc, $type, $csids, $username) = @_;

    my $user = $username || USER;
    my $uuid;
   
    my @result = getUUIDByUnixName($svc, $user);
    my @value = split(/:/, $result[0]) if @result;
    $uuid = $value[1];
    

    my $headers;
    if(defined $uuid) {
	$headers = HTTP::Headers->new(HEADER_NEW_STATUS,   $type,
				      HEADER_UPDATER() => $uuid);
    } else {	 
	$headers = HTTP::Headers->new(HEADER_NEW_STATUS,   $type,
				      HEADER_CREATOR() => $user);
    }

    $headers->push_header(HEADER_ID, $_) foreach @$csids;
    
    my $request = HTTP::Request->new("POST", 
                                     SCM_HOST. "/" .
                                     CSDB_MULTI_UPDATE_STATUS,
                                     $headers, "");
    $svc->sendRequest($request, LONG_SVC_TIMEOUT);
    my $response = $svc->readResponse();

    return 1 if $response->is_success;

    $svc->setError($response->content || "<Error>");
    return;
}

=head2 getUUIDByUnixName($svc, @unixname)

=cut

sub getUUIDByUnixName {
    my($svc, @unixname)=@_;

    my $header = HTTP::Headers->new();

    foreach my $user (@unixname){
	$header->push_header(HEADER_TESTER, $user);
    }

    my $request = HTTP::Request->new("POST",
				     SCM_HOST."/".
				     BAS_GET_MULTI_UUID_BY_UNIX_NAME,
				     $header, "dummy");    

    my $response = $svc->sendRequest($request);
    
    
    if ($response->is_success) {
        my @pairs = split(/;/, $response->content);
        return @pairs;
    }
}

=head2 addDpendencuyToChangeSet ($svc,$csid,$dependsOn,$type)

Adds a dependency of type I<$type> on change set with the ID I<$dependsOn>
to the change set given through ID I<$csid>.

Returns a true value if the operation succeeds. False otherwise.

=cut

{
    my %DEP2STRING = (
            $DEPENDENCY_TYPE_NONE       => 'NONE',
            $DEPENDENCY_TYPE_ROLLBACK   => 'ROLLBACK',
            $DEPENDENCY_TYPE_CONTINGENT => 'CONTINGENT',
            $DEPENDENCY_TYPE_DEPENDENT  => 'DEPENDENT',
            $DEPENDENCY_TYPE_SIBLING    => 'SIBLING',
            );

    use constant DUMMY => 'DUMMY';

    sub addDependencyToChangeSet {
        my ($svc, $csid, $depends_on, $type) = @_;

        my $depstring = $DEP2STRING{ $type }
        or do {
            error "$type: Invalid dependency type";
            return;
        };

        my $header = HTTP::Headers->new(
                $HEADER_ID          => $csid,
                $HEADER_ID_DEP      => "$depends_on $depstring",
                'Content-Length'    => length DUMMY,
                );

        my $req = HTTP::Request->new(
                POST => "$SCM_HOST/$SCM_ADD_DEPENDENCY",
                $header, DUMMY);

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($req);

        return 1 if $response->code == 250;

        $svc->setError($response->content) if UNIVERSAL::can($svc, "setError");
        return 0;
    }

    sub deleteDependencyFromChangeSet {
        my ($svc, $csid, $depends_on, $type) = @_;

        my $depstring = $DEP2STRING{ $type }
        or do {
            error "$type: Invalid dependency type";
            return;
        };

        my $header = HTTP::Headers->new(
                $HEADER_ID          => $csid,
                $HEADER_ID_DEP      => "$depends_on $depstring",
                'Content-Length'    => length DUMMY,
                );

        my $req = HTTP::Request->new(
                POST => "$SCM_HOST/$SCM_DELETE_DEPENDENCY",
                $header, DUMMY);

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request($req);

        return 1 if $response->code == 250;

        $svc->setError($response->content) if UNIVERSAL::can($svc, "setError");
        return 0;
    }
}

=head getLatestSweptCsid($svc,$file)

Returns information pertaining to the most recently swept change set for
I<$file> (a plain string). Returns a three element list ($creator, $movetype,
$csid) or the empty list in case of errors.

=cut

sub getLatestSweptCsid {
    my ($svc, $file) = @_;

    my $base;
    if (UNIVERSAL::isa($file, 'Change::File')) {
        $base = $file->getLeafName;
    } else {
        require File::Basename;
        $base = File::Basename::basename($file);
    }

    my $header = HTTP::Headers->new(
            &HEADER_FILE        => $base,
            'Content-Length'    => 0,
    );

    my $req = HTTP::Request->new(
            POST => "$SCM_HOST/$SCM_GET_LATEST_SWEPT_CSID", $header);

    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($req);

    if ($response->code != 250) {
        $svc->setError($response->content || $response->message)
            if UNIVERSAL::can($svc, "setError");
        return;
    }

    my ($creator, $movetype, $csid) = split / /, $response->content;
    
    # does the right thing in scalar context (returning $csid)
    return ($creator, $movetype, $csid);
}

=head2 createPrqsTicket($svc,$changeset,$type)

Request that the specified L<Production::Services> instance create a new
PRQS ticket for the specified change set. The change set should already have
been entered into the database with L<"createChangeSetDbRecord"> prior to
calling this function.

The PRQS ticket type is specified as the third argument and should be one of
the C<PRQS_TYPE_*> symbols defined in L<Change::Symbols>. Currently valid
types are C<PRQS_TYPE_EMERGENCY> and C<PRQS_TYPE_IMMEDIATE>. Alternatively
one of the convenience functions below can be used.

On success, returns the (integer) ticket number of the created ticket. On
failure, returns false and records the reason for the error so that it may be
retrieved with L<Production::Services/getError>.

=head2 createPrqsEmergencyTicket($svc,$changeset)

Convenience wrapper for L<"createPrqsTicket> to create a PRQS ticket for an
emergency move (a.k.a. EMOV).

=head2 createPrqsImmediateTicket($svc,$changeset)

Convenience wrapper for L<"createPrqsTicket> to create a PRQS ticket for an
immediate move (a.k.a. 'Straight-Through Processing' or STP).

=cut

sub createPrqsTicket ($$$;$) {
    my ($svc,$cs,$type,$reviewer) = @_;

    my $ua = LWP::UserAgent->new;
    my $header = changeSetMakeHTTPHeaders($cs, 
					  HEADER_PRQS_TYPE() => $type);
     
    if ($type eq $PRQS_TYPE_CODEREVIEW and $reviewer) {
	$header->remove_header(HEADER_APPROVER) if $header->header(HEADER_APPROVER);
	$header->push_header(HEADER_APPROVER, $reviewer) ;
    }

    my $req = HTTP::Request->new(POST => "$SCM_HOST/$BAS_CREATE_PRQS_TICKET",
				 $header, $cs->getMessage);
    
    my $response = $ua->request($req);
   
    if ($response->code == 250) {
        return $response->content + 0;  # Content contains PRQS Ticket number
    } else {
        $svc->setError($response->content || "<Error>");
        return undef;
    }
}

# PRQS EM
sub createPrqsEmergencyTicket ($$) {
    return createPrqsTicket($_[0],$_[1],PRQS_TYPE_EMERGENCY);
}

# PRQS ST
sub createPrqsImmediateTicket ($$) {
    return createPrqsTicket($_[0],$_[1],PRQS_TYPE_IMMEDIATE);
}

# PRQS PG
sub createPrqsProgressTicket ($$) {
    return createPrqsTicket($_[0],$_[1],PRQS_TYPE_PROGRESS);
}

# PRQS CR
sub createPrqsCodeReviewTicket ($$$) {
    return createPrqsTicket($_[0],$_[1],$PRQS_TYPE_CODEREVIEW,$_[2]);
}

#==============================================================================

=head1 AUTHOR

Pablo Halpern (phalpern@bloomberg.net)

=head1 SEE ALSO

L<Production::Services>, L<Production::Services::Move>

=cut

1;
