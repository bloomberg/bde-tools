package Build::Option::Dimension::What;
use strict;

use base 'Composite::Dimension';
use Composite::Dimension;

use Symbols qw[
    OPTFILE_EXTENSION DEFFILE_EXTENSION CAPFILE_EXTENSION DEFAULT_OPTFILE
];

use BDE::Util::DependencyCache qw(getAllGroupDependencies);

use BDE::Util::Nomenclature qw[
    isComponent isPackage isGroupedPackage isGroup
    getComponentPackage getPackageGroup
];

#==============================================================================

=head1 NAME

Build::Option::Dimension::What - Implement dimensional collapse of unit

=head1 SYNOPSIS

    my $what=new Build::Option::Dimension::What;
    my $new_cv=$what->collapse($old_cv => "grppkg", "clone me");

=head1 DESCRIPTION

This dimension collapses build options on the name of the unit - package group,
package, or component. The default collapse criteria is C<default.opts> which
corresponds to the default options file (though there need be no hard
correlation between the name and the file).

=head1 NOTES

As with all dimensions, any subclass of a composite value set, composite value,
or composite value item can be collapsed with the C<collapse> method. Value
sets are more usually collapsed through their own methods for bookkeeping and
state maintenance. To create a new object rather than collapsing the original,
pass a third argument with a true value (i.e. C<clone me> as above).

=head1 TODO

Currently, for this dimension to operate, the L<BDE::Util::DependencyCache>
module must be loaded and initialised with a valid filesystem object, so that
dependencies can be determined. This undesirable 'action at a distance' will
be resoved in a future release.

=cut

#==============================================================================

# local cache of dependencies to avoid hitting the main cache repeatedly.
my $dvlast="";
my $dvdeps;

sub match {
    my ($self,$valueitem,$dimensionvalue)=@_;

    my $what=$valueitem->{$self->getAttribute()};

    # default.opts always matches
    return 1 if $what eq DEFAULT_OPTFILE;
    return 0 if $dimensionvalue eq "default"; #<<< hardwired, fix later

    my ($base,$ext)=($what,"");
    $what =~ /^([^.]+)(\.[\w]+)$/ and ($base,$ext) = ($1,$2);

    # match on any 'what' with a basename of the dimension or its parents
    # (package -> group, component -> package and group) that is, foobar_baz
    # matches foobar_baz.*, foobar.*, foo.*
    return 1 if $base eq $dimensionvalue;

    if (isComponent $dimensionvalue) {
	$dimensionvalue=getComponentPackage($dimensionvalue);
    }

    if (isPackage $dimensionvalue) {
	return 1 if $base eq $dimensionvalue;
	if (isGroupedPackage $dimensionvalue) {
	    $dimensionvalue=getPackageGroup($dimensionvalue);
	}
    }

    if (isGroup($dimensionvalue)) {
	return 1 if $base eq $dimensionvalue;
    }

    #--- Here we have either an isolated pkg or a package group ---#

    unless ($dvlast eq $dimensionvalue) {
	$dvlast=$dimensionvalue;
	$dvdeps={ map { $_=>1 } getAllGroupDependencies($dimensionvalue) };
    }

    # match bar.def and bar.cap if bar is a dependency of foo.
    if ($ext eq DEFFILE_EXTENSION or $ext eq CAPFILE_EXTENSION) {
	return 1 if exists $dvdeps->{$base};
    }

    #---

    return 0;
}

sub matchDefault {
    return $_[0]->match($_[1] => DEFAULT_OPTFILE);
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;
