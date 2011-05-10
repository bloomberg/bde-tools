package Change::AccessControl;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    isPrivilegedMode
    isPrivilegedCscompileMode
    isInvalidContext
    isAdminUser
    isTestMode
    isRestrictedFile
    isNewCpp
    isValidFileType
    isStraightThroughLibrary
    isProgressLibrary
    isRapidBuild
    getChangeSetStraightThroughState
    getChangeSetManualReleaseState
    getChangeSetProgressState
    skipArch
    getRejectedSymbols
    getDeprecatedSymbols
    isGobWerrorException
    getFileLock
    setFileLock
    removeFileLock
    bssSizeCheck
    checkMaintenanceLocks
    canRecompileRestrictedFile
];

use Symbol ();
use IO::File;

use Util::Message qw(debug alert debug2 debug3 fatal get_debug error warning
		     verbose2);
use Util::File::Basename qw(basename dirname);
use Util::Retry qw(retry_output retry_output3);
use Util::AccessControl qw(acceptUser);

use BDE::FileSystem;
use Binary::Object;
use BDE::Build::Invocation qw($FS);
use BDE::Util::Nomenclature qw(isApplication isIsolatedPackage
			       getCanonicalUOR getPackageGroup);
use BDE::Util::DependencyCache qw(getCachedGroupOrIsolatedPackage);

use Change::Identity qw(deriveTargetfromName deriveUORfromName lookupName);
use Change::Symbols qw(ADMINLIST FILELOCKLIST FILETYPESALLOWED FILETYPESDENIED
		       MALLOCFILES REJECTLIST REJECTLIST_BADCALL SKIPONARCH
		       COMPONENTLIBLIST STRAIGHTTHROUGHLIST PROGRESSLIBLIST 
		       $RAPIDLIST
		       USER GROUP CHECKIN_ROOT POISONFUNC_EXCEPTIONS
		       CSTOOLS_BIN GOB_WERROR_EXCEPTION_FILE CS_INTEGRATION
		       STAGE_PREALPHA RECOMPILELOCKLIST RCS_RLOG);

use Change::Bulletin qw(displayBulletin);
use Change::Util::InterfaceRCS qw/getFileArchivePath lockFile unlockFile/;

my @CHECKLOCKCMD = (RCS_RLOG,"-L","-l");

use Util::Test qw(ASSERT);

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
}


#==============================================================================

=head1 NAME

Change::AccessControl - Utility functions for change set release permissioning

=head1 SYNOPSIS

    use Change::AccessControl(isRestrictedFile isLockedFile);
    my $restricted=isRestrictedFile("sensitive_file.c");

=head1 DESCRIPTION

C<Change::AccessControl> implements utility functions that provide various
forms of access control verification. As the implementation of change
and release mechanisms evolves, it is likely this module will evolve with it.

=cut

#==============================================================================

=head1 ROUTINES

The following routines are available for export

=head2 isInvalidContext()

This routine carries out various miscellanous checks for the validity of
the invoking context. It returns false if the context is valid, or a string
containing a reason message if any check fails.

In this implementation, I<valid constitutes> a C<GROUP> environment variable
with a valid value: defined, no spaces, and not one of the groups
C<blank-group>, C<training-class>, or C<put_your_group_here>.

=cut

sub isInvalidContext () {
    if (GROUP) {
	return "GROUP '${\GROUP}' contains whitespace" if GROUP =~ /\s/;
	return "GROUP '${\GROUP}' is invalid"
	  if GROUP =~ /^(blank-group|training-class|put_your_group_here)$/;
    } else {
	return "GROUP not set";
    }

    return undef; #OK.
}

=head2 isAdminUser($user)

Return true if the specified user is on the admin list C<change.admin>, or
false otherwise.

=cut

sub isAdminUser ($) {
    my $user=shift;

    return acceptUser(ADMINLIST,$user) ? 1 : 0;
}

=head2 isTestMode()

=cut

sub isTestMode() {
    return 1 if
      $ENV{CHANGE_CSTOOLS_BIN} &&
      $ENV{CHANGE_CSTOOLS_BIN} eq "/bbcm/infrastructure/tools/bin" &&
      $ENV{CHANGE_CS_DATA} &&
      $ENV{CHANGE_CS_DATA} =~ m-^/home/\w+/tmp- &&
      $ENV{PRODUCTION_HOST} &&
      $ENV{PRODUCTION_HOST} eq "local" &&
      $ENV{CHANGE_BF_DATA} &&
      $ENV{CHANGE_BF_DATA} =~ m-^/home/\w+/tmp- &&
      $ENV{CHANGE_BIG_DATA} &&
      $ENV{CHANGE_BIG_DATA} =~ m-^/home/\w+/tmp- &&
      $ENV{CHANGE_DATA_PATH} &&
      $ENV{CHANGE_DATA_PATH}  =~ m-^/home/\w+/tmp- &&
      $ENV{CHANGE_SWEEPLOCK} &&
      $ENV{CHANGE_SWEEPLOCK}  =~ m-^/home/\w+/tmp- &&
      $ENV{CHANGE_CSCOMPILE_TMP} &&
      $ENV{CHANGE_CSCOMPILE_TMP}  =~ m-^/home/\w+/tmp- &&
      $ENV{CHANGE_CHECKIN_ROOT} &&
      $ENV{CHANGE_CHECKIN_ROOT}  =~ m-^/home/\w+/tmp-;
    return 0;
}

