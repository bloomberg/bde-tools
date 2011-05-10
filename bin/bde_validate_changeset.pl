#!/bbs/opt/bin/perl-5.8.8 -w
#
# Please note -- this frankenstinian monstrosity was part of the
# oracle before it was ripped out for this sample task, and then
# ripped to shreds again to make it reasonably performant.
use strict;
use Carp;
use Digest::MD5 qw(md5_hex);

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";
use Binary::Analysis;
use Binary::Analysis::Tools;
use Getopt::Long;
use Binary::Aggregate;
use Binary::Archive;

use BDE::Util::Nomenclature qw(isGroup isPackage isIsolatedPackage
 			       isLegacy isApplication isThirdParty isFunction
 			       getCanonicalUOR);
use BDE::Util::DependencyCache qw(getGroupDependencies getPackageDependencies
 				  getCachedGroupOrIsolatedPackage);

#use Change::Set;

use Util::File::Basename qw(dirname basename);
use Util::Message qw(message alert verbose verbose2 verbose_alert
		     get_verbose debug fatal warning error get_prog
		     set_prog get_prefix set_prefix set_verbose
		    );

use constant ERR_HIERARCHY => 1;
use constant ERR_MULTIDEF => 2;
use constant ERR_UNDEF => 4;
use constant ERR_INUSE => 8;
use constant ERR_HARDVIOLATION => 16;
use constant ERR_MAIN => 32;

use Symbols qw[
	       EXIT_FAILURE EXIT_SUCCESS
	      ];

my @free_libs;

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | symbol|archive|object
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --instance   | -i           instance to use 
  --verbose    | -v           print details of what's happening
  --dbtype                    Which type of database to use
  --debug      | -d           Enable debug logging

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
        verbose|v+
	dbtype=s
        arch=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    usage(), exit EXIT_FAILURE if @ARGV != 1;

    # debug mode
    $opts{debug} = 1 if exists $opts{debug};
    $opts{dbtype} = 'informix' unless $opts{dbtype};
    if ($opts{dbtype} ne 'informix' && !defined $opts{instance}) {
      $opts{instance} = 'newvalid';
    }
    set_verbose($opts{verbose}) if $opts{verbose};

    return \%opts;
}


# Some general notes here, since this is getting complex enough that
# I'm losing track.
#
# This module skips Binary::Symbol for the most part.The data is in
# the serialized symbol file, and not in the format that
# Binary::Symbol likes (since it doesn't have a preference for this
# sort of thimg) so there's little point in round-tripping through
# Binary::Symbol. There's no win, and it slows things down, so we
# don't.
#
# The internal symbol format used is the same as the one that the
# serialized changeset code uses, for ease of use. Generally speaking
# we sling these 'objects' around so we have full info at hand.


# General logging package. This probably ought to be yanked out and
# pulled into its own module or rolled into Util::Message or something.
{
  package llog;
  use Change::Symbols qw[COMPCHECK_DIR];
  use Util::Message qw(warning verbose);
  sub open_logfile {
    my ($csid) = @_;
    my $self = {};
    # Base filename is either the changeset or 
    $csid = $csid || '<no id>';
    if ($csid eq '<no id>') {
      $csid = 'cscompile' . time();
    }
    my $logname = $csid;
    my $fh;
    open($fh, '>'.$logname) || do {warning("Unable to open log file $logname, $!"); $fh = undef } ;
    $self->{fh} = $fh;
    return bless $self;
  }

  sub log {
#    return;
    my ($self, @args) = @_;
    print "(pid $$) ", scalar(time()), " ", @args, "\n";
    return unless defined $self->{fh};
    my $fh = $self->{fh};
    print $fh scalar(time()), " ", @args, "\n";
  }

  sub log_verbose {
#    return;
    my ($self, @args) = @_;
    verbose("(pid $$) ". scalar(time()). " ". join(" ", @args));
    return unless defined $self->{fh};
    my $fh = $self->{fh};
    print $fh scalar(time()), " ", @args, "\n";
  }

  sub DESTROY {
    my $self = shift;
    if (defined $self->{fh}) {
      close $self->{fh};
    }
  }
}

