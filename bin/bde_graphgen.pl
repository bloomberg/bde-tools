#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Component;
use BDE::FileSystem::MultiFinder;
use BDE::Util::DependencyCache qw(
    getCachedPackage getCachedGroup getCachedGroupOrIsolatedPackage
    getAllPackageDependencies getAllGroupDependencies
    getBuildOrder getBuildLevels
);
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent isGroupedPackage isApplication isFunction
    getComponentGroup getComponentPackage getPackageGroup isThirdParty
);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
    FILESYSTEM_NO_DEFAULT FILESYSTEM_NO_SEARCH
    FILESYSTEM_NO_LOCAL FILESYSTEM_NO_ROOT FILESYSTEM_NO_PATH
);
use Util::Message qw(alert fatal error verbose warning message debug);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

bde_graphgen.pl - Generate hierarchy graphs from dependency declarations

=head1 SYNOPSIS

    # search all locations
    $ bde_graphgen.pl bde            # package group
    $ bde_graphgen.pl l_foo          # grouped package
    $ bde_graphgen.pl a_bdema        # isolated package

    # display types
    $ bde_graphgen.pl -D a_bdema     # generate DOT graph
    $ bde_graphgen.pl -Y a_bdema     # generate level stack diagram
    $ bde_graphgen.pl -M a_bdema     # generate dependency map (default)

    # search selected locations
    $ bde_graphgen.pl -l bde         # search locally only (no root or path)
    $ bde_graphgen.pl -lr bde        # search locally and root (no path)
    $ bde_graphgen.pl -rp bde        # search root and path (not locally)
    $ bde_graphgen.pl -lrp bde       # search all locations

    # display selected dependencies
    $ bde_graphgen.pl -S l_foo       # show only strong dependencies of l_foo
    $ bde_graphgen.pl -W e_ipc       # show only weak dependencies of e_ipc
    $ bde_graphgen.pl -A m_bass      # show all dependncies of m_bass
    $ bde_graphgen.pl m_bass         # same as above (default)

    # generate DOT graph of all strong dependencies in universe
    $ bde_graphgen.pl -DUST

    # as above, but split heavily cyclic nodes into two
    $ bde_graphgen.pl -DUST -s acclib,apputil,trdutil

=head1 DESCRIPTION

C<bde_graphgen.pl> searches the local filing system, the local root, and the
current path to determine the 'closest' instance of the specified package
group, package, or component, as determined by the shape of the universe
(as determined by the configuration of the C<BDE_ROOT> and C<BDE_PATH>
environment variables, and the current working directory). It will then
generate an output file specifying the relationships between the specified
unit of release.

Any of the three search areas (local, root, and path) may be enabled separately
with the C<-l>, C<-r>, and C<-p> options. Specifying no areas is equivalent to
specifying all of them.

The specified group, package, or component must physically exist to be found.
Declared membership in the containing group (for grouped packages) or package
(for components) is not sufficient. If a component search is not necessarily
expected to succeed, the C<-X> option may be useful to cause the tool to return
faster; without this option, retry semantics will repeatedly check for the
component files within the closest associated package, which will cause a
delay if the files do not in fact exist.

=head1 DISPLAY MODES

C<bde_graphgen.pl> will generate three types output depending on the
use of the C<--dot>, C<--layer> or C<--map> (default) options.

=over 4

=item * C<--dot> will generate a DOT graph description that may be fed into
        a GraphViz client for rendering.

=item * C<--map> will display every identified unit of release along with
        its dependencies, in the form: C<uor: uor uor uor ...>.

=item * C<--layer> will display a layer stack diagram showing level numbers
        and all units of release at that level, in the form:
        C<level: uor uor uor ...>

=back

Note that the layer stack diagram will have non-sequential numbers if there are
strong cycles. (The level number is computed from strong dependencies only,
irrespective of the use of C<--strong> or C<--weak>.) All units of release are
considered for the level number so it is possible that listed entities will have
higher scores due to cycles with entities that are not listed in the report (because
they are not being shown).

Graph generation with the DOT mode is discussed in more detail below.

=head1 GRAPH GENERATION

A primary function of C<bde_graphgen.pl> is to generate output suitable for
graphical rendering, via GraphViz. To use the output of this tool to generate
GraphViz graphs, use the C<--dot> option. The output file is a DOT graph
description and can be rendered in various ways. Transative reduction must be 
performed if a graph of large size (e.g. a universe graph) is to be rendered
comprehensibly.

