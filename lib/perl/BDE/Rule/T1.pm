package BDE::Rule::T1;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;
use Source::Iterator::CPlusMode;
use BDE::Util::Nomenclature qw(isComponent getComponentGroup getComponentPackage);
use Util::Message qw(debug
                     warning);
use Source::Symbols qw(PREPROCESSOR
                       METHOD_FWD
                       OPERATOR_FWD
                       METHOD
                       INCLUDE
                       DEFINE);
use BDE::Rule::Codes qw(NO_METHOD_TEST
                        NO_T_CPP
                        ILL_TST_DEP);
use Context::Message::Codes qw(EMP_FILE);
use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::T1 - verifies test drivers

=head1 SYNOPSIS

my $rule = new BDE::Rule::T1

my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

This rule carries out the following checks:

=over

=item *

T1a: all public methods are invoked within test driver

=item *

T1b: Dependencies of test driver cannot exceed that of component

=back

See C<bde_rule.pl T1> for more information.

=head1 TEST DRIVERS

Test drivers are supplied by this module.  To invoke, enter:

=over

=item *

perl -w -MBDE::Rule::L1 -e "BDE::Rule::T1->testT1a"

=item *

perl -w -MBDE::Rule::L1 -e "BDE::Rule::T1->testT1b"

=back

=cut

#==============================================================================

=head1 METHODS

=cut

=head2 verifyT1a($component)

=cut

sub verifyT1a($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule T1a...");

    my $rc = 0;

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "T1a");

    # tst might be empty
    my $tstFile = $component->getTstFile;
    my $tst = $tstFile->getSlimSource;
    $ctx->addError(fileName => $tstFile->getName,
                   code     => &EMP_FILE), return 0 if $tstFile->isEmpty;

    # get intf methods
    my $intfFile = $component->getIntfFile;
    $ctx->addError(fileName => $intfFile->getName,
                   code     => &EMP_FILE), return 1 if $intfFile->isEmpty;
    my $iter = new Source::Iterator::CPlusMode($intfFile->getSlimSource);
    my %methods;
    my %defines;
    my $public;
    my $currentClass;

    while (defined(my $line = $iter->next)) {

        # only want public methods
        $public = 1 if $line =~ /\bpublic\s*:/o;
        $public = 0 if $line =~ /\bprivate\s*:/o;
        if ($public and $iter->inClassOrStruct and 
            ($iter->isStatementType(METHOD_FWD) or 
             $iter->isStatementType(OPERATOR_FWD))) {
            $line =~ /\b(\S+)\s*\(/;
            $methods{$1}++;
        }
    }

    for my $method (sort keys %methods) {
        if ($$tst !~ /\b\Q$method\E\s*\(/) {
            $ctx->addWarning(fileName => $tstFile->getName,
                             code     => NO_METHOD_TEST,
                             text     => $method);
            $rc = 0;
        }
    }
    return $rc;
}

#------------------------------------------------------------------------------

=head2 verifyT1b($component)

=cut

sub verifyT1b($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule T1b...");

    my $rc = 0;

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "T1b");

    # tst might be empty
    my $tstFile = $component->getTstFile;
    my $tst = $tstFile->getSlimSource;
    $ctx->addError(fileName => $tstFile->getName,
                   code => &EMP_FILE), return 0 if $tstFile->isEmpty;

    # get deps
    my %okDeps;
    foreach my $file ($component->getIntfFile, $component->getImplFile) {
	$ctx->addError(fileName => $file->getName,
                       code => &EMP_FILE), return 1 if $file->isEmpty;
        my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);

        while (defined(my $line = $iter->next)) {
            if ($iter->isStatementType(INCLUDE)) {
                $line =~ /#\s*include\s+["<]\s*(.*)\s*[">]/;
                my $comp = $1;
                $comp =~ s/\.h$//;
                next if !isComponent($comp);
                $okDeps{$comp}++
            }
        }
    }

    my $iter = new Source::Iterator::CPlusMode($tst);
    $ctx->setDefault(fileName => $tstFile->getName,
                     displayFrom => $tstFile->getFullSource,
                     lineNumber  => $iter);

    while (defined(my $line = $iter->next)) {
        if ($iter->isStatementType(INCLUDE)) {
            $line =~ /#\s*include\s+["<]\s*(.*)\s*[">]/;
            my $comp = $1;
            $comp =~ s/\.h$//;
            next if !isComponent($comp);
            next if getComponentPackage($comp) ne getComponentPackage($component);
            if ($comp ne $component and !$okDeps{$comp}) {
                $ctx->addError(code => ILL_TST_DEP);
                $rc = 1;
            }
        }
    }
    return $rc;
}

