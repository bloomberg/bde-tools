#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
BEGIN {
    $FindBin::Bin =~/^(.*)$/ and $FindBin::Bin=$1;
    $ENV{PATH}="/usr/bin:$FindBin::Bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next
	  unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH$|PLINK_GRIDENABLE$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
    $ENV{PATH}.=":/bbs/opt/bin";
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Symbol ();
use IPC::Open3 ();
use Getopt::Long;
use File::Copy;
use File::Path;
use File::Spec;
use File::Temp;
use Sys::Hostname ();

use Task::Manager;
use Task::Action;
use Term::Interact;

use Fcntl ':flock';

use Util::File::Basename qw(dirname basename);
use Util::Message qw(message debug debug2 debug3 fatal error alert verbose 
		     get_debug warning open_log alert);

use Symbols qw(EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
               FILESYSTEM_NO_DEFAULT);
use constant DEFAULT_JOBS => 10; # for this tool, more parallel

use Change::Set;
use Change::AccessControl qw(getRejectedSymbols skipArch isTestMode
			     isValidFileType isNewCpp isPrivilegedMode
			     getDeprecatedSymbols bssSizeCheck
			     isGobWerrorException
                             isPrivilegedCscompileMode);
use Change::Symbols qw(USER APPROVELIST STAGE_INTEGRATION STAGE_DEVELOPMENT
                       STAGE_PRODUCTION_ROOT STAGE_PRODUCTION_LOCN
                       FILE_IS_UNKNOWN FILE_IS_UNCHANGED FILE_IS_REMOVED
                       DBPATH CSCOMPILE_TMP COMPCHECK_DIR COMPCHECK_DIR_CB2
                       CS_INTEGRATION CS_INTEGRATION_INCLUDE GETBESTHOST
                       ROBOPCOMP DEFAULTPCOMP GOB SMRG GCC GPP INC2HDR LEX YACC
                       CSCOMPILE_3PSINC CS_DATA DO_SYMBOL_VALIDATION
                       MOVE_REGULAR MOVE_BUGFIX MOVE_EMERGENCY MOVE_IMMEDIATE
		       CSCOMPILE_TOOL CHANGERCFILES HOME GTK_SKIP_FINDINC_LIBS
		       FINDINC_FILES_LIMIT LNKWGETHOSTS);

use Change::Configure qw(readConfiguration);
use Change::Arguments qw(parseArgumentsRaw identifyArguments
			 getParsedTrailingLibraryArgument);
use Change::Identity qw(getStageRoot deriveTargetfromFile lookupName);
use Change::Util::SourceChecks qw(checkChangeSet Inc2HdrRequired
				  checkCompileHeaderList
				  TreatWarningsAsErrors);

use Change::Approve qw(checkApproval);
use Change::Plugin::Manager;

use Source::Util::ParseTools qw(isCplusPlus);

use Build::Option::Finder;
use Build::Option::Factory;

use BDE::Build::Uplid;
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::DependencyCache qw(getAllGroupDependencies getCachedGroup
				 getAllInternalPackageDependencies
				 getCachedGroupOrIsolatedPackage);
use BDE::Util::Nomenclature qw(isLegacy isGroup isPackage getPackageGroup
			       isIsolatedPackage isGroupedPackage isFunction
			       getCanonicalUOR isThirdParty isApplication);

use Production::Services;
use Production::Services::Move;
use Production::Services::ChangeSet qw();
use Production::Symbols qw(VALIDATE_OLD_ORACLE
			   VALIDATE_NEW_ORACLE_AIX VALIDATE_NEW_ORACLE_SOLARIS
			   ENFORCE_OLD_ORACLE
			   ENFORCE_NEW_ORACLE_AIX ENFORCE_NEW_ORACLE_SOLARIS);

my %osetfh; #global filehandle for constructing object set from forked children

open_log(); # Open up the default session-tracking log

my $suppress_status_messages = 1; # Suppress by default for right now

#==============================================================================

=head1 NAME

cscompile - perform source checks and test complilations of source files.

=head1 SYNOPSIS

Test a single file:

  $ cscompile que.c acclib

Test multiple files in a single library:

  $ cscompile * acclib
  (or using --to option)
  $ cscompile --to acclib *

Test multiple files to multiple libraries:

  $ cscompile acclib/* mtgeutil/*

=head1 DESCRIPTION

The tool performs basic integrity  tests for various file types.  This
includes test compilation via C<pcomp> (.c/.cpp/.f/.gob), test compilation
for warnings via C<gcc -Wall> (.c/.cpp), and test C<smrgNT> (.ml).  pcomp test
compilation is performed on all available platforms.  Invalid symbols (malloc,
etc.) are also checked for.

This tool is invoked by C<cscheckin> (with the change set ID automatically
supplied), but it can also be invoked directly.  Developers are encouraged to
invoke it directly during their development process.

Performance has been optimized by parallelizing tasks where possible; the
default number of parallel tasks can be changed via the C<--jobs> option.

=cut

#==============================================================================
#<<<TODO:
#
# - Figure out generated file names rather than use glob to sweep.
# - Create table of tasks with single call to $mgr->run.
# - Implement table to drive tmp file setup.
# - Parallelize tmp dir and symlink creation.
#------------------------------------------------------------------------------

# a few globals

my $prog    = "cscompile"; #basename $0;

# These two variables must match get_best_host usage (eq uname -s)
my $sun             = "SunOS";
my $ibm             = "AIX";
my $compcheckdir    = COMPCHECK_DIR;

{ my $localHost = Sys::Hostname::hostname();	# (POSIX::uname())[1]
  my $localOS = `uname -s`;			# (POSIX::uname())[0]
  fatal("uname failed: $?") if $?;
  chomp($localOS);

  sub localHost() { return $localHost; }
  sub localOS()   { return $localOS; }
}

{
    my @hostlist = ();
    sub setHostList(@) { @hostlist= map { split /,/,$_ } @_; }
	 
    sub isPresentHostList()  { return @hostlist; }
}
#------------------------------------------------------------------------------

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $DEFAULT_JOBS=DEFAULT_JOBS; #for interpolation

    print <<_USAGE_END;
Usage: $prog -h | [-B|-e] [-C|-f] [-t<n>] [-D<t>] [-w<d>] [-j<n>] [-v] [-d] <files>

  --debug           | -d            enable debug reporting
  --help            | -h            usage information (this text)

  --jobs            | -j [<jobs>]   build files in parallel up to the specified
                                    number of jobs (default: $DEFAULT_JOBS jobs)
  --to              | -t <uor>      specify destination unit of release
                                    (only with unqualified file arguments)
  --where           | -w <dir>      specify explicit alternate local root
  --noretry         | -X            disable retry semantics on file operations
  --verbose         | -v            enable verbose reporting
  --config          | -z		 specify configuration file
  --ignoreconfig    | -Z            ignore per-user configuration file, if present
  --ignoretests                     ignore the test files[.t.<ext>] from compile
  --nodependency    | -n            switch dependency analysis on/off. Be default on.        
  --host            | -o [host]     provide hostname/host list to test compile code.
  --local           | -l            compile locally on local host.

File input options:

  --csid         | -C            derive test files from a registered change set
  --input        | -i [<file>]   read additional list of explicit filenames
                                 from standard input or a file (if specified)
  --from         | -f            read change set from file (e.g. previously
                                 generated with cscheckin -lM or csquery -M)
                                 (e.g. created by bde_createcs.pl/release)
Staging options:

  --bugf | --bf  | -b            compile against bug fix and EMOV headers
  --emov         | -e            compile against EMOV headers only
  --stage        | -s <stage>    compile against 'prod', 'prea' or 'devl'
  --devl                         shorthand for --stage=devl
  --include      | -I            specify abitrary additional include paths
                                 (only with --devl or --stage=devl)

Testing options:

  --do           | -D <check>    specify a specific check stage to perform
                                 (source|binary|header|native|gcc|all)
  --Werror       | -W            treat warnings as errors
  --nogccwarnings                do not display gcc warnings (when no errors)
  --gcc-ansi                     run gcc/g++ -ansi for gcc compile tests
  --Wnoexempt                    ignore exemption config file
  --dir <dir>                    specify root of directory structure in which
                                 compilations take place. <dir> is not deleted.
Extended functionality options:

  --plugin       | -L <plugin>   load the specified extension


_USAGE_END

    my $plugin_usage=getPluginManager()->plugin_usage();
    print $plugin_usage,"\n" if $plugin_usage;

    print "See 'perldoc $prog' for more information.\n";
}

#------------------------------------------------------------------------------

{ my $manager = new Change::Plugin::Manager(CSCOMPILE_TOOL);
  sub getPluginManager { return $manager; }
}

{ my $ignoretest=0;

  sub setIgnoretestFlag() {
      $ignoretest=1;
  }

  sub getIgnoretestFlag { return $ignoretest; }
}

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

sub getoptions {
    my @options=qw[
        bugf|bf|b!
        csid|C=s
        debug|d+
        devl
        dir=s
        do|D=s@
        emov|e!
        from|f=s
        help|h
        include|I=s@
	jobs|j:i
        stage|s=s		   
        to|t=s
        where|root|w|r=s
        Werror|W
	gccwarnings!
	gcc-ansi
        Wnoerror
        Wnoexempt
        noretry|X
        verbose|v+
	bypassGCCwarnings
        host|o=s@
        local|l
	nodependency|n
        compiletype|c=s
    ];

    my %opts;
    Getopt::Long::Configure("bundling");

    # files-from-input
    Getopt::Long::Configure("pass_through");
    GetOptions(\%opts,"input|i:s");
    GetOptions(\%opts,"ignoretests");
    if($opts{ignoretests}) {
	verbose "Ignoretest flag is set";
	setIgnoretestFlag();	
    }
    
    # rc files
    GetOptions(\%opts,"ignoreconfig|Z","config|z=s@");
    unless ($opts{ignoreconfig}) {
	$opts{config}
	  ? readConfiguration @ARGV,"cscompile",
			      (split / /,(join ' ',@{$opts{config}}))
	  : readConfiguration @ARGV,"cscompile",
			      (map { HOME.'/'.$_ } split / /, CHANGERCFILES);
    }
    
    # get plugins 
    $opts{plugin}=undef;
    GetOptions(\%opts,"plugin|L=s@");
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
	my @input_args=map { chomp; split /\s+/,$_ } @lines;
	unshift @ARGV,@input_args if @input_args;
    }

    unless (GetOptions(\%opts, @options)) {
        usage();
        exit EXIT_FAILURE;
    }


    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage("nothing to do!"), exit EXIT_FAILURE if @ARGV<1 and
      not ($opts{from} or $opts{csid});

    # move type
    usage("nothing to do!"), exit EXIT_FAILURE if
      $opts{bugf} and $opts{emov};

    # filesystem root
    # *Don't* default it as per usual for this tool, see below

    # from/csid
    if ($opts{from}) {
	if ($opts{csid}) {
	    usage("--from and --csid are mutually exclusive");
	    exit EXIT_FAILURE;
	}
	fatal "--from incompatible with file arguments (@ARGV)" if @ARGV;
    }
    if ($opts{csid}) {
#        $checkinMode = 1;  #<<<TODO: changeset needs additional state
	fatal "--csid incompatible with file arguments (@ARGV)" if @ARGV;
    }

    if ($opts{do}) {
	setDoTasks(@{$opts{do}});
	my $list = getDoTasks();
	
	$list =~ s/(source|binary|header|native|gcc|all|\s*)//g;
	usage("invalid \'do\' switch"), exit EXIT_FAILURE unless $list eq "";
        alert("@{$opts{do}} checks selected") if $opts{do} ne "all";
    } else {
        $opts{do} = "all";
	setDoTasks($opts{do});
    }

    # jobs
    $opts{jobs} = default_job_count() unless $opts{jobs};

    # stage
    unless ($opts{stage}) {
	$opts{stage}=($opts{devl}) ? STAGE_DEVELOPMENT : STAGE_INTEGRATION;
    }

    # include
    if ($opts{include}) {
	if ($opts{stage} ne STAGE_DEVELOPMENT) {
	    fatal "--include can only be used with --devl or --stage=devl";
	}
    }

    # filesystem root - unusually, for this tool, we don't automatically
    # upgrade to DEFAULT_FILESYSTEM_ROOT unless --stage=devl
    unless ($opts{where}) {
	$opts{where} = ($opts{stage} eq STAGE_DEVELOPMENT) ?
	  DEFAULT_FILESYSTEM_ROOT : undef;
    }

    $opts{compiletype} ||= 'optimistic';
    $compcheckdir = COMPCHECK_DIR_CB2 
        if $opts{compiletype} eq 'cb2';

    # disable retry
    $Util::Retry::ATTEMPTS = 0 if $opts{noretry};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------
# Utilities
#------------------------------------------------------------------------------

{ my %mkpathed;
  sub cachedMkpath($) {
      my($dirs)=@_;

      if (!ref($dirs)) {
          return 0 if !$dirs;
	  return 1 if $mkpathed{$dirs} or (-d $dirs && ++$mkpathed{$dirs});
          eval { mkpath($dirs,0,02775) };
          fatal("could not mkpath: $@") if $@;
          $mkpathed{$dirs}++;
          return 1;
      }
      return 0 if !@$dirs;
      for my $dir (@$dirs) {
	  return 0 unless $dirs ne "";
          next  if $mkpathed{$dir}
		or (-d $dir && ++$mkpathed{$dir});
          eval { mkpath($dir,0,02775) };
          fatal("could not mkpath: $@") if $@;
          $mkpathed{$dir}++;
      }
      return 1;
  }

  my %negative_cache;
  sub is_existing_path($;$) {
    return 1 if exists $mkpathed{$_[0]};
    if (!$_[1]) {
	return (!(exists $negative_cache{$_[0]}) && -d $_[0]
		? ++$mkpathed{$_[0]}
		: ($negative_cache{$_[0]}=0));
    }
    else {
	return (-d $_[0]
		? ++$mkpathed{$_[0]}
		: 0);
    }
  }
}

sub multiSymlink($@) {
    my($file,@dirs) = @_;
    # Create symlink to $file in all directories in @dirs.

    cachedMkpath(\@dirs);
    for my $toDir (@dirs) {
        symlink($file, "$toDir/".basename($file)) or
          fatal("can not create symlink in $toDir to $file: $!");
    }
}

sub install2TmpInclude($$$) {
    my($uor,$file,$toDir) = @_;
    fatal("$file not found, or not a regular file") unless -f $file;

    # Uses library and relative path to file to create target directory
    # structure under $toDir, and then copies $file to the appropriate
    # directory therein:
    # - Headers are relative-pathed for libraries marked as such
    # - Headers under Cinclude are accessed directly (including relative paths)
    # - Headers under bbinc are accessed via relative paths
    # - Headers are private to applications, no relative paths
    # - Headers elsewhere are placed at top of the library, no relative paths
    # Note:biglets might be accessed via <uor/header.h> for menus libs and mbig
    # initialization libraries so allow for those references with extra symlink
    # Note: the original GTK library made the assumption that headers would be
    # referenced via gtk/, so allow for those references with extra symlink
    # (There is a check in SourceChecks.pm which disallows <gtk/f_*/header.h>)
    # Note: Save a -I rule by placing Cinclude in the top of bbinc/. While this
    # allows accessing bbinc/pl other other headers with <Cinclude/pl/..> which
    # will break the robocop build, we will lart developers who do this or can
    # add symlinks in the real bbinc/Cinclude to allow these to resolve
    # Note: there is currently no support for .pub metadata files here
    # This might be added in the future or enforced elsewhere in a source check

    my $lib = basename $file->getLibrary;   # (remove leading "gtk/" from libs)
    my $subdir = $file->getTrailingDirectoryPath;
    my $is_relative_pathed = $uor->isRelativePathed;
    my $copydir;
    if ($uor eq "bbinc/Cinclude") {
	$copydir = $toDir."/"."bbinc".($subdir ne "" ? "/".$subdir : "");
    }
    elsif (substr($uor,0,6) eq "bbinc/") {
	$copydir = $toDir."/".$uor.($subdir ne "" ? "/".$subdir : "");
    }
    elsif ($is_relative_pathed) {
	##<<<TODO: might also need to make top-level glib -> bbglib symlink
	$copydir = $lib ne "bbglib"
	  ? $toDir."/".$uor."/".$lib.($subdir ne "" ? "/".$subdir : "")
	  : $toDir."/".$uor."/glib";  # one-off special-case for bbglib
    }
    elsif (isApplication($uor)) {
	$copydir = $toDir."/".$uor;
    }
    else {
	$copydir = $toDir."/".$uor;
    }
    cachedMkpath($copydir);
    copy($file,$copydir)
      || fatal("cannot copy $file to $copydir: $!");

    symlink(".",$toDir."/".$uor."/".$uor)
      if ((isFunction($uor) || $uor =~ /^gtk.*init$/)
	  && !-l $toDir."/".$uor."/".$uor);
    symlink(".",$toDir."/".($is_relative_pathed ? "$uor/$lib" : $uor)."/gtk")
      if ($uor->isGTKbuild()
	  && !-l $toDir."/".($is_relative_pathed ? "$uor/$lib" : $uor)."/gtk");

    my $hdr = $copydir."/".basename($file);
    chmod(0664,$hdr)
      || fatal("cannot chmod $hdr: $!");
    return $hdr;
}

