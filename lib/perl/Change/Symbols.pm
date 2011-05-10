package Change::Symbols;
use strict;

BEGIN {
    # cstools have their environment cleared, which includes TZ.
    # this leads to inconsistent times. Not surprisingly, IBM
    # requires special handling (see DRQS 9506629)
    $ENV{TZ} = ($^O =~ /^(aix|hpux)$/) ? 'EST5EDT' : 'US/Eastern';
}

use base qw(Symbols); # For RELEASE, otherwise would be Common::Symbols

use vars qw($OVERRIDE_PREFIX);
$OVERRIDE_PREFIX = "CHANGE_";

use Symbols;
use File::Spec::Functions qw(catfile);

# Additional exports - Common::Symbols is an Exporter.
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(STATUS_NAME DEPENDENCY_NAME);

require FindBin;

#==============================================================================

=head1 NAME

Change::Symbols - Symbols for change set management.

=head1 SYNOPSIS

    use Change::Symbols qw(STAGE_PRODUCTION);

=head1 DESCRIPTION

This module provides descriptive constants for use with change set management.

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Common::Symbols>, L<bde_createcs.pl>

=cut

#==============================================================================

sub STATUS_NAME ($) {
    my $status=shift;

    return
      ($status eq STATUS_ENTERED())    && STATUS_ENTERED_NAME() ||
      ($status eq STATUS_SUBMITTED())  && STATUS_SUBMITTED_NAME() ||
      ($status eq STATUS_WAITING())    && STATUS_WAITING_NAME() ||
      ($status eq STATUS_WITHDRAWN())  && STATUS_WITHDRAWN_NAME() ||
      ($status eq STATUS_ACTIVE())     && STATUS_ACTIVE_NAME() ||
      ($status eq STATUS_ROLLEDBACK()) && STATUS_ROLLEDBACK_NAME() ||
      ($status eq STATUS_REINSTATED()) && STATUS_REINSTATED_NAME() ||
      ($status eq STATUS_FAILED())     && STATUS_FAILED_NAME() ||
      ($status eq STATUS_INPROGRESS()) && STATUS_INPROGRESS_NAME() ||
      ($status eq STATUS_COMPLETE())   && STATUS_COMPLETE_NAME() ||
      ($status eq STATUS_BEINGADDED()) && STATUS_BEINGADDED_NAME() ||
      ($status eq STATUS_UNKNOWN())    && STATUS_UNKNOWN_NAME() || do {
        require Util::Message;
        Util::Message::fatal("Status '$status' is invalid");
      };
}

# we can't declare this anonymous hash-ref as a static hash
# outside this function because when the module is compiled
# the DEPENDENCY_TYPE_* symbols don't yet exist. So we need 
# to delay it until this function is actually called by which 
# time all of its symbols have been generated.
sub DEPENDENCY_NAME ($) {
    my $dep = shift;
    return {
        &DEPENDENCY_TYPE_ROLLBACK   => 'ROLLBACK',
        &DEPENDENCY_TYPE_NONE       => 'NONE',
        &DEPENDENCY_TYPE_CONTINGENT => 'CONTINGENT',
        &DEPENDENCY_TYPE_DEPENDENT  => 'DEPENDENT',
        &DEPENDENCY_TYPE_SIBLING    => 'SIBLING',
    }->{$dep} || do {
        require Util::Message;
        Util::Message::fatal("Dependency '$dep' is invalid");
    };
}

# Given a program (script or executable binary) and its official directory
# location, check for the existence of the program in the TOOLS_TESTBIN
# directory and, if present, return the full path to the test version of the
# specified program.  Otherwise, return the full path to the program in its
# official directory.  If TOOLS_TESTBIN is empty, return the official
# location.
sub findTool($$) {
    my ($tool,$officialDir) = @_;

    if (TOOLS_TESTBIN()) {
        my $fullpath = catfile(TOOLS_TESTBIN(), $tool);
        return $fullpath if (-x $fullpath);
    }

    return catfile($officialDir, $tool);
}

#==============================================================================

1;

__DATA__

RELEASE           => { Symbols->RELEASE }
CONFDIR           => { Symbols->CONFDIR }

CSCHECKIN_NEWS    => "${CONFDIR}/${RELEASE}/cscheckin_news"
CSCHECKIN_MOTD    => "${CONFDIR}/${RELEASE}/cscheckin_motd"
CSCHECKIN_LOCK    => "${CONFDIR}/${RELEASE}/cscheckin_lock"
%INCLUDE	  "${CONFDIR}/${RELEASE}/change.sym"

