#!/bbs/opt/bin/perl

use strict;
use warnings;

use English qw( -no_match_vars );

use FindBin;
use File::Path;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Cwd qw();
use Compat::File::Spec qw(rel2abs);
use Getopt::Long;
use Carp;
use IO::File;

use Config;
my $PS = $Config{path_sep};

use BDE::Build::Invocation qw($FS $FSRE $INVOKE);
use BDE::FileSystem;
use BDE::Group;
use BDE::Package;
use BDE::Component;
use BDE::Util::DependencyCache qw(
    getCachedGroup        getAllGroupDependencies
    getCachedPackage      getAllPackageDependencies
    getCachedComponent    getCachedGroupOrIsolatedPackage
    getAllInternalPackageDependencies
    getAllExternalComponentDependencies
    getAllInternalComponentDependencies
    getAllComponentFileDependencies
    getAllComponentDependencies
    getTestOnlyDependencies
    getAllFileDependencies
    getBuildOrder
    getLinkName
    createFileFinderForComponent
);
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::File::Finder;

use Build::Option::Finder;
use Build::Option::Factory;

use BDE::Util::Nomenclature qw(
    isCompliant isNonCompliant    isIsolatedPackage
    isComponent isPackage isGroup isGroupedPackage
    isApplication isFunction isLegacy
    getPackageGroup getComponentPackage getComponentGroup
    getTypeName getType
);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_JOBS MAKEFILE_NAME
    PACKAGE_META_SUBDIR GROUP_META_SUBDIR ROOT
    OPTFILE_EXTENSION MEMFILE_EXTENSION DEPFILE_EXTENSION
    REFFILE_EXTENSION DUMFILE_EXTENSION
    CONSTANT_PATH
);
use Task::Action;
use Task::Manager;
use Util::File::Basename qw(basename dirname);
use Util::File::Attribute qw(is_newer is_newer_missing_ok);
use Util::Message qw(
    alert message error fatal debug debug2 warning
    set_debug get_debug set_verbose verbose
);
use Util::Retry qw(:all);

use Data::Dumper;

# platform independent constant paths
my $constant_path = join($PS, split(/:/, CONSTANT_PATH));

#==============================================================================

=head1 NAME

bde_build.pl - build tool for component-based libraries and executables

=head1 SYNOPSIS

  # source unit argument: group, package, or component
  $ bde_build.pl bde                          - build base library
  $ bde_build.pl l_grppkg                     - build department package
  $ bde_build.pl m_bdeoffline                 - build application
  $ bde_build.pl a_bdema_gmallocallocator     - build adaptor component
  $ bde_build.pl (no unit argument)           - get name from parent directory

  # common options and options bundling
  $ bde_build.pl -R bde                       - force-rebuild makefiles
  $ bde_build.pl -RBclean bde                 - ...and clean before build
  $ bde_build.pl -RBclean -j8 bde             - ...and increase parallelisation
  $ bde_build.pl -RBclean -j8 -e bde          - ...and don't build or run tests
  $ bde_build.pl -RBclean -ej8 -v bde         - ...and increase verbosity
  $ bde_build.pl -RBclean -vej8 -cCC64 bde    - ...and do a 64-bit build
  $ bde_build.pl -RBclean -vej8 -cCC64 -S bde - ...and suppress command output
  $ bde_build.pl -j8 bde -SveRBclean -cCC64   - options can go after unit

  # express builds
  $ bde_build.pl -U bde                       - assume makefiles are up-to-date
  $ bde_build.pl -e bde                       - express build group (no tests)
  $ bde_build.pl -en bdema                    - build package, no dependants
  $ bde_build.pl -e bdet_datetime             - build all, test component only
  $ bde_build.pl -ne bdet_datetime            - no dependencies, test component
  $ bde_build.pl -nee bde_datetime            - build but do not test component
  $ bde_build.pl -en bde                      - no intrapackage dependencies

  # build and build failure modes
  $ bde_build.pl bde       - build dependent packages using current build if
                             successful, or previous successful build otherwise
  $ bde_build.pl -F bde    - do not build dependent packages on failure
  $ bde_build.pl -Q bde    - abort build process immediately on failure
  $ bde_build.pl -X bde    - disable all retry semantics

  # change build root and/or path
  $ bde_build.pl -w /path/to/root bde         - specify explicit root
  $ BDE_ROOT=/path/to/root bde_build.pl bde   - the same
  $ BDE_PATH=/path_a:/path_b:/path_c foo      - where to look for dependencies

  # control of low-level build options
  $ bde_build.pl -DRETRY_TIMEOUT=10 bde       - set retry timeout to 10s
  $ bde_build.pl -DALLTEST_PARALLEL='-s' bde  - serial tests in parallel build
  $ bde_build.pl -DCC=/opt/other/CC bde       - override C++ compiler

=head1 DESCRIPTION

C<bde_build.pl> is a general-purpose build tool for constructing
component-based libraries and executables for packages and package groups.
It has a wide range of options intended to support a diverse range of usage
patterns. Please see the synopsis for a selection of example build commands
showing the use of the most common options.

=head2 Build Strategy

By default, C<bde_build.pl> will attempt to build each package of a package
group in parallel, waiting for all required packages to complete for each
given dependant package. If a required package fails to build and a previous
build of that package succeeded (for the same architecture and build type)
then any dependant packages will include and link against the previously
successful build. This is the 'best effort' algorithm. (Note that this only
applies to package groups. Individual packages either succeed or they don't.)

The build strategy may be adjusted in several ways. Firstly, the C<-F> and
C<-Q> options will both cause C<bde_build.pl> to stop trying to build
dependent packages on a failed package build. C<-Q> will in addition cancel
any unprocessed build stages of parallel package builds. This is the 'fail
as soon as possible' algorithm. Secondly, using the C<-n> option with a package
group will disable intrapackage dependencies and permit dependant packages to
build immediately. Since this may cause test drivers builds to reach for
package libraries of required packages before they have been constructed, this
use of C<-n> is not recommended without C<-e>.

With a package argument, C<-n> simply disables the checks and possible
rebuilds of required packages.

=head2 Build Types

Source may be built in debug or optimised forms, with or without threads,
with or without exceptions, as static or shared libraries. The build type
is specified with -t and defaults to 'dbg_exc_mt'. Valid build type flags
include:

  dbg|opt, exc, mt, shr, ndebug, pure, purewin, ins

For example, to build optimised, no threads, with exceptions, use:

  bde_build.pl -t opt_exc ...

To link against dependent libraries build with a different build type,
use the C<-l> option. To build test drivers with a different build type to
their components, use the C<-T> option. This allows, for example, purified
components to be build in debug mode with non-purified drivers and optimised
dependent libraries.

(Note: Windows DLLs are not fully supported currently.)

=head2 Build Stages

C<bde_build.pl> constructs a dependency tree of build stages for the requested
source unit and then attempts to satisfy all dependencies until the build is
complete. Within each package, the dependency tree is as follows:

               [required groups/isolated packages, if -H]
                                |
           (-B prebuild targets, if any)
                        |                  [required packages]
            preprocess_package_includes        /
                                 \            /
                             build_package_objects
                             /                   \
                  build_package_library       build_test
                    |                |             |
             install_package         |            test
              /           \          |            /
             /          (-A postbuild targets, if any)
   [dependant packages]

For package groups and isolated packages, a C<install_group> stage is
then carried out by the group-level makefile:

                        (all package postbuild stages)
                                |
                           install_group
                                |
               [dependant groups/isolated packages, if -H]

Stages in the middle of the diagram (i.e. without braces or parantheses)
are make targets which create logs and which can be invoked directly via
C<-M> or through the generated makefile (see below).

Use of the C<-n> option with a package group switches off the connection
between the C<install_package> stage of required packages and the
C<build_package_objects> stage of packages which depend on them.

=head2 Build Directories and Make Logs

Builds are carried out in an architecture-derived subdirectory under each
package. The name of the directory is the Unified Platform ID, or UPLID,
also retrievable from L<bde_uplid.pl>.

A build directory will contain copies of the source (for various reasons),
built objects, the makefile and makefile variables, the package library (on
a successful build), test driver executables if a non-express build has been
invoked, and log files for each stage of the build process. To quickly
determine which stage failed, use C<ls -lrt> to list files in reverse time
order; the bottom log file is the one written to most recently.

=head2 Using Autogenerated Makefiles Directly

The makefiles created by C<bde_build.pl> contain targets of convenience to
allow them to be invoked directly by the developer if desired. In addition,
the most recently invoked build type (e.g. 'dbg_exc_mt', 'dbg_mt', etc.) will
be referenced by a C<Makefile> symbolic link so make tools will find it without
an explicit C<-f> option.

The makefiles contain targets beyond those invoked by C<bde_build.pl> itself,
including targets to build and test individual components. The most useful of
these are:

Package level:

    build                  - build package objects and library
    build_test             - build package objects and test drivers, but do not
                             run the test drivers.
    install                - install package objects and headers to the package
                             installation locations. Targets 'install_package'
                             and so on may be used to carry out more specific
                             parts of the overall installation target.
    clean                  - clean package objects, library, test drivers for
                             the configured build type (e.g. C<dbg_exc_mt>).
    uninstall              - uninstall package headers from package and group
                             locations.
    noop                   - do nothing (use -RMnoop to build makefiles only)

Component level:

    <component>            - build and test the component
    test.<component>       - "
    <component>.test       - "
    build.<component>      - build the component, not the test driver
    <component>.build      - "
    build_test.<component> - build component and driver, do not run driver.
    <component>.build_test - "
    clean.<component>      - clean component and intra-package dependencies
    <component>.clean      - "

C<clean> and C<uninstall> targets will clean and uninstall headers and the
package library for the specifc build target the makefile was generated for,
so other build types will not be affected. Individial components can also be
cleaned, in which case the object files for that component, its test driver,
and any components in the same package on which it depends, will be cleaned.

=head2 Group-Level Makefiles

Makefiles are also generated at the package group level (or package level,
for isolated packages) to handle the operations of installing headers and
libraries units of release.  These makefiles are invoked at the end of the
build process if a group or isolated package build is requested. They are
also invoked if the C<--honordeps> or C<-H> has been specified.

The C<-M> option is supported and passed to both the package-level and
group-level makefiles, so C<-Mclean> will cause the removal of the appropriate
group library and headers.

The C<-B> and C<-A> flags (see below) "wrap" the package-level build process,
and so will not invoke targets in the group-level makefile. They can however
still be used to invoke targets in the package makefiles that install headers
or objects to the group location. (Note that it is only possible to update
a static library with new objects this way.) Equivalent flags to handle
start and end of group build targets may be supported in future.

=head2 Hono(u)ring External Dependencies

If the C<-H> or C<--honordeps> option is specified, all external dependencies
(that is, other package groups or isolated packages) on which the requested
group, package, or component depends will also be built, in dependnecy order.
For example, if C<m_myapp> depends on both C<bde> and C<bce>, then C<bde> and
C<bce> are built as well, with C<bde> built first as it is also a dependnecy
of C<bce>.

Any external dependency so built is implicitly built express. That is, test
drivers within depended-on units-of-release are not built or run. More
flexible build options for dependencies may be supported in future.

=head2 Pre- and Post-Build Targets

The C<-B>, C<-A>, and C<-M> options can be used to specify targets to be
invoked before, after, and instead of the normal build process respectively.
For example, to clean and uninstall a package group prior to building it:

    $ bde_build.pl -Bclean,uninstall bde

To carry out the clean and uninstall but not proceed with the build:

    $ bde_build.pl -Mclean,uninstall bde

To install package headers and objects into the group library in a
package-level build (which ordinarily does not do so):

    $ bde_build.pl -Ainstall_group btemt

To forcibly rebuild the makefiles generated by C<bde_build.pl> but not use
them through C<bde_build.pl>:

    $ bde_build.pl -RMnoop

(See the last section for more on the C<install_group> and C<noop> targets.)

=head2 Component Builds

If a component name is specified as the source unit then C<bde_build.pl> will
do only enough work to build that component, and no other component in the
same package. If C<-e> is used, all dependant packages will be built but their
test drivers will not be run. As a convenience, the test driver of the
component itself however is built and run. (Use <-ee> to disable this if
desired).

Component builds do not invoke the C<build_package_library> stage, and
therefore do not install that component into either the package or group
install directories. A package or group build must be performed to achieve
this.

=head2 Locating Requested and Dependent Sources

C<bde_build.pl> will automatically seek out the appropriate locations for
the source unit specified and any dependants of that unit. The search is
carried out in the following order:

* In a source directory directly above or adjacent to the current working
directory. This permits local 'sandbox' directories, if needed.

* In the appropriate subdirectory of the path specified by C<BDE_ROOT>.
It is important to set this environment variable or the local root will not be
seen.

* On the search path defined by C<BDE_PATH>. A default search path is
used if no explicit path is set. It is strongly suggested that this path is not
overridden without explicit need.

The C<-v> option may be used to have C<bde_build.pl> report on where it
finds the requested source unit and dependent source units.

If C<bde_build.pl> is invoked above or in the directory of a package group
or package, the source unit may be omitted from the command line.

=head2 Creating a New Source Root

A new root may be set up using L<bde_setup.pl>. This tool can also populate a
new or existing root with files for a new package or package group. Set
C<BDE_ROOT> to the top of the new root to have C<bde_build.pl> and other BDE
development tools see and use it.

=head2 Configuring the Build Root and Build Path

The build root should point to the local source tree. The default value,
C</bbcm/infrastructure> can be overridden by defining the environment variable
C<BDE_ROOT>, which should reference the directory containing the C<groups>
subdirectory (amongst others created by C<bde_setup.pl>).

The build path should contain a comma-separated list of other build roots,
from which dependencies not present in the local source tree can be fetched.
By configuring the path, it is possible to pick up dependencies from any
number of nominated build roots. Units of release are searched for in each
root in turn, with the first root that contains the unit being used to supply
that unit.

The default build path is slightly atypical because it defines three alternate
'fallback' locations, at least one of which is expected to exist:

    /bbcm/infrastructure                      - for Clearcase users
    /view/dev-<username>/bbcm/infrastructure  - for Clearcase users on DGUX
    /bbsrc/bde/root/latest                    - for non-Clearcase users

Each of these paths (if they exist) provides access to the BDE libraries. In
general, at least one of them should be present in any redefined build path.
Note that while the default path repeats the default root as its first element,
this is not required. It is the default simply so that the root can be
changed without requiring the path to be changed also.

For example:

    $ BDE_ROOT=/home/me/bderoot \
      BDE_PATH=/home/you/bderoot:/home/other/bderoot:/bbsrc/bde/root/latest \
      bde_build.pl -Sve m_myapplication

The C<-v> or C<--verbose> option will, amongst other details, list where in
the local root or build path a given dependency was found.

On top of the build root and build path, a 'local context' search is also done.
If C<bde_build.pl> is run in a location in which a valid directory structure
exists for the specified unit of release or any of its dependencies, the local
directory will be used as the source. This means that, so long as
C<bde_build.pl> is run from a current working directory either immediately
above or inside a package or package group directory, the local source will be
used even if C<BDE_ROOT> has not been set up to reference it.

=head2 Troubleshooting

* If a build is aborted during makefile construction then an incomplete
makefile may sometimes result, causing 'no rule to make target' errors in the
build. To make C<bde_build.pl> update makefiles, use the C<-R> option.

* If a build reports a C<gmake> error that a required header cannot be
included, and this header is from a dependant package or package group, it
is most likely that the dependant library has either not been built, or has
been updated in source control with new components not included in the last
successful build.

* A 'bad location' or similar error indicates that no valid location could
be found for a required package or package group. This most probably indicates
that BDE_ROOT is not set to point to the right local root. It may also indicate
a dependency file with an entry for a non-existent unit of release.

* An application main file should usually have the name C<m_appname.m.cpp>. To
use any other name, or configure any other kind of unit of release to build
an application sourcefile, add the variable APPLICATION_MAIN to the options
file for that unit (package or package group). More than one application main
may be specified as the value of this variable. See I<m_bdeoffline> for an
example.

* Source that includes 'unconstrained' header files (i.e. most files in the
C</bbsrc/bbinc/Cinclude> directory) may include a header that conforms to a
component name. To instruct bde_build.pl and other tools to disregard this
header for the purposes of dependency analysis, place the comment
C<// not a component> on the end of the line containing the include directive.

=head1 TO DO

These are some of the extensions planned for C<bde_build.pl>:

=over 4

=item The bde_build.pl manual

More extensive documentation will be provided in a separate document.

=item Multiple build targets and source units

Currently C<bde_build.pl> only builds one specified source unit, in one
specified build target type. This will be extended to allow multiple parallel
builds.

=item Recognize external source unit dependencies

Group dependencies are presumed to be satisfied to prevent lengthy prebuild
dependency checks. The option to check dependant source units as well will be
added.

=item Component-level pre- and post-targets

The -A, -B, and -M flags will understand component-level builds, so commands
like C<bde_build.pl -Bclean bdet_datetime> and C<bde_build.pl bde -Abdema.test>
will work.

=item ...and many more

=back

=cut

#==============================================================================

my %opts;     # options
my $root;      # initialised from --where option or default
my $ufid;      # build flags for component objects
my $test_ufid; # ufid for test driver objects/link, if different
my $link_ufid; # ufid for library links, if different
my $uplid;     # platform id
my $factory;   # options constructor

my $RETRY_MAKEPROG =
    "${FindBin::Bin}${FS}retry -t1500 -m '".
    q{(CC|munch|make|Makefile|ld|\(S\))}.
    q{[^\n]+}.
    q{(fork\sfailed|not\senough\sbuffer\sspace|SEVERE\sERROR|device\sor\saddress|Error\sreading\sinput\sfile)}.
    "' -- ";

my $EOF_MARKER="#--- END-OF-MAKEFILE ---\n";

#    q{(No\srule\sto\smake\starget|fork\sfailed|not\senough\sbuffer\sspace|SEVERE\sERROR|device\sor\saddress|Error\sreading\sinput\sfile)}.
#    "' -- ";
#------------------------------------------------------------------------------

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-c <comp>] [-d] [-s|-j<n>] [-t <tgt>] [-u <upl>]
        Build a group: ... [-e] <group>
      Build a package: ... [-e] [-n] <package>
    Build a component: ... [-e[e]] [-n] <component>
        Mkdevdir mode: ... [-m] [-G] [-l <target>] [-b <view>] <component>|'.'

  --after      | -A <rule>    make explicit target(s) after regular build
  --before     | -B <rule>    make explicit target(s) before regular build
  --compiler   | -c <comp>    compiler definition for system (default: 'def')
  --clearmake  | -C           enable clearmake mode (disables --output)
  --debug      | -d           enable debug reporting
  --define     | -D <macro>   define one or more makefile macro overrides:
                                <name>[=<value>][,<name>[=<value>]...]
  --express    | -e           express build (do not build or run test drivers)
  --ncexpress  | -E           skip tests for non-compliant packages only
  --fail       | -F           do not build dependant packages on failure
  --help       | -h           usage information (this text)
  --honordeps  | -H           analyse and build dependant units also
  --jobs       | -j [<jobs>]  build in parallel up to the specified number of
                              jobs (default: ${\DEFAULT_JOBS} jobs)
                              default if platform is not 'windows'
  --makejobs   | -J [<jobs>]  call underlying make program with
                              appropriate option to parallelize to 'jobs'
                              jobs (default: -j value).  This option allows
                              bde_build.pl to be invoked with -s for safety,
                              but still exploit gmake's parallelization capabilities
  --keepgoing  | -k           pass the -k option to gmake/nmake to build unrelated
                              targets even if errors occur
  --ifcapable  | -K           return success rather than failure if the
                              capabilities of the target do not allow build
  --linktarget | -l <target>  link to libraries with different <target>
  --mkdevdir   | -m           create local development directory makefile
  --make       | -M <rule>    make explicit target(s) only (e.g.: 'build_test')
                              instead of entering normal build process
  --nodepend   | -n           do not build dependent packages (not with groups)
  --nolog      | -N           do not create build-stage logfiles
  --output     | -o <path>    place derived files on different filesystem, rooted
                              at <path>
                              If ~/.bde_build_output_location is a symlink, its
  --no-output  | -O           place output files locally, ignoring
                              ~/.bde_build_output_location if present (overrides
                              -o if both are present)
                              target will be used if -o is not specified
  --path       | -p           override BDE_PATH
  --quit       | -Q           quit immediately on failure (see also -F)
  --serial     | -s           serial build (equivalent to -j 1)
                              default if platform is 'windows'
  --silent     | -S           suppress build command output
  --target     | -t <target>  build target <target> (default: 'dbg_exc_mt')
  --testtarget | -T <target>  build test drivers with different <target>
  --uplid      | -u <uplid>   specify rather than derive platform ID. -c will
                              override or add compiler if specified.
  --uptodate   | -U           assume makefiles are up-to-date (opposite of -R)
  --rebuild    | -R           force rebuild makefiles even if up to date
  --where      | -w <dir>     specify explicit alternate build root
  --verbose    | -v           enable verbose reporting
  --noretry    | -X           disable retry semantics on file operations
                              (default)
  --retry      | -x           enable retry semantics on file operations

