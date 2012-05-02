#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Component;
use BDE::FileSystem::MultiFinder;
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent
    getComponentGroup getComponentPackage getPackageGroup
);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
    FILESYSTEM_NO_DEFAULT FILESYSTEM_NO_SEARCH
    FILESYSTEM_NO_LOCAL FILESYSTEM_NO_ROOT FILESYSTEM_NO_PATH
);
use Util::Message qw(fatal);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

bde_find.pl - locate the root for a group, package, or component

=head1 SYNOPSIS

    # search all locations
    $ bde_find.pl bde            # package group
    $ bde_find.pl l_foo          # grouped package
    $ bde_find.pl a_bdema        # isolated package
    $ bde_find.pl bdet_datetime  # component

    # search selected locations
    $ bde_find.pl -l bde         # search locally only (no root or path)
    $ bde_find.pl -lr bde        # search locally and root (no path)
    $ bde_find.pl -rp bde        # search root and path (not locally)
    $ bde_find.pl -lrp bde       # search all locations

=head1 DESCRIPTION

C<bde_find.pl> searches the local filing system, the local root, and the
current path to determine the 'closest' instance of the specified package
group, package, or component, as determined by the shape of the universe
(as determined by the configuration of the C<BDE_ROOT> and C<BDE_PATH>
environment variables, and the current working directory).

Any of the three search areas (local, root, and path) may be enabled separately
with the C<-l>, C<-r>, and C<-p> options. Specifying no areas is equivalent to
specifying all of them.

The specified group, package, or component must physically exist to be found.
Declared membership in the containing group (for grouped packages) or package
(for components) is not sufficient. If a component search is not necessarily
expected to succeed, the C<-X> option may be useful to cause the tool to return
faster; without this option, retry semantics will repeatedly check for the
component files within the closest associated package, which will cause a
delay if the files do not in fact exist.

=cut

#==============================================================================

sub usage (;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-l][-p][-r] [-w <dir>] [-X] <group|package|component>
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --local      | -l           search local filesystem
  --path       | -p           search path
  --root       | -r           search local root
  --verbose    | -v           enable verbose reporting
  --where      | -w <dir>     specify explicit alternate root
  --noretry    | -X           disable retry semantics on file operations

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
        local|l
        noretry|X
	path|p
        root|r
	verbose|v
        where|w=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV != 1;

    # filesystem root
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

sub search_mode ($$$) {
    my $l = (shift) ? FILESYSTEM_NO_LOCAL : 0;
    my $r = (shift) ? FILESYSTEM_NO_ROOT  : 0;
    my $p = (shift) ? FILESYSTEM_NO_PATH  : 0;

    return 0 unless $l || $r || $p; # none=all
    return FILESYSTEM_NO_SEARCH ^ ($l | $r | $p);
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $root=new BDE::FileSystem::MultiFinder($opts->{where});

    my $mode=search_mode($opts->{local},$opts->{root},$opts->{path});
    $mode |= FILESYSTEM_NO_DEFAULT;
    $root->setSearchMode($mode);

    my $name=$ARGV[0];
    my $locn;
    if (isComponent $name) {
	$locn=eval { $root->getComponentBasepath($name) };
	$locn=undef unless eval { BDE::Component->new($locn) };
    } elsif (isPackage $name) {
	$locn=eval { $root->getPackageLocation($name) };
    } elsif (isGroup $name) {
	$locn=eval { $root->getGroupLocation($name) };
    } else {
        fatal "Not a group, package, or component: $name";
    }

    if ($locn) {
	print $locn,"\n";
	exit EXIT_SUCCESS;
    } else {
	exit EXIT_FAILURE;
    }
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_depends.pl>, L<bde_usersof.pl>

=cut
