package Change::Plugin::Base;
use strict;

use base 'BDE::Object';

use overload '""' => "toString", fallback => 1;

use Change::Symbols qw(DBPATH DBLOCKFILE);
use Change::DB;
use Util::File::NFSLock ();
use Util::File::Functions qw(ensure_path);
use Util::File::Basename qw(dirname);

#==============================================================================

=head1 NAME

Change::Plugin::Base - Base class for cscheckin plugins

=head1 SYNOPSIS

    package Change::Plugin::MyPlugin;
    use strict;
    use base 'Change::Plugin::Base'

    sub usage {
        my $usage=" --mypluginoption              an option for this plugin\n";
	...
	return $usage;
    }

    sub initialise {
	my ($plugin,$opts)=@_;

	my $option=$opts->{mypluginoption};
	...
    }

    sub pre_find_filter {
        my ($plugin,$changeset)=@_;
        ...
    }

    ...

    1;

=head1 DESCRIPTION

This is the base class for L<cscheckin> plugin modules. It provides a null
(i.e. no effect) implementation for each supported plugin method so that
derived plugin modules need only implement the methods they need.

The following plugin methods are supported, listed in order of invokation.
All methods return 1 on success or 0 on failure, with the exception of
C<plugin_usage>, which returns an information string that is appended to the
usage, and C<plugin_options>, which return a list of options specifications.

    [lnc] plugin_ismanual()

    [lnc] plugin_usage()

    [lnc] plugin_options()

    [lnc] plugin_initialize($opts)

    [lnc] plugin_pre_find_filter($changeset)

    [lnc] plugin_post_find_filter($changeset)

    [..c] plugin_early_interaction($opts,$interact)

    [..c] plugin_late_interaction($opts,$interact)

    [..c] plugin_pre_change($changeset)

    [..c] plugin_post_change_success($changeset)

    [..c] plugin_post_change_failure($changeset)

    [..c] plugin_finalize($opts,$exit_code)

(Key: executes on l=list n=test c=commit)

=head2 NOTES

All plugin methods are prefixed with C<plugin_>. Avoid this prefix for any
methods that are internal to the plugin.

B<plugin_ismanual>

The C<plugin_ismanual> method takes no arguments and returns a boolean value
indicating whether or not the plugin may be manually loaded (i.e. with the
C<--plugin> option of L<cscheckin>). In the base class it returns true.

Automatic plugins, which are loaded in response to events outside of user
control (such as approval processes), should overload this method and
return false.

B<plugin_initialize>

The C<plugin_initialize> method receives the hash reference of options
processed by C<cscheckin>. The only options that should usually be accessed
from this hash reference are options supplied by the plugin itself. Other
options may be accessed, but note that the contents of this hash reference
are not formally documented and may change -- be aware that reading or writing
this hash may break in future implementations, until a formal interface is
defined. However, the intent of this method is to allow plugins to fill in
or modify values passed into the tool, so contact the developers if you want
to make use of it, so we are aware of your intents.

B<plugin_early_interaction> and B<plugin_late_interaction>

The C<plugin_early_interaction> and C<plugin_late_interaction> methods are
used to manage additional information that must be supplied on the command
line or otherwise prompted for. They differ in that the early method is called
before any other prompts supplied by the tool itself, while the late method
is called at the end of the information gathering segment.

Both methods receive the options hash reference and a terminal interaction
object (an instance of L<Term::Interact>) with which to issue prompts.

I<Note: Currently, the only generic plugin-fillable data value available is the
reference, i.e. C<$opts->{reference}>. A more flexible mechanism will likely
be implemented when future demands dictate it. Plugins can of course use
alternate sources of information to fill in other options like C<--isbf>.)

B<plugin_pre_find_filter> and B<plugin_post_find_filter>

The C<plugin_pre_find_filter> and C<plugin_post_find_filter> methods are
permitted to alter the change set object passed to them as part of their
function. All other methods should treat their arguments as read-only and
I<not> alter the change set (or change file, where applicable) passed to them.

The distinction between C<plugin_pre_find_filter> and
C<plugin_post_find_filter> is that C<plugin_pre_find_filter> is called prior
to the identification of each file in the candidate set and the determination
of its status (new, changed, or unchanged). C<plugin_post_find_filter> is
called after this determination, and in particular will not see unchanged
files if the C<--unchanged> or C<-U> option was passed to C<cscheckin>.

