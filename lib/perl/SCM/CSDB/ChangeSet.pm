# vim:set ts=8 sts=4 noet:

package SCM::CSDB::ChangeSet;

use strict;
use warnings;

use base qw/SCM::CSDB/;

use Change::Symbols     qw/MOVE_EMERGENCY MOVE_IMMEDIATE
			   $DEPENDENCY_TYPE_DEPENDENT
			   $DEPENDENCY_TYPE_CONTINGENT
			   $DEPENDENCY_TYPE_SIBLING
			   $DEPENDENCY_TYPE_ROLLBACK
			   $DEPENDENCY_TYPE_NONE/;
use Production::Symbols qw/$HEADER_APPROVER $HEADER_TESTER
                           $HEADER_FUNCTION $HEADER_TASK/;

our $SQL = {
  get_cs_record => 
    q{ select cs.change_set_name		as csid,
	      cs.create_tsp			as create_time,
	      cs.create_user			as creator,
	      r1.ref_code_value			as ticket_type,
	      cs.ticket_number			as ticket_number,
	      r2.ref_code_value			as stage,
	      r3.ref_code_value			as movetype,
	      cs.number_of_files		as num_files,
	      cs.short_descr			as description,
	      cs.prqs_number                    as prqs_no,
	      r4.ref_code_value                 as status,
	      cs.dev_ref_tag                    as reference
	from  change_set as cs, ref_code as r1,
	      ref_code as r2, ref_code as r3,
	      ref_code as r4
	where cs.change_set_name = %csid%       and
	      cs.ticket_type = r1.ref_cd        and
	      cs.stage_id = r2.ref_cd           and
	      cs.move_type = r3.ref_cd          and
	      cs.status_cd = r4.ref_cd 
    },

  get_cs_deps => 
    q{ select c2.change_set_name,
	      r.ref_code_value  
       from   change_set as c1, change_set as c2, 
	      change_set_dep as d, ref_code as r
       where  c1.change_set_name = %csid%                and
	      c1.change_set_id = d.change_set_id         and
	      d.change_set_id_targ = c2.change_set_id    and
	      d.change_set_dep_typ = r.ref_cd 
    },

  get_cs_files => 
    q{ select f.source_location, f.target_location,
	      f.staging_location, f.file_name,
	      f.lib_identifier, r.ref_code_value,
	      f.chg_set_file_id
       from   change_set_file as f, change_set as c,
	      ref_code as r
       where  c.change_set_name = %csid%           and
	      f.change_set_id = c.change_set_id    and
	      r.ref_cd = f.file_change_type
       order by f.chg_set_file_id 
    },

  get_cs_approver => 
    q{ select a.val_string as val
       from   change_set as cs, attribute_def as d,
	      attribute_value as a
       where  cs.change_set_name = %csid%	      and
	      d.attr_name	 = 'emapprover'	      and
	      a.attribute_id	 = d.attribute_id     and
	      a.change_set_id	 = cs.change_set_id 
    },

  get_cs_tasks =>
    q{ select t.task_name as val
       from   change_set_task as t, change_set as cs
       where  cs.change_set_name  = %csid% and
	      t.change_set_id	  = cs.change_set_id
    },

  get_cs_funcs =>
    q{ select f.bb_func as val
       from   change_set_func as f, change_set as cs
       where  cs.change_set_name = %csid% and
	      f.change_set_id	 = cs.change_set_id
    },

  get_cs_testers => 
    q{ select t.tester_uuid as val
       from   chg_set_tester as t, change_set as cs
       where  cs.change_set_name = %csid% and
	      t.change_set_id	 = cs.change_set_id
    },

  get_emov_props => 
    q{ select task.task_name as task, func.bb_func as function, 
	      test.tester_uuid as tester, 
	      attr.val_string as approver
       from   change_set_task as task, change_set_func as func,
	      chg_set_tester as test, attribute_value as attr,
	      attribute_def as def, change_set as cs
       where  cs.change_set_name = %csid%              and
	      task.change_set_id = cs.change_set_id    and
	      func.change_set_id = cs.change_set_id    and
	      test.change_set_id = cs.change_set_id    and
	      def.attr_name      = 'emapprover'        and
	      attr.attribute_id  = def.attribute_id    and
	      attr.change_set_id = cs.change_set_id 
    },

  create_change_set =>
    q{ insert into change_set
	      (change_set_name, create_tsp, create_user, 
	       ticket_type, ticket_number, stage_id, 
	       move_type, number_of_files, short_descr, 
	       priority_cd, prqs_number, status_cd, 
	       update_tsp, update_by_uuid, bvbmv_tkt_type, 
	       bbmv_tkt_number, dev_ref_tag, link_type)
       select  $csid$, current year to fraction(5), $user$, 
	       r1.ref_cd, $tick_num$, r2.ref_cd, 
	       r3.ref_cd, $num_files$, $short_desc$, 
	       r4.ref_cd, $prqs_num$, r5.ref_cd, 
	       current year to fraction(5), $updater_uuid$, r6.ref_cd, 
	       $bbmv_tick_num$, $ref_tag$, r7.ref_cd
       from    ref_code as r1, ref_code as r2, ref_code as r3,
	       ref_code as r4, ref_code as r5, ref_code as r6,
	       ref_code as r7
       where   r1.ref_code_value = %tick_type%	    and
	       r2.ref_code_value = %stage_id%	    and
	       r3.ref_code_value = %move_type%	    and
	       r4.ref_code_value = %priority%	    and
	       r5.ref_code_value = %status%	    and
	       r6.ref_code_value = %bvbmv_tick_type% and
	       r7.ref_code_value = %link_type% 
    }, 

  add_file_to_cs =>
    q{ insert into change_set_file 
	      (change_set_id, source_location, target_location, 
	       staging_location, file_name, lib_identifier, 
	       file_change_type)
       select c.change_set_id, $src$, $targ$, 
	      $dest$, $base$, $lib$, 
	      r.ref_cd
       from   change_set as c, ref_code as r
       where  r.ref_code_value	= %type%  and
	      c.change_set_name = %csid%
    },

  insert_emov_testers =>
    q{ insert into chg_set_tester
	      (tester_uuid, change_set_id)
       select $uuid$, c.change_set_id 
       from   change_set as c
       where  c.change_set_name = %csid% 
    },

  insert_emov_approver =>
    q{ insert into attribute_value 
	      (change_set_id, attribute_id, value_no, 
	       val_string, update_by_uuid, update_tsp)
       select c.change_set_id, d.attribute_id, $val_no$,
	      $approver$, $updater$, current year to fraction(5)
       from   change_set as c, attribute_def as d
       where  c.change_set_name = %csid%	and
	      d.attr_name	= 'emapprover'
    },

  insert_emov_functions => 
    q{ insert into change_set_func
	      (bb_func, change_set_id)
       select $func$, c.change_set_id
       from   change_set as c
       where  c.change_set_name = %csid%
    },

  insert_emov_tasks =>
    q{ insert into change_set_task
	      (task_name, change_set_Id)
       select $task$, c.change_set_id
       from   change_set as c
       where  c.change_set_name = %csid% 
    },

  add_dep_to_cs =>
    q{ insert into change_set_dep 
       select c1.change_set_id, c2.change_set_id, r.ref_cd
       from   change_set as c1, change_set as c2, ref_code as r
       where  c1.change_set_name = %csid%     and
	      c2.change_set_name = %dep_on%   and
	      r.ref_code_value	 = %dep_type% 
    },

  del_dep_from_cs => 
    q{ delete from change_set_dep 
       where  change_set_id	  = (select change_set_id from change_set 
		    		     where change_set_name=%csid%) and 
	      change_set_id_targ  = (select change_set_id from change_set 
				     where change_set_name=%dep_on%) and 
	      change_set_dep_typ  = (select ref_cd from ref_code 
				     where ref_code_value=%dep_type%) 
    },
};

