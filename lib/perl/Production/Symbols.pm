package Production::Symbols;
use strict;

use base qw(Symbols); # For RELEASE and CONFDIR, otherwise would be Common::Symbols
use vars qw($OVERRIDE_PREFIX @EXPORT_OK);
use Symbols;

$OVERRIDE_PREFIX = "PRODUCTION_";

@EXPORT_OK = qw/SCM_HOSTNAME $SCM_HOSTNAME
		SCM_HOST     $SCM_HOST
		SCM_HOST_SCM $SCM_HOST_SCM
                RANDOM_BUILD_ONLY_MACHINE
	       /;

sub SCM_HOSTNAME() {
    return $ENV{"${OVERRIDE_PREFIX}SCM_HOSTNAME"}
        if defined $ENV{"${OVERRIDE_PREFIX}SCM_HOSTNAME"};

    my $confdir = Symbols->CONFDIR;
    open my $fh, "$confdir/scm/scm.master"
        or die "Error retrieving SCM_HOSTNAME: $!"; 
    chomp(my $h = <$fh>);
    return $h || die "SCM_HOSTNAME empty";
}

@scm_hostname::ISA = qw/Constant::Scalar/;
tie our $SCM_HOSTNAME => 'scm_hostname';
sub scm_hostname::TIESCALAR { return bless \my $c => shift } 
sub scm_hostname::FETCH     { return SCM_HOSTNAME() }


# Makes explicit use of the value of SCM_PORT.
sub SCM_HOST() {
    return $ENV{"${OVERRIDE_PREFIX}SCM_HOST"}
        if defined $ENV{"${OVERRIDE_PREFIX}SCM_HOST"};

    my $port;
    {
        no warnings 'once';
        $port = defined($ENV{"${OVERRIDE_PREFIX}SCM_PORT"})
                    ? $ENV{"${OVERRIDE_PREFIX}SCM_PORT"}
                    : $Production::Symbols::SCM_PORT;
    }
    return 'http://'.SCM_HOSTNAME().":$port";
}

@scm_host::ISA = qw/Constant::Scalar/;
tie our $SCM_HOST => 'scm_host';
sub scm_host::TIESCALAR { return bless \my $c => shift } 
sub scm_host::FETCH     { return SCM_HOST() }

sub SCM_HOST_SCM() {
    return $ENV{"${OVERRIDE_PREFIX}SCM_HOST_SCM"}
        if defined $ENV{"${OVERRIDE_PREFIX}SCM_HOST_SCM"};

    my $select = $Production::Symbols::SCM_VERSION 
                    ? "/$Production::Symbols::SCM_VERSION" 
                    : "";
    return SCM_HOST()."$select/scm";
}

@scm_host_scm::ISA = qw/Constant::Scalar/;
tie our $SCM_HOST_SCM => 'scm_host_scm';
sub scm_host_scm::TIESCALAR { return bless \my $c => shift } 
sub scm_host_scm::FETCH     { return SCM_HOST_SCM() }

#==============================================================================

=head1 NAME

Production::Services::Symbols - Sybmbols for production services

=head1 SYNOPSIS

    use Symbols qw(HOST HOST_NUM);

=head1 DESCRIPTION

This module provides common symbols for use with production services.

=head1 AUTHOR

Pablo Halpern (phalpern@bloomberg.net)

=head1 SEE ALSO

L<Common::Symbols>, L<Production::Services>

=cut

#==============================================================================

1;

__DATA__

RELEASE           => { Symbols->RELEASE }
CONFDIR           => { Symbols->CONFDIR }
%INCLUDE	  "${CONFDIR}/${RELEASE}/production.sym"

# List of production host names and their corresponding host numbers.
HOST_LIST => "N121:P122:N299:P300:N283:P284:Sundev9"
HOST_NUMS => "121 :122 :299 :300 :283 :284:280"

# List of production hosts to try, in order.  By default, sundev9 is missing
# from this list because it is only a test server.
#
# For testing:
# Override HOST with a single name from HOST_LIST to use that host.
# Override HOST with 'local' to get the default local program (no ssh).
# Override HOST with an explicit path, i.e. '/home/me/dev/prlspd' to use
# an arbitrary local program.
HOST      => "N121:P122:N299:P300:N283:P284"
# set up for alpha server
# nysbvn1 == 172.17.13.14
# njsbvn1 == 172.17.14.10
#HOST      => "172.17.13.14"
#HOST      => "172.17.14.10"


HOST_TYPE_NONE => 0
HOST_TYPE_CSDB => 1
HOST_TYPE_BAS  => 2

