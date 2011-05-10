# Symbol analysis base class. Manages the backing database
#

#
# XXXXXXXXX IMPORTANT XXXXXXXX
#

package Binary::Analysis;
use strict;
use FindBin;
use Carp;

use DBI;
use BDE::Package;
use BDE::FileSystem;
use BDE::FileSystem::MultiFinder;
use BDE::Util::Nomenclature qw(isApplication isFunction getCanonicalUOR isGroup
			       isIsolatedPackage isPackage);
use BDE::Util::DependencyCache qw(getGroupDependencies getPackageDependencies
				  getCachedGroupOrIsolatedPackage
				  getCachedPackage getCachedGroup);
use BDE::Group;
#use Binary::Archive;
#use Binary::Object;
use Binary::Analysis::Files;
use Build::Option::Factory;
use Build::Option::Finder;
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use Symbols qw(DEFAULT_FILESYSTEM_ROOT FILESYSTEM_PATH_ONLY
	       FILESYSTEM_NO_DEFAULT CONSTANT_PATH);
use Production::Symbols qw(VALIDATION_HOST);

use Date::Parse;

use Binary::Analysis::Utils;
use Binary::Analysis::Tools;

use Cwd;

use Digest::MD5 qw(md5_hex);

#use Util::Message qw(debug);

use Util::File::Basename qw(dirname basename);

our (@pathlist);
my $plink_arch = $^O eq "aix" ? "ibm" : "sundev1";

our %pathtrans;
%pathtrans = ('/bb/source/lib' => '/bbs/lib',
	       '/bb/source/stage/stagelib' => '/bbs/stage/stagelib',
	       );

# Some common aliases
my %branchalias = (monbf => 'bugf',
		     emove => 'emov',
		     bugfix => 'bugf',
		     mov => 'move',
		    );

#==============================================================================

=head1 NAME

Binary::Analysis - Create, manage, and analyze the binary parts of BDE-compliant libraries

=head1 SYNOPSIS

  use Binary::Analysis;
  my $db = new Binary::Analysis;
  # Find all the declared children of acclib
  my (@children) = $db->findChildren('acclib');
  # Find all the symbols in the first declared dependency of acclib
  # that acclib uses
  my (@syms) = $db->getLinkedSymbols('acclib', $children[0]);

=head1 DESCRIPTION

=cut

# Code to set things up so the library search path is properly
# initialized and everything for when we're running.
#INIT {
  BDE::Util::DependencyCache::setFileSystemRoot(BDE::FileSystem::MultiFinder->new(CONSTANT_PATH));
  initLibrarySearchPaths();
#}

=item $obj = new([{parameters}])

Creates a new connection to the analysis database. The following
parameters can be passed in:

=over 4

=item cache_mode => (readonly | strict_timestamp | objectoverides | refreshonce | onlymissing | nosymbols)

Set the way that the backing database cache is managed. If set to
C<readonly> then this connection to the database won't make any
updates. (Though other users connected to the same database may make
changes)

If set to C<strict_timestamp> then the cache will always be updated
based on file times.

If set to C<objectoverrides> then if an object is registered with the
data store that its contents always is used instead of the data from
the same object in a library even if the library has been updated more
recently than the object file.

If set to C<refreshonce> then each thing in the database will be
checked only once to see if it has been updated.

If set to C<onlymissing>, the cache will attempt to load in any
packages or groups that are not already cached, but will leave
anything in the cache alone.

If set to C<nosymbols> the cache won't look for or scan object files
or archives for units of release.

C<onlymissing> is the default mode of operation.

=item instance => <instancename>

Change the instance of the backing database that we're using

=item ufid => ufid

Set the ufid that will be used, instead of the default C<dbg_exc_mt>

=item uplid_root => <root>

Set the filesystem root for UPLID resolution instead of the default

=item fs_root => <root>

Set the root to be used by L<BDE::FileSystem::MultiFinder>, instead of
the default.

=item debug => <level>

Set debugging to C<level>. At the moment, any value will have the code
emit debugging messages, and messages are supressed by default.

=back

=cut

sub new {
  my ($class, $opts) = @_;
  my $self = {};

  bless $self, $class;
  $opts->{instance} = 'newvalid'                  unless $opts->{instance};
  $opts->{ufid} = 'dbg_exc_mt'                    unless $opts->{ufid};
  $opts->{uplid_root} = CONSTANT_PATH   unless $opts->{uplid_root};
  $opts->{cache_mode} = 'only_missing'            unless $opts->{cache_mode};
  $opts->{fs_root} = CONSTANT_PATH      unless $opts->{fs_root};
  $opts->{debug} = 0                              unless $opts->{debug};
  $opts->{buildtag} = 'source'                    unless $opts->{buildtag};
  $opts->{dbtype} = 'postgres'                    unless $opts->{dbtype};
  $opts->{autocommit} = 0                         unless $opts->{autocommit};
  $opts->{basebranch} = 0                         unless $opts->{basebranch};
  $opts->{port} = 5432                            unless $opts->{port};
  $opts->{host} = VALIDATION_HOST                 unless $opts->{host};
  $opts->{dbuser} = 'performance'                 unless $opts->{performance};
  $opts->{dbpass} = 'performance'                 unless $opts->{dbpass};
  $opts->{movetype} = 'move'                      unless $opts->{movetype};

  $SIG{__WARN__} = sub { confess } if $opts->{debug};

  my (%branchids) = (source => 0,
 		       stage => -1,
		       local => -2);

  my (%moveids) = (move => 3,
		    bugf => 2,
		    emov => 1);
  $opts->{moveid} = $moveids{$opts->{movetype}} unless $opts->{moveid};

  $opts->{basebranch} = $branchids{$opts->{buildtag}} unless $opts->{basebranch};
  $opts->{basebranch} ||= 0;
  my (%archid) = (solaris => 1,
		   sunos => 1,
		   sun => 1,
		   sundev1 => 1,
		   '.sundev1' => 1,
		   aix => 2,
		   ibm => 2,
		 );
  if ($opts->{arch}) {
    # If we got a number we'll just use it, otherwise we look things up
    if ($opts->{arch} !~ /^\d+$/) {
      $opts->{arch} = $archid{lc $opts->{arch}};
    }
  } else {
    $opts->{arch} = $archid{lc $^O};
  }

  # Copy the settings
  %$self = %$opts;

  $self->debug("base is ".$opts->{buildtag}, ", branchid is ", $opts->{basebranch}." arch is " . $opts->{arch} . " moveid is " . $opts->{moveid} . "\n");
  # Open the db
  $self->{dbh} = $self->openDB();

  # Yes, we want sizes
  {
    no warnings 'once';
    $Binary::Symbol::Scanner::do_size = 1;
  }

  # Get a root to the filesystem
  $self->{root} = new BDE::FileSystem::MultiFinder($self->{fs_root});
  if ($self->{fs_root} eq CONSTANT_PATH) {
    $self->{root}->setSearchMode(FILESYSTEM_PATH_ONLY|FILESYSTEM_NO_DEFAULT);
  }

  # Right, we don't want to retry. Either the files exist, or they
  # don't, and we just don't care about NFS wonkiness.
  {
    no warnings 'once';
    $BDE::Utility::Retry::ATTEMPTS = 1;
    $BDE::Utility::Retry::PAUSE = 1;
  }

  # Set up our factory and uplid/ufid stuff
  $self->{factory} = new Build::Option::Factory;
  $self->{factory}->setFinder(new Build::Option::Finder($self->{root}));
  $self->{factory}->setDefaultUplid(new BDE::Build::Uplid({where => $self->{uplid_root}}));
  $self->{factory}->setDefaultUfid(new BDE::Build::Ufid($self->{ufid}));

  $self->{refreshed} = {};
  $self->{archive_cache} = {};

  # Add the stage/source/local path to our path
  addTypeSearchPath($self->{buildtag});


  # Return us
  return $self;
}


# Open up the analysis database, creating it if it doesn't already
# exist.
#
# Returns a handle on the database necessary for any other operation.

sub openDB {
  my ($self) = @_;
  my $db_name = $self->{instance};
  my $handle;

  if ($self->{dbtype} eq 'informix') {
    eval {
      $handle = DBI->connect("dbi:Informix:validtdb\@devadsp", "", "", {AutoCommit => $self->{autocommit}});
    };
    if ($@) {
      confess $@;
    }
    $handle->do("set lock mode to wait");
    $handle->do("set buffered log");
  } else {
    my $host = $self->{host};
    my $port = $self->{port};
    $self->debug("Connecting to $host, port $port, user $self->{dbuser} database $db_name\n");
    $handle = DBI->connect("dbi:Pg:dbname=$db_name;host=$host;port=$port",
			   $self->{dbuser},$self->{dbpass},
			   {AutoCommit => 0});
    $handle->do("set temp_buffers=10000");
  }
  $handle->{HandleError} = sub { confess(shift) };
  $handle->{RaiseError} = 1;

  $self->{sth}{insert_into_symbols} = $handle->prepare("insert into symbols (symbolname, fullsymbolname, symbolhash,demangledname) values (?,?,?,?)");
  $self->{need_symfix} = 0;
  $self->{need_idfix} = 0;

  return $handle;
}

sub DESTROY {
  my $self = shift;
  $self->closeDB if defined $self->{dbh};
}

=item closeDB()

Close the analysis database. Releases any outstanding locks and aborts
any pending transactions. This I<will>, regardless of the underlying
database used, roll back any open transaction.

=cut
sub closeDB {
  my ($self) = @_;
  # It's possible this may fail if the handle's really whacked, so we wrap it
  eval {
    $self->{dbh}->rollback;
  };
  foreach my $sth (keys %{$self->{sth}}) {
    $self->{sth}{$sth}->DESTROY if defined($self->{sth}{$sth});
    $self->{sth}{$sth} = undef;
  }
  $self->{sth} = undef;
  {
    $self->{dbh}{PrintError} = 0;
    $self->{dbh}{PrintWarn} = 0;
    $self->{dbh}{Warn} = 0;
    local $^W =undef;
    local $SIG{__WARN__} = sub { return; };
    $self->{dbh}->disconnect;
  }
  $self->{dbh} = undef;
}

=item debug(@message)

Emit the message pieces if debugging's enabled.

=cut

sub debug {
  my ($self, @message) = @_;
  if ($self->{debug}) {
    local $| = 1;
    print @message;
  }
}

sub debug_stamp {
  my ($self, @message) = @_;
  if ($self->{debug}) {
    local $| = 1;
    $self->debug(time, " ", @message);
  }
}

=item commit

Commit any outstanding changes to the database so they become permanent.

=cut
sub commit {
  my ($self) = shift;
  if ($self->{need_symfix}) {
    $self->_flush_symbols();
  }
  if ($self->{need_idfix}) {
    $self->_flush_ids();
  }
  $self->{dbh}->commit() unless $self->{autocommit};
}


sub rollback {
  my ($self) = shift;
  $self->{need_symfix} = 0;
  $self->{pendingsyms} = undef;
  $self->{need_idfix} = 0;
  $self->{pendingids} = undef;
  $self->{temptablepending} = undef;
  $self->{dbh}->rollback;
}

