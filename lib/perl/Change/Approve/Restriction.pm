package Change::Approve::Restriction;
use strict;

use base 'BDE::Object';

use overload '""' => "getApproval", fallback => 1;

use Util::File::Basename qw(basename);
use Util::Message qw(get_debug debug2 debug3);

#==============================================================================

=head1 NAME

Change::Approve - Identification and management of approval processes

=head1 SYNOPSIS

    use Change::Approve qw(getApproval);
    my ($approval_type,$approval_criteria)=getApproval($filename);

=head1 DESCRIPTION

C<Change::Approve> encapsulates the logic that determines whether an approval
process is required, and if so, which one and what criteria (if any) are
applied to it.

In string context a restriction object returns the approval type, without
criteria or optional qualifier.

=cut

#==============================================================================

=head1 CONSTRUCTOR

=head2 new(\($files,$users,$approval[, $criteria [,$optional]]))

Create a new L<Change::Approve::Restriction> object from the specified
array reference of attribute values. The files and users are themselves
array references containing the names of the files and users applicable to
the restriction.

=cut

sub initialiseFromArray ($$) {
    my ($self,$aref)=@_;
    my ($files,$users,$approval,$criteria,$optional)=@$aref;

    $self->throw("Initialiser passed argument not an array reference")
      unless UNIVERSAL::isa($aref,"ARRAY");
    $self->throw("Initialiser passed files subelement not an array reference")
      unless UNIVERSAL::isa($files,"ARRAY");
    $self->throw("Initialiser passed users subelement not an array reference")
      unless UNIVERSAL::isa($users,"ARRAY");

    $self->{files}={ map {$_=>1} @$files };
    $self->{users}={ map {$_=>1} @$users };
    $self->{approval}=$approval;
    $self->{criteria}=$criteria;
    $self->{optional}=$optional ? 1 : 0;

    return $self;
}

#------------------------------------------------------------------------------

=head1 ACCESSORS/MUTATORS

=head2 getID()

=head2 setID($name)

=cut

sub getID  ($) { return $_[0]->{id}; }
sub setID ($$) { $_[0]->{id}=$_[1];  }

=head2 getFiles()

Get the files associated with this restriction. Return the list of files in
list context, or an array reference of the file in scalar context.

=head2 setFiles($aref)

Set the files associated with this restriction.

=head2 getUsers()

Get the users associated with this restriction. Return the list of users in
list context, or an array reference of the file in scalar context.

=head2 setUsers($aref)

Set the users associated with this restriction.

=head2 getApproval()

Return the approval type for this restriction. Registered approval types are
defined by symbols in L<Change::Symbols> and may be one of:

   APPROVE_NONE      - no approval required
   APPROVE_CSAPPROVE - approved by the csapprove tool
   APPROVE_PRQSMV    - approved by PRQS MV ticket
   APPROVE_RDMV      - approved by RDMV ticket
   APPROVE_TSMV      - approved by TSMV ticket
   APPROVE_BBMV	     - approved by BBMV ticket
   APPROVE_REJECT    - file may not be checked in by this user

=head2 setApproval($approval_type)

Set the approval type, which should be one of the registered approval types
noted above.

=head2 getCriteria()

Get the criteria (if any) for the approval.

=head2 setCriteria($approval_criteria)

Set the criteria for the approval. Note that criteria are aribtrary and
vary in use and applicabilty depending on the approval type.

=head2 isOptional()

Return true if the approval type is optional, or false if it is mandatory.

=head2 setOptional(true|false)

Set the approval type to be optional if passed a true argument, or mandatory
otherwise.

=cut

sub getFiles     ($) { return wantarray ? (keys %{$_[0]->{files}})
                                        : $_[0]->{files}; }
sub setFiles    ($@) { shift->{files}={ map {$_=>1} @_} }

sub getUsers     ($) { return wantarray ? (keys %{$_[0]->{users}})
                                        : $_[0]->{users}; }
sub setUsers    ($@) { shift->{users}={ map {$_=>1} @_} }

sub getApproval  ($) { return $_[0]->{approval}; }
sub setApproval ($$) { $_[0]->{approval}=$_[1];  }

sub getCriteria  ($) { return $_[0]->{criteria}; }
sub setCriteria ($$) { $_[0]->{criteria}=$_[1];  }

sub isOptional   ($) { return $_[0]->{optional}; }
sub setOptional ($$) { $_[0]->{optional}=$_[1] ? 1 : 0 }

#------------------------------------------------------------------------------

=head1 UTILITY METHODS

=head2 match($changefile,$username])

Return true if the supplied change file matches one of the files registered for
this restriction (which may be a filename, library target, or wildcard of
either), and the supplied user is one of the users registered for
this restruction. Return false otherwise.

=cut

sub match ($$$) {
    my ($self,$file,$username)=@_;

    my $leafname=basename($file);
    my $source=$file->getSource();
    my $debug=get_debug();
    my $id=$self->getID();

    # 1 - users
    return 0 unless
      exists $self->{users}{$username} or exists $self->{users}{"*"};

    # 2a - files
    return 1 if exists $self->{files}{".*"};
    return 1 if exists $self->{files}{$leafname};

    foreach my $filematch (keys %{$self->{files}}) {
	return 1 if $leafname=~m~^$filematch$~;
    }

    # 2b - directories/targets
    my $target=$file->getTarget();

    return 1 if exists $self->{files}{$target};
    foreach my $filematch (keys %{$self->{files}}) {
	return 1 if $target=~/^$filematch$/;
    }

    # 2c - directories/targets plus file
    my $relfile=$target.'/'.$leafname;

    return 1 if exists $self->{files}{$target};
    foreach my $filematch (keys %{$self->{files}}) {
	return 1 if $relfile=~/^$filematch$/;
    }

    return 0;
}


#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<change.approve>, L<Change::Approve::Restriction>

=cut

1;
