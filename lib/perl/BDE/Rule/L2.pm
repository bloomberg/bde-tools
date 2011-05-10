package BDE::Rule::L2;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;
use Source::Iterator::CPlusMode;
use Source::Util::ParseTools qw(getParamUserTypes
                                normalizeScopedName);
use BDE::Util::Nomenclature qw(isSubordinateComponent
                               isComponentHeader
                               isAdapter);
use Util::Message qw(debug
                     alert);
use Source::Symbols qw(EXTERN
                       CLASS
                       UNION
                       ENUM
                       METHOD
                       FUNCTION
                       OPERATOR
                       FRIEND
                       USING);
use BDE::Rule::Codes qw(ILL_EXTERN
                        ILL_FRIEND_TYPE
                        ILL_FRIEND_ARGS
                        ILL_USING
                        ILL_USING_WARN);
use Context::Message::Codes qw(EMP_FILE);
use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::L2 - Validation of dependency constructs

=head1 SYNOPSIS

my $rule = new BDE::Rule::L2;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

This rule carries out the following checks:

* L2a: Dependencies are satisfied by #include directives, not by externs

* L2b: No inter-component friendship

* L2c: No 'using' directives at file or namespace scope

See C<bde_rule.pl L2> for more information.

=head1 TEST DRIVERS

Test drivers are supplied by this module.  To invoke, enter:

perl -w -MBDE::Rule::L2 -e "BDE::Rule::L2->testL2a"

perl -w -MBDE::Rule::L2 -e "BDE::Rule::L2->testL2b"

perl -w -MBDE::Rule::L2 -e "BDE::Rule::L2->testL2c"

=cut

#==============================================================================

=head2 verifyL2a($component)

=cut

sub verifyL2a($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule L2a...");

    my $rc = 0;

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "L2");

    foreach my $file ($component->getIntfFile, $component->getImplFile) {

	$ctx->setDefault(fileName => $file->getName);
	$ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

	my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
	$ctx->setDefault(displayFrom => $file->getFullSource);

	while (defined(my $line = $iter->next)) {

            # extern returned by one iteration, and comment the next
            if ($iter->isStatementType(EXTERN)) {
                my $saveLineNum = $iter->lineNumber;
                $line = $iter->next;
                if (!defined($line) or 
                    # KEEP THIS REGEXP IN STEP WITH ParseTools::significantComment
                    $line !~ m-^\s*//\s*L2\s+EXCEPTED:\s*\w[\w\s]*$-mo) {
                    $ctx->addError(code       => &ILL_EXTERN,
                                   lineNumber => $saveLineNum);
                    $rc = 1;
                }
	    }
	}
    }
    return $rc;
}

#------------------------------------------------------------------------------

=head2 verifyL2b($component)

=cut

sub verifyL2b($$) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule L2b...");
    alert("L2b bypassed for subordinate component $component"), return 0 if
      isSubordinateComponent($component);

    my $ctx = $self->getContext;
    $ctx->setDefault(rule => "L2b");
    my $rc = 0;

    # read intf to get all user types
    my $file = $component->getIntfFile;
    $ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;
    my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
    while (defined($iter->next)) { }

    my @names = $iter->getNames(CLASS, UNION, ENUM);

    foreach my $file ($component->getIntfFile, $component->getImplFile) {
        $ctx->setDefault(fileName => $file->getName);
        $ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

        my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
        $ctx->setDefault(displayFrom => $file->getFullSource,
                         lineNumber  => $iter);

        while (defined(my $line = $iter->next)) {
            if ($iter->isStatementType(FRIEND)) {
                if ($line =~ /\bfriend\s+(?:class|struct|union|enum)\s+(\w+)/o) {
                    my $fullName = normalizeScopedName($iter->getNSScope, $1);
                    if (!grep /^$fullName$/, @names) {
                        $ctx->addError(code => &ILL_FRIEND_TYPE);
                        $rc = 1;
                    }
                }
                else {
                    $self->throw("regexp failure for $line") if $line !~ /\((.*)\)/so;
                    my @types = getParamUserTypes($1);
                    my $found = 0;
                    for my $type (@types) {
                        my $fullName = normalizeScopedName($iter->getNSScope, $type);
                        if (grep /^$fullName$/, @names) {
                           $found = 1;
                        }
                    }
                    if (!$found ){
                            $ctx->addError(code => &ILL_FRIEND_ARGS);
                            $rc = 1;
                    }
                }
            }
        }
    }
    return $rc;
}

