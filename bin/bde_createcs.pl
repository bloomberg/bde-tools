#!/bbs/opt/bin/perl -w
use strict;

my $parent_pid;
 
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
    $parent_pid = $$;
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use File::Temp;
use File::Copy qw(copy);
use Term::Interact;
use Change::Util::InterfaceSCM qw(postChangeSetSCM enqueueChangeSetSCM
				  getOverlappedCsidsSCM);

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE
    DEFAULT_FILESYSTEM_ROOT FILESYSTEM_NO_DEFAULT FILESYSTEM_ROOT_ONLY
);
use Change::Symbols qw(
    STAGE_PRODUCTION STAGE_BETA STAGE_INTEGRATION DBPATH DBLOCKFILE
    CHECKIN_ROOT UNRELEASED_ROOT CSCHECKIN_STAGED CHECKIN_ROBOCOP ACCEPTLIST
    FILE_IS_CHANGED FILE_IS_NEW FILE_IS_UNKNOWN FILE_IS_UNCHANGED

    STATUS_SUBMITTED STATUS_ACTIVE STATUS_WAITING STATUS_ROLLEDBACK
    STATUS_FAILED STATUS_COMPLETE STATUS_WITHDRAWN STATUS_REINSTATED

    MOVE_REGULAR MOVE_BUGFIX MOVE_EMERGENCY MOVE_IMMEDIATE

    CSCOMPILE CSCOMPILE_TMP CS_DIFFREPORT_DIR CSROLLBACK $BADREASON_RE
    STAGE_PRODUCTION_ROOT STAGE_PRODUCTION_LOCN CHECKIN_CBLD
    USER GROUP HOME COMPCHECK_DIR
    DEBUG_ACTIVATION_DELAY
    APPROVELIST APPROVE_REJECT APPROVE_NONE

    CHANGERCFILES CSCHECKIN_TOOL

    DEPENDENCY_TYPE_CONTINGENT
    DEPENDENCY_TYPE_DEPENDENT
    DEPENDENCY_TYPE_NONE
    DEPENDENCY_TYPE_SIBLING
    DEPENDENCY_TYPE_ROLLBACK

    CSCHECKIN_NEWS CSCHECKIN_MOTD CSCHECKIN_LOCK

    $MAX_TASKS $MAX_FUNCS $MAX_FILES $MAX_TESTERS
);

use Change::Bulletin qw(displayBulletin);
use Change::Arguments qw(parseArgumentsRaw identifyArguments
			 getParsedTrailingLibraryArgument);
use Change::Identity qw(deriveTargetfromName getLocationOfStage);
use Change::Util::Interface qw(
    installScripts installScript
    isBugFixOnly setForBugFix isSweepLocked
    removeStagedFiles installFilesTo installFiles
    getCanonicalPath
);
use Change::Util::InterfaceRCS qw(getMostRecentFileVersion
                                  getWorkingFileVersion
                                  compareFileVersions
				  compareToMostRecentFileVersion
				  getDiffOfFiles
				 );
use Change::Util::SourceChecks qw(checkChangeSet);
use Change::Configure qw(readConfiguration);

use Util::File::NFSLock ();
use Util::Message qw(
    message verbose verbose2 alert verbose_alert
    warning error fatal debug debug2 debug3 open_log
);
use Util::File::Functions qw(ensure_path);

use Util::File::Basename qw(dirname basename);
use Util::Retry qw(retry_output3);

use BDE::Component;
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::DependencyCache qw(getCachedGroupOrIsolatedPackage);
use BDE::FileSystem;
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent isGroupedPackage isIsolatedPackage isLegacy
    getComponentPackage getComponentGroup getPackageGroup
    getSubdirsRelativeToUOR
);

use Change::DB;
use Change::AccessControl qw(
    isInvalidContext isRestrictedFile isValidFileType getFileLock setFileLock
    getChangeSetStraightThroughState isStraightThroughLibrary 
    isProgressLibrary checkMaintenanceLocks getChangeSetManualReleaseState
);
use Change::Approve qw(checkApproval);
use Change::Plugin::Manager;

use Production::Services;
use Production::Services::Move;
use Production::Services::ChangeSet qw();
use Production::Services::Ticket;
use Production::Services::Util;
use Production::Symbols qw(
    HEADER_FUNCTION HEADER_TASK HEADER_APPROVER HEADER_TESTER HEADER_REFERENCE
    HEADER_ORIGINAL_ID SCM_SERVER_ENABLED SCM_CHECKINROOT_ENABLED
    SCM_MULTICHECKIN_ENABLED SCM_BRANCHING_ENABLED
    ENVIRONMENT_IS_TEST
);

use constant DEFAULT_JOBS => 10; # for this tool, more parallel

my @RCSDIFFKKCMD=('/usr/local/bin/rcsdiff','-kk','-q');
my @RCSDIFFKKVCMD=('/usr/local/bin/rcsdiff','-kkv','-q');
my @RCSDIFFKKVLCMD=('/usr/local/bin/rcsdiff','-kkvl','-q');
my @DIFFCMD=('/usr/bin/diff','-s');

my $copy_to_cbld = 0;# Compatibility -- should disappear in future.

# No parameter means the default logfile
open_log();

# Before we go any further, log the commandline we got
verbose("Commandline: " . join(" ", $0, @ARGV));

# Figure out how many jobs we should run. This is based on the current
# time. If it's off-hours for new york and london there's a multiplier
# of 2, for off-hours new york there's a multiplier of 1.5.
sub default_job_count {
  my $base_count = DEFAULT_JOBS;
  my $hour = (gmtime(time))[2];
  my $day = (gmtime(time))[6];
  my @multiplier = (1, 1,                # midnight GMT, 7 Eastern
		    1.5, 1.5, 1.5, 1.5, 1.5, 1.5,      # 9 PM Eastern
		    1.5, 1.5, 1.5, 1.5, 1.5, 1.5,      # 3A eastern, 8A GMT
		    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1);  # 9A eastern
  my $jobcount = $base_count * $multiplier[$hour];
  if ($day == 0 or $day == 6) {
    $jobcount = $base_count * 3;
  }
  verbose("Simultenaity count set to $jobcount");
  return $jobcount;
}

#==============================================================================

=head1 NAME

cscheckin - Create and submit change sets for multiple files

=head1 SYNOPSIS

Commit multiple files to a single library, prompting for required info:

  $ cscheckin * acclib
  (or using --to option)
  $ cscheckin --to acclib *
  Ticket: drqs1234567
  Message: comment
  Message: .

List changes to screen without committing, single library:

  $ cscheckin -l * acclib
  (or, if parent directory is called 'acclib')
  $ cscheckin -l *

Carry out pre-commit checks without committing, single library:

  $ cscheckin -n * acclib
  (or, if parent directory is called 'acclib')
  $ cscheckin -n *

Commit multiple files to a single library, all required info on command line

  $ cscheckin --drqs 1234567 --message 'comment' --to acclib *
  (or, alternate form not using --to option, destination is last argument)
  $ cscheckin --drqs 1234567 --message 'comment' * acclib

