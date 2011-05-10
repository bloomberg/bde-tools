# Utility routines that're DB independent and factored out to make
# rejigging the code easier for either a new database or new database
# schema.
package Binary::Analysis;
use Graph;
use Change::Symbols qw(COMPCHECK_DIR GMAKE RCS_CO BREAKFTNX);
use BDE::Build::Invocation qw($FS);

# From parent, kinda icky
our (@pathlist);

#
# Parse a makefile and return a list of things from it that we need to
# link against.
#
sub parseMakefileForStuff {
  my ($self, $makefile) = @_;
  my ($cmd);
  ##<<TODO: should really do gmake -p and parse database once; see bde_metalink.pl
  $self->debug("Looking for makefile $makefile\n");
  # This env variable quiets the plink whines about missing main things
  local $ENV{PLINK_CHECK_LINKER_MAIN} = 0;
  if (-e $makefile) {
    $cmd = GMAKE." -f $makefile";
  } elsif (-e "$makefile,v") {
    $self->debug("Looking at the ,v\n");
    $cmd = RCS_CO." -q -p $makefile,v | ".GMAKE." -f -";
  }
  $cmd .= " -f /bbsrc/tools/data/ap-extra.mk";
  my $linker = `$cmd var-xp-LD`;
  $self->debug("linker is $linker\n");
  my $linkargs = `$cmd var-xp-LINKARGS`;
  $self->debug("linkargs is $linkargs\n");
  my $user_ldflags = `$cmd var-xp-USER_LDFLAGS`;
  $self->debug("user_ldflags is $user_ldflags\n");
  my $aligns = `$cmd var-xp-ALIGNS`;
  $self->debug("aligns is $aligns\n");
  my $specialobjs = `$cmd var-xp-ARCHSPECIALOBJS`;
  my $sharedlibs = `$cmd var-xp-LINKSHLIBS`;
  my $libs_pre = `$cmd var-xp-LIBS_PRE`;
  my $plink_libpath = `$cmd var-xp-PLINK_LIBPATH`;
  my $libs = `$cmd var-xp-LIBS`;
  my $objs = `$cmd var-xp-ARCHOBJS`;
  my $tasklocation = `$cmd var-xp-REFERENCE_TASK`;
  chomp($linker, $linkargs, $user_ldflags, $aligns, $specialobjs, $sharedlibs,
        $libs_pre, $plink_libpath, $objs, $libs, $tasklocation);
  $self->debug("Linker is >$linker<\n");
  my ($platform_objs, $platform_libs);
  if ($^O eq 'solaris') {
    if ($linker =~ /CC/) {
      $platform_objs = '/bb/util/common/studio8-v3/SUNWspro/prod/lib/crti.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/CCrti.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/crt1.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/values-xa.o';
      $platform_libs = '-lCstd -lCrun -lm -lw -lc /bb/util/common/studio8-v3/SUNWspro/prod/lib/CCrtn.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/crtn.o';
    }
    if ($linker =~ /cc/) {
      $platform_objs = ' /bb/util/common/studio8-v3/SUNWspro/prod/lib/crti.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/crt1.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/values-xa.o  ';
      $platform_libs = ' -lc /bb/util/common/studio8-v3/SUNWspro/prod/lib/crtn.o ';
    }
    if ($linker =~ /f90/) {
      $platform_objs = '/bb/util/common/studio8-v3/SUNWspro/prod/lib/crti.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/crt1.o /bb/util/common/studio8-v3/SUNWspro/prod/lib/values-xi.o ';
      $platform_libs = '  -lfui -lfai -lfai2 -lfsumai -lfprodai -lfminlai -lfmaxlai -lfminvai -lfmaxvai -lfsu -zallextract -lompstubs -zdefaultextract -lsunmath -lm -lc /bb/util/common/studio8-v3/SUNWspro/prod/lib/crtn.o';
    }
  }

  my (@things);
  foreach my $thing ($linkargs, $user_ldflags, $platform_objs, $aligns, $specialobjs, $objs, $sharedlibs, $libs_pre, $plink_libpath, $libs, $platform_libs) {
    next unless $thing;
    $thing =~ s/^\s+//;
    $thing =~ s/\s+$//;
    $thing =~ s/-l//g;
    next unless $thing;
    push @things, split(/\s+/, $thing);
  }
  $self->debug("things are ", join("|", @things), "\n");
  return {linkitems => \@things,
	  taskloc => $tasklocation,
	  }
}

