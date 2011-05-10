package SCM::CSDB::Handlers::GetChangeSetDbRecord;

use strict;
use warnings;

use Change::Symbols     qw/DEPENDENCY_NAME/;
use Production::Symbols qw($HEADER_ID $HEADER_CREATION_TIME $HEADER_CREATOR 
			   $HEADER_MOVE_TYPE $HEADER_STATUS $HEADER_TICKET
			   $HEADER_STAGE $HEADER_FILE $HEADER_REFERENCE 
			   $HEADER_TASK $HEADER_APPROVER $HEADER_FUNCTION
			   $HEADER_TESTER $HEADER_ID_DEP $HEADER_BRANCH
			   );
use SCM::Symbols        qw/SCM_CSDB SCM_CSDB_DRIVER/;

use SCM::CSDB::Handlers::Common qw/write_response/;
use SCM::CSDB::ChangeSet;

my %headers = (
	       $HEADER_ID            => \&setId,
	       $HEADER_CREATION_TIME => \&setCreationTime,
	       $HEADER_CREATOR       => \&setCreator,
	       $HEADER_MOVE_TYPE     => \&setMoveType,
	       $HEADER_STATUS        => \&setStatus,
	       $HEADER_TICKET        => \&setTicket,
	       $HEADER_STAGE         => \&setStage,
	       $HEADER_FILE          => \&setFile,	        	     
	       $HEADER_FUNCTION      => \&setFunction,
	       $HEADER_TASK          => \&setTask,
	       $HEADER_APPROVER      => \&setApprover,
	       $HEADER_TESTER        => \&setTester,
	       $HEADER_REFERENCE     => \&setReference,
	       $HEADER_ID_DEP        => \&setDependencies,
	       $HEADER_BRANCH        => \&setBranch,
);

sub setId {
    my ($field, $record, $header) = @_;
    $header->{$field} = $record->getID;
}

sub setCreationTime {
    my ($field, $record, $header) = @_;
    my $time = $record->getTime;

    $time =~/\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s(\S+)/;
    my %monthes = ("Jan" => 1,
		 "Feb" => 2,
		 "Mar" => 3,
		 "Apr" => 4,
		 "May" => 5,
		 "Jun" => 6,
		 "Jul" => 7,
		 "Aug" => 8,
		 "Sep" => 9,
		 "Oct" => 10,
		 "Nov" => 11,
		 "Dec" => 12);   
    $header->{$field} = $5.'-'.$monthes{$2}.'-'.$3.' '.$4;   
}

sub setCreator {
    my ($field, $record, $header) = @_;
    $header->{$field} = $record->getUser;
}

sub setMoveType {
    my ($field, $record, $header) = @_;
    $header->{$field} = $record->getMoveType;
}

sub setTicket {
    my ($field, $record, $header) = @_;
    $header->{$field} = $record->getTicket;
}

#maybe need to translate status from num to string
sub setStatus {
    my ($field, $record, $header) = @_;
    my $status = $record->getStatus;
    $header->{$field} = $status .' '.'-';
}

#maybe need to translate stage from num to string
sub setStage {
    my ($field, $record, $header) = @_;
    $header->{$field} = $record->getStage;
}

sub setFile {
    my ($field, $record, $header) = @_;
  
    my @files;

    foreach my $file ($record->getFiles) {
	my ($text, $lib, $target, $from, $to, $type);
	$lib = $file->getLibrary; $lib =~ s/\s+// ;
	$target = $file->getTarget; $target=~ s/\s+//;
	$from = $file->getSource; $from=~s/\s+//;
	$to= $file->getDestination; $to=~s/\s+//;
	$type= $file->getType; $type=~s/\s+//;

	$text="library=".$lib.":target=".$target.":from=".$from.":to=".$to.":type=".$type;
	push @files, $text;
    }
    
    $header->{$field} = \@files if @files;
    
}

sub setReference {
    my ($field, $record, $header) = @_;
    my %ref = $record->getReferences;  
    $header->{$field} =  join ',' => map "$_|$ref{$_}", keys %ref;
}

sub setDependencies {
    my ($field, $record, $header) = @_;
    my $depends = $record->getDependencies;
    $header->{$field} = [ map "$_ " . DEPENDENCY_NAME($depends->{$_}), keys %$depends ];
}

sub setFunction {
    my ($field, $record, $header) = @_;
    my @functions;

    foreach ($record->getFunctions) {
	push @functions, $_;
    }
    $header->{$field} = \@functions if @functions;
}

sub setTask {
    my ($field, $record, $header) = @_;
    my @tasks;

    push @tasks, $_ for $record->getTasks;
    $header->{$field} = \@tasks if @tasks;
}

sub setApprover {
    my ($field, $record, $header) = @_;   
    my $approver = $record->getApprover;

    $header->{$field} = $approver if $approver;
}

sub setTester {
    my ($field, $record, $header) = @_;
    my @testers;

    foreach ($record->getTesters) {
	push @testers, $_;
    }
    $header->{$field} = \@testers if @testers;
}

sub setBranch {
    my ($field, $record, $header) = @_;
    my $branch = $record->getBranch;

    $header->{$field} = $branch if $branch;
}

sub handle_request {
    my $req = shift;

    warn "GetChangeSetDbRecord>>>>>\n";
    warn $req->as_string, "\n";

    my $db = SCM::CSDB::ChangeSet->new(database => SCM_CSDB, 
                                       driver   => SCM_CSDB_DRIVER);

    my $record = $db->getChangeSetDbRecord($req->head($HEADER_ID));

    my %header;
    map { $headers{$_}->($_, $record, \%header)} keys %headers;

    print write_response( -status => [ qw/250 OK/ ],
                          -header => \%header,
                          -body   =>  $record->getMessage,
    );

    warn "<<<<<GetChangeSetDbRecord\n";
}

1;


