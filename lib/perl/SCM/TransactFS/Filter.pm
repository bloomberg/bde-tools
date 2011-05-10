package SCM::TransactFS::Filter;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  bless $self => $class;
  $self->init(@_);
  return $self;
}

sub init {
  my $self = shift;
  return $self;
}

sub tfs_open { return 1; }
sub tfs_close { return 1; }
sub tfs_filter { return undef; }

1;

