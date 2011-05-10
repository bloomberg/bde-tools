package Change::Set;
use strict;

use overload '""'     => "toString",
             fallback => 1;
use base 'BDE::Object';

use Change::File;
use Change::Symbols qw(
    STAGE_INTEGRATION STATUS_ACTIVE STATUS_UNKNOWN STATUS_NAME
    SERIAL_DELIMITER
    MOVE_EMERGENCY MOVE_REGULAR MOVE_BUGFIX MOVE_IMMEDIATE
    DEPENDENCY_TYPE_NONE DEPENDENCY_TYPE_ROLLBACK DEPENDENCY_TYPE_CONTINGENT
    DEPENDENCY_TYPE_DEPENDENT DEPENDENCY_TYPE_SIBLING $ROBOSCM_MESSAGE
    USER
);
use Production::Symbols qw(HEADER_STATUS HEADER_MOVE_TYPE HEADER_ID
			   HEADER_CREATOR HEADER_CREATION_TIME
			   HEADER_STAGE HEADER_TICKET HEADER_REFERENCE
                           HEADER_ID_DEP
                           HEADER_TESTER HEADER_APPROVER HEADER_FUNCTION
                           HEADER_TASK HEADER_BRANCH);
use BDE::Build::Invocation qw($FSRE);

use Util::Message qw(warning debug);

#==============================================================================

=head1 NAME

Change::Set - Abstract representation of a change set

