package Change::Util::InterfaceRCS;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    getDiffOfFiles
    getFileArchivePath
    getFileVersionForCSID
    getFileVersions
    getMostRecentFileVersion
    getWorkingFileVersion
    copyOutFileVersion
    copyOutFileVersionForCSID
    copyOutMostRecentFileVersion
    compareToMostRecentFileVersion
    compareFileVersions
    lockFile
    unlockFile
    rcs_commit_file
    rcs_commit_cs
    get_rcs_head_revision
    get_rcs_prior_revision
    get_removed_Fortran_subs
    strip_rcs_lines
];

use Util::File::Basename qw(basename dirname);
use Util::Message qw(message warning fatal error debug debug2);
use Util::Retry qw(retry_output retry_system);
use BDE::Build::Invocation qw($FS);
use BDE::Util::Nomenclature qw(isApplication);
use Symbols qw(LEGACY_PATH);
use Change::Symbols qw(STAGE_PRODUCTION_LOCN ROBORCSLOCK ADD_RCSID
		       FILE_IS_UNCHANGED FILE_IS_NEW BREAKFTNX
		       $RCS_CI $RCS_CO $RCS_RCS RCS_RCSDIFF RCS_RLOG);

my @COPYOUTCMD = ($RCS_CO, qw/-M -T -q/);
my @RCSDIFFCMD=  (RCS_RCSDIFF, qw/-kk -q -w -u/); #as cscheckin

#==============================================================================

=head1 NAME

Change::Util::InterfaceRCS - Utility functions to perform RCS services

=head1 SYNOPSIS

    use Change::Util::InterfaceRCS qw(getFileVersionForCSID);

=head1 DESCRIPTION

This module provides utility functions that provide services that implement
RCS queries of various kinds.

=cut

#==============================================================================

=head2 getFileArchivePath($file,[$stagelocn])

Determine path to ,v file given Change::File and optional stage location.
Returns path to ,v file if ,v file exist.  Returns undef if ,v file not found.

=cut

{
  my %fileArchivePath;

  sub getFileArchivePath ($;$) {
    my($file, $stagelocn) = @_;
    fatal "Not a Change::File" 
        unless ref $file and $file->isa("Change::File");
    $stagelocn ||= STAGE_PRODUCTION_LOCN;
    my $libpath = join '/', $stagelocn, _physical_relative_lib_path($file);
    my $base = $file->getLeafName;
    my $key = "$libpath/$base";

    if (exists $fileArchivePath{$key}) {
        return $fileArchivePath{$key};
    } elsif (-f "$libpath/$base,v") {
        return ($fileArchivePath{$key} = "$libpath/$base,v");
    } elsif (-f "$libpath/RCS/$base,v") {
        return ($fileArchivePath{$key} = "$libpath/RCS/$base,v");
    }
    
    return;
  }
}

#---

=head1 ROUTINES

The following routines are available for export. In all cases,
if the file argument is a L<Change::File> object, the archive location is
determined from the file's basename and target using the specified stage
(if not supplied, the stage defaults to production). Otherwise, the file is
taken as a literal pathname to the archive file to be examined. The stage
argument has no meaning if the first argument is not a L<Change::File> object.

=head2 getFileVersionForCSID($file, $csid)

Analyse the version history for the specified file and return the version
for the specified file that corresponds to the specified change set ID.
If the change set is not found then C<undef> is returned.

=cut

sub getFileVersionForCSID {
    my ($file, $csid)=@_;

    if (ref $file) {
        $file=getFileArchivePath($file) if ref $file;
        return if not defined $file;
    } else {
        return undef unless -f($file.",v")
          or -f(dirname($file)."/RCS/".basename($file).",v");
    }
    
    my @log=split /\n/, retry_output(RCS_RLOG,$file);
    error($?),return if $?;

    my ($version,$current,$found);
    foreach my $line (@log) {
	$line=~/^revision\s+([\S]+)$/ and $version=$1;
	unless ($current) {
	    $line=~/^head:\s+(.*)$/ and $current=$1;
	}
	$found=1,last if $line=~/\bCSID:$csid\b/;
    }

    return $found ? ($version ? $version : $current) : undef;
}

