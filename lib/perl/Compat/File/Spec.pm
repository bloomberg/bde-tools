package Compat::File::Spec;
use strict;
use base 'File::Spec';
use Cwd;

#==============================================================================

=head1 NAME

Compat::File::Spec - Compatibility wrapper for older File::Spec implementations

=head1 SYNOPSIS

    use Compat::File::Spec;

    $x=Compat::File::Spec->catfile('a', 'b', 'c');

    $abs=rel2abs("my/relative/path");

=head1 DESCRIPTION

Use this module in place of the standard L<File::Spec> to use more recent
features of that module on older versions of Perl that do not supply them
as standard.

This wrapper module adds C<rel2abs> if (and only if) the underlying
L<File::Spec> module is determined not to provide it.

=cut

#==============================================================================

sub _my_rel2abs {
    my ($self,$path,$base ) = @_;

    # Clean up $path
    if ( ! $self->file_name_is_absolute( $path ) ) {
        # Figure out the effective $base and clean it up.
        if ( !defined( $base ) || $base eq '' ) {
            $base = cwd() ;
        }
        elsif ( ! $self->file_name_is_absolute( $base ) ) {
            $base = $self->_my_rel2abs( $base ) ;
        }
        else {
            $base = $self->canonpath( $base ) ;
        }

        # Glom them together
        $path = $self->catdir( $base, $path ) ;
    }

    return $self->canonpath( $path ) ;
}

unless (File::Spec->can('rel2abs')) {
    no warnings 'once';
    *rel2abs=\&_my_rel2abs;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net), from code in (newer versions of)
L<File::Spec>.

=head1 SEE ALSO

L<File::Spec>

=cut

1;