#------------------------------------------------------------------------------

=head2 verifyL2c($component)

=cut

sub verifyL2c($) {
    my $self = shift;
    my $component = shift;

    debug("Invoking sub-rule L2c...");

    my $ctx = $self->getContext();
    $ctx->setDefault(rule => "L2");
    my $rc = 0;

    foreach my $file ($component->getIntfFile, $component->getImplFile) {

        last if isAdapter($component) and
          $file->getBaseName eq $component->getImplFile->getBaseName;

	$ctx->setDefault(fileName    => $file->getName);
        $ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

	my $iter = new Source::Iterator::CPlusMode($file->getSlimSource());
	$ctx->setDefault(displayFrom => $file->getFullSource(),
                         lineNumber  => $iter);

        while (defined(my $output = $iter->next)) {
            if ($iter->isStatementType(USING) and
                !$iter->inBlock(METHOD)       and
                !$iter->inBlock(FUNCTION)     and
                !$iter->inBlock(OPERATOR)) {

                # error in .h, warning in .cpp
                if ($file->getBaseName eq $component->getIntfFile->getBaseName) {
                    $ctx->addError(code => &ILL_USING);
                    $rc = 1;
                }
                else {
                    $ctx->addWarning(code => &ILL_USING_WARN);
                }

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

    $result = 
      $self->verifyL2a($component) +
      $self->verifyL2b($component) +
      $self->verifyL2c($component);

    return $self->setResult($result);
}

#==============================================================================

sub testL2a() {

my $comp = "bdes_types";

my $E1 = "extern foo;";
my $E2 = "extern \"C\";";
my $E3 = "extern foo; // L2 EXCEPTED: test";

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====

# --- D0 ---
{a=>__LINE__,b=>                               "",c=>          EMP_FILE,d=>1 },

{a=>__LINE__,b=>                            "$E1",c=>        ILL_EXTERN,d=>1 },
{a=>__LINE__,b=>                            "$E2",                      d=>0 },
{a=>__LINE__,b=>                            "$E3",                      d=>0 },
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
    my $rule = new BDE::Rule::L2;
    ASSERT(__LINE__ . ".$line", $rule->verifyL2a($compObj), $rc);
    ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) if $errCode;
    unlink($tmpnam);
  }

}

#------------------------------------------------------------------------------

sub testL2b() {

my $comp = "bdes_types";

my $C1   = "class a{};";
my $C2   = "class b";
my $Ob   = "{";
my $Cb   = "}";
my $S    = ";";
my $F1   = "friend class a;";
my $F2   = "friend int operator++(const a);";
my $F3   = "friend int operator++(a);";
my $F4   = "friend class c;";
my $F5   = "friend int operator++(const c);";
my $F6   = "friend int operator++(c);";

my @DATA = (

#            <-------------- INPUT -------------> <------- OUTPUT ------->
#
#    line                    input                      error code        rc
#=========== ==================================== ===================== ====
{a=>__LINE__,b=>              "$C1$C2$Ob$F1$Cb$S",                      d=>0 },

# --- D0 ---
{a=>__LINE__,b=>                               "",c=>          EMP_FILE,d=>1 },

{a=>__LINE__,b=>              "$C1$C2$Ob$F1$Cb$S",                      d=>0 },
{a=>__LINE__,b=>              "$C1$C2$Ob$F2$Cb$S",                      d=>0 },
{a=>__LINE__,b=>              "$C1$C2$Ob$F3$Cb$S",                      d=>0 },
{a=>__LINE__,b=>              "$C1$C2$Ob$F4$Cb$S",c=>   ILL_FRIEND_TYPE,d=>1 },
{a=>__LINE__,b=>              "$C1$C2$Ob$F5$Cb$S",c=>   ILL_FRIEND_ARGS,d=>1 },
{a=>__LINE__,b=>              "$C1$C2$Ob$F6$Cb$S",c=>   ILL_FRIEND_ARGS,d=>1 },
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $errCode = ${$entry}{c};
    my $rc      = ${$entry}{d};

    my($tmpnam1, $tmpnam2, $fh1, $fh2);
    $tmpnam1 = POSIX::tmpnam();
    $fh1 = IO::File->new($tmpnam1, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh1 "$input\n";
    close $fh1;

    $tmpnam2 = POSIX::tmpnam();
    $fh2 = IO::File->new($tmpnam2, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh2 "#define 1\n";
    close $fh2;

    my $compObj = new BDE::Component($comp);
    my $rule = new BDE::Rule::L2;
    $compObj->readInterface($tmpnam1);
    $compObj->readImplementation($tmpnam2);
    print "LINE: $line INPUT: $input\n" if $ENV{BDE_TRACE};
    ASSERT(__LINE__ . ".$line", $rule->verifyL2b($compObj), $rc);
    ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) if $errCode;
    unlink($tmpnam1);
    unlink($tmpnam2);
  }

}

#------------------------------------------------------------------------------

sub testL2c() {

my $comp = "bdes_types";
my $N  = "namespace BloombergLP {";
my $Cb = "}";
my $U  = "using ttt;";
my $F  = "void t() {";

my @DATA = (

#            <------------------- INPUT ------------------->    <------ OUTPUT ------>
#
#    line                         input                                error code   rc
#=========== =============================================== ==================== ====
# --- D0 ---

{a=>__LINE__,b=>                                         "", c=>        EMP_FILE,d=>1},

# --- D1 ---

{a=>__LINE__,b=>                             "$N$F$U$Cb$Cb",                      d=>0},
{a=>__LINE__,b=>                                  "$N$U$Cb", c=>       ILL_USING, d=>1},
);

require IO::File;
require POSIX;

for my $entry (@DATA) {
    my $line    = ${$entry}{a};
    my $input   = ${$entry}{b};
    my $errCode = ${$entry}{c};
    my $rc      = ${$entry}{d};

    my($tmpnam1, $tmpnam2, $fh1, $fh2);
    $tmpnam1 = POSIX::tmpnam();
    $fh1 = IO::File->new($tmpnam1, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh1 "$input\n";
    close $fh1;

    $tmpnam2 = POSIX::tmpnam();
    $fh2 = IO::File->new($tmpnam2, IO::File::O_RDWR|IO::File::O_CREAT|IO::File::O_EXCL);
    print $fh2 "#define 1\n";
    close $fh2;

    my $compObj = new BDE::Component($comp);
    $compObj->readInterface($tmpnam1);
    $compObj->readImplementation($tmpnam2);
    my $rule = new BDE::Rule::L2();
    ASSERT(__LINE__ . ".$line", $rule->verifyL2c($compObj), $rc);
    if ($errCode) {
        $rule->getContext->getMessage(0) and
          ASSERT(__LINE__ . ".$line", $rule->getContext->getMessage(0)->{code}, $errCode) or
            ASSERT(__LINE__ . ".$line", 0, $errCode);
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
Verification of component dependencies
--------------------------------------

a. All dependencies are satisfied by #include directives, not by local
   declarations, i.e., no extern declarations.  The check can be circumvented
   only by appending the comment:

    ... // L2 EXCEPTED: <reason>

   [cross reference: rule 12]

b. No inter-component friendship.

   [cross reference: rule 19]

c. 'using' directives/declarations should be limited to function scope.  In
   interface files they are not allowed at file or namespace scope. In
   implementation files they are allowed although a warning is issued (an
   exception to this is adapter implementation files, when no warning is 
   issued.

   [cross references: rules 16,6]

