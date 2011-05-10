package SCM::TransactFS::CS::ToCS;

use base qw(SCM::TransactFS::Consumer);
use Change::Set;
use Change::File;
use Change::Identity qw(identifyProductionName deriveTargetfromName);
use BDE::Util::Nomenclature qw(getCanonicalUOR);
use Change::Symbols qw(
  STATUS_ACTIVE STATUS_ROLLEDBACK
  FILE_IS_NEW FILE_IS_CHANGED FILE_IS_UNCHANGED
  FILE_IS_UNKNOWN FILE_IS_REMOVED FILE_IS_RENAMED
  FILE_IS_COPIED
);
use Storable qw();
use File::Basename;
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

sub tfs_write {
  my ($self, $cs, @ops) = @_;

  my %cfstatus =
  ( 
    add   => FILE_IS_NEW,
    mk    => FILE_IS_NEW,
    write => FILE_IS_CHANGED,
    patch => FILE_IS_CHANGED,
    rm    => FILE_IS_REMOVED,
    mv    => FILE_IS_RENAMED,
    cp    => FILE_IS_COPIED,
  );

  for my $op (@ops) {
    my %cfinit;

    if ($op->{action} eq 'cp') {
      # FIXME for copies, overload source to hold the temporal origin
      $cfinit{source} = $op->{source_path}.'@@'.$op->{source_temporal};
    }
    elsif ($op->{node_kind} eq 'file' &&
           grep $_ eq $op->{action}, qw(add write patch)) {
      $cfinit{source} = $op->{content_path} or
        die "Content path required for file changes.";
    }
    else {
      $cfinit{source} = $op->{target_path};
    }

    my $dir;

    $dir = dirname($op->{target_path}) if $op->{node_kind} eq 'file';
    $dir = $op->{target_path} if $op->{node_kind} eq 'dir';

    $cfinit{destination} = $op->{target_path};
    $cfinit{destination} =~ s{([^/])$}{$1/} if $op->{node_kind} eq 'dir';
    $cfinit{type} = $cfstatus{$op->{action}};
    $cfinit{target} = deriveTargetfromName($dir, $cs->getStage);
    $cfinit{library} = getCanonicalUOR($cfinit{target}) || $cfinit{target};
    $cfinit{production} = identifyProductionName($cfinit{library}, $cs->getStage);

    $cs->addFile(Change::File->new(\%cfinit));
  }
 
  return 1;
}

1;

