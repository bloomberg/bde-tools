package SCM::TransactFS::Native::Export;

use base qw(SCM::TransactFS::Consumer);
use SCM::Util::Slurp qw(:all);
use IO::File;
use Errno qw(:POSIX);
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
  $self->{_base_path} = $arg->{base_path};
  return $self;
}

sub rewrite_path {
  my ($self, $path) = @_;
  my @parts = split m{/}, $path;
  @parts = grep length, @parts; # strip root path
  unshift @parts, $self->{_base_path} if defined $self->{_base_path};
  return join '/', @parts;
}

sub tfs_write {
  my ($self, $op) = @_;
  my $path = $self->rewrite_path($op->{target_path});
  my $opname = $op->{action} . $op->{node_kind};

  if ($opname eq 'mkdir') {
    _mkdirp($path);
  }
  elsif ($opname eq 'addfile') {
    _mkdirp(_dirname($path));
    my $outfh = IO::File->new("> $path")
      or die "Error opening $path for writing: $!.";
    my $in = _content_streamable($op)
      or die "Error acquiring content from op: $!.";
    slurp($in, $outfh);
    ($outfh, $in) = undef, undef;
  }
  else {
    # TODO implement all local fs operations
    die "Unimplemented operation: $opname.";
  }

  return 1;
}

sub _mkdirp {
  my $path = shift;
  my @parts = split m{/}, $path;
  my @mkparts;

  local $!;

  while (@parts) {
    push @mkparts, shift @parts;
    my $mkpath = join '/', @mkparts;
    mkdir $mkpath;
    die "mkdir $mkpath failed: $!" if $! && !$!{EEXIST};
  }

  return 1;
}

sub _dirname {
  my $path = shift;
  my @parts = split m{/}, $path;
  return join '/', @parts[0..$#parts-1];
}

sub _content_streamable {
  my $op = shift;

  if (exists $op->{content_path}) {
    my $infh = IO::File->new($op->{content_path})
      or die "Error opening $op->{content_path} for read: $!.";
    return $infh;
  }

  return $op->{content_stream} if exists $op->{content_stream};
  return $op->{content} if exists $op->{content};
  return undef;
}

1;