=item @objectfiles = $handle->sourceToObject($source)

Takes a source filename with an optional package qualifier and returns
the .o file or files that it creates.

For C and C++ code it just transforms the extension. For Fortran
programs it runs breakftnx and gets the results

This code probably ought to live in another library, not here.

=cut
sub sourceToObject {
  my ($self, @source) = @_;
  my @results;
  
  foreach my $file (@source) {
    my ($package, $filename);
    if ($file =~ /:/) {
      ($package, $filename) = split(':', $file, 2);
    } else {
      $filename = $file;
    }

    if ($filename =~ /\.c$/ || $filename =~ /\.c(pp|\+\+)/) {
      $filename =~ s/\.c(pp|\+\+)?/.o/;
      if ($package) {
	push @results, $package.":".$filename;
      } else {
	push @results, $filename;
      }
    } elsif  ($filename =~ /\.gob$/) {
      $filename =~ s/\.gob$/.o/;
      if ($package) {
	push @results, $package.":".$filename;
      } else {
	push @results, $filename;
      }
    } elsif ($filename =~ /\.f$/i) {
      my (@filenames);
      my ($directory, $basefilename);
      if ($package) {
	if (isGroup($package)) {
	  $directory = $self->{root}->getGroupLocation($package);
	} else {
	  $directory = $self->{root}->getPackageLocation($package);
	}
	$directory =~ s|/$||;
	$basefilename = $directory . '/' . $filename . ',v';
      } else {
	print "Error processing file $file: Fortran files must have a package or group attached to them\n";
	next;
      }
      if (!-e $basefilename) {
	print "basefilename $basefilename for $file not found\n";
	$basefilename =~ s/,v$//;
      }
      @filenames = `${\RCS_CO} -q -p $basefilename | ${\BREAKFTNX} -breakftnxlistobjs -stdin`;
      chomp @filenames;
      foreach my $oname (@filenames) {
	if ($package) {
	  $self->debug("Adding $package:$oname.o\n");
	  push @results, $package . ':' . $oname . '.o';
	} else {
	  $self->debug("Adding $oname.o\n");
	  push @results, $oname . '.o';
	}
      }
    } elsif ($filename =~ /\.o$/) {
      if ($package) {
	push @results, $package.":".$filename;
      } else {
	push @results, $filename;
      }
    } else {
      print "Don't know how to find the object file for $filename\n";
    }
  }
  return @results;
}


#
# Return the date on the .opt file. We assme that if there's no dep
# file that there's no opt file, which makes a certain amount of sense.
sub getOptDate {
  my ($self, $package) = @_;
  my $opt_date = -1;
  my $filename;
  eval {
    if (isGroup($package)) {
      $filename = $self->{root}->getGroupDepFilename($package);
    } else {
      $filename = $self->{root}->getPackageDepFilename($package);
    }
    $filename =~ s/\.dep/.opts/;
    $opt_date = (stat $filename)[9];
  };
  return $opt_date;
}

sub getPackageDate {
  my ($self, $package) = @_;
  my ($memdate, $depdate) = (-1, -1);
  eval {
    my $memfile = $self->{root}->getPackageMemFilename($package);
    $memdate = (stat $memfile)[9];
  };
  eval {
    my $depfile = $self->{root}->getPackageDepFilename($package);
    $depdate = (stat $depfile)[9];
  };
  return($memdate > $depdate ? $memdate : $depdate);
}

sub getGroupDate {
  my ($self, $group) = @_;
  my ($memdate, $depdate) = (-1, -1);
  eval {
    my $memfile = $self->{root}->getGroupMemFilename($group);
    $memdate = (stat $memfile)[9];
  };
  eval {
    my $depfile = $self->{root}->getGroupDepFilename($group);
    $depdate = (stat $depfile)[9];
  };
  return($memdate > $depdate ? $memdate : $depdate);
}


=item %levels = allLevels()

Scans the whole level hierarchy and returns a list of key/value pairs
where the key is the UOR and the value is the level in the hierarchy.

=cut

sub allLevels {
  my ($self) = @_;
  my ($levels) = $self->annotatedLevels();
  return %$levels;
}

=item @graphs = $handle->getCycles()



=cut