sub globCp($$$) {
    my($fromDir,$pattern,$toDir) = @_;
    fatal("pattern not set") unless $pattern; 
    ## get list of files first to avoid creating directory if not needed
    ## (should not be so obscenely large that we are unable to read into memory)

    my @files = glob("$fromDir/$pattern");
    return unless (scalar @files);

    cachedMkpath($toDir);
    for my $file (@files) {
        fatal("cannot copy $file to $toDir: $!") unless copy($file,$toDir);
    }
}

#------------------------------------------------------------------------------
# Tmp directory setup
#------------------------------------------------------------------------------

{ my ($tmp, $tmpCreated);

  sub setTmp($) {
      $tmp = File::Spec->rel2abs($_[0]);

      # Debugging sanity check:
      fatal "Tried to set temp directory after it was already created"
          if ($tmpCreated);

      if (-d $tmp) {
          # User sanity checks:

          fatal "$tmp is not a writable directory\n" unless (-w $tmp);

          # If directory exists, it must be writable and empty.  Otherwise,
          # we might accidentally pollute a user's directory (e.g. their home
          # directory) with build files.
          opendir(THISDIR,$tmp) or fatal "cannot open dir $tmp";
          for (readdir THISDIR) { fatal "$tmp is not empty" unless /^\.{1,2}$/ }
      }

      $tmp=~/^(.*)$/ and $tmp=$1; #untaint
  }

  sub createTmp() {
      eval { mkpath($tmp,0,02775) unless (-d $tmp); };
      fatal("cannot create $tmp: $@") if $@;
      $tmpCreated = 1;
  }

  sub getTmp() { return $tmp; }

  sub getPlatformTmp($) { return $tmp."/".$_[0];                              }

  sub getIncludeTmp()  { return "$tmp/include";                               }
  sub getSrcTmp()      { return "$tmp/src";                                   }
  sub getProdinsTmp()  { return getIncludeTmp."/bbinc/prodins";               }
  sub getInc2HdrTmp($) { return getPlatformTmp($_[0])."/inc2hdr";             }
  sub getGobTmp($)     { return getPlatformTmp($_[0])."/gob";                 }
  sub getHdrCompTmp($) { return getPlatformTmp($_[0])."/robopcomp";           }
  sub getSymValTmp($)  { return getPlatformTmp($_[0])."/symval";              }
  sub getSmrgTmp($)    { return getPlatformTmp($_[0])."/smrg";                }
  sub getPcompTmp($)   { return getPlatformTmp($_[0])."/pcomp";               }
  sub getRobopcompTmp($) { return getPlatformTmp($_[0])."/robopcomp";         }
  sub getLexTmp($)     { return getPlatformTmp($_[0])."/lexyacc";             }
  sub getYaccTmp($)    { return getPlatformTmp($_[0])."/lexyacc";             }
  sub getGccTmp($)     { return getPlatformTmp($_[0])."/gcc";                 }
  sub getXlcTmp($)     { return getPlatformTmp($_[0])."/xlc8";                }
  sub getIncCacheTmp($){ return getPlatformTmp($_[0])."/cacheinc";            }

  sub getObjTmps($)    { return (getPcompTmp($_[0]), getGobTmp($_[0]), 
				 getRobopcompTmp($_[0]));       }

  sub setupTmpFiles($) {
      my ($fileset)=@_;

      # Copy headers to tmp include (which is then #included as appropriate),
      # and code to tmp src, and then make symlinks as necessary from actual
      # task directories as needed.

      # Also performs other pre-processing:
      #   - create src file that includes header for test compilation of header

      my $includeTmp = getIncludeTmp();
      my $srcTmp = getSrcTmp();
      cachedMkpath($srcTmp);
      cachedMkpath(getSymValTmp($sun)); cachedMkpath(getSymValTmp($ibm));
      my($uor,$hdr,@incfiles,@fortran_files,$subdirs,$suntmp,$ibmtmp);
      foreach my $target (sort $fileset->getTargets) {
	  foreach my $file ($fileset->getFilesInTarget($target)) {
	      $uor   = getCachedGroupOrIsolatedPackage($file->getLibrary);
	      if ($file =~ /\.(?:h|hpp|inc|gobxml)$/) {
		  $hdr = install2TmpInclude($uor,$file,$includeTmp);
		  next if ($file =~ /\.gobxml$/);
		  if ($file =~ /\.inc$/) {
		      push @incfiles, [ $file, $hdr ];
		      next unless Inc2HdrRequired($file);
		      $suntmp = getInc2HdrTmp($sun);
		      $ibmtmp = getInc2HdrTmp($ibm);
		  }
		  else {
		      $suntmp = getHdrCompTmp($sun);
		      $ibmtmp = getHdrCompTmp($ibm);
		  }
		  # directory structure maintained
		  $subdirs = $uor->isRelativePathed() || $uor =~ m|^bbinc/|
		    ? "/".$target
		    : "";
		  multiSymlink($hdr, $suntmp.$subdirs, $ibmtmp.$subdirs);
              } else {
                  fatal("cannot copy $file: $!") unless copy($file,$srcTmp);
                  my $srcFile = $srcTmp."/".basename($file);
                  fatal("cannot chmod $srcFile: $!")
		    unless chmod(0664,$srcFile);
                  if ($file =~ /\.(gob|gmm|gwp)$/) {
		      multiSymlink($srcFile,getGobTmp($sun),getGobTmp($ibm));
                  } elsif ($file =~ /\.cpp$/) {
                      multiSymlink($srcFile,
				   getRobopcompTmp($sun),getRobopcompTmp($ibm),
                                   getPcompTmp($sun),getPcompTmp($ibm),
				   getGccTmp($sun),getGccTmp($ibm),
				   getXlcTmp($ibm));
                  } elsif ($file =~ /\.(?:c|ec|f)$/) {
                      multiSymlink($srcFile,
				   getRobopcompTmp($sun),getRobopcompTmp($ibm),
                                   getPcompTmp($sun),getPcompTmp($ibm),
				   getGccTmp($sun),getGccTmp($ibm),
				   getSmrgTmp($sun),getSmrgTmp($ibm));
		      push @fortran_files, [ $file, $srcFile ]
			if ($file =~ /\.f$/);
                  } elsif ($file =~ /\.l$/) {
                      multiSymlink($srcFile,getLexTmp($sun),getLexTmp($ibm),
				   getRobopcompTmp($sun),getRobopcompTmp($ibm),
                                   getPcompTmp($sun),getPcompTmp($ibm),
				   getGccTmp($sun),getGccTmp($ibm));
                  } elsif ($file =~ /\.y$/) {
                      multiSymlink($srcFile,getYaccTmp($sun),getYaccTmp($ibm),
				   getRobopcompTmp($sun),getRobopcompTmp($ibm),
                                   getPcompTmp($sun),getPcompTmp($ibm),
				   getGccTmp($sun),getGccTmp($ibm));
                  } elsif ($file =~ /\.ml$/) {
                      multiSymlink($srcFile,getSmrgTmp($sun),getSmrgTmp($ibm));
                  }
              }
          }
      }
      
      #make a symlink of Cinclude -> . in tmp/bbinc due to DRQS 8174122
      if(-d $includeTmp."/bbinc" && !(-f $includeTmp."/bbinc/Cinclude")) {
	  symlink(".", $includeTmp."/bbinc/Cinclude");
      }
      # orphan .inc check
      checkForOrphanIncs(@incfiles,@fortran_files) if (@incfiles);
  }
}

#------------------------------------------------------------------------------
# Logging
#------------------------------------------------------------------------------

{ my $logFile;
  my $logLock;
  my $logFH;

  sub openLog() {
      $logFile = getTmp()."/log";
      $logLock = "$logFile.lock";
      $logFH = new IO::File;
      fatal("cannot open $logFile: $!") unless open($logFH,"+>",$logFile);
  }

  sub logMsg($$$$$) { 
      $logFH || openLog() || open($logFile,">&STDERR");
      my($fileName,$tag,$platform,$host,$msg) = @_;
      return unless defined($msg);
      ## Note: not serializing access to this file (by using a lock) means
      ## that output to the log by multiple processes might be interleaved.
      print $logFH
	("-" x 80),
	"\nFILE: $fileName TEST: $tag PLATFORM: $platform HOST: $host\n",
	("-" x 80),
	"\n\n$msg\n\n";
  }

  sub displayLog() {
      return 1 unless $logFH;
      $logFH->flush;
      -s $logFH or return 1;
      seek $logFH,0,0; # seek() to beginning of file
      local $/= undef;
      my ($content) = <$logFH>;
      seek $logFH,0,2; # (always seek() between reads and writes)
      print STDERR "\n\n$content\n";
  }

  sub getLogFile() {
      return $logFile;
  }
}

#------------------------------------------------------------------------------
# CS Data support
#------------------------------------------------------------------------------

{
    my $csId;
    my $moveType = MOVE_REGULAR;
    my %moveDirs = (&MOVE_REGULAR   => MOVE_REGULAR,
                    &MOVE_BUGFIX    => MOVE_BUGFIX,
                    &MOVE_EMERGENCY => MOVE_EMERGENCY,
                    &MOVE_IMMEDIATE => MOVE_IMMEDIATE);

    sub setCSId($)     { $csId = shift;               }
    sub getCSId()      { return $csId;                }
    #sub setMoveType($) { $_[0] and $moveType = $_[0]; }
    sub setMoveType($) { exists $moveDirs{$_[0]}
			  ? ($moveType = $_[0])
			  : (error("invalid move type '$_[0]'\n")); }
    sub getMoveType()  { return $moveType;            }

    sub getCSDataMTInc(;$) {
        my($mt) = $_[0] || getMoveType();
        return ($compcheckdir."/".$moveDirs{$mt}."/include");
    }
}

sub getCSDataIncludes() {
    my @dirs;
    @dirs = getCSDataMTInc(MOVE_EMERGENCY);
    unshift(@dirs,getCSDataMTInc(MOVE_BUGFIX))
      if getMoveType() eq MOVE_BUGFIX or getMoveType() eq MOVE_REGULAR;
    unshift(@dirs,getCSDataMTInc(MOVE_REGULAR))
      if getMoveType() eq MOVE_REGULAR;
    return(wantarray ? @dirs : join(" ",map{"-I$_ "}@dirs));
}

sub getCSDataObjsDir($) { # requires platform
    return if !getCSId();
    return $compcheckdir."/".getMoveType()."/".getCSId()."/$_[0]";
}

sub setupCSDataDirs() {
    cachedMkpath(getCSDataObjsDir($sun));
    cachedMkpath(getCSDataObjsDir($ibm));
}

sub getCSDataLogDir() {
    return if !getCSId();
    return CS_DATA."/logs";
}

sub getCSDataLog() { 
    return if !getCSId();
    return getCSDataLogDir()."/".getCSId().".log";
}

sub writeObjectSetHeader {
    my ($fh, $changeset, $compiletype) = @_;
    debug "writing object set header to $fh";
    my $tmpid = $changeset->getID;
    $changeset->setID(undef) if $compiletype eq 'cb2';
    print $fh $changeset->listChanges(0,1),"\n"; #machine, headeronly
    $changeset->setID($tmpid);
}

#------------------------------------------------------------------------------
# Cleanup and exit
#------------------------------------------------------------------------------

