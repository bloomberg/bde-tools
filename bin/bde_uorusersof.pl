#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use File::Path;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Util::File::Basename qw(basename);

use Getopt::Long;

use BDE::FileSystem;
use BDE::FileSystem::MultiFinder;
use BDE::Util::Nomenclature qw(
    getCanonicalUOR  isValidDependency
);
use BDE::Util::DependencyCache qw( getAllGroupDependencies
				   getCachedGroupOrIsolatedPackage
				   getBuildOrder);
use Change::Symbols qw( STAGE_PRODUCTION_ROOT);
use Util::Message qw(
    message warning error fatal debug debug2 debug3
); 
use Symbols qw(EXIT_FAILURE EXIT_SUCCESS);

#==============================================================================

=head1 NAME

bde_uorusersof.pl 

=head1 SYNOPSYS

    List direct dependants
    $ bde_uorusersof.pl bde
    $ bde_uorusersof.pl bde bae

    List direct and indirect dependants
    $ bde_uorusersof.pl -i bae
    $ bde_uorusersof.pl -i bde bae

    List dependants in canonical order
    $ bde_uorusersof.pl -o bde
    $ bde_uorusersof.pl -o -i bde

    pretty mode
    $ bde_uorusersof.pl -p bde
    
    machine mode
    $ bde_uorusersof.pl -m bde > bde.usersof

    

=head1 DESCRIPTION

C<bde_uorusersof.pl> searches the visible universe for unit of release that
are in the forward light cone (i.e. dependant upon and in need of rebuilding)
of a specified list of one or more unit of releases. The declared dependency 
information from the dependency files are used to find the answer.

=head2 Direct vs Indirect Clients

If the C<--indirect> or C<-i> option is used, indirect (e.g. transitive)
dependants will be taken into consideration as well as direct ones.

=head2 Ordered output

If the C<--order> or C<-o> option is userd, the output will be in a canonical
order that is suitable to build serially.

=head2 Pretty vs Machine output

It has two primary display modes, I<machine mode> and I<pretty mode>, which
are selected depending on whether the C<--machine> or C<-m> option is 
specified


=head1 NOTES

C<bde_uorusersof.pl> searches units of release only. To examime component-level
and file-level dependencies, see L<bde_usersof.pl>.

The external name of this tool is C<uorusersof>.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h |  [-d] [-v] [-w <dir>] [-i] [-o] [-m] <uor>

  --debug       | -d           enable debug reporting
  --help        | -h           usage information (this text)
  --verbose     | -v           enable verbose reporting
  --where       | -w <dir>     specify explicit alternate root

Query modes:

  --indirect    | -i           show all (including transitive) dependencies

Output options:

  --order       | -o           arrange output in dependency order

Display options:

  --pretty      | -p           list changes in human-parseable output
  --machine     | -m           list changes in machine-parseable output


See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        indirect|i
        debug|d+
        help|h
        machine|m
        pretty|p
        where|root|w|r=s
	order|o
        verbose|v+	
    ])) {
        usage();
        exit EXIT_FAILURE;
    }
   
    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    #no arguments
    usage, exit EXIT_FAILURE if @ARGV<1;

    # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	exit EXIT_FAILURE;
    }

    # filesystem root
    $opts{where} = STAGE_PRODUCTION_ROOT unless $opts{where};
	
    unless ($opts{pretty} or $opts{machine}) {
	if (-t STDIN) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    my $root=new BDE::FileSystem::MultiFinder($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    BDE::Util::DependencyCache::setFaultTolerant("Xp");

    my @uors;

    # validate arguments
    foreach my $argv (@ARGV) {
	foreach my $arg (split /[,\s+-]/,$argv) {
	    my $src = getCanonicalUOR($arg);
	    unless ($src) {
		error "$arg is not a library";
		next;
	    }
	    push @uors, $src;		
	}
    }
    unless (@uors) {
	error "No valid source libraries provided";
	exit EXIT_FAILURE;
    }

    
    #retrieve clients depend upon uors
    my @universe = $root->findUniverse();   
    
    foreach my $src (@uors) {       	
	my @clients;
	
	
	foreach my $unit (@universe) {	 
	    my @deps = ();
	    # retrieve dependants for each UOR in universe
	    if ($opts->{indirect}) {
		@deps = getAllGroupDependencies($unit);
	    } else {
		my $object = getCachedGroupOrIsolatedPackage($unit);
		if ($object) {
		    @deps = $object->getDependants();		
		}
	    }
	
	    #found a match and add the UOR to clients list
	    if (@deps && grep { $_ eq $src } @deps ) {		  
		push @clients, $unit;
	    }	    
	}
	

	if(@clients) {
	    if($opts->{indirect}){
		message "Listing All Units of Releases that depend upon $src:"	    	
		    if $opts->{pretty};
	    } else {
		message "Listing Units of Releases that directly depend upon $src:"	    	
		    if $opts->{pretty};
	    }

	    if($opts->{order}){
		my @order = getBuildOrder(@clients);
		print "@order\n";
	    } else {
		print "@clients\n";
	    }
	} else {
	    if($opts->{indirect}) {
		print "There is no library or unit of release (uor) directly or indirectly depend upon $src\n";
	    } else {
		print "There is no library or unit of release (uor) directly depend upon $src\n";
	    }
	}
    } 

    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Ellen Chen (qchen1@bloomberg.net)

=head1 SEE ALSO

L<bde_uordepends.pl>, L<bde_depends.pl>, L<bde_usersof.pl>, L<bde_graphgen.pl>, L<bde_buildorder.pl>

=cut

