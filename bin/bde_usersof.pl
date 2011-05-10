#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Component;
use BDE::Util::DependencyCache qw(
    getCachedComponent getCachedPackage getCachedGroup
    getAllInternalPackageDependencies
    getAllGroupDependencies

    getAllComponentFileDependencies
    getAllComponentDependencies
    getAllExternalComponentDependencies
    getAllInternalComponentDependencies
);
use BDE::FileSystem::MultiFinder;
use BDE::Build::Invocation qw($FS);
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent isValidDependency
    getComponentGroup getComponentPackage getPackageGroup
);
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT);
use Util::Message qw(fatal debug);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 SYNOPSIS

    # list dependant components of component
    $ bde_usersof.pl bael_loggermanager

    # list dependant units of release of package or group
    $ bde_usersof.pl l_foo     # group
    $ bde_usersof.pl a_bdema   # isolated package
    $ bde_whatdeoendson.pl l_foobar  # grouped package

    # print out dependency information in a prettier format
    $ bde_usersof.pl -p btesos

    # just internal dependencies (only relevant for package groups)
    $ bde_usersof.pl -p -i bdema

    # tolerate invalid package and groups, no retry semantics
    $ bde_usersof.pl -TXp bdema

=head1 DESCRIPTION

C<bde_usersof.pl> searches the visible universe for groups, packages, or
components that are in the forward light cone (i.e. dependant upon and in need
of rebuilding) of the group, package, or component specified.

=head2 Package and Group Searches

If a package or group argument is supplied then declared dependency information
from the membership and dependency files only is used to provide an answer. If
a grouped package is supplied, internal package dependencies within the group
can also be extracted.

=head2 Component Searches

If a component argument is supplied, the source of all potentially dependant
components is analysed to establish whether or not they are actually dependant.
This takes a lot longer than package- or group-level dependency calculations.

=head2 Intra-unit Searches

If the C<-i> or C<--internal> option is used, external dependencies are not
analysed and only components or packages (depending on the argument supplied)
are returned. This is much faster since the universe need not be searched.

=head2 Pretty vs Machine output

If the C<-p> or C<--pretty> option is used, more helpful output is returned
for more digestible human consumption. Otherwise, the list of dependant
units and/or internal packages is returned for a package or group search and
the list of externally and internally dependant components is returned for
a component search.

=head2 Fault Tolerant Searches

Because C<bde_usersof.pl> searches outwards into the universe, it cannot
know in advance whether or not the groups and packages it finds are well-formed
and have correctly declared dependencies.

Ordinarily, an invalid group or package, or a package or component that exceeds
its declared dependencies, will cause a fatal error, but C<bde_usersof.pl> can
be told to instead ignore invalid groups and packages with the C<--tolerant>
or C<-T> option (although it will still complain about them).

Since one of the most common reasons for an invalid group or package is a
missing file, it is usually advisable to combine C<-T> with the C<--noretry>
or C<-X> option, to prevent the tool repeatedly trying to read missing files
(the default behaviour, to handle transient filesystem errors). Using C<-X>
may significantly reduce the time taken to return a result in these cases.
See the last example in the synopsis.

=head1 TO DO

This is a first-pass implementation. A future release is expected to provide
additional ouput options to allow the machine-parsable output to be used
directly in makefiles and other build tools.

=cut

#==============================================================================

sub usage (;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-i] [-w <dir>] [-X] <group|package|component>
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --internal   | -i           report only internal dependencies
                              (relevant to package groups only)
  --external   | -x           report only external dependencies
  --pretty     | -p           generate human-readable dependency information
  --tolerant   | -T           ignore badly formatted packages and groups
  --verbose    | -v           enable verbose reporting
  --where      | -w <dir>     specify explicit alternate root
  --noretry    | -X           disable retry semantics on file operations

_USAGE_END
}

#  --macros     | -m           generate output using makefile macros rather
#                              than explicit paths

#------------------------------------------------------------------------------

{ my $pretty=0;

  sub set_pretty ($) { $pretty=$_[0] }
  sub pretty { print "@_\n" if $pretty }
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h 
        internal|i
        external|x
        noretry|X
        pretty|p
        tolerant|T
	verbose|v
        where|root|w|r=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV != 1;

    # filesystem root
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # 'pretty' mode
    set_pretty($opts{pretty} || 0);

    # internal/external
    unless (exists($opts{internal}) or exists ($opts{external})) {
	$opts{internal} = $opts{external} = 1;
    }

    return \%opts;
}

#------------------------------------------------------------------------------

# for units bigger than a component, return a list of the components within.
sub getComponentsOf ($) {
    my $item=shift;

    my @components=();

    if (isGroup($item)) {
	foreach my $pkg (getCachedGroup($item)->getMembers()) {
	    push @components,getCachedPackage($pkg)->getMembers();
	}
    } elsif (isPackage($item)) {
	push @components,getCachedPackage($item)->getMembers();
    } elsif (isComponent($item)) {
	push @components,$item;
    }

    return wantarray ? @components : \@components;
}

