package BDE::Rule::P4;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;
use Source::Iterator::CPlusMode;
use BDE::Util::Nomenclature qw(isValidDependency);
use BDE::Util::RuntimeFlags qw(getNoMetaMode);
use Util::Message qw(verbose2);
use Source::Symbols qw(INCLUDE);
use Context::Message::Codes qw(EMP_FILE);
use BDE::Rule::Codes qw(ILL_INCLUDE
                        ILL_DPT_INCLUDE);
use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::P4

=head1 SYNOPSIS

my $rule = new BDE::Rule::P4;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

Verifies dependencies via isValidDependency.

See C<bde_rule.pl P4> for more information.


=cut

#==============================================================================

=head2 verifyP4($component, $fileSystem)

=cut

sub verifyP4($$$$) {
    my $self = shift;
    my $component = shift;
    my $fs = shift;
    my $noMeta = shift;

    my $rc = 0;

    my $ctx = $self->getContext();
    $ctx->setDefault(rule => "P4");

    for my $file ($component->getIntfFile, $component->getImplFile) {

	$ctx->setDefault(fileName => $file->getName);
	$ctx->addError(code => &EMP_FILE), return 1 if $file->isEmpty;

	my $iter = new Source::Iterator::CPlusMode($file->getSlimSource);
	$ctx->setDefault(displayFrom => $file->getFullSource,
                         lineNumber  => $iter);

        while (defined(my $line = $iter->next)) {
            next if !$iter->isStatementType(INCLUDE);
            $line =~ m-^\s*#\s*include\s+[<"]([\w\./]+)[>"]-;
            my $depComp = $1;
            my $ivd = isValidDependency($component, $depComp);
            if (!$ivd) {
                $ctx->addError(code => &ILL_INCLUDE);
                $rc = 1;
            }
            elsif ($ivd == 2 and !getNoMetaMode()) {
                if ($fs->getDepartment($component) ne $fs->getDepartment($depComp)) {
                    $ctx->addError(code => &ILL_DPT_INCLUDE);
                    $rc = 1;
                }
            }
        }
    }

    return $rc;
}

#------------------------------------------------------------------------------

sub verify ($$$$) {
    my ($self,$component,$fs,$noMeta) = @_;
    my $result = $self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    $result = $self->verifyP4($component, $fs, $noMeta);

    return $self->setResult($result);
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
Validation of include dependencies
----------------------------------

Dependencies of applications, adapters, wrappers, and biglets are restricted 
as follows:

  a. Applications may depend directly upon 3rd party libraries, but if 
     possible should use an adapter. Applications may not be depended upon. 
     Shared components must be placed into a package inside an appropriate 
     package group (initially this will most probably be a departmental 
     library).

  b. Adapters may depend upon 3rd party libraries and existing legacy C 
     libraries. Applications, biglets and department libraries may depend 
     upon adapters for functionality.

  c. C API wrappers may depend only upon the C++ package group that they 
     wrap. C code may depend on the wrapper but never on the C++ library 
     being wrapped.

  d. Biglets may depend upon C++ libraries and adapters. They may not be 
     depended upon except by the BIG router. In addition, the only logical 
     names the BIG router may depend upon are entry points with external C 
     linkage named after the component that implements them. (N5).