{
  # END processing - but is called after every task manager tasks exit, so use
  # flags to control 
  my ($cleanExit, $rmTmpOnExit) = (1, 1);
  sub rmTmpOnExit($) { $rmTmpOnExit = $_[0]; }
  sub cleanExit($) { $cleanExit = $_[0]; }

  END {
      my $ret = $?;

      my $tmp = getTmp();
      exit EXIT_SUCCESS unless $tmp;

#      ## leave output around for debugging
#      if (-d $tmp and $rmTmpOnExit and $cleanExit) {
#	  #my $cmd = "rm -rf $tmp 2>&1";
#	  #debug($cmd);
#          #my $out = `$cmd`;
#          #warning("\n$cmd\n\$?: $? $out") if $?;
#      }
#      else {
#	  ## (no longer necessary)
#	  #system("chmod -R ug+rw $tmp") if (-d $tmp);
#      }
      if ($cleanExit) {
          verbose("$prog output left under $tmp");
          my $logfile = getLogFile();
          message("cscompile log file contains errors or warnings:\n\t$logfile")
            if ($logfile && -s $logfile);
      }
      exit($ret);
  }
}

{
  my $opts;

  sub _setOpts ($) {
    $opts = shift;
  }

  sub cleanupAndExit($;$) {
    my($ret, $nolog)=@_;
    cleanExit(1);
    displayLog() unless ($nolog or !$ret);
    $ret and message("$prog FAILED") or !$ret and message("$prog finished OK");
    my $manager = getPluginManager();
    $manager->plugin_finalize($opts, $ret);
    exit($ret);
  }
}

#------------------------------------------------------------------------------
# Other helpers
#------------------------------------------------------------------------------

sub checkForOrphanIncs (@) {
    # A module in SourceChecks is used to distinguish .inc files for which
    # a header (.h file) should be generated (using inc2hdr).  This is
    # generally done because the generated header file (for some reason) will
    # fail compile testing.
    #
    # There are many inc files that were created for organization purposes
    # (to arrange code in separate physical units) and thus do not compile
    # in isolation.  It makes sense to compile them with the "parent" inc
    # file from which these "child" inc were spawned off.
    # Thus this tool requires that the changeset that this child inc is a part
    # of should include its corresponding parent inc file or a fortran file
    # that includes this child file.
    #
    # Once the parent file is supplied in the changeset, then the child inc
    # file is not compile tested in isolation.  Instead the successful
    # compilation of the parent file is interpreted as a successful compilation
    # of the child file.

    verbose("checking for orphan .inc files");
    my @children;
    my @parentIncludes;
    my($file,$inc);
    for my $pair (@_) {
	($file,$inc) = @$pair;
        my $fh = new IO::File;
        error("cannot open $inc: $!"), cleanupAndExit(1)
	  unless open($fh, "<$inc");
        local $/= undef;
        my ($content) = <$fh>;
        error("cannot close $inc: $!"), cleanupAndExit(1) unless close($fh);
	
	if ($inc=~/\.inc$/) {
	    push(@children,basename($inc))
		unless Inc2HdrRequired ($file);
        }
	
        push(@parentIncludes, $content =~ /^\s+include\b(.*)$/img);
    }

    return unless @children;
    for my $child (@children) {
        error("$child not included by any parent inc or fortran file"),
        cleanupAndExit(1)
	  unless grep { /\b$child\b/ } @parentIncludes;
    }
}

sub checkForInvalidSymbols($$) {
    my ($opts,$fileset) = @_;

    # this reproduces the '$files' hashref as previously passed in.
    my $fileobjs={ map { basename($_) => $_->getLibrary } $fileset->getFiles };

    verbose("checking for rejected symbols...");
    my $platform = localOS();

    #<<<TODO: add ibm...
    #error("can only check symbols on sun"), cleanupAndExit(1) unless $sun;

    my %files;
    for my $tmpDir (getObjTmps($platform)) {
        for my $obj (glob("$tmpDir/*.o")) {
            (my $src = $obj) =~ s/\.o//;
            $src =~ s/(.*)\..*$/$1/;
            $src = "$src.ec" if -f "$src.ec";
            $src = "$src.c" if -f "$src.c";
            $src = "$src.f" if -f "$src.f";
            $src = "$src.cpp" if -f "$src.cpp";
	    $files{$src} = $obj;
        }
    }
    my ($bn,$src,$lib,$type,@actions);
    my ($deprecated,$rejected)=(0,0);
    foreach my $file (keys(%files)) {
        $bn = basename($file);
        $src = basename $bn,".c",".cpp",".f";

	if (-f getGobTmp($platform)."/$src.gob") {
	    $src .= ".gob";
	}
	elsif (-f getGobTmp($platform)."/$src.gmm") {
	    $src .= ".gmm";
	}
	elsif (-f getGobTmp($platform)."/$src.gwp") {
	    $src .= ".gwp";
	}
	else {
	    (my $src1 = $src) =~ s/-cpp$//;
	    # check if this file is C++ wrapper file from gob
	    if (-f getGobTmp($platform)."/$src1.gob") {
		$fileobjs->{$src} = $fileobjs->{$src1};
		$src = "$src1.gob";
	    }
	    elsif(-f getGobTmp($platform)."/$src1.gwp") {
		$fileobjs->{$src} = $fileobjs->{$src1};
		$src = "$src1.gwp";
	    }
	    else {
		$src = $bn;
	    }
	}

	$lib = $fileobjs->{$src};
	if(!defined $lib) {
	    next;
	}
	##<<<TODO: replace inefficient search (and this whole routine) to
	## use the $fileset changeset rather than globbing from filesystem
	$type = FILE_IS_UNKNOWN;
	
	foreach my $chfile ($fileset->getFiles) {
	    if ($lib eq $chfile->getLibrary && $src eq $chfile->getLeafName) {
		##<<<TODO: this is disabled until a method is provided!
		## should be something like $chfile->examineType which will
		## alleviate the need to check for FILE_IS_UNKNOWN and check
		## ourselves in the application.
		#$type = $chfile->getType();
		#$type = $chfile->foo() if $type eq FILE_IS_UNKNOWN;
		last;
	    }
	}
	next if $type eq FILE_IS_REMOVED;

	## currently only test on Solaris because IBM calculates
	## size differently when global commons are involved
	##<<<TODO: should probably move into symbol_oracle.pl
	my $path = $files{$file};
	$path =~ s|/AIX/|/SunOS/|g;  # hack to update path on AIX
	$path =~ s/\.ibm\./\.sundev1\./g;  # hack to update path on AIX

	push(@actions,new Task::Action
	     ({name=>".bss size check $path ($sun)",action=>\&bssSizeCheckTest,
	      args=>[$sun,$lib,$src,$path]})) if $sun;

	## Skip (certain) policy checks if file is unchanged
	next if $type eq FILE_IS_UNCHANGED;

	unless (getDeprecatedSymbols($src, $lib, $files{$file})) {
	    error("deprecated symbols found in $bn");
	    $deprecated++;
	}

	##<<<TODO: some checks here and above may move into symbol_oracle.pl

        my @rejects = getRejectedSymbols($lib,$file,$files{$file});
	if (@rejects) {
            error("invalid symbols \"$_\" found in $bn")
	      foreach (@rejects);
	    $rejected++;
        }
    }

    # if any errors were found, summarise and exit
    if ($deprecated or $rejected) {
	if ($deprecated) {
	    my $file=($deprecated==1)?"file contains":"files contain";
	    error ("$deprecated $file calls to functions".
		   " forbidden by R&D policy.");
	}
	if ($rejected) {
	    my $file=($rejected==1)?"file contains":"files contain";
	    error ("$rejected $file calls to restricted memory".
		   "-allocation functions.");
	}
	error("* Please check BP BANNED CALLS <go> for a list of banned calls and their"
	      ." recommended replacements.");
	error("* If this is for an EMOV, please file a DRQS OU to group 55".
	      " explaining why an exemption should be granted.");
	cleanupAndExit(1,1);
    }

    # otherwise, proceed to checks in task actions
    if (@actions) {
        my $mgr=new Task::Manager
	  ("running binary checks".
	   (getCSId()?" for change set ".getCSId()."":""));
        $mgr->addActions(@actions);
	$mgr->setLogSub(\&alert);
	my $jobs = $opts->{jobs};
	$jobs = 8 if $jobs > 8;
        $mgr->run($jobs) and cleanupAndExit(1,1);
    }
}

sub updateCSData($$) {
    my ($fileset,$stage)=@_;

    verbose("updating change set data area...");

    ##<<<TODO: note that f_****** -> . symlinks are currently not created
    ## and therefore not propagated here.  The means that checking code into
    ## gtk*init libraries that uses these headers must occur after the code
    ## in the f_****** library is swept into RCS.  Since this only requires
    ## waiting for the the initial checkin of the f_****** header, this can
    ## be viewed as a safety measure.

    my $tmpincdir = getIncludeTmp();
    if (-d $tmpincdir) {
	##<<<TODO replace with something nicer, like File::Find
        my $cmd = qq{find "$tmpincdir" -type f -o -type l};
        my @out = `$cmd`;
        fatal("$cmd failed: $?") if $?;
        chomp(@out);
	
	# create header install manifest
	my $manifestFile = $compcheckdir."/".getMoveType()."/"
			 . getCSId()."/"."header.manifest";
	cachedMkpath(dirname $manifestFile);
	my $manifestFH = new IO::File(">".$manifestFile)
	  || fatal("cannot open $manifestFile: $!");
	my $cachedir=getCSDataMTInc();
	for my $tmpinc (@out) {   
	    (my $copyinc = $tmpinc) =~ s($tmpincdir)($cachedir);
	    cachedMkpath(dirname $copyinc);
	    if (!-l $tmpinc) {
		##<<<TODO: maybe log pre-existence of header to be overwritten
		copy($tmpinc, $copyinc)
		  || fatal("cannot copy $tmpinc to $copyinc: $!");
		print $manifestFH $copyinc,"\n";
	    }
	    elsif (!-l $copyinc) {
		symlink(readlink($tmpinc),$copyinc)
		  || fatal("cannot create symlink $copyinc: $!");
	    }
	}
	close($manifestFH)
	  || fatal("cannot close $manifestFile: $!");
    }

    # For BREG files, we have to also install them into the EMOV location
    # even though they're not EMOVs because they're 'special'. They are also
    # placed into the bugfix location so regular moves still work after the
    # emov cache is cleaned out. (see /home/alan/bin/autobreg)
    my $breg_move = getCSDataMTInc(MOVE_REGULAR)."/bbinc/registry";
    if (is_existing_path($breg_move,1)) { # yes if breg headers installed above
	map { -l $_."/bbinc/registry"
	      || (cachedMkpath($_."/bbinc")
		  && symlink($breg_move,$_."/bbinc/registry")) }
	    getCSDataMTInc(MOVE_EMERGENCY),
	    getCSDataMTInc(MOVE_BUGFIX);
    }
    #< end BREG special case

    return if !getCSId();

    ## continuous build (approximation)
    ## hard link object set file (contains source files and paths to objects)
    foreach my $platform (keys %osetfh) {
      my $objectsetFile = $compcheckdir."/".getMoveType()."/"
 	                  . getCSId()."/"."object.set.$platform";
      cachedMkpath(dirname $objectsetFile);
      link($osetfh{$platform},$objectsetFile)
	|| warning("link ".$osetfh{$platform}." $objectsetFile: $!");
      if (-e $osetfh{$platform}.".symbols") {
	link($osetfh{$platform}.'.symbols',$objectsetFile.'.symbols')
	  || warning("link ".$osetfh{$platform}.".symbols $objectsetFile.symbols: $!");
      }
    }

## gps
##<<<TODO: should we bother doing this for now?  We're not using this.
##	Also, if we are doing this, we should be doing this for both
##	Sun and IBM, regardless of on which platform we started
## ***  Up to when I commented this out, the code was broken
##	because $bfile needs to be basename($bfile)
#    for my $file ($fileset->getFiles) {
#        (my $bfile = $file) =~ s-\.\w+$--;
#        $bfile = basename($bfile);
#        if ($sun) {
#            for my $dir (getObjTmps($sun)) {
#                globCp($dir,"$bfile.*o",getCSDataObjsDir($sun));
#            }
#        }
#        if ($ibm) {
#            for my $dir (getObjTmps($ibm)) {
#                globCp($dir,"$bfile.*o",getCSDataObjsDir($ibm));
#            }
#        }
#    }
## gps
##<<<TODO: at this point we also need to ar the files into candidate libraries
## Basically, for each library directory, copy the current candidate library,
## ar all objects in the test directory into the new library, and then
## replace the candidate library.  Be sure to hold an NFSLock around these
## operations.  Alternatively, kick off a process to do this in the background
## and have that (possibly a daemon) do work serialized.


## (we have a log of what was sent to the user, including the path to log file)
#    my $fromLog = getLogFile();
#    if (-s $fromLog) {
#	cachedMkpath(getCSDataLogDir());
#	my $toLog = getCSDataLog();
#	copy($fromLog,$toLog)
#	  || fatal("cannot copy log from $fromLog to $toLog: $!");
#	alert("log file saved as $toLog");
#    }
}

#------------------------------------------------------------------------------
# TASK MANAGER ROUTINES
#
# These routines must not print directly (use logging) or exit/fatal/die.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# dependency/include configuration
#------------------------------------------------------------------------------

{ my @localincs;

  sub setLocalIncludes (@) { @localincs=@_; }
  sub getLocalIncludes (@) { return @localincs; }
}

{ my $doTasks="";

  sub setDoTasks (@) { my @tmp= map { split /,/,$_ } @_;
		       $doTasks="@tmp"; }
  sub getDoTasks () { return $doTasks; }
}

{ my @cppincs;

  sub setCppIncludes (@) { unshift(@cppincs, @_); } 
  sub getCppIncludes (@) { 
      my %unique;
      my @allIncludes = grep(!$unique{$_}++, @cppincs);
      # unique list
      return @allIncludes; }
}

sub get3psIncludePath ($) {
    #<<<TODO: remove this when 3ps entities are handled as UORs!
    my $platform=shift;
    my @incs=split / /,CSCOMPILE_3PSINC;

    return " ".(join " ",map {
	"-I/bbsrc/3ps/$platform/$_/production/include"
    } @incs);
}