sub addBareObject {
  my ($self, $objname, $objpath, $uor) = @_;
  if (!defined $objpath) {
    if (-e $objname) {
      $objpath = getcwd();
    } else {
      die "Can't find object";
    }
  }
  my $fullname;
  if (! ($objpath =~ m|/$|)) {
    $fullname = $objpath . '/' . $objname;
  } else {
    $fullname = $objpath . $objname;
  }

  my ($objdate, $objsize) = (stat $fullname)[9,7];
  die "Object $fullname doesn't exist" unless $objdate && $objsize;

  my $obj = Binary::Analysis::Files::Object->new($fullname);
  my $objid = $self->addObject($objname, $objpath);
  if (!$objid) {
    confess("No object id for $objname $objpath $fullname");
  }


  $self->debug("Object $objname ($objpath) id: $objid, size: $objsize\n");
  my ($objinstance) = $self->addObjectInstance($objid, $obj, $objdate, undef, $objsize);

  if ($self->{copy_in_progress}) {
    $self->{dbh}->pg_endcopy;
    $self->{copy_in_progress} = 0;
  }

  return ($objid, $objinstance);
}




sub addObject {
  my ($self, $objname, $objpath) = @_;
  $objpath = '' if not defined $objpath;
  my $objid = $self->getObjectID($objname, $objpath);
  if (!$objid) {
    $self->{dbh}->do("insert into objects (objectname, directory) values (?,?)", undef, $objname, $objpath);
  }
  $objid = $self->getObjectID($objname, $objpath);
  return $objid;
}



sub addObjectInstance {
  my ($self, $objid, $objobj, $date, $csid, $size) = @_;
  $size ||= 0;
  my $objinstance = $self->getObjectInstance($objid, $date);
  return ($objinstance, 0, 0, 0) if $objinstance;
  if (defined $objobj && $objobj->can("getSize")) {
    $size = $objobj->getSize;
  }

  $self->{dbh}->do("insert into objectinstance (objid, objectsize, csid, objectdate, general_use, architecture) values (?,?,?,?,?,?)", undef, $objid, $size, $csid, $date, 1, $self->{arch});
  $objinstance = $self->getObjectInstance($objid, $date);
  my ($defs, $undefs);
  if (defined $objobj) {
    ($defs, $undefs) = $self->addSymbols($objinstance, $objobj->getSymbols);
    if ($objobj->can("getIDs")) {
      $self->addIDs($objinstance, $objobj->getIDs)
    }
  }
  return($objinstance, 1, $defs||0, $undefs||0);
}

sub getObjectInstance {
  my ($self, $objid, $date) = @_;
  my (@row) = $self->{dbh}->selectrow_array("select objinstance from objectinstance where objectdate = ?  and objid = ? and architecture = ?", undef, $date, $objid, $self->{arch});
  return $row[0];
}

sub cacheLoadObjectName {
  my ($self, @objids) = @_;
  my $quest = join(", ", map {'?'} @objids);
  my $rows = $self->{dbh}->selectall_arrayref("select objid, objectname from objects where objid in ($quest)", undef, @objids);
  foreach my $row (@$rows) {
    $self->{cache}{objname}{$row->[0]} = $row->[1];
  }
}

sub cacheLoadSymbolID {
  my ($self, @symnames) = @_;
  return unless @symnames;
  my $quest = join(", ", map {'?'} @symnames);
  my $sql = "select symbolid, fullsymbolname from symbols where symbolhash in ($quest)";
  my $rows = $self->{dbh}->selectall_arrayref($sql, undef, map {md5_hex($_)} @symnames);
  foreach my $row (@$rows) {
    my $symname = $row->[1];
    $symname =~ s/\s+$//;
    $self->{cache}{symbolid}{$symname} = $row->[0];
  }
}


sub getObjectID {
  my ($self, $objname, $path) = @_;
  my @row;
  if (defined $path && $path ne '') {
    if (defined $self->{cache}{objid}{$path}{$objname}) {
      return $self->{cache}{objid}{$path}{$objname};
    }
    (@row) = $self->{dbh}->selectrow_array("select objid from objects where objectname = ? and directory = ?", undef, $objname, $path);
    $self->{cache}{objid}{$path}{$objname} = $row[0];
  } else {
    if (defined $self->{cache}{objid}{'.'}{$objname}) {
      return $self->{cache}{objid}{'.'}{$objname};
    }
    (@row) = $self->{dbh}->selectrow_array("select objid from objects where objectname = ? and directory = ''", undef, $objname);
    $self->{cache}{objid}{'.'}{$objname} = $row[0];
  }
  return $row[0];
}

sub getObjectName {
  my ($self, $objid) = @_;

  return unless $objid;

  if (defined $self->{cache}{objname}{$objid}) {
    return $self->{cache}{objname}{$objid};
  }

  my ($objname) = $self->{dbh}->selectrow_array("select objectname from objects where objid = ?", undef, $objid);
  $self->{cache}{objname}{$objid} = $objname;
  return $objname;
}

sub getCSID {
  my ($self, $objinstance) = @_;
  return "" unless $objinstance;
  my ($csid) = $self->{dbh}->selectrow_array("select csid from objectinstance where objinstance = ?", undef, $objinstance);
  $csid ||= "";
  return $csid;
}

sub addThing {
  my ($self, $thing) = @_;
  my ($thingloc, $thingtype);
  return unless defined $thing;
  $self->debug("addThing: considering $thing\n");
    $thing = getCanonicalUOR($thing);
    return unless defined $thing;
    return if $thing =~ /phantoms\b/;

    # Try getting it as a package
    if (isApplication($thing)) {
      $self->addOffline($thing);
    }
    if (isGroup($thing)) {
      $thingtype = 'group';
    }

    if (isIsolatedPackage($thing)) {
      $thingtype = 'isolatedpackage';
    }

    if (isPackage($thing)) {
      $thingtype = 'package';
    }

    if ($thingtype eq 'group') {
      $self->addGroup($thing);
    } else {
      my $package = getCachedPackage($thing);
      my $group = $package->getGroup();
      if ($group) {
	$self->addGroup($group);
      } else {
	$self->addPackage($thing);
      }
    }
}

sub addOffline {
  my ($self, $name, $id) = @_;

  # Skip out if we've done this already
  if ($self->{cache_mode} eq 'refreshonce') {
    if (exists $self->{refreshed}{$name}) {
      return;
    }
    $self->{refreshed}{$name}++;
  }

  # Get a package object and bail if there was a problem
  my ($offline);
#  eval {
    $offline = getCachedGroupOrIsolatedPackage($name);
# };
#  if ($@) {
#    print "Error $@ adding $name\n";
#    return;
#  }

  # Does it exist? If we can find an ID, it does
  my ($offline_exists) = $self->{dbh}->selectrow_array("select offlineid from offlines where offlinename = ?", undef, $name);
  $id = $self->getEntityID($name) unless $id;
  if (!$id) {
    $self->debug("Adding offline $name", "\n");
    $id = $self->addEntity($name);
  }
  if (!$offline_exists) {
    $self->{dbh}->do("insert into offlines (offlinename, offlineid, createdate) values (?,?,?)", undef, $name, $id, time);
  }

  $self->addUOR($name, $offline);

  # Right, we may have a makefile. Go parse it. (Currently disabled)
  if (0) {
    my $appdir = dirname($self->{root}->getApplicationMemFilename($name));
    $self->debug("$name Appdir is $appdir for " . $self->{root}->getApplicationMemFilename($name) . "\n");
    $appdir =~ s|package/?$||;
    $appdir =~ s|/$||;
    my $apptail; $appdir =~ m|([^/]+)$|; $apptail = $1;
    $apptail =~ s/^m_//;
  MAKELOOP:
    foreach my $suffix ('.mk', '.mk,v') {
      foreach my $prefix ('', 'm_') {
	$self->debug("Looking for " . $appdir . '/' . $prefix . $apptail . $suffix . "\n");
	if (-e $appdir . '/' . $prefix . $apptail . $suffix) {
	  $self->debug("Adding " . $appdir . '/' . $prefix . $apptail . $suffix);
	  $self->addApplication($name, $prefix . $apptail . $suffix, $appdir);
	  last MAKELOOP;
	}
      }
    }
  }

}

sub addPackage {
  my ($self, $name, $id) = @_;

  # Skip out if we've done this already
  if ($self->{cache_mode} eq 'refreshonce') {
    if (exists $self->{refreshed}{$name}) {
      return;
    }
    $self->{refreshed}{$name}++;
  }

  # Get a package object and bail if there was a problem
  my ($package);
#  eval {
    $package = getCachedPackage($name);
# };
#  if ($@) {
#    print "Error $@ adding $name\n";
#    return;
#  }

  # Does it exist? If we can find an ID, it does
  my ($package_exists) = $self->{dbh}->selectrow_array("select packageid from packages where packagename = ?", undef, $name);
  my $packagetype = isIsolatedPackage($name) ? 'isolatedpackage' : 'package';
  $id = $self->getEntityID($name, $packagetype) unless $id;
  if (!$id) {
    $self->debug("Adding package $name", "\n");
    $id = $self->addEntity($name);
  }
  if (!$package_exists) {
    $self->{dbh}->do("insert into packages (packagename, packageid, packagetype, createdate) values (?,?,?,?)", undef, $name, $id, $packagetype, time);
  }

  if (isIsolatedPackage($name)) {
    my $fallback = $self->{root}->getPackageLocation($name);
    $fallback = "$fallback/lib$name"; # Stick in the potential fallback
    $self->addUOR($name, $package, $fallback);
  }
}

sub addGroup {
  my ($self, $name, $id) = @_;

  # Skip out if we've done this already
  if ($self->{cache_mode} eq 'refreshonce') {
    if (exists $self->{refreshed}{$name}) {
      return;
    }
    $self->{refreshed}{$name}++;
  }

  # Get a package object and bail if there was a problem
  my ($group);
#  eval {
    $group = getCachedGroup($name);
# };
  if ($@) {
    print "Error $@ adding $name\n";
    return;
  }

  # Does it exist? If we can find an ID, it does
  my ($group_exists) = $self->{dbh}->selectrow_array("select groupid from groups where groupname = ?", undef, $name);
  $id = $self->getEntityID($name, 'group') unless $id;
  if (!$id) {
    $self->debug("Adding package $name", "\n");
    $id = $self->addEntity($name);
  }
  if (!$group_exists) {
    $self->{dbh}->do("insert into groups (groupname, groupid, createdate) values (?,?,?)", undef, $name, $id, time);
  }

  # Unconditionally recreate the groups file. We really ought not do this
  $self->{dbh}->do("delete from group_members where groupid = ?", undef, $id);
  my %seen;
  foreach my $package ($group->getMembers()) {
    next if $seen{$package}++;
    $self->addPackage($package);
    my $packageid = $self->getEntityID($package);
    $self->{dbh}->do("insert into group_members (groupid, packageid) values (?,?)", undef, $id, $packageid) if $packageid;
  }

  my $fallback = $self->{root}->getGroupLocation($name);
  $fallback = "$fallback/lib$name"; # Stick in the potential fallback
  $self->addUOR($name, $group, $fallback);
}