=head2 isPrivilegedMode()

Return true if running in privileged mode, or false otherwise.

No explicit check of a specific user or group ID is made. Rather, the
determination of privilege is made by establishing whether or not the
Robocop staging directory C</bbsrc/checkin> is writable or not.

=cut

sub isPrivilegedMode() {
    return -w CHECKIN_ROOT;
}

=head2 isPrivilegedCscompileMode()

Returns true if running in a mode privileged enough to update the
cscompile header cache.

It does so be testing the effective UID against a list of allowed
users.

=cut

sub isPrivilegedCscompileMode() {

    # FIXME
    # Better move to a config file a la /bbsrc/tools/data/newcheckin/scm.accept
    my %accept_user = qw/robocop 1
                         cstools 1/;

    my $effective = getpwuid($>);
    return exists $accept_user{ $effective };
}


=head2 isRestrictedFile($file [,$user])

Return true if the supplied filename is restricted and the invoking real users
name is not in the accept list, or false otherwise. If the optional second
argument is specfied, check against that username instead of the name of the
real user.

In this implementation, I<restricted> means the file is listed in the file
C</bb/bin/locked.files>. This file does not include library information and
therefore any file with a given leafname is locked if listed here. The file
is read and cached the first time this routine is invoked, and will throw
an exception if for any reason it cannot be read. If a file is passed in with
a full or partial pathname, the leading path is stripped before the check is
made.

Note that this routine does not know of or respect locking information that
may be established by capabilities, and will likely be replaced by a pure
capability-based mechanism in time. At that time this routine will be
deprecated.

=cut

