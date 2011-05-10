package Build::Option::Dimension::CompilerVersion;
use strict;

use base 'Composite::Dimension::Version';

use constant DEFAULT => "0";

use constant DIMENSION_CV => "BDE_COMPILERVERSION_FLAG";

#==============================================================================

=head1 NAME

Build::Option::Dimension::CompilerVersion - Implement dimensional collapse of
compiler version.

=head1 DESCRIPTION

This dimension collapse module collapses the sixth element of the UPLID, the
compiler version. See L<Composite::Dimension::Version> for the collapse
algorithm.

The version for comparison is derived from the build option
C<BDE_COMPILERVERSION_FLAG>. See C<default.opts> for the configured derivation
of this option. The default version is C<0>.

=cut

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
