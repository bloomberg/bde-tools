package Common::Symbols;

#perltidy

use strict;
no strict 'refs';

use vars qw(@ISA);
use IO::Handle;
use Exporter;
use Scalar::Util 'looks_like_number';

@ISA = qw(Exporter);

#------------------------------------------------------------------------------

# name of environment-override prefix; override if required
use vars qw($OVERRIDE_PREFIX);
$OVERRIDE_PREFIX = undef;

#------------------------------------------------------------------------------

=head1 NAME

Common::Symbols - sharable non-volatile data values

=head1 SYNOPSIS

    use Common::Symbols '$EXIT_SUCCESS'; #import one symbol as scalar
    print "The EXIT_SUCCESS symbol is $EXIT_SUCCESS\n";

    use Common::Symbols qw(/EXIT/); # import symbols by RegEx (like Exporter)

    # also for derived classes of Common::Symbols
    use BDE::Symbols qw(:TYPENAME); #import a symbol group as functions
    print "The adapter typename is",ADAPTER_TYPENAME,"\n";
    print "The wrapper typename is",WRAPPER_TYPENAME,"\n";

=head1 DESCRIPTION

C<Common::Symbols> implements a shared repository of constant symbols. It is
intended as a scalable replacement for 'use constant' where the same constant
symbols are shared across several modules and applications.

Any symbol may be exported on request. Symbols may be exported either as
constant functions (i.e. bareword subroutines), constant scalars, or both.
In addition, symbols may be overridden by defining a suitably prefixed
variable in the environment of the invoking process.

Although it is possible to place symbol definitions directly into this
module, it is more common (and strongly recommended) to create a derived
class of C<Common::Symbols> and place new symbol definitions into the new
class. Derived classes may use definitions from their parent symbols module
to construct their own symbols, but do not export symbols defined in a
parent symbols module automatically. See L<"Writing Symbol Subclasses">
below for more information.

=head2 Defining Symbols

Symbol definitions are placed below the C<__DATA__> token located in the source
file of either the C<Common::Symbols> module or a subclass, and are of the
form:

  SYMBOL_NAME => value

Blank lines and comments are handled as in Perl:

  # This is an example symbol
  SYMBOL_NAME => value

  ANOTHER_SYMBOL => erewhon

To include leading or trailing whitespace, quote the value with single or
double quotes:

  SYMBOL_NAME => '  spaced out   '

Double quotes will also cause the value to be interpolated. This allows
symbols to define themselves in terms of one other so long as the referred
symbol appears before the definition of the symbol that uses it:

  SYMBOL_ONE  => act
  SYMBOL_TWO  => "${SYMBOL_ONE}ivate"; # value 'activate'

Braces can be used to define a symbol using a block of perl code:

  USER => { getpwuid($<) }

Symbols can also be defined with deferred evaluation by prefixing the symbol
name with a '+'. In this case the evaluation of the symbol's value will only
take place the first time the symbol is actually used. Deferred symbols cannot
be constant folded by perl because their value is not known at compile time.

  +USER => { sleep 2; getpwuid($<) }

=head2 Including External Symbol Definitions

The special directive C<%INCLUDE> may be used to include an additional
external file of symbol definitions (with the same syntax as above). For
example:

  %INCLUDE "/path/to/symbols/file.txt"

The value of an include directive is evaluated the same way as symbol values,
so other symbols can be used to influence the path.

  %INCLUDE "${LEADING_PATH}/file.txt"

The included file contents are evaluated in the place of the include
directive, so their symbol contributions can be used in the values of other
symbols that appear after the include directive.

=head2 Using Symbols

Once defined, a symbol may be imported as a constant subroutine (which is then
optimised away) or a constant scalar:

  use Derived::Symbols::Class qw(CONSTANT_SUB $CONSTANT_SCALAR);

  print "Constant sub has value ",CONSTANT_SUB,"\n";
  print "Constant scalar has value $CONSTANT_SCALAR\n";

Constant scalars are convenient for interpolation, otherwise they have the
same properties as their subroutine counterparts.

=head2 Tag Groups

Symbols are automatically grouped into tag groups based on the last part of
their name, as determined by the last underscore. (Symbols with no underscore
are not grouped by this process). For instance, the symbols C<FOO_BAZ> and
C<QUX_BAR_BAZ> are both put in group C<BAZ> and may be imported with
C<use Derived::Symbols::Class qw(:BAZ)>. Just as in L<Exporter>, symbols may
also be exported by regular expression, e.g. C<use Symbols qw(/^DEFAULT/);>.

The special C<:ALL> tag may also be used to import all symbols, even ones that
are not otherwise grouped. This is intended for use in subclasses; mass-import
of symbols in general is unhealthy and may cause indigestion.

=head2 Writing Symbol Subclasses

