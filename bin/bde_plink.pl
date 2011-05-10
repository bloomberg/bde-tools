#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Cwd;

use BDE::Component;
use BDE::Build::Ufid;
use BDE::Build::Uplid;
use BDE::Util::DependencyCache qw(
    getCachedGroup getCachedPackage getAllGroupDependencies
);
use BDE::FileSystem;
use Build::Option::Finder;
use Build::Option::Factory;

use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent isApplication
    getPackageGroup getComponentPackage
);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE ROOT
);
use Util::Message qw(
    message alert warning warnonce verbose fatal
);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

bde_plink.pl - Generate a plink makefile for a specified package or group

=head1 SYNOPSIS

    $ bde_plink a_bdema > abdema.mk
    $ bde_plink --beta --include=/bbsrc/bbinc/Cinclude > l_foo.mk
    $ bde_plink --target dbg_mt_shr -L/path/to/xlibs -lxlib1 l_foo > l_foo.mk

=head1 DESCRIPTION

C<bde_plink.pl> generates C<plink> makefiles for the specified package or
group. It automatically extracts the list of objects to build, the name of
the task (if an application build) and sets the values of macros like
IS_PTHREAD and IS_EXCEPTION based on the supplied build target type
(default: C<dbg_exc_mt>).

Use the C<--target> or C<-t> option to select a different build target.
Note that if C<bde_plink.pl> is asked to construct a library makefile the
UFID is automatically promoted to include the C<shr> flag, as C<plink> does
not perform static library builds.

The C<--beta> or C<-b> option will enable use of the beta BDE release in
place of the current production version. The actual version of the BDE
libraries used can be then controlled with BDE_VERSION, as documented in
C</bb/bin/machindep.bdebeta.newlink>.

The C<--uplid> or C<-u> option is used for querying initial options. However,
since options like the task name do not depend on the UPLID, there should
never be a need to use this option in normal circumstances.

The makefile is generated with macros for different build types enabled or
commented out, to aid with converting a makefile between different purposes.

=head2 Included Options

The following BDE build options are looked for (in the same manner as
C<bde_build.pl> or C<bde_buildoptions.pl> and incorporated into the makefile
if found:

=over 4

=item APPLICATION_MAIN

The first application defined here is used to determine which application is
built, either based on the source filename or the attached taskname (if one
has been provided, as in C<foo.m.cpp=bar.tsk>).

=item PLINK_LIBS

The list of libraries required for linking that must be supplied by the user
and which are not componentized libraries.

=item BDE_INCLUDE

The list of extra include paths required to compile, itself derived from
C<DEF_INCLUDE>.

=back

These options provide values that would ordinarily be specified in a C<plink>
makefile and cannot otherwise be derived. All other options are ignored,
since C<plink> is presumed to be able to derive them.

=head2 Specifying Additional Resources

Additional resources and definitions may be specified to augment those
extracted from the BDE build options listed above or derived automatically
by C<plink>.

The following options are availble, all of which are named in their
single-letter form to mirror the equivalent compiler or linker option:

=over 4

=item --defines or -D

Specify additional C<-D> compiler definitions.

=item --includes or -I

Specify additional C<-I> include search paths.

=item --libs or -l

Specify additional libraries on the link line.

=item --libpaths or -L

Specify additional library search paths.

=back

All of the above options may be specified multiple times as needed.

=head1 TO DO

=over 4

=item *

Currently the generate makefile is sent to standard output. In future
an option will be provided to determine where the makefile is written to.

=item *

The generated makefile references flat files, so it will build packages
(including applications). However, the directory structure of package
groups is not reflected in the output. This will change in future.

=item *

An option to automatically invoke the makefile with plink after
generation will be provided.

=item *

Tasks are assumed to be IS_PEKLUDGE; support for other task variants
may be added in future, if capabilities are extended to allow this
information to be communicated via the capability (C<.cap>) file for
the unit of release.

=back

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-w <dir>] [-X] [-t <target>] [-D<define>]
                  [-I<path>...] [-L<path>...] [-llib...] <package|group>
  --beta        | -b           enable beta BDE location
  --debug       | -d           enable debug reporting
  --defines     | -D           add additional compiler definitions
  --flat        | -F           source is in one directory (group only)
  --help        | -h           usage information (this text)
  --include     | -I           add additional include paths
  --libpaths    | -L           add additional library search paths
  --libs        | -l           add additional libraries
  --target      | -t <target>  build target <target> (default: 'dbg_exc_mt')
  --uplid       | -u <uplid>   target platform for querying initial options
  --verbose     | -v           enable verbose reporting
  --where       | -w <dir>     specify explicit alternate root
  --noretry     | -X           disable retry semantics on file operations

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        beta|b!
        debug|d+
        defines|D=s@
        help|h
        flat|F!
        include|I=s@
        libpaths|L=s@
        libs|l=s@
        target|ufid|t=s
        uplid|platform|u=s
        verbose|v+
        where|root|w|r=s
        noretry|X
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    if (@ARGV<1 or $ARGV[0] eq '.') {
	my $location=Cwd::cwd();
	# strip build directory if we happen to be in one
	$location =~ s[/(unix|windows)-([^-]+)-([^-]+)-([^-]+)-(\w+)/?$][];
	my $arg=basename($location);
	message("Building from directory argument '$arg'");
	@ARGV=($arg);
    }

    # filesystem root
    $opts{where} = ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # UFID
    $opts{target} = "dbg_exc_mt" unless $opts{target};

    # UPLID
    $opts{uplid} = BDE::Build::Uplid->new() unless $opts{uplid};

    # Beta
    $opts{beta} ||= 0;

    return \%opts;
}

#------------------------------------------------------------------------------

