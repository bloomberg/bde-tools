package BDE::Rule::L5;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;

use BDE::Util::Nomenclature qw(isFunctionEntry);
use Context::Message::Codes qw(EMP_FILE);
use BDE::Rule::Codes qw(NO_GLUE);

use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::L5 - Validates that interface file has biglet entry point.

=head1 SYNOPSIS

my $rule = new BDE::Rule::L5;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

Validates that the appropriate interface file (as determined by 
Nomenclature::isFunctionEntry) has biglet entry point declaration.

See C<bde_rule.pl L5> for more information.


=cut

#==============================================================================

sub verifyL5($) {
    my $self = shift;
    my $component = shift;

    my $ctx = $self->getContext();
    my $intf = $component->getIntfFile();
    $ctx->addError(code => &EMP_FILE), return 1 if $intf->isEmpty();

    $ctx->setDefault(fileName => $intf->getName());
    my $RE = qr/int\s+$component\s*\(\)/o;
    $ctx->addError(code => &NO_GLUE), return 1 if
      ${$intf->getSlimSource()} !~ /$RE/;

    return 0;
}

#------------------------------------------------------------------------------

sub verify($$) {
    my ($self,$component)=@_;

    # return immediately if we're not in a function entry component
    return $self->setResult(0) if !isFunctionEntry($component);

    my $result=$self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    $result = $self->verifyL5($component);
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
Verification of biglet entry point
----------------------------------

Biglet entry point components must provide a single entry point with
external C linkage.