The C<Common::Symbols> module may be inherited from to provide categorised
symbols management on a per-module basis. For example:

  package My::Symbols;

  use Common::Symbols qw($ENABLED $DISABLED); #make superclass symbols visible
  use vars qw(@ISA);
  @ISA=qw(Symbols);

  __DATA__

  MY_SYMBOL           = my_symbol_value"
  MY_OPTIONAL_FEATURE = "$ENABLED"

The C<use Common::Symbols> statement will invoke C<Common::Symbols>'s import
method on its own data, so symbols defined in package C<My::Symbols> may refer
to symbols defined in C<Common::Symbols> as in the last line of the example
above. If necessary this class may be be itself subclassed so its own symbols
may be made visible in a subclass via the import list passed to it in the
C<use> declaration.

Symbols in C<My::Symbols> are not initialised until the module is
itself used elsewhere. This will trigger C<Symbol>'s import method via
inheritance on the symbol data in C<My::Symbols>. Also note that symbols
in parent classes are not automatically made available for import to users of
the subclass; the import list merely makes symbols visible for use in
local symbol definitions. Code that wants to use a symbol from the parent class
should C<use> the parent directly and request the symbol through the import
list.

=head2 Overriding Symbols from the Environment

While symbols are constant in use, they may be redefined from the environment
at application startup. To override symbols in the base module, define
C<$Symbols::OVERRIDE_PREFIX>.

Similarly, to override symbols in a subclass, define the corresponding package
variable according to the package name, e.g. C<My::Symbols::OVERRIDE_PREFIX>.
If a subclass does not provide a default value for this variable then
overrides will be disabled.

Applications may disable or enable overrides for any Symbols-derived module
that permits it (i.e. does not explictly hard-code a prefix) by defining the
variable prior to using the module:

  BEGIN { $My::Symbols::OVERRIDE_PREFIX='FOO_' }
  use My::Symbols qw(BAR);
  #override BAR from environment with FOO_BAR

To disable overrides set or leave the override variable as the undefined value.

=head1 TO DO

The following are changes or enhancements scheduled for future incarnations
of this module:

=over 4

=item Other Data Types

Array and hash symbols are currently not supported. contact the author
if this is important to you. (But note that in the meantime it is perfectly
possible to create an array or hash reference in evaluated code assigned
as a symbol value).

=item Specify OVERRIDE_PREFIX in import list

The OVERRIDE_PREFIX variable for an inherited subclass will ultimately be
definable in the import list via a special syntax of the form:

    use Derived::Symbols::Class (-override=>'BDE_','ROOT','PATH');

=back

=cut

#------------------------------------------------------------------------------

# closure to generate better contextual warnings during symbol definition
{
    my ( $package, $symbol, $value );

    # called with info of next symbol about to be defined
    sub warn_about ($$$) {
        $package = $_[0];
        $symbol  = $_[1];
        $value   = $_[2];
        $value   = "*undef*" unless defined $value;
    }

    # called if a warning occurs, notably in the eval statements improves the
    # warning with contextual info set by warn_about
    sub definition_warning {
        my $msg = shift;
        chomp $msg;
        $msg =~ s/ at .*$//;
        my $prog = $0;
        $0 =~ m|([^/\\]+)$| and $prog = $1;
        print STDERR
          "$msg while defining $package\:\:$symbol, value $value ($prog)\n";
    }
}

#------------------------------------------------------------------------------

# specialised import - make sure we define before we export
{
    my %seen;

    sub import {
        my $package = shift;
        if ( !$seen{$package} ) {
            $package->read_symbols();
        }
        $seen{$package}++;
        $package->export_to_level( 1, $package, @_ );
    }
}