##<<<TODO: abstract to a module so that bde_build.pl can use some of this logic
##         (e.g. a getDeployedInclude method to Groups and Isolated Packages)
{
  my %includePathCache;

  my %trimmedIncCache;
  my $uniqcount = '';
  sub getIncludePath($$$);
  sub _getIncludePath($$$);
  sub getIncludePath($$$) {
    my ($uor, $platform, $file) = @_;

    my $starttime = time;
    # Get the include path for this file
    my $i_path = _getIncludePath($uor, $platform, $file);

    # Skip if we don't have the current include path in anywhere
    my $temp_spot = CSCOMPILE_TMP;

    my $is_gob = 0;
    $is_gob = 1 if $file =~ /\.gob/;
    return $i_path if $is_gob;
    my $new_path = '';
    $i_path =~ s/-I\s+/-I/g;
    # Have we seen it? If so, return it
    if ($trimmedIncCache{$i_path}) {
      debug("Returning (".$trimmedIncCache{$i_path}.") for <$i_path>");
      my $ret = $trimmedIncCache{$i_path};
      $ret =~ s/-I(\S)/-I $1/g if $is_gob;
      return $ret;
    }

    my $incpath = getIncCacheTmp($platform)."/$uor$uniqcount";
    cachedMkpath($incpath);
    $uniqcount++;

    # Collapse down the path
    $new_path = _collapse_i($i_path, $incpath);

    # Save it in case we need it again
    $trimmedIncCache{$i_path} = $new_path;
    my $totaltime = time - $starttime;
    debug("Generated ($new_path) for <$i_path>");
    verbose("Header cache build for $platform/$uor/$file took $totaltime seconds");
    my $ret = $new_path;
    $ret =~ s/-I(\S)/-I $1/g if $is_gob;
    return $ret;
  }

  sub _collapse_i {
    my ($base_i, $destdir) = @_;
    my (@new_rules);
    my %h_cache;
    my %i_seen;
    my $ok_dir = CSCOMPILE_TMP;

    my $cachedir =  "-I$destdir";
    my $skip_rest = 0;
    my $seen_regular = 0;

    # Add in a gtk symlink
    symlink($destdir, "$destdir/gtk");

    # Run through all the things on the commandline 
  RULELOOP:
    foreach my $rule (split /\s+/, $base_i) {
      my $no_push = 0;
      if (! ($rule =~ /^-I.+/)) {
	push @new_rules, $rule;
	next;
      }

      # Skip dupes
      next if $i_seen{$rule};
      $i_seen{$rule}++;

      # Are we in skip-to-the-end mode?
      if ($skip_rest) {
	push @new_rules, $rule;
	next;
      }

      # Generally speaking we don't want to not link
      my $no_link = 0;

      # Is it the directory for the changeset? We look but don't link
      if ($rule =~ /$ok_dir/) {
	$no_link = 1;
	push @new_rules, $rule;
      } else {
	# A non-private dir. If we haven't pushed our cache dir, do it now
	if (!$seen_regular) {
	  push @new_rules, $cachedir;
	  $seen_regular = 1;
	}
      }

      # Did we hit one of the big deployed directories? We don't scan
      # 'em, they're too big, and if we've hit them we can pretty much
      # figure we're done
      if ($rule =~ /include\/00/ || $rule =~ /bbsrc\/bbinc/) {
	$skip_rest = 1;
	push @new_rules, $rule;
      }

      # Okay, then, we have a directory we want to scan. 
      my ($dir) = $rule =~ /^-I(.*)/;
      my (@files) = glob("$dir/*");
      if (@files > 200) {
	$no_link = 1;
	push @new_rules, $rule;
	$no_push = 1;
      }

      # Go look for directories. If there's a subdir we bail, unless
      # it's either gtk or has the same name as the dir we're in
      my $taildir;
      $dir =~ /.*\/(.*)/;
      $taildir = $1;
      foreach my $file (@files) {
	my $tail;
	$file =~ m|.*/(.*)|;
	$tail = $1;
	next if $tail eq 'gtk';
	next if $tail eq $taildir && $tail =~ /^f_/;
	if (-d $file) {
	  $no_link = 1;
	  push @new_rules, $rule unless $no_push;
	  next RULELOOP;
	}
      }

      foreach my $file (@files) {
	next if $file eq 'gtk';
	if (-d $file) {
	  next if -e "$destdir/$taildir";
	  my $taildir;
	  $file =~ /.*\/(.*)/;
	  $taildir = $1;
	  symlink($destdir, "$destdir/$taildir");
	  next;
	}

	if ($file =~ m|$dir/(.*)$|) {
	  my $header = $1;
	  # Skip the file if we've already seen it
	  next if $h_cache{$header};
	  # If we don't link files from this directory we still need to
	  # note we've seen the header file
	  if ($no_link) {
	    $h_cache{$header} = $file;
	  } else {
	    # Symlink it
	    symlink($file, "$destdir/$header");
	  }
	}
      }
    }
    my $returndata = " " . join(" ", @new_rules) . " ";
    return $returndata;
  }

  sub _getIncludePath($$$) {
      my($uor,$platform,$file) = @_;
      my $stage = (getStage() eq "prod" ? "stage/" : "");

      my @items=($uor);
      $uor=getCachedGroupOrIsolatedPackage($uor);
      # dependencies that are other units of release (groups or isolated pkgs)
      if (my @grps=getAllGroupDependencies($uor)) {
	  push @items,@grps;
      }

##<<<TODO: GPS:
##	get all dependencies recursively for strong dependencies
##	get all dependencies, but not recursively for weak dependencies
##	make sure we end up with unique names on the list
##	see if we can push strong dependencies on the list before weak deps
##     (The following just gets direct dependants)
#      my @dependencies = $uor->getDependants();
#      unshift @dependencies, $uor unless (substr($uor,0,6) eq "bbinc/");
      my @dependencies = map { /^bbinc\b/ ? () : $_ } @items;
      unshift @dependencies, "bbinc";

      # check for cached include path and add custom additions
      if (exists $includePathCache{$uor}) {
	  # (This is not cached because it might change as tests such as
	  #  'gob' generate contents in the compiletmp include directory)
	  my $IncludeTmp = getIncludeTmp();
	  my $compiletmp = "";
	  foreach my $dep ($uor, @dependencies) {
	      $compiletmp .= " -I".$IncludeTmp."/".$dep
		if is_existing_path($IncludeTmp."/".$dep, 1);
	  }

	  # Include the BDE STL header location only for cpp files because
	  # the headers supplied by the STLport conflict with stdC headers
	  my $bde_stlport =
	    (ref($file) && $file =~ /\.cpp$/ && grep /^bde$/, @items)
	    ? " -I/bbsrc/${stage}proot/include/stlport"
	    : "";

	  return $compiletmp
		.$includePathCache{$uor}
		.$bde_stlport;

	  # (pcomp provides these; may need this once "metadata pcomp" exists
	  #my $default_inc = " -I/bbsrc/bbinc -I/bbsrc/bbinc/Cinclude";
	  #return $compiletmp
	  #	.$includePathCache{$uor}
	  #	.$bde_stlport
	  #	.$default_inc;
      }

      my @locns;

      foreach my $include (getCSDataIncludes()) {
	  foreach my $dep ($uor, @dependencies) {
	      push @locns, $include."/".$dep
		if is_existing_path($include."/".$dep);
	  }
      }

      # add local includes
      push @locns, getLocalIncludes if (scalar getLocalIncludes);

      # (always false at present)
      # ($uor will never be a grouped package; it'll be the package group)
      # (bde_verify should handle this rather than exploding #'s of -I rules)
      # (probably need to do the below if part of bde_build.pl)
      # for packages in groups, the package itself and other pkgs in the group
      #if (isGroupedPackage $uor) {
      #    if (my @pkgs=getAllInternalPackageDependencies($uor)) {
      #      push @items,@pkgs;
      #     }
      #}

      my $root=getRoot();
      my $locn;
      foreach my $item (@items) {
          # deployed and rolled-up header locations
          $locn = isPackage($item)
	    ? $root->getRootLocationFromPackage($item)
            : $root->getRootLocationFromGroup($item);
          $locn.=$FS."include".$FS.(getPackageGroup($item) || $item);
	  if (-d $locn) {
	      push @locns,$locn;
	  }
	  elsif ($item eq $uor && !(isLegacy($item) or isThirdParty($item))) {
	      debug3("SKIPPING -I rule for nonexistent location: $locn");
	  }

          # for legacy stuff and stuff that's not rolled up, add direct locns
          # (placed after the 'include' locations so rolled-up headers are seen
          # first, for libraries that are being built that way)

	  next unless $item eq $uor;  # only want to do this for target uor

	  ##<<<TODO: technically, only need if stage eq STAGE_DEVELOPMENT, too
	  ##   but we don't have the stage information here.  We should
	  ##   pass around the changeset to enable $csid->getStage()
	  ##   (need to do this if isApplication())
          push @locns,$root->getPackageLocation($item) if isApplication($item);

	  ##   (need to do the below if part of bde_build.pl)
          #if (isPackage $item) {
          #    push @locns,$root->getPackageLocation($item);
          #} else {
          #    push @locns,map {
          #        $root->getPackageLocation($_)
          #    } getCachedGroup($item)->getMembers();
          #}
      }

      # Special-case the BDE library suite until they are actually released
      # and deployed like other Robocop-managed software
      #push @locns, "/bbsrc/${stage}bbinc/Cinclude/bde"
      #	if (grep /^(?:bae|bce|bde|bse|bte)$/, @items);

      # (remove 3ps includes once they are configured as UORs)
      # (applications return true for offline-only)
      my $bbfa_hack = $uor->isOfflineOnly()
        ? get3psIncludePath($platform)
        : "";
      # offlines can depend on 'glib' (which is not 'bbglib')
      # (remove when the duplicate glib problem is properly resolved)
      # NOTE: this does not recognize versions of glib
      my $glib_hack = dependsOn($uor,"glib")
        ? " -I/bbs/glib/include"
        : "";

      $includePathCache{$uor}= $bbfa_hack.$glib_hack
			     . (@locns ? " -I".(join " -I",@locns) : " ");

      # recurse to check for 3ps and BDE STLport append
      return _getIncludePath($uor,$platform,$file);
  }
}

#---

sub dependsOn ($$) {
    my ($file,$dlib)=@_; # file object or UOR
    my $lib;

    if (ref $file) {
	if ((UNIVERSAL::isa($file,"BDE::Package")) ||
	    (UNIVERSAL::isa($file,"BDE::Group"))) {

	    $lib=$file->toString();
	} else {
	    $file->getLibrary();
	}
    } else {
	$lib=getPackageGroup($file) || $file;
    }

    foreach my $grp (getAllGroupDependencies($lib)) {
	return 1 if $grp eq $dlib;
    }

    return 0;
}

sub dependsOnBDE ($) {
    return dependsOn($_[0],"bde");
}

sub createTestHdrSrc($$) {
    my($hdr,$destDir)=@_;

    my $fh = new IO::File;
    my $src = $hdr;
    if ($hdr =~ /\.(?:inc|ins)$/) {
        $src .= ".f";
    } else {
        my ($rc,$results) = isCplusPlus($hdr);
        return(0, $results) if !$rc;
	$destDir =~ s/\.h$/\.t/;
        $src = $destDir.($results ? ".cpp" : ".c");
    }
    return(0, "cannot open $src: $!") unless open($fh, ">$src");

    my $uor = getCachedGroupOrIsolatedPackage($hdr->getLibrary);
    my $relpath="";
    my $subdir = $hdr->getTrailingDirectoryPath;
    $subdir .= "/" if $subdir;

    if ($uor eq "bbinc/Cinclude") {
	$relpath.= $subdir;
    }
    elsif($uor->isRelativePathed) {
	$relpath = $uor ne "bbglib" ? $hdr->getLibrary."/" : "glib/";
	$relpath.= $subdir;
    }

    if ($src =~ /\.c(?:pp)?$/) {
        print $fh "#include \"".$relpath.basename($hdr)."\"\n";
	print $fh "static void foo () {}"
    } else {
        print $fh "      include \'".basename($hdr)."\'\n       END\n";
    }
    return(0, "cannot close $src: $!") unless close($fh);
    return(1, $src);
}

{ ## cache the best host
  ## (must revisit caching if this code gets moved to a library)
  my %best_host;

  sub get_best_host ($;$) {
    my ($platform, $bldomachine) = @_;
    return $best_host{$platform} if $best_host{$platform};

    ##<<<TODO: should this be done once per changeset (and then cached),
    ##         or once for each and every remote command?

    my $host;
    my $retry = 0;
    my $command;
    if((exists $ENV{PLINK_GRIDENABLE} && defined $ENV{PLINK_GRIDENABLE} && 
	($ENV{PLINK_GRIDENABLE} eq 'no' || $ENV{PLINK_GRIDENABLE} eq '0'))
       || getpwuid($<) eq 'op') {
	$command = GETBESTHOST." -a ".$platform;
    }
    else {
	$command = GETBESTHOST." --ring LNKW-BLDO -a ".$platform;
    }

    ## find host to execute on
    ## (rudimentary retry if get_best_host fails)
    ## (Util::Retry::retry_output3 not used b/c we don't want to wait forever)
    while ($retry++ < 5) {
	$host = `$command`;
	if ($? == 0) {
	    chomp $host;
	    return ($best_host{$platform} = $host);
	}
    }
    alert("get_best_host failed ($?): $!\n");
    return undef;
  }
}

{ ## cache the best host
  ## (must revisit caching if this code gets moved to a library)
  my %host_list;

  sub get_host_list($) {
    my $platform = shift;
    return $host_list{$platform} if $host_list{$platform};

    ##<<<TODO: should this be done once per changeset (and then cached),
    ##         or once for each and every remote command?

    my $list;
    my $retry = 0;
    my $command = LNKWGETHOSTS." --ring LNKW-PLINK";
    
    ## find host to execute on
    ## (rudimentary retry if get_host_list fails)
    ## (Util::Retry::retry_output3 not used b/c we don't want to wait forever)
    while ($retry++ < 5) {
	$list = `$command`;
	chomp $list;
	if ($? == 0) {
	    $list =~ s/ibm\d*//g if $platform eq $sun; 
	    $list =~ s/sundev\d*//g if $platform eq $ibm; 
	    return ($host_list{$platform} = $list);
	}
    }
    alert("get_host_list failed ($?): $!\n");
    return undef;
  }
}

