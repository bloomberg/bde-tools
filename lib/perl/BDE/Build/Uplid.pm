package BDE::Build::Uplid;
use strict;

use POSIX;
use Scalar::Util qw(looks_like_number);
use vars qw(@ISA);
use overload '""' => "toString", fallback => 1;


use BDE::Object;
@ISA=qw(BDE::Object);

use Util::Message qw(fatal);
use Util::File::Functions qw(wild2re);

# for expansion
use Build::Option::Finder;
use Build::Option::Factory;

#==============================================================================

use constant DEFAULT_UPLID_COMPILER => "def";

#==============================================================================

=head1 NAME

BDE::Build::Uplid - Class for the Universal Platform ID (a.k.a. UPLID)

=head1 SYNOPSIS

    my $uplid=new BDE::Build::Uplid(); #default
    $uplid->compiler("mycc");
    $uplid->compilerversion("1.0");
    my $uplid_from_string=BDE::Build::Uplid->fromString("a-b-c-d");

    print "UPLID is: $uplid\n";
    print "The type is: ",$uplid->kin(),"\n";
    print "The OS is: ",$uplid->os(),"\n";
    print "The architecture is: ",$uplid->arch(),"\n";
    print "The OS version is: ",$uplid->osversion(),"\n";
    print "The compiler is: ",$uplid->compiler(),"\n";
    print "The compiler version is: ",$uplid->compilerversion(),"\n";

    print "The platform is: ",$uplid->platform(),"\n";

    my $wildmatch=$uplid->matchWild("a-?-?");
    my $rematch=$uplid->matchRegex("[aA]-(b|c)-.");

=head1 DESCRIPTION

This module encapsulates UPLID (Uniform PLatform ID) derivation in the form:

    I<kin>-I<os>-I<arch>-I<osversion>-I<compiler>-I<compilerversion>

Where:

    I<kin> is the operating system genus (C<unix> or C<windows>)
    I<os> is the operating system name (as in C<uname>)
    I<arch> is the machine architecture
    I<osversion> is the operating system version
    I<compiler> is the selected compiler label
    I<compilerversion> is the selected compiler version

Example:

    unix-SunOS-sparc-5.8-cc-5.2

The first four values are derived from C<uname> but vary across platform
in how the information is derived, due to differences in the implementation of
C<uname>.

The last two values, C<compiler> and C<compilerversion>, are user-defined
value which default to C<def> and C<0> respectively. External to this module,
these values can be derived from C<default.opts> and are I<upgraded> to a
fully qualified six-element representation.during the course of options
expansion. See L<bde_uplid.pl>.

=head1 NOTES

With the exception of the compiler and compliler elements, objects created by
this module arec considered read-only. If you need a different UPLID, create
a new object and specify the flags explicitly.

The C<platform> is a legacy concept that is supported for older scripts that
still use it. The C<os> element is a preferred way to convey the same
information.

=head1 CONSTRUCTOR

=cut

#==============================================================================

=head2 new ([$uplid_string])

Create a new UPLID object instance. If no argument is passed, then the platform
attrbutes are analysed to determine the appropriate values for the UPLID's
elements. Otherwise, an UPLID description string may be used to initialise the
UPLID elements.

If no description string is provided, or the provided description string does
now include the compiler, expansion is carried out using the build option
configuration to derive the compiler identity. Similarly, if not provided,
the compiler version is expanded in kind. If neither is provided then the
compiler is expanded first and its value then used to expand the compiler
version in turn. To avoid this expansion and get an unexpanded UPLID instead,
use the C<"unexpanded"> constructor.

=head2 unexpanded([$uplid_string])

As C<"new"> but do not expand the compiler or compiler version if not
provided. An unexpanded UPLID can be converted into an expanded one with the
C<"expand"> method, or by manually assigning the compiler and compiler version.

=cut

sub new {
    my ($class,$args)=@_;

    my $self=$class->SUPER::new($args);
    $self->expand();

    return $self;
}

sub unexpanded {
    my ($class,$args)=@_;

    return $class->SUPER::new($args);
}

