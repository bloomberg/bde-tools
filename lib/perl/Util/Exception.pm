package Util::Exception;

use overload
  q{""} => \&message,
  q{0+} => \&code,
  q{bool} => \&iserror,
  fallback => 1;

use base qw/Exporter/;
our $VERSION = '0.01';
our @EXPORT_OK = qw(exception);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

use strict;

sub exception { return new(__PACKAGE__, @_) }

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = [ @_ ];
  bless $self => $class;
  return $self;
}

sub message { shift->[0] };
sub code { shift->[1] };
sub iserror { shift->[1] ? 1 : 0 };

1;