# CHANGE_USER and CHANGE_GROUP overrides
+USER              => { my$u=getpwuid($<);$u eq'robocop'?$ENV{unixnameis}||'robocop':$u }
+EFFECTIVE_USER    => { getpwuid($>) }
GROUP             => { (exists $ENV{GROUP})?($ENV{GROUP}=~/^(.*)$/ and $1):"" }
+HOME              => { (getpwnam(Change::Symbols::USER))[7] or "nohome" }

BB_BUILD               => /bb/build

#----------
# stages - fixed-length four-character codes

STAGE_PRODUCTION       => prod
STAGE_BETA             => beta
STAGE_ALPHA            => alph
STAGE_PREALPHA         => prea
STAGE_DEPARTMENT       => dept
STAGE_INTEGRATION      => "$STAGE_PREALPHA"
STAGE_IMMEDIATE        => stpr
#--
STAGE_DEVELOPMENT      => devl
# STAGE_DEVELOPMENT is not a true stage. It means 'work in development space'

# stage locations - all the same as there's no true staging yet
STAGE_PRODUCTION_LOCN  => /bbsrc
STAGE_BETA_LOCN        => /bbsrc
STAGE_ALPHA_LOCN       => /bbsrc
STAGE_PREALPHA_LOCN    => /bbsrc
STAGE_DEPARTMENT_LOCN  => /bbsrc
STAGE_INTEGRATION_LOCN => "$STAGE_PREALPHA_LOCN"
STAGE_IMMEDIATE_LOCN   => /bbsrc
#--
### STAGE_DEVELOPMENT_LOCN => n/a

# stage roots
STAGE_PRODUCTION_ROOT  => "$STAGE_PRODUCTION_LOCN/proot"
STAGE_BETA_ROOT        => "$STAGE_BETA_LOCN/proot"
STAGE_ALPHA_ROOT       => "$STAGE_ALPHA_LOCN/proot"
STAGE_PREALPHA_ROOT    => "$STAGE_PREALPHA_LOCN/proot"
STAGE_DEPARTMENT_ROOT  => "$STAGE_DEPARTMENT_LOCN/proot"
STAGE_INTEGRATION_ROOT => "$STAGE_PREALPHA_ROOT"
STAGE_IMMEDIATE_ROOT   => "$STAGE_IMMEDIATE_LOCN/stproot"
#--
### STAGE_DEVELOPMENT_ROOT => n/a

#----------
# move types - fixed-length four-character codes
MOVE_REGULAR           => move
MOVE_BUGFIX            => bugf
MOVE_EMERGENCY         => emov
MOVE_IMMEDIATE         => stpr

#----------
# branch policies, this is a dump of the policy_names table
POLICY_TRUNK           => trunk
POLICY_STP             => stp
POLICY_PROGRESS        => progress
POLICY_DEVL            => devl
POLICY_CLOSED          => closed
POLICY_BUGFIX          => bugfix
POLICY_BETA_EMOV       => beta_emov
POLICY_PRODUCTION      => production
POLICY_LOCKDOWN        => lockdown

#----------
# outputs (primary)
DATA_PATH              => /bbsrc/tools/data/newcheckin
SWEEP_ROOT_ROBO	       => /bbsrc/sweep
SWEEP_ROOT_DEV	       => /bb/csdata/scm/sweep
SWEEP_ROOT_BUILD       => /bb/csdata/scm/build
SWEEP_MOVE_DIR         => "$SWEEP_ROOT/move"
SWEEP_BFIX_DIR         => "$SWEEP_ROOT/bfix"
SWEEP_EMOV_DIR         => "$SWEEP_ROOT/emov"
SWEEP_IMOV_DIR         => "$SWEEP_ROOT/imov"
# svn checked out location
BUILD_SHARE            => "$BB_BUILD/share"
# outputs (secondary)
DBPATH                 => "$DATA_PATH/change.db"
DBLOCKFILE             => "$DATA_PATH/change.lock"
ACCEPTLIST             => "$DATA_PATH/change.accept"
BETALIST               => "$DATA_PATH/change.beta"
DENYLIST               => "$DATA_PATH/change.deny"
ADMINLIST              => "$DATA_PATH/change.admin"
APPROVELIST            => "$DATA_PATH/change.approve"
ROBOLIST               => "$DATA_PATH/change.robo"
SCMACCEPTLIST          => "$DATA_PATH/scm.accept"
TEMPAPPTESTERLIST      => "$DATA_PATH/change.temptesters"
DISABLEVALIDATION      => "$DATA_PATH/validation.disable"
# external data files
BBFA_HEADERS_LIST      => "$DATA_PATH/bbfa_headers.list"