# Execute $cmd in $directory for $platform; actual host is
# determined by 'get_best_host'.  Returns 0 for success, else 1.
#
sub execRmtCommand($$$$$;$) {
    my($tag,$platform,$dir,$bfile,$cmd,$xlC8test) = @_;
    $cmd = "echo 'f77' >/dev/null; exec 2>&1; cd $dir && $cmd";
    
    # get the host list as sent by user.
    my @gotohosts = isPresentHostList();
    my $host = undef;
    my $count = scalar(@gotohosts);
    if($count > 0) {
	my $list = get_host_list($platform) || return 1;
	for my $temp (@gotohosts) {
	    # check whether gotohost is in the plink list.
	    if ($list =~ /$temp/) {
		$host = $temp;
		last;
	    }	
	}
	
	if (!defined $host && $platform eq $ibm) {
	    error "WARNING: Compilation Skipped on IBM as requested.";
	    return 0;
	}
	if (!defined $host && $platform eq $sun) {
	    error "ERROR: SunOS hostname should be present in --host list.";
	    return 1;
	}
    }
    
    # if process is robocop/run by cscheckin then run compile tests 
    # on new build machines. 
    my $process_real_username = getpwuid($<);

    if($process_real_username eq "robocop" && !@gotohosts) {
	$host = get_best_host($platform,1)
	    || return 1;
    }
    else {
	$host = get_best_host($platform)
	    || return 1;
    }
   
    $cmd = $host ne localHost()
      ? "/usr/local/bin/ssh -x $host \"$cmd; echo ".$$." \\\$?\""
      : "$cmd;echo ".$$." \$?\"";
    # run command
    $cmd =~ /^(.*)$/ and $cmd=$1; #untaint - <<<TODO this is too coarse
    debug($cmd);

    my $out = `$cmd`;
    my $rv = $?;
    chomp $out;
    
    my $rc = 1;  # default to failure code
    if (!$out) {
	$out =
	  "\nno output from backticks: \$?: $?\nhost:\n$host\ncommand:\n$cmd";
    } elsif ($rv != 0) {
	$out =
	  "\nbackticks error: \$?: $?\nhost: $host\n"
	 ."command:\n$cmd\noutput:\n$out";

        ####   xlc8 transition code begins
        if (($xlC8test) && ($out =~ /\(U\)/)) {
            my $logFile = getLogFile();
            my $mailxMikeGcmd = "echo $logFile | /usr/bin/mailx -s \"IBM xlC8 U error found\" mgiroux\@bloomberg.net";
            system($mailxMikeGcmd);
        }
        ####   xlc8 transition code ends

    } elsif ($out =~ s/$$ (-?\d+)$//) {
	$rc = $1;
    } else {
	$out =
	  "\nerror code not set, host: $host\n"
	 ."command:\n$cmd\noutput:\n$out";
    }

    logMsg($bfile,$tag,$platform,$host,$out) if ($rc || $out =~ /warning:/s);
    return $rc;
}

sub min_incs ($;$) {
    my $uor = $_[1];
    ## skip this optimization for applications and offline-only libraries
    ## which might have custom -I rules instead of including headers
    ## relative-pathed from offline-only libs
    ## (disabled: header-deploy-check.pl deploys offline headers to 00offlonly)
    #return $_[0]
    #  if $uor && getCachedGroupOrIsolatedPackage($uor)->isOfflineOnly();
    $uor ||= "f_[^/]+";  # handle case where $uor is not defined
    #my $re = qr%^/bbsrc/${stage}proot/include/(?:f_[^/]+|$uor|gtk[^/]+init)$%;
    ##<<<TODO: /bbsrc/proot/include is added by pcomp 
    ##        (to 00deployed and 00depbuild)
    ## (Still need -I rule into proot/include for the UOR and biglets,
    ##  in case its header are not published to proot/include)
    ## (if ever uncommented, $stage is not integrated in length or string match)
    #return " ".join " ",grep{substr($_,0,21) ne "/bbsrc/proot/include/"||/$re/}

    my $stage = (getStage() eq "prod" ? "stage/" : "");
    my $filter_path = "-I/bbsrc/${stage}proot/include/";
    my $filter_len  = length($filter_path);
    return " ".join " ",grep { substr($_,0,$filter_len) ne $filter_path }
			     split ' ',$_[0];
}

sub min_gob_incs ($$) {
    my $uor = shift;
    my $re  = qr%/$uor$%;
    return " ".join " ",grep { /$re/ } split ' ',$_[0];
}

#------------------------------------------------------------------------------
# Actions
#------------------------------------------------------------------------------

sub pcompTest ($$$;$) {
    my ($platform,$file,$symbol_oracle_test,$header_testing)=@_;
    my $starttime = time;
    $header_testing = 0 unless $header_testing;
    $symbol_oracle_test = 0 unless $symbol_oracle_test;
    #+++ object set - sanity check
    fatal("Not a Change::File") unless ref $file and
      UNIVERSAL::isa($file, "Change::File");

    my $uor=$file->getLibrary();
    my $bfile = basename($file);
    my $tag = "pcomp";
    verbose("$tag $bfile\@$uor ($platform)...");
    my $dobde=dependsOnBDE($uor) ? " -bde -exception" : "";
    # -DBDE_API was added to allow compilation of code using BBFA libraries.
    # BBFA defines BDE_API macro for code that uses BDE STL and defining this
    # macro at compile time is necessary for correct compilation of such code.
    my $cmd = $dobde." -c -pthread".
      ($bfile =~ /\.cpp$/ ? " -DBDE_API " : "").
      min_incs(getIncludePath($uor,$platform,$file),$uor)." $bfile";
   
    my $tmpdir1=getPcompTmp($platform);
    ## (do ROBOPCOMP second so that is the object left around for binary tests)
    my $rc = 0; # disabled second test for Sun Fortran; we've moved to Studio 8
    #my $rc= ROBOPCOMP ne DEFAULTPCOMP && $platform eq $sun && $bfile =~ /\.f$/
    #  ? execRmtCommand($tag,$platform,$tmpdir1,$bfile,DEFAULTPCOMP.$cmd)
    #  : 0;
    my $tmpdir=getRobopcompTmp($platform);
    my $rc2=execRmtCommand($tag,$platform,$tmpdir,$bfile,ROBOPCOMP.$cmd);
    if ($rc2) {
      $rc2=execRmtCommand($tag,$platform,$tmpdir,$bfile,"PLINK_DEBUG=1 ".ROBOPCOMP.$cmd);
    }

    #+++ object set: add a corresponding object file to the objset
    if (!$rc and !$rc2 and !$header_testing
	and $symbol_oracle_test == 1) {
	my $ofile=$file->clone();
	my $object="$tmpdir/$bfile";
	$ofile->setSource($object);
	my $subs = $platform eq $sun ? '.sundev1.o' : '.ibm.o';
	$object=~s/\.\w+$/$subs/;
	$ofile->setDestination($object);
	flock($osetfh{$platform}, LOCK_EX);
	my $osetfh = $osetfh{$platform};
	print $osetfh $ofile->serialise(),"\n";
	flock($osetfh{$platform}, LOCK_UN);
	verbose("Added " . $ofile->serialise(). " to the symbol changeset");
    } else {
      if ($platform eq $sun) {
	verbose("Adding to object set failed, rc $rc, rc2 $rc2, header testing $header_testing");
      }
    }

    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", (($rc | $rc2) ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc | $rc2, header test $header_testing oracle: $symbol_oracle_test step time $endtime");
    return ($rc|$rc2);
}

sub hdrCompTest ($$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $uor=$file->getLibrary();
    my $bfile = basename($file);

    my $hpath=getHdrCompTmp($platform)."/".$bfile;
    return 0;
    if(checkCompileHeaderList($file)) {
	alert "$bfile not test compiled on $platform per configuration.";
	return 0;
    }

    my $tag = "pcomp header";
    verbose("$tag $bfile\@$uor ($platform)...");
    my($rc,$results) = createTestHdrSrc($file,$hpath);
    if (!$rc) {
        logMsg($bfile,$tag,$platform,$platform,$results);
        return 1;
    }
    $results =~ /\.(\w+)$/;
    alert("test compiling $bfile as ".
	  ($1 eq "f"?"fortran":($1 eq "c"?"c":"c++"))." source");

    my $hfile=new Change::File($file->serialise());
    $hfile->setSource($results);
    $hfile->setDestination($results);
    $rc = pcompTest($platform,$hfile,0,1);
    $results =~ s/\.c(?:pp)?$//;
    verbose "\nCleaning up the header file objects.";
    my $cmd = "rm -r $results* 2>&1";
    debug($cmd);
    my $out = `$cmd`;
    debug($out);
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc step time $endtime");
    return $rc;
}

sub inc2HdrTest ($$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $uor=$file->getLibrary();
    my $relfile = $file->getTarget().'/'.basename($file);
    my $tag = "inc2hdr";
    verbose("$tag $relfile ($platform)...");
    ## modified from getIncludePath($uor,$platform) to have only ../bbinc paths
    my $path = " ".join(" ",map {"-I$_"} getLocalIncludes);
    my $include = getIncludeTmp();
    $path .= " -I".$include."/bbinc" if is_existing_path($include."/bbinc", 1);
    foreach $include (getCSDataIncludes()) {
	$path.=" -I".$include."/bbinc" if is_existing_path($include."/bbinc");
    }
    my $cmd = INC2HDR.$path." $relfile .";
    my $rc = execRmtCommand($tag,$platform,getInc2HdrTmp($platform),
			  $relfile,$cmd);
    if (!$suppress_status_messages) {
      print "$tag $relfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $relfile ($platform): status $rc step time $endtime");
    return $rc;
}

sub gobTest ($$$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $uor=$file->getLibrary();
    my $bfile = basename($file);
    my $tag = "gob";
    verbose("$tag $bfile\@$uor ($platform)...");
    my $cmd = GOB." ".
        min_gob_incs($uor,getIncludePath($uor,$platform,$file)).
	(isGobWerrorException($uor,$bfile) ? "" : " --exit-on-warn").
	" $bfile";
        
    # OCaml option processing needs space after each "-I":
    $cmd =~ s/(?<=\s)-I(?=[^\s])/-I /g;
    my $rc = execRmtCommand($tag,$platform,getGobTmp($platform),$bfile,$cmd);
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc step time $endtime");
    return $rc;
}

