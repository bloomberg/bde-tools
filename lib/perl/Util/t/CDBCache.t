#!/usr/bin/env perl -w

# a simple CDBCache for looking up the nth prime
package PrimeCache;

use base qw(Util::CDBCache);
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = $class->SUPER::new(@_);
  return $self;
}

sub fetchmiss {
  my ($self, $n) = @_;
  return nthprime($n);
}

sub nthprime {
  my ($n) = @_;
  my ($x, $i) = (2,0);

  while ($i < $n) {
    $x++;
    $i++ if isprime($x);
  }

  return $x;
}

sub isprime {
  my $n = shift;

  return 1 if $n == 2;

  for (my $i=2; $i<=int(sqrt($n)); $i++) {
    return 0 if $n % $i == 0;
  }

  return 1;
}

1;


package main;
use strict;

my %known = do { my $i; map { ($i++,$_) } qw/2 3 5 7 11 13 17 19 23 29/ };
my $primes;

# the tests
my @t;
push @t, [ setup => \&setup ];
push @t, [ init_cache => \&init_cache ];
push @t, [ cold_fetch => \&known_fetch ];
push @t, [ hot_fetch => \&known_fetch ];
push @t, [ load_misses => sub { return $primes->loadmisses } ];
push @t, [ rebuild => sub { return $primes->rebuild } ];
push @t, [ get_keys => \&get_keys ];
push @t, [ get_values => \&get_values ];
push @t, [ dump_misses => sub { return $primes->dumpmisses } ];
push @t, [ teardown => \&teardown ];

print '1..'.@t.$/;

for (my $i=0; $i<@t; $i++) {
  local $@;
  my ($test, $f) = @{ $t[$i] };
  my $ok = $^P ? $f->() : (eval { $f->() } && !$@);
  print join ' ', $ok ? 'ok' : 'not ok', $i+1, $test.$/;
  print STDERR "#   Failed test $test: ".$@.$/ if $@;
}

sub setup {
  teardown();
  mkdir $_ or return 0 for qw{CDBCache CDBCache/misses CDBCache/tmp};
  return 1;
}

sub teardown {
  $primes = undef;
  system('rm', '-rf', 'CDBCache') == 0 or return 0;
  return 1;
}

sub init_cache {
  return $primes = PrimeCache->new
  (
    cdbpath => 'CDBCache/nthprime.cdb',
    missdir => 'CDBCache/misses',
    tempdir => 'CDBCache/tmp',
  );
}

sub known_fetch {
  for (keys %known) {
    $primes->get($_) == $known{$_} or return 0;
  }
  
  return 1; 
}

sub get_keys {
  my %seen;
  map { $seen{$_}++ } $primes->keys;
  map { $seen{$_} == 1 or return 0 } keys %known;
  return 1;
}

sub get_values {
  my %seen;
  map { $seen{$_}++ } $primes->values;
  map { $seen{$_} == 1 or return 0 } values %known;
  return 1;
}

