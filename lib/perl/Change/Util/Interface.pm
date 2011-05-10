package Change::Util::Interface;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    installScript
    installReason
    installFile
    installScripts
    installFiles
    installFilesTo
    createReason
    removeScripts
    removeAllFiles
    removeStagedFiles

    setForBugFix
];

use IO::File;
use File::Copy qw(copy);
use Util::File::Basename qw(basename dirname);
use Util::File::Functions qw(ensure_path);
use Util::Message qw(warning fatal error debug debug3 verbose message);
use BDE::Build::Invocation qw($FS);
use BDE::Util::DependencyCache qw(getCachedGroupOrIsolatedPackage);
use BDE::Util::Nomenclature qw(isApplication isThirdParty
                               getSubdirsRelativeToUOR
			       getRootRelativeUOR getRootRelativePath
			       getFullTypeDir getPackageType getType );

use Change::Util::SourceChecks qw(Inc2HdrRequired);
use Change::Util::Canonical    qw(canonical_path);
use Change::Symbols qw(
    BSTSTRIP MLSTRIP INC2HDR MAKEALIB
    BFONLY_FLAG BFLIBRARYFILE
    MOVE_EMERGENCY STAGE_PRODUCTION STAGE_PRODUCTION_LOCN 
    FILE_IS_NEW FILE_IS_UNCHANGED FILE_IS_CHANGED
    CHECKIN_ROBOCOP
    COMPCHECK_DIR MOVE_REGULAR MOVE_BUGFIX MOVE_IMMEDIATE
    CSCHECKIN_STAGED GROUP

    $INC2HDR_CINCRCS
);

#==============================================================================

=head1 NAME

Change::Util::Interface - Utility functions to perform low-level servides

=head1 SYNOPSIS

    use Change::Util::Interface qw(installScript installReason);

=head1 DESCRIPTION

This module provides utility functions that provide services that implement
specific detail in change set propagation. Typically, it providies routines
that check, create, or modify files that are related to the release process
mechanism.

=cut

#==============================================================================

sub _openFileFor ($$$;$) {
    my ($destfile,$locn,$extension,$perms)=@_;

    if ($locn) {
	if (-d $locn) {
	    $locn.=$FS.basename("$destfile.$extension");
	} else {
	    # locn=name of destination file
	}
    } else {
	$locn="$destfile.$extension";
    }

    $locn=~/^(.*)$/ and $locn=$1; #untaint.
    debug3 "opening $locn";

    my $ffh;
    if ($locn eq "STDOUT") {
	$ffh=new_from_fd IO::Handle(fileno(STDOUT),"w");
    } else {
        # Change umask in addition to passing a mode to IO::File because passing
        # a mode can only restrict, rather than open permissions.  We want to
        # ensure that owner and group have write permission, but nobody else
        # does.  Also, we use the Unix-style "O_WRONLY|O_CREATE" open mode 
        # because using the Perl-style ">" or C-style "w" open mode causes the
        # permissions argument to be ignored.
	$perms = 0664 unless defined($perms);  # (will be masked by umask)
        open $ffh, '>', $locn or do {
            error("Unable to open $locn: $!"); 
            return 0;
        };
        chmod $perms, $ffh;
    }

    return ($ffh,$locn);
}

##<<<TODO FIXME not sure why the above is so complex
##  There should be routine to figure out $locn; it should not be combined above
##  This routine is a temporary "undo" routine for the above so that the routine
##  can be called from installScripts() when installScript() fails.  Most of the
##  code here is copied from above
sub _deleteFileFor ($$$) {
    my ($destfile,$locn,$extension)=@_;

    if ($locn) {
	if (-d $locn) {
	    $locn.=$FS.basename("$destfile.$extension");
	} else {
	    # locn=name of destination file
	}
    } else {
	$locn="$destfile.$extension";
    }

    $locn=~/^(.*)$/ and $locn=$1; #untaint.
    debug3 "opening $locn";

    if ($locn ne "STDOUT" && -f $locn) {
	unlink($locn)
	  || warning("Failed to unlink $locn: $!");
    }
}

=head1 ROUTINES

The following routines are available for export:

=cut

=head2 installScript($file_obj,$user,$group,$tkt,$stage,$csid[,$locn])

Generate the '.checkin.sh' script for a change file.

The first argument is a L<Change::File> instance.  Be sure to set the type
of the L<Change::File> to indicate whether the file is a new or changed file.
The user is the submitting user, and the group is the 'release group', usually
defined by the C<GROUP> environment variable at cscheckin run time.
The ticket and change set ID, if
defined, provide the ticket number and ID number of the change set
respectively.

