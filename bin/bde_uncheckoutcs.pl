#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:${FindBin::Bin}:/usr/local/bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Term::Interact;

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE
    DEFAULT_FILESYSTEM_ROOT );
use Change::Symbols qw(
    STAGE_PRODUCTION STAGE_BETA STAGE_INTEGRATION DBPATH DBLOCKFILE
    USER GROUP HOME CHANGERCFILES CHECKIN_ROOT
);

use Change::Arguments qw(getParsedTrailingLibraryArgument
			 parseCheckoutArgumentsRaw identifyCheckoutArguments);

use Change::Identity qw(deriveTargetfromName getLocationOfStage);

use Change::Configure qw(readConfiguration);

use Change::Util::Interface qw(getCanonicalPath);

use Util::File::NFSLock ();
use Util::Message qw(
    message verbose verbose2 alert verbose_alert
    warning error fatal debug debug2 debug3
);
use Util::File::Functions qw(ensure_path);

use Util::File::Basename qw(dirname basename);

use BDE::Component;
use BDE::Build::Invocation qw($FS);
use BDE::FileSystem;

use Change::AccessControl qw(
    isInvalidContext isRestrictedFile
    getFileLock removeFileLock checkMaintenanceLocks
);
use Change::Plugin::Manager;

use Change::Util::InterfaceSCM  qw/filesStagedSCM/;

use File::Path;
use File::Spec;

use Production::Services;
use Production::Services::ChangeSet qw();


#==============================================================================

=head1 NAME

csuncheckout - uncheckout file(s) by wildcard, changeset or filename

=head1 SYNOPSIS

Wildcard Usage

Uncheckout file by file name

  $ csuncheckout <filename> library
  $ csuncheckout library/filename

Uncheckout multiple files:

  $ csuncheckout ar* acclib
  (or using --to option)
  $ csuncheckout --to acclib ar*
    Found 4 files. Want to continue (y/n)?

List the checkout files

  $ csuncheckout -l ar* acclib
    Found 4 file(s) for 'ar*'. Want to continue (y/n)? y
    --- List of files to be checked out ---: 
    library=acclib:target=acclib:from=/bbsrc/acclib/arddb_utils.c:to=acclib/arddb_utils.c:type=CHANGED:production=acclib

