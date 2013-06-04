#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use File::Path;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Util::File::Basename qw(basename);

use Getopt::Long;

use BDE::Build::Ufid;

use BDE::FileSystem;use BDE::Util::DependencyCache qw(
    getDependencyBuildOrder getCachedPackage getCachedGroup getSimpleLinkName
    getBuildLevels
);
use BDE::Util::Nomenclature qw(
    isPackage isGroup isGroupedPackage isApplication getPackageGroup
);
use Util::Message qw(fatal message debug);
use Symbols qw(ROOT EXIT_FAILURE EXIT_SUCCESS);

#==============================================================================

=head1 NAME

bde_buildorder.pl - Extract and display dependencies in order of build

=head1 SYNOPSIS

  $ bde_buildorder bas
  $ bde_buildorder.pl --linkline m_bdeoffline
  $ bde_buildorder.pl -all mde
  $ bde_buildorder.pl --level bas
  $ bde_buildorder.pl --all --level bas

=head1 DESCRIPTION

C<bde_buildorder.pl> generates a canonical build order for all dependencies
of the specified package or package group. It can optionally also list
out the dependencies of each dependency (with C<--all> or C<-a>) and report
the numeric library level (with C<--level> or C<-n>). Both C<--all> and
C<--level> can be specified for a combined report.

It can also, on demand, generate the canonical link line or a report of all
dependencies and their respective dependencies with C<--linkline> or C<-l>.
This mode is incompatible with C<--all> and C<--level>.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-p <prefix>] [-t <ufid>] [-u <ufid>] [-w <root>]
                           [-o name,name [-o name]] [-d[d]] [-v[v]] [-x]
                           <unit of release>
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --verbose    | -v           enable verbose reporting
  --where      | -w <dir>     specify explicit alternate root (default: .)

Alternate report styles:

  --all        | -a           output all dependencies with their own lists
  --level      | -n           output libraries with level number
                              (may be combined with --all)
  --layers     | -Y           output level numbers with libraries
  --linkline   | -l           output link line (-l options)
  --ufid       | -u           build target type
                              (only with --linkline)

See 'perldoc $prog' for more information.

_USAGE_END
}

  #--linkpath  | -L           output link path (-L options)
  #--includes  | -I           output include path (-I options)
  #--stage

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        all|a
        debug|d+
        help|h
        where|root|w|r=s
        verbose|v+
        level|levels|n!
        layer|layers|Y|s!
        linkline|l!
        linkpath|L!
        inludes|I!
        ufid|target|u|t=s
    ])) {
        usage("Arfle Barfle Gloop?");
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage("Nothing to do"), exit EXIT_FAILURE if @ARGV < 1;

    # too many arguments
    usage("Specify only one group or package argument"), exit EXIT_FAILURE
      if @ARGV > 1;

    usage("--all and --linkline are mutually exclusive"), exit EXIT_FAILURE
	  if $opts{all} and $opts{linkline};
    usage("--all and --layer are mutually exclusive"), exit EXIT_FAILURE
	  if $opts{all} and $opts{layer};
    usage("--level and --linkline are mutually exclusive"), exit EXIT_FAILURE
	  if $opts{level} and $opts{linkline};
    usage("--layer and --linkline are mutually exclusive"), exit EXIT_FAILURE
	  if $opts{layer} and $opts{linkline};

    # filesystem root
    $opts{where} = ROOT unless $opts{where};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);

    my $ufid=new BDE::Build::Ufid($opts->{ufid});

    my $item=$ARGV[0];

    my @order=getDependencyBuildOrder($item);
    if (isGroupedPackage($item)) {
	my $group=getPackageGroup($item);
	@order = (getDependencyBuildOrder($group),@order);
    }
    my %level=getBuildLevels(@order); #free

    if ($opts->{all}) {
	foreach my $dep (@order) {
	    my @deporder=getDependencyBuildOrder($dep);
	    @deporder=reverse map {
		getSimpleLinkName($_,$ufid)
	    } @deporder if $opts->{linkline};
	    print $dep;
	    print " (level ".$level{$dep}.")" if $opts->{level};
	    my $ndeps=scalar(@deporder);
	    print ": $ndeps ";
	    print " - @deporder" if @deporder;
	    print "\n";
	}
    } elsif ($opts->{includes}) {
	print join(" ",map { "-I$_" } @order),"\n";
	#<<<TODO: handle package dirs or use deployment dirs
    } elsif ($opts->{layer}) {
	my @stack;
	foreach my $uor (keys %level) {
	    $stack[$level{$uor}] ||= [];
	    push @{$stack[$level{$uor}]},$uor;
	}
	foreach my $lvl (0..$#stack) {
	    next unless defined $stack[$lvl];
	    printf "%3d: ".(join ' ',sort @{$stack[$lvl]})."\n", $lvl;
	}
    } elsif ($opts->{level}) {
	foreach my $uor (sort { $level{$a} <=> $level{$b} || $a cmp $b }
			 keys %level) {
	    print "$uor (level $level{$uor})\n";
	}
    } elsif ($opts->{linkline} or $opts->{linkpath}) {
	if ($opts->{linkline}) {
	    print join(" ",map {
		getSimpleLinkName($_,$ufid)
	    } reverse @order),"\n";
	}
	#...if ($opts->{linkpath}) { } reverse @order),"\n";
    } else {
	# default output
	print "@order \n";
    }
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_uordepends.pl>, L<bde_uorusersof.pl>, L<bde_graphgen.pl>

=cut