# if we are passed a unit bigger than a component, turn it into a list of the
# components contained within.
sub getComponentsOf ($;$) {
    my $item=shift;
    my $nometarules = shift;

    my @components=();

    if (isGroup($item)) {
	foreach my $pkg (getCachedGroup($item)->getMembers()) {
	    push @components,getCachedPackage($pkg)->getMembers();
	}
    } elsif (isPackage($item)) {
	push @components,getCachedPackage($item)->getMembers();
    } elsif (isComponent($item)) {
	push @components,$item;
    }

    return wantarray ? @components : \@components;
}

#------------------------------------------------------------------------------

sub generate_makefile ($\@$$) {
    my ($unit,$components,$options,$opts)=@_;

    my $ufid = $opts->{ufid};

    #---

    my ($mainsrc,$mainobj,$taskname)=(undef,undef,"");

    if (my $option=$options->getValue("APPLICATION_MAIN")) {
	$mainsrc=$option->getValue();
	($mainsrc)=split / /, $mainsrc, 1;
	($mainsrc,$taskname)=split /=/, $mainsrc, 2;
	$mainobj=$mainsrc; $mainobj=~s/\.\w+$//; $mainobj.='.o';

	verbose "found application main $mainsrc, task name $taskname";
    } elsif (isApplication $unit) {
	$taskname="$unit.tsk";
    } elsif (not $ufid->hasFlag('shr')) {
	$ufid->setFlag('shr');

	warning "no task name found for $unit, building as shared library";
	warning "promoted UFID to ".$ufid->toString(1)
    }

    my $plink_libs=$options->getValue("PLINK_LIBS") || "";

    #---

    my @includes = map { "-I$_" } (".",@{$opts->{include}});
    if (isGroup($unit) and not $opts->{flat}) {
	# regrettably, this doesn't work for some plink-created reason
	@$components = map {
	    getComponentPackage($_).'/'.$_
	} @$components;

	my @packages=getCachedGroup($unit)->getMembers();
	push @includes, map { "-I./$_" } @packages;

	# Another approach that also doesn't work, unfortunately
	# print "VPATH = ",join(':',@packages),"\n";
    }
    if (my $includes=$options->getValue("BDE_INCLUDE")) {
	my $value=$includes->getValue();
	push @includes,$value if $value;
    }

    my @objects  = map { "$_.o" } @$components;
    push @objects, $mainobj if defined $mainobj;
    my @defines  = map { "-D$_" } @{$opts->{defines}};


    my @libpaths = map { "-L$_" } @{$opts->{libpaths}};
    my $runpath  = "";
    if ($ufid->hasFlag('shr') and @libpaths) {
	$runpath  = "-R".join(':',@{$opts->{libpaths}});
    }
    my @libs     = map { "-l$_" } @{$opts->{libs}};

    my @ccflags  = (@includes,@defines);
    my @ldflags  = (@libpaths,$runpath);
    my $objects=join " \\\n                ",@objects;

    #---

print <<_END_OF_MAKEFILE_;
# Autogenerated by bde_plink.pl

include /bb/bin/machdep.newlink
include /bbsrc/tools/data/libmacros.mk

${\(defined($mainsrc)           ? "" : "# ")}IS_PEKLUDGE          = 1
IS_BDE        = 1
${\scalar($opts->{beta} ? "" : "# ")}IS_BDE_BETA   = 1
${\scalar($opts->{beta} ? "" : "# ")}BDE_VERSION   = beta
${\scalar($opts->{beta} ? "" : "# ")}BDE_TARGET    = ${\ $ufid->toString(1) }

IS_CPPMAIN    = 1
IS_COMO       = 1
${\scalar($ufid->hasFlag('mt')  ? "" : "# ")}IS_PTHREAD    = 1
${\scalar($ufid->hasFlag('exc') ? "" : "# ")}IS_EXCEPTION  = 1

USER_CFLAGS   = @includes
USER_CPPFLAGS = @includes
USER_LDFLAGS  = @ldflags

OBJECTS       = $objects ${\ ($mainsrc ? "/bbsrc/big/nonbigdummy.o" : "") }

${\(defined($mainsrc)           ? "" : "# ")}TASK          = $taskname
${\scalar($ufid->hasFlag('shr') ? "# " : "")}OBJS          = \$(OBJECTS)

${\scalar($ufid->hasFlag('shr') ? "" : "# ")}SNAME         = $unit.$ufid.so
${\scalar($ufid->hasFlag('shr') ? "" : "# ")}SOBJS         = \$(OBJECTS)

LIBS          = @libs $plink_libs

include /bb/bin/linktask.newlink
# DO NOT DELETE

_END_OF_MAKEFILE_
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    my $uplid=new BDE::Build::Uplid($opts->{uplid});
    fatal "Bad uplid: $opts->{uplid}" unless defined $uplid;
    $opts->{uplid}=$uplid;

    my $ufid=new BDE::Build::Ufid($opts->{target});
    fatal "Bad ufid: $opts->{target}" unless defined $ufid;
    $opts->{ufid}=$ufid;

    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root);
    my $finder=new Build::Option::Finder($root);
    my $factory=new Build::Option::Factory($finder);

    my @items=@ARGV;
    foreach my $item (@items) {
	my $result=0;

	unless (isPackage($item) or isGroup($item)) {
	    warning "$item is not a group or package -- skipped";
	    next;
	}

	my $options=$factory->construct({
	    uplid => $opts->{uplid},
            ufid  => $opts->{ufid},
            what  => $item
        });

	my @components=getComponentsOf($item);
	unless (@components) {
	    warning "no components for '$item'";
	}

	generate_makefile($item => @components, $options, $opts);
    }
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_build.pl>

=cut