=head2 Generating a Universe Graph

To generate a universe graph, run a command similar to:

   bde_graphgen.pl -DUST > ~/universe.dot

This generates a DOT graph of all strong dependencies in the findable
universe and places it in your home directoy. The -T option means that
entities in the universe that are malformed will not cause the tool to abort.
Phantoms, functions, and applications are omitted unless explicitly requested.

=head2 Splitting Strongly-Connected Nodes

Some nodes in the graph have very many inbound and outbound edges. In order
to see other structure in the generate graph more easily it is sometimes
useful to split these nodes into 'inbound' and 'outbound' halves. Use the
C<--split> or C<-s> option to do this. For example:

   bde_graphgen.pl -DUST -s acclib,apputil,trdutil > splituniverse.dot

The resulting graph may have many fewer cycles present, as well as being
easier to read. This is of couse 'cheating' in the strict sense, but can
provide more useful input (at least for some analyses) to the transitive
reduction filter (below).

=head2 Transitive Reduction and Unflattening

Transitive reduction removes direct connections from the graph when the nodes
are indirectly connected, i.e. if a->b and b->c then the connection a->c can
be removed. This results in some loss of information, but greatly improved
legibility, especially for universe graphs.

To perform a transitive reduction, use the C<tred> tool from the GraphViz
toolset. The C<unflatten> tool can often clean up the output a little more:

   > tred universe.dot > tred.dot
   > unflatten tred.dot > unflat.dot

Both these commands work using the Windows installation of GraphViz; to
transfer the dot file to the desktop use the File Transfer feature of the
R&D toolkit and double-click on the file. (The above commands can be run
from a DOS shell after C<cd>ing into the Desktop subdirectory.)

I<Note: GraphViz is BOSS approved and can be installed on a desktop by filing
an ISHD ticket.>

=head2 Rendering the Graph

Finally, render the graph. The C<dotty> browser which comes with GraphViz will
do this if no more advanced browsers are readily to hand:

   > dotty unflat.dot

Dotty is a little awkward, but is very quick at rendering this diagram. Dotty
can also be used to remove nodes and/or edges and then redo the layout for the
purposes of experimentation.

=head1 NOTES

=over 4

=item * The universe mode is better tested than the specific units-of-release
        mode.

=item * For universe mode, C<--tolerant> or C<-T> is advised.

=back

=cut

#==============================================================================

