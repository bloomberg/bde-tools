package Composite::Dimension::States;
use strict;
use base 'Symbols';

#==============================================================================

=head1 NAME

Composite::Dimension::States - Define constants for dimension state

=head1 SYNOPSIS

  use Composite::Dimension::States qw(COLLAPSED UNCOLLAPSED IGNORED);

=head1 DESCRIPTION

This module provides exportable constants for the state of a dimension, in
contexts where that makes useful sense. The currently defined states are:

  COLLAPSED
  UNCOLLAPSED
  IGNORED

=cut

#==============================================================================

=head1 SEE ALSO

L<Composite::ValueSet>, L<Composite::Dimension>

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;

#==============================================================================

1;

__DATA__

COLLAPSED	=> 1
UNCOLLAPSED	=> 2
IGNORED		=> 3
