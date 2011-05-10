#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Component;
use BDE::Util::DependencyCache qw(
    getCachedComponent
    getAllComponentFileDependencies
    getAllComponentDependencies
    getAllExternalComponentDependencies
    getAllInternalComponentDependencies
    getAllFileDependencies
);
use BDE::FileSystem;
use BDE::Build::Invocation qw($FS);
use BDE::Util::Nomenclature qw(
    isComponent isPackage getComponentGroup getComponentPackage
);
use Symbols qw(EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT);
use Util::Message qw(fatal debug);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

bde_depends.pl - Find and return downwards dependencies of a component

=head1 SYNOPSIS

  # machine mode
  $ bde_depends.pl bdet_datetime > bdet_datetime.deps

  # pretty mode
  $ bde_depends.pl -p bces_platform | less

=head1 DESCRIPTION

C<bde_depends.pl> extracts the dependency information for the specified
component and sends it to standard output. It has two primary output modes,
I<machine mode> and I<pretty mode>, which are selected depending on whether
the C<--pretty> or C<-p> option is specified:

=over 4

=item Machine mode

The list of files on which the component has a compile-time dependency is
returned as a simple space-separated list of fully-qualified filenames suitable
for use in makefiles.

If the C<--production> or C<-P> option is used, the fully-qualified names are
adjusted to their final locations in the production envrionment, otherwise they
refer to the development root in which the component was located. (but see the
C<--macros> option below).

=item Pretty mode

The internal (intra-package) and external (extra-package) component
dependencies of the specified component are reported in a human-readable
format. Both internal and external dependencies are calculated for I<interface
only>, I<interface plus implementation>, and I<full dependencies> (i.e.
link-time object-file component dependencies).

Following this, the list of non-component includes that are external to the
system are reported, followed by the list of unqualified identified
non-component includes (i.e. originating from non-compliant packages).
If the C<--verbose> or C<-v> flag is used, the list of identified files is
reiterated, this time fully qualified.

=back

The C<--macros> or C<-m> flag converts fully qualified paths to a macro form
that is suitable for overriding in makefiles. This affects the output of
Machine mode, and the output of Pretty mode if the C<--verbose> flag is
used to list out file includes in their qualified form.

=head1 TO DO

In this implementation the C<--groupdeps> option does not generate output that
corresponds to the new location of group-level includes. This will be remedied
in a future release.

=cut

#==============================================================================

sub usage (;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-l] [-p] [-w <dir>] [-X] <component> | <file> <package>
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)
  --direct     | -D           depend directly on source rather than installed
                              include directories
  --groupdeps  | -G           depend on groups rather than packages
  --macros     | -m           generate output using makefile macros rather
                              than explicit paths
  --pretty     | -p           generate human-readable dependency information
  --production | -P           adapt paths to production locations - note this
                              does *not* mean files are analysed from there
  --verbose    | -v           output more information in --pretty mode
  --where      | -w <dir>     specify explicit alternate root
  --noretry    | -X           disable retry semantics on file operations

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
	direct|D
	groupdeps|G
        macros|m
        pretty|p
	production|P
        noretry|X
	verbose|v
        where|root|w|r=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1; # or @ARGV>2;

    # filesystem root
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    my $inc=($opts->{direct})?"":"${FS}include";

    #---

    #if (@ARGV==2) {
#	my ($filename,$packagename)=@ARGV;
#	unless (isPackage($packagename)) {
#	    fatal "Not a package: $packagename";
#	}
#
#	# this is a very primitive first implementation.
#	my @dependencies=getAllFileDependencies($filename,$packagename);
#	print "File dependencies: ",
#	  scalar(@dependencies),"\n", map {
#	      "    (".($_->getPackage or "-").") $_\n"
#	  } @dependencies;
#
#	exit EXIT_SUCCESS;
#    }

    #---

    my $componentname=$ARGV[0];
    foreach my $componentname (@ARGV) {
        unless (isComponent($componentname)) {
            fatal "Not a component: $componentname";
        }
        my $component=getCachedComponent($componentname);

        my @dependencies;
        if ($opts->{pretty}) {

            @dependencies=$component->getDependants();
            print "Direct dependencies: ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;
            @dependencies=getAllExternalComponentDependencies($component,0);
            print "External dependencies (interface only): ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;
            @dependencies=getAllExternalComponentDependencies($component,1);
            print "External dependencies (interface+implementation): ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;
            @dependencies=getAllExternalComponentDependencies($component,2);
            print "External dependencies (full): ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;
            @dependencies=getAllInternalComponentDependencies($component,0);
            print "Internal dependencies (interface only): ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;
            @dependencies=getAllInternalComponentDependencies($component,1);
            print "Internal dependencies (interface+implementation): ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;
            @dependencies=getAllInternalComponentDependencies($component,2);
            print "Internal dependencies (full): ",
              scalar(@dependencies),"\n", map { "    $_\n" } @dependencies;

            @dependencies=getAllComponentFileDependencies($component);
            print "Exterior files: @{[grep {not $_->getPackage} @dependencies]}\n";
            @dependencies=grep { $_->getPackage } @dependencies;
            print "Tracked Files: @dependencies\n";

            if ($opts->{verbose}) {
                if ($opts->{macros}) {
                    @dependencies=map {
                        "\$(".uc($_->getGroup)."_LOCN)${FS}".$_->getPackage().
                          $FS.$_->getPathname();
                    } @dependencies;
                } else {
                    @dependencies=map {
                        $_->getRealname();
                    } @dependencies;
                }
                print "Fully qualified files: @dependencies\n";
            }
        } else {

            if ($opts->{macros}) {

                @dependencies=map {
                    "\$(".uc(getComponentGroup($_))."_LOCN)$inc${FS}".
                      ($opts->{groupdeps}?"":(getComponentPackage($_).$FS)).
                        "$_.h";
                } getAllComponentDependencies($component);
                push @dependencies, map {
                    "\$(".uc($_->getGroup())."_LOCN)$inc${FS}".
                      ($opts->{groupdeps}?"":($_->getPackage().$FS)).
                        $_->getPathname();
                } getAllComponentFileDependencies($component);

            } else {

                @dependencies=map {
                    (($opts->{groupdeps} and getComponentGroup($_))
                       ? $root->getGroupLocation(getComponentGroup($_))
                       : $root->getPackageLocation(getComponentPackage($_))
                    ).$inc.$FS.$_.".h"
                } getAllComponentDependencies($component);

                push @dependencies, map {
                    (($opts->{groupdeps} and $_->getGroup)
                       ? $root->getGroupLocation($_->getGroup)
                       : $root->getPackageLocation($_->getPackage)
                    ).$inc.$FS.$_->getPathname()
                } grep {
                    $_->getPackage()
                } getAllComponentFileDependencies($component);

            }

            if ($opts->{production}) {
                # convert paths to their production locations
                # handle stlport subdir as a special case for simplicity
                map {
                    ##<<<TODO: $(CINCLUDE) is /bbsrc/bbinc/Cinclude
                    ##         Use $(CINCLUDE) or create macro for BDE header locn?
                    s{^.*/(stlport/.*)$}{/bbsrc/bbinc/Cinclude/bde/$1} or
                    s{^.*/(\w+(\.\w)?)$}{/bbsrc/bbinc/Cinclude/bde/$1}
                } @dependencies;
            }

            print "@dependencies";
        }

        print "\n";
    }

    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_usersof.pl>, L<BDE::Util::DependencyCache>

=cut