See 'perldoc $prog' for more information.

_USAGE_END
}

# Under development:
#
#  --groupdeps  | -G           construct makefile with local group dependencies
#                              rather than depend on local packages directly
#  --production | -P           production-style build (under development)

#------------------------------------------------------------------------------

# Override Util::Retry::retry_chdir to add debugging
{
    no warnings 'redefine';
    sub retry_chdir ($) {
        debug "chdir to $_[0]";

        Util::Retry::retry_chdir($_[0]);
    };
}

# if needed, make directory, or, if opts{output} is in effect, make directory
# under opts{output} and put symlink in place
sub mkdirOrLink($$) {
    my ($dir, $mask) = @_;
    return 1 if -e $dir;

    my @dirParts=split /$FSRE/,$dir;

    if(!$opts{output}) {
        my $currentDir="";
        foreach my $dirPart(@dirParts) {
            next if $dirPart eq "";

            # windows drive letters...
            if(length($currentDir)!=0 || $dirPart!~/^\w:/) {
                $currentDir.=${FS}.$dirPart;
            }
            else {
                $currentDir=$dirPart;
            }
            if(!-d $currentDir) {
                mkdir $currentDir,$mask;

                # don't use or on the mkdir - it may have failed because other
                # process created the dir
                if(!-d $currentDir) {
                    fatal "Cannot create $currentDir: $!";
                }

                debug "Created directory $currentDir";
            }
        }

        return 1;
    }

    # opts{output} is in effect
    my $currentDir = $opts{output};
    foreach my $dirPart(@dirParts) {
        $currentDir.=${FS}.$dirPart;
        if(!-d $currentDir) {
            mkdir $currentDir,$mask;
            # don't use or on the mkdir - it may have failed because other
            # process created the dir
            if(!-d $currentDir) {
                fatal "Cannot create $currentDir: $!";
            }
            debug "Created directory $currentDir";
        }
    }

    my $targetDir = "";
    pop @dirParts; # don't want to mkdir last part of path for target, that
                   # will be symlink
    foreach my $dirPart(@dirParts) {
        $targetDir.=${FS}.$dirPart;
        if(!-d $targetDir) {
            mkdir $targetDir,$mask;
            # don't use or on the mkdir - it may have failed because other
            # process created the dir
            if(!-d $targetDir) {
                fatal "Cannot create $targetDir: $!";
            }
            debug "Created directory $targetDir";
        }
    }

    unlink $dir; # removing existing symlink if we get this far
    symlink $currentDir, $dir;
    # don't use or on the symlink - it may have failed because another process
    # already created the symlink.
    if(!-l $dir && !-d $dir) {
        fatal "Cannot create symlink from $currentDir to $dir: $!";
    }
    debug "Created symlink $dir -> $currentDir (or $dir is a directory already)";

    return 1;
}

# return package group or the package if it's isolated
sub getGop ($) {
    return getPackageGroup($_[0]) or $_[0];
}

sub getUnitMacro ($) {
    my $gop=uc($_[0]);
    $gop=~s|[~+=/]|_|g;
    return $gop;
}

# return group macro + package path or just the package macro if it's isolated
sub getGopLocnMacro ($) {
    if (my $group=getPackageGroup($_[0])) {
        return "\$(".getUnitMacro($group)."_LOCN)".$FS.$_[0];
    } else {
        return "\$(".getUnitMacro($_[0])."_LOCN)";
    }
}

# Write a options string (or options object) to the specified filename
sub writeBuildVarsFile($$) {
    my ($options,$varsfile)=@_;

    debug "Writing $varsfile";
    my $GVH=new IO::File;
    retry_open($GVH,">$varsfile")
      or fatal "Unable to open $varsfile: $!";
    print $GVH $options;
    print $GVH $EOF_MARKER;
    close $GVH;
}

sub constructOptions ($$$) {
    my ($item,$uplid,$ufid)=@_;

    fatal "Bad uplid: $uplid" unless $uplid->isa("BDE::Build::Uplid");
    fatal "Bad ufid: $ufid" unless $ufid->isa("BDE::Build::Ufid");

    my $options=$factory->construct({
        uplid => $uplid,
        ufid  => $ufid,
        what  => $item,
    });

    return $options;
}

sub writeOptions ($$$$;$$) {
    my ($unit,$options,$makename,$from,$prefix,$to)=@_;
    $prefix ||="";
    $to=$from unless $to;

    fatal "Not a Build::Option::Set"
      unless $options->isa("Build::Option::Set");

    my $vars=$options->render($prefix);

    # ::GROUP:: and ::PACKAGE:: expansion
    my %expansion = (
        group   => (getPackageGroup($unit) || $unit),
        package => (isPackage($unit) ? $unit : "NOT_A_PACKAGE"),
    );
    $vars =~ s/::([A-Z]+)::/uc($expansion{lc($1)})/ge;

    return writeBuildVarsFile($vars."\n",
                              "$to/$makename.".$ufid->toString(1).".vars");
}

#------------------------------------------------------------------------------

# Determine whether or not a makefile needs rebuilding
sub makefileNeedsRebuild ($$$) {
    my ($pkg,$uplid,$makefile)=@_;

    my $dir=$root->getPackageLocation($pkg);

    $pkg=getCachedPackage($pkg);
    my @comps = map { getCachedComponent ($_) } $pkg->getMembers();
    my @files=map {
        $dir.$FS.$_.".h",
        $dir.$FS.$_.".".$_->getLanguage(),
        ($opts{express}?():$dir.$FS.$_.".t.".$_->getLanguage()),
    } @comps;

    my $memfile=$dir.$FS.PACKAGE_META_SUBDIR.$FS.$pkg.MEMFILE_EXTENSION;
    my $depfile=$dir.$FS.PACKAGE_META_SUBDIR.$FS.$pkg.DEPFILE_EXTENSION;
    my $reffile=$dir.$FS.PACKAGE_META_SUBDIR.$FS.$pkg.REFFILE_EXTENSION;
    my $dumfile=$dir.$FS.PACKAGE_META_SUBDIR.$FS.$pkg.DUMFILE_EXTENSION;
    unshift @files,$0,$memfile,$depfile; #most likely to change
    push @files,$dumfile if -f $dumfile;
    push @files,$reffile if -f $reffile;
    push @files,values(%INC); #least likely to change

    debug2("checking $pkg/$uplid/$makefile timestamp against @files")
      if (Util::Message::get_debug() >= 2);
    my $makefilePath="$dir/$uplid/$makefile";
    my $result=is_newer($makefilePath,@files);
    if ($result<0) {
        fatal "dependant file $files[-$result-1] does not exist";
    } elsif ($result>0) {
        verbose("$pkg makefile is older than $files[$result-1]");
    } elsif ($result and $result==0) {
        verbose("$pkg makefile does not exist");
        $result=1; # from "0 but true"
    }

    if(!$result) {
        if(!is_complete_makefile($makefilePath)) {
            verbose("$pkg makefile is incomplete, will rebuild");
            $result=@files+1;
        }
        else {
            verbose("$pkg makefile is complete and up-to-date");
        }
    }

    return $result;
}

sub is_complete_makefile($) {
    my ($filename)=@_;
    my $MKF=new IO::File;
    retry_open($MKF, "<$filename")
        or return 0;

    $MKF->seek(-2 * length($EOF_MARKER), 2); # 2=SEEK_END

    my $result=0;
    while(<$MKF>) {
        if($_ eq $EOF_MARKER) {
            $result=1;
            last;
        }
    }
    close($MKF);

    return $result;
}

# mkDotOCompCmd - make cmd to compile .o
sub mkDotOCompCmd($;$$$) {
    my ($impl,$flags,$prefix,$flagType) = @_;
    my $retstr;
    $flags=($flags)?"$flags ":"";
    $prefix ||= "";
    $flagType ||= "COMPONENT_";

    if ($impl =~ /\.c$/) {
        $retstr = "\$(${prefix}CC) \$(${flagType}BDEBUILD_CFLAGS) $flags".
          "\$(${prefix}OBJ_OPT) $impl\n\n";
    } elsif ($impl =~ /\.f$/) {
        $retstr = "\$(${prefix}F77) \$(${flagType}BDEBUILD_F77FLAGS) $flags".
          "\$(${prefix}OBJ_OPT) $impl\n\n";
    } elsif ($impl =~ /\.cpp$/ || $impl =~ /\.h$/) {
        $retstr = "\$(${prefix}CXX) \$(${flagType}BDEBUILD_CXXFLAGS) $flags".
          "\$(${prefix}OBJ_OPT) $impl\n\n";
    } else {
        fatal "Bad component implementation file: '$impl'";
    }
    return "\n\t".$retstr;
}

# mkDotOAssyCmd - make cmd to compile .o from .s
sub mkDotOAssyCmd($) {
    my ($impl) = @_;
    my $retstr;

    if ($impl =~ /\.s$/o) {
        $retstr = "\n\t\$(AS) \$(ASFLAGS) -o \"\$@\" $impl\n\n";
    } else {
        fatal "Bad assembly file: '$impl'";
    }
    return $retstr;
}

# Extracts list of files matching the specified regex. Used for non-compliant
# makefile generation. [[<<<TODO: May also be useful for m_ makefiles]]
sub scanPackageDirectory ($$;$) {
    my ($package,$subdir,$regex)=@_;
    ($regex=$subdir,$subdir=undef) unless defined $regex;

    my $dir=$root->getPackageLocation($package);
    $dir.=$FS.$subdir if $subdir;
    opendir(DIR,$dir) or do {
        warning "Can't open $dir: $!";
        return ();
    };
    my @files = sort grep { /$regex/ && -f "$dir/$_" } readdir(DIR);
    closedir DIR;

    return @files;
}

#------------------------------------------------------------------------------

# return DCL defines for library builds (only Windows DLL defines a value)
sub getLibBuildDefines ($;@) {
    my ($group,@deps)=@_;

    return uc "-D${group}_DCL=\$(${group}_DCL_EXPORT) ".(
             join ' ',map { "-D${_}_DCL=\$(${_}_DCL_IMPORT)" } (@deps)
           );
}

# return DCL defines for binary executable builds (see above)
sub getExeBuildDefines ($;@) {
    my ($group,@deps)=@_;

    return uc join ' ',map { "-D${_}_DCL=\$(${_}_DCL_IMPORT)" } ($group,@deps);
}

#------------------------------------------------------------------------------

