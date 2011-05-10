package Change::DB;
use strict;

use base qw(BDE::Object);

use Time::HiRes;
use IO::File   (); # a really simple 'database', for now
use File::Path ();

use Change::Set;
use Change::Symbols qw(
    $STATUS_SUBMITTED $STATUS_ACTIVE $STATUS_ROLLEDBACK $STATUS_REINSTATED
    $STATUS_WAITING $STATUS_FAILED $STATUS_COMPLETE $STATUS_WITHDRAWN CS_DATA

    $DBDELIMITER FILE_IS_CHANGED
    USER
    DEPENDENCY_TYPE_ROLLBACK STAGE_INTEGRATION MOVE_REGULAR
);

use Util::Message qw(fatal debug error warning);

my $reinstatable_status_re=
  "(?:$STATUS_ROLLEDBACK|$STATUS_FAILED|$STATUS_WITHDRAWN|$STATUS_COMPLETE)";
my $rollbackable_status_re=
  "(?:$STATUS_SUBMITTED|$STATUS_ACTIVE|$STATUS_WAITING)";

#==============================================================================

=head1 NAME

Change::DB - Read/write change set data from/to underlying database.

=head1 SYNOPSIS

    my $changedb=new Change::DB "/path/to/change.db";
    my $csid=$changedb->createChangeSet($user,$stage,$ticket,$message);
    $changedb->addFileToChangeSet($csid,$library,$sourcefile,$destinationfile);
    ...
    $changedb->rollbackChangeSet($csid);
    ...
    $changedb->reinstateChangeSet($csid);

=head1 DESCRIPTION

C<Change::DB> manages the storage and retrieval of change set information in
an underlying database. The mechanics of the database operation are hidden
from the user.

To create a change set, first use the L<"createChangeSet"> method to record
the master record and return a unique ID for the change set. This unique ID
is then used in calls to L<"addFileToChangeSet"> for as many files as there
are to add to the change set. For each file, the unit of release (a.k.a
product, application, or library), and the source and destination filenames
must be supplied.

=head1 NOTE

This module assumes that an appropriate locking mechanism is in place before
the methods provided here are invoked, e.g. by L<Util::File::NFSLock>. It does
I<not> attempt to verify atomic operations internally.

=head1 TO DO

In Phase 0, the database is in fact a flat file. This will change in future
phases, but the interface will remain the same apart from naturally evolving
extensions. A filehandle is opened to the dastabase file on construction and
is automatically closed when the database object is destroyed.

=cut

#==============================================================================

=head1 CONSTRUCTORS

=head2 new($dbpath)

Construct a new C<Change::DB> object using the specified database filename.
If the database does not exist, it is created. The database file remains open
until the object is destroyed. If the database object cannot be created, an
exception is thrown.

By default the database is opened for update (mode C<+E<lt>>), which will
present a problem for non-privileged clients in scenarios where write access to
the database is restricted. For these clients to open the database read-only,
prefix the database path with C<E<lt>>.

=cut

sub fromString ($$) {
    my ($self,$init)=@_;

    my $mode="+<"; #read/update by default
    $self->{writable}=1;
    if ($init=~/^(<)\s*(.*?)$/) {
	$mode=$1; $init=$2; #mode override
	$self->{writable}=0;
    }

    unless (-f $init) {
	$self->throw("Unable to create $init: $!\n")
	  if system "touch",$init;
    }
    $self->{fh}=new IO::File($init,$mode);
    $self->throw("Unable to access $init: $!\n")
      unless defined $self->{fh};
    $self->{fh}->autoflush(1);

    ## Open a second handle in append mode (if $mode is not read-only)
    ## This is an attempt to thwart NFS issues we have been seeing.
    ## The filehandle above will be used for reading and writing only single
    ## chars, and this filehandle will be used for writes that append to file
    unless ($mode eq "<") {
	$self->{fhappend}=new IO::File($init,">>");
	$self->throw("Unable to access $init: $!\n")
	  unless defined $self->{fhappend};
	$self->{fhappend}->autoflush(1);
    }

    unless (-f $init.".log") {
	$self->throw("Unable to create ${init}.log: $!\n")
	  if system "touch",$init.".log";
    }
    $self->{logfh}=new IO::File($init.".log",$mode eq "<" ? "<" : "+>>");
    $self->throw("Unable to access ${init}.log: $!\n")
      unless defined $self->{logfh};
    $self->{logfh}->autoflush(1);

    debug "opened change database $init";
    return $self;
}

#------------------------------------------------------------------------------

# cache of file positions at start of change sets

sub _csid_pos ($$;$) {
    my($self,$csid,$pos) = @_;  ## csid should be passed upper-cased
    return (defined $pos)
      ? ($self->{offsets}{$csid} = $pos)
      : $self->{offsets}{$csid};
}

