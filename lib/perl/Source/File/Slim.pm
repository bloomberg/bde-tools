package Source::File::Slim;
use strict;

use Source::File;
use base 'Source::File';
use Source::Util::ParseTools qw(slimSrcLines);

#==============================================================================

=head1 NAME

Source::File::Slim - Abstract representation of a source file without comments

=head1 SYNOPSIS

    my $source = new Source::File::Slim($filepath);
    print "$source\n";

=head1 DESCRIPTION

C<Source::File::Slim> is a subclass of L<Source::File> that overloads the
behaviour of a source file object in string evaluation context to return the
source in I<slim> format, i.e. without comments but preserving line order.
See the L<Source::File> class for more information.

=cut

#==============================================================================

sub fromString ($$) {
    my ($self,$init)=@_;

    $self->SUPER::fromString($init);
    $self->getSlimSource();
    return $self;
}

#------------------------------------------------------------------------------

=head2 getSlimSource()

Return a reference to the string representation of the source content, with
comments removed but line order and numbering preserved.

=cut

sub getSlimSource () {
    my $self=shift;

    unless ($self->{slimSource}) {
	$self->{slimSource} = slimSrcLines($self->getFullSource());
    }

    $self->{source} = $self->{slimSource};
    return $self->{slimSource};
}

#==============================================================================

=head1 AUTHOR

Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<Source::File>

=cut

1;