=head2 getMostRecentFileVersion($file)

Get the most recent version of a given file, i.e. the version at the head.

=cut

sub getMostRecentFileVersion {
    my $file = shift;

    $file = getFileArchivePath($file) if ref $file;

    return if not defined $file;

    my @log=split /\n/, retry_output(RCS_RLOG,$file);
    my $version=undef;
    foreach my $line (@log) {
	$line=~/^head:\s+(.*)$/ and $version=$1,last;
    }

    return $version;
}

=head2 getFileVersions ($file, $csid)

Get the version prior to the specified CSID, the version associated with the
CSID, and the most recent version for the specified file. Returns a list
in the form:

   ($previousversion, $csidversion, $headversion)

If the CSID is not found then the first two values in this list will be
C<undef>. If the file itself is not found then just C<undef> is returned. If
the file was new for the specified CSID then the previous version will be
undef.

=cut

sub getFileVersions {
    my ($file, $csid) = @_;

    if (ref $file) {
        $file = getFileArchivePath($file) if ref $file;
        return if not defined $file;
    } else {
        return unless -f($file.",v") or 
                      -f(dirname($file)."/RCS/".basename($file).",v");
    }

    my @log=split /\n/, retry_output(RCS_RLOG,$file);
    error($?),return if $?;

    my ($got,$csversion,$previous,$head);
    foreach my $line (@log) {
	if ($line=~/^revision\s+([\S]+)$/) {
	    $got=$1;
	    next;
	} elsif (!$head and $line=~/^head:\s+(.*)$/) {
	     $got=$head=$1;
	     next;
	}

	if ($line=~/\bCSID:$csid\b/) {
	    # we have seen the CSID, so record it and unset
	    # the captured version so we can now look for the
	    # previous version.
	    $csversion=$got;
	    $got=undef;
	    next;
	}

	if ($csversion and $got) {
	    # the CSID has been seen and we have got a new
	    # version, so this must be the previous version
	    $previous=$got;
	    last;
	}
    }

    return ($previous,$csversion,$head);
}


sub getFileContent ($) {
    my $FH = new IO::File;
    substr($_[0],-2) eq ",v"
      ? open($FH, "$RCS_CO -p $_[0] 2>/dev/null|")
          || (warn "$RCS_CO -p $_[0] failed: $!\n", return)
      : open($FH,'<'.$_[0])
          || (warn "open $_[0] failed: $!\n",  return);
    local $/ = undef;
    my $contents = <$FH>;
    close $FH;
    return \$contents;
}

=head2 getDiffOfFiles ($localfile, $stagefile)

Get diff of 2 files removing all rcsid comparisons.

Return 0 if same file else return 1;

=cut

sub getDiffOfFiles {
    my($file_A,$file_B) = @_;
    
    my $contents_A = getFileContent($file_A);
    my $contents_B = getFileContent($file_B);
    return 1 unless defined($contents_A);
    return 1 unless defined($contents_B);

    # strip lines that remotely look like RCS-Headers
    $_ = strip_rcs_lines($_) for $$contents_A, $$contents_B;
 
    if ($$contents_A ne $$contents_B) {
	debug2 "different: $file_A and $file_B\n";
	return 1;    
    }
    else {
        debug2 "Same: $file_A and $file_B\n";
	return 0; 
    }		       

}


#------------------------------------------------------------------------------

sub safe_system (@) {
    my $FH;
    open($FH, '|-', @_) && close($FH);
    return $?;
}

#------------------------------------------------------------------------------

=head2 getWorkingFileVersion($file, $need_locker_info)

Extract and return the revision string for the specified current
working (checked out) file by scanning it for one or more of the RCS
keyword strings C<$>C<Header$>, C<$>C<Id$>, and C<$>C<Revision$>.
These keywords are generally expanded by the RCS co command to
contain revision information is generally. This module can also
return locker id from the header.  Although a false return
value indicates that revision information cannot be found, there are
actually two different false values that may be returned:

