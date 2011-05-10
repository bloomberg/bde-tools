package Util::CDBCache;

use CDB_File;
use File::Temp; # FIXME File::Temp sucks, replace with scoped tempdir class
use Errno;
use strict;

=head1 NAME

Util::CDBCache - base class for a CDB that can grow with cache misses

=head1 SYNOPSIS

  use Util::CDBCache;
  
  my $cache = Util::CDBCache->new(cdbpath => 'nthprime.cdb');

  print "100th prime is ". $cache->get(100) . $/;
  print "cached primes: " . join '', $/, $cache->values, ''; 

  print "first 1000 primes: " . $/;
  print $cache->get($_).$/ for (1..1000);

  print "cache misses in memory: ". join $/, '', values %{$cache->misses}, '';

  print "rebuilding cache to include misses..." . $/;
  $cache->rebuild;

  print "cached primes: " . join '', $/, $cache->values, ''; 

=head1 DESCRIPTION

L<CDBCache|CDBCache> implements a fast, read-only key / value hash that can accumulate cache misses and their associated values. It can be configured to write these cache misses through to disk as they occur. The cache can be rebuilt atomically at any time, augmented by cache miss material. In this way, the cache can be "grown."

This name of this module contains the word "cache." Please use it for good, not evil.

=head1 METHODS

=head2 new(...)

Construct a new cache object. Calls L<init>. See L<init> for options.

=cut

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = bless {} => $class;
  return $self->init(@_);
}

=head2 init(...)

Initialize an instance created with L<new>. You shouldn't need to call this directly, new will pass on its parameters as key => value pairs to L<init> directly. The parameters are:

=over 4

=item cdbpath => $cdbpath

Path to the L<CDB|http://cr.yp.to/cdb.html> for this cache. Required, but need not yet exist on disk.

=item missdir => $missdir

Directory where cache misses are written when the B<writemisses> option is on. Default is 1.

=item missdb => { key1 => 'value1', key2 => 'value2', ... }

Initialize the in-memory cache of misses when using the B<cachemisses> option. Defaults to an empty hash.

=item cachemisses => 0|1

Accumulate cache misses in memory. Default is 1.

=item writemisses => 0|1

Write cache misses out to disk as they occur. Default is 1.

=item tempdir => $tempdir

Use this directory for temp files, which are needed for atomic updates. Defaults to I<TMPDIR> environmental variable.

=back

=cut

sub init {
  my $self = shift;
  my %arg = @_ & 1 ? die "Expected: parameter hash." : @_;
  my %required = map { ($_=>1) } qw/cdbpath/;
  my %permitted = map { ($_=>1) }
    qw/cdbpath missdb cachemisses writemisses tempdir missdir/;
  my %default =
  (
    missdb => {},
    cachemisses => 1,
    writemisses => 1,
    tempdir => $ENV{TMPDIR},
  );

  do { my $member="_$_"; $self->$member($default{$_}) } for keys %default;
  map { exists $arg{$_} || die "Parameter required: $_.$/" } keys %required;

  for (keys %arg) {
    die "Unknown parameter: $_." unless $permitted{$_};
    my $member = "_$_";
    $self->$member($arg{$_});
  }

  -e $self->_cdbpath ? $self->_tiecdb : $self->_cdb({});

  return $self;
}

=head2 get($key)

Retrieve the value associated with C<$key>.

First look in the CDB for C<$key>. If not found, fall back to the in-memory hash of cache misses. If all else fails, this is a new cache miss. Call L<fetchmiss>, which you should override for your particular cache.

With the B<cachemisses> option, store the cache miss in memory. With the B<writemisses> option, write the cache miss out to disk beneath the directory given by the B<missdir> option. Misses written through to disk can be loaded via L<loadmisses> and later used to L<rebuild> the CDB cache to improve performance.

=cut

sub get {
  my ($self, $key) = @_;
  my ($rc, $value);

  if (exists $self->_cdb->{$key}) {
    ($rc, $value) = (0, $self->_cdb->{$key});
  }
  elsif (exists $self->_missdb->{$key}) {
    ($rc, $value) = (0, $self->_missdb->{$key});
  }
  else {
    my @fetch = $self->fetchmiss($key);
    ($rc, $value) = @fetch>1 ? @fetch[0..1] : (defined $fetch[0], $fetch[0]);
    return ($rc, $value) if !defined $value;
    $self->_missdb->{$key} = $value if $self->_cachemisses;
    $self->_writemiss($key, $value) if $self->_writemisses;
  }

  return ($rc, $self->thawvalue($value));
}

=head2 thawvalue($value)

Override this method to deserialize values (to say, a perl hash) before they're returned by L<get> or L<values>.

=cut

sub thawvalue { my ($self, $value) = @_; return $value; }

=head2 keys(), values(), exists($key)

Treat the cache as a hash. The cache here consists of the CDB + the in-memory cache of misses, which accumulates misses only if the B<cachemisses> option is set.

=cut

sub keys {
  my $self = shift;
  return (keys %{ $self->_cdb }, keys %{ $self->_missdb });
}

