package Build::Option;

use base 'Composite::Value';

use constant DEFAULT_VALUEITEMCLASS => 'Build::Option::Raw';

#==============================================================================

=head1 NAME

Build::Option - Abstract representation of a build option

=head1 SYNOPSIS

    my $option=new Build::Option();
    $option->addValueItems(@valueitems);
    print $option->getValue();

=head1 DESCRIPTION

The C<Build::Option> class is a straight subclass of L<Composite::Value> and
implements no functionality of its own except to nominate L<Build::Option::Raw>
as the value item object class that it manages.

C<Build::Option> instances are rarely created directly. More usually, they are
created by a L<Build::Option::Set> instance, from raw options parsed
by C<Build::Option::Parser>.

=cut

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Build::Option::Set>, L<Build::Option::Raw>, L<Composite::Value>

=cut

1;