sub addLibrary {
  my ($self, $libname, $fullpath, $entityid) = @_;
  my ($dir, $file);
  my ($realdir, $realfile);
  $realdir = dirname($fullpath); $realfile = basename($fullpath);
  if ($fullpath =~ m|bb/csdata/robo/libcache/(\w+)/|) {
    my $where = $1;
    if ($where eq 'source') { $dir = '/bbs/lib' }
    if ($where eq 'stage') { $dir = '/bbs/stage/stagelib' }
    if ($where eq 'local') { $dir = '/local/lib' }
    if ($where eq 'prod') { $dir = '/bbs/stage/prodlib' }
  }
  if (!$dir) {
    $dir = $realdir;
  }
  $file = $realfile;

  $self->{dbh}->do("insert into library (libshortname, libdirectory, libname, architecture, entityid) values (?,?,?,?,?)", undef, $libname, $dir, $file, $self->{arch}, $entityid);
}

# Evil, evil hack to get the physical directory based on the current
# build tag setting
sub getGeneralDirectory {
  my ($self) = @_;
  my $retval;
  if ($self->{basebranch}) {
    $retval = '/bbs/stage/stagelib'
  } else {
    $retval = '/bbs/lib';
  }
  $self->debug("base lib directory is $retval\n");
  return $retval;
}

sub getLibraryID {
  my ($self, $shortname, $physicalname, $static) = @_;

  my $arch = $self->{arch};
  $physicalname ||= '';
  $static = 1 unless defined $static;

  $shortname =~ s/^Library:://;

  if (exists $self->{fakelibs}{$shortname}) {
    return $self->{fakelibs}{$shortname};
  }
  if (exists $self->{cache}{"arch$arch"}{libid}{$static}{$shortname.$physicalname}) {
    return $self->{cache}{"arch$arch"}{libid}{$static}{$shortname.$physicalname};
  }

  my $ordering = ' order by shared ';
  if (!$static) {
    $ordering = ' order by shared DESC ';
  }

  my ($libid, $dir, $file);
  if ($shortname) {
    if ($physicalname) {
      $dir = dirname($physicalname); $file = basename($physicalname);
      ($libid) = $self->{dbh}->selectrow_array("select libid from library where libname = ? and libdirectory = ? and libshortname = ? and architecture = ? $ordering", undef, $file, $dir, $shortname, $arch);
    } else {
      $dir = $self->getGeneralDirectory();
      ($libid) = $self->{dbh}->selectrow_array("select libid from library where libshortname = ? and architecture = ? and libdirectory = ? $ordering", undef, $shortname, $arch, $dir);
	
    }
  } else {
      $dir = dirname($physicalname); $file = basename($physicalname);
      ($libid) = $self->{dbh}->selectrow_array("select libid from library where libname = ? and libdirectory = ? and architecture = ? $ordering", undef, $file, $dir, $arch);
  }

  $self->{cache}{"arch$arch"}{libid}{$static}{$shortname.$physicalname} = $libid if $libid;

  return $libid;
}  

### arch/branch in metadata done to here

sub scanExtraLibraries {
  my ($self, $thing, $uorid) = @_;
  my ($others, $system, $construct, $plinks);
#  eval {
    $construct = $self->{factory}->construct($thing);
    $others = $construct->expandValue(uc($thing).'_OTHER_LIBS');
    $system = $construct->expandValue(uc($thing).'_SYSTEM_LIBS');
#    $plinks = $construct->expandValue('PLINK_OBJS');
#  };
  if ($@) {
    $self->debug("Option factory threw $@\n");
    return;
  }

  my ($arch, $branch) = ($self->{arch}, $self->{basebranch});
  my (@oldpathlist) = @pathlist;
  local @pathlist = @oldpathlist;
  while ($others =~ /\s*-L(?:\s+)?(\S+)/g) {
    unshift @pathlist,$1;
  }
  while ($system =~ /\s*-L(?:\s+)?(\S+)/g) {
    unshift @pathlist,$1;
  }

  my (@extralibs) = $others =~ /\s?-l(?:\s+)?([^\s]+)/g;
  push @extralibs, $system =~ /\s?-l(?:\s+)?([^\s]+)/g;

  my $thingid = $self->getEntityID($thing);

  $self->{dbh}->do("delete from dependencies where fromid = ? and strength = 'extra' and architecture = ? and branchid = ?", undef, $uorid, $arch, $branch);
  $self->{dbh}->do("delete from extra_libs_linkage where uorid = ? and architecture = ? and branchid = ?", undef, $uorid, $arch, $branch);

  my %libcache;
  foreach my $name (@extralibs) {
    next if $libcache{$name}++;
    my $extraid = $self->addExtraLibrary($uorid, undef, $name);
    if ($extraid) {
      $self->{dbh}->do("insert into dependencies (fromid, toid, strength, architecture, branchid) values (?,?,'extra',?,?)", undef, $uorid, $extraid, $arch, $branch);
    }
  }

#  foreach my $plink_obj (split /\s+/, $plinks) {
#    $self->addPlinkObj($plink_obj, $uorid);
#  }

}

sub getSymbolID {
  my ($self, $symbol) = @_;
  if ($self->{cache}{symbolid}{$symbol}) {
    return $self->{cache}{symbolid}{$symbol};
  }
  my ($id) = $self->{dbh}->selectrow_array("select symbolid from symbols where symbolhash = ?", undef, md5_hex($symbol));
  $self->{cache}{symbolid}{$symbol} = $id;
  return $id;
}

sub getSymbolName {
  my ($self, $symid) = @_;
  return $self->{cache}{symid}{$symid} if $self->{cache}{symid}{$symid};
  my ($symname) = $self->{dbh}->selectrow_array("select fullsymbolname from symbols where symbolid = ?", undef, $symid);
  $self->{cache}{symid}{$symid} = $symname;
  return $symname;
}

sub getDemangledSymbolName {
  my ($self, $symid) = @_;
  return $self->{cache}{symdemid}{$symid} if $self->{cache}{symdemid}{$symid};
  my ($symname) = $self->{dbh}->selectrow_array("select demangledname from symbols where symbolid = ?", undef, $symid);
  $self->{cache}{symdemid}{$symid} = $symname;
  return $symname;
}

sub newSymbolID {
  my ($self, $symbol) = @_;
  if (!defined $symbol) {
    use Carp;
    $self->debug(Carp::longmess("Undefined symbol passed into newSymbolID"));
    return;
  }
  my $id = $self->getSymbolID($symbol);
  return $id if $id;
  $self->{sth}{insert_into_symbols}->execute(substr($symbol, 0, 254), $symbol, md5_hex($symbol), Binary::Analysis::Demangle::demangle_sym($symbol));
 ($id) = $self->{dbh}->selectrow_array("select symbolid from symbols where symbolhash = ?", undef, md5_hex($symbol));
  return $id;
}

sub addExtraLibrary {
  my ($self, $uorid, $fullpath, $libname) = @_;

  my $name = 'Library::'.$libname;
  my $entityid = $self->getEntityID($name);
  if (!$entityid) {
    $entityid = $self->addEntity($name);
  }
  if (!$fullpath) {
    $fullpath = $self->figureAbsPath($libname, 0);
    if (!$fullpath) {
      return;
    }
  } else {
    my ($path, $base);
    $path = dirname($fullpath);
    $base = basename($fullpath);
    if ($pathtrans{$path}) {
      $path = $pathtrans{$path};
    }
    $fullpath = $path . '/' . $base;
  }

  my $libid = $self->getLibraryID($libname, $fullpath);
  if (!$libid) {
    $self->addLibrary($libname, $fullpath, $entityid);
    $libid = $self->getLibraryID($libname, $fullpath);
  }

  my ($exists) = $self->{dbh}->selectrow_array("select count(*) from extra_libs where entityid = ?", undef, $entityid);
  if (!$exists) {
    $self->{dbh}->do("insert into extra_libs (entityid, architecture, branchid) values (?,?,?)", undef, $entityid, $self->{arch}, $self->{basebranch});
  }

  if ($uorid) {
#    eval {
    $self->{dbh}->do("delete from  extra_libs_linkage where libid = ? and  uorid = ? and architecture = ? and branchid = ?", undef, $libid, $uorid, $self->{arch}, $self->{basebranch});
    $self->{dbh}->do("insert into extra_libs_linkage (libid, uorid, architecture, branchid) values (?,?,?,?)", undef, $libid, $uorid, $self->{arch}, $self->{basebranch});
#    };
  }

  $self->loadLibrary($libid, $libname, $fullpath, $entityid);
  return $entityid;

}

