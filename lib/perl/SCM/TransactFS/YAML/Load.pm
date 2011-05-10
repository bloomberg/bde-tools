package SCM::TransactFS::YAML::Load;

use base qw(SCM::TransactFS::Producer);
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
  $self->{_infh} = $arg->{infh};
  return $self;
}

sub tfs_read {
  my ($self) = @_;
  my $infh = $self->{_infh};
  local $/ = "\n---";

  my $yaml = <$infh>;
  return undef if not defined $yaml;  # input eof
  chomp $yaml;
  $yaml = $yaml . "\n";

  return YAML::Load($yaml);
}

1;

