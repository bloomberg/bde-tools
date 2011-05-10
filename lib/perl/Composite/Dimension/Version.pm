package Composite::Dimension::Version;
use strict;

use base 'Composite::Dimension';

#==============================================================================

=head1 NAME

Composite::Dimension::Version - Basic version string comparison superclass

=head1 DESCRIPTION

This dimensional collapse superclass provides the means to collapse a
dimension according to version string criteria. As version strings can be
complex and varied, the algorithm attempts to handle a wide range of possible
version formats, but may not handle every possible circumstance.

The match criteria is strictly 'greater than or equal to', so a raw option with
a higher version number (or no version number) must be used to override a raw
option with a lower one.

=head2 Version Matching Algorithm

=over 4

=item *

The test version string is compared to the current version string by
splitting both strings according to the version delimiter, by default a literal
dot.

=item *

The number of elements produced by each string is counted, and the
element pairs (one from the test version string and one from the current
version string) are in turn compared, up to the highest mutual element number.

=item *

For each element pair, the version element strings are again split
according to the version element delimiter, by default a regular expression
that matches the boundary between digit and non-digit characters. The
subelements produced from each string (test and current) are compared against
each other.

=item *

Subelements are compared numerically if both the test and current
subelements under test are fully numeric, or compared as strings otherwise.

=back

=head2 Version Matching Methods

The methods that implement this algorithm can be overloaded to alter the
version comparison logic:

=over 4

=item matchVersion

Matches version strings. Splits strings according to the version element
delimiter, and passes them to L<"matchVersionElement">. Overloading this
method completely replaces the version matching logic, exception straight
string equality and wildcard C<*> matching.

=item matchVersionElement

Matches version elements. Splits strings according to the version element
delimiter, and passes them to L<"matchVersionSubelement">. Overloading this
method replaces the matching logic for version elements.

=item matchVersionSubelement

Matches version subelements. Carries out either a numeric C<E<gt>=> comparison
if both subelements are numeric, or a string C<ge> comparision otherwise.

=back

These methods, and the methods to set and get the delimiters, are described
in more detail below.

=cut

#==============================================================================

=head1 METHODS

The following methods are available:

=cut

#--- Version String

=head2 matchVersion($test,$current)

Match the test version string against the current version string. This
implementation splits both the test and current version strings into elements
using a regular expression delimiter that by default is set to:

    \.

This expression splits on a literal dot, which is the usual delimiter that
versions strings use to denote separation of their constituent elements.

The subelements extracted are passed in pairs, one from the test element and
one from the current element, to L<"matchVersionEelement">, up to the last
element. If the number of elements is different, the excess elements from
either the test or current version string (whichever produced more elements)
are discarded. If all tested subelements match, returns 1, otherwise returns 0.

=cut

sub matchVersion ($$$) {
    my ($self,$testv,$currentv)=@_;

    return 1 if $testv eq $currentv;

    my $delim=$self->getVersionDelimiter();

    # split version strings into elements
    my @tv=split $delim,$testv;
    my @dv=split $delim,$currentv;

    # compare version up to the end of the smaller one (if differently sized.
    my $segments = (@tv > @dv) ? $#dv : $#tv;

    foreach my $segment (0..$segments) {
	my $match = $self->matchVersionElement($tv[$segment],$dv[$segment]);
	return 1 if $match == 1;
	return 0 if $match == -1;
    }

   return 1; #all element tests returned 0, so equal. Since the strings
             #were not equal this implies a leading zero in a numeric test.
}

=head2 getVersionDelimiter()

Get the regular expression delimiter used by L<"matchVersion"> to extract
elements from a version element string.

=cut

sub getVersionDelimiter ($) {
    $_[0]->{versiondelimiter}=quotemeta '.'
      unless defined $_[0]->{versiondelimiter};
    return $_[0]->{versiondelimiter};
}

=head2 setVersionDelimiter($delimiter)

Set the I<regular expression> delimiter used by L<"matchVersion"> to extract
elements from a version element string.

=cut

sub setVersionDelimiter ($$) {
    $_[0]->{versiondelimiter}=$_[1];
}

#--- Element