# write change set record out into separate file (one per change set)
# to allow for a recovery mechanism should the flat file become corrupt

sub _audit_record ($$$$) {
    my($self,$csid,$record,$not_on_scm) = @_;

    $csid = uc $csid;
    unless ($self->{auditfh} && $self->{audit_csid} eq $csid) {
	close $self->{auditfh} if $self->{auditfh};
	my $audit_dir  = CS_DATA."/logs/db/".substr($csid,-2);
	File::Path::mkpath($audit_dir,0,0775) unless (-d $audit_dir);

	my $audit_path = $audit_dir."/$csid.log";
	$self->{auditfh}=new IO::File($audit_path,">>");
	$self->throw("Unable to access $audit_path: $!\n")
	  unless defined $self->{auditfh};
	$self->{auditfh}->autoflush(1);
	$self->{audit_csid} = $csid;
    }
    $self->{auditfh}->print($$record);
}

# update status in individual file containing change set info

sub _update_cs_status ($$$;$) {
    my($self,$csid,$status,$user) = @_;  ## csid should be passed upper-cased
    my $audit_path = CS_DATA."/logs/db/".substr($csid,-2)."/$csid.log";
    my $FH = new IO::File($audit_path,"+<");
    unless ($FH) {
	$self->logEvent($csid, "failed to update $audit_path to status $status",
			$user);
	return;
    }
    ## read through file, store position of beginning of each line,
    ## and then go back and change the status (first char) on each line
    my @pos = (0);
    push @pos,tell($FH) while (defined(<$FH>));
    pop @pos;
    seek($FH,$_,0) && $FH->print($status) foreach (@pos);
    close $FH;
}

# read in change set from individual file

sub _get_cs_file ($$) {
    my($self,$csid) = @_;
    my $stream = "delimiter=($DBDELIMITER)";
    my $audit_path = CS_DATA."/logs/db/".substr($csid,-2)."/$csid.log";
    my $i = 1+length($DBDELIMITER)*2+length($csid); # (e.g. "<state>:<csid>:")
    my $FH = new IO::File($audit_path,"<");
    return undef unless $FH;
    $stream .= <$FH>;
    $stream .= substr($_,$i) while (<$FH>);
    close $FH;
    return new Change::Set($stream);
}

sub _trawl_db ($;$) {
    my($self,$time) = @_;
    my $cs_match=qr/^\0*[A-Z]${DBDELIMITER}(-?[0-9A-F]+)${DBDELIMITER}(.*)/s;
    $time = sprintf("%X",$time || 0);

    my($csid,$lines,$audit_path,$FH,$stream);
    my $fh=$self->{fh};
    seek $fh,0,0;
    $fh->input_line_number(0);
    my $line = <$fh>;
    while (defined($line)) {
	if ($line =~ $cs_match) {
	    $csid = $1;
	    if (substr($csid,0,1) eq '-' || (substr($csid,0,8) cmp $time) < 0) {
		$line = <$fh>;
		next;
	    }
	}
	else {
	    error("CORRUPT line (",$fh->input_line_number,"): $line");
	    $line = <$fh>;
	    next;
	}
	unless (substr($2,0,7) eq "created") {
	    error("Error parsing DB - saw:\n\t${line}before master record")
	      unless (substr($csid,0,1) eq '-');
	    $line = <$fh>;
	    next;
	}
	$line =~ s/^\0+//;
	$lines = $line;
	while (defined($line=<$fh>) && $line =~ $cs_match && $csid eq $1) {
	    $lines.=$line;
	}

	$stream = "";
	$audit_path = CS_DATA."/logs/db/".substr($csid,-2)."/$csid.log";
	$FH = new IO::File($audit_path,"<");
	if ($FH) {
	    local $/ = undef;
	    $stream = <$FH>;
	    close $FH;
	}

	unless ($stream eq $lines) {
	    -f $audit_path
	      ? error("MISMATCH: $csid")
	      : error("DOES NOT EXIST: $audit_path");

	      #: $self->_audit_record($csid,\$lines);  # generate if missing
	}
    }
}

#------------------------------------------------------------------------------

=head1 METHODS

=head2 isWritable()

Return true if the database is open for update, or false if it is open
read-only. See C<"new">.

=cut

sub isWritable ($) {
    return $_[0]->{writable} ? 1 : 0;
}

=head2 createChangeSet($user,$ticket,$stage,$move,$msg,[$status[,$files]])

Create a master record for a new change set, returning the unique change set
ID on success, or throwing an exception on failure.

