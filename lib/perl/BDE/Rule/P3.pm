package BDE::Rule::P3;
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

=head1 NAME - checks for valid #include dependencies

BDE::Rule::P3

=head1 SYNOPSIS

my $rule = new BDE::Rule::P3;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

Verifies dependencies via isValidDependency.

See C<bde_rule.pl P3> for more information.

=cut

#==============================================================================

=head2 verifyP3($component, $fileSystem)

=cut

sub verifyP3($$$$) {
    my $self = shift;
    my $component = shift;
    my $fs = shift;
    my $noMeta = shift;

    my $rc = 0;

    my $ctx = $self->getContext();
    $ctx->setDefault(rule => "P3");

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

    $result = $self->verifyP3($component, $fs, $noMeta);

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

Dependencies of libraries (package groups) are restricted as follows:

  a.  Core libraries may never depend upon anything other than other core 
      libraries (all BDE libraries fall into this category). They may be 
      depended upon by C++ code but never by C code, except via a wrapper.

  b.  Department libraries may depend directly on adapters, legacy C libraries,
      and 3rd party libraries. They may be depended upon only by applications,
      biglets, and other department libraries managed under the same business
      unit. To become generally reusable a departmental library must evolve
      into a core library and one or more adaptors, if necessary. (R&D
      Infrastructure libraries are a single exception to this restriction.)

  c.  Enterprise libraries may depend upon core libraries and an approved 
      subset of 3rd party libraries only (to be defined).  They may be 
      depended upon by all C++ software classes except core libraries.

