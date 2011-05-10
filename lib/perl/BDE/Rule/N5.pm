package BDE::Rule::N5;
use strict;

use base 'BDE::Rule::Base';

use BDE::Component;

use BDE::Util::DependencyCache qw(getCachedPackage);
use BDE::Util::RuntimeFlags qw(getNoMetaMode);
use BDE::Util::Nomenclature qw(getComponentPackage isFunction);
use Context::Message::Codes qw(EMP_FILE);
use BDE::Rule::Codes qw(NO_ENTRYF NO_ENTRY);

#==============================================================================

=head1 NAME

BDE::Rule::N5 - Check for biglet entry point files

=head1 SYNOPSIS

my $rule = new BDE::Rule::N5;
my $returnCode = $rule->verify($component);

=head1 DESCRIPTION

Checks for biglet entry point files.  In no-meta mode the unix filesystem is
queried directly.

See C<bde_rule.pl N5> for more information.

=cut

#==============================================================================

sub verify($$) {
    my ($self,$component)=@_;

    # return immediately if we're not in a function entry component
    return $self->setResult(0) if !isFunction($component);

    my $result = $self->SUPER::verify($component); #generic rule checks
    return $result unless defined($result) and not $result;

    my $ctx = $self->getContext();
    my $entry = getComponentPackage($component) . "_entry";
    $result = 0;

    if (getNoMetaMode()) {
        for my $f (("$entry.h", "$entry.cpp")) {
            if (! -r $f) {
                $ctx->addError(code => &NO_ENTRYF, fileName => $f);
                $result = 1;
            }
        }
    }

    else {
        if (!grep /\b$entry\b/,
            getCachedPackage($component->getPackage())->getMembers) {
            $ctx->addError(code => &NO_ENTRY, fileName => undef);
            $result = 1;
        }
    }

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
Biglet entry point component must exist
---------------------------------------

The default entry point to the biglet must be defined in a component with the
name f_{key}{mnemonic}_entry.
