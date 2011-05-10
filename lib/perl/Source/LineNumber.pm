package Source::LineNumber;
use strict;

#use overload '""' => "lineNumber", fallback => 1;

use base 'BDE::Object';

#==============================================================================

=head1 NAME

Source::LineNumber - Maps text character positions to line numbers.

=head1 SYNOPSIS

use Source::LineNumber;
my lineNumberObj = new Source::LineNumber(\$input);

=head1 DESCRIPTION

C<Source::LineNumber> takes text input and creates an internally-held table 
which maps the character positions of the input to line numbers, where each 
line is a sequence of characters termined by a newline ('\n').  A method is 
provided which, when provided with a character position, returns the 
appropriate line number.  

=head1 CAVEATS

Line numbers start from 1.

If a position which is out of bounds is passed to the query method, 
undef is returned.

=head1 TEST DRIVERS

A simple breathing test is provided.  To invoke:

perl -w -MSource::LineNumber -e "Source::LineNumber->test"

=cut

#==============================================================================

=head1 METHODS

=cut

#==============================================================================
# Constructor support

=head2 CONSTRUCTOR()

Supply a scalar reference.  Return $self if input is empty or only whitespace.
Append newline to input if not present.

=cut

sub fromString($$) {
    my($self, $input) = @_;

    $self->throw("not a ref") unless ref($input);

    # return is input is only whitespace
    return $self if $$input =~ m-^\s*$-o;

    # append newline if not there
    $$input .= '\n' if $$input !~ /\n$/;

    # save current pos (undef checked for on restore)
    my $savePos = pos(${$input});

    # create map 
    my %lineNumbers;
    my $lineNumber = 1;
    my $leftPos = 0;

    while (${$input} =~ /.*?\n/go) {
        my $rightPos = pos(${$input})-1;
        while ($leftPos <= $rightPos) {
            $lineNumbers{$leftPos} = $lineNumber;
            $leftPos++;
        }
        $lineNumber++;
    }

    # save map in object
    $self->{pos2LineNumber} = \%lineNumbers;

    # restore pos if set
    pos(${$input}) = $savePos if defined($savePos);
}

#------------------------------------------------------------------------------

=head2 getLineNumber()

Given a position return the appropriate line number.

=cut

sub getLineNumber($$) {
    my($self,$pos) = @_;

    return $self->{pos2LineNumber}->{$pos};
}

#==============================================================================

sub test() {
    my $f = new Source::LineNumber(\"A\nB\nC\n");

    for (my $i = 0; $i < 10; $i++) {
        my $j = $f->lineNumber($i);
        print "$j\n" if $j;
    }
}

#==============================================================================

=head1 AUTHOR

Ralph Gibbons, rgibbons1@bloomberg.net

=cut

1;

#==============================================================================

