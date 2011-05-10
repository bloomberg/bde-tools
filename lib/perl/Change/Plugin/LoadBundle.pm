package Change::Plugin::LoadBundle;

use base qw/Change::Plugin::Base/;

use File::Temp qw/tempdir/;
use File::Spec;

use Util::Message qw/fatal debug/;
use Change::Util::Bundle  qw/unbundleChangeSet/;

my $pre = "LoadBundle plugin:";

sub plugin_usage {
    return "  --from    <bundle>    compile-test change set stored in <bundle>";
}

sub plugin_options {
}

sub plugin_initialize {
    my ($self, $opts) = @_;

    if (not $opts->{from}) {
        debug("$pre --from not provided. Returning.");
        return;
    }

    debug("$pre --from=$opts->{from}");

    my $tmp = tempdir(CLEANUP => !Util::Message::get_debug());
    debug("$pre unpacking bundle to $tmp");
    my $cs = Change::Set->new;
    unbundleChangeSet($cs, $opts->{from}, $tmp);

    debug("$pre rewriting source paths in change set to point to $tmp/root");
    for my $file ($cs->getFiles) {
	(my $dest = $file->getDestination) =~ s!^root/\d+/!root/!;
        my $newdest = File::Spec->catfile($tmp, $dest);
        debug($file->getSource . " => $newdest");
        $file->setSource($newdest);
    }
    
    my $path = File::Spec->catfile($tmp, $cs->getID);
    debug("$pre serializing altered change set to $path");

    open my $fh, '>', $path
        or fatal "Could not open $path for writing: $!";
    print $fh $cs->serialise;
    close $fh 
        or fatal "Could not close $path: $!";

    debug("$pre Setting --from to $path");
    $opts->{from} = $path;
}

1;

=head1 NAME

Change::Plugin::Bundle - Allow cscompile to compile change set bundles

=head1 SYNOPSIS

    $ cscompile -LLoadBundle --from /path/to/bundle

=head1 DESCRIPTION

The purpose of this plugin is to trigger pessimistic compile tests from 
the SCM machines: copy the respective bundle to a build machine and then
invoke (via ssh) cscompile on that bundle.

This plugin will take care of adjusting the paths in the change set 
contained in the bundle to point to some temporary directory in which
the bundle is unpacked.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
