#!/bbs/opt/bin/perl-5.8.8 -w
use strict;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Binary::Analysis;
use Binary::Analysis::Demangle;
use Binary::Archive;
use Binary::Object;
use Date::Parse qw(str2time);
use Util::File::Basename qw(dirname basename);
use Getopt::Long;
use POSIX qw(_exit);

 use Symbols qw[
     EXIT_FAILURE EXIT_SUCCESS 
 ];

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | uor
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --instance   | -i           instance to use 
  --verbose    | -v           print details of what's happening

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        instance|i=s
	refresh|r
        verbose|v
	dbtype=s
        unsafe
        insane
	branch
	buildtag=s
	date=s
        offline
	makefile|f=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    $opts{debug} = 1 if exists $opts{debug};
    $opts{dbtype} = 'informix' unless $opts{dbtype};
    if ($opts{dbtype} ne 'informix' && !defined $opts{instance}) {
      $opts{instance} = 'validation';
    }
    $opts{buildtag} = 'source' unless $opts{buildtag};
    return \%opts;
}

sub load_up_lib {
  my ($db, $entity, $entityid, $libsyms, $provide_hash, $use_hash) = @_;

  $db->debug("Loading in for $entity\n");

#   my $rows = $db->{dbh}->selectall_arrayref("
#    select symbolid,
#           myobjinstances.objinstance,
#           objorder
#      from provide_symbol,
#           myobjinstances
#     where provide_symbol.objinstance = myobjinstances.objinstance
#       and myobjinstances.entityid = ?
#  order by objorder", undef, $entityid);
  my $rows = $libsyms->[$entityid];
  $db->debug("Loading in provide hash with ". scalar(@$rows). " symbol entries\n");

  foreach my $row (@$rows) {
    next if exists $provide_hash->{$row->[1]};
#    $db->debug("sym $row->[0] provided by $entityid:$row->[1]\n");
    $provide_hash->{$row->[1]} = $entityid.':'.$row->[2];
  }
  $db->debug("done\n\n");

}