#---------
# Service default timeout value
DEFAULT_SVC_TIMEOUT  => 30

LONG_SVC_TIMEOUT => 180
#---------
# PRQS ticket types

PRQS_TYPE_EMERGENCY  => EM
PRQS_TYPE_IMMEDIATE  => ST
PRQS_TYPE_CODEREVIEW => CR
PRQS_TYPE_PROGRESS   => PG

#---------
# HTTP headers for production service transactions

HEADER_APPROVER      => Change-Set-Approver
HEADER_CREATION_TIME => Change-Set-Creation-Time
HEADER_CREATOR       => Change-Set-Creator
HEADER_FILE          => Change-Set-File
HEADER_FUNCTION      => Change-Set-Function
HEADER_ID            => Change-Set-ID
HEADER_MOVE_TYPE     => Change-Set-Move-Type
HEADER_REFERENCE     => Change-Set-Reference
HEADER_STAGE         => Change-Set-Stage
HEADER_STATUS        => Change-Set-Status
HEADER_TASK          => Change-Set-Task
HEADER_TESTER        => Change-Set-Tester
HEADER_TICKET        => Change-Set-Ticket
HEADER_PRQS_TYPE     => Change-Set-Prqs-Type
HEADER_DEPENDENCIES  => Change-Set-Dependencies
HEADER_UPDATER       => Change-Set-Updater
HEADER_APPROVER_UUID => Change-Set-Approver-Uuid
HEADER_TESTER_UUID   => Change-Set-Tester-Uuid
HEADER_ID_DEP        => Change-Set-ID-DEP
HEADER_HISTORY       => Change-Set-History
HEADER_LIBRARY       => Change-Set-Library
HEADER_SEND_TO       => Change-Set-To
HEADER_SEND_FROM     => Change-Set-From
HEADER_SUBJECT       => Change-Set-Subject
HEADER_DIFF_MACHINE  => Change-Set-Diff-Machine
HEADER_DIFF_PATH     => Change-Set-Diff-Path
HEADER_REASON        => Change-Set-Reason
HEADER_START         => Change-Set-Start-Date
HEADER_END           => Change-Set-End-Date
HEADER_GLOB          => Change-Set-Glob
HEADER_CHANGED       => Change-Set-Changed
HEADER_DEPENDENT_TYPE=> Change-Set-Dependent-Type
HEADER_BRANCH        => Change-Set-Branch
# update headers insert 'New-'
HEADER_NEW_STATUS    => Change-Set-New-Status
# historical headers (e..g for reinstatement) insert 'Original-'
HEADER_ORIGINAL_ID   => Change-Set-Original-ID
HEADER_PRQS_NUMBER   => Change-Set-Prqs-Number
HEADER_PRQS_STATUS   => Change-Set-Prqs-Status
HEADER_PRQS_UPDATER  => Change-Set-Prqs-Updater
#
HEADER_CONTENT_LENGTH=> Content-Length

# Turn this off to stop writing files to /bbsrc/checkin.
SCM_BRANCHING_ENABLED => 1

#---------
# HTTP headers for production service transactions
# Two servers per machine.

# Client-selectable SCM server versions:
# The currently running version is always:      "stable"
# If it turns out to be not stable, set to:     "lgood"
# To run a particular version, e.g. 42:         "versions/42"
SCM_VERSION => stable

# Value used above for runtime calculation.
SCM_PORT                => 28270
#SCM_PORT                => 28275
# nysbvn1 == 172.17.13.14
# njsbvn1 == 172.17.14.10
# Defined above for runtime calculation.
#SCM_HOST		=> "http://172.17.13.14:$SCM_PORT"
#SCM_HOST		=> "http://172.17.14.10:$SCM_PORT"
# Defined above for runtime calculation.
#SCM_HOST_SCM		=> "${SCM_HOST}/scm"