If the seventh (optional) argument is supplied, the script is written out to
the specified filename, or to standard output if the string C<STDOUT> is
specified. (To capture output to a string, see L<Util::Process/capture>.)

NOTE: before calling this routine, be sure to configure the DependencyCache:
    my $root = Change::Identity::getStageRoot($stage);
    BDE::Util::DependencyCache::setFileSystemRoot($root);

Returns true on success or false on failure.

=cut

##<<TODO: we should probably move lock testing to the point at which we
##	generate these scripts so that we have a better idea if we're
##	going to succeed or not.  There is still a LARGE race condition
##	between when the script is created and when it is run, but that
##	will change in the future when robocop pushes a button to have
##	the SCM dump to /bbsrc/checkin.

sub installScript ($$$$$$$;$) {
    my ($file,$user,$group,$tkt,$stage,$move,$csid,$locn)=@_;
    my $destfile=$file->getDestination();
    my $type=$file->getType();
    my $target=$file->getProductionTarget();

    $target=~s|^/+||; # called from csalter the target sometimes seems to
                      # start with a '/'. Suppressed here until the cause
                      # is known.
    $target=~s|/+$||; # sometimes a trailing '/' also. <<<TODO: investigate

    # tvp: Force CHANGED for REVERTED files:
    #	   this used to be UNCHANGED but a conversation with
    #      Belmonte convinced me that CHANGED is really the 
    #      right thing here. 
    $type = FILE_IS_CHANGED if $file->isReverted;

    my $base=basename($destfile);
    $tkt  ||= "<unknown>";
    $csid ||= "<unknown>";
    $move ||= "<unknown>";

    my $sdir="${\STAGE_PRODUCTION_LOCN}/$target";

    # add EMOVE comment when appropriate. The addition of the staging name
    # is explicit rather than using symbols because this is part of the
    # interface to Robocop. It may evolve in time as staging becomes a
    # more concrete reality. <<<TODO:
    my $emov_comment = ($move eq MOVE_EMERGENCY)
      ? "# EMOVE: ".(($stage eq STAGE_PRODUCTION) ? 'prod' : 'beta')
      : "";

    my $script = <<_CHECKIN_SH_SCRIPT;
#!/bin/ksh
# This script was auto-generated by $0 on ${\scalar localtime}.
# SRC_LIB: $sdir
# GROUP: $group
# LOGNAME: $user
# TICKET: $tkt
# STAGE: $stage
# CHANGE_SET: $csid
# FILE_TYPE: $type
# MOVE_TYPE: $move
$emov_comment

umask 002

# checkin.robocop --type <type> --user <user> <robofile> <target> <group>
${\CHECKIN_ROBOCOP} --type "$type" --user "$user" "$base" "$target" "$group"
if [[ \$? -ne 0 ]]; then
    echo "ERROR: \$0: ${\CHECKIN_ROBOCOP} failed for file $base";
    exit 1
fi

#* Yes, this script deletes itself as its last act
/usr/bin/rm -f \$0

_CHECKIN_SH_SCRIPT

    # Write out file with execute permissions enabled. (will be masked by umask)
    my($scriptfh)=_openFileFor($destfile,$locn,"checkin.sh",0774);
    return 0 unless defined $scriptfh;
    print $scriptfh $script;
    close $scriptfh;

    return 1;
}

=head2 installReason($destfile,$is_new,$user,$msg,$tkt,$stage,$move,$csid)

