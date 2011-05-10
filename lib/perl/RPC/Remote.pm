package RPC::Remote;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  $self->{package} = shift if @_;
  $self->{id} = shift if @_;
  $self->{client} = shift if @_;

  return bless $self => $class;
}

sub package { return shift->{package}; }
sub id { return shift->{id}; }
sub client { return shift->{client}; }

1;

