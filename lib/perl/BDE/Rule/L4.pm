package BDE::Rule::L4;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;
use Source::Iterator::CPlusMode;
use BDE::Util::Nomenclature  qw(isGroupedPackage
                                isAdapter
                                isWrapper
                                isValidDependency);
use BDE::Rule::Codes         qw(ILL_INCLUDE
                                ILL_DPT_INCLUDE
                                NS_STATE_NON_NS
                                NS_STATE_NON_PNS
                                NS_NO_BLP
                                NS_NO_PKG
                                NS_PG_INVALID);
use BDE::Util::RuntimeFlags qw(getDeprecationLevel
                               getNoMetaMode);
use Source::Symbols qw(PREPROCESSOR
                       EXTERN
                       EXTERNC
                       EXTERNC_END
                       SEMI_COLON
                       UNAMESPACE
                       UNAMESPACE_END
                       NAMESPACE
                       NAMESPACE_END
                       CLASS_FWD
                       OPERATOR);

use Context::Message::Codes qw(EMP_FILE);
use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::L4 - Verification of namespace constructs

=head1 SYNOPSIS

my $rule = new BDE::Rule::L4;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

This checks that code is contained within correctly named namespaces, and that
the namespaces are in the correct logical order.

See C<bde_rule.pl L4> for more information.

=head2 TEST DRIVERS

A test driver is supplied by this module.  To invoke, enter:

perl -w -MBDE::Rule::L4 -e "BDE::Rule::L4->testL4"

#<<TODO: add more test vectors

=cut

#==============================================================================

=head2 verifyL4($component)

=cut

