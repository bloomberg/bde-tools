package SCM::CSDB::FileHistory;

use strict;
use warnings;

use base qw/SCM::CSDB/;

use Change::Symbols qw/$FILE_IS_UNCHANGED/;

our $SQL = {
    file_sweep_history =>
	qq{ select
	       cs.change_set_name         as csid,
	       cs.create_user             as creator,
	       cs.create_tsp              as create_time,
	       rc_movetype.ref_code_value as movetype,
	       rc_status.ref_code_value   as status,
	       ch.status_tsp              as update_time
	   from
	       change_set as cs,
	       change_set_file as cf,
	       chg_set_stat_his as ch,	    
	       ref_code as rc_movetype,
	       ref_code as rc_status,
               ref_code as rc_type
	   where
	       rc_status.ref_code_value = 'C'                   and
               rc_type.ref_code_value   = '$FILE_IS_UNCHANGED'  and

	       cf.change_set_id         = cs.change_set_id      and
	       ch.change_set_id         = cs.change_set_id      and
	       cf.file_name             = %filename%            and
	       ch.status_cd             = rc_status.ref_cd      and
               cf.file_change_type      != rc_type.ref_cd       and
	       cs.move_type             = rc_movetype.ref_cd    and
	       cs.number_of_files       > 0
	   order by
	       ch.status_tsp desc},
   history_after_cutoff =>
       qq{ select
	     cs.change_set_name           as csid,
	     cs.create_tsp                as create_time,
	     cs.create_user               as creator,
	     rc_movetype.ref_code_value   as movetype,
	     rc_status.ref_code_value     as status,
	     ch.status_tsp                as update_time
	 from
	     change_set as cs,
	     change_set_file as cf,
	     chg_set_stat_his as ch,
	     ref_code as rc_movetype,
	     ref_code as rc_status,
             ref_code as rc_type
	 where
             rc_type.ref_code_value             = '$FILE_IS_UNCHANGED'              and
	     rc_movetype.ref_code_value         = %move%                            and

	     ch.status_tsp                      > datetime(&cutoff&) year to second and
	     cf.change_set_id                   = cs.change_set_id                  and
	     cf.file_name                       = %filename%                        and
             cf.file_change_type                != rc_type.ref_cd                   and
	     rc_movetype.ref_cd                 = cs.move_type                      and
	     ch.change_set_id                   = cs.change_set_id                  and	      
	     ch.status_cd                       = rc_status.ref_cd                  and
	     rc_status.ref_code_value           = 'C'                               and
	     cs.number_of_files                 > 0
	order by
	    ch.status_tsp desc},

       history_after_cutoff_no_beta =>
	   qq{ select
	     cs.change_set_name           as csid,
	     cs.create_tsp                as create_time,
	     cs.create_user               as creator,
	     rc_movetype.ref_code_value   as movetype,
	     rc_status.ref_code_value     as status,
	     ch.status_tsp                as update_time
	 from
	     change_set as cs,
	     change_set_file as cf,
	     chg_set_stat_his as ch,
	     ref_code as rc_movetype,
	     ref_code as rc_status,
	     ref_code as rc_stage,
             ref_code as rc_type
	 where
	     rc_status.ref_code_value       = 'C'                   and
             rc_type.ref_code_value         = '$FILE_IS_UNCHANGED'  and
	     rc_movetype.ref_code_value     = %move%                and

	     ch.status_tsp>datetime(&cutoff&) year to second a      and
	     cf.change_set_id               = cs.change_set_id      and
	     cf.file_name                   = %filename%            and
             cf.file_change_type            != rc_type.ref_cd       and
	     rc_movetype.ref_cd             = cs.move_type          and
	     ch.change_set_id               = cs.change_set_id      and	      
	     ch.status_cd                   = rc_status.ref_cd      and
	     rc_stage.ref_cd                = cs.stage_id           and
	     rc_stage.ref_code_value        != 'BETA'               and	     
	     cs.number_of_files             > 0
	order by
	    ch.status_tsp desc},

   history_before_cutoff =>
       qq{ select
	     cs.change_set_name           as csid,
	     cs.create_tsp                as create_time,
	     cs.create_user               as creator,
	     rc_movetype.ref_code_value   as movetype,
	     rc_status.ref_code_value     as status,
	     ch.status_tsp                as update_time
	from
	    change_set as cs,
	    change_set_file as cf,
	    chg_set_stat_his as ch,
	    ref_code as rc_movetype,
	    ref_code as rc_status,
            ref_code as rc_type
        where
            rc_type.ref_code_value          = '$FILE_IS_UNCHANGED'              and
	    rc_status.ref_code_value        = 'C'                               and	

	    cf.change_set_id                = cs.change_set_id                  and
	    ch.status_tsp                   < datetime(&cutoff&) year to second and
	    cf.file_name                    = %filename%                        and
            cf.file_change_type             != rc_type.ref_cd                   and
	    ch.change_set_id                = cs.change_set_id                  and
	    cs.move_type                    = rc_movetype.ref_cd                and   
	    ch.status_cd                    = rc_status.ref_cd                  and
	    cs.number_of_files              > 0
	    
	order by
	    ch.status_tsp desc},

	file_history => 
	    qq{ select
	     cs.change_set_name           as csid,
	     cs.create_user               as creator,
	     cs.create_tsp                as create_time,
	     rc_stage.ref_code_value      as stage,	     
	     rc_movetype.ref_code_value   as movetype,
	     rc_ticket.ref_code_value	  as ticket_type,
	     cs.ticket_number		  as ticket_number,
	     cs.number_of_files		  as num_files,
	     rc_status.ref_code_value     as status,
	     cs.short_descr		  as description	     
	from
	    change_set as cs,
	    change_set_file as cf,
	    ref_code as rc_movetype,
	    ref_code as rc_status,
	    ref_code as rc_stage,
	    ref_code as rc_ticket,
            ref_code as rc_type
        where
            rc_type.ref_code_value  = '$FILE_IS_UNCHANGED'  and

	    cf.change_set_id        = cs.change_set_id      and
	    cf.file_name            = %filename%            and
	    cs.ticket_type          = rc_ticket.ref_cd      and 
	    cs.move_type            = rc_movetype.ref_cd    and   
	    cs.status_cd            = rc_status.ref_cd      and
	    cs.stage_id             = rc_stage.ref_cd       and
	    cs.number_of_files      > 0      
	order by
	    cs.create_tsp desc},
};


