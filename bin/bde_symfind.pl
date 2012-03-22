#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Binary::Analysis;
use Binary::Archive;
use Binary::Object;
use Date::Parse qw(str2time);
use Util::File::Basename qw(dirname basename);

 use Symbols qw[
     EXIT_FAILURE EXIT_SUCCESS
 ];


#==============================================================================

=head1 NAME

sym_lookup - Find a symbol in the library hierarchy

=head1 SYNOPSIS

    $ sym_lookup f77override

=head1 DESCRIPTION

C<sym_lookup> takes a list of symbols, object files, and archives, and
looks up the symbols, returning to the user the location of the
symbols. 

The default mode takes a symbol and returns the places in the
hierarchy on your current architecture that provide a function with
that name, but this program's behaviour can be modified by providing
the appropriate switches.

=over 4

=item caller

Instead of printing the providers of a symbol, print the callers of
that symbol instead.

=item arch

Either C<aix> or C<solaris>, search for the symbols in the libraries
for the specified architecture. Overrides the default, which is the
current architecture.

=item mangled

Assume the symbol passed in is mangled, and search for it as a mangled
name.

=item demangled

Assume the symbol passed in is demangled, and search for a
corresponding demangled name.

=item wildcard

Scan the symbol names and, if an SQL wildcard is detected (% and _) do
a wildcard lookup of the symbols instead. (This isn't the default as
symbol names often have underscores in them, and wildcard lookups are
relatively expensive)

=item data

Look for data symbols that match the passed-in names. (Not valid for
C<--callers>)

=item text

Look for text symbols that match the passed-in names. (Not valid for
C<--callers>)

=item bss

Look for bss symbols that match the passed-in names. (Not valid for
C<--callers>)

=item mostrecent

Report the most recent version of the symbol, if the symbol doesn't
currently exist in the libraries. This may take some time as
historical data needs to be searched. In this case only the most
recent version of a symbol is reported.

=item date

Choose the date to use to find symbols. A snapshot of the libraries as
of that date is made, and then searched.

=item withpending

Look at the libraries with changesets applied, otherwise look at just
the base libraries.

=item buildtag=(source|stage)

Look at either the source or stage libraries. Default is source.

=back

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | symbol|archive|object
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --instance   | -i           instance to use 
  --verbose    | -v           print details of what's happening
  --callers    | -c           Print callers of the symbol
  --arch=[solaris|aix]        Look things up on the given architecture
  --mangled                   Assume the passed-in symbol is mangled
  --demangled                 Assume the passed-in symbol is demangled
  --wildcard                  Do a wildcard lookup of the symbol
  --datasym                   Look for data symbols
  --text                      Look for text symbols
  --bss                       Look for bss symbols
  --mostrecent                Find the most recent version of the symbol if
                              it isn't currently available
  --withpending               Consider changesets in reporting symbols
  --date=datestring           Report symbols as of the specified date and time
  --buildtag=(source|stage)   Look at source or stage libs
  --offline                   Look in offline libraries too

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
        verbose|v
	dbtype=s
        callers|caller|refs|c
        arch=s
        lookup
        mangled
        demangled
        wildcard
        data|datasym
        text
        bss
        mostrecent
        date=s
        offline
        attribute=s@
        date=s
        withpending
	buildtag=s
        complain
        tidy
	deps|dep|dependencies
        stdin
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    $opts{debug} = 1 if exists $opts{debug};
#    $opts{dbtype} = 'informix' unless $opts{dbtype};
#    if ($opts{dbtype} ne 'informix' && !defined $opts{instance}) {
#      $opts{instance} = 'newvalid';
#    }
    if ($opts{callers} && ($opts{text} || $opts{data} || $opts{bss})) {
      print "Can't mix caller with text/data/bss\n";
      usage();
      exit EXIT_FAILURE;
    }

    # For right now we only want folks calling our text symbols
    $opts{text} = 1 if $opts{callers};

    # Are we offline only?
    if ($opts{offline}) {
      if ($opts{attribute}) {
	push @{$opts{attribute}}, 'offlineonly';
      } else {
	$opts{attribute} = ['notoffline', 'offlineonly'];
      }
    }

    # Yell if they used something we told them was OK if we haven't
    # actually implemented it yet.
#    unimp('date') if $opts{date};

    $opts{attribute} = ['notoffline'] unless $opts{attribute};
    push @{$opts{attribute}}, 'notoffline';
    return \%opts;
}