#------------------------------------------------------------------------------

sub verify ($$) {
    my ($self, $component)=@_;
    my $result = $self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;
    if ($component->{testPath}) {
        $component->readTestDriver($component->{testPath});
    }
    else {
        $self->getContext->addWarning(fileName => "",
                                     text     => $component,
                                     code     => &NO_T_CPP);
        return $self->setResult(0);
    }

      return $self->setResult(0) if
        $component eq "bdes_chararray" ||
        $component eq "bdes_bitutil";

    $result =
      $self->verifyT1a($component) +
      $self->verifyT1b($component);

    return $self->setResult($result);
}

#==============================================================================

sub testT1a() {

my $comp = "bdes_types";

my $C1 = <<EOF;
class A {
  public:
    void M1();
  private:
    void M2();
  public:
    void M3();
};
EOF

my $T1 = <<EOF;
M1();
M3();
EOF
my @DATA = (

#            <------------------ INPUT ------------------> <------- OUTPUT ------>
#
#    line           intf                     tst               error code      rc
#=========== ====================== ====================== ================== ====

# --- D0 ---
{a=>__LINE__,b=>           "int i;",c=>                 "",d=>       NO_T_CPP,e=>0 },

{a=>__LINE__,b=>              "$C1",c=>           "int i;",d=> NO_METHOD_TEST,e=>1 },
{a=>__LINE__,b=>              "$C1",c=>              "$T1",                   e=>0 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $intfIn  = ${$entry}{b};
    my $tstIn   = ${$entry}{c};
    my $errCode = ${$entry}{d};
    my $rc      = ${$entry}{e};

    my($tmpnam1, $fh1);
    $tmpnam1 = POSIX::tmpnam();
    $fh1 = IO::File->new($tmpnam1, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh1 "$intfIn\n";
    close $fh1;

    my($tmpnam2, $fh2);
    $tmpnam2 = POSIX::tmpnam();
    $fh2 = IO::File->new($tmpnam2, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh2 "$tstIn\n";
    close $fh2;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam1);
    $compObj->readTestDriver($tmpnam2);
    my $rule = new BDE::Rule::T1;
    my $realRC = $rule->verifyT1a($compObj);
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
  }

}


#==============================================================================

sub testT1b() {

my $comp = "bdes_types";

my $H1 = "#include <bdema_xxx.h>\n";
my $H2 = "#include <bdema_yyy.h>\n";

my @DATA = (

#            <------------------ INPUT ------------------> <------- OUTPUT ------>
#
#    line           intf                     tst               error code      rc
#=========== ====================== ====================== ================== ====
{a=>__LINE__,b=>              "$H1",c=>           "$H1$H2",d=>    ILL_TST_DEP,e=>1 },

# --- D0 ---
{a=>__LINE__,b=>           "int i;",c=>                 "",d=>       NO_T_CPP,e=>0 },

{a=>__LINE__,b=>              "$H1",c=>              "$H1",                   e=>0 },
{a=>__LINE__,b=>              "$H1",c=>           "$H1$H2",d=>    ILL_TST_DEP,e=>1 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $intfIn  = ${$entry}{b};
    my $tstIn   = ${$entry}{c};
    my $errCode = ${$entry}{d};
    my $rc      = ${$entry}{e};

    my($tmpnam1, $fh1);
    $tmpnam1 = POSIX::tmpnam();
    $fh1 = IO::File->new($tmpnam1, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh1 "$intfIn\n";
    close $fh1;

    my($tmpnam2, $fh2);
    $tmpnam2 = POSIX::tmpnam();
    $fh2 = IO::File->new($tmpnam2, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh2 "$tstIn\n";
    close $fh2;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam1);
    $compObj->readImplementation($tmpnam1);
    $compObj->readTestDriver($tmpnam2);
    my $rule = new BDE::Rule::T1;
    my $realRC = $rule->verifyT1b($compObj);
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
Test driver validation
----------------------

a. If test driver is non-empty then it should test all methods.  Currently this
   only issues warnings.

   [cross reference: rule 28]

b. The dependencies of the test driver cannot exceed those of the component 
   under test.

   [cross reference: rule 29]

