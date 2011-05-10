package BDE::Rule::X1;
use strict;

use base 'BDE::Rule::Base';

use BDE::Rule::Codes qw(LNG_COMPNAME);

use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::X1

=head1 SYNOPSIS


  my $rule = new BDE::Rule::X1;
  my $returnCode = $rule->verify("bdes_platform");

=head1 DESCRIPTION

  Component name cannot be greater than ???

=cut

#==============================================================================

sub verify ($$) {
    my ($self, $component)=@_;
    my $result=$self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    my $ctx = $self->getContext();

    $ctx->addError(code => &LNG_COMPNAME), $result = 1 if
      length($component->toString()) > 30;

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
A component name must not exceed 30 characters in length.
