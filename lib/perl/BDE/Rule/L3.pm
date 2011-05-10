package BDE::Rule::L3;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;
use Source::Iterator::CPlusMode;
use Source::Util::ParseTools qw(getParamUserTypes);
use Util::Message qw(debug);
use BDE::Util::RuntimeFlags qw(getDeprecationLevel);
use Source::Symbols qw(PREPROCESSOR
                       EXTERN
                       EXTERNC
                       EXTERNC_END
                       NAMESPACE
                       NAMESPACE_END
                       UNAMESPACE
                       UNAMESPACE_END
                       SEMI_COLON
                       CLASS_FWD
                       UNION_FWD
                       OPERATOR_FWD
                       UNION
                       CLASS
                       METHOD
                       OPERATOR
                       FUNCTION
                       UNAMESPACE_END
                       ENUM);
use BDE::Rule::Codes qw(ILL_SCOPE
                        ILL_DECDEF
                        ILL_FREE_OP
                        ETC_MORE_ERRORS
                        NS_STATE_NON_NS);
use Context::Message::Codes qw(EMP_FILE);
use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::L3 - Verification of header declarations and defintions

=head1 SYNOPSIS

my $rule = new BDE::Rule::L3;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

This rule carries out the following checks:

* L3a: Verification of interface declarations and definitions

* L3b: Verification of free operator arguments

See C<bde_rule.pl L3> for more information.

=head1 TEST DRIVERS

Test drivers are supplied by this module.  To invoke, enter:

perl -w -MBDE::Rule::L3 -e "BDE::Rule::L3->testL3a"

perl -w -MBDE::Rule::L3 -e "BDE::Rule::L3->testL3b"

#<<TODO: add more test vectors

=cut

#==============================================================================

=head2 verifyL3a()

=cut

sub verifyL3a($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule L3a...");

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "L3a");
    my $rc = 0;

    my $file = $component->getIntfFile;
    $ctx->setDefault(fileName => $file->getName);
    $ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

    my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
    $ctx->setDefault(displayFrom => $file->getFullSource,
                     lineNumber  => $iter);

    $iter->deselect(PREPROCESSOR,
                    EXTERN,
                    EXTERNC,
                    EXTERNC_END,
                    SEMI_COLON,
                    NAMESPACE_END,
                    UNAMESPACE,
                    UNAMESPACE_END);
    my $ns;

    while (defined(my $line = $iter->next)) {
        if (!$iter->inBlock(NAMESPACE)) {
            $ctx->addError(code => &NS_STATE_NON_NS);
            $rc = 1;
            last;
        }
        elsif ($iter->getStatementType eq NAMESPACE) {
            next if !getDeprecationLevel() and $iter->blockDepth(NAMESPACE) > 2 or
              getDeprecationLevel() == 2 and $iter->blockDepth(NAMESPACE) > 1;
            $ns = 1;
        }
        elsif ($ns) {  # validate statements immediately after namespace statement
            $ns = 0;
            if ($iter->getStatementType ne CLASS_FWD    and
                $iter->getStatementType ne UNION_FWD    and
                $iter->getStatementType ne OPERATOR_FWD and
                $iter->getStatementType ne CLASS        and
                $iter->getStatementType ne UNION        and
                !($line =~ /\binline\b/o and
                  $iter->isStatementType(METHOD)   ||
                  $iter->isStatementType(OPERATOR) ||
                  $iter->isStatementType(FUNCTION))) {
                $ctx->addError(code => &ILL_DECDEF);
                $rc = 1;
            }
        }
    }
    return $rc;
}

#------------------------------------------------------------------------------

=head2 verifyL3b($component)

=cut

sub verifyL3b($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule L3b...");

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "L3b");
    my $rc = 0;

    my $file = $component->getIntfFile;

    $ctx->setDefault(fileName    => $file->getName);
    $ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

    my $iter = new Source::Iterator::CPlusMode($file->getSlimSource());
    $ctx->setDefault(displayFrom => undef, lineNumber  => undef);

    my @freeOpTypes;

    while (defined(my $line = $iter->next)) {
        if ($iter->isStatementType(OPERATOR_FWD) and !$iter->inClassOrStruct) {
            $line =~ /\boperator\b.*?\((.*?)\)/so;
            my @tmp;
            for my $tmp (getParamUserTypes($1)) {
                push @tmp, $iter->getScope."::".$tmp;
            }
            push @freeOpTypes, \@tmp;
        }
    }

    my @types = $iter->getNames(CLASS);
    push(@types, $iter->getNames(ENUM));
    push(@types, $iter->getNames(UNION));

    for my $ref (@freeOpTypes) {
        my $found;
        my $str = "";
        for my $type (@$ref) {
            $found++, last if grep /^$type$/, @types;
            $str .= "$type $str";
        }
        next if $found;
        $ctx->addError(code => &ILL_FREE_OP, text => "$str", lineNumber => undef);
    }
    return $rc;
}