# initialiser
sub initialise ($;$) {
    my ($self,$args)=@_;

    # return if initialised by some other means
    if ($self->SUPER::initialise($args)) {
        return 1; # done
    }

    # compiler
    if ($args->{compiler}) {
        ($self->{compiler},$self->{compilerversion})=
          split /-/,$args->{compiler} unless $args->{compilerversion};
        $self->compilerversion('0') unless $self->{compilerversion};
    } else {
        $self->compiler(DEFAULT_UPLID_COMPILER);
        $self->compilerversion('0');
    }

    #-----

    # kin
    $self->{kin} = $^O eq "MSWin32" ? "windows" : "unix";

    # system & version
    ($self->{system}, $self->{version}, $self->{model})
      = (POSIX::uname())[0,2,4];
    $self->{system} =~ s/[-\s]+/_/g;
    $self->{version} =~ s/[-\s]+/_/g;
    # DRQS 10671949, limit version to xx.yy.zz...  This limits
    # the proliferation of versions on Linux
    $self->{version} =~ s/^([0-9.]+).*/$1/;

    $self->{model} =~ s/[-\s]+/_/g;

    # arch
    if ($self->{kin} ne "windows") {
        $self->{system} =~ /^(linux|HP.?UX)$/i
          and $self->{arch} = `uname -m 2> /dev/null`
            or $self->{arch} = `uname -p 2> /dev/null`;
    } else {
        if ($self->{compiler} eq 'def') {
        	# find microsoft compiler in path and detect its version and 
        	# target platform.
        	# MS compiler is env driven. If the environment is not set
        	# up correctly and if the compiler is not in path, the build
        	# will break. So when we cannot find the compiler, it makes
        	# sense to die instead of falling back to bogus default from
        	# default.opts (cl-999.999).
        	my $cl = `cl.exe 2>&1`;
        	if ($cl =~ /Compiler Version ([0-9]+\.[0-9]+).*? for (\S*)/) {
        		$self->{compiler} = 'cl';
        		$self->{compilerversion} = $1;
        		$self->{model} = ($2 eq '80x86' ? 'x86' :
                                          $2 eq 'x64' ? 'amd64' :
                                          $2);
	       	}
	       	else {
	       	    die "Could not find Microsoft Visual C++ compiler (cl.exe), PATH=".$ENV{PATH};
	       	}
        }
        $self->{arch} = $self->{model};
    }
    $self->{arch} =~ s/\s.*$//;

    # hard-code cygwin...
    if ($self->{system}=~/^CYGWIN/) {
        if ($self->{compiler}=~/^(vc|vs|net)/i) {
            $self->{kin}     = "windows";
        } else {
            $self->{kin}     = "unix";
        }
        $self->{version} = "5.0";
        $self->{system}=~/([^_]+)$/ and
            $self->{version} = $1;
        $self->{system}  = "Cygwin";
        $self->{arch}    = "x86";
    }

    # on AIX system version is uname -v + uname -r
    if ($self->{system} =~ /^aix$/i) {
        my $major = `uname -v 2> /dev/null`;
        if (!$? && defined($major)) {
            $major =~ s/\s+//g;
            $self->{version} = $major.".".$self->{version};
        }
    }

    # on DG, rename 'PentiumPro' to 'x86'
    if ($self->{system} =~ /^dgux$/i) {
        $self->{arch} = "x86";
    }

    # for expansion
    #$self->{where}=$args->{where} if exists $args->{where};

    return 0; # continue
}

# convert string to uplid object. Strings must be 4 or 5 elements long; if the
# 5th element is not supplied it is defaulted.
sub fromString ($$) {
    my ($self,$string)=@_;

    $self=$self->new() unless ref $self; #called as Class method?

    $string=~s/\W+$//s; # remove trailing non-text chars
    $string=~s/-+$//s;  # remove trailing '-'s

    my @rec = split /-/,$string;

    if (scalar(@rec) > 6) {
        fatal "String '$string' contains too many elements";
    } elsif (scalar(@rec)==4) {
        $string.="-".DEFAULT_UPLID_COMPILER;
    } elsif (scalar(@rec)<4) {
        fatal "String '$string' contains too few elements";
    }

    $self->{kin}      = $rec[0];
    $self->{system}   = $rec[1];
    $self->{arch}     = $rec[2];
    $self->{version}  = $rec[3];
    $self->{compiler} = $rec[4];
    $self->{compilerversion} = $rec[5];

    $self->expand();

    return $self;
}

=head2 expand($where)

Expand the UPLID to include the compiler and compiler version, if unset, or
alternatively if set to the default (C<def>) and zero (C<0>) respectively.
The C<expand> method is automatically invoked as part of construction unless
the L<"unexpanded"> constructor is used.

If both the compiler and compiler version are set and are not C<def> and C<0>
respectively then the UPLID is considered already expanded and calling this
method has no effect.

=cut

