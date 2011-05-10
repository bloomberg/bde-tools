package SCM::TransactFS::SVN::Prepare;

use base qw(SCM::TransactFS::Filter);
use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = $class->SUPER::new(@_);
  return $self;
}

sub init {
  my ($self, $arg) = @_;
  $self->SUPER::init(@_);
  return $self;
}

sub tfs_filter {
  my ($self, @inops) = @_;
  my @outops;

  for my $op (@inops) {
    if ($op->{action} eq 'mv') {
      # with current svn, clients must expand mv => cp + rm
      # (see subversion issue 898)

      my (%op_cp, %op_rm);

      @op_cp{keys %$op} = values %$op;
      $op_cp{action} = 'cp';
      $op_cp{source_temporal} = $op->{base_temporal};

      @op_rm{keys %$op} = values %$op;
      $op_rm{action} = 'rm';
      $op_rm{target_path} = $op->{source_path};
      delete $op_rm{source_path};

      push @outops, \%op_cp, \%op_rm; 
    }
    else {
      push @outops, $op;
    }
  }
 
  # canonicalize paths to avoid complaints from svn
  # (FIXME this entails too much dwim: users can pass in ///path/to//foo/?)

  my @pathfields = qw(target_path source_path content_path);

  for my $op (@outops) {
    for my $field (grep exists $op->{$_}, @pathfields) {
      $op->{$field} =~ s{/+}{/}g;
      $op->{$field} =~ s{/$}{};
    }
  }

  return \@outops;
}

1;