# outputs (installation deployment)
DEPLOYED_HEADER_LOCN      => "$STAGE_PRODUCTION_ROOT/include"

# override for testing
TOOLS_TESTBIN     => { undef }

# external scripts (used primarily in the generated .sh script)
TOOLS_MAKEBIN     => /bbsrc/mkincludes
TOOLS_SHAREDBIN   => /bb/shared/bin
TOOLS_SHAREDABIN  => /bb/shared/abin
BREAKFTNX         => "${ \findTool(breakftnx => TOOLS_SHAREDABIN) }"
BSTSTRIP          => "${ \findTool(bststrip => TOOLS_SHAREDBIN) }"
MLSTRIP           => "${ \findTool(mlstrip => TOOLS_SHAREDBIN) }"
CHECKIN_ROBOCOP   => "${ \findTool('checkin.robocop' => TOOLS_SHAREDBIN) }"
TYPESCAN          => "${ \findTool(typescan => TOOLS_SHAREDBIN) }"
CHECKFORTABS      => "${ \findTool(checkfortabs => TOOLS_SHAREDBIN) }"
GETBESTHOST       => "${ \findTool(get_best_host => TOOLS_SHAREDBIN) }"
LNKWGETHOSTS      => "${ \findTool(lnkw_get_hosts => TOOLS_SHAREDBIN) }"
INC2HDR           => "${ \findTool(inc2hdr => TOOLS_SHAREDBIN) }"
ADD_RCSID         => "${ \findTool(add_rcsid => TOOLS_SHAREDBIN) }"
UNEXPAND_RCSID    => "${ \findTool(unexpand_rcsid => TOOLS_SHAREDBIN) }"
SCANT_N           => "${ \findTool(scant_n => TOOLS_SHAREDBIN) }"
FINDINC           => "${ \findTool(findinc => TOOLS_SHAREDBIN) }"
SMRG              => "${ \findTool(smrgnt_check => TOOLS_SHAREDBIN) }"
SMRGNT_TOOL       => "${ \findTool(smrgNT => TOOLS_SHAREDABIN) }"
BSTGENHEADER_TOOL => "${ \findTool(bstgenheader => TOOLS_SHAREDABIN) }"
PCOMP             => "${ \findTool(robopcomp => TOOLS_SHAREDBIN) }"
LOCUM             => "${ \findTool(locum => TOOLS_SHAREDBIN) }"
ROBOPCOMP         => "${ \findTool(robopcomp => TOOLS_SHAREDBIN) }"
DEFAULTPCOMP      => "${ \findTool(pcomp => TOOLS_MAKEBIN) }"
GOB2O             => "${ \findTool(gob2o => TOOLS_SHAREDABIN) }"
TRACE_ROUTERCHG	  => "${ \findTool(trace_routerchg_binary => TOOLS_SHAREDABIN) }"
LONG2INT	  => "${ \findTool(long2int => TOOLS_SHAREDABIN) }"
SYMFIND		  => "${ \findTool(symfind => TOOLS_SHAREDBIN) }"

MDEP_NEWLINK	  => "$TOOLS_MAKEBIN/machindep.newlink"

SSH               => /opt/ssh/bin/ssh
GMAKE             => /opt/swt/bin/gmake
LEX               => /opt/swt/bin/flex
YACC              => /opt/swt/bin/bison

ROBOSCRIPTS_DIR   => /bbsrc/roboscripts

MAKEALIB          => makealib
# vanilla RCS tools
RCS_CI            => /opt/swt/bin/ci
RCS_CO            => /opt/swt/bin/co
RCS_RCS           => /opt/swt/bin/rcs
RCS_RCSDIFF       => /opt/swt/bin/rcsdiff
RCS_RLOG          => /opt/swt/bin/rlog
# robocop SCM tools
ROBORCSLOCK       => "${\ findTool(roborcslock => TOOLS_SHAREDABIN) }"
ROBOSCM_MESSAGE	  => 'Change generated by roboscm tool.'

SVN               => /opt/swt/bin/svn

