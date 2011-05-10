package Build::Option::Dimension::Arch;
use strict;

use base 'Composite::Dimension::WildEq';

use constant DEFAULT => "sparc";

#==============================================================================

=head1 NAME

Build::Option::Dimension::Arch - Implement dimensional collapse of Arch

=head1 DESCRIPTION

This dimension collapses the machine architecture. The supplied dimension is
generally generated from C<uname>. See L<BDE::Build::Uplid>.

=cut

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