sub usage (;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-A|-S|-W] [-E][-F] [-l][-p][-r][-T] [-w <dir>] [-X]
                         [-s lib[,lib...] <group|package|--universe>
  --debug         | -d        enable debug reporting
  --help          | -h        usage information (this text)
  --verbose       | -v        enable verbose reporting
  --noretry       | -X        disable retry semantics on file operations

Reporting options:

  --all           | -A        show all dependencies (default)
  --strong        | -S        show only strong dependencies
  --weak          | -W        show only weak dependencies
  --universe      | -U        show all units of release in searchable universe
  --[no]apps      | -E        show applications (universe mode, default: no)
  --[no]functions | -F        show functions (universe mode, default: no)
  --[no]orphans   | -O        show orphans (universe mode, default: no)
  --[no]phantoms  | -P        show phantoms (default: no)

Search options:

  --local         | -l        search local filesystem
  --path          | -p        search path
  --root          | -r        search local root
  --tolerant      | -T        ignore badly formatted packages and groups
  --where         | -w <dir>  specify explicit alternate root

Output options:

  --dot           | -D        generate a DOT graph description
  --map           | -M        generate a direct dependency mapping table
  --layer         | -Y        generate a level stack chart
  --order         | -o        arrange output in dependency order
                              (implied by --map, --layer, optional with --dot)
  --split         | -s <libs> (DOT only) bisect nodes into 'in' and 'out' nodes
  --group         | -g <regex> Regex to group nodes

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        all|A
        apps|applications|E!
        debug|d+
        dot|D
        functions|F!
        help|h
        layer|Y
        local|l
        map|M
        order|o
        orphans|O
        noretry|X
	path|p
        phantoms|P
        root|r
        split|s=s@
        strong|S
        tolerant|T
	universe|U
	verbose|v
        weak|W
	group|g=s@
        where|w=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE
      if @ARGV<1 and not $opts{universe};

    $opts{universe}=1,@ARGV=() if @ARGV and $ARGV[0] eq 'all';

    # filesystem root
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # strong/weak/all
    if ($opts{all}) {
	$opts{strong}=$opts{weak}=1;
    } else {
	$opts{all}=1 if $opts{strong} and $opts{weak};
        $opts{all}=1 unless $opts{strong} or $opts{weak}; #default
    }

    # map/dot
    $opts{map}||=0; $opts{dot}||=0; $opts{layer}||=0;
    if (($opts{map} + $opts{dot} + $opts{layer}) > 1) {
	usage "--map, --dot, and --layer are mutually exclusive";
	exit EXIT_FAILURE;
    } else {
	$opts{map}=1 unless $opts{dot} or $opts{layer};
    }

    # split
    if ($opts{split}) {
	if (not $opts{dot}) {
	    warning "--split has no effect without --dot";
	} else {
	    @{$opts{split}}=map { split /,/ } @{$opts{split}};
	}
    }

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

sub search_mode ($$$) {
    my $l = (shift) ? FILESYSTEM_NO_LOCAL : 0;
    my $r = (shift) ? FILESYSTEM_NO_ROOT  : 0;
    my $p = (shift) ? FILESYSTEM_NO_PATH  : 0;

    return 0 unless $l || $r || $p; # none=all
    return FILESYSTEM_NO_SEARCH ^ ($l | $r | $p);
}

sub display_mode ($$$) {
    my ($all,$strong,$weak)=@_;
    my $display_mode=undef;

    if ($all) {
        $display_mode="strong and weak";
    } elsif ($strong) {
	$display_mode="strong";
    } elsif ($weak) {
	$display_mode="weak";
    }

    return $display_mode;
}

# return a list of descriptive 'info' lines about the graph being generated
# embedded into output as well as listed on screen.
sub info_header ($$) {
    my ($opts,$split)=@_;

    my @lines;

    if ($opts->{universe}) {
	push @lines, "Universe dependency graph";
    } else {
	push @lines, "Dependency graph for @{[sort @ARGV]}";
    }
    push @lines, "Showing ".display_mode(
        $opts->{all},$opts->{strong},$opts->{weak}
    )." dependencies";
    push @lines, "Applications ".($opts->{apps} ?"included":"excluded");
    push @lines, "Functions ".($opts->{functions} ?"included":"excluded");
    push @lines, "Phantoms ".($opts->{phantoms} ?"included":"excluded");
    if (%$split) {
	push @lines, "Split nodes: @{[sort keys %$split]}";
    }

    return @lines;
}

#------------------------------------------------------------------------------

sub getUniverseDependencies ($$) {
    my ($opts,$root)=@_;

    # search the universe
    my %deps=map {$_ => $_} $root->findUniverse();

    # remove applications, unless we were asked to keep them
    unless ($opts->{apps}) {
	foreach my $dep (keys %deps) {
	    delete $deps{$dep} if isApplication($dep);
	}
    }

    # remove functions, unless we were asked to keep them
    unless ($opts->{functions}) {
	foreach my $dep (keys %deps) {
	    delete $deps{$dep} if isFunction($dep)
	      or ($dep eq "icpplib"); #special case, remove when icpplib
	                              #(made entirely of functions) goes
	}
    }

    # remove 'phantom' dependencies, unless we were asked to keep them
    unless ($opts->{phantoms}) {
	foreach my $dep (keys %deps) {
	    delete $deps{$dep} if $dep=~/^phantoms\b/;
	}
    }

    # retrieve metadata
    my $errors=0;
    foreach my $uor (keys %deps) {
	if (my $gop=getCachedGroupOrIsolatedPackage $uor) {
	    $deps{$uor}=$gop;
	} else {
	    delete $deps{$uor};
	    error "Failed to retrieve metadata for $uor";
	    $errors=1;
	}
    }

    return undef if $errors and not $opts->{tolerant};

    return \%deps;
}

sub getSpecifiedDependencies ($$@) {
    my ($opts,$root,@items)=@_;
    my %deps;

    # load all requested items plus all their declared dependencies
    foreach my $item (@items) {
	next if exists $deps{$item}; # dependency of something else

	# locate requested item, abort if it does not exist
	my $locn;
	if (isPackage $item) {
	    $locn= $root->getPackageLocation($item) ;
	} elsif (isGroup $item) {
	    $locn= $root->getGroupLocation($item) ;
	} else {
	    fatal "Not a group, package, or component: $item";
	}
	error("$item not found"),return(undef) unless $locn;
	
	# retrieve its metadata - abort if malformed (<<<TODO:tolerance)
	my $gop=(isPackage $item) ?
	  getCachedPackage($item):getCachedGroup($item);
	fatal "Not a package or package group: $item" unless $gop;

	$deps{$gop}=$gop;
	if (isGroupedPackage $gop) {
	    foreach my $pkgdep (getAllPackageDependencies $gop) {
		$deps{$pkgdep}=getCachedPackage($pkgdep);
		debug "Added ",ref($pkgdep)," for $pkgdep\n";
	    }
	} else {
	    foreach my $uordep (getAllGroupDependencies $item) {
		$deps{$uordep}=getCachedGroupOrIsolatedPackage($uordep);
		debug "Added ",ref($uordep)," for $uordep\n";
	    }
	}
    }

    return \%deps;
}

sub filterOrphans {
    my $depdeps=shift;

    my %mentions;
    foreach my $node (keys %$depdeps) {
	$mentions{$node}=0 unless exists $mentions{$node};
	foreach my $depdep (@{$depdeps->{$node}}) {
	    $mentions{$node}=1;
	    $mentions{$depdep}=1;
	}
    }

    my @orphans;
    foreach my $node (keys %mentions) {
	if (not $mentions{$node}) {
	    # if the mention value is zero, it's an unloved node
	    push @orphans,delete $depdeps->{$node};
	}
    }

    return @orphans;
}


#------------------------------------------------------------------------------

sub renderDot ($$$) {
    my ($opts,$depdeps,$split)=@_;

    print "digraph hierarchy {\n";
    print "    // Graph generated by ",basename($0),
      " on ",scalar(localtime)."\n";
    print map { "    // $_\n" } info_header($opts,$split);
    print "\n";
    print "    node [shape=box];\n";
    print "    page=\"11,17\";\n";
    print "    orientation=landscape;\n";
    print "    // concentrate=true;\n";   #does not seem to help much
    print "    // ordering=out;\n";       #does not seem to help much
    print "    // ratio=auto;\n";
    print "\n";

# Example stuff, commented out
#    $opts->{group} = [['gtk', '^gtk'],
#		      ['News', '^news/'],
#		     ];

    my ($graphgroup, %nodeprinted);
    foreach my $group (@{$opts->{group}}) {
      my $regex = $group;
      $graphgroup++;
      print " subgraph cluster_$graphgroup \{ color=black;\n";
      foreach my $node (keys %$depdeps) {
	if ($node =~ /$regex/) {
	  next if not $opts->{phantoms}  and $node=~/^phantoms\b/;
	  next if not $opts->{functions} and isFunction($node);
	  next if not $opts->{apps}      and isApplication($node);
	  my $dep=(isPackage $node)?getCachedPackage($node)
	    :getCachedGroup($node);
	  $node=$node."_out" if $split->{$node};

	  $node=~s/\W/__/g;
	  print "    $node \[";
	  if ($dep->isOfflineOnly) {
	    print "shape=ellipse,";
	  }
	  if ($dep->isGTKbuild && !isThirdParty($dep)) {
	    print "style=filled,color=lightgrey,";
	  } elsif (!$dep->isLegacy && !isThirdParty($dep)) {
	    print "style=filled,color=yellow,";
	  } elsif (isThirdParty($dep)) {
	    print "style=filled, color=red,";
	  }

	  print "label=\"$dep\"\];\n";
	  $nodeprinted{$node}++;

	}
      }
      print "}\n";
    }

    foreach my $node (keys %$depdeps) {
        next if not $opts->{phantoms}  and $node=~/^phantoms\b/;
	next if not $opts->{functions} and isFunction($node);
	next if not $opts->{apps}      and isApplication($node);
        my $dep=(isPackage $node)?getCachedPackage($node)
	                         :getCachedGroup($node);
        $node=$node."_out" if $split->{$node};

        $node=~s/\W/__/g;
	if (!exists $nodeprinted{$node}) {
	  print "    $node \[";
	  if ($dep->isOfflineOnly) {
	    print "shape=ellipse,";
	  }
	  if ($dep->isGTKbuild && !isThirdParty($dep)) {
	    print "style=filled,color=lightgrey,";
	  } elsif (!$dep->isLegacy && !isThirdParty($dep)) {
	    print "style=filled,color=yellow,";
	  } elsif (isThirdParty($dep)) {
	    print "style=filled, shape=octagon, color=lightblue2,";
	  }

	  print "label=\"$dep\"\];\n";
	}

	foreach my $depdep (@{$depdeps->{$dep}}) {
	    next unless $depdep; #failed to retrieve metadata, bad dep
	    next if not $opts->{phantoms}  and $depdep=~/^phantoms\b/;
	    next if not $opts->{functions} and isFunction($depdep);
	    next if not $opts->{apps}      and isApplication($depdep);
		
	    $depdep.="_in" if $split->{$depdep};
	    $depdep=~s/\W/__/g;
	    # this syntax makes it easy to comment out one edge
	    print "    $node -> $depdep;\n";
	}
    }

    print "}\n";
}

sub renderMap ($$$) {
    my ($opts,$depdeps,$split)=@_;

    print "# Graph generated by ",basename($0)," on ",scalar(localtime)."\n";
    print map { "# $_\n" } info_header($opts,$split);
    my @deps=keys %$depdeps;
    @deps=getBuildOrder(@deps);
    foreach my $dep (@deps) {
	print "$dep: ".join(' ',@{$depdeps->{$dep}})."\n";
    }
}

sub renderLayer ($$$) {
    my ($opts,$depdeps,$split)=@_;

    print "# Graph generated by ",basename($0)," on ",scalar(localtime)."\n";
    print map { "# $_\n" } info_header($opts,$split);
    my @deps=keys %$depdeps;
    @deps=getBuildOrder(@deps);
    my %level=getBuildLevels(@deps);

    my @stack;
    foreach my $uor (keys %level) {
	$stack[$level{$uor}] ||= [];
	push @{$stack[$level{$uor}]},$uor;
    }
    foreach my $lvl (0..$#stack) {
	next unless defined $stack[$lvl];
	printf "%3d: ".(join ' ',sort @{$stack[$lvl]})."\n", $lvl;
    }
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $root=new BDE::FileSystem::MultiFinder($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    BDE::Util::DependencyCache::setFaultTolerant($opts->{tolerant});

    my $mode=search_mode($opts->{local},$opts->{root},$opts->{path});
    $mode |= FILESYSTEM_NO_DEFAULT;
    $root->setSearchMode($mode);

    #--- Extract split arguments and check they are are valid

    my %split;
    if (defined $opts->{split}) {
	my $errors=0;
	foreach my $uor (@{$opts->{split}}) {
	    unless (my $gop=getCachedGroupOrIsolatedPackage $uor) {
		error "Failed to retrieve metadata for specified split: $uor";
		$errors=1;
	    }
	}
	if ($errors) {
	    error "Units of release specified for splitting were not found";
	    exit EXIT_FAILURE;
	}

	%split=map {$_ => 1} @{$opts->{split}};
	verbose "Splitting nodes:",(sort keys %split);
    }

    #--- Polite conversation

    if ($opts->{dot}) {
	alert "Generating DOT graph";
    } elsif ($opts->{map}) {
	alert "Generating dependency map";
    }
    message "- $_" foreach info_header($opts,\%split);

    #--- Get the list of all nodes that will be in the tree

    my $deps;
    if ($opts->{universe}) {
	$deps=getUniverseDependencies($opts,$root);
    } else {
	$deps=getSpecifiedDependencies($opts,$root,@ARGV);
    }
    error("Problem loading dependency information"),exit(EXIT_FAILURE)
      unless defined $deps;

    #--- Gather *direct* dependencies for every node in the tree ---

    my $depdeps={};
    foreach my $dep (values %$deps) {
	my @depdeps;

	if ($opts->{all}) {
	    @depdeps=$dep->getDependants();
	} elsif ($opts->{strong}) {
	    @depdeps=$dep->getStrongDependants();
	} elsif ($opts->{weak}) {
	    @depdeps=$dep->getWeakDependants();
        }

	my @depuors;
	foreach my $d (@depdeps) {
	    my $uor=(isPackage $d) ? getCachedPackage($d):getCachedGroup($d);
	    push @depuors,$uor;
	}

	$depdeps->{$dep}=\@depuors;
    }

    filterOrphans($depdeps) unless $opts->{orphans};

    #--- Rendered gathered dependency data ---

    if ($opts->{dot}) {
	renderDot($opts,$depdeps,\%split);
    } elsif ($opts->{map}) {
	renderMap($opts,$depdeps,\%split);
    } elsif ($opts->{layer}) {
	renderLayer($opts, $depdeps, \%split);
    } else {
	fatal "Unknown output mode"; #for future expansion...
    }

    alert "done";
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_depends.pl>, L<bde_usersof.pl>

=cut
