package BDE::Rule::L1;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;
use Source::Iterator::LineMode;
use Source::Iterator::CPlusMode;
use Util::Message qw(debug);
use BDE::Util::RuntimeFlags qw(getDeprecationLevel);
use BDE::Util::Nomenclature qw(isComponent
                               getComponentPackage);

use Source::Symbols qw(PREPROCESSOR
                       NAMESPACE
                       UNAMESPACE
                       CLASS
                       METHOD
                       OPERATOR
                       FUNCTION
                       STATIC_FUNCTION
                       METHOD_FWD
                       OPERATOR_FWD
                       FUNCTION_FWD
                       STATIC_FUNCTION_FWD);
use BDE::Rule::Codes qw(NO_DEFINE_GUARD
                        NO_IFNDEF_GUARD
                        EXT_IFNDEF
                        DPR_GUARD
                        NO_INTF_INCLUDE
                        ILL_METHOD_DEF
                        NO_FUNC_DEC);
use Context::Message::Codes qw(EMP_FILE);
use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::L1 - Verification of public interface

=head1 SYNOPSIS

 my $rule = new BDE::Rule::L1;
 my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

This rule carries out the following checks:

=over

=item *

L1a: The interface file contains a correctly named include guard

=item *

L1b: The implementation file includes the interface file as its first act

=item *

L1c: A component must not define externally visible constructs which are 
not declared in interface, and the definition of a logical entity with external
linkage must be in the same component in which the entity is declared.

=back

See C<bde_rule.pl L1> for more information.

=head1 TEST DRIVERS

Test drivers are supplied by this module.  To invoke, enter:

=over

=item *

perl -w -MBDE::Rule::L1 -e "BDE::Rule::L1->testL1a"

=item *

perl -w -MBDE::Rule::L1 -e "BDE::Rule::L1->testL1b"

=item *

perl -w -MBDE::Rule::L1 -e "BDE::Rule::L1->testL1c"

=over

=cut

#=============================================================================

=head1 METHODS

=head2 verifyL1a($component)

Verify that the interface file contains a correctly named include guard.

Standard guard form:

    /^\s*#\s*ifndef\s+(INCLUDED_\U$component)/

Deprecated guard form:

    /^\s*#\s*(?:ifndef|if\s*!\s*defined)\s*[(]?(\w*$component\w*)[)]?\s*$/i

=cut

sub verifyL1a($$) {
    my ($self,$component) = @_;

    debug("Invoking sub-rule L1a...");

    my $intf = $component->getIntfFile;
    my $ctx = $self->getContext();
    $ctx->setDefault(rule        => "L1a",
		     fileName    => $intf->getName());
    $ctx->addError(code => &EMP_FILE), return 1 if $intf->isEmpty;

    my $iter = new Source::Iterator::LineMode($intf->getSlimSource);
    $ctx->setDefault(displayFrom => $intf->getFullSource,
                     lineNumber  => $iter);

    my $line;
    my $guard = qr/^\s*#\s*ifndef\s+(INCLUDED_\U$component)/;
    my $dprGuard = qr/^\s*#\s*(?:ifndef|if\s*!\s*defined)\s*[(]?(\w*$component\w*)[)]?\s*$/i;
    my $ifndefGuard;
    my $depth;

    while (defined($line = $iter->next)) {

        next if $line eq "";

        if (($line =~ $guard or $line =~ $dprGuard) and !$ifndefGuard) {
            $ifndefGuard = $1;
            if ($ifndefGuard =~ $dprGuard) {
                $ctx->addError(code => &DPR_GUARD), return 1 if
                  !getDeprecationLevel();
                $ctx->addWarning(code => &DPR_GUARD);
            }
            $line = $iter->next;
	    $ctx->addError(code => &NO_DEFINE_GUARD), return 1 if
              $line !~ /^\s*#\s*define\s+$ifndefGuard$/;
            $depth++;  # keep track of #ifdef depth
        }

        # we should have seen #ifndef if we get here...
        elsif (!$ifndefGuard) {
	    $ctx->addError(code => &NO_IFNDEF_GUARD);
            return 1;
        }

        # content outside of $ifdef
        if (!$depth) {
            $ctx->addError(code => &EXT_IFNDEF);
            return 1;
        }

        # need to also increment depth for other CPPs...
        elsif ($line =~ /^\s*#\s*(?:ifndef|ifdef|if)/g) {
            $depth++;
        }

        # decrement depth
        elsif ($line =~ /^\s*#\s*endif/o) {
            $depth--;
        }
    }

    return 0; #success
}

