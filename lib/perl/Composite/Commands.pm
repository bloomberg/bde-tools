package Composite::Commands;
use strict;
use base 'Symbols';

#==============================================================================

=head1 NAME

Composite::Commands - Define standard prefix strings for raw option commands

=head1 DESCRIPTION

This module provides the prefix strings that correspond to the commands used
to combine composite value items, as used by L<Composite::Value/render>.
Currently defined commands (and their prefixes) are:

  ADD          ++
  INSERT       --
  APPEND       <<
  PREPEND      >>
  OVERRIDE     !!
  RESET        ^^

See L<Composite::ValueItem/addeq> for how these commands control the result
of combining raw options together.

=cut

#==============================================================================

=head1 SEE ALSO

L<Composite::Value>, L<Composite::ValueItem>

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;

#==============================================================================

__DATA__

# Combine with space separator
ADD             => ++
INSERT          => --

# Combine, no separator
APPEND		=> <<
PREPEND         => >>

# Special
OVERRIDE	=> !!
RESET		=> ^^