sub unimp {
  my $option = shift;
  $option ||= "";
  print "Unimplemented option $option chosen\n";
  exit EXIT_FAILURE;
}

MAIN: {
  my $db;
  my $opts = getoptions();
  $| = 1;
  my $params = {};

  my $date = time;
  if ($opts->{date}) {
    $date = str2time($opts->{date});
  }

  my $tempstatus = $opts->{withpending} || 0;

  $params->{instance} = $opts->{instance} if $opts->{instance};
  $params->{dbtype} = $opts->{dbtype} if $opts->{dbtype};
  $params->{arch} = $opts->{arch} if $opts->{arch};
  $params->{debug} = $opts->{debug} if $opts->{debug};
  $params->{buildtag} = $opts->{buildtag} if $opts->{buildtag};
  if ($opts->{debug}) {
    print "opening db connection\n";
  }

  $db = Binary::Analysis->new($params);
  my $branch = $db->{basebranch};
  if ($params->{dbtype} eq 'informix') {
    # This is kinda evil, but for symbol lookup it's actually OK.
    $db->{dbh}->do("set isolation to dirty read");
  }

  my @symids;
  my @symparams;
  my %syms;
  if ($opts->{stdin}) {
    local $/ = undef;
    push @symparams, split ' ', <STDIN>;
  } else {
    @symparams = @ARGV;
  }
  foreach my $sym (sort @symparams) {
    if ($sym =~ /\.o$/ || $sym =~ /\.a$/) {
      my $binobj;
      if ($sym =~ /\.a$/) {
	$binobj = Binary::Archive->new($sym);
      } else {
	$binobj = Binary::Object->new($sym);
      }
      my @binsyms;
      if ($opts->{callers} || $opts->{lookup}) {
	foreach my $sym ($binobj->getDefinedSymbols()) {
	  my $type = $sym->getType;
	  next if (($type eq 'D') && !$opts->{data});
	  next if (($type eq 'T') && !$opts->{text});
	  next if (($type eq 'B') && !$opts->{bss});
	  $db->debug("adding symbol $sym type $type\n");
	  push @binsyms, $sym;
	}
      } else {
	$db->debug("Undefs\n");
	@binsyms = $binobj->getUndefinedSymbols();
      }
      foreach my $binsym (@binsyms) {
	$syms{$binsym}++;
	my $symid = $db->getSymbolID($binsym);
	if (!defined $symid) {
	  next;
	}
	push @symids, $symid;
      }
    } else {
      if ($opts->{wildcard}) {
	my $field;
	if ($opts->{mangled}) {
	  $field = 'fullsymbolname';
	} else {
	  $field = 'demangledname';
	}

	$db->debug("Getting symbolids\n");
	my $qsym = $db->{dbh}->quote($sym);
	my $syms = $db->{dbh}->selectcol_arrayref("select symbolid from symbols where $field like $qsym");
	$db->debug("Got " .scalar(@$syms)."\n");
	push @symids, @$syms;
      } else {
	my $symid;
	$syms{$sym}++;
	$db->debug("Getting symbolid\n");
	if ($opts->{demangled}) {
	  ($symid) = $db->{dbh}->selectrow_array("select symbolid from symbols where demangledname = ?", undef, $sym);
	} else {
	  $symid = $db->getSymbolID($sym);
	}
	$db->debug("Gotten\n");
	if (!defined $symid) {
	  print "No such symbol $sym\n" unless $opts->{complain};
	  next;
	}
	push @symids, $symid;
      }
    }
  }

  if (!@symids) {
    print "No symbols to look up\n";
    exit;
  }

  # Uniquify them
  {
    my %uniq;
    @uniq{@symids} = ();
    @symids = keys %uniq;
  }

  my $symidquest = join(', ', map {'?'} @symids);
  my $attrquest = join(', ', map {'?'} @{$opts->{attribute}});

  my %seensym;
  if ($opts->{callers}) {
    $db->debug("Getting callers\n");
    $db->debug(scalar(@symids)." symbols to look up\n");
    my ($rows) = $db->{dbh}->selectall_arrayref("
select libinstance.entityid,
       objid,
       symbolid,
       libobject.objinstance
  from libinstance,
       libobject,
       use_symbol
 where libinstance.libdate <= ?
   and libinstance.enddate > ?
   and libinstance.libinstanceid = libobject.libinstanceid
   and libinstance.architecture = ?
   and libinstance.istemp = ?
   and libobject.objinstance = use_symbol.objinstance
   and libinstance.branchid = ?
   and use_symbol.symbolid in ($symidquest)",
       undef, $date, $date, $db->{arch}, $tempstatus, $branch, @symids);
    foreach my $row (@$rows) {
      my ($entityid, $objid, $symbolid, $objinstance) = @$row;
      my $entity = $db->getEntityName($entityid) || "<$entityid>";
      next unless grep {$db->hasAttribute($entity, $_)} @{$opts->{attribute}};
      my $csid = $db->getCSID($objinstance);
      my $object = $db->getObjectName($objid) || "<$objid>";
      $object =~ s/\.o//;
      my $symbol = $db->getSymbolName($symbolid) || "";
      $seensym{$symbol}++;
      if ($csid) {
	print "$entity\[$object]:$symbol $csid\n";
      } else {
	print "$entity\[$object]:$symbol\n";
      }
    }
  } else {
    my @types;
    push @types, 'D' if $opts->{data};
    push @types, 'T' if $opts->{text};
    push @types, 'B' if $opts->{bss};
    push @types, 'T' unless @types;

#
# XXXXXXXXXX Note the two queries are out of sync. QUery 2 is hacked
# down to do fewer tables to try and make things go faster, with the
# assumption that there'll be post-processing. Preliminary results say
# it looks good.
#

    my $rows;
    if (@types == 1) {
      $db->debug("Getting (1) providers\n");
      my $curdate = time;
#      $db->{dbh}->do("set explain on");
      $rows = $db->{dbh}->selectall_arrayref("
select libinstance.entityid,
       objid,
       symbolid,
       symboltype,
       libobject.objinstance
  from libinstance,
       libobject,
       provide_symbol
 where libinstance.libdate <= ?
   and libinstance.enddate > ?
   and libinstance.libinstanceid = libobject.libinstanceid
   and libinstance.architecture = ?
   and libinstance.istemp = ?
   and libobject.objinstance = provide_symbol.objinstance
   and libinstance.branchid = ?
   and provide_symbol.symboltype = ?
   and provide_symbol.symbolid in ($symidquest)",
      undef, $date, $date,
      $db->{arch}, $tempstatus, $branch, @types,  @symids);
    } else {
      $db->debug("Getting (X) providers\n");
      my $curdate = time;
      $rows = $db->{dbh}->selectall_arrayref("
select libinstance.entityid,
       objid,
       symbolid,
       symboltype,
       libobject.objinstance
  from libinstance,
       libobject,
       provide_symbol
 where libinstance.libdate <= ?
   and libinstance.enddate > ?
   and libinstance.libinstanceid = libobject.libinstanceid
   and libinstance.architecture = ?
   and libinstance.istemp = ?
   and libinstance.branchid = ?
   and libobject.objinstance = provide_symbol.objinstance
   and provide_symbol.symboltype in (" . join(", ", map {'?'} @types) .")
   and provide_symbol.symbolid in ($symidquest)",
       undef, $date, $date,
       $db->{arch}, $tempstatus, $branch, @types,  @symids);
    }
    $db->debug(time." extracting objects\n");
    {
      my @objs;
      foreach my $row (@$rows) {
	push @objs, $row->[1];
      }
      $db->debug(time." loading cache\n");
      if (@objs > 50) {
	$db->cacheLoadObjectName(@objs[0..49]);
      }
    }
    $db->debug(time." dumping rows\n");
    foreach my $row (@$rows) {
      my ($entityid, $objid, $symbolid, $symboltype, $objinstance) = @$row;
      my $entity = $db->getEntityName($entityid) || "<$entityid>";
      next unless grep {$db->hasAttribute($entity, $_)} @{$opts->{attribute}};
      my $csid = $db->getCSID($objinstance);
      my $object = $db->getObjectName($objid) || "<$objid>";
      $object =~ s/\.o//;
      my $symbol = $db->getSymbolName($symbolid) || "";
      $seensym{$symbol}++;
      if ($csid) {
	print "$entity\[$object]:$symbol $symboltype $csid\n";
      } else {
	print "$entity\[$object]:$symbol $symboltype\n";
      }
    }

  }
  if ($opts->{complain}) {
    foreach my $sym (keys %syms) {
      if (!exists $seensym{$sym}) {
	print "****MISSING $sym\n";
      }
    }
  }

}