=head1 SYNOPSIS

    use Change::Set;
    use Change::Symbols qw(STATE_INTEGRATION MOVE_REGULAR);

    my $set=new Change::Set(getpwuid($<),"t1234567",STAGE_INTEGRATION,
                            MOVE_REGULAR,"a comment");
    my $fobj=$set->addFile("acclib",
                           "/home/me/acclib/que.c" => "/bbsrc/acclib/que.c");
    $set->addFile("derutil","/home/you/lib2/new.f" => /bbsrc/derutil/what.f");

    foreach my $file ($self->getFiles) {
        print $file->getTarget(),": ",
              $file->getSource(),"=>",$file->getDestination(),
              " (",$file->getType(),")\n";
    }

    foreach my $target ($self->getTargets) {
        print "$target: ",$self->getFilesInTarget($target),"\n";
    }

    print join "\n",$set->getFiles();
    $set->removeFile($fobj);

=head1 DESCRIPTION

C<Change::Set> implements a change set object class that is comprised of one
or more C<Change::File> objects, plus metadata describing the user, stage,
ticket and description associated with the changes.

A C<Change:Set> instance may be serialised by evaluating it in string
context. The serialised form may be later turned back into a new C<Change::Set>
by passing it to the L<"new"> constructor.

=cut

#==============================================================================

=head1 CONSTRUCTORS

=head2 new([$csid [,$when [,$user [,$tkt [,$stg [,$move [,$msg [,$stat [,$deps}]]]]]]])

Create a new empty change set with the specified metadata values. If
unspecified, the user defaults to the login name of the real user ID, and
the stage defaults to the value of C<STAGE_INTEGRATION>. The change set ID,
ticket, and message are set to C<undef>.

I<Note: if no change set ID is specified, the string representation of the
object is the empty string, which evaluates to false. Therefore, do not
use code like 'C<if (my $cs=new Change::Set)>' because this will never
succeed. Instead, use c<defined> to see if construction was successful.>

=head2 new({ csid=>$id, when=>$when, user=>$usr, stage=>$stg, move=>$movetype,
             ticket=>$tkt, message=>$msg, status=>$status, depends=>$deps })

As above, except using a hash reference of named properties and values.

=head2 new($serialised_changeset_string)

Create a populated change set by parsing the provided string, which should
contain a serialised record created from a previously streamed change set
object (potentially edited). Returns the change set object on success. Throws
an exception if the passed string cannot be parsed.

If necessary, the delimiter used to parse the change set data can be overridden
by prefixing the serialised string with C<delimiter=(<delimiter>)>, where
C<delimiter> is the replacement delimiter. The default delimiter is the
delimiter used to stream out change sets, which is C<:>.

=cut

sub initialise ($;$) {
    my ($self,$init)=@_;
    my $args;

    return 0  unless defined($init);

    if (my $reftype=ref $init) {
	if ($reftype eq 'ARRAY') {
	    my ($csid,$when,$user,$tkt,$stage,$move,$msg,$status,$deps,$refs,$ctime,$group,$tasks, $functions, $testers, $branch)=@$init;
	    $ctime ||= time();
	    $when  ||= $self->getCurrentTime($ctime);
	    my ($uname,$gname) = (getpwuid((int $user)?$user:$<))[0,3];
	    $gname = getgrgid($gname);
	    $args={
		   csid		=> ($csid   || undef),
		   when		=> ($when   || $self->getCurrentTime()),
		   user		=> ($user   || $uname),
		   stage	=> ($stage  || STAGE_INTEGRATION),
		   move		=> ($move   || MOVE_REGULAR),
		   ticket	=> ($tkt    || undef),
		   message	=> ($msg    || undef),
		   status	=> ($status || STATUS_ACTIVE),
		   depends	=> ($deps   || {}),
                   reference    => ($refs   || {}),
                   ctime	=> ($ctime  || undef),
		   group	=> ($group  || $gname),
		   order        => ([]),
		   tasks        => ($tasks  || []),
		   testers      => ($testers|| []),
		   functions    => ($functions || []),
		   branch       => $branch,
		  };
	} elsif ($reftype eq 'HASH') {
	    $args=$init;
	} else {
	    $self->throw("Invalid reference type: $reftype");
	}
	
	return $self->SUPER::initialise($args);
    } else {
	return $self->SUPER::initialiseFromScalar($init);
    }

    return 0;
}

sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->throw("Initialiser passed argument not a hash reference")
      unless UNIVERSAL::isa($args,"HASH");

    $self->{_meta}={map {$_=>undef}
		    (qw[csid when update user move stage ticket message status group 
                        deptype numfiles approver branch])};
    $self->{_meta}{depends} = {};
    $self->{_meta}{reference} = {};
    $self->{_meta}{tasks} = [];
    $self->{_meta}{functions} = [];
    $self->{_meta}{testers} = [];
    $self->{_meta}{order} = [];

    foreach (keys %$args) {
	$self->{_meta}{$_}=$args->{$_};
    }

    $self->{_meta}{ctime} ||= time();

    return 1; #done
}

sub fromString {
    my ($self,$init)=@_;

    # strip comments and blank lines
    my ($header,@files)=grep {
	$_ !~ /^\s*(#|$)/
    } (split /\n/,$init);

    # @files now also contains the dependency section

    # permit a different delimiter
    my $delimiter=SERIAL_DELIMITER;
    if ($header=~s/^delimiter=\(([^)]+)\)//) {
	$delimiter=$1;
    }

    my @fields=split($delimiter,$header);
    my %fields=(status=>shift(@fields), csid=>shift(@fields));

    my $nf;
    local *_;
    while ($_=shift @fields) {
	# reconnect quoted things with the delimiter in them
	$_.=$delimiter.shift(@fields) while @fields and /"/ and not /"$/;

        # Watch out:
        # The use of the positive look-behind for \\" is intentional. When
        # replacing (?<=\\)" with the more conventional \\", perl may segfault
        # on certain complex change set messages.
	$self->throw("Unparsable change set field: $_")
	  unless /^(\w+)=(")?((?:[^"]|(?<=\\)")*)(")?$/;
	my ($key,$value)=($1,$3);

	# don't allow '<no message>' etc.
	$value=undef if $value=~/^<no\s\w+>$/;

	if ($key eq "files") {
	    # the 'files' key is passed if the string was read from a DB record
	    # for regular streamed change sets it is not present.
	    $self->throw("Number of files specified (".scalar(@files).") does".
			 " not agree with number supplied (".$value.")")
			 unless (not @files) or $value==scalar(@files);
	} elsif ($key eq "depends") {
	    # this is a comma-separated list of values
            my %deps;
            for (split /,/, $value) {
                my ($csid, $type) = split /\|/;
                $deps{$csid} = $type;
            }
	    $fields{$key} = \%deps;
	} elsif ($key eq "reference") {
            my %refs;
            for (split /,/, $value) {
                my ($type, $val) = split /\|/;
                $refs{$type} = $val;
            }
            $fields{$key} = \%refs;
        } elsif ($key eq "functions" || $key eq "testers" || $key eq "tasks") {
	    my @data;

	    push @data, $_ for (split /,/, $value);
	    
	    $fields{$key} = \@data;
	} else {
	    #map serialisation keys to internal attributes
	    $key="when" if $key eq "created";

	    $fields{$key}=$value;
	}
    }

    # empty fields really ought to be undef so that callers
    # can do 'if defined' tests safely; we do however allow
    # 0 as legit value
    defined $_ && $_ eq '' and $_ = undef for values %fields;

    $fields{message}=$self->unflatten($fields{message}) if $fields{message};
    $fields{depends} ||= {};
    $fields{reference} ||= {};
    $fields{ctime} ||= time();
    $fields{functions} ||= [];
    $fields{tasks} ||= [];
    $fields{testers} ||= [];
    $fields{group} ||= undef;

    $self->initialise(\%fields);

    foreach my $filespec (@files) {
	if ($filespec=~/^[A-Z]:([^:]+):/) {
	    warning "Additional change set $1 header detected in stream ".
	      "-- discarded";
	    next;
	}
	$self->addFile(Change::File->new($filespec));
    }

    return $self;
}

=head2 load($file)

Load a serialised change set string from the specified file and instantiate
a new C<Change::Set> object from it. Calls L<"new"> in its third usage mode
described above. Throws an exception if the file cannot be opened, otherwise
as L<"new">.

=cut

sub load ($$) {
    my ($self,$file)=@_;

    if (my $fh=new IO::File($file)) {
	-f $fh || $self->throw("$file is not a regular file (directory?)");
	local $/=undef;
	my $definition=<$fh>;
	close $fh;
	return new Change::Set($definition);
    } else {
	$self->throw("Cannot open $file for reading: $!");
    }
}

# BDE::Object's clone() does not return a deep copy
sub clone {
    my $self = shift;

    my $clone = $self->SUPER::clone;

    # at that point, Change::File objects are not clones
    $clone->removeAllFiles;
    $clone->addFiles(map $_->clone, $self->getFiles);

    return $clone;
}