The user should be the login name of the user (e.g. C<getpwuid($<)>. The
stage should be derived from one of the stage constants such as
C<STAGE_PRODUCTION> found in L<Change::Symbols>. The ticket should be a string
describing the ticket in the form DRQSE<lt>NNNNNNNE<gt> or TREQE<lt>NNNNNE<gt>.
The message is a descriptive string describing the reason for the change.
The status should be derived from one of the state constants such as
C<STATUS_SUBMITTED> (to which it defaults if not specified).

The number of files in the changeset is provided as the last argument. For
backwards compatibility this argument is optional but should ordinarily
always be specified in order to allow the database to optimise retrieval.
Note, however, that the number of files is I<not> enforced by
L<"addFileToChangeSet"> or L<"addFilesToChangeSet">.

=cut

sub createChangeSet ($$$;$) {
    my ($self,$user,$ticket,$stage,$move,$msg,$status,$files,$depend,$refs)=@_;
    $user ||= USER;

    $files ||= 0; #unknown or unspecified
    $depend ||= {}; # No specified dependencies
    $refs ||= {};

    debug("generating csid");
    my $csid=$self->_generateChangeSetID($user);

    $self->{current}={ csid  => $csid,  user    => $user, ticket  => $ticket,
                       stage => $stage, move    => $move, message => $msg,
                       files => $files, depends => $depend, reference => $refs,
                     };
    debug("flattening message");
    $msg=Change::Set->flatten($msg);

    $status ||= $STATUS_SUBMITTED;
    my $time=scalar(localtime);
    my $record=join($DBDELIMITER,
                           $status,
                           $csid,
                           qq[created="$time"],
                           "user=$user",
                           "ticket=$ticket",
                           "stage=$stage",
                           "move=$move",
                           "depends=".join(",", map "$_|$depend->{$_}", keys %$depend),
                           qq[message="$msg"],
                           "files=$files",
                           "reference=".join(','=> map "$_|$refs->{$_}", keys %$refs),
                          )."\n";
    debug("Created record: ($record)");

    my $rc=$self->{fhappend}->print($record);
    $self->_audit_record($csid,\$record, 'dont write on SCM');

    #seek $self->{logfh},0,2;  # not necessary; file opened for append
    $self->{logfh}->print("-->".$record); #the '-' is for cosmetic purposes

    $self->throw("Failed to create master record for $csid") unless $rc;

    return $csid;
}

=head2 createChangeSetNoWrite($user,$ticket,$stage,$move,$msg,[$status[,$files]])

Similar to C<createChangeSet>, but do not write the generated change set to the database.

Return the newly created change set object.

=cut

sub createChangeSetNoWrite ($$$;$) {
    my ($self,$user,$ticket,$stage,$move,$msg,$status,$files, $depend, $refs)=@_;
    $user ||= USER;

    $files ||= 0; #unknown or unspecified
    $depend ||= {}; # No specified dependencies
    $refs ||= {};

    debug("generating csid");
    my $csid=$self->_generateChangeSetID($user);
    my $cs = 
    Change::Set->new({ csid  => $csid,  user    => $user, ticket  => $ticket,
		       stage => $stage, move    => $move, message => $msg,
		       files => $files, depends => $depend, reference => $refs,
		     });
    $cs->setTime(scalar localtime);
    return $cs;
}

=head2 addChangeSet($changeset,[$status])

Writes i<$changeset> to the database with a status of I<$status> which defaults
to STATUS_SUBMITTED if not provided.

=cut

sub addChangeSet ($$) {
    my ($self, $cs, $status) = @_;

    
    my $csid        = $cs->getID;
    my $files       = my @files = $cs->getFiles;
    
    $status ||= $STATUS_SUBMITTED;

    my $user        = $cs->getUser;
    my $ticket      = $cs->getTicket;
    my $stage       = $cs->getStage;
    my $move        = $cs->getMoveType;
    my $depend      = $cs->getDependencies;
    my $refs        = $cs->getReferences;
    my $msg         = Change::Set->flatten($cs->getMessage);
    my $time        = $cs->getTime;

    $depend ||= {}; # No specified dependencies

    my $record=join($DBDELIMITER,
                           $status,
                           $csid,
                           qq[created="$time"],
                           "user=$user",
                           "ticket=$ticket",
                           "stage=$stage",
                           "move=$move",
                           "depends=".join(",", map "$_|$depend->{$_}", keys %$depend),
                           qq[message="$msg"],
                           "files=$files",
                           "reference=".$refs,
                          )."\n";
    debug("Created record: ($record)");

    my $rc=$self->{fhappend}->print($record);
    $self->_audit_record($csid,\$record, 'dont write to SCM');

    $self->{logfh}->print("-->".$record); #the '-' is for cosmetic purposes

    $self->throw("Failed to create master record for $csid") unless $rc;

    $self->addFileToChangeSet($csid, $_) for @files;

    return $csid;
}


=head2 createRollbackChangeSet (%args)

Creates a rollback changeset with the properties specified in I<%args>.

I<%args> is a list of key value pairs that in most parts correspond to
the properties of a I<Change::Set> object. Additionally, the key 'csids'
is mandatory and its value is expected to be a reference to an array of
change set IDs.

Returns the new Change::Set object.

=cut

sub createRollbackChangeSet ($@) {
    my ($self, %args) = @_;

    fatal "Need to specify a list of IDs of change sets to be rolled back"
        if not $args{csid};

    debug("generating csid");

    # get move type of changeset to be rolled back
    my $rbcandidate = $self->getChangeSet($args{csid})
        or fatal "No such changeset '$args{csid}'";

    my $user    = $args{user} || USER;
    my $csid    = $self->_generateChangeSetID($user);
    my $ticket  = $args{ticket} || '';
    my $stage   = STAGE_INTEGRATION;
    my $move    = $rbcandidate->getMoveType,
    my $msg     = $args{message};
    my $files   = 0;
    my $refs    = $args{reference} || {};
    my $depend  = { $args{csid} => DEPENDENCY_TYPE_ROLLBACK };

    $self->{current}={ csid  => $csid,  user    => $user, ticket  => $ticket,
                       stage => $stage, move    => $move, message => $msg,
                       files => $files, depends => $depend, reference => $refs,
                     };
    debug("flattening message");
    $msg=Change::Set->flatten($msg);
    
    my $time=localtime;
    my $record=join($DBDELIMITER,
                           $STATUS_SUBMITTED,
                           $csid,
                           qq[created="$time"],
                           "user=$user",
                           "ticket=$ticket",
                           "stage=$stage",
                           "move=$move",
                           "depends=".join(",", map "$_|$depend->{$_}", keys %$depend),
                           qq[message="$msg"],
                           "files=$files",
                           "reference=".join(',' => map "$_|$refs->{$_}", %$refs),
                          )."\n";
    debug("Created record: ($record)");

    my $rc=$self->{fhappend}->print($record);
    $self->_audit_record($csid,\$record, 'dont write on SCM');

    $self->{logfh}->print("-->".$record); #the '-' is for cosmetic purposes

    $self->throw("Failed to create master record for $csid") unless $rc;
    
    return $self->getChangeSet($csid);
}

=head2 addFileToChangeSet($csid,$target,$source,$destination
                           [,$type [,$library [,$origin]]])

=head2 addFileToChangeSet($csid,$changefile_object)

Add a change record for a specific file to a previously created change set. The
target is the library or application path where the file belongs. The
source is the absolute path of the file in its origin location. The destination
is the location of the file in its destination location (which may vary
depending on what the stage is, see L<createChangeSet>). The optional type
indicates if the file is new, or changed (if unspecified or passed as C<undef>,
the file is assumed to be changed). The optional library indicates the library
to which the file belongs, if it is different to the target (the target should
always start with the library but may or may not include trailing
subdirectories). Finally, the optional origin is the name of the development
library, if this is different from the production library (due to naming
translations or amalgamations). See L<Change::File> for more details on the
meaning and proper assignment of these values.

A L<Change::File> object may also be passed in as the second argument
to supply all six change file arguments, in which case any arguments following
it (if specified) are ignored.

The status of the change file recorded into the database is automatically
set to C<STATUS_SUBMITTED>, unless a L<Change::Set> object is passed as the
first argument. In that case, the status of the file is taken from the change
set status. No other information from the change set object is used.

Note: In this implementation, the supplied change set ID I<must> agree with the
most recently generate ID returned from the previous invocation of
L<"createChangeSet>, above. If it does not, an exception is thrown.

=cut

sub addFileToChangeSet ($$$$$;$$$) {
    my ($self,$csid,$target,$source,$destination,$type,$library,$prdlib)=@_;
    $csid = uc($csid) unless ref($csid);

    if (ref $target) {
	$source      = $target->getSource();
	$destination = $target->getDestination();
	$type        = $target->getType();
	$library     = $target->getLibrary();
	$prdlib      = $target->getProductionLibrary();
	$target      = $target->getTarget();
    }

    $type    ||= FILE_IS_CHANGED;
    $library ||= $target;
    $prdlib  ||= $library;

    my $status=ref($csid) ? $csid->getStatus() : $STATUS_SUBMITTED;

    my $record=join( $DBDELIMITER,
		     $status,$csid,
		     "target=$target",
		     "from=$source",
		     "to=$destination",
		     "library=$library",
		     "production=$prdlib",
		     "type=$type" )."\n";


    my $rc=$self->{fhappend}->print($record);
    $self->_audit_record($csid,\$record);

    $self->throw("Failed to commit $destination for $csid") unless $rc;
    return $rc;
}

=head2 getChangeSet($csid [,$state])

Get the change set with the specified ID. If the optional state is supplied,
only return the change set if it is also in the specified state. If the
change set does not exist or is in a different state, C<undef> is returned.
Otherwise, a change set object instance is returned.

=head2 getChangeSets(\@csids [,$state])

Get the change sets with the specified IDs. If the optional state is supplied,
only return change sets if they are also in the specified state. If change sets
do not exist or are in a different state, they are silently ommitted.
Otherwise, an array reference of change set objects instances is returned.

=head2 getChangeSetHeader($csid [,$state])

As L<"getChangeSet">, but return a change set object instance containing
only the header information, without any file information attached. This
is less memory-intensive and faster to instantiate, but of course cannot
be used for file-level queries.

=head2 getChangeSetHeaders($csid [,$state])

As L<"getChangeSetHeader">, but on a list of change sets.

=cut

sub getChangeSetHeader ($$;$) {
    my($self,$csid,$state)=@_;
    return $self->getChangeSets([$csid],$state,"header only");
}

sub getChangeSetHeaders ($$;$) {
    my($self,$csids,$state)=@_;
    return $self->getChangeSets($csids,$state,"header only");
}

sub getChangeSet ($$;$) {
    my ($self,$csid,$state)=@_;
    return $self->getChangeSets([$csid],$state);
}

sub getChangeSets ($$;$$) {
    my ($self,$csids,$state,$headeronly)=@_;
    return unless @$csids;

    my $num_csids = scalar @$csids;
    my $csid_regex = join('|',map { uc } @$csids);
    $state='[A-Z]' unless $state;
    my $cs_re=qr/^\0*$state${DBDELIMITER}(?:$csid_regex)${DBDELIMITER}/;
    my $cs_match=qr/^\0*$state${DBDELIMITER}($csid_regex)${DBDELIMITER}(.*)/s;
    my $debug = Util::Message::get_debug();

    my $line = "";  # (define for initial condition in while () loop below)
    my($stream,$csid,%csids,$changeset);

    ## While we might speed up this routine by looking up change sets in
    ## individual files, we would then pay a much larger price when we came
    ## back to transition states (and scanned through db once for each csid)
    ## Therefore, only take this shortcut here when number of csids is one (1)
    ## or if header-only flag is defined (A $headeronly == "" is false, but
    ## still defined to allow csquery to indicate it wants this speedup since
    ## it will be using the data read-only.  csfind already scanned the db so
    ## the benefit is more marginal, especially with lots and lots of matches
    ## since that will result in many individual file opens, reads, and closes)
    ## Anything not found in individual files will be looked up in the database
    if ($num_csids == 1 || defined $headeronly) {
	my $check_state = ($state ne '[A-Z]');
	foreach my $id (@$csids) {
	    $csid = uc $id;
	    $changeset = $self->_get_cs_file($csid);
	    next unless ($changeset
			 && (!$check_state || $changeset->getStatus eq $state));
	    $csids{$csid} = $changeset;
	}
    }

    my $fh=$self->{fh};
    my $pos = ($num_csids == 1 ? $self->_csid_pos(uc $csids->[0]) || 0 : 0);
    seek $fh,$pos,0 unless ($num_csids == scalar keys %csids);

    while (defined($line) && $num_csids > scalar keys %csids) {
	unless ($line =~ $cs_re) {
	    do {} while (defined($line=<$fh>) && $line !~ $cs_re);
	}
	last unless defined $line;

	warning "Error parsing DB - saw:\n\t${line}before master record"
	  unless ($line =~ $cs_match && "created" eq substr($2,0,7));
	$csid = $1;

	debug "Found master record for $csid";
	$self->_csid_pos($csid,tell($fh)-length($line));  ## cache csid offset
	$line =~ s/^\0+//;
	$stream = "delimiter=($DBDELIMITER)".$line;
        
	while (defined($line=<$fh>) && $line =~ $cs_match && $csid eq $1) {
	    $stream.=$2	 # strip off prefix to provide file spec
	      unless $headeronly;# private argument, set via getChangeSetHeaders
	}
	$changeset = new Change::Set($stream);

	## (could check if it already exists in hash, but should not happen)
	$csids{$csid} = $changeset;
    }

    return $num_csids > 1
      ? sort values %csids	# CSIDs are numerically and character ascending
      : (each %csids)[1];	# (force change set to be returned when called
				#  in a scalar context, not num of change sets)
}

#----------

=head2 logTransition($csid, $from => $to, $user)

Primarily internal method to log a transition to the transition log. Used by
L<"transitionChangeSetStatus"> and similar methods detailed below.

=cut

sub logTransition ($$$$;$) {
    my ($self,$csid,$from,$to,$user)=@_;

    $user ||= USER;
    my $time=scalar(localtime);
    #seek $self->{logfh},0,2;  # not necessary; file opened for append
    $self->{logfh}->print(join($DBDELIMITER,"$from->$to",$csid,
			       "user=$user","updated=\"$time\"")."\n");
}

=head2 logEvent($csid,$eventmsg,$user)

Log a non-transitional event to the transition log. The event message text
is freeform, but may have additional constraints imposed on it elsewhere.

This method is primarily used to record metadata transitions outside the
primary metadata, for example the manipulation of associated ticket IDs.
In these cases the event message should be of the form:

   type number (type qualifier) message

For example:

   PRQS 123456 (EM) created

=cut

sub logEvent($$$;$) {
    my ($self,$csid,$eventmsg,$user)=@_;

    $user ||= USER;
    $eventmsg ||= '';
    my $time=scalar(localtime);
    #seek $self->{logfh},0,2;  # not necessary; file opened for append
    $self->{logfh}->print(join($DBDELIMITER,"----",$csid,
			       "user=$user","updated=\"$time\"",
			       $eventmsg)."\n");
}

=head2 transitionChangeSetStatus($csid,$from => $to [,$user])

Transition the specified change set from the status indicated by C<$from> to
the status indicated by C<$to>. If the change set is not in a matching status
then it is not transitioned and a false value is returned, otherwise the status
is changed and a true value is returned. The from status may be a regular
expression, in which case any of the states matched can be transitioned, e.g.
C<.> to match all states. The user, if supplied, is logged in the transition
log as the user effecting the change. If not supplied, the C<USER> symbol is
used to provide this value.

=cut

sub transitionChangeSetStatus ($$$$;$) {
    my ($self,$csid,$from,$to,$user)=@_;
    $csid = uc $csid;
    $from="[A-Z]" unless $from;

    $self->throw("end transition not defined") unless $to;
    $to=uc(substr $to,0,1); # must be 1 chr or it will corrupt the DB
    $self->_update_cs_status($csid,$to,$user);
    # (would prefer to do logTransition() here, but do not know orig status)

    my $cs_re=qr/^\0*$from${DBDELIMITER}$csid${DBDELIMITER}/;
    my $fh=$self->{fh};

    my $line;
    my $pos = $self->_csid_pos($csid) || 0;
    seek $fh,$pos,0;
    do {} while (defined($line=<$fh>) && $line !~ $cs_re);
    return 0 unless defined $line;	## did not find change set	
    $self->_csid_pos($csid,tell($fh)-length($line)) if $pos == 0;

    my $n = $line =~ tr/\0/\0/; # number of nulls (assume all are leading nulls)
    $self->logTransition($csid,substr($line,0+$n,1) => $to,$user);
    do {
        $n = $line =~ tr/\0/\0/;
        seek $fh,-length($line)+$n,1;	## seek back length of line just read
        $fh->print($to);		## print 1 char
        seek $fh,length($line)-1-$n,1;	## seek line length minus 1 char printed
    } while (defined($line=<$fh>) && $line =~ $cs_re);

    return 1;
}


=head2 transitionAllChangeSetStatuses($from => $to [,$user])

Transition all change sets with status C<$from> to status C<$to>. Arguments
have the same meaning as for L<"transitionChangeSetStatus"> above.
In particular, the from status may be a regular expression.

=head2 transitionAllChangeSetStatusesExcept($from => $to, $user, @except)

Transition all change sets with status C<$from> to status C<$to> except
those specified. Arguments have the same meaning as for
L<"transitionChangeSetStatus"> above. In particular, the from status may be a
regular expression.

The user argument is mandatory for this method, but may be passed a false
value (e.g. undef, empty string) to default to the invoking user. Note
that the user is used only in transaction logging.

=cut

sub transitionAllChangeSetStatusesExcept ($$$;$@) {
    my ($self,$from,$to,$user,@except)=@_;
    $from="." unless $from;
    $self->throw("end transition not defined") unless $to;
    $to=uc(substr $to,0,1); # must be 1 chr or it will corrupt the DB
    my %exceptions=map { uc($_) => 1 } @except;

    ## (even faster would be to assume static length of $csid and use substr())
    my $cs_match=
      qr/^(\0*)$from${DBDELIMITER}([^${DBDELIMITER}]+)${DBDELIMITER}/;
    my $fh=$self->{fh};
    my($n,@seen);
    my $csid = "";

    seek $fh,0,0;
    while (my $line=<$fh>) {
	next unless $line=~$cs_match && not exists $exceptions{$2};
	$n = length($1);
	if ($2 ne $csid) {
	    $csid = $2;
	    push @seen, $csid;
	    $self->logTransition($csid,substr($line,0+$n,1) => $to,$user);
	}
	seek $fh,-length($line)+$n,1;	## seek back length of line just read
	$fh->print($to);		## print 1 char
	seek $fh,length($line)-1-$n,1;	## seek line length minus 1 char printed
    }
    $self->_update_cs_status($_,$to,$user) foreach (@seen);

    return sort @seen;
}

sub transitionAllChangeSetStatuses ($$$;$) {
    my ($self,$from,$to,$user)=@_;
    return $self->transitionAllChangeSetStatusesExcept($from,$to,$user);
}

=head2 rollbackChangeSet($csid)

Rollback the specified active change set. Returns true if the rollback was
successful, or false if the rollback could not be done (for instance, because
the change set was not present in the database, or was not in a submitted or
active state).

=cut

sub rollbackChangeSet ($$;$) {
    my ($self,$csid,$user)=@_;
    return $self->transitionChangeSetStatus($csid,$rollbackable_status_re
					    => $STATUS_ROLLEDBACK, $user);
    #!! remember to actually rm the corresponding destination files...
}

=head2 reinstateChangeSet($csid)

Reinstate the specified previously rolled-back change set. Returns true if the
rollback was successful, or false if the rollback could not be done (for
instance, because the change set was not present in the database, or was not
in a rolled-back state).

=cut

sub reinstateChangeSet ($$;$) {
    my ($self,$csid,$user)=@_;
    $csid = uc $csid;
    ##<<<TODO: $reinstatable_status_re instead of $STATUS_ROLLEDBACK ?
    my $cs_re=qr/^\0*$STATUS_ROLLEDBACK${DBDELIMITER}$csid${DBDELIMITER}/;
    my $cs_match=
      qr/^(\0*)$STATUS_ROLLEDBACK${DBDELIMITER}$csid(${DBDELIMITER}.*)/s;
    my($line,$n);
    my $fh=$self->{fh};
    my $pos = $self->_csid_pos($csid) || 0;
    seek $fh,$pos,0;
    do {} while (defined($line=<$fh>) && $line !~ $cs_re);
    return 0 unless defined($line);
    #$self->_csid_pos($csid,tell($fh)-length($line)) if $pos == 0;

    my $newcsid=$self->_generateChangeSetID($user);
    my $cs_str = "";
    $self->_update_cs_status($csid,$STATUS_REINSTATED,$user);
    while (defined($line) && $line =~ $cs_match) {
	$cs_str .= $STATUS_SUBMITTED.$DBDELIMITER.$newcsid.$2;
	$n = length($1);
	seek $fh,-length($line)+$n,1;	## seek back length of line just read
	$fh->print($STATUS_REINSTATED);	## print 1 char
	seek $fh,length($line)-1-$n,1;	## seek line length minus 1 char printed
	$line = <$fh>;
    }
    #seek $fh,0,2;
    #$self->_csid_pos($newcsid,tell $fh);  ## cache csid offset in db file
    #$fh->print($cs_str);
    $self->{fhappend}->print($cs_str);
    $self->_audit_record($newcsid,\$cs_str);

    $self->logTransition($csid,$STATUS_ROLLEDBACK=>$STATUS_REINSTATED,$user);
    $self->logTransition($newcsid,$STATUS_REINSTATED=>$STATUS_SUBMITTED,$user);

    # remember to recopy the corresponding source files to destination files...
    return $newcsid;
}

=head2 rewriteChangeSet($csid)

Recover a change set from its individual audit file.  Replace the record in the 
db by overwriting the change set id, and then appending the recovered record
to the end of the database.

=cut

sub rewriteChangeSet ($$;$) {
    my($self,$csid,$user) = @_;
    $csid = uc $csid;

    my $cs_str = "";
    {
	my $audit_path = CS_DATA."/logs/db/".substr($csid,-2)."/$csid.log";
	my $FH = new IO::File($audit_path,"<")
	  || return 0;
	local $/ = undef;
	$cs_str = <$FH>;
	close $FH;
    }
    my $cs_re=qr/^(\0*[A-Z]${DBDELIMITER})$csid${DBDELIMITER}/;
    my $fh=$self->{fh};
    my $pos = $self->_csid_pos($csid) || 0;
    seek $fh,$pos,0;
    my($line,$n);
    do {} while (defined($line=<$fh>) && $line !~ $cs_re);
    if (defined $line) {
	do {
	    $n = length($1);
	    seek $fh,-length($line)+$n,1; ## seek back to csid
	    $fh->print('-');		  ## print 'X' char; invalidate csid
	    seek $fh,length($line)-1-$n,1;## seek line length minus char printed
	} while (defined($line=<$fh>) && $line =~ $cs_re);
    }
    
    #seek $fh,0,2;
    #$self->_csid_pos($csid,tell $fh);  ## cache csid offset in db file
    #$fh->print($cs_str);
    $self->{fhappend}->print($cs_str);

    $self->logEvent($csid, "replaced cs with info from individual file", $user);
    return 1;
}

#----

=head2 find($match_text [,$as_regexp])

Search for the match text in the database. Any change set that contains the
match text in any field will be returned.

If the optional second argument is specified and true, regular expression
characters are recognized, so C<.> becomes 'any character' instead of a
literal period character.

=cut

sub find ($$) {
    my ($self,$file,$asre)=@_;

    my %csids=();
    my $fh=$self->{fh};

    $file=quotemeta($file) unless $asre;
    my $re = qr/${file}/;

    seek $fh,0,0;
    while (my $line=<$fh>) {
	$csids{ (split $DBDELIMITER,$line,3)[1] } = 1 if ($line=~$re);
    }

    return unless keys %csids; # return () or undef if nothing was found
    return sort keys %csids;   # CSIDs are numerically and character ascending
}

{
    no warnings 'once';
    *findFile=\&find; #Old name, back when this was slightly file-specific.
                      #To be replaced later if necessary.
}

=head2 getHistory($csid)

Search for the change set in the database transaction log and return a
machine-parseable list of all matching transaction events. The creation
record, if present, has the same format as the machine-parsable header
returned by L<Change::Set/listFiles>. A status transition record has
the format:

   FROM->TO:CSID:user=USER:updated="UPDATED"

Note that a new changeset generated from a reinstated rolledback changeset
will not return a creation record.

=cut

sub getHistory ($$) {
    my ($self,$csid)=@_;
    my @lines;
    my $re = qr/${csid}/;

    my $logfh=$self->{logfh};
    seek $logfh,0,0;
    while (my $line=<$logfh>) {
	next unless ($line=~$re);
	chomp $line;
	push @lines,$line;
    }

    return @lines;
}

=head2 verifyDB()

Check consistency of database

=cut

sub verifyDB ($;$) {
    my($self,$time) = @_;
    $time ||= 0;
    $self->_trawl_db($time);
}

=head2 addDependencyToChangeSet($csid,$depends_on,$type)

Adds the dependency of type I<$type> on the change set with the ID I<$depends_on>
to the change set with the ID I<$csid> and rewrites the database record.

Returns a true value in case of success. A false one otherwise.

=cut

sub addDependencyToChangeSet($$$) {
    my ($self, $csid, $depends_on, $type) = @_;

    my $cs = $self->getChangeSet($csid);

    if (not $cs) {
        error "No change set with ID '$csid' in database";
        return 0;
    }

    $cs->addDependency($depends_on, $type);

    my $status  = $cs->getStatus;
    my $time    = $cs->getTime;
    my $user    = $cs->getUser;
    my $ticket  = $cs->getTicket;
    my $stage   = $cs->getStage;
    my $move    = $cs->getMoveType;
    my $depend  = $cs->getDependencies;
    my $msg     = $cs->getMessage;
    my $files   = my @files = $cs->getFiles;
    my $refs    = $cs->getReferences;

    $msg = Change::Set->flatten($msg);

    my $record=join($DBDELIMITER,
			   $status,
			   $csid,
			   qq[created="$time"],
			   "user=$user",
			   "ticket=$ticket",
			   "stage=$stage",
			   "move=$move",
		           "depends=".join(",", map "$_|$depend->{$_}", keys %$depend),
			   qq[message="$msg"],
			   "files=$files",
                           "reference=".$refs,
			  )."\n";

    $self->_audit_record($csid, \$record);

    for (@files) {
        my $target      = $_->getTarget;
        my $source      = $_->getSource;
        my $destination = $_->getDestination;
        my $library     = $_->getLibrary;
        my $prdlib      = $_->getProductionLibrary;
        my $type        = $_->getType;
        my $record=join( $DBDELIMITER,
                         $status,$csid,
                         "target=$target",
                         "from=$source",
                         "to=$destination",
                         "library=$library",
                         "production=$prdlib",
                         "type=$type" )."\n";
        $self->_audit_record($csid,\$record);
    }
    
    return $self->rewriteChangeSet($csid,USER);
}

#------------------------------------------------------------------------------

sub _generateChangeSetID ($;$) {
    my($self,$user) = @_;
    return Change::Set->generateChangeSetID($user);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)
Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<Change::Symbols>, L<bde_createcs.pl>, L<bde_rollbackcs.pl>, L<bde_querycs.pl>

=cut

1;