sub verifyL4($$) {
    my $self = shift;
    my $component = shift;
    my $fs = shift;

    my $rc = 0;
    my $ctx = $self->getContext();
    $ctx->setDefault(rule => "L4");

    # loop over .cpp and .h
    foreach my $file ($component->getIntfFile, $component->getImplFile) {

        $ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

	my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
	$ctx->setDefault(fileName    => $file->getName,
			 displayFrom => $file->getFullSource);

        $iter->deselect(PREPROCESSOR,
                        EXTERN,
                        EXTERNC,
                        EXTERNC_END,
                        SEMI_COLON,
                        NAMESPACE_END,
                        UNAMESPACE,
                        UNAMESPACE_END);

        my $lineSeen;
        my $innerNSSeen;

        while (defined(my $line = $iter->next)) {

            $lineSeen++;

            # must be in at least one namespace
            if (!$iter->inBlock(NAMESPACE)) {
                $ctx->addError(code => &NS_STATE_NON_NS, lineNumber  => $iter);
                $rc = 1;
                last;
            }

            # non-namespace statement
            if (!$iter->isStatementType(NAMESPACE)) {
                if ($iter->blockDepth(NAMESPACE) == 1  and
                    !getDeprecationLevel()             and
                    !$iter->isStatementType(CLASS_FWD) ) {
                    $ctx->addError(code => &NS_STATE_NON_PNS, lineNumber  => $iter);
                    $rc = 1;
                }
                next;
            }

            # namespace depth == 1 should be BloombergLP
            if ($iter->blockDepth(NAMESPACE) == 1 and $line !~ /namespace\s+BloombergLP\s*{/o) {
                $ctx->addError(code => &NS_NO_BLP, lineNumber  => $iter);
                $rc = 1;
                last;
            }

            # namespace depth > 1
            else {
                $line =~ /namespace\s+(\S+)\s*{/;
                my $ns = $1;

                # depth 2 might be package or (deprecated) package group
                if ($iter->blockDepth(NAMESPACE) == 2 and
                    ($ns eq $component->getComponentPackage or
                     isGroupedPackage($component->getComponentPackage) and
                     $ns eq $component->getComponentGroup)) {
                    if ($ns eq $component->getComponentPackage) {
                        $innerNSSeen++;
                    }
                    else {
                        if (!getDeprecationLevel()) {
                            $ctx->addError(code => &NS_PG_INVALID, lineNumber  => $iter);
                            $rc = 1;
                        }
                        else {
                            $ctx->addWarning(code => &NS_PG_INVALID, lineNumber  => $iter);
                            $innerNSSeen++;
                        }
                    }
                }

                # other namespace needs to be checked as valid or not dependency
                else {
                    my $ivd = isValidDependency($component, $ns);
                    if (!$ivd) {
                        $ctx->addError(code => &ILL_INCLUDE, lineNumber  => $iter);
                        $rc = 1;
                    }
                    elsif ($ivd == 2        and 
                           !getNoMetaMode() and 
                           $fs->getDepartment($component) ne $fs->getDepartment($ns)) {
                        $ctx->addError(code => &ILL_DPT_INCLUDE, lineNumber  => $iter);
                        $rc = 1;
                    }
                }
            }
        } 


        # test to see if any package-level namespace was found
        if ($lineSeen) {
            if (!$innerNSSeen) {
                if (getDeprecationLevel() != 2) {
                    $ctx->addError(code => &NS_NO_PKG);
                    $rc = 1;
                }
                else {
                    $ctx->addWarning(code => &NS_NO_PKG, text => "(deprecated)");
                }
            }
        }
    }
    return $rc;
}

#------------------------------------------------------------------------------

sub verify ($$$$) {
    my ($self,$component,$fs,$noMeta)=@_;
    my $result=$self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    return($self->setResult(0)) if isWrapper($component);

    $result=$self->verifyL4($component, $fs, $noMeta);

    return $self->setResult($result);
}

#==============================================================================

sub testL4() {

my $pkg = "bdes";
my $comp = $pkg . "_types";

my $Ns1  = "namespace BloombergLP {\n";
my $Ns2  = "namespace $pkg {\n";
my $Cb   = "}\n";
my $Cl   = "class {};";
my $Fn   = "void f(){}";
my $S    = "int i;";

my @DATA = (

#            <------------------- INPUT ------------------> <------- OUTPUT -------->
#
#    line                         input                           error code       rc
#=========== ============================================== ==================== ====
# --- D0 ---
{a=>__LINE__,b=>                           "$Ns1$Ns2$Cb$Cb",                      d=>0},

{a=>__LINE__,b=>                                         "",c=>  EMP_FILE,        d=>1},

# --- D1 ---

{a=>__LINE__,b=>                                  "$Ns2$Cb",c=>         NS_NO_BLP,d=>1},
{a=>__LINE__,b=>                                "$Ns1$S$Cb",c=>  NS_STATE_NON_PNS,d=>1},

);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $errCode = ${$entry}{c};
    my $rc      = ${$entry}{d};

    print "LINE: $line INPUT:\n$input\n" if $ENV{BDE_TRACE};

    my($tmpnam1, $tmpnam2, $fh1, $fh2);
    $tmpnam1 = POSIX::tmpnam();
    $fh1 = IO::File->new($tmpnam1, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh1 "$input\n";
    close $fh1;

    $tmpnam2 = POSIX::tmpnam();
    $fh2 = IO::File->new($tmpnam2, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh2 "#include \"$comp.h\"\n";
    close $fh2;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam1);
    $compObj->readImplementation($tmpnam2);
    my $rule = new BDE::Rule::L4;
    my $realRC = $rule->verifyL4($compObj);
    ASSERT(__LINE__ . ".$line", $realRC, $rc);
    if ($errCode) {
        $rule->getContext->getMessage(0) and
          ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) or
            ASSERT(__LINE__ . ".$line", 0, $errCode);
    }
    elsif ($realRC and $rule->getContext->getMessage(0)) {
        print "GOT UNEXPECTED ERROR: ".$rule->getContext->getMessage(0)->{code}."\n";
    }
    unlink($tmpnam1);
    unlink($tmpnam2);
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
Namespace verification
----------------------

Every logical construct defined in a C++ component (or C++ source file, in the
case of applications) must be nested within the BloombergLP namespace.  C++
components must further nest their logical constructs within a package-named
namespace.

There are two exceptions to this latter rule:

  1. Free operator *definitions* *must* be outside of the inner namespace.

  2. Forward declarations *may* be outside of the inner namespace.


Deprecation level 1 permits package group-named namespaces.

Deprecation level 2 permits omission of inner namespaces.

[cross references: rules 15,4,5]


