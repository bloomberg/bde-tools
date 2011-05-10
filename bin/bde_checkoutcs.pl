#!/bbs/opt/bin/perl -w
use strict;

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
    $ENV{PATH}="/usr/bin:${FindBin::RealBin}:/usr/local/bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}

use lib "$FindBin::RealBin/../lib/perl";
use lib "$FindBin::RealBin/../lib/perl/site-perl";

use Getopt::Long;
use Term::Interact;

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE
    DEFAULT_FILESYSTEM_ROOT );
use Change::Symbols qw(
    STAGE_PRODUCTION STAGE_BETA STAGE_INTEGRATION 
    USER GROUP HOME CHANGERCFILES CSCHECKOUT_TOOL 
    MOVE_REGULAR MOVE_BUGFIX MOVE_EMERGENCY FILE_IS_NEW ADD_RCSID);

use Change::Arguments qw(getParsedTrailingLibraryArgument
			 parseCheckoutArgumentsRaw identifyCheckoutArguments);

use Change::Identity qw(deriveTargetfromName getLocationOfStage);

use Change::Util::Interface qw/getCanonicalPath/;
use Change::Util::InterfaceRCS qw(checkOutFile getWorkingFileVersion);
use Change::Util::InterfaceSCM qw(copyoutLatestFilesSCM copyoutFilesByCsidSCM 
				  copyoutFilesByBranchSCM getFileHistorySCM);
use Change::Util::SourceChecks qw(checkChangeSet checkInc2HdrGenerated);
use Change::Configure qw(readConfiguration);

use Util::Message qw(
    message verbose verbose2 alert verbose_alert
    warning error fatal debug debug2 debug3 open_log
);
use Util::File::Functions qw(ensure_path);

use Util::File::Basename qw(dirname basename);
use Util::Retry qw(retry_output3);

use BDE::Build::Invocation qw($FS $FSRE);
use BDE::FileSystem;

use Change::DB;
use Change::AccessControl qw(isInvalidContext isRestrictedFile getFileLock
			     setFileLock checkMaintenanceLocks);
use Change::Approve qw(checkApproval);
use Change::Plugin::Manager;

use File::Path;
use File::Spec;

use File::Temp qw(tempdir);
use Production::Services;
use Production::Services::ChangeSet qw();
use Production::Symbols         qw(SCM_MULTICHECKIN_ENABLED);

#==============================================================================

=head1 NAME

cscheckout - check-out files by wildcard, changeset or filename

=head1 SYNOPSIS

Check out (retrieve and acquire lock for) 'latest' version of a single file:

  # fetches most recently checked-in file (regular, bug fix or EMOV branch)
  $ cscheckout bloom-chgsdisp1.gob f_xxmycs
  # (same as above, preferred syntax)
  $ cscheckout f_xxmycs/bloom-chgsdisp1.gob

Check out latest version of a file(from emov branch):

  # ignores versions of this file staged for regular or bug fix
  $ cscheckout f_xxmycs/bloom-chgsdisp1.gob --emov

Check out most recently swept version of a file (ignore staged copies):

  # from emergency move branch only
  $cscheckout <filename> library --swept --emov
  # from regular move branch
  $cscheckout <filename> library --swept --move
  # (same as above, regular move is the default for --swept)
  $cscheckout <filename> library --swept

Check out multiple files with wildcards:

  # All files starting with 'ar' in acclib
  $ cscheckout ar* acclib
  # (or using --to option)
  $ cscheckout --to acclib ar*
  Found 4 files. Want to continue (y/n)?

