package BDE::FileSystem::MakeType;
use strict;

use overload '0+' => "toNumber",
             '""' => "toString",
             '==' => "isMakeType",
             fallback => 1;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

#------------------------------------------------------------------------------

use vars qw($GMAKE $NMAKE $UNDEF $MAX_MAKETYPE);

$UNDEF=0;
$GMAKE=1;
$NMAKE=2;

$MAX_MAKETYPE=$NMAKE; #highest numeric type = NMAKE

#------------------------------------------------------------------------------
# constructor support

# initalise from a string or an integer
sub fromString ($$) {
    my ($self,$type)=@_;

    if ($type=~/^(\d)$/) {
        if ($type>=0 and $type<=$MAX_MAKETYPE) {
            $self->{make_type}=$type;
        } else {
            $self->{make_type}=$UNDEF;
            $self->throw("Out of range: $type");
            return undef;
        }
    } elsif ($type=~/^([ugnm])/i) {
        $type=uc($1);
        SWITCH: foreach ($type) {
            /[GM]/ and do { $self->{make_type}=$GMAKE; last };
            /N/    and do { $self->{make_type}=$NMAKE; last };
          DEFAULT:
             $self->{make_type}=$UNDEF;
        }
    } else {
        $self->throw("Bad initialiser: $type\n");
        return undef;
    }

    return $self;
}

#------------------------------------------------------------------------------

sub setMakeType ($$) {
    return $_[0]->fromString($_[1]);
}

sub getMakeType ($) {
    return $_[0]->{make_type};
}

sub isMakeType ($$) {
    my ($self,$type)=@_;
    return ($self->getMakeType()==$type)?1:0;
}

#------------------------------------------------------------------------------

sub toNumber ($) {
    return $_[0]->getMakeType();
}

sub toString ($) {
  SWITCH: foreach ($_[0]->getMakeType()) {
	$_==$NMAKE and return "nmake";
	$_==$GMAKE and return "gmake";
    }

    return undef;
}

#------------------------------------------------------------------------------

sub test {
    foreach (qw[u g n m x]) {
	my $type=new BDE::FileSystem::MakeType($_);
	print "Type $_ : $type (",0+$type,")\n";
    }
}

#------------------------------------------------------------------------------

1;