# cstools
CSTOOLS_BIN       => "$FindBin::Bin"
CSCOMPILE         => "$CSTOOLS_BIN/bde_compilecs.pl"
CSROLLBACK        => "$CSTOOLS_BIN/bde_rollbackcs.pl"
CSCHECKOUT        => "$CSTOOLS_BIN/bde_checkoutcs.pl"
HEADERDEPLOYCHECK => "$CSTOOLS_BIN/robo/header-deploy-check.pl"
CHK_GOBXML_VERS   => "$CSTOOLS_BIN/chk_gobxml_version.pl"

# 'opt' (third-party) tools
GCC		  => "/opt/swt/install/gcc-4.3.2/bin/gcc -pipe"
GPP		  => "/opt/swt/install/gcc-4.3.2/bin/g++ -pipe"

# external configuration files
TOOLS_DATA        => /bbsrc/tools/data
FILELOCKLIST      => "$TOOLS_DATA/checkin_restricted_files.tbl"
RECOMPILELOCKLIST => "$TOOLS_DATA/checkin_recompile_restricted_files.tbl"
FILETYPESALLOWED  => "$TOOLS_DATA/filetypesallowed.tbl"
FILETYPESDENIED   => "$TOOLS_DATA/filetypesdenied.tbl"
FORTRANALLOWED    => "$TOOLS_DATA/new_fortran.lst"
SKIPONARCH        => "$TOOLS_DATA/skip_on_arch"
MALLOCFILES       => "$TOOLS_DATA/malloc.files"
LONGS_ARE_OK_LIST => "$TOOLS_DATA/longs_are_ok.list"
REJECTLIST        => "$TOOLS_DATA/reject.list"
REJECTLIST_BADCALL    => "$TOOLS_DATA/slint/slint.badcalls"
POISONFUNC_EXCEPTIONS => "$TOOLS_DATA/poisonfunc_exceptions.tbl"
CPP_BDE_VERIFY_EXEMPT => "$TOOLS_DATA/is_cpp_bde_exception.tbl"
STRAIGHTTHROUGHLIST   => "$TOOLS_DATA/is_Friday_stagedir.tbl"
CHECKINBLACKLIST  => "$TOOLS_DATA/checkin_blacklist.tbl"
UNDEFPRESCREEN_EXCEPTION => "$TOOLS_DATA/undefprescreen_exception.tbl"
OFFLINELIB_LIST   => "$TOOLS_DATA/nonbig_code.lst"
CPPCAPABLE_LIBS_LIST => "/home/alan/bin/skipintel.file"
# Not LEGACY_DATA, but the actual file
REAL_LEGACY_DATA  => "$TOOLS_DATA/robocop.libs"
CHECKALLOBJS      => "/home/alan/bin/checkallobjs"
PROGRESSLIBLIST   => "$TOOLS_DATA/is_progress_library.tbl"
TYPESCANSKIPLIST  => "$TOOLS_DATA/skip-typescan.tbl"
RAPIDLIST => "/bbsrc/roboscripts/rapidbuild_offline_list"
COMPILEHDREXCEPTIONLIST  => "$TOOLS_DATA/compilehdr_exception.tbl"
SLINTENFORCEMENT  => "$TOOLS_DATA/slint_enforcement.tbl"
SLINTEXCEPTION    => "$TOOLS_DATA/slint.exceptions"
UOR_LIST_DIR      => "/bb/csdata/cache/aotools/UorCache"

INC2HDR_LIST  => "/bbsrc/mkincludes/_plinkdata/aodata/inc2hdr.txt"

# external lock/control files
BIG_DATA          => /bbsrc/big
BFONLY_FLAG       => "$BIG_DATA/.monday_bug_fix_flag"
NOEMOV_FLAG       => "$BIG_DATA/.no_emov_flag"
SWEEPLOCK         => "$BIG_DATA/checkin.go"
# are backups done?
BACKUPS_ARE_DONE  => "/bbsrc/RCShist/proot/etc/.backupsaredone"

#----------
# file types. Note that FILE_IS_RECOMPILE shouldn't appear in changesets

FILE_IS_NEW       => NEW
FILE_IS_CHANGED   => CHANGED
FILE_IS_UNCHANGED => UNCHANGED
FILE_IS_REMOVED   => REMOVED
FILE_IS_RENAMED	  => RENAMED
FILE_IS_COPIED    => COPIED
FILE_IS_UNKNOWN   => UNKNOWN
FILE_IS_REVERTED  => REVERTED
FILE_IS_NEW_UOR   => NEWUOR
FILE_IS_RECOMPILE => RECOMPILE

#----------
# database configuration

DBDELIMITER            => :

