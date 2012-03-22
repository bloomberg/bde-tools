#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE  
);

use Change::Symbols qw(
    DBPATH
);

use Change::DB;
use Production::Services;
use Production::Services::ChangeSet qw();
use Util::File::Basename qw(basename);
#==============================================================================
=head1 NAME

Compare change set from development and production

=head1 SYNOPSIS

    $csdbdiff  443D1FE5001047E8F8

=head1 DESCRIPTION

This tool extract change set infromation from production change set database 
and development change set database, compare if they are same and show 
the difference if they are different. Ignore creation time difference since
they are always different on production database and development database

=head1 EXIT STATUS

A non-zero exit status is returned if the change set was not found 
in production database or development database.

=cut   

#==============================================================================
sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-r] <match text>
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting

Search options:

  --regexp      | -r              treat match text as regular expression

Display options:

  --pretty      | -P              list changes in human-parseable output
                                  (default if run interactively)
  --machine     | -M              list changes in machine-parseable output
                                  (default if run non-interactively)
  --expand      | -x              list full changeset details
                                  (default: list only brief details)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        expand|x
        help|h
        machine|M
        pretty|P
        regexp|r
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{list};

    # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	exit EXIT_FAILURE;
    }
    unless ($opts{pretty} or $opts{machine}) {
	if (-t STDOUT) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}
#------------------------------------------------------------------------------
sub convert_mon($)
{
    my($strmon) = @_;
    my $mon;
    
    if($strmon eq "Jan") {
	$mon="01";
    } elsif ($strmon eq "Feb") {
        $mon="02";
    } elsif ($strmon eq "Mar") {
	$mon="03";
    } elsif ($strmon eq "Apr") {	 
	$mon="04";
    } elsif ($strmon eq "May") {
	$mon="05";
    } elsif ($strmon eq "Jun") {
	$mon="06";
    } elsif ($strmon eq "Jul") {
	$mon="07";
    } elsif ($strmon eq "Aug") {
        $mon="08";
    } elsif ($strmon eq "Sep") {
	$mon="09";
    } elsif ($strmon eq "Oct") {
	$mon="10";
    } elsif ($strmon eq "Nov") {
	$mon="11";
    } elsif ($strmon eq "Dec") {
	$mon="12";
    }
    
    return $mon;
}

sub collect_emov_fields($)
{
    my ($headers) = @_;
    my %emovhdr;
 
    while ($headers =~ /^(Change-Set-[-A-Za-z]+): (.*)$/mg ) {
	    push @{$emovhdr{$1}}, $2;
    }
 
    return %emovhdr;
}