#------------------------------------------------------------------------------

=head1 METADATA ACCESSOR/MUTATORS

=head2 getStatus()

Get the status for this change set, or C<undef> if no status is set.

=head2 setStatus($id)

Set the status for this change set. See L<Change::Symbols> for a list of
constants that are valid as arguments to this method. The default for a new
C<Change::Set> is C<STATUS_ACTIVE>.

=head2 getStatusName()

Get the descriptive name for the state of this change set.

=cut

sub getStatus      ($)  { return $_[0]->{_meta}{status}; }
sub setStatus      ($$) { $_[0]->{_meta}{status}=$_[1]; }

sub getStatusName  ($)  { return undef unless $_[0]->{_meta}{status};
			  return STATUS_NAME($_[0]->{_meta}{status}); }

=head2 getMoveType()

Get the move type for this change set, or C<undef> if no ID is set.

=head2 setMoveType($type)

Set the move type for this change set. See L<Change::Symbols> for a list of
constants that are valid as arguments to this method. The default for a new
C<Change::Set> is C<MOVE_REGULAR>.

=head2 isMoveType($type)

Return true if the change set is of the specified type.

=head2 isRegularMove()

=head2 isBugFixMove()

=head2 isEmergencyMove()

=head2 isImmediateMove()

Return true if the change set is of type C<MOVE_EMERGENCY>, C<MOVE_BUGFIX>,
C<MOVE_REGULAR>, or C<MOVE_IMMEDIATE> respectively.

I<Note: The immediate move type is the basis of 'Straight Through Processing',
or STP.>

=cut

sub getMoveType    ($)  { return $_[0]->{_meta}{move}; }
sub setMoveType    ($$) { $_[0]->{_meta}{move}=$_[1]; }

sub isMoveType     ($$) { return 0 unless $_[0]->{_meta}{move};
                          return ($_[0]->{_meta}{move} eq $_[1]) ? 1 : 0; }
sub isRegularMove   ($) { return $_[0]->isMoveType(MOVE_REGULAR); }
sub isBugFixMove    ($) { return $_[0]->isMoveType(MOVE_BUGFIX); }
sub isEmergencyMove ($) { return $_[0]->isMoveType(MOVE_EMERGENCY); }
sub isImmediateMove ($) { return $_[0]->isMoveType(MOVE_IMMEDIATE); }
   # aka 'Straight Through Processing', or STP.

=head2 isBregMove()

This greps for breg-specific target libraries.  While strictly speaking not a
move type, it behaves like one that we have yet to invent but will in future.
This methods should provide sufficient abstraction to isolate the future
development from production usage.

=cut

sub isBregMove ($) {
    my %constraint = (
	0 => [ qr{\btarget=bregacclib} ],
    );
    # Constraint is an and of negative conditions.
    # Reverse to create or of positive matches.
    return !(Change::Set->checkConstraints($_[0],%constraint));
}

=head2 isStructuralChangeSet()

This determines whether the change set arose as a structural change, as opposed
to a regular cscheckin call.

=cut

sub isStructuralChangeSet ($) {
    return ($_[0]->getMessage =~ /^$ROBOSCM_MESSAGE/ ? 1 : 0);
}

=head2 isRollbackChangeSet()

This determines whether the change set arose as a rollback of another change
set.

=cut

sub isRollbackChangeSet ($) {
    my @deps = $_[0]->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK);
    return @deps ? 1 : 0;
}

=head2 getID()

Get the change set ID for this change set, or C<undef> if no ID is set.

=head2 setID($id)

Set the change set ID for this change set.

=cut

sub getID      ($)  { return $_[0]->{_meta}{csid}; }
sub setID      ($$) { $_[0]->{_meta}{csid}=$_[1]; }

=head2 getUser()

Get the user name for this change set, or C<undef> if no user name is set. The
default for a new C<Change::Set> is the user name of the real user ID, or
C<getpwuid($E<lt>)>.

=head2 setUser($id)

Set the user name for this change set.

=cut

sub getUser    ($)  { return $_[0]->{_meta}{user}; }
sub setUser    ($$) { $_[0]->{_meta}{user}=$_[1]; }

=head2 getGroup()

Get the group name for this change set, or C<undef> if no group name is set. The
default for a new C<Change::Set> is the group name of the real group ID, or
C<getpwuid($E<lt>)>.

=head2 setGroup($id)

Set the group name for this change set.

=cut

sub getGroup    ($)  { return $_[0]->{_meta}{group}; }
sub setGroup    ($$) { $_[0]->{_meta}{group}=$_[1]; }

=head2 getCtime()

Get a useful time value for the of this change set, or C<undef> if no time is
set. The default for a new C<Change::Set> is the time of creation as unix epoch.

=head2 setCtime($epoch)

Set the time for this change set, only as a useful time, not as a descriptive string.

=cut

sub getCtime    ($)  { return $_[0]->{_meta}{ctime}; }
sub setCtime    ($$) { $_[0]->{_meta}{ctime}=$_[1]; }

=head2 getTime()

Get the time of this change set, or C<undef> if no time is set. The
default for a new C<Change::Set> is the time of creation as returned by
C<"getCurrentTime">.

=head2 setTime($dateandtime_string)

Set the time for this change set, as a descriptive string.

=cut