sub loadLibrary {
  my ($self, $libid, $libname, $fullpath, $entityid) = @_;
  if (!defined $entityid) {
    $self->{dbh}->rollback;
    confess "entityid is undef!";
  }
  my ($libdate, $libsize) = (stat $fullpath)[9,7];

  my ($libinstanceid) = $self->{dbh}->selectrow_array("select libinstanceid from libinstance where libid = ? and libdate = ? and architecture = ? and branchid = ?", undef, $libid, $libdate, $self->{arch}, $self->{basebranch});
  # Does it exist? If so... skip.
  if ($libinstanceid) {
    # Are we cleaning this out?
    if ($self->{libclean}) {
      $self->{dbh}->do("delete from libinstance where libinstanceid = ?", undef, $libinstanceid);
      $libinstanceid = undef;
    } else {
      return;
    }
  }

  my $cksum = $self->_getArchiveChecksum($fullpath);
  
  ($libinstanceid) = $self->{dbh}->selectrow_array("select libinstanceid from libinstance where libid = ? and enddate = 1999999999 and architecture = ? and branchid = ? and checksum = ? and filesize = ?", undef, $libid, $self->{arch}, $self->{basebranch}, $cksum, $libsize);
  if ($libinstanceid) {
    return;
  }

  # Load in the library object
  my (%times);
  $times{start} = time;

  $self->debug("Loading $libname:");
  # Load in the library
  my $libobj = Binary::Analysis::Files::Archive->new($fullpath);

  # Load in the object dates
  $self->_loadObjects($fullpath);

  $times{libload} = time;
  $self->debug(" archive load ". ($times{libload} - $times{start}) . " secs");
  my $enddate = "1999999999";

  my $checkrow = $self->{dbh}->selectall_arrayref("select libdate from libinstance where libid = ? and libdate > ? and architecture = ? and branchid = ? and istemp = 0 order by libdate", undef, $libid, $libdate, $self->{arch}, $self->{basebranch});
  if ($checkrow && @$checkrow) {
    $enddate = $checkrow->[0][0];
  }

  # Add it and fetch the ID it got

  $self->{dbh}->do("insert into libinstance (libid, libdate, entityid, architecture, branchid, checksum, enddate, filesize) values (?,?,?,?,?,?,?,?)", undef, $libid, $libdate, $entityid, $self->{arch}, $self->{basebranch}, $cksum, $enddate, $libsize);
  # Close off any library instance that stretches past this one
  $self->{dbh}->do("update libinstance set enddate = ? where libid = ? and libdate < ? and enddate > ? and architecture = ? and branchid = ? and istemp = 0", undef, $libdate, $libid, $libdate, $libdate, $self->{arch}, $self->{basebranch});
  ($libinstanceid) = $self->{dbh}->selectrow_array("select libinstanceid from libinstance where libid = ? and libdate = ? and architecture = ? and branchid = ? and istemp = 0", undef, $libid, $libdate, $self->{arch}, $self->{basebranch});

  my (@archiveobjects, $objsadded, $defs, $undefs);
  $undefs = 0; $defs = 0; $objsadded = 0;
  @archiveobjects = @{$self->{archive_cache}{$fullpath}{':ordering'}};
  $times{archivescan} = time;

  $self->debug(", ar ".($times{archivescan} - $times{libload}) . " secs");
  my $order = 0;
  $self->{sth}{add_obj_instance} = $self->{dbh}->prepare("insert into libobject (libinstanceid, objinstance, objid, objorder, libid, entityid) values (?,?,?,?,?, ?)",{ix_InsertCursor => 1});

  my ($oldinstanceid) = $self->{dbh}->selectrow_array("select libinstanceid from libinstance where libid = ? and enddate = ? and architecture = ? and branchid = ?", undef, $libid, $libdate, $self->{arch}, $self->{basebranch});
  my $rows;
  if ($oldinstanceid) {
    $rows = $self->{dbh}->selectall_arrayref("select objectname, objectdate, objectsize, libobject.objinstance, objects.objid from objects, libobject, objectinstance where objects.objid = objectinstance.objid and objectinstance.objinstance = libobject.objinstance and libobject.libinstanceid = ?", undef, $oldinstanceid);
  } else {
    $rows = [];
  }
  my %ohash;
  foreach my $row (@$rows) {
    $ohash{$row->[0]} = $row;
  }

  # .so files have 
  if (@archiveobjects) {
    foreach my $objinfo (@archiveobjects) {
      $order++;
      my ($objinstanceid, $propobjinstanceid, $propname, $objid);
      $propobjinstanceid = -1;
      # Did we already find it?
      if (exists $ohash{$objinfo->[0]} && 
	  $ohash{$objinfo->[0]}[1] == $objinfo->[1] &&
	  $ohash{$objinfo->[0]}[2] == $objinfo->[2]) {
	$propobjinstanceid = $ohash{$objinfo->[0]}[3];
	$propname = $objinfo->[0] . "/" . $ohash{$objinfo->[0]}[0];
	$objinstanceid = $propobjinstanceid;
	$objid = $ohash{$objinfo->[0]}[4];
      } else {
	$objid = $self->addObject($objinfo->[0]);
	my ($objobj, $objnew, $objdef, $objundef);
	$objobj = $libobj->getObject($objinfo->[0]);
	($objinstanceid, $objnew, $objdef, $objundef) = 
	  $self->addObjectInstance($objid, $objobj, $objinfo->[1], 
				   undef, $objinfo->[2]);
	if ($objnew) {
	  $objsadded++;
	  $defs += $objdef;
	  $undefs += $objundef;
#	} else {
	  #      print "weird with ", $objinfo->[0], "\n";
#	  next;
	}
      }
      if ($propobjinstanceid != -1 && $propobjinstanceid != $objinstanceid) {
	print "$propobjinstanceid didn't match $objinstanceid $propname\n";
      }
      $self->addObjInstanceToLibInstance($libinstanceid, $objinstanceid, $objid, $order, $libid, $entityid);
    }
  } else {
    foreach my $objobj ($libobj->getObjects()) {
      $order++;
      my $objid = $self->addObject($objobj->getName());

      my ($objinstanceid, $objnew, $objdef, $objundef) =
	$self->addObjectInstance($objid, $objobj, $libdate, undef, -s $fullpath);
      if ($objnew) {
	$objsadded++;
	$defs += $objdef;
	$undefs += $objundef;
      }

      $self->addObjInstanceToLibInstance($libinstanceid, $objinstanceid, $objid, $order, $libid, $entityid);

    }
  }
  $self->{sth}{add_obj_instance}->finish();
  $times{addtodb} = time;

  $self->debug(", db load ". ($times{addtodb} - $times{archivescan}) . " secs");
  $self->debug(", (" . scalar(@archiveobjects) . " objs/$objsadded added/$defs new defs/$undefs new undefs)\n");
#  print "Load time " . ($times{libload} - $times{start}), "\n";
#  print "ar scan time " . ($times{archivescan} - $times{libload}), "\n";
#  print "db load time " . ($times{addtodb} - $times{archivescan}), "\n";

}

sub addObjInstanceToLibInstance {
  my ($self, $libinstance, $objinstance, $objid, $order, $libid, $entityid) = @_;
  if (!defined $entityid) {
    $self->{dbh}->rollback;
    confess "Null entityid!";
  }
  if ($self->{copy_in_progress}) {
    $self->{dbh}->pg_endcopy;
    $self->{copy_in_progress} = 0;
  }
  $self->{sth}{add_obj_instance}->execute($libinstance, $objinstance, $objid, $order, $libid, $entityid);
}

sub getUORDates {
  my ($self, $uorid) = @_;
  my (@dates) = $self->{dbh}->selectrow_array("select mem_date, opt_date, dep_date, defs_date from uor where entityid = ? and architecture = ? and branchid = ?", undef, $uorid, $self->{arch}, $self->{basebranch});
  return @dates;
}

sub addUOR {
  my ($self, $uorname, $uorobj, $potentiallibbase) = @_;
  my $uorid = $self->getEntityID($uorname);
  if (!$uorid) {
    $uorid = $self->addEntity($uorname);
  }
  my (@rows) = $self->{dbh}->selectrow_array("select entityid from uor where entityid = ? and architecture = ? and branchid = ?", undef, $uorid, $self->{arch}, $self->{basebranch});
  if (!@rows) {
    $self->{dbh}->do("insert into uor (entityid, architecture, branchid) values (?,?,?)", undef, $uorid, $self->{arch}, $self->{basebranch});
  }

  # Check for library changes
  if (!isApplication($uorname)) {
    my $libpath = $self->figureAbsPath($uorname, 0, $potentiallibbase);
    #  return unless $libpath;
    if ($libpath) {
      my $libid = $self->getLibraryID($uorname, $libpath);
      if (!$libid) {
	$self->addLibrary($uorname, $libpath, $uorid);
	$libid = $self->getLibraryID($uorname, $libpath);
	if (!defined $libid) {
	  confess "looking for libid with $uorname $libpath";
	}
	#    $self->{dbh}->do("update uor set libid = ? where entityid = ?", undef, $libid, $uorid);
      }
      # Load up the library, creating a new instance of it if we need
      $self->loadLibrary($libid, $uorname, $libpath, $uorid);

      # Are we throwing integrity to the wind?
      if ($self->{commit_piecemeal}) {
	$self->commit();
      }
    }
  }

  my ($memdate, $optdate, $depdate, $defsdate) = $self->getUORDates($uorid);
  $memdate += 0;
  $optdate += 0;
  $depdate += 0;
  $defsdate += 0;

  my $memfile;
  if (isGroup($uorname)) {
    $memfile = $self->{root}->getGroupMemFilename($uorname);
  } else {
    if (isApplication($uorname)) {
      $memfile = $self->{root}->getApplicationMemFilename($uorname);
    } else {
      $memfile = $self->{root}->getPackageMemFilename($uorname);
    }
  }

  my $basefile = $memfile;
  $basefile =~ s/\.mem$//;

  my ($memfiledate, $optsfiledate, $depfiledate, $defsfiledate);
  $memfiledate = (stat $basefile.'.mem')[9] || 0;
  $optsfiledate = (stat $basefile.'.opts')[9] || 0;
  $depfiledate = (stat $basefile.'.dep')[9] || 0;
  $defsfiledate = (stat $basefile.'.defs')[9] || 0;
  $self->{dbh}->do("update uor set opt_date = ?, mem_date = ?, dep_date = ?, defs_date = ?, opt_name = ?, mem_name = ?, dep_name = ?, defs_name = ? where entityid = ? and architecture = ? and branchid = ?", undef, $optsfiledate, $memfiledate, $depfiledate, $defsfiledate, $basefile.'.opts', $basefile.'.mem', $basefile.'.dep', $basefile.'.defs', $uorid, $self->{arch}, $self->{basebranch});

  # Should we redo dependencies?
  if ($depdate < $depfiledate) {
    # Strong dependencies first
    my (@dependencies) = sort $uorobj->getStrongDependants();
    $self->{dbh}->do("delete from dependencies where fromid = ? and strength = 'weak' and architecture = ? and branchid = ?", undef, $uorid, $self->{arch}, $self->{basebranch});
    $self->{dbh}->do("delete from dependencies where fromid = ? and strength = 'strong' and architecture = ? and branchid = ?", undef, $uorid, $self->{arch}, $self->{basebranch});
    foreach my $dependant (@dependencies) {
      my $depid = $self->getEntityID($dependant);
      # Does it exist?
      if (!$depid) {
	$self->addThing($dependant);
	$depid = $self->getEntityID($dependant);
      }

      next unless defined $depid;
      $self->addStrongDependant($uorid, $depid);
    }

    if (!isApplication($uorname)) {
      (@dependencies) = sort $uorobj->getWeakDependants();
      foreach my $dependant (@dependencies) {
	my $depid = $self->getEntityID($dependant);
	# Does it exist?
	if (!$depid) {
	  $self->addThing($dependant);
	  $depid = $self->getEntityID($dependant);
	}

	next unless defined $depid;
	$self->addWeakDependant($uorid, $depid);
      }
    }
  }

  # Should we redo attributes?
  if ($memdate < $memfiledate) {
    $self->setAttributeStatus($uorid, $memfiledate, 'metaonly',       $uorobj->isMetadataOnly);
    $self->setAttributeStatus($uorid, $memfiledate, 'prebuilt',       $uorobj->isPrebuilt);
    $self->setAttributeStatus($uorid, $memfiledate, 'relativepath',   $uorobj->isRelativePathed);
    $self->setAttributeStatus($uorid, $memfiledate, 'offlineonly',    $uorobj->isOfflineOnly);
    $self->setAttributeStatus($uorid, $memfiledate, 'notoffline',     !$uorobj->isOfflineOnly);
    $self->setAttributeStatus($uorid, $memfiledate, 'gtkbuild',       $uorobj->isGTKbuild);
    $self->setAttributeStatus($uorid, $memfiledate, 'hardvalidate',   $uorobj->isHardValidation);
    $self->setAttributeStatus($uorid, $memfiledate, 'hardincoming',   $uorobj->isHardInboundValidation);
    $self->setAttributeStatus($uorid, $memfiledate, 'bigonly',        $uorobj->isBigOnly);
    $self->setAttributeStatus($uorid, $memfiledate, 'closed',         $uorobj->isClosed);
    $self->setAttributeStatus($uorid, $memfiledate, 'undependable',   $uorobj->isUndependable);
    $self->setAttributeStatus($uorid, $memfiledate, 'mechanized',     $uorobj->isMechanized);
    $self->setAttributeStatus($uorid, $memfiledate, 'screenlibrary',  $uorobj->isScreenLibrary);
    $self->setAttributeStatus($uorid, $memfiledate, 'application',    isApplication($uorname));
  }

  if (!isApplication($uorname)) {
    # How about weak symbols
    if ($optdate < $optsfiledate) {
      $self->addUORWeakDepSymbols($uorname);
    }

    # And extra libs?
    if ($optdate < $optsfiledate or $defsdate < $defsfiledate) {
      $self->scanExtraLibraries($uorname, $uorid);
    }
  }

}