sub expand ($;$) {
    my ($self,$where)=@_;

    my $compiler=$self->{compiler};
    my $compilerversion=$self->{compilerversion};
    if (looks_like_number $compilerversion and $compilerversion==0 and $compiler eq DEFAULT_UPLID_COMPILER) {
        # if the compiler and version are the default unexpanded ones,
        # treat the compiler as unset.
        $compiler="";
    }

    ($compiler,$compilerversion)=split /-/,$compiler
      unless $compilerversion;

    # derive compiler and compiler version from options if not set
    unless ($compiler and $compilerversion) {
        my $root=$where ? $where : $self->{where};
        $self->throw("Cannot expand UPLID without a root") unless $root;

        #<<<TODO: this implementation is overkill, simplify later for speed.
        my $finder=new Build::Option::Finder($root);
        my $factory=new Build::Option::Factory($finder);
        $factory->load("default");
        my $set=$factory->getValueSet();
        $set->collapseDimension(uplid => $self);

        my $compilerdimension=$set->getDimension('compiler');
        if ($self->compiler() eq $compilerdimension->DEFAULT) {
            $self->compiler($compilerdimension->getDefault);
        }
        my $compilerversiondimension=$set->getDimension('compiler_v');
        if ($self->compilerversion() eq $compilerversiondimension->DEFAULT) {
            $self->compilerversion($compilerversiondimension->getDefault);
        }
    }

    return $self;
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSOR/MUTATORS

=head2 kin()

Return the OS kin (C<unix> or C<windows>) of the UPLID object.

=head2 os()

Return the OS name of the UPLID object.
(C<system> is a legacy alias for this method.)

=head2 arch()

Return the CPU Architecture of the UPLID object.

=head2 osversion()

Return the OS Version of the UPLID object.
(C<version> is a legacy alias for this method.)

=cut

sub kin       ($) { return $_[0]->{kin}     };
sub os        ($) { return $_[0]->{system}  }; # new name
sub system    ($) { return $_[0]->{system}  }; # old name
sub arch      ($) { return $_[0]->{arch}    };
sub osversion ($) { return $_[0]->{version} }; # new name
sub version   ($) { return $_[0]->{version} }; # old name

=head2 compiler([$compiler_id])

Return, or optionally set, the Compiler ID of the UPLID object. Note that this
is the fifth UPLID element, and is mapped to an actual compiler in the options
files.

=head2 compilerversion([$compiler_version_id])

Return, or optionally set, the Compiler Version ID of the UPLID object.

=cut

# accessor/mutator - only compiler and compilerversion are overridable
sub compiler ($;$) {
    my ($self,$compiler)=@_;

    if ($#_>0) {
        fatal("Bad compiler '$compiler'") if $compiler =~ /[\s\-\_]/;
        $self->{compiler}=$compiler;
    }
    return $self->{compiler};
};

# accessor/mutator - only compiler and compilerversion are overridable
sub compilerversion ($;$) {
    my ($self,$compilerversion)=@_;

    if ($#_>0) {
        fatal "No version" unless defined $compilerversion;
        # Version must be one or more sequence of alphanum chars
        # separated by dots, e.g. A123, 1.2, B.3C.A4
        fatal("Bad compiler version '$compilerversion'")
          if $compilerversion =~ /^(\w+\.)+$/;
        $self->{compilerversion}=$compilerversion;
    }
    return $self->{compilerversion};
};

=head2 platform()

I<DEPRECATED>

Return the legacy 'common name' for the UPLID. The common name was used by
some older scripts to provide filename elements and is retained for any
scripts that still make use of it. Such scripts should in time be migrated to
use the C<os> method in preference.

=cut

sub platform ($) {
     my $self=shift;

     $self->{platform}=undef;

     $self->{platform}="sun"    if $self->system() =~ /(sunos|sparc|solaris)/i;
     $self->{platform}="dg"     if $self->system() =~ /dgux/i;
     $self->{platform}="ibm"    if $self->system() =~ /(aix|ibm)/i;
     $self->{platform}="win"    if $self->system() =~ /win/i;
     $self->{platform}="linux"  if $self->system() =~ /(linux|bsd)/i;
     $self->{platform}="darwin" if $self->system() =~ /darwin/i;
     $self->{platform}="cygwin" if $self->system() =~ /cygwin/i;
     $self->{platform}="hp"     if $self->system() =~ /(hp)/i;

     return $self->{platform};
}

#------------------------------------------------------------------------------

=head1 METHODS

=head2 matchRegex($regex)

Match the UPLID against the provided regular expression, which should be in the
form:

    <re>[-<re>[-<re>[-<re>[-<re>]]]]

Where C<re> is a regular expression. Note that versions are I<not> checked
in terms of numerical comparisions, see C<Build::Option::Dimension::OSVersion>
and other parts of the C<Build::Option> family of modules for that.

=cut

sub matchRegex ($$) {
    my ($self,$regex)=@_;

    my ($kin, $system, $arch, $version, $compiler, $compilev);
    my @rec = split /-/,$regex;

    $kin      = $rec[0] if $#rec >= 0;
    return 0 if (defined($kin)      && $self->{kin}      !~ /^$kin$/i);
    $system   = $rec[1] if $#rec >= 1;
    return 0 if (defined($system)   && $self->{system}   !~ /^$system$/i);
    $arch     = $rec[2] if $#rec >= 2;
    return 0 if (defined($arch)     && $self->{arch}     !~ /^$arch$/i);
    $version  = $rec[3] if $#rec >= 3;
    return 0 if (defined($version)  && $self->{version}  !~ /^$version$/i);
    $compiler = $rec[4] if $#rec >= 4;
    return 0 if (defined($compiler) && $self->{compiler} !~ /^$compiler$/i);
    #    $compilev = $rec[5] if $#rec >= 5;
    #    return 0 if (defined($compilev) && $self->{compilerversion}
    #            !~ /^$compilev$/i);

    return 1;
}

=head2 matchWild($wild)

Match the UPLID against the provided wildcard expression.

=cut

# match against wildcard pattern
sub matchWild ($$) {
    my ($self,$wildcard)=@_;

    return $self->matchRegex(wild2re $wildcard);
}

#------------------------------------------------------------------------------

# convert uplid object to string. Used by stringify operator
sub toString ($) {
    my $self=shift;

    return $self->{kin}.
           '-'.$self->{system}.
           '-'.$self->{arch}.
           '-'.$self->{version}.
           '-'.$self->{compiler}.
           ($self->{compilerversion} ? '-'.$self->{compilerversion} : "");
}

#==============================================================================

# test module
sub test ($;$) {
    my ($proto,$test_string)=@_;
    $test_string ||="a-b-c-d";

    my $uplid=$proto->new();
    print "to string (explicit): ",$uplid->toString(),"\n";
    print "to string (implicit): $uplid \n";

    print "object is a ",ref($uplid),"\n";
    print "kin     : ",$uplid->kin(),"\n";
    print "system  : ",$uplid->system(),"\n";
    print "arch    : ",$uplid->arch(),"\n";
    print "version : ",$uplid->version(),"\n";
    print "compiler: ",$uplid->compiler(),"\n";
    print "platform: ",$uplid->platform(),"\n";

    $uplid->compiler("CC64");
    print "compiler: ",$uplid->compiler(),"\n";
    print $uplid->toString(),"\n";

    print $uplid->fromString($test_string),"\n";
    print "kin     : ",$uplid->kin(),"\n";
    print "system  : ",$uplid->system(),"\n";
    print "arch    : ",$uplid->arch(),"\n";
    print "version : ",$uplid->version(),"\n";
    print "compiler: ",$uplid->compiler(),"\n";
    print "platform: ",$uplid->platform(),"\n";

    print "match a-b-c (Wild): ",$uplid->matchWild("a-b-c"),"\n";
    print "match ?-b-*-d (Wild): ",$uplid->matchWild("a-b-*-d"),"\n";
    print "match ?-c-*-d (Wild): ",$uplid->matchWild("?-c-*-d"),"\n";
    print "match * (Wild): ",$uplid->matchWild("*"),"\n";
    print "match [ab]-(b|c)-.-d (Regex): ",
      $uplid->matchRegex("[ab]-(b|c)-.-d"),"\n";
    print "match [ab]-(c|e)-.-d (Regex): ",
      $uplid->matchRegex("[ab]-(c|e)-.-d"),"\n";

    $uplid->initialise();
    print "Reset to $uplid\n";

    eval { $uplid=$proto->new("A-B-C"); };
    eval { $uplid=$proto->new("A-B-C-D-E-F"); };

    $uplid=$proto->new("A-B-C-D");
    print "fromString 4: $uplid\n";
    $uplid=$proto->new("A-B-C-D-E");
    print "fromString 5: $uplid\n";
    $uplid=$proto->new({compiler => "foo"});
    print "compiler hash arg foo: $uplid\n";
    eval { $uplid=$proto->new({compiler => "foo-bar"}); };
    print "bad compiler hash arg foo: $uplid\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_build.pl>, L<bde_uplid.pl>

=cut

1;