B<plugin_finalize>

The C<plugin_finalize> method is called as the penultimate act of main
processing, between the commit attempt and exit.  It receives the same hash
reference of options processed by C<cscheckin> as does C<plugin_initialize>.
The same caveats apply to use of the options.  It takes as a second argument
the prospective exit code for the run.

=cut

#==============================================================================

=head1 UTILITY METHODS

=cut

# private method -- open a database connection. Used only by logEvent
sub _openDB ($) {
    my $path=shift;

    ensure_path(dirname $path);
    my $changedb=new Change::DB($path);
    error("Unable to access $path: $!"), return 0
      unless defined $changedb;

    return $changedb;
}

=head2 logEvent ($csid,$eventmsg)

Log an event to the development database transaction log. See
L<Change::DB/logEvent> for more information. Typically these messages are used
to note events that have taken place elsewhere (such as production). As such,
this is purely a development-side database mechanism.

=cut

{ my $changedb;

  sub logEvent ($$$) {
      my ($self,$csid,$eventmsg)=@_;

      my $unlock_token = Util::File::NFSLock::safe_nfs_lock(DBLOCKFILE);
      my $changedb=_openDB(DBPATH) unless $changedb;
      my $changeset=$changedb->logEvent($csid,$eventmsg);
      Util::File::NFSLock::safe_nfs_unlock($unlock_token);
  }
}

#==============================================================================
=head1 ACCESSORS/MUTATORS

=head2 getToolId($name)

Get the toolname for the plugin. It is set by manager and
accessed by the plugin modules which allow plugins to modify
their per-tool behavior.

=cut

sub getToolId($) {
    my ($self)=@_;

    return  $self->{toolname};
}

=head2 setToolId($name)

Set the toolname for the plugin. It is set by manager and
accessed by the plugin modules which allow plugins to modify
their per-tool behavior.

=cut

sub setToolId($$) {
    my ($self,$name)=@_;

    $self->{toolname}=$name;
}

sub plugin_ismanual ($) {
    return 1;
}

sub getSupportedTools($) {
    my ($plugin)=@_;
    my @tools = ();
    return @tools;
}

sub plugin_usage ($$) {
    my ($plugin,$opts)=@_;

    return "  (no options supplied by this plugin)";
}

sub plugin_options ($$) {
    my ($plugin,$opts)=@_;
    return ();
}

sub plugin_initialize ($$) {
    my ($plugin,$opts)=@_;
    return 1;
}

sub plugin_early_interaction ($$) {
    my ($plugin,$opts,$interact)=@_;
    return 1;
}

sub plugin_late_interaction ($$) {
    my ($plugin,$opts,$interact)=@_;
    return 1;
}

sub plugin_pre_find_filter ($$) {
    my ($plugin,$changeset)=@_;
    return 1;
}

sub plugin_post_find_filter ($$) {
    my ($plugin,$changeset)=@_;
    return 1;
}

sub plugin_pre_change ($$) {
    my ($plugin,$changeset)=@_;
    return 1;
}

#--DEPRECATED--
sub plugin_pre_file ($$$) {
    my ($plugin,$changeset,$changefile)=@_;
    return 1;
}

#--DEPRECATED--
sub plugin_post_file ($$$) {
    my ($plugin,$changeset,$changefile)=@_;
    return 1;
}

sub plugin_post_change_success ($$) {
    my ($plugin,$changeset)=@_;
    return 1;
}

sub plugin_post_change_failure ($$) {
    my ($plugin,$changeset)=@_;
    return 1;
}

sub plugin_finalize ($$$) {
    my ($plugin,$opts,$exit_code)=@_;
    return 1;
}

#------------------------------------------------------------------------------

sub toString ($$) {
    return $_[0]->{name} if $_[0]->{name};

    my $name=ref($_[0]) || $_[0];
    $name=~s/^.*\:\:([^:]+)$/$1/;
    $_[0]->{name}=$name;
    return $name;
}

sub name { return $_[0]->toString() }

#==============================================================================

1;

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Change::Set>, L<Change::File>

=cut