sub getTime    ($)  { return $_[0]->{_meta}{when}; }
sub setTime    ($$) { $_[0]->{_meta}{when}=$_[1]; }

=head2 getTsp()

Returns the descriptive string of C<getTime> as less descriptive
but more useful UNIX timestamp.

=cut

sub getTsp {
    my $self = shift;
    require HTTP::Date;
    return HTTP::Date::str2time($self->getTime);
}

=head2 setUpdateTime($dateandtime_string)

Sets the time of the last status update for this change set.

=head2 getUpdateTime()

Returns the time of the last status update for this change set.

=cut

sub getUpdateTime   { return $_[0]->{_meta}{update}; }
sub setUpdateTime   { $_[0]->{_meta}{update}=$_[1]; }

=head2 getStage()

Get the stage for this change set, or C<undef> if no stage is set.

=head2 setStage($id)

Set the stage for this change set. See L<Change::Symbols> for a list of
constants that are valid as arguments to this method. The default for a new
C<Change::Set> is C<STAGE_INTEGRATION>.

=cut

sub getStage   ($)  { return $_[0]->{_meta}{stage}; }
sub setStage   ($$) { $_[0]->{_meta}{stage}=$_[1];  }

=head2 getTicket()

Get the ticket for this change set, or C<undef> if no ticket is set.

=head2 setTicket($id)

Set the ticket for this change set. Should usually be of a form that matches
the regular expression:

   ^(TREQ|DRQS)\d{6,7}$

=cut

sub getTicket  ($)  { return $_[0]->{_meta}{ticket}; }
sub setTicket  ($$) { $_[0]->{_meta}{ticket}=$_[1];  }

=head2 getMessage()

Get the reason message for this change set, or C<undef> if no message is set.

=head2 setMessage($id)

Set the reason message for this change set.

=cut

sub getMessage ($)  { return $_[0]->{_meta}{message}; }
sub setMessage ($$) { $_[0]->{_meta}{message}=$_[1]; use Carp; confess if !defined $_[1]}

=head2 getBranch()

Get the branch for this change set, or C<undef> if no branch is set.

=head2 setBranch($branch)

Set the branch for this change set.

=cut

sub getBranch { return $_[0]->{_meta}{branch}; }
sub setBranch { $_[0]->{_meta}{branch}=$_[1]; }

#------------------------------------------------------------------------------

=head1 TARGET/LIBRARY/FILE ACCESSORS

=head2 getNumOfFiles()

Returns the number of files in this change set.

=cut

sub getNumOfFiles {
    my $self = shift;

    return scalar($self->getFiles) || $self->{_meta}{numfiles};
}

=head2 getFiles()

Return the list of change file objects currently associated with this change
set.

=cut

sub getFiles ($) {
    my ($self, @type) = @_;

    return @{$self->{_meta}{order} || []}
        if not @type;

    my $pat = '^' . join('|', @type) . '$';
    return grep $_->getType =~ /$pat/, 
                @{$self->{_meta}{order} || []};
}

=head2 getTargets()

Return the list of targets currently associated with this change set (i.e.
have one or more files present in the change set.)

I<C<getUORs>> is a deprecated alias for this method>

=cut

sub getTargets ($) {
    my $self=shift;

    return grep { $_!~/^_/ } keys %$self;
}

{
    no warnings 'once';
    *getUORs=\&getTargets;
}

=head2 getLibraries()

Return the list of libraries (units-of-release) associated with this change
set. (See L<Change::File/Targets vs Libraries> for the distinction between
targets and libraries.)

=cut

sub getLibraries ($) {
    my $self=shift;

    my %libs=();
    foreach my $file ($self->getFiles) {
	$libs{$file->getLibrary}=1;
    };

    return keys %libs;
}

=head2 hasFile($filepath)

Search the change set for the specified file path. Returns true if the path
matches the tail end of either the source or destination locations of any
change file in the set. Returns false otherwise.

=cut

sub hasFile ($$) {
    my ($self,$what)=@_;

    foreach my $target (keys %$self) {
	next if $target=~/^_/;
	my $files=$self->{$target};
	foreach my $cf (values %$files) {
	    return 1 if ($cf->getSource)=~/(^|${FSRE})${what}$/;
	    return 1 if ($cf->getDestination)=~/(^|${FSRE})${what}$/;
	}
    };

    return 0;
}

=head2 getFileByName($filepath)

Returns the Change::File object which matches I<$filepath>. This has the
same matching semantics as C<hasFile>.

Returns the empty list of no such object could be found.

=cut

sub getFileByName {
    my ($self, $what) = @_;
    foreach my $target (keys %$self) {
        next if $target =~ /^_/;
        my $files = $self->{$target};
        foreach my $cf (values %$files) {
            return $cf if $cf->getDestination =~ /(^|$FSRE)$what$/;
            return $cf if $cf->getSource =~ /(^|$FSRE)$what$/;
        }
    }
}

=head2 hasTarget($target)

Return true if the specified target has one or more files present in the
change set, or false otherwise.

I<C<hasUOR>> is a deprecated alias for this method>

=cut

sub hasTarget ($$) {
    my ($self,$what)=@_;

    foreach my $target (keys %$self) {
	next if $target=~/^_/;
	return 1 if $target eq $what;
    }
    return 0;
}

