package Build::Option::Dimension::OSVersion;
use strict;

use base 'Composite::Dimension::Version';

# no DEFAULT_OSVER

#==============================================================================

=head1 NAME

Build::Option::Dimension::OSVersion - Implement dimensional collapse of OS
version.

=head1 DESCRIPTION

This dimension collapse module collapses the fourth element of the UPLID, the
operating system version. See L<Composite::Dimension::Version> for the collapse
algorithm.

The version for comparison is derived from the L<BDE::Build::Uplid> module,
which in turn extracts the operating system using C<uname> or a variant
(depending on the platform of invocation). The default version is C<0>.

=cut

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
