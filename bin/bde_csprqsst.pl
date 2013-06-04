#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:${FindBin::Bin}:/usr/local/bin:/bbsrc/checkin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$|SUID_EXECUTION_PATH$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Util::File::Basename qw(basename);
use Util::File::Functions qw(ensure_path);

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
    DEFAULT_FILESYSTEM_ROOT
);
use Change::AccessControl qw(isPrivilegedMode 
			     getChangeSetManualReleaseState);
use Change::DB;
use Change::Symbols qw(DBPATH DBLOCKFILE CHECKIN_ROOT SNAPONE CHECKINONE
                       OPT_BIN CS_PRQSPG_DIR MOVE_IMMEDIATE
		       FILE_IS_UNCHANGED GROUP STATUS_COMPLETE);
use Util::Message qw(message error fatal verbose debug log_input
		     log_output open_log warning);
use Util::Retry;
use Production::Services;
use Production::Services::ChangeSet;
use Term::Interact;

use BDE::Util::DependencyCache;
use Change::Util::InterfaceSCM qw/recoverFilesSCM/;
use File::Temp qw/tempfile tempdir/;
use Change::Util::Bundle qw/unbundleChangeSet/;
use Change::Util::Interface qw/getCanonicalPath installScript
                               installReason createReason/;
use Change::Util::InterfaceRCS qw/rcs_commit_file/;
use File::Copy;

#==============================================================================

=head1 NAME

bde_csprqsst.pl - Move the files corresponding to a change set into RCS

=head1 SYNOPSIS

    # Moves files corresponding to the specified change set to RCS
    $ bde_csprqsst.pl 4267DA960320E94D

=head1 DESCRIPTION

This tool moves the files associated with a change set from the staging area to
RCS and updates the status of the development change set database accordingly.

=head1 NOTES

This tool calls the snap1 (/bbsrc/roboscripts/snap1) and checkin1
(/bbsrc/roboscripts/checkin1) scripts to move the files from the staging area
to RCS.

=head1 EXIT STATUS

A zero exit status is returned if all specfied files were successfully moved 
to RCS or non-zero if either the specified file was not found in the specified
change set or the move to RCS failed.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-c] [-d] [-v] <filename>
  --copy        | -c              copy the files to csdata directory 
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting
  --manual      | -m              manually release

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
	copy|c
        help|h
        verbose|v+
	manual|m
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1;

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

sub getFilesFromSCM {
    my $cs = shift;
    
    my $csid = $cs->getID;
    my (undef, $tarball) = do {
        local $^W;
        tempfile(OPEN => 0, CLEANUP => 0);
    };
    my ($ok, $error) = recoverFilesSCM($csid, $tarball);

    if($ok) {	
	my $tmp = tempdir(CLEANUP => 1);
	debug("getFilesFromSCM successfully $tarball, $tmp");
	unbundleChangeSet(Change::Set->new, $tarball, $tmp);
	return $tmp;	
    } else {
	fatal("Failed to get $csid from SCM");
    }    
}

