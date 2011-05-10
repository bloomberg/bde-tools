use strict;
use warnings;

my $informix = '/bb/bin/informix.misc2';
my $database = 'changesetdb@devarch_sec_tcp';

my %sql = (
    create_tables => q{
        create table branch (
            branch_id serial primary key,
            parent_id integer references branch(branch_id),
            start_time datetime year to second not null
        );

        create table branch_map (
            map_id serial primary key,
            branch_alias varchar(254) not null,
            branch_id integer references branch(branch_id),
            start_time datetime year to second not null,
            end_time datetime year to second
        );
    },
    clean_up => q{
        drop table branch_map;
        drop table branch;
    },
);

##############
init();      #
##############

# Put your tests here


##############
cleanup();   #
##############

sub init {
    open SQLCMD, '|-', ". $informix && sqlcmd -d $database" 
        or die "Can't open pipe to sqlcmd: $!";
    print SQLCMD $sql{ create_tables };
    close SQLCMD 
        or die "Can't close pipe to sqlcmd: $! . $?";
}

sub cleanup {
    open SQLCMD, '|-', ". $informix && sqlcmd -d $database" 
        or die "Can't open pipe to sqlcmd: $!";
    print SQLCMD $sql{ clean_up };
    close SQLCMD 
        or die "Can't close pipe to sqlcmd: $! . $?";
}