{
    my %files;
    my %recompileFiles;

    sub isRestrictedFile ($;$) {
	my ($file_obj,$user)=@_;

	# set user either to argument passed or to real USER
	$user ||= USER;

	# (uncomment the following to allow robocop to cscheckin any file)
	# user "robocop" is privileged to cscheckin any file
	#return 0 if $user eq "robocop";

	my $target = $file_obj->getTarget();
	my $file=basename($file_obj->getSource());

	unless (%files) {
	    my $db = _getCachedDBHandle();

	    # Load our cache in
	    my $rows = $db->{dbh}->selectall_arrayref("select elementname, username from metadata_restricted_checkin");
	    foreach my $row (@$rows) {
	      my ($rfile, $user) = @$row;
	      if ($user =~ /^\$/) {
		foreach $user (_expand_macro($user)) {
		  $files{$rfile}{$user} = 1;
		}
	      } else {
		$files{$rfile}{$user} = 1;
	      }
	    }
	    $db->rollback;
	    _clearCachedDBHandle();
	}

	# check file
	my $lib = $file_obj->getLibrary();    

        #not restricted
	return 0 unless (exists $files{$file} or exists $files{$target}
			 or exists $files{$lib});

	#allowed user
	return 0
	    if (exists $files{$file} && exists $files{$file}{$user});
	return 0  
	    if (exists $files{$target} && $files{$target}{$user});
	return 0  
	    if (exists $files{$lib} && $files{$lib}{$user});    

	return 0 if isAdminUser($user) && -f CS_INTEGRATION."/.admin_override";

	if(canRecompileRestrictedFile($file_obj,$user)) {
	    alert("Unchanged restricted file $file will be recompiled.");
	    return 0;
	}	 
        	    
	return 1; #restricted, not an allowed user.
    }


=head2 canRecompileRestrictedFile($file [,$user])

Return true if the supplied filename is not present in recompile-list and
if present, invoking user name is present in the accept list, else return 
false otherwise. If the optional second argument is specfied, check against 
that username instead of the name of the real user.

The filelist(/bbsrc/tools/data/checkin_recompile_restricted.tbl)is read and cached 
the first time this routine is invoked, and will throw
an exception if for any reason it cannot be read. If a file is passed in with
a full or partial pathname, the leading path is stripped before the check is
made.

=cut

    sub canRecompileRestrictedFile ($;$) {
	my ($file_obj,$user)=@_;
	my $target = $file_obj->getTarget();
	my $file=basename($file_obj->getSource());
	
	# recompile not allowed if file is changed
	return 0 if (! $file_obj->isUnchanged);

	unless (%recompileFiles) {
	    my $db = _getCachedDBHandle();

	    # Load our cache in
	    my $rows = $db->{dbh}->selectall_arrayref("select elementname, username from metadata_restricted_recompile");
	    foreach my $row (@$rows) {
	      my ($rfile, $user) = @$row;
	      if ($user =~ /^\$/) {
		foreach $user (_expand_macro($user)) {
		  $recompileFiles{$rfile}{$user} = 1;
		}
	      } else {
		$recompileFiles{$rfile}{$user} = 1;
	      }
	    }
	    $db->rollback;
	    _clearCachedDBHandle();
	}
	# check file
	    
	my $lib = $file_obj->getLibrary();

	# recompile allowed if file/lib/target is not present
	return 1 unless (exists $recompileFiles{$file} or 
			 exists $recompileFiles{$target} or 
			 exists $recompileFiles{$lib});

	# set user either to argument passed or to real USER
	$user ||= USER;

	#allowed user
	return 1
	    if (exists $recompileFiles{$file} && exists $recompileFiles{$file}{$user});
	return 1
	    if (exists $recompileFiles{$target} && $recompileFiles{$target}{$user});
	return 1
	    if (exists $recompileFiles{$lib} && $recompileFiles{$lib}{$user});

	return 1 if isAdminUser($user) && -f CS_INTEGRATION."/.admin_override";
	    
	print "\n";
	error("NOTE: $file is restricted file(even for recompilation). Please file a ");
	error("DRQS OU to group 55 to allow you to recompile this particular file."); 
	error("(applicable only for Unchanged Restricted file) \n");    
	    
	return 0; #restricted, not an allowed user to recompile.
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

#------------------------------------------------------------------------------

=head2 isNewCpp ($uor)

Return true if new C++ compilation options should be applied. Currently, this
queries the C<is_bde_library.tbl> file.

I<Note: This routine will be deprecated when build options are queried for this
information and C<pcomp> is no longer used by C<cscompile>.>

=cut

{
    my %newcode;

    sub isNewCpp ($) {
	my $uor=shift;

	unless (%newcode) {
	    my $fh=new IO::File COMPONENTLIBLIST
	      or fatal "Unable to open ".COMPONENTLIBLIST;

	    while (my $line=<$fh>) {
		next if $line=~/^\s*(#|$)/;
		chomp $line;
		$line=~s|^/bbsrc/||;
		$newcode{$line}=1;
		$newcode{basename($line)}=1;
	    }
	    close $fh;
	}

	return $newcode{$uor} ? 1 : 0;
    }
}

#------------------------------------------------------------------------------

=head2 isValidFileType ($uor,[$filename|.$extension])

Return true if the supplied unit-of-release is permitted to contain a file
of the type specified by the supplied file or extension. A filename with
no extension is considered 'typeless'.

In this implementation, I<permitted> means that a) the unit-of-release is
listed in the C<filetypesallowed.tbl> file and is associated with the file extension in question, or that the file extension is one of those universally
allowed in C<filetypesallowed.tbl>, and b) the unit-of-release is I<not> listed
in C<filetypesdenied.tbl> with the specified extension.

Special treatment is restricted to the following cases:

=over 4

=item * A component-based (i.e., non-legacy) location always allows C<cpp>
        files.

=item * The metadata extensions C<mem>, C<dep>, C<opts>, C<defs>, and C<cap>
        are always treated as universally allowed. (But note that the actual
        location and name of such files is further restricted elsewhere.)

=back

Note that this routine does not know of or respect file type information that
may be established by capabilities, and will likely be replaced by a pure
capability-based mechanism in time. At that time this routine will be
deprecated or its functionality substantially replaced.

Also note that in this implementation that C<new_fortran.lst> is no longer
supported, as its function is now served by appropriate configuration in
C<filetypesallowed.tbl>.

=cut

#As a special case, if the filename is passed as a C<Change::File> object with
#a status of C<FILE_IS_NEW>, the C<new_fortran.lst> file is also consulted and
#a false value returned unless the file or UOR is listed there.

{ my (%allowed,%denied);

  sub isValidFileType ($$) {
      # We need a DB handle, and this is the easiest way to get one
      my ($uor,$file)=@_;


      unless (%allowed) {
	  # Note that this probably puts unreasonable demands on
	  # anything using the module, as we really only need a
	  # postgres handle not a full binary::analysis object. We'll
	  # factor this out properly later.

	  my $db = _getCachedDBHandle();
 	  if (defined $db) {
 	      debug "reading filetypesallowed table";
 	      my $rows = $db->{dbh}->selectall_arrayref("select filetype, uor, allow from metadata_filetypes_allowed");
	      foreach my $row (@$rows) {
		my ($type, $uor, $allow) = @$row;
 		  $uor ||= "AnyLibrary";
		  $allow ||= 0;
 		  $allowed{$uor}{$type}=$allow;
 	      }
#	      $db->rollback; # Not strictly needed, but this way we're
                             # not hanging around in a transaction
                             # just in case.
	      _clearCachedDBHandle();
 	  } else {
 	      # this file must exist, or something is wrong
 	      fatal "Unable to open database handle: $@";
 	  }

	  $allowed{AnyLibrary}{$_}=1 foreach qw[mem dep opts defs cap pub];
      }

      my $ext="(NoType)";
      $file=~/\.(\w+)$/ and $ext=$1;
      my $canonical = getCanonicalUOR($uor);

      if (get_debug) {
	  if (exists $allowed{$uor}{$ext}) {
	      my $msg= $allowed{$uor}{$ext} ? "allowed" : "denied";
	      debug "file type .$ext in $uor: $msg";
	  } elsif (exists $allowed{$canonical}{$ext}) {
	      my $msg= $allowed{$canonical}{$ext} ? "allowed" : "denied";
	      debug "file type .$ext in $canonical: $msg";	  
	  } else {
	      debug "file type .$ext in $uor: no criterion configured";
	  }
	  if (exists $allowed{AnyLibrary}{$ext}) {
	      my $msg= $allowed{AnyLibrary}{$ext} ? "allowed" : "denied";
	      debug "file type .$ext in <any>: $msg";
	  } else {
	      debug "file type .$ext in <any>: no criterion configured";
	  }
      }

      if ($allowed{$uor}{$ext} or 
	  $allowed{$canonical}{$ext} or 
	  $allowed{AnyLibrary}{$ext}) {
	if (defined $allowed{$uor}{$ext}) {
	    return $allowed{$uor}{$ext};
	}
	if (defined $allowed{$canonical}{$ext}) {
	    return $allowed{$canonical}{$ext};
	}
	if (defined $allowed{AnyLibrary}{$ext}) {
	  return $allowed{AnyLibrary}{$ext};
	}
      }
      return 0;
  }
}

#------------------------------------------------------------------------------

=head2 isStraightThroughLibrary($library)

Return the straight-through process state of the specified target, which
is relative to the staging root. (The target is typically derived from the
target attribute of a L<Change::File> object.)

The library (UOR) name is derived from the supplied target, and is also
checked, so targets under STP libraries will return true even if the target
itself is not configured.

Note that due to some legacy locations, it is possible for certain targets
to be configured that are below library level where the target is STP but
the library is not. If this were not the case, this routine would be
C<isStraigtThroughUOR>, as STP shuld ordinarily only apply to a unit of
release as a whole.

=cut

{
    my %stp;

    sub isStraightThroughLibrary ($) {
	my $uor=shift;

	unless (%stp) {
	    debug "reading ".STRAIGHTTHROUGHLIST;
	    my $fh=new IO::File STRAIGHTTHROUGHLIST
	      or fatal "Unable to open ".STRAIGHTTHROUGHLIST;

	    while (my $line=<$fh>) {
		next if $line=~/^\s*(#|$)/;
		chomp $line;
		$line=~s|^/bbsrc/||;
		$stp{$line}=1;
	    }
	    close $fh;
	}

	return $stp{$uor} ? 1 : 0;
    }
}

{
    my %progress;

    sub isProgressLibrary($) {
	my $uor=shift;

	unless (%progress) {
	    debug "reading ".PROGRESSLIBLIST;
	    my $fh=new IO::File PROGRESSLIBLIST
	      or fatal "Unable to open ".PROGRESSLIBLIST;

	    while (my $line=<$fh>) {
		next if $line=~/^\s*(#|$)/;
		chomp $line;
		$line=~s|^/bbsrc/||;
		$progress{$line}=1;
	    }
	    close $fh;
	}

	return $progress{$uor} ? 1 : 0;
    }

}

=head2 isRapidBuild($prodlib, $lib, $target)

Given the production library I<$prodlib>, the UOR I<$lib> and the target
I<$target>, determine whether this thing is handled by rapidbuild. Returns
a true value if so, false otherwise.

=cut

{
    my %rapid;

    sub isRapidBuild {
	my ($prod, $lib, $target) = @_;

	my ($tail)  = $target =~ m!^$lib/(.*)!;

	my $relativ = $tail ? "$prod/$tail" : $prod;

	if (not %rapid) {
	    open my $fh, '<', $RAPIDLIST 
		or fatal "Unable to open $RAPIDLIST: $!";

	    while (<$fh>) {
		next if /^\s*(#|$)/;
		chomp;
		$rapid{$_} = 1;
	    }
	}

	return exists $rapid{$relativ};
    }
}

=head2 getChangeSetStraightThroughState($changeset)

Return the straight-through status of the supplied change set. Each file in
the set is evaluated as described by C<"isStraightThroughFile"> above. The
return value is positive, negative, or false, according to the following
criteria:

=over 4

=item * If all files are indicated as valid for straight-through processing
        then a true positive integer value is retured.

=item * If all files are indicated as not valid for straight-through processing
        then a true negative integer value is returned.

=item * If files are indicated in both states then the change set is in
        process conflict and a false value is returned.

=back

Because change sets are atomic, it is not valid some files to be processed
straight through and others to be staged. Depending on the intent, a false
return value can be treated as a negative return value, i.e. if one file
cannot be passed straight through, then no file in the change set can. This
is however at the discretion of the process implementation.

=cut

sub getChangeSetStraightThroughState ($) {
    my $changeset=shift;

    my ($isstp,$ispg,$neither)=(0,0,0);

    foreach my $file ($changeset->getFiles) {
	if (isStraightThroughLibrary $file->getLibrary) {
	    $isstp++;
	} elsif (isProgressLibrary $file->getLibrary) {
	    $ispg++;
	} else {
	    $neither++
	}
    }

    return 0 if ($isstp and $neither) || ($ispg and $neither)
	|| ($ispg and $isstp);
    return 1 if $isstp;
    return 2 if $ispg;
    return -1;
}

=head2 getChangeSetProgressState($changeset)

Return the progress status of the supplied change set. Call
getChangeSetStraightThroughState inside.

=cut

sub getChangeSetProgressState ($) {
    my $changeset = shift;

    return 1 if getChangeSetStraightThroughState($changeset) == 2;
    return 0;
}

=head2 getChangeSetManualReleaseState($changeset)

Return the "manual release" status of the supplied change set.
Each unit of release in the change set is checked to see if it is configured
for manual release.  The return value is positive, negative, or false,
according to the following criteria:

=over 4

=item * If all units of release are marked "manual release"
        then a true positive integer value is retured.

=item * If none of the units of release are marked "manual release"
        then a true negative integer value is returned.

=item * If units of release are indicated in both states then the
	change set is in process conflict and a false value is returned.

=back

Because change sets are atomic, it is not valid some files to be manually
released and others to be staged.

=cut

sub getChangeSetManualReleaseState ($) {
    my $changeset=shift;
    my($is_manual_release,$is_staged_release) = (0,0);

    foreach my $uor ($changeset->getLibraries) {
	$uor = getCachedGroupOrIsolatedPackage($uor) || next;
	$uor->isManualRelease()
	  ? $is_manual_release++
	  : $is_staged_release++;
    }

    return
      $is_manual_release
	? $is_staged_release
	    ? 0 # some marked manual release (error)
	    : 1 # all  marked manual release
	: -1;	# none marked manual release
}

#------------------------------------------------------------------------------

=head2 skipArch($arch)

Return true if $arch is to be exempted from checkin checks. In this
implementation, $arch must be set to "SunOS" or "AIX".

In this implementation, the list is specified by C<skip_on_arch>.  The file
is read and cached the first time this routine is invoked, and will thown an
exception if for any reason it cannot be read.

=cut

{
    my $skipArchs = "";

    sub skipArch ($) {
	my ($arch)=@_;

        fatal("unknown arch: $arch") if $arch !~ /^(?:SunOS|AIX)$/;
	unless ($skipArchs) {
	    debug "reading ".SKIPONARCH;
	    my $fh=new IO::File SKIPONARCH
	      or fatal "Unable to open ${\SKIPONARCH}: $!";
            for my $a (<$fh>) {
                next if $a =~ /^\s*#/;
                $a =~ s/\s//g;
                $skipArchs .= "$a\n";
            }
            close $fh or fatal "Unable to close ${\SKIPONARCH}: $!";
	}
        return 1 if $arch eq "SunOS" and $skipArchs =~ /^sundev$/mo;
        return 1 if $arch eq "AIX" and $skipArchs =~ /^AIX$/mo;
        return 0;
    }
}

#------------------------------------------------------------------------------

=head2 fileCanCallBadCalls($file)

Return true if $file is allowed to invoke poisoned symbols, or false otherwise.
If $file has a leading path it is stripped via basename.

In this implementation, the files which are allowed to make these calls
the file C<slint/slint.badcalls>.  The file is read and cached the first time
this routine is invoked, and will die if for any reason it cannot be read.

=cut

{
    my $files;

    sub fileCanCallBadCalls ($$) {
	my ($lib,$file)=@_;

	##<<TODO this code is broken on files not directly under $lib
	unless (defined $files) {
	    debug "opening ".POISONFUNC_EXCEPTIONS;
	    my $fh=new IO::File POISONFUNC_EXCEPTIONS
	      or fatal "Unable to open ${\POISONFUNC_EXCEPTIONS}: $!";
            local $/= undef;
            ($files) = <$fh>;
	    $files ||= "";
            close $fh;
	}
	$file=basename($file);
        return($files =~ m%^\Q$lib/$file\E(?:\n|$)%m or 0);
    }
}

=head2 fileCanCallRejects($file)

Return true if $file is allowed to invoke rejected symbols, or false otherwise.
If $file has a leading path it is stripped via basename.

In this implementation, the files which are allowed to make these calls
the file C<malloc.files>. This file does not include library information and
therefore any file with a given leafname can be checked via this routine.
The file is read and cached the first time this routine is invoked, and will
die if for any reason it cannot be read.

=cut

{
    my $files;

    sub fileCanCallRejects ($) {
	my ($file)=@_;

	unless ($files) {
	    debug "opening ".MALLOCFILES;
	    my $fh=new IO::File MALLOCFILES
	      or fatal "Unable to open ${\MALLOCFILES}: $!";
            local $/= undef;
            ($files) = <$fh>;
            close $fh;
	}
	$file=basename($file);
        return($files =~ /^\Q$file\E(?:[ \t]*\n|$)/m or 0);
    }
}

=head2 getRejectList()

Returns list of "rejected" (i.e., disallowed) function calls that allocate
memory via malloc and are therefore not allowed the most Big code.
Currently specified list is in the external file C<reject.list>.

File is read and cached the first time this routine is invoked.
An exception is thrown if the file cannot be read.

=cut

{
    my @rejectList;

    sub getRejectList () {

	unless (@rejectList) {
	    debug "reading ".REJECTLIST;
	    my $reject_fh=new IO::File REJECTLIST
	      or fatal "Unable to open ${\REJECTLIST}: $!";
            @rejectList = <$reject_fh>;
            close $reject_fh;

	    @rejectList=grep { $_!~/^\s*(#|$)/ } @rejectList;

            chomp(@rejectList);
	}

	return \@rejectList;
    }
}

=head2 getBadCallsList()

Returns list of "rejected" (i.e., disallowed) function calls, currently
specified in the external file C<slint/slint.badcalls>.

File is read and cached the first time this routine is invoked.
An exception is thrown if the file cannot be read.

=cut

{
    my @badcallsList;

    sub getBadCallsList ($$) {

        return [] if &fileCanCallBadCalls;  # (pass args through)

	unless (@badcallsList) {
	    debug "reading ".REJECTLIST_BADCALL;
	    my $badcall_fh=new IO::File REJECTLIST_BADCALL
	      or fatal "Unable to open ${\REJECTLIST_BADCALL}: $!";
            push @badcallsList, <$badcall_fh>;
            close $badcall_fh;	

	    @badcallsList=grep { $_!~/^\s*(#|$)/ } @badcallsList;

            chomp(@badcallsList);
	}

	return \@badcallsList;
    }
}

=head2 getRejectedSymbols ($lib, $sourcefile, $objectpath)

Returns the list of "rejected" symbols (as provided by L<"getRejectList">
and L<"getBadCallsList">) that are present in the specified source file,
as determined by analysing its compiled object file, specified as the third
argument. If the file is listed in the exceptions list (i.e. returns true
from L<"fileCanCallRejects">) then no symbols are considered rejected and
so the return value is the empty list (which constitutes a "pass").

An exception is thrown if the object file specified by the second argument
cannot be read.

=cut

sub getRejectedSymbols ($$$) {
    my($lib,$file,$objPath) = @_;

## GPS: $lib should be robocop target, not library.
## but then we need to fix getCachedGroupOrIsolatedPackage() call below
#print STDERR "\n\nLIB: $lib FILE: $file OBJPATH: $objPath\n\n\n";
#sleep 3;

    return if fileCanCallRejects($file);

    my $object = new Binary::Object($objPath)
      || fatal("cannot create object $objPath");

    ## The filesystem root must have already been set by caller
    ##   e.g. BDE::Util::DependencyCache::setFileSystemRoot($root);
    my $uor = getCachedGroupOrIsolatedPackage($lib);

    my @rejects;
    unless (isApplication($lib) || ($uor && $uor->isOfflineOnly())) {
	if (substr($file,rindex($file,'.')+1) eq "f") {
	    ## Sun Studio8 compiler might add 'malloc' symbol to Fortran so
	    ## allow the symbol to exist, but disallow 'malloc_' and the like
	    map { $object->getSymbol("${_}_") && push @rejects,"${_}_" }
		@{getRejectList()};
	}
	else {
	    map { $object->getSymbol($_) && push @rejects,$_ }
		@{getRejectList()};
	}
    }
# Check for slint/slint.badcalls 
#    if ($file->isNew) {
#	map { $object->getSymbol($_) && push @rejects,$_ }
#	@{getBadCallsList($lib,$file)};
#    }

    return @rejects;
}

#------------------------------------------------------------------------------

=head2 getDeprecatedSymbols ($file, $lib, $objectpath)

Returns the list of "deprecated" symbols (as provided by C<deprecated_check>.
C<$objectpath> is passed as an absolute path and is assumed to be readable.
The routine will fail if the object cannot be read.

=cut

sub getDeprecatedSymbols ($$$) {
    my($file,$lib,$objPath) = @_;

    # (For some reason, this was triggering "Insecure dependency"
    #  but using the 3+ argument to open() bypasses the error.)
    #system("/bbsrc/bin/deprecated_check","-o",$objPath,$file,$lib);

    my $FH = Symbol::gensym;
    open($FH,'|-',"/bbsrc/bin/deprecated_check","-o",$objPath,$file,$lib)
      && close($FH);

    return ($? == 0);
}

=head2 isGobWerrorException($lib,$file)

Return true if $file is exempted from gob compile tests with --error-on-warn,
false otherwise.

In this implementation, the files which are exempted are listed in the file
C<gob_werror_exception.tbl>.  The file is read and cached the first time
this routine is invoked, and will die if for any reason it cannot be read.

=cut

{
    my %files;

    sub isGobWerrorException ($$) {
	my($lib,$file) = @_;
	$lib = getCanonicalUOR($lib) || $lib;

	unless (keys %files) {
	    debug "opening ".GOB_WERROR_EXCEPTION_FILE;
	    my $fh=new IO::File GOB_WERROR_EXCEPTION_FILE
	      or fatal "Unable to open ${\GOB_WERROR_EXCEPTION_FILE}: $!";
	    my($uor,$fname);
	    while (<$fh>) {
		next if /^\s*(#|$)/;
		($uor,$fname) = split ' ';
		$files{$uor.$FS.$fname} = 1;
	    }
            close $fh;
	}
        return exists $files{'gtk/'.$lib.$FS.$file};
    }
}

#------------------------------------------------------------------------------

=head2 bssSizeCheck ($file, $objPath)

Checks that the .bss size of the object is less than 1 MB or is listed in
the exception list (as provided by C<bss_size_exception.tbl()>.

$objPath is passed as an absolute path and is assumed to be readable;
the routine will fail if the object cannot be read.

=cut

#<<<TODO: GPS: FIXME revisit this code written very quickly
# Do not hard-code path to 'size' command

{
  my %bss_size_exceptions;

  sub _bssSizeCheckInitialize() {
    my $FH = Symbol::gensym;
    open($FH,"</bbsrc/tools/data/bss_size_exception.tbl") || die;
    while (<$FH>) {
      next if /^\s*#/;
      chomp;
      next unless /\s*(\S+)/;  # get first word (skips blank lines)
      $bss_size_exceptions{$_} = 1;
    }
    close $FH;
    undef $FH;
  }

  sub bssSizeCheck ($$;$) {
    my($file,$objPath,$bss_size) = @_;

    (%bss_size_exceptions)  or  _bssSizeCheckInitialize();

    unless (defined $bss_size) {
	return 1 if $^O eq "aix";  ##<<<TODO: skip AIX for now
	## AIX includes common areas in bss size so different solution needed

	my $PH = Symbol::gensym;
	unless (open($PH,'-|',"/usr/ccs/bin/size","-f",$objPath)) {
	    ##<<<TODO: check if this command fails; give error message
	    return 0;
	}
	local $/ = undef;
	$bss_size = <$PH>;
	close $PH;
	return 0 unless ($? == 0);
	unless ($bss_size =~ /(\d+)\(\.bss\)/s) {
	    return 1;  # allow file to pass if (.bss) size not reported
	}
	$bss_size = $1;
    }

    return 1 if $bss_size < 1048576;  # 1 MB limit on bss size

    ## RFE: place a limit on exceptions; modify format of exception table
    if ($bss_size_exceptions{$file}) {
	return 1;
    }

    return 0;  ## failure
  }

}

#------------------------------------------------------------------------------

=head2 getFileLock

If the supplied filename is locked, returns the unix user ID of the user
holding the lock. Otherwise, returns C<undef>.

In this implementation, I<locked> refers to an RCS archive file; the
supplied filename is looked for under C</bbsrc>, and a C<,v> extension
applied if necessary. C<rlog -L> is used to determine if a lock is present.
If the RCS file is not present it is presumed not to be locked. If a lock
is detected, a logfile (<.log> extension) is looked for. If found, the last
line is read and the user extracted from it. This user is then returned,
overriding the lock owner extracted from the C<rlog> command.

If the lock owner cannot be extracted from the output of the C<rlog> command,
or the last line of the log file (if detected) does not correspond to a
checkout record (starting with C<out>) then a fatal error is thrown.

=cut

sub getFileLock {
    my ($infile, $nonfatal) = @_;
    my $file=$infile;

    # FIXME 
    # This here (and a few lines further below) is a special case for
    # cscheckin:
    # It's a flag indicating that locking does not apply because the 
    # file is potentially staged as NEW. If the ,v file doesn't exist
    # for other reasons of course, we are screwed and let it slip by.
    return "-1" if not defined $file;

    $file.=",v" unless $file=~/,v$/;
    unless (-f $file) {
	$file=dirname($file).$FS.'RCS'.$FS.basename($file);
        if (not -f $file) {
            fatal "RCS archive for $infile not found" if not $nonfatal;
            error "RCS archive for $infile not found";
            return "-1"; 
        }
    }

    debug2 "Checking lock: @CHECKLOCKCMD $file";

    $file=~/^(.*)$/ and $file=$1; #untaint.
    my $output=retry_output(@CHECKLOCKCMD,$file);
    fatal("'@CHECKLOCKCMD $file' failed: $?") if $?;
    return undef unless $output; #not locked

    $output =~ /locked by:\s*([-\w]+)/;
    my $owner=$1;
    fatal "$file was found to be locked but no user was extracted:\n$output"
      if $output and not defined($owner);

    debug2 "Checking lock: lock owner is '$owner'";

    my $logfile=$file.".log";
    $logfile=~s/,v//g;
    if (-f $logfile) {
	my $FH = Symbol::gensym;
	my @lines = <$FH> if (open($FH,"<",$logfile));
	if (@lines && $lines[$#lines]=~/^out\s.*?\sby\s([-\w]+)/) {
	    $owner=$1;
	} else {
	    warning "$infile is locked but last line of $logfile is not ".
	      "a checkout record - file is in inconsistent state";
	}
    } else {
	fatal "$infile is locked but $logfile is not ".
	  "present - file is in inconsistent state";
    }

    debug2 "Checking lock: logged owner is '$owner'";

    return $owner;
}

=head2 setFileLock ($archivefile [,$steallock]);

Lock the specified filename, returning true on success or false otherwise.
If C<$steallock> is true, this routine will attempt lock the file even
if it is necessary to steal the lock from another user (use with care).

In this implementation, I<locked> refers to an RCS archive file; the supplied
filename is looked for under C</bbsrc>, and a C<,v> extension applied if
necessary.

The file is checked for a lock first with L<"getFileLock"> above. Attempting
to lock a file already locked by another user will fail unless C<$steallock>
is true. Attempting to lock a file already locked by the invoking real user ID
will succeed but will cause no actual change to the RCS. The special variable
C<$?> will contain the reason for the failure (if it is for a reason other than
a conflicting lock).

=cut

sub setFileLock ($;$) {
    my ($file,$steallock)=@_;
    $file = getFileArchivePath($file) if UNIVERSAL::isa($file, 'Change::File');

    if (my $owner=getFileLock $file) {
	if ($owner eq USER) {
	    verbose2("$file already locked by ".USER);
	    return 2;
	}
	elsif ($steallock || $owner eq "robocop") {
	    # (transfer from robocop since RCS file continues to be locked)
            debug3 "Transferring lock on $file held by $owner";
	}
	else {
	    error("$file is locked by $owner");
	    return 0;
	}
    }
    else {
        $steallock = 0;  #Not locked.  No stealing needed.
    }

    return (lockFile($file,$steallock) ? ($steallock ? 3 : 1) : 0);
}


=head2 removeFileLock ($archivefile [,$forceunlock]);

Unlock the specified filename and return the lock owner. The file is 
checked for a lock first 
with L<"getFileLock"> above. return undef if there is no lock

=cut

sub removeFileLock ($;$) {
    my ($file,$forceunlock)=@_;
    $file = getFileArchivePath($file) if UNIVERSAL::isa($file, 'Change::File');
    $forceunlock ||= 0;

    if (my $owner=getFileLock $file) {
	if ($owner ne USER && !$forceunlock) {
	    error("$file locked by $owner; not unlocking");
	    return 0;
	}
        debug3 "Unlocking $file held by $owner";
    }
    else {
	return 1;  # not locked; return success
    }

    return unlockFile($file,$forceunlock);
}

#------------------------------------------------------------------------------

=head2 getDeprecatedSymbols ($file, $lib, $objectpath)

Check for UOR maintenance locks. In list context returns a hash of
'UOR => reason' pairs in scalar context return the number of locked UORs.

=cut
sub checkMaintenanceLocks ($) {
    my $changeset=shift;

    my %locks;
    foreach my $uor ($changeset->getLibraries) {
	my $gop=getCachedGroupOrIsolatedPackage($uor);
	if ($gop->isLocked) {
	    $locks{$uor}=$gop->getLockMessage();
	}
    }

    return wantarray ? %locks : scalar(keys %locks);
}

#==============================================================================

sub testFileCanCallRejects() {

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                rc
#=========== ==================================== ====

# --- D0 ---
{a=>__LINE__,b=>                               "",c=>0 },

# --- D1 ---
{a=>__LINE__,b=>                          "cde.c",c=>1 },
{a=>__LINE__,b=>                      "foo/cde.c",c=>1 },
{a=>__LINE__,b=>                          "foo.c",c=>0 },
{a=>__LINE__,b=>                      "foo/foo.c",c=>0 },

);

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $rc      = ${$entry}{c};

    ASSERT(__LINE__ . ".$line", fileCanCallRejects($input), $rc);
  }

}

#==============================================================================

sub testSkipArch() {

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                 rc
#=========== ==================================== ====

# --- D1 ---
{a=>__LINE__,b=>                            "AIX",c=>0 },
{a=>__LINE__,b=>                          "SunOS",c=>0 },

);

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $rc      = ${$entry}{c};

    ASSERT(__LINE__ . ".$line", skipArch($input), $rc);
  }

}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