#------------------------------------------------------------------------------

=head2 verifyL1B($component)

Verify that the implementation file includes the interface file as its first
substantive act.

=cut

sub verifyL1b ($$) {
    my ($self,$component) = @_;
 
    debug("Invoking sub-rule L1b...");

    my $impl = $component->getImplFile;
    my $ctx = $self->getContext();
    $ctx->setDefault(rule        => "L1b",
		     fileName    => $impl->getName);
    $ctx->addError(code => &EMP_FILE), return 1 if $impl->isEmpty;

    my $iter = new Source::Iterator::LineMode($impl->getSlimSource);
    $ctx->setDefault(displayFrom => $impl->getFullSource,
                     lineNumber  => $iter);

    my $line = $iter->next;
    return 0 if $line =~ /^\s*#\s*include\s+[<"]\s*$component\.h\s*[>"]/;
    $ctx->addError(code => &NO_INTF_INCLUDE);
    return 1;
}

#------------------------------------------------------------------------------

=head2 verifyL1c($self,$component)

A component must not define externally visible constructs which are not
declared in interface.

=cut

sub verifyL1c($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule L1c...");

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "L1c", lineNumber => undef, displayFrom => undef);
    my $rc = 0;
    my($file,$iter);

    $file = $component->getIntfFile;
    $ctx->addError(code => &EMP_FILE,fileName => $file->getName), return 1 if $file->isEmpty;
    $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
    $iter->deselect(UNAMESPACE, STATIC_FUNCTION, STATIC_FUNCTION_FWD);

    while (defined(my $line = $iter->next)) { }

#       my $tmp = $iter->getScope;
#       push(@scopes, $tmp) if $tmp and !grep /^\Q$tmp\E$/,@scopes;

    # save all declarations
    my(%decs);
    for my $name ($iter->getNames(METHOD_FWD, OPERATOR_FWD, FUNCTION_FWD)) {
#                  $iter->getPrivateNames(METHOD_FWD, OPERATOR_FWD, FUNCTION_FWD)) {
        $decs{$name}++;
    }

    # remove declaration if also defined
    #for my $name ($iter->getNames(METHOD, OPERATOR, FUNCTION),
    #              $iter->getPrivateNames(METHOD, OPERATOR, FUNCTION)) {
    #    delete $decs{$name};
    #}
    #print keys(%decs),"\n";

    $file = $component->getImplFile;
    $ctx->addError(code => &EMP_FILE,fileName => $file->getName), return 1 if $file->isEmpty;
    $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
    $iter->deselect(UNAMESPACE, STATIC_FUNCTION, STATIC_FUNCTION_FWD);
    while (defined(my $line = $iter->next)) { }


    for my $name ($iter->getNames(METHOD, OPERATOR, FUNCTION)) {
#                  $iter->getPrivateNames(METHOD, OPERATOR, FUNCTION)) {

        # Do not complain about qualified names if the qualified name is
        # within a class.  This prevents giving an error for every member of
        # the class.  If we want, we give a single error about the class
        # itself not being in the .h file (currently this is not detected).
        my $qualification = $name =~ /^(.*)::[^:]+$/ ? $1 : "";

        $ctx->addError(code => &NO_FUNC_DEC, text => $name), $rc=1
	  unless $decs{$name} || $iter->getName($qualification, CLASS);
    }

#   push(@defs, $iter->getNames(METHOD, OPERATOR, FUNCTION));
#   push(@defs, $iter->getPrivateNames(METHOD, OPERATOR, FUNCTION));

#   for my $def (@defs) {
#       my $qmdef;
#	$qmdef = quotemeta($def);
#       $ctx->addError(code => &NO_FUNC_DEC, text => "\"$def\""), $rc=1
#	  unless grep /^$qmdef$/, @decs;
#       if (@scopes) {
#           $def =~ s/(.+)::.+?$/$1/;
#           $qmdef = quotemeta($def);
#           $ctx->addError(code => &NO_FUNC_DEC, text => "\"$def\""), $rc=1
#             unless grep /^$qmdef$/, @scopes;
#       }
#   }
    return $rc;
}

#------------------------------------------------------------------------------