sub emov_field_diff(\@\@)
{
    my($dev_flds, $prd_flds) = @_;
    my $isdiff = 0;
   
    if($#{@$dev_flds} ne $#{@$prd_flds}) {
	$isdiff = 1;
	return $isdiff;
    }
  
    foreach my $fld1 (@{$dev_flds}) {
	my $found = 0;
		
	foreach my $fld2 (@{$prd_flds}) {	 
	    if ($fld1 eq $fld2) {
		$found = 1;		
		last;
	    }
	}

	if($found != 1) {	
	    $isdiff = 1;
	    last;
	}
    } 

    return $isdiff;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $isdiff=0;

    my $changedb=new Change::DB('<'.DBPATH);
    error("Unable to access ${\DBPATH}: $!"), return EXIT_FAILURE
	unless defined $changedb;

    my $csid = $ARGV[0];
    my $changeset_dev = $changedb->getChangeSet($csid, undef, "");
    
    my $svc=new Production::Services;
    my $changeset_prod = Production::Services::ChangeSet::getChangeSetDbRecord(
			       $svc, $csid);
  

    if(! defined $changeset_dev) {
	print "Can not find $csid in development\n";
	exit(EXIT_FAILURE); 
    }

    if(! defined $changeset_prod) {
	print "Can not find $csid in production\n"; 
	exit(EXIT_FAILURE);
    }

    if($changeset_dev->getStatus ne $changeset_prod->getStatus){
	$isdiff =1;
	print "Status: development: ",
	      $changeset_dev->getStatus, "\n",
	      "        production: ",
	      $changeset_prod->getStatus, "\n";
    }

    if($changeset_dev->getUser ne $changeset_prod->getUser){
	$isdiff =1;
	print "User: development: ",
	      $changeset_dev->getUser,
	      "\n    production: ",
	      $changeset_prod->getUser, "\n";
    }
    
    if(uc($changeset_dev->getMoveType) ne uc($changeset_prod->getMoveType)){
	$isdiff =1;
	print "MoveType: development: ",
	      $changeset_dev->getMoveType(),"\n",  
	      "          production: ", 
              $changeset_prod->getMoveType,"\n";
    }

    if(uc($changeset_dev->getStage) ne uc($changeset_prod->getStage)){
	$isdiff =1;
	print "Stage: development: ",
              $changeset_dev->getStage(),"\n",
	      "       production: ",
	      $changeset_prod->getStage(),"\n";
    }

    if($changeset_dev->getTicket ne $changeset_prod->getTicket){
	$isdiff =1;
	print "Ticket: development: ",
	      $changeset_dev->getTicket,"\n",
	      "        production: ",
	      $changeset_prod->getTicket,"\n";
    }

    my $dev_message = $changeset_dev->getMessage;
    my $prod_message = $changeset_prod->getMessage;
    
#   reference is stored in emov header
    my %dev_emovhdr;
    if($dev_message =~ /^Change-Set-[-A-Za-z]+:/ ) {
	my $headers;
	($headers,$dev_message) = split(/\n\n/, $dev_message, 2);

	%dev_emovhdr = collect_emov_fields($headers);
    }
    
    my %prod_emovhdr; 
    if($prod_message =~ /^Change-Set-[-A-Za-z]+:/ ){
	my $headers;
	($headers,$prod_message) = split(/\n\n/, $prod_message, 2);	
	%prod_emovhdr = collect_emov_fields($headers);
	
    } else {
	$prod_message =~ /^\s*(\w+)\s*/;
	$prod_message = $1;
    }

    foreach (keys %dev_emovhdr) {	
	my (@dev_fld) = @{$dev_emovhdr{$_}};
	my (@prod_fld)= @{$prod_emovhdr{$_}};

	if(emov_field_diff(@dev_fld, @prod_fld)) {
	    $isdiff = 1;

	    $,=' ';
	    print "$_: development:\n";
	    print @dev_fld, "\n";
	    print "$_: production:\n";
	    print @prod_fld, "\n";
	}
    }

    if($dev_message ne $prod_message){
	$isdiff =1;
	print "Message: development: \n",
	      $dev_message, "\n",
	      "         production: ", 
	      $prod_message,"\n";
    }

    
    my($dev_files, $prod_files);
    $dev_files = $changeset_dev->listFiles;
    $prod_files = $changeset_prod->listFiles;
    
    $dev_files =~ s/:production=.*\s//g;

    $prod_files =~ s/:production=.*\s//g;

    if($dev_files ne $prod_files) {
	$isdiff = 1;
	print "Files: development: ",
	       $dev_files, "\n",
	       "      production: ",
	       $prod_files, "\n";
    }

#   since creation time is always different, we might ignore it for now
#    my ($prod_time_str, $dev_time_str);
#    $dev_time_str = $changeset_dev->getTime;
#    $prod_time_str = $changeset_prod->getTime;
   
#    my($wkofday, $dev_mon, $dev_day, $dev_time, $dev_year) =
#    split(/ +/, $dev_time_str);
  
#    $dev_mon=convert_mon($dev_mon);
#    my $result_day = sprintf("%02d", $dev_day);
#    $dev_time = $dev_year.'-'.$dev_mon.'-'.$result_day.' '.$dev_time;
 
#   if($dev_time ne $prod_time_str){
#	$isdiff =1;
#	print "Creation Time: development: ",
#	      $dev_time,
#	      "\n    production: ",
#	      $prod_time_str, "\n";
#    }

    if(!$isdiff) {
	print "The Change set is same in Production and Development\n";
    } else {
	print "The Change Set is different in Production and Development\n";
    }

    exit EXIT_SUCCESS;
}


#==============================================================================
