package Change::Plugin::Example;
use strict;

use base 'Change::Plugin::Base';

use Util::Message qw(message);

#==============================================================================

=head1 NAME

Change::Plugin::Example - Example plugin module for cscheckin

=head1 SYNOPSIS

    $ cscheckin --plugin Example ....

=head1 DESCRIPTION

This is an example plugin module for L<cscheckin>. It inherits from
L<Change::Plugin::Base> and implements the full plugin interface to issue a
simple message for each interface. See L<Change::Plugin::Base> for information
on how to write a plugin, including what interfaces are available,
the arguments supplied to each interface routine, and their expected return
values.

=cut

#==============================================================================

sub _plugin_message { message __PACKAGE__." -> @_" };

#------------------------------------------------------------------------------

sub plugin_usage ($) {
    return "  --example          <string>   an example plugin option";
}

sub plugin_options ($) {
    return qw[example=s];
}

sub plugin_initialize ($$) {
    my ($plugin,$opts)=@_;
    _plugin_message "[initialize] example option was '".$opts->{example}."'";
}

sub plugin_pre_find_filter ($$) {
    my ($plugin,$changeset)=@_;

    _plugin_message "[pre_find_filter $changeset]";
}

sub plugin_post_find_filter ($$) {
    my ($plugin,$changeset)=@_;

    _plugin_message "[post_find_filter $changeset]";
}

sub plugin_early_interaction ($$) {
    my ($plugin,$opts,$interact)=@_;

    _plugin_message "[early_interaction]";
}

sub plugin_late_interaction ($$) {
    my ($plugin,$opts,$interact)=@_;

    _plugin_message "[late_interaction]";
}

sub plugin_pre_change ($$) {
    my ($plugin,$changeset)=@_;

    _plugin_message "[pre_change $changeset]";
}

sub plugin_pre_file ($$) {
    my ($plugin,$changeset,$changefile)=@_;

    _plugin_message "[pre_file $changeset:$changefile]";
}

sub plugin_post_file ($$) {
    my ($plugin,$changeset,$changefile)=@_;

    _plugin_message "[post_file $changeset:$changefile]";
}

sub plugin_post_change_success ($$) {
    my ($plugin,$changeset)=@_;

    _plugin_message "[post_change_success $changeset]";
}

sub plugin_post_change_failure ($$) {
    my ($plugin,$changeset)=@_;

    _plugin_message "[post_change_failure $changeset]";
}

sub plugin_finalize ($$$) {
    my ($plugin,$opts,$exit_code)=@_;

    _plugin_message "[finalize]";
}

#==============================================================================

1;

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>

=cut