sub _gather_output ($$) {
    my ($cmd,$logfile)=@_;
    my @cmd=(split /\s+/,$cmd);
    map {
        s/^(['"])(.*)(\1)$/$2/o
    } @cmd; #strip shell quotes as we go direct

    if ($opts{nolog}) {
        if ($opts{noretry}) {
            system(@cmd);
        } else {
            retry_system(@cmd);
        }
    } else {
        my $LOG=new IO::File;

        retry_open($LOG,">$logfile") || fatal "Cannot create makelog as $logfile: $!";

        my ($rdfh,$wrfh)=(new IO::Handle,new IO::Handle);
        my $pid=retry_open3($rdfh,$wrfh,$rdfh,@cmd);
        close $wrfh;

        while (my $line=<$rdfh>) {
            print $line;
            print $LOG $line if $LOG;
        }

        # clean up
        waitpid $pid,0;
        close $LOG if defined($LOG);
    }

    # return exit status
    return $? >> 8;
}

# a 'null' build action for phony targets within tool
sub nopPackageTarget ($$$$$) { return 0; }

{
    my $useGNUMakeOnWindows=-1;
# build a given package makefile target
    sub buildPackageTarget($$$$$) {
        my ($pkg, $what, $uplid, $ufid, $jobs) = @_;

        my $comp=undef;
        if (isComponent($pkg)) {
            $comp=$pkg;
            $pkg=getComponentPackage($comp);
            alert(qq[Building component $comp (].($ufid->toString(1)).
                        qq[ "make $what")...]);
            $what="$what.$comp";
        } elsif (getCachedPackage($pkg)->isPrebuilt) {
            debug "$pkg is prebuilt-legacy, skipping";
            return 0;
        } else {
            alert(qq[Building package $pkg (].($ufid->toString(1)).
                        qq[ "make $what")...]);
        }

        my $makefile = MAKEFILE_NAME.".".$ufid->toString(1);
        my $mklog = "make.$what.$pkg.".$ufid->toString(1).".log";

        my $dir = $root->getPackageLocation($pkg);
        retry_chdir($dir) or fatal "Cannot chdir to '$dir': $!";
        retry_chdir($uplid) or fatal "Cannot chdir to '$dir${FS}$uplid': $!";
        $dir .= "${FS}$uplid";

# generate actual make command and run it
        my $make_cmd;
        if ($opts{clearmake}) {
            $make_cmd = "clearmake -C gnu -e";
            $make_cmd .= ($opts{silent}) ? " -s":"";
            $make_cmd .= ($opts{keepgoing}) ? " -k":"";
            $make_cmd .= " -J $jobs";
        }
        elsif ($uplid->platform() eq "win") {
            # static check, done once
            if ($useGNUMakeOnWindows==-1) {
                my $makeVer=`make -v`||"";
                if (!$? && $makeVer=~/GNU Make ([0-9.]+)/ && $1>=3.81) {
                    message "Using GNU make version $1, allowing parallel builds";
                    $useGNUMakeOnWindows=1;
                }
                else {
                    message "Using nmake, no parallel builds";
                    $useGNUMakeOnWindows=0;
                }
            }

            if (1 == $useGNUMakeOnWindows) {
                $make_cmd="make -e ";
                $make_cmd .= ($opts{silent}) ? " --silent":"";
                $make_cmd .= ($opts{keepgoing}) ? " -k":"";
                $make_cmd .= ($jobs==1) ?
                    " -j1" : " -j$jobs";
            }
            else {
                $make_cmd = "nmake /nologo /e";
                $make_cmd .= ($opts{silent}) ? " /s":"";
                $make_cmd .= ($opts{keepgoing}) ? " /k":"";
            }
        } else {
            my $mk=($uplid->platform() =~ "^(cygwin|darwin)")?"make":"gmake";
            $make_cmd = ($jobs==1) ?
                "$mk -e -j1" : "$mk -e -j$jobs";
            $make_cmd .= ($opts{silent}) ? " --silent":"";
            $make_cmd .= ($opts{keepgoing}) ? " -k":"";

#pathalogical retry
            $make_cmd = $RETRY_MAKEPROG.$make_cmd unless $opts{noretry};
        }

        $make_cmd .= " -f $makefile $what";

        if ($opts{silent} and $what eq "test") {
            #$make_cmd .= " ALLTEST_VERBOSE=-q";
            $make_cmd .= " ALLTEST_VERBOSE=-f";
        }

        print Dumper(\%ENV), "\n" if (Util::Message::get_debug() >= 2);

        debug("$pkg $what: $make_cmd");

        my $rc=_gather_output($make_cmd,$mklog);

        my $msg = "$what failed for $pkg when running $make_cmd ".
            "(see $dir${FS}$mklog)\n";  # DO NOT CHANGE - RE-MATCHED IN SLAVE

        if ($rc && $opts{keepgoing}) {
            if ($what =~ /test/) {
                error $msg;
            }
            else {
                fatal $msg;
            }
        }

        return $rc;
    }
}

#------------------------------------------------------------------------------

sub makeMakefilePreamble ($$$$$$$) {
    my ($fh,$package,$makename,$ufid,$link_ufid,$test_ufid,$root)=@_;

    fatal "Not a package: $package" unless isPackage($package);
    fatal "Bad ufid: $ufid" unless $ufid->isa("BDE::Build::Ufid");
    fatal "Bad link ufid: $ufid" unless $link_ufid->isa("BDE::Build::Ufid");
    fatal "Bad test ufid: $ufid" unless $test_ufid->isa("BDE::Build::Ufid");

    $package=getCachedPackage($package);
    my $group=$package->getGroup() || $package;

    # DRQS 12785861: include bbmkvars.mk and libmacros.mk
    unless($^O=~/MSWin/ || ($^O=~/solaris/ && `uname -p`=~/i386/)) {
        # MS NMAKE doesn't have a "nofail" include syntax that
        # I can find quickly, and these files don't make sense
        # on Windows anyhow
        if ($^O=~/linux/) {
            # avoid makefile forwarding proxy files on Linux
            print $fh "MKINCL?=/bbsrc/source/proot/mk/\n";
        }
        else {
            print $fh "MKINCL?=/bbsrc/mkincludes/\n";
        }
        print $fh "-include \$(MKINCL)bbmkvars.mk\n";
        print $fh "-include \$(LIBMACROS_MK)\n\n";
    }

    print $fh "include $makename.".$ufid->toString(1).".vars\n";
    if ($test_ufid ne $ufid) {
        print $fh "include $makename.".$test_ufid->toString(1).".vars\n";
    }

    # In case default.opts is out of date
    print $fh "SWITCHCHAR?=-\n";

    print $fh "\n";
    print $fh ".SUFFIXES:\n\n";

    print $fh "UPLID            = $uplid\n";
    print $fh "UFID             = ",$ufid->toString(1),"\n";
    print $fh "LIBUFID          = $ufid\n";
    print $fh "LINK_UFID        = ",$link_ufid->toString(1),"\n";
    print $fh "LINK_LIBUFID     = $link_ufid\n";
    print $fh "FORCED_VIEW      = $1\n"
      if ($opts{where} && $opts{where} =~ m!^(/view/[^/]+)/bbcm/!);

    # TEST_UFID & TEST_LIBUFID come from test varsfile, if one was configured

    print $fh "GROUP            = $group\n" if $group ne $package;
    print $fh "PACKAGE          = $package\n";
    print $fh "ROOT_LOCN        = $root\n";
    if (my $loc=$root->getGroupsSubdir()) {
        print $fh "BASE_LOCN        = \$(ROOT_LOCN)${FS}$loc\n",
    }
    if (my $loc=$root->getAdaptersSubdir()) {
        print $fh "ADAPTER_LOCN     = \$(ROOT_LOCN)${FS}$loc\n";
    }
    if (my $loc=$root->getWrappersSubdir()) {
        print $fh "WRAPPER_LOCN     = \$(ROOT_LOCN)${FS}$loc\n";
    }
    if (my $loc=$root->getApplicationsSubdir()) {
        print $fh "APPLICATION_LOCN = \$(ROOT_LOCN)${FS}$loc\n";
    }
    if (my $loc=$root->getFunctionsSubdir()) {
        print $fh "FUNCTION_LOCN    = \$(ROOT_LOCN)${FS}$loc\n";
    }
    if (my $loc=$root->getDepartmentsSubdir()) {
        print $fh "DEPARTMENT_LOCN  = \$(ROOT_LOCN)${FS}$loc\n";
    }
    if (my $loc=$root->getEnterprisesSubdir()) {
        print $fh "ENTERPRISE_LOCN  = \$(ROOT_LOCN)${FS}$loc\n";
    }
    print $fh "\n";
}

sub makeUnitPathMacros ($$;$) {
    my($root,$unit,$mkf) = @_;
    my $unit_tag         = getUnitMacro($unit);
    my($locn,$rootlocn)  = isGroup($unit)
      ? ($root->getGroupLocation($unit),   $root->getGroupRoot($unit))
      : ($root->getPackageLocation($unit), $root->getPackageRoot($unit));
    $mkf ||= [];
    push @$mkf, sprintf("%-17s= $locn\n",    $unit_tag."_LOCN");
    push @$mkf, sprintf("%-17s= $rootlocn\n",$unit_tag."_ROOTLOCN");
    return $mkf;
}

sub makePackageDependencyMacros ($$$;$$) {
    my ($fh,$package,$link_ufid,$local,$depend_on_groups)=@_;

    fatal "Not a package: $package" unless isPackage($package);
    $package=getCachedPackage($package);

    my $group=$package->getGroup() || $package;
    my @groups=getAllGroupDependencies($group); #UORs = groups + isolated pkgs

    my $PKG=getUnitMacro($package);

    foreach (@groups,$group,(($group ne $package)?$package:())) {
        unless (isGroupedPackage $_) {
            next if getCachedGroupOrIsolatedPackage($_)->isPrebuilt;
        }
        print $fh @{makeUnitPathMacros($root,$_)};
    }
    print $fh "\n";

    print $fh sprintf("%-17s","${PKG}_BLOC")."= ".($local
        ? "." : "\$(${PKG}_LOCN)${FS}\$(UPLID)")."\n";
    print $fh "\n";

    if (@groups or ($package->getGroup() and $depend_on_groups)) {
        @groups=($group,@groups) if $depend_on_groups;
        @groups=map {
            getCachedGroupOrIsolatedPackage($_)
        } reverse getBuildOrder(@groups);

        # split into things we build, things prebuilt, and discard meta-only
        # packages that aren't prebuilt legacy

        # filter dependency list to only entities we actually manage
        my @builtgroups=grep {
            (isGroup($_) and not $_->isPrebuilt)
              or (isPackage($_) and not $_->isPrebuilt)
        } @groups;

        print $fh "#=== Group Dependencies\n\n";
        # include path
        print $fh "GRP_INCLUDES = ",join(" \\\n               ", map {
            "\$(SWITCHCHAR)I\$(".uc($_)."_ROOTLOCN)${FS}include${FS}${_}${FS}".
              "\$(UPLID)${FS}\$(LINK_UFID) " #bde_build.pl ufid/uplid here
        } @builtgroups),"\n";

        # regions support
        my %reggroups;
        my @reggroups;
        foreach my $group (@builtgroups) {
            if (isGroup $group) {
                if (my @regions=$group->getRegions) { #<<getRegionBuildOrder
                    $reggroups{$_}=$group foreach @regions;
                    push @reggroups,@regions;
                } else {
                    $reggroups{$group}=$group;
                    push @reggroups,$group;
                }
            } else {
                $reggroups{$group}=$group;
                push @reggroups,$group;
            }
        }
        @builtgroups=@reggroups;

        # library flags for link line
        my %seen_locations;
        my @grp_lib_locations =
            grep {!$seen_locations{$_}++}
                 ($root->getRootLocation(), split $PS, $root->getPath());
        print $fh "GRP_LIBS     = ",join(" \\\n               ", map {
            "\$(LIBPATH_FLAG)".$_.
              "${FS}lib${FS}\$(UPLID) "
          } @grp_lib_locations)," \\\n               ",
            join(" \\\n               ", map {
                getLinkName("\$(LIB_FLAG)\$(LINK_LIB_PREFIX)",$_,"\$(LIBUFID)",
                         "\$(LINK_LIB_EXT)","has_regions")
          } @builtgroups);
        if ($link_ufid->toString(1)=~/shr/o) {
            print $fh " \$(LIBRUNPATH_FLAG)".join($PS, map {
                "\$(".uc($reggroups{$_})."_ROOTLOCN)${FS}lib${FS}\$(UPLID)"
            } reverse @builtgroups);
            ##<<<TODO support shared libs of legacy libs?
            print $fh "${PS}${FS}lib${PS}${FS}usr${FS}lib${PS}." if $depend_on_groups;
        }
        print $fh "\n";

        # library files for dependencies
        print $fh "GRP_DEPLIBS  = ",join(" \\\n               ", map {
            "\$(".uc($reggroups{$_})."_ROOTLOCN)${FS}lib${FS}\$(UPLID)${FS}".
              "\$(LIB_PREFIX)${_}.\$(LINK_LIBUFID)\$(LIB_EXT)"
          } @builtgroups),"\n";
        print $fh "\n";

        # the list of 'prebuilt' libraries as simple -l rules
        # NOTE: Do *NOT* include intbasic, since it's in the NS-suite and
        # not named intbasic
        my @prebuilt_libs=grep { $_->isPrebuilt() && !/^intbasic$/ } @groups;

        print $fh getUnitMacro($_)."_LIB=".
          getLinkName("\$(LIB_FLAG)\$(LINK_LIB_PREFIX)",$_,"\$(LIBUFID)",
                   "\$(LINK_LIB_EXT)")."\n"
                     foreach @prebuilt_libs;
        # we need to reverse these for link line to be correct
        print $fh "PREBUILT_LIBS= ",join(" ", map {
            "\$(".getUnitMacro($_)."_LIB)";
        } reverse getBuildOrder(@prebuilt_libs)),"\n";
        print $fh "\n";
    }

    if (isGroupedPackage($package) and not $depend_on_groups) {
        # depend on *internal* packages for included headers and link libraries

        my @packages=$package?(getAllInternalPackageDependencies($package)):();
        return unless @packages;

        @packages=map {
            getCachedPackage($_)
        } reverse getBuildOrder(@packages);

        print $fh "#=== Package Dependencies\n\n";

        # include path
        print $fh "PKG_INCLUDES = ",join(" \\\n               ", map {
            "\$(SWITCHCHAR)I\$(".uc(getPackageGroup($_))."_LOCN)${FS}${_}${FS}include".
                     "${FS}\$(UPLID)${FS}\$(LINK_UFID)"
        } @packages),"\n";

        # library flags for link line
        print $fh "PKG_LIBS     = ",join(" \\\n               ", map {
            "\$(LIBPATH_FLAG)\$(".uc(getPackageGroup($_))."_LOCN)".
            "${FS}${_}${FS}lib${FS}\$(UPLID) "
        } @packages)," \\\n               ",
          join(" \\\n               ", map {
            "\$(LIB_FLAG)\$(LINK_LIB_PREFIX)".basename($_). # FIXME libname
              ".\$(LINK_LIBUFID)\$(LINK_LIB_EXT)"
        } @packages);

        if ($link_ufid->toString(1)=~/shr/o) {
            print $fh " \$(LIBRUNPATH_FLAG)".join($PS, map {
                "\$(".uc(getPackageGroup($_))."_LOCN)${FS}${_}${FS}\$(UPLID)"
            } reverse @packages);

            #<<<TODO: support shared libs of legacy libs?
            print $fh "${PS}${FS}lib${PS}${FS}usr${FS}lib${PS}."
        }
        print $fh "\n";

        # library files for dependencies
        print $fh "PKG_DEPLIBS  = ",join(" \\\n               ", map {
            "\$(".uc(getPackageGroup($_))."_LOCN)${FS}${_}${FS}lib${FS}".
              "\$(UPLID)${FS}\$(LIB_PREFIX)${_}.\$(LINK_LIBUFID)\$(LIB_EXT)"
        } @packages),"\n";
        print $fh "\n";
    }
}

sub makeMakefileBuildFlags ($$) {
    my ($fh,$package)=@_;

    print $fh "#=== Build Flags\n\n";

    #<<<TODO: move all of these into default.opts
    print $fh "BDE_CINCLUDES = \$(SWITCHCHAR)I. \$(BDE_CINCLUDE) ".
                             "\$(PKG_INCLUDES) \$(GRP_INCLUDES)\n";
    print $fh "BDE_CXXINCLUDES = \$(SWITCHCHAR)I. \$(BDE_CXXINCLUDE) ".
                             "\$(PKG_INCLUDES) \$(GRP_INCLUDES)\n";
    print $fh "BDE_F77INCLUDES = \$(SWITCHCHAR)I. \$(BDE_F77INCLUDE) ".
                             "\$(PKG_INCLUDES) \$(GRP_INCLUDES)\n";

    if (isCompliant($package)) {
        print $fh "BDE_LIBS     = \$(PKG_LIBS) \$(GRP_LIBS)\n";
        print $fh "BDE_DEPLIBS  = \$(PKG_DEPLIBS) \$(GRP_DEPLIBS)\n";
    } else {
        print $fh "THIS_LIB     = \$(LIBPATH_FLAG). ".
          "\$(LIB_FLAG)\$(LINK_LIB_PREFIX)".basename($package). # FIXME libname
          ".\$(LINK_LIBUFID)\$(LINK_LIB_EXT)\n";
        print $fh "THIS_DEPLIB  = ".
          "\$(LIB_PREFIX)".basename($package). # FIXME libname
          ".\$(LINK_LIBUFID)\$(LIB_EXT)\n";
        print $fh "BDE_LIBS     = \$(THIS_LIB) \$(PKG_LIBS) \$(GRP_LIBS)\n";
        print $fh "BDE_DEPLIBS  = \$(THIS_DEPLIB) ".
                                 "\$(PKG_DEPLIBS) \$(GRP_DEPLIBS)\n";
    }

    # CFLAGS, CXXFLAGS, F77FLAGS, and LDFLAGS moved to default.opts
    # as BDEBUILD_{CFLAGS,CXXFLAGS,F77FLAGS,LDFLAGS}
    print $fh "\n";
}

sub getComponentDependencyVar ($$$) {
    my ($comp,$link_ufid,$depend_on_groups)=@_;
    fatal "Not a component: $comp" unless isComponent($comp);
    fatal "Bad link ufid: $link_ufid" unless
      $link_ufid->isa("BDE::Build::Ufid");
    $comp=getCachedComponent($comp);
    my (@compdeps,@filedeps);

    if(!defined $depend_on_groups) {
        $depend_on_groups = "";
    }

    my $varname=    uc($comp)
               ."_".uc($link_ufid)
               ."_".uc($depend_on_groups)
               ."_DEPS";

    my $depline="$varname=";

    my $depSep = " \\\n               ";

    if ($depend_on_groups) {
        @compdeps=getAllComponentDependencies($comp);
        @filedeps=getAllComponentFileDependencies($comp);

        # @compdeps and @filedeps now contain all includes, whether in the same
        # unit of release as the component, or not
    } else {
        # includes in same package
        my $PKG=uc $comp->getPackage();
        my $package=$comp->getComponentPackage();
        my $group=$comp->getComponentGroup(); #undef if isolated package

        # We need to include "local" headers from this package which the test
        # driver might (illegally) include without them being in the actual
        # component's dependencies.  Otherwise, we wind up with intermittent
        # 'make' failures when the test driver starts to build before the
        # depended-upon local headers are all done copying over.
        my @localTestOnlyDependencies = grep {/^${package}_/} getTestOnlyDependencies($comp);

        $depline.=join($depSep, map {
            "\$(${PKG}_BLOC)${FS}$_.h"
        } (getAllInternalComponentDependencies($comp,1), @localTestOnlyDependencies));

        @compdeps=getAllExternalComponentDependencies($comp);
        @filedeps=getAllComponentFileDependencies($comp);

        # includes in other packages in same group
        if ($group) {
            # 1 - components => compliant packages
            my @comps_in_group=grep { /^$group/ } @compdeps;
            if (@comps_in_group) {
                $depline.=$depSep.join($depSep,map {
                    getGopLocnMacro(getComponentPackage($_)).
                      "${FS}include${FS}\$(UPLID)${FS}\$(LINK_UFID)${FS}${_}.h"
                  } @comps_in_group);
            }
            my %comps_in_group=map { $_ => 1 } @comps_in_group;
            @compdeps = grep { ! exists $comps_in_group{$_} } @compdeps;

            # 2 - files => non-compliant packages
            my @files_in_group=grep {
                $_->getGroup() and ($_->getGroup() eq $group)
            } @filedeps;
            if (@files_in_group) {
                $depline.=$depSep.join($depSep,map {
                    getGopLocnMacro($_->getPackage()).
                      "${FS}include${FS}\$(UPLID)${FS}\$(LINK_UFID)${FS}"
                        .$_->getPathname()
                } @files_in_group);
            }
            my %files_in_group=map { $_ => 1 } @files_in_group;
            @filedeps = grep { ! exists $files_in_group{$_} } @filedeps;
        }

        # @compdeps and @filedeps now contain only includes outside the
        # target unit of release (to which the component belongs)
    }

    # depend on the group include dir for dependant groups - components
    my @comps_outside_group=@compdeps;
    if (@comps_outside_group) {
        $depline.=$depSep.join($depSep,map {
            "\$(".uc(getComponentGroup($_) ||
                     getComponentPackage($_))."_ROOTLOCN)${FS}include${FS}".
                       (getComponentGroup($_) || getComponentPackage($_)).
                         "${FS}\$(UPLID)${FS}\$(LINK_UFID)${FS}${_}.h"
                     } @comps_outside_group);
    }

    # depend on the group include dir for dependant groups - files
    my @files_outside_group=@filedeps;
    if (@files_outside_group) {
        $depline.=$depSep.join($depSep,map {
            "\$(".uc($_->getGroup() || $_->getPackage())."_ROOTLOCN)".
              "${FS}include${FS}".
                ($_->getGroup() || $_->getPackage()).
                  "${FS}\$(UPLID)${FS}\$(LINK_UFID)${FS}"
                    .$_->getPathname()
                } grep { $_->getPackage() } @files_outside_group);
    }

    # if clearmake is in effect, we need to break up overly long lines
    # however, if clearmake isn't in effect, we should not do this, since
    # nmake does not support +=
    if($opts{clearmake}) {
        $depline=~s/(?:(^[A-Z](?:.*\n){1,100}))(?:^\s+((?:.*\n){1,100}))/$1\n$varname+=$2/gm;
        $depline=~s/\+=\s+/\+=/g;
        $depline=~s/\s+$/\n/gm;
    }

    return ($varname,$depline);
}

sub makeComponentObjectRule ($$$$$) {
    my ($fh,$comp,$link_ufid,$depend_on_groups,$libdefs)=@_;
    my $intf=$comp.".h";
    my $impl=$comp.".".getCachedComponent($comp)->getLanguage();
    my ($depvarname,$depline)=getComponentDependencyVar($comp,$link_ufid,$depend_on_groups);
    my $pkg=getComponentPackage($comp);
    my $PKG=getUnitMacro($pkg);

    print $fh "$depline\n\n";

    print $fh "\$(${PKG}_BLOC)${FS}$comp.\$(UFID)\$(OBJ_EXT): ".
      "\$(${PKG}_BLOC)${FS}$impl \$(${PKG}_BLOC)${FS}$intf \$($depvarname) ";
    print $fh mkDotOCompCmd("\$(${PKG}_BLOC)${FS}$impl",$libdefs);
    print $fh "build.$comp: \$(${PKG}_BLOC)${FS}$comp.\$(UFID)\$(OBJ_EXT)\n\n";
    print $fh "$comp.build: \$(${PKG}_BLOC)${FS}$comp.\$(UFID)\$(OBJ_EXT)\n\n";
}

{
my %cachedTestDependents;

sub makeTestDriverRule ($$$$$$$\@\@) {
    my ($fh,$comp,$prefix,$link_ufid,$depend_on_groups,$exedefs,$finder,$objdeps,
        $extraobjs)=@_;
    $comp=getCachedComponent($comp);
    my $intf=$comp.".h";
    my $impl=$comp.".".$comp->getLanguage();
    my $tst=$comp.".t.".$comp->getLanguage();
    my ($depvarname,$depline)=getComponentDependencyVar($comp,$link_ufid,$depend_on_groups);
    my $PKG=getUnitMacro($comp->getPackage());
    my $package=$comp->getComponentPackage();
    my $group=$comp->getComponentGroup(); # undef if isolated package
    my @deps;

    my @objdeps = @$objdeps;
    push @objdeps, @$extraobjs if $extraobjs and @$extraobjs;

    my @testDriverComponentDeps = getTestOnlyDependencies($comp);

    my %seenDependants = map {$_ => undef} @testDriverComponentDeps;
    my %checkedDependants;

    while (my @search=grep !exists $checkedDependants{$_},@testDriverComponentDeps) {
        foreach my $component(@search) {
            $checkedDependants{$component} = undef;

            my @newDeps;
            # Use cached dependencies if we've already gotten them.
            if (exists $cachedTestDependents{$component}) {
                debug "$tst: using cached dependencies for $component";
                @newDeps = @{$cachedTestDependents{$component}};
            }
            else {
                debug "$tst: getting dependencies for $component";

                my $component_obj = getCachedComponent($component);

                # Get interface-only dependencies!
                @newDeps = getAllComponentDependencies($component_obj, 0);
                @newDeps = sort @newDeps;
                $cachedTestDependents{$component} = [@newDeps];
            }

            # Add previously unseen dependencies to our test driver's dependencies.
            push @testDriverComponentDeps, grep {!exists $seenDependants{$_}} @newDeps;
            $seenDependants{$_} = undef foreach @newDeps;
        }
    }

    # make it easier to find dependencies.
    @testDriverComponentDeps = sort @testDriverComponentDeps;

    if(@testDriverComponentDeps) {
        if($group) { # we're not an isolated package
            # stuff in my group
            push @deps, map {
                getGopLocnMacro(getComponentPackage($_)).
                    "${FS}include${FS}\$(UPLID)${FS}".
                    "\$(LINK_UFID)${FS}${_}.h"
            }
            grep /^$group/,
                 @testDriverComponentDeps;
            # remove the things we've already dealt with
            @testDriverComponentDeps=grep !/^$group/,@testDriverComponentDeps;
        }

        # if any elements remain, either outside of this group
        # or outside of this non-compliant package, we have to
        # access them via the more universal include location
        push @deps,map {
            "\$(".uc(getComponentGroup($_) ||
                        getComponentPackage($_))."_ROOTLOCN)${FS}include${FS}".
                (getComponentGroup($_) || getComponentPackage($_)).
                "${FS}\$(UPLID)${FS}\$(LINK_UFID)${FS}${_}.h"
        } @testDriverComponentDeps;
    }

    # test driver .o
    print $fh "\$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID)\$(OBJ_EXT): ".
      "\$(${PKG}_BLOC)${FS}$tst \$(${PKG}_BLOC)${FS}$intf \$($depvarname)";

    if(@deps) {
        # I'll save you the perlvar lookup - this is the array interpolation separator
        local $"= "  \\\n                 ";
        print $fh "  \\\n              @deps";
    }

    print $fh mkDotOCompCmd("\$(${PKG}_BLOC)${FS}$tst",$exedefs,$prefix,"TESTDRIVER_");

    # test driver executable - dependency line
    print $fh "\$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID)\$(EXE_EXT): ".
      "\$(${PKG}_BLOC)${FS}$comp.\$(UFID)\$(OBJ_EXT) ".
        "\$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID)\$(OBJ_EXT) ".
          "@objdeps ".
            "\$(BDE_DEPLIBS)\n";
    if ($uplid->platform() eq "win") {
        print $fh "\tcd \$(${PKG}_BLOC)\n";
        @objdeps=map {s/\$\(${PKG}_BLOC\)/./; $_} @objdeps;
    }
    # test driver executable - link line
    if ($impl =~ /\.c$/o) {
        print $fh "\t\$(${prefix}CLINK) ";
    } elsif ($impl =~ /\.cpp$/o) {
        print $fh "\t\$(${prefix}CXXLINK) ";
    } elsif ($impl =~ /\.f$/o) {
        print $fh "\t\$(${prefix}F77LINK) ";
    } else {
        fatal "Bad component file: '$impl'";
    }
    print $fh "\$(EXE_OPT) \$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID)\$(OBJ_EXT) ".
      "\$(${PKG}_BLOC)${FS}$comp.\$(UFID)\$(OBJ_EXT) ".
        "@objdeps ".
          "\$(TESTDRIVER_BDEBUILD_LDFLAGS)\n\n";
}
} # scope for %recursedDependents

sub makeApplicationMainRule ($$$$$$$$\@) {
    my ($fh,$pkg,$mainsrc,$mainexe,$prefix,$link_ufid,$depend_on_groups,$exedefs,$extraobjs)
      =@_;
    my $PKG=getUnitMacro($pkg);

    my $leafname=$mainsrc; $leafname=~s/\.\w+$//;
    my $depline="\$(INC_FILES) \$(${PKG}_BLOC)${FS}$mainsrc";
    my @extraobjs = @$extraobjs if defined $extraobjs;

    print $fh "#=== Application Main (${prefix}UFID)\n\n";

    print $fh "\$(${PKG}_BLOC)${FS}$leafname.\$(${prefix}UFID)\$(OBJ_EXT): $depline";
    # for now, use COMPONENT_ variables
    print $fh mkDotOCompCmd("\$(${PKG}_BLOC)${FS}$mainsrc",$exedefs,$prefix);

    # .exe
    ## dependency line
    print $fh "\$(${PKG}_BLOC)${FS}$leafname.\$(${prefix}UFID)\$(EXE_EXT): ".
      "\$(${PKG}_BLOC)${FS}$leafname.\$(${prefix}UFID)\$(OBJ_EXT) ".
        "\$(OBJS) @extraobjs \$(BDE_DEPLIBS)\n";
    ## link line: C++ only
    print $fh "\t\$(${prefix}CXXLINK) \$(EXE_OPT) ".
      "$leafname.\$(${prefix}UFID)\$(OBJ_EXT) ".
        "\$(OBJS) @extraobjs \$(COMPONENT_BDEBUILD_LDFLAGS)\n\n";

    if ($mainexe and $mainexe ne "$leafname.\$(${prefix}UFID)\$(EXE_EXT)") {
        print $fh "\$(${PKG}_BLOC)${FS}$mainexe:".
          " \$(${PKG}_BLOC)${FS}$leafname.\$(${prefix}UFID)\$(EXE_EXT)\n";
        print $fh "\t\$(RM) \"\$@\"\n";
        print $fh "\t\$(LINK) \"\$?\" \"\$@\"\n\n";
    }
}

sub makeTestRule ($$$;$) {
    my ($fh,$comp,$prefix,$concurrency)=@_;
    my $PKG=getUnitMacro(getComponentPackage $comp);

    print $fh "$comp: test.$comp.t.\$(${prefix}UFID)\n\n"; # very short rule
    print $fh "test.$comp: test.$comp.t.\$(${prefix}UFID)\n\n"; # short rule
    print $fh "$comp.test: test.$comp.t.\$(${prefix}UFID)\n\n"; # alt sh rule
    print $fh "test.$comp.t.\$(${prefix}UFID):".
              " build_test.$comp.\$(${prefix}UFID)\n";
    print $fh "\t\$(ALLTEST) ";
    if ((!defined $concurrency) || $concurrency==1) {
        print $fh "\$(ALLTEST_SERIAL) ";
    } else {
        print $fh "\$(ALLTEST_PARALLEL) ";
    }
    print $fh "-l \$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID).log ".
      "\$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID)\$(EXE_EXT)\n\n";

    print $fh "build_test.$comp: ".
      "build_test.$comp.\$(${prefix}UFID)\n\n";
    print $fh "$comp.build_test: ".
      "build_test.$comp.\$(${prefix}UFID)\n\n";
    print $fh "build_test.$comp.\$(${prefix}UFID): ".
      "\$(${PKG}_BLOC)${FS}$comp.t.\$(${prefix}UFID)\$(EXE_EXT)\n\n";
}

# look for and add extra files for full build list. Assign new sources
# to their components based on their basename.
sub calculateExtraSources ($$\@) {
    my ($options,$pkg,$build_list)=@_;

    my $extrasrcinfo={};

    if (my $extra_src_macro=$options->getValue("EXTRA_".uc($pkg)."_SRCS")) {
        message("* Found extra sources: $extra_src_macro");

        my %srcs=map { $_ => 1 } split / /,$extra_src_macro;
        SRC: foreach my $src (keys %srcs) {
            foreach my $comp (sort { length($b) <=> length ($a) } @$build_list) {
                debug2 "looking for association $comp <-> $src"
                  if (Util::Message::get_debug() >= 2);
                if ($src=~/^$comp/) {
                    $extrasrcinfo->{$comp} ||= [];
                    push @{$extrasrcinfo->{$comp}},$src;
                    delete $srcs{$src};
                    message("* Associated $src with $comp");
                    next SRC;
                }
            }
            fatal("Source file $src has no similarly named component");
        }
    }

    return $extrasrcinfo;
}

# find all possible sources of non-compliant headers
sub setFileSearchPathForNcPackage ($$;$) {
    my ($finder,$pkg,$extradir)=@_;
    $pkg=getCachedPackage($pkg);

    my @ncpackages=grep {isNonCompliant($_)} $pkg->getPackageDependants;
    my @depgroups=$pkg->isIsolated ? $pkg->getDependants()
      : getCachedGroup($pkg->getGroup)->getDependants;
    foreach (@depgroups) {
        if (isGroup $_) {
            push @ncpackages, getCachedGroup($_)->getNonCompliantMembers()
        } else {
            push @ncpackages, $_;
        }
    }

    if (@ncpackages) {
        @ncpackages = map { getCachedPackage($_) } @ncpackages;

        $finder->addPackageSearchPath($_) foreach @ncpackages;
    }

    $finder->addPackageSearchPath($pkg);
    $finder->addPackageSearchPath($pkg => basename($extradir)) if $extradir;

    return $finder;
}

#------------------------------------------------------------------------------

# Make makefile for $pkg. @pkg_deps determines include and lib dependencies.
sub makeMakefile ($@) {
    my ($pkg, $depend_on_groups, $ufid, $link_ufid, $test_ufid) = @_;
    my $PKG=getUnitMacro($pkg);
    $pkg=getCachedPackage($pkg);

    if ($pkg->isPrebuilt) {
        debug "$pkg is a prebuilt package, makefile generation skipped\n";
        return;
    } elsif ($pkg->isPrebuilt) {
        debug "$pkg is a prebuilt-legacy package, makefile generation skipped\n";
        return;
    }

    my @pkg_deps=getAllInternalPackageDependencies($pkg);

    my $dir = $root->getPackageLocation($pkg);

    my $makename = MAKEFILE_NAME;
    my $makefile = $makename.".".$ufid->toString(1);
    my $group = getPackageGroup($pkg); # may be undef
    my $unit = $group || (
        BDE::Util::Nomenclature::isIsolatedPackage($pkg) && $pkg
    ); #unit of release?
    my $UNIT = uc($unit);
    my $filefinder=new BDE::File::Finder($root);

    retry_dir($dir) or fatal "Cannot find '$dir': $!\n";

    # write variables for component object build
    my $options=constructOptions($pkg,$uplid,$ufid); #upgrades $uplid
    $dir .= "${FS}$uplid";
    unless (retry_dir $dir) {
        mkdirOrLink($dir,0777) or fatal "Cannot create $dir: $!\n";
    }
    writeOptions($pkg,$options,$makename,$dir);

    # if a separate test ufid was given, write variables file for that too
    if ($test_ufid ne $ufid) {
        writeOptions($pkg,$options,$makename,$dir,"TEST_");
    }

    if (isNonCompliant $pkg) {
        debug("Rebuilding ".$ufid->toString(1).
              " makefile for non-compliant package $pkg");
    } elsif ($opts{rebuild} and not $opts{uptodate}) {
        debug("Force rebuilding ".$ufid->toString(1).
              " makefile for package $pkg");
    } elsif ($opts{uptodate}) {
        message("Makefile ".$ufid->toString(1).
                " for package $pkg assumed up to date");
        return;
    } elsif (makefileNeedsRebuild($pkg,$uplid,$makefile)) {
        debug("Making ".$ufid->toString(1)." makefile for package $pkg ...");
    } else {
        message("Makefile ".$ufid->toString(1).
                " for package $pkg is up to date");
        return;
    }

    my $start_time=time;

    my @build_list;
    if (isNonCompliant $pkg) {
        # if package contains a non-word character, it's a nonstandard pkg
        # first see if members file contains a list of .c/.cpps/.f
        @build_list = $pkg->getMembers();
        @build_list = grep { /\.(c|cpp|f)$/ } @build_list;

        # if not, fall back to a directory scan
        unless (@build_list) {
            @build_list = scanPackageDirectory($pkg,'\.(c|cpp|f)?$');
        }

        #<<<TODO: in future this may need to get smarter about other kinds
        # of files, i.e. describing header files to install as well as
        # files that get built.
    } else {
        # otherwise, derive the component build order the usual way
        @build_list = $pkg->getMembers();
    }
    unless (@build_list) {
        warning("no components found for $pkg - generating no-op makefile");
        my $FMK=new IO::File;
        retry_open($FMK, "> $dir${FS}$makefile")
            or fatal "Cannot create $dir${FS}$makefile: $!\n";

        print $FMK <<'EMPTY_MAKEFILE' ;

# $pkg has no components - this is a special empty no-op makefile.

.PHONY: all test install install_library install_include \
        uninstall_library uninstall_include preprocess_package_include \
        install_package install_package_library install_package_include \
        uninstall_package uninstall_package_library uninstall_package_include\
        install_group install_group_library install_group_include \
        uninstall_group uninstall_group_library uninstall_group_include \
        lib clean cleancache realclean build_test \
        build_package_objects build_package_test_objects \
        build_package_library preprocess_package_include noop

all: test install

install: install_package install_group

install_library: install_package_library install_group_library

install_include: install_package_include install_group_include

uninstall: uninstall_package uninstall_group

uninstall_lib: uninstall_package_library uninstall_group_library

uninstall_include: uninstall_package_include uninstall_group_include

noop:

#--- Build Package

preprocess_package_include:

build:

build_package_library:

build_package_objects:

build_package_test_objects:

#--- Install Package

install_package: install_package_library install_package_include

install_package_include:


install_package_library:

#--- Uninstall Package

uninstall_package:

uninstall_package_include:

uninstall_package_library:

#--- Install (Package to) Group

install_group:

install_group_include:


install_group_library:

#--- Uninstall (Package from) Group

uninstall_group:

uninstall_group_include:

uninstall_group_library:

#--- Clean!

clean:

clean.using_relative_paths:

cleancache:

realclean:

cleandir:

cleanalldir:

#--- Tests and Checks

build_test:

test:

EMPTY_MAKEFILE

        return;
    }
    # look for extra source files
    my $extrasrcinfo = calculateExtraSources($options,$pkg,@build_list);

    #-------------------

    # write makefile...
    my $FMK=new IO::File;
    retry_open($FMK, "> $dir${FS}$makefile")
      or fatal "Cannot create $dir${FS}$makefile: $!\n";

    if ($pkg->isPrebuilt) {
        my $FMK=new IO::File;
        retry_open($FMK, "> $dir${FS}$makefile")
          or fatal "Cannot create $dir${FS}$makefile: $!\n";
        print $FMK "# This is a prebuilt package\n";
        close $FMK;
        return;
    }

    makeMakefilePreamble($FMK,$pkg,$makename,$ufid,$link_ufid,
                         $test_ufid,$root);
    makePackageDependencyMacros($FMK,$pkg,$link_ufid,0,$depend_on_groups);
    makeMakefileBuildFlags($FMK,$pkg);

## GPS:
    print $FMK "PACKAGE_LIB = \$(LIB_PREFIX)$pkg.\$(LIBUFID)\$(LIB_EXT)\n";
    print $FMK "PACKAGE_WLD = \$(LIB_PREFIX)$pkg.\$(LIBUFID).*\n";
    my $gop=$group || $pkg;
    print $FMK "GROUP_LIB   = \$(LIB_PREFIX)$gop.\$(LIBUFID)\$(LIB_EXT)\n";
    print $FMK "GROUP_WLD   = \$(LIB_PREFIX)$gop.\$(LIBUFID).*\n";

    print $FMK "\n";

    my $sep=" \\\n\t      ";
    my (@inc_files,@test_list);

    #rm command for source files copied to build dir, compliant-packages
    my $rmclbuildfiles="";
    #optional additional include directory to install, non-compliant packages
    my ($grpinstextradir,$pkginstextradir)=("","");
    # prefix for clean commands - use package when compliant, nothing when not
    my $clpkg=isCompliant($pkg)?$pkg:"";

    my ($hasrefs,$hasdums,$hasgrprefs,$hasgrpdums)=(0,0,0,0);
    # refs/dums
    if (-f $root->getPackageLocation($pkg).$FS.PACKAGE_META_SUBDIR.
        $FS.$pkg.REFFILE_EXTENSION) {
        $hasrefs=1;
        verbose "Found forward reference file for $pkg";
    }
    if (isGroupedPackage $pkg) {
        if (-f $root->getGroupLocation($group).$FS.GROUP_META_SUBDIR.
            $FS.$group.REFFILE_EXTENSION) {
            $hasgrprefs=1;
            verbose "Found group forward reference file for $pkg";
        }
    }
    if (-f $root->getPackageLocation($pkg).$FS.PACKAGE_META_SUBDIR.
        $FS.$pkg.DUMFILE_EXTENSION) {
        $hasdums=1;
        verbose "Found dummy symbol file for $pkg";
    }
    if (isGroupedPackage $pkg) {
        if (-f $root->getGroupLocation($group).$FS.GROUP_META_SUBDIR.
            $FS.$group.DUMFILE_EXTENSION) {
            $hasgrpdums=1;
            verbose "Found group dummy symbol file for $pkg";
        }
    }

    if (isCompliant $pkg) {
        # convert hash of array-refs to flat list, without extensions
        my @extra_o_list=();
        foreach my $extrasrcinfo (values %$extrasrcinfo) {
            push @extra_o_list, map { /^(.*)\.\w+$/ } @{$extrasrcinfo};
        };

        print $FMK "OBJS        = " .
          join($sep, map { "\$(${PKG}_BLOC)${FS}${_}.\$(UFID)\$(OBJ_EXT)" }
               (@build_list,@extra_o_list)) . "\n\n";
        @inc_files = map { "$_.h" } @build_list;
        print $FMK "INC_FILES   = " .
          join($sep, map { "\$(${PKG}_LOCN)${FS}${_}" } @inc_files) . "\n\n";
        print $FMK "BINC_FILES  = " .
          join($sep, map { "\$(${PKG}_BLOC)${FS}${_}" } @inc_files) . "\n\n";
        if ($test_ufid ne $ufid) {
            print $FMK "TESTS       = " .
              join($sep, map {
                  "\$(${PKG}_BLOC)${FS}${_}.t.\$(TEST_UFID)\$(EXE_EXT)"
              } @build_list)."\n\n";
            print $FMK "TEST_OBJS   = " .
              join($sep, map {
                  "\$(${PKG}_BLOC)${FS}${_}.t.\$(TEST_UFID)\$(OBJ_EXT)"
              } @build_list)."\n\n";
        } else {
            print $FMK "TESTS       = " .
              join($sep, map {
                  "\$(${PKG}_BLOC)${FS}${_}.t.\$(UFID)\$(EXE_EXT)"
              } @build_list)."\n\n";
            print $FMK "TEST_OBJS   = " .
              join($sep, map {
                  "\$(${PKG}_BLOC)${FS}${_}.t.\$(UFID)\$(OBJ_EXT)"
              } @build_list)."\n\n";
        }
        # a rule to delete build sources, for compliant packages only
        $rmclbuildfiles="\$(RM) \$(BINC_FILES) *.c*";
    } else {
        # look for extra include dir, if configured
        my $extradir="";
        if (my $subdir=$options->getValue($PKG."_DIR")) {
            $extradir="\$(${PKG}_LOCN)${FS}$subdir";
            debug "Found extra package directory: $extradir";

            my $tfs=$options->getValue("TRAILFS");

            $grpinstextradir=
                "\t\@-\$(MKDIR) \$(GRP_INC_DIR)${FS}$subdir\n".
                "\t\$(CPRECURSE) $extradir$tfs \$(GRP_INC_DIR)${FS}$subdir\n".
                "\t\@-\$(MKDIR) \$(GRP_INC_MDIR)${FS}$subdir\n".
                "\t\$(CPRECURSE) $extradir$tfs \$(GRP_INC_MDIR)${FS}$subdir";
            $pkginstextradir=
                "\t\@-\$(MKDIR) \$(PKG_INC_DIR)${FS}$subdir\n".
                "\t\$(CPRECURSE) $extradir$tfs \$(PKG_INC_DIR)${FS}$subdir\n";

            #for getAllFileDependencies
            setFileSearchPathForNcPackage($filefinder,$pkg,$subdir);
        } else {
            setFileSearchPathForNcPackage($filefinder,$pkg);
        }

        # we only care about group installs; we use headers from a non-
        # compliant package as-is; preprocessing is presumed to be handled
        # with macros in the package already, where applicable. This of
        # course might be changed if we find a compelling reason to need to
        # preprocess an external source package prior to bde_building it.

        # convert hash of array-refs to flat list, without extensions
        my @extra_src_list=();
        foreach my $srcinfo (values %$extrasrcinfo) {
            push @extra_src_list, @{$srcinfo};
        };

        print $FMK "OBJS        = " .
          join($sep, map {
              /^(.*)\.\w+$/ && "\$(${PKG}_BLOC)${FS}$1.\$(UFID)\$(OBJ_EXT)"
          } (@build_list,@extra_src_list)) . "\n\n";

        if (my $incfiles=$options->getValue("INSTALL_INC")) {
            @inc_files=split /\s+/,$incfiles;
        } else {
            # if no INSTALL_INC is found, assume .h in the top directory
            @inc_files=scanPackageDirectory($pkg,'\.h$');
        }
        print $FMK "INC_FILES   = " .
          join($sep, map {
              "\$(${PKG}_LOCN)${FS}$_"
          } @inc_files) . "\n\n";
        print $FMK "BINC_FILES = \$(INC_FILES)\n"; #install directly

        my @testlist=();
        if (my $tests=$options->getValue("TEST_CASES")) {
            @test_list = split /\s+/,$tests;
            message("Using explicit list of",
                    scalar(@test_list),"test cases for $pkg");
        } else {
        my $testdir=$options->getValue("TEST_SUBDIR") || 'test';
            @test_list = scanPackageDirectory($pkg,$testdir,'\.c(?:pp)?$');
            message("Scanned and found",scalar(@test_list),"tests for $pkg");
        }
        print $FMK "TESTS       = " .
         join($sep, map {
             /^(.*)\.c(?:pp)?$/ && "\$(${PKG}_BLOC)${FS}$1.\$(UFID)\$(EXE_EXT)"
         } @test_list)."\n\n";

        # non-compliant packages use source directly, no build source to clean
        $rmclbuildfiles="";
    }

    # default 'all' targets for direct invokation
    my $alltargets="";
    if (isApplication($pkg)) {
        $alltargets="test build_application";
        #<<<TODO: add install_application
    } else {
        $alltargets="test install";
    }

    my $mainsrc=$options->getValue("APPLICATION_MAIN");
    my $mainsrc_clean_rule_name = "";
    my $have_mainsrc_clean_rule = 0;

    if ($mainsrc) {
        message "Have mainsrc clean rule";
        $mainsrc_clean_rule_name = "clean.using_relative_paths.application_main_objects";
        $have_mainsrc_clean_rule = 1;
    }

    # destination installation paths for include files
    my @pkg_inc_files  = map { "\$(PKG_INC_DIR)${FS}$_" } @inc_files;
    my @grp_inc_files  = map { "\$(GRP_INC_DIR)${FS}$_" } @inc_files;
    my @grp_minc_files = map { "\$(GRP_INC_MDIR)${FS}$_" } @inc_files;

    #--------------------

    my $groupedpkg_rules="";
    if (isGroupedPackage $pkg) {
        $groupedpkg_rules=<<_GROUPEDPKG_RULES_END
#--- Install Package

install_package: install_package_library install_package_include

install_package_include: \$(PKG_INC_FILES)
$pkginstextradir

install_package_library: \$(PKG_LIB_DIR)${FS}\$(PACKAGE_LIB)

\$(PKG_LIB_DIR)${FS}\$(PACKAGE_LIB): \$(PACKAGE_LIB)
\t\@-\$(MKDIR) \$(PKG_LIB_DIR)
\t\$(F2DCP) \$(PACKAGE_WLD) \$(PKG_LIB_DIR)

#--- Uninstall Package

uninstall_package: uninstall_package_library uninstall_package_include

uninstall_package_include:
\t\@-\$(MKDIR) \$(PKG_INC_DIR)
\t\$(RM) \$(PKG_INC_FILES)

uninstall_package_library:
\t\@-\$(MKDIR) \$(PKG_LIB_DIR)
\t\$(RM) \$(PKG_LIB_DIR)${FS}\$(PACKAGE_LIB)
_GROUPEDPKG_RULES_END
    }

    #--------------------

    my $MAKEFILE=MAKEFILE_NAME;
    my $remove_subdirs = ($uplid->platform() ne "win")
      ? "\t\$(RMRECURSE) .${FS}*${FS}"
      #: "\t(FOR /D %i IN (*) DO RMDIR /S /Q %i) || echo done";
      : qq{\t}.q{perl -e "sub rmdir_s { foreach(@_) { next if /\\\\Makefile/; if(-d $$_) { rmdir_s($$_); print qq{Running rmdir $$_\n}; rmdir($$_); } else { print qq{Running unlink $$_\n}; unlink $$_ }}} foreach my $$item(@ARGV) {foreach(glob($$item)) {rmdir_s($$_)}}"}.qq{ .${FS}*${FS}\n};

    print $FMK <<_MAKE_TARGETS_END;
#=== Locations

PKG_LIB_DIR   = \$(${PKG}_LOCN)${FS}lib${FS}\$(UPLID)
PKG_INC_DIR   = \$(${PKG}_LOCN)${FS}include${FS}\$(UPLID)${FS}\$(UFID)
PKG_INC_FILES = @pkg_inc_files

GRP_LIB_DIR   = \$(${UNIT}_ROOTLOCN)${FS}lib${FS}\$(UPLID)
GRP_INC_MDIR  = \$(${UNIT}_ROOTLOCN)${FS}include${FS}${unit}
GRP_INC_DIR   = \$(GRP_INC_MDIR)${FS}\$(UPLID)${FS}\$(UFID)
GRP_INC_MFILES= @grp_minc_files
GRP_INC_FILES = @grp_inc_files

#=== Package Targets

.PHONY: all test install install_library install_include \\
        uninstall_library uninstall_include preprocess_package_include \\
        install_package install_package_library install_package_include \\
        uninstall_package uninstall_package_library uninstall_package_include\\
        install_group install_group_library install_group_include \\
        uninstall_group uninstall_group_library uninstall_group_include \\
        lib clean cleancache realclean build_test \\
        build_package_objects build_package_test_objects \\
        build_package_library preprocess_package_include noop

all: $alltargets

install: install_package install_group

install_library: install_package_library install_group_library

install_include: install_package_include install_group_include

uninstall: uninstall_package uninstall_group

uninstall_lib: uninstall_package_library uninstall_group_library

uninstall_include: uninstall_package_include uninstall_group_include

noop:
\t\@\$(NOOP)

#--- Build Package

preprocess_package_include: \$(BINC_FILES)

build: build_package_library

build_package_library: \$(PACKAGE_LIB)

#\$(PACKAGE_LIB): \$(OBJS) noop
\$(PACKAGE_LIB): \$(OBJS)
\t\$(RM) \$(PACKAGE_LIB)
\t\@\$(AR_PACKAGE) \$(notdir \$(OBJS))
\t\$(RANLIB)

build_package_objects: \$(OBJS)

build_package_test_objects: \$(TEST_OBJS)

$groupedpkg_rules
#--- Install (Package to) Group

install_group: install_group_library install_group_include

install_group_include: \$(GRP_INC_FILES) \$(GRP_INC_MFILES)
$grpinstextradir

install_group_library: \$(GRP_LIB_DIR)${FS}\$(GROUP_LIB)

\$(GRP_LIB_DIR)${FS}\$(GROUP_LIB): \$(OBJS) noop
\t\@-\$(MKDIR) \$(GRP_LIB_DIR)
\t\@\$(RM) \$(GRP_LIB_DIR)${FS}\$(GROUP_LIB)
\t\@\$(AR_INSTALL) \$(notdir \$(OBJS))
\t\$(RANLIB)

#--- Uninstall (Package from) Group

uninstall_group: uninstall_group_library uninstall_group_include

uninstall_group_include:
\t\@-\$(MKDIR) \$(GRP_INC_DIR)
\t\@-\$(MKDIR) \$(GRP_INC_MDIR)
\t\$(RM) \$(GRP_INC_FILES)
\t\$(RM) \$(GRP_INC_MFILES)

uninstall_group_library:
\t\@-\$(MKDIR) \$(GRP_LIB_DIR)
\t\$(RM) \$(GRP_LIB_DIR)${FS}\$(GROUP_LIB)

#--- Clean!

clean: cleancache
\t\$(CD) \$(${PKG}_BLOC) && \$(MAKE) -f $dir${FS}$makefile clean.using_relative_paths

clean.using_relative_paths: $mainsrc_clean_rule_name
\t\$(RM) ${clpkg}*.\$(UFID)\$(OBJ_EXT)
\t\$(RM) ${clpkg}*.\$(UFID).log
\t\$(RM) make.*.\$(UFID).log
\t\$(RM) ${clpkg}*.\$(UFID).out
\t\$(RM) ${clpkg}*.\$(UFID).pdb
\t\$(RM) vc*.pdb
\t\$(RM) ${clpkg}*.cod
\t\$(RM) ${clpkg}*.t.\$(UFID)\$(EXE_EXT)
\t\$(RM) \$(PACKAGE_LIB)
$remove_subdirs
# wipes out all build types, unfortunately <<<TODO: fix later

cleancache:
\t\$(RMRECURSE) \$(${PKG}_BLOC)${FS}\$(TEMPLATE_CACHE_DIR) \$(${PKG}_BLOC)${FS}tempinc

realclean: clean uninstall
\t\$(RM) \$(${PKG}_BLOC)${FS}${MAKEFILE}.\$(UFID)
\t\$(RM) \$(${PKG}_BLOC)${FS}${MAKEFILE}.\$(UFID).vars
\t${rmclbuildfiles}

cleandir:
\t\$(RMRECURSE) \$(${PKG}_BLOC)${FS}

cleanalldir:
\t\$(CD) \$(${PKG}_LOCN) && \$(RMRECURSE) unix-* windows-*

#--- Tests and Checks

build_test: \$(TESTS)

_MAKE_TARGETS_END

#---

    print $FMK "test: ";
    if (isCompliant $pkg) {
        foreach my $comp (@build_list) {
            print $FMK "test.$comp.t.\$(UFID) ";
        }
    } else {
        print $FMK join $sep, map {
            /^(.*)\.\w+$/ and "test.$1.\$(UFID)"
        } @test_list;
    }
    print $FMK "\n\n";

    my $libdefs=($unit and ($uplid->platform() eq "win"))?
      getLibBuildDefines($unit,getAllGroupDependencies($unit)) : "";
    my $exedefs=($unit and ($uplid->platform() eq "win"))?
      getExeBuildDefines($unit,getAllGroupDependencies($unit)) : "";

    if (isCompliant $pkg) {
        #----------
        print $FMK "#=== Components\n\n";

        foreach my $comp (@build_list) {
            $comp=getCachedComponent($comp);
            my $intf = $comp.".h";
            my $impl = $comp.".".$comp->getLanguage();
            my $tst  = $comp.".t.".$comp->getLanguage();

            # derive list of all component dependencies
            my @linkdeps = getAllInternalComponentDependencies($comp,2);
            my @objfdeps = map {
                "\$(${PKG}_BLOC)${FS}$_.\$(UFID)\$(OBJ_EXT)"
            } @linkdeps;
            my @extrasrcs=();
            foreach ($comp,@linkdeps) {
                push @extrasrcs, (exists $extrasrcinfo->{$_})?
                  @{$extrasrcinfo->{$_}} : ();
            }
            my @extraobjs=map {
                my $o=$_; $o=~s/.\w+$/.\$(UFID)\$(OBJ_EXT)/ && $o
            } @extrasrcs;
            push @extraobjs,
              "\$(${PKG}_BLOC)${FS}${pkg}_refs.\$(UFID)\$(OBJ_EXT)"
                if $hasrefs;
            push @extraobjs,
              "\$(${PKG}_BLOC)${FS}${group}_refs.\$(UFID)\$(OBJ_EXT)"
                if $hasgrprefs;
            push @extraobjs,
              "\$(${PKG}_BLOC)${FS}${pkg}_dums.\$(UFID)\$(OBJ_EXT)"
                if $hasdums;
            push @extraobjs,
              "\$(${PKG}_BLOC)${FS}${group}_dums.\$(UFID)\$(OBJ_EXT)"
                if $hasgrpdums;

            # Extra sources
            if (exists $extrasrcinfo->{$comp}) {
                print $FMK "# $comp extra file\n";
                my $ext;
                foreach my $extrasrc (@{$extrasrcinfo->{$comp}}) {
                    #<<<TODO: not copied to build dir yet
                    my $extra=$extrasrc;
                    $extra=~s/\.(\w+)$//o and $ext=$1;
                    print $FMK "\$(${PKG}_BLOC)${FS}$extra.\$(UFID)\$(OBJ_EXT):".
                      " \$(${PKG}_LOCN)${FS}${FS}$extra.$ext";

                  SWITCH: foreach ($ext) {
                        /^s$/ and do {
                            # use COMPONENT_ flags
                            print $FMK mkDotOAssyCmd("\$(${PKG}_LOCN)${FS}$extra.$ext");
                            last;
                        };
                      DEFAULT:
                        # use COMPONENT_ flags
                        print $FMK mkDotOCompCmd("\$(${PKG}_BLOC)${FS}$extra.$ext",
                                                 $libdefs);
                        last;
                    }
                }
            }

            # COMPONENT .o RULE
            print $FMK "#=== $comp ===\n\n";
            ##process implementation
            print $FMK "\$(${PKG}_BLOC)${FS}$impl: \$(${PKG}_LOCN)${FS}$impl"
              ."\n"; #" \$(${PKG}_LOCN)\n"; #add the dir for Clearcase 'unco' detection
            print $FMK "\t\$(PROCESS_IMP) \$(${PKG}_LOCN)${FS}$impl \"\$@\"\n\n";
            ##process include
            print $FMK "\$(${PKG}_BLOC)${FS}$intf: \$(${PKG}_LOCN)${FS}$intf"
              ."\n"; #" \$(${PKG}_LOCN)\n"; #add the dir for Clearcase 'unco' detection
            print $FMK "\t\$(PROCESS_INC) \$(${PKG}_LOCN)${FS}$intf \"\$@\"\n\n";

            if (isGroupedPackage $pkg) {
                ##install processed inc - package
                print $FMK
                  "\$(PKG_INC_DIR)${FS}$intf: \$(${PKG}_BLOC)${FS}$intf\n";
                print $FMK "\t\@-\$(MKDIR) \$(PKG_INC_DIR)\n";
                print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
            }

            ##install processed inc - group include (producemake compatible)
            print $FMK "\$(GRP_INC_DIR)${FS}$intf: \$(${PKG}_BLOC)${FS}$intf\n";
            print $FMK "\t\@-\$(MKDIR) \$(GRP_INC_DIR)\n";
            print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
            ##install processed inc - group include (build type)
            print $FMK "\$(GRP_INC_MDIR)${FS}$intf: \$(${PKG}_BLOC)${FS}$intf\n";
            print $FMK "\t\@-\$(MKDIR) \$(GRP_INC_DIR)\n";
            print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";

            # (Optional) ASSOCIATED EXTRA .o RULES
            makeComponentObjectRule($FMK,$comp,$link_ufid,$depend_on_groups,
                                    $libdefs);

            # TEST DRIVER
            print $FMK "\$(${PKG}_BLOC)${FS}$tst: \$(${PKG}_LOCN)${FS}$tst"
              ."\n"; #" \$(${PKG}_LOCN)\n"; #add the dir for ClearCase 'unco' detection
            print $FMK "\t\$(PROCESS_IMP) \$(${PKG}_LOCN)${FS}$tst \"\$@\"\n\n";
            makeTestDriverRule($FMK,$comp,"",$link_ufid,$depend_on_groups,
                               $exedefs,$filefinder,@objfdeps,@extraobjs);
            makeTestRule($FMK,$comp,"",$opts{jobs});

            if ($test_ufid ne $ufid) {
                makeTestDriverRule($FMK,$comp,"TEST_",$link_ufid,
                                   $depend_on_groups,$exedefs,$filefinder,
                                   @objfdeps,@extraobjs);
                makeTestRule($FMK,$comp,"TEST_",$opts{jobs});
            }


            # clean
            print $FMK "$comp.clean: clean.$comp\n\n";
            print $FMK "clean.$comp:\n";
            print $FMK "\t\$(RM)".
                       " \$(${PKG}_BLOC)${FS}$comp.t.\$(UFID)\$(OBJ_EXT)".
                       " @objfdeps ".
                       " \$(${PKG}_BLOC)${FS}$comp.t.\$(UFID)\$(EXE_EXT)".
                       " \$(${PKG}_BLOC)${FS}$comp.t.\$(UFID).log".
                       " \$(${PKG}_BLOC)${FS}$comp.t.\$(UFID).pdb\n\n";

            # realclean
            print $FMK "realclean.$comp: clean.$comp\n\n";
        } #foreach my $comp (@build_list)

        if (isApplication($pkg) and not $mainsrc) {
            $mainsrc="${pkg}.m.cpp=${pkg}.tsk";
        }

        my @srcsNeedingCleanObjs;

        if ($mainsrc) {
            my (@exes,$exe);
            foreach my $src (split ' ',$mainsrc) {
                # extract exe name if specified, derive it from src otherwise
                ($src,$exe)=split /=/,$src;
                unless ($exe) {
                    $exe=$src;
                    $exe=~s[\.\w+$][.\$(UFID)\$(EXE_EXT)];
                }

                my @extraobjs;
                push @extraobjs,
                  "\$(${PKG}_BLOC)${FS}${pkg}_refs.\$(UFID)\$(OBJ_EXT)"
                    if $hasrefs;
                push @extraobjs,
                  "\$(${PKG}_BLOC)${FS}${group}_refs.\$(UFID)\$(OBJ_EXT)"
                    if $hasgrprefs;
                push @extraobjs,
                  "\$(${PKG}_BLOC)${FS}${pkg}_dums.\$(UFID)\$(OBJ_EXT)"
                    if $hasdums;
                push @extraobjs,
                  "\$(${PKG}_BLOC)${FS}${group}_dums.\$(UFID)\$(OBJ_EXT)"
                    if $hasgrpdums;

                print $FMK "\$(${PKG}_BLOC)${FS}$src:".
                           " \$(${PKG}_LOCN)${FS}$src\n"; # \$(${PKG}_LOCN)\n";
                             # add directory for Clearcase unco detection
                print $FMK "\t\$(PROCESS_IMP) \$(${PKG}_LOCN)${FS}$src \"\$@\"\n\n";
                makeApplicationMainRule($FMK,$pkg,$src,$exe,"",$link_ufid,
                                        $depend_on_groups,$exedefs,
                                        @extraobjs);
                push @exes,$exe;

                push @srcsNeedingCleanObjs,$src;

            }

            print $FMK "build_application: ",join(' ',map {
                "\$(${PKG}_BLOC)${FS}$_"
            } @exes)."\n\n";

            if ($have_mainsrc_clean_rule) {
                print $FMK "# -- Extra cleanup rule for APPLICATION_MAIN objects\n";
                print $FMK "$mainsrc_clean_rule_name:\n";
                foreach my $src (@srcsNeedingCleanObjs) {
                    # strip extension from sourcename
                    $src=~s/\.\w+$//;
                    print $FMK "\t\$(RM) $src.\$(UFID)\$(OBJ_EXT)\n";
                }
                print $FMK "\n";
            }
        }

        #----------
    } else {
        #----------
        # non-compliant package
        print $FMK "#=== Sources\n\n";

        my $is_legacy = isLegacy($pkg);
        foreach my $sourcefile (@build_list) {
            my $objfile=$sourcefile;

            $objfile=~s/\.\w+$/.\$(UFID)\$(OBJ_EXT)/;
            my @results= $is_legacy
              ? ()  #<<<TODO: ?? parse file for dependencies of legacy files ??
              : getAllFileDependencies($sourcefile,$filefinder);
            if (@results) {
                @results = grep { $_ } map { $_->getRealname() } @results;
            }
            print $FMK "\$(${PKG}_BLOC)${FS}$objfile: \$(${PKG}_LOCN)${FS}$sourcefile @results";
            my $objdir=dirname($objfile);
            if ($objdir ne '.') {
                # there's a path in the name, so make sure the corresponding
                # path exists for the resulting object
                print $FMK "\n\t\@-\$(MKDIR) \$(${PKG}_BLOC)${FS}$objdir";
            }
            # use COMPONENT_ flags
            print $FMK mkDotOCompCmd("\$(${PKG}_LOCN)${FS}$sourcefile",$libdefs);
        }

        print $FMK "#=== Headers\n\n";

        foreach my $intf (@inc_files) {
            my $subdir=dirname($intf);
            if ($subdir ne '.') {
                # there's a path in the name, so make sure the corresponding
                # path exists in the destination directory
                $subdir="${FS}".$subdir;
            } else {
                $subdir="";
            }

            if (isGroupedPackage $pkg) {
                ##install processed inc - package include
                print $FMK
                  "\$(PKG_INC_DIR)${FS}$intf: \$(${PKG}_LOCN)${FS}$intf\n";
                print $FMK "\t\@-\$(MKDIR) \$(PKG_INC_DIR)$subdir\n";
                print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
            }

            ##install processed inc - group include (producemake compatible)
            print $FMK "\$(GRP_INC_DIR)${FS}$intf:".
                       " \$(${PKG}_LOCN)${FS}$intf\n";
            print $FMK "\t\@-\$(MKDIR) \$(GRP_INC_DIR)$subdir\n";
            print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";

            ##install processed inc - group include (uplid/ufid dependent)
            print $FMK "\$(GRP_INC_MDIR)${FS}$intf:".
                       " \$(${PKG}_LOCN)${FS}$intf\n";
            print $FMK "\t\@-\$(MKDIR) \$(GRP_INC_MDIR)$subdir\n";
            print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
        }

        #---
        my $testdir=$options->getValue("TEST_SUBDIR") || 'test';

        my ($base,$extension);
        my $cmntst_objs="";
        if (my $common=$options->getValue("TEST_COMMON")) {
            print $FMK "#=== Tests (Common Sources)\n\n";
            my @common=split /\s+/,$common;
            my @cmntst_objs=();
            foreach my $tst (@common) {
                $tst=~/^(.*)\.(\w+)$/o and ($base,$extension)=($1,$2);

                print $FMK "#--- $base\n\n";
                # test object rule
                my $cmntst_obj="\$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(OBJ_EXT)";
                push @cmntst_objs,$cmntst_obj;
                print $FMK "$cmntst_obj: ".
                  "\$(${PKG}_LOCN)${FS}${testdir}${FS}$tst";
                # use COMPONENT_ flags  (TBD: Decide whether this should use TESTDRIVER_)
                print $FMK mkDotOCompCmd("\$(${PKG}_LOCN)${FS}${testdir}${FS}$tst",
                                         "\$(TEST_DEFINES) ".
                                         "\$(TEST_INCLUDE) $libdefs");

            }
            $cmntst_objs=join(' ',@cmntst_objs);
        }
        #---

        print $FMK "#=== Tests\n\n";
        foreach my $tst (@test_list) {
            $tst=~/^(.*)\.(\w+)$/o and ($base,$extension)=($1,$2);
            print $FMK "#--- $base\n\n";
            # test object rule
            print $FMK "\$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(OBJ_EXT): ".
              "\$(${PKG}_LOCN)${FS}${testdir}${FS}$tst";
            # use COMPONENT_ flags  (TBD: Decide whether this should use TESTDRIVER_)
            print $FMK mkDotOCompCmd("\$(${PKG}_LOCN)${FS}${testdir}${FS}$tst",
                                     "\$(TEST_DEFINES) ".
                                     "\$(TEST_INCLUDE) $libdefs");
            # test executable rule
            print $FMK "\$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(EXE_EXT):".
              " \$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(OBJ_EXT)".
                " $cmntst_objs \$(BDE_DEPLIBS)\n";
            if ($uplid->platform() eq "win") {
                print $FMK "\tcd \$(${PKG}_BLOC)\n";
            }
            if ($extension eq "c") {
                if ($uplid->platform() ne "win") {
                    print $FMK "\t\$(CLINK) \$(EXE_OPT)".
                               " \$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(OBJ_EXT)";
                } else {
                    print $FMK "\t\$(CLINK) \$(CFLAGS) \$(EXE_OPT)".
                               " \$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(OBJ_EXT)";
                }
            } else {
                print $FMK "\t\$(CXXLINK) \$(EXE_OPT)".
                           " \$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(OBJ_EXT)";
            }
            if ($uplid->platform() eq "win") {
                my $tst_objs=$cmntst_objs;
                $tst_objs=~s/\$\(${PKG}_BLOC\)/./g;
                print $FMK " $tst_objs \$(TESTDRIVER_BDEBUILD_LDFLAGS)\n\n";
            }
            else {
                print $FMK " $cmntst_objs \$(TESTDRIVER_BDEBUILD_LDFLAGS)\n\n";
            }
            # shorthand test rule
            print $FMK "test.$base: test.$base.\$(UFID)\n\n";
            # test rule
            print $FMK "test.$base.\$(UFID): ".
                       "\$(${PKG}_BLOC)${FS}$base.\$(UFID).out".
                       " \$(${PKG}_LOCN)${FS}test${FS}$base.exp \n";
            print $FMK "\t\$(DIFF) \$(${PKG}_LOCN)${FS}test${FS}$base.exp".
                       " \$(${PKG}_BLOC)${FS}$base.\$(UFID).out\n\n";
            # expect file (first time through generation)
            print $FMK "\$(${PKG}_LOCN)${FS}test${FS}$base.exp:\n";
            print $FMK "\t\$(TEST_RUNPREFIX)\$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(EXE_EXT)".
                       " \$(TEST_RUNSUFFIX) > \"\$@\" 2>&1\n\n";
            # result file
            print $FMK "\$(${PKG}_BLOC)${FS}$base.\$(UFID).out: ".
                       "\$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(EXE_EXT)\n";
            print $FMK "\t\$(TEST_RUNPREFIX)\$(${PKG}_BLOC)${FS}$base.\$(UFID)\$(EXE_EXT)".
                       " \$(TEST_RUNSUFFIX) > \"\$@\" 2>&1\n\n";
        }
        #----------
    }

    print $FMK "#=== References\n\n" if $hasrefs or $hasgrprefs;
    if ($hasrefs) {
        print $FMK "\$(${PKG}_BLOC)${FS}${pkg}_refs.\$(UFID)\$(OBJ_EXT): ".
                     "\$(${PKG}_BLOC)${FS}${pkg}_refs.c";
        # use COMPONENT_ flags
        print $FMK mkDotOCompCmd("\$(${PKG}_BLOC)${FS}${pkg}_refs.c");
        print $FMK "\$(${PKG}_BLOC)${FS}${pkg}_refs.c: ".
                   "\$(${PKG}_LOCN)${FS}${\PACKAGE_META_SUBDIR}".
                     "${FS}${pkg}${\REFFILE_EXTENSION}\n";
        print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
    }
    if ($hasgrprefs) {
        print $FMK "\$(${PKG}_BLOC)${FS}${group}_refs.\$(UFID)\$(OBJ_EXT): ".
                     "\$(${PKG}_BLOC)${FS}${group}_refs.c";
        # use COMPONENT_ flags
        print $FMK mkDotOCompCmd("\$(${PKG}_BLOC)${FS}${group}_refs.c");
        print $FMK "\$(${PKG}_BLOC)${FS}${group}_refs.c: ".
                   "\$(${UNIT}_LOCN)${FS}${\GROUP_META_SUBDIR}".
                     "${FS}${group}${\REFFILE_EXTENSION}\n";
        print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
    }

    print $FMK "#=== Dummies\n\n" if $hasdums or $hasgrpdums;
    if ($hasdums) {
        print $FMK "\$(${PKG}_BLOC)${FS}${pkg}_dums.\$(UFID)\$(OBJ_EXT): ".
                     "\$(${PKG}_BLOC)${FS}${pkg}_dums.c";
        # use COMPONENT_ flags
        print $FMK mkDotOCompCmd("\$(${PKG}_BLOC)${FS}${pkg}_dums.c");
        print $FMK "\$(${PKG}_BLOC)${FS}${pkg}_dums.c: ".
                   "\$(${PKG}_LOCN)${FS}${\PACKAGE_META_SUBDIR}".
                     "${FS}${pkg}${\DUMFILE_EXTENSION}\n";
        print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
    }
    if ($hasgrpdums) {
        print $FMK "\$(${PKG}_BLOC)${FS}${group}_dums.\$(UFID)\$(OBJ_EXT): ".
                     "\$(${PKG}_BLOC)${FS}${group}_dums.c";
        # use COMPONENT_ flags
        print $FMK mkDotOCompCmd("\$(${PKG}_BLOC)${FS}${group}_dums.c");
        print $FMK "\$(${PKG}_BLOC)${FS}${group}_dums.c: ".
                   "\$(${UNIT}_LOCN)${FS}${\GROUP_META_SUBDIR}".
                     "${FS}${group}${\DUMFILE_EXTENSION}\n";
        print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
    }

    print $FMK $EOF_MARKER;

    close $FMK;

    # create/move a convenience link for direct invokation
    if ($uplid->platform() ne "win") {
        my $curdir=Cwd::cwd;
        retry_chdir $dir;
        if (-e $makename or -l $makename) {
            if (-l $makename) {
                unlink $makename;
                eval { makeLink($makefile,$makename,1) };
            }
        } else {
            eval { makeLink($makefile,$makename,1) };
        }
        retry_chdir $curdir;
    }

    my $duration=time-$start_time;
    message("Made ".$ufid->toString(1).
            " makefile for package $pkg in $duration seconds");

    return 0; #success
}

sub makeMakefiles ($@) {
    my ($concurrency,$args,@packages)=@_;
    my $mgr=new Task::Manager("Making ".
                                        $ufid->toString(1)." makefiles");

    fatal "Args not an array ref" unless ref($args)
      and ref($args) eq "ARRAY";

    for my $pkg (@packages) {
        my $makefile = $root->getPackageLocation($pkg).
          "/$uplid/".getMakefileName($ufid);

        $mgr->addAction(new Task::Action ({
            name   => "${pkg}.makefile",
            action => \&makeMakefile,
            args   => [$pkg, @$args],
        }));
    }

    my $result=$mgr->run($concurrency);
    return $result;
}

#------------------------------------------------------------------------------

sub makeLink($$;$) {
    my ($from, $to, $existing_ok) = @_;
    if (-e $to) {
        if (-l $to) {
            my $reallyfrom=readlink($to);
            if ($reallyfrom ne $from) {
                if ($existing_ok) {
                    debug "Found existing link to $reallyfrom - preserving";
                } else {
                    fatal "Cound not link $from to $to: ".
                          "existing link to $reallyfrom in the way";
                }
            } else {
                debug "Found existing and correct link for $to";
            }
        } else {
            if ($existing_ok) {
                debug "Found existing file - preserving";
            } else {
                fatal "Could not link $from to $to: local file in the way";
            }
        }

        return 1;
    } else {
        my $rc=symlink($from, $to); #<<<TODO: change to copy on Windows?
        if ($existing_ok) {
            debug "Could not link $from to $to: $!" unless $rc;
        }
        else {
            fatal "Could not link $from to $to: $!" unless $rc;
        }
        return $rc;
    }
}

sub makeLinks ($@) {
    my ($existing_ok,$comps)=@_;

    for my $comp (@_) {
        fatal "Not a component: $comp" unless isComponent($comp);
        my $intf = $root->getComponentIntfFilename($comp);
        makeLink($intf, basename($intf),$existing_ok);
        my $impl = $root->getComponentImplFilename($comp);
        makeLink($impl, basename($impl),$existing_ok);
    }
}

#------------------------------------------------------------------------------

sub makeLocalMakefile($$$;$$) {
    my ($comp,$depend_on_groups,$ufid,$link_ufid,$test_ufid) = @_;
    fatal "Not a component: $comp" unless isComponent($comp);

    $link_ufid=$ufid unless $link_ufid;
    $test_ufid=$ufid unless $test_ufid;

    # local versions
    my $intf = $comp.".h";
    my $impl = $comp.".cpp";   # adapt for .c use
    my $tst  = $comp.".t.cpp"; # adapt for .c use

    my $package = getComponentPackage($comp);
    my $PKG = uc $package;
    my $dir = $root->getPackageLocation($package);
    # is this derived from a real package?
    my $package_exists = 0;

    if (retry_dir $dir) {
        $package_exists = 1;
    } else {
        $package_exists = 0;
        # component is from an invented package - look for group dir to set
        # $dir for possible deriviation from a group.opts file
        $dir = $root->getGroupLocation(getPackageGroup($package));
        unless (retry_dir $dir) {
            $dir = $root->getRootLocation();
        }
    }

    # even if the package doesn't actually exist, its enclosing group might
    my $group = getPackageGroup($package);
    $group=getCachedGroup($group) if $group; #undef => no group applies

    my $libdefs=$group?
      getLibBuildDefines($group,getAllGroupDependencies($group)) : "";
    my $exedefs=$group?
      getExeBuildDefines($group,getAllGroupDependencies($group)) : "";

    # derive list of all component dependencies
    my @linkdeps = getAllInternalComponentDependencies($comp,2);
    my @objfdeps = map { "$_.\$(UFID)\$(OBJ_EXT)" } @linkdeps;

    if ($package_exists) {
        # component is based from a real package - try to make links to any
        # dependent components that don't already exist locally.
        makeLinks($comp,@linkdeps);
        my $ftst = $root->getComponentTestFilename($comp);
        makeLink($ftst,$tst,1); # test driver for target component
    }

    # write variables for component object build
    my $options=constructOptions($comp,$uplid,$ufid);
    writeOptions($package,$options,MAKEFILE_NAME,$dir,"",".");

    # if a separate test ufid was given, write variables file for that too
    if ($test_ufid ne $ufid) {
        my $toptions=constructOptions($comp,$uplid,$test_ufid);
        writeOptions($package,$options,MAKEFILE_NAME,$dir,"TEST_",".");
    }

    # write makefile...
    my $FMK=new IO::File;
    retry_open($FMK, "> ".MAKEFILE_NAME)
      or fatal "cannot create Makefile: ".MAKEFILE_NAME." $!";

    makeMakefilePreamble($FMK,$package,MAKEFILE_NAME,$ufid,$link_ufid,
                         $test_ufid,$root);
    makePackageDependencyMacros($FMK,$package,$link_ufid,"local",
                                $depend_on_groups);
    makeMakefileBuildFlags($FMK,$package);

    print $FMK "#=== General Targets\n\n";

    print $FMK "all: build\n\n";

    # clean
    print $FMK "clean: cleancache\n";
    print $FMK "\t\-\$(RM) $comp.t.\$(UFID)\$(OBJ_EXT)\n";
    if ($test_ufid ne $ufid) {
        print $FMK "\t-\$(RM) $comp.t.\$(TEST_UFID)\$(OBJ_EXT)\n";
    }
    if (@linkdeps) {
        print $FMK "\t-\$(RM) $comp.\$(UFID)\$(OBJ_EXT) @objfdeps\n";
    }
    print $FMK "\t\-\$(RM) a.\$(UFID)\$(EXE_EXT) $comp.t.\$(UFID)\$(EXE_EXT)\n";
    if ($test_ufid ne $ufid) {
        print $FMK "\t-\$(RM) a.\$(TEST_UFID)\$(EXE_EXT)".
                   " $comp.t.\$(TEST_UFID)\$(EXE_EXT)\n";
    }
    print $FMK "\n";
    print $FMK "cleancache:\n";
    print $FMK "\t\$(RMRECURSE) \$(TEMPLATE_CACHE_DIR) tempinc";
    print $FMK "\n";

    # realclean
    print $FMK "realclean: clean\n";
    print $FMK "\t\-\$(RM) Makefile Makefile.$ufid.vars".
      (($test_ufid ne $ufid)?" Makefile.$test_ufid.vars":"")."\n";
    print $FMK "\n";

    # build
    print $FMK "build: a.\$(UFID)\$(EXE_EXT)".(
        ($test_ufid ne $ufid)?" a.\$(TEST_UFID)\$(EXE_EXT)":""
    )."\n\n";

    print $FMK "a.\$(UFID)\$(EXE_EXT): $comp.t.\$(UFID)\$(EXE_EXT)\n";
    print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
    if ($test_ufid ne $ufid) {
        print $FMK "a.\$(TEST_UFID)\$(EXE_EXT): $comp.t.\$(TEST_UFID)\$(EXE_EXT)\n\n";
        print $FMK "\t\$(F2FCP) \"\$?\" \"\$@\"\n\n";
    }

    # look for extra source files
    my $extrasrcinfo = calculateExtraSources($options,$package,@linkdeps);

    # component objects
    if (@linkdeps) {
        print $FMK "#=== Dependent Components\n\n";
        for my $compdep (@linkdeps) {
            my @extrasrcs=(exists $extrasrcinfo->{$compdep})?
              @{$extrasrcinfo->{$compdep}} : ();
            makeComponentObjectRule($FMK,$compdep,$link_ufid,
                                    $depend_on_groups,$libdefs);
        }
    }
    print $FMK "#=== Target Component\n\n";
    my @extrasrcs=(exists $extrasrcinfo->{$comp})?
      @{$extrasrcinfo->{$comp}} : ();
    makeComponentObjectRule($FMK,$comp,$link_ufid,
                            $depend_on_groups,$libdefs);

    my @extraobjs=map { s/.\w+$/.\$(UFID)\$(OBJ_EXT)/ && $_ } @extrasrcs;

    # component test driver object and excutable
    makeTestDriverRule($FMK,$comp,"",$link_ufid,$depend_on_groups,
                       $exedefs,$comp->getPackage(),@objfdeps,@extraobjs);
    makeTestRule($FMK,$comp,"",1);
    if ($test_ufid ne $ufid) {
        makeTestDriverRule($FMK,$comp,"TEST_",$link_ufid,$depend_on_groups,
                           $exedefs,$comp->getPackage(),@objfdeps,@extraobjs);
        makeTestRule($FMK,$comp,"TEST_",1);
    }

    return 1;
}

# --- "group" makefile routines ----

sub getGroupBuildDir($$$) {
    my ($root, $group, $uplid) = @_;
    my $dir = "build";

    my $t = isGroup($group) ? $root->getGroupLocation($group)
      : $root->getPackageLocation($group);
    fatal("not group or package: $group") if !$t;
    return $t."${FS}${dir}${FS}$uplid";
}

sub getPackageBuildDir($$$) {
    my ($root, $package, $uplid) = @_;
    return $root->getPackageLocation($package)."${FS}${uplid}";
}

sub getMakefileName($) {
    my ($ufidstr) = @_;
    return "Makefile.${ufidstr}";
}

sub getObj($$) {
    my ($component, $ufidstr) = @_;
    return "${component}.${ufidstr}\$(OBJ_EXT)";
}


# Creates a "group" makefile, where group can be package group OR
# standalone package.
sub makeGroupMakefile($$$$$) {
    my ($root, $gop, $uplid, $ufid, $jobs) = @_;
    $jobs ||= 1;
    $gop=getCachedGroupOrIsolatedPackage($gop);
    if ($gop->isPrebuilt) {
        debug "$gop is prebuilt, makefile generation skipped\n";
        return;
    } elsif ($gop->isPrebuilt) {
        debug "$gop is prebuilt-legacy, makefile generation skipped\n";
        return;
    }
    alert("Making top level makefile for $gop");

    my @regions=isIsolatedPackage($gop) ? () : $gop->getRegions();
    my @group_deps = map {
        getCachedGroupOrIsolatedPackage($_);
    } getAllGroupDependencies($gop);

    my $build_dir = getGroupBuildDir($root, $gop, $uplid);
    #mkpath($build_dir, 0, 0775);
    # make sure directories leading up to build_dir exist
    mkdirOrLink($build_dir, 0775);
    rmdir($build_dir);

    mkdirOrLink($build_dir, 0775);
    my $ufidstr = $ufid->toString(1);
    my $mkf = "Makefile.".$ufidstr;
    my $varsf = "$build_dir${FS}${mkf}.vars";

    my $start_time=time;
    my $phony="noop";

    my @mkf;

    push @mkf, "include $varsf\n\n";
    push @mkf, "MAKEFILE         = $mkf\n";
    push @mkf, "UPLID            = $uplid\n";

    push @mkf, "UFID             = ",$ufid->toString(1),"\n";
    push @mkf, "LIBUFID          = $ufid\n";
    #push @mkf, "LINK_UFID        = ",$link_ufid->toString(1),"\n";
    #push @mkf, "LINK_LIBUFID     = $link_ufid\n";

    #push @mkf, "UFID             = $ufid\n";
    #push @mkf, "LIBUFID          = $ufid\n";

    push @mkf, "ROOT_LOCN        = $root\n";
    makeUnitPathMacros($root,$gop,\@mkf);
    push @mkf, "GRP_LIB_DIR      =".
        " \$(".getUnitMacro($gop)."_ROOTLOCN)${FS}lib${FS}\$(UPLID)\n";

    foreach my $lib ($gop,@regions) {
        push @mkf, getUnitMacro($lib)."_LIB         =".
          " \$(GRP_LIB_DIR)${FS}\$(LIB_PREFIX)$lib.\$(LIBUFID)\$(LIB_EXT)\n";
    }

    push @mkf, "FORCED_VIEW      = $1\n"
      if ($opts{where} && $opts{where} =~ m!^(/view/[^/]+)/bbcm/!);
    push @mkf, "\n";

    #---

    push @mkf, "# ---------- ".uc($gop)." TOP-LEVEL TARGETS "."----------\n\n";

    push @mkf, "all:\n";
    if (@group_deps) {
        push @mkf, "\t\$(MAKE) -f $mkf build_dependencies\n";
    }
    push @mkf, "\t\$(MAKE) -f $mkf group\n\n";

    push @mkf, "group: install_group_include\n";
    push @mkf, "\t\$(MAKE) -f $mkf build_package_libraries\n";
    push @mkf, "\t\$(MAKE) -f $mkf install_group_library\n\n";

    #---

    my $all_grp_include_targets = " ";
    my $all_grp_lib_targets = " ";
    my $all_grp_clean_targets = " ";

    if (@group_deps) {
        push @mkf, "build_dependencies: ".
          "install_dependencies_includes\n";
        push @mkf, "\t\$(MAKE) -f $mkf install_dependencies_libraries\n\n";

        push @mkf, "# --------------- Dependent UOR Rules ---------------\n\n";

        for my $grp (@group_deps) {
            next if $grp->isPrebuilt; #includes prebuilt.

            $all_grp_include_targets .= "$grp.include ";
            $all_grp_lib_targets     .= "$grp.lib ";
            $all_grp_clean_targets   .= "$grp.clean ";

            push @mkf,"$grp.include:\n";
            push @mkf,"\t\$(CD) ".getGroupBuildDir($root,$grp,$uplid).
              " && \\\n";
            push @mkf,"\t\$(MAKE) -f $mkf install_group_include\n\n";

            push @mkf,"$grp.lib:\n";
            push @mkf,"\t\$(CD) ".getGroupBuildDir($root,$grp,$uplid).
              " && \\\n";
            push @mkf,"\t\$(MAKE) -f $mkf install_group_library\n\n";

            push @mkf,"$grp.clean:\n";
            push @mkf,"\t\$(CD) ".getGroupBuildDir($root,$grp,$uplid).
              " && \\\n";
            push @mkf,"\t\$(MAKE) -f $mkf clean\n\n";
        }

        push @mkf, "install_dependencies_includes: ".
          $all_grp_include_targets."\n\n";
        push @mkf, "install_dependencies_libraries: ".
          $all_grp_lib_targets."\n\n";
        push @mkf, "clean_dependencies: ".
          $all_grp_clean_targets."\n\n";

        $phony.="$all_grp_include_targets $all_grp_lib_targets".
                " $all_grp_clean_targets dep_group_includes".
                " dep_group_libraries dep_group_cleans build_dependencies";
    }

    #-------------------------------------------------------------------------

    my @packages = isIsolatedPackage($gop)
      ? $gop
      : map { getCachedPackage($_) } getCachedGroup($gop)->getMembers();

    push @mkf, "# ---------- ".uc($gop)." PACKAGE TARGETS ----------\n\n";

    my $all_pkg_include_targets;
    my $all_pkg_lib_targets;
    my $all_pkg_clean_targets;

    my %all_objects = ($gop => []);
    my %all_objects_relative = ($gop => []);
    foreach my $region (@regions) {
        $all_objects{$region}=[];
        $all_objects_relative{$region}=[];
    }

    ## XXX: quick fix so that non-package-groups with the top level name
    ## symlinked will build (as in the case of departments/index/<group>
    ## pointing to departments/<department_code>/<group>.
    ## Assumes getGroupLocation return a directory (which is a
    ## valid assumption), hence the ugly $FS..$FS is ok here.
    my $gop_locn_virt = isGroup($gop) ? $root->getGroupLocation($gop)
      : $root->getPackageLocation($gop);
    my $gop_locn_real = -l $gop_locn_virt
      ? readlink($gop_locn_virt)
        : $gop_locn_virt;
    $gop_locn_real =
      Cwd::abs_path($gop_locn_virt."$FS..$FS".$gop_locn_real)
          if ($gop_locn_real =~ m|^\.\.\Q${FS}\E|);
    my $gop_locn_virt_len = length($gop_locn_virt);
    my $gop_locn_real_len = length($gop_locn_real);

    #--------[begin package loop]

    for my $package (@packages) {
        my $bdir = getPackageBuildDir($root, "$package", $uplid);
        my $bdir_relative =
          substr($bdir,0,$gop_locn_virt_len) eq $gop_locn_virt
            ? substr($bdir,$gop_locn_virt_len+1)
              : substr($bdir,$gop_locn_real_len) eq $gop_locn_real
                ? substr($bdir,$gop_locn_real_len+1)
                  : $bdir;

        push @mkf, "$package.include:\n";
        push @mkf, "\t\$(CD) $bdir && \\\n";
        push @mkf, "\t\$(MAKE) -f $mkf install_include\n\n";

        push @mkf, "$package.lib:\n";
        push @mkf, "\t\$(CD) $bdir && \\\n";
        push @mkf, "\t\$(MAKE) -f $mkf build_package_library\n\n";

        push @mkf, "$package.clean:\n";
        push @mkf, "\t\$(CD) $bdir && \\\n";
        push @mkf, "\t\$(MAKE) -f $mkf clean\n\n";

        $all_pkg_include_targets .= "$package.include ";
        $all_pkg_lib_targets .= "$package.lib ";
        $all_pkg_clean_targets .= "$package.clean ";

        my (@objs_abs,@objs_rel);

        if (isNonCompliant $package) {
            my @build_list = getCachedPackage($package)->getMembers();
            @build_list = grep { /\.(c|cpp|f)$/ } @build_list;
            unless (@build_list) {
                @build_list = scanPackageDirectory($package,
                                                   '\.(c|cpp|f)?$');
            }
            s/\.(c|cpp|f)$// foreach @build_list;

            @objs_abs=map { "${bdir}${FS}".getObj($_, $ufidstr) } @build_list;
            @objs_rel=map { "${bdir_relative}${FS}".getObj($_, $ufidstr)
                          } @build_list;
        } else {
            @objs_abs=map { "${bdir}${FS}".getObj($_, $ufidstr)
                          } $package->getMembers();
            @objs_rel=map { "${bdir_relative}${FS}".getObj($_, $ufidstr)
                          } $package->getMembers();
        }

        #--------

        ## XXX: temporary fix to reach into package level to grab extra
        ## sources (e.g. EXTRA_BCES_OBJS for compilation on IBM AIX)

        my $xo_macro="EXTRA_".uc($package)."_OBJS";
        $factory->load($package);
        if (my $value=$factory->getValueSet()->getValue($xo_macro)) {
            # don't do the work now unless the option is actually present
            my $options=$factory->construct({
                uplid   => $uplid,
                ufid    => $ufid,
                what    => $package
            });

            if (my $xobjs=$options->getValue($xo_macro)) {
                push @objs_abs, map {
                    s/\.o$// && "${bdir}${FS}".getObj($_,$ufidstr)
                } split(' ',$xobjs);
                push @objs_rel, map {
                    s/\.o$// && "${bdir_relative}${FS}".getObj($_,$ufidstr)
                } split(' ',$xobjs);
            }
        }

        #--------

        push @{$all_objects{$gop}}, @objs_abs;
        push @{$all_objects_relative{$gop}}, @objs_rel;
        if (isGroup $gop) {
            foreach my $region (@regions) {
                if ($gop->regionHasMember($region => $package)) {
                    push @{$all_objects{$region}}, @objs_abs;
                    push @{$all_objects_relative{$region}}, @objs_rel;
                }
            }
        }
    }

    #--------[end package loop]

    push @mkf, "install_group_include: $all_pkg_include_targets\n\n";
    push @mkf, "install_group_library: $all_pkg_lib_targets\n";
    push @mkf, "\t\$(MAKE) -f $mkf ".join(" ",map {
        "\$(".uc($_)."_LIB)"
    } ($gop,@regions))."\n\n";
    push @mkf, "install_group: install_group_include".
      " install_group_library\n\n";
    push @mkf, "build_package_libraries: $all_pkg_lib_targets\n\n";

    push @mkf, "clean: $all_pkg_clean_targets\n\n";

    push @mkf, "realclean: clean_dependencies clean\n\n";

    push @mkf, "noop:\n\n";

    $phony .= " $all_pkg_include_targets $all_pkg_lib_targets".
              " $all_pkg_clean_targets install_group_include".
              " install_group_library install_group".
              " build_package_libraries group all";

    #---

    push @mkf, ".PHONY : $phony\n\n";

    #--------

    # XXX: workaround for Windows shell command line length limitation by using
    # a temporary file instead of passing the object list on the command line
    if ($uplid->platform() eq "win") { #<<<TODO: actually 'nmake' sensitive
        my $options=$factory->construct({
             uplid => $uplid, ufid => $ufid, what => $gop
        });
        my $obj_ext = $options->expandValue("OBJ_EXT");

        foreach my $lib (keys %all_objects_relative) {
            s/\$\(OBJ_EXT\)/$obj_ext/go foreach
              @{$all_objects_relative{$lib}};

            my $objects_file = "${build_dir}${FS}$lib.objs";
            my $OBJFH = new IO::File;
            retry_open($OBJFH, ">$objects_file")
              or fatal "Cannot create $objects_file file: $!\n";
            print $OBJFH join " ",@{$all_objects_relative{$lib}};
            close $OBJFH;

            # replace explicit list with file reference
            $all_objects_relative{$lib} = [ '@'.$objects_file ];
        }
    }

    #--------

    push @mkf, "# ---------- ".uc($gop)." LIBRARY TARGETS ----------\n\n";

    # * targets are constructed to support build via bde_build (i.e. install
    #   only) or build via makefile itself
    # * Relative paths are used to reduce the chance that an excessively long
    #   command line will be generated.
    # * Because we are not using $? macro with AR_INSTALL, we are passing
    #   -all- objects to AR_INSTALL instead of just the ones that have changed.
    #   Therefore, we are not "updating" the archive but effectively rebuilding
    #   it from scratch.
    #   <<<TODO: revise use of AR_INSTALL vs AR_PACKGE (create AR_GROUP?)

    foreach my $lib ($gop,@regions) {
        push @mkf, "\$(".uc($lib)."_LIB): \\\n\t".
          (join " \\\n\t",@{$all_objects{$lib}})."\n";
        push @mkf, "\t\$(MKDIR) \$(GRP_LIB_DIR)\n";
        push @mkf, "\t\$(RM) \$\@\n";
        push @mkf, "\t\$(CD) $gop_locn_real && ".
          "\$(AR_INSTALL) \\\n\t".
            (join " \\\n\t",@{$all_objects_relative{$lib}})."\n";
    }

    push @mkf,"# ---------------- END ".uc($gop)." MAKEFILE ---------------\n";

    #--- write group-level varsfile

    writeBuildVarsFile(
        constructOptions($gop, $uplid, $ufid)->render()."\n", $varsf
    ) or fatal "Error creating .vars file $varsf";

    #--- write group-level makefile

    my $MKFH = new IO::File;
    retry_open($MKFH, ">${build_dir}${FS}${mkf}")
      or fatal "Cannot create makefile ${build_dir}${FS}${mkf}: $!\n";
    print $MKFH @mkf;
    close $MKFH;

    my $duration=time-$start_time;
    message("Made ".$ufid->toString(1).
            " top level makefile for $gop in $duration seconds");
}

{
    my $useGNUMakeOnWindows=-1;
    sub groupMake($$$$$$) {
        my ($root, $group, $uplid, $ufid, $jobs, $target) = @_;

        return if getCachedGroupOrIsolatedPackage($group)->isPrebuilt;

        my @depgroups = getAllGroupDependencies($group);
        return if !@depgroups and $target eq "build_dependencies";
        if ($target eq "build_dependencies") {
            alert("Building dependencies - this may take a while...");
        } else {
            alert("Making top level target \"$target\"");
        }

        my $dir     = getGroupBuildDir($root, $group, $uplid);
        my $ufidstr = $ufid->toString(1);
        my $mkf     = "Makefile.$ufidstr";
        my $mkflog  = "Makefile.$ufidstr.log";
        retry_chdir($dir) or fatal "Cannot chdir to '$dir': $!";

#<<<TODO: duplication of make-command construction code
#<<<TODO: This needs abstraction to default.opts in any case
# generate make command up to target
        my $make_cmd;
        if ($uplid->platform() eq "win") {
            # static check, done once
            if ($useGNUMakeOnWindows==-1) {
                my $makeVer=`make -v`||"";
                if (!$? && $makeVer=~/GNU Make ([0-9.]+)/ && $1>=3.81) {
                    message "Using GNU make version $1, allowing parallel builds";
                    $useGNUMakeOnWindows=1;
                }
                else {
                    message "Using nmake, no parallel builds";
                    $useGNUMakeOnWindows=0;
                }
            }

            if (1 == $useGNUMakeOnWindows) {
                $make_cmd="make -e ";
                $make_cmd .= ($opts{silent}) ? " --silent":"";
                $make_cmd .= ($opts{keepgoing}) ? " -k":"";
                $make_cmd .= ($jobs==1) ?
                    " -j1" : " -j$jobs";
            }
            else {
                $make_cmd = "nmake /nologo /e";
                $make_cmd .= ($opts{silent}) ? " /s":"";
                $make_cmd .= ($opts{keepgoing}) ? " /k":"";
            }
        } else {
            my $mk=($uplid->platform() =~ "^(cygwin|darwin)")?"make":"gmake";
            $make_cmd = ($jobs==1) ?
                "$mk -e -j1" : "$mk -e -j$jobs";
            $make_cmd .= ($opts{silent}) ? " --silent":"";

#pathalogical retry
            $make_cmd = $RETRY_MAKEPROG.$make_cmd unless $opts{noretry};
        }
        $make_cmd .= " -f $mkf";

# add on target
        $make_cmd .= " $target";

# execute make
        my $rc=_gather_output($make_cmd, $mkflog);
        $rc and fatal "Build failed for package '$dir' $$=>$? ".
            "(see $dir${FS}$mkflog)\n";

        return $rc;
    }
}

#------------------------------------------------------------------------------
#==============================================================================
#------------------------------------------------------------------------------
# Begin main script

#------------------------------------------------------------------------------
# OPTIONS

STDOUT->autoflush(1);

if($UID != 31041 && `hostname` ne "nyphatfhqa5\n") {
    print <<_WARNING_END;


#     #   #####   #######        #     #     #     #######   ###
#     #  #     #  #              #  #  #    # #    #         ###
#     #  #        #              #  #  #   #   #   #         ###
#     #   #####   #####          #  #  #  #     #  #####      #
#     #        #  #              #  #  #  #######  #
#     #  #     #  #              #  #  #  #     #  #         ###
 #####    #####   #######         ## ##   #     #  #         ###

TEAM PAGE: {TEAM BDEI:BUILDING USING WAF<GO>}
TEAM URL:  http://cms.prod.bloomberg.com/team/display/bdei/Building+Using+WAF
CONTACT:   Chen He, Henry Verschell, Mike Giroux

Pausing for 3 seconds for you to consider your decision...

_WARNING_END

    sleep(3);
}


Getopt::Long::Configure("bundling");
unless (GetOptions(\%opts, qw[
    after|A=s
    before|B=s
    compiler|c=s
    clearmake|C
    debug|d+
    define|D=s@
    express|e+
    ncexpress|E
    fail|F
    groupdeps|G
    help|h
    honordeps|honourdeps|H
    jobs|parallel|j|pa:i
    makejobs|J:i
    keepgoing|k
    ifcapable|K
    linktarget|l=s
    mkdevdir|m
    make|M=s
    nodepend|n
    nolog|N
    output|o=s
    no-output|O
    path|p=s
    production|P
    quit|Q|q
    rebuild|R
    serial|s
    silent|S|quiet
    target|t=s
    testtarget|T=s
    uplid|u=s
    uptodate|U
    verbose|v+
    where|root|w|r=s
    noretry|X
    retry|x
])) {
    usage();
    exit EXIT_FAILURE;
}

if($opts{noretry} && $opts{retry}) {
    usage("only one of -x or -X (the default) can be provided");
    exit EXIT_FAILURE;
}

usage(), exit EXIT_SUCCESS if $opts{help};

$opts{where} ||= ROOT;
$root = $opts{where};
my $target       = $opts{target}     || "dbg_exc_mt";
my $test_target  = $opts{testtarget} || undef;
my $link_target  = $opts{linktarget} || undef;

#---

# package group/package options
my $express      = $opts{express};
$opts{nodepend} ||= 0;
$opts{nolog}    ||= $ENV{BDE_NOLOG};

# mkdevdir options
my $mkdevdir     = $opts{mkdevdir};
my $groupdeps    = $opts{groupdeps};

# debug mode
set_debug($opts{debug} || 0);

# verbose mode
set_verbose($opts{verbose} || 0);

# macro defines
if ($opts{define}) {
    foreach (@{$opts{define}}) {
        my ($name,$value)=split '=',$_,2;
        $value ||= 1;
        alert(qq[$name defined as "$value"]);
        $ENV{$name}=$value;
    }
}

# disable retry
if($opts{retry}) {
    $opts{noretry}=0;
}
else {
    $opts{noretry}=1;
}

if ($opts{noretry}) {
    $Util::Retry::ATTEMPTS = 0; # For Util::Retry
    $ENV{RETRY_OPT}="-X";       # should it be re-enabled elsewhere
    $ENV{RETRY_ON_SIGNAL}="";   # undefine standard macros
    $ENV{RETRY_ON_EXIT}="";     # ...
    $ENV{RETRY_ALLTEST}="";     # ...
}

#---
# Set up root - for legacy reasons may be true root or groups root

my $subdir="";

if ($root) {
    $root=~m|^(.*)${FSRE}([^${FSRE}]+)$FSRE?$|
      and ($root,$subdir)=($1,$2);
} elsif ($ENV{BDE_ROOT}) {
    $ENV{BDE_ROOT}=~m|^(.*)${FSRE}([^${FSRE}]+)$FSRE?$|
      and ($root,$subdir)=($1,$2);
} else {
    $root=$FindBin::Bin;
    $root=~s|(/tools)?/|$FS|g; #NB FindBin returns / even when FS is \...
    $root=~s|${FSRE}[^${FSRE}]+$FSRE?$||;
}

if ($subdir) {
    unless ($subdir=~/groups/) {
        $root=$root.$FS.$subdir;
        $subdir="";
    }
}
$root=~s/$FSRE$//;

debug "Initial root is $root";

# if opts{output} is in effect, and the platform/filesystems support symlinks,
# uplid directories will be symlinks, which must be disambiguated by view,
# since /bbcm/infrastructure would otherwise collide.
#
# If the view is being accessed via "/view/<viewname>", the view information
# will be redundant, but cause no harm.
#
# if ~/.bde_build_output_location, use that to set opts{output} if not already
# set

my $symlink_exists = eval { symlink("",""); 1 };

# if symlinks aren't allowed on platform, there's no point in the -o option
# Also, if clearmake is used, the output options is probably harmful
debug "Suppressed output location with --no-output or -O"
                                                       if $opts{'no-output'};

my $allow_output = !$opts{'no-output'}
                   && $symlink_exists
                   && !(exists $opts{clearmake});

if($allow_output) {
    if(!$opts{output}) {
        my $homedir=(getpwuid $<)[7];
        my $outputLink="$homedir${FS}.bde_build_output_location";
        if (-l $outputLink) {
            $opts{output}=readlink $outputLink;
            debug "Set output location to $opts{output} based on $outputLink";
        }
    }

    if($opts{output}) {
        if(!(-d $opts{output} && -w $opts{output})) {
            error "Output directory for -o doesn't exist ($opts{output})";
        }

        debug "Output directory: $opts{output}";

        if(!-d $opts{output}) {
            mkdir($opts{output},0777);
            error "Unable to create output directory $opts{output}, error $!"
                    unless -d $opts{output} && -w $opts{output};
        }
    }
} # check for $allow_output
else {
    $opts{output}=undef;
}

$root=new BDE::FileSystem($root);
# BDE_PATH is probably wrong since proot got nuked
if(exists $opts{path}) {
    $root->setPath($opts{path}.$PS.$constant_path);
}
elsif(exists $ENV{BDE_PATH}) {
    $root->setPath($ENV{BDE_PATH}.$PS.$constant_path);
}
else {
    $root->setPath($constant_path);
}

$root->setGroupsSubdir($subdir) if $subdir;
BDE::Util::DependencyCache::setFileSystemRoot($root); #<<<TODO: temporary
my $finder=new Build::Option::Finder($root);
$factory=new Build::Option::Factory($finder);

debug "Using groups = ".$root->getGroupsLocation();

$FindBin::Bin = qq["$FindBin::Bin"] if $FindBin::Bin=~/ /;
$ENV{BDE_BINDIR}=$INVOKE.$FindBin::Bin.$FS; #pass to Makefiles
$ENV{BDE_BINDIR}=~s|/|$FS|g; #FindBin returns / even when FS is \...

#---

$uplid=(exists $opts{uplid})
  ? BDE::Build::Uplid->unexpanded($opts{uplid})
  : BDE::Build::Uplid->new({where=>$root,compiler=>$opts{compiler}});

$opts{jobs}=1 if $opts{serial};

unless ($opts{jobs}) {
    if ($uplid->kin() eq "windows" || $uplid->os() eq "cygwin") {
        alert "Defaulting to serial build for $uplid";
        $opts{jobs}=1;
    } else {
        $opts{jobs}=DEFAULT_JOBS;
    }
}

unless ($opts{jobs}>=1) {
    usage("number of --jobs must be >= 1");
    exit EXIT_FAILURE;
}

if(!exists $opts{makejobs}) {
    $opts{makejobs}=$opts{jobs};
}
else {
    verbose("Will invoke make with -j$opts{makejobs} option");
}

#==============================================================================

my %groupsMakefilesGeneratedFor;

my ($grp,$pkg,$comp,$grp_build);

foreach my $arg(@ARGV) {
    # if arg is '.', use the parent directory as the build argument
    if ($arg eq ".") {
        my $location=Cwd::cwd();
    # strip build directory if we happen to be in one
        $location =~ s{/(unix|windows)-([^-]+)-([^-]+)-([^-]+)-(\w+)/?$}{};
        $arg=basename($location);
        message("Building from directory argument '$arg'");
    }

    # if arg is only 3 characters we're building a package group
    if (isGroup($arg)) {
        alert "Building: $arg (group build)";
        usage("Can't build group locally"), exit EXIT_FAILURE
        if $mkdevdir;
        if ($opts{nodepend}) {
        #<<<TODO: This may need to be revisited when more than one thing
        #<<<TODO: can be built at once.
            warning "Building group without interpackage dependencies";
        }
        $grp_build = 1;
        $grp = $arg;
    } elsif (isPackage($arg)) {
        alert "Building: $arg (package build)";
        usage("Can't build package locally"), exit EXIT_FAILURE
        if $mkdevdir;
        $pkg = $arg;
        $grp = getPackageGroup($pkg);
    } elsif (isComponent($arg)) {
        alert "Building: $arg (component build)";
        unless ($mkdevdir) {
            eval { $root->getComponentIntfFilename($arg) };
            fatal "Component $comp does not exist\n" if $@;
        }
        $comp = $arg;
        $pkg = getComponentPackage($comp);
        $grp = getPackageGroup($pkg);
    } elsif (isFunction($arg)) {
        message "Building: $arg (function build)";
        $pkg = $arg;
        $grp = undef;
    } elsif (isApplication($arg)) {
        message "Building: $arg (application build)";
        $pkg = $arg;
        $grp = undef;
    } else {
        usage("Unknown build unit: $arg");
        exit EXIT_FAILURE;
    }
    my $uor = $grp || $pkg; # introduced relatively recently

    message "Build root: $root";
    message "Build path:",$root->getPath();
    if ($opts{jobs}==1) {
        message "Serial build";
    } elsif ($opts{jobs}>1) {
        message "Parallel build: up to $opts{jobs} jobs";
    }

    message "Building for: $uplid";

    #--------------------------------------------------------------------
    # Build type determination

    # get the normalised build target (e.g. exc_dbg -> dbg_exc)
    $ufid=new BDE::Build::Ufid($target);
    message("Build type: $ufid");

    # can link with libraries built with another ufid
    $link_ufid = $ufid;
    if ($link_target) {
        $link_ufid = new BDE::Build::Ufid($link_target);
        fatal "Cannot obtain ufid '$link_target'" unless $link_ufid;
        message("Linking build type: $link_ufid");
    }

    # can build executables (test drivers) with another ufid
    $test_ufid = $ufid;
    if ($test_target) {
        $test_ufid = new BDE::Build::Ufid($test_target);
        fatal "Cannot obtain ufid '$test_target'" unless $test_ufid;
        message("Executable build type: $test_ufid");
    }

    if ($mkdevdir) {
        message("Constructing $comp makefile with ".
            ($groupdeps?"group":"package")
            ." dependencies");
        message("Building against: $root");
        makeLocalMakefile($comp, $groupdeps, $ufid, $link_ufid, $test_ufid);
        alert("Makefile constructed for $comp");
        exit EXIT_SUCCESS;
    }

    #---------------------------------------------------------------------
    # Check capabilities

    unless ($factory->isCapable($uor,$uplid,$ufid)) {
        if ($opts{ifcapable}) {
            warning "Capabilities of $uor deny build of $ufid on $uplid - ignored";
            exit EXIT_SUCCESS;
        } else {
            fatal "Capabilities of $uor deny build of $ufid on $uplid";
        }
    }

    #---------------------------------------------------------------------
    # Build start

    my $start_time=time;
    alert($ufid->toString(1)." build of $arg started on",
        scalar localtime($start_time));
    my @pkgs=();
    if ($pkg) {
        if (getPackageGroup($pkg)) {
            push @pkgs, getAllPackageDependencies($pkg);
        }
    # isolated packages don't have dependent packages
    } elsif ($grp) {
        push @pkgs, getCachedGroup($grp)->getMembers();
    }

    if ($pkg) {
        if ($opts{nodepend}) {
            message("building in $pkg without dependencies");
        # ONLY build one package for nodepend
            @pkgs = $pkg;
        } elsif (@pkgs) {
            message("dependencies: @pkgs");
        }
        unshift @pkgs,$pkg;
    }

        # prepare caches of package dependencies so they are available to all
        # forked child processes in a parallel build.
    foreach my $pkg (@pkgs) {
        # gather dependencies
        getAllPackageDependencies($pkg);
        # preload options
        $factory->load($pkg) unless $opts{uptodate};
    }

    # purify builds: tweak the stack if we have the required binding available
    if ($target=~/pure/) {
        if (eval { require 'sys/syscall.ph' }) {
            my $rlimit = pack("LL", ());
            my $RLIMIT_STACK = 3;  #on solaris, from sys/resource.h
            $rlimit = pack("LL", 16777216, 16777216);
            syscall(&SYS_setrlimit, $RLIMIT_STACK, $rlimit);
            $! and fatal "setrlimit failed: $!";
        } else {
            warning "sys/syscall.ph unavailable - unable to adjust stack limit";
        }
        $opts{jobs} = 1;  #force serial
    }

    #--------------------
    # make makefiles

    if (!$opts{uptodate}) {
        makeGroupMakefile($root, $grp||$pkg, $uplid, $ufid, $opts{jobs});
        fatal "Error building makefiles" if
        makeMakefiles($opts{jobs},
            [ $groupdeps,$ufid,$link_ufid,$test_ufid ], @pkgs);
        if ($opts{honordeps}) {
            alert("Making lower-level makefiles - this may take a few minutes...");
            for my $tmp (getAllGroupDependencies($grp||$pkg)) {
                next if $groupsMakefilesGeneratedFor{$tmp}++;
                next if getCachedGroupOrIsolatedPackage($tmp)->isPrebuilt;
                makeGroupMakefile($root, $tmp, $uplid, $ufid, $opts{jobs});
                fatal "Error building makefiles for $tmp" if
                makeMakefiles($opts{jobs},
                    [ $groupdeps,$ufid,$link_ufid,$test_ufid ],
                    isGroup($tmp) ? getCachedGroup($tmp)->getMembers()
                    : ($tmp) );
            }
        }
    }

    #--------------------
    # determine general make targets

    my %make_deps=();

    if ($opts{make}) {
        # make targets serially dependent in -M mode
        my @targets = split /[^\w\.-]+/,$opts{make};

        $make_deps{$targets[0]} = [];
        if (@targets > 1) {
            my $previous=$targets[0];
            foreach my $idx (1..$#targets) {
                print "PREVIOUS[$idx]:$previous\n";
                $make_deps{$targets[$idx]} = [ $previous ];
                $previous = $targets[$idx];
            }
        }
    } else {
        # before targets are parallel, gather into !before target
        if (my @befores=$opts{before} ? split(/[^\w\.-]+/,$opts{before}):()) {
            $make_deps{$_} = [] foreach @befores;
            $make_deps{"!before"}=[ @befores ];
        }

        # core dependencies for each packages - hooked together below
        $make_deps{preprocess_package_include}=$opts{before} ? ["!before"] : [];
        $make_deps{build_package_objects}=[
        "preprocess_package_include"
        ];
        $make_deps{build_package_library}=[ "build_package_objects" ];
        unless ($express) {
            $make_deps{build_test}=[ "build_package_objects" ];
            $make_deps{test}=[ "build_test" ];
        }

        unless ($pkg and isIsolatedPackage($pkg)) {
            $make_deps{install_package} = [ "build_package_library" ];
        }

        if ($pkg and isIsolatedPackage($pkg)) {
            $make_deps{install_group} = [ "build_package_library" ];
        }

        # after targets are parallel, initiate from !after target
        if (my @afters =$opts{after}  ? split(/[^\w\.-]+/,$opts{after}):()) {
            $make_deps{"!after"}=[
            ($pkg and isIsolatedPackage($pkg))
            ? "install_group" : "install_package" ];
            $make_deps{$_}=[ "!after" ] foreach @afters;
        }
    }

    debug("Building targets: ",keys %make_deps);

    #---------------------
    # do make

    my $mgr=new Task::Manager("Building ".$ufid->toString(1));
    $mgr->setQuitOnFailure($opts{quit});

    if ($comp) {
        @pkgs = grep { $_ ne $pkg } @pkgs;
    }

    # generate actions from per-package structure above, for each package in
    # build
    for my $target (keys %make_deps) {
        my $skip_package="";
        my $unskip_package="";

        my @args=();
        my $action = ($target=~/^!/) ? \&nopPackageTarget : \&buildPackageTarget;

        for my $thispkg (@pkgs) {
            # specific specialisation: non-compliant package tests and -E
            if ($target=~/^(build_)?test$/o and $opts{ncexpress}
                    and isNonCompliant($thispkg)) {
                debug "skipping non-compliant package tests in ncexpress mode";
                next;
            }

            # calculate required actions:
            my @deps=();
            # 1 - internal dependencies
            if (exists $make_deps{$target}) {
                push @deps, map { "$thispkg.$_" } @{$make_deps{$target}};
            }

            # 2 - dependant packages - cross-link inter-package dependencies
            unless ($opts{nodepend}) {
                if (($target eq "build_package_objects") or
                    ($comp and ($target =~/^build_test/))) {
                    if (my @deppkgs=getAllInternalPackageDependencies($thispkg)) {
                        push @deps, "$_.install_package" foreach @deppkgs;
                    }
                }
            }

            # allow depending build_package_objects actions to carry-on even
            # on a failure of their dependant install_package actions
            my $failok=($target eq "install_package")?1:0;
            $failok=0 if $opts{fail}; #don't permit carry-on if disabled

            # dep groups must be built first
            push @deps, "build_dependencies" if $opts{honordeps} and
            ($target eq "!before" or $target eq "preprocess_package_include");

            $mgr->addAction(new Task::Action({
                        name     => "$thispkg.$target",
                        action   => $action,
                        args     => [ $thispkg,
                                      $target,
                                      $uplid,
                                      $ufid,
                                      $opts{makejobs}
                                    ],
                        requires => \@deps,
                        failok   => $failok,
                    }));
        } #foreach $thispkg
    }

    # add group-level make on to end of tree
    if ($opts{honordeps}) {
        my $target = $opts{make} || "build_dependencies";
        $mgr->addAction(new Task::Action({
                    name     => "build_dependencies",
                    action   => \&groupMake,
                    args     => [ $root, $grp||$pkg, $uplid, $ufid,
                    $opts{makejobs}, $target ],
                    requires => [],
                    failok   => 0,
                }));
    }

    if ($grp_build) {
        my $target = $opts{make} || "install_group";
        if ($target eq "install_group") { #??or $target =~ /^(clean|realclean)$/)
            $mgr->addAction(new Task::Action({
                        name     => "install_group",
                        action   => \&groupMake,
                        args     => [ $root, $grp, $uplid, $ufid,
                        $opts{makejobs}, $target ],
                        requires => [ map { "$_.install_package" } @pkgs ],
                        failok   => 0,
                    }));
        }
    }

    # add tasks for application mains, if present.
    if ($pkg and !$comp and !$opts{make}) {
        # Retrieve options to determine if application mains are to be built
        my $options=$factory->construct({
                uplid   => $uplid,
                ufid    => $ufid,
                what    => $pkg,
            });

        if (isApplication($pkg) or $options->getValue("APPLICATION_MAIN")) {
            $mgr->addAction(new Task::Action({
                        name     => "$pkg.build_application",
                        action   => \&buildPackageTarget,
                        args     => [ $pkg, "build_application", $uplid, $ufid,
                        $opts{makejobs}],
                        requires => [ "$pkg.build_package_objects" ],
                        failok   => 0,
                    }));

            # applications are one package in size and have a special build
            # rule
            if (isApplication($pkg)) {
                $mgr->removeAction("$pkg.build_package_library");
                $mgr->removeAction("$pkg.install");
                $mgr->removeAction("$pkg.install_group");
                $mgr->removeAction("$pkg.install_package");
            }
        }
    }

    # component-only mode - add component-specific targets; currently this is
    # the only such mode: 'clean.<component>' and similar will come later.
    if ($comp) {
        if ($opts{express} and $opts{express}>=2) {
            # build object
            $mgr->addAction(new Task::Action({
                        name     => "$comp.build",
                        action   => \&buildPackageTarget,
                        args     => [ $comp, "build", $uplid, $ufid, $opts{makejobs}],
                        requires => $opts{nodepend} ?
                        [] : [ map { "$_.install_package" } @pkgs ],
                        failok   => 0,
                    }));
        } else {
            # build_test and test
            $mgr->addAction(new Task::Action({
                        name     => "$comp.build_test",
                        action   => \&buildPackageTarget,
                        args     => [ $comp,"build_test",$uplid,$ufid,$opts{makejobs}],
                        requires => $opts{nodepend} ?
                        [] : [ map { "$_.install_package" } @pkgs ],
                        failok   => 0,
                    }));
            $mgr->addAction(new Task::Action({
                        name     => "$comp.test",
                        action   => \&buildPackageTarget,
                        args     => [ $comp, "test", $uplid, $ufid, $opts{makejobs} ],
                        requires => [ "$comp.build_test" ],
                        failok   => 0,
                    }));
        }
    }

    # dump out the task list of what we're about to do if asked
    $mgr->dump() if Util::Message::get_debug() > 1;

    # do it
    my $result=$mgr->run($opts{jobs});

    # post-build (a hack prior to introduction of group-level operation)
    # takes place at the end of the build, if a group-level build was done.
    # this is hackish because it uses the old options system to get a
    # variable from the top level unit-of-release
    if (!$opts{make} and
        ($grp_build or (!$comp and isIsolatedPackage($pkg)))) {

        my $options=$factory->construct({
                uplid => $uplid,
                ufid  => $ufid,
                what  => $grp || $pkg, #group or isolated package
            });

        if (my $postbuild=$options->getValue("POST_BUILD")) {
            my $postbuildopt=$options->getValue("POST_BUILD_OPT") || "";
            if ($postbuildopt) {
                message "Post-build executing: $postbuild $postbuildopt";
                print "<< ",retry_output3($postbuild,$postbuildopt);
            } else {
                message "Post-build executing: $postbuild $postbuildopt";
                print "<< ",retry_output3($postbuild);
            }
            message "Post-build done";
        }
    }

    if ($result) {
        error $ufid->toString(1)." build of $arg FAILED on ".
        scalar(localtime);
        exit EXIT_FAILURE;
    } else {
        my $duration=time-$start_time;
        message("elapsed time: $duration seconds");
        alert $ufid->toString(1)." build of $arg finished OK on ".
        scalar localtime;
    }
}

#============================================================================

=head1 AUTHOR

Current maintainers:
Peter Wainwright (pwainwright@bloomberg.net)
Ralph Gibbons (rgibbons@bloomberg.net)

Previous version and additional contributions:
Sasha Belikoff (abel@bloomberg.net)

=head1 SEE ALSO

L<bde_setup.pl>, L<bde_verify.pl>, L<bde_rule.pl>, L<bde_snapshot.pl>

=cut