{
    no warnings 'once';
    *hasUOR=\&hasTarget;
}

=head2 hasLibrary($target)

Return true if the specified library has one or more files present in the
change set, or false otherwise. (See L<Change::File/Targets vs Libraries> for
the distinction between targets and libraries.)

=cut

#<<<TODO: Could possibly optimise this based on the assumption that the
#<<<TODO: library is always a substring of the target, and in many case
#<<<TODO: *is the same* as the target, by checking for a target key with
#<<<TODO: the library's name.
sub hasLibrary ($$) {
    my ($self,$lib)=@_;

    foreach my $file ($self->getFiles) {
	return 1 if $file->getLibrary() eq $lib;
    };

    return 0;
}

=head2 getFilesInTarget($target)

Return the file objects registered for the specified target in the change set.
Returns an empty list if the target is not present.

I<C<getFilesInUOR>> is a deprecated alias for this method>

=cut

sub getFilesInTarget ($$) {
    my ($self,$target)=@_;

    my $files=$self->{$target};
    return unless $files;
    return values %$files;
}

{
    no warnings 'once';
    *getFilesInUOR=\&getFilesInTarget;
}

=head2 getFilesInLibrary($library)

Return the file objects registered for the library (unit-of-release) in the
change set. Returns an empty list if no files belong to the specified library.

=cut

sub getFilesInLibrary ($$) {
    my ($self,$lib)=@_;

    my @files=();
    foreach my $file ($self->getFiles) {
	push @files,$file if $file->getLibrary() eq $lib;
    };

    return @files;
}

#---

=head1 TARGET/LIBRARY/FILE MUTATORS

=head2 addFile($cfobj)

Add the specified change file object to the change set, replacing an existing
instance of a file object with the same target destination and source file,
if present. Returns the change set.

=head2 addFile($target,$source,$destination [,$type [,$library]])

Create a new L<Change::File> object with the specified target location, source
file, and destination file. Optionally, the file type and library (if different
from the target) may also be specified.

A new change file object is constructed using L<Change::File/new> and added
to the set as above.

=cut

sub addFile ($$$$;$) {
    my ($self,$target,$source,$destination,$type,$library,$prdlib)=@_;
    
    if (ref($target) and $target->isa("Change::File")) {
	$self->addFiles($target);
    } else {
	my $fobj=new Change::File([$target,$source,$destination,
				   $type,$library,$prdlib]);
	$self->addFiles($fobj);
    }

    return $self;
}

=head2 addFiles(@cfobjs)

Add each of the specified change file objects to the change set, replacing
any existing instances of file objects with the same target location and
source file, if present. Returns the change set.

=cut

sub addFiles ($@) {
    my ($self,@fobjs)=@_;

    foreach my $fobj (@fobjs) {
	$self->throw("$fobj is not an object of class Change::File")
	  unless $fobj->isa("Change::File");
		
	my ($target,$src,$dest)=($fobj->getTarget,$fobj->getSource);
	$self->{$target}{$src}=$fobj;
	push @{$self->{_meta}{order}}, $fobj;
    }

    return $self;
}


#---

=head2 removeFile($cfobj)

Remove the specified change file object from this change set, if present.
Returns true if the change file object was found, or false otherwise.

=cut

sub removeFile ($$) {
    my ($self,$fobj)=@_;

    my $result=$self->removeFiles($fobj);
    return $result ? 1 : 0;
}

=head2 removeFiles(@cfobjs)

Remove each change file in the supplied list from this change set. A change
file that is not present in the change set is ignored. If called in a
non-void context, returns the list of file objects removed.

=cut

sub removeFiles ($@) {
    my ($self,@fobjs)=@_;

    my @removed=();
    my $order=$self->{_meta}{order};
    foreach my $fobj (@fobjs) {
	$self->throw("$fobj is not an object of class Change::File")
	  unless $fobj->isa("Change::File");

	foreach my $target (keys %$self) {
            # we need this check to remove key, _meta, which is related to
            # the implementation artifact metadata of a change set
	    next if $target=~/^_/;
	    my $files=$self->{$target};
	    foreach my $file (keys %$files) {
		my $fileobj=$files->{$file};
		if ($fileobj->getSource eq $fobj->getSource) {
		    push @removed, $files->{$file};
            delete $files->{$file};
		    next;
		}
	    }
	}

	my $ii=0;
	
	foreach my $forder (@$order) {	   
	    if($forder->getSource eq $fobj->getSource) {
		splice(@$order, $ii, 1); 
	    }
	    $ii++;
	}
    }

    # if a target has all files removed from it, remove the target
    foreach my $target (keys %$self) {
	delete $self->{$target} unless %{ $self->{$target} };
    }

    return @removed if defined wantarray;
}

=head2 removeAllFiles()

Remove all files currently associated with this change set. If called in a
non-void context, returns a list of the change file objects that were removed.

=cut

sub removeAllFiles ($) {
    my $self=shift;

    return $self->removeFiles($self->getFiles);
}

#------------------------------------------------------------------------------

=head1 DECLARED DEPENDENCIES

=head2 setDependencyType($dependency)

Set the default dependency that is to be declared upon file-overlap.

=cut

sub setDependencyType {
    my ($self, $type) = @_;
    $self->{_meta}{deptype} = $type;
}