=head2 matchVersionElement($testel,$currentel)

Match the elements extracted by L<"matchVersion">. If the test and current
version elements are string-equivalent, returns 0 (meaning equal). Otherwise,
this implementation further splits both the test and current version elements
into subelements using a regular expression delimiter that by default is set
to:

    (?<=\d)(?=\D)|(?<=\D)(?=\d)

This expression splits, without consuming any characters, on boundaries between
digits and non-digits, so C<AB12CD34> is split into C<AB>, C<12>, C<CD>, and
C<34>. The delimiter may be changed with L<"setVersionElementDelimiter">
above.

The subelements extracted are passed in pairs, one from the test element and
one from the current element, to L<"matchVersionSubelement">, up to the last
subelement. If the number of subelements is different, the excess subelements
from either the test or current version element (whichever is longer) are
discarded. The first subelement pair to return a non-zero comparison result
(i.e. 1 or -1, see L<"matchVersionSubelement">) ends the test, or if all
subelements tests return 0, 0 is returned.

=cut

sub matchVersionElement ($$$) {
    my ($self,$testv,$currentv)=@_;

    #DBG print "E [[ $testv <- $currentv ]]\n";

    return 0 if $testv eq $currentv;

    my $delim=$self->getVersionElementDelimiter();

    # split version strings into elements
    my @tv=split $delim,$testv;
    my @dv=split $delim,$currentv;

    # compare version up to the end of the smaller one (if differently sized.
    my $segments = (@tv > @dv) ? $#dv : $#tv;

    foreach my $segment (0..$segments) {
	my $match = $self->matchVersionSubelement($tv[$segment],$dv[$segment]);
	#DBG print "SEG:$segments:$segment:$tv[$segment],$dv[$segment]:GES:$match=M\n";
	return $match if $match; #if result is -1 or 1, return it immediately
    }

    return 0;
}

=head2 getVersionElementDelimiter()

Get the regular expression delimiter used by L<"matchVersionElement"> to
extract subelements from a version element string.

=cut

sub getVersionElementDelimiter ($) {
    $_[0]->{versionelementdelimiter}=qr/(?<=\d)(?=\D)|(?<=\D)(?=\d)/
      unless defined $_[0]->{versionelementdelimiter};
    return $_[0]->{versionelementdelimiter};
}

=head2 setVersionElementDelimiter($demimiter)

Set the I<regular expression> delimiter used by L<"matchVersionElement"> to
extract subelements from a version element string.

=cut

sub setVersionElementDelimiter ($$) {
    $_[0]->{versionelementdelimiter}=$_[1];
}

#--- Subelement

=head2 matchVersionSubelement($test,$current)

Match the subelements extracted by L<"matchVersionElement">. This
implementation checks to see if both the test and current values are fully
numeric, and if so, does a numeric comparison. Otherwise, it does a string
comparison. Returns 1 if the test subelement is greater than the current
subelement, 0 if it is equal to it, and -1 if it is less than it, in the
same manner as C<cmp> and C<E<le>=E<gt>>.

=cut

sub matchVersionSubelement ($$$$) {
   my ($self,$testv,$currentv)=@_;

   #DBG print "SE [[[ $testv <- $currentv ]]]\n";

   if ($testv =~ /^\d+$/ and $currentv =~ /^\d+$/) {
       return $currentv <=> $testv;
   }

   return $currentv cmp $testv;
}

#------------------------------------------------------------------------------

sub match {
    my ($self,$value,$dimensionvalue)=@_;

    $self->throw("What's this? $value") unless ref $value;

    my $testvalue=$value->{$self->getAttribute()};
    return 1 if (not $testvalue) or $testvalue eq '*';
    return 1 if (not $dimensionvalue) or $dimensionvalue eq '*';
          #<<<TODO: review this idea later

    ###print "DBG >> [ $testvalue <- $dimensionvalue ] $value\n";

    return $self->matchVersion($testvalue => $dimensionvalue);
}

sub matchDefault {
    return 1; #all versions match in the face of no requested version
}

#==============================================================================

=head1 SEE ALSO

L<Composite::Dimension>, L<Composite::Dimension::WildEq>

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
