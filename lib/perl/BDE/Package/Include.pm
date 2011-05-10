package BDE::Package::Include;
use strict;

use overload '""' => "toString", fallback => 1;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

use BDE::Util::Nomenclature qw(getPackageGroup);
use BDE::Build::Invocation qw($FS $FSRE);

#------------------------------------------------------------------------------

=head1 NAME

BDE::Package::Include - Abstract representation of an included file reference

=head1 SYNOPISIS

    my $inc=new BDE::Package::Include({
        name    => "subdir/header.h",
        package => "bxe+ncpkg"
    }

    print "The leafname is $inc\n";      # header.h
    my $leafname => $inc->getName();     # header.h
    my $fullname => $inc->getFullname(); # subdir/header.h
    my $package  => $inc->getPackage();  # bxe+ncpkg
    my $group    => $inc->getGroup();    # bxe
    my $includes => $inc->getIncludes(); # included files

=head1 DESCRIPTION

This module provides a simple object class to represent non-compliant package
includes. An NCP-include object knows its leafname, fullname, and the package
to which it belongs. This is necessary because unlike component headers, there
is no automatic way to derive the (non-compliant) package to which the include
belongs.

This module is used in two different contents:

=over 4

=item *

L<BDE::Package> uses it to create the list of includes defined by the
C<.pub> file for nonc-compliant packages. (This list is returned by
C<$package->getIncludes()>.). These objects always know the package to
which they belong since they are created to serve a particular package.

=item *

L<BDE::Util::DependencyCache> uses it to track non-component includes
as part of the dependency resolution mechanism. In this case, the
includes do not usually know their true origin until later.

=back

No mutator methods are provided for this class as it is not intended that
object instances will be manipulated after creation.

=cut

#------------------------------------------------------------------------------
# Constructor support

# Initialise a new Include Object
# name     - the leafname of the include
# fullname - the full name of the include
# pathname - relative pathname under package directory
# package  - the package this include comes from, if known
# subdir   - the subdirectory (if any) this include comes from
# includes - array reference of includes (strings or objects)
# notacomp - not a component header (even if it looks like one)
sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->BDE::Object::initialiseFromHash($args);

    $self->throw("Must provide 'name' or 'fullname' attribute")
      unless $self->{name} or $self->{fullname};

    # if one of name or fullname is defined, derive the other one from it
    if (! $self->{name}) {
	if ($self->{fullname} =~ m|[/\\]([^/\\]+)$|) {
	    $self->{name} = $1; 
	} else {
	    $self->{name} = $self->{fullname};
	}
    } elsif (! $self->{fullname}) {
	if ($self->{name} =~ m|[/\\]([^/\\]+)$|) {
	    $self->{fullname} = $self->{name};
	    $self->{name} = $1;
	} else {
	    $self->{fullname} = $self->{name};
	}
    }

    $self->{notacomponent}=1;

    # empty array of include statements (to be filled)
    $self->{includes} ||= [];

    return $self;
}

#------------------------------------------------------------------------------

# the leafname of the include, i.e. the actual filename
sub getName          ($) { return $_[0]->{name};        }
sub setName         ($$) { $_[0]->{name}=$_[1];         }

# the full name of the include, i.e. the name it was referenced by, including
# any leading path, if present. This is not the full pathname, nor is it the
# relative name under the package -- see getRealname and getPathname
sub getFullname      ($) { return $_[0]->{fullname};    }
sub setFullname     ($$) { $_[0]->{fullname}=$_[1];     }

sub getPackage       ($) { return $_[0]->{package};     }
sub setPackage       ($) { $_[0]->{package}=$_[1];      }
sub getGroup         ($) { return $_[0]->{package} ?
			   getPackageGroup($_[0]->{package}) : undef }

# The includes that were found in this include
sub getIncludes      ($) { return @{$_[0]->{includes}}; }
sub setIncludes     ($$) {
    my ($self,$aref)=@_;
    $self->throw("Not an array reference") unless ref $aref;
    $self->{includes}=$aref;
}

# Local - true if the include was in quotes rather than angle brackets
sub isLocal          ($) { return $_[0]->{local}        }
sub setLocal        ($$) { $_[0]->{local}=$_[1];        }

# Not a component - true if '//not a component' was seen'
sub isNotAComponent  ($) { return $_[0]->{notacomponent}; }
sub setNotAComponent ($) { $_[0]->{notacomponent}=$_[1];  }

#----

# this property is populated when the include is located, e.g. by the
# BDE::File::Finder->find method.
sub getRealname      ($) { return $_[0]->{realname}; } # full pathname
sub setRealname     ($$) { $_[0]->{realname}=$_[1];
		           $_[0]->{_pathname}=undef; }

# pathname = the realname minus the package location. Repeat the sub just in
# case the root contains the package name (unlikely, but possible). System
# includes have no package and so just get passed back as-is.
sub getPathname  ($) {
    my $self=shift;

    return $self->{_pathname} if $self->{_pathname};

    my $path=$self->getRealname();

    if (my $pkg=$self->getPackage) {
	my $qpkg=quotemeta $pkg;
	1 while $path=~s/^.*${FSRE}${qpkg}${FSRE}//;
    }

    $self->{_pathname}=$path;

    return $path;
}

#------------------------------------------------------------------------------

sub toString    ($) { return $_[0]->{fullname}; }

#------------------------------------------------------------------------------

sub test {
    my $f1=new BDE::Package::Include({
        name => "foo",
        package => "barbaz",
    });
    print "File1 is $f1\n";
    print "File1 full name is ",$f1->getFullname(),"\n";
    print "File1 package is ",$f1->getPackage(),"\n";
    print "File1 group is ",$f1->getGroup(),"\n";

    print "\n";

    my $f2=new BDE::Package::Include({
        name => "dir/subdir/qux",
        package => "quux",
    });
    print "File2 is $f2\n";
    print "File2 full name is ",$f2->getFullname(),"\n";
    print "File2 package is ",$f2->getPackage(),"\n";
    print "File2 group is ",$f2->getGroup(),"\n";
}

#------------------------------------------------------------------------------

1;