Uncheckout files from multiple libraries:

  $ csuncheckout  acclib/* mtgeutil/*
  
Generate list of would-be-unchecked-out files, edit it, check out:

  $ cscheckin -n * acclib > acclib.changes
  $ vi acclib.changes
  (remove unwanted files from calculated changeset)
  $ csuncheckout --from acclib.changes

Uncheckout files in a changeset

  $ csuncheckout --csid <csid>


Uncheckout file by file name

  $ csuncheckout <filename> library
  $ csuncheckout library/filename

=head1 DESCRIPTION

This tool allows developers to uncheckout files from one or more libraries. 
File wildcards can be used to have the tool scan all candidate files in
current directory and if not found, then in the library. 

=head2 Plugins

C<csuncheckout> provides support for external plugins to augment or alter its
behaviour for application-specific purposes. This allows the tool to be
adapted to carry out additional processing and/or alter the list of files
considered according to additional logic supplied by the plugin.

Plugins are loaded with the C<--plugin> or C<-L> option. For example, to
load the example plugin, which simply prints out messages when it is
accessed:

    csuncheckout -LExample ...

Usage information, including command line extensions, can be extracted using
the usual C<--help> or C<-h> option:

    csuncheckout -LExample -LFileMap -LAnotherPlugin -h

Currently supported plugins include:

=item FileMap - Allows local files to be mapped to different destination
      libraries and/or application directories using a map file. An alternative
      way to specify multiple destinations.

=back

=head2 Per-User Configuration Files

C<csuncheckout> supports per-user configuration files which can be used to
supply automatic options to csuncheckout without specifying them on the command
line. The per-user configuration file is called C<.csrc> (pronounced 'cuzruck')
and must exist in the user's home directory.

The configuration file structure consists of a series of sections, one for
each CS tool, plus the special section C<[all]> that applies to all tools.
Blank lines and comments are supported, anything else is considered to be
a command-line option. Here is an example C<.csrc> file that provides 

    [all]
    # enable verbose for all tools
    -v

    [csuncheckout]
    # automatically load the FileMap plugin
    -LFileMap 

The C<.csrc> configuration file can be used to:

=over 4

* Automatically enable debug or verbose modes

* ...or supply any other command-line options the user desires.

=back

=head1 EXIT STATUS

The exit status is zero for success or non-zero on failure.

=cut

#==============================================================================


{ my $command="";

  sub setCommand($) { $command = shift; }
  sub isUncheckout()   {($command eq "uncheckout" ? return 1 : return 0); }
}

sub usage_uncheckout
{
    print qq|Usage:  uncheckout  [options] <file>  [<library>]
THIS VERSION USES CSUNCHECKOUT UNDERNEATH.
PLEASE USE "rcsuncheckout" if need to run legacy uncheckout tool. 

uncheckout cancels YOUR checkout for a file.  If you want to cancel somebody else's
checkout, the -F (forceunlock) option is required. 

Options are:

   -F  - Forcibly uncheckout the file (bypass .log & user checks).
         [ PLEASE USE -F instead of -f option earlier ]
   -h  - Print this message.
  
|;
}


sub usage(@) {
    print STDERR "!! @_\n" if @_;

    my $prog = "csuncheckout"; #basename $0;
    if(isUncheckout()) 
    {
	usage_uncheckout();
	exit 1;
    }

    print <<_USAGE_END;
Usage: $prog -h | [-d] [[-c]| [-p]] [-v] [-d] [-t=<unit>] <files>
  --debug        | -d            enable debug reporting
  --help         | -h            usage information (this text)
  --ignoreconfig                 ignore per-user configuration file, if present 
  --to           | -t <uor>      specify destination unit of release
                                 (only with unqualified file arguments)
  --noretry      | -X            disable retry semantics on file operations
  --verbose      | -v            enable verbose reporting
  --forceunlock  | -F            Forcibly uncheckout the file (bypass .log & user checks)

File input options:

  --from         | -f            read change set from file (e.g. previously
                                 generated with --list and --machine). Implies
                                 --unchanged.
  --input        | -i [<file>]   read additional list of explicit filenames
                                 from standard input or a file (if specified)
  --csid         | -C <csid>     checkout files from a previous change set id


Extended functionality options:

  --plugin       | -L <plugin>   load the specified extension

_USAGE_END
    my $plugin_usage=getPluginManager()->plugin_usage();
    print $plugin_usage,"\n" if $plugin_usage;

    print "See 'perldoc $prog' for more information.\n";
}

#------------------------------------------------------------------------------

{  #my $manager = new Change::Plugin::Manager(CSUNCHECKOUT_TOOL);
   my $manager = new Change::Plugin::Manager;
   sub getPluginManager { return $manager; }
}

sub getoptions {
    my @options=qw[
	debug|d+
        from|f=s
	help|h
	forceunlock|F	   
        list|l
        pretty|P
        csid|C
        to|t=s
        verbose|v+
	uncheckout	   
       ];

    my %opts;
    # this allows support for single, double - options
    Getopt::Long::Configure("bundling");

    # BEGIN pass through sections
    # 
    Getopt::Long::Configure("pass_through");

    # rc files
    # what configuration might be useful in csuncheckout??
    GetOptions(\%opts,"ignoreconfig","config=s@");
    unless ($opts{ignoreconfig}) {
	readConfiguration @ARGV,"csuncheckout",(map {
	    HOME.'/'.$_
	} split / /,($opts{config} ? (join ' ',${$opts{config}})
					: CHANGERCFILES));
    }

    # plugins and files-from-input (or rc files)
    $opts{plugin}=undef;

    GetOptions(\%opts,"plugin|L=s@","input|i:s","uncheckout");
    if($opts{uncheckout}) {
	$opts{curdir} = 1;
	push @{$opts{plugin}}, "GuessLib";
	$opts{do} = "none";
	setCommand("uncheckout");
    }

    GetOptions(\%opts,"plugin|L=s@","input|i:s");
    # END pass through sections

    Getopt::Long::Configure("no_pass_through");
    if ($opts{plugin}) {
	my $mgr=getPluginManager();
	foreach my $plugin_name (map { split /,/,$_ } @{$opts{plugin}}) {
	    my $plugin=$mgr->load($plugin_name);
	}
	push @options,$mgr->plugin_options();
    }
    if (defined $opts{input}) {
	my @lines;
	if ($opts{input}) {
	    open INPUT,$opts{input}
	      or fatal "Unable to open $opts{input}: $!";
	    @lines=<INPUT>;
	    close INPUT;
	} else {
	    @lines=<STDIN>;
	}
	verbose "input = @lines";
	my @input_args=map { chomp; split /\s+/,$_ } @lines;
	unshift @ARGV,@input_args if @input_args;
    }

    unless (GetOptions(\%opts,@options)) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS  if $opts{help};

    # filesystem root for local searches (*not* the destination root)
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    #$Util::Retry::ATTEMPTS = 0 if $opts{noretry};


    if ($opts{from}) {
	fatal "--from incompatible with file arguments (@ARGV)" if @ARGV;
    }
    
    if ($opts{from} and $opts{csid}) {
	fatal "--from and --csid are mutually exclusive";
    }

    if ($opts{csid}) {
	fatal "--csid allows only one argument" if @ARGV>1;
	$opts{csid}=$ARGV[0];
	@ARGV=();
    }
   
    # At this point @ARGV contains either nothing or a list of file names.
    # Make the list available to plugin_initialize hooks.
    $opts{files} = [ @ARGV ];
    @ARGV = ();

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

# FUNCTION: validate the changeset.
 # -> check if current directory is writable.
    # for each file
    #    -> check if it exists and belongs to the library.
    #    -> check if it should be checked out 
    #       -> it's dep/mem file 
    #       -> it's a functbl
    #       -> if it's a header derived from .inc, dont checkout that header
    #       -> is a restricted file
    #    -> check if the file is already checked-out 
    #   

sub validate_changeset($$$)
{
    my ($candidateset, $stage, $forceunlock) = @_;
    my $changeset=new Change::Set({stage=>$stage});
    my @checkFiles=();
    my @checkFilesRef=();
    my @stageDir=();
    verbose "Validating Changeset";
    foreach my $file ($candidateset->getFiles)
    {
	my $ptarget=$file->getProductionTarget();
	my $stagelocn=getLocationOfStage($stage).$FS.$ptarget;
	my $leafname=$file->getLeafName();
	my $stagefile=$stagelocn.$FS.$leafname;
	
	verbose2 "Check if $leafname is functbl.inp";
	#2 check if the target is not /bbsrc/functbl
	if($leafname =~ "functbl.inp" && $ptarget =~ "functbl") {
	    warning "WARNING: You may not uncheckout functbl.inp directly. Use 'functbl_tool' instead.  See BP.";
	    next;
	}
	#print "stagefile: $stagefile";
	#1 check if the file exists
	if (-f $stagefile.",v") {
	    $stagefile=$stagefile.",v";
	} elsif (-f $stagelocn.$FS.'RCS'.$FS.$leafname.',v') {
	    $stagefile=$stagelocn.$FS.'RCS'.$FS.$leafname.',v';
	} elsif (-f $stagefile) {
	    # A file not under RCS control:   it is in checkout hence I put it here.
	    warning "WARNING: '$leafname' cannot be unchecked out. Not under RCS control.";
	    next;
	} else {
	    warning "WARNING: '$leafname' does not exist in '$ptarget'. File skipped!";
	    verbose "$stagefile,v is not found.";
	    next;
	}
	debug3 "Found $stagefile";
	
	#4 check if this is restricted file
	if (isRestrictedFile($file)) {
	    #my $srcfile=$file->getSource();
	    warning "WARNING: $leafname is restricted file. You cannot uncheckout.";
	    next;
	}
	
	my $locker=getFileLock($stagefile);
	#5 check if file is checked out
	if (!defined $locker) {
	    warning "WARNING: $leafname is not checked out. File skipped!";
	    next; 
	}
	
	if($locker ne USER && !defined $forceunlock) {
	    warning "WARNING: $leafname is checked out by $locker.";
	    warning "Please use -F option to force the uncheckout.";
	    next;
	}
	
	if($locker ne USER && defined $forceunlock) {
	    #check if this file is staged.
	    my @fileref = ($leafname, $file->getProductionTarget());
	    push @checkFilesRef, \@fileref;
	    push @checkFiles, $file;
	    push @stageDir, $stagefile;
	    next;
	}
	
	# all checks made, file good to checkout.
	my $dest = ".";

	# remove ,v from the end.
	$stagefile =~ s/,v//;
	$changeset->addFile($file->getProductionTarget(), $stagefile, 
			    $file->getProductionTarget()."/".$leafname, undef,
			    $file->getLibrary(), $file->getProductionLibrary());
    }
    
    # check what files are staged, send all filenames together for this check 
    my $allStagedFiles = filesStagedSCM(@checkFilesRef) if defined $forceunlock;
    my $index = 0;
    foreach my $file (@checkFiles) {
	# check if this file is present in 
	my $found = 0;
	my $leafname = $file->getLeafName();
	foreach my $fileref (@$allStagedFiles) {
	    if($leafname eq @{$fileref}[0]) {
		$found = 1;
		warning "WARNING: $leafname is staged. File will not be unchecked out!";
		last;
	    }
	}
	$stageDir[$index] =~ s/,v//;
	# if it is not staged then add it to be unchecked out
	$changeset->addFile($file->getProductionTarget(), $stageDir[$index], 
			    $file->getProductionTarget()."/".$leafname, undef,
			    $file->getLibrary(), $file->getProductionLibrary()) 
	    if $found==0;
	$index++;
	
    }

    return $changeset;
}

#------------------------------------------------------------------------------

MAIN: {
    my $exit_code = EXIT_FAILURE;
    
    my $opts=getoptions();

# checks for the GROUP value- this is ENV variable,
    if (my $reason=isInvalidContext) {
	fatal $reason;
    }

# why it is needed?
    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    
# how this plugin works or helps?
    my $manager=getPluginManager();
    $manager->plugin_initialize($opts);

    # (make sure umask is consistent on files and directories created)
    umask(0002);
     # stage - set to default 'regular' stage
    $opts->{stage}=STAGE_INTEGRATION;
    #----- GATHER CHANGE SET FILES

    my ($candidateset,$changeset);
    if ($opts->{from}) {
	verbose "reading from input file";
	# regenerate change set from previously written file
	$candidateset=load Change::Set($opts->{from});
	# if loading from a file, we will unconditionally accept an unchanged
	# file if it was listed there.
	$opts->{unchanged}=1;
	# prep the identity cache with the previously identified targets
	Change::Identity::deriveTargetfromName($_,$opts->{stage})
	    foreach $candidateset->getTargets();
	message "read change set information from $opts->{from}";
    } elsif ($opts->{csid}) {
	my $csid=$opts->{csid};
        my $svc=new Production::Services;
        $candidateset = Production::Services::ChangeSet::getChangeSetDbRecord($svc, uc $csid);
	error("No such change set $csid"),goto FINALIZE
	    unless $candidateset;
	# if loading from a CS, we will unconditionally accept an unchanged
	# file if it was previously in the CS
	$opts->{unchanged}=1;
	$opts->{yes}=1; #if we said 'y' last time we mean it this time too
	# prep the identity cache with the previously identified targets
	Change::Identity::deriveTargetfromName($_,$opts->{stage})
	    foreach $candidateset->getTargets();
	message "retrieved change set information from $csid";
	$opts->{csid}=$csid;
    } else {
	usage("nothing to do!"), goto FINALIZE
	  if (@{$opts->{files}}<1);
	# create a  change set from all candidate files
	$candidateset=parseCheckoutArgumentsRaw($root,$opts->{stage},
						$opts->{honordeps},$opts->{to},
						1, 0, @{$opts->{files}});
	$opts->{to} ||= getParsedTrailingLibraryArgument();
    }

    $manager->plugin_pre_find_filter($candidateset);
   
    # revalidate all components of the CS 
    identifyCheckoutArguments($root,$opts->{stage},
		      $opts->{honordeps},$opts->{to},$candidateset);
    
    for my $file ($candidateset->getFiles) {
	my $srcfile = $file->getLeafName();
	if(-f CHECKIN_ROOT."/".$srcfile) {
	    warning("File '$srcfile' is staged for deferred checkin by robocop. Skipped..");
	    $candidateset->removeFile($file);
	}
    }

    my $forceunlock=undef;
    if ($opts->{forceunlock}) {
	$forceunlock = 1;
    }

    # Exit if a unit of release is 'blocked' by Group 412
    if (my %locks=checkMaintenanceLocks($candidateset)) {
	error "Maintenance locks are in effect for:";
	error "  ".join(",",sort keys %locks);
	foreach my $uor (sort keys %locks) {
	    error "$uor: $_" foreach split /\n/,$locks{$uor};
	}
	error "Please try later";
	goto FINALIZE;
    }

    $changeset = validate_changeset($candidateset, $opts->{stage},
				    $forceunlock);
   
    if (Util::Message::get_debug >=2) {
	my $text=$changeset->listFiles();
	chomp $text;
	debug2 "change set:$text",$changeset->listFiles(1);
    }

    # by now we know files are ready to be checkedout.
    if ($opts->{list}) {
	$exit_code = EXIT_SUCCESS;
	my $text=$changeset->listFiles();
	print "\n--- List of files to be checked out ---: \n";
	print "$text \n";
    } 
    else {	
        Util::File::NFSLock::safe_nfs_signal_traps(); #graceful under SIGINT
	  ($SIG{INT},$SIG{TERM},$SIG{ALRM})=('IGNORE','IGNORE','IGNORE');  
	  for my $file ($changeset->getFiles) {
	      removeFileLock ($file->getSource.",v", $forceunlock);
	  }
	  $exit_code = EXIT_SUCCESS;
	  goto FINALIZE;
      }
   
  FINALIZE:
    $manager->plugin_finalize($opts,$exit_code);

    exit $exit_code;
}


#==============================================================================

=head1 AUTHOR

Nitin Khosla(nkhosla1@bloomberg.net)

=head1 SEE ALSO

L<cscheckin>, L<csrollback>, L<csquery>, L<csfind>, L<csrecover>, L<cshistory>

=cut
