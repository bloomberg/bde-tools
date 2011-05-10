package Change::Approve;
use strict;

use base 'Exporter';
use vars '@EXPORT_OK';
@EXPORT_OK=qw[checkApproval getApproval parseApprovalConfiguration isRoleAccount];

use Change::Symbols qw(USER APPROVE_REJECT APPROVE_NONE APPROVE_BBMV);
use Change::Approve::Restriction;

use Util::File::Basename qw(basename);
use Util::File::Functions qw(wild2re);
use Util::Message qw(fatal error debug debug2 debug4 debug5 get_debug);

use Production::Services::Ticket    qw/bbmv_is_mandatory/;

#==============================================================================

=head1 NAME

Change::Approve - Identification and management of approval processes

=head1 SYNOPSIS

    use Change::Approve qw(getApproval parseApprovalConfiguration);
    use Change::Symbols qw(APPROVELIST);
    parseApprovalConfiguration(APPROVELIST);

    my $filename=$ARGV[0];
    my ($approve_type,$approve_criteria)=getApproval($filename);
    print "File $ARGV[0] has approve type $approve_type($approve_criteria)";

    ...

    my $approval_type=checkApproval($changeset);
    exit EXIT_FAILURE if $approval_type eq APPROVE_REJECT;

=head1 DESCRIPTION

C<Change::Approve> encapsulates the logic that determines whether an approval
process is required, and if so, which one and what criteria (if any) are
applied to it. It works by reading a series of macro definitions and
restriction criteria (called simply I<restrictions>), and checking a file
against each restriction in turn until one matches.

Checking a change set is simply a matter of checking each of the files in the
change set, with the additional limitation that two files in the same change
set cannot have conflicting approval processes (since this would necessitate
the change set be non-atomic, which is not permitted).

This module provides routines to read, parse, and define macro definitions,
create restrictions (as L<Change::Approve::Restriction> objects), and
query approval information for both individual files and change sets.

=cut

#==============================================================================

# This is cloned frlom Change::AccessControl. It should be in its own
# module, but for the moment it isn't.
{
  # Shared, because it's better that way...
  my $db;
  my $creatingpid = 0;
  my $required = 0;

  sub _getCachedDBHandle {
    if (defined $db) {
      eval {
	$db->{dbh}->do("select 123");
      };
      if ($@) {
	eval {
	  undef $db;
	};
#	print "failed, resetting\n";
      }
    }
    if ($creatingpid != $$ || !defined $db || !defined $db->{dbh} || !$db->{dbh}->ping) {
#      print "requiring $$\n";
      if (!$required) {
	require Binary::Analysis;
	$required = 1;
      }
      eval {
	$db = Binary::Analysis->new();
	$creatingpid = $$;
      };
      if ($@) {
	undef $db;
	undef $creatingpid;
	fatal "unable to access database, $@";
      }
    }
 #   print "ping says ", $db->{dbh}->ping(), " and pg_ping is ", $db->{dbh}->pg_ping(), "\n";
    return $db;
  }

  sub _clearCachedDBHandle {
    if (defined $db) {
      eval {
	$db->rollback;
      };
      undef $db;
    }
  }

  # This subroutine expands out user macros. They always start with
  # a dollar-sign. The second parameter is a seen cache thing so we
  # don't get caught by circular macro definitions. Note that we do
  # *not* do a uniqifying pass, nor do we guarantee that circularly
  # dependent macros return things in the same order. (Circularly
  # dependent macros will have the same things in them, but the
  # ordering may be different, and there may be duplication in one
  # that's not in the other, and the output may depend on the order
  # they're expanded in or asked for)
  my %macro_expansions;
  my %raw_macros;
  sub _expand_macro {
    my ($macroname, $recursioncache) = @_;

    my $primary = 0;
    $primary = 1 unless $recursioncache;

    # The easy check -- is this even a macro? If not just return
    # what was passed in
    return $macroname unless $macroname =~ /^\$/;
    # Strip off the leading dollar sign
    $macroname =~ s/^\$//;

    # Have we seen it already?
    if ($macro_expansions{$macroname}) {
      return @{$macro_expansions{$macroname}};
    }

    # No, so we have to work. Dammit. Do we have a cache already?
    # Mark that we've already dived into ourself to start
    $recursioncache = {"\$$macroname" => 1} unless $recursioncache;

    # Load in the raw data if we haven't already
    unless (%raw_macros) {
      my $db = _getCachedDBHandle();

      my $rows = $db->{dbh}->selectall_arrayref("select macroname, element from metadata_user_macros");
      foreach my $row (@$rows) {
	push @{$raw_macros{$row->[0]}}, $row->[1];
      }
      # Reset the DB handle and release the memory for the rows
      $db->rollback;
      undef $rows;
      _clearCachedDBHandle();
    }

    my @expanded;
    foreach my $thing (@{$raw_macros{$macroname}}) {
      if ($thing =~ /^\$/) {
	if (!$recursioncache->{$thing}++) {
	  push @expanded, _expand_macro($thing, $recursioncache);
	}
      } else {
	push @expanded, $thing;
      }
    }

    # Remember for later
    $macro_expansions{$macroname} = \@expanded if $primary;
    return @expanded
  }

}