sub verify ($$) {
    my ($self, $component)=@_;

    my $result = $self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    $result = $self->verifyL1a($component)
            + $self->verifyL1b($component)
            + $self->verifyL1c($component);

    return $self->setResult($result);
}

#==============================================================================

sub testL1a() {

my $comp = "bdes_types";

my $G  = "INCLUDED_BDES_TYPES";
my $I  = "#ifndef $G\n";
my $D  = "#define $G\n";
my $E  = "#endif\n";
my $S  = "int i;\n";

my $R1 = "static const char rcs \$Header:\n";
my $R2 = "#ifndef lint\nstatic const char rcs \$Header:\n#endif\n";

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====

# --- D0 ---
{a=>__LINE__,b=>                               "",c=>          EMP_FILE,d=>1 },

{a=>__LINE__,b=>                         "$I$D$E",                      d=>0 },
{a=>__LINE__,b=>                           "$I$E",c=>   NO_DEFINE_GUARD,d=>1 },
{a=>__LINE__,b=>                             "$D",c=>   NO_IFNDEF_GUARD,d=>1 },
{a=>__LINE__,b=>                     "$I$D$E$I$E",c=>        EXT_IFNDEF,d=>1 },
{a=>__LINE__,b=>                       "$I$D$E$S",c=>        EXT_IFNDEF,d=>1 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $errCode = ${$entry}{c};
    my $rc      = ${$entry}{d};

    my($tmpnam, $fh);
    $tmpnam = POSIX::tmpnam();
    $fh = IO::File->new($tmpnam, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh "$input\n";
    close $fh;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam);
    $compObj->readImplementation($tmpnam);
    my $rule = new BDE::Rule::L1;
    ASSERT(__LINE__ . ".$line", $rule->verifyL1a($compObj), $rc);
    ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) if $errCode;
    unlink($tmpnam);
  }

}

#------------------------------------------------------------------------------

sub testL1b() {

my $comp = "bdes_types";

my $I1  = "#include \"$comp.h\"\n";
my $I2  = "#include <$comp.h>\n";
my $D  = "#define aaa\n";

my $R1 = "static const char rcs \$Header:\n";
my $R2 = "#ifndef lint\nstatic const char rcs \$Header:\n#endif\n";

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====

# --- D0 ---
{a=>__LINE__,b=>                               "",c=>          EMP_FILE,d=>1 },

{a=>__LINE__,b=>                            "$I1",                      d=>0 },
{a=>__LINE__,b=>                          "$I1$D",                      d=>0 },
{a=>__LINE__,b=>                            "$I2",                      d=>0 },
{a=>__LINE__,b=>                             "$D",c=>   NO_INTF_INCLUDE,d=>1 },
{a=>__LINE__,b=>                          "$D$I1",c=>   NO_INTF_INCLUDE,d=>1 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $errCode = ${$entry}{c};
    my $rc      = ${$entry}{d};

    my($tmpnam, $fh);
    $tmpnam = POSIX::tmpnam();
    $fh = IO::File->new($tmpnam, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh "$input\n";
    close $fh;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam);
    $compObj->readImplementation($tmpnam);
    my $rule = new BDE::Rule::L1;
    ASSERT(__LINE__ . ".$line", $rule->verifyL1b($compObj), $rc);
    ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) if $errCode;
    unlink($tmpnam);
  }

}

#------------------------------------------------------------------------------

