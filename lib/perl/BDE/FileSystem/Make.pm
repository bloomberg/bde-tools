package BDE::FileSystem::Make;
use strict;

use BDE::FileSystem;
use BDE::FileSystem::MakeType;
use vars qw(@ISA);

use Symbols qw(
    $PACKAGE_META_SUBDIR
    $GROUP_META_SUBDIR
);

@ISA=qw(BDE::FileSystem);

#------------------------------------------------------------------------------

=head1 DESCRIPTION

This module provides additional filesystem methods for deriving the name of
build files such as makefiles for Unix or Windows and vars files containing
platform-specific macros.

It is intended for use by the C<producemake> utility, but as yet is not
integrated into that application.

The naming scheme here is I<not> compatible with the makefile generation
logic implemented by C<bde_build.pl>.

=cut

#------------------------------------------------------------------------------

our $LIB_SUBDIR               = "lib";
our $INCLUDE_SUBDIR           = "include";
our $MAKEFILE_EXTENSION       = "mk";
our $NMAKEFILE_EXTENSION      = "nmk";
our $MAKEVARS_EXTENSION       = "vars";
our $UNIVERSAL_MAKEFILE       = "Makefile";

my $MAKE_NMAKE = $BDE::FileSystem::MakeType::NMAKE;

#------------------------------------------------------------------------------

sub fromString ($$) {
    my ($self,$init)=@_;

    $self->SUPER::fromString($init);
    $self->{maketype}=new BDE::FileSystem::MakeType("g");
}

sub intialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->SUPER::initialiseFromHash($args);
    if ($self->{maketype} and !ref($self->{maketype})) {
	$self->{maketype}=new BDE::FileSystem::MakeType($self->{maketype});
    }

    return $self;
}

#------------------------------------------------------------------------------

sub isMakeType ($$) {
    my ($self,$type)=@_;
    return $self->{maketype}->isMakeType($type);
}

sub getMakeType ($$) {
    my $self=shift;
    return $self->{maketype};
}

sub setMakeType ($$) {
    my ($self,$type)=@_;
    $self->{maketype}=new BDE::FileSystem::MakeType($type);
}

#------------------------------------------------------------------------------
# Build files

sub getPackageMakefileName ($$) {
    my ($self,$package)=@_;

    my $extension=$self->isMakeType($MAKE_NMAKE)?
      $NMAKEFILE_EXTENSION:$MAKEFILE_EXTENSION;

    return $self->getPackageLocation($package).
      "/${PACKAGE_META_SUBDIR}/${package}.${extension}";
}

sub getGroupMakefileName ($$) {
    my ($self,$group)=@_;

    my $extension=$self->isMakeType($MAKE_NMAKE)?
      $NMAKEFILE_EXTENSION:$MAKEFILE_EXTENSION;

    return $self->getGroupLocation($group).
      "/${GROUP_META_SUBDIR}/${group}.${extension}";
}

sub getPackageVarsfileName ($$$) {
    my ($self,$package,$platform)=@_;

    return $self->getPackageLocation($package).
      "/${PACKAGE_META_SUBDIR}/${package}.${platform}.${MAKEVARS_EXTENSION}";
}

sub getGroupVarsfileName ($$$) {
    my ($self,$group,$platform)=@_;

    return $self->getGroupLocation($group).
      "/${GROUP_META_SUBDIR}/${group}.${platform}.${MAKEVARS_EXTENSION}";
}

sub getUniversalMakefileName ($) {
    my $self=shift;

    my $name=$self->getRootLocation()."/${UNIVERSAL_MAKEFILE}";

    if ($self->isMakeType($MAKE_NMAKE)) {
	$name.=".".$NMAKEFILE_EXTENSION;
    }

    return $name;
}

#------------------------------------------------------------------------------

1;