=head1 RESTRICTION FUNCTIONS

=head2 addRestriction($restriction_object)

Register a restriction (a L<Change::Approve::Restriction> instance).
Restrictions are stored in order of registration. Registering the same
restriction twice will enter it into the list twice, which is redundant but
harmless.

=head2 getRestrictions

Return a list of the currently registered restrictions.

=cut

{ my @restrictions;

  sub addRestriction ($) {
      fatal "Not a Change::Approve::Restriction object"
        unless $_[0]->isa("Change::Approve::Restriction");
      push @restrictions,$_[0];
  }

  sub getRestrictions () {
      return @restrictions;
  }
}

sub parseApproval ($) {
    my ($approvalstr)=@_;

    unless ($approvalstr=~/^([a-z]+)(?:\(([^)]+)\))?(\?)?$/) {
        # either abcd or abcd(some stuff)
        fatal "unparsable approval spec '$approvalstr'";
    }

    return ($1,$2,$3);
}

=head2 parseApprovalConfiguration($filename)

Read the contents of the supplied filename and extract macro definitions
(both user and file) and restriction specifications from it.

=cut

sub parseApprovalConfiguration {
    my $approvelist=shift;

    my $db = _getCachedDBHandle();
    my $rows = $db->{dbh}->selectall_arrayref("select location, username, approval, ordering from metadata_change_approve order by ordering");
    $db->rollback;

    foreach my $row (@$rows) {
      my @users = _expand_macro($row->[1]);
      my @files = map { wild2re $_} _expand_macro($row->[0]);
      my ($approval, $criteria, $optional) = parseApproval($row->[2]);
      foreach my $file (@files) {
	my $restriction = Change::Approve::Restriction->new([[$file],
							     \@users,
							     $approval,
							     $criteria,
							     $optional]);
	$restriction->setID($row->[3]);
	addRestriction($restriction);
      }
    }

}

#==============================================================================

=head1 ANALYSIS ROUTINES

=head2 getApproval($filename [,$username])

This is the core function of this module. It performs the lookup of
restriction data and returns the first matching restriction definition that
matches the input criteria. It is the only function that may be exported
through the C<use> statement.

Return the matching approval restriction (a L<Change::Approve::Restriction>
object) for the specified user name and file.
If no user is specified, the invoking user (as determined from the C<USER>
symbol) is used.

(Note: The L<cscheckin> tool may load a plugin to satisfy the process
requirements of some of these approval types. However, this module is not
coupled to such requirements and is not aware of them.)

=cut

sub getApproval ($;$$) {
    my ($file,$user,$approveconfig)=@_;
    $user ||= USER;

    parseApprovalConfiguration($approveconfig) if $approveconfig;

    fatal "First argument is not a Change::File"
      unless $file->isa("Change::File");
    foreach my $restriction (getRestrictions) {
	return $restriction if $restriction->match($file,$user);
    }
    
    # no match = reject. Note that the last line of change.approve would
    # typically say '* : * : none' so getting to this line may indicate
    # a malformed configuration file
    return new Change::Approve::Restriction([[],[],APPROVE_REJECT,undef,0]);
}

=head2 checkApproval($changeset [,$configfile])

Check the supplied change set for applicable approval restrictions. If
the second optional file argument is specified, load the restriction
configuration from that file. (Otherwise, the existing configiration, if
any, is applied -- see L<"parseApprovalConfiguration">.)

