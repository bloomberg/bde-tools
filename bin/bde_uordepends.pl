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

use BDE::Util::DependencyCache qw(
    getAllGroupDependencies
    getCachedGroupOrIsolatedPackage
    getBuildOrder getBuildLevels
);
use BDE::Util::Nomenclature qw(
    getCanonicalUOR
);
use Change::Symbols qw(STAGE_PRODUCTION_ROOT);
use Util::Message qw(
    message verbose verbose2 alert verbose_alert
    warning error fatal debug debug2 debug3
);

use Util::Message qw(fatal message debug);
use Symbols qw(EXIT_FAILURE EXIT_SUCCESS);

#==============================================================================

=head1 NAME

bde_uordepends.pl - Display dependenies and check allowable dependencies

=head1 SYNOPSIS

    Display direct dependencies:
    $ bde_uordepends.pl f_xxmycs
    $ bde_uordepends.pl f_xxmycs l_cny

    Display direct and indirect dependencies
    $ bde_uordepends.pl -i f_xxmycs
    $ bde_uordepends.pl -i f_xxmycs l_cny

    Check if libraries depend *directly* on other libraries
    $ bde_uordepends.pl f_xxmycs -l gtkcore,bas,bde
    $ bde_uordepends.pl f_xxmycs l_cny -l gtkcore -l bas -l bde
    $ bde_uordepends.pl f_xxmycs,l_cny -l gtkcore,bas,bde #same as above

    Check if libraries depend directly or indirectly on other libraries
    $ bde_uordepends.pl -i f_xxmycs -l gtkcore -l bas -l bde
    $ bde_uordepends.pl -i f_xxmycs,l_cny -l gtkcore,bas,bde

    Get level number
    $ bde_uordepends.pl -i -n f_xxmycs
    $ bde_uordepends.pl -n f_xxmycs l_cny

=head1 DESCRIPTION

C<bde_uordepends.pl> checks dependancies for a specified list of
one or more source libraries. With only a list of source libraries it will
generate a list of their dependencies. With a list of target libraries, it
will test the dependencies between the set of source and set of target
libraries to determine if the combined dependency scenario is valid.

Note: C<uordepends> is the external name for this tool.

=head2 Testing Dependencies

With the C<--targetlib> or C<-l> option, the tool will test for dependencies
between the source libraries and a specified list of destination or target
libraries. Otherwise, it will list out the configured dependnecies for the
specified source libraries.

=head2 Direct vs Indirect Dependencies

If the C<--indirect> or C<-I> option is used, indirect (e.g. transitive)
dependencies will be taken into consideration -- with C<--targetlib/-l>,
indirect dependencies will be listed as well as direct ones. For untargeted
searches, the indirect dependencies the source libraries will be given in
addition to the direct ones.

=head2 Level

With the C<--level> or C<-n> options, level number of the uor will be print
out.

=head1 OUTPUT

In untargeted mode, strong dependencies are listed as-is, weak dependencies
are prefixed with 'weak:' and indirect dependencies (if requested) are
prefixed with 'indirect:'.

In pretty mode (the default when run interactively), dependencies are listed
one per line, with headers for the direct and indirect sections of the output.

  -- bde_uordepends.pl: Listing direct dependencies of l_foo:
  bde
  l_bar
  l_baz
  weak:a_foobar
  weak:acclib
  weak:apputil
  ...
  -- bde_uordepends.pl: Listing indirect dependencies of l_fxo:
  indirect:a_qux
  indirect:e_bazlib
  indirect:quxx
  ...

In machine mode (the default when run non-interactively), dependencies are
listed as a space-separated string, terminated by a line feed.

  bde l_bar l_baz weak:a_foobar weak:acclib weak:apputil indirect:a_qux
  indirect:e_bazlib indirect quxx

In targetted mode the output is the same for either mode, depending on the
result. If not searching indirect dependencies:

=over 4

=item foo directly depends on bar

=item foo does not directly (but may indirectly) depend on bar

=back

If searching indirect dependencies also:

=over 4

=item foo directly depends on bar

=item foo indirectly depends on bar

=item foo does not depend on bar

=back

=head1 NOTES

=over 4

=item * C<bde_uordepends.pl> searches units of release only. To examime
        component- and file-level dependencies, see L<bde_depends.pl>.

=item * To prevent searching local roots, set C<BDE_PATH=nonsuch> and either
        use C<-w nonsuch> or set C<BDE_ROOT=nonsuch>.

=back

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h |  [-d] [-v] <source libs> [-l <libs>]

  --debug        | -d           enable debug reporting
  --help         | -h           usage information (this text)
  --verbose      | -v           enable verbose reporting
  --where        | -w <dir>     specify explicit alternate root

Query modes:

  --target[libs] | -l <libs>    check if source lib depends on comma-separated
                               target libraries (may specify more than once)
  --indirect     | -i           show all (including transitive) dependencies
  --level        | -n           ouotput libraries with level number


