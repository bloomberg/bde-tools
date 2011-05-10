package Build::Option::Set;
use strict;

use base 'Composite::ValueSet';

use constant DEFAULT_VALUECLASS => 'Build::Option'; # what this set supports

#==============================================================================

=head1 NAME

Build::Options::Set - Aggegation of Build::Option composite values

=head1 SYNOPSIS

    use Build::Option::Set;
    use Build::Option;
    use BDE::Build::Uplid;

    my $set=new Build::Option::Set("ExampleSet");
    my $option=new Build::Option("ExampleOption");
    $set->addValue($option);
    # add more options...

    my @options=$set->getValues();
    $set->collapseDimensions({
        what => "bde", uplid => BDE::Build::Uplid->new(), ufid => 'dbg_exc_mt'
    });
    print $set->render();

See L<Build::Option::Factory> for a more advanced example.

=head1 DESCRIPTION

This module provides a container for a collection of L<Build::Option>
instances, and establishes the dimensional collapse algorithms for each of the
dimensions present in a raw L<Build::Option::Raw> object.

C<Build::Option::Set> is a subclass of L<Composite::ValueSet>; see the
documentation for that module for more information on composite values and
value sets. It implements the C<register> method )(which is called by the
constructor of L<Composite::ValueSet> to register the following dimensions:

    what        - component, package, or package group

    kin         - OS family: unix or windows
    os          - OS name: SunOS, AIX, Linux, etc.
    arch        - CPU architecture: sparc, x86, powerpc, etc.
    os_v        - OS version
    compiler    - Compiler ID (see default.opts)
    compiler_v  - Compiler version (see default.opts)

    ufid        - Unified flag ID: dbg_exc_mt, opt_safe, etc.

In addition, C<Build::Option::Set> overloads C<collapseDimension> to allow
a L<BDE::Build::Uplid> object to be used to collapse the fictional C<uplid>
dimension.

    uplid       - kin + os + arch + os_v + compiler + compiler_v

This has the effect of collapsing all six of the platform ID values
at once. Importantly, it I<also> upgrades the L<BDE::Build::Uplid> object with
any information derived from calculation of defaults for the C<compiler> or
C<compiler_v> dimensions. This allows the caller to get back the
fully-qualified UPLID that was used to derive the compiler ID and version.

=cut

#==============================================================================

sub register ($) {
    my $self=shift;

    # this is a (simplistic) way to allow a subclass to redefine all the
    # dimensions simply by placing them into the appropriately named
    # packages. If this isn't the desired effect, overload this 'register'
    # method instead. Note that instantiation of the dimensions only occurs
    # later as the classname is specified here, not an instance. This means
    # it is possible to call this method and then overwrite a dimension
    # setting without incuring the cost of needless object construction.
    my $class=$self->getValueClass();

    $self->setDimension(what       => $class.'::Dimension::What');

    $self->setDimension(kin        => $class.'::Dimension::Kin');
    $self->setDimension(os         => $class.'::Dimension::OS');
    $self->setDimension(arch       => $class.'::Dimension::Arch');
    $self->setDimension(os_v       => $class.'::Dimension::OSVersion');
    $self->setDimension(compiler   => $class.'::Dimension::Compiler');
    $self->setDimension(compiler_v => $class.'::Dimension::CompilerVersion');

    $self->setDimension(ufid       => $class.'::Dimension::Ufid');

    return $self;
}

#------------------------------------------------------------------------------

# this overload of C::VS's collapseDimension allows an Uplid object to be
# use to collapse all six dimensions at once. It *also* upgrades the
# uplid to its fully-qualified form (compiler and compiler_v) as this
# determination is made by the compiler and compilerversion dimensions
sub collapseDimension ($$$;$) {
    my ($self,$dimension,$value,$clone)=@_;

    if ($dimension eq 'uplid') {
	$self->throw("value is not a BDE::Build::Uplid")
	  unless (ref $value) and $value->isa("BDE::Build::Uplid");

	$self = $self->collapseDimensions({
	    kin        => $value->kin(),
	    os         => $value->os(),
            os_v       => $value->osversion(),
            arch       => $value->arch(),
            compiler   => $value->compiler(),
            compiler_v => $value->compilerversion(),
	}, $clone);

	# upgrade the uplid we were passed - compiler and compiler version
	# DEFAULT is the hardwired 'default' default. getDefault() is the
	# calculated default out of the options file.

	my $compilerdimension=$self->getDimension('compiler');
	if ($value->compiler() eq $compilerdimension->DEFAULT) {
	    $value->compiler($compilerdimension->getDefault);
	}
	my $compilerversiondimension=$self->getDimension('compiler_v');
	if ($value->compilerversion() eq $compilerversiondimension->DEFAULT) {
	    $value->compilerversion($compilerversiondimension->getDefault);
	}

    } else {
	$self = $self->SUPER::collapseDimensions($dimension => $value,$clone);
    }

    return $self;
}

#<<< slightly ugly hack because collapseDimension calls collapseDimensions
#<<< and not vice-versa. Resolve this in C::SV's implementation later.
sub collapseDimensions ($$;$) {
    my ($self,$dimensionmap,$clone)=@_;

    my $uplidvalue;

    # do the uplid separately.
    if (exists $dimensionmap->{uplid}) {
	$uplidvalue=delete $dimensionmap->{uplid};
	$self = $self->collapseDimension(uplid => $uplidvalue, $clone);
	$clone=0;
    }

    if (keys %$dimensionmap) {
	# do *not* pass $clone here, because the set was cloned already
        # cloned above, if $clone was true
	$self = $self->SUPER::collapseDimensions($dimensionmap, $clone);
    }

    # replace uplid in case caller wants it back.
    $dimensionmap->{uplid}=$uplidvalue if $uplidvalue;

    return $self;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Build::Option>, L<Build::Option::Raw>, L<Composite::ValueSet>

=cut

1;
