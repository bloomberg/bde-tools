# vim:set ts=8 sts=4 sw=4 noet:

package SCM::Symbols;
use strict;

use base qw(Common::Symbols);

use vars qw($OVERRIDE_PREFIX);

use Symbols;

$OVERRIDE_PREFIX = "SCM_";

#==============================================================================

=head1 NAME

SCM::Symbols - Symbols for Source Control Management.

=head1 SYNOPSIS

    use SCM::Symbols qw(SCM_QUEUE);

=head1 DESCRIPTION

This module provides descriptive constants for use with SCM.

=head1 CONSTANTS

Each of the following constants are exportable on requeust.

=head2 Base directory for an SCM queue

=over 4

=item SCM_QUEUE

=back

=head2 FIFOs for triggering the daemons

=over 4

=item SCM_PREQUEUE_TRIGGER

=item SCM_INCOMING_TRIGGER

=back

=head2 Subdirectories inside a queueing system

=over 4

=item SCM_DIR_TMP

=item SCM_DIR_PREQUEUE

=item SCM_DIR_DATA

=item SCM_DIR_QUEUE

=item SCM_DIR_PENDING

=item SCM_DIR_DONE

=item SCM_DIR_FAIL

=item DSCM_DIR_REJECT

=item SCM_DIR_TERM

=item SCM_DIR_ABANDON

=item SCM_DIR_ROLLBACK

=item SCM_DIR_OFFLINE

=back

=head2 Job file priorities

=over 4

=item SCM_PRIO_ROLLBACK

=item SCM_PRIO_EMERGENCY

=item SCM_PRIO_BUGFIX

=item SCM_PRIO_DEVCHANGE

=item SCM_PRIO_IMMEDIATE

=back

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=head1 SEE ALSO

L<Common::Symbols>, L<Change::DB>, L<bde_createcs.pl>

=cut

#==============================================================================

1;

__DATA__

RELEASE			=> { Symbols->RELEASE }
CONFDIR			=> { Symbols->CONFDIR }
%INCLUDE		"${CONFDIR}/${RELEASE}/scm.sym"

SCM_ROOT                => /bb/csdata/scm

# Base directory for SCM queue.
SCM_QUEUE		=> "$SCM_ROOT/data/queue"
SCM_REPOSITORY		=> "$SCM_ROOT/data/repository"

# Base directory for diff reports
SCM_DIFF_PATH           => "$SCM_ROOT/data/diffs"

# Desc directory
SCM_DESCRIPTION_PATH    => "$SCM_ROOT/data/desc"

# directory tree for SCM stats
SCM_STATS_PATH		    => "$SCM_ROOT/data/stats"
SCM_STATS_CHECKIN_WEEKLY    => "$SCM_STATS_PATH/checkin/weekly"
SCM_STATS_LOAD_DAILY	    => "$SCM_STATS_PATH/load/daily"
SCM_STATS_DEV_LOG           => "$SCM_STATS_PATH/dev"

# The FIFOs to trigger the respective daemon
SCM_PREQUEUE_TRIGGER	=> "$SCM_ROOT/service/prequeued/trigger"
SCM_TESTING_TRIGGER	=> "$SCM_ROOT/service/testd/trigger"
SCM_PRECOMMIT_TRIGGER	=> "$SCM_ROOT/service/precommitd/trigger"
SCM_COMMIT_TRIGGER	=> "$SCM_ROOT/service/commitd/trigger"
SCM_SWEEP_TRIGGER	=> "$SCM_ROOT/service/sweepd/trigger"
SCM_OFFLINE_TRIGGER	=> "$SCM_ROOT/service/offline/trigger"

# lock files
SCM_SWEEP_LOCK		=> "$SCM_ROOT/service/sweepd/lock"

# The various subdirectories in a queue system
SCM_DIR_TMP		=> tmp
SCM_DIR_PREQUEUE	=> prequeue
SCM_DIR_DATA		=> data
SCM_DIR_OFFLINE		=> offline
SCM_DIR_QUEUE		=> queue
SCM_DIR_PRECOMMIT	=> precommit
SCM_DIR_PENDING		=> pending
SCM_DIR_DONE		=> committed
SCM_DIR_REJECT		=> reject
SCM_DIR_FAIL		=> fail
SCM_DIR_TERM		=> term
SCM_DIR_ABANDON		=> abandon
SCM_DIR_ROLLBACK	=> rollback
SCM_DIR_SWEPT		=> swept
SCM_DIR_INPROG		=> inprogress
SCM_DIR_COMPILE_FAIL	=> compile/fail
SCM_DIR_COMPILE_OK	=> compile/ok
SCM_DIR_COMPILE_LOGS	=> compile/logs
SCM_DIR_COMPILE_RB	=> compile/rback
SCM_DIR_COMPILE_STATS	=> compile/stats

# Scratchpad area on sundev13's scm. Compile-tests happen in here.
SCM_TMP			=> /bb/csdata/scm/tmp

# Job file priorities
SCM_PRIO_ROLLBACK   => 0
SCM_PRIO_EMERGENCY  => 1
SCM_PRIO_BUGFIX     => 2
SCM_PRIO_DEVCHANGE  => 3
SCM_PRIO_IMMEDIATE  => 99

# Repository behavior flags
SCM_REPOSITORY_AUTOADD        => 1
SCM_REPOSITORY_AUTOCHANGE     => 1
SCM_ROLLBACK_DIRS             => 0

# CSDB name
SCM_CSDB            => changesetdb
SCM_CSDB_DRIVER     => Informix

# Location of CDB cache for the uuid service
SCM_UUID_DATA       => "$SCM_ROOT/data/uuid"

# Should uuid caches be automatically rebuilt on init?
SCM_UUID_REBUILD_CACHES => 1

# Location of CDB cache for rev <-> csid mappings
SCM_REV2CSID_DATA   => "$SCM_ROOT/data/rev2csid"
SCM_CSID2REV_DATA   => "$SCM_ROOT/data/csid2rev"

# Location of CDB cache for branch info
SCM_BRANCHINFO_DATA => "$SCM_ROOT/data/branchinfo"

# Location of CDB cache for svn commit info
SCM_COMMITINFO_DATA => "$SCM_ROOT/data/commitinfo"

# Location of file that stores the last swept CSID when a branch promotion happened in roboland
SCM_BRANCH_PROMOTION_MARK => "$SCM_ROOT/data/branchpromotion/csid_at_prom"

# Location of sweep-info related stuff
SCM_SWEEPINFO_DATA => "$SCM_ROOT/data/sweepinfo"

# stagedby cache location
SCM_STAGEDBY_DATA => "$SCM_ROOT/data/stagedby"

# rpcd stuff
SCM_RPCD_PORT	    => 28274
SCM_RPCD_REGISTRY   => "$SCM_ROOT/data/registry"

SCM_FALLBACK_CSID   => "A00000000000000000"