sub getChangeSetDbRecord {
    my ($self, $csid, %args) = @_;

    my $rec = $self->select_one('get_cs_record', { csid => $csid });

    $self->throw("Changeset $csid not found.") if not defined $rec;

    my $dep = $self->getChangeSetDependencies($csid);

    require SCM::Util;
    require Change::Set;
    my $cs = Change::Set->new({
	    csid        => $rec->{csid},
	    when        => SCM::Util::datetime2csdate($rec->{create_time}),
	    user        => $rec->{creator},
	    stage       => lc($rec->{stage}),
	    move        => $rec->{movetype},
	    ticket      => join('', @$rec{qw/ticket_type ticket_number/}),
	    status      => $rec->{status},
	    depends     => $dep,
	    $rec->{reference} 
		? (reference   => [ $rec->{reference} ])
		: ()
    });

    require SCM::UUID;
    my $resolve = SCM::UUID->new;

    my $msg = '';
    if (my $appr  = $self->getChangeSetApprover($csid)) {
	$appr =~ s/\s+$//;
	my $name = $resolve->uuid2unix($appr);
	$msg = "$HEADER_APPROVER: $name\n";
    }
    if (my @tasks = $self->getChangeSetTasks($csid)) {
	s/\s+$// for @tasks;
	$msg .= "$HEADER_TASK: $_\n" for @tasks;
    }
    if (my @test  = $self->getChangeSetTesters($csid)) {
	s/\s+$// for @test;
	my @names = map scalar $resolve->uuid2unix($_), @test;
	$msg .= "$HEADER_TESTER: $_\n" for @names;
    }
    if (my @funcs = $self->getChangeSetFunctions($csid)) {
	s/\s+$// for @funcs;
	$msg .= "$HEADER_FUNCTION: $_\n" for @funcs;
    }

    $msg .= "\n" if $msg;
    $msg .= $rec->{description};
    $cs->setMessage($msg);

    $cs->addFiles(@{ $self->getFilesForChangeSet($csid) });

    return $cs;
}

