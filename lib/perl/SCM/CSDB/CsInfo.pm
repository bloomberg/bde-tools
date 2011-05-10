package SCM::CSDB::CsInfo;

use strict;
use warnings;

use base qw/SCM::CSDB/;
use Date::Manip qw/DateCalc/;

sub _sql_str {
    my ($self, $arg)=@_;

    my $where_clause=$self->construct_where_clause(
			$arg);

    my $sql_str = "select                        
                      cs.update_tsp            as date,
                      cs.create_user           as user,
                      cs.change_set_name       as csid,
                      rc_move.ref_code_value   as move,
                      rc_status.ref_code_value as status,
                      cf.file_name             as file,
                      cf.lib_identifier        as lib
                   from 
                      change_set      as cs,
                      change_set_file as cf,
                      ref_code        as rc_status,
                      ref_code        as rc_move
                   where
                      $where_clause
                   order by
                      cs.update_tsp";
 
    return $sql_str;
}


sub construct_where_clause {
    my ($self, $arg)=@_;

    my $where_clause;
    my $operator;
    
    if(exists $arg->{regex} && defined $arg->{regex}) {
	$operator = "matches";
    } else {
	$operator = "=";
    }

    if( exists $arg->{user} && defined $arg->{user}) {
	$where_clause="cs.create_user $operator %user%";
    }

    if( exists $arg->{file} && defined $arg->{file}) {
        if(defined $where_clause) {
	    $where_clause.=" and cf.file_name $operator %file%";
	} else {
	    $where_clause.="cf.file_name $operator %file%";
	}
    }

    if (exists $arg->{lib} && defined $arg->{lib}) {
	if(defined $where_clause) {
	    $where_clause.=" and cf.lib_identifier $operator %lib%";
	} else {
	    $where_clause.="cf.lib_identifier $operator %lib%";
	}
    }

    if (exists $arg->{csid} && defined $arg->{csid}) {
	if(defined $where_clause) {
	    $where_clause.=" and cs.change_set_name $operator %csid%";
	} else {
	    $where_clause.="cs.change_set_name $operator %csid%";
	}
    }

    if (exists $arg->{status} && defined $arg->{status}) {
	if (defined $where_clause) {
	    $where_clause.=" and rc_status.ref_code_value = %status% and cs.status_cd = rc_status.ref_cd";
	} else {
	    $where_clause.="rc_status.ref_code_value = %status% and cs.status_cd = rc_status.ref_cd";
	}
    }

    if (exists $arg->{move} && defined $arg->{move}) {
	if (defined $where_clause) {
	    $where_clause.=" and rc_move.ref_code_value = %move% and cs.move_type = rc_move.ref_cd";
	} else {
	    $where_clause.="rc_move.ref_code_value = %move% and cs.move_type = rc_move.ref_cd";
	}
    }

    if (exists $arg->{start} && defined $arg->{start}) {
	if(defined $where_clause) {
	    $where_clause.=" and cs.create_tsp > &start&";
        } else {
	    $where_clause.="cs.create_tsp > &start&";
	}
    }
    
    if (exists $arg->{end} && defined $arg->{end}) {
	if(defined $where_clause) {
	    $where_clause.=" and cs.create_tsp < &end&";
	} else {
	    $where_clause.="cs.create_tsp < &end&";
	}
    }

    
    $where_clause.= " and cf.change_set_id = cs.change_set_id and cs.status_cd = rc_status.ref_cd and cs.move_type = rc_move.ref_cd and rc_status.ref_code_value != 'R' and  rc_status.ref_code_value != 'I'";
    warn "<<< where clause is: $where_clause\n";

    return $where_clause;
}

sub  _get_query {
    my ($self, $query, $values)=@_;

    my $sql = $self->_sql_str($values);
    
    my @parms;
    $sql =~ s/&(\w+?)&/$self->_sub_literal($values, $1, $query)/ge;
    $sql =~ s/%(\w+?)%/push @parms, $self->_sub_bind($values, $1, $query); '?'/ge;
  

    warn "<<< param is:  @parms \n";
    warn "<<< sql is: $sql \n";

    return ($sql, \@parms, undef);
}

sub getCsInfo {
    my ($self, %arg)=@_;
    
    if(exists $arg{start} && defined $arg{start}) {
	$arg{start}=$arg{start}." 00:00:00";
    }
    else {	
	my($year, $month, $day) = 
	    DateCalc('today', '-15 days') =~ /(\d\d\d\d)(\d\d)(\d\d)/;
	$arg{start}= "$year-$month-$day 00:00:00";
    }
 
    if(exists $arg{end} && defined $arg{end}) {	
	$arg{end}=$arg{end}." 00:00:00";
    } 
    else {
	my ($sec, $min, $hr, $day, $mon, $year)=localtime();
	$year+=1900;
	$mon+=1;
	if ($mon <10){
	    $arg{end}="$year-0$mon-$day 00:00:00";
	} else {
	    $arg{end}="$year-$mon-$day 00:00:00";
	}
    }

    my $recs=$self->select_all('get_cs_info',
			       \%arg);
    return $recs;
}

1;