#------------------------------------------------------------------------------

# determine size and direction of light cone
sub findDependableUniverse ($$;@) {
    my ($root,$name,@universe)=@_;
    unless ($#_ > 1) {
	@universe=$root->findUniverse();
    }

    @universe = grep { isValidDependency($_ => $name) } @universe;

    return wantarray ? @universe : \@universe;
}

sub findInternalUnitDependencies ($) {
    my $unit=shift;
    my $group=getPackageGroup($unit) || $unit;
    my @intdeps;

    my @members=getCachedGroup($group)->getMembers();
    foreach my $member (@members) {
	my @deps=getAllInternalPackageDependencies($member);
	if (grep { $_ eq $unit } @deps) {
	    push @intdeps,$member;
	}
    }

    return wantarray ? @intdeps : \@intdeps;
}

sub findExternalUnitDependencies ($@) {
    my ($gop,@universe)=@_;
    my @extdeps;

    foreach my $unit (@universe) {
        my @deps = getAllGroupDependencies($unit); # group or isol. pkg. ok
	debug "$unit deps=[@deps]\n";
        if (grep { $_ eq $gop } @deps) {
	    push @extdeps,$unit;
        }
    }

    return wantarray ? @extdeps : \@extdeps;
}

sub findInternalComponentDependencies ($@) {
    my ($component,@intpdeps)=@_;
    my @intcdeps;
    unless ($#_ > 0) {
	@intpdeps=findInternalUnitDependencies(getComponentPackage $component);
    }

    foreach my $pdep (@intpdeps) {
	my @comps=getCachedPackage($pdep)->getMembers();
	foreach my $comp (@comps) {
	    my @incs=getAllComponentDependencies($comp);
	    push @intcdeps,$comp if grep { $_ eq $component } @incs;
	}
    }

    return wantarray ? @intcdeps : \@intcdeps;
}

sub findExternalComponentDependencies ($@) {
    my ($component,@extpdeps)=@_;
    my @extcdeps;
    unless ($#_ > 0) {
	return wantarray ? () : undef;
	#@extpdeps=findDependableUniverse($component);
    }

    foreach my $unit (@extpdeps) {
	my @comps=getComponentsOf($unit);
	foreach my $comp (@comps) {
	    my @incs=getAllComponentDependencies($comp);
	    push @extcdeps,$comp if grep { $_ eq $component } @incs;
	}
    }

    return wantarray ? @extcdeps : \@extcdeps;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $root=new BDE::FileSystem::MultiFinder($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root); #for components
    BDE::Util::DependencyCache::setFaultTolerant($opts->{tolerant});

    my $name=$ARGV[0];
    my ($group,$package,$unit,$comp);
    if (isComponent $name) {
        $comp=$name;
        $package=getComponentPackage($name);
        $group=getComponentGroup($name);  #may be undef
        $unit = $group || $package;
    } elsif (isPackage $name) {
        $package=$name;
        $group=getPackageGroup($package); #may be undef
        $unit = $group || $package;
    } elsif (isGroup $name) {
        $group=$name;
        $unit = $group;
    } else {
        fatal "Not a unit of release: $name";
    }

    my (@universe,@intpdeps,@extudeps,@intcdeps,@extcdeps);

    if ($opts->{external}) {
	@universe=findDependableUniverse($root,$name);
	pretty "Dependable universe: @universe";
    }

    if ($opts->{internal} and $package and $group) {
	# a component or package in a package group
	@intpdeps=findInternalUnitDependencies($package);
	if (@intpdeps) {
	    pretty "Internal packages that depend on $package: @intpdeps";
	} else {
	    pretty "No internal packages depend on $package";
	}
    }

    if ($opts->{external}) {
	@extudeps=findExternalUnitDependencies($unit => @universe);
	if (@extudeps) {
	    pretty "External units that depends on $unit: @extudeps";
	} else {
	    pretty "No external units depend on $unit";
	}
    }

    unless ($comp) {
	my @udeps=(@intpdeps,@extudeps);
	print "@udeps";
    }

    if ($comp) {
	if ($opts->{internal}) {
	    @intcdeps=findInternalComponentDependencies($comp => $package,
                                                                 @intpdeps);
	    if (@intcdeps) {
		pretty "Internal components that depend on $comp: @intcdeps";
	    } else {
		pretty "No internal components depend on $comp";
	    }
	}

	if ($opts->{external}) {
	    @extcdeps=findExternalComponentDependencies($comp => @extudeps);
	    if (@extcdeps) {
		pretty "External component dependants of $comp: @extcdeps";
	    } else {
		pretty "No external components depend on $package";
	    }
	}

	unless ($opts->{pretty}) {
	    my @comps=(@intcdeps,@extcdeps);
	    print "@comps\n";
	}
    }

    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_depends.pl>, L<bde_build.pl>

=cut