# change stati
STATUS_UNKNOWN         => X
STATUS_ENTERED         => E
STATUS_SUBMITTED       => S
STATUS_WAITING         => N
STATUS_WITHDRAWN       => W
STATUS_ACTIVE          => A
STATUS_ROLLEDBACK      => R
STATUS_REINSTATED      => I
STATUS_FAILED          => F
STATUS_COMPLETE        => C
STATUS_INPROGRESS      => P
STATUS_BEINGADDED      => B

# change stati
STATUS_UNKNOWN_NAME    => "Unknown"
STATUS_ENTERED_NAME    => "Entered"
STATUS_SUBMITTED_NAME  => "Submitted"
STATUS_WAITING_NAME    => "Waiting for Approval"
STATUS_WITHDRAWN_NAME  => "Withdrawn"
STATUS_ACTIVE_NAME     => "Active"
STATUS_ROLLEDBACK_NAME => "Rolled Back"
STATUS_REINSTATED_NAME => "Reinstated"
STATUS_FAILED_NAME     => "Failed"
STATUS_COMPLETE_NAME   => "Complete"
STATUS_INPROGRESS_NAME => "In Progress"
STATUS_BEINGADDED_NAME => "Being Added"

# types for declared dependencies
DEPENDENCY_TYPE_NONE        => N
DEPENDENCY_TYPE_ROLLBACK    => R
DEPENDENCY_TYPE_CONTINGENT  => C
DEPENDENCY_TYPE_DEPENDENT   => D
DEPENDENCY_TYPE_SIBLING     => S

# serialisation
SERIAL_DELIMITER       => :

#---------
# arbitrary checks and limits

NUM_FILES_LIMIT        => 5000
FINDINC_FILES_LIMIT    => 200
FINDINC_BUGF_LIMIT     => 500
FINDINC_EMOV_LIMIT     => 100

# This limit imposed by grabber
PROGRESS_FILES_LIMIT   => 384
# see Change::Util::SourceChecks
BADREASON_RE           => ^\s*(?i:bug\s*fix)\s*$

# bump limit to 80 because of recent checkin of bas autogen'd code --no more
# bumps!  Write shorter element names in your WSDL files!!!
FILELENGTH_LIMIT       => 80
FILELENGTH_LIMIT_LK    => 80

# Any file modified after this date is automatically dependency built,
# regardless of how the containing library is marked. The base date is
# currently 2009/05/21 16:00
DEPENDENCY_BASEDATE    => 1242936000

GTK_FORBIDDEN_INCLUDES => glibconfig.h gtypes.h gmacros.h gdebug.h gerror.h gmessages.h gmem.h garray.h gdate.h glist.h gslist.h gstring.h gutils.h gstrfuncs.h gtree.h gnode.h ghash.h gqsort.h gprimes.h gdataset.h ghook.h gmain.h gutils.h gboxed.h genums.h gobject.h gparam.h gparamspecs.h gsignal.h gtype.h gtypeplugin.h gvalue.h gvaluearray.h gvaluetypes.h glib-object.h

GTK_SKIP_FINDINC_LIBS => bbdm bbglib gap gctrl gee glibmm gobject gof goo gsvc gsvg gtest gtkcore gtkdm spidermonk


#---------
# approval types
APPROVE_NONE           => none
APPROVE_REJECT         => reject
#
APPROVE_CSAPPROVE      => csapprove
APPROVE_PRQSCR         => prqscr
APPROVE_RDMV           => rdmv
APPROVE_TSMV           => tsmv
APPROVE_BBMV	       => bbmv

#---------
# user custom configuration
CHANGERCFILES          => ".csrc cs.rc"

#---------
# debug-specific symbols

DEBUG_ACTIVATION_DELAY => 0
# ACTIVATION_DELAY, if positive, causes tools to sleep for that number of
# seconds before the 'S'ubmitted to 'A'ctive state transition. See cscheckin.

# enable/disable symbol validation in cscompile
DO_SYMBOL_VALIDATION   => 1

#----------
# cs data area

CS_DATA                => /bb/cstools
CS_SCRATCH             => /bb/csbuild
CSCOMPILE_TMP          => "$CS_SCRATCH"
CS_INTEGRATION         => "$CS_DATA/$STAGE_INTEGRATION"
CS_INTEGRATION_INCLUDE => "$CS_INTEGRATION/include"
CS_DIFFREPORT_DIR      => "$CS_DATA/diffs"
CS_PRQSPG_DIR          => "$CS_DATA/prqspg"
CS_STPR_DIR	       => "$CS_DATA/stpr"
CS_SWEEP_DIR	       => "$CS_DATA/sweep"

