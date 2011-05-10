package Source::Iterator::LineMode;
use strict;

use base 'Source::Iterator';

use Util::Test qw(ASSERT); #for testing only

#==============================================================================

=head1 NAME

Source::Iterator::LineMode - Line iterator

=head1 SYNOPSIS

use Source::Iterator::LineMode;
my $iter = new Source::Iterator::LineMode($file);
while (defined(my $line = $iter->next)) { .

=head1 DESCRIPTION

This class provides an iterator which is reads input in line-oriented mode.

=cut

#==============================================================================

=head1 METHODS

=cut

#==============================================================================

=head2 next()

Mandatory method.

=cut

sub next($) {
    my($self) = @_;

    return if !$self->initialize();
    ${$self->{src}} =~ /(.*)\n/og;
    $self->savePos;
    return $1;
}

1;

#==============================================================================

=head1 AUTHOR

Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<SourceIterator>

=cut

1;