SCM_REQ_POST_CS		            => postChangeSetSCM
SCM_REQ_ENQUEUE_CS	            => enqueueChangeSetSCM
SCM_REQ_SWEEP_INC		    => sweepSCM
SCM_REQ_SWEEP		            => sweepChangesSCM
SCM_REQ_SWEEP_FAST                  => sweepChangesFastSCM
SCM_REQ_FETCH_CS	            => fetchChangeSetSCM
SCM_REQ_GET_UUID_BY_UNIX_LOGIN      => getUUIDByUnixLoginSCM
SCM_REQ_RECOVER_FILES               => recoverFilesSCM
SCM_REQ_CREATE_ROLLBACK             => createRollbackSCM
SCM_REQ_COPY_OUT_FILES_BY_CSID      => copyoutFilesByCsidSCM
SCM_REQ_COPY_OUT_LATEST_FILES       => copyoutLatestFilesSCM
SCM_REQ_RECOVER_CURRENT             => recoverCurrentSCM
SCM_REQ_RECOVER_PRIOR               => recoverPriorSCM
SCM_REQ_RECOVER_LIST                => recoverListSCM
SCM_REQ_CSID_IS_STAGED              => csidIsStagedSCM
SCM_REQ_DO_SWEEP_CALCULATION        => doSweepCalculationSCM
SCM_REQ_GET_SWEEP_FILELIST          => getSweepFilelistSCM
SCM_REQ_FILES_STAGED                => filesStagedSCM
SCM_REQ_RECORD_BRANCH_PROMOTION     => recordBranchPromotionSCM
SCM_REQ_PATH_EXISTS                 => pathExistsSCM
SCM_REQ_BLAME                       => blameSCM

HTTP_METHOD             => POST
HTTP_VERSION            => HTTP/1.1
PROTOCOL                => TCP

HEADER_HOST             => Host
HEADER_REASONPHASE      => reasonPhase
HEADER_STATUSCODE       => StatusCode

SCM_CSDB_PREFIX                 => Csq

# Production CSDB Request
CSDB_CREATE_CHANGE_SET_DB_RECORD => "${SCM_CSDB_PREFIX}CreateChangeSetDbRecord"
CSDB_GET_CHANGE_SET_DB_RECORD    => "${SCM_CSDB_PREFIX}GetChangeSetDbRecord"
CSDB_UPDATE_CHANGE_SET_DB_STATUS => "${SCM_CSDB_PREFIX}UpdateChangeSetDbStatus"
CSDB_MULTI_UPDATE_STATUS         => "${SCM_CSDB_PREFIX}MultiUpdateStatus"
CSDB_GET_CHANGE_SET_HISTORY      => "${SCM_CSDB_PREFIX}GetChangeSetHistory"
CSDB_GET_FILE_HISTORY            => "${SCM_CSDB_PREFIX}GetFileHistory"
CSDB_GET_CS_INFO                 => "${SCM_CSDB_PREFIX}GetCsInfo"
CSDB_GET_DEPS_OF_CHANGE_SET      => "${SCM_CSDB_PREFIX}GetDepsOfChangeSet"
CSDB_GET_CHANGE_SET_REFERENCES   => "${SCM_CSDB_PREFIX}GetChangeSetReferences"

#Production BAS Request
BAS_CREATE_PRQS_TICKET           => "BasCreatePRQSTicket"
BAS_ADD_TICKET_NOTE              => "BasAddTicketNote"
BAS_IS_VALID_TICKET              => "BasIsValidTicket"
BAS_GET_VALID_TSMV_SUMMARY       => "BasGetValidTSMVSummary"
BAS_POPULATE_TSMV                => "BasPopulateTSMV"
BAS_ROLLBACK_TSMV                => "BasRollbackTSMV"

BAS_GET_EMOVE_LINK_TYPE          => "BasGetEmoveLinkType"
BAS_IS_BETA_DAY                  => "BasIsBetaDay"
BAS_IS_VALID_APPROVER            => "BasIsValidApprover"
BAS_ARE_VALID_TESTERS            => "BasAreValidTesters"
BAS_GET_LOCK_DOWN_STATUS         => "BasGetLockdownStatus"
BAS_GET_MULTI_UUID_BY_UNIX_NAME  => "BasGetMultiUuidByUnixLogin"
BAS_GET_PRQS_STATUS              => "BasGetPrqsStatus"
BAS_UPDATE_PRQS_STATUS           => "BasUpdatePrqsStatus"

BAS_GENERATE_BREG_MAPPING        => "BasGenerateBregMapping"

BAS_ATTACH_CSID_TO_BBMV		 => "BasAttachCSIDToBBMV"
BAS_IS_ENABLED_FOR_BBMV		 => "BasIsEnabledForBBMV"
BAS_IS_VALID_BBMV_TICKET	 => "BasIsValidBBMVTicket"


##############################################################################
# Symbols for the various request types that go either to csdbsrv.tsk or BAS #
##############################################################################


