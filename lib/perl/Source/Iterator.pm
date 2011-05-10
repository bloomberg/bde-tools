package Source::Iterator;
use strict;

use base 'BDE::Object';
use Source::LineNumber;

use overload '""' => "next", '0+' => "lineNumber", fallback => 1;

use Util::Test qw(ASSERT); #for testing only

#==============================================================================

=head1 NAME

Source::Iterator - Base class for source iterators

=head1 SYNOPSIS

This class is not directly invoked.  It is invoked by a sub-class, e.g.,

use base 'Source::Iterator';

=head1 DESCRIPTION

This class provides a number of methods common to all iterators and cooperates
with them as necessary.  An 'Iterator' is an abstract class and an instances
of it should not be created (they can be, but the 'next' will throw).

'Iterator' maintains state for each instance, which means that multiple 
iterators can be created for the same input.  The instances can also reset to
the beginning of the input.

In detail, the module provides:

    - A constructor, which also creates a LineNumber object
    - A method to get the current line number (which is based on the current
      position)
    - Methods to manipulate the current position (pos) within the input
    - An initialize routine that all iterators must call as their first act;
      this routine:
          * restores the current position for the iterator instance
          * returns undef if the end of input has been reached
          * "skips" unwanted lines via a (configurable) regexp

An iterator sub-class is then constructed as follows:

    - use base 'Source::Iterator';
    - provide a 'next' method, which must do two things to cooperate with 
      this module:
          * as the first statement: "return if !$self->initialize();"
          * as the last statement before returning: "$self->savePos"

Note that a reference must be passed to the constructor, thereby reducing
unnecessary duplication of the input in memeory.  A proviso to this is that
the current position (pos) of the input will be lost to the client once an
iterator is created.

=cut

#==============================================================================

=head1 METHODS

=cut

#==============================================================================

=head2 CONSTRUCTOR()

Initialize a new source iterator from the supplied file contents.

=cut

sub fromString ($$) {
    my($self,$src) = @_;

    $self->throw("not a reference in Iterator ctor") if !ref($src);
    $self->{src} = $src;
    $self->resetPos;
    $self->{lineNumberObj} = new Source::LineNumber($self->{src});
    $self->{currentLineNumber} = 0;
    $self->{skipLineRE} = qr/\s*?\n/o;
    return $self;
}

#------------------------------------------------------------------------------

=head1 METHODS

=cut

#------------------------------------------------------------------------------

=head2 next()

This method is purposely not implemented; throw if client invokes it.

=cut

sub next($) { $_[0]->throw("No next method implemented for $_[0]"); }

#------------------------------------------------------------------------------

=head2 setSkipLineRE()

Set a regular expression which the iterator will then skip.

=cut

sub setSkipLineRE ($$) {
    my($self,$pat) = @_;

    $self->{skipLineRE} = $pat;
}

#------------------------------------------------------------------------------

=head2 lineNumber()

Return current line number.

=cut

sub lineNumber ($) {
    my($self) = @_;

    return $self->{currentLineNumber};
}

#------------------------------------------------------------------------------

=head2 resetPos()

Reset position of iterator instance to 0.

=cut

sub resetPos($) {
    my($self) = @_;

    $self->{pos} = 0;
    $self->restorePos;
}

#------------------------------------------------------------------------------

=head2 savePos()

Save current position of iterator instance.

=cut

sub savePos($) { 
    my($self) = @_;

    $self->{pos} = pos(${$self->{src}});

}

#------------------------------------------------------------------------------

=head2 restorePos()

Restore the position as saved by savePos.

=cut

sub restorePos($) {
    my($self) = @_;

    pos(${$self->{src}}) = $self->{pos};
}

#------------------------------------------------------------------------------

=head2 initialize()

Initialize iterator before next read.  Skip unwanted lines.  Set the current
line number based on the current position.  Return undef if end of input is
reached.

=cut

sub initialize ($) {
    my($self) = @_;

    $self->restorePos;
    return if pos(${$self->{src}}) == length(${$self->{src}});
    if ($self->{skipLineRE} ne "") {
        while (${$self->{src}} =~ /\G($self->{skipLineRE})/) {
            pos(${$self->{src}}) += length($1);
        }
        return if pos(${$self->{src}}) == length(${$self->{src}});
    }
    $self->{currentLineNumber} = 
      $self->{lineNumberObj}->getLineNumber(pos(${$self->{src}}));
    return 1;
}

#==============================================================================

=head1 AUTHOR

Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<LineNumber>

=cut

1;