sub getChangeSetDependencies {
    my ($self, $csid, %args) = @_;
    my $res = $self->select_all('get_cs_deps', { csid => $csid });
    my %dep;
    $dep{$_->[0]} = substr($_->[1], 0, 1) for @$res;
    return \%dep;
}

sub getFilesForChangeSet {
    my ($self, $csid, %args) = @_;
    my $res = $self->select_all('get_cs_files', { csid => $csid });

    require Change::File;
    my @files;
    for (@$res) {
	my ($src, $target, $dest, $fname, $lib, $type) = @$_;
	push @files, Change::File->new({
		target      => $target,
		source      => $src,
		destination => $dest,
		type        => $type,
		library     => $lib,
		production  => '', # on SCM identifyProductionName is out
	});
    }
    return \@files;
}

sub getEmovProperties {
    my ($self, $csid, %args) = @_;
    return $self->select_one('get_emov_props', { csid => $csid });
}

sub getChangeSetApprover {
    my ($self, $csid, %args) = @_;
    my $ret = $self->select_one('get_cs_approver', { csid => $csid });
    return $ret->{val} if $ret;
    return '';
}

sub getChangeSetTasks {
    my ($self, $csid, %args) = @_;
    return map @$_, @{ $self->select_all('get_cs_tasks', { csid => $csid }) };
}

sub getChangeSetFunctions {
    my ($self, $csid, %args) = @_;
    return map @$_, @{ $self->select_all('get_cs_funcs', { csid => $csid }) };
}

sub getChangeSetTesters {
    my ($self, $csid, %args) = @_;
    return map @$_, @{ $self->select_all('get_cs_testers', { csid => $csid }) };
}