#------------------------------------------------------------------------------

sub verify ($$) {
    my ($self, $component)=@_;
    my $result = $self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    $result =
      $self->verifyL3a($component) +
      $self->verifyL3b($component);

    return $self->setResult($result);
}

#==============================================================================

sub testL3a() {

my $comp = "bdes_types";

my $N  = "namespace N {\n";
my $C1 = "class C {};\n";
my $S1 = "struct C {};\n";
my $F1 = "void M() {}\n";

my $C2 = "class C {\n";

my $cb = "}";
my $sc = ";";

my @DATA = (

#            <-------------- INPUT -------------> <-------- OUTPUT -------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====

# --- D0 ---
{a=>__LINE__,b=>                               "",c=>          EMP_FILE,d=>1 },

# --- D1 ---
{a=>__LINE__,b=>                            "$C1",c=>   NS_STATE_NON_NS,d=>1 },
{a=>__LINE__,b=>                            "$F1",c=>   NS_STATE_NON_NS,d=>1 },
{a=>__LINE__,b=>                          "$N$cb",                      d=>0 },

# --- D2 ---
{a=>__LINE__,b=>                       "$N$C1$cb",                      d=>0 },
{a=>__LINE__,b=>                       "$N$S1$cb",                      d=>0 },
{a=>__LINE__,b=>                       "$N$F1$cb",c=>        ILL_DECDEF,d=>1 },

# --- D2 ---
{a=>__LINE__,b=>              "$N$C2$F1$cb$sc$cb",                      d=>0 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $errCode = ${$entry}{c};
    my $rc      = ${$entry}{d};

    print "LINE: $line INPUT:\n$input\n" if $ENV{BDE_TRACE};

    my($tmpnam, $fh);
    $tmpnam = POSIX::tmpnam();
    $fh = IO::File->new($tmpnam, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh "$input\n";
    close $fh;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam);
    $compObj->readImplementation($tmpnam);
    my $rule = new BDE::Rule::L3;

    ASSERT(__LINE__ . ".$line", $rule->verifyL3a($compObj), $rc);
    if ($errCode) {
        $rule->getContext->getMessage(0) and
          ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) or
            ASSERT(__LINE__ . ".$line", 0, $errCode);
    }
    unlink($tmpnam);
  }

}

#------------------------------------------------------------------------------

sub testL3b() {

my $comp = "bdes_types";

my $C1 = "class C {};";
my $O1 = "void operator+(C c);\n";
my $O2 = "void operator+(C c,int i);\n";
my $O3 = "void operator+(int i,C c);\n";
my $O4 = "void operator+(int i);\n";
my $O5 = "void operator+(int i,int j);\n";

my $X  = "#define x";

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====

# --- D0 ---
{a=>__LINE__,b=>            "",c=>             "",d=>          EMP_FILE,e=>1 },

# --- D2 ---
{a=>__LINE__,b=>      "$C1$O1",c=>           "$X",                      e=>0 },
{a=>__LINE__,b=>      "$C1$O2",c=>           "$X",                      e=>0 },
{a=>__LINE__,b=>      "$C1$O3",c=>           "$X",                      e=>0 },
{a=>__LINE__,b=>      "$C1$O4",c=>           "$X",d=>       ILL_FREE_OP,e=>0 },
{a=>__LINE__,b=>      "$C1$O5",c=>           "$X",d=>       ILL_FREE_OP,e=>0 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line     = ${$entry}{a};
    my $inputh   = ${$entry}{b};
    my $inputcpp = ${$entry}{c};
    my $errCode  = ${$entry}{d};
    my $rc       = ${$entry}{e};

    print "LINE: $line INPUT:\n\n$inputh\n\n$inputcpp\n------\n" if $ENV{BDE_TRACE};

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
    my $rule = new BDE::Rule::L3;

    ASSERT(__LINE__ . ".$line", $rule->verifyL3b($compObj), $rc);
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
Verification of interface declarations and definitions
------------------------------------------------------

a. Only classes, structures, unions and free operators can be *declared* at
   namespace scope in the component header; only classes, structures, unions
   and inline functions can be *defined* at namespace scope.

   [cross reference: rule 17]

b. A component header may contain a *declaration* of a free operator only when
   one or more of its argument types are *defined* in the *same* component.

   [cross reference: rule 18]