sub getCycles {
  my ($self, $graph) = @_;
  my ($cycles, @cycles);
  my $subgraph;
  if (!defined $graph) {
    (undef, $cycles) = $self->annotatedLevels();
    $graph = $self->getGraph();
  } else {
    (undef, $cycles) = $self->annotatedLevels($graph);
  }
  @cycles = @$cycles;
  my @cycle_graphs;
  foreach my $cycle (@cycles) {
    my $new_graph = $graph->copy;
    my %vertices;
    @vertices{@$cycle} = ();
    foreach my $vertex ($new_graph->vertices) {
      $new_graph->delete_vertex($vertex) unless exists $vertices{$vertex};
    }
    push @cycle_graphs, $new_graph;
  }
  return @cycle_graphs;
}


=item (\%levels, \@cycles) = $handle->annotatedLevels

Do a scan of the hierarchy and return a set of results for it. Returns
a reference to a hash with the units of release and their levels, and
a reference to an array of cycles.

=cut

sub annotatedLevels {
  my ($self, $graph) = @_;
#  my @allUOR = $self->allUOR;

  my @returngroups;

  # First we build up a directed graph
  my $base_graph;
  if ($graph) {
    $base_graph = $graph->copy();
  } else {
    $base_graph = $self->getGraph
  }
  my (%levels, @successorless, $current_level);

  $self->debug("assigning bottom levels (".time.")\n");
  # First find all the UORs with no children. Those are level 0.
  @successorless = $base_graph->successorless_vertices;

  local $| = 1;
  # Clean up the dangling bits at the end of the tree. These are
  # reasonably easy -- we just trim and assign levels
  while (@successorless) {
    $current_level++;
    foreach my $vertex (@successorless) {
      $levels{$vertex} = $current_level;
    }
    $base_graph->delete_vertices(@successorless);
    # Get the new successorless vertices
    @successorless = $base_graph->successorless_vertices;
  }

  $self->debug("trimming top levels (".time.")\n");
  # Go clean up the top bits. We can't assign levels, but we can get
  # them out of the way so they don't participate in the strong
  # component check.
  my (@topnodes, @cleanupnodes);
  @topnodes = $base_graph->predecessorless_vertices;
   @cleanupnodes = @topnodes;
   while(@cleanupnodes) {
     $base_graph->delete_vertices(@cleanupnodes);
     @cleanupnodes = $base_graph->predecessorless_vertices;
     push @topnodes, @cleanupnodes;
   }

  $self->debug("getting strongly connected components (".time.")\n");
  my @strongs = $base_graph->strongly_connected_components;
  my @groups = grep {@$_ > 1} @strongs;

  $self->debug("assigning group levels (".time.")\n");
  my %childhash;
  while (@strongs) {
    my @pending_strongs;
    @strongs = sort {@$b <=> @$a } @strongs;
    foreach my $strong (@strongs) {
      my $highest_level = 0;
      my $levels_OK = 1;
      my %grouphash;
      @grouphash{@$strong} = ();
      foreach my $element (@$strong) {
#	print "looking at $element\n";
	if (!exists $childhash{$element}) {
	  $childhash{$element} = [$self->findChildren($element)];
	}
	foreach my $dep (@{$childhash{$element}}) {
	  if (defined $levels{$dep}) {
	    $highest_level = $levels{$dep} if $levels{$dep} > $highest_level;
	  } else {
	    if (!exists $grouphash{$dep}) {
	      $levels_OK = 0;
	    }
	  }
	}
      }
      if ($levels_OK) {
	my $level = $highest_level + @$strong;
#	$level++ if @$strong > 1;
	foreach my $element (@$strong) {
	  $levels{$element} = $level;
	}
      } else {
	push @pending_strongs, $strong;
      }
    }
    @strongs = @pending_strongs;
  }

  $self->debug("assigning top levels (".time.")\n");
  # Now run through the elements from the top of the tree, only in
  # reverse order. That makes it more likely that we'll actually not
  # have to make a second pass through.
  while (@topnodes) {
    my @pendingnodes;
    foreach my $element (reverse @topnodes) {
      my $highest_level = 0;
      my $levels_OK = 1;
      if (!exists $childhash{$element}) {
	$childhash{$element} = [$self->findChildren($element)];
      }
      foreach my $dep (@{$childhash{$element}}) {
	if (defined $levels{$dep}) {
	  $highest_level = $levels{$dep} if $levels{$dep} > $highest_level;
	} else {
	  if (!exists $levels{$dep} || !defined $levels{$dep}) {
	    $levels_OK = 0;
	  }
	}
      }
      if ($levels_OK) {
	$levels{$element} = $highest_level+1;
      } else {
	push @pendingnodes, $element;
      }
    }
    @topnodes = @pendingnodes;
  }
  $self->debug("levels done (".time.")\n");

  return(\%levels, \@groups);

}