sub createChangeSetDbRecord {
    my ($self, $cs, $uuid, %args) = @_;

    # $uuid is, when defined, a hash-ref mapping usernames to uuids.
    # If not defined, create mapping using SCM::UUID.
    if (not defined $uuid) {
	require SCM::UUID;
	my $resolve = SCM::UUID->new;
	for (map $cs->$_, qw/getUser getTesters getApprover/) {
	    my ($err, $id) = $resolve->unix2uuid($_);
	    $uuid->{$_} = $err ? 0 : $id; 
	}
    }

    my ($tick_type, $tick_num) = $cs->getTicket =~ /^(DRQS|TREQ)(\d+)/;

    my %csinfo = (
	csid		=> $cs->getID,
	user		=> $cs->getUser,
	stage_id	=> uc $cs->getStage,
	move_type	=> $cs->getMoveType,
	num_files	=> scalar(my @files = $cs->getFiles),
	short_desc      => _flatten($cs->getMessage),
	priority	=> 'DEFAULT_PRIORITY_CD',
	prqs_num	=> 0,
	status		=> 'B',   # initial state is B - being added
	ref_tag		=> scalar $cs->getReferences,
	updater_uuid    => $uuid->{$cs->getUser},
	bvbmv_tick_type => 'NO_BBMV_TKT',
	bbmv_tick_num   => 0,
	link_type	=> 'REGULAR',
	tick_type	=> $tick_type,
	tick_num	=> $tick_num,
    );

    $self->throw("Wont create change set record without CSID")
	if not defined $csinfo{csid};

    my $txn = $self->_enter_txn(\%args);

    # insert basic change set information. This is stuff
    # usually in the change set header, minus emov props.
    my $ok = $self->execute('create_change_set', \%csinfo);

    # insert status B, being added, to chg_set_stat_his
    require SCM::CSDB::History;
    my $hcsdb = SCM::CSDB::History->new(dbh => $self->dbh);
    $hcsdb->insertStatusHistory($csinfo{csid}, %args);

    # emov and stpr have an approver,
    # unless it's a rollback request

    my $is_rollback = $cs->getDependenciesByType($DEPENDENCY_TYPE_ROLLBACK);

    # only exists for emov and stpr, but who knows.
    $self->addChangeSetApprover($csinfo{csid}, $_, $uuid->{$cs->getUser}, %args)
	for map $uuid->{$_}, $cs->getApprover;

    # the following should only exist for emovs. Again, who knows.
    $self->addChangeSetTester($csinfo{csid}, $_, %args)
	for map $uuid->{$_}, $cs->getTesters;
    $self->addChangeSetTask($csinfo{csid}, $_, %args)
	for $cs->getTasks;
    $self->addChangeSetFunction($csinfo{csid}, $_, %args)
	for $cs->getFunctions;

    # insert dependencies
    $self->addDependenciesToChangeSet($csinfo{csid}, $cs->getDependencies, %args)
	if %{ $cs->getDependencies };

    # insert files. Sigh, will this ever end...
    $self->addFilesToChangeSet($csinfo{csid}, \@files, %args);

    # haha, and you thought we were done now.
    require SCM::CSDB::Status;
    SCM::CSDB::Status->new(dbh => $self->dbh)
		     ->alterChangeSetDbRecordStatus($csinfo{csid},
						    newstatus => $cs->getStatus,
						    uuid      => $uuid->{$cs->getUser},
						    %args);
    # Done!
    $txn->commit if $txn;

    return $ok;
}

sub addFilesToChangeSet {
    my ($self, $csid, $files, %args) = @_;

    my $txn = $self->_enter_txn(\%args);

    # we can't use execute_array since for each file
    # we need to prepare a new statment: all of the following
    # parameters but 'csid' are in fact inserted as literals
    # into the select-clause.
    for my $f (@$files) {
	$self->execute('add_file_to_cs', { csid => $csid,
					   src  => $f->getSource,
					   dest => $f->getDestination,
					   targ => $f->getTarget,
					   lib  => $f->getLibrary,
					   base => $f->getLeafName,
					   type => $f->getType, });
    }

    $txn->commit if defined $txn;
    return scalar @$files;
}