Check out files from multiple libraries:

  # specific files
  $ cscheckout acclib/foo.c mtgeutil/test.c
  # using wildcards
  $ cscheckout gtk/f_xxprqs/*.c gtk/f_xxmycs/*.c


Copy out files (no check-out):

  $ cscheckout -n ar* acclib

List files only (do not retrieve or acquire locks for files):

  $ cscheckout -l ar* acclib
  Found 4 file(s) for 'ar*'. Want to continue (y/n)? y
  --- List of files to be checked out ---: 
  ...

Generate candidate change set, edit it, check out out from candidate set

  $ cscheckin -lM * acclib > changes.cs #NB cscheckin, not cscheckout
  $ vi changes.cs
  # (remove unwanted files from calculated changeset)
  $ cscheckout --from changes.cs

Check out files in a previous change set(revisions of file 
in that csid)

  $ cscheckout --csid <csid>

Check out historical files from a previous change set and check them in

  $ cscheckout --csid <csid>
  $ csrecover <csid>
  $ cscheckin --reinstate <csid>

'Roll back' a change set, with modifications:

  $ cscheckin -lM --csid <csid> > changes.cs
  # edit change.cs (if necessary)
  $ cscheckout --from changes.cs    # lock files, retrieve current versions
  $ csrecover --previous <csid>     # replace with historical versions
  # edit historical files (if necessary)
  $ cscheckin --from changes.cs     # check in historical files as new

=head1 DESCRIPTION

This tool allows developers to check-out (retrieve and lock) files from one or
more libraries. File wildcards can be used to scan all candidate files. When a
checkout command is completed, a directory structure suitable for C<cscheckin>
is created in the current directory. For example:

  $ cscheckout f_xxprqs/prqs*
  Found 62 files for 'f_xxprqs/prqs*'. Want to continue (y/n)?

This will create a C<f_xxprqs> directory in the current directory and will put
the latest version of all selected files under it. If the file is in
staged area, it will get the staged version.

=head2 File version

By default, the latest version of the files will be checkout. If the speficied
files exist in stage area with the given branch type, it will get the files from
stage area. If no branch provided, the latest version of the files from
stage area for all branch type will be retrieved.

If files are not found in staged area, the files will be checked out from
repository with specified branch. If branch provided, it will
check out the file from the most recenttly checked-in change set (staged or
swept).

    # specific branch, staged or swept
    $ cscheckout bloom-chgsdisp1.gob f_xxmycs --bugf
    # most recent file, any branch
    $ cscheckout bloom-chgsdisp1.gob f_xxmycs

Checkout the swpet version of the file, if specify C<--swept> together
with C<--move>, C<--bugf> or C<--emov>, it will only checkout swept files 
from that branch. If no branch provided, it will get the swept version
of the regular move branch.

    # specific branch, swept only (not staged)
    $ cscheckout --swept bloom-chgsdisp1.gob f_xxmycs --bugf
    # most recent file, regular (move) branch
    $ cscheckout --swept bloom-chgsdisp1.gob f_xxmycs

If the C<--move>, C<--bugf> or C<--emov> option is specified, file are fetched
from that branch.


=head2 Using Wildcards:

Files may be specified explicitly, using wildcards, from a streamed changeset
(using the C<--from> option), or read from standard input with the C<--input>
option.

Files may be specified with wildcards, in which case the filenames are
expanded using standard Unix shell wildcard expansion. The behaviour of
wildcards varies depending on whether local files match the wildcard or not:

=over 4

=item * If the wildcard matches files locally, it is expanded locally and
        that list of files is retrieved from source control.

=item * If the wildcards matches I<no local files> then it is submitted as
        a wildcard expression and matches files <in the repository>.

=back

To guarantee expansion in the repository, therefore, check out into an empty
location. Repeated check-outs will extract only the files that are locally
present (as the wildcard expands locally and not at the repository).

I<Note: Only swept files are matched. New unswept files are not considered>.

=head2 Reading Files from Standard Input:

To provide file-list specification that would exceed the length limit of a
command line, use the C<--input> or C<-i> option. This will read a list of
files from the specified file, or standard input if no file is specified, and
is an alternative to C<--from> or C<-f> that has no length limitations.

   $ find . -name *.h -o -name *.c > file.list
   $ cscheckout -i file.list

Or without the intervening file, reading from standard input:

   $ find . -name *.h -o -name *.c | cscheckout -i

=head1 NOTES

=head2 Limitations of the Trailing Library Argument

If the C<--to> or C<-t> option is not specified, and the last file argument
is not an identifiable local file, and exists as a directory path under
C</bbsrc>, then the last file argument is assumed to be an implicit
destination argument and removed from the list of candidate files. This mode
however, like the C<--to> option, will not permit the tool to extract files 
from multiple libraries. To do that, use appropriate container directory
names.

=head2 Plugins

C<cscheckout> provides support for external plugins to augment or alter its
behaviour for application-specific purposes. This allows the tool to be
adapted to carry out additional processing and/or alter the list of files
considered according to additional logic supplied by the plugin.

Plugins are loaded with the C<--plugin> or C<-L> option. For example, to
load the example plugin, which simply prints out messages when it is
accessed:

    cscheckout -LExample ...

Usage information, including command line extensions, can be extracted using
the usual C<--help> or C<-h> option:

    cscheckout -LExample -LFileMap -LAnotherPlugin -h

Currently supported plugins include:

=over 4

=item * FileMap - Allows local files to be mapped to different destination
        libraries and/or application directories using a map file. An
        alternative way to specify multiple destinations.

=back

Plugins may be supported by any development group, and may be contributed as
part of cscheckout as 3rd-party extensions to the tool. All such plugins must
first be vetted by the maintainers of cscheckout prior to installation, but
if accepted become part of the standard cscheckout toolset.

Contributed plugins are actively encouraged - see the PWHO contacts for
cscheckout for more information, and L<Change::Plugin::Base> and
L<Change::Plugin::Example> for more information on how to create plugins.

=head2 Per-User Configuration Files

C<cscheckout> supports per-user configuration files which can be used to
supply automatic options to cscheckout without specifying them on the command
line. See L<cscheckin> for more information.

=head1 EXIT STATUS

The exit status is zero for success or non-zero on failure.

=cut
#============================================================================
my $tmpdir_prefix = "/bb/data/tmp/";
my $has_tty = -t STDIN or -t STDOUT;

# No parameter means the default logfile
open_log();

#==============================================================================
sub usage_copyout
{
    print "\n";
    print qq|Usage:  copyout  [options] file  [library]
##PLEASE NOTE: To retrieve a particular revision, please USE "rcscopyout -r "
THIS VERSION USES CSCHECKOUT UNDERNEATH.

copyout copies a source file (or files) into the current directory.

file     - Your version of a file to check in.
library  - The path to find the RCS file for checkout.

If library does not begin with a slash it is assumed to be a
subdirectory of /bbsrc, otherwise directory is taken as an
absolute pathname.  [Use '.' for the current directory.]

The library is optional when scant can find one RCS file in /bbsrc
Any library value not starting with /, ~ or . will be relative to /bbsrc.

If you supply the -l option, all items on the command line are treated as
filenames that are to be checked out from the same directory.

copyout supports the following option:
   --head    (default) Get the latest version from RCS directory.
   --stage   Get the file from the unreleased/stage area if it is there.
             [ THIS IS NOT SUPPORTED in this version. PLEASE 
	      USE "rcscopyout --stage" ]

   --latest  Find the most recent version available (either --head or --stage).
   --zLT     Use zone local time. The opton -zLT will be pass along to RCS co command.
             [ THIS IS NOT SUPPORTED. PLEASE USE "rcscopyout -zLT" ]

   -d        Enable debugging.
   -f        Forcibly overwrite a writable, local file.
             [ THIS IS NOT SUPPORTED. PLEASE USE "rcscopyout -f" ]

   -n        (or --dryrun) Go through all the motions but leave no file behind.
             [ THIS IS NOT SUPPORTED. PLEASE USE "rcscopyout -n" ]

   -r <rev>  Specifies a particular revision level, either a number or tag.
             Revision number is of the form: major.minor.
             If the minor level is omitted the newest minor level for the
             requested major level is returned.
	     [ THIS IS NOT SUPPORTED. PLEASE USE "rcscopyout -r" ] 
|;
}


sub usage_checkout()
{
    
    print "\n";
    print qq|Usage:  checkout  [options] file  [library]
NOTE: THIS VERSION USES CSCHECKOUT UNDERNEATH.

file     - Your version of a file to check in.
library  - The path to find the RCS file for checkout.

The library is optional when scant can find one RCS file in /bbsrc.
Any library value not starting with /, ~ or . will be relative to /bbsrc.

If you supply the -l option, all items on the command line are treated as
filenames that are to be checked out from the same directory.

Options are:
   -d               - Enable debugging.
   -f               - Force checkout to succeed if you (and only you)
                      already have the file checked out.
                      [THIS WILL NOT WORK. PLEASE USE "cscheckout --transferlock" ]
   -h               - Prints this message.
   -v               - Verbose mode.

checkout gets the latest revision from an RCS archive and also sets a lock
so that the user has an exclusive chance to checkin a new revision.

To undo a checkout, use "uncheckout".  To undo someone elses checkout, 
use "uncheckout -f".
|;

}


{
    my $isCurDir = 0; 
    sub setCurDir($) { $isCurDir = shift;}
    sub isCurDir()  { return $isCurDir; }
}


sub usage(@) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;
    if($prog eq "checkout") {
	usage_checkout();
	exit 1;
    }
    elsif($prog eq "copyout") {
	usage_copyout();
	exit 1;
    }
    else {
	$prog = "cscheckout";
    }

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-w <dir>] [[-c]| [-p]] [-v] [-d] [-t=<unit>] [--latest] [-m] <files>
  --debug        | -d            enable debug reporting
  --help         | -h            usage information (this text)
  --ignoreconfig                 ignore per-user configuration file, if present 
  --to           | -t <uor>      specify destination unit of release
                                 (only with unqualified file arguments)
  --where        | -w <dir>      specify explicit alternate local root
  --noretry      | -X            disable retry semantics on file operations
  --verbose      | -v            enable verbose reporting
  --curdir       | -c            copyout or checkout the file in current directory 
                                 and do not create directory structure.

Copyout/checkout option:
  --swept                        Get latest swept files(CSID in 'C' state)
  --bugf         | -b            move type is bugf
  --emov         | -e            move type is emov
  --beta         | -B            emov is beta emov
  --move         | -m            move type is regular move
  --nolock       | -n            just copyout the latest file and do not lock.
                                 THIS HAS RESTRICTED FUNCTIONALITY AS YET.
  --lockonly                     Just take the lock but not copyout/checkout the file
  --yestoall                     yes to question to copyout all files found by using
                                 using wildcard.  
                          
File input options:

  --from         | -f            read change set from file (e.g. previously
                                 generated with --list and --machine). Implies
                                 --unchanged.
  --input        | -i [<file>]   read additional list of explicit filenames
                                 from standard input or a file (if specified)
  --csid         | -C <csid>     checkout files from a previous change set id
                                 NOTE: PARTICULAR REVISIONS OF FILES CORRESPONDING
                                 TO THAT CSID WOULD BE RETRIEVED. FILES MAY "not"
                                 be LATEST.  
  --transferlock | -R            transfer lock from another user to allow 
                                 multiple checkin. ONLY TO BE USED FROM CSCHECKOUT.

Display options:

  --list         | -l            list all files to be checked-out

Extended functionality options:

  --plugin       | -L <plugin>   load the specified extension
  --do           | -D <check>    specify a specific check stage to perform
                                 (source|all|none). By default: source check is performed.

For Uncheckout:
   Use "csuncheckout" tool to uncheckout the files.

_USAGE_END
    my $plugin_usage=getPluginManager()->plugin_usage();
    print $plugin_usage,"\n" if $plugin_usage;

    print "See 'perldoc $prog' for more information.\n";
}

# --swept                          checkout the swept version of the file

#------------------------------------------------------------------------------

{  my $manager = new Change::Plugin::Manager(CSCHECKOUT_TOOL);
   sub getPluginManager { return $manager; }
}

sub getoptions {
    my @options=qw[
	debug|d+
        from|f=s
        nolock|n 		   
	curdir|c            
	help|h
        list|l
	do|D=s
        machine|M
        pretty|P
        csid|C
	transferlock|R
        stage|s=s
        to|t=s
	where|root|w=s
        verbose|v+
 	latest
	swept
	move|m
        bugf|b
	emov|e
	beta|B
	yestoall
	lockonly	
	head
	noaddrcsid	   
	rev|r=s	   
       ];
    # TODO: 
    # swept

    my %opts;
    # this allows support for single, double - options
    Getopt::Long::Configure("bundling");

    # BEGIN pass through sections
    # 
    Getopt::Long::Configure("pass_through");

    # rc files
    # what configuration might be useful in cscheckout???
    GetOptions(\%opts,"ignoreconfig","config=s@");
    unless ($opts{ignoreconfig}) {
	readConfiguration @ARGV,"cscheckout",(map {
	    HOME.'/'.$_
	} split / /,($opts{config} ? (join ' ',${$opts{config}})
					: CHANGERCFILES));
    }

    # plugins and files-from-input (or rc files)
    $opts{plugin}=undef;
    my $prog = basename $0;
    if($prog eq "checkout") {
	$opts{curdir} = 1;
	push @{$opts{plugin}}, "GuessLib";
	$opts{do} = "none";
    }
    elsif($prog eq "copyout") {
	$opts{curdir} = 1;
	push @{$opts{plugin}}, "GuessLib";
	$opts{do} = "none";
	$opts{nolock} = 1;
	$opts{swept} = 1 unless $opts{latest};
    }

    if($opts{beta} && !$opts{emov}) {
	warning "--beta/-B option has no effect unless with --emov/-e";
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
    
    # this will help in case of copyout
    fatal "Please use rcscopyout -r to retreive a revision" if $opts{rev};

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
   
    my $move_count += 0;
    foreach ($opts{move}, $opts{emov}, $opts{bugf}) {
	if($_) {
	    $move_count++;
	}
    }
    unless ($move_count < 2) {
	fatal "too many branches";
    }

    # by default, source checks, 
    # all = source + binary
    if ($opts{do}) {
        usage("invalid \'do\' option"), exit EXIT_FAILURE unless
          $opts{do} eq "source" or
	  $opts{do} eq "all" or
	  $opts{do} eq "none";
        alert("$opts{do} checks selected") if $opts{do} ne "source";
    } else {
        $opts{do} = "source";
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

#------------------------------------------------------------------------------

sub checkout_changeset_RCS($$$$;$$) {

# check
# what to do if file is checkout by somebody and person uses -f option

  # FUNCTION: checkout the changeset
    # -> create the directory structure 
    # For each file  
    #     -> create the files.
    #        -> if there is existing file in current directory with write mode.
    #        -> ask the question to overwrite.

    
    my ($changeset, $lock, $curdir, $fromdir, $getRCS, $rcsid)=@_;
    my ($filename, $target, $fpath, $cmd, $srcfile, $missingCount, $count, $rc, $msg);
    my $currentDir=File::Spec->rel2abs(".");
    my $move_location=".";
    my @msgs=();
    my $svc=new Production::Services;
    verbose "perform Copyout/Checkout of Changeset";

    if (defined $curdir && ! -w $currentDir) {
	fatal "No write permission for working directory.";
    }

    $count = 0;
    $msg = "checked";
    my @targets = $changeset->getTargets();
    # smart directory checking.
    my %uniqhash = map { $_, 1 } @targets;
    my @uniqtargets = keys %uniqhash;
    
    # create a metadata hash for each file.
    my %metahash=();
    if(defined $fromdir && $rcsid) {
	my $fh=new IO::File;
	my $metafile = $fromdir."/meta";
	verbose "metafile: $metafile";
	$fh->open($metafile) or die "Error opening file";
	my @lines = <$fh>;
	$fh->close();
	# metadata has 'filename' as keys and  "values = CSID and svn info"
	foreach my $line (@lines) {
            # the below split is compatible with both a space-separated two element
            # list as returned by the old SCM::Server as well as the more recent ones
            # that return a comma-separated six element list
	    chomp($line);
	    my @tmp = split /[,]/, $line, 6;
	    $metahash{basename($tmp[0])} = \@tmp;
	}
    }
    
    for $target (@targets) {
	$move_location = $target;
	# create these directory if not present
	unless (defined $curdir || (scalar(@uniqtargets) == 1 && 
		basename($currentDir) eq basename($target))) {
	    print "Created $target directory; Made it Writable. \n";
	    eval {mkpath($move_location,0,02775) };
	    fatal("could not mkpath: $@") if $@;
	    if (! -w $move_location) {
		fatal "No write permission for working directory.";
	    }
	}
	for my $file ($changeset->getFilesInTarget($target)) {
	    $filename=$file->getLeafName();
	    #print "\n88888888888888 filename: $filename";
	    #print ",,,value:".$metahash{$filename};
	    $srcfile = $file->getSource();
	    debug3 "Target: $target, source: $srcfile, filename: $filename ";	   
	    if(defined $curdir || (scalar(@uniqtargets) == 1 && 
		basename($currentDir) eq basename($target))) {
		setCurDir(1);
		$fpath = $filename;
		$move_location = ".";
	    }
	    else {
		$fpath = $move_location."/".$filename;
		if(-f $filename) {
		    fatal "ERROR: $filename exists in current dir.";
		}
	    }
	    
	    debug "check if file already exists: $fpath";
	    if(-f $fpath) {
		if(-w $fpath) {
		    error "ERROR: A writable copy of '$fpath' exists.";
		    $missingCount++;
		    next;
		}
		debug "removing preexisting file: $fpath";
		if(!unlink $fpath){
		    error "ERROR: Could not remove '$fpath'";
		    $missingCount++;
		    next;
		}	    
	    }
	    
	    my $tmpdir = tempdir(DIR=> $tmpdir_prefix, CLEANUP =>1);
	    my $res_file;
	    if (defined $fromdir) {
		$res_file =  $fromdir .'/'.$filename;
		debug3 "Copying file from $res_file";
		debug3 "Could not checkout $filename from SCM " if (!-f $res_file);	
	    }

	    # fromdir is SCM tmp dir that contains these scm files
	    # only do all this if noaddrcsid is NOT there.
	    # TODO: SPECIFY MOVE type
	    if (defined $fromdir && $rcsid) {
		# get the file history so that we can get CSID for a
		# a swept file(completed CSID) and not 'A' state one.
		my ($logref, $err) = getFileHistorySCM($filename, $target, 1);
		#print "\n file: $filename, target: $target\n";
		fatal $err if $err;
		my $scm = ".";  # just to have some value
		my $csid = "."; # so add_rcsid does not fail
		                
		if(@$logref) {
		    my ($scmid, $date, $author, $log) = @{$logref->[0]};
		    $scm="\"$scmid $date $author\"";
		}
		
		# get move type from META file and check if the movetype
		# is regular which is passed in getFileHistory
		# Example: prqsobj_default.c is only checked in as 
		# mbf or emov.
		# TODO: Some problem here.
		my ($lroot,$author,$movetype,$status,$timestamp);
		if(exists $metahash{$filename}) {
		    my $ref =  $metahash{$filename};
		    ($lroot,$csid,$author,$movetype,$status,$timestamp)= @{$ref};
		    #print "\n$filename, $csid, $author, $movetype, $status, $timestamp";
		}
		
		my $cmd = ADD_RCSID." --csid $csid --scmid $scm $res_file";
		
		my $out = "";
		$out = system($cmd) if $rcsid && $res_file !~ /\.ml$/; 
		debug "add_rcsid output: $out" if $out =~ "ERROR:";

		if($rcsid && exists $metahash{$filename}) {
		    # it is a possible that SCM retrieves a file which does not have CSID
		    # this file was never checked in so $changeset can be uindefined
		    my $msg = "$csid  $status \t $movetype   $timestamp".
			"  $filename\n";
		    push @msgs, $msg if $msg;
		}
	    }
	    # if you want lock then rcs call has to be made.
	    if($lock && !$file->isNew) {
		verbose "Set RCS lock on $srcfile";		
		$srcfile.=",v";
		
		if($fromdir && -f $res_file) {		 
		    $rc = checkOutFile($srcfile, $tmpdir.'/'.$filename);
		    debug3 "RCS file tmpdir $tmpdir";
		    fatal "Could not checkout $filename from RCS." if (!$rc);
		    system("cp $res_file $currentDir/$move_location");
		    fatal "Could not copyout $filename to $move_location." if($?);
		} elsif($getRCS){
		    $rc = checkOutFile($srcfile, $fpath);
		    fatal "Could not checkout $filename. Target: $move_location" if (!$rc || !-f $fpath);
		}
		#chown USER $tmpdir."./".$srcfile;

	    } else {
		#append ,v to files for copyout
		$srcfile.=",v";

		verbose "Performing copyout of $srcfile";
		
		# > $text, verbose $text
		if($fromdir && -f $res_file) {
		    debug3 "Could not copyout $filename. Target: $move_location" if ($?);
		    system ("cp $res_file $currentDir/$move_location");
		    require File::Temp;
		    my $r_file = File::Spec->catfile($currentDir, $move_location, $filename);

		    # for new files we have to check if there is lock.
		    chmod 0444, $r_file unless $lock;		   
		    fatal "Could not copyout $filename from $fromdir. " if($?);
		} elsif($getRCS) {
		    $cmd = "cd $currentDir/$move_location; /usr/local/bin/co  -M -T $srcfile > /dev/null 2>&1";
		    system $cmd;
		    fatal "Could not copyout $filename. Target: $move_location" if ($? || !-f $fpath);	
		    
		}
		
			
		$msg = "copied";
		$count++;
	    }
	   
	}
    }
    unless (defined $fromdir) {
	#message "$count file(s) $msg out.";
    }
    if($rcsid) {
	print "\nChecked-out/Copyout Files info: \n";
	print "-------------------------------";
	print "\nCSID   \t\t   STATUS MOVETYPE   TIMESTAMP\t\t  FILENAME\n";	
	print @msgs;
	print "\n";
    }
    error "ERROR: $missingCount file(s) could not be $msg out." if $missingCount;
 
}


# checkout_changeset_SCM retrieves files from SCM
# based on provided criteria
sub copyout_changeset_SCM($$$$$$) {

    my ($changeset, $lock, $curdir, $move, $type, $beta) = @_;
    my ($count, $msg, $missingCount);
    my $currentDir=File::Spec->rel2abs(".");
    verbose "perform Copyout/Checkout of Changeset from SCM";

    if (defined $curdir && ! -w $currentDir) {
	fatal "No write permission for working directory.";
    }
   
    my @lroots;
    for my $fobject ($changeset->getFiles) {
    
	my $lroot = getCanonicalPath($fobject);
	push(@lroots, $lroot);
    }

    unless(@lroots) {
	fatal "No valid files for checkout";
    }

    my $tmpdir = tempdir(DIR=> $tmpdir_prefix,CLEANUP =>1);
    my $targetfile = "$tmpdir/copyout.tar";
    debug3 "target file is $tmpdir/copyout.tar";
    system("touch $targetfile");

    if($type eq "latest") {
	my($status, $response)=copyoutLatestFilesSCM($targetfile, $move,
						     $beta, undef, @lroots);
    } elsif($type eq "repository") {
	my $swept = "swept";
	my($status, $response)=copyoutLatestFilesSCM($targetfile, $move,
						     $beta, $swept, @lroots);
    }
    elsif($type eq "csid") {
	my $csid = $beta;
	my ($status, $response)=copyoutFilesByCsidSCM($targetfile, $csid, 
						      $move, @lroots);
    }
    # Not sure if we should display this or not
    #if (!$status) {
    #	warning $response;
    #}  

    if (-z $targetfile) {
	verbose "perform Copyout/Checkout of Changeset from RCS";
	return undef;
    }
   
    unless (system ( "cd $tmpdir && tar xmf $targetfile") == 0) {
	warning "Failed to retrieve data from the tarball: $!";
	verbose "perform Copyout/Checkout of Changeset from RCS";
	return undef;
    }
    
    return $tmpdir;    
}

sub safe_system (@) {
    my $FH = Symbol::gensym;
    open($FH,'|-',@_) && close($FH);
    return $?;
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

sub validate_changeset($$$$)
{
    my ($candidateset, $stage, $nolock, $transferlock) = @_;
    my $changeset=new Change::Set({stage=>$stage});

    verbose "Validating Changeset";
    foreach my $file ($candidateset->getFiles)
    {
	my $ptarget=$file->getProductionTarget();
	my $stagelocn=getLocationOfStage($stage).$FS.$ptarget;
	my $leafname=$file->getLeafName();
	my $stagefile=$stagelocn.$FS.$leafname;
	my $isnew = 0;

	verbose2 "Check if $leafname is functbl.inp";
	#2 check if the target is not /bbsrc/functbl
	if($leafname =~ "functbl.inp" && $ptarget =~ "functbl") {
	    warning "WARNING: You may not checkout functbl.inp directly. Use 'functbl_tool' instead.  See BP.";
	    next;
	}
	
	#1 check if the file exists
	if (-f $stagefile.",v") {
	    $stagefile=$stagefile.",v";
	    debug3 "Found $stagefile";
	} elsif (-f $stagelocn.$FS.'RCS'.$FS.$leafname.',v') {
	    $stagefile=$stagelocn.$FS.'RCS'.$FS.$leafname.',v';
	    debug3 "Found $stagefile";
	}  elsif (! -f $stagefile.",v") {
	    # A file not under RCS control:   it is in checkout hence I put it here.
	    warning "WARNING: '$leafname' is not under RCS control(may be a new file).";
	    $isnew = 1 if (!defined $nolock);
	}
	elsif (!defined $nolock) {
	    warning "WARNING: '$leafname' is a new file.";
	    $isnew = 1;
	}
	

	# You can only checkout existing file now from here
	#3 it's a header derived from .inc, dont checkout that header
	if($leafname =~ /\.h$/ && $ptarget =~ /Cinclude$/) {
	    my $tmp = $file;
	    $tmp->setSource($stagelocn.$FS.$leafname);
	    # destination field should be set for basename to work.
	    # basename used in checkInc2HdrGenerated
	    $tmp->setDestination($stagelocn.$FS.$leafname);
	    
	    if(checkInc2HdrGenerated($file)) {
		next;
	    }
	}
	#4 check if this is restricted file
	if (isRestrictedFile($file) && !defined $nolock) {
	    #my $srcfile=$file->getSource();
	    warning "WARNING: $leafname is restricted file. You cannot checkout.";
	    next;
	}
	
	my $locker;
	#5 check if file is checked out
	if (!defined $nolock && !$isnew && ($locker=getFileLock($stagefile))
	    && (!SCM_MULTICHECKIN_ENABLED || !defined $transferlock)) {
	    warning "WARNING: $leafname is already checked out by $locker. File skipped!";
	    next; 
	}
	# lock is defined and still here. means lock is stealed.
	if((defined $locker && SCM_MULTICHECKIN_ENABLED) && !defined $nolock) {
	    my $msg = "Lock on $leafname will be transferred from $locker to ".USER;
	    warning "WARNING: ".$msg;
	    #my $recipient=`PATH=/bb/bin; /bb/bin/unixinfo -e $locker`;
	    #my $sendmsg = `/bb/bin/bb_email.sh  $recipient $msg`;
	}
	
	# all checks made, file good to checkout.
	my $dest = ".";

	# remove ,v from the end.
	$stagefile =~ s/,v//;

	if($isnew) {
	    $changeset->addFile($file->getTarget(), $stagefile, 
			    $file->getTarget()."/".$leafname, FILE_IS_NEW,
			    $file->getLibrary(), $file->getProductionLibrary());
	} else {
	    $changeset->addFile($file->getTarget(), $stagefile, 
			    $file->getTarget()."/".$leafname, undef,
			    $file->getLibrary(), $file->getProductionLibrary());
	}
    }
       
    return $changeset;
}

#------------------------------------------------------------------------------

MAIN: {
    my $exit_code = EXIT_FAILURE;

    my $opts=getoptions();
    
    if ($has_tty) {
      verbose("Interactive: yes");
    } else {
      verbose("Interactive: no");
    }
    
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
    my $lock = 1;
    $lock = 0 if $opts->{nolock};
    my $yes = 0;
    $yes = 1 if $opts->{yestoall};
    my $move;
    if($opts->{bugf}) {
	$move = MOVE_BUGFIX;
    }elsif($opts->{emov}) {
	$move = MOVE_EMERGENCY;
    }elsif($opts->{move}) {
	$move = MOVE_REGULAR;
    }

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
        $candidateset = 
            Production::Services::ChangeSet::getChangeSetDbRecord($svc, uc $csid);
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
						$lock, $yes, @{$opts->{files}});
	$opts->{to} ||= getParsedTrailingLibraryArgument();
	# when user does not specify the directory then getParse...
	# should return undefined. This basically implies copyout in current
	# directory implicitly.
	#if(!defined $opts->{to}) {
	#    $opts->{curdir} = 1;
	#}
    }

    $manager->plugin_pre_find_filter($candidateset);
   
    # revalidate all components of the CS  
    identifyCheckoutArguments($root,$opts->{stage},
			      $opts->{honordeps},$opts->{to},$candidateset, $lock);    
    $manager->plugin_post_find_filter($candidateset);
    
    # Warn and do NOT lock file if a unit of release is 'blocked' by Group 41
    unless (defined $opts->{nolock}) {
	if (my %locks=checkMaintenanceLocks($candidateset)) {
	    warning "Maintenance locks are in effect for:";
	    warning "  ".join(",",sort keys %locks);
	    foreach my $uor (sort keys %locks) {
		error "$uor: $_" foreach split /\n/,$locks{$uor};
	    }

	    $opts->{nolock} = 1;
	    $lock = 0;
	}
    }

    $changeset = validate_changeset($candidateset, $opts->{stage}, 
				    $opts->{nolock}, $opts->{transferlock});
   
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
    elsif ($opts->{lockonly}) {
	my $steallock = 0;
	$steallock = 1 if (defined $opts->{transferlock});
	$exit_code = EXIT_SUCCESS;
	$opts->{do} = "none";
	for my $file ($changeset->getFiles) {
	    # do not get lock if file is new
	    setFileLock($file->getSource(), undef, $steallock, 1) if(!$file->isNew);
	    #print "\nFile: ".$file->getSource();
	}
    }
    else {
	($SIG{INT},$SIG{TERM},$SIG{ALRM},$SIG{TSTP})=('IGNORE','IGNORE','IGNORE','IGNORE');     
	my $lock = 1;
	$lock = 0 if $opts->{nolock};
#	my $staged = 0;
#	if ($opts->{transferlock} && $opts->{stagedcopy}) {
#	    $staged = 1;
#	}
	my $rcsid = 1;
	if($opts->{noaddrcsid} || $opts->{do} eq "none") {
	    $rcsid = 0;
	}	
	
	if($opts->{csid}) {
	    alert ("IMPORTANT NOTE: Revision of files corresponding to this csid will be retrieved.");
	    $move = $candidateset->getMoveType();
	    my $tmpdir = copyout_changeset_SCM($changeset, $lock, 
					       $opts->{curdir}, $move,
					       "csid", $opts->{csid});
	    checkout_changeset_RCS($changeset, $lock, $opts->{curdir}, $tmpdir, 1, $rcsid);	
	}
	elsif($opts->{swept}) { 
	    my $tmpdir = copyout_changeset_SCM($changeset, $lock,
					       $opts->{curdir}, $move, 
					       "repository", $opts->{beta});
	    checkout_changeset_RCS($changeset, $lock, $opts->{curdir}, $tmpdir, 0, $rcsid);
        } 
	else {
	    my $tmpdir = copyout_changeset_SCM($changeset, $lock, 
					       $opts->{curdir}, $move,
					       "latest",$opts->{beta});
	    checkout_changeset_RCS($changeset, $lock, $opts->{curdir}, $tmpdir, 1, $rcsid);	    	
	}

	$exit_code = EXIT_SUCCESS;
    }
    #----- GATHER REQUIRED INFORMATION
    
    
    # Warn the user to conform to existing checkin rules at checkout time itself
    # do source checks
    if ($opts->{do} =~/^(all|source)$/ && !($opts->{list}) && $opts->{do} ne "none"
	&& !defined $opts->{lockonly}) {
	my $fileset = new Change::Set($opts->{stage});
	# checkChangeset reads the files from 'source' field
	# in the file object. In cscheckout 'source' field is RCS file-path
	# hence here it actually should look in 'destination' or 'to'
	# field where the file would be after checkout
	for my $file ($changeset->getFiles) {
	    if($opts->{curdir} || isCurDir() == 1) {
		$file->setDestination($file->getLeafName);
	    }
	    $fileset->addFile($file->getTarget, $file->getDestination, 
			      $file->getSource, undef, $file->getLibrary(), 
			      $file->getProductionLibrary());
	    my $localfile=$file->getDestination;
	   	   
	    # check if the file is present
	    if($localfile !~ /\.ml$/ && -f $localfile) {
		my $localver=getWorkingFileVersion($file->getDestination);
		unless (defined $localver) {
		    warning("WARNING: ".$file->getLeafName()." missing RCS ID string - please use add_rcsid."); 
		}
	    }
	}
	
	 error "ERROR: source checks failed. Please do fix them before checkin."
	    unless checkChangeSet($fileset);
    }

  FINALIZE:
    $manager->plugin_finalize($opts,$exit_code);
    
    print "PLEASE NOTE: With no branch specified, the most recently submitted file over all \n".
	"       branches will be retrieved. The move type of retrieved files is noted above.\n";
    exit $exit_code;
}


#==============================================================================

=head1 AUTHOR

Nitin Khosla(nkhosla1@bloomberg.net)

=head1 SEE ALSO

L<cscheckin>, L<csrollback>, L<csquery>, L<csfind>, L<csrecover>, L<cshistory>

=cut