=item $level = getLevel($uor)

Returns the level in the hierarchy of the passed-in unit of
release. If the level is indeterminate (because, for example, of
cycles in the hierarchy) it will return -1.

=cut

sub getLevel {
  my ($self, $uor) = @_;
  my %levels = $self->allLevels;
  if (exists $levels{$uor}) {
    return $levels{$uor};
  } else {
    return -1;
  }
}

=item refreshUOR([@uor])

Takes a list of units of release and refreshes the cache for them,
assuming your cache mode allows this. If no list is passed in then all
the units in the database will be refreshed.

This method takes all the passed-in units and refreshes them, then
takes all the immediate dependencies of those units and refreshes
them, and so forth until there are no units left to refresh. Circular
dependencies are properly handled so a unit won't get refreshed more
than once.

Note that since this works off the data initially in the database, a
refreshUOR call on an empty database will not have any effect.

Also note that this call will commit its changes after each UOR has
been processed, so care should be used if this method is used in
anything other than a generic database refreshing program.

=cut
sub refreshUOR {
  my ($self, @toscan) = @_;
  # If we got nothing, then go for everything in the DB and everything
  # in the universe except for applications
  if (!@toscan) {
    @toscan = sort($self->allUOR(), $self->{root}->findUniverse());
  }

  my (@nextUOR, %seenUOR);
  while (@toscan) {
    undef @nextUOR;
    foreach my $uor (@toscan) {
      next if exists $seenUOR{$uor};
      my $found = 0;
      # Should we nuke the thing?
      if (isGroup($uor)) {
	$found++;
	my $group;
	eval {$group = getCachedGroup($uor);};
	if ($@ || !defined $group) {
	  $self->debug("Deleting group $uor\n");
	  $self->deleteGroup($uor);
	  next;
	}
      }
      if (isPackage($uor) || isIsolatedPackage($uor)) {
	$found++;
	my $package;
	eval {$package = getCachedPackage($uor);};
	if ($@ || !defined $package) {
	  $self->debug("Deleting package $uor\n");
	  $self->deletePackage($uor);
	  next;
	}
      }

      if (isApplication($uor)) {
	$found++;
	my $app;
	eval {$package = getCachedGroupOrIsolatedPackage($uor);};
	if ($@ || !defined $package) {
	  $self->debug("Deleting offline $uor\n");
	  $self->deleteOffline($uor);
	  next;
	}
      }

      if (!$found) {
	$self->debug("Deleting $uor\n");
	my $rows = $self->{dbh}->selectall_arrayref("select * from packages where packagename = ?", undef, $uor);	
	if (@$rows) {
	  $self->debug("Deleting package $uor\n");
	  $self->deletePackage($uor);
	} else {
	  $self->debug("Deleting group $uor\n");
	  $self->deleteGroup($uor);
	}
      } else {
	eval {
	  $self->addThing($uor);
	  $seenUOR{$uor}++;
	  $self->commit() if $self->{commit_piecemeal};
	};
	if ($@) {
	  $self->debug("Got an error $@\n");
	  #	$self->rollback;
	}
      }
    }
    @toscan = @nextUOR;
  }
#  $self->commit();
}

sub _getArchiveChecksum {
  my ($self, $filename) = @_;
  if (defined $self->{archive_checksum}{$filename}) {
    return $self->{archive_checksum}{$filename};
  }

  my $cksum = `cksum $filename`;
  chomp $cksum;
  $cksum =~ /^\s*(\d+)/;
  $cksum = $1;
  $self->{archive_checksum}{$filename} = $cksum;
  return $cksum;
}

# Get the date for an object file
sub _getArchiveObjectDate {
  my ($self, $object, $archive) = @_;
  if (!exists $self->{archive_cache}{$archive}) {
    $self->_loadObjects($archive);
  }
  $self->{archive_cache}{$archive}{$object} = -1 unless $self->{archive_cache}{$archive}{$object};
  return $self->{archive_cache}{$archive}{$object};
}