sub addUORWeakDepSymbols {
  my ($self, $uor) = @_;
  return if $self->{cache_mode} =~ /(nosymbols|read_only)/;

  $self->debug( "->Adding in weak dependencies for $uor\n");
  local $SIG{__WARN__};
  my $meta = $self->{factory}->construct($uor)->expandValue('_BAD_SYMBOLS');

  my $baseid = $self->getEntityID($uor);
  $self->{dbh}->do("update uor set opt_date = ? where entityid = ? and architecture = ? and branchid = ?", undef, time(), $baseid, $self->{arch}, $self->{basebranch});
  $self->{dbh}->do("delete from weak_symbols where baseuorid = ? and architecture = ? and branchid = ?", undef, $baseid, $self->{arch}, $self->{basebranch});

  my %seensyms;
  my $lastgood = "";
  foreach my $symbol (split(/(?:\s|,)/, $meta)) {
    my (@elems) = $symbol =~ /^(.*)\s*\[\s*(.*)\s*\]\s*:\s*(.*)/;
    if (!defined $elems[2]) {
      $self->debug("Bad weak sym >$symbol< found for $uor, last good was $lastgood");
      next;
    }

    my @symnames = $elems[2];
    # AIX and the symbol doesn't have a leading dot?
    if ($self->{arch} == 2 && ord($elems[2]) != 46) {
      push @symnames, '.'.$elems[2];
    }
    foreach my $symname (@symnames) {
      next if $seensyms{$elems[0].$elems[1].$symname}++;
      my $id = $self->newSymbolID($symname);
      my $objid = $self->getObjectID($elems[1]);
      if (!defined $objid) {
	$objid = $self->addObject($elems[1]);
      }
#    eval {
      $self->{dbh}->do("insert into weak_symbols (baseuorid, objid, symbolid, architecture, branchid) values (?,?,?,?,?)", undef, $baseid, $objid, $id, $self->{arch}, $self->{basebranch});
#    };
      if ($@) {
	print STDERR "Error inserting weak for $uor $symname $elems[2] : $@\n";
      }
    }
  }
}

sub setAttributeStatus {
  my ($self, $uorid, $date, $attribute, $status) = @_;
  my ($count) = $self->{dbh}->selectrow_array("select count(attribute) from attributes where attribute = ? and entityid = ? and architecture = ? and branchid = ?", undef, $attribute, $uorid, $self->{arch}, $self->{basebranch});
  # If they want it on and it is, bail
  return if ($count && $status);
  # If they want it off and it is, bail
  return if (!$count && !$status);
  
  if ($count) {
    # They want it off and it's on
    $self->{dbh}->do("delete from attributes where attribute = ? and entityid = ? and architecture = ? and branchid = ?", undef, $attribute, $uorid, $self->{arch}, $self->{basebranch});
  } else {
    # They want it on
    $self->{dbh}->do("insert into attributes (attribute,entityid,architecture,branchid) values (?,?,?,?)", undef, $attribute, $uorid,$self->{arch},$self->{basebranch});
  }
}


sub getName {
  my ($self, $id) = @_;
  if ($self->{cache}{entityid}{$id}) {
    return $self->{cache}{entityid}{$id};
  }
  my ($name) = $self->{dbh}->selectrow_array("select entityname from entity where entityid = ?", undef, $id);
  $name ||= '>>>undefined<<<';
  $self->{cache}{entityid}{$id} = $name;
  return $name;
}

sub addWeakDependant {
  my ($self, $fromid, $toid) = @_;
  $self->debug("Adding weak dependent for ".$self->getName($fromid) . " to " . $self->getName($toid), "\n");
  $self->{dbh}->do("insert into dependencies (fromid, toid, strength,architecture, branchid) values (?,?,'weak',?,?)", undef, $fromid, $toid, $self->{arch},$self->{basebranch});
}

sub addStrongDependant {
  my ($self, $fromid, $toid) = @_;
  $self->debug("Adding strong dependent for ".$self->getName($fromid) . " to " . $self->getName($toid), "\n");
  $self->{dbh}->do("delete from dependencies where fromid = ? and toid = ? and strength = 'strong' and architecture = ? and branchid = ?", undef, $fromid, $toid, $self->{arch}, $self->{basebranch});
 $self->{dbh}->do("insert into dependencies (fromid, toid, strength, architecture, branchid) values (?,?,'strong',?,?)", undef, $fromid, $toid, $self->{arch}, $self->{basebranch});
}


sub _stupid_symfix {
  my ($self, $name) = @_;
  $name = substr($name, 0, 250);
#  if ($self->{dbtype} eq 'informix') {
#    $name .= ' ';
#  }
  return $name;
}

sub _dumpInSymbolInfo {
  my ($self) = @_;
  return unless $self->{pendingsyms};
  my ($sth, $type);

  # Get our stuff set up
  if ($self->{dbtype} eq 'informix') {
    $sth = $self->{dbh}->prepare("insert into temp_symnames (symbolname, symbolhash, fullsymbolname, demangledname) values (?,?,?,?)");
    $type = 1;
  } else {
    $self->{dbh}->do("copy temp_symnames (symbolname, symbolhash, fullsymbolname, demangledname) from STDIN");
    $type = 0;
  }

  # Load the symbols
  foreach my $syms (values %{$self->{pendingsyms}}) {
    if ($type) {
      $sth->execute($syms->{smallname}, $syms->{hash}, $syms->{fullname}, $syms->{demangled});
    } else {
      $self->{dbh}->pg_putline(join("\t", $syms->{smallname}, $syms->{hash}, $syms->{fullname}, $syms->{demangled})."\n");
    }
  }
  undef $self->{pendingsyms};

  # Finish the copy
  if ($type) {
    $sth->finish();
  } else {
    $self->{dbh}->pg_endcopy;
  }

  # Update the info
}

sub addIDs {
  my ($self, $objinstance, @ids) = @_;

  $self->{need_idfix} = 1;
  foreach my $id (@ids) {
    push @{$self->{pendingids}}, [$objinstance, @$id];
  }
}

sub addSymbols {
  my ($self, $objinstance, @symbols) = @_;
  if (!$self->{temptablepending}) {
    $self->create_tempsymtable;
  }
  my $symhash = $self->{symhash};
  if (!defined $symhash) {
    $symhash = {}; $self->{symhash} = $symhash;
  }
  my ($defs, $undefs) = (0,0);
  my %defs;
  # Grab the defs.
  foreach my $symbol (@symbols) {
    $defs{$symbol->getName()}++ if $symbol->getType ne 'U';
  }
  foreach my $symbol (@symbols) {
    my $name = $symbol->getName();
    my $first =  !exists $symhash->{$name};
    $symhash->{$name}++;
    my $shortname = $self->_stupid_symfix($name);

    # Local is kinda funny. For defined things we know it's there, so
    # we can trust the symbol's telling us. For undefs we can't know
    # for sure since they're not tagged right -- we consider an undef
    # a local if there's a def of the same symbol in this object. We
    # can hack this out once isLocal is reliable for undefs, but
    # that'll require custom nm programs on both AIX and Solaris,
    # which we don't have. Yet.
    my $islocal = $symbol->isLocal;
    if (($symbol->getType eq 'U') && $defs{name}) {
      $islocal = 1;
    }

    if (!$self->{copy_in_progress}) {
      $self->{copy_in_progress} = 1;
      $self->{dbh}->do("copy temp_symbols (symbolhash, symboltype, symbolsize, objinstance, is_weak, is_common, section, symbolvalue,isfirst, is_local, is_template, sym_offset) from STDIN");
    }
    #
    # XXXXXXXXXXXXXXXXXXXXXXXXX
    # This is a hack to work around the datbase definition for
    # now. Offset is 32 bit unsigned in the object files but 32 bit
    # signed in the database. Set out-of-range things to -1 until we
    # can get the database fixed.
    my $offset = $symbol->getOffset || 0;
    $offset = -1 if $offset > 0x7fffffff;

    $self->{dbh}->pg_putline(join("\t", md5_hex($name), $symbol->getType, $symbol->getSize || 0, $objinstance, $symbol->isWeak, $symbol->isCommon, $symbol->getSection, $symbol->getValue||0, $first||0, $islocal, $symbol->isTemplate, $offset)."\n");

    $symbol->getType eq 'U' ? $undefs++ : $defs++;
    $self->{pendingsyms}{md5_hex($name)} = {smallname => $shortname,
					    hash => md5_hex($name),
					    fullname => $name,
					    demangled => Binary::Analysis::Demangle::demangle_sym($name),
					   };
  }
  return ($defs, $undefs);
}

sub addEntity {
  my ($self, $entityname) = @_;
#  eval {
    $self->{dbh}->do("insert into entity (entityname) values (?)", undef, $entityname);
#  };
  undef $self->{fakelibs};
  undef $self->{cache}{entityid};
  return $self->getEntityID($entityname);
}

sub allApplications {
  my ($self) = @_;
  my $apps = $self->{dbh}->selectall_arrayref("select appname, makefile, directoryname, createdate from applications where architecture = ?", undef, $self->{arch});
  return @$apps;
}

#
# 
#
sub refreshApplication {
  my ($self, $app, $makefile, $directory) = @_;
  my $appname = "App::$app";

  my $arch = $self->{arch};
  my ($appid, $makefiledate) = $self->{dbh}->selectrow_array("select appid, createdate from applications where architecture = ? and appname = ?", undef, $arch, $app);
  if (!$appid) {
    $self->addApplication($app, $makefile, $directory);
  } else {
    my $filename = "$directory/$makefile";
    $filename =~ s/,v$//;
    my $date;
    if (-e $filename) {
      $date = (stat $filename)[9];
    } elsif (-e $filename.',v') {
      $date = (stat $filename.',v')[9];
    }
    if (!$date) {
      $self->debug("Can't find app $app/$makefile/$directory\n");
      return;
    }
    # If we found a file and the file had the same date as in the
    # database then we bail since there was no change
    return if ($date && $makefiledate && ($date == $makefiledate));
    $self->debug("makefile date is $date\n");
    $self->debug("db date is $makefiledate\n") if $makefiledate;
    $self->{dbh}->do("delete from application_links where appid = ?", undef, $appid);
    $self->_loadApplication($appid, $app, $makefile, $directory);
  }
}

