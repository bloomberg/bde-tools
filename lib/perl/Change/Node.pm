package Change::Node;

use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  bless $self, $class;
  return $self;
}

1;