sub _loadObjects {
  my ($self, $archive) = @_;
  # We assume that archive is a filename
  my (@objinfo);
  $self->debug("Loading archive $archive:");
  if ($archive =~ /\.a/) {
    ##<<<TODO: abstract 'ar' to symbol with full path in Change::Symbols
    my $ar = 'ar'; $ar = '/usr/ccs/bin/ar' if $^O eq 'solaris';
    my (@objentries) = `$ar -tv $archive`;
    if ($?) {
      $self->debug("error $?");
      die "Can't ar $archive, $?";
    }
    $self->debug(" retval $?, ", scalar(@objentries), " objects\n");
    foreach my $objline (@objentries) {
      $objline =~ /((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d+\s+\d\d:\d\d \d+)\s+(.*)$/;
      my ($date, $name) = ($1, $2);
      $objline =~ /^.{22}\s*(\d+)\s*[a-zA-Z]/;
      my ($size) = $1 || 0;
      $date = str2time($date);
      $self->{archive_cache}{$archive}{$name} = $date;
      push @objinfo, [$name, $date, $size];
    }
  }
  $self->debug("Setting $archive\n");
  $self->{archive_cache}{$archive}{':ordering'} = \@objinfo;
}


# Sun only right now. Set up the basic search paths we use to find
# library files.
sub initLibrarySearchPaths {
  # Set the search paths
  push @pathlist, split(':', $ENV{LD_LIBRARY_PATH}) if exists($ENV{LD_LIBRARY_PATH}) && defined($ENV{LD_LIBRARY_PATH});
  if ($^O eq 'solaris') {
    unshift @pathlist, COMPCHECK_DIR.$FS.'SunOS';
    unshift @pathlist, '/opt/SUNWspro8/lib', '/bb/util/common/studio8/SUNWspro/prod/lib', '/usr/ccs/lib';
  }
  if ($^O eq 'aix') {
    unshift @pathlist, '/usr/ccs/lib';
  }
  unshift @pathlist, '/usr/lib', '/lib';
  return;
}

sub addTypeSearchPath {
  my ($type) = @_;
  if ($type eq 'source') {
    unshift @pathlist, "/bbs/lib";
  }
  if ($type eq 'stage') {
    unshift @pathlist, "/bbs/stage/stagelib";
  }
  if ($type eq 'local') {
    unshift @pathlist, "/local/lib";
  }
}

#
# When given a full name, figure out what the actual library name is.
sub getLibShortName {
  my ($fullname) = @_;
}

# Figure out the actual path to the physical library
sub figureAbsPath {
  my ($self, $libname, $preferdynamic, $fallback) = @_;
  my $baselib = substr($libname, rindex($libname, '/')+1);
  my $testpath;

  # If it's fully qualified that's good enough.
  if ($libname =~ m|^/| && $libname =~ m<(\.a|\.so)>) {
    if (-e $libname) {
      return $libname;
    } else {
      # Abs path but we can't find it. Too bad for them, I guess.
      return;
    }
  }

  my @extlist;
  if ($preferdynamic) {
    @extlist = ('.dbg_exc_mt.so', '.opt_exc_mt.so', '.so', 
		'.realarchive.a', '.dbg_exc_mt.a', '.opt_exc_mt.a', '.a', '');
  } else {
    @extlist = (
		'.realarchive.a', '.dbg_exc_mt.a', '.opt_exc_mt.a', '.a', '',
		'.dbg_exc_mt.so', '.opt_exc_mt.so', '.so', 
	       );
  }

  foreach my $path (@pathlist) {
    foreach my $ext (@extlist) {
      $testpath = $path.'/lib'.$baselib.$ext;
#      $self->debug("Checking $testpath\n");
      if (-e $testpath) {
	$self->debug("Found $testpath for $libname\n");
	return $testpath;
      }
    }
  }

  if ($fallback) {
    # If we got here we didn't find it. Try the fallback location we got
    my $suffix = $^O eq "aix" ? "ibm" : "sundev1";
    my $file = "$fallback.$suffix";
    foreach my $ext ('.a.realarchive', '.realarchive.a', '.a') {
      $self->debug("checking $file$ext\n");
      return $file.$ext if -e $file.$ext;
    }
  }

  $self->debug("Can't find library for $libname in " . join(' ', @pathlist).  "\n");
#  confess();
  return;
}


1;