# converts the various string formats we accept in the DATA segment into their
# actual perl value
sub _evaluate {
    my ( $package, $value_string ) = @_;
    my $value;

    s/^\s+//, s/\s+$// for $value_string;

    if ( my ( $quote, $quoted ) = $value_string =~ /^(\'|\")(.*)(\1)$/ ) {

        # we allow quotes so whitespace can be used to pad
        if ( $quote eq '"' ) {

            # if quotes were double quotes, interpolate too
            $value = eval qq(package $package; "$quoted");
        } else {

            # just eat the single quotes
            $value = $quoted;
        }
    } elsif ( my ($expression) = $value_string =~ /^\{(.*)\}$/ ) {

        # curly braces indicate evalable code
        # need to eval code in the context of $package
        # or else things like this wont work:
        #   IS_BUGFIX_ONLY => { -e $BFONLY_FLAG }
        # when $BFONLY_FLAG is defined in the same package
        # as IS_BUGFIX_ONLY
        $value = eval "package $package; $expression";
    } elsif ( looks_like_number($value_string) ) {

        # if it looks like a number, force numeric evaluation
        # or else things like NUM_CONSTANT1 | NUM_CONSTANT2
        # will go awry
        $value = $value_string + 0;
    } else {
        $value = $value_string;
    }

    return $value;
}

# a tied scalar implementation that evaluates by eval'ing itself, allows us to
# define $FOO in terms of &FOO
{

    package Tie::EvalScalar;
    require Tie::Scalar;
    our @ISA = 'Tie::StdScalar';
    use Carp;

    sub STORE {
        carp "Modification of a read-only value attempted";
    }

    sub FETCH {
        return eval ${ $_[0] };
    }
}

# creates a $PACKAGE::FOO and &PACKAGE::FOO symbol table entry that will
# lazily evaluate to the value of $value
sub _install_deferred {
    my ( $package, $symbol, $value_string ) = @_;
    if ( !defined *{"${package}::${symbol}"}{CODE} ) {
        my $value_ref;
        *{"${package}::${symbol}"} = sub () {
            if ( !$value_ref ) {
                $$value_ref = _evaluate( $package, $value_string );
            }
            return $$value_ref;

        };
        tie my $s, 'Tie::EvalScalar', "${package}::${symbol}";
        *{"${package}::${symbol}"} = \$s;
    }
}

# creates a true readonly $PACKAGE::FOO and a constant-foldable &PACKAGE::FOO
# in the symbol table from the immediately evaluated value of $value
sub _install_constant {
    my ( $package, $symbol, $value_string ) = @_;

    if ( !defined *{"${package}::${symbol}"}{CODE} ) {
        my $value = _evaluate( $package, $value_string );
        *{"${package}::${symbol}"} = sub () { $value };
        *{"${package}::${symbol}"} = \$value;
        no strict 'refs';
        Internals::SvREADONLY( ${"${package}::${symbol}"} => 1 );
    }
}

# autogenerate @EXPORT_OK and %EXPORT_TAGS from data
sub read_symbols {
    my $package = shift;
    my $class = ref($package) || $package;

    my $data;
    {    # The DATA pseudohandle is not as friendly as might be desired
        local $/ = undef;
        $data = eval "package $class; <DATA>";
    }

    return unless $data;    #either nothing defined, or it's already read

    local $SIG{__WARN__} = \&definition_warning;    #only for this scope

    my @data = split /\n/, $data;
    while (@data) {
        my $item = shift @data;

        $item =~ s/[\r\n]+$//;  #all-platform chomp, seemingly needed for Cygwin

        next if $item =~ /^\s*($|\#)/;    # skip if a comment or blank line

        if ( $item =~ /^\s*\%INCLUDE\s*(\S.*)\s*$/ ) {

            # include files
            my $file = _evaluate( $class, $1 );
            if ( open my $fh, $file ) {
                unshift @data, <$fh>;
                close $fh;
            } elsif ( $^O =~ /win/i ) {
            } else {
                # Useless warning - not going to bother with it any more unless
                # BDE_BACKTRACE is set in env...
                warn "Unable to open symbol definition file" . " '$file': $!\n"
                            if exists $ENV{BDE_BACKTRACE};
            }
        } else {

            # symbol definition

            my ( $deferred, $symbol, $value_string ) =
              $item =~ /^\s*(\+)?(\w+)\s*=>\s*(\S.*)\s*$/
              or die "Invalid symbol def: $item\n";

            # for definition_warning
            warn_about( $class, $symbol => $value_string );

            # check for and allow environment to override the value
            my $env;
            if ( defined ${ $package . '::OVERRIDE_PREFIX' } ) {
                $env = $ENV{ ${ $package . '::OVERRIDE_PREFIX' } . $symbol };
                if ( defined $env ) {

                    # values from the environment are handled as if they were
                    # single quoted
                    $value_string = $env;
                    $value_string =~ s/^(\'|\")(.*)(\1)$/$2/;
                    $value_string = qq('$value_string');
                }
            }

            if ($deferred) {
                _install_deferred( $class, $symbol, $value_string );
            } else {
                _install_constant( $class, $symbol, $value_string );
            }

            # add symbol and constant scalar to export list
            push @{ $class . '::EXPORT_OK' }, $symbol, "\$$symbol";

            # any symbol with a '_' in it is assumed to belong to a tag
            # group whose name is the last part of the symbol name. Add
            # matching symbols to their tag groups
            if ( $symbol =~ /_([A-Z][A-Z0-9]*)$/ ) {
                my $tag = $1;
                ${ $class . '::EXPORT_TAGS' }{$tag} ||= [];
                push @{ ${ $class . '::EXPORT_TAGS' }{$tag} }, $symbol,
                  "\$$symbol";
            }

            # define the ':ALL' tag
            push @{ ${ $class . '::EXPORT_TAGS' }{'ALL'} }, $symbol,
              "\$$symbol";
        }
    }
}

#------------------------------------------------------------------------------

=head1 AUTHOR

Peter Wainwright, pwainwright@bloomberg.net

=cut

1;

__DATA__
