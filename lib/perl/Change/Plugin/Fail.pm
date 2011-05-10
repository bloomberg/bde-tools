package Change::Plugin::Fail;
use strict;

use base 'Change::Plugin::Base';

use Util::Message qw(message verbose);

#==============================================================================

=head1 NAME

Change::Plugin::Fail - Fail plugin module for cscheckin

=head1 SYNOPSIS

    $ cscheckin --plugin Fail --fail hookname ....

=head1 DESCRIPTION

This is a testing plugin module for L<cscheckin>. It inherits from
L<Change::Plugin::Base> and implements the full plugin interface to issue a
simple message for each interface.  Using the --fail hookname option causes its
plugin_hookname call to return false signalling failure.  This serves primarily
to test cscheckin behavior under plugin failure conditions.

The argument to --fail does not include the "plugin_" prefix.  If you supply a
name that does not correspond to an actual hook, then the module dutifully
configures it to fail, but never encounters it.

=cut

#==============================================================================

sub _plugin_message { message __PACKAGE__." -> @_" };

#------------------------------------------------------------------------------

{ my %fail = ();
  sub _hook_return {
    if (exists $fail{$_[0]}) {
      verbose "failing plugin_$_[0]";
      return 0;
    } else {
      return 1;
    }
  }
  sub plugin_usage ($) {
      return "  --fail          <string>   fail the hook named in the argument";
  }

  sub plugin_options ($) {
      return qw[fail=s@];
  }

  sub plugin_initialize ($$) {
      my ($plugin,$opts)=@_;
      if (exists $opts->{fail}) {
	_plugin_message "[initialize] failing hooks: ".
			join(', ' => map("plugin_$_" => @{$opts->{fail}})).
			".";
	%fail = map(("$_" => undef) => @{$opts->{fail}});
      } else {
	_plugin_message "[initialize] passing all hooks."; 
      }
      return _hook_return('initialize');
  }

  sub plugin_pre_find_filter ($$) {
      my ($plugin,$changeset)=@_;

      _plugin_message "[pre_find_filter $changeset]";
      return _hook_return('pre_find_filter');
  }

  sub plugin_post_find_filter ($$) {
      my ($plugin,$changeset)=@_;

      _plugin_message "[post_find_filter $changeset]";
      return _hook_return('post_find_filter');
  }

  sub plugin_early_interaction ($$) {
      my ($plugin,$opts,$interact)=@_;

      _plugin_message "[early_interaction]";
      return _hook_return('early_interaction');
  }

  sub plugin_late_interaction ($$) {
      my ($plugin,$opts,$interact)=@_;

      _plugin_message "[late_interaction]";
      return _hook_return('late_interaction');
  }

  sub plugin_pre_change ($$) {
      my ($plugin,$changeset)=@_;

      _plugin_message "[pre_change $changeset]";
      return _hook_return('pre_change');
  }

  sub plugin_pre_file ($$) {
      my ($plugin,$changeset,$changefile)=@_;

      _plugin_message "[pre_file $changeset:$changefile]";
      return _hook_return('pre_file');
  }

  sub plugin_post_file ($$) {
      my ($plugin,$changeset,$changefile)=@_;

      _plugin_message "[post_file $changeset:$changefile]";
      return _hook_return('post_file');
  }

  sub plugin_post_change_success ($$) {
      my ($plugin,$changeset)=@_;

      _plugin_message "[post_change_success $changeset]";
      return _hook_return('post_change_success');
  }

  sub plugin_post_change_failure ($$) {
      my ($plugin,$changeset)=@_;

      _plugin_message "[post_change_failure $changeset]";
      return _hook_return('post_change_failure');
  }

  sub plugin_finalize ($$$) {
      my ($plugin,$opts,$exit_code)=@_;

      _plugin_message "[finalize]";
      return _hook_return('finalize');
  }
}

#==============================================================================

1;

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)
Peter Wainwright did not write this module.  He disavows any knowledge of or
responsibility for it.

=head1 SEE ALSO

L<Change::Plugin::Base>

=cut