=head2 getDependencyType

Returns the default dependency that is to be declared upon file-overlap.

=cut

sub getDependencyType {
    my ($self) = @_;
    return $self->{_meta}{deptype} || DEPENDENCY_TYPE_CONTINGENT;
}

=head2 addDependency($csid)

Add the changeset $csid as dependency to this change set.

=cut

sub addDependency ($$$) {
    my ($self,$csid,$type) = @_;
    $self->{_meta}{depends}{$csid} = $type;
}

=head2 addDependencies(%deps)
    
Add the dependencies given through I<%deps> to this change set.

=cut

sub addDependencies ($@) {
    my ($self,%deps) = @_;

    while (my ($csid, $type) = each %deps) {
        $self->{_meta}{depends}{$csid} = $type;
    }
}

=head2 getDependencies()

Return the declared dependencies for this change set as a hash-reference,
with change set IDs as hash keys and the type of dependency as value.

=cut

sub getDependencies() {
    my $self = shift;
    return $self->{_meta}{depends};
}

=head2 getDependenciesbByType ($type)

Return a list of change set IDs that are a declared dependency for this
change set with type I<$type>.

Returns the empy list if no such declared dependencies were found.

=cut

sub getDependenciesByType ($) {
    my ($self, $type) = @_;
    my @csids;
    while (my ($csid, $t) = each %{ $self->getDependencies }) {
        push @csids, $csid if $t eq $type;
    }
    return @csids;
}

=head2 removeDependency($csid)

Remove the dependency on the change set with the ID I<$csid>.

Returns the type of this now deleted dependency.

=cut

sub removeDependency($) {
    my ($self, $csid) = @_;
    delete $self->{_meta}{depends}{$csid};
}

=head2 clearDependencies()

Clear the list of declared dependencies for this change set.

=cut

sub clearDependencies() {
    my $self = shift;
    %{$self->{_meta}{depends}} = ();
}

#------------------------------------------------------------------------------

=head1 RENDERING/SERIALISATION METHODS

=head2 listChanges([$pretty [,$headeronly]])

List out changes in human-readable or machine-readable format, according to
whether the passed argument is true, or false (or not specified) respectively.
See also L<"render"> and L<"serialise">, which are convenience wrappers for
this method.

The output of this method is a change set header describing the status, ID,
time of creation, creating user, ticket, stage, and message. Unless the
C<headeronly> argument is supplied and true, this is followed by
one line per change file describing the target (relative directory path),
library (unit-of-release), source, destination, and file type (usually one
of new, changed, or unknown and represented by the C<FILE_IS_> symbols from
L<Change::Symbols>).

=cut

my %dependencyAsString = (
    (DEPENDENCY_TYPE_NONE)          => 'none',
    (DEPENDENCY_TYPE_ROLLBACK)      => 'rollback',
    (DEPENDENCY_TYPE_CONTINGENT)    => 'contingent',
    (DEPENDENCY_TYPE_DEPENDENT)     => 'dependent',
    (DEPENDENCY_TYPE_SIBLING)       => 'sibling',
);

sub listChanges ($;$$) {
    my ($self,$pretty,$headeronly)=@_;
    my $text="";

    my ($uname,$gname) = (getpwuid($<))[0,3];
    $gname = getgrgid($gname);
    my $ctime   = $self->getCtime()	    || time();
    my $csid	= $self->getID()	    || "<no id>";
    my $status	= $self->getStatus()	    || STATUS_UNKNOWN;
    my $move	= $self->getMoveType()	    || MOVE_REGULAR;
    my $time	= $self->getTime()	    || $self->getCurrentTime($ctime);
    my $user	= $self->getUser()	    || $uname;
    my $group	= $self->getGroup()	    || $gname;
    my $ticket	= $self->getTicket()	    || "<no ticket>";
    my $stage	= $self->getStage()	    || "<no stage>";
    my $message	= $self->getMessage()	    || "<no message>";
    my $depends	= $self->getDependencies();
    my $deptype = $self->getDependencyType();
    my $branch  = $self->getBranch();

    #my $references = $self->listReferences($pretty);

    if ($pretty) {
        my %refs    = $self->getReferences();
        my $refs = join ', ' => 
                        map { (my $s = $_) =~ s/emapprover/em approver/; uc($s) . " $refs{$_}" } 
                        keys %refs;
	$text.="Change set $csid status '$status' (".
	  STATUS_NAME($status).") created by $user on $time\n";
	$text.="  ".scalar($self->getFiles)." files in ".
	  scalar($self->getTargets)." targets\n";
	$text.="  Ticket $ticket, stage '$stage', move type '$move'";
	$text.=", branch '$branch'" if defined $branch;
	$text.="\n";
	$message=~s/\n/\n          > /g;
	$text.="  Message > ".$message."\n";
	$text.="  References: ".$refs."\n";
	$text.="  Functions: ".$self->getFunctions()."\n" if $self->getFunctions();
	$text.="  Testers: ".$self->getTesters()."\n" if $self->getTesters();;
	$text.="  Tasks: ".$self->getTasks()."\n" if $self->getTasks();
	$text.="  ".keys(%$depends)." declared " .(keys(%$depends) == 1 
                                                    ? "dependency.\n" 
                                                    : "dependencies.\n");
        for (keys %$depends) {
            $text .= "    $_  with type " . $dependencyAsString{$depends->{$_}} . "\n";
        }
    } else {
	# serialisation format. Note that this is like the record header in
	# change.db, but is *not* formally related to it in any way
	$branch = '' if not defined $branch;
	$text.=join SERIAL_DELIMITER,
	              $status,
	              $csid,
	  'created="'.$time.'"',
	      'user='.$user,
	    'ticket='.$ticket,
	     'stage='.$stage,
	      'move='.$move,
	  'message="'.$self->flatten($message).'"',
	  'depends='.join(',' => map "$_|$depends->{$_}", keys %$depends),
          'reference='.$self->getReferences,
	  'functions='.$self->getFunctions(),
	  'tasks='.$self->getTasks(),
	  'testers='.$self->getTesters(),
          'ctime='.$ctime,
          'group='.$group,
          'deptype='.$deptype,
	  'branch='.$branch;
	;
	$text.="\n";
    }
    
    $text.=$self->listFiles($pretty) unless $headeronly;

    return $text;
}