sub testL1c() {

my $comp = "bdes_types";

my $H0 = "#define z\n";
my $C0 = "#define z\n";

# functions
my $H1  = "void F();\n";
my $H2  = "namespace N { void F(); }\n";
my $C1  = "void F(){}\n";
my $C1a = "void F(){}\nstatic void FF(){}\n";
my $C2  = "namespace N { void F(){} }\n";
my $C5  = "namespace N { extern \"C\" void F(){} }\n";

# classes
my $H3 = "class C { void M(); };\n";
my $H4 = "namespace N { class C { void M(); }; }\n";
my $H5 = "namespace N { class C { N::C::operator unsigned long(); }; }\n";
my $C3 = "void C::M(){}\n";
my $C4 = "void N::C::M(){}\n";
my $C6 = "extern \"C\" void C::M(){ if (0) return; }\n";
my $C7 = "N::C::operator unsigned long() const { }\n";
my $C8 = "namespace N { struct D { void M(const char *l) { foo(); } } };\n";

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====

# --- D0 ---
{a=>__LINE__,b=>            "",c=>             "",d=>          EMP_FILE,e=>1 },

# --- D2 ---
{a=>__LINE__,b=>         "$H0",c=>          "$C0",                      e=>0 },
{a=>__LINE__,b=>         "$H1",c=>          "$C0",                      e=>0 },
{a=>__LINE__,b=>         "$H2",c=>          "$C0",                      e=>0 },

{a=>__LINE__,b=>         "$H0",c=>          "$C1",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H1",c=>          "$C1",                      e=>0 },
{a=>__LINE__,b=>         "$H1",c=>         "$C1a",                      e=>0 },
{a=>__LINE__,b=>         "$H2",c=>          "$C1",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H2",c=>         "$C1a",d=>       NO_FUNC_DEC,e=>1 },

{a=>__LINE__,b=>         "$H0",c=>          "$C2",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H1",c=>          "$C2",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H2",c=>          "$C2",                      e=>0 },

{a=>__LINE__,b=>         "$H0",c=>          "$C5",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H1",c=>          "$C5",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H2",c=>          "$C5",                      e=>0 },

{a=>__LINE__,b=>         "$H3",c=>          "$C0",                      e=>0 },
{a=>__LINE__,b=>         "$H4",c=>          "$C0",                      e=>0 },

{a=>__LINE__,b=>         "$H0",c=>          "$C3",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H3",c=>          "$C3",                      e=>0 },
{a=>__LINE__,b=>         "$H4",c=>          "$C3",d=>       NO_FUNC_DEC,e=>1 },

{a=>__LINE__,b=>         "$H0",c=>          "$C4",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H3",c=>          "$C4",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H4",c=>          "$C4",                      e=>0 },

{a=>__LINE__,b=>         "$H0",c=>          "$C6",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H3",c=>          "$C6",                      e=>0 },
{a=>__LINE__,b=>         "$H4",c=>          "$C6",d=>       NO_FUNC_DEC,e=>1 },

#{a=>__LINE__,b=>         "$H4",c=>          "$C7",d=>       NO_FUNC_DEC,e=>1 },
{a=>__LINE__,b=>         "$H5",c=>          "$C7",                      e=>0 },

{a=>__LINE__,b=>         "$H0",c=>          "$C8",                      e=>0 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line     = ${$entry}{a};
    my $inputh   = ${$entry}{b};
    my $inputcpp = ${$entry}{c};
    my $errCode  = ${$entry}{d};
    my $rc       = ${$entry}{e};

    my($tmpnamh, $fhh);
    $tmpnamh = POSIX::tmpnam();
    $fhh = IO::File->new($tmpnamh, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fhh "$inputh\n";
    close $fhh;

    my($tmpnamcpp, $fhcpp);
    $tmpnamcpp = POSIX::tmpnam();
    $fhcpp = IO::File->new($tmpnamcpp, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fhcpp "$inputcpp\n";
    close $fhcpp;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnamh);
    $compObj->readImplementation($tmpnamcpp);
    my $rule = new BDE::Rule::L1;
    ASSERT(__LINE__ . ".$line", $rule->verifyL1c($compObj), $rc);
    if ($errCode) {
        $rule->getContext->getMessage(0) and
          ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) or
            ASSERT(__LINE__ . ".$line", 0, $errCode);
    }
    unlink($tmpnamh);
    unlink($tmpnamcpp);
  }

}

#==============================================================================

=head1 AUTHOR

Ralph Gibbons

=head1 SEE ALSO

BDE::Rule::Base

=cut

#==============================================================================

1;

__DATA__
Verification of public interface
--------------------------------

a. The header file must contain an "include guard" of the form:

       #ifndef  INCLUDED_<COMPONENT>
       #define INCLUDED_<COMPONENT>
       <content>
       #endif

   Deprecated forms are also supported.

   All non-commentary content must be contained between the #define and #endif
   statements.  Note that <COMPONENT> is the name of the component shifted
   entirely to upper case, and does not include the file extension.

   [cross reference: rule 14]

b. The implementation file must include its own header file as its first
   substantive act.

   [cross reference: rule 16]

c. A component must not define externally visible constructs which are not
   declared in interface.

   [cross reference: rule 10]

   The definition of a logical entity with external linkage must be in the
   same component in which the entity is declared.

   [cross reference: rule 11]

   Limitations:

   1. Currently the checks are only performed for methods and functions.

   2. Functions cannot be declared "extern".


