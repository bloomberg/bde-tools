#!/bbs/opt/bin/perl -w

use SCM::Symbols qw/$SCM_CSDB $SCM_CSDB_DRIVER/;
use SCM::CSDB::Lock;
use Benchmark;
use strict;

my $db = SCM::CSDB::Lock->new
(
  driver => $SCM_CSDB_DRIVER,
  database => $SCM_CSDB
) or die;

sub randpath() {
  return join '', map { ('a'..'z','A'..'Z')[rand 52] } (1..10);
}

my $user1 = getpwuid($<);
my $path1 = randpath;
my $param1 = { path => $path1, user => $user1 };
my $user2 = getpwuid($< - int rand 50);
my $param2 = { path => $path1, user => $user2 };

# the test cases
my @t;

push @t, [ lock_unlock => \&lock_unlock ];
push @t, [ reentrant_lock => \&reentrant_lock ];
push @t, [ reentrant_unlock => \&reentrant_unlock ];
push @t, [ steal_lock => \&steal_lock ];
push @t, [ force_lock => \&force_lock ];
push @t, [ locked_by => \&locked_by];
push @t, [ history => \&history ];
push @t, [ nuke_lock => \&nuke_lock ];
push @t, [ perf_lock_unlock => \&perf_lock_unlock ];

print '1..'.@t.$/;

for (my $i=0; $i<@t; $i++) {
  my ($test, $f) = @{ $t[$i] };
  my $ok = $f->();
  print join ' ', $ok ? 'ok' : 'not ok', $i+1, $test.$/;
}

sub lock_unlock {
  $db->lock($param1) or return 0;
  $db->owner($param1) eq $user1 or return 0;
  $db->unlock({ path => $path1, user => $user1 }) or return 0;
  return 1;
}

sub reentrant_lock {
  $db->lock($param1) or return 0;
  $db->lock($param1) or return 0;
  return 1;
}

sub reentrant_unlock {
  $db->unlock($param1) or return 0;
  $db->unlock($param1) or return 0;
  return 1;
}

sub steal_lock {
  $db->lock($param2) or return 0;
  $db->steal({ path => $path1, olduser => $user1, user => $user2 }) or return 0;
  $db->owner($param2) eq $user2 or return 0;
  !$db->unlock($param1) or return 0;
  $db->unlock($param2) or return 0;
  return 1;
}

sub force_lock {
  $db->force({ path => $path1, user => $user1, eventby => $user1 }) or return 0;
  $db->owner({ path => $path1 }) eq $user1 or return 0;
  $db->force({ path => $path1, user => undef, eventby => $user2 }) or return 0;
  !defined $db->owner({ path => $path1 }) or return 0;
  return 1;
}
 
sub locked_by {
  my %paths = map { (randpath, 1) } 0 .. 10;
  $db->lock({ path => $_, user => $user1}) or return 0 for keys %paths;
  my $lockedby = $db->lockedby({ user => $user1 }) or return 0;
  my %bypaths = map { ($_->[0], 1) } @$lockedby;
  map { $bypaths{$_} && $paths{$_} or return 0 } keys %paths, keys %bypaths;
  $db->rmlockable({ path => $_, user => $user1 }) or return 0 for keys %paths;
  return 1; 
}

sub history { 
  my $history = $db->history($param1) or return 0;
  return 1;
}

sub nuke_lock {
  $db->rmlockable($param1) or return 0;
  return 1;
}

sub perf_lock_unlock {
  my @paths = map randpath, (1..100);
  my @testpaths = @paths;
  my $bench = eval {
    Benchmark::timeit(scalar @paths, sub {
      my $param = { path => pop @testpaths, user => $user1 };
      $db->lock($param) or die;
      $db->unlock($param) or die;
    });
  };

  return 0 if $@;
  my $locks_per_s = $bench->[-1] / ($bench->[1] + $bench->[2]);
  return 0 if $locks_per_s < 10; # this would be pathetic
  $db->rmlockable({ path => $_, user => $user1 }) or return 0 for @paths;
  return 1;
}

