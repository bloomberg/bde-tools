package BDE::Rule::X2;
use strict;

use base 'BDE::Rule::Base';
use BDE::Component;
use Source::Iterator;

use Context::Message::Codes qw(EMP_FILE);
use BDE::Rule::Codes qw(LNG_LINE NO_TABS);

use Util::Test qw(ASSERT);

#==============================================================================

=head1 NAME

BDE::Rule::X2

=head1 SYNOPSIS

  my $rule = new BDE::Rule::X2;
  my $returnCode = $rule->verify("bdes_platform");

=head1 DESCRIPTION

  Verify that:
     - lines cannot be > 80 characters long
     - lines cannot contain tabs

=cut

#==============================================================================

=head2 verify($component, $extension)

=cut

sub verifyX2($$) {
    my $self = shift;
    my $component = shift;

    my $ctx = $self->getContext();
    my $rc = 0;

    for my $file ($component->getIntfFile, $component->getImplFile) {
	$ctx->setDefault(fileName    => $file->getName(),
			 displayFrom => $file->getFullSource());
	$ctx->addError(code => &EMP_FILE), next if $file->isEmpty();

        my $iter = new Source::Iterator(${$file->getFullSource()});
	$ctx->setDefault(lineNumber => $iter);  # will evaluate to int

        while (defined(my $line = $iter->next())) {
            $ctx->addError(code => &LNG_LINE) if length($line) > 79;
            if ($line =~ /\t/) {
                $line =~ s/\t/\\t/g;
                $ctx->addError(code => &NO_TABS, text=> $line);
            }
        }
    }
    return $rc;
}
#------------------------------------------------------------------------------

sub verify ($$) {
    my ($self, $component)=@_;
    my $result=$self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    $result = $self->verifyX2($component);

    return $self->setResult($result);
}

#==============================================================================

=head1 AUTHOR

...

=head1 SEE ALSO

...

=cut

#==============================================================================

1;

__DATA__
a. Lines cannot be longer than 80 characters in length.

b. Tabs are not allowed.
