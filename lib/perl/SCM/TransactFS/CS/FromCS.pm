package SCM::TransactFS::CS::FromCS;

use base qw(SCM::TransactFS::Producer);
use Change::Set;
use Change::File;
use Change::Symbols qw(
  STATUS_ACTIVE STATUS_ROLLEDBACK
  FILE_IS_NEW FILE_IS_CHANGED FILE_IS_UNCHANGED FILE_IS_REVERTED
  FILE_IS_UNKNOWN FILE_IS_REMOVED FILE_IS_RENAMED
  FILE_IS_COPIED
);
use Meta::Change::Places qw(:all);
use Storable qw();
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
  $self->{_branchmap} = $arg->{branchmap};
  return $self;
}

sub tfs_open { my ($self) = @_; return 1; }
sub tfs_close { my ($self) = @_; return 1; }

sub tfs_read {
  my ($self, $cs) = @_;
  my @ops = map { $self->_from_cf($cs, $_) || () } $cs->getFiles;
  push @ops, $self->_from_cs_meta($cs);
  return \@ops;
}

sub _from_cs_meta {
  my ($self, $cs) = @_;

  return
  { 
    action => 'add',
    node_kind => 'file',
    base_temporal => $self->_get_cs_base_temporal($cs),
    target_path => getMetaChangePath($cs),
    content => $cs->serialise(),
  };
}

sub _from_cf {
  my ($self, $cs, $cf) = @_;
  my %op;

  my $destpath = $cf->getDestination();
  my $srcpath = $cf->getSource();
  my $status = $cf->getType();

  $op{target_path} = $destpath;
  $op{node_kind} = ($op{target_path} =~ s{/$}{}) ? 'dir' : 'file';
  $op{base_temporal} = $self->_get_cf_base_temporal($cs, $cf);
  $op{action} =
  {
    FILE_IS_NEW       , ($op{node_kind} eq 'file') ? 'add' : 'mk',
    FILE_IS_CHANGED   , ($op{node_kind} eq 'file') ? 'write' : undef,
    FILE_IS_REVERTED  , ($op{node_kind} eq 'file') ? 'write' : undef,
    FILE_IS_UNCHANGED , ($op{node_kind} eq 'file') ? 'write' : undef,
    FILE_IS_UNKNOWN   , undef,
    FILE_IS_REMOVED   , 'rm',
    FILE_IS_RENAMED   , 'mv',
    FILE_IS_COPIED    , 'cp',
  }->{$status};

  # HACK - do not commit UNCHANGED files
  return undef if $status eq FILE_IS_UNCHANGED;

  die "Change::File $destpath has unsupported status $status."
    if not defined $op{action};

  if (grep $_ eq $op{action}, qw(patch add write)) {
    $op{content_path} = $srcpath;
    $op{content_path} =~ s!root/\d+/(.*)!root/$1!;
  }

  if ($op{action} eq 'mv' || $op{action} eq 'cp') {
    # FIXME for copies, overload source to hold the temporal origin
    @op{qw(source_path source_temporal)} = (split /\@\@/, $srcpath);
  }

  my $root = getBranchRootPath();
  $op{target_path} =~ s{^root/}{$root/};
  $op{source_path} =~ s{^root/}{$root/} if exists $op{source_path};

  return \%op;
}

# FIXME rewrite when Change::{File,Set} carry base revision, or via co tracking
# for now just do something that amounts to clobber mode

sub _get_cs_base_temporal { my ($cs) = @_; return 'S:HEAD'; }
sub _get_cf_base_temporal { my ($cs, $cf) = @_; return 'S:HEAD'; }

1;