sub refreshAppObjects {
  my ($self) = @_;
  my $objlist = $self->{dbh}->selectall_arrayref("select distinct objectinstance.objid, objectinstance.objinstance, objectdate, directory, objectname from objects, objectinstance, appobjects, application_links, applications where applications.appid = application_links.appid and application_links.thingid = appobjects.objid and application_links.thingtype = 'object' and applications.architecture = ? and objects.objid = objectinstance.objid and objectinstance.objinstance = appobjects.objinstance", undef, $self->{arch});
  $self->debug("Scanning " . scalar(@$objlist) . " objects\n");
  my $count = 0;
  foreach my $row (@$objlist) {
    my ($objid, $objinst, $objdate, $directory, $name) = @$row;
    # Fetch the object, check its date against the objinstance, and
    # see if the objinstance needs to be updated.
    my ($date, $size) = (stat "$directory/$name")[9,7];
    # Nonexistant? Log and skip, presumably someone just cleaned it up
    if (!$date) {
      $self->debug("object $directory/$name doesn't exist\n");
      next;
    }
    # The same? Skip
    if ($date == $objdate) {
#      $self->debug("same date for $directory/$name\n");
      next;
    }
    $count++;
    my $objobj = Binary::Analysis::Files::Object->new("$directory/$name");
    eval {
      my ($newid) = $self->addObjectInstance($objid, $objobj, $date, undef, $size);
      if ($self->{copy_in_progress}) {
	$self->{dbh}->pg_endcopy;
	$self->{copy_in_progress} = 0;
      }
      $self->{dbh}->do("update appobjects set objinstance = ? where objid = ?", undef, $newid, $objid);
      # Are we doing a piecewise commit?
      if ($self->{commit_piecemeal}) {
	$self->commit;
      }
    };
    if ($@) {
      $count--;
      print STDERR "Error updating $directory/$name: $@";
      eval {
	$self->{copy_in_progress} = 0;
	$self->{dbh}->pg_endcopy;
      };
      $self->rollback;
      next;
    }
  }
  $self->debug("Updated $count objects\n");
}

sub getApplicationID {
  my ($self, $app) = @_;
  my $arch = $self->{arch};
  my ($appid) = $self->{dbh}->selectrow_array("select appid from applications where architecture = ? and appname = ?", undef, $arch, $app);
  return $appid;
}

sub getApplication {
  my ($self, $app) = @_;
  my $row = $self->{dbh}->selectrow_arrayref("select appname, makefile, directoryname, createdate from applications where architecture = ? and appname = ?", undef, $self->{arch}, $app);
  if ($row) {
    return $row;
  } else {
    return;
  }
}

sub addApplication {
  my ($self, $app, $makefile, $directory) = @_;
  my $appname = "App::$app";
  $directory =~ s|/$||;
  my $arch = $self->{arch};
  my ($appid) = $self->{dbh}->selectrow_array("select appid from applications where architecture = ? and appname = ?", undef, $arch, $app);
  return $appid if $appid;

  if (!$appid) {
    my $entityid = $self->getEntityID($appname);
    if (!$entityid) {
      $entityid = $self->addEntity($appname);
    }

    # Fix this later to extract useful stuff from the makefile name
    if (!$directory) {
      die "Need a dir!";
    }

    # Strip the trailing ,v if there is one
    $makefile =~ s/,v$//;
    $self->{dbh}->do("insert into applications (appname, apptype, directoryname, makefile, architecture, entityid) values (?,?,?,?,?,?)", undef, $app, 'App', $directory, $makefile, $arch, $entityid);
    ($appid) = $self->{dbh}->selectrow_array("select appid from applications where architecture = ? and appname = ?", undef, $arch, $app);

    $self->_loadApplication($appid, $app, $makefile, $directory);
  } else {
    $self->refreshApplication($app, $makefile, $directory);
  }
}

sub _loadApplication {
  my ($self, $appid, $app, $makefile, $directory) = @_;

  my $filename = "$directory/$makefile";
  my $date;
  if (-e $filename) {
    $date = (stat $filename)[9];
  } elsif (-e $filename.',v') {
    $date = (stat $filename.',v')[9];
  } else {
    print "No makefile $filename\n";
    return;
  }

  $self->{dbh}->do("update applications set createdate = ? where appid = ?", undef, $date, $appid);

  my $makefileinfo = $self->parseMakefileForStuff("$directory/$makefile");
  if ($makefileinfo->{taskloc}) {
    $self->{dbh}->do("update applications set applocation = ? where appid = ?", undef, $makefileinfo->{taskloc}, $appid);
  }
  my (@things) = @{$makefileinfo->{linkitems}};
  local (@pathlist);
  if ($ENV{LD_LIBRARY_PATH}) {
    @pathlist = split ':', $ENV{LD_LIBRARY_PATH};
  }
  push @pathlist, '/usr/lib', '/bb/util/common/studio8/SUNWspro/prod/lib';
  my $order;
  my $preferdynamic = 0;
  my $allextract = 0;
  foreach my $thing (@things) {
    $order++;
    if ($thing eq '-Bstatic') {
      $preferdynamic = 0;
      next;
    }
    if ($thing eq '-Bdynamic') {
      $preferdynamic = 1;
      next;
    }
    if ($thing eq '-zallextract') {
      $allextract = 1;
      next;
    }
    if ($thing eq '-zdefaultextract') {
      $allextract = 0;
      next;
    }
    # Object file?
    if ($thing =~ /\.o$/) {
      my $path; my $name;
      $path = dirname($thing);
      $name = basename($thing);
      if (!($path =~ m|^/|)) {
	$path = $directory . '/' . $path;
      }
      my ($objid, $objinstance) = $self->addBareObject($name, $path);
      my ($oldobjid, $oldobjinst) = $self->{dbh}->selectrow_array("select objid, objinstance from appobjects where objid = ?", undef, $objid);
      if ((!defined $oldobjid) || ($oldobjinst != $objinstance)) {
	$self->{dbh}->do("delete from appobjects where objid = ?", undef, $objid) if $objid;
	$self->{dbh}->do("insert into appobjects (objid, objinstance) values (?,?)", undef, $objid, $objinstance);
      }
      $self->{dbh}->do("insert into application_links (appid, thingtype, thingid, thingorder) values (?, 'object', ?, ?)", undef, $appid, $objid, $order);
      next;
    }

    # Library?
    if ($thing =~ /^\w.*$/) {

      # Find where this library lives right now
      my $lib = $self->figureAbsPath($thing, $preferdynamic);
      next unless $lib;
      my $libid = $self->getLibIDForPath($lib);
      # Did we find an existing instance?
      if ($libid) {
	# Yes, use it
	$self->{dbh}->do("insert into application_links (appid, thingtype, thingid, thingorder, preferstatic, all_extract) values (?, 'library', ?, ?, ?, ?)", undef, $appid, $libid, $order, 1-$preferdynamic, $allextract);
      } else {
	# No, add in the library as an extra and then use ut.
	$self->addExtraLibrary(undef, $lib, $thing);
	$libid = $self->getLibIDForPath($lib);
	if (!$libid) {
	  confess "no libid for $lib\n";
	}
	$self->{dbh}->do("insert into application_links (appid, thingtype, thingid, thingorder, preferstatic, all_extract) values (?, 'extra', ?, ?, ?, ?)", undef, $appid, $libid, $order, 1-$preferdynamic, $allextract);
      }
      next;
    }
    if ($thing =~ /^-L/) {
      $thing =~ s/^-L//;
      push @pathlist, $thing;
      next;
    }
    if ($thing =~ /^-R/) {
      $thing =~ s/^-R//;
      push @pathlist, split(':', $thing);
      next;
    }
    if ($thing =~ /\.a$/) {
#      next;
      my $name = basename($thing);
      $name =~ s/(\.realarchive)?\.a$//;
      my $libid = $self->getLibIDForPath($thing);
      if (!$libid) {
	my $extraid = $self->addExtraLibrary(undef, $thing, $name);
	$libid = $self->getLibIDForPath($thing);
      }
#      my $libid = $self->getLibIDForPath($thing);
      $self->debug("Adding extra library $thing\n");
      $self->{dbh}->do("insert into application_links (appid, thingtype, thingid, thingorder) values (?, 'standalone', ?, ?)", undef, $appid, $libid, $order);
      next;
    }
    $self->debug("Can't do anything with >$thing<\n");
  }
}

sub getLibIDForPath {
  my ($self, $path) = @_;
  my ($basename, $pathname);
  $basename = basename($path);
  $pathname = dirname($path);
  if ($pathtrans{$pathname}) {
    $pathname = $pathtrans{$pathname};
  }

  my $rows = $self->{dbh}->selectall_arrayref("select libid from library where architecture = ? and libname = ? and libdirectory = ?", undef, $self->{arch}, $basename, $pathname);
  if (@$rows) {
    return $rows->[0][0];
  }
  return;
}

sub getEntityID {
  my ($self, $entityname) = @_;
  if (exists $self->{fakelibs}{$entityname}) {
    return $self->{fakelibs}{$entityname};
  }
  if (exists $self->{cache}{entityid}{$entityname}) {
    return $self->{cache}{entityid}{$entityname};
  }
  my (@row) = $self->{dbh}->selectrow_array("select entityid from entity where entityname = ?", undef, $entityname);
  $self->{cache}{entityid}{$entityname} = $row[0] if defined($row[0]);
  $self->{cache}{entityname}{$row[0]} = $entityname if defined $row[0];
  return $row[0];
}

sub getEntityName {
  my ($self, $entityid) = @_;
  return unless $entityid;
  if ($self->{cache}{entityname}{$entityid}) {
    return $self->{cache}{entityname}{$entityid};
  }
  my ($entityname) = $self->{dbh}->selectrow_array("select entityname from entity where entityid = ?", undef, $entityid);
  $self->{cache}{entityname}{$entityid} = $entityname;
  $self->{cache}{entityid}{$entityname} = $entityid if $entityname;
  return $entityname;
}

### Architecture changed to here
sub getObjectsUORID {
  my ($self, $libid, $date) = @_;
  my $arch = $self->{arch};
  if ($date) {
    print "getObjectsUORID date: $date\n";
  } else {
    print "getObjectsUORID no date\n";
  }
  my $colref;
  if ($date) {
    $colref = $self->{dbh}->selectcol_arrayref("select objid, archiveorder from objectinstance where uorid = ? and objectdate >= ? and enddate <= ? and architecture = ? order by archiveorder", undef, $libid, $date, $date, $arch);
  } else {
    $colref = $self->{dbh}->selectcol_arrayref("select objid, archiveorder from objectinstance where uorid = ? and enddate is null and architecture = ? order by archiveorder", undef, $libid, $arch);
  }
  return @$colref;
}

#
# Create the temp table we're stuffing all the symbols into.
#
sub create_tempsymtable {
  my ($self) = @_;
  eval {
    $self->{dbh}->do("create temp table temp_symbols (
    symbolhash character(32),
    symbolid integer DEFAULT -1 NOT NULL,
    symboltype char(1),
    symbolsize integer,
    objinstance integer NOT NULL,
    is_weak smallint DEFAULT 0,
    is_common smallint default 0,
    section integer,
    symbolvalue numeric(18),
    isfirst smallint default 0,
    is_local smallint default 0,
    is_template smallint default 0,
    sym_offset integer
          ) ");
  };
  if ($@) {
    confess $@ unless $@ =~ /already exists/;
  }
  eval {
    $self->{dbh}->do("create temp table temp_symnames (
    symbolname varchar(254),
    symbolhash character(32),
    fullsymbolname text,
    demangledname text
          ) ");
  };
  if ($@) {
    confess $@ unless $@ =~ /already exists/;
  }
  
  $self->{copy_in_progress} = 1;
  $self->{dbh}->do("copy temp_symbols (symbolhash, symboltype, symbolsize, objinstance, is_weak, is_common, section, symbolvalue, isfirst, is_local, is_template, sym_offset) from STDIN");
  $self->{need_symfix} = 1;
  $self->{temptablepending} = 1;
}