CS_INCFILE             => INC
CS_GENINCFILE          => GENINC
CS_OBJFILE             => OBJ

# deprecated
COMPCHECK_DIR          => "$CS_DATA/robo"
COMPCHECK_DIR_CB2      => "$CS_DATA/cb2"

# also deprecated!
CS_DIR                 => "$CS_INTEGRATION"
SUPPORTED_FILETYPES    => "h|c|cpp|s|gob|inc|f|l|y|ml|ec|sh|ksh|css|pl|cmd|cfg|env|lst|dta|que|xml|csc|csc2|lrl|xsd|sql|txt|init|bst|wsdl|p|i|conf|cnf|pf|py|ddl|drv|dat|ini|tbl|awk|js|pc|pm"
FILETYPES_BUILDING_OBJECTS => '(c|cpp|cc|f|gob|s|y|l|ec|pc)'
OOEXTRA_SRC_FILETYPES  => "h|c|cpp|gob|gobxml|inc|f|l|y|ml|ec|mk"
IMPORTABLE_FILETYPES   => "$SUPPORTED_FILETYPES|mk"
CSCOMPILE_TOOL         => "cscompile"
CSCHECKIN_TOOL         => "cscheckin"
CSCHECKOUT_TOOL        => "cscheckout"

INC2HDR_CINCRCS        => "/bbsrc/proot/prebuild/inc2hdr/RCS"

QUARANTINE_DIR	      => "/bb/csdata/robo/quarantine"
# temporary
SCM_BUNDLE_DIR	      => "/bb/csdata/scm/bundles"
FINDINC_PLUGIN        => 0
FINDINC_NON_INTERACTIVE_LIMIT => 5

# database and other legacy limitations
MAX_TASKS   => 100
MAX_FUNCS   => 100
MAX_FILES   => 5000
MAX_TESTERS => 2

# support token database directory
TOKEN_DB_DIR => "/bb/csdata/logs/tokens"
LOG_DIR => "/bb/csdata/logs"

# cscheckin/ao metadata working copy
METADATA_BRANCH_DIR => "/bb/csdata/branches"
CSCHECKIN_WORKING_COPY => "/bb/csdata/branches"

# XXX use this username to update PRQS status until prqs api is fixed
PRQS_UPDATE_USER      => { $ENV{unixnameis} || "alan" }

# is it a monday bugfix
IS_BUGFIX_ONLY      => { -e $BFONLY_FLAG }

# are emovs forbidden
ARE_EMOVS_DISALLOWED => { -e $NOEMOV_FLAG }

# is a sweep currently underway
IS_SWEEP_LOCKED     => { -e $SWEEPLOCK }

# where robo builds stuff
ALL_ARCH_REGEX      => "(?:AIX-powerpc|SunOS-(?:sparc|i386)|HP-UX-ia64|Linux-x86_64)"
ALL_ARCH_REGEX_WBITS => "$ALL_ARCH_REGEX(?:-32|-64)?"
ROBO_IBM_BUILD_MOUNT   => "/bb/robocop/ibm-source"
ROBO_SUN_BUILD_MOUNT   => "/bb/robocop/sun-source"

# what status to consider for sweep
ELIGIBLE_SWEEP_STATUS   => "$STATUS_INPROGRESS"

# sweep user
ELIGIBLE_SWEEP_USER	=> robocop

# symbol that determines where STP/rapidbuild flags are stored
STP_META_IN_MEMFILES => 1

# symbols specifying the locations of various RCS-archives
VC_ATTIC        => "/bbsrc/Attic"
VC_MASTER       => "/bbsrc/RCShist"
VC_MASTER_BIG   => "$VC_MASTER/proot"
VC_MASTER_STP   => "$VC_MASTER/stproot"
VC_SLAVE_SOURCE => "/bbsrc/source/proot"
VC_SLAVE_STAGE  => "/bbsrc/stage/proot"
VC_SLAVE_STP       => "$STAGE_IMMEDIATE_ROOT"

# directory containing makefiles for PQC reports
PQC_MAKEFILE_DIR    => /bbsrc/bin/prod/bin/build/pqc

# commonly this is /bbsrc
CLASSIC_ROOT => "/bbsrc"

RCS_IS_DEAD => 0
RECOMPILE_PASS_MULTIPLIER => 100

LROOT => "/bbsrc/lroot"