sub smrgTest ($$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $bfile = basename($file);
    my $tag = "smrgNT";
    verbose("$tag $bfile ($platform)...");
    my $tmpdir = getSmrgTmp($platform);

    # Since the .ins output file generated from smrgNT does not have to have
    # the same base name as the .ml input file, the only way to see if a .ins
    # file was actually created is to check how many .ins files are in the
    # directory before and after running smrgNT.
    my @old_ins_files = <$tmpdir/*.ins>;

    my $cmd = SMRG." $bfile.error -batch $bfile -robo";
    my $rc = execRmtCommand($tag,$platform,$tmpdir,$bfile,$cmd);
    my $endtime = time - $starttime;
    if ($rc == 0) {
        my @new_ins_files = <$tmpdir/*.ins>;
	logMsg($bfile,$tag,$platform,$platform,
	       "smrgNT returned 0 but did not generate .ins file"), $rc = 1
                   unless (scalar @new_ins_files) > (scalar @old_ins_files);
        verbose("Generated ins files: ", @new_ins_files);
    }
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    return $rc;
}

sub lexTest ($$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $bfile = basename($file);
    # remove .l and get the name of the file
    my $prefix = substr($bfile,0,-2);
    if($prefix =~ /\./) {
	fatal "Lex filename should not have prefix with '.'. Prefix: $prefix";
    }
    my $tag = "lex";
    verbose("$tag $bfile ($platform)...");
    my $cmd = LEX." -P$prefix -o${prefix}_lex.c $bfile";
    #return execRmtCommand($tag,$platform,dirname($file),$bfile,$cmd);
    my $rc =execRmtCommand($tag,$platform,getLexTmp($platform),$bfile,$cmd);
    my $endtime = time - $starttime;
    verbose("$tag $bfile ($platform): status $rc step time $endtime");
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    return $rc;
}

sub yaccTest ($$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $bfile = basename($file);
     # remove .l and get the name of the file
    my $prefix = substr($bfile,0,-2);
    if($prefix =~ /\./) {
	fatal "yacc filename should not have prefix with '.'. Prefix: $prefix";
    }
    my $tag = "yacc";
    verbose("$tag $bfile ($platform)...");
    my $cmd = YACC." -d -l -p$prefix -o${prefix}_yacc.c $bfile";
    my $rc = execRmtCommand($tag,$platform, getYaccTmp($platform),$bfile,$cmd);
    my $endtime = time - $starttime;
    verbose("$tag $bfile ($platform): status $rc step time $endtime");
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    return $rc;
}


sub pcompLexYaccTest ($$$;$) {
    my ($platform,$file,$symbol_oracle_test,$header_testing)=@_;
    #+++ object set - sanity check
    fatal("Not a Change::File") unless ref $file and
      UNIVERSAL::isa($file, "Change::File");

    my $starttime = time;
    my $uor=$file->getLibrary();
    my $bfile = basename($file);
    my $srcfile;
    my $tmpdir;

    # lex file
    if($bfile =~ /\.l$/) {
	$srcfile = substr($bfile,0,-2)."_lex.c";
	$tmpdir = getLexTmp($platform);
    }
    else {
	$srcfile = substr($bfile,0,-2)."_yacc.c";
	$tmpdir = getYaccTmp($platform);
    }
    
    my $tag = "pcomp";
    verbose("$tag $srcfile\@$uor ($platform)...");
    my $dobde=dependsOnBDE($uor) ? " -bde -exception" : "";
    # -DBDE_API was added to allow compilation of code using BBFA libraries.
    # BBFA defines BDE_API macro for code that uses BDE STL and defining this
    # macro at compile time is necessary for correct compilation of such code.
    my $cmd = $dobde." -I$tmpdir -c -pthread".
      ($srcfile =~ /\.cpp$/ ? " -DBDE_API " : "").
      min_incs(getIncludePath($uor,$platform,$file),$uor)." $srcfile";
    

    my $rc2=execRmtCommand($tag,$platform,$tmpdir,$srcfile,ROBOPCOMP.$cmd);

    #+++ object set: add a corresponding object file to the objset
    if (!$rc2 and !$header_testing
	and $symbol_oracle_test == 1) {
	my $ofile=$file->clone();
	my $object="$tmpdir/$srcfile";
	$ofile->setSource($object);
	my $subs = $platform eq $sun ? '.sundev1.o' : '.ibm.o';
	$object=~s/\.\w+$/$subs/;
	$ofile->setDestination($object);
	flock($osetfh{$platform}, LOCK_EX);
	my $osetfh = $osetfh{$platform};
	print $osetfh $ofile->serialise(),"\n";
	flock($osetfh{$platform}, LOCK_UN);
	verbose("Added ", $ofile->serialise(), " to object set");
    } else {
      if ($platform eq $sun) {
	verbose("Not added to object set, rc2: $rc2 header_testing: $header_testing platform: $platform");
      }
    }

    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc2 ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc2 step time $endtime");

    return ($rc2);
}


sub pcompGobTest ($$$$) {
    my ($platform,$file,$ext,$symbol_oracle_test)=@_;

    my $starttime = time;
    my $uor=$file->getLibrary;

    #+++ object set - sanity check

    my $bfile = basename($file);
    my $tag = "pcomp gob";
    verbose("$tag $bfile\@$uor ($platform)...");
    my $dobde=dependsOnBDE($uor) ? " -bde -exception" : "";
    my $srcFile = substr($bfile, 0, length($bfile)-length($ext)-1);
    
    # check if it is C or C++ gob file 
    my $tmpFile = ($ext eq "gmm" && -f getGobTmp($platform)."/$srcFile.cpp")
      ? "$srcFile.cpp"
      : "$srcFile.c";

    my $cmd = $dobde." -c -pthread ".
      min_incs(getIncludePath($uor,$platform,$file),$uor)." $tmpFile";

    my $tmpdir=getGobTmp($platform);
    #my $rc=0;
    ## [if this is re-enabled, see pcompTest()]
    ## (do ROBOPCOMP second so that is the object left around for binary tests)
    #my $rc= ROBOPCOMP ne DEFAULTPCOMP && $platform eq $sun
    #  ? execRmtCommand($tag,$platform,$tmpdir,$bfile,DEFAULTPCOMP.$cmd)
    #  : 0;
    
    my $rc=0;
    my $cppflag = 0;

    # check if it is wrapper gob file which will generate c and c++ wrappers 
    # we should add this cpp object only if cpp would go in library 
    if (($ext eq "gob" || $ext eq "gwp")
	&& isValidFileType($file->getProductionTarget, ".cpp") 
	&& -f getGobTmp($platform)."/$srcFile-cpp.cpp") {
	# this means it is .gwp kind file
	$cppflag=1;
	my $cmd1 = $dobde." -c -pthread ".
	    min_incs(getIncludePath($uor,$platform,$file),$uor).
	    " $srcFile-cpp.cpp";
	$rc=execRmtCommand($tag,$platform,$tmpdir,$bfile,ROBOPCOMP.$cmd1);	
    }
    my $rc2=execRmtCommand($tag,$platform,$tmpdir,$bfile,ROBOPCOMP.$cmd);

    #+++ object set: add a corresponding object file to the objset
    if (!$rc and !$rc2
	and $symbol_oracle_test == 1) {
	my $ofile=$file->clone();
	my $object="$tmpdir/$bfile";
	$ofile->setSource($object);
	my $subs = $platform eq $sun ? '.sundev1.o' : '.ibm.o';
	$object=~s/\.\w+$/$subs/;
	$ofile->setDestination($object);
	flock($osetfh{$platform}, LOCK_EX);
	my $osetfh = $osetfh{$platform};
	print $osetfh $ofile->serialise(),"\n";	
	flock($osetfh{$platform}, LOCK_UN);
	verbose("Added ", $ofile->serialise(), " to object set");
	
	if($cppflag == 1) {
	    my $object1="$tmpdir/$bfile";
	    $object1=~s/\.\w+$/-cpp$subs/;
	    $ofile->setDestination($object1);
	    flock($osetfh{$platform}, LOCK_EX);
	    print $osetfh $ofile->serialise(),"\n";
	    flock($osetfh{$platform}, LOCK_UN);
	    verbose("Added ", $ofile->serialise(), " to object set");
	}
    }

    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", (($rc | $rc2) ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc | $rc2 step time $endtime");

    return ($rc|$rc2);
}

sub gccWallTest ($$$) {
    my ($platform,$file,$opts)=@_;
    my($werror,$gccwarnings,$ansi) = @$opts{"Werror","gccwarnings","gcc-ansi"};
    my $starttime = time;

    ##<<<TODO this needs to be in a more useful abstraction
    my %extraCompilerOpts = (
        $sun => [ qw(
            -pthreads
            -D_REENTRANT
            -DBB_THREADED
            -D__FUNCTION__=__FILE__
            -D_SUN_SOURCE
            ) ],

        $ibm => [ qw(
            -pthread
            -D_THREAD_SAFE
            -D__VACPP_MULTI__
            -DBB_THREADED
            -D_IBM_SOURCE
            -DMAXHOSTNAMELEN=64
            ) ],
    );

    my $stage = (getStage() eq "prod" ? "stage/" : "");
    my $uor=$file->getLibrary();
    my $bfile = basename($file);
    my $is_cpp = $bfile =~ /\.cpp$/;

    my $tag = $is_cpp ? "g++ -Wall ..." : "gcc -Wall ...";
    verbose("$tag $bfile\@$uor ($platform)...");

    # display gcc warnings by default (unless --nogccwarnings specified)
    # (-w *must not* be specified with -Werror)
    $gccwarnings = 1 unless (defined $gccwarnings && !$werror);

    ##<<<TODO temporary until TSMV -Werror is turned on for C++
    $werror = 0 if $is_cpp;

    ##<<<TODO get these from default.opts or some other central place!
    my $extra = join(" ", @{$extraCompilerOpts{$platform}});

    # -DBDE_API was added to allow compilation of code using BBFA libraries.
    # BBFA defines BDE_API macro for code that uses BDE STL and defining this
    # macro at compile time is necessary for correct compilation of such code.
    my $bde_api = ($is_cpp && dependsOnBDE($uor)) ? " -DBDE_API" : "";

    my $cmd=($is_cpp
		? GPP.$bde_api." -fno-implicit-templates" 
		: GCC." -Wmissing-declarations").
	($ansi   ? " -ansi"   : "").
	($werror ? " -Werror" : "").
	" -Wall".($gccwarnings || $werror ? "" : " -w").
	" -Wno-unknown-pragmas -Wno-unused -Wno-char-subscripts".
	" -Dlint ".$extra.
	getIncludePath($uor,$platform,$file).
        " -I/bbsrc/${stage}bbinc -I/bbsrc/${stage}bbinc/Cinclude".
	" -c $bfile";

    my $rc = execRmtCommand($tag,$platform,getGccTmp($platform),$bfile,$cmd);
    ## Because ACE and fab currently do not pass g++ compile tests,
    ## we run the g++ test, but a non-zero exit is not a failure for cscompile
    $rc = 0 if $is_cpp;
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc step time $endtime");
    return $rc;
}

# xlc8 test to be performed for cpp files
sub xlc8Test ($$) {
    my ($platform,$file)=@_;

    my $starttime = time;
    my $uor=$file->getLibrary();
    my $bfile = basename($file);
    #message "running xlC8 ... $bfile";
    my $tag = "xlc8 -Wall ...";
    verbose("$tag $bfile\@$uor ($platform)...");
    my $stage = (getStage() eq "prod" ? "stage/" : "");

    ##<<<TODO get these from default.opts or some other central place!
    my $extra = $platform eq "AIX"
      ? "-D_IBM_SOURCE -DMAXHOSTNAMELEN=64 "
      : "-D_SUN_SOURCE -D__FUNCTION__=__FILE__ ";

    # -DBDE_API was added to allow compilation of code using BBFA libraries.
    # BBFA defines BDE_API macro for code that uses BDE STL and defining this
    # macro at compile time is necessary for correct compilation of such code.
    my $bde_api = (dependsOnBDE($uor)) ? " -DBDE_API" : "";

    my $cmd="/bb/util/version8-122006/usr/vacpp/bin/xlC_r ".$bde_api.
	    " -qpath=ILbcmld:/bb/util/xlC8-20070112/exe/ -qlanglvl=staticstoreoverlinkage".
	    " -qalias=noansi -qxflag=tocrel -qtbtable=small -qrtti=all -qfuncsect=noimplicitstaticref".
            " -qxflag=inlinewithdebug -qsuppress=1501-201 -qsuppress=1500-029 -qsuppress=1540-2910 ".
	    # directory cache for compiler. Arg 1 is a prime between 2
	    # and 71 (go IBM!) and the second is the number of
	    # elements in the per-dir cache. (Between 1 and 999)
	    " -qxflag=dircache:71,100 ".
	    $extra.min_incs(getIncludePath($uor,$platform,$file),$uor).
	" -I/bbsrc/${stage}proot/include/00depbuild".
	" -I/bbsrc/${stage}proot/include/00deployed".
	(getCachedGroupOrIsolatedPackage($uor)->isOfflineOnly()
	  ? " -I/bbsrc/${stage}proot/include/00offlonly"
	  : "").
	" -I/bbsrc/${stage}proot/include/stlport".
	" -I/bbsrc/${stage}bbinc".
	" -I/bbsrc/${stage}bbinc/Cinclude".
	" -c $bfile";
   
    my $rc = execRmtCommand($tag,$platform,getXlcTmp($platform),$bfile,$cmd,1);
    # not non-fatal any more...
    # $rc = 0;
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc step time $endtime");
    return $rc;
}

sub bssSizeCheckTest ($$$$) {
    my ($platform,$uor,$bfile,$objPath)=@_;
    $objPath =~ /^(.*)$/ and $objPath=$1; #untaint - <<<TODO this is too coarse

    my $starttime = time;
    my $tag = ".bss size check";
    verbose("$tag $bfile\@$uor ($platform)...");

    my @cmd = ("/usr/ccs/bin/size","-f",$objPath);

    ## (execute remote command, capturing output)
    my $host = get_best_host($platform)
      || return 1;
    $host =~ /^(.*)$/ and $host=$1; #untaint - <<<TODO this is too coarse
    @cmd = ("/usr/local/bin/ssh","-x",$host,"@cmd")
      if ($host ne localHost());
    my($pid,$output);
    {
	my $PH = Symbol::gensym;
	$pid = open($PH, '-|', @cmd);
	local $/ = undef;
	$output = <$PH> if defined $pid;
	close $PH;
    }
    unless (defined($pid) && $? == 0) {
	error("error executing: @cmd: $!");
	return 1;
    }
    ## (execute remote command, capturing output)

    my $rc = ($output =~ /(\d+)\(\.bss\)/s)
      ? !bssSizeCheck($bfile,$objPath,$1)
      : 0;  # allow file to pass if (.bss) not present in size -f output
    if (!$suppress_status_messages) {
      print "$tag $bfile ($platform): ", ($rc ? 'failed' : 'succeeded'), "\n";
    }
    my $endtime = time - $starttime;
    verbose("$tag $bfile\@$uor ($platform): status $rc step time $endtime");
    return $rc;

}

sub newSymbolValidationTest {
  my ($platform, $symbolfile) = @_;

  my $starttime = time;
  my $tag = "new symbol validation check";
  verbose("$tag ($platform)...");

  my $cmd = "$FindBin::Bin/bde_validate_changeset_wrapper.pl $symbolfile";
  my $rc;
  eval {
    local $SIG{ALRM} = sub {die "alarm\n"};
    alarm(20*60); # 20 minute timeout
    $rc = execRmtCommand($tag, $platform, getSymValTmp($platform), basename($symbolfile), $cmd);
    alarm 0;
  };

  # Did we timeout?
  $rc = 1 if $@;
  my $endtime = time - $starttime;
  verbose("$tag ($platform): status $rc step time $endtime");

  # For now we unconditionally succeed
  if ($platform eq $sun && VALIDATE_NEW_ORACLE_SOLARIS) {
    return $rc;
  }
  if ($platform eq $ibm && VALIDATE_NEW_ORACLE_AIX) {
    return $rc;
  }

  return 0;

}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------

{ my $root;

  sub setRoot($;$) {
      my($stage,$where)=@_;

      $root=getStageRoot($stage);
      $root->setRootLocation($where) if $where;
      # beware, don't use -w with -s unless you really intend it...

      BDE::Util::DependencyCache::setFileSystemRoot($root);
      return $root;
  }

  sub getRoot { return $root; }
}

{ my $stage;

  sub setStage($) {
      $stage = shift;
  }

  sub getStage { return $stage; } 
}

  # Should return S, R, or ? based on what type of emove the day is.
  sub get_cur_emov_day {
      my $cs = shift;
      return 'R' unless $cs; # If we got an undef changeset, then we're
      # just going to go against 
      my $svc = Production::Services->new;
      my (@tasks, @libs);
      @tasks = $cs->getTasks;
      @tasks = ("ibig") unless @tasks;
      @libs = $cs->getTargets;
      @libs = ("acclib") unless @libs;
      my $stage = $cs->getStage;
      if (!defined $stage) {
          debug "switching to beta\n";
          $stage = "beta";
      }

      my $type = Production::Services::Move::getEmoveLinkType($svc, $stage,
                                                              @libs, @libs);
      my $retval;
#  print "----------------->$type $stage\n";
      if (defined $type && $type =~ /stage/i) {
          $retval = 'S';
      } else {
          $retval = 'R';
      }
#  $retval = 'R';
      return $retval;
  }



MAIN: {

    #--------------------------------------------------------------------------
    # setup
    #--------------------------------------------------------------------------

    # (make sure umask is consistent on files and directories created)
    umask(0002);

    #DRQS 7345438 caused this to set it explicitly.
    $ENV{TMPDIR}='/bb/data/tmp';

    error(CS_DATA." not accessible - please run from another host"),
        exit 1 unless -d CS_DATA;

    # figure out arch's
    error("both $sun and $ibm checkin disabled"), exit 1
      if skipArch($sun) and skipArch($ibm);
    if (skipArch($sun)) {
        localOS() eq $sun and fatal("$sun disabled - check in from $ibm");
        warning("$sun disabled");
        $sun = "";
    }
    if (skipArch($ibm)) {
        localOS() eq $ibm and fatal("$ibm disabled - check in from $sun");
        warning("$ibm disabled");
        $ibm = "";
    }

    # get options
    my $opts=getoptions();
    _setOpts($opts);
    
    # Set temp directory
    if ($opts->{dir}) {
        setTmp($opts->{dir});
        rmTmpOnExit(0);  # Don't delete directory on exit.
    } else {
        setTmp(CSCOMPILE_TMP."/$prog.$$.$^T");  # Generate temp name
    }

    if ($opts->{host} and $opts->{local}) {
        usage("--local and --local are mutually exclusive");
	exit EXIT_FAILURE;
    }
    # set host list for cscompile
    setHostList(@{ $opts->{host}}) if($opts->{host});
    setHostList(localHost()) if($opts->{local});
    #+++ object set: create a tempfile for streamed object set
    foreach my $platform ($sun, $ibm) {
      my $osetfh=new File::Temp(TEMPLATE => "objectset.$platform.".USER.".XXXXXX",
			     SUFFIX   => ".cs",
			     DIR      => CSCOMPILE_TMP,
			     UNLINK   => 0);
      fatal "Unable to create temporary file $osetfh: $!" unless $osetfh;
      chmod 0664,$osetfh;  ## File::Temp will create file 0600; we need g+rw
      $osetfh{$platform} = $osetfh;
    }

    # Don't delete temp directory if debugging
    rmTmpOnExit(0) if get_debug;

    setLocalIncludes(@{$opts->{include}}) if $opts->{include};

    # set the stage value as it may be called at many places.
    setStage($opts->{stage});

    # get staging root
    my $root = setRoot($opts->{stage},$opts->{where});

    # get plugin Manager
    my $manager=getPluginManager();
    $manager->plugin_initialize($opts);

    # get fileset
    my $fileset;
    if ($opts->{from}) {
	$fileset=load Change::Set($opts->{from});
	# for cscompile the 'destination' is the original source.
	$_->setDestination($_->getSource) foreach $fileset->getFiles();
	$opts->{stage} = $fileset->getStage();
    } elsif ($opts->{csid}) {
        my $svc=new Production::Services;
        $fileset = Production::Services::ChangeSet::getChangeSetDbRecord(
            $svc,$opts->{csid});
	fatal("Change set $opts->{csid} not found in database")
	    unless defined $fileset;
    } else {
	$fileset=parseArgumentsRaw($root,$opts->{stage},
				   $opts->{honordeps},
				   $opts->{to},@ARGV);
	$opts->{to} ||= getParsedTrailingLibraryArgument();
        $fileset->setID(undef);
    }

    $manager->plugin_pre_find_filter($fileset);

    # revalidate all components of the CS so no funny business can transpire
    # for example, oddly editied streamed changesets, or strange targets in
    # file maps.
    identifyArguments($root,$opts->{stage},
                     $opts->{honordeps},$opts->{to},$fileset);

     # move type, setup cs data area
    fatal("changset already has move type of ".$fileset->getMoveType()) if 
      $fileset->getMoveType() and 
        ($opts->{bugf} and $fileset->getMoveType() ne MOVE_BUGFIX or
         $opts->{emov} and $fileset->getMoveType() ne MOVE_EMERGENCY);
    if ($fileset->getMoveType()) {
        setMoveType($fileset->getMoveType());
    } elsif ($opts->{bugf}) {
        alert("compiling as bugfix");
        setMoveType(MOVE_BUGFIX);
    } elsif ($opts->{emov}) {
        alert("compiling as emov");
        setMoveType(MOVE_EMERGENCY);
    }
    $fileset->setMoveType(getMoveType());

    # cscompile --emov should mean prod so take care of that case.
    # cscompile -f should read from file and it does above
    #            to get the stage value
    # stage=prod will be set either by cscheckin OR provided by user
    # --emov will be provided by user
    if($opts->{stage} eq "prod" || $opts->{emov}) {
       # set stage to prod if stage value is not provided
       # AND in case --emov option is used
       $opts->{stage} = 'prod' if (!defined $opts->{stage}); 
       # why set here? because user 
       $fileset->setStage($opts->{stage});
	# we check this because it could be wednesday today
	# wednesday prod emovs mean different
	my $emovtype = get_cur_emov_day($fileset);
        print "\n Movetype per get_cur_emov_day: $emovtype";
	if ($emovtype eq 'R') {
	    $opts->{stage} = 'prea'; 
	    $fileset->setStage($opts->{stage});
	}
        else {
	    # set opts->where appropriately
            $opts->{where} = "/bbsrc/stage/proot";
            # root is set correctly previously to /bbsrc/proot
            # now we set it again only if stage = prod actually
            # root = locn/proot
            $root = setRoot($opts->{stage}, $opts->{where});
        }
	# re-set stage always
	setStage($opts->{stage});
	#print " \n **  after setRoot: $root";
    }

    debug2 "candidate set:\n",$fileset->listFiles();
    unless (keys %$fileset) {
        fatal "No changed or new files founds - aborted";
        exit EXIT_FAILURE;
    }

    # Load FindInc plug-in for all change sets with gtk library
    # John Belmonte, Andrew Paprocki, Eric lunde, Edward Christie are exempted
    # keep a copy of this fileset.
    my $copyfileset = $fileset->clone();
    unless ((USER eq "jbelmont") || (USER eq "apaprock") || (USER eq "echristi")
	    || USER eq "elunde1") {
	my $gtk_found=0;
	my %skiplibs=map { $_ => 1 } split /\s/,GTK_SKIP_FINDINC_LIBS;
	
	foreach my $target (sort $fileset->getLibraries) {
	    my $uor = getCachedGroupOrIsolatedPackage($target);
	    if(exists $skiplibs{$uor}) {
		next;
	    }
	    $gtk_found = ($uor->isGTKbuild() ? 1 : $gtk_found);
	}

	if ($gtk_found && !defined $opts->{nodependency}) {
	    my $plugin_name="FindInc";
	    my $mgr=getPluginManager();
	    $mgr->load($plugin_name);
	    push @{$opts->{plugin}}, $plugin_name ."=GTK,add";

            # load the NoRestricted plugin
            $mgr->load("NoRestricted");

            # Set recompilation file limit to 5000
	    $opts->{findinclimit} = 5000;
	    $mgr->plugin_initialize($opts);
	    fatal "Fatal error in plugin post-find filter - cannot proceed."
		unless $mgr->plugin_post_find_filter($fileset);
	}
    }
    
    # Load FindInc plug-in for TSMV users
    my $approval=checkApproval($fileset,APPROVELIST);
    my $FindInc_Loaded = 0;
    if ($approval eq "tsmv") {
	my $plugin_name="FindInc";
	my $mgr=getPluginManager();
	$mgr->load($plugin_name);
	push @{$opts->{plugin}}, $plugin_name ."=prompt";
	# Set recompilation file limit to 5000
	$opts->{findinclimit} = 5000;
	$mgr->plugin_initialize($opts);
	fatal "Fatal error in plugin post-find filter - cannot proceed."
	    unless $mgr->plugin_post_find_filter($fileset);
    }
    
    # ignore .t.<ext> files so that they dont get compiled
    # otherwise, set destination to source (required because we are
    # using parseArgumentsRaw instead of parseArgumentsAsSourceCS above)
    # (see Change::Arguments)
    foreach my $file ($fileset->getFiles) {
	my $leafname=$file->getLeafName();
	if($leafname =~ /\.t\.(\w)+$/) {
	    verbose "file $leafname ignored for compile";
	    $fileset->removeFile($file);
	}
	else {
	    $file->setDestination($file->getSource);
	}
    }

    #+++ object set: write object set header (from source set)
    foreach my $osetfh (values %osetfh) {
      writeObjectSetHeader($osetfh, $fileset, $opts->{compiletype});
    }

    if (my $csid=$fileset->getID) {
	setCSId($csid) if $csid=~/^\w/; #don't set if '<no id>'
    }
    #setupCSDataDirs();  # (unused at the moment)

    # source checks
    my $doTaskList = getDoTasks();
    if ($doTaskList =~/(all|source)/) {
        fatal "source checks failed"
	  unless checkChangeSet($fileset,$opts->{jobs});
	exit EXIT_SUCCESS if $doTaskList =~ "source";
    }

    # create base tmp directories
    createTmp();

    # populate work areas and check for orphan .inc files
    setupTmpFiles($fileset);

    # cache incpath
    #foreach my $target ($fileset->getTargets) { # might not all be defined
    foreach my $target ($fileset->getLibraries) {
	next if $target=~/^bbinc/; #special 'bbinc' case
	my $incpath=min_incs(getIncludePath(getCanonicalUOR($target),$sun,""));
	debug "Include path for $target: $incpath\n";
    }

    # start logging
    openLog();
    message("\n\ncscompile log: ",getLogFile(),"\n");

    # to keep tmp from being removed on task END
    cleanExit(0);

    #--------------------------------------------------------------------------
    # .h .ml .y .l .gob(1) .inc
    #--------------------------------------------------------------------------

    my @actions;

    ##<<<TODO: might create a table of gob files and what they produce
    ## so that table can be passed around to various compile test and copy subs
    ## GOB --depend-only to find out which files are generated
    ## (.h, -protected.h, c or cpp)
    
    for my $file (grep { /\.(?:inc|h|gob|gmm|gwp|ml|l|y)$/ } $fileset->getFiles) {
        if ($file =~ /\.inc$/) {
	    next unless (Inc2HdrRequired($file));
            push(@actions,new Task::Action
		 ({name=>"inc2hdr $file ($sun)",action=>\&inc2HdrTest,
		   args=>[$sun,$file]})) if $sun;
            push(@actions,new Task::Action
		 ({name=>"inc2hdr $file ($ibm)",action=>\&inc2HdrTest,
		   args=>[$ibm,$file]})) if $ibm;
        } elsif ($file =~ /\.h$/ and $doTaskList =~ /(header|all|binary)/) {
	    #<<<TODO: for now, headers are not test-compiled under 'all'
	    #<<<TODO: or under 'binary', only when requested explicitly.
            #<<<TODO: This relaxation will be removed once people have
            #<<<TODO: had time to adjust.
	    push(@actions,new Task::Action
		 ({name=>"pcomp $file ($sun)",action=>\&hdrCompTest,
		   args=>[$sun,$file]}
		 )) if $sun;
            push(@actions,new Task::Action
		 ({name=>"pcomp $file ($ibm)",action=>\&hdrCompTest,
		   args=>[$ibm,$file]}
		 )) if $ibm;
        } elsif ($file =~ /\.(?:gob|gmm|gwp)$/) {
            push(@actions,new Task::Action
		 ({name=>"gob $file ($sun)",action=>\&gobTest,
		   args=>[$sun,$file]}
                  )) if $sun;
            push(@actions,new Task::Action
		 ({name=>"gob $file ($ibm)",action=>\&gobTest,
		   args=>[$ibm,$file]}
                  )) if $ibm;
        } elsif ($file =~ /\.ml$/) {
            push(@actions,new Task::Action
		 ({name=>"smrgNT $file ($sun)",action=>\&smrgTest,
		   args=>[$sun,$file]})) if $sun;
            push(@actions,new Task::Action
		 ({name=>"smrgNT $file ($ibm)",action=>\&smrgTest,
		   args=>[$ibm,$file]})) if $ibm
        } elsif ($file =~ /\.l$/) {
            push(@actions,new Task::Action
		 ({name=>"lex $file ($sun)",action=>\&lexTest,
		   args=>[$sun,$file]})) if $sun;
            push(@actions,new Task::Action
		 ({name=>"lex $file ($ibm)",action=>\&lexTest,
		   args=>[$ibm,$file]})) if $ibm
        } elsif ($file =~ /\.y$/) {
            push(@actions,new Task::Action
		 ({name=>"yacc $file ($sun)",action=>\&yaccTest,
		   args=>[$sun,$file]})) if $sun;
            push(@actions,new Task::Action
		 ({name=>"yacc $file ($ibm)",action=>\&yaccTest,
		   args=>[$ibm,$file]})) if $ibm
        }
    }

    if (@actions) {
        my $mgr=new Task::Manager
	  ("running header, yacc, lex, gob and smrgNT checks".
	   (getCSId()?" for change set ".getCSId()."":""));
        $mgr->addActions(@actions);
	$mgr->setLogSub(\&alert);
        $mgr->run($opts->{jobs}) and cleanupAndExit(1);

        # copy generated headers to include
	# (.../bbinc and .../bbinc/Cinclude share .../bbinc dir in our cache)
	my $IncludeTmp = getIncludeTmp();
        globCp(getInc2HdrTmp(localOS()),"*.h",   $IncludeTmp."/bbinc");
        globCp(getSmrgTmp(localOS()),   "*.h",   getProdinsTmp());
        globCp(getSmrgTmp(localOS()),   "*.ins", getProdinsTmp());
	## (not quite ideal to throw yacc headers into Cinclude, but ok for now)
        globCp(getYaccTmp(localOS()),   "*.h",  $IncludeTmp."/bbinc");
	##<<<TODO: could be more efficient; might do this within gobTest()
        my $GobTmp = getGobTmp(localOS());
	for my $file (grep { /\.(gob|gmm|gwp)$/ } $fileset->getFiles) {
	    my $uor = $file->getLibrary();
	    my $bfile = basename($file);
	    substr($bfile,-4,4,'');  # remove '.gob' extension
	    ##<<<TODO: assumes .h and optionally -protected.h headers produced
	    cachedMkpath($IncludeTmp."/".$uor);
	    # create gcc directories
	    cachedMkpath(getGccTmp($sun));
	    cachedMkpath(getGccTmp($ibm));
	    my $srcfile = -f getGobTmp($sun)."/$bfile.c" ?
		"$bfile.c" : "$bfile.cpp";
	    symlink(getGobTmp($sun)."/".$srcfile, getGccTmp($sun)."/$srcfile");

	    # do the same for ibm
	    $srcfile = -f getGobTmp($ibm)."/$bfile.c" ?
		"$bfile.c" : "$bfile.cpp";
	    symlink(getGobTmp($ibm)."/".$srcfile, getGccTmp($ibm)."/$srcfile");

	    copy($GobTmp."/".$bfile.".h",$IncludeTmp."/".$uor."/".$bfile.".h");
	    copy($GobTmp."/".$bfile."-protected.h",
		 $IncludeTmp."/".$uor."/".$bfile."-protected.h")
	      if (-e $GobTmp."/".$bfile."-protected.h");
	    ##<<<TODO: temporary while "gtk/" still a valid prefix
	    symlink(".", $IncludeTmp."/".$uor."/gtk")
	      unless (-e $IncludeTmp."/".$uor."/gtk");
	}

        # test compile ml-generated headers

        #<<<TODO:  disable this:
        #  - assume smrgNT output valid
        #  - cannot assume that will compile standalone
        if (0) {
            @actions = ();

            for my $filename (glob(getSmrgTmp(localOS())."/*.ins"),
			      glob(getSmrgTmp(localOS())."/*.h")) {
		my $file=new Change::File($filename,$filename,"mlfiles");

                # get ml name from generated file - need this for uor
                (my $mlFile = $file) =~ s-.*/(\w+)(?:_ins\.h|\.ins)$-$1\.ml-;
                $mlFile = basename($mlFile);
                push(@actions,new Task::Action
                     ({name=>"ml header compile $file ($sun)",
                       action=>\&hdrCompTest,
                       args=>[$sun,$file]})) if $sun;
                push(@actions,new Task::Action
                     ({name=>"ml header compile $file ($ibm)",
                       action=>\&hdrCompTest,
                       args=>[$ibm,$file]})) if $ibm;
            }
            if (@actions) {
                my $mgr=new Task::Manager
                  ("running pcomp for .ml headers".
                   (getCSId()?" for change set ".getCSId()."":""));
                $mgr->addActions(@actions);
		$mgr->setLogSub(\&alert);
                $mgr->run($opts->{jobs}) and cleanupAndExit(1);
            }
        } # if (0)

    }

    #--------------------------------------------------------------------------
    # gcc -Wall
    #--------------------------------------------------------------------------
    # replacing back original changeset because we dont need to do these
    # gcc tests on already RCSed files.
    # ALSO, neither we should do any symbol checking for all files
    # included due to FincInc - dependency build check.