sub who_provides {
  my ($db, $sym) = @_;
  my $retval = "";

  my $symid = $db->getSymbolID($sym->{name});

  my $row = $db->{dbh}->selectrow_arrayref("
select first 1 objid,
               entityid
  from provide_symbol,
       temp_libobject
 where temp_libobject.objinstance = provide_symbol.objinstance
   and provide_symbol.symbolid = ?", undef, $symid);
  if ($row && @$row) {
    my $obj = $db->getObjectName($row->[0]);
    my $entity = $db->getName($row->[1]);
    $retval = "$entity\[$obj]:$sym->{name}";
  }

  return $retval;
}


sub final_report {
  my ($db, $logfile, $multidef, $undef, $h_viol, $inuse, $main_viol) = @_;

  my $status = 0;
  $status |= ERR_HIERARCHY if @$h_viol;
  $status |= ERR_MULTIDEF if @$multidef;
  $status |= ERR_UNDEF if @$undef;
  $status |= ERR_INUSE if @$inuse;
  $status |= ERR_MAIN if $main_viol;

  foreach my $sym (@$h_viol) {
    if ($sym->{harderror}) {
      $status |= ERR_HARDVIOLATION;
      last;
    }
  }

  print "Validation status (rc: $status)\n\n";

  if (@$h_viol) {
    print STDERR "The following symbols violate the hierarchy:\n";
    foreach my $sym (@$h_viol) {
      my $extra = $sym->{harderror} ? ' FATAL ERROR ' : "";
      print STDERR "  ", $sym->{LongName}, " $extra (do you need ", who_provides($db, $sym), "?)\n";
    }
    print STDERR "\n";
  }

  if (@$multidef) {
    print STDERR "The following symbols were multiply defined:\n";
    foreach my $errors (@$multidef) {
      my ($libsym, $cssyms, $type) = @$errors;
      if ($libsym) {
	print STDERR "  ", join(" ", map {$_->{LongName}} @$cssyms), " conflict with ", $libsym->[2], "[",$libsym->[1],']:',$libsym->[0], "\n";
      } else {
	print STDERR "  in-changeset symbol conflicts with ", join(" ", map {$_->{LongName}} @$cssyms), "\n";
      }	
    }
    print STDERR "\n";
  }

  if (@$undef) {
    print STDERR "The following symbols are undefined in the robo hierarchy:\n";
    foreach my $sym (@$undef) {
      print STDERR "  ", $sym->{LongName}, "\n";
    }
    print STDERR "\n";
  }

  if (@$inuse) {
    print STDERR "The following symbols being removed are still used:\n";
    foreach my $sym (@$inuse) {
      print STDERR "  ", $sym->{LongName}, " used by ", find_user($db, $sym), "\n";
    }
    print STDERR "\n";
  }

  if ($main_viol) {
    print STDERR "main is not allowed in code\n\n";
  }

  return $status;
}

# Load in a .o file from disk, with a cache. That way we don't bother
# loading the same .o file multiple times, which is slow since it
# involves disk and all that.
sub load_o_file_cached {
  my ($db, $ofile, $lib, $o_cache, $logfile) = @_;
  if (defined $o_cache->{$lib}{$ofile}) {
    return $o_cache->{$lib}{$ofile};
  }
  my %obj;
  @obj{qw(lib source target dest arch)} = @{$ofile}{qw(lib source target dest arch)};
  foreach my $sym (@{$ofile->{symbols}}) {
    my $symobj = {archive => $ofile->{lib},
		  object => $ofile->{dest},
		  name => $sym->{symbol},
		  type => $sym->{type},
		  size => $sym->{size},
		  value => $sym->{value},
		  common => $sym->{common},
		  LongName => $ofile->{lib}.'['.$ofile->{dest}.']:'.$sym->{symbol},
		  weak => $sym->{weak},
		 };
    if ($sym->{type} eq 'U') {
      push @{$obj{undefs}}, $symobj;
    } else {
      push @{$obj{defs}}, $symobj;
    }
    my $oid = $db->getObjectID($ofile->{dest});
    if (!$oid) {
      $oid = $db->addObject($ofile->{dest});
    }
    $symobj->{oid} = $oid;
    my $eid = $db->getEntityID($ofile->{lib});
    $symobj->{eid} = $eid;
  }

  $o_cache->{$lib}{$ofile} = \%obj;
  return \%obj;
}

sub split_o_files {
  my ($source) = @_;
  if (!wantarray) {
    confess "Not in array context!";
  }
  debug("Splitting $source\n");
  my @o_files;
  if (substr($source, -2) eq '.f') {
    my $num_funcs = 0;
    my $PH = Symbol::gensym;
    open($PH, "-|",
         "/bb/bin/breakftnx",
         "-breakftnxlistobjs",
         $source) || next;
    $num_funcs = 0;
    while (<$PH>) {
      chomp;
      push @o_files, $_.".o";
    }
    close $PH;
  } else {
    $source =~ s/\.[^.]*$//;
    $source .= '.o';
    push @o_files, $source;
  }
  return @o_files;
}

# Takes a DB handle and list of symbols, and checks to see if any of
# them are already defined in the database.
#
# Returns a list of arrayrefs. The arrayref holds the symbolname,
# objectname, and entityname of the things we found that provides a
# symbol we asked for.
sub multiDef {
  my ($db, $logfile, @syms) = @_;
  my %uniq;
  @uniq{@syms} = ();
  @syms = keys %uniq;
  return unless @syms;
  my %seensym;
  $logfile->log_verbose("Looking for multidefs for " . scalar(@syms) . " symbols\n");
  my $symref = $db->{dbh}->selectall_arrayref("
  select distinct symbols.symbolid, 
                  objid,
                  temp_libobject.entityid
    from provide_symbol,
         temp_libobject,
         symbols
   where symbolhash in (". join(", ", map {'?'} @syms). ") 
     and provide_symbol.symbolid = symbols.symbolid
     and provide_symbol.objinstance = temp_libobject.objinstance
     and temp_libobject.offline_only != 1",
    undef, map {md5_hex($_)} @syms);
  my @retvals;
  $logfile->log_verbose("Got back " . scalar(@syms) . " multidefs\n");
  foreach (@$symref) {
    next if $seensym{$_->[0]};
    push @retvals, [$db->getSymbolName($_->[0]),
		    $db->getObjectName($_->[1]),
		    $db->getName($_->[2])
		   ];
    $seensym{$_->[0]}++;
  }
  return @retvals;
}

# Takes a DB handle and list of symbols, and checks to see if any of
# them are already defined in the database. This is a plain list of
# symbol names that aren't in the current set of libraries. We don't
# get any fancier since we don't have much info -- the symbols may not
# have ever been in the symbol table (and therefore have no ID) or may
# have been once but currently aren't.
sub notProvided {
  my ($db, @syms) = @_;
  my %uniq;
  @uniq{@syms} = ();
  @syms = keys %uniq;
  my $symref = $db->{dbh}->selectcol_arrayref("
  select distinct symbolname
    from  provide_symbol,
         temp_libobject,
         symbols
   where symbols.symbolhash in (". join(", ", map {'?'} @syms). ")
     and provide_symbol.symbolid = symbols.symbolid
     and provide_symbol.objinstance = temp_libobject.objinstance
     and temp_libobject.offline_only != 1",
    undef, map {md5_hex($_)} @syms);
  foreach my $sym (@$symref) {
    delete $uniq{$sym};
  }
  return sort keys %uniq;
}

# Takes a DB handle and list of symbols, and checks to see if any of
# them are already defined in the database.
#
# SLOW SLOW SLOW SLOW
#
sub notProvidedUndefs {
  my ($db, $logfile, @syms) = @_;
  my %uniq;
  $logfile->log_verbose("Uniquing syms");
  @uniq{@syms} = ();
  @syms = keys %uniq;
  my %symhash;
  foreach my $sym (@syms) { $symhash{md5_hex($sym)} = $sym};
  $db->debug_stamp("notProvidedUndef looking for ".scalar(keys %symhash). " undefs\n");
  $logfile->log_verbose("uniqing done");
  $db->cacheLoadSymbolID(values %symhash);
  my (@symid) = map {$db->getSymbolID($_)} values %symhash;
  my $quest = join(", ", map {'?'} @symid);
  my $symidmatch;
  if (@symid > 1) {
    $symidmatch = "in ($quest)";
  } else {
    $symidmatch = " = ?";
  }
#   my $symref = $db->{dbh}->selectcol_arrayref("
# select distinct symhash
#   from temp_undef_syms,
#        provide_symbol,
#        temp_libobject
#  where provide_symbol.symbolid = temp_undef_syms.symbolid
#    and provide_symbol.objinstance = temp_libobject.objinstance
#    and temp_undef_syms.symbolid in ($quest)
#    and temp_libobject.offline_only != 1", undef, @symid);
  my $symref = $db->{dbh}->selectcol_arrayref("
select distinct symhash
  from temp_undef_syms,
       provide_symbol,
       temp_libobject
 where temp_undef_syms.symbolid = provide_symbol.symbolid
   and provide_symbol.objinstance = temp_libobject.objinstance
   and provide_symbol.symbolid $symidmatch
   and temp_libobject.offline_only != 1", undef, @symid);
  $logfile->log_verbose("cleaning out provided");
  $db->debug_stamp("Got back ".scalar(@$symref)." things\n");
  foreach my $sym (@$symref) {
    if (exists $symhash{$sym}) {
      delete $uniq{$symhash{$sym}};
    }
  }
  $logfile->log_verbose("cleaning done");
  return sort keys %uniq;
}

# Takes a DB handle and list of symbols, and checks to see if any of
# them are already defined in the database. This function is
# insufficiently selective -- it only returns the names of the symbols
# that aren't provided, which really isn't enough.
#
# SLOW SLOW SLOW SLOW
#
sub notProvidedChildUndefs {
  my ($db, @syms) = @_;
  my %uniq;
  @uniq{@syms} = ();
  @syms = keys %uniq;
  my %symhash;
  foreach my $sym (@syms) { $symhash{md5_hex($sym)} = $sym};
  my $freelibsql = "";
  if (@free_libs) {
    $freelibsql = "or temp_libobject.entityid in (".join(", ", @free_libs).")";
  }
  $db->debug_stamp("notProvidedChildUndef looking for ".scalar(keys %symhash). " undefs\n");
  $db->cacheLoadSymbolID(values %symhash);
  my (@symid) = map {$db->getSymbolID($_)} values %symhash;
  my $quest = join(", ", map {'?'} @symid);
  my $symidmatch;
  if (@symid > 1) {
    $symidmatch = "in ($quest)";
  } else {
    $symidmatch = " = ?";
  }

  my $symref = $db->{dbh}->selectcol_arrayref("
select distinct symhash
  from temp_undef_syms,
       provide_symbol,
       temp_libobject
 where temp_undef_syms.symbolid = provide_symbol.symbolid
   and provide_symbol.objinstance = temp_libobject.objinstance
   and provide_symbol.symbolid $symidmatch
   and (temp_libobject.entityid in (select toid from dependencies where fromid = temp_undef_syms.entityid and (strength = 'strong' or strength = 'extra'))
$freelibsql
     or temp_libobject.entityid = temp_undef_syms.entityid)
   and temp_libobject.offline_only != 1", undef, @symid);

  $db->debug_stamp("Got back ".scalar(@$symref)." things\n");
  foreach my $sym (@$symref) {
    if (exists $symhash{$sym}) {
      delete $uniq{$symhash{$sym}};
    }
  }
  return sort keys %uniq;
}

sub stillUsed {
  my ($db, @syms) = @_;
  my %uniq;
  @uniq{@syms} = ();
  @syms = keys %uniq;
  return unless @syms;
  my $symref = $db->{dbh}->selectcol_arrayref("
  select distinct symbols.symbolname
    from symbols a,
         use_symbol,
         temp_libobject,
         symbols
   where a.symbolhash in (". join(", ", map {'?'} @syms). ")
     and use_symbol.symbolid = a.symbolid
     and symbols.symbolid = use_symbol.symbolid
     and use_symbol.objinstance = temp_libobject.objinstance
     and temp_libobject.offline_only != 1",
        undef, map {md5_hex($_)} @syms);
  return @$symref;

}

sub buildUndefTable {
  my ($db, @undefs) = @_;
  if ($db->{dbtype} eq 'informix') {
    $db->{dbh}->do("create temp table temp_undef_syms (entityid integer, symhash char(32), symbolid integer)");
    my $sth = $db->{dbh}->prepare("insert into temp_undef_syms (entityid, symhash) values (?,?)", {ix_InsertCursor => 1});
#   $db->{dbh}->do("set explain off");

    foreach my $sym (@undefs) {
      $sth->execute($db->getEntityID($sym->{archive}), md5_hex($sym->{name}));
    }
    $sth->finish();
    undef $sth;
  } else {
    $db->{dbh}->do("create temp table temp_undef_syms (entityid integer, symhash char(32), symbolid integer)");
    my $sth = $db->{dbh}->prepare("insert into temp_undef_syms (entityid, symhash) values (?,?)");
#   $db->{dbh}->do("set explain off");

    foreach my $sym (@undefs) {
      $sth->execute($db->getEntityID($sym->{archive}), md5_hex($sym->{name}));
    }
    $sth->finish();
    undef $sth;
  }
#   $db->{dbh}->do("set explain on");
  $db->{dbh}->do("update temp_undef_syms set symbolid = (select symbolid from symbols where symbols.symbolhash = temp_undef_syms.symhash)");
  $db->{dbh}->do("create index tus_1 on temp_undef_syms (symbolid)");
  if ($db->{dbtype} eq 'informix') {
    $db->{dbh}->do("update statistics for table temp_undef_syms");
  }

}

sub cleanup {
  my $db = shift;
  eval {
    $db->{dbh}->do("drop table temp_undef_syms");
  };
  $db->cleanupTempTables();
}


sub filterWeakOK {
  my ($db, $undefs, $added_hash) = @_;
  my @badundefs;
  foreach my $sym (@$undefs) {
    foreach my $symhash (@{$added_hash->{$sym}}) {
      if (!defined $symhash->{eid}) {
	push @badundefs, $symhash;
	next;
      }
      my ($count) = $db->{dbh}->selectrow_array("select count(*) from weak_symbols where baseuorid = ? and symbolid = ? and objid = ?", undef, $symhash->{eid}, $db->getSymbolID($symhash->{name}), $symhash->{eid});
      if (!$count) {
	push @badundefs, $symhash;
      }
    }
  }
  return @badundefs;
}

MAIN:
{

  my $opts = getoptions();
  $| = 1;

  my $csfile = shift @ARGV;
  my $fh;
  open $fh, "<$csfile";
  my $changedata = Binary::Analysis::Tools::load_objset($fh);
  close $fh;

  my $params = {};
  my $arch = $changedata->{objects}[0]{arch};
  $params->{arch} = $arch;
  $params->{instance} = $opts->{instance} if $opts->{instance};
  $params->{dbtype} = $opts->{dbtype} if $opts->{dbtype};
  $params->{arch} = $opts->{arch} if $opts->{arch};
  $params->{debug} = $opts->{debug} if $opts->{debug};

  my $logfile = llog::open_logfile($changedata->{csid});
  my @file_list;

  my $db = Binary::Analysis->new($params);
  if ($db->{dbtype} eq 'informix') {
    $db->{dbh}->do("set isolation to dirty read");
  }

  # Run through all the 'free' libraries we get, which is platform specific
  my @syslibs;
  if ($db->{arch} == 1) {
    @syslibs = qw(c C Crun m);
  } elsif ($db->{arch} == 2) {
    @syslibs = qw(c C Crun m nsl pthreads);
    # The 'magic' symbols the AIX kernel just provides as a gimmie
    push @free_libs, $db->getEntityID("Magic::aixkernel");
  }
  foreach my $syslib (@syslibs) {
    my $libid = $db->getEntityID("Library::$syslib");
    if ($libid) {
      push @free_libs, $libid;
    }
  }

#  $db->{dbh}->do("set explain on");
  $logfile->log_verbose("Starting");

  # Iterate through the files and see what's there to see.
  foreach my $file (@{$changedata->{objects}}) {
    my $lib = $file->{lib};
    next unless $lib;
    if (isApplication($lib) ||
	getCachedGroupOrIsolatedPackage($lib)->isOfflineOnly()) {
      $logfile->log_verbose("Skipping file $file->{source}, for offline lib or application");
    } else {
      push @file_list, $file;
      $logfile->log_verbose("Lib $lib for file $file->{source}\n");
    }
  }

  # Get us a private version of the libraries to work from
  $db->makeTempSnapshot($changedata->{ctime});
  $logfile->log_verbose("Snapshot done");

  $| = 1;

  # Go see what symbols have been added and removed on a per-file
  # basis.
  my (%def_added, %def_removed, %def_duplicated, $objids,
      %existing_undefs, %undef_added, %undef_removed, @def_dupes,
      %csprovides);
  debug("Looking for duplicates\n");
  $logfile->log_verbose("Processing files");
  my $o_cache = {};
  {
    my (%base_objs, %nukeobjs);
    my $o_count = 0;
    foreach my $obj_file (@file_list) {
      $o_count++;
      my $lib = $obj_file->{lib};
      my $uor = $db->getEntityID($lib);

      my $bin_obj = load_o_file_cached($db, $obj_file, $lib, $o_cache, $logfile);
      debug("Examining $obj_file for symbols\n");

      my (%new_def, %new_undef, %old_def, %old_undef);
      # Get all the new defineds and undefined
      my @defs;
      if (defined $bin_obj->{defs}) {
	@defs = @{$bin_obj->{defs}};
	# Record that the changeset provides this
	foreach my $def (@defs) {
	  $csprovides{$lib}{$def->{name}}++;
	}
      } else {
	@defs = ();
      }
      $logfile->log_verbose("found defs in $bin_obj->{dest}:\n  ", join("\n  ", map {$_->{name}} @defs));
      $logfile->log_verbose("New defs: ".join(" ", map {$_->{name}} @defs)."\n");
      @new_def{map {$_->{name}} @defs} = @defs;

      if (defined $bin_obj->{undefs}) {
	@defs = @{$bin_obj->{undefs}};
      } else {
	@defs = ();
      }
      $logfile->log_verbose("found undefs in $bin_obj->{dest}:\n  ", join("\n  ", map {$_->{name}} @defs));
      $logfile->log_verbose("New undefs: ".join(" ", map {$_->{name}} @defs)."\n");
      @new_undef{map {$_->{name}} @defs} = @defs;
      my (@old_o) = (split_o_files($obj_file->{source}));
      debug("Looking at old o files " . join(" ", @old_o));
      foreach my $base_o (@old_o) {
	$logfile->log_verbose("looking for old .o file $base_o for lib $lib");

	my $o_name = $base_o;
	$o_name =~ s/^.*\///;
	$o_name =~ s/\.sundev1//;

	@defs = $db->getTempSymbolsForObject($o_name, $lib, 'T');
	$logfile->log_verbose("Old defs: ".join(" ", @defs)."\n");
	@old_def{@defs} = map {{archive => $lib,
				 object => $o_name,
				 name => $_,
				 LongName => $lib.'['.$o_name.']:'.$_,
				 type => 'T'
				    } } @defs;
	@defs = $db->getTempSymbolsForObject($o_name, $lib, 'D');
	$logfile->log_verbose("Old defs: ".join(" ", @defs)."\n");
	@old_def{@defs} = map {{archive => $lib,
				 object => $o_name,
				 name => $_,
				 LongName => $lib.'['.$o_name.']:'.$_,
				 type => 'D'
			       } } @defs;
	@defs = $db->getTempUndefinedSymbolsForObject($o_name, $lib);
	$logfile->log_verbose("Old undefs: ".join(" ", @defs)."\n");
	@old_undef{@defs} = map {{archive => $lib,
				   object => $o_name,
				   name => $_,
				   type => 'U',
				   LongName => $lib.'['.$o_name.']:'.$_,
				  } } @defs;
	$logfile->log_verbose("deleting $uor/$lib/$o_name");
	push @{$nukeobjs{$lib}}, $o_name;
      }
      foreach my $sym (keys %new_def) {
	if (exists $old_def{$sym}) {
	  delete $old_def{$sym};
	}
      }
      foreach my $sym (keys %new_def) {
	# If it's a dupe, remember that
	if (exists $def_added{$sym}) {
	  push @{$def_duplicated{$sym}}, @{$def_added{$sym}}, $new_def{$sym};
	}
	push @{$def_added{$sym}}, $new_def{$sym};
      }
      foreach my $sym (keys %old_def) {
	debug("Adding removed symbol ".$old_def{$sym}."\n");
	push @{$def_removed{$sym}}, $old_def{$sym};
      }

      foreach my $sym (keys %new_undef) {
	if (exists $old_undef{$sym}) {
	  delete $old_undef{$sym}; delete $new_undef{$sym};
	}
      }
      foreach my $sym (keys %new_undef) {
	push @{$undef_added{$sym}},  $new_undef{$sym};
      }
      foreach my $sym (keys %old_undef) {
	debug("Adding removed undef ".$old_undef{$sym}."\n");
	push @{$undef_removed{$sym}}, $old_undef{$sym};
      }

    }
    foreach my $lib (keys %nukeobjs) {
      $logfile->log_verbose("Cleaning out objects for $lib");
      $db->deleteTempObjects($lib, @{$nukeobjs{$lib}});
    }
  }

  $logfile->log_verbose("there are ", scalar keys %def_added, " defs added\n");

  # At this point the temporary lib snapshot has none of the object
  # files that are in our changeset.
  $logfile->log_verbose("Checking multidefs");

  my (@multiply_defined, @to_check);
 MDLOOP:
  # First strip out RTTI and vtbl entries, as well as data
  # symbols. Those are all OK to be duplicated.
  foreach my $sym (keys %def_added) {
    next if $sym =~ /__RTTI__/;
    next if $sym =~ /__vtbl_$/;
    foreach my $symobj (@{$def_added{$sym}}) {
      next MDLOOP if $symobj->{type} eq 'D';
      next MDLOOP if $symobj->{type} eq 'B';
    }
    push @to_check, $sym;
  }

  my $have_main;
  $have_main = 1 if (exists $def_added{main} || exists $def_added{'.main'});

  # Take our list of symbols and see if any are already provided in
  # the hierarchy. If so... that's bad.
  $logfile->log_verbose("Pruned data syms and rtti/vtbl");
  foreach my $sym (multiDef($db, $logfile, @to_check)) {
    $logfile->log_verbose("Found multiply defined symbol $sym->[1]/$sym->[0] (",
		  join(" ", map {$_->{LongName}} @{$def_added{$sym->[0]}}),
		  ")\n");
    push @multiply_defined, [$sym, $def_added{$sym->[0]}, 'library'];
  }

  # Check to see if the changeset conflicts with itself. Which can
  # happen, especially when we're handed files that've been recompiled
  # because of FindInc and the like.
  $logfile->log_verbose("Checking in-changeset multidefs");
  foreach my $sym (keys %def_duplicated) {
    # Skip data syms
    next if $def_duplicated{$sym}[0]->{type} eq 'D';
    # Lots of things are B for AIX
    next if $def_duplicated{$sym}[0]->{type} eq 'B';
    $logfile->log_verbose("Found multiply defined symbol $sym in-changeset");
    push @multiply_defined, [undef, $def_duplicated{$sym}, 'changeset'];
  }

  # Trim out the undefs that're provided by other defs in this
  # changeset in the same library. Which is sub-optimal, but we deal.
  {
    my %new_undef_added;
    foreach my $undef (values %undef_added) {
    SYMLOOP:
      foreach my $sym (@$undef) {
	# Skip if it's found
	next if ($csprovides{$sym->{archive}}{$sym->{name}});
	# In a child?
	foreach my $child ($db->findChildren($sym->{archive})) {
	  next SYMLOOP if $csprovides{$child}{$sym->{name}};
	}
	# Otherwise we save it
	push @{$new_undef_added{$sym->{name}}}, $sym;
      }
    }
    %undef_added = %new_undef_added;
  }

  # Do the initial building of the table of undefs. We use this table
  # for a number of things, since it's fastest (theoretically) to let
  # the db engine handle it all.
  $logfile->log_verbose("Sending up undefs");
  buildUndefTable($db, map {@{$undef_added{$_}}} keys %undef_added);


  # Look for undefs that just aren't anywhere in the libraries, and
  # complain. There are no weak overrides for this. There possibly
  # should be, as we don't necessarily see symbols provided by
  # top-level .o files.
  $logfile->log_verbose("Checking unprovided undefs");
  my (@undefs);
  @undefs = notProvidedUndefs($db, $logfile, grep {!exists $def_added{$_}} keys %undef_added);
  if (@undefs) {
    $logfile->log_verbose("The following undefs don't exist: ", join(" ", @undefs));
  }
  {
    my @tempundef;
    foreach my $undef (@undefs) {
      push @tempundef, @{$undef_added{$undef}};
      delete $undef_added{$undef};
    }
    @undefs = @tempundef;
  }
#  @undefs = map {@$_} values %undef_added;

  # Check to find the undefs that aren't provided by declared
  # dependencies for the various libraries.
  $logfile->log_verbose("Checking hierarchy undefs");
  my (@h_undefs) = notProvidedChildUndefs($db, keys %undef_added);
  if (@h_undefs) {
    # If strong dependencies didn't give us our undefs, are there weak
    # declarations?
    @h_undefs = filterWeakOK($db, \@h_undefs, \%undef_added);
    if (@h_undefs) {
      $logfile->log_verbose("The following undefs violate the hierarchy: ", join("\n", map {$_->{LongName}} @h_undefs));
      # Check here to see if libraries with violations are fatal or
      # not. 
      my %libs;
      foreach my $sym (@h_undefs) {
	if ($db->hasAttribute($sym->{archive}, 'hardvalidation')) {
	  $sym->{harderror}++;
	}
      }
    }
  }

  # Here we go and take the removed symbols and see if anything is
  # still providing them. If they're multiply defined with stuff in
  # the libraries, then we're fine.
  $logfile->log_verbose("Checking for removed still provided");
  my (@stillOK) = multiDef($db, keys %def_removed);
  foreach my $sym (@stillOK) {
    # Clean out anything in the removed list that's still provided
    delete $def_removed{$sym->[0]};
  }

  # Anything left in the removed hash is 
  my @stillused = stillUsed($db, keys %def_removed);
  if (@stillused) {
    $logfile->log_verbose("The following symbols were removed but still used:\n ", join(" ", @stillused));
    @stillused = map { @{$def_removed{$_}}} @stillused;
  }

  my $status = final_report($db, $logfile, \@multiply_defined, \@undefs, \@h_undefs, \@stillused, $have_main);

  cleanup($db);
  $logfile->log_verbose("Done");
  exit $status;
}