my %dep2dep = (
  $DEPENDENCY_TYPE_DEPENDENT  => 'DEPENDENT',
  $DEPENDENCY_TYPE_CONTINGENT => 'CONTINGENT',
  $DEPENDENCY_TYPE_NONE	      => 'NONE',
  $DEPENDENCY_TYPE_ROLLBACK   => 'ROLLBACK',
  $DEPENDENCY_TYPE_SIBLING    => 'SIBLING',

  # The following are for convenience so that we
  # can do the hash lookup even when the type
  # is already in the corract format
  ROLLBACK    => 'ROLLBACK',
  DEPENDENT   => 'DEPENDENT',
  CONTINGENT  => 'CONTINGENT',
  NONE	      => 'NONE',
  SIBLING     => 'SIBLING',
);
sub addDependencyToChangeSet {
  my ($self, $csid, $on, $type, %args) = @_;

  return scalar $self->execute('add_dep_to_cs', { csid      => $csid,
			    			  dep_on    => $on,
				  		  dep_type  => $dep2dep{$type} });
}
sub addDependenciesToChangeSet {
    my ($self, $csid, $pairs, %args) = @_;

    return $self->addDependencyToChangeSet($csid, %$pairs)
	if keys(%$pairs) == 1;

    # execute_array is not atomic so wrap it in transaction
    # This is even more performant so we always win. :-)
    # When called from createChangeSetDbRecord however, we
    # already are inside a transaction. Therefore look at $notxn.
    my $txn; 

    $txn = $self->_enter_txn(\%args);

    my @csids = ($csid) x keys %$pairs;
    my @on    = keys %$pairs;
    my @type  = map $dep2dep{$_}, values %$pairs;

    my $count = $self->execute_array('add_dep_to_cs', { csid	 => \@csids,
							dep_on   => \@on,
							dep_type => \@type, },
						      ArrayTupleStatus => \my @status);

    $txn->commit if defined $txn;

    return $count;
}

sub deleteDependencyFromChangeSet {
    my ($self, $csid, $on, $type, %args) = @_;

    return scalar $self->execute('del_dep_from_cs', { csid     => $csid,
						      dep_on   => $on,
						      dep_type => $dep2dep{$type} });
}

# methods to add emove properties
sub addChangeSetTester {
    my ($self, $csid, $tester, %args) = @_;

    $self->throw("Wont insert NULL tester") if grep !defined, $tester;

    return scalar $self->execute('insert_emov_testers', { csid => $csid,
							  uuid => $tester });
}

sub addChangeSetApprover {
    my ($self, $csid, $approver, $updater, %args) = @_;

    $self->throw("Wont insert NULL approver")
	if not defined $approver;
    $self->throw("Wont insert NULL updater")
	if not defined $updater;

    return scalar $self->execute('insert_emov_approver', { csid      => $csid,
							   approver  => $approver,
							   updater   => $updater,
							   val_no    => 1, # no idea what it's for 
							  });
}

sub addChangeSetFunction {
    my ($self, $csid, $func, %args) = @_;

    $self->throw("Wont insert NULL function") if grep !defined, $func;

    return scalar $self->execute('insert_emov_functions', { csid => $csid,
							    func => $func });
}

sub addChangeSetTask {
    my ($self, $csid, $task, %args) = @_;

    die exception("Wont insert NULL task") if grep !defined, $task;

    return scalar $self->execute('insert_emov_tasks', { csid => $csid,
							task => $task });
}

sub _flatten {
    my $str = shift;

    my $msg;

    if ($str =~ /^Change-Set-\w+:/) {
	(undef, $msg) = split /\n\n/, $str, 2 
    } else {
	$msg = $str;
    }
    $msg =~ tr/\n/ /;

    return $msg;
}

1;
