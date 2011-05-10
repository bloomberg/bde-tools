package SCM::TransactFS::YAML::Dump;

use base qw(SCM::TransactFS::Consumer);
use YAML qw();
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
  $self->{_outfh} = $arg->{outfh};
}

sub tfs_write {
  my ($self, $op) = @_;
  my $outfh = $self->{_outfh};
  return print $outfh YAML::Dump($op);
}

1;

