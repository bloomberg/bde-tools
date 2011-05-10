package BDE::Object;
use strict;

# load the thread support if the 'threads' module has been loaded.
use if scalar(@threads::ISA),'BDE::Object::Threaded';
use if !scalar(@threads::ISA),'BDE::Object::Unthreaded';

# accessible as BDE::Object::croak, etc.
use Carp qw(croak carp confess);

use Symbols qw(BACKTRACE);

#------------------------------------------------------------------------------

# default 'naked' constructor - create object without initialisation.
# note that the $ref argument is only applicable to object that explicitly
# do not want to use new() or initialise().
sub create ($;$) {
    my ($proto,$ref)=@_;
    $ref = {} unless $ref;
    my $class=(ref $proto) || $proto;

    return bless $ref,$class;
}

# clone constructor - create a new object using the data of an existing one.
# a 'semi-shallow' copy is made using the _copy class method below, so that
# unblessed hash and array references are copied across, but other reference
# types are left alone, notably blessed references. Put another way, the
# object's 'own' data is copied but has-a relationships are not.
sub clone ($) {
    my $self=shift;

    my $other={ map {
        $_ => $self->_copy($self->{$_})
    } (keys %$self) };
    return bless $other,ref $self;
}

sub _copy {
    my ($self, $thing) = @_;

    return $thing unless ref($thing);

  SWITCH: foreach my $ref (ref $thing) {
	$ref eq 'ARRAY' and do {
	    return [ map {
                $self->_copy($_)
            } @$thing ];
	};
	$ref eq 'HASH' and do {
	    return { map {
                $_ => $self->_copy($thing->{$_})
            } (keys %$thing) };
	};
	$ref eq 'REF' || $ref eq 'SCALAR' and do {
	    return $self->_copy($$thing);
	};
    }

    return $thing; #object? filehandle? shallow copy
}

#------------------------------------------------------------------------------

# default scalar initialiser: call fromString if it exists, otherwise barf
# note that fromString should return a new object if $self is a class.
# to initialise from a different kind of scalar, overload this method.
sub initialiseFromScalar ($$) {
    my ($self,$string)=@_;

    if ($self->can("fromString")) {
	$self->fromString($string);
	return 1; # done
    }

    $self->throw("Unable to initialiseFromScalar: ".
	  "subclass does not override or supply fromString method");
}

# default array initialiser
sub initialiseFromArray ($$) {
    my ($self,$aref)=@_;

    $self->throw("Initialiser passed argument not an array reference")
      unless UNIVERSAL::isa($aref,"ARRAY");

    foreach my $arg (@$aref) {
	$self->{$arg}=1;
    }

    return 0; # continue
}

# default hash initialiser: copy keys to object.
sub initialiseFromHash ($$) {
    my ($self,$href)=@_;

    $self->throw("Initialiser passed argument not a hash reference")
      unless UNIVERSAL::isa($href,"HASH");

    my $result=0; #continue;

    # look for an initialiser key in passed args
    if (exists $href->{"_INITIALISE"}) {
	$self->initialiseFromScalar(delete $href->{"_INITIALISE"});
	$result=1; # done
    }

    ####<<<< return $self if $self==$href;

    foreach my $arg (keys %$href) {
	$self->{$arg}=$href->{$arg};
    }

    return $result;
}

# default handle initialiser
sub initialiseFromHandle ($$) {
    my ($self,$fh)=@_;

    local $/=undef;
    my $input=<$fh>;
    return $self->initialiseFromScalar($input);
}

#-----

# default initialiser: initialise an object from passed argument.
# In general subclasses will overload this or one of its specialisations above
# rather than define their own new().
sub initialise ($$) {
    my ($self,$args)=@_;

    return 0 unless $args; #nothing to initialise by default, continue
    #return 0 unless $#_; #nothing to initialise by default, continue

    my $result;
    if (my $ref=ref $args) {
        SWITCH: foreach ($ref) {
	    /IO|GLOB/ and do {
		$result=$self->initialiseFromHandle($args);
		last;
	    };
	    /ARRAY/ and do {
		$result=$self->initialiseFromArray($args);
		last;
	    };
	    /HASH/ and do {
		$result=$self->initialiseFromHash($args);
		last;
	    };
	  DEFAULT:
	    # isa(BDE::Object)?
	    $result=$self->initialiseFromScalar($args);
	}
    } else {
	# not a ref at all - string initialiser
	$result=$self->initialiseFromScalar($args);
    }

    return $result;
}

#------------------------------------------------------------------------------

# default constructor; creates a 'naked' object and initialises it if asked to.
sub new ($;$) {
    my ($proto,$args)=@_;
    my $self=$proto->create();
    $self->initialise($args);
    return $self;
}

#------------------------------------------------------------------------------

# centralised and overloadable method for propagating 'exceptions' via die.
sub throw ($$) {
    my ($self,$msg)=@_;
    my $me;

    if ($self->can("getName")) {
	$me=$self->getName() || ref($self)."(unnamed)";
    } elsif ($self->can("toString")) {
	$me= (ref($self) && $self->toString())
	  || (ref($self)||"$self")."(unnamed)";
    } else {
	$me=ref($self);
    }

    if (BACKTRACE) {
	local $^W=0; #suppress strange Carp warnings
	confess "$me: $msg\n";
    } else {
        die "$me: $msg\n";
    }
}

#------------------------------------------------------------------------------

# debug routine to dump out object attributes
sub dump ($;$) {
    my ($self,$prefix)=@_;
    $prefix=$prefix?"$prefix: ":"";
    print $prefix,$self," ",scalar (keys %$self)," keys\n";
    print "  $_ => $self->{$_}\n" foreach sort keys %$self;
}
*_dump=\&dump;

#==============================================================================

1;