If no approval process applies to any file in the change set, then false
is returned. Otherwise, a restriction object is returned containing the
aggregated properties of the analysis. The string context evaluation of
this restriction object is the approval type, so the returned object can be
treated as the approval type for comparison purposes. Additional information
such as the optional or mandatory nature of the determined approval process
can be queried using the appopriate methods.

I<Note: Only the approval type and the optional attribute have explicit
values in the returned object in this implementation. The values of other
attributes, notably the file and user lists, are not specified and should
not be relied upon.>

If any file is determined to have 'reject' approval then an error message is
emitted to standard error and a restriction object with an approval type of
C<APPROVE_REJECT> is returned.

If two or more files are determined to have conflicting approval processes
then a (different) error message is emitted and a restriction object with an
approval type of C<APPROVE_REJECT> is again returned. Otherwise, the approval
type for the change set (being that there is at least one, and also no more
than one) is used for the returned object.

I<Note: At this time approval criteria are not handled. This means that
two files both with C<csapprove> approval but different criteria lists are
not checked to determine if their lists contain a common user or users. This
will be implemented in a future release.>

=cut

#<<<TODO: implement approval criteria resolution, see note in doc above.

sub checkApproval {
    my ($changeset, $approveconfig) = @_;

    return if isRoleAccount($changeset->getUser);

    my ($mandatory, $error) = bbmv_is_mandatory($changeset->getUser || USER);

    fatal "Could not determine if BBMV is mandatory: $error"
	if $error;

    return Change::Approve::Restriction->new([[], [], APPROVE_BBMV, undef, 0])
	if $mandatory;

    parseApprovalConfiguration($approveconfig) if $approveconfig;

    my (%atypes,%frestr,@restrictions);
    my $rejected=0;
    my $optional=1;
    foreach my $file ($changeset->getFiles) {
	my $restriction=getApproval($file);
	my $atype = $restriction->getApproval();
	my $acrit = $restriction->getCriteria() || "";
	my $id    = $restriction->getID();

	$frestr{$file}="$atype".($acrit?"($acrit)":"")." (restriction $id)";
	debug "$file has approval $frestr{$file}";

	if ($atype eq APPROVE_NONE) {
	    next;
	} elsif ($atype eq APPROVE_REJECT) {
	    my $reason=$acrit; $reason=~s/^"//; $reason=~s/"$//;
	    $reason=": $reason" if $reason;
	    error "Check in of ".basename($file)." to ".$file->getTarget().
	      " denied$reason";
	    error("(restriction $id)") if Util::Message::get_debug();
	    $rejected=1;
	    $optional=0 unless $restriction->isOptional();
	} else {
	    push @restrictions, $restriction;
	    $atypes{$atype}=1;
	    $optional=0 unless $restriction->isOptional();
	}

    }

    # if any file is rejected, the CS is rejected
    return new Change::Approve::Restriction([[],[],APPROVE_REJECT,
					    undef,$optional]) if $rejected;

    # check other files for consistency
    # First imp: very dumb, only checks type. Future imp: calculate
    # the intersection of users across criteria <<<TODO:
    if (scalar keys %atypes > 1) {
	error "File $_ has approval type $frestr{$_}"
	  foreach $changeset->getFiles();
	error "Conflicting approval types in change set: ".
	  join (", ",(sort keys %atypes));
	return new Change::Approve::Restriction([[],[],APPROVE_REJECT,
						undef,0]); #not optional!
    }

    my $type=%atypes ? (join '',keys %atypes) : 0; #one key, or none at all

    # only the summed type and optional nature need to be passed back
    return $type ? new Change::Approve::Restriction([[],[],$type,
						    undef,$optional]) : 0;
}

=head2 isRoleAccount([$user])

Returns true if I<$user> is a role-account, false otherwise.
If I<$user> is not specified, assumes C<Change::Symbols::USER>.

=cut

sub isRoleAccount {
    my $user = shift;

    $user = USER if not defined $user;

    my $db = _getCachedDBHandle();

    my $data = $db->{dbh}->selectall_arrayref(<<EOSQL);
select element from metadata_user_macros where macroname='ROLE_ACCOUNTS';
EOSQL

    my %role = map { $_->[0] => 1 } @$data;

    return exists $role{ $user };
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<change.approve>, L<Change::Approve::Restriction>, L<cscheckin>

=cut

1;
