package Base::Architecture;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK);
@ISA=qw(Exporter);
@EXPORT_OK=qw(name namespace module);

#==============================================================================

=head1 NAME

Base::Architecture - Transparent support for architecture specialisations

=head1 SYNOPSIS

    # get the submodule name for the current platform
    use Base::Architecture qw(module);
    my $module=module("Module::Family");

    # automatically use and add platform-specific namespace to @ISA
    use base qw(Other::Superclasses);
    use Base::Architecture qw(auto);

    # predefine embedded support for one architecture
    package Module::Family;
    {
        package Module::Family::SunOS;
        sub native_os_functionality { ... }
    }
    use Base::Architecture qw(auto);

    # load external module even if the architecture namespace exists
    use Base::Architecture qw(auto force);

=head1 DESCRIPTION

C<Base::Architecture> provides support for deriving names for per-platform
specialisation modules. It is designed to help modules that need to work on
multiple invoke the appropriate architecture-specific submodule automatically.
The submodule is automatically made a superclass of the primary module, so
platforms but need support from the OS to do so.

=head2 Automatic Mode

Automatic modue is the primary usage model for this module, and is enabled
by passing the C<auto> keyword in the module's import list. If the C<auto>
keyword is specified, C<Base::Architecture> will calculate the appropriate
submodule name, and insert it into the @ISA array of the calling class.

If the namespace is I<not> already present in the symbol table, or the C<force>
keyword is also specified, then in C<auto> mode the calculated architecture
module will also be loaded with C<require> and its C<import> method called with
any arguments not handled by this module.

An architecture support package may be defined internal to the primary module
instead of implemented as an external module. The C<auto> mode will not attempt
to load a corresponding module I<if> the package declaration is seen first, i.e.
appears in the source before the C<Base::Architecture> module is used.

Because C<auto> mode modifies the C<@ISA> array of the calling package at
compile time, it is essential to use the C<use base> pragma to define direct
superclasses rather than modify C<@ISA> at runtime. (The latter idiom will
clobber the modifications made to @ISA by C<Base::Architecture>.)

=head1 ARCHITECTURES

The derived name is based on the value of C<$^O> (C<$OS_NAME>) and mapped to a
more conventional name in keeping with other commonly available Perl module.
For instance, Windows support is traditionally provided by modules in a 'Win32'
namespace.

The following architecture mappings are currently defined:

    aix     => AIX
    cygwin  => Cygwin
    dgux    => DG
    hpux    => HP
    MacOS   => Mac
    MSWin32 => Win32
    solaris => SunOS

Unrecognized values of C<$^O> (C<$OS_NAME>) are mapped to C<Unknown>.

=head1 TO DO

The following features will be added in the future:

* Permit C<Unknown> to be overridden

* Define mappings to be added or changed in the import list

* Allow fallback families (i.e. 'Unix' for all unix-like OS)

=cut

#==============================================================================

use vars qw($PLATFORM);
$PLATFORM = $^O;

my %module = (
    MacOS   => 'Mac',
    MSWin32 => 'Win32',
    cygwin  => 'Cygwin',
    aix     => 'AIX',
    solaris => 'SunOS',
    dgux    => 'DG',
    hpux    => 'HP',
);

#------------------------------------------------------------------------------

# remove all instances of a specified value from an array
sub extract_from_array (\@$) {
    my ($aref,$item)=@_;

    my $result=undef;
    @$aref = grep { ($_ ne $item)? 1 : ($result=$item and 0) } @$aref;

    return $result;
}

sub import {
    my $package=shift;
    my $caller=caller(0);

    # remove flags
    my $auto=extract_from_array(@_,'auto');
    my $force=extract_from_array(@_,'force');

    # remove directly exportable subs
    my @subs;
    foreach (@EXPORT_OK) {
	push @subs,$_ if extract_from_array(@_,$_);
    }

    if ($auto) {
	no strict 'refs';
	no warnings 'once';
	my $namespace=namespace($caller);
	push @{"$caller\:\:ISA"},$namespace;
	if (not %{*$namespace.'::'} or $force) {
	    my $module=module($caller);
	    require $module;
	    $module->import(@_) if @_ and $module->can("import");
	}
    }

    $package->export_to_level(1,$package,@subs);
}

#------------------------------------------------------------------------------

=head1 EXPORTS

The following subroutines are available for export:

=head2 name

Return the standardised name for a platform-specific module subclass. For
example (assuming C<$^O eq 'solaris'>):

    print name(); # returns 'SunOS'

=cut

sub name { return $module{$PLATFORM} || 'Unknown'; }

=head2 namespace ($umbrella_name)

Given the umbrella name for a generic cross-platform module, return the
correct platform-specific namespace (i.e. package) name. For example:

    print module("Foo::Bar"); # returns 'Foo::Bar::SunOS'

=cut

sub namespace (;$) {
    return ($_[0]?$_[0]:scalar(caller 0)).'::'.name();
}

=head2 module ($umbrella_name)

Given the umbrella name for a generic cross-platform module, return the
correct platform-specific module filename (Perl style). For example:

    print module("Foo::Bar"); # returns 'Foo/Bar/SunOS.pm

This path is suitable for use with C<require>.

=cut

sub module (;$) {
    my $family=shift || scalar(caller 0);
    $family=~s|::|/|g;
    return $family.'/'.name().".pm";
}

#==============================================================================

sub test ($) {
    my $family=shift;

    print "Family  : $family\n";
    print "Name    : $PLATFORM => '",name(),"'\n";
    print "Package : ",namespace($family),"\n";
    print "Module  : ",module($family),"\n";

    $PLATFORM="Plan9";

    print "Name    : $PLATFORM => '",name(),"'\n";
    print "Package : ",namespace($family),"\n";
    print "Module  : ",module($family),"\n";
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=cut

1;
