package BDE::Object::Unthreaded;
use strict;

use Util::Message qw(debug);

BEGIN { debug "threads not detected - loading no-op support"; }

#==============================================================================

=head1 NAME

BDE::Object:Unthreaded - No-op extensions to BDE::Object for unthreaded apps

=head1 SYNOPSIS

    #use threads; #<<<no threads loaded so no thread support
    use BDE::Object;

    my $shared_object=shared BDE::Object; #shared == new if unthreaded

=head1 DESCRIPTION

This module implements the same methods as L<BDE::Object::Threaded> but as
no-ops. This allows code written to use threaded objects to run in
unthreaded applications (without data sharing, of course).

Note that unlike L<BDE::Object::Threaded/share>, the implementation in this
module does not copy the original structure and simply returns the passed
reference.

See L<BDE::Object::Threaded> for more information.

=cut

#==============================================================================

package BDE::Object;

#==============================================================================

{
    no warnings 'once';
    *shared=\&new;
}

sub share ($$) {
    return $_[1];
}

#==============================================================================

1;