=head2 listFiles([$pretty])

List out the change files in a change set in human-readable or
machine-readable format. This is identical to listChanges() except
that the change set header is not included.

=cut

sub listFiles ($;$) {
    my ($self,$pretty)=@_;
    my $text="";

    if ($pretty) {    
	# human readable: group files by target, losing order
	foreach my $target ($self->getTargets) {
	    my @files=$self->getFilesInTarget($target);
	    $text.="  Target: $target (${\ scalar @files} files)\n";

	    foreach my $file (@files) {
		$text.="    ".$file->getSource." -> ".$file->getDestination.
		    " (".$file->getType.")\n";
	    }
	}
    }
    else {
	# machine readable: retain file order
	$text.=$_->serialise."\n" for $self->getFiles;
    }

    return $text;
}

=head2 metadataHash()

Return the metadata for the changeset as a list of key/value pairs,
where the key is the HTTP header that represents the metadata and the
value is a serialized version of the metadata

=cut

sub metadataHash {
  my ($self) = @_;
  my $deps = $self->getDependencies;
  my %headers = (HEADER_STATUS,          $self->getStatus,
		  HEADER_MOVE_TYPE,       $self->getMoveType,
		  HEADER_ID,              $self->getID,
		  HEADER_CREATOR,         $self->getUser,
		  HEADER_CREATION_TIME,   $self->getTime,
		  HEADER_STAGE,           $self->getStage,
		  HEADER_TICKET,          $self->getTicket,
                  HEADER_ID_DEP,          [ map "$_ $deps->{$_}", keys %$deps ],
		  HEADER_APPROVER,        $self->getApprover,
                  HEADER_REFERENCE,       scalar $self->getReferences,
		  HEADER_BRANCH,          $self->getBranch,
                );
  foreach (keys %headers) {
    delete $headers{$_}, next if !defined $headers{$_};
    delete $headers{$_} if $headers{$_} =~ /^\s*$/;
  }
  return %headers;
}

#-----

sub addReferences (@) {
    my ($self, %ref)=@_;
    while (my ($type, $val) = each %ref) {
        $self->{_meta}{reference}{$type} = $val;
    }
}

sub clearReferences () {
    my ($self) = @_;
    %{$self->{_meta}{reference}} = ();
}

sub getReferences {
    my ($self, @keys) = @_;

    if (%{$self->{_meta}{reference}}) {
        if (wantarray) {
	    return @{ $self->{_meta}{reference} }{@keys} if @keys;
            return %{$self->{_meta}{reference}};
        } else {
	    my @k = @keys ? @keys : keys %{$self->{_meta}{reference}};
            return join ",", map "$_|$self->{_meta}{reference}{$_}", @k;
        }
    }

    # grab it from the message instead
    my @refs = $self->_grepFromMessage(HEADER_REFERENCE);
    
    return @refs if wantarray;
    return join ',' => @refs;
}

#-----

=head2 getTesters()

Return the testers for the change set as a list.

Return the empty list if no testers exist.

=cut

sub getTesters() {
    my ($self) = @_;
  
    if (wantarray) {
	return @{$self->{_meta}{testers} || []};
    } else {
	return join "," => @{$self->{_meta}{testers} || []};
    }    
}

sub setTesters {
    my ($self, @testers) = @_;
    $self->{_meta}{testers} = \@testers;
}

=head2 getApprover()

Return the approver for the change set. 

Returns a false value if no approver exists.

=cut

sub getApprover() {
    my ($self) = @_;
    return $self->{_meta}{approver};
}

sub setApprover {
    my ($self, $approver) = @_;
    $self->{_meta}{approver} = $approver;
}

=head2 getFunctions()

Returns the functions as declared in this change set as a list. 

Returns an empty list of no functions were defined.

=cut

sub getFunctions() {
    my ($self) = @_;
    
    if(wantarray) {
	return @{$self->{_meta}{functions} || []};
    } else {
	return join "," => @{$self->{_meta}{functions} || []};
    }    
}

sub setFunctions {
    my ($self, @funcs) = @_;
    $self->{_meta}{functions} = \@funcs;
}

=head2 getTasks()

Returns the tasks as declared in this change set as a list. 

Returns an empty list of no tasks were defined.