my $has_warned = 0;
sub _flush_symbols {
  my ($self) = @_;
  my %time;
  local $| = 1;
  $time{start}= time;
  # Flush the insert cursor
  if ($self->{dbtype} eq 'informix') {
    $self->{sth}{insert_temp_symbol}->finish();
  } else {
    if ($self->{copy_in_progress}) {
      $self->{dbh}->pg_endcopy;
      $self->{copy_in_progress} = 0;
    }
  }
  undef $self->{sth}{insert_temp_symbol};

  # Go create an index or two so this isn't horribly slow
  $time{finish} = time;
  $self->debug("finish ", $time{finish} - $time{start}, ", ");


  $self->{dbh}->do("create index tempsymindex1 on temp_symbols (symbolid, symbolhash, isfirst)");
  $time{index} = time();
  $self->debug("index ", $time{index} - $time{finish}, ", ");

  # Assign symbolids to the known symbols
  my $tname = "";
  if ($self->{dbtype} eq 'informix') {
    $tname = "temp_symbols.";
  }
#  $self->{dbh}->do("set explain on");
  $self->{dbh}->do("
update temp_symbols 
   set ${tname}symbolid = symbols.symbolid
  from symbols
 where symbols.symbolhash = temp_symbols.symbolhash
");
#  $self->{dbh}->do("set explain off");
  $time{update1} = time();
  $self->debug("update1 ", $time{update1} - $time{index}, ", ");

  # Clean out anything that existed so we don't re-upload it
  my $hashcol = $self->{dbh}->selectcol_arrayref("select distinct symbolhash from temp_symbols where symbolid != -1");
  $time{existingsym} = time();
  $self->debug("existingsym ", $time{existingsym} - $time{update1}, ", ");

  foreach my $hash (@$hashcol) {
    delete $self->{pendingsyms}{$hash};
  }
  $time{symclean} = time();
  $self->debug("symclean ", $time{symclean} - $time{existingsym}, ", ");

  # Go add in the pending symbols
  $self->_dumpInSymbolInfo();
  $time{symdump} = time();
  $self->debug("symdump ", $time{symdump} - $time{symclean}, ", ");

  # Add the unknown symbols into the symbol table
  $self->{dbh}->do("insert into symbols (symbolname, symbolhash, fullsymbolname, demangledname) select symbolname, symbolhash, fullsymbolname, demangledname from temp_symnames");
  $time{insert} = time();
  $self->debug("insert ", $time{insert} - $time{symdump}, ", ");

  my $sname = ""; $sname = 'symbols.' if $self->{dbtype} eq 'informix';

  # Update the remaining symbols with a value
  $self->{dbh}->do("
update temp_symbols 
   set ${tname}symbolid = symbols.symbolid
  from symbols
 where symbols.symbolhash = temp_symbols.symbolhash
   and temp_symbols.symbolid = -1");
  $time{update2} = time();
  $self->debug("update2 ", $time{update2} - $time{insert}, ", ");

  # Now dump the symbols into their real tables and clean up
  $self->{dbh}->do("insert into provide_symbol (symbolid, symboltype, symbolsize, objinstance, is_weak, is_common, section, symbolvalue, is_local, is_template, sym_offset) select symbolid, symboltype, symbolsize, objinstance, is_weak, is_common, section, symbolvalue, is_local, is_template, sym_offset from temp_symbols where symboltype != 'U'");
  $time{provide} = time();
  $self->debug("provide ", $time{provide} - $time{update2}, ", ");

  $self->{dbh}->do("insert into use_symbol (symbolid, objinstance, is_weak, section, is_local, sym_offset) select symbolid, objinstance, is_weak, section, is_local, sym_offset from temp_symbols where symboltype = 'U'");
  $time{use} = time();
  $self->debug("use ", $time{use} - $time{provide}, ", ");

  eval {$self->{dbh}->do("drop table temp_symbols");};
  eval {$self->{dbh}->do("drop table temp_symnames");};
  if (!$has_warned && $@) {
    print "error dropping table: $@\n";
    $has_warned = 1;
    eval {$self->{dbh}->do("drop index tempsymindex1");};
    eval {$self->{dbh}->do("delete from temp_symbols");};
    eval {$self->{dbh}->do("delete from temp_symnames");};
  }
  $self->{temptablepending} = 0;
  $self->{need_symfix} = 0;


  $time{end} = time;
  $self->debug("clean ", $time{end} - $time{use}, ", ");

  $self->debug("flush took ", $time{end} - $time{start}, " seconds total\n");
}

sub _flush_ids {
  my $self = shift;
  foreach my $id (@{$self->{pendingids}}) {
    $self->{dbh}->do("insert into object_metadata (objinstance, meta_type, tagid, valueid) values (?,?,?,?)", undef, $id->[0], 'RCSID', $self->getTagID($id->[1]), $self->getValueID($id->[2]));
  }
  undef $self->{pendingids};
  $self->{need_idfix} = 0;
}

sub getTagID {
  my ($self, $tag) = @_;
  confess if !defined $tag;
  if (!$self->{cache}{tagid}{$tag}) {
    my ($id) = $self->{dbh}->selectrow_array("select tagid from metadata_tags where tag = ?", undef, $tag);
    if (!$id) {
      ($id) = $self->{dbh}->selectrow_array("insert into metadata_tags (tag) values (?) returning tagid", undef, $tag);
    }
    $self->{cache}{tagid}{$tag} = $id;
  }

  return $self->{cache}{tagid}{$tag};
}

sub getValueID {
  my ($self, $value) = @_;
  if (!$self->{cache}{valueid}{$value}) {
    if ($value =~ /\x90/) {
      confess "Got a x90!";
    }
    my ($id) = $self->{dbh}->selectrow_array("select valueid from metadata_values where value = ?", undef, $value);
    if (!$id) {
      ($id) = $self->{dbh}->selectrow_array("insert into metadata_values (value) values (?) returning valueid", undef, $value);
    }
    $self->{cache}{valueid}{$value} = $id;
  }

  return $self->{cache}{valueid}{$value};
}

=item @uor = $db->allUOR

Return a list of all the units of release in the database.

=cut

sub allUOR {
  my $self = shift;
  my $symbolreg = $self->{dbh}->selectcol_arrayref("select entityname from entity, uor where entity.entityid = uor.entityid and uor.architecture = ? and uor.branchid = ?", undef,  $self->{arch}, $self->{basebranch});
  return @$symbolreg;
}


sub getLibraryInstance {
  my ($self, $uorid, $date, $istemp) = @_;
  $istemp = 0 unless $istemp;
  $date ||= time;
  my $row = $self->{dbh}->selectcol_arrayref("select libinstanceid from libinstance where entityid = ? and libdate <= ? and enddate > ? and architecture = ? and branchid = ? and istemp = ?", undef, $uorid, $date, $date, $self->{arch}, $self->{basebranch}, $istemp);
  return $row->[0];
}

sub getSymbolType {
  my ($self, $symbol) = @_;
  my $symhash = md5_hex($symbol);
  my $type = $self->{dbh}->selectcol_arrayref("select distinct symboltype from provide_symbol, symbols where symbolhash = ? and provide_symbol.symbolid = symbols.symbolid", undef, $symhash);
  return $type->[0];
}

=item @objects = $db->symbolUsedInUOR($symbol, $uor[, $type])

Return a list of objects in the passed in uor that use the passed-in
symbol. The type is optional, and should be generally left out since
undefined symbols don't differentiate between text and data. If not
left out it is ignored anyway.

=cut

sub symbolUsedInUOR {
  my ($self, $symbol, $uor, $type, $arch) = @_;
  $type = 'T' unless $type;
  $arch = $^O unless $arch;
  my $symid = $self->getSymbolID($symbol);
  my $uorid = $self->getEntityID($uor);
  my $libinstanceid = $self->getLibraryInstance($uorid);
  my $objref = $self->{dbh}->selectcol_arrayref("select objectname from objects, provide_symbol, objectinstance, libobject where libinstanceid = ? and symbolid = ? and objectinstance.objinstance = libobject.objinstance and provide_symbol.objinstance = objectinstance.objinstance and objects.objid = objinstance.objid", undef, $libinstanceid, $symid);
  return @$objref;
}

=item @parents = $db->findParents($thing)

Find all the things that depend on this particular thing. Only strong
dependencies are examined.

=cut

sub findParents {
  my ($self, $thing) = @_;
  my @parents;
  my $id = $self->getEntityID($thing);
  my $rows_ref = $self->{dbh}->selectall_arrayref("select entityname from dependencies, entity where entityid = dependencies.fromid and dependencies.toid = ? and dependencies.strength = 'strong' and architecture = ? and branchid = ?", {}, $id, $self->{arch}, $self->{basebranch});
  foreach my $row (@$rows_ref) {
    push @parents, $row->[0];
  }
  return @parents;
}

=item (@children) = $db->findExtraChildren($thing)

Searches the database and returns all the extra_lib libraries that the
thing depends on.

=cut

sub findExtraChildren {
  my ($self, $thing) = @_;
  my @kids;
  my $id = $self->getEntityID($thing);
  my $rows_ref = $self->{dbh}->selectall_arrayref("select entityname from dependencies, entity where entityid = dependencies.toid and dependencies.fromid = ? and dependencies.strength = 'extra' and architecture = ? and branchid = ?", {}, $id, $self->{arch}, $self->{basebranch});
  foreach my $row (@$rows_ref) {
    push @kids, $row->[0];
  }
  return @kids;
}

=item (@children) = $db->findChildren($thing)

Searches the database and returns all the immediate children for the
passed in thing. Uses the declared dependencies, and only returns the
strongly linked children. (Dependencies declared weak aren't returned)

=cut
sub findChildren {
  my ($self, $thing) = @_;
  my @kids;
  if (defined $self->{cache}{children}{$thing}{$self->{arch}}{$self->{basebranch}}) {
    return @{$self->{cache}{children}{$thing}{$self->{arch}}{$self->{basebranch}}};
  }
  my $id = $self->getEntityID($thing);
  my $rows_ref = $self->{dbh}->selectall_arrayref("select entityname from dependencies, entity where entityid = dependencies.toid and dependencies.fromid = ? and dependencies.strength = 'strong' and architecture = ? and branchid = ?", {}, $id, $self->{arch}, $self->{basebranch});
  foreach my $row (@$rows_ref) {
    push @kids, $row->[0];
  }
  $self->{cache}{children}{$thing}{$self->{arch}}{$self->{basebranch}} = \@kids;
  return @kids;
}

=item (@children) = $db->findWeakParents($thing)

Searches the database and returns all the immediate weakly-linked
parents for the passed in thing. Uses the declared dependencies.

=cut
sub findWeakParents {
  my ($self, $thing) = @_;
  my @kids;
  my $id = $self->getEntityID($thing);
  my $rows_ref = $self->{dbh}->selectall_arrayref("select entityname from dependencies, entity where entityid = dependencies.fromid and dependencies.toid = ? and dependencies.strength = 'weak' and architecture = ? and branchid = ?", {}, $id, $self->{arch}, $self->{basebranch});
  foreach my $row (@$rows_ref) {
    push @kids, $row->[0];
  }
  return @kids;
}

=item (@children) = $db->findWeakChildren($thing)

Searches the database and returns all the immediate weakly-linked
children for the passed in thing. Uses the declared dependencies.

=cut
sub findWeakChildren {
  my ($self, $thing) = @_;
  my @kids;
  my $id = $self->getEntityID($thing);
  my $rows_ref = $self->{dbh}->selectall_arrayref("select entityname from dependencies, entity where entityid = dependencies.toid and dependencies.fromid = ? and dependencies.strength = 'weak' and architecture = ? and branchid = ?", {}, $id, $self->{arch}, $self->{basebranch});
  foreach my $row (@$rows_ref) {
    push @kids, $row->[0];
  }
  return @kids;
}

=item getAttributes($thing);

Return the attributes which have been set on a package or group. Currently
the attrobites are 'metaonly', 'prebuilt', 'relativepath',
'offlineonly', and 'gtkbuild'.

=cut
sub getAttributes {
  my ($self, $thing) = @_;
  my $thingid = $self->getEntityID($thing);
  return unless $thingid;
  if ($self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes}{$thingid}) {
    return @{$self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes}{$thingid}};
  }

  my $attributes = $self->{dbh}->selectcol_arrayref("select attribute from attributes where entityid = ? and architecture = ? and branchid = ?", undef, $thingid, $self->{arch}, $self->{basebranch});
  $self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes}{$thingid} = $attributes;
  return @$attributes;
}