#------------------------------------------------------------------------------
MAIN: {
    open_log();

    my $opts=getoptions();

    fatal "Not privileged to run this script $ARGV[0]" unless isPrivilegedMode();

    my $svc=new Production::Services;
            
    my $csid = $ARGV[0];
    $csid =~ /^(.*)$/ and $csid = $1; #untaint
    $csid=uc($csid); #allow case insensitivity

    my $changeset=Production::Services::ChangeSet::getChangeSetDbRecord($svc, $csid);    
    error("Change set $csid not found in database"), exit EXIT_FAILURE
      unless defined $changeset;

    unless ($changeset->getMoveType() eq MOVE_IMMEDIATE){   
	error("Change set $csid is not marked for straight-through processing."),
	exit EXIT_FAILURE;		
    } 

    if($changeset->getStatus() eq STATUS_COMPLETE) {
	error("Change set is complete. Nothing to do.");
	exit EXIT_SUCCESS;
    }

    # Run snap1 for all files
    # Set the logname as robocop
    $ENV{LOGNAME} = "robocop";

    my $root=new BDE::FileSystem(DEFAULT_FILESYSTEM_ROOT);
    BDE::Util::DependencyCache::setFileSystemRoot($root);

    # determine if change set will be manually released
    my $is_manual_release = getChangeSetManualReleaseState($changeset)
      || (error("Change set $csid is invalid mix of manual and staged release"),
	  exit EXIT_FAILURE); # (should not happen by time ST gets released)

    #check if change set is progress move
    my $is_progress_move=$changeset->isProgressMove;
   
    #change the status to 'P'
    unless($is_manual_release > 0 && $opts->{manual}) {
	debug("Changing status to P\n");

	my @cmd=("$FindBin::Bin/bde_altercs.pl","--status","P",$csid);
	my $output = Util::Retry::retry_output3(@cmd);
	warning "Failed to change $csid to P" if $?;

	debug("The result from csalter to P is $output\n") if $output;
	if($is_manual_release >0) {
	    exit EXIT_SUCCESS;
	}
    }
   
    my $rc;
    if($is_progress_move) {
	debug("Processing progress release\n");

	my $user  = $changeset->getUser();
	my $ticket= $changeset->getTicket();
	my $stage = $changeset->getStage();
	my $move  = $changeset->getMoveType();
	my $msg   = $changeset->getMessage();
	my $grp	  = $changeset->getGroup() || GROUP;

	my $fromdir=getFilesFromSCM($changeset); 
	foreach my $file ($changeset->getFiles) {
	    my $path=getCanonicalPath($file);
	    my $filename=$file->getLeafName;
	    my $target=$file->getTarget;
	    my $dest=CS_PRQSPG_DIR."/".$csid."/".$target;
	    my $type=$file->getType();
	    $type=FILE_IS_UNCHANGED if $file->isUnchanged;
	    	    
	    ensure_path($dest);	

	    verbose "Copy $fromdir/root/$path prqs pd directory";	    
	    unless(File::Copy::copy("$fromdir/root/$path",
				    "$dest/$filename")) {
		fatal("Failed to copy $dest/$filename");		
	    }

	    my $fobject= Change::File->new({
		target  => $file->getTarget,
		source => "$fromdir/root/$path",
		type   => $type
	    });

	    my $reason=createReason($filename, $type, $user,
				      $msg, $ticket, $stage,
				      $move, $csid);

	    $rc=rcs_commit_file($fobject, $user, \$reason);
	    if($rc) {
		debug("rcs commit file success");
		$rc = 0;
	    } else {
		debug("rcs commit file failed");
		$rc = 1;
	    }
	    
	}	
	
    }elsif($is_manual_release < 0) {
	debug("Processing straight through release\n");

	my @allFiles;
	foreach my $file ($changeset->getFiles) {
	    my $filename = $file->getDestination();
	    $filename    =~ s/\/bbsrc\/checkin\///;
	    push (@allFiles, $filename);
	}

	my $snaprc = 1;
	foreach my $file (@allFiles) {
	    my @cmd=(SNAPONE,"$file.checkin");
	    my $output = Util::Retry::retry_output3(@cmd);
	    $rc = $?;
	    debug("The result from snap1 is $output") if $output;
	    print $output if $output;
	    
	    $snaprc = 0 unless $rc;
	}
	
	if ($snaprc) {
	    error("snap1 failed for $csid");
	    # snap1 failed for all files, return failure
	    exit EXIT_FAILURE;
	}
		
	foreach my $file (@allFiles) {
	    my @cmd=(CHECKINONE,"$file.checkin","reg");	    	   	    
	    my $output = Util::Retry::retry_output3(@cmd);
	    $rc = $?;
	    debug("The result from checkin1 is $output") if $output;
	    print $output if $output;
	    if ($rc)
	    {
		error("checkin1 failed for $file $csid.");
		exit EXIT_FAILURE;
	    }	     
	}
    } else {
	debug("Processing manual release");
      	
	my $has_tty = -t STDIN or -t STDOUT;
	my $interact=new Term::Interact;	
	my $fromdir;
	if($has_tty) {
	    my $yn=$interact->promptForYN("Do you want to manually release $csid (y/n)?");		
	    exit EXIT_FAILURE unless $yn;
	    
	    # get files from SCM
	    $fromdir=getFilesFromSCM($changeset);	    
	} else {
	    verbose("Do nothing for manual release");
	    exit EXIT_SUCCESS;
	}

	my %file_err;
	my $err_num=0;

	my $user  = $changeset->getUser();
	my $ticket= $changeset->getTicket();
	my $stage = $changeset->getStage();
	my $move  = $changeset->getMoveType();
	my $msg   = $changeset->getMessage();
	my $grp	  = $changeset->getGroup() || GROUP;
	
	# Run snap1 and checkin1 for all manual files 
	foreach my $file ($changeset->getFiles) {
	    #install script file and reason file	
	    my $path = getCanonicalPath($file);
	    	  
	    my $filename=$file->getLeafName;
	    my $destfile=CHECKIN_ROOT.'/'.$filename;
	    
	    if (exists $file_err{$filename}) {
		warning("Duplicate file name is being processed.");
		warning("The following files need to be recovered from ".
			"the SCM -- correct version is NOT in /bbsrc/checkin ".
			@{$file_err{$filename}});
		warning("You MUST NOT run checkin1 manually without first".
			"recovering the file from the SCM.");
	    }

	    File::Copy::copy("$fromdir/root/$path", $destfile);
	   	   
	    my $type=$file->getType();
	    $type = FILE_IS_UNCHANGED if $file->isUnchanged;

	    debug("Install Reason file now");
	    installReason($destfile,
			  $type,
			  $user, 
			  $msg,
			  $ticket,
			  $stage,
			  $move,
			  $csid);
	    debug("Install Script now");
	    installScript($file, $user,
			  $grp, 
			  $ticket,
			  $stage, 
			  $move,
			  $csid,
			  "$destfile.checkin.sh");

	    my @cmd=(SNAPONE,"$filename.checkin");
	    debug("snap1 command is ", @cmd);
	    my $output = Util::Retry::retry_output3(@cmd);
	    $rc = $?;	 
	    debug("The result from snap1 is $output") if $output;
	    print $output if $output;
	    if ($rc) {
		$err_num++;
		error("snap1 failed for $path");
		push @{$file_err{filename}}, $path;
		next;
	    }
	
	    my @cmd2=(CHECKINONE,"$filename.checkin","reg");
	    $output = Util::Retry::retry_output3(@cmd2);
	    $rc = $?;
	    debug("The result from check1 is $output") if $output;
	    print $output if $output;
	    if ($rc)
	    {
		$err_num++;
		error("checkin1 failed for $path.");
		push @{$file_err{filename}}, $path;
	    }
	}
		
	$rc = 0;
	debug("checkin rcode is $err_num");
	exit EXIT_FAILURE if $err_num;
    }  

   
    # Change status of the change set to completed
    my @cmd=("$FindBin::Bin/bde_altercs.pl","--status","C",$csid);
    my $output = Util::Retry::retry_output3(@cmd);
    warning("Failed to change status of $csid to C") if $?;
    debug("The result from csalter C is $output") if $output;
    print $output if $output;
       
    exit $rc;
}

#==============================================================================

=head1 AUTHOR

Rohan Bhindwale (rbhindwale@bloomberg.net)

=head1 SEE ALSO
L<bde_altercs.pl>

=cut
