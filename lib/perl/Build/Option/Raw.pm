package Build::Option::Raw;
use strict;

#use overload '""' => 'toString', fallback => 1;

use base 'Composite::ValueItem';

use vars qw(@DIMENSIONS);
@DIMENSIONS=qw(what kin os arch os_v comp comp_v ufid);

#==============================================================================

=head1 NAME

Build::Option::Raw - Abstract representation of a raw build option

=head1 SYNOPSIS

    use Build::Option::Raw qw(ADD);

    # create new raw option instance, set some attributes
    my $rawoption=new Build::Option::Raw({
        name    => "OPTION_NAME",
        value   => "rawoption_value",
        command => ADD,
        what    => "bte",
        kin     => "unix",
        ufid    => "dbg"
    });

    # set some more attributes with mutators
    $rawoption->setOS("SunOS");
    $rawoption->setCompiler("cc");
    $rawoption->setCompilerVersion("5.5");

    # render
    print $rawoption,"\n";         # 'rawoption_value'
    print $rawoption->toString(1); # 'OPTION_NAME=rawoption_value'
    print $rawoption->dump();      # print detailed contents of raw option

=head1 DESCRIPTION

C<Build::Option::Raw> provides the abstract representation of a raw build
option, derived from a single configuration line of an options file. Objects
of this class are managed by the L<Build::Option> class, which in turn
creates objects that are managed by the L<Build::Option::Set> class.

Much of the functionality of this class, and in particular the combination
of raw options through their commands, is provided by the parent class
L<Composite::ValueItem>. See that module for details on how raw options
combine, and L<Composite::Value> (the parent class of C<Build::Option>) for
how collections of raw options are managed.

Objects of this class are rarely instantiated directly. Instead, they are
produced by a L<Build::Option::Parser> object from suitable text input (for
example, extracted from an options file by a L<Build::Option::Scanner> object).
A list of C<Build::Option> objects created this way can be passed to
L<Build::Option::Set/new> to automatically collect them into L<Build::Option>
objects, which are instantiated on-the-fly according to the names of the
raw options supplied.

=cut

#==============================================================================
# Dimensions

=head1 DIMENSION ACCESSORS/MUTATORS

=head2 getWhat()

Get the context of the raw option.

=head2 setWhat()

Set the context of the raw option -- that is, the file from which it was
originally read, such as C<bde.opts> or C<a_ossl.defs>. 

The context is typically used to determine the order in which options from
different files are processed, according to dependency calculations carried
out elsewhere. This is however up to the implementation of the dimension
collapse module used to collapse this value. See
L<Build::Option::Dimension::What>.

=cut

sub getWhat            ($)  { return $_[0]->{what}; }

sub setWhat            ($$) { $_[0]->{what}=$_[1]; }

#--- Uplid Elements

=head2 getKin()

Get the kin for the raw option.

=head2 setKin($)

Set the kin for the raw option.

The kin is typically one of two values: C<unix> or C<windows>, although other
kins are technically possible.

A value of C<*> means the raw option is wildcarded on this dimension.

=cut

sub getKin             ($)  { return $_[0]->{kin}; }

sub setKin             ($$) { $_[0]->{kin}=$_[1]; }

=head2 getOS()

Get the OS name for the raw option.

=head2 setOS($)

Set the OS name for the raw option. This is usually the same as the output of
running C<uname>, for example C<SunOS> or C<Linux>.

A value of C<*> means the raw option is wildcarded on this dimension.

=cut

sub getOS              ($)  { return $_[0]->{os}; }

sub setOS              ($$) { $_[0]->{os}=$_[1]; }

=head2 getArch()

Get the platform architecture for the raw option.

=head2 setArch($)

Set the platform architecture for the raw option. This is usually the same as
the output of running C<uname -p> (or C<uname -m> on Linux and HP-UX), for
example C<sparc> or C<powerpc>.

A value of C<*> means the raw option is wildcarded on this dimension.

=cut

sub getArch            ($)  { return $_[0]->{arch}; }

sub setArch            ($$) { $_[0]->{arch}=$_[1]; }

=head2 getOSVersion()

=head2 setOSVersion($)

Set the OS version for the raw option.

=cut

sub getOSVersion       ($)  { return $_[0]->{os_v}; }

sub setOSVersion       ($$) { $_[0]->{os_v}=$_[1]; }

=head2 getCompiler()

Get the compiler ID for the raw option. 

=head2 setCompiler($)

Set the compiler ID for the raw option.

The compiler ID is usually named after a compiler command, but is in
reality an abstract value that relates to a suite of compilers.
For example, the C<gcc> compiler ID maps to C<gcc> for C but C<g++> for
C++.

A value of C<*> means the raw option is wildcarded on this dimension.

=cut

sub getCompiler        ($)  { return $_[0]->{compiler}; }

sub setCompiler        ($$) { $_[0]->{compiler}=$_[1]; }

=head2 getCompilerVersion()

Get the compiler version for the raw option.

=head2 setCompilerVersion($)

Set the compiler version for the raw option.

Since the compiler ID is abstract, a sensible means of relating a
version to it must be found. For example, the version can be based 
on the version of the C++ compiler, or the compiler suite (which
often has a different version).

Analysis of the compiler version is performed by the
L<Build::Option::Dimension::CompilerVersion> dimensional collapse
module.

A value of C<0> means the raw option is wildcarded on this dimension.

=cut

sub getCompilerVersion ($)  { return $_[0]->{compiler_v}; }

sub setCompilerVersion ($$) { $_[0]->{compiler_v}=$_[1]; }

#--- Ufid

=head2 getUfid()

Get the UFID for the raw option.

=cut

sub getUfid    ($)  { return $_[0]->{ufid}; }

=head2 setUfid($ufid)

Set the UFID for the raw option.

Usually set with a L<BDE::Build::Ufid> object, although this class will also
accept a string value (in which case it is the programmers responsibility to
ensure the string contains a valid UFID descriptor).

=cut

sub setUfid    ($$) { $_[0]->{ufid}=$_[1]; }

#------------------------------------------------------------------------------

=head1 UTILITY METHODS

=head2 dump()

Routine to dump out the contents of a raw option in an expanded format, for
debugging.

=cut

sub dump ($) {
    my $s=shift;

    # print join "\n", map { "['$_'=>'$s->{$_}']" } sort keys %$s;

    return "[".(defined($s->{command}) ? $s->{command} : "??")."] ".(
               defined($s->{what}) ? $s->{what} : "<???>"
           )." [".(
               join("-", map {
                   defined($s->{$_}) ? $s->{$_} : "???"
               } (qw[kin os arch os_v compiler compiler_v]))
           )."] [".(
               defined($s->{ufid}) ? $s->{ufid}->toString(1) : "_"
           )."] ".(
               defined($s->getName)  ? $s->getName  : "<anon>"
           )."=".(
               defined($s->getValue) ? $s->getValue : "<no value>"
           );
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Build::Option>, L<Build::Option::Parser>, L<Build::Option::Scanner>,
L<Composite::ValueItem>, L<Composite::Value>

Chapter 5 of I<Developing with BDE>

=cut

1;