# BAS requests
SCM_SEND_COMMIT_MESSAGE         => BasSendCommitMessage
SCM_SEND_MANAGER_COMMIT_MSG     => BasSendManagerCommitMSG
SCM_SEND_GENERIC_MESSAGE        => BasSendGenericMessage
SCM_GET_UUID_BY_UNIX_LOGIN      => BasGetUUIDByUnixLogin
SCM_GET_UNIX_LOGIN_BY_UUID      => BasGetUnixLoginByUUID
SCM_ADD_TICKET_NOTE             => BasAddTicketNote
SCM_POPULATE_TSMV               => BasPopulateTSMV
SCM_ROLLBACK_TSMV               => BasRollbackTSMV
SCM_ARE_VALID_TESTERS           => BasAreValidTesters
SCM_CREATE_PRQS_TICKET          => BasCreatePRQSTicket
SCM_GET_LOCKDOWN_STATUS         => BasGetLockdownStatus
SCM_GET_VALID_TSMV_SUMMARY      => BasGetValidTSMVSummary
SCM_IS_BETA_DAY                 => BasIsBetaDay
SCM_GET_EMOVE_LINK_TYPE         => BasGetEmoveLinkType
SCM_IS_VALID_APPROVER           => BasIsValidApprover
SCM_IS_VALID_TICKET             => BasIsValidTicket

# CSDB requests
SCM_CREATE_CSDB_RECORD		    => "${SCM_CSDB_PREFIX}CreateChangeSetDbRecord"
SCM_GET_CS_STATUS                   => "${SCM_CSDB_PREFIX}GetChangeSetStatus"
SCM_GET_CSDB_RECORD                 => "${SCM_CSDB_PREFIX}GetChangeSetDbRecord"
SCM_MULTI_UPDATE_STATUS             => "${SCM_CSDB_PREFIX}MultiUpdateStatus"
SCM_UPDATE_CSDB_STATUS              => "${SCM_CSDB_PREFIX}UpdateChangeSetDbStatus"
SCM_ADD_DEPENDENCY                  => "${SCM_CSDB_PREFIX}CreateDependentCS"
SCM_DELETE_DEPENDENCY               => "${SCM_CSDB_PREFIX}DeleteDependentCS"
SCM_GET_LATEST_SWEPT_CSID           => CsqGetLatestSweptCsid

# Validation switches
VALIDATE_OLD_ORACLE             => 1
VALIDATE_NEW_ORACLE_AIX         => 0
VALIDATE_NEW_ORACLE_SOLARIS     => 0
ENFORCE_OLD_ORACLE              => 1
ENFORCE_NEW_ORACLE_AIX          => 0
ENFORCE_NEW_ORACLE_SOLARIS      => 0

# New validation stuff
VALIDATION_HOST                 => "nyfbldo1"

# Oracle stuff
SYMBOL_ORACLE_LIBS              => "/bb/csdata/robo/libcache"

STATIC_INITIALIZERS_ARE_EVIL    => 0

SYMBOL_ORACLE_HOST              => "nysbldo1"
SYMBOL_ORACLE_PORT              => 7788

SYMBOL_ORACLE_SOURCE_HOST       => "nysbldo1"
SYMBOL_ORACLE_SOURCE_PORT       => 7788

SYMBOL_ORACLE_STAGE_HOST        => "nysbldo1"
SYMBOL_ORACLE_STAGE_PORT        => 7778

SYMBOL_ORACLE_LOCAL_HOST        => "nysbldo1"
SYMBOL_ORACLE_LOCAL_PORT        => 7768

SYMBOL_ORACLE_SOURCE_HOST1      => "nysbldo1"
SYMBOL_ORACLE_SOURCE_PORT1      => 7788
SYMBOL_ORACLE_SOURCE_HOST2      => "nysbldo1"
SYMBOL_ORACLE_SOURCE_PORT2      => 7789

SYMBOL_ORACLE_STAGE_HOST1       => "nysbldo1"
SYMBOL_ORACLE_STAGE_PORT1       => 7778
SYMBOL_ORACLE_STAGE_HOST2       => "nysbldo1"
SYMBOL_ORACLE_STAGE_PORT2       => 7779

SYMBOL_ORACLE_LOCAL_HOST1       => "nysbldo1"
SYMBOL_ORACLE_LOCAL_PORT1       => 7768
SYMBOL_ORACLE_LOCAL_HOST2       => "nysbldo1"
SYMBOL_ORACLE_LOCAL_PORT2       => 7769

SYMBOL_ORACLE_HOST1             => "nysbldo1"
SYMBOL_ORACLE_PORT1             => 7788
SYMBOL_ORACLE_HOST2             => "nysbldo1"
SYMBOL_ORACLE_PORT2             => 7779

BUILD_ONLY_MACHINES             => "nyibldo1,nyibldo2,nysbldo1,nysbldo2,nyfbldo1,nyfbldo2"

# False when we are in production mode
# True when etc/csenv is loaded. This allows
# us to change the behaviour of tools like
# cscheckin to properly work in test mode.
ENVIRONMENT_IS_TEST             => 0