MAIN: {
  my $db;
  my $opts = getoptions();
  $| = 1;

  my $params = {};
  $params->{instance} = $opts->{instance} if $opts->{instance};
  $params->{dbtype} = $opts->{dbtype} if $opts->{dbtype};
  $params->{debug} = $opts->{debug} if $opts->{debug};
  $params->{basebranch} = $opts->{branch} if $opts->{branch};
  $params->{buildtag} = $opts->{buildtag} if $opts->{buildtag};
  $db = Binary::Analysis->new($params);

  my $date = time;
  if ($opts->{date}) {
    $date = str2time($opts->{date});
  }

  if ($params->{dbtype} eq 'informix') {
    # This is kinda evil, but for symbol lookup it's actually OK.
    $db->{dbh}->do("set isolation to dirty read");
  }

  my (@basedefs, @baseundefs);
  my (%provides_sym);
  my (%uses_sym);
  my %resolved_sym;
  my %seen_objects;
  my @libsyms;
  my (@pendingundefs);
  my (@libs);
  my (@symprovide);
  my (%outofband);
  my (%missing);

  my @objs;
  if ($opts->{makefile}) {
    $db->debug("makefile is $opts->{makefile}\n");
    @objs = grep { /\.o$/ } $db->parseMakefileForStuff($opts->{makefile});
  } else {
    @objs = @ARGV;
  }
  $db->debug("Object files are ", join(" ", @objs), "\n");
  # Extract out the base set of objects
  foreach my $obj (@objs) {
    eval {
      my $obj_obj = Binary::Object->new($obj);
      foreach my $sym ($obj_obj->getDefinedSymbols) {
	my $symid = $db->getSymbolID($sym->getName);
	if (!$symid) {
	  $outofband{$sym}++;
	  next;
	}
	$provides_sym{$symid} = '.base:.base';
	$resolved_sym{$symid} = 1;
      }
      foreach my $sym ($obj_obj->getUndefinedSymbols) {
	next if $outofband{$sym}; # Just skip if we saw it in another
                                  # .o already
	my $symid = $db->getSymbolID($sym->getName);
	if (!$symid) {
	  $missing{$sym}++;
	  next;
	}
	push @pendingundefs, $symid;
      }
    };
  }
  # Run through everything we found that we didn't see anywhere in the
  # library hierarchy
  foreach my $sym (sort keys %missing) {
    next if $outofband{$sym};
    print STDERR "$sym not known to system\n";
  }


  $db->debug("Making temp table\n");

  # Build up the temp table we drive stuff from
  my ($pgin, $infxin) = ("","");
  if ($db->{dbtype} eq 'informix') {
    $infxin = "into temp myobjinstances";
  } else {
    $pgin =  "into temp myobjinstances";
  }
  my ($attribs, $attribwhere) = ("", "");
  my ($addinextras);
  if (!$opts->{offline}) {
    $attribs = ", attributes";
    $attribwhere = "and libinstance.entityid = attributes.entityid and attributes.attribute = 'notoffline'";
    $addinextras++;
  }
  $db->{dbh}->do("SELECT libobject.entityid,
                    objinstance,
		    objorder
$pgin
               FROM libinstance,
                    libobject
                    $attribs
      WHERE libdate <= ?
        AND enddate > ?
        AND libobject.libinstanceid = libinstance.libinstanceid
        AND architecture = ?
        AND branchid = ?
        AND istemp = 0
$attribwhere
       $infxin", undef, $date, $date, $db->{arch}, $db->{basebranch});

  # Do we think we need to throw in all the third party libs?
  if ($addinextras) {
    $db->{dbh}->do("INSERT INTO myobjinstances
             SELECT libobject.entityid,
                    objinstance,
		    objorder
               FROM extra_libs,
                    libinstance,
                    libobject
      WHERE libdate <= ?
        AND enddate > ?
        AND libobject.libinstanceid = libinstance.libinstanceid
        AND architecture = ?
        AND istemp = 0
        AND extra_libs.entityid = libobject.entityid
       ", undef, $date, $date, $db->{arch});
  }

  $db->{dbh}->do("create index myobjinstindex on myobjinstances (entityid)");

  $db->debug("Fetching undefs (".time.")\n");
  {
    my $rows = $db->{dbh}->selectall_arrayref("
   select entityid,
          symbolid,
          myobjinstances.objinstance
     from use_symbol,
          myobjinstances
    where use_symbol.objinstance = myobjinstances.objinstance", undef);
    foreach my $row (@$rows) {
      push @{$uses_sym{$row->[0]}{$row->[2]}}, $row->[1];
    }
  }


  $db->debug("Fetching defs (".time.")\n");
  {
    my $rows = $db->{dbh}->selectall_arrayref("
   select entityid,
          symbolid,
          myobjinstances.objinstance,
          objorder
     from provide_symbol,
          myobjinstances
    where provide_symbol.objinstance = myobjinstances.objinstance
 order by entityid, objorder", undef);
    foreach my $row (@$rows) {
      push @{$libsyms[$row->[0]]}, $row;
      $symprovide[$row->[1]] = $row->[0] unless $symprovide[$row->[1]];
    }
  }

  $db->debug("Walking undef list(".time."\n");
  # We have our undefs. We're gonna be horrid here and just take 'em
  # one by one.
  while (@pendingundefs) {
    my $symid = pop @pendingundefs;
    # Have we already resolved this symbol? Go to the next one if we have
    if (exists $resolved_sym{$symid}) {
#      $db->debug("Already resolved $symid\n");
      next;
    }

    # Have we already added a library that provides this symbol?
    if (!exists $provides_sym{$symid}) {
      # We haven't seen a library that provides this symbol. Go
      # find one.

      my $entityid = $symprovide[$symid];
      # If we can't find anything then complain and skip to the next symbol
      if (! defined $entityid) {
	my $sym = $db->getSymbolName($symid);
	print STDERR "Nothing provides $sym\n";
	# No sense looking again -- it's not like it'll magically appear
	$resolved_sym{$symid}++;
	next;
      }
      # Go load up the library
      my $entity = $db->getName($entityid);
      push @libs, $entity unless $entity =~ /^Magic::/;
      load_up_lib($db, $entity, $entityid, \@libsyms, \%provides_sym, \%uses_sym);
    }

    # Note that we've resolved this symbol
    $resolved_sym{$symid}++;
    # Skip if we've loaded the .o that provides this symbol already
    if (!$provides_sym{$symid}) {
      my $sym = $db->getSymbolName($symid);
      die "Something didn't provide $sym!";
    }
    if ($seen_objects{$provides_sym{$symid}}) {
#      $db->debug("seen object ".$provides_sym{$symid}. " for symbol $symid\n");
      next;
    }

    # Right, gotta load the .o
    my ($lib, $obj) = split(':', $provides_sym{$symid});
    # Note we've seen the object
    $seen_objects{$provides_sym{$symid}}++;


    my (@o_undefs);
    @o_undefs = @{$uses_sym{$lib}{$obj}} if $uses_sym{$lib}{$obj};
#    $db->debug("Adding $lib:$obj, ".join(" ", @o_undefs). " undefs\n");
    # Note the object's undefs
    push @pendingundefs, @o_undefs;

  }

  my $inclibs = "INCLIBS = " . join(" ", map {"-l$_"} @libs). "\n";
  $inclibs =~ s/Library:://g;
  # Patch up the bde extensions
  $inclibs =~ s/-l(bae|bce|bde|bse|bte) /-l$1.dbg_exc_mt /g;
  print $inclibs;
  _exit(1);

}