sub hasAttribute {
  my ($self, $thing, $attrib) = @_;
  my $thingid = $self->getEntityID($thing);
  # If it doesn't exist we can pretty much guarantee that it doesn't
  # have the attribute...
  if (!$thingid) {
    return;
  }
  if (exists $self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes_indiv}{$thingid}) {
    return $self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes_indiv}{$thingid}{$attrib};
  }
  foreach my $attr ($self->getAttributes($thing)) {
    $self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes_indiv}{$thingid}{$attr} = 1;
  }
  return $self->{cache}{"arch$self->{arch}"}{"branch$self->{basebranch}"}{attributes_indiv}{$thingid}{$attrib};
}

=item @uor = $db->symbolProvidedByUOR($symbol[, $type])

Returns a list of UORs that provide the symbol. The type is optional
and if not specified defaults to text symbols.

=cut

sub symbolProvidedByUOR {
  my ($self, $symbol, $type, $date) = @_;
  $type = 'T' unless $type;
  $date ||= time;

  my $symid = $self->getSymbolID($symbol);
  my $uorref = $self->{dbh}->selectcol_arrayref("
select distinct entityname
  from entity,
       uor,
       libinstance,
       libobject,
       provide_symbol
 where provide_symbol.symbolid = ?
   and uor.entityid = libinstance.entityid
   and entity.entityid = uor.entityid
   and libobject.libinstanceid = libinstance.libinstanceid
   and provide_symbol.objinstance = libobject.objinstance
   and libinstance.libdate <= ?
   and libinstance.enddate > ?
   and libinstance.architecture = ?
   and libinstance.branchid = ?
   and uor.architecture = ?
   and uor.branchid = ?", undef, $symid, $date, $date, $self->{arch}, $self->{basebranch}, $self->{arch}, $self->{basebranch});

  return @$uorref;
}

=item getDefinedSymbols($uor[,$type])

Get a list of all the symbols that C<$uor> defines. 

=cut

sub getDefinedSymbols {
  my ($self, $uor, $type, $date) = @_;
  $type = 'T' unless $type;
  $date ||= time;
  my $uorid = $self->getEntityID($uor);
  my $libinstanceid = $self->getLibraryInstance($uorid, $date);
  my $cols =  $self->{dbh}->selectcol_arrayref("select distinct fullsymbolname from symbols, libinstance, libobject, provide_symbol where symbols.symbolid = provide_symbol.symbolid and libobject.libinstanceid = ? and provide_symbol.objinstance = libobject.objinstance and provide_symbol.symboltype = ? and libinstance.libinstanceid = libobject.libinstanceid", undef, $libinstanceid, $type);
  return @$cols;
}

=item getUndefinedSymbols($uor)

Return a list of all the undefined symbols for C<$uor>

=cut

sub getUndefinedSymbols {
  my ($self, $uor, $date) = @_;
  $date ||= time;
  my $uorid = $self->getEntityID($uor);
  my $libinstanceid = $self->getLibraryInstance($uorid, $date);
  my $cols =  $self->{dbh}->selectcol_arrayref("select distinct fullsymbolname from symbols, libobject, use_symbol where symbols.symbolid = use_symbol.symbolid and libobject.libinstanceid = ? and use_symbol.objinstance = libobject.objinstance", undef, $libinstanceid);
  return @$cols;

}

=item getGraph($library)

Returns an annotated graph object as constructed by the Graph.pm module.

=cut

sub getGraph {
  my ($self) = @_;
  my $graph = Graph->new();


  my $rows = $self->{dbh}->selectall_arrayref("
select fromuor.entityname,
       touor.entityname 
  from entity fromuor,
       entity touor,
       dependencies
 where fromuor.entityid = fromid
   and touor.entityid = toid
   and strength = 'strong'
   and architecture = ?
   and branchid = ?", undef, $self->{arch}, $self->{basebranch});
  foreach my $rec (@$rows) {
    $graph->add_edge($rec->[0], $rec->[1]);
  }
  my $lonely = $self->{dbh}->selectall_arrayref("
select entityname 
  from entity,
       uor
 where entity.entityid=uor.entityid
   and uor.entityid not in (select distinct fromid from dependencies where dependencies.architecture = ? and dependencies.branchid = ?)
   and uor.architecture = ?
   and uor.branchid = ?
   and uor.entityid not in (select distinct toid from dependencies where dependencies.architecture = ? and dependencies.branchid = ?)", undef, $self->{arch}, $self->{basebranch}, $self->{arch}, $self->{basebranch}, $self->{arch}, $self->{basebranch});
  foreach my $rec (@$lonely) {
    $graph->add_vertex($rec->[0]);
  }

  return $graph;

}


sub deletePackage {
  my ($self, $package) = @_;
  my $entityid = $self->getEntityID($package);
  $self->{dbh}->do("delete from packages where packageid = ?", undef, $entityid);
  $self->{dbh}->do("delete from uor where entityid = ?", undef, $entityid);
  $self->{dbh}->do("delete from dependencies where fromid = ? or toid = ?", undef, $entityid, $entityid);
  my $endtime = time;
  $self->{dbh}->do("update libinstance set enddate = ? where entityid = ? and enddate > ?", undef, $endtime, $entityid, $endtime);
  $self->{dbh}->do("delete from weak_symbols where baseuorid = ?", undef, $entityid);
  $self->{dbh}->do("delete from group_members where packageid = ?", undef, $entityid);
}

sub deleteGroup {
  my ($self, $group) = @_;
  my $entityid = $self->getEntityID($group);
  $self->{dbh}->do("delete from groups where groupid = ?", undef, $entityid);
  $self->{dbh}->do("delete from uor where entityid = ?", undef, $entityid);
  $self->{dbh}->do("delete from dependencies where fromid = ? or toid = ?", undef, $entityid, $entityid);
  my $endtime = time;
  $self->{dbh}->do("update libinstance set enddate = ? where entityid = ? and enddate > ?", undef, $endtime, $entityid, $endtime);
  $self->{dbh}->do("delete from weak_symbols where baseuorid = ?", undef, $entityid);
  $self->{dbh}->do("delete from group_members where groupid = ?", undef, $entityid);
}


=item rollbackChangeset($oldcsid, $newcsid, $date)

Rolls back changeset C<$oldcsid>. Object files affected are tagged
with changeset C<$newcsid>. Rollback will be done as of date C<$date>,
which makes it possible to roll back a changeset and have the rollback
still not take effect if the library has been modified after the
passed-in date.

Note that rollback won't function across a library load boundary.

=cut

sub rollbackChangeset {
  my ($self, $oldcsid, $newcsid, $date) = @_;
  $date = time unless $date;

  # Get all the data we need for validation checks
  my $instancerows = $self->{dbh}->selectall_arrayref("select libinstanceid, libid, libdate, branchid, architecture from libinstance where csid = ?", undef, $oldcsid);
  # Always possible there just aren't any to be had.
  if (!@$instancerows) {
    return;
  }

  foreach my $row (@$instancerows) {
    my ($instid) = $self->{dbh}->selectrow_array("select libdate from libinstance where libid = ? and architecture = ? and branchid = ? and istemp = 0 and libdate > ? and libdate < ?", undef, $row->[1], $row->[4], $row->[3], $row->[2], $date);
    if ($instid) {
      
    }
  }

}


sub getLibIDForLibInstance {
  my ($self, $libinstanceid) = @_;
  if (!$self->{cache}{libidforlibinstance}{$libinstanceid}) {
    my ($libid) = $self->{dbh}->selectrow_array("select libid from libinstance where libinstanceid = ?", undef, $libinstanceid);
    $self->{cache}{libidforlibinstance}{$libinstanceid} = $libid;
  }
  return $self->{cache}{libidforlibinstance}{$libinstanceid};
}


sub getAppsForLib {
  my ($db, $library, $type) = @_;
  $library =~ s/^Library:://;
  $type ||= 'Big';
  my $rows = $db->{dbh}->selectall_arrayref("select distinct appname from library, applications, application_links where applications.appid = application_links.appid and library.libid = application_links.thingid and library.libshortname = ? and application_links.thingtype = 'library' and applications.apptype = ?", undef, $library, $type);
  return map {$_->[0]} @$rows;
}

sub getLinklinePositions {
  my ($db, $app, $library) = @_;
  $library =~ s/^Library:://;
  my $appid = $db->getApplicationID($app);
  return unless $appid;

  my $rows = $db->{dbh}->selectall_arrayref("select thingorder from library, application_links where appid = ? and libshortname = ? and thingtype = 'library' and library.libid = thingid order by thingorder", undef, $appid, $library);
  return map {$_->[0]} @$rows;
}


# Get the branch ID for a particular date, with 'now' as the
# default. This will be replaced by calls to other infrastructure bits
# as soon as they're ready, but for now they aren't.
sub getBranchID {
  my ($self, $branch, $datestamp) = @_;
  $datestamp = time unless $datestamp;
  $branch = lc $branch;
  $branch = $branchalias{$branch} if $branchalias{$branch};

  my ($branchid) = $self->{dbh}->selectrow_array("select branchid from branchstatus where branchname = ? and startdate <= ? and enddate > ?", undef, $branch, $datestamp, $datestamp);
  return $branchid;
}

1;