sub values {
  my $self = shift;
  return map { $self->thawvalue($_) }
    (values %{ $self->_cdb }, values %{ $self->_missdb });
}

sub exists {
  my ($self, $key) = @_;
  return exists $self->_cdb->{$key} || exists $self->_missdb->{$key};
}

=head2 fetchmiss($key)

=cut

sub fetchmiss {
  my ($self, $key) = @_;
  warn "Warning: cache miss unimplemented, inherit from ".__PACKAGE__.".$/";
  return undef;
}

=head2 rebuild()

Atomically rebuild the CDB cache. If this succeeds, remove all misses on disk that were folded into the CDB.

=cut

sub rebuild {
  my ($self) = @_;

  my %newcdb = (%{$self->_missdb}, %{$self->_cdb});
  my $tempcdbpath = join('/', $self->_mktempdir, 'new.cdb');

  $self->_untiecdb;

  CDB_File::create %newcdb, $self->_cdbpath, $tempcdbpath or
    die "Error rebuilding cdb at $tempcdbpath: $?.$/";

  $self->_tiecdb;

  # clear misses: fresh start. safe because cdb was rebuilt ok.

  my @misskeys = CORE::keys %{ $self->_missdb };
  unlink $self->_missfile($_) for @misskeys;
  $self->_missdb({});

  return $self;
}

=head2 key2file($key), file2key($file)

Transform a key into a filename, or a filename into a key. These are used when cache misses are written to / read from disk. Override them if you know your keys may contain illegal filename characters. By default, no tranformation is performed.

=cut

sub key2file { my ($self, $key) = @_; return $key; }
sub file2key { my ($self, $file) = @_; return $file; }

=head2 misses()

Access the in-memory cache of misses directly as a hash.

=cut

sub misses { return shift->_member('missdb', @_); }

=head2 loadmisses()

Populate the in-memory cache of misses from the misses on disk. Follow this by a call to L<rebuild> to improve performance of the CDB.

=cut

sub loadmisses {
  my ($self) = @_;
  my %misses;

  opendir my $missdh, $self->_missdir or
    die "Error opening ".$self->_missdir." directory for read.$/";

  while (my $file = readdir $missdh) {
    next if $file eq '.' || $file eq '..';
    my $key = $self->file2key($file);
    next if exists $self->_cdb->{$key}; # dedupe dedupedee du
    my $path = $self->_missfile($key);

    open my $missfh, '<', $path or do {
      die "Error opening $path for read: $?.$/" unless $!{ENOENT};
      next;
    };

    $misses{$key} = do { local $/; <$missfh> };

    close $missfh or
      die "Error closing $path after read: $?.$/";
  }

  closedir $missdh or
    die "Error closing ".$self->_missdir." directory after read.$/";

  $self->_missdb(\%misses);
  return $self;
}

=head2 dumpmisses()

Dump the in-memory cache of misses to disk. This is normally done on every cache miss when the B<writemisses> option is set.

=cut

sub dumpmisses {
  my ($self) = @_;

  while (my ($k, $v) = each %{ $self->_missdb }) {
    $self->_writemiss($k, $v);
  }

  return $self;
}

sub _writemiss {
  my ($self, $key, $value) = @_;
  my $tmppath = join '/', $self->_mktempdir, $self->key2file($key);
  my $path = $self->_missfile($key);

  open my $missfh, '>', $tmppath or
    die "Error opening $tmppath for write: $?.$/";
  print $missfh $value;
  close $missfh or
    die "Error closing $tmppath after write: $?.$/";

  system("mv $tmppath $path") == 0 or
    die "Error moving $tmppath to $path: $?.$/";

  return $self;
}

sub _tiecdb {
  my ($self) = @_;

  tie my %cdb, 'CDB_File', $self->_cdbpath or
    die "Error, can't tie cdb ".$self->_cdbpath." to hash.$/";

  $self->_cdb(\%cdb);

  return $self;
}

sub _untiecdb {
  my ($self) = @_;

  my $cdb = $self->_cdb; # falls out of scope, unties itself
  $self->_cdb({});

  return $self;
}

sub _mktempdir {
  my ($self) = @_;
  return File::Temp::tempdir(DIR => $self->_tempdir, CLEANUP => 1);
}

sub _missfile {
  my ($self, $key) = @_;
  return join '/', $self->_missdir, $self->key2file($key);
}

# members - encapsulated because, well, you never know

sub _cachemisses { return shift->_member('cachemisses', @_); }
sub _writemisses { return shift->_member('writemisses', @_); }
sub _tempdir { return shift->_member('tempdir', @_); }
sub _cdbpath { return shift->_member('cdbpath', @_); }
sub _cdb { return shift->_member('cdb', @_); }
sub _missdb { return shift->_member('missdb', @_); }
sub _missdir { return shift->_member('missdir', @_); }

sub _member {
  my ($self, $name) = (shift,shift);
  return $self->{"_$name"}=shift if @_;
  return $self->{"_$name"};
}

1;

__END__

=head1 AUTHOR

Alan Grow, E<lt>agrow@bloomberg.netE<gt>

