package SCM::TransactFS::Native::Import;

use base qw(SCM::TransactFS::Producer);
use Fcntl qw(:mode);
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

sub get_base_temporal {
  my ($self, $path, $nodekind) = @_;
  return 'S:HEAD';
}

sub get_action {
  my ($self, $path, $nodekind) = @_;
  return 'add' if $nodekind eq 'file';
  return 'mk' if $nodekind eq 'dir';
  return undef;
}

sub rewrite_path {
  my ($self, $path, $nodekind) = @_;
  return $path;
}

sub get_node_kind {
  my ($self, $path, $fstat) = @_;
  return 'file' if S_ISREG($fstat->[2]);
  return 'dir' if S_ISDIR($fstat->[2]);
  return undef;
}

sub tfs_read {
  my ($self) = @_;
  my $infh = $self->{_infh};

  my $path = <$infh>;
  return undef if not defined $path;
  chomp $path;

  my @fstat = stat $path;
  my $nodekind = $self->get_node_kind($path, \@fstat);

  if (not defined $nodekind) {
    return undef, "Error: unsupported node kind at path $path.";
  }

  my %op =
  (
    action => $self->get_action($path, $nodekind),
    node_kind => $nodekind,
    base_temporal => $self->get_base_temporal($path, $nodekind),
    target_path => $self->rewrite_path($path),
  );

  $op{content_path} = $path if $nodekind eq 'file';

  return \%op;
}

1;

