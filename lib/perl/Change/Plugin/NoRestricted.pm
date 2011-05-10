package Change::Plugin::NoRestricted;
use strict;

use base 'Change::Plugin::Base';

use Util::File::Basename qw(basename);
use Util::Message qw(message warning);
use Change::AccessControl qw(isRestrictedFile);

#==============================================================================

=head1 NAME

Change::Plugin::NoRestricted - Remove restricted files from change set

=head1 SYNOPSIS

Remove retricted files that invoker does not have permission to check in:

    $ cscheckin -LNoRestricted ...

Filter a streamed change set with restricted files removed.

    $ cscheckin -lM --from original.cs -LNoRestricted > filtered.cs

Use after the FindInc plugin to also remove restricted found includees:

    $ cscheckin -LFindInc -LNoRestricted <files>

=head1 DESCRIPTION

The C<NoRestricted> plugin allows L<cscheckin> to automatically filter out
restricted files that the invoking user does not have permission to check in.

A common use of this plugin is to remove restricted files added automatically
through another plugin, such as the L<FindInc> plugin.

=head2 Note on Ordering

The C<NoRestricted> plugin filters files in the change set at the time it
is invoked. Therefore it will I<not> filter files found by plugins loaded
after it:

    $ cscheckin -LFindInc -LNoRestricted <files>

Is different from:

    $ cscheckin -LNoRestricted -LFindInc <files>

In the latter case, the C<NoRestricted> plugin will filter out restricted
files originally supplied by C<E<lt>filesE<gt>>, but will not affect any of
the files then added subsequently by the L<FindInc> plugin.

=cut

#------------------------------------------------------------------------------

sub plugin_post_find_filter ($$) {
    my ($plugin,$changeset)=@_;
    my @changeSetFiles = $changeset->getFiles;

    for my $file (@changeSetFiles) {
	if (isRestrictedFile($file)) {
   	    my $target=$file->getTarget();
            $changeset->removeFile($file);
	    my $leaf=basename($file->getSource());
	    warning "removed restricted file $leaf ($target) from change set";
	}
    }

    return 1;
}

#==============================================================================

1;

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Plugin::Example>, L<cscheckin>

=cut