Display options:

  --pretty       | -P           list changes in human-parseable output
  --machine      | -M           list changes in machine-parseable output

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
        machine|M
        pretty|P
        where|root|w|r=s
	level|levels|n
        verbose|v+
	targetlib|targetlibs|target|l=s@
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

    if ($opts{level} and $opts{target}) {
	usage("--level and --target are mutually exclusive");
	exit EXIT_FAILURE;
    }

    # filesystem root
    $opts{where} = STAGE_PRODUCTION_ROOT unless $opts{where};

    # process multivalue options
    foreach my $listarg (qw[targetlib]) {
	if (my $listval=$opts{$listarg}) {
	    my @actualargs=();
	    foreach my $val (@$listval) {
		push @actualargs, (split /[,\s+-]/,$val);		
	    }

	    $opts{$listarg}=join " ",@actualargs;
	}
    }
	
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

    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);

    my (%srcmap, %targetmap);

    # validate source libraries
    foreach my $argv (@ARGV) {
	foreach my $arg (split /[,\s+-]/,$argv) {
	    my $srclib = getCanonicalUOR($arg);
	    unless ($srclib) {
		error "$arg is not a library";
		next;
	    }
	    $srcmap{$srclib} =1;		
	}
    }
    unless (%srcmap) {
	error "No valid source libraries provided";
	exit EXIT_FAILURE;
    }

    # validate target libararies
    if ($opts->{targetlib}) {
	my @tmptargets = map {split / /,$_} $opts->{targetlib};
	debug "Target lib are @tmptargets\n";

	foreach my $tmptarget (@tmptargets) {
	    my $tarlib = getCanonicalUOR($tmptarget);
	    unless($tarlib) {
		error "$tmptarget is not a library";
		next;
	    }	
	    $targetmap{$tarlib} =1;
	}

	if (scalar(keys %targetmap) == 0) {
	    error "No valid destination libraries provided";
	    exit EXIT_FAILURE;
	}
    }

    # retrieving dependencies
    foreach my $srclib (keys %srcmap) {		
	my (%indirect, %direct, %level);
	
	my $object = getCachedGroupOrIsolatedPackage($srclib);

	%direct = map {$_=>$srclib} $object->getDependants();

	if ($opts->{indirect}) {
	    %indirect = map {$_ => $srclib} getAllGroupDependencies($object);
	    if($opts->{level}) {
		my @order = getBuildOrder(keys %indirect);
		push @order, $srclib;
		%level = getBuildLevels(@order);
	    }
	} else {
	    if($opts->{level}) {
		my @order = getBuildOrder(keys %direct);
		push @order, $srclib;
		%level = getBuildLevels(@order);
	    }
	}	
	
	if (exists $opts->{targetlib}) {
	    foreach my $tarlib (sort keys %targetmap) {		
		if (defined $tarlib) {
		    if ($tarlib eq $srclib) {
			warning "skipping test of $srclib against itself";
		    } elsif (exists $direct{$tarlib}) {
			print "$srclib directly depends on $tarlib\n";
		    } elsif (%indirect and exists $indirect{$tarlib}) {
			print "$srclib indirectly depends on $tarlib\n";
		    } else {
			print "$srclib does not ".
			  ($opts->{indirect} ? ""
			   : "directly (but may indirectly) ")
			  ."depend on $tarlib \n";
		    }
		}
	    }
	} else { #show dependency list only if user does not provide target
	    if ($opts->{pretty}) {
		if ($opts->{level}) {
		    message "Listing direct dependencies of $srclib (level $level{$srclib}):";
		} else {
		    message "Listing direct dependencies of $srclib :";
		}
		
	    } 
	   	  
	    if($opts->{level}) {
		if($opts->{pretty}) {
		    my @order= sort {$level{$a}<=> $level{$b} or $a cmp $b } keys %direct;
		    print join("\n",  map {
			($object->isWeakDependant($_) ? "weak:" : "").$_.
			' (level '.$level{$_}.')'} @order);
		} else {
		    print join(" ", sort map {
			($object->isWeakDependant($_) ? "weak:" : "").$_.
			    ': '.$level{$_} } keys %direct);
		}
	    } else { 
		print join(($opts->{pretty} ? "\n" : " "), sort map {
		    ($object->isWeakDependant($_) ? "weak:" : "").$_
		    } keys %direct);
	    }

	    my @indirect;
	    if ($opts->{indirect}) {
		print ($opts->{pretty} ? "\n" : " ");

		foreach my $lib (keys %indirect) {
		    if( !exists $direct{$lib}) {
			push @indirect, $lib;
		    }
		}

		message "Listing indirect dependencies of $srclib:"
		  if $opts->{pretty};

		if($opts->{level}) {
		    if($opts->{pretty}) {
			my @order = sort {$level{$a}<=> $level{$b} or $a cmp $b } @indirect;
			print join("\n",  map {
			    "indirect:$_".' (level '.$level{$_}.')'
			} @order);
		    } else {
			print join(" ", sort map {
			    "indirect:$_".': '.$level{$_}
			} @indirect);
		    }
		} else { 
		    print join(($opts->{pretty} ? "\n" : " "), sort map {
			"indirect:$_"
			} @indirect);
		}
	    }

	    print "\n";
	}
    }

    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Ellen Chen (qchen1@bloomberg.net)

=head1 SEE ALSO

L<bde_uorusersof.pl>, L<bde_depends.pl>, L<bde_usersof.pl>,
L<bde_graphgen.pl>, L<bde_buildorder.pl>

=cut