Generate the '.checkin.reason' script for a change file. The first argument is
the the destination location. (A L<Change::File> instance may also be specified
The second argument should be true if the file is new, or false if the file is
a change. The user is the submitting user. The message is the reason text
provided by the user describing the reason for the checked-in file. The ticket
and change set ID, if defined, provide the ticket number and ID number of the
change set respectively.

If the seventh (optional) argument is supplied, the script is written out to
the specified filename, or to standard output if the string C<STDOUT> is
specified. (To capture output to a string, see L<Util::Process/capture>.)

Returns true on success or false on failure.

=cut

# Removed prototype ($$$$$$$$;$$) because it caused incorrect calculation of
# final two arguments.
sub installReason {
    my ($destfile, $type, $user, $message, $tkt, $stage, $move, $csid, $locn) = @_;

    my ($messagefh,$genfile)=_openFileFor($destfile, $locn, "checkin.reason");
    return 0 unless defined $messagefh;
    my $reason=createReason($destfile, $type, $user, $message, $tkt,
			    $stage, $move, $csid);

    print $messagefh "$reason";
    close $messagefh;

    return 1;
}

sub createReason {
    my ($file, $type, $user, $message, $tkt, $stage, $move, $csid)=@_;
    
    $tkt=~s/^(\D+)/$1:/; #reason file expects a colon delimiter, add it
    $message=~s/\\n/\n/g; #LF token to LF

    my $reason=$message."\n";
    $reason=$reason."(file $file, stage $stage, movetype $move, is ".lc($type).")\n";
    $reason=$reason."--- $user checked this in ---\n";
    $reason=$reason."\@ticket: CSID:$csid $tkt\n";

    return $reason;
}

sub installFile {
    my ($srcfile, $destfile) = @_;

    $destfile=~/^(.*)$/ and $destfile=$1; #untaint.
    #<<<TODO: not clear why destfile is tainted at this point. Resolve.
    ensure_path dirname($destfile);

    error("Unable to copy $srcfile to $destfile: $!"), return 0
      unless (copy $srcfile => $destfile);

    return 1;
}

#------------------------------------------------------------------------------
# Change Set wrappers for File routines above

=head2 installFiles($changeset)

Install the source files to the destination files for a specified changeset.

=cut

sub installFiles {
    my ($changeset) = @_;

    my $csid=$changeset->getID();
    my $usr=$changeset->getUser();
    my $grp=$changeset->getGroup() || GROUP;
    my $tkt=$changeset->getTicket();
    my $move=$changeset->getMoveType();
    my $stage=$changeset->getStage();
    my $msg=$changeset->getMessage();

    my $result=1;
    foreach my $file ($changeset->getFiles) {
	my $src=$file->getSource();	
	my $dest=$file->getDestination();
	
	unless (installFile $src => $dest) {
	    error "Failed to copy $src to $dest: $!";
	    $result=0;
	}

	my $type=$file->getType();

        # force REVERTED into CHANGED
        $type = FILE_IS_CHANGED if $file->isReverted;

	$result = 0 
	    unless installReason($dest, $type, $usr, $msg, $tkt, $stage, $move, $csid);
    }

    return $result;
}

sub installFilesTo {
    my ($changeset, $destdir)=@_;

    my $csid=$changeset->getID();
    my $usr=$changeset->getUser();
    my $grp=$changeset->getGroup() || GROUP;
    my $tkt=$changeset->getTicket();
    my $move=$changeset->getMoveType();
    my $stage=$changeset->getStage();
    my $msg=$changeset->getMessage();

    my $result=1;
    foreach my $file ($changeset->getFiles) {
	my $src=$file->getSource();	
	my $dest=$destdir.'/'.basename($src);
	
	unless (installFile $src => $dest , undef) {
	    error "Failed to copy $src to $dest: $!";
	    $result=0;
	}

	my $type = $file->getType();

	$result = 0 
	    unless installReason($dest, $type, $usr, $msg, $tkt, $stage, $move, $csid);

	$result = 0
	    unless installScript($file, $usr, $grp, $tkt, $stage, $move, $csid, $destdir);
    }

    return $result;
}

=head2 installScripts($changeset)

Install all the C<.checkin.sh> scripts for a specified changeset.

=cut

sub installScripts ($;$) {
    my ($changeset) = @_;

    my $csid=$changeset->getID();
    my $usr=$changeset->getUser();
    my $grp=$changeset->getGroup() || GROUP;
    my $tkt=$changeset->getTicket();
    my $move=$changeset->getMoveType();
    my $stage=$changeset->getStage();

    my $result=1;
    foreach my $file ($changeset->getFiles) {
	$result = 0 
	    unless installScript($file, $usr, $grp, $tkt, $stage, $move, $csid);

	# also install in the SCM backup location (usually /bb/csdata/staged/):
	my $backup = CSCHECKIN_STAGED . "/$move";
	installScript($file, $usr, $grp, $tkt, $stage, $move, $csid, $backup);
    }

    ##<<<TODO FIXME  quick fix to remove all .checkin.sh files if creating 
    ##  one fails.  This does not remove auxscript if one is created (dubious).
    unless ($result) {
	foreach my $file ($changeset->getFiles) {
	    _deleteFileFor($file->getDestination(),undef,"checkin.sh");
	    _deleteFileFor($file->getDestination(),CSCHECKIN_STAGED."$FS$move","checkin.sh");
	}
    }

    return $result;
}

=head2 removeAllFiles($changeset)

Remove all destination files (source file, script file, and reason file)
for a specified changeset. If any file is missing an error is emitted and
a non-zero exit status is returned, however all files that should be removed
will be. (That is, the first missing file does not abort the removal of
subsequent ones.)

=cut

sub removeAllFiles ($) {
    my $changeset=shift;

    my $result=1;
    foreach my $file ($changeset->getFiles) {
	my $src=$file->getSource();
	my $dest=$file->getDestination();
	
	
	unless (unlink $dest) {
	    error "Failed to unlink $dest: $!";
	    $result=0;
	}

	foreach my $otherfile ("$dest.checkin.sh","$dest.checkin.reason") {
	    if (-f $otherfile) { #the checkin.sh might not be installed yet
		unless (unlink $otherfile) {
		    error "Failed to remove $otherfile: $!";
		    $result=0;
		}
	    }
	}

	my $leafname=$file->getLeafName();
	my $move=lc($changeset->getMoveType());
	my $stagedfile = CSCHECKIN_STAGED."$FS$move$FS$leafname";
	

	if(-f $stagedfile) {
	    unless (unlink $stagedfile) {
		error "Failed to unlink $stagedfile: $!";
		$result=0;
	    }
	}	
	 
	foreach my $other ("$stagedfile.checkin.sh", 
			   "$stagedfile.checkin.reason") {
	    if(-f $other) {
		unless (unlink $other) {
		    error "Failed to remove $other: $!";
		    $result=0;
		}
	    }
	}
	
    }

    return $result;
}


=head2 removeStagedFiles($changeset)

Remove all destination files (source file, script file, and reason file)
for a specified changeset.  A nonexistent file is considered trivial success.

=cut

sub removeStagedFiles ($) {
    my $changeset=shift;

    my $result=1;
    foreach my $file ($changeset->getFiles) {
	my $src=$file->getSource();
	my $dest=$file->getDestination();
	
	
	if (-f $dest) {
	    debug("Removing destination");
	    unless (unlink $dest) {
		error "Failed to unlink $dest: $!";
		$result=0;
	    }
	}

	foreach my $otherfile ("$dest.checkin.sh","$dest.checkin.reason") {
	    if (-f $otherfile) { #the checkin.sh might not be installed yet
		debug("Removing other files");
		unless (unlink $otherfile) {
		    error "Failed to remove $otherfile: $!";
		    $result=0;
		}
	    }
	}

	my $leafname=$file->getLeafName();
	foreach my $move (MOVE_REGULAR, MOVE_BUGFIX, MOVE_EMERGENCY,MOVE_IMMEDIATE) {
	    my $stagedfile = CSCHECKIN_STAGED."$FS$move$FS$leafname";

	    if(-f $stagedfile) {
		debug("Removing staged files");
		unless (unlink $stagedfile) {
		    error "Failed to unlink $stagedfile: $!";
		    $result=0;
		}
	    }	
	     
	    foreach my $other ("$stagedfile.checkin.sh", 
			       "$stagedfile.checkin.reason") {
		if(-f $other) {
		    debug("Removing other staged files");
		    unless (unlink $other) {
			error "Failed to remove $other: $!";
			$result=0;
		    }
		}
	    }
	}
    }

    return $result;
}

=head2 removeScripts($changeset)

Remove the script files (if present in the destination) for the specified
change set. Other than that it only removes the scripts this routine is
as L<"removeAllFiles"> above.

=cut

sub removeScripts ($) {
    my $changeset=shift;

    my $result=1;
    my $move=$changeset->getMoveType();
    foreach my $file ($changeset->getFiles) {
	my $dest=$file->getDestination();

	my $otherfile="$dest.checkin.sh";
	if (-f $otherfile) { #the checkin.sh might not be installed yet
	    unless (unlink $otherfile) {
		error "Failed to remove $otherfile: $!";
		$result=0;
	    }
	}
	my $leafname=$file->getLeafName();
	$otherfile = CSCHECKIN_STAGED."$FS$move$FS$leafname.checkin.sh";
    	if (-f $otherfile) { #the checkin.sh might not be installed yet
	    unless (unlink $otherfile) {
		error "Failed to remove $otherfile: $!";
		$result=0;
	    }
	}
    }

    return $result;
}

#------------------------------------------------------------------------------

=head2 setForBugFix ($changeset)

Write the details of the supplied change set such that it is marked as being
a I<bug fix>, i.e. swept into the next production build even if change set
propagation is restructed to bug fixes only (see
L<Change::Symbols::IS_BUGFIX_ONLY>).

In this implementation, change set details are written to the three files
C<monday_checkin>, C<monday_reasons>, and C<monday_libs>.

=cut

sub setForBugFix {
    my $changeset=shift;

    open my $lfh, ">>", BFLIBRARYFILE or do {
	error("Unable to open ".BFLIBRARYFILE.": $!");
	return;
    };

    foreach my $target ($changeset->getUORs) {
	print $lfh MAKEALIB." $target\n";
    }

    close $lfh;

    return 1;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