C<0> is returned if one or more of the needed RCS keywords were xxx
    found, but they are not expanded -- usually a benign condition.

C<undef> indicates that the file could not be opened or does not
    contain any of the needed RCS keywords -- usually an error condition.

=cut

sub getWorkingFileVersion($;$)
{
    my ($file, $need_locker) = @_;

    my $base = basename($file);

    # For FORTRAN files use add_rcsid --check to check if each SUBROUTINE has
    # an rcsid. 
    if ($file=~/\.f$/) {
	my @cmd_Header = (ADD_RCSID,"--check","-R","-q",$file);
	my @cmd_Id = (ADD_RCSID,"--check","-I","-q",$file);
	if (safe_system(@cmd_Header) && safe_system(@cmd_Id)) {
            error "One of the Subroutines in $base is missing an RCS Header ".
	        "or Id. Please use add_rcsid to add RCS id to the file.";
	    return undef;
	}
    }

    open FILE, "< $file" or do {
        error "Could not open $file for reading: $!";
        return undef;
    };

    my $unexpandedKeyword = 0;
    my $line = 0;
    while (<FILE>) {

        ++$line;

        # Extract version number from first Id, Header, or Revision string.
        # NOTE: Regexps are constructed to ensure that they themselves would
        # not be interpreted as an RCS keyword string.
        if ( /(?:\@\(\#\))?\$(?:Id|Header):[^\$]*[ \/]([^\/\$]+),v
                  \s(\d+(?:\.\d+)+)\s(?:\d+\/?)+\s(?:\d+:?)+\s\w+\s\w+\s(\w*) /x ) {
	    if(defined $need_locker) {
		my @fileinfo=($2, $3);
		return @fileinfo if ($1 eq $base);
	    }
	    else {
		return $2 if ($1 eq $base);
	    }

            warning("RCSid for $1 found in file $base at line $line");
            $unexpandedKeyword = 1;
        } elsif ( /\$Revision[:] (\d+(?:\.\d+)+)/ ) {
            return $1;
        }

        # Keep track of whether an unexpanded keyword string was found.
        $unexpandedKeyword = 1 if ( /\$(Id|Header|Revision):?\s*\$/ );
    }

    return $unexpandedKeyword ? 0 : undef;
}

=head2 copyOutFileVersion($file, $version, $destdir )

Copy out the specified RCS version for the specified file and places the copy
in I<$destdir>.  The timestamp of the checked out revision will be preserved.

Return true if successful and false otherwise.

=cut

sub copyOutFileVersion {
    my ($file, $version, $destdir) = @_;

    $file = getFileArchivePath($file) if ref $file;
    return if not defined $file;

    debug2 "executing '@COPYOUTCMD -r$version $file";

    if (system("cd $destdir; @COPYOUTCMD -r$version $file") == 0) {
        return 1;
    } else {
        error "Failed to copy out $file: $?";
        return 0;
    }
}

=head2 copyOutFileForCSID($file, $csid, $destdir)

Copy out the file version for the specified CSID to the directory I<$destdir>.
The timestamp of the checked out revision will be preserved.

Returns true on success or false (and emits an error to standard error) on
failure.

=cut

sub copyOutFileVersionForCSID {
    my ($file, $csid, $destdir) = @_;

    my $version = getFileVersionForCSID($file, $csid);
    unless ($version) {
	debug "File version for ".basename($file)." (CSID $csid) not found";
	return 0;
    }

    return copyOutFileVersion($file, $version, $destdir);
}

=head2 copyOutMostRecentFileVersion($file, $destdir)

Copy out the most revent revision for the specified file and place
the copy in I<$destdir>. The timestamp of the checked out revision
will be preserved.

If the file argument is a L<Change::File> object, the archive location is
determined from the file's basename and target using the specified stage
(if not supplied, the stage defaults to production). Otherwise, the file is
taken as a literal pathname to the archive file to be examined.

=cut

sub copyOutMostRecentFileVersion {
    my ($file, $destdir) = @_;

    $file = getFileArchivePath($file) if ref $file;
    return if not defined $file;

    debug2 "executing '@COPYOUTCMD $file";

    if (system("cd $destdir; @COPYOUTCMD $file") == 0) {
        return 1;
    } else {
        error "Failed to copy out $file: $?";
        return 0;
    }
}

=head2 compareToMostRecentFileVersion ($lclfile, $arcfile, $pretty [,$stage])

Compare the supplied local file to the most recent revision of the archive
locati$localfile,$localfile,on indicated by the file argument. Return a string containing the
difference report, or C<undef> if the difference could not be computed.
Note that an empty string is a legal return value meaning 'no difference'
and is not the same thing as C<undef>.

If the local file is a L<Change::File> object, the source attribute is
extracted and used as the local file path. The archive file is treated
as for L<"copyOutMostRecentFileVersion"> above. Note that the same file
object can be supplied for both local and archive file; in the first case
the local context is used, in the second the archive context.

By specifying the value C<html> as the third argument, an HTML document
fragment is generated. The caller still needs to supply the top-level
HTML elements to create a legal HTML document. A false value generates a
standard C<rcsdiff> report. Other values for this argument are not defined
and may beused to extend functionality in the future.

=cut

sub compareToMostRecentFileVersion {
    my ($localfile, $file, $pretty) = @_;

    $pretty ||= "none";
    $localfile=$localfile->getSource()
      if UNIVERSAL::isa($localfile,"Change::File");

    if (ref $file) {
        $file = getFileArchivePath($file) if ref $file;
        return if not defined $file;
    } else {
        # There seems to be a bug in rcsdiff; according to the man page,
        # specifying a repository file and a working file should diff the head
        # rev against the working copy.  In reality, you have to specify the
        # proper path to the repository's ,v file (with possible /RCS/
        # included).
        $file .= ",v" if ($file !~ m{,v$});
        debug2 "The different file is: $file, $localfile\n";

        if (! -f $file) {
            $file = dirname($file) . "/RCS/" . basename($file);

            if (! -f $file) {
                debug2 "$file not found\n";
                return undef;
            }
        }
    }


    my $base=basename($file);

    my $content;
  SWITCH: foreach ($pretty) {
	/^none$/ and do {
	    $content=retry_output(@RCSDIFFCMD,$file,$localfile);
	    last;
	};
	/^html$/ and do {
	    #<<<TODO: enhance later
	    $content=retry_output(@RCSDIFFCMD,$file,$localfile);
	    $content=~s/\&/&amp;/g;
	    $content=~s/</&lt;/g;
	    $content=~s/>/&gt;/g;
	    $content=~s|^(\-.*)$|<font color="red"><b>$1</b></font>|mg;
	    $content=~s|^(\+.*)$|<font color="green"><b>$1</b></font>|mg;
	    $content=~s|^(\@\@.*)$|<font color="blue"><b>$1</b></font>|mg;
	    $content="<pre>\n".$content."</pre>\n" if $content =~ /.+/; 
	    last;
	};
    }
    
    error "Failed to @{RCSDIFFCMD}: $?" if $content !~ /.+/;
	
    return $content; #may be undef
}

=head2 compareFileVersions($id1, $id2)

Compare RCS version IDs.  Return an integer less than, equal to, or greater
than 0, according to whether $id1 is older than, the same as, or newer than,
$id2.

=cut

sub compareFileVersions ($$) {
    my ($id1,$id2)=@_;

    my @parts1 = split '\.', $id1;
    my @parts2 = split '\.', $id2;

    # normalize (e.g., account for comparing 1.2 with 1.2.3)
    if ($#parts1 < $#parts2) {
        push @parts1, 0 x ($#parts2-$#parts1);
    }
    if ($#parts2 < $#parts1) {
        push @parts2, 0 x ($#parts1-$#parts2);
    }

    while (defined (my $n1 = scalar(shift @parts1))) {
        my $n2 = scalar(shift @parts2);
        next if $n1 == $n2;
        return $n1 < $n2 ? -1 : 1;
    }

    return 0;
}

#------------------------------------------------------------------------------

=head2 lockFile($file,[$verbose])

Lock a roboized RCS file (uses special setuid robocop program)
Pass in Change::File object ($file) or path to ,v file.
Returns 1 upon success, 0 upon error.

=cut

sub lockFile ($;$) {
    my($file,$verbose) = @_;
    $file = getFileArchivePath($file) if ref $file;
    return if not defined $file;

    my @quiet = $verbose ? () : ("-q");
    retry_system(ROBORCSLOCK,"-l",@quiet,$file) == 0
      ? return 1
      : (error("Failed to lock $file: $!"), return 0);
}

=head2 unlockFile($file,[$verbose])

Unlock a roboized RCS file (uses special setuid robocop program)
Pass in Change::File object ($file) or path to ,v file.
Returns 1 upon success, 0 upon error.

=cut

sub unlockFile ($;$) {
    my($file,$verbose) = @_;
    $file = getFileArchivePath($file) if ref $file;
    return if not defined $file;

    my @quiet = $verbose ? () : ("-q");
    retry_system(ROBORCSLOCK,"-u",@quiet,$file) == 0
      ? return 1
      : (error("Failed to unlock $file: $!"), return 0);
}

=head2 rcs_commit_file($file,$author,$commit_message_ref)

Commit file to RCS.  Pass in Change::File object ($file), unix name of author
and a reference to the message to be used for the RCS commit comment.
Returns 1 upon success, 0 upon error.

Source file is removed in the course of a successful commit.
However, caller should clean up any temporary directories.

=cut

sub rcs_commit_file {
    my($file, $author, $commit_message, $logfile) = @_;
    my $type     = $file->getType();
    my $src_file = $file->getSource();
    my $filename = $file->getLeafName();
    my $target   = $file->getTarget();
    my $vlib     = join '/' => LEGACY_PATH, _physical_relative_lib_path($file);

    my $ext      = substr($filename,rindex($filename,".")+1);

    -f $src_file || (warning("$src_file does not exist."), return 0);

    my $PH;

    if (not defined $logfile) {
	$logfile ||= '';
    } else {
	$logfile = ">$logfile 2>&1";   # output redirection when shelling out
    }

    my $vfile; 
    if ($vfile = getFileArchivePath($file)) {
	## ,v file exists

	## unconditionally grab RCS lock on ,v
	## (ignore any error; return code of 'ci' is what matters)
	system("$RCS_RCS -l -M -T $vfile $logfile");
    }
    else {
	## ,v file is new
	$vfile = -d "$vlib/RCS" ? "$vlib/RCS/$filename,v" : "$vlib/$filename,v";
   
	if ($type ne FILE_IS_NEW) {
	    warning "$filename is marked '$type' but $vfile does not exist";
	    return 0 if ($type eq FILE_IS_UNCHANGED);
	}

	message "creating initial version $target/$filename";

	## initialize new RCS file for .ml and .bst files
	## (set the keyword expansion rule for binary .ml & .bst files)
	## (using the real reason as the comment to rcs -i command is silly,
	##  but when r1.1 is checked in later, the comment will be ignored.)
	if ($ext eq "ml" || $ext eq "bst") {
	    local $SIG{PIPE} = 'IGNORE';
	    if (not open($PH, "|-", "$RCS_RCS -i -kb $vfile $logfile")) {
		error("Could not run $RCS_RCS -i -kb $vfile $logfile: $!");
		return;
	    }
	    print $PH $$commit_message;
	    close $PH or do {
		error("Failed to close $RCS_RCS -i -kb $vfile $logfile: $? . $!");
		return;
	    }
	}
    }

    if ($file->getType() eq FILE_IS_UNCHANGED) {
	## file is unchanged (checked-in only to force recompile)
	message "unchanged: $target/$filename"; 
	message $$commit_message;
        unlink($src_file)
	  || (warning("unlink $src_file: $!"),
	      return 0);
    }
    else {
	## check-in file to RCS
	$author ||= "robocop";
	message "checking $filename into $target";
	local $SIG{PIPE} = 'IGNORE';
	# TODO
	# remove -f option once RCS archives are split into movetypes.
	open($PH, "|-", "$RCS_CI -f -T -M -w$author $vfile $src_file $logfile") or do {
	    error "Could not do '$RCS_CI -T -M -w$author $vfile $src_file $logfile': $!";
	    return;
	};
	print $PH $$commit_message;
	close $PH or do {
	    error "Failed: ci -f -T -M -w$author '$vfile' '$src_file': $? . $!";
	    return;	
	};
    }

    # append to file ,v log (BLP-ism)
    my $vfilelog;
    substr($vfilelog = $vfile, -2, 2, ".log"); # replace ,v with .log
    if ($type ne FILE_IS_UNCHANGED and open($PH,">>",$vfilelog)) {
	## (scalar localtime() does not include timezone
	##  could include POSIX module or generate ourself;
	##  but easier to just shell out for now)
	my $date = `/usr/bin/date` || scalar localtime();
	chomp($date);
	$ENV{LOGNAME} ||= `/usr/bin/logname` || "robocop";
	chomp($ENV{LOGNAME});
	print $PH "in  on $date by $ENV{LOGNAME}\n";
	close $PH;
    }
    else {
	warning "open $vfilelog: $!" if $type ne FILE_IS_UNCHANGED;
    }

    ## update SICIRCS Index (preserve existing behavior of checkin.robocop)
    if (LEGACY_PATH eq "/bbsrc") { ## (i.e. skip updating stats if in test env)
	my $revision = get_rcs_head_revision($vfile);

	##<<<TODO: laziness, just shell out to these paths
	##	This should be replaced instead of calling legacy DevTools.
	my $envpath= $ENV{PATH};
	$ENV{PATH} = "/usr/local/bin:/usr/bin:/bin:/bbsrc/bin";
	## (note: $filename is a basename; duplicate basenames will conflict)
	system("/bbsrc/bin/bblog","-T","SICIRCS",$filename,$revision);
	$? == 0 || system("/bbsrc/bin/tools_support_logger","-s","e",
			  "perl_checkin_robocop",
			  "Failed: bblog -T SICIRCS $filename $revision");
	$ENV{PATH} = $envpath;
    }

    ## No need to update legacy /bbsrc/tools/hdr header cache
    ## No need to copy out headers; they're deployed by .checkin.sh sweep script
    ##   (and verified deployed by header-deploy-check.pl)

    ## copy out headers (** no longer necessary **)
    ## (TODO: remove existing headers within source tree before disabling this)
    ## (copy out headers even for unchanged files to force consistency with ,v)

    if (index($vlib,LEGACY_PATH."/") == 0
	&& $ext =~ /^(?:h|inc|hpp|ddl)$/
	&& isApplication($target)) {
	system("$RCS_CO -M -f $vlib/$filename $vfile $logfile");
	$? == 0 || warning "failed to co -M -f $vlib/$filename $vfile";
    }

    return 1;
}

sub _physical_relative_lib_path {
    my $file = shift;

    my $prod	= $file->getProductionLibrary;
    my $lib	= $file->getLibrary;
    my $target	= $file->getTarget;
    my ($tail)	= $target =~ m!^$lib/(.*)!;

    return $tail ? "$prod/$tail" : $prod;
}

=head2 rcs_commit_cs($cs, [$keep_original])

Commits all files in the change set I<$cs> and commits them to RCS. If the
optional second argument I<$keep_original> is true, the input files from I<$cs>
will not be deleted.

Returns a true value upon success, undef on failure.

=cut

sub rcs_commit_cs {

    my ($cs, $keep_original) = @_;

    my $mesg = $cs->getMessage;
    my $csid = $cs->getID;
    my $stag = $cs->getStage;
    my $user = $cs->getUser;
    my $tick = $cs->getTicket;
    my $move = $cs->getMoveType;

    require Change::Util::Interface;
    require File::Temp;
    require Util::File::Copy;

    my $tmp = File::Temp::tempdir(CLEANUP => 1);

    for my $file ($cs->getFiles) {

	my $type = $file->getType;
	my $leaf = $file->getLeafName;
	my $targ = $file->getTarget;

	my $log = Change::Util::Interface::createReason($leaf, $type, $user, $mesg, 
							$tick, $stag, $move, $csid);

	my $copy = $file->clone;

	if ($keep_original) {
	    my $tfile	= File::Spec->catfile($tmp, $copy->getLeafName);
	    Util::File::Copy::copyx($file->getSource, $tfile);
	    $copy->setSource($tfile);
	}

	if (not rcs_commit_file($copy, $user, \$log)) {
	    error "Failed to commit $file to RCS";
	    return;
	}
    }

    return 1;
}

=head2 get_rcs_head_revision($vfile)

Get the revision number of latest commit to given ,v file.
Revision is returned upon success, empty string upon error.

=cut

sub get_rcs_head_revision {
    my $vfile = shift;
    my $revision = "";
    if (open(my $ph,"-|",RCS_RLOG,"-h","-N",$vfile)) {
	while (<$ph>) {
	    /^head:\s+([\d.]+)/ && ($revision = $1, last);
	}
	close $ph;
    }
    return $revision;
}

=head2 get_rcs_prior_revision($vfile)

Get the revision number of commit immediately prior to head of given ,v file.
Revision is returned upon success, empty string upon error.

Assumes that timestamp on ,v file is timestamp of latest commit,
and finds the revision immediately prior to this point in time.

=cut

sub get_rcs_prior_revision {
    my $vfile = shift;

    ## create date stamp for localtime minus one second last modification time
    ## (generate datestamp for getting revision less than or equal to datestamp)
    my $date = stat($vfile) ? (scalar gmtime((stat(_))[9] - 1)) : return "";

    my $revision = "";
    if (open(my $ph,"-|",RCS_RLOG,"-N","-d$date",$vfile)) {
	while (<$ph>) {
	    /^revision\s+([\d.]+)/ && ($revision = $1, last);
	}
	close $ph;
    }
    return $revision;
}

=head2 get_removed_Fortran_subs($vfile)

List Fortran subroutines removed between prior revision and head revision
of given ,v file.  Returns list of routines upon success, empty list upon error.

Assumes that timestamp on ,v file is timestamp of latest commit,
and finds the revision immediately prior to this point in time for comparison.

=cut

sub get_removed_Fortran_subs {
    my $vfile = shift;
    my $breakftnx = BREAKFTNX." -breakftnxlistobjs -stdin";
    my %subroutines;

    my $prev = get_rcs_prior_revision($vfile)
      || return ();
    open(my $ph,"-|", "$RCS_CO -p -q -r$prev $vfile | $breakftnx")
      || return ();
    while (<$ph>) {
	chomp;
	$subroutines{$_} = undef;
    }
    close $ph;

    open($ph,"-|", "$RCS_CO -p -q $vfile | $breakftnx")
      || return ();
    while (<$ph>) {
	chomp;
	delete $subroutines{$_};
    }
    close $ph;

    return (keys %subroutines);  ## subroutines in prior ver not in current ver
}

=head2 strip_rcs_lines ($source)

Strips all lines from I<$source> that look like they could be RCS IDs.

Returns the thusly modified string.

=cut

sub strip_rcs_lines {
    my $src = shift;
    $src =~ 
	s{^.*(@\(#\))?(\$Date|Id|Header|Source|RCSfile|Revision|What|CSID|SCMId|cc|Log)\b.*\$.*}{}gm;
    return $src;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
