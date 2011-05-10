package BDE::Object::Threaded;
use strict;

use Util::Message qw(debug);

BEGIN { debug "threads detected - loading thread support"; }

#==============================================================================

=head1 NAME

BDE::Object:Threaded - Extensions to BDE::Object to support shared data

=head1 SYNOPSIS

    use threads;
    use BDE::Object;

    my $shared_object=shared BDE::Object;

=head1 DESCRIPTION

This module extends L<BDE::Object> with a new constructor and a new method
to support the creation of objects that are shared between threads. It is
automatically loaded by L<BDE::Object> when a threaded application is detected.

=cut

#==============================================================================

package BDE::Object;

use threads::shared qw();
use Scalar::Util qw(reftype);

#==============================================================================

=head1 CONSTRUCTORS

=head2 shared([$args])

This method is a base object constructor. It is identical in operation to
L<BDE::Object/new>, except that the returned object is shared between threads.

=cut

sub shared ($;$) {
    my ($proto,$args)=@_;

    my $self=&threads::shared::share({});
    my $class=(ref $proto) || $proto;

    $self->initialise($args);
    $self=$self->share(); # replace non-shared original with shared copy
    bless $self,$class;

    return $self;
}

=head1 METHODS

=head2 share($reference)

Take the passed reference to an arbitrarrily complex data structure and return an identical data structure that is shared between threads.

In this implementation the shared data structure is a new structure that
is identical to the original but a copy of it. This means that variables
holding references to parts of the old structure will still reference the
unshared structure and not the new shared one. I<This behaviour may change
and should not be relied upon to preserve the original structure.>

=cut

sub share ($$) {
    my ($self,$in)=@_;

    my $out : shared;

    if (ref $in) {
      SWITCH: foreach my $type (reftype $in) {
	    $type=~/^ARRAY/ and do  {
		$out=&threads::shared::share([]);
		foreach my $el (@$in) {
		    push @$out, $self->share($el);
		}
	    };
	    $type=~/^HASH/ and do {
		$out=&threads::shared::share({});
		foreach my $key (keys %$in) {
		    $out->{$key}=$self->share($in->{$key});
		}
	    };
	    $type=/^SCALAR/ and do {
		$out=$self->share($$in);
	    };
	}
    } else {
	$out=${ &threads::shared::share(\$in); };
    }
	
    return $out;
}

#==============================================================================

1;