Commit multiple files to multiple libraries:

  $ cscheckin --treq 987654 --message 'comment' acclib/* mtgeutil/*
  (or with short options)
  $ cscheckin -T 987654 -m 'comment' acclib/* mtgeutil/*

Generate list of would-be-committed files, edit it, commit it:

  $ cscheckin -n * acclib > acclib.changes
  $ vi acclib.changes
  (remove unwanted files from calculated changeset)
  $ cscheckin --from acclib.changes

Submit as bug fix move to alpha:

  $ cscheckin --drqs 1234567 --bugf --message 'comment' acclib/*
  (or with short options)
  $ cscheckin --drqs 1234567 -bm 'comment' acclib/*

Add a note to the associated drqs ticket when change set is committed: 

  $ cscheckin --note 'comment' acclib/*

=head1 DESCRIPTION

This tool allows developers to submit changes for one or more libraries as a
single I<change set>. File wildcards can be used to have the tool scan all
candidate files and determine automatically which are unchanged, which are
modified, and which are new. To submit changes to multiple libraries as an
atomic change set, place the files being worked on into a directory with the
corresponding name -- for example, to work on C<acclib> and C<mtgeutil> as
part of a single change, create directories C<acclib> and C<mtgeutil> and copy
out the files to be worked on into their respective directories.

A fairly typical workflow for a developer working on a single library looks
like the following, assuming the library is C<acclib>. The developer checks
out two files from the library's current production version, edits only one of
them, then uses the tool first to see what was changed, then commit it:

    $ mkdir acclib
    $ cd acclib
    $ checkout a_file.c acclib
    $ checkout another_file.c acclib
    $ vi a_file.c

...hack away...

    $ vi a_new_file.c

...add some code...

    $ cscheckin -n *

...check local files against production SCM, lists new or changed files. Only
new or changed files appear:

    Unit of release: acclib (2 files)
    Destination: /bbsrc/acclib
        a_file.c     (CHANGED)
        a_new_file.c (NEW)

...assuming work is complete, these can now be submitted together:

    $ cscheckin --treq123456 --message 'comment' *

...change set committed, change set ID assigned and returned to user:

    Unit of release: acclib (2 files)
    Destination: /bbsrc/acclib
        a_file.c     (CHANGED)
        a_new_file.c (NEW)
    Committed: Change set ID = 1234567890

...if a conflicting change set has been submitted, an error is returned:

    Unit of release: acclib (2 files)
    Destination: /bbsrc/acclib
        a_file.c     (CONFLICT!)
        a_new_file.c (NEW)
    Conflicting changes (a_file.c) - cannot commit.

If working on more than one library, create a directory for the local copy of
the files for each directory, work on them, then create a change set for all
the files together:

    $ cscheckin -T123456 -m 'comment' acclib/* mtgeutil/*

C<cscheckin> will determine the parent directory if it isn't specified (as in
the acclib example above) and use that to determine the library to which the
file belongs. The wildcards are regular filesystem wildcards, and so can be as
precise or vague as needed to identify the files to be considered for
submission.

=head2 Submitting Unchanged Files for Recompilation

By default, specified files (e.g. expanded from wildcard arguments) that are
unchanged are not included in a change set. To include unchanged files also,
use the C<--unchanged> or C<-U> option. To use a wildcard to conveniently
select a large group of files but avoid submitting files for recompilation
unnecessarily, edit the change set first.

C<--unchanged> is implied if C<--from> is used (see below), but note that
the streamed change set file supplied to C<--from> must have been originally
created with C<--unchanged> for any unchanged files to be actually present.

=head2 Reverting a Staged File Without Using Rollback

You can checkin a file that is unchanged relativ to the most recently swept
version and force this version to undo any staged version of that file by
using the C<--revert> option. Previous to the introduction of this switch,
this was not possible as an unchanged file could not eclipse a staged file
that was changed.

C<--revert> therefore alters the behaviour of unchanged files. Note however,
that a reverted file is still being recompiled. Also, unchanged files included
by the FindInc plugin will not be marked as reverted but will instead remain
what they used to be: Requests for recompilation.

=head2 Editing Change Sets Prior To Submission

It is possible to edit a change set prior to submission by using the
C<--list>/C<-l> and C<--machine>/C<-M> options to stream a candidate change
set to a file, and then the C<--from>/C<-f> option to read it in again:

    $ cscheckin -l -M acclib/* mtgeutil/* otherlib/* > candidate.set
    <edit candidate.set to remove unwanted files from the change set>
    $ cscheckin -f candidate.set

Use the C<--unchanged> or C<-U> option to include unchanged files in the
streamed change set, otherwise they will be removed:

    $ cscheckin -l -M -U acclib/* mtgeutil/* otherlib/* > candidate.set

The ticket and message may be supplied in the initial command, in which case
they are written out to the candidate change set and will be used when the
change set is read back in again. Otherwise, they must be provided when the
change set is submitted. (The original ticket and message may also be
overridden in the second command if necessary.)

Additional files may not be combined with a candidate set read from a file.

=head2 Reading Filenames from a File (or Standard Input)

To create a change set with a file specification that would exceed the length
limit of a command line, use the C<--input> or C<-i> option. This will read
a list of files from the specified file, or standard input if no file is
specified, and is an alternative to C<--from> or C<-f> that has no length
limitations.

   $ find . -name *.h -o -name *.c > file.list
   $ cscheckin -i -n file.list

Or without the intervening file, reading from standard input:

   $ find . -name *.h -o -name *.c | cscheckin -i -n

Unlike C<--from>, C<--input> does not read a streamed change set to get its
information and therefore I<will> remove unchanged files from the change set
unless C<--unchanged> or C<-U> is specified:

   $ find . -name *.h -o -name *.c | cscheckin -i -n -U

C<-i> may be combined with C<-l> and C<-M> to generate a candidate changeset
description from an arbitrarily long list of files without exceeding the
command-line length limit:

   $ find . -name *.h -o -name *.c | cscheckin -i -lMU > candidate.set

=head2 Adding a note to associated drqs ticket

When the associated ticket user provided is a drqs ticket, after the changeset
committed, a note will be added to the drqs log saying this changeset
created. User can also specify the note with C<--note> 'comment':

   $ cscheckin --note 'comment'

=head2 Plugins

cscheckin has a plugin architecture by which custom functionality can be hooked
into the checkin procedure. For details, please see {BP CSCHECKIN PLUGINS} for details
on existing plugins and how to develop your own.

=cut

=begin disabled

=head2 Declaring dependencies on existing change sets

The SCM systems knows about dependencies between change sets. Dependencies
serve various purposes. For one, they play a vital role in multiple checkins in
that a change set is made C<contingent> on a prior change set with overlapping
files. This means that the change set wont be processed before the prior one (
the one it depends on) has been processed.

You can specify the following dependencies:

=over 4

=item * --dependent CSID1[,CSID2,CSID3,...]

Make the change set dependent on CSID1, CSID2, etc. This means your change
set will only be processed when all dependent change sets have succesfully
been committed to the repository. If one of them fails, your change set 
will be withdrawn.

=item * --contingent CSID1[,CSID2,CSID3,...]

This is a less strict version of C<--dependent>. The contingencies CSID1,
CSID2, etc. are only required to have a final state which could mean the commit
failed. This is in essence a means to enforce ordering: CSID1, CSID2, ... will
be processed before your change set.

=item * --independent CSID1[,CSID2,CSID3,...]

Make your change set forcibly independent of CSID1, CSID2, etc. This is useful
if for some reason you want to dodge colision detection on SCM. Ordinarily, when
a new change set is enqueued on SCM, the queue ahead is scanned for file-overlap.
If overlap is detected, the change sets further ahead in the queue containing
an overlapping set of files are marked as contingencies, thus forcing them to
be processed before your new submission.

=back

=end disabled

=head1 NOTES

=head2 Limitations of the Trailing Library Argument

If the C<--to> or C<-t> option is not specified, and the last file argument
is not an identifiable local file, and exists as a directory path under
C</bbsrc>, then the last file argument is assumed to be an implicit
destination argument and removed from the list of candidate files. This mode
however, like the C<--to> option, will not permit a change set to include
files from multiple libraries. To do that, use appropriate container directory
names.

=head2 Emergency Moves

An emergency move can be indicated with the C<--emove> or C<-e> option.

Additional information required for EMOV processing is requested if running
interactively, or can be supplied with the C<--testers|-G>, C<--approver|A>,
C<--tasks|E>, and C<--functions|F> options. If the move type of the EMOV
is indeterminate (i.e., could be beta-only or all-production) then the
C<--beta|B> or C<--nobeta> options can be used to resolve the question on the
command line.

=head2 New File Policy for Bug Fixes and Emergency Moves

Traditionally, new files are not permitted when bug fix restrictions are in
effect. This tool I<will> allow a new file to be checked in as part of a bug
fix (i.e. if the 'bug fix only' flag is set) but I<only> if the new file is
part of a change set that also includes at least one changed file.

=head2 Optional Approval Stages

When an approval stage applies to a changeset it will automatically be
invoked by C<cscheckin>. If an approval stage is optional, then C<cscheckin>
will ask whether or not to apply it. To answer this question on the
command line, the --approval or -Y option, or the --noapproval or -N option
can be specified.

=head2 File Length Limit Policy

Filenames up to 60 characters are now permitted.

=head2 Multi-value Interactive Prompts

Some options, notably those for emergency moves such as functions, tasks,
or testers, allow more than one value to be supplied. When these values are
prompted for interactively, use spaces to separate each item from the next:

    Tasks to relink for this EMOV: ibig aebig rmdbex

=head2 Option Bundling

As with all tools in the BDE Tools Suite, options may be bundled
(concatenated) when they do not take parameters. Options may also trail the
arguments, so the following is equivalent to the previous example:

    $ cscheckin -m 'comment' acclib/* mtgeutil/* -T123456

=head2 Running Compile Tests Without Checking In

The L<cscompile> tool can be used to carry out compile tests without worrying
about checking in, or supplying check-in details not applicable to a compile
test (such as the ticket number, etc.).

L<cscompile> takes the same wildcard file list and optional trailing library
argument as C<cscheckin>, and carries out the same compile tests. In addition,
it can have its level of parallelisation altered with C<-j>. C<cscompile>
also carries out source checks, but does I<not> carry out permission-releated
validation checks like detecting file locks or determining if a given file
type is allowed in a given location. See the L<cscompile> manual page for
more information.

=head2 Plugins

C<cscheckin> provides support for external plugins to augment or alter its
behaviour for application-specific purposes. This allows the tool to be
adapted to carry out additional processing and/or alter the list of files
considered according to additional logic supplied by the plugin.

Plugins are loaded with the C<--plugin> or C<-L> option. For example, to
load the example plugin, which simply prints out messages when it is
accessed:

    cscheckin -LExample ...

Usage information, including command line extensions, can be extracted using
the usual C<--help> or C<-h> option:

    cscheckin -LExample -LFileMap -LAnotherPlugin -h

Currently supported plugins include:

=over 4

=item ClearCase - Provides integration with ClearCase, including checks for
      the validity of the ClearCase view, checks that the files being checked
      in are current checked-in VOB elements, and labelling the files in
      ClearCase afterwards (in the event of a successful check-in).

=item FileMap - Allows local files to be mapped to different destination
      libraries and/or application directories using a map file. An alternative
      way to specify multiple destinations.

=item Approval::TSMV - Integration with the TSMV approval process.
      Automatically loaded when TSMV is applicable to a change set.

=item Approval::PRQSCR - Integration with the PRQS CR approval process.
      Automatically loaded when PRQS CR is applicable to a change set.

=back

Plugins may be supported by any development group, and may be contributed as
part of cscheckin as 3rd-party extensions to the tool. All such plugins must
first be vetted by the maintainers of cscheckin prior to installation, but
if accepted become part of the standard cscheckin toolset.

Contributed plugins are actively encouraged - see the PWHO contacts for
cscheckin for more information, and L<Change::Plugin::Base> and
L<Change::Plugin::Example> for more information on how to create plugins.

=head2 Per-User Configuration Files

C<cscheckin> supports per-user configuration files which can be used to
supply automatic options to cscheckin without specifying them on the command
line. The per-user configuration file is called C<.csrc> (pronounced 'cuzruck')
and must exist in the user's home directory.

The configuration file structure consists of a series of sections, one for
each CS tool, plus the special section C<[all]> that applies to all tools.
Blank lines and comments are supported, anything else is considered to be
a command-line option. Here is an example C<.csrc> file that provides 

    [all]
    # enable verbose for all tools
    -v

    [cscheckin]
    # automatically load the FileMap and Example plugins, enable autolocking
    -LFileMap -LExample
    --autoco

    [cscompile]
    -v
    # an extra level of verbosity for cscompile

The C<.csrc> configuration file can be used to:

=over 4

* Automatically supply an approver for EMOVs

* Automatically answer questions by supplying the associated command line
  option.

* Automatically load plugins such as ClearCase or FileMap

* Automatically enable debug or verbose modes

* ...or supply any other command-line options the user desires.

=back

=head1 EXIT STATUS

The exit status is zero for success or non-zero on failure. The specific
meaning of success or failure depends on the mode in which C<cscheckin> is
being invoked:

=over 4

=item If committing

A zero exit status is returned if the change set was successfully submitted,
or a non-zero exit status otherwise.

=item If testing (-n)

A zero exit status is returned if the change set passes all tests, or a
non-zero exit status otherwise.

=item If listing (-l)

A zero exit status is returned if the change set contains files elegible for
consideration -- that is, the change set is not empty after inapplicable files
like RCS archives and object files are removed. A non-zero exist status is
returned otherwise.

=cut

#==============================================================================

sub usage(@) {
    my $prog = "cscheckin"; #basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-w <dir>] [[-c]|-n [-p]] [-v] [-d] [-t=<unit>] <files>
  --debug        | -d            enable debug reporting
  --help         | -h            usage information (this text)
  --config       | -z		 specify configuration file
  --ignoreconfig | -Z            ignore per-user configuration file, if present
  --ignoretests                  ignore test drivers (extension .t.*)
  --to           | -t <uor>      specify destination unit of release
                                 (only with unqualified file arguments)
  --where        | -w <dir>      specify explicit alternate local root
  --noretry      | -X            disable retry semantics on file operations
  --verbose      | -v            enable verbose reporting

File input options:

  --from         | -f            read change set from file (e.g. previously
                                 generated with --list and --machine). Implies
                                 --unchanged.
  --input        | -i [<file>]   read additional list of explicit filenames
                                 from standard input or a file (if specified)
  --reinstate    | -R <csid>     reinstate from a previous change set id
                                 

Display options:

  --list         | -l            list changes, do not commit or perform checks
  --pretty       | -P            list changes in human-parseable output
                                 (default if run interactively)
  --machine      | -M            list changes in machine-parseable output
                                 (default if run non-interactively)
  --difference   | -K <file>     generate difference report to specified file

Commit options:

  --[no]autoco   | -a            automatically check out files prior to commit
                                 (only for files in the set that are unlocked)
  --[no]approval | -Y (no=-N)    (do not) use optional approval, if applicable
  --commit       | -c            commit changes (default, prompts for DRQS or
                                 TREQ unless one of --drqs or --treq is also
                                 specified)
  --nocommit     | -n            perform checks but do not commit (see also
                                 --list)
  --oldfiles                     'clobber' if old (different) files are
                                 supplied for check-in.
  --nooldfiles                   abort processing if old (different) files are
                                 supplied for check-in (default). 
				 (implies merge required)
  --ignoreoldfiles               ignore if old (different) files are
                                 supplied for check-in.
				 (implies merge required)
  --revert       | -V            treat unchanged files as a revert to head of RCS
                                 (except those added by the FindInc plugin)
  --note                         attach a note to log of the drqs ticket
                                 associated with the change set
  --drqs         | -D <drqs>     commit on specified DRQS (implies --commit)
  --treq         | -T <treq>     commit on specified TREQ (implies --commit)
  --message      | -m <message>  attach message/comment to change set
                                 (prompted for if commiting and not specified)
  --reference    | -r            optional 'reference' information
  --unchanged    | -U            include unchanged files in the change set,
                                 to force a recompile (default)
  --nounchanged                  do NOT include unchanged files
  --changed      | -C            include changed older files in the change set
                                 (implies merge is not required)
  --yestonew     | -y            automatically confirm changeset when new files
                                 will be created as a result of the submission.

Commit options (bug fix):

  --[no]bugf | --bf | -b         change is (not) a bug fix move to alpha
                                 for the current release cycle

Commit options (emergency move):

  --[no]emov     | -e            (do not) commit as emergency move
  --[no]beta     | -B            EMOV is (not) beta only [no=all machines]
  --functions    | -F <funcs>    impacted functions for EMOV
  --tasks        | -E <tasks>    tasks (executables) to relink for EMOV
  --testers      | -G <testers>  one, or two comma-separated, logins or UUIDs
                                 for suggested testers.
  --approver     | -A <approver> login or UUID of approver

Commit options (straight-through processing)

  --approver     | -A <approver> login or UUID of approver

Testing options:

  --gcc-ansi                     run gcc/g++ -ansi for gcc compile tests
  --Werror       | -W            treat warnings as errors
  --nogccwarnings                do not display gcc warnings (when no errors)

Extended functionality options:

  --plugin       | -L <plugin>   load the specified extension

_USAGE_END

    my $plugin_usage=getPluginManager()->plugin_usage();
    print $plugin_usage,"\n" if $plugin_usage;

    print "See 'perldoc $prog' for more information.\n";

    print STDERR "\n!! @_\n" if @_;
}


=begin disabled

  --timeout                      only used by machine backends

Declared dependencies:

  --dependent    | -CD <csids>   make change set dependent on <csids>
  --contingent   | -CC <csids>   declare <csids> as contingencies
  --independent  | -CU <csids>   change set is independent from <csids>

=end disabled

=cut

#------------------------------------------------------------------------------

# FIXME Shouldn't this be an AND rather than an OR?
my $has_tty = -t STDIN || -t STDOUT;

my $ctrlCcaught = 0;

sub ctrlCsigHandler {
    $ctrlCcaught = 1;   #  SIGINT-caused rollback which does not really work
                        #  as we expected, :-(
}

{ my $manager = new Change::Plugin::Manager(CSCHECKIN_TOOL);
  sub getPluginManager { return $manager; }
}

{ my $ignoretest=0;

  sub setIgnoretestFlag() {
      $ignoretest=1;
  }

  sub getIgnoretestFlag { return $ignoretest; }
}


{
    # closure for --revert flag:
    # we only want to mark unchanged files NOT included by FindInc as REVERTED.

    my %unchanged_pre_findinc;
    sub addUnchangedPreFindInc {
        for (@_) {
            my $target = $_->getTarget;
            my $leaf = $_->getLeafName;
            $unchanged_pre_findinc{ "$target/$leaf" } = 1;
        }
    }
    sub isToBeReverted {
        my $file = shift;
        my $target = $file->getTarget;
        my $leaf = $file->getLeafName;
        return exists $unchanged_pre_findinc{ "$target/$leaf" };
    }
    sub markAsReverted {
        my @cs = @_;
        for my $cs (@_) {
            isToBeReverted($_) and $_->setFileIsReverted
                for $cs->getFiles;
        }
    }
}

sub getoptions {
    my @options=qw[
        approver|approvers|A=s@
        approval|Y
        noapproval|N
        autoco|a!
        beta|B!
	changed
        nounchanged
        revert|V
        commit|c
        nocommit|n
        debug|d+
        difference|K=s
        drqs|D=i
        emov|isemov|e!
        from|f=s
        functions|function|F=s@
        bugf|bf|isbf|b!
        help|h
        honordeps|H
	ignoreoldfiles
        list|l
        message|m=s
        machine|M
	note=s
        nooldfiles
        oldfiles
        pretty|P
        reinstate|R
        reference|r=s
        stage|s=s
        tasks|task|E=s@
        testers|tester|G=s@
        to|t=s
        treq|T=i
        where|root|w=s
	Werror|W
        unchanged|U
        verbose|v+
        noretry|X
        yes|yestonew|y
	bypassGCCwarnings
	gccwarnings!
	gcc-ansi

        dependent|CD=s@
        contingent|CC=s@
        independent|CU=s@

	timeout=i
    ];

    my %opts;
    Getopt::Long::Configure("bundling");

    # BEGIN pass through sections
    Getopt::Long::Configure("pass_through");

    # rc files
    GetOptions(\%opts,"ignoreconfig|Z","config|z=s@");
    unless ($opts{ignoreconfig}) {
        $opts{config}
	? readConfiguration @ARGV,"cscheckin",
	(split / /,(join ' ',@{$opts{config}}))
	    : readConfiguration @ARGV,"cscheckin",(map {
		HOME.'/'.$_
		} split / /, CHANGERCFILES);
    }

    GetOptions(\%opts,"ignoretests");
    if($opts{ignoretests}) {
	verbose "Ignoretest flag is set";
	setIgnoretestFlag();	
    }

    # plugins and files-from-input (or rc files)
    $opts{plugin}=undef;
    GetOptions(\%opts,"plugin|L=s@","input|i:s");
    # END pass through sections

    Getopt::Long::Configure("no_pass_through");
    if ($opts{plugin}) {
	my $mgr=getPluginManager();
	foreach my $plugin_name (map { split / /,$_ } @{$opts{plugin}}) {
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
	my @input_args=map { chomp; split /\s+/,$_ } @lines;
	unshift @ARGV,@input_args if @input_args;
    }

    unless (GetOptions(\%opts,@options)) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS  if ($opts{help});

    # filesystem root for local searches (*not* the destination root)
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    $Util::Retry::ATTEMPTS = 0 if $opts{noretry};

    #commit/nocommit/list
    if ($opts{list} and ($opts{commit} or $opts{nocommit})) {
	warning("--list overrides --commit and --nocommit");
	$opts{commit}=$opts{nocommit}=0;
    }
    if ($opts{commit} and $opts{nocommit}) {
	warning "--nocommit overrides --commit";
	$opts{commit}=0;
    }
    $opts{commit}=1 unless $opts{list} or $opts{nocommit};

    if ($opts{from}) {
	fatal "--from incompatible with file arguments (@ARGV)" if @ARGV;
    }
    if ($opts{from} and $opts{unchanged}) {
	warning "--unchanged is automatically implied when using --from";
	warning "To include unchanged files from a streamed change set, ".
	  "use --unchanged when initially creating the change file";
    }
    if ($opts{from} and $opts{reinstate}) {
	fatal "--from and --reinstate are mutually exclusive";
    }
    if ($opts{reinstate}) {
	fatal "--reinstate allows only one argument" if @ARGV>1;
	$opts{reinstate}=$ARGV[0];
	@ARGV=();
    }

    # At this point @ARGV contains either nothing or a list of file names.
    # Make the list available to plugin_initialize hooks.
    $opts{files} = [ @ARGV ];
    @ARGV = ();

    # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	goto FINALIZE;
    }
    unless ($opts{pretty} or $opts{machine}) {
	if ($has_tty) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # stage - set to default 'regular' stage
    $opts{stage}=STAGE_INTEGRATION unless $opts{stage};

    # transient
    warning("--honordeps not yet supported - option ignored")
      if $opts{honordeps};

    # commit logic
    if ($opts{drqs} or $opts{treq}) {
	$opts{commit}=1 unless $opts{list} or $opts{nocommit};
    };

    # optional approval/nonapproval: approval=undef(ask)/0/1
    if ($opts{approval} and $opts{noapproval}) {
	fatal "--approval and --noapproval are mutually exclusive";
    }
    $opts{approval}=0 if $opts{noapproval};

    # 
    if ($opts{changed} and $opts{nounchanged}) {
	warning "--nounchanged is automatically implied when using --changed";
    }

    $opts{nounchanged}=1 if ($opts{changed});

    # Make unchanged the default behavior
    $opts{unchanged}=1 unless ($opts{nounchanged} || $opts{changed});

    # Make nooldfile the default behavior
    $opts{nooldfiles}=1 unless $opts{ignoreoldfiles};

    # timeout
    $opts{timeout}=300 unless (exists $opts{timeout});

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # pre-process multivalue options
    foreach my $listarg (qw[approver testers tasks functions]) {
	if (my $listval=$opts{$listarg}) {
	    my @actualargs=();
	    foreach my $val (@$listval) {
		#remove '_' from the delimiter list
		if($listarg eq "tasks") {
		    push @actualargs, (grep $_, split /[^\w.]+/,$val);
		} else {
		    push @actualargs, (grep $_, split /\W+/,$val); 
		}
	    }

	    $opts{$listarg}=join " ",@actualargs;
	}
    }

    return \%opts;
}

#------------------------------------------------------------------------------

# return destination location for files being passed on as part of changeset.
# Some external process will pick them up from this location. Right now, the
# location is flat, so the $target and $stage parameters don't do anything.
sub getDestinationOfFile ($$$) {
    my ($localfile,$target,$stage)=@_;

    my $file=CHECKIN_ROOT.$FS.basename($localfile);
    return $file;
}

#------------------------------------------------------------------------------

# create, and move this to, Util::File::Types
sub _isBinary ($) {
    my $file=shift;

    return ($file=~/\.ml$/)?1:0;
}

# compare candidate changeset to the stage repository and return a new
# changeset with all older or newer-but-identical files removed. All files
# that remain have their destinations filled-in in the new changset. The
# original candidate set is left unchanged.
sub findChanges ($$$;$$$$$) {
    my ($root,$candidateset,$stage,$nonfatal,$include_unchanged,
	$oldfiles,$nooldfiles,$ignoreoldfiles)=@_;

    # Copy over the attributes from the candidate set, with the
    # assumption that the subsequent code will override them later if
    # appropriate. We at least have reasonable defaults in this case
    # if we're working from a rolled-back changeset, and if we've got
    # a new changeset passed in as the candidateset then the values
    # will be the default for a new changeset, which is OK.
    my $changeset=new Change::Set({stage=>$stage,
				   when=>$candidateset->getTime(),
				   user=>$candidateset->getUser(),
				   group=>$candidateset->getGroup(),
				   ctime=>$candidateset->getCtime(),
				   move=>$candidateset->getMoveType(),
				   status=>$candidateset->getStatus(),
				   message=>$candidateset->getMessage(),
				   depends=>$candidateset->getDependencies(),
                                   reference=>[$candidateset->getReferences()],
				  });
    my $unchanged=0; #counters
    my $norcsid=0;
    my $badrcsid=0;
    my $metafile=0;
    my $oldfile=0;

  FILE: foreach my $file ($candidateset->getFiles) {
	my $target=$file->getTarget();
	my $ptarget=$file->getProductionTarget();
	my $lib=$file->getLibrary();
	my $prdlib=$file->getProductionLibrary();
	my $localfile=$file->getSource();
	my $localver; #!0=version, 0=unexpanded id, undef=no ID present
	my $leafname=$file->getLeafName();
	my $isbinary=_isBinary($leafname);
	my $looked=0; #have we checked for a version yet?
	if ($isbinary) {
	    $looked=1; $localver=0; #binaries can't have version strings
	}

	# phase 1: error if it's a metadata file; file a ticket for these
	if ($localfile=~/\.(mem|dep|opts|defs|cap)$/) {
	    if ($nonfatal) {
		warning("Metadata file $localfile must be submitted via DRQS");
	    } else {
		error("Metadata file $localfile must be submitted via DRQS");
	    }
	    $metafile++;
	    next FILE; #don't continue as it's an invalid type
	}

	# 1 - figure out stage location of the source controlled file
	my $stagelocn=getLocationOfStage($stage).$FS.$ptarget;

	# 2 - for each file, get file's stage location
	my $stagefile=$stagelocn.$FS.$leafname;
	
	# ignore .t.<ext> files so that they cannot be checked in 
	# if ignoretests is true
	if(getIgnoretestFlag() && $leafname =~ /\.t\.(\w)+$/){
	    verbose "file $leafname ignored for checkin";
	    next FILE;
	}

	# 2a- identify the correct stage file (i.e. look for archives first)
	debug3 "looking for stage file: ${stagefile},v";
	debug3 "     or for stage file: ".
	  $stagelocn.$FS.'RCS'.$FS.$leafname.',v';

	if (-f $stagefile.",v") {
	    $stagefile=$stagefile.",v";
	} elsif (-f $stagelocn.$FS.'RCS'.$FS.$leafname.',v') {
	    $stagefile=$stagelocn.$FS.'RCS'.$FS.$leafname.',v';
	} elsif (-f $stagefile) {
	    # A file not under RCS control
	} else {
	    verbose_alert "$leafname is a new file for $target";
	    # Check for existence of RCSid
	    my $dest=getDestinationOfFile($localfile,$target,$stage);
	    unless ($looked) { $localver=getWorkingFileVersion($localfile);
			       $looked=1 }
            unless ($isbinary or (defined $localver)) {
                if ($nonfatal) {
                    warning("$localfile has no valid RCSid");
		    # allow through for listing-only purposes
                } else {
                    error("$localfile has no valid RCSid");
		}
		$norcsid++;
            }

	    $changeset->addFile($target,$localfile,$dest,FILE_IS_NEW,
				$lib,$prdlib);
	    next FILE;
	}

	# 3 - detect if local file is older than stage file
	my $stagetime=-M $stagefile;
	my $localtime=-M $localfile;
	my $older=($localtime > $stagetime)?1:0;

	my $changed = 0;

	# 4 - skip if local file is identical to current stage version
	my @cmd;
	my $diff=0;
	if ($stagefile=~/,v$/) {
	    # Ideally this diff is to be done when localver is undefined
	    # BUT there are files where RCS string is defined
	    # in a comment and hence we will have a issue there.
	    # example at the time of writing the code: apitsprn.h
	    # Why this is needed: look for any file in year 2002 in RCS 
	    # ensure it has $id. use legacy checkout of the file
	    # then run cscheckin without statement below, it will
	    # say file changed.
	    $diff = getDiffOfFiles($localfile, $stagefile);	        
	} 
	else {
	    @cmd=@DIFFCMD;
	}

	debug "Checking file difference: @cmd $localfile $stagefile";

	$localfile=~/^(.*)$/ and $localfile=$1; #untaint.
	$stagefile=~/^(.*)$/ and $stagefile=$1; #untaint.
	if ($diff == 1 || (@cmd && retry_output3 @cmd,$localfile,$stagefile)) {
	    # note... rcsdiff on a binary file seems to generate a
	    # 'diff failed' error even though it only does it when there is
	    # a genuine difference. Using the '3' version here to suppress
	    # that error output going to the user.

	    # there's a difference
	    if ($older) {
		if ($oldfiles) {
		    warning("$localfile is older (and different than) ".
			    "$stagefile - clobbering (file merge required?)");
		} elsif ($ignoreoldfiles) {
		    warning("$localfile is older (and different than) ".
			    "$stagefile - ignoring (file merge required?)");
		    next FILE;
		} else {
		    error("$localfile is older (and different than) ".
			  "$stagefile - aborting (file merge required?)");
		    $oldfile++;
		    next FILE;
		}
	    }
	    $changed = 1;
	    verbose_alert "$localfile is changed";
	} elsif ($include_unchanged) {
	    $unchanged++;
	    verbose("$localfile is identical to $stagefile (recompile)");
	} else {
	    verbose("$localfile is identical to $stagefile, ignored");
	    $unchanged++;
	    next FILE;
	}

        # 5 - Make sure our file is derived from the tip of the RCS branch
	if ($isbinary) {
	    #<<<TODO: .inc bypasses version check until f2c is updated
	    #<<<TODO: to be able to handle the version string. See f2c TREQ
	    #<<<TODO: for this work, on completion of which this exception
	    #<<<TODO: can be removed.
	    debug "$leafname is binary - skipping file version check";
	} else {
	    my $stagever = getMostRecentFileVersion($stagefile, $stage);
	    unless ($looked) { $localver=getWorkingFileVersion($localfile);
			       $looked=1 }

	    debug2("Validating versions: $stagefile(".
		   (defined $stagever ? "r$stagever" : "undef").
		   ") $localfile(".
                   (defined $localver ? "r$localver" : "undef").")");

	    if ($nonfatal) {
		warning("$localfile has no valid RCSid"),$badrcsid++
                    unless (defined $localver) or (not $changed);
		#warning("$localfile (r$localver) ".
		#	"is older than checkout from $stagefile (r$stagever)"),
		#	  $badrcsid++
		#	    if ($localver) and
		#	      (compareFileVersions($localver, $stagever) < 0);
	    } else {
		error("$localfile has no valid RCSid"),$badrcsid++
                    unless (defined $localver) or (not $changed);
		#error("$localfile (r$localver) ".
		#      "is older than checkout from $stagefile (r$stagever)"),
		#    $badrcsid++
		#      if ($localver) and
		#	(compareFileVersions($localver, $stagever) < 0);
	    }
	}
	
	# 6 - it's a change! Add it to the change set (if it's not older)
        my $dest=getDestinationOfFile($localfile,$target,$stage);
        $changeset->addFile($target,$localfile,$dest,
			    ($changed ? FILE_IS_CHANGED : FILE_IS_UNCHANGED),
                            $lib,$prdlib);
    }

    # X - Bail if fatal errors were detected for any files in the CS
    error("$metafile attempt".($badrcsid>1 ? "s":"").
	      " to check in metadata detected") if $metafile;
    error("$norcsid file".($norcsid>1 ? "s":"").
	      " missing RCS ID string - use add_rcsid?") if $norcsid;
    error("$badrcsid file".($badrcsid>1 ? "s":"").
	      " detected with an older version") if $badrcsid;
    error("$oldfile file".($oldfile>1 ? "s":"").
	      " detected older but different (merge required?)") if $oldfile;
    unless ($nonfatal) {
	fatal("Errors in change set - cannot proceed")
	  if $norcsid or $badrcsid or $metafile or $oldfile;
    }

    if ($unchanged) {
	my $s=($unchanged>1)?"s":"";
	if ($include_unchanged) {
	    message "$unchanged unchanged file$s marked for recompilation";
	} else {
	    warning "$unchanged unchanged file$s ignored";
	}
    } else {
	verbose "no unchanged files found";
    }

    # return changeset with only actual changes listed
    return $changeset;
}

# generate diff report <<<TODO: extend to do 'plain' as well as 'html'
sub generateDifferenceReport ($$) {
    my ($changeset,$destination)=@_;
    my $csid=$changeset->getID() || "anonymous";

    ensure_path(dirname $destination);
    my $fh=new IO::File(">".$destination);
    unless ($fh) {
	warning "Unable to open difference report file $destination: $!";
	return undef;
    }

    # preamble
    print $fh qq[<html><head>\n];
    print $fh qq[    <title>Difference report for Change Set $csid</title>\n];
    print $fh qq[</head><body>\n];
    print $fh qq[    <font size="5">Difference report for Change Set].
      qq[$csid</font>\n];
    print $fh qq[    <hr noshade size="1" color="black">\n];
    print $fh qq[<pre>\n];
    print $fh $changeset->listChanges(1,"header only");
    print $fh qq[</pre>\n];

    # diff report index
    print $fh "<ul>\n";
    foreach my $target ($changeset->getTargets) {
	my @files=$changeset->getFilesInTarget($target);
	print $fh "<li>Target: $target (${\ scalar @files} files)</li>";
	print $fh "<ul>\n";
	foreach my $file (@files) {
	    print $fh "<li>".qq[<a href="#].$file->getSource().
	      qq[">].$file->getSource.qq[ -&gt; ].$file->getDestination.
		" (".$file->getType.")</a></li>\n";
	}
	print $fh "</ul>\n";
    }
    print $fh "</ul>\n";

    # diff reports
    foreach my $file ($changeset->getFiles) {
	next unless $file->isChanged();
	next if _isBinary($file->getLeafName);
	print $fh qq[<br>\n];
	print $fh qq[<table width="100%" style="border:1px solid black;">].
	  qq[<tr><td width="*">\n];
	print $fh qq[<table width="100%" bgcolor="#a0a0a0">].
	  qq[<tr><td width="*">\n];
	print $fh qq[&nbsp;<a name="].$file->getSource().qq["><font size="4">].
	  $file->getTarget().'/'.basename($file).qq[</font></a>\n];
	print $fh qq[</td></tr></table>\n];
	print $fh compareToMostRecentFileVersion($file,$file,"html");
	print $fh qq[</td></tr></table>\n];
    }

    print $fh qq[</body></html>\n];
    close $fh;

    return 1;
}

# THIS CODE IS STOLEN STRAIGHT OUT OF BDE_ROLLBACKCS.PL. It shouldn't
# be there, and it shouldn't be here, but it is. Should be library
# code, but this is being hacked in to solve an immediate (and pretty
# bad) problem rolling back changesets that fail validation, since
# they leave symbol files lying around.
sub remove_symbol_changes ($$) {
    my($changeset,$csid) = @_;
    my @movetypes = ($changeset->getUser() ne "registry")
      ? ($changeset->getMoveType())
      : (MOVE_EMERGENCY, MOVE_BUGFIX, MOVE_REGULAR);
    my @symbol_files;
    foreach my $movetype (@movetypes) {
	push @symbol_files,
	     map { COMPCHECK_DIR.'/'.$movetype."/symbols/$_.$csid" }
		 qw(added removed);
    }
    my $FH = Symbol::gensym;

    foreach my $file (@symbol_files) {
	## truncate file instead of attempting removal because user "robocop"
	## is part of "sibuild" group, but initgroups() is not run in robogw,
	## and "bldtools" owns the directory containing these files
        if (-e $file) {
	    if (! -f $file) {
	        warning("symbol file $file is not a regular file (contact SI Build Team)");
		next;
	    }
	    if (!open $FH, ">".$file) {
	        warning("Attempt to open symbol file $file failed (contact SI Build Team): $!");
		next;
	    }

	    if (!close $FH) {
	        warning("Attempt to close symbol file $file failed (contact SI Build Team): $!");
		next;
	    }
	}
    }
}

# check whether a changeset can be added to the stage SCM or not
# these are 'compile time' checks - intrinsic to the CS, like the file type
# and not to otherwise changeable state like whether the file is locked or not.
# see also checkRestructions
sub verifyChanges ($$) {
    my($changeset,$is_manual_release)=@_;
    my $stage=$changeset->getStage();
    my $user=$changeset->getUser();

    # phase 1: file type restriction
    my $badtype=0;
    foreach my $file ($changeset->getFiles) {
	my $prdtgt=$file->getProductionTarget();
	unless (isValidFileType($prdtgt,$file)) {
	    if ($file->isNew) {
		$badtype=1;
		my $src=basename($file);
		error "$src is not a permitted file type in $prdtgt. If this";
		error "is the correct destination for $src, please contact ";
		error "group 412 to update the file types allowed in $prdtgt.";
	    } else {
		# already exists, grandfather it.
	    }
	};

    }

    return 0 if $badtype;

# Nomenclature lock disabled pending further review /CPP WG
#	# phase 1: nomenclature lock
#	my $badname=0;
#	foreach my $file ($changeset->getFiles) {
#	    next unless $file->isNew();
#	    my $target=$file->getTarget();
#	    my $name=basename($file); #string context = destination
#	    $name =~ s/\.(.*)*$//;
#	    if (isLegacy($target) or !(isGroup($target) or isPackage($target))) {
#		# legacy code must not conflict with naming scheme
#		if (isComponent $name) {
#		    error "new non-component file $file conflicts with ".
#		      "component nomenclature";
#		    $badname=1;
#		}
#	    } else {
#		# component code must adhere to naming scheme
#		unless (isComponent $name) {
#		    error "new component file $file does not adhere to ".
#		      "component nomenclature";
#		    $badname=1;
#		}
#	    }
#	}
#	return 0 if $badname;

    # phase 1: miscellaneous 'quick' source checks
    return 0 unless ($is_manual_release || checkChangeSet($changeset, 
							  default_job_count()));

    # phase 0: user restriction via file lock list
    my $restricted=0;
    foreach my $file ($changeset->getFiles) {
	my $target=$file->getTarget();
	if (isRestrictedFile($file)) {
	    $restricted=1;
	    my $srcfile=basename($file->getSource());
	    error "$srcfile ($target) is restricted";
	}
    }
    return 0 if $restricted;

    #<<<TODO: check members file for 'membered' units of release.

    verbose "changeset is valid";
    return 1; # OK.
}

sub promptForYND {
    my $prompt = shift;
    my $term = Term::Interact->new;
    my $re = qr/^([yndYND])/;
    my $result = $term->promptForSingle($prompt,$re);
    $result =~ m/$re/;
    $result = $1 || 'n';
    return lc($result);
}

sub promptForEnter {
    my $prompt = shift;
    my $term = Term::Interact->new;
    return $term->promptForSingle($prompt);
}

sub more_overlap_info {
    my ($conflicts, @lroots) = @_;

    my %incs;
    $incs{ basename($_) } = $_ for @lroots;

    while (my ($csid, $info) = each %$conflicts) {
        print sprintf '%s by %s at %s with status %s contains:'.$/,
            $csid, $info->{user},
            scalar localtime $info->{timestamp},
            $info->{status};

        my @files = map { /^file:(.+)$/ ? ($1) : () } keys %$info;

        for (@files) {
            my $filestatus = $info->{'file:'.$_};
            next if not exists $incs{$_};
            print "  $incs{$_} ($filestatus)".$/;
        }
    }

    my $term = Term::Interact->new;
    return $term->promptForYN("Do you want to continue (y/n)?");
}


# return true if 'run time' restrictions on the CS allow it to proceed.
# - file conflicts
sub checkConflicts ($;$) {# changeset, overwrite
    my ($changeset,$overwrite)=@_;
    my $stage=$changeset->getStage();
    my $user=$changeset->getUser();

    # phase 0: check for existing conflicting changeset by file presence
    my $conflict=0;
    my @conflict=();
    my $movetype = lc($changeset->getMoveType());
    my %priority = (
       (MOVE_EMERGENCY) => 3,
       (MOVE_BUGFIX) => 2, 
       (MOVE_REGULAR) => 1, 
       (MOVE_IMMEDIATE) => 0,
    );

    my @lroots;
    foreach my $file ($changeset->getFiles) {
	my $target=$file->getTarget();
	my $destfile=getDestinationOfFile($file,$target,$stage);
	
	my $lroot = getCanonicalPath($file);
	push(@lroots, $lroot) if not $file->isUnchanged;

	# Not present in /bbsrc/checkin ... move on.
	(SCM_CHECKINROOT_ENABLED  and  -f $destfile)  or  next;
	# Old school: no multicheckin.
	if (!SCM_MULTICHECKIN_ENABLED) {
	    $conflict=1;
	    error "$destfile ($file) already exists";
	}
	# check 'old-style' checkin staging area
	# FIXME: get rid of this?
	# This appears to exclude a fixed list of files at present.
	if (-f UNRELEASED_ROOT.$FS.basename($destfile)) {
	    $conflict=2;
	    error "$destfile conflicts with ".UNRELEASED_ROOT;
	}
	# New school: multicheckin.
	# If reason file cannot be opened, let them overwrite.
	open(FH,"$destfile.reason")  or  next;
	while(<FH>) {
	   m/^(file $destfile, stage \w+, movetype (\w+),.*)$/  and  last;
	}
	# If we have no move type, let them overwrite.
	my $reasontype = $1  or  next;
	my $higher = ($priority{$reasontype} > $priority{$movetype}) ? 1 : 0;
	error "$destfile ($file) exists in a previous "
	  .($higher?'higher priority ':'')."submission";
	$conflict ||= $higher;
	if ($overwrite  and  !$higher) {
	    push(@conflict,$destfile);
	}
    }
    
    my $conflicts;
    if (SCM_CHECKINROOT_ENABLED) {
      if ($conflict) {
	  return 0;
      }
      if (@conflict) {
	  my $interact=new Term::Interact;
	  my $yn=$interact->promptForYN("Do you want to overwrite the files (y/n)?");
	  # if answer is no, then conflict remains and this changeset cannot go further
	  return 0 unless $yn;
      }
    } elsif ($overwrite) {
	if(@lroots and $conflicts = getOverlappedCsidsSCM($changeset->getMoveType, @lroots)) {
            # Damian's sufficiently advanced Lingua::EN::Inflect
            # would be quite cool here. And quite generally,
            # what follows herre is despicable and disgusting.
            # 90% of the code is for trying to maintain readable
            # formatting.
            my (@csids, $has_or_have, $this_or_these);
            my @allids = keys %$conflicts;

            # split into orderinary CSIDs (@ids) and those
            # that are rollback requests (@rbids)
            my (@ids, @rbids);
            for my $i (@allids) {
                my $rec = getChangeSetDbRecord($i)
                    or next;
                if ($rec->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK)) {
                    push @rbids, $i;
                } else {
                    push @ids, $i;
                }
            }

            if (@ids > 1) {
                ($has_or_have, $this_or_these) = qw/have these/;
                @csids = "$ids[0], ";
                for (1 .. $#ids) {
                    if ($_ % 2) {
                        $csids[-1] .= $ids[$_];
                    } else {
                        push @csids, $ids[-1];
                    }
                    if ($_ < $#ids - 1) {
                        $csids[-1] .= ', ';
                    } elsif ($_ == $#ids - 1) {
                        $csids[-1] .= ' and ';
                    }
                }
            } else {
                ($has_or_have, $this_or_these) = ('has', 'this one');
                @csids = $ids[0];
            }
           
	    alert "WARNING: This change set contains files overlapping with";
	    alert "WARNING: change sets in the staging area:";
            my (@wait, @nowait);
            for my $csid (@ids) {
                my $info = $conflicts->{$csid};
                if ($info->{status} eq STATUS_WAITING) {
                    push @wait, $csid;
                } else {
                    push @nowait, $csid;
                }
                alert sprintf 'WARNING: %s by %s at %s with status %s',
                    $csid, $info->{user},
                    scalar localtime $info->{timestamp},
                    $info->{status};
            }
            alert "WARNING: Your change set will NOT be processed until";
            alert "WARNING: $_" for @csids;
            alert "WARNING: $has_or_have been approved or rolled back.";
            alert "WARNING: If you want your change set to replace $this_or_these, ";
            alert "WARNING: first take the appropriate actions for";
            alert "WARNING: $_" for @csids;
            
            print "\n";
            alert "WARNING: In particular, this means:";
            if (@nowait) {
                while (my @c = splice @nowait, 0, 2) {
                    if (@c == 1) {
                        push @nowait, @c;
                        last;
                    }
                    alert "WARNING: @c";
                }
                my $r = @nowait ? "$nowait[0] " : '';
                alert "WARNING: ${r}will (fully or partially) be overwritten";
                alert "WARNING: by your submission.";
            }
            if (@wait) {
                while (my @c = splice @wait, 0, 2) {
                    if (@c == 1) {
                        push @wait, @c;
                        last;
                    }
                    alert "WARNING: @c";
                }
                my $r = @wait ? "$wait[0] " : '';
                alert "WARNING: ${r}must be approved or rolled back";
                alert "WARNING: before your change set has a chance to get processed.";
            }

            if (@rbids) {
                my ($this, $this_is, $rollback_is);
                if (@rbids > 1) {
                    ($this, $this_is, $rollback_is) = 
                        ('these', 'these are', 'rollbacks are');
                } else {
                    ($this, $this_is, $rollback_is) = 
                        ('this', 'this is', 'rollback is');
                }
                alert "WARNING: Your submission also overlaps with the following";
                alert "WARNING: rollback change sets:";
                alert "WARNING: $_" for @rbids;
                alert "WARNING: Your submission will wait in the staged area until";
                alert "WARNING: $this_is processed. No action is required from your";
                alert "WARNING: side as far as $this $rollback_is concerned.";
            }
            
            return 1 if not $has_tty;

            my $prompt = 
                "Do you want to continue [ (y)es / (n)o / more (d)etails ]?";
            my $ynd = promptForYND($prompt);
            return 0                                        if $ynd eq 'n';
            return more_overlap_info($conflicts, @lroots)   if $ynd eq 'd';
	}
    }

    verbose "changeset passes conflict checks";
    return 1; # OK.
}

# return true if 'run time' restrictions on the CS allow it to proceed.
# - file locks
sub checkFileLocks ($$) {
    my ($changeset,$autoco)=@_;
    my $stage=$changeset->getStage();
    my $user=$changeset->getUser();
    my @autocofiles;

    # phase 0: file locked by other user, or not locked at all
    my $locked=0;
    foreach my $file ($changeset->getFiles) {
	my $ptarget=$file->getProductionTarget();

	my $stagelocn=getLocationOfStage($stage).$FS.$ptarget;
	my $leafname=$file->getLeafName();
	my $stagefile=$stagelocn.$FS.$leafname;
	if (-f $stagefile.",v") {
	    $stagefile=$stagefile.",v";
	} elsif (-f $stagelocn.$FS.'RCS'.$FS.$leafname.",v") {
	    $stagefile=$stagelocn.$FS.'RCS'.$FS.$leafname.",v"
	}

	if ($file->isNew  or  $file->isUnchanged) {
	    # file is new or unchanged - no locking to be done.
        } else {
	    if (my $locker=getFileLock($stagefile)) {
		if ($locker ne $user) {
		    $locked=1;
		    error basename($file)." is already checked out by $locker";
		}
	    } else {
                if ($autoco) {
                    push @autocofiles, $file;
                } else {
		    $locked=1;
		    error "$stagefile ($file) is not locked - ".
		      "checkout before proceeding or use --autoco";
		}
	    }
	}
    }
    return 0 if $locked;

    if (@autocofiles) {
        message("Obtaining locks for files: ",@autocofiles);
	return 0 unless checkoutChangeSet($changeset, @autocofiles);
    }

    verbose "changeset passes file lock checks";
    return 1; # OK.
}

# check out a change set (use by file lock test above in 'autoco' mode)
# Can specify a subset of the changeset by passing in file objects
sub checkoutChangeSet ($;@) {
    my ($changeset, @files) = @_;
    my $stage=$changeset->getStage();
    my $user=$changeset->getUser();

    my $failed=0;
    @files = $changeset->getFiles unless (@files);
    foreach my $file (@files) {
	my $ptarget=$file->getProductionTarget();

	my $stagelocn=getLocationOfStage($stage).$FS.$ptarget;
	my $leafname=$file->getLeafName();
	my $stagefile=$stagelocn.$FS.$leafname;
	if (-f $stagefile.",v") {
	    $stagefile=$stagefile.",v";
	} elsif (-f $stagelocn.$FS.'RCS'.$FS.$leafname.",v") {
	    $stagefile=$stagelocn.$FS.'RCS'.$FS.$leafname.",v"
	}

	if ($file->isNew) {
	    # file is new - no checkout to be done.
	} else {
	    if (setFileLock($stagefile,$file->getSource)) {
		verbose2 "checked out $stagefile ($file)";
	    } else {
		$failed=1;
		error "$stagefile ($file) could not be checked out: $?";
	    }
	}
    }
    return 0 if $failed;

    verbose "changeset checked out";
    return 1; # OK.
}

# open the change database and return a Change::DB object
sub openDB ($) {
    my $path=shift;

    ensure_path(dirname $path);
    my $changedb=new Change::DB($path);
    error("Unable to access $path: $!"), return 0
      unless defined $changedb;

    return $changedb;
}

# duplicate $changeset for lesser movetypes
# for movetype 'move' this is evidently a no-op.
sub generateLesserChangeSets ($$) {
    my ($changeset,$changedb) = @_;

    my $user    = $changeset->getUser();
    my $group   = $changeset->getGroup();
    my $ctime   = $changeset->getCtime();
    my $ticket  = $changeset->getTicket();
    my $stage   = $changeset->getStage();
    my $move    = $changeset->getMoveType();
    my $msg     = $changeset->getMessage();
    my $depends = $changeset->getDependencies();
    my @refs    = $changeset->getReferences();
    my @files   = $changeset->getFiles();

    my @movetypes;
    if ($move eq MOVE_EMERGENCY) {
        push @movetypes, MOVE_BUGFIX, MOVE_REGULAR;
    } elsif ($move eq MOVE_BUGFIX) {
        push @movetypes, MOVE_REGULAR;
    } else {
        # nothing to do
    }

    my @lesser;
    for my $lesser_move (@movetypes) {
        my $cs = $changedb->createChangeSetNoWrite($user,$ticket,$stage,$lesser_move,$msg,
                                                   STATUS_SUBMITTED,
                                                   scalar($changeset->getFiles),
                                                   { %$depends },\@refs);
	$cs->setGroup($group);
	$cs->setCtime($ctime);
        $cs->addFiles(@files);
        my $csid = $cs->getID;
        debug("Lesser changeset (movetype $lesser_move) created with ID '$csid'");
        push @lesser, $cs;
    }

    return @lesser;
}

# write the changeset out
sub writeChanges ($;$$@) {
    my ($changeset,$plugin,$changedb,@lesser)=@_;

    # Fix the dependency: A split changeset
    # has the dependency SIBLING on all other changesets
    # involved in this split

    for my $c ($changeset, @lesser) {
        for my $d (grep $_->getID ne $c->getID, ($changeset, @lesser)) {
            $c->addDependency($d->getID, DEPENDENCY_TYPE_SIBLING);
        }
    }

    # Write them all to the DB
    debug("Adding change set DB record");
    $changedb->addChangeSet($_) for $changeset, @lesser;

    for my $cs ($changeset, @lesser) {
        my $scm_result = postChangeSetSCM($cs);
        if (SCM_SERVER_ENABLED and !$scm_result) {
            fatal "Unable to post change set to SCM: $!";
        }
    }

    my $csid = $changeset->getID;

    # now the changeset exists in the DB, update user and time fields
    $changeset->setTime(scalar localtime);
    debug("Updating status");
    $changeset->setStatus(STATUS_SUBMITTED);

    return $csid;
}

sub changeChangeSetStatus ($$$) {
    my ($csid,$from,$to)=@_;

    my $unlock_token = wrap_safe_nfs_lock($csid);
    my $db=openDB(DBPATH);
    my $rc=$db->transitionChangeSetStatus($csid,$from,$to);
    unless ($rc) {
	alert "NFS error, fail to change status for $csid, retrying";
	$rc = $db->rewriteChangeSet($csid);
    }
    Util::File::NFSLock::safe_nfs_unlock($unlock_token);

    alterChangeSetDbRecordStatus($csid,$to) if $rc;

    return $rc;
}

# transition a recorded change set status from submitted to active
sub makeChangeSetActive ($;$) {
    my ($changeset,$approval)=@_;
    my $to_state = $approval ? STATUS_WAITING : STATUS_ACTIVE;
    my $csid=$changeset->getID();

    return changeChangeSetStatus($csid,STATUS_SUBMITTED,$to_state);
}

sub logChangeSetEvent ($$$) {
    my ($csid,$eventmsg,$opts)=@_;

    # Ignoring NFS issues for the moment, failing to obtain a lock here is
    # not fatal because we are only appending to the log.  We do not want to
    # abort the entire check-in simply because we could not log the ticket
    # creation info.  Issue a warning and continue hoping for POSIX compliant
    # append of log info to event log.
    my $unlock_token;
    eval {
	local $SIG{ALRM} = sub {die "alarm caught; timeout expired\n"};
	alarm($opts->{timeout} || 0);
	$unlock_token = wrap_safe_nfs_lock();
	alarm(0); 1;
    } || (alarm(0), warning("Log event failed (timeout); continuing"));
    #<-all the above is redundant as/when the NFS lock is retired, delete->
    #<-no need to pass in $opts either->

    my $changedb=openDB(DBPATH);
    my $changeset=$changedb->logEvent($csid,$eventmsg);
    Util::File::NFSLock::safe_nfs_unlock($unlock_token) if $unlock_token;
}

sub wrap_safe_nfs_lock (;$) {
    my($csid)= @_;
    my $unlock_token = $csid
      ? Util::File::NFSLock::safe_nfs_lock(DBLOCKFILE,USER.".".$csid)
      : Util::File::NFSLock::safe_nfs_lock(DBLOCKFILE,USER);
    return $unlock_token;
}

#------------------------------------------------------------------------------

sub safe_system (@) {
    my $FH = Symbol::gensym;
    open($FH,'|-',@_) && close($FH);
    return $?;
}

sub redisplayWarnings () {
    my @msgs=grep { /^(\!\!|\?\?)/ } @{Util::Message::retrieve_messages()};
    return unless @msgs;
    alert(scalar(@msgs)." warnings were generated:");
    Util::Message::m_message("$_\n") foreach @msgs;
    alert("Please review these warnings.");
}

#------------------------------------------------------------------------------
# Production services integration

{ my $svc=new Production::Services;

  sub getLockdownStatus () {
       my $rc=Production::Services::Move::getLockdownStatus($svc);
       error $svc->getError() unless defined $rc;

       return $rc; #0==no lockdown, 0!=lockdown of some kind
  }

  sub isBetaDay ($$) {
      my ($changeset,$tasks)=@_;
      my @tasks=map { s/\.tsk$//; $_ } grep $_, split /[^\w.]+/,$tasks;
      my @libs=$changeset->getLibraries();

      my $rc=Production::Services::Move::isBetaDay($svc,@tasks,@libs);
      error $svc->getError() unless defined $rc;

      return $rc;
  }

  sub createChangeSetDbRecord ($) {
      my $changeset=shift;

      my $rc=Production::Services::ChangeSet::createChangeSetDbRecord(
          $svc,$changeset
      ); 
      fatal $svc->getError() unless $rc;

      return $rc;
  }

  sub addDependenciesToChangeSet ($) {
      my $cs = shift;

      my $csid = $cs->getID;
      my $deps = $cs->getDependencies;

      while (my ($on, $type) = each %$deps) {
          Production::Services::ChangeSet::addDependencyToChangeSet(
              $svc, $csid, $on, $type)
              or fatal $svc->getError;
      }
  }

  sub addDeclaredDependencies ($$$) {
      my ($changeset, $type, $deps) = @_;

      for my $id (@$deps) {
          my $cs = getChangeSetDbRecord($id);
          if (not defined $cs) {
              error("Cannot declare dependency on non-existing CS $id.");
              error("Skipping.");
          }
          if ($changeset->getMoveType ne $cs->getMoveType) {
              error("Change set $id has different move type.");
              error("Skipping.");
              next;
          }
          debug("Adding dependency: $id=$type");
          Production::Services::ChangeSet::addDependencyToChangeSet(
                $svc, $changeset->getID, $cs->getID, $type)
              or error("Failed to add dependency $id=$type");
      }
  }

  sub createPrqsEmergencyTicket ($) {
      my $changeset=shift;

      my $rc=Production::Services::ChangeSet::createPrqsEmergencyTicket(
          $svc,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub createPrqsImmediateTicket ($) {
      my $changeset=shift;

      my $rc=Production::Services::ChangeSet::createPrqsImmediateTicket(
          $svc,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub createPrqsProgressTicket ($) {
      my $changeset=shift;

      my $rc=Production::Services::ChangeSet::createPrqsProgressTicket(
          $svc,$changeset
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub areValidTesters ($) {
      my @testers=map { grep $_, split /\W+/,$_ } @_;

      if (@testers > $MAX_TESTERS) {
          error "Maximum number of testers ($MAX_TESTERS) exceeded.";
          return 0;
      }

      my $result=1;
      foreach my $tester (@testers) {
	  my $rc=Production::Services::Move::isValidTester($svc,$tester);
	  error $svc->getError() unless $rc;
	  $result=0 unless $rc;
      };

      return $result;
  }

  sub areValidFunctions ($) {
    return 1 if not defined $_[0];
    my @functions = split /\W+/, $_[0];
    if (@functions > $MAX_FUNCS) {
        error "Maximum number of functions ($MAX_FUNCS) exceeded.";
        return;
    }
    return 1;
  }

  sub areValidTasks ($) {
    return 1 if not defined $_[0];
    my @tasks = grep $_, split /[^\w.]+/, $_[0];
    if (@tasks > $MAX_TASKS) {
        error "Maximum number of tasks ($MAX_TASKS) exceeded.";
        return;
    }
    return 1;
  }

  sub isValidEmergencyApprover ($) {
      my $approver=shift;

      my $rc=
	Production::Services::Move::isValidEmergencyApprover($svc,$approver);
      error $svc->getError() unless $rc;

      return $rc;
  };

  sub isValidImmediateApprover ($) {
      my $approver=shift;

      my $rc=
	Production::Services::Move::isValidImmediateApprover($svc,$approver);
      error $svc->getError() unless $rc;

      return $rc;
  };

  sub isValidProgressApprover ($) {
      my $approver=shift;

      my $rc=
	Production::Services::Move::isValidProgressApprover($svc,$approver);
      error $svc->getError() unless $rc;

      return $rc;
  };

  sub alterChangeSetDbRecordStatus ($$) {
      my ($changeset,$newstatus)=@_;

      my $rc=Production::Services::ChangeSet::alterChangeSetDbRecordStatus(
          $svc,$changeset,$newstatus
      );
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub isValidTicket($) {
      my $ticket=shift;

      my $rc = Production::Services::Ticket::isValidTicket($svc,$ticket);    
      error $svc->getError() unless $rc;

      return $rc;
  }

  sub addTicketNote ($$$) {
      my($changeset,$note, $ticket)=@_;
      my $rc=0;

      if($ticket =~ /^(DRQS)/ ) {
	  $rc=Production::Services::Ticket::addTicketLog(
		  $svc, $changeset->getID(), $changeset->getTicket(), 
		  $changeset->getUser(), $note);
	  error $svc->getError() unless $rc;
      }

      return $rc;
  }

  sub getChangeSetDbRecord {
      my $csid = shift;
      my $cs = Production::Services::ChangeSet::getChangeSetDbRecord($svc, $csid);
      return $cs;
  }

  sub sendManagerCommitMSG {
      my $cs = shift;
      
      my ($rc, $err)= Production::Services::Util::sendManagerCommitMSG($cs);
      if(!$rc) {
	  warning "Failed to send commit message to Manager:$err";
      }
  }
}

#------------------------------------------------------------------------------

MAIN: {
    Util::Message::set_recording(1);

    my $exit_code = EXIT_FAILURE;
    my $opts=getoptions();

    my $interact=new Term::Interact;

    if (my $reason=isInvalidContext) {
	fatal $reason;
    }

    if ($has_tty) {
	verbose("Interactive: yes");
    } else {
	verbose("Interactive: no");
    }

    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);

    my $manager=getPluginManager();
    fatal "Fatal error in plugin_initialize - cannot proceed."
        unless $manager->plugin_initialize($opts);

    if ($opts->{emov} and getLockdownStatus()) {
	my $msg="Lockdown is in effect, emergency moves are restricted";
		
	if(!$has_tty && $opts->{approver}) {
	    my $is_valid_approver=isValidEmergencyApprover($opts->{approver});
	    if(!$is_valid_approver) {
		error $msg;
		fatal "Invalid Approver\n";
	    }
	} elsif (!$has_tty && $opts->{commit}) {
	    $msg = $msg ."\n"."Please run cscheckin interactively!";
	    error $msg;
	    goto FINALIZE;
	} else {
	    warning $msg;
	    if($has_tty) {		
		my $yn=$interact->promptForYN("Do you want to continue (y/n)?");
		goto FINALIZE unless $yn;	
	    }
	}
    }
 
    # Display message of the day (MOTD)
    my $MOTD_displayed = displayBulletin (CSCHECKIN_MOTD, "//")
      if (!$opts->{nocommit});

    # Exit without prompting if non-empty lock file is present/displayed 
    goto FINALIZE if (displayBulletin (CSCHECKIN_LOCK, "!!"));
 
    if (!$opts->{nocommit} && $MOTD_displayed) {
	if ($has_tty) {
	    print STDERR "Please press Enter to continue ... ";
	    <STDIN>;
	}
    }

    # (make sure umask is consistent on files and directories created)
    umask(0002);

    #----- GATHER CHANGE SET FILES

    my ($candidateset,$changeset);
    if ($opts->{from}) {
	# regenerate change set from previously written file
	$candidateset=load Change::Set($opts->{from});
	# Rectify ticket format
	my $ticket  = $candidateset->getTicket();
	if (defined($ticket) && $ticket eq '<no ticket>') {
	    $candidateset->setTicket('');
	} elsif ($ticket) {
	  $ticket=~/^(\D)\D*(\d+)$/
	    or  fatal "Invalid ticket: $ticket";
	  my ($type,$number)=(uc($1),$2);
	  $ticket=(($type eq 'D') ? 'DRQS':'TREQ').$number;
	  fatal "Invalid ticket: $ticket"
	      unless (isValidTicket($ticket));
	  $candidateset->setTicket($ticket);
	}
	my $movetype = $candidateset->getMoveType();
	if ($movetype eq MOVE_EMERGENCY) {
	    $opts->{emov} = 1;
	} elsif ($movetype eq MOVE_BUGFIX) {
	    $opts->{bugf} = 1;
	} 
	# if loading from a file, we will unconditionally accept an unchanged
	# file if it was listed there.
	$opts->{unchanged}=1;
	# prep the identity cache with the previously identified targets
	Change::Identity::deriveTargetfromName($_,$opts->{stage})
	    foreach $candidateset->getTargets();
	message "read change set information from $opts->{from}";
    } elsif ($opts->{reinstate}) {
	#<<<TODO: moved here from csrollback, this feature is under test.
	#<<<TODO: it is here because of approval mechanics and plugin support
	my $csid=$opts->{reinstate};
	$candidateset=getChangeSetDbRecord(uc $csid);
	error("No such change set $csid"),goto FINALIZE
	  unless $candidateset;
	my $status=$candidateset->getStatus();
	error("Change set $csid has status $status and cannot be reinstated"),
	  goto FINALIZE
	    unless ($status eq STATUS_ROLLEDBACK) or ($status eq STATUS_FAILED)
	      or ($status eq STATUS_WITHDRAWN) or ($status eq STATUS_COMPLETE);
	# if loading from a CS, we will unconditionally accept an unchanged
	# file if it was previously in the CS
	$opts->{unchanged}=1;
	$opts->{yes}=1; #if we said 'y' last time we mean it this time too
	# prep the identity cache with the previously identified targets
	Change::Identity::deriveTargetfromName($_,$opts->{stage})
	    foreach $candidateset->getTargets();
	message "retrieved change set information from $csid";
	$opts->{reinstate_from_status}=$status;
	my $movetype = $candidateset->getMoveType();
        if ($movetype eq MOVE_EMERGENCY) {
            $opts->{emov} = 1;
        } elsif ($movetype eq MOVE_BUGFIX) {
            $opts->{bugf} = 1;
        } 
	$opts->{reinstate_from_id}=$csid;
	debug("Reinstated changeset $csid has a message of ".$candidateset->getMessage());
    } else {
	usage("nothing to do!"), goto FINALIZE
	  if (@{$opts->{files}}<1);

	# calculate change set from all candidate files
	$candidateset=parseArgumentsRaw($root,$opts->{stage},
					$opts->{honordeps},$opts->{to},
					@{$opts->{files}});
	$opts->{to} ||= getParsedTrailingLibraryArgument();
    }
    fatal "Fatal error in plugin_pre_find_filter - cannot proceed."
        unless $manager->plugin_pre_find_filter($candidateset);

    # revalidate all components of the CS so no funny business can transpire
    # for example, oddly editied streamed changesets, or strange targets in
    # file maps.
    identifyArguments($root,$opts->{stage},
		      $opts->{honordeps},$opts->{to},$candidateset);

    if (Util::Message::get_debug >=2) {
	my $text=$candidateset->listChanges(1);
	chomp $text;
	debug2 $text;
    }

    my $is_manual_release = getChangeSetManualReleaseState($candidateset);

    # find changes
    $changeset=findChanges($root,$candidateset,
			   $opts->{stage},$opts->{list}||$is_manual_release==1,
			   $opts->{unchanged},$opts->{oldfiles},
			   $opts->{nooldfiles},$opts->{ignoreoldfiles});


    addUnchangedPreFindInc($changeset->getFiles(FILE_IS_UNCHANGED))
        if $opts->{revert};

    $changeset->setTicket($candidateset->getTicket);
    if (my $message=$candidateset->getMessage) {
        if ($message =~ /\n\n/) {
	    my ($reasonheaders, $message) = split(/\n\n/, $message, 2);
	    $changeset->setMessage($message);
	    # strip all existing headers. <<<TODO: parse some headers (reference?)
        }
    }

    # no files - check 1, after pre_find_filter
    unless ($changeset->getFiles) {
	if ($opts->{unchanged}) {
	    error "No elegible files found";
	} else {
	    error "No changed or new files found";
	}
        goto FINALIZE;
    }

    # identify move type
    my $stp_type=getChangeSetStraightThroughState($changeset);
    if ($stp_type>0) {
	
	$changeset->setMoveType(MOVE_IMMEDIATE);
	message "Change set marked for straight-through processing";
	
	if ($opts->{emov} or $opts->{bugf}) {
	    warning "Emergency move and bug fix options do not apply to ".
	      "this change set";
	    delete $opts->{emov};
	    delete $opts->{bugf};
	}
    } else {
	if ($stp_type==0) {
	    warning "Conflicting staging in destinations:";
	    foreach my $library ($changeset->getLibraries) {
		warning "* library '$library' is ".
		  ((isStraightThroughLibrary $library) ?
		   "marked for straight-through processing":"staged normally");
	    }
	    if ($opts->{commit}) {
		error "Change set contains a mixture of straight-through ".
		  "and staged destinations, cannot proceed";
		goto FINALIZE;
	    } else {
		error "Change set contains a mixture of straight-through ".
		  "and staged destinations, would not proceed";
		goto FINALIZE;
	    }
	}

	if ($opts->{emov}) {
	    $changeset->setMoveType(MOVE_EMERGENCY);
	    message "Change set marked for emergency move";
	} elsif ($opts->{bugf} and isBugFixOnly) {
	    #can only create a BF changeset if the BF flag is on
	    $changeset->setMoveType(MOVE_BUGFIX);
	    message "Change set marked for bug fix move to alpha";
	} else {
	    $changeset->setMoveType(MOVE_REGULAR);
	    message "Change set marked for normal staged processing";
	}
    }

    $is_manual_release = getChangeSetManualReleaseState($changeset);
    if ($is_manual_release) {
	if ($is_manual_release > 0) {
	    unless ($changeset->getMoveType() eq MOVE_IMMEDIATE) {
		##<<<TODO: Note that when this changes, other code in
		##  bde_createcs.pl should be updated to support the change, too
		error "Change set marked for manual release currently".
		      "must be configured for straight-through processing";
		goto FINALIZE;
	    }
	}
	else {
	    ## modify tri-state return value to be boolean yes/no manual state
	    $is_manual_release = 0;
	}
    }
    else {
	## getChangeSetManualReleaseState return tri-state and
	## zero (0) indicates error (mixed manual and staged releases)
	warning "Conflicting manual and staged release types for destinations:";
	foreach my $library ($changeset->getLibraries) {
	    warning "* library '$library' is ".
	      (getCachedGroupOrIsolatedPackage($library)->isManualRelease()
		? "marked for manual release"
		: "marked for staged release");
	}
	if ($opts->{commit}) {
	    error "Change set contains a mixture of manual and staged ".
	      "release types -- cscheckin cannot proceed";
	    goto FINALIZE;
	} else {
	    error "Change set contains a mixture of manual and staged ".
	      "release types -- cscheckin would not proceed";
	    goto FINALIZE;
	}
    }

    my $approval=checkApproval($changeset,APPROVELIST);

    { my $approval_plugin;

      # determine if approval is needed, if so if it's optional, and if
      # it's optional whether it was preselected or needs to be asked for.
      # also discriminate 'reject' approval from other conventional kinds.
      if ($approval) {
	  if ($approval->isOptional) {
	      if ($opts->{commit}) {
		  if (defined $opts->{approval}) {
		      if ($opts->{approval}) {
			  if ($approval eq APPROVE_REJECT) {
			      warning "Bypassing configured rejection for ".
				"this change set";
			  } else {
			      message "Optional $approval approval ".
				"chosen for this change set";
			  }
		      } else {
			  if ($approval eq APPROVE_REJECT) {
			      goto FINALIZE if $approval eq APPROVE_REJECT;
			  } else {
			      message "Optional $approval approval ".
				"bypassed for this change set";
			  }
		      }
		  } else {
		      unless ($has_tty) {
			  error "Optional $approval neither chosen nor ".
			    "bypassed for this changeset";
			  goto FINALIZE;
		      }

		      if ($approval eq APPROVE_REJECT) {
			  warning "This change set should be *rejected* ".
			    "according to configured approval criteria";
			  warning "You may choose to bypass this restriction ".
			    "if you are sure of what you are doing";
			  my $yn=$interact->promptForYN(
                              "Bypass configured rejection (y/n)? ");
			  $opts->{approval}=$yn;
		      } else {
			  message "$approval approval optionally applies ".
			    "to this change set";
			  my $yn=$interact->promptForYN(
                               "Apply $approval approval (y/n)? ");
			  $opts->{approval}=$yn;
			  message "$approval approval ".($yn?"chosen":
							 "bypassed");
		      }
		  }

		  $approval=undef unless $opts->{approval};
	      } else {
		  if ($approval eq APPROVE_REJECT) {
		      warning "This change set should be *rejected* ".
			"according to configured approval criteria";
		      warning "You are permitted to bypass this restriction ".
			"if you are sure of what you are doing";
		  } else {
		      message "$approval approval would optionally apply ".
			"to this change set";
		  }
	      }

	  } else {
	      if ($opts->{commit}) {
		  goto FINALIZE if $approval eq APPROVE_REJECT;
		  message "$approval approval applies to this change set";
	      } else {
		  if ($approval eq APPROVE_REJECT) {
		      warning "This change set would be *rejected* according ".
			"to configured approval criteria";
		  } else {
		      message "$approval approval would apply to this ".
			"change set";
		  }
	      }
	  }
      }

      # if approval applies (optional or mandatory) load the plugin
      if ($approval) {
	  $approval_plugin=$manager->loadApprovalPlugin($approval);
	  if (defined $approval_plugin) {
	      fatal "Fatal error in plugin_initialize - cannot proceed."
		  unless $approval_plugin->plugin_initialize($opts);
	  }
	  # not all approval types have a plugin so it is valid for there
	  # to be no plugin loaded here.
      }

      # reject any manually loaded plugins that are automatic and whose
      # criteria for automatic loading weren't satisfied
      foreach my $plugged ($manager->getPlugins) {
	  next if $plugged->plugin_ismanual;
	  next if defined($approval_plugin) and $plugged eq $approval_plugin;
	  fatal "Plugin $plugged is not valid for this change set";
      }
    } # end approval closure

    if ($opts->{checkin} and not $opts->{machine}) {
	print "The following files have been identified for processing:\n",
	  $changeset->listFiles($opts->{pretty});
    };
    $changeset->setUser(USER);
    $changeset->setGroup(GROUP);
    
    markAsReverted($changeset) if $opts->{revert};

    fatal "Fatal error in plugin post-find filter - cannot proceed."
      unless $manager->plugin_post_find_filter($changeset);

    # no files - check 2, after post_find_filter
    unless ($changeset->getFiles) {
	if ($opts->{unchanged}) {
	    error "No elegible files found";
	} else {
	    error "No changed or new files found";
	}
        goto FINALIZE;
    }

    if ($changeset->getFiles > $MAX_FILES) {
        error "Maximum number of files ($MAX_FILES) exceeded.";
        goto FINALIZE;
    }

    if (Util::Message::get_debug >=2) {
	my $text=$changeset->listFiles();
	chomp $text;
	debug2 "change set:$text",$changeset->listFiles(1);
    }

    # if just listing, just list the detected changes out
    unless ($opts->{commit}) {
	if ($opts->{pretty} and $opts->{list}) {
	    print "Listing calculated changes only (no commit)\n";
	}

	$changeset->setMessage($opts->{message}) if $opts->{message};
	$changeset->setTicket("DRQS".$opts->{drqs}) if $opts->{drqs};
	$changeset->setTicket("TREQ".$opts->{treq}) if $opts->{treq};
       	print $changeset->listChanges($opts->{pretty});
	if ($opts->{difference}) {
	    if (generateDifferenceReport $changeset,$opts->{difference}) {
		print "Generated difference report to $opts->{difference}\n";
	    } else {
		warning "Difference report generation failed: skipped\n";
	    }
	}
	$exit_code = EXIT_SUCCESS,goto FINALIZE if $opts->{list};
	#go forward if -n
    }

    #-----

    # lock check: 1 of 2 (prevalidation)
    if ($opts->{commit}) {
	# Exit if a unit of release is 'blocked' by Group 412
	if (my %locks=checkMaintenanceLocks($changeset)) {
	    error "Maintenance locks are in effect for:";
	    error "  ".join(",",sort keys %locks);
	    foreach my $uor (sort keys %locks) {
		error "$uor: $_" foreach split /\n/,$locks{$uor};
	    }
	    error "Please try later";
	    goto FINALIZE;
	}
	# Exit if the sweep lock is in effect
	if (isSweepLocked) {
	    error "Sweep lock is in effect, please try later";
	    goto FINALIZE;
	}
    } else {
	# Warn if a unit of release is 'blocked' by Group 412
	if (my %locks=checkMaintenanceLocks($changeset)) {
	    warning "Maintenance locks are in effect for:";
	    warning "  ".join(",",sort keys %locks);
	    foreach my $uor (sort keys %locks) {
		error "$uor: $_" foreach split /\n/,$locks{$uor};
	    }
	}
	# Warn if the sweep lock is in effect
	if (isSweepLocked) {
	    warning "Sweep lock is in effect";
	}
    }

    #-----

    fatal "Fatal error in plugin_pre_change - cannot proceed."
        unless $manager->plugin_pre_change($changeset);

    #----- VERIFY

    # verify 1a - check to see if we're ok. Don't lock while prompting!
    unless (verifyChanges($changeset,$is_manual_release)) {
	error ($opts->{commit} ? "Commit failed (verify)"
			       : "Commit would fail (verify)");
	goto FINALIZE;
    }

    # if verifying but not committing, carry out local binary tests, then exit

    unless ($opts->{commit}) {
	my $tmpfile=new File::Temp(TEMPLATE => "cscompile.".USER.".XXXXXX",
				   SUFFIX   => ".cs",
				   DIR      => CSCOMPILE_TMP,
				   UNLINK   => Util::Message::get_debug?0:1);
	fatal "Unable to create temporary file $tmpfile: $!" unless $tmpfile;

	print $tmpfile $changeset->listChanges(0);
        my @cmd = (CSCOMPILE,"-Z","--do=binary");
        push @cmd, "gcc-ansi" if $opts->{"gcc-ansi"};
        push @cmd, "-W" if $opts->{Werror};
        push @cmd, "--nogccwarnings"
	  if (defined($opts->{gccwarnings}) && !$opts->{gccwarnings});
        push @cmd, "--bypassGCCwarnings" if $opts->{bypassGCCwarnings};
	push @cmd, "-f",$tmpfile;

        debug("invoking: @cmd");
        push @cmd, "-t", $opts->{to} if $opts->{to};
        push @cmd, "-" . "d" x $opts->{debug} if $opts->{debug};
        push @cmd, "-" . "v" x $opts->{verbose} if $opts->{verbose};
	#<<<TODO: should pass the --emov/--bf flag so cscompile knows which
	#<<<TODO: branch to test-compile against.
	my $result = 0;
 	$result=safe_system(@cmd) unless ($is_manual_release);
	debug "streamed candidate set file left at $tmpfile"; #only if debug
	if ($result!=0) {
	    error("Commit would fail (compile)");
	    goto FINALIZE;
	} else {
	    unless (checkFileLocks($changeset,0)) {
		unless ($opts->{autoco}) {
		    error ("Commit would fail (locks)");
		    goto FINALIZE;
		}
	    }
	    message("Commit would succeed");
	}
	$exit_code = EXIT_SUCCESS,goto FINALIZE;
    }

    # verify 1b - 'run time' restrictions - conflicts
    unless (checkConflicts $changeset) {
	error ($opts->{commit} ? "Commit failed (conflict)"
			       : "Commit would fail (conflict)");
	goto FINALIZE;
    }
    # verify 1c - 'run time' restrictions - locks
    unless (checkFileLocks($changeset,$opts->{autoco})) {
	error ($opts->{commit} ? "Commit failed (locks)"
			       : "Commit would fail (locks)");
	goto FINALIZE;
    }

    #----- GATHER REQUIRED INFORMATION

    # new file confirmation
    unless ($opts->{yes}) {
	my @new=grep { $_->isNew() } $changeset->getFiles();
	if (@new && $has_tty) {
	    message "New file:",basename($_),"(".$_->getTarget.")"
	      foreach @new;
	    my $yn=$interact->promptForYN(scalar(@new)." new file".
					  ((@new==1) ? "":"s").
					  " will be created - ".
					  "proceed (y/n)? ");
	    goto FINALIZE unless $yn;
	}
	elsif (@new) {
	    error("New files are in this change set and --yestonew flag ".
		  "was not provided, so manual confirmation is needed to ".
		  "continue, but terminal is not interactive.  Exiting.");
	    goto FINALIZE;
	}
    }

    # gather any unspecified info required - bug fix?
    if (isBugFixOnly and not
	($changeset->isImmediateMove or $changeset->isEmergencyMove)) {
	my $isbf=0;
	if (defined $opts->{bugf}) {
	    $isbf = $opts->{bugf} ? 1 : 0;
	    message "Change is ".($isbf?"":"not ")."a bug fix move to alpha";
	} elsif ($has_tty) {
	    $interact->printOut("Change set propagation is currently limited ".
	      "to bug fix moves to alpha.\n");
	    my $yn=$interact->promptForYN
	      ("Is this a bug fix move to alpha (y/n)? ");
	    $isbf = $yn ? 1 : 0;
	    # this flag controls setForBugFix at commit time
	} else {
	    error("Bug fix move status of this change is unknown, ".
		  "and bug fix restrictions are in effect");
	    goto FINALIZE;
	}
	$changeset->setMoveType(MOVE_BUGFIX) if $isbf;
    }

    # bug fix/emov new/changed file policy
    if ($changeset->isBugFixMove() or $changeset->isEmergencyMove()) {
	my ($new,$changed)=(0,0);
	foreach my $file ($changeset->getFiles()) {
	    unless ($file=~/\.(inc|h)$/){
		$new++,next if $file->isNew();
	    }
	    $changed++ if $file->isChanged();
	}
	if (not ENVIRONMENT_IS_TEST and $new and not $changed) {
	    error ("Cannot commit a new file as a ".
		   ($changeset->isEmergencyMove?"emergency":"bug fix")." move".
		   " without at least one changed file in the change set");
	    goto FINALIZE;
	}

	if ($new) {
	alert "* This change set contains one or more new file submitted for";
        alert "* a bug fix or emergency move. Once the change set has been";
        alert "* submitted, please file a DRQS OU citing the change set ID";
        alert "* to group 55 to have these new files handled.";
        alert "* Failure to do so may cause your changes to be WITHDRAWN.";
        }
    }

    fatal "Fatal error in plugin_early_interaction - cannot proceed."
        unless $manager->plugin_early_interaction($opts,$interact);

    # gather any unspecified info required - ticket
    my $ticket=$changeset->getTicket();
    if ((not $ticket) or defined $opts->{drqs} or defined $opts->{treq}) {
	if (defined $opts->{drqs}) {	  
	    $ticket="DRQS".$opts->{drqs};	    
	    fatal "Invalid DRQS ticket" 
		unless ( isValidTicket($ticket) || 
			$opts->{drqs} =~/^(0+)$/);		
	} elsif (defined $opts->{treq}) {
	    $ticket="TREQ".$opts->{treq};
	    fatal "Invalid TREQ ticket" 
		unless ( isValidTicket($ticket) ||
			 $opts->{treq} =~/^(0+)$/);
	} elsif ($has_tty) {
            if ($changeset->isEmergencyMove) {
                warning "This change set is an emergency move. ".
                  "A DRQS should be entered in nearly all cases.";
                warning "Entering a TREQ may cause this changeset ".
                  "to be withdrawn.";
            }
	    $interact->printOut("Please enter a DRQS or TREQ ticket number, ".
	      "e.g. 'd1234567' or 't999001'.\n");
	    do {
		$ticket=
		    $interact->promptForSingle("Ticket: ",
				     q[^(?i)(d(rqs)?|t(req)?)\d{6,7}$]);
		$ticket=~/^(\D)\D*(\d+)$/;
		my ($type,$number)=(uc($1),$2);
	        $ticket=(($type eq 'D') ? 'DRQS':'TREQ').$number;
	    } until (isValidTicket($ticket));
	} else {
	    error("No ticket supplied and not interactive");
	    goto FINALIZE;
	}
	$changeset->setTicket($ticket);
    }

    # Headers: this info is prepended to the message reason, from where it
    # may be parsed out. The top of the message reason is therefore
    # somewhat like an HTTP or Email header.

    # Function header - mandatory for EMOV, optional otherwise
    if ($opts->{functions}) {
        goto FINALIZE if not areValidFunctions($opts->{functions});
    } elsif ($changeset->isEmergencyMove) {
	if ($has_tty) {
            my $funcs;
            do {
                $funcs = $interact->promptForSingle("Functions affected by this EMOV: ")
            } until areValidFunctions($funcs);
	    $opts->{functions} = $funcs; 
	} elsif ($opts->{emov}) {
	    error "Emergency move has no specified impacted functions";
	    goto FINALIZE;
	}
    }

    # Task header - mandatory for EMOV, optional otherwise
    if ($opts->{tasks}) {
        goto FINALIZE if not areValidTasks($opts->{tasks});
    } elsif ($changeset->isEmergencyMove) {
	if ($has_tty) {
            my $tasks;
            do {
                $tasks = $interact->promptForSingle("Tasks to relink for this EMOV (none, if none): ")
            } until areValidTasks($tasks);
	    $opts->{tasks} = $tasks;
            if (not $opts->{tasks}) {
                $opts->{tasks} = 'none';
            } else {
	        $opts->{tasks} = join " ", grep $_, split /[^\w.]+/, $opts->{tasks};
            }
	} else {
	    error "Emergency move has no specified tasks to relink";
	    goto FINALIZE;
	}

	# special cases - tasks that are implied by targets
	# 1 - mlfiles
	if ($changeset->hasTarget("mlfiles")) {
	    unless ($opts->{tasks}=~/\bbig95(\.tsk)?\b/i) {
		$opts->{tasks}.=" big95";
		warning "mlfiles target detected -- added 'big95' to tasks";
                goto FINALIZE if not areValidTasks($opts->{tasks});
	    }
	}
	# 2 - any gtk library
	my $gtk=0;
	foreach my $file ($changeset->getFiles) {
	    $gtk=1, last if $file->getProductionLibrary=~/^gtk/;
	}
	if ($gtk) {
	    unless ($opts->{tasks}=~/\bgtk\b/i) {
		warning "GTK library detected -- added 'gtk' to tasks";
		$opts->{tasks}.=" gtk";
                goto FINALIZE if not areValidTasks($opts->{tasks});
	    }
	}

        if (grep($_, split(/[^\w.]+/, $opts->{tasks})) > $MAX_TASKS) {
            error "Maximum number of tasks ($MAX_TASKS) exceeded.";
            goto RETRY;
        }
    }

   # this is because of DRQS 6443103
    if (defined $opts->{beta} and !$changeset->isEmergencyMove) {
	warning "--beta/-B option has no effect unless used with --emov/-e.";
    }	

    # determine whether or not an emov is beta-only or all-production
    if ($changeset->isEmergencyMove) {
	if (not isBetaDay($changeset,$opts->{tasks})) {
	    $opts->{stage} = STAGE_PRODUCTION;
	    if ($opts->{beta}) {
		error "This EMOV can move to production only - ".
		  "cannot deploy to beta machines only";
		goto FINALIZE;
	    }
	} elsif (defined $opts->{beta}) {
	    $opts->{stage} = $opts->{beta} ? STAGE_BETA : STAGE_PRODUCTION;
	} elsif ($has_tty) {
	    my $pb=$interact->promptForSingle(
	      "Should this EMOV move to production, or ".
		"only beta machines? (p/b): ", q/^[pb]/);
	    my $yn=($pb=~/^b/i)?1:0; #beta->y, production->n
	    $opts->{stage} = $yn ? STAGE_BETA : STAGE_PRODUCTION;
	} else {
	    error "Beta conditions apply and EMOV beta status not specified";
	    goto FINALIZE;
	}
	$changeset->setStage($opts->{stage});
	message "Emergency move marked for ".(($opts->{stage} eq STAGE_BETA)
					      ? "beta" : "production");
    }

    # Tester header - mandatory for EMOV, optional otherwise
    if ($opts->{testers}) {
	fatal "Invalid testers" unless areValidTesters($opts->{testers});
    } elsif ($changeset->isEmergencyMove) {
	if ($has_tty) {
	    $interact->printOut("Enter the login names or UUIDs ".
	      "for one or two testers.\n");
	    do {
		$opts->{testers} =
		  $interact->promptForSingle("Tester(s) for this EMOV: ");
		# As for --tester above.
		$opts->{testers} = join(' ' => grep $_, split(/\W+/ , $opts->{testers}));
	    } until (areValidTesters($opts->{testers}));
	} else {
	    error "Emergency move has no specified tester";
	    goto FINALIZE;
	}
    }

    # Approver header - mandatory for EMOV and STP, optional otherwise
    my $is_stp=($changeset->isImmediateMove) ? 1 : 0;
    my @tars = $changeset->getLibraries();
    my $is_pg = isProgressLibrary($tars[0]);
    if ($opts->{approver}) {
	fatal "Invalid approver" unless
	  $is_stp ? ($is_pg ? isValidProgressApprover($opts->{approver})
		     : isValidImmediateApprover($opts->{approver}))
	    : isValidEmergencyApprover($opts->{approver});
    } elsif ($changeset->isEmergencyMove or $is_stp) {
	if ($has_tty) {	    
	    $interact->printOut("Enter the login name or UUID ".
	      "for the approver.\n");
	    do {
		$opts->{approver} =
		  $interact->promptForSingle("Approver for this ".
					     ($is_stp?"immediate":"emergency").
					     " move: ");
		$opts->{approver} = join " ", grep $_, 
		                    split /\W+/, $opts->{approver}
		if $opts->{approver};
	    } until ($is_stp ? ($is_pg ? isValidProgressApprover($opts->{approver})
				: isValidImmediateApprover($opts->{approver}))
		     : isValidEmergencyApprover($opts->{approver}));
	} else {
	    error(($is_stp ? "Immediate":"Emergency").
		  " move has no specified approver");
	    goto FINALIZE;
	}
    }

    fatal "Fatal error in plugin_late_interaction - cannot proceed."
        unless $manager->plugin_late_interaction($opts,$interact);

    # gather any unspecified info required - message
    if ($opts->{message} and length($opts->{message})) {
	# supplied on command line
    } elsif (my $message=$changeset->getMessage) {
	# not supplied but a previous msg (--from or --reinstate) supplied
	$opts->{message}=$message;
    } elsif ($has_tty) {
	# no message and interactive, so ask for one
	while (1) {
	    $interact->printOut("Please enter a description ".
	      "for this change (Max length: 255).\n");
	    $opts->{message}=
	      $interact->promptForMultipleMax("Message ('.' to end): ", 255);
	    last unless $opts->{message} =~ /$BADREASON_RE/o;
	    error "Invalid description - please try again.";
	}
    } else {
	# no message and not interactive, so bail
	error("No message supplied and not interactive");
	goto FINALIZE;
    }

    # Note the references.
    if (defined $opts->{reference}) {
        my (@references) = split(',', $opts->{reference});
        $changeset->addReferences(@references);
    }

    # assemble additional headers into message, if any are in effect
    # tasks, functions, testers, approver and reference
    if ($opts->{functions} or $opts->{tasks} or $opts->{testers}
       or $opts->{approver} or $opts->{reinstate_from_id}) {
	$opts->{message}="\n".$opts->{message}; # blank line separator

	$opts->{functions}=join "\n",map { HEADER_FUNCTION.": $_" }
	   grep $_, split /\W+/, $opts->{functions} 
	if $opts->{functions};
	$opts->{tasks}=join "\n",map { HEADER_TASK.": $_" }
	  grep $_, split /[^\w.]/,$opts->{tasks}
	if $opts->{tasks};
	$opts->{testers}=join "\n",map { HEADER_TESTER.": $_" }
	  grep $_, split /\W+/,$opts->{testers} if $opts->{testers};
	$opts->{approver}=join "\n",map { HEADER_APPROVER.": $_" }
	  grep $_, split /\W+/,$opts->{approver} if $opts->{approver};
	$opts->{reinstate_from_id}=HEADER_ORIGINAL_ID.": ".
	  $opts->{reinstate_from_id}
	    if $opts->{reinstate_from_id};

	foreach my $header (qw[tasks functions testers approver
			      reinstate_from_id]) {
	    $opts->{message} =
	      $opts->{$header}."\n".$opts->{message} if $opts->{$header};
	}
    }

    # place the post-processed message into the CS instance
    $changeset->setMessage($opts->{message});

    #---- COMMIT CHANGE SET

    # lock check: 2 of 2 (postvalidation)
    # Exit if a unit of release is 'blocked' by Group 412
    if (my @uors=checkMaintenanceLocks($changeset)) {
	error "Maintenance locks are in effect for @uors, ".
	  "please try later";
	goto FINALIZE;
    }
    # Exit if the sweep lock is in effect
    if (isSweepLocked()) {
	error "Sweep lock is in effect, please try later";
	goto FINALIZE;
    }

    alert "Committing change set for $ticket..." if $has_tty;

    # proceed with change
    ensure_path(dirname DBPATH);

    Util::File::NFSLock::safe_nfs_signal_traps(); #graceful under SIGINT
    my ($intsig,$termsig,$hupsig, $tstpsig)=($SIG{INT},$SIG{TERM},$SIG{HUP},$SIG{TSTP});
    ($SIG{INT},$SIG{TERM},$SIG{HUP},$SIG{TSTP})=('IGNORE','IGNORE','IGNORE','IGNORE');
    my $unlock_token;
    eval {
	local $SIG{ALRM} = sub {die "alarm caught; timeout expired\n"};
	alarm($opts->{timeout} || 0);
	$unlock_token = wrap_safe_nfs_lock();
	alarm(0); 1;
    } || (alarm(0), error("Commit failed (timeout)"), goto FINALIZE);
## GPS: catch signals INT, TERM, HUP when going out to production instead
##	of ignoring them and allow ourselves to be interrupted (exit gracefully
##	with a rollback (gets more complicated when ticket deletes come into
##	play)

    # verify 2 - verify 'run time' restrictions a second time after getting
    # the lock, just in case someone beat us in
    # verify 2b - 'run time' restrictions - conflicts
    unless (checkConflicts($changeset,1)) {
	error "Commit failed (conflict2)";
	goto FINALIZE;
    }
    # verify 2c - 'run time' restrictions - locks
    unless (checkFileLocks($changeset,0)) {
	error "Commit failed (locks2)";
	goto FINALIZE;
    }

    my $csid;
    my $do_rollback = 0;
    my @lesser_changesets = ();
    eval {
	local $SIG{ALRM} = sub {die "alarm caught; timeout expired\n"};
	alarm($opts->{timeout} || 0);

        # changeset is fine, however doesn't have ID nor time
	debug("Creating CSID");
        $changeset->setID(Change::DB->_generateChangeSetID(USER));
        $changeset->setTime(scalar localtime);

        my $changedb = openDB(DBPATH);
	if (SCM_BRANCHING_ENABLED) {
	  debug("Creating sibling change sets");
	  @lesser_changesets = generateLesserChangeSets($changeset,$changedb);
	}

        # in the presence of --revert, turn any UNCHANGED file into REVERTED
        markAsReverted($changeset, @lesser_changesets)
            if $opts->{revert};

	debug("Writing changes");
	$csid=writeChanges($changeset,$manager,$changedb,@lesser_changesets);

	# write to production database
	debug("Writing CSDB");
	createChangeSetDbRecord($changeset);
        createChangeSetDbRecord($_) for @lesser_changesets;
        addDependenciesToChangeSet($_) for $changeset, @lesser_changesets;

        addDeclaredDependencies($changeset, DEPENDENCY_TYPE_DEPENDENT,
                                            $opts->{dependent});
        addDeclaredDependencies($changeset, DEPENDENCY_TYPE_CONTINGENT,
                                            $opts->{contingent});
        addDeclaredDependencies($changeset, DEPENDENCY_TYPE_NONE, 
                                            $opts->{independent});
	alarm(0); 1;
    } || ((error "$@"), alarm(0), $do_rollback = 2); # release lock below, then act on errors
    Util::File::NFSLock::safe_nfs_unlock($unlock_token);
    goto EXIT_CHECK unless ($csid && !$do_rollback);

    if ($has_tty) {
        alert "Change set $csid submitted";
	# Enable w/ verbose?
        #print $changeset->listChanges($opts->{pretty});
        if (SCM_BRANCHING_ENABLED and @lesser_changesets) {
            alert "Changesets of lower priority movetype have been generated:";
            for (@lesser_changesets) {
                my $id = $_->getID;
                my $move = $_->getMoveType;
                alert "  $id ($move)";
            }
        }
    }

    #--- this code will move to the daemon later ---#
    #--- (which is why it bases off the CSID after commit) ---#
    my $tmpfile=new File::Temp(TEMPLATE => "cscompile.".USER.".XXXXXX",
			       SUFFIX   => ".cs",
			       DIR      => CSCOMPILE_TMP,
			       UNLINK   => Util::Message::get_debug?0:1);
    fatal "Unable to create temporary file $tmpfile: $!" unless $tmpfile;
    my $tmpdir=$tmpfile;
    $tmpdir=~s/\.cs$/.files/;
    ensure_path($tmpdir);
    installFilesTo($changeset, $tmpdir);
    my $csdesc=$changeset->listChanges(0);
    $csdesc=~s{to=${\CHECKIN_ROOT}}{to=$tmpdir}smg;
    #<<<PRANG $csdesc
    print $tmpfile $csdesc
	or  fatal "Unable to write temporary file $tmpfile: $!";
    close $tmpfile
	or  fatal "Unable to close temporary file $tmpfile: $!";

    my @cmd = (CSCOMPILE,"-Z","--do=binary","-f",$tmpfile);
    push @cmd, "gcc-ansi" if $opts->{"gcc-ansi"};
    push @cmd, "-t", $opts->{to} if $opts->{to};
    push @cmd, "-W" if $opts->{Werror};
    push @cmd, "--nogccwarnings"
      if (defined($opts->{gccwarnings}) && !$opts->{gccwarnings});
    push @cmd, "--bypassGCCwarnings" if $opts->{bypassGCCwarnings};
    push @cmd, "-" . "d" x $opts->{debug} if $opts->{debug};
    push @cmd, "-" . "v" x $opts->{verbose} if $opts->{verbose};
    debug("@cmd");

    if (!$is_manual_release) {
        local $SIG{INT} = \&ctrlCsigHandler;
        $do_rollback = safe_system(@cmd) != 0;
    }
    else {
	$? = 0;
    }

    ##  check if CSCOMPILE is killed by SIGINT (2)
    if ($? && (($? & 127) == 2)) {
       $ctrlCcaught = 1;   #  SIGINT-caught
       $do_rollback = 3;   #  SIGINT-caused rollback
       error "CTRL-C caught;   process aborted\n";
       goto EXIT_CHECK;
    }

    if($do_rollback) {
	error "cscompile returned non-zero rcode";
	goto EXIT_CHECK;
    }

    # debug mode for testing submitted to active state transition
    my $delay=DEBUG_ACTIVATION_DELAY;
    if ($delay > 0) {
	message "Entering activation delay ($delay seconds)...";
	sleep $delay;
	message "...leaving activation delay, proceeding";
    }

    ## GPS: revisit program flow.  Shouldn't installScripts or do bugfix
    ## until after all tickets created; move down.  We really want to
    ## update the change set status, create tickets, and log all within
    ## a single lock, but talking to production might take too long.
    ## (added return status check and rollback for BREG checkins, which
    ##  will use the timeout flag when trying to update the database)
    ## (Program flow throught bde_createcs.pl needs to be arranged for
    ##  better recovery when errors occur.  For now, the following will
    ##  suffice for the way that BREG uses cscheckin, but is not a
    ##  general solution.)

    # change status in DB
    my $rc_cs;
    eval {
	local $SIG{ALRM} = sub {die "alarm caught; timeout expired\n"};
	alarm($opts->{timeout} || 0);
	$rc_cs=makeChangeSetActive($changeset,$approval);
        
        if ($rc_cs  and  @lesser_changesets) {
            for my $lesser (@lesser_changesets) {
                my $ok = makeChangeSetActive($lesser,$approval);
                $rc_cs = 0 if not $ok;
            }
        }
	alarm(0); 1;
    } || (alarm(0), $do_rollback = 2, goto EXIT_CHECK);
    unless ($rc_cs) {
	$do_rollback = 1;
	error "makeChangeSetActive failed";
	goto EXIT_CHECK;
    }

    if ($opts->{reinstate}) {
	changeChangeSetStatus($opts->{reinstate},
			      $opts->{reinstate_from_status}
			      => STATUS_REINSTATED);
    }

    #--- install locally

    # 1 - the old /bbsrc/checkin location
    debug("Installing files");
    # install scripts if SCM_CHECKINROOT_ENABLED=1
    # or is STP (but not "manual release")
    if (SCM_CHECKINROOT_ENABLED
	  or  ($changeset->isImmediateMove() &&
	       !$is_manual_release &&
	       !$is_pg)
	  or  $changeset->isBregMove()) {
	installFiles($changeset,$copy_to_cbld);
	unless ($approval) {
	    installScripts($changeset,$copy_to_cbld)
	}
    }

    # 2 - The SCM 'backup' location
    { my $SCMmove=$changeset->getMoveType();
      my $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_REGULAR;
      if ($SCMmove eq MOVE_BUGFIX) {
	  $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_BUGFIX;
      } elsif ($SCMmove eq MOVE_EMERGENCY) {
	  $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_EMERGENCY;
      } elsif ($SCMmove eq MOVE_IMMEDIATE) {
	  $SCMdestloc=CSCHECKIN_STAGED."/".MOVE_IMMEDIATE;
      }

      installFilesTo($changeset, $SCMdestloc);
      my $user  = $changeset->getUser();
      my $ticket= $changeset->getTicket();
      my $stage = $changeset->getStage();
      my $move  = $changeset->getMoveType();
      my $msg   = $changeset->getMessage();
      my $csid  = $changeset->getID();
      my $grp	  = $changeset->getGroup() || GROUP;

      foreach my $file ($changeset->getFiles) {
          my $leafname=$file->getLeafName();
          my $destfile=$SCMdestloc.'/'.basename($file->getDestination());
          my $touchfile=$destfile;
          # create checkin script
          my $_file = $file->clone;
          # FIXME: what is the correct path?
          $_file->setDestination("/bbsrc/checkin/$leafname");
          debug "installScript($file,$user,$grp,$ticket,$stage," . 
      	  "$move,$csid,$destfile.checkin.sh)";
          installScript($_file,$user,$grp,$ticket,$stage,$move,
      		  $csid,"$destfile.checkin.sh");
          system('/usr/bin/touch','-r',$touchfile,"$destfile.checkin.sh");
      }
    }


    #----

    if ($changeset->isBugFixMove and not $approval) {
	setForBugFix($changeset); # append to bugfix logfiles
    }


    # Generate diff report and copy it to local location if
    # requested.  This happens before any PRQS ticket is created so 
    # that the diff report can be referenced in the PRQS ticket.
    my $diffreport=CS_DIFFREPORT_DIR.'/'.$csid.".diff.html";
    if (generateDifferenceReport $changeset,$diffreport) {
	if ($opts->{difference}) {
	    message "Generated difference report to $diffreport";
	    unless (copy $diffreport => $opts->{difference}) {
		warning "Failed to copy difference report to ".
		  "$opts->{difference}: $!";
	    } else {
		message "Local copy of difference report written to ".
		  $opts->{difference};
	    }
	}
    } else {
	warning "Difference report generation failed: skipped";
    }


    if ($changeset->isImmediateMove and not $approval) {
	# changeset targets should be either all Immediate target 
	# or all progress target now, so only check one
        # target is sufficient here 
	my @Libraries = $changeset->getLibraries;
	if(isProgressLibrary $Libraries[0] ) {
	    my $ticket=createPrqsProgressTicket($changeset);
	    logChangeSetEvent($csid,"PRQS $ticket (PG) created",$opts);
	    if($ticket) {
		message "Created PRQS $ticket (PG) for change set $csid";
	    } else {
		warning "PRQS PG ticket is not created.";
		warning "Please contact SI Build team for assistance.";
	    }
	} else {
	    my $ticket=createPrqsImmediateTicket($changeset);
	    logChangeSetEvent($csid,"PRQS $ticket (ST) created",$opts);
	    if($ticket) {
		message "Created PRQS $ticket (ST) for change set $csid";
	    } else {
		warning "PRQS ST ticket is not created.";
		warning "Please contact SI Build team for assistance.";
	    }
	}
    } elsif (not $approval) {
	# only create these if no approval is to take place
	# otherwise, csalter or csapprove will create them later
	if ($changeset->isEmergencyMove) {
	    my $ticket=createPrqsEmergencyTicket($changeset);
	    logChangeSetEvent($csid,"PRQS $ticket (EM) created",$opts);
	    message "Created PRQS $ticket (EM) for change set $csid";
	}
    }

    if ($has_tty) {
	# this is because of drqs 6441511
	unless ($rc_cs) {
	    alert "Development database not updated with the status.";
	}
	if ($approval) {
	    alert "Change set $csid committed ".
	      "and waiting for $approval approval";
	} else {
	    alert "Change set $csid committed";
	}
	my $ticket = $changeset->getTicket();
	if ($changeset->isEmergencyMove and $ticket =~ /^TREQ/) {
	    alert "Change set $csid is an emergency move. ".
	      "associated with $ticket.";
	    alert "Because this changeset is associated with a TREQ ".
	      "it may be withdrawn.";
	}
    } else {
	print $csid; #return just the number if not interactive
    }

    unless ($manager->plugin_post_change_success($changeset)) {
	error "Error encountered in plugin post-change success";
	warning "Your change set completed processing successfully, but";
	warning "a plugin encountered an error in post-processing.";
	warning "Please contact SI Build team for assistance.";
    }

    {
	my $ticket = $changeset->getTicket();
		
	if($ticket =~/^DRQS/) {
	    if($opts->{note}) {
		addTicketNote($changeset,  $opts->{note}, $ticket);
	    } else {
		my $note = "created.";
		addTicketNote($changeset,  $note, $ticket);
	    }
	}
    }


    if ($has_tty) {
	# redisplay really important stuff
	$changeset->listChanges(1);
	redisplayWarnings();
    }
    

EXIT_CHECK:
    ##  ignore SIGINT.   Reasons:
    ##  1. at this point, the remaining steps are not time-consuming
    ##  2. avoid potential race condition: after CS has been enqueued,
    ##     if SIGINT arrives, we may end up setting the 'R' status but
    ##     the CS has already been enqueued
    $SIG{INT} = 'IGNORE';

    if ($csid  and  !$do_rollback) {
        for my $cs ($changeset, @lesser_changesets) {
            my $scm_result = enqueueChangeSetSCM($cs);
            if (SCM_SERVER_ENABLED  and  !$scm_result) {
                $do_rollback = 1;
                last;
            }
        }

        sendManagerCommitMSG($changeset) unless $do_rollback;
    }

    if (!defined $csid) {
	error "Commit failed (csid)";
    } elsif ($do_rollback) {
	error("Error: $@") if $do_rollback == 2;
	#<<<TODO: finish abstracting rollback logic so this can
	#<<<TODO: done without invoking an external tool
	my $status_to_rollback=$changeset->getStatus();
	my $result=changeChangeSetStatus($csid,$status_to_rollback,
					STATUS_ROLLEDBACK);
	# Remove the added/removed symbol files for the changeset.
	remove_symbol_changes($changeset, $csid);

	$result
	  ? error("Commit rolled back")
	  : error("Failed to roll commit back!  Please contact SI Build team");
	fatal "Fatal error in plugin_post_change_failure - cannot proceed."
	    unless $manager->plugin_post_change_failure($changeset);
	undef $csid;
	#--- this code will move to the daemon later ---#
    } else {
        # Right, no rolling back. Apply the object set data
        my (@setfiles, $movetype);
	$movetype = $changeset->getMoveType();
	@setfiles = glob(COMPCHECK_DIR."/$movetype/$csid/object.set.*.symbols");
	# Work with the case where maybe there are no set files. Odd,
	# but worth compensating for.
	if (@setfiles) {
	  system("$FindBin::Bin/bde_inject_changeset.pl", @setfiles);
	}
      }

    $exit_code = $csid ? EXIT_SUCCESS : EXIT_FAILURE;

FINALIZE:
    fatal "Fatal error in plugin_finalize - cannot proceed."
	    unless $manager->plugin_finalize($opts,$exit_code);

    #($SIG{INT},$SIG{TERM},$SIG{HUP})=($intsig,$termsig,$hupsig);

    exit $exit_code;
}

END {
    # Display bulletin msg
    displayBulletin (CSCHECKIN_NEWS, "//") if ($$ eq $parent_pid);
}



#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<csrollback>, L<csquery>, L<csfind>, L<csrecover>, L<cshistory>

=cut