=cut

sub getTasks() {
    my ($self) = @_;
  
    if(wantarray) {
	return @{ $self->{_meta}{tasks} || []};
    } else {
	return join "," => @{ $self->{_meta}{tasks} || []};
    }
    
}

sub setTasks {
    my ($self, @tasks) = @_;
    $self->{_meta}{tasks} = \@tasks;
}

=head2 getTasks()

Returns the original ID of a change set (presumably this only exists for
reinstated change sets).

Returns a false value if no original ID exists.

=cut

sub getOriginalID() {
    my ($self) = @_;
    return $self->_grepFromMessage(HEADER_ID);
}

#-----

=head2 render()

List out change set in human-readable (a.k.a. I<pretty>) format.

=head2 serialise()

List out change set in machine-readable format.

=cut

sub render    ($) { return $_[0]->listChanges(1); }

sub serialise ($) { return $_[0]->listChanges(0); }

# string representation is CSID
sub toString {
    return $_[0]->{_meta}{csid} || "<no id>";
}

=head1 CONSTRAINTS

=head2 checkConstraints(class,changeset,%constraints)

Checks the given I<%constraints> and returns true if they are satisfied, false
otherwise.

I<%constraints> is a hash with the two keys C<0> and C<1>. As values, both
receive a reference to a list of regular expressions. The regular expressions
will be matched against the serialized Change::File objects. Regular
expressions under the key C<0> are supposed not to match whereas those under
C<1> are supposed to match.

Satisfying the constraints means that none of the C<0> matches any Change::File
object and all of the C<1> match each Change::File object.

    my %constraints = (
            1   => [ qr#\bto=/bbsrc/# ],
            0   => [],
    );
    
    if (Change::Set->checkConstraints($cs, %constraints)) {
        print "All files have sane robocop paths";
    }

=cut

sub checkConstraints {
    my ($class, $cs, %constraints) = @_;

    my @files; 
    
    if (UNIVERSAL::isa($cs, 'Change::Set')) {
        @files = map $_->serialise, $cs->getFiles;
    } else {
        @files = split /\n/, $cs;
        shift @files;
    }

    for my $cons (@{ $constraints{0} }) {
        /$cons/ and return 0 for @files;
    }

    for my $cons (@{ $constraints{1} }) {
        /$cons/ or return 0 for @files;
    }

    return 1;
}

=head2 checkConstraintsForFile($file)

Checks the constraints for a change set whose serialized form
is read from I<$file> which is either a filename or a reference
to a readable filehandle.

This method considers failure to open the passed in <$file> to be
a failure of constraints and thus returns false.

=cut

sub checkConstraintsForFile {
    my ($class, $file, %constraints) = @_;

    if (not ref $file) {
        open $file, '<', $file
            or return 0;
    }

    my $cs = do {
        local $/;
        <$file>;
    };

    return $class->checkConstraints($cs, %constraints);
}

#------------------------------------------------------------------------------

=head1 CLASS METHODS

=head2 flatten($text)

Convert supplied text into a flattened format suitable for streaming messages
into text format:

=over 4

=item * Double quotes are escaped.

=item * Existing backslash characters are escaped.

=item * Line feeds are converted into literal C<\n> strings (i.e.,
        a C<\> followed by a C<n>).

=back

This routine is used by L<Change::DB> to write the header line of database
records.

=cut

sub flatten ($$) {
    my ($proto,$msg)=@_;

    $msg=~s/\\/\\\\/g;
    $msg=~s/"/\\"/g;
    $msg=~s/\n/\\n/g;

    return $msg;
}

=head2 unflatten($text)

Perform the inverse transformation to L<"flatten"> above.

=cut

sub unflatten ($$) {
    my ($proto,$msg)=@_;

    $msg=~s/\\\\n/\0/g;
    $msg=~s/\\n/\n/g;
    $msg=~s/\\"/"/g;
    $msg=~s/\\\\/\\/g;
    $msg=~s/\0/\\n/g;

    return $msg;
}

=head1 MISCELLANEOUS METHODS

=head2 getCurrentTime()

Get the current time in the format "Day Date HH:MM:SS YYYY". This is the
same as the return value of C<scalar(localtime)>

=cut

sub getCurrentTime ($;$) {
    my ($self,$epoch) = @_;
    my $time=scalar(localtime(defined $epoch ? $epoch : ()));
    return $time;
}

sub _grepFromMessage ($) {
    my ($self, $field) = @_;

    return if not my $msg = $self->getMessage();

    my ($head) = split /\n\n/, $msg, 1;
    my @values;
    for (split /\n/, $head) {
        push @values, $1 if /$field:\s*(\S+)/;
    }
    return @values if wantarray;
    return shift @values;
}

=head2 generateChangeSetID([$user])

This class method Generates a valid change set ID for I<$user>.
If I<$user> is ommitted, the current user according to I<USER>
is assumed

=cut

sub generateChangeSetID {
    my($self,$user) = @_;

    my $uid = scalar getpwnam($user || USER);

    require Time::HiRes;
    return sprintf "%08X%06X%04X", time, 
                   ((Time::HiRes::gettimeofday())[1] & 0xFFFFFF),($uid & 0xFFFF);

}


#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::File>, L<Change::Symbols>, L<Change::DB>

L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