#$fileset = $copyfileset;
    if ($doTaskList =~ /(all|binary|gcc)/) {

	@actions = ();
	my (@cpp_files, @other_files);
	@cpp_files = grep { /\.(?:cpp|gmm|gwp)$/ } $copyfileset->getFiles();
	@other_files = grep { /\.(?:c|gob)$/ } $copyfileset->getFiles();

	for my $file (@other_files, @cpp_files) {
	    # TreatWarningsAasErrors depending on slint config files
	    $opts->{Werror} = TreatWarningsAsErrors ($file, $opts);

	    #<<<TODO: ftn disabled
	    #for my $file (grep { /\.(?:c|cpp|f)$/ } keys(%$files))
	    
	    #next if $file =~ /\.cpp$/ and isNewCpp($file->getLibrary);
	    #<<<TODO: while not using default.opts
	    if($file =~ /\.(gob|gmm|gwp)$/) {
		(my $srcfile = basename($file)) =~ s/\.gob$//;
		my $gccfile = -f getGobTmp($sun)."/$srcfile.c" ?
		    "$srcfile.c" : "$srcfile.cpp";
		
		$gccfile = getGccTmp($sun)."/$gccfile";
		# cloning the file object and replace .gob with .c file
		# as source/destination parameters
		my $gfile=new Change::File($file->serialise());
		$gfile->setSource($gccfile);
		$gfile->setDestination($gccfile);
		
	        # Cache population
	        getIncludePath($gfile->getLibrary, $sun, $gfile);
		push(@actions,new Task::Action
		     ({name=>"gcc -Wall ... $gfile ($sun)",
		       action=>\&gccWallTest, args=>[$sun,$gfile,$opts]}))
		  if $sun;
		
		$gccfile = -f getGobTmp($ibm)."/$srcfile.c" ?
		    "$srcfile.c" : "$srcfile.cpp";	
		$gccfile = getGccTmp($ibm)."/$gccfile";
		$gfile->setSource($gccfile);
		$gfile->setDestination($gccfile);
		
	        # Cache population
	        getIncludePath($gfile->getLibrary, $ibm, $gfile);
		push(@actions,new Task::Action
		     ({name=>"gcc -Wall ... $gfile ($ibm)",
		       action=>\&gccWallTest, args=>[$ibm,$gfile,$opts]}))
		  if $ibm;
	    }
	    else {
	        # Cache population
	        getIncludePath($file->getLibrary, $sun, $file);
	        getIncludePath($file->getLibrary, $ibm, $file);
		push(@actions,new Task::Action
		     ({name=>"gcc -Wall ... $file ($sun)",
		       action=>\&gccWallTest, args=>[$sun,$file,$opts]}))
		  if $sun;
		
		push(@actions,new Task::Action
		     ({name=>"gcc -Wall ... ($ibm)",
		       action=>\&gccWallTest, args=>[$ibm,$file,$opts]}))
		    if $ibm;
	    }
	}

	if (@actions) {
	    my $mgr=new Task::Manager("running gcc -Wall ...".
				      (getCSId()
					? " for change set ".getCSId()
					: ""));
	    $mgr->addActions(@actions);
	    $mgr->setLogSub(\&alert);
	    my $GCCrv = $mgr->run($opts->{jobs});

	    if ($opts->{Werror}) {
		displayLog();

		#************************************************************
		# The bypassGCCwarnings check is for TSMV users ONLY.       *
		# It is TEMPORARY, till the end of September 2006.          *
		#************************************************************

		if ($GCCrv) {
		    if ($opts->{bypassGCCwarnings}) {
			cleanExit(0);
			my $interact=new Term::Interact;
			my $yn=$interact->promptForYN
			    ("\nYou have chosen to bypass GCC WARNINGS! ".
			     "Are you sure (y/n) ");
			if ($yn) {
			    my $FH = Symbol::gensym;
			    open ($FH, ">>".CS_DATA."/logs/TSMV_gcc_response");
			    print $FH scalar localtime()," ",USER,"           ",
			    getCSId(),"\n";
			    close $FH;
			} else {
			    cleanupAndExit(1,1);
			}
		    } else {
			cleanupAndExit(1,1);
		    }
		}
	    } elsif ($GCCrv) {
		cleanupAndExit(1);
	    }
	}
    }

    #--------------------------------------------------------------------------
    # pcomp: .gob(2) .c .cpp .f
    #--------------------------------------------------------------------------
    # this is done so that symbol_oracle gets file objects from original changeset 
    # and not the objects included due to dependency build
    my $origfiles={ map { basename($_) => $_->getLibrary } $copyfileset->getFiles };
    my @actions1 = ();
    if ($doTaskList =~ /(all|binary|native)/) {

	@actions = ();
	
	for my $file (grep { /\.(?:gob|c|ec|cpp|f|gmm|gwp|l|y)$/ } ($fileset->getFiles)) {
	    my $symbol_oracle_test = 0;
	    if(exists $origfiles->{basename($file)}) 
	    {
		$symbol_oracle_test = 1;
		debug "file added for symbol validation: ".basename($file);
	    }
	    if ($file =~ /\.(gob|gmm|gwp)$/) {
		push(@actions,new Task::Action
		     ({name=>"pcomp gob $file ($sun)",action=>\&pcompGobTest,
		       args=>[$sun,$file,$1,$symbol_oracle_test]}
		     )) if $sun;
		push(@actions,new Task::Action
		     ({name=>"pcomp gob $file ($ibm)",action=>\&pcompGobTest,
		       args=>[$ibm,$file,$1,$symbol_oracle_test]}
		     )) if $ibm;		
		
	    }
	    elsif ($file =~ /\.(y|l)$/) {
		push(@actions,new Task::Action
		     ({name=>"pcomp $file ($sun)",action=>\&pcompLexYaccTest,
		       args=>[$sun,$file,$symbol_oracle_test]}
		      )) if $sun;
		push(@actions,new Task::Action
		     ({name=>"pcomp $file ($ibm)",action=>\&pcompLexYaccTest,
		       args=>[$ibm,$file,$symbol_oracle_test]}
		      )) if $ibm;
	    }
	    else {
	        # Cache population
	        getIncludePath($file->getLibrary, $sun, $file);
	        getIncludePath($file->getLibrary, $ibm, $file);
		push(@actions,new Task::Action
		     ({name=>"pcomp $file ($sun)",action=>\&pcompTest,
		       args=>[$sun,$file,$symbol_oracle_test]}
		     )) if $sun;
		push(@actions,new Task::Action
		     ({name=>"pcomp $file ($ibm)",action=>\&pcompTest,
		       args=>[$ibm,$file,$symbol_oracle_test]}
		     )) if $ibm;
		if($file =~ /\.cpp/) {
		    push(@actions1,new Task::Action
			 ({name=>"xlC8 ... $file ($ibm)",
			   action=>\&xlc8Test,
			   args=>[$ibm,$file]}))
			if $ibm;
		}

	    }
	}

	if (@actions) {
	    my $mgr=new Task::Manager
	      ("running pcomp".(getCSId()
				?" for change set ".getCSId()."":""));
	    $mgr->addActions(@actions);
	    $mgr->setLogSub(\&alert);
	    # Extra offset for the disparity in speed between AIX and
	    # Solaris compiles. We'd increase this even more, except
	    # that it'd pile onto the solaris box at startup
	    $mgr->run($opts->{jobs} + 2) and cleanupAndExit(1);
	    # Note this check is running on copy of fileset
	    checkForInvalidSymbols($opts,$copyfileset);
	}
	if (@actions1) {
	    my $mgr=new Task::Manager
	      ("running xlC8 test".(getCSId()
				?" for change set ".getCSId()."":""));
	    $mgr->addActions(@actions1);
	    $mgr->setLogSub(\&alert);
	    $mgr->run($opts->{jobs} + 4) and cleanupAndExit(1);
	}
    }

    #--------------------------------------------------------------------------
    # update changeset directory
    #--------------------------------------------------------------------------

    #+++ object set - close temp file
    foreach my $osetfh (values %osetfh) {
      close $osetfh;
      debug "generated object set $osetfh";
    }

    # Go validate with the new validator
    {
      my $mgr = new Task::Manager("Running beta validation test".(getCSId()
				?" for change set ".getCSId()."":""));
      foreach my $platform (keys %osetfh) {
	my $file = $osetfh{$platform};
	if ($platform eq $sun && VALIDATE_NEW_ORACLE_SOLARIS) {
	  my $action = Task::Action->new({name=>"validate $file ($platform)",
					  action=>\&newSymbolValidationTest,
					  args=>[$platform, $file]});
	  $mgr->addAction($action);
	}
	if ($platform eq $ibm && VALIDATE_NEW_ORACLE_AIX) {
	  my $action = Task::Action->new({name=>"validate $file ($platform)",
					  action=>\&newSymbolValidationTest,
					  args=>[$platform, $file]});
	  $mgr->addAction($action);
	}
      }
      $mgr->setLogSub(\&alert);
      # Run 'em all at once, which should be fine
      $mgr->run(scalar keys %osetfh);
    }

    alert "running binary symbol validation -- please be patient";
    alert "Symbol validation cannot be interrupted by Ctrl-C -- please be patient";

    my $output = "";
    my $symval = DO_SYMBOL_VALIDATION ? 1 : 0;
    #$symval = 0 ; #if (USER eq "registry");  # skip symbol validation for breg

    $symval && eval {
        local $SIG{INT} = 'IGNORE';

	my $PH = Symbol::gensym;
	my $pid = IPC::Open3::open3(undef, $PH, $PH,
	  "$FindBin::Bin/symbol_oracle.pl","--file",$osetfh{$sun});
	local $/ = undef;
	$output = <$PH>;
	close $PH;
	$symval = (waitpid($pid,0) == $pid) ? $? : 1;
    };

    my $yn = ($symval == 0);

    ## (leave file around for debugging)
    #unlink $osetfh unless Util::Message::get_debug();

    if ($output ne "") {
	alert("\n",$output);	
	if (getCSId()
	    && (isPrivilegedMode() or isTestMode && !isPrivilegedMode())) {
	    ## Note that CS_DATA/logs/binary_validation will
	    ## grow quickly and should be cleaned out regularly.
	    ##<<<TODO warn upon open() failure, but continue
	    my    $FH = Symbol::gensym;
	    -d CS_DATA."/logs/binary_validation"
	      || mkpath(CS_DATA."/logs/binary_validation");
	    if (open($FH, ">".CS_DATA."/logs/binary_validation/".getCSId())) {
		print $FH scalar localtime()," ",USER," ",getCSId(),"\n";
		print $FH $output;
		close $FH;
	    }
	}
    }
    my($rc) = $output =~ /FAILED\*\* \(rc:(\d)\)/s;

    my $has_tty = -t STDOUT || -f "/home/".USER."/.cs_ask";
    my $ask_question = $opts->{from} || $opts->{csid};
    if (defined $rc && $rc == 2) {
	error("Symbol validation failed!\n");
    }
    elsif ($symval != 0 && $has_tty && $ask_question) {
	my $interact=new Term::Interact;
	$yn= $interact->promptForYN("\nSymbol validation failed!  ".
				    "Proceed anyway? (Caution!)\n".
	  "\n    ".
	  "Some symbols marked undefined may be the result of violations of\n".
	  "    ".
	  "the robocop library hierarchy.  {BP TOOLS WIZARDS CONTACTS<go>}\n".
	  "    ".
	  "and speak with your department tools representative for help.\n".
	  "    ".
	  "{BP ROBOCOP LIBRARY HIERARCHY<go>}\n".
				    "\nSymbol validation failed!  ".
				    "Proceed anyway? (Caution!) ".
				    "(y/n) ");
	if ($yn && getCSId()) {
	# (disable second prompt per Shubha, 2006.10.05 -gps)
	#    $yn= $interact->promptForYN("Are you sure?  ".
	#				"(Affirmative answers are ".
	#				"logged) (y/n)? ");
	    if ($yn &&
		(isPrivilegedMode() or isTestMode() && !isPrivilegedMode())){
		##<<<TODO warn upon open() failure, but continue
		my    $FH = Symbol::gensym;
		open ($FH, ">>".CS_DATA."/logs/symbol_validation");
		print $FH scalar localtime()," ",USER," ",getCSId(),"\n";
		close $FH;
	    }
	}
	print "\n";
    }
    elsif ($symval != 0 && ! $has_tty) {
	error("Symbol validation failed!\n");
	error("     Run cscheckin or cscompile in a fully interactive\n"
	     ."     shell and you "
 	     ."will be prompted with a question asking if you\n     want to "
	     ."proceed.\n") if $ask_question;

	## bregacclib and bbinc/Cinclude/registry checkins must always succeed
	if (USER eq "registry") {
	    warning("User 'registry' proceeding with cscheckin");
	    $yn = 1;
	}
    }
    #+++

    if ($yn and
	(isPrivilegedCscompileMode() or isTestMode() && !isPrivilegedMode()) and
        getCSId() || isTestMode()) {
	updateCSData($fileset,$opts->{stage});
    }

    cleanupAndExit(!$yn,1);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwri@bloomberg.net)
Glenn Strauss (gstrauss1@bloomberg.net)
Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl> (a.k.a. C<cscheckin>)

=cut

__END__