sub getLatestSweptCsid {
    my ($self, $filename, %args) = @_;
    
    my $rec = $self->select_one('file_sweep_history', { filename => $filename});
   # $self->throw("$filename sweep history not found") if not defined $rec;
    
    return $rec;
}

sub getFileSweptHistory {
    my ($self, $filename, %args) = @_;

    my @recs = $self->select_all('file_sweep_history', $filename);
    return @recs;
}

sub history_after_cutoff {
    my ($self, $filename, %arg) = @_;
    my $rec = $self->select_one('history_after_cutoff',
				{filename => $filename,
				 move => $arg{move}, 
				 cutoff => $arg{cutoff}});
    return $rec;
} 

sub history_before_cutoff {
    my ($self, $filename, %arg) = @_;
    my $rec = $self->select_one('history_before_cutoff',
				{filename => $filename,		
				cutoff   => $arg{cutoff}});
    return $rec;
} 

sub history_after_cutoff_no_beta {
    my ($self, $filename, %arg) = @_;
    my $rec = $self->select_one('history_after_cutoff',
				{filename => $filename,
				 move     => $arg{move},
				 cutoff   => $arg{cutoff}});
    return $rec;
}

sub getFileHistory {
    my ($self, $filename, $start, $end) =@_;
    my $rec = $self->select_all('file_history',
				{filename => $filename});
    return $rec;
}
