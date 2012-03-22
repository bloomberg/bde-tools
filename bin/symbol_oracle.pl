#!/usr/bin/env perl

use strict;
use warnings;

use Symbol ();
use FindBin;
use lib "$FindBin::Bin/../lib/perl";

use Getopt::Long;
use IO::Handle ();
use File::Path ();
use POSIX ":sys_wait_h";

use Binary::Aggregate;
use Binary::Archive;
use Binary::Symbol::Scanner;
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::FileSystem::MultiFinder;
use Build::Option::Factory;
use Build::Option::Finder;

use BDE::Util::Nomenclature qw(isGroup isPackage isIsolatedPackage
			       isLegacy isApplication isThirdParty isFunction
			       getCanonicalUOR);
use BDE::Util::DependencyCache qw(getGroupDependencies getPackageDependencies
				  getCachedGroupOrIsolatedPackage);

use BDE::Build::Invocation qw($FS);

use Change::DB;
use Change::Set;
use Change::Symbols qw[ COMPCHECK_DIR CSCOMPILE_TMP DBPATH
			MOVE_EMERGENCY MOVE_BUGFIX MOVE_REGULAR
			STATUS_COMPLETE STATUS_INPROGRESS ];
use Change::Symbols qw[ CSCOMPILE_TMP DBPATH CS_DATA
			MOVE_EMERGENCY MOVE_BUGFIX MOVE_REGULAR
			STATUS_COMPLETE STATUS_INPROGRESS ];

use Production::Services;
use Production::Services::Move;

#use constant COMPCHECK_DIR => "/bb/csdata/devoracle";

use Symbols qw[
    EXIT_FAILURE EXIT_SUCCESS CONSTANT_PATH DEFAULT_FILESYSTEM_ROOT
    FILESYSTEM_PATH_ONLY FILESYSTEM_NO_DEFAULT
];

use Production::Symbols qw[SYMBOL_ORACLE_SOURCE_HOST1 SYMBOL_ORACLE_SOURCE_PORT1
			   SYMBOL_ORACLE_SOURCE_HOST2 SYMBOL_ORACLE_SOURCE_PORT2
			   SYMBOL_ORACLE_STAGE_HOST1 SYMBOL_ORACLE_STAGE_PORT1
			   SYMBOL_ORACLE_STAGE_HOST2 SYMBOL_ORACLE_STAGE_PORT2
			   SYMBOL_ORACLE_LOCAL_HOST1 SYMBOL_ORACLE_LOCAL_PORT1
			   SYMBOL_ORACLE_LOCAL_HOST2 SYMBOL_ORACLE_LOCAL_PORT2
			   SYMBOL_ORACLE_PROD_HOST1  SYMBOL_ORACLE_PROD_PORT1
			   SYMBOL_ORACLE_PROD_HOST2  SYMBOL_ORACLE_PROD_PORT2
			   SYMBOL_ORACLE_LOCAL_PORT  SYMBOL_ORACLE_STAGE_PORT
			   SYMBOL_ORACLE_SOURCE_PORT SYMBOL_ORACLE_PROD_PORT
			   SYMBOL_ORACLE_LIBS
			  ];

use Util::File::Basename qw(dirname basename);
use Util::Message qw(
    message alert verbose verbose2 verbose_alert get_verbose debug fatal warning
    error get_prog set_prog get_prefix set_prefix
);

my (%base_libraries) = (source => "/bb/source/lib",
			  stage => "/bb/source/stage/stagelib",
			  local => "/local/lib",
		          prod => "/bb/source/stage/prodlib");
my $base_library_directory;
my $dest_library_directory;

#$SIG{CHLD} = 'IGNORE';

#==============================================================================

=head1 NAME

symbolvalidate.pl - Check validity of undefined symbols in a binary aggregate

=head1 SYNOPSIS

    # explicitly check a collection of objects against nominated libraries
    $ symbolvalidate.pl -lfoo -lbar -Sundefsymbol -Sbadlib:undefsym2 *.o

    # implicitly check a package or package group using its metadata
    $ symbolvalidate.pl apputil

    # verbosely report on symbols required by gtkcore that are defined in
    # gtkapp and not listed as waived symbols.
    $ symbolvalidate.pl -lgtkapp gtkcore -v -D --nodl

=head1 DESCRIPTION

C<symbolvalidate.pl> checks for consistency in defined symbols between an
arbitrary collection of libraries and objects. It operates in one of two modes,
targeted or untargeted, and reports on either defined or undefined symbols, or
both. Additionally, if run in a BDE-compliant environment, it can also use
package metadata to derive most of the necessary information necessary for
it to carry out validation with the correct arguments, eliminating the need
to specify them on the command line.

=head2 Targeted and Untargeted Validation

C<symbolvalidate.pl> operates in either a I<targeted> or I<untargeted> mode,
depending on how its arguments are specified.

=over 4

=item Untargeted

In I<untargetted> mode, all binary files to be analysed are provided to the
script as C<-l> (for archives) or C<-o> (for object files) options.
C<symbolvalidate.pl> will then check that out of the aggregation of all 
objects, no symbols are referenced but not defined.

This mode mimics a complete link, so it will likely be necessary to specify
standard system libraries such as those automatically linked in byca linker.
On SunOS, for example, C<-lc>, C<-lCrun>, and C<-ldl> will often be necessary.

=item Targeted

In I<targetted> mode, one or more binary files (libraries or objects or both)
are specified to the tool as bare arguments -- that is, not provided through
a C<-l> or C<-o> option. In this case, symbol resolution is carried out as
for the untargeted mode, but only undefined symbols in the I<target aggregate>
(the aggregate of all bare argument binary files) are resolved. Any libraries
or object provided by C<-l> or C<-o> are placed into a I<dependency aggregate>
and used to resolve symbols. They are not however checked for undefined symbol
references that they themselves create.

=back

The targeted mode is the more useful of the two, and is typically used for
validating a single library against its dependencies. The untargeted mode is
useful for performing a full validation of an entire self-contained set of
binary files, and is therefore analogous to an actual link.

Both modes make use of metadata in the C<E<lt>UORE<gt>_SYSTEM_LIBS>,
C<E<lt>UORE<gt>_OTHER_LIBS> and C<PLINK_OBJS> macros.  C<UOR> stands
for unit-of-release, e.g. the library name.  *_LIBS macros should
contain any necessary -l and -L rules used when linking the library.
PLINK_OBJS should contain any big object files needed when compiling.

In targetted mode, these values are parsed and included in the aggregate
for the target library.  In untargetted mode, these values are parsed and
included for each library listed.

=head2 Output Reports and Exit Status

The output of C<symbolvalidate.pl> is by default a list of all the undefined
symbols in the target aggregate. This is one of two reports that the tool
can produce, each enabled explicitly by a corresponding option:

=over 4

=item *

The C<--defined> or C<-D> option generates a report of all resolved
symbols. For the targeted mode, where this is most useful, this allows
two libraries to be compared and for the list of symbols referenced in
one and defined in the other to be generated. See below for why this
is particularly useful. In the untargeted mode, all defined symbols
are listed.

=item *

The C<--undefined> or C<-U> option generates a report of all unresolved
symbols. In targeted mode, this is the list of symbols referenced in
the target aggregate that are not defined by the dependency aggregate
(or waived as 'bad' symbols, see below). In untargeted mode, it is the
list of all undefined symbols.

=back

The unresolved symbol report is generated by default, but not if the C<-D>
option is used. To generate I<both> reports, therefore, use C<-D> and C<-U>
together.

I<Note that the exit status is determined by whether or not unresolved symbols
are present, irrespective of the reports that are enabled.  No unresolved 
symbols is success; having unresolved symbols is failure>

=head2 Standard, Verbose, and Terse Output

By default, the symbol reports are generated without additional commentary.
If both reports are enabled then they can be differentiated due to the
different syntaxes for resolved and unresolved symbols.

If the C<--terse> or C<-T> option is specified, the output is further
reduced into a format suitable for machine parsing.

For human consumption, however, the C<--verbose> or C<-v> option generates
more meaningful output, including details of how and where each requested
library was found. A short title is also placed before each report that is
enabled, and a summary status line is generated at the end of the output,
including the number of symbols that were ignored through a waiver (see below).

With the exception of the report titles, all of this output is sent to
standard error instead of standard out, and is prefixed with a message type
prefix (C<--> for messages, C<??> for warnings, etc. -- see
L<Util::Message>) for easy discrimination.

=head2 Library Searches

When a library is specified, either with the C<-l> option or as a bare
argument, C<symbolvalidate.pl> looks for the library in a standard set of
locations that includes C</bbs/lib> and </usr/lib>, augmented by any special
default locations on a per-platform basis (for example, C</opt/SUNWspro/lib>
for SunOS>. Additional library search locations may be specified with the
C<-L> option, which has the same meaning and semantics as the linker flag of
the same name.

In targeted mode, if a unit of release (an isolated package or package group)
is specified as a bare argument, its direct dependencies are automatically
sought out using its <.dep> metadata and added to the dependency aggregate to
resolve symbols. This means that, for example, resolving C<bte> will
automatically pull in C<bde> and C<bce> to resolve symbols.

Both static and shared library extensions are searched for, with shared
libraries taking preference over static ones in the same location, unless the
C<--static> or C<-s> option is specified, in which case this preference is
reversed.

Additionally, libraries are looked for with a UFID extension (see
L<BDE::Build::Ufid>, by default C<dbg_exc_mt> unless the C<--target> or C<-t>
option is used to override it. If verbosity is enabled, the extensions that
are searched are listed out prior to the search. The default search list is:

    .so .a .dbg_exc_mt.so .dbg_exc_mt.a <empty>

The last extension searched is the empty extension (i.e. no extension). This
allows libraries with unusual extensions, such as explicit version numbers
(for example, C<libfoo.so.1.0.2>) to be given explicitly as C<-l> or bare
arguments to C<symbolvalidate.pl> and still found by the search.

As well as honoring the UFID, libraries are also searched for under the
UPLID of the invoking platform, unless the C<--uplid> or C<-u> option is used
to override the UPLID, or the C<--compiler> or C<-c> option is used to modify
the fifth and sixth elements of the UPLID. This allows libraries located in
a valid BDE development root to be detected and used for validation as well
as libraries located in an official location such as C</bbs/lib>.

=head2 Defining 'Bad' Symbols

A bad symbol is a symbol which is not defined in any binary file, either in
the target or dependency aggregate, but which is known to belong to a library
'outside' the defined dependency structure (it may also, conceivably, be 
a 'dummied out' symbol). These symbols can be specified with the C<--symbol> or
C<-S> option. If present, any undefined symbols that would otherwise be
included in the undefined symbols report are removed.

A bad symbol may optionally be prefixed by its object and library name, to
indicate that its true origin is actually known, and is simply not allowed to
resolve any other symbols than those listed, irrespective of whether or not it
actually has them. This allows the strength of an undesired dependency to be
constrained to only those symbols already in use.

Bad symbols may be defined for a packaged library by adding them to the list
of symbols assigned to the option C<_BAD_SYMBOLS> in the package C<.opts>
file. Note that this list can easily be derived on a library-by-library basis
by running the target library against the undesired dependency with the C<-D>
option (to list only the symbols defined by the undesired dependency on the
output) and -T (for terse output):

    $ symbolvalidate.pl -lgtkapp gtkcore -T -D > bad_gtkapp_deps.out

This command will dump out all the dependencies that the C<gtkcore> library
has on the C<gtkapp> library, which may then be added to <gtkcore.opts> as
the value of the C<_BAD_SYMBOLS> option.

When checking the C<_BAD_SYMBOLS> list against the target aggregate, the
tools will additionally report any symbol explicitly specified to be ignored
that is no longer present in the target aggregate.  This allows the symbol
to be removed from the explicit list when the target code is fixed to no
longer contain the bad symbol.

Any library whose symbols are listed in C<_BAD_SYMBOLS> must be listed with
the "weak:" prefix in the C<.dep> file.  This allows the library to be listed
in the C<.dep> file -- so that it can still be built -- but tells this tool
that the library should be excluded from the list of valid library dependencies.

=head1 TO DO

The following features and improvements will be added to a later version of
C<symbolvalidate.pl>:

=over 4

=item *

Currently the library and object qualifications for 'bad' symbols are
ignored. In future they will be used to check that the symbol is
actually provided by that library. Such libraries are 'weak'
dependencies might be declared in the C<.dep> files of libraries
that depend on them with a 'weak:' qualifier. Such dependencies do
not play a part in symbol resolution or dependency management, but
could be taken into account on the link line to derive the 'optimal'
link line for any combination of mutually dependent libraries.

=item *

Default libraries are only pre-set for SunOS currently.

=item *

C<-D> (defined) does not include filtered symbols (e.g. C<_BAD_SYMBOLS>)
It also provides no output when there are no undefined symbols
present after symbol resolution.  In other words, C<-D> with C<-lE<lt>libE<gt>>
is useless when <lib> is listed in package .dep file.

=item *

Use metadata in the C<BDE_ENDLDFLAGS>.

=back

=cut

#==============================================================================

{

# GPS: TESTING
#    my $CH = tie *STDOUT, 'CaptureHandle' || die;
#    $CH = tie *STDERR, 'CaptureHandle'    || die;

package CaptureHandle;

use Tie::Handle;
@CaptureHandle::ISA = 'Tie::Handle';

my $output = "";

sub TIEHANDLE { my $i; bless \$i, shift  }
sub PRINT { shift; $output .= $_ foreach (@_); }
sub get_output_ref { return \$output; }

}

#==============================================================================

{

package Binary::Context;

use Binary::Archive;
use BDE::Build::Invocation qw($FS);
use BDE::Package;
use BDE::Util::Nomenclature qw(isGroup isPackage
			       isIsolatedPackage isApplication);
use Util::Message qw(verbose debug fatal);

sub new ($$$$$$$$$) {
    my($self,$targets,$root,$finder,$factory,
       $uplid,$ufid,$paths,$extensions) = @_;
    my $ctx = {
	targets	=> $targets,
	root	=> $root,
	finder	=> $finder,
	factory	=> $factory,
	uplid	=> $uplid,
	ufid	=> $ufid,
	paths	=> $paths,
	extensions => $extensions,
	found_libs => {},
	loaded_libs => {}
    };
    return bless $ctx;
}

sub get_meta ($$) {
    my($ctx,$lib) = @_;
    $lib = substr($lib,rindex($lib,'/')+1) unless isApplication($lib);
    return $ctx->{factory}->construct({
	what => $lib, ufid => $ctx->{ufid}, uplid => $ctx->{uplid}
    });
}

sub fatal_library_not_found ($$;$) {
    my($ctx,$lib,$paths)=@_;
    $paths = $paths
      ? [@$paths,@{$ctx->{paths}}]
      : $ctx->{paths};
    fatal("Unable to locate library for $lib in ".join(":",@$paths));
}

sub is_metadata_only ($$) {
    my($ctx,$library)=@_;
    ##<<<TODO might wrap in an eval {} so that we do not fail if a new
    ## compliant library is added to lroot, but metadata not created yet
    ## (improve robustness where metadata not set up for compliant package yet)
    my $pkg = isIsolatedPackage($library)
      ? new BDE::Package($ctx->{root}->getPackageLocation($library))
      : eval { new BDE::Group($ctx->{root}->getGroupLocation($library)) };
    return $pkg && $pkg->isMetadataOnly() && !$pkg->isPrebuilt();
}

sub is_offline_only ($$) {
    my($ctx,$library)=@_;
    ##<<<TODO might wrap in an eval {} so that we do not fail if a new
    ## compliant library is added to lroot, but metadata not created yet
    ## (improve robustness where metadata not set up for compliant package yet)
    my $pkg = isIsolatedPackage($library)
      ? new BDE::Package($ctx->{root}->getPackageLocation($library))
      : eval { new BDE::Group($ctx->{root}->getGroupLocation($library)) };
    return $pkg && $pkg->isOfflineOnly();
}

sub find_library ($$;$$) {
    my($ctx,$library,$paths,$extensions)=@_;
    my $lib = substr($library,rindex($library,'/')+1); # basename

    return $ctx->{found_libs}->{$library}
      if (exists $ctx->{found_libs}->{$library});

    $paths = $paths
      ? [@$paths,@{$ctx->{paths}}]
      : $ctx->{paths};

    $extensions ||= $ctx->{extensions};

    foreach my $path (@$paths) {
	foreach my $ext (@$extensions) {
	    my $pathname=$path.'/lib'.$lib.$ext;
	    debug("looking for $pathname...");
	    if (-f $pathname) {
		$ctx->{found_libs}->{$library} = $pathname;
		return $pathname;
	    }
	}
    }

    # (special-case libraries with version at the end)
    if ($library =~ /\d/) {
	foreach my $path (@$paths) {
	    my $pathname=$path.'/'.$lib;
	    debug("looking for $pathname...");
	    if (-f $pathname) {
		$ctx->{found_libs}->{$library} = $pathname;
		return $pathname;
	    }
	}
    }

    # (special-case offline-only libs deployed in src tree instead of /bbs/lib)
    #<<<TODO: do less hard-coding and special-casing for Solaris here
    if ($ctx->is_offline_only($library)) {
	my $pathname = isPackage($library)
	  ? $ctx->{finder}->getPackageLocation($library)
	  : $ctx->{finder}->getGroupLocation($library);
	$pathname.=$FS."lib".$lib.".sundev1.a";
	if (-f $pathname) {
	    $ctx->{found_libs}->{$library} = $pathname;
	    return $pathname;
	}
    }

    return undef;
}

sub get_library_path ($$) {
    my($ctx,$lib) = @_;
    verbose("Looking for lib $lib\n");
    # check multi-rooted path if the library resembles a UOR
    if (isIsolatedPackage($lib) or isGroup($lib)) {
	my($finder,$uplid) = ($ctx->{finder}, $ctx->{uplid});
	# it *might* be a legacy lib, package group, or 'a_' package:
	# add to search path (it might also just happen to look like one
	# but is really just a regular system library).
	my $locn=isPackage($lib) ? $finder->getPackageRoot($lib)
				 : $finder->getGroupRoot($lib);
	$locn.=$FS."lib".$FS.$uplid;
	return $ctx->find_library($lib,[$locn]);
    }
    else {
	return $ctx->find_library($lib);
    }
}

{
    my %archive_cache;

    ## caller MUST NOT MODIFY the returned archive
    ##<<<TODO: FIXME this is broken for removed objects when working with
    ## orphan objects.  This is not the case for symbol validate in cscheckin.
    sub cache_load_library ($$) {
	my($library,$pathname)=@_;
	use Carp;
	if (!defined $pathname) {
	  confess;
	}
	my $entry = $archive_cache{$pathname};
	if ($entry && $entry->[1] > (stat($pathname))[9]) {  ## check mtime
	    return $entry->[0];
	}
	else {
	    my $time = time();
	    my $archive = eval { new Binary::Archive($pathname) };
	    if (!defined $archive) {
	      Util::Message::warning("Can't load library $library from $pathname");
	      return;
	    }
	    verbose("cached $library from $pathname");
	    $archive_cache{$pathname} = [$archive,$time];
	    return $archive;
	}
    }

    sub cache_fetch_library {
      my ($library, $pathname) = @_;
      my $entry = $archive_cache{$pathname};
      return $entry->[0];
    }

    sub cache_get_library_defines ($$$) {
	my($library,$pathname,$defined_symbols)=@_;
	my $entry = $archive_cache{$pathname};
	if ($entry && $entry->[1] > (stat($pathname))[9]) {  ## check mtime
	    ## shallow copy; Symbol objects are copied
	    ## caller should not modify them
	    $entry->[0]->getDefinedSymbols($defined_symbols);
	    return @$entry;
	}
	return undef;
    }
}

sub load_library ($$$$) {
    my($ctx,$library,$pathname,$aggregate)=@_;
## GPS: FIXME FIXME FIXME
## Are we adding this to the correct aggregates?
## Check that the $ctx cache is working as we want with the $aggregate passed
    if (!exists $ctx->{loaded_libs}->{$library}) {
	verbose("loading $library");
	my $archive = cache_load_library($library,$pathname);
	fatal("Unable to add $pathname") unless $archive;
	$aggregate->addObject($archive);
	$ctx->{loaded_libs}->{$library} = 1;
	verbose("loaded $library from $pathname");
    }
    return $aggregate;
}

sub load_library_defines ($$$$) {
    my($ctx,$library,$pathname,$defined_symbols)=@_;
    my($def,$k,$v);
    my $entry = $ctx->{loaded_defines}->{$library};
    if (defined($entry) && $entry->[0] eq $pathname) {
	my $mtime = (stat($pathname))[9];
	$def = $entry->[2] if ($entry->[1] > $mtime);
    }
    if (!defined($def)) {
	my $time;
	($def,$time) =
	  cache_get_library_defines($library,$pathname,$defined_symbols);
	unless (defined($def)) {
	    $def = {};
	    $time = time();
	    (new Binary::Symbol::Scanner)->scan_for_defined($pathname, $def);
	    verbose("loaded $library from $pathname");
	}
	$ctx->{loaded_defines}->{$library} = [$pathname, $time, $def];
    }
    keys(%$defined_symbols) =  # (preallocate more hash buckets)
      (scalar keys %$defined_symbols) + (scalar keys %$def);
    while (($k,$v) = each %$def) {
	$defined_symbols->{$k} = $v;  # shallow copy
    }
}


}

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-w <dir>] [-X] [-s] [-C] [-B]
                              [-l<lib> ...] [-L<libpath> ...]
                              [-o<object> ...] [-S <[lib:]symbol> ...]
                              <object|library> ...
  --csid          | -C                 registered change set id
  --file          | -f                 read changeset from file
  --daemon                             run in daemon mode
  --foreground    | -F                 run daemon in foreground (for svc)
  --debug         | -d                 enable debug reporting
  --help          | -h                 usage information (this text)
  --library       | -l <library>       retrieve symbols from the specified
                                       library (with or without extensions)
  --libpath       | -L <paths>         places to look for libraries
  --[no]nodl      | -M                 do not [not] load default libraries
  --[no]nodp      | -P                 do not [not] use default library paths
  --[no]nobadmeta | -B                 do not parse _BAD_SYMBOLS from metadata
  --object        | -o <object>        retrieve symbols from the specified
                                       object file
  --owner         | -O <library>       nominate a library name to associate
                                       with object files specfied as arguments
                                       (i.e not those specified with C<-o>).
  --static        | -s                 prefer static libraries over dynamic
                                       (default: prefer dynamic)
  --symbol        | -S <[lib:]symbol>  symbols that may be undefined,
                                       optionally prefixed by the library that
                                       resolves the specified symbol (only).
  --verbose       | -v                 enable verbose reporting
  --noretry       | -X                 disable retry on file operations
  --match         | -m <text>          display only symbols that contain the
                                       specifed text in either the symbol,
                                       object, or library name.
  Display options:

  --[no]defined   | -D                 do [not] report symbols in target
                                       defined by dependencies (default: off)
  --[no]undefined | -U                 do [not] report symbols in target not
                                       defined by dependencies (default: on)
  --[no]terse     | -T                 do [not] produce terse reports that
                                       can be directly used in configuration.

  Connection options:

  --host                               Remote oracle host to connect to
  --port                               Port remote oracle is listening on

  Library options

  --libdir                             Base directory for libraries
  --source                             Use the source libs
  --local                              Use the local libs
  --stage                              Use the stage libs
  --tag=(source|stage|local|prod)      Use source, stage, local or prod libs
  --beta                               This is a beta validation
  --prod                               This is prod validation

  Search extension options for component-based libraries:

  --compiler      | -c <comp>          compiler name (default: 'def')
  --target        | -t <ufid>          build target <target>
                                       (default: 'dbg_exc_mt')
  --uplid         | -u <uplid>         target platform (default: from host)
  --where         | -w <dir>           specify explicit alternate root

See 'perldoc $prog' for more information.

_USAGE_END
## TODO: document besteffortlink option once it works
}

# This distinction may or may not be necessary for this tool
#  --units       | -u <units>         retrieve symbols for the specified comma-
#                                     separated list of groups/packages only

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    @ARGV || (usage(), exit EXIT_FAILURE);
    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
	csid|C=s
	file|from|f=s
        compiler|c=s
	daemon
        debug|d+
        defined|D!
	port=s
        host=s
        foreground|F
	nodl|M!
        nodp|P!
	nobadmeta|B!
	daemon_no_connect
        help|h
        libraries|library|l=s@
        libpath|L=s@
	lookup
        match|m=s
        objects|o=s@
        owner|O=s
	refresh
        report|R!
        static|s!
	symbols|S=s@
        target|ufid|t=s
        terse|T!
        undefined|U!
        uplid|platform|u=s
        where|root|w|r=s
        verbose|v+
        noretry|X
	besteffortlink
	ignorelibs=s
	offline
	datasym!
        libdir=s
        source
        local
        stage
	tag|buildtag=s
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};


    return \%opts;
}

#----

sub parse_options {
    my $opts = shift;

    $base_library_directory = $opts->{libdir} if $opts->{libdir};
    if (!exists $base_libraries{$opts->{libtype}}) {
      fatal "Bad library type $opts->{libtype}";
    }
    if (!defined $base_library_directory) {
      $base_library_directory = $base_libraries{$opts->{libtype}};
    }
    $dest_library_directory = SYMBOL_ORACLE_LIBS . "/" . $opts->{libtype} . "/$^O";

    # filesystem root
    $opts->{where} = DEFAULT_FILESYSTEM_ROOT unless $opts->{where};

    # disable retry
    if ($opts->{noretry}) {
	local $^W=0;
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts->{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts->{verbose} || 0);

    # set UPLID
    if ($opts->{uplid}) {
	fatal "--uplid and --compiler are mutually exclusive"
	  if $opts->{compiler};
	$opts->{uplid} = BDE::Build::Uplid->unexpanded($opts->{uplid});
    }
    elsif ($opts->{compiler}) {
	$opts->{uplid} = BDE::Build::Uplid->new({ compiler=>$opts->{compiler},
						  where   =>$opts->{where}   });
    }
    else {
	$opts->{uplid} = BDE::Build::Uplid->new({ where   =>$opts->{where} });
    }
    my $uplid = $opts->{uplid};
    fatal "Bad uplid: $opts->{uplid}" unless defined $uplid;

    # set UFID
    $opts->{target} = "dbg_exc_mt" unless $opts->{target};
    my $ufid=new BDE::Build::Ufid($opts->{target});
    fatal "Bad ufid: $opts->{target}" unless defined $ufid;


    # default library paths
    $opts->{libpath}=[] unless defined $opts->{libpath};
    @{$opts->{libpath}}=map { split /,/ } @{$opts->{libpath}};
    unless ($opts->{nodp}) {

	##<<<TODO: support a --stage argument and adjust path appropriately
	##<<<TODO: FIXME doing so is necessary for EMOV oracle
	# default location of BB libraries
	push @{$opts->{libpath}}, $dest_library_directory;

	# <<TODO: defaults for AIX, Linux, Darwin
	# <<TODO: migrate to an options file (UPLID+UFID) somewhere?
        SWITCH: foreach ($^O) {
	    /^(solaris|SunOS)/ and do {
		push @{$opts->{libpath}}, "/opt/SUNWspro8/lib", "/opt/SUNWspro/lib", "/usr/ccs/lib", "/bb/util/common/studio8/SUNWspro/prod/lib";
		last;
	    };
	    /^aix/ and do {
		push @{$opts->{libpath}}, "/usr/vacpp/lib";
		last;
	    };
	}

	# default libpath for all platforms
	push @{$opts->{libpath}}, qw[/usr/lib /lib];
    }

    # default libraries (untargetted mode)
    $opts->{libraries}=[] unless defined $opts->{libraries};
    @{$opts->{libraries}}=map { split /,/ } @{$opts->{libraries}};
    if ($opts->{nodl}) {
	verbose "default libraries not loaded";
	$opts->{deflibs} = [];
    } else {
## GPS: TODO add 3ps support (?) or do that as BDE_ROOT/thirdparty/ ?
## GPS: get JAVA_LIBS from machdep; configure as thirdparty?
	# <<TODO: default libraries - use Base::Architecture OR default.opts
	# (Keep core_libs in the order they should appear at end of link line
	#  for besteffortlink().  These libs MUST NOT be circularly dependent
	#  with any other libraries.)
	push @{$opts->{core_libs}},
	     qw(pure_stubs demangle openbsd-compat
		l y m z dl rt mqiz sys pthread);
      SWITCH: foreach ($^O) {
	    /^(solaris|SunOS)/ and do {
		@{$opts->{deflibs}}=qw(c Crun Cstd);
		push @{$opts->{core_libs}},
		     qw(md5 nsl socket xnet posix4
			F77 M77 sunmath cx f77compat fui fai fai2 fsumai
			fprodai fminlai fmaxlai fminvai fmaxvai fsu ompstubs);
		last;
	    };
	    /^aix/             and do {
		@{$opts->{deflibs}}=qw(c C);
		push @{$opts->{core_libs}},
		     qw(xlf90 xlopt xlf xlomp_ser msaa);
		last;
	    };
	}
	push @{$opts->{libraries}}, @{$opts->{deflibs}} if $opts->{deflibs};
    }

    # symbols
    $opts->{symbols}=[] unless $opts->{symbols};
    @{$opts->{symbols}}=map { split /,/ } @{$opts->{symbols}};
    push @{$opts->{symbols}}, "plink_timestamp___";

    # objects
    $opts->{objects}=[] unless defined $opts->{objects};
    @{$opts->{objects}}=map { split /,/ } @{$opts->{objects}};

    # display options
    unless ($opts->{defined} or $opts->{undefined}) {
	$opts->{defined}=0; $opts->{undefined}=1;
    }

    # generate list of valid extension permutations
    # (default to static .a over .so because .a contains more symbol info)
    my @extensions=
      !(exists $opts->{static}) || $opts->{static} ? qw(.a .so) : qw(.so .a);
    my $extsize=$#extensions;
    foreach (@extensions[0..$extsize]) {
	push @extensions, ".${ufid}$_"; #search for ufid-extended libs
    }
    push @extensions, ""; #allow for fully qualified names too

    my @paths=@{$opts->{libpath}};
    verbose2 "searching locations: @paths";
    verbose2 "searching extensions: @extensions";

    # set up filesystem
    my $root=new BDE::FileSystem::MultiFinder($opts->{where});
    $root->setSearchMode(FILESYSTEM_PATH_ONLY|FILESYSTEM_NO_DEFAULT)
      if $opts->{daemon};
    my $finder=new Build::Option::Finder($root);
    BDE::Util::DependencyCache::setFileSystemRoot($finder);
    my $factory=new Build::Option::Factory($finder);

    return 
      new Binary::Context(\@ARGV,$root,$finder,$factory,$uplid,$ufid,
			  \@paths,\@extensions);
}

#------------------------------------------------------------------------------

sub load_object ($$;$) {
    my ($aggregate,$pathname,$dep_defined_symbols)=@_;

    fatal ("First argument must be aggregate or archive")
      unless ref($aggregate) and
	($aggregate->isa("Binary::Aggregate") or
	 $aggregate->isa("Binary::Archive"));

    -f $pathname
      or fatal("$pathname does not exist");

    if ($dep_defined_symbols) {
	(new Binary::Symbol::Scanner)->scan_for_defined($pathname,
							$dep_defined_symbols);
    }
    else {
	my $ok=$aggregate->addBinaryFile($pathname);
	fatal("Unable to add $pathname") unless $ok;
    }
    verbose("loaded $pathname");

    return $aggregate;
}

#----

sub load_from_meta ($$$$;$$$) {
    my($ctx,$uor,$aggregate,$options,$dep_defined_symbols,$bad_libs,
       $added_libs) = @_;
    use Carp;
    local $SIG{__DIE__} = sub {confess};
    my $paths = $ctx->{paths};  ## FIXME use accessor
    $bad_libs ||= {};
    my $baseuor = substr($uor,rindex($uor,'/')+1);

    my $addtl_libs=" ".$options->expandValue(uc($baseuor)."_OTHER_LIBS");
    my @meta_paths = ();
    while ($addtl_libs =~ /\s-L(?:\s+)?([^\s]+)/g) {
	unshift @meta_paths,$1;
    }
    ## XXX: should this be a local (temporary) addition, or global?
    ## ==> should be global; currently is not
    ##     (should also be unique, else lots of -lm -lm -lm -lm ...)
    ## (technically should build this up through all deps before loading
    ##  any libraries, so that full path is employed by all library searches)
    #unshift @$paths,@meta_paths;
    push @meta_paths, @$paths;

    $addtl_libs = " ".$options->expandValue(uc($baseuor)."_SYSTEM_LIBS")
		. $addtl_libs;

    my $lib;
    while ($addtl_libs =~ /\s-l(?:\s+)?([^\s]+)/g) {
	# skip libraries that are bad dependencies --
	# such libs must have bad symbols listed in _BAD_SYMBOLS
	next if ($bad_libs->{$1});
	$lib = $1;
	if (my $pathname=$ctx->find_library($lib, \@meta_paths)) {
	    ## (load_from_meta() is only called on things added to dependency
	    ##  aggregate; we always want to remove undefined symbols from it,
	    ##  except when called from init milieu where $added_libs is passed)
	    unless (defined($added_libs)) {
		$ctx->load_library_defines($lib,$pathname,$dep_defined_symbols);
	    }
	    else {
		$ctx->load_library($lib, $pathname, $aggregate);
		push @$added_libs,$lib;
	    }
	} else {
	    fatal("Unable to locate library for $lib in ".
		  join(":",@meta_paths));
	}
    }

    my $plink_objs = $options->expandValue("PLINK_OBJS");
    if ($plink_objs) {
	load_object($aggregate => $_, $dep_defined_symbols)
	  foreach (split /\s+/, $plink_objs);
    }
}

#------------------------------------------------------------------------------


# Filter out hard-coded list of symbols defined as macros by system libraries
#<<<TODO: find out where these are really being defined
sub macro_kludge ($) {
    my $undefined = shift;
    if ($^O eq 'aix') {
	delete @$undefined{
	    '.___bzero',
	    '.___fill',
	    '.___memmove',
	    '.___memset',
	    '.__divss',
	    '.__divus',
	    '.__mulh',
	    '.__mull',
	    '.__quous',
	    '.mmap',
	    '.msgctl',
	    '.msgget',
	    '.shmctl',
	    '.shmget',
	    '___fill',
	    '___memmove',
	    '__divss',
	    '__divus',
	    '__mull',
	    '__quous',
	    '_system_configuration',
	    'close',
	    'errno',
	    'mmap',
	    'open'
	  };
    }
    ## Yet another special case.  Ignore BDE style version symbols.
    ## This works on Sun.
    my @version_symbols;
    foreach (keys %$undefined) {
	push @version_symbols,$_
	  if /BloombergLP\w+scm\w+Version\w+d_version/;
    }
    delete $undefined->{$_} foreach (@version_symbols);
}

#----

#
# Note that this code still needs cleanup -- it's got some minimal
# amount of cleaning done to it 
sub report_symbols ($$$) {
    my ($title,$symbols,$match)=@_;
    $match = qr/$match/ if $match;

    ## store symbols to differentiate undefined and hierarchy violations
    my(%hierarchy,$len);
    my $defined = get_milieu_defined_symbols();

    verbose_alert $title if ($title && @$symbols);

    my($symbol,@longnames,$extra);
    my $report = \&warning;
    my $prefix = get_prefix();
    my $prog = get_prog();
    local $Util::Message::MESSAGE_PREFIX="";
    local $Util::Message::WARNING_PREFIX="";
    set_prog("");
    set_prefix("");
    if (@$symbols) {
	$report->("\n  undefined symbols (based on declared dependencies)\n  "
		 .('-' x (length($title)-1))."\n");
	foreach (sort {$a->[1]->getLongName cmp $b->[1]->getLongName} @$symbols) {
	    $symbol = $defined->{$_->[1]};
	    $len = length($_->[1]->getLongName);
	    if ($symbol) {
		$extra = "     "
			.($symbol->getType() eq 'D'
			    ? "[missing .h or .inc to define data symbol]"
		  	    : "[Do you need ".$symbol->getLongName()." ?]");
	    }
	    $report->(" ",$_->[1]->getLongName,($len < 54 ? (' 'x(54-$len)) : "\t"),
		      ($symbol
			? "(hierarchy violation)".$extra.($_->[2] ? ' (FATAL)' : '')

			: "(SYMBOL NOT FOUND)"),
		     );
	}
	$report->("");
    }
    set_prog($prog);
    set_prefix($prefix);
}

#==============================================================================

{
    ## Storing $cs, among other things, is not thread-safe
    my($milieu,$changedb,$cs,$milieu_defined,$milieu_undefined,
       $milieu_offline,$milieu_offline_defined,$milieu_offline_undefined,
       $thirdpartylibpaths);
    my $prev_lib_refresh = 0;

    my $plink_arch = $^O eq "aix" ? "ibm" : "sundev1";
    my %bbsrc_big_objs = (
	# PEKLUDGE
	"/bb/source/align/align_dbcommon.o" => 1,
	"/bb/source/align/align_corpcomn.o" => 1,
	# GENTB_TOOLBARSTUFF
	# (/bbsrc/mkincludes/machindep.defines)
	"/bbsrc/big/gentb_router.$plink_arch.o" => 1,
	"/bbsrc/big/gentb_general.$plink_arch.o" => 1,
	"/bbsrc/big/gentb_security_utils.$plink_arch.o" => 1,
	"/bbsrc/big/gentb_security_utils_server.$plink_arch.o" => 1,
	"/bbsrc/big/dummyforincludes.$plink_arch.o" => 1,
	# OTHER
	"/bbsrc/big/blockdataall.$plink_arch.o" => 1,
	"/bbsrc/big/ctrl_use_sess19z.$plink_arch.o" => 1,
	"/bbsrc/big/dumpstack_opendb.$plink_arch.o" => 1,
	"/bbsrc/big/fencef.$plink_arch.o" => 1,
	"/bbsrc/big/getglsec.$plink_arch.o" => 1,
	"/bbsrc/big/ibig.$plink_arch.o" => 1,
	"/bbsrc/big/inbig_for_big.$plink_arch.o" => 1,
	"/bbsrc/big/init_dbstats.$plink_arch.o" => 1,
	"/bbsrc/big/is_none_savrngable.$plink_arch.o" => 1,
	"/bbsrc/big/pdf_router.$plink_arch.o" => 1,
	"/bbsrc/big/routemtg.$plink_arch.o" => 1,
	"/bbsrc/big/routerwrap.$plink_arch.o" => 1,
	"/bbsrc/big/ztmgr.$plink_arch.o" => 1);

    sub init_change () {
	$milieu = new Binary::Aggregate("symbol oracle");
	$milieu_offline = new Binary::Aggregate("offline symbol oracle");
	$changedb = new Change::DB('<'.DBPATH);
	fatal("Unable to access ${\DBPATH}: $!") unless defined $changedb;
    }

    sub init_milieu ($$) {
	init_change() unless $milieu;
	my($ctx,$opts) = @_;
	my $root = $ctx->{root};
	$ctx->{loaded_libs} = {};  # reset list of loaded libraries
	my $start_time = time();

	## Refresh library cache
	## We cache /bb/source/lib so that we are immune to in-place
	## modifications due to robocop performing 'ar' directly on libraries
	##<<<TODO: should be a symbol, depending on stage (devel, emov, etc)
	refresh_library_cache($base_library_directory, $dest_library_directory, $prev_lib_refresh);
	$prev_lib_refresh = $start_time;

	## Load all libraries.  Takes about 1 GB memory (as of 2005.10)
	my($pathname,$options,@thirdparty);
	foreach my $lib (@{$opts->{deflibs}}, @{$opts->{core_libs}}) {
	    $pathname = $ctx->get_library_path($lib)
	      || (warning("Unable to locate library for $lib"), next);
	    $ctx->load_library($lib, $pathname, $milieu);
	}
### TESTING TESTING TESTING
	foreach my $lib ($ctx->{root}->findUniverse()) {
#	my @foolibs = ('peutil','dbutil','msgutil','smr','bde','bce','bae','bbglib','gobject','asn1cpp');
#	foreach my $lib (@foolibs) {
### TESTING TESTING TESTING
	    next if isApplication($lib);
	    unless (grep(/^\Q$lib\E$/,@{$opts->{libraries}})) {
		$lib = getCanonicalUOR($lib)
		  || (warning("Unable to determine canonical name for $lib"),
		      next);
	    }
	    # (eventually probably want to always load from meta for all pkgs)
	    # (check for offline-only only because we don't want to load glib
	    #  thirdparty library along with bbglib)
	    if (isThirdParty($lib) && !$ctx->is_offline_only($lib)) {
		$options = $ctx->get_meta($lib);
		load_from_meta($ctx,$lib,$milieu,$options,
			       undef,undef,\@thirdparty);
		# repeat some of the logic from load_from_meta so that we can
		# store the -L rules needed by thirdparty libraries for use by
		# besteffortlink if the link generation finds that it needs a
		# thirdparty library (for which an additional -L rule is needed)
		# This might be optimized in the future to provide the exact
		# link line that is needed for a list of -L and -l rules needed
		# by each thirdparty app, with excess repetitions of the -l
		# rules interspersed on the link line moved to the end.
		my $baseuor = uc(substr($lib,rindex($lib,'/')+1));
		my $tparty =" ".$options->expandValue($baseuor."_OTHER_LIBS");
		#my $tparty=" ".$options->expandValue($baseuor."_SYSTEM_LIBS");
		#$tparty   =" ".$options->expandValue($baseuor."_OTHER_LIBS")
		#	  .$tparty;
		my $tpartyL = "";
		while ($tparty =~ /\s-L(?:\s+)?([^\s]+)/g) {
		    $tpartyL .= " -L".$1;
		}
		if ($tpartyL ne "") {
		    while ($tparty =~ /\s-l(?:\s+)?([^\s]+)/g) {
			$thirdpartylibpaths->{$1} = $tpartyL;
		    }
		}
	    }
	    next if $ctx->is_metadata_only($lib);
	    $pathname = $ctx->get_library_path($lib)
	      || (warning("Unable to locate library for $lib"), next);
	    ## skip "test" libraries
	    next if $pathname =~ m%/lib(?:tst|test|test2|test3)\.a$%;
	    ## skip "phantom" libraries
## GPS: should we be loading these in offline only?
	    next if $pathname =~ m%/lib(?:des|eaydes|mlrmxlib|nolib|otrade|query|rfc|smartheap_smp|sp|xslt)\.a$%;
	    if ($ctx->is_offline_only($lib)) {
		$ctx->load_library($lib, $pathname, $milieu_offline);
	    }
	    else {
		$ctx->load_library($lib, $pathname, $milieu);
	    }
	}
	my $load_time = time();

	## Remove libraries that no longer exist
	## (make assumption that library is named lib<name>.*)
	my @delete;
	/^lib([^.]+)\./ && $ctx->{loaded_libs}->{getCanonicalUOR($1)||''}
	  || /\.o$/
	  || grep(/^\Q$1\E$/,@{$opts->{deflibs}},@{$opts->{core_libs}},
			     @thirdparty)
	  || push @delete,$_ foreach ($milieu->getObjects());
	map { $milieu->removeObject($_) } @delete;
	debug("removed from milieu: @delete\n") if @delete;
	@{$opts->{thirdparty}} = @thirdparty;

	## Special-case objects always included in the Bigs
	## This is not all objects.  Things like router*.o depend on the Big.
	## Also intentionally omitted are /bbsrc/big/*_staticinitializer.o
	my $scanner = new Binary::Symbol::Scanner;
	foreach my $obj (keys %bbsrc_big_objs) {
	    next unless (-e $obj);
## GPSGPSG: might load a new Binary::Object and put pathname as 'archive'
##	same for thirdparty metadata processing above
##	But see besteffortlink first -- would need to change some logic there
	    my $ofile = Binary::Object->new($obj);
	    if ($ofile) {
	      my $name = $ofile->getName;
	      $name =~ s/$plink_arch//;
	      $name =~ s/\.\./\./;
	      $ofile->setName($name);
	      alert("loaded $obj as " . $ofile->getName);
	      $milieu->addObject($ofile);
	    } else {
	      warning("Unable to add $obj");
	    }
	}

       ## break circular references between symbol Binary::Objects
       undef $_->{dups}
         foreach (values %$milieu_defined, values %$milieu_offline_defined);
       undef $_->{refs}
         foreach (values %$milieu_undefined,values %$milieu_offline_undefined);
        $milieu_defined   = undef;
	$milieu_undefined = undef;
	$milieu_defined   = $milieu->getDefinedSymbols();
	$milieu_undefined = $milieu->getAllUndefines();
	$milieu_offline_defined   = undef;
	$milieu_offline_undefined = undef;
	$milieu_offline_defined   = $milieu_offline->getDefinedSymbols();
	# (currently unused; don't waste memory for now)
	#$milieu_offline_undefined = $milieu_offline->getAllUndefines();

	## Clean up header cache
	cleanup_header_cache();

	debug("TIME: Library Load: ".($load_time - $start_time).
	      " seconds; Rehash: ".(time() - $load_time)." seconds\n");
    }

    sub init_changeset ($$$) {
	my($ctx,$opts,$csid) = @_;
	init_change() unless $changedb;
	## *** Assumes fork() was done; not thread-safe ***
	$opts->{csid} = $csid;
	$opts->{cs} = $cs = $changedb->getChangeSet($csid);
        unless (defined $cs) {
	    alert ("Change set $csid not found in database");
	    return undef;
	}

        return new Binary::Context([$cs->getLibraries()],
				   @{$ctx}{'root','finder','factory','uplid',
					   'ufid','paths','extensions'});
    }

    sub init_changeset_from_file ($$$) {
	my($ctx,$opts,$file) = @_;
	init_change() unless $changedb;  ## necessary?
	## *** Assumes fork() was done; not thread-safe ***
	$opts->{cs} = $cs = eval { load Change::Set($file) };
        unless (defined $cs) {
	    alert ("Loading changes from $file failed");
	    alert ("($@)") if (defined($@) && $@ ne '');
	    return undef;
	}
	$opts->{csid} = $cs->getID();

        return new Binary::Context([$cs->getLibraries()],
				   @{$ctx}{'root','finder','factory','uplid',
					   'ufid','paths','extensions'});
    }

    sub get_change_set_header ($) {
	init_change() unless $changedb;
	my $header;
	eval {$header = $changedb->getChangeSetHeader($_[0]);};
	$header = undef if $@;
	return $header;
    }

    sub _have_libs_changed_since ($$) {
	my($libpath,$watermark) = @_;
	## coarse check: if any file has changed (not subdirectory)
	my $DH = Symbol::gensym;
	opendir($DH,$libpath);
	while (my $file = readdir($DH)) {
	    next unless -f $libpath.'/'.$file;
	    return 1 if (stat(_))[9] >= $watermark;
	}
	return 0;
    }

    ## Refresh library cache
    ## We cache /bb/source/lib so that we are immune to in-place
    ## modifications due to robocop performing 'ar' directly on libraries
    ## We only refresh if the libraries have changed since last sweep, meaning
    ## that we do not clean up added.<csid> and removed.<csid> files unless the
    ## libraries have been rebuilt.  It means that our added.* and removed.* are
    ## still accurate for the libraries that we are caching against, although
    ## attempts to check in the same file that was swept into RCS, but not yet
    ## built into the libraries might fail with multiple-defines.
    sub refresh_library_cache ($$$) {
	## Perform rsync and then check for modifications of files during rsync
	my($libpath,$destdir, $prev_start) = @_;
	return unless _have_libs_changed_since($libpath,$prev_start);
	my $start_time = time();
	while (_have_libs_changed_since($libpath,$prev_start)) {
	    $prev_start = $start_time;
	    $start_time = time();
	    system(
	     '/usr/bin/rsync -aW --delete --delete-excluded '
	    .' --include="lib[A-Z]*.*"'
	    .' --exclude="lib*[A-Z].*"'
	    .' --include="lib*.a" --include="lib*.so"'
	    .' --exclude="*" '.$libpath.'/ '.$destdir.'/');
	    system('chgrp -R sibuild '.$destdir);
	    system('chmod g+s '.$destdir);
	}
    }

    sub cleanup_header_cache () {
	## Clean up added and removed symbols
	my $FH = Symbol::gensym;
	my($csid,$csheader,$tag,$symbol,@unlinkfiles);
	my (%changesets);
	# Gather up the changeset files and aggregate them
	foreach my $symfile (glob(COMPCHECK_DIR."/emov/symbols/*"),
			     glob(COMPCHECK_DIR."/bugf/symbols/*"),
			     glob(COMPCHECK_DIR."/move/symbols/*")) {
	  ($tag,$csid) = split /\./,$symfile,2;
	  next if $csid =~ tr/0-9A-F//c;
	  $csheader = get_change_set_header($csid) || next;

	  next unless ($csheader->getStatus() eq STATUS_COMPLETE);
	  #			 || $csheader->getStatus() eq STATUS_INPROGRESS);
	  # Read first symbol in file and check if libs have been rebuilt yet
	  # Only delete if libs have been built with new information.
	  push @{$changesets{$csid}}, $symfile;
	}

	# Run through each changeset
      CSID_LOOP:
	foreach $csid (keys %changesets) {
	  # By default we assume that we can delete the files
	  my $can_delete = 1;
	  foreach my $symfile (@{$changesets{$csid}}) {

	    open($FH,'<'.$symfile)
	      || (warning("unable to open $symfile: $!"), next);
	    $symfile =~ /(added|removed)/;
	    $tag = $1;
	    while ($symbol = <$FH>) {
	      chomp $symbol;
	      # Chop off the trailing type
	      $symbol =~ s/\s+(\S+)\s*$//;
	      my $symtype = $1;
	      # If we were added, see if we're in
	      if ($tag eq "added") {
		if ($symtype eq 'U') {
		  next if ($milieu_undefined->{$symbol});
		} else {
		  next if ($milieu_defined->{$symbol}
			   || $milieu_offline_defined->{$symbol});
		}
	      }
	      # Or removed. Still there?
	      elsif ($tag eq "removed") {
		if ($symtype eq 'U') {
		  next if (!$milieu_undefined->{$symbol});
		} else {
		  next if (!$milieu_defined->{$symbol}
			   && !$milieu_offline_defined->{$symbol});
		}
	      }

	      # Hrm. We aren't built into the libraries. Pity, guess
	      # we have to stay.
	      $can_delete = 0;
	      # Setting the flag's redundant since we're just skipping
	      # the changeset
	      next CSID_LOOP;
	    }
	  }

	  # Right, we can delete the files
	  print "Unlinking file(s) ", join(" ", @{$changesets{$csid}}), " for changeset $csid\n";
	  push @unlinkfiles,@{$changesets{$csid}};
	  File::Path::rmtree(
		 COMPCHECK_DIR."/".$csheader->getMoveType()."/".$csid);
	  ##<<<TODO: can also clean up other parts of cache area (move/<CSID>)
	  ## e.g. remove headers from the header cache, though that should
	  ## be done closer to the actual sweep, in case someone checked in
	  ## the file again shortly after the sweep.  ==> Could check if file
	  ## is present in /bbsrc/checkin, too, and remove if not.
	  ## Still need to clean out rolledback move/<CSID>
	}
	unlink(@unlinkfiles) if @unlinkfiles;
    }

    sub update_milieu ($) {
	my $target_aggregate = shift;
	$milieu->addObject($_) foreach ($target_aggregate->getObjects());
	$milieu_defined   = undef;
	$milieu_undefined = undef;
    }

    sub get_milieu () {
	return $milieu;           ## caller MUST NOT modify
    }

    sub get_milieu_offline () {
	return $milieu_offline;   ## caller MUST NOT modify
    }

    sub clean_all_symbols () {
      clean_milieu_defined_symbols();
      clean_offline_milieu_defined_symbols();
      clean_milieu_undefined_symbols();
      clean_offline_milieu_undefined_symbols();
    }
    sub clean_milieu_defined_symbols () {
      undef $milieu_defined;
    }

    sub clean_milieu_undefined_symbols () {
      undef $milieu_undefined;
    }

    sub clean_offline_milieu_defined_symbols () {
      undef $milieu_offline_defined;
    }

    sub clean_offline_milieu_undefined_symbols () {
      undef $milieu_offline_undefined;
    }

    sub get_milieu_defined_symbols () {
      if (!defined $milieu_defined) {
	($milieu_defined, $milieu_undefined) = grovel_for_symbols($milieu)
      }
      return $milieu_defined;   ## caller MUST NOT modify
    }

    sub get_milieu_undefined_symbols () {
      if (!defined $milieu_undefined) {
	($milieu_defined, $milieu_undefined) = grovel_for_symbols($milieu)
      }
      return $milieu_undefined; ## caller MUST NOT modify
    }

    sub get_milieu_offline_defined_symbols () {
	$milieu_offline_defined = grovel_for_defined_symbols($milieu_offline)
	  unless defined($milieu_offline_defined);
	return $milieu_offline_defined;   ## caller MUST NOT modify
    }

    sub get_milieu_offline_undefined_symbols () {
	$milieu_offline_undefined = grovel_for_undefined_symbols($milieu_offline)
	  unless defined($milieu_offline_undefined);
	return $milieu_offline_undefined; ## caller MUST NOT modify
    }

    sub get_thirdpartylibpaths () {
	return $thirdpartylibpaths;       ## caller MUST NOT modify
    }

    sub get_bbsrc_big_objs () {
	return \%bbsrc_big_objs;          ## caller MUST NOT modify
    }

    sub grovel_for_symbols {
      my ($binary) = @_;
      my (@objs) = values %{$binary->{objects}};
      my (%defsymbols, %undefsymbols);
      keys %defsymbols = 800000; # about the right amount, alas
      keys %undefsymbols = 300000; # about the right amount, alas
      while (@objs) {
	my @newobjs;
	foreach my $obj (@objs) {
	  if (ref($obj) eq 'Binary::Object') {
	    foreach my $sym ( values %{$obj->{symbols}}) {
	      if (${$sym->{type}} eq 'U') {
		push @{$undefsymbols{$sym}}, $sym;
	      } else {
		$defsymbols{$sym} = $sym;
	      }
	    }
	  } else {
	    push @newobjs, values %{$obj->{objects}};
	  }
	}
	@objs = @newobjs;
      }
      print "There are " . scalar(keys(%defsymbols)) . " defs and " . scalar(keys(%undefsymbols)) . " undefs\n";
      return \%defsymbols, \%undefsymbols;
    }


    sub grovel_for_defined_symbols {
      my ($binary) = @_;
      my (@objs) = values %{$binary->{objects}};
      my %symbols;
      keys %symbols = 600000; # about the right amount, alas
      while (@objs) {
	my @newobjs;
	foreach my $obj (@objs) {
	  if (ref($obj) eq 'Binary::Object') {
	    my (@syms) = grep {${$_->{type}} ne 'U'} values %{$obj->{symbols}};
	    @symbols{@syms} = @syms;
	  } else {
	    push @newobjs, values %{$obj->{objects}};
	  }
	}
	@objs = @newobjs;
      }
      print "There are " . scalar(keys(%symbols)) . " defs\n";
      return \%symbols;
    }

    sub grovel_for_undefined_symbols {
      my ($binary) = @_;
      my (@objs) = values %{$binary->{objects}};
      my %symbols;
      keys %symbols = 600000; # about the right amount, alas
      while (@objs) {
	my @newobjs;
	foreach my $obj (@objs) {
	  if (ref($obj) eq 'Binary::Object') {
	    my (@syms) = grep {${$_->{type}} eq 'U'} values %{$obj->{symbols}};
	    foreach my $sym (@syms) {
	      push @{$symbols{$sym}}, $sym;
	    }
#	    @symbols{@syms} = @syms;
	  } else {
	    push @newobjs, values %{$obj->{objects}};
	  }
	}
	@objs = @newobjs;
      }
      print "There are " . scalar(keys(%symbols)) . " undefs\n";
      return \%symbols;
    }

#<<TODO optimization: improve infrastructure so as not to generate
# the duplicate symbol list twice (once for DefinedSymbols, once for Undefined)

## TEMPORARY until $cs supports hasObject() method
    my $cs_files = +{};
    sub set_cs_files_hash ($) {
	$cs_files = $_[0];
    }

    ## check that removed symbols are not in use by someone else
    sub in_use_symbol_check ($$$) {
	my($csid,$removed_symbols, $logfile) = @_;
	print "(pid $$) getting undef symbols ", time(), "\n";
	my $undefined = get_milieu_undefined_symbols();
	my $defined = get_milieu_defined_symbols();
	print "(pid $$) got undef symbols ", time(), "\n";
	my $status = 1;
	my($sym,$obj,$rsym);
	foreach my $r (@$removed_symbols) {
	  next if $defined->{$r};
	  next unless defined $undefined->{$r};
	  
	  if ($undefined->{$r}) {
	    foreach my $use (@{$undefined->{$r}}) {
	      $logfile->log_verbose("Detected undef symbol " . $r->getLongName() . " used at " . $use->getLongName());
	      warning("detected undefined symbol ".$r->getLongName() . " used at " . $use->getLongName());
	    }
	    $status = 0;
	  }
	}
	unless ($status == 1) {
	  warning("removed symbol(s) still in use");
	  warning("  (in above location(s) reporting undefines)");
	}
	return $status;
    }

    # Take the changeset and apply its object files to the internal
    # cache. addObject is nice in that it'll toss an existing object
    # if one of the same name exists. The one funky bit is that for
    # fortran files we have to split the damn thing first and yank out
    # the potential half-zillion .o files that the split fortran file
    # could've generated.
    sub apply_cs_changes {
      my ($ctx, $files, $o_cache, $logfile) = @_;
      my $rv= 1;
      # First remove the files from out of the cache.
      foreach my $obj_file (@$files) {
	my $source = $obj_file->getSource();
	my $lib = $obj_file->getLibrary();
#	my $pathname = $ctx->get_library_path($lib);
	# Go make sure the cache is up to date. Probably not
	# needed if we roll forward right, but...
	my $library = get_aggregate($ctx, $lib);
	$logfile->log_verbose("applycschanges: $obj_file, $source, $lib, $library\n");
	# Find all the .os for this source (may be multiple because of
	# fortran)
	my (@sub_o_files) = split_o_files($source, $logfile);
	foreach my $sub_o (@sub_o_files) {
	  #my $bin_sub_obj = 
	  # Remove the .o
	  $logfile->log_verbose("Removing $sub_o from $library");
	  debug("removing $sub_o from $library\n");
	  $library->removeObject($sub_o);
	  if ($sub_o =~ s/\.sundev1//) {
	    $logfile->log_verbose("Removing trimmed $sub_o from $library");
	    $library->removeObject($sub_o);
	  }
	}
	# Is it fortran? Yell if we break the gtk fortran rule
	if (substr($source, -2) eq '.f') {
	  if (@sub_o_files > 1
	      && (getCachedGroupOrIsolatedPackage($lib)
		 )->isGTKbuild) {
	    error("disallowed: new Fortran functions are ".
		  "not allowed in existing GTK .f files\n");
	    $rv = 2;
	  }
	}
	$logfile->log_verbose("Adding $obj_file to $library");
	debug("Adding $obj_file to $library\n");
	# Add the changeset .o file backin
	my $obj_obj = load_o_file_cached($obj_file, $lib, $o_cache, $logfile);
	foreach my $sym ($obj_obj->getDefinedSymbols) {
	  $logfile->log_verbose("$obj_obj has defined symbol $sym");
	}	
	$library->addObject($obj_obj);
        debug("Object added\n");
      }
      return $rv;
    }

    sub getLibDefines {
      my ($ctx, $lib) = @_;
      my $pathname = $ctx->get_library_path($lib);
      my $libobj = Binary::Context::cache_fetch_library($lib, $pathname);
      my $defs = $libobj->getDefinedSymbols();
      return $defs;
    }

    sub remove_o_for_file {
      my ($ctx, $obj_file, $logfile) = @_;
      my $source = $obj_file->getSource();
      my $o_name = $obj_file->getDestination();
      my $lib = $obj_file->getLibrary();
      my $pathname = $ctx->get_library_path($lib);
      # Go make sure the cache is up to date. Probably not
      # needed if we roll forward right, but...
      my $library = get_aggregate($ctx, $lib);
      $logfile->log_verbose("Looking to remove $obj_file from $library\n");
      # Find all the .os for this source (may be multiple because of
      # fortran)
      my (@sub_o_files) = split_o_files($source, $logfile);
      foreach my $sub_o (@sub_o_files) {
	$sub_o =~ s/^.*\///;
	#my $bin_sub_obj = 
	# Remove the .o
	debug("Removed fortran split .o file $obj_file\n");
	$logfile->log_verbose("removing $sub_o from $library\n");
	if (!$library->removeObject($sub_o)) {
	  $logfile->log_verbose("removal failed");
	}
	if ($sub_o =~ s/\.sundev1//) {
	  $logfile->log_verbose("removing $sub_o from $library\n");
	  if (!$library->removeObject($sub_o)) {
	    $logfile->log_verbose("removal failed");
	  }
	}
      }
      debug("Removed .o file $obj_file\n");
      $o_name =~ s/^.*\///;
      $logfile->log_verbose("removing $o_name from $library\n");
      if (!$library->removeObject($o_name)) {
	$logfile->log_verbose("removal failed");
      }
      if ($o_name =~ s/\.sundev1//) {
	$logfile->log_verbose("removing $o_name from $library\n");
	if (!$library->removeObject($o_name)) {
	$logfile->log_verbose("removal failed");
	}
      }
    }

    sub save_source_to_o_mapping {
      my ($cs, $source, $logfile) = @_;
      return unless $source =~ /\.f$/;
      my $filename = COMPCHECK_DIR . "/splitf/$cs";

      my $fh = Symbol::gensym;
      open $fh, ">>$filename";
      foreach my $o (split_o_files($source, $logfile)) {
	print $fh $source, "\t", $o, "\n";
      }
      close $fh;
    }

    {
      my %o_cache;

      sub split_o_files {
	my ($source, $logfile) = @_;
	if (!wantarray) {
	  confess "Not in array context!";
	}
	debug("Splitting $source\n");
	my @o_files;
	if (!defined($o_cache{$source})) {
	  if (substr($source, -2) eq '.f') {
	    my $num_funcs = 0;
	    my $PH = Symbol::gensym;
	    open($PH, "-|",
		 "/bb/bin/breakftnx",
		 "-breakftnxlistobjs",
		 $source) || next;
	    $num_funcs = 0;
	    while (<$PH>) {
	      chomp;
	      push @o_files, $_.".o";
	    }
	    close $PH;
	  } else {
	    $source =~ s/\.[^.]*$//;
	    $source .= '.o';
	    push @o_files, $source;
	  }
	  $o_cache{$source} = \@o_files;
	}
	return @{$o_cache{$source}};
      }
    }

    sub cs_sort {
      $_[0] =~ /(added|removed)\.(\w+)/;
      my ($l1, $l2) = ($1, $2);
      $_[1] =~ /(added|removed)\.(\w+)/;
      my ($r1, $r2) = ($1, $2);
      $l1 = $l1 eq 'added' ? '2' : '1';
      $r1 = $r1 eq 'added' ? '2' : '1';
      return($l2.$l1 cmp $r2.$r1);
    }

    sub roll_forward_changesets {
      my ($ctx, $logfile) = @_;
      my (@symfiles, %symbols);
      my %objcache;
      my $movetype = $cs->getMoveType();
      if ($movetype eq MOVE_EMERGENCY) {
	push @symfiles,sort glob(COMPCHECK_DIR."/emov/symbols/removed.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/emov/symbols/added.*");
      }
      elsif ($movetype eq MOVE_BUGFIX) {
	push @symfiles,sort glob(COMPCHECK_DIR."/emov/symbols/removed.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/emov/symbols/added.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/bugf/symbols/removed.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/bugf/symbols/added.*");
      }
      elsif ($movetype eq MOVE_REGULAR) {
	push @symfiles,sort glob(COMPCHECK_DIR."/emov/symbols/removed.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/emov/symbols/added.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/bugf/symbols/removed.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/bugf/symbols/added.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/move/symbols/removed.*");
	push @symfiles,sort glob(COMPCHECK_DIR."/move/symbols/added.*");
      }

      @symfiles = sort { cs_sort($a, $b) } @symfiles;

      # Okay, we have the changeset symbol files. Roll 'em into the database.
	my($type,$csid, $aggregate);
	my $FH = Symbol::gensym;
	foreach my $file (@symfiles) {
	    next unless -s $file;
## GPS: this assumes there is no other dot ('.') in path segments! bad
	    ($type,$csid) = split /\./,$file,2;
	    open($FH,'<'.$file)
	      || (warning("unable to open $file: $!"), next);
	    $logfile->log_verbose("Opened changeset $file");
	    debug("Opened changeset file $file\n");
	    while (<$FH>) {
		chomp;
#		$logfile->log_verbose("Line is >$_<");
		next unless /^([^\[]*)\[([^\]]+)\]:(\S+) ?(\S*)/;
		my ($lib, $obj, $sym, $symtype) = ($1, $2, $3, $4);
		$symtype = 'T' unless $symtype;
		$obj =~ s/\.sundev1//; # Chop out the sundev1 bit
		$logfile->log_verbose("Archive $lib, object $obj, symbol $sym, type $symtype\n");
		$aggregate = get_aggregate($ctx, $lib);
		if (!defined $aggregate) {
		  $logfile->log_verbose("No aggregate found for $lib for line $_ from changeset file $file");
		  warning("Error processing line $_ from changeset file $file");
		  next;
		}
		# Use the name the aggregate thinks it is
		$lib = $aggregate->getName();
		my $symobj = Binary::Symbol->new({archive => \"$lib",
						  object => \"$obj",
						  name => \"$sym",
						  type => \"$symtype",
						 });
#		$aggregate = get_milieu()->getObject($lib);
		debug("Aggregate for $lib is $aggregate, adding symbol ". $symobj->getLongName() . "\n");
		if ($type =~ /added/) {
#		  debug("Adding symbol $sym into aggregate for $lib\n");
		  add_sym_to_aggregate($aggregate, $lib, $obj, $sym,
				       $symobj, \%objcache, $logfile);
		  $symbols{$sym} = $csid;
		} else {
#		  debug("Removing symbol $sym into aggregate for $lib\n");
		  remove_sym_from_aggregate($aggregate, $lib, $obj,
					    $sym, $symobj, \%objcache, $logfile);
		  undef $symbols{$sym};
		}
	    }
	    close $FH;
	}
        return \%symbols;
    }

    my %libpaths;
    # return the Binary::Archive object for library $lib
    my %seen_aggregate;
    sub get_aggregate {
      my ($ctx, $lib, $searchpaths) = @_;
      $searchpaths = ['/local/lib'] unless $searchpaths;
      if ($lib =~ /^lib(.*)\./) {
	$lib = $1;
      }
      my $fqlib = "lib${lib}.a";
      my $wildlib = "lib${lib}.dbg_exc_mt.a";
      my $solib = "lib${lib}.so";
      my $agg = get_milieu()->getObject($lib);
      if (!defined $agg) {
	$agg =  get_milieu()->getObject($fqlib);
      }
      if (!defined $agg) {
	$agg =  get_milieu()->getObject($wildlib);
      }
      if (!defined $agg) {
	$agg =  get_milieu()->getObject($solib);
      }
      if (!defined $agg) {
	$agg = get_milieu_offline()->getObject($lib);
      }
      if (!defined $agg) {
	$agg =  get_milieu_offline()->getObject($fqlib);
      }
      if (!defined $agg) {
	$agg =  get_milieu_offline()->getObject($wildlib);
      }
      if (!defined $agg) {
	$agg =  get_milieu_offline()->getObject($solib);
      }
      if (!defined $agg) {
	my $aggregate = Binary::Aggregate->new($lib);
	# If we've already looked for this thing and haven't found it
	# then we need to just bail, since there's no point in going
	# 'round this loop yet again
	return $aggregate if $seen_aggregate{$lib};
	eval {
	  my $options = $ctx->get_meta($lib);
	  load_from_meta($ctx,$lib,$aggregate,$options);
	  $agg = get_milieu()->getObject($lib);
	};
	# Okay, is the damn thing maybe a third-party library sitting
	# on disk somewhere?
	if ($@) {
	  my $libloc = $ctx->find_library($lib, $searchpaths, ['.a', '.so']);
	  if (defined $libloc) {
	    $ctx->load_library($lib, $libloc, get_milieu());
	  }
	}
	$seen_aggregate{$lib}++;
	# GO try 
	$agg =  get_milieu()->getObject($fqlib);
	if (!defined $agg) {
	  $agg =  get_milieu()->getObject($wildlib);
	}
	if (!defined $agg) {
	  $agg =  get_milieu()->getObject($solib);
	}
	if (!defined $agg) {
	  $agg = get_milieu_offline()->getObject($lib);
	}
	if (!defined $agg) {
	  $agg =  get_milieu_offline()->getObject($fqlib);
	}
	if (!defined $agg) {
	  $agg =  get_milieu_offline()->getObject($wildlib);
	}
	if (!defined $agg) {
	  $agg =  get_milieu_offline()->getObject($solib);
	}
      }
      return $agg;
    }

    sub remove_sym_from_aggregate {
      my ($aggregate, $lib, $obj, $name, $symobj, $objcache, $logfile) = @_;
      my $object;
      $object = $aggregate->getObject($obj);
      if (defined $object) {
	# We found the .o file. Rip out the symbol
	delete $object->{symbols}{$name};
	$logfile->log_verbose("removing symbol $name from object $obj in aggregate $aggregate\n");
      } else {
	$logfile->log_verbose("Didn't find $obj in $aggregate\n");
      }
    }

    # Add a symbol to an aggregate
    sub add_sym_to_aggregate {
      my ($aggregate, $lib, $obj, $name, $sym, $objcache, $logfile) = @_;
      my $found = 0;
      # Go looking through all the object fiels for one that matches
      # our name.
      my $object = $aggregate->getObject($obj);
      if (defined $object) {
	# We found the .o file. Stuff the symbol right into the guts
	# of the object object.
	$object->{symbols}{$name} = $sym;
	$logfile->log_verbose("Added $sym to existing aggregate $object, name $name");
	
      } else {
	# Didn't find the object file. That means it's new, so we need
	# to create it
	my $newobj = Binary::Object->new();
	$newobj->setName($obj);
	$newobj->{symbols}{$name} = $sym;
	$aggregate->addObject($newobj);
	$logfile->log_verbose("Adding new .o file $newobj to aggregate $aggregate, and adding symbol $sym/name $name");
	$objcache->{aggregate}{$obj} = $newobj;
      }
    }
  }

# write out files of new symbols added and old symbols removed
# chown is used to give the files away to user "robocop" so that
# user "robocop" can roll back change sets.  (I dislike systems
# that allow one to give away files, but Bloomberg's setup of
# Solaris and AIX both allow this.)

sub write_added_removed_symbols ($$$$$) {
    my($csid,$movetype,$list,$tag, $logfile) = @_;
    my $file = COMPCHECK_DIR.$FS.$movetype.$FS."symbols".$FS."$tag.$csid";
    my $FH = new IO::Handle;
    open($FH,'>'.$file)
      || fatal("open $file: $!");
    $logfile->log_verbose("$movetype $tag symbols:");
    print $FH map { $_->getLongName(). " ". $_->getType()."\n" } @$list;
    $logfile->log_verbose(map { $_->getLongName(). " " . $_->getType() . "\n" } @$list);
    close $FH;
#    my $uid = (getpwnam("robocop"))[2] || 20066;
#    chown($uid,-1,$file);
}

sub store_added_removed_symbols ($$$$$) {
    my($cs,$csid,$added,$removed, $logfile) = @_;
    return unless (scalar @$added || scalar @$removed);
    my $umask = umask(0002);
    my @movetypes = ($cs->getUser() ne "registry")
      ? ($cs->getMoveType())
      : (MOVE_EMERGENCY, MOVE_BUGFIX, MOVE_REGULAR);
    foreach my $movetype (@movetypes) {
	write_added_removed_symbols($csid,$movetype,$added,"added", $logfile)
	  if @$added;
	write_added_removed_symbols($csid,$movetype,$removed,"removed", $logfile)
	  if @$removed;
    }
    umask($umask);
}

{
  package llog;
  use Change::Symbols qw[COMPCHECK_DIR];
  use Util::Message qw(warning verbose);
  sub open_logfile {
    my ($opts) = @_;
    my $self = {};
    # Base filename is either the changeset or 
    my $csid = $opts->{cs}->getID || '<no id>';
    if ($csid eq '<no id>') {
      $csid = 'cscompile' . time();
    }
    my $logname = COMPCHECK_DIR . '/logs/'.$csid;
    my $fh;
    open($fh, '>'.$logname) || do {warning("Unable to open log file $logname, $!"); $fh = undef } ;
    $self->{fh} = $fh;
    $self->{csid} = $csid;
    return bless $self;
  }

  sub log {
    my ($self, @args) = @_;
    my $csid = $self->{csid};
    print "(pid $$ csid $csid) ", scalar(time()), " ", @args, "\n";
    return unless defined $self->{fh};
    my $fh = $self->{fh};
    print $fh scalar(time()), " ", @args, "\n";
  }

  sub log_verbose {
    my ($self, @args) = @_;
    my $csid = $self->{csid};
    verbose("(pid $$ csid $csid) ". scalar(time()). " ". join(" ", @args));
    return unless defined $self->{fh};
    my $fh = $self->{fh};
    print $fh scalar(time()), " ", @args, "\n";
  }

  sub DESTROY {
    my $self = shift;
    if (defined $self->{fh}) {
      close $self->{fh};
    }
  }
}

#==============================================================================

{
    my $no_follow_archive_regex;
    my $ignore_libs_regex;

    sub set_besteffortlink_no_follow_archive_regex ($;$) {
	my($opts,$ignorelibs) = @_;
	my $libs = join('|', map { quotemeta $_ }
				 @{$opts->{deflibs}}, @{$opts->{core_libs}});
	if ($ignorelibs) {
	    my $ignore_list = join('|', map { quotemeta $_ }
					   split ',',$ignorelibs);
	    $ignore_libs_regex = qr/^lib(?:$ignore_list)\./;
	    $libs .= '|'.$ignore_list;  ## assumes there is -something- in $libs
	}
	$no_follow_archive_regex = qr/^lib(?:$libs)\./;
	return($no_follow_archive_regex,$ignore_libs_regex);
    }

    my $passes = 0;  ## not thread-safe

    sub besteffortlink ($$$$$$$$$$$$$$$);
    sub besteffortlink ($$$$$$$$$$$$$$$) {
	my($ctx,$opts,$baselibs,$milieu,$milieu_offline,$predefined,
	   $defined,$undefined,$offline_defined,$bbsrc_big_objs,
	   $cmns,$objs,$add_objs,$libs,$linear_link) = @_;
	$passes = 0 unless (keys %$objs);
	$passes++;
	#print STDERR "RECURSE PASS: $passes\n";

	my $i = 1; # 1-indexed; intentionally > 0
	my %lastlinkorder;
	while ($$linear_link =~ /\s(?:-l)?([^\s]+)/g) {
	    $lastlinkorder{$1} = $i++;
	}

	while (my($k,$v) = each %$add_objs) {
	    ##$objs->{$k} = $v->[0]; # (value not used)
	    $objs->{$k} = undef;
	}
	my($obj,$nobj,$src,$archive,$name,$sym,%next_objs,%linear);
	my($src_idx,$arch_idx);
	## Optimization: feedback objects pulled in during this pass
	## to reduce repetition on the link line as much as possible.
	## copy values into an array that is accessed via index so that we can
	## safely push elements onto end of array to handle them on this pass
	## (as opposed to iterating over hash values directly)
	my @add_objs = values %$add_objs;  ## ( values are [ $obj, $archive ] )
	for (my $i = 0; $i < @add_objs; $i++) {
	    $src = $add_objs[$i];
	    ## (Note: if $obj eq "unknown" here, it's usually thirdparty or .so)
	    $obj = $src->[0];
	    $src_idx = $src->[1] =~ /^lib([^.]+)\./
	      ? $lastlinkorder{$1} || 65535		#(or large index)
	      : $lastlinkorder{$src->[1]} || 65535;	#(or large index)
	    foreach $name (keys %{$obj->getUndefinedSymbols()}) {
		next if exists $predefined->{$name};
		$sym = $defined->{$name}
		  || ($offline_defined && $offline_defined->{$name})
		  || ($undefined->{$name}=1, next);
		##(Intentionally ignore data syms or dup text syms for now)
		##(attempt to catch C++ .data symbols with BloombergLP string)
		$sym->getType() eq "T" || $sym =~ /BloombergLP/ || next;
		$archive = $sym->getArchive;
		if ($archive) {
		    next if exists($objs->{$archive.':'.$sym->getObject});
		    $libs->{$archive} = 1;
		    $arch_idx = $archive =~ /^lib([^.]+)\./
		      ? $lastlinkorder{$1} || 0
		      : $lastlinkorder{$archive} || 0;
		    $archive = $milieu->getObject($archive)
			    || $milieu_offline->getObject($archive);
		    $nobj = $archive->getObject($sym->getObject);
		    if ($src_idx <= $arch_idx
			&& $archive !~ $no_follow_archive_regex) {
			if (delete $linear{$archive}->{$nobj}) {
			    delete $linear{$archive}
			      unless keys %{$linear{$archive}};
			    delete $next_objs{$archive.':'.$nobj};
			}
			$objs->{$archive.':'.$nobj} = undef;
			push @add_objs, [ $nobj, $archive ];
			next;
		    }
		    $linear{$archive}->{$nobj} = 1;
		}
		elsif (($nobj = $milieu->getObject($sym->getObject)
			    || $milieu_offline->getObject($sym->getObject))) {
		    $archive = $nobj->getPath().'/'.$nobj;
		    # do not add /bbsrc/big objects if linking for an offline
		    # (Note that skipping /bbsrc/big objects if this is an
		    #  offline may result in an undefined in the offline that
		    #  is later dummied out.  If we want to dummy it out now,
		    #  then add to %$undefined, but might instead check for
		    #  multiply defined and guess at stubbing (yuck!))
		    next if $bbsrc_big_objs
			    && exists $bbsrc_big_objs->{$archive};
		    next if exists($objs->{$archive.':'.$sym->getObject});
		    substr($$linear_link,0,0," ".$archive)
		      unless $libs->{$archive};
		    $libs->{$archive} = 1;
		    $objs->{$archive.':'.$nobj} = undef;
		    $lastlinkorder{$archive} = 1;  ## 1-indexed; b/4 -l rules
		    push @add_objs, [ $nobj, $archive ];
		    next;
		}
		else {
		    ##(should not happen unless symbols from objects are added
		    ## to defined hashes without being added to milieus)
		    next;
		}
		# (Just take the last found archive in this pass that needs this
		#  Could optimize to save the earliest archive in link line
		#  generated for this pass, but that would be a lot more work)
		if ($archive !~ $no_follow_archive_regex) {
		    $next_objs{$archive.':'.$nobj} = [ $nobj, $archive ];
		}
		else {
		    # (see while() loop above outer foreach() loop)
		    # (Core libs are moved to end of link line later on in
		    #  besteffortlinkCmd(), so skip repeated lookup here.)
		    $objs->{$archive.':'.$nobj} = undef;
		    # If library is on the ignore list, add symbol to
		    # undef list so that metalink will dummy it out.
		    $undefined->{$name}=1
		      if (defined($ignore_libs_regex)
			  && $archive =~ $ignore_libs_regex);
		}
	    }
	}
	$$linear_link .= besteffortlinearlink($baselibs,\%linear);

	my $symbols;
	foreach $src (@add_objs) {
	    $obj = $src->[0];
	    $symbols = $obj->getSymbols;
	    foreach $sym (values %$symbols) {
		next unless $sym->isDefined && $sym->getType eq 'D';
		$sym = $defined->{$sym}
		  || ($offline_defined && $offline_defined->{$sym})
		  || next;
		## (C++ .data symbols with BloombergLP are not Fortran commons)
		next if $sym =~ /BloombergLP/;
		## Store Fortran commons that might be pulled in
		## by the linker from one of multiple locations.
		## (misses case where symbols is defined exactly once in big
		##  and once in offline libs -- probably not worth extra effort)
		$cmns->{$sym} = undef if exists $sym->{dups};
	    }
	}
	undef $symbols;

	## The answer we are looking for is in $libs if there are
	## no more undefined symbols that we know how to resolve
	return $$linear_link unless (keys %next_objs);

	## undef various data refs to possibly free up some memory
	undef %lastlinkorder; undef %linear; undef @add_objs;
	undef $nobj; undef $src; undef $archive; undef $name; undef $sym;

	## Recurse to resolve more symbols
	return besteffortlink($ctx,$opts,$baselibs,$milieu,$milieu_offline,
			      $predefined,$defined,$undefined,$offline_defined,
			      $bbsrc_big_objs,$cmns,$objs,\%next_objs,$libs,
			      $linear_link);
    }

    sub besteffortlinearlink ($$) {
	my($baselibs,$linear) = @_;
	return "" unless (keys %$linear);
	my(@linear,@append);  # filter out base libs before getBuildOrder
	foreach my $lib (map { /lib([^.]+)\./ ? $1 : $_ } keys %$linear) {
	    next if (substr($lib,-2,2) eq ".o");
	    $baselibs->{$lib} ? push(@append,$lib) : push(@linear,$lib);
	}
	@linear = reverse BDE::Util::DependencyCache::getBuildOrder(@linear)
	  if (@linear);
	push @linear,@append;
	return (@linear ? " -l".join(" -l", @linear) : "");
    }

}

#==============================================================================

# Manage a cache of .o files so we don't have to rescan every time we
# need one, and so we can have the library set right for the damn things
sub load_o_file_cached {
  my ($o_file, $lib, $cache, $logfile) = @_;
  
  if (exists ($cache->{$o_file})) {
    $logfile->log_verbose("$o_file in cache");
    return $cache->{$o_file};
  }
  if (!defined $lib) {
    $logfile->log_verbose("lib undefined for $o_file\n");
    use Carp;
    confess;
  }
  if (! ($lib=~ /^lib/)) {
    $lib = 'lib' . $lib;
  }
  if (!($lib=~/\.(a|so)$/)) {
    $lib .= '.a';
  }
  # Doesn't exist. Read it in and assign it 
  my $obj = Binary::Object->new($o_file);
  my $old_name = $obj->getName;
  my $name = $old_name;
  $name =~ s/\.sundev1//;
  if ($name =~ /(\[a-zA-Z0-9_-]+\.o)$/) {
    $name = $1;
  }
  $obj->setName($name);
  $logfile->log_verbose("Loading o file. Disk name $old_name, set to name $name");
  $logfile->log_verbose("Setting archive name of symbols to $lib and object name to $name");
  map {$_->setArchive($lib); $_->setObject($name)} $obj->getSymbols();
  foreach my $sym($obj->getSymbols()) {
    $logfile->log_verbose("o_file: $name has symbol " . $sym->getLongName() . " " . $sym->getType());
  }
  $cache->{$o_file} = $obj;
  return $obj;

}

sub validate_symbols ($$);
sub validate_symbols ($$) {
    my($ctx,$opts) = @_;

    my $logfile = llog::open_logfile($opts);

    use Carp;
    local $SIG{__DIE__} = sub {confess};

    my @file_list;

    $logfile->log("validate start");
    $logfile->log("changeset ", $opts->{cs}->getID()) if $opts->{cs}->getID();
    $logfile->log("user ", $opts->{cs}->getUser());
    $logfile->log("Base libraries searched: ", $dest_library_directory, " for lib set ", $opts->{libtype});
    foreach my $file ($opts->{cs}->getFiles()) {
      my $lib = $file->getLibrary();
      if (isApplication($lib) || getCachedGroupOrIsolatedPackage($lib)->isOfflineOnly()) {
	$logfile->log("Skipping file $file, for offline lib or application");
      } else {
	my $source = $file->getSource();
	my $libobj = get_aggregate($ctx, $lib) ;
	if ($libobj) {
	  $logfile->log_verbose("file: $source obj: $file lib: $lib libobj: $libobj");
	  push @file_list, $file;
	} else {
	  $logfile->log_verbose("Can't find library object for file: $source obj: $file lib: $lib");
	}
      }
    }

    my $dep_defined_symbols = {};
    my $aggregate=new Binary::Aggregate("symbol validation");
    my $binaries; # Temp to disable compile errors during refactor

    #---- Create the aggregate of 'dependency' symbols


    verbose((@{$ctx->{targets}} ? "dependency " : "untargetted ").
      "aggregate: @{[ $aggregate->getObjects() ]}") if (get_verbose);

    #---- Analyse symbols

    my($definedsymbols,$undefinedsymbols,$options);
    my $rv=1;
    my $pendingstat = 0;
    my (%defcache, %optioncache);

    # Run through all the targets and refresh the library info for
    # them and pull in the bad symbols
    foreach my $item (@{$ctx->{targets}}) {
      next if (isApplication($item)
	       || (getCachedGroupOrIsolatedPackage($item))->isOfflineOnly
	       || $item =~ m%^bbinc/|^mlfiles$%);

      # we accept either explicit objects or a UOR library as the
      # target, not a system or generic anonymous library.
      if (isIsolatedPackage($item) or isGroup($item)) {
	my $options = $ctx->get_meta($item);
	$optioncache{$item} = $options;

	# seek out 'waived' symbols and add them to symbol list
	my $bad_symbols;
	eval {
	  $bad_symbols = $options->expandValue("_BAD_SYMBOLS")
	  unless $opts->{nobadmeta};
	};
	if ($@) {
	  fatal("Loading symbol overrides for $item failed. SYMBOL VALIDATION HAS FAILED!\nBacktrace is:\n$@");
	}
	if ($bad_symbols) {
	  my @symbols;
	  #<<<TODO: to support demangled C++ symbols, the format of
	  #_BAD_SYMBOLS will need to change since the symbol might
	  #contain spaces
	  foreach (split /(?:\s+|,)/s,$bad_symbols) {
	    # skip symbols that begin with '#'
	    # (note that '#' must immediately precede symbol
	    #  no spaces inbetween '#' and symbol)
	    push @symbols,$_ unless (substr($_,0,1) eq "#");
	    $logfile->log_verbose("Library $item: Adding weak symbol >$_<") unless (substr($_,0,1) eq "#");
	  }
	  if (get_verbose) {
	    verbose2 "added ".scalar(@symbols)
	      ." symbol waivers for $item: @symbols";
	  }
	  push @{$opts->{symbols}}, @symbols;
	  my %weaks; @weaks{@symbols} = (@symbols);
	  $opts->{weak_symcache}{$item} = \%weaks;
	}
      } else {
	fatal("Got a bare object $item!");
	#	        load_object($binaries => $item); #indeterminate origin
      }
    }

    $logfile->log("refresh done");

    my $plink_archive = Binary::Aggregate->new("plink objects");
    my %notfoundlibs;
    # Now load in the dependency list and defined symbols for the libs
    foreach my $item (@{$ctx->{targets}}) {
      next if (isApplication($item)
	       || (getCachedGroupOrIsolatedPackage($item))->isOfflineOnly
	       || $item =~ m%^bbinc/|^mlfiles$%);

      my $obj = getCachedGroupOrIsolatedPackage($item);
      my %bad_libs = map { $_ => 1 }  $obj->getWeakDependants();

      # load direct dependencies into dependency aggregate
      my @listed_deps = isGroup($item)
	? getGroupDependencies $item
	  : getPackageDependencies $item;
      # Filter the weaks out
      @listed_deps = grep {!defined $bad_libs{$_}} @listed_deps;
      my $baseuor = uc(substr($item, rindex($item,'/')+1));
      my $otherliblist = $optioncache{$item}->expandValue($baseuor."_OTHER_LIBS");
      my $systemliblist = $optioncache{$item}->expandValue($baseuor."_SYSTEM_LIBS");
      my $plink_objs = $optioncache{$item}->expandValue("PLINK_OBJS");
      $logfile->log_verbose("${baseuor}_OTHER_LIBS is $otherliblist");
      $logfile->log_verbose("${baseuor}_SYSTEM_LIBS is $systemliblist");
      $logfile->log_verbose("PLINK_OBJS is $plink_objs");

      # Load the plink objects into the archive
      if ($plink_objs) {
	foreach my $obj (split /\s+/, $plink_objs) {
	  load_object($plink_archive, $obj);
	}
      }

      my (@extralibs, @libpaths);
      @libpaths = @{$opts->{libpath}};
      foreach my $thing (split(/\s+/, $otherliblist . " " . $systemliblist)) {
	if ($thing =~ /-L(.*)/) {
	  unshift @libpaths, $1;
	  next;
	}
	next unless $thing=~/-l(.*)/;
	$thing = $1;
	my $agg = get_aggregate($ctx, $thing, \@libpaths);
	if ($agg) {
	  $logfile->log_verbose("adding library $agg for -l rule $thing");
	  push @extralibs, $thing;
	} else {
	  $logfile->log_verbose("Can't find library for $thing");
	}
      }
      $opts->{dependency_cache}{$item} = [@listed_deps, $item, @extralibs, 'c', 'Crun', 'Cstd', 'm', 'fsu'];
      $logfile->log_verbose("Dependencies for $item are ", join(" ", @{$opts->{dependency_cache}{$item}}));
      next;
      ####
      ####
      #### 
      foreach my $d (@listed_deps) {
	# skip libraries that are bad dependencies --
	# such libs must have bad symbols listed in _BAD_SYMBOLS
	next if ($bad_libs{$d});
	eval {
	  my $defsyms = {};
	  my $depname = $ctx->get_library_path($d);
	  if ($depname) {
	    $ctx->load_library_defines($d,$depname,
				       $defsyms);
	  } elsif (!$ctx->is_metadata_only($d)) {
	    warning("Unable to locate dependency $d for $item");
	    $ctx->fatal_library_not_found($d);
	  }
	
	  ## ThirdParty might be marked metadata-only and define
	  ## its library location(s) in the .defs file, so process
	  ## metadata for third-party.
	  if (isThirdParty($d)) {
	    my $doptions = $ctx->get_meta($d);
	    load_from_meta($ctx,$d,$aggregate,$doptions,
			   $defsyms,\%bad_libs);
	  }
	
	  $options = $ctx->get_meta($item);
	
	  load_from_meta($ctx,$item,$aggregate,$options,
			 $dep_defined_symbols,\%bad_libs)
	    unless $opts->{nodl};

	  if (get_verbose) {
	    verbose "extended dependency aggregate: "
	      ."@{[ $aggregate->getObjects() ]}";
	  }
	};
	if ($@) {
	  $notfoundlibs{$d}++;
	}
      }
    }

    $logfile->log("dependencies done");

    clean_all_symbols();

    # Go ahead and load in the changeset changes from disk
    debug("Rolling forward changesets");
    my $symchanges = roll_forward_changesets($ctx, $logfile);
    debug("Done rolling forward");

    $logfile->log("changeset roll forward done");

    # Go see what symbols have been added and removed on a per-file
    # basis.
    my (%def_added, %def_removed, %def_duplicated, %def_multidefcheck,
	%existing_undefs, %undef_added, %undef_removed, @def_dupes);
    debug("Looking for duplicates\n");
    my $o_cache = {};
    {
      my %base_objs;
      foreach my $obj_file (@file_list) {
	my $lib = $obj_file->getLibrary();
	my $libobj = get_aggregate($ctx, $lib);

	if (!defined $libobj) {
	  $logfile->log("Can't find library object for $lib");
	} else {
	  $lib = $libobj->getName();
	}

	my $bin_obj = load_o_file_cached($obj_file, $lib, $o_cache, $logfile);
	debug("Examining $obj_file for symbols\n");

	my (%new_def, %new_undef, %old_def, %old_undef);
	# Get all the new defineds and undefined
	my @defs;
	@defs = $bin_obj->getDefinedSymbols();
	$logfile->log_verbose("found defs in $bin_obj:\n  ", join("\n  ", @defs));
	debug("New defs: ".join(" ", @defs)."\n");
	@new_def{@defs} = @defs;
	@defs = $bin_obj->getUndefinedSymbols();
	$logfile->log_verbose("found undefs in $bin_obj:\n  ", join("\n  ", @defs));
	debug("New undefs: ".join(" ", @defs)."\n");
	@new_undef{@defs} = @defs;
	my (@old_o) = (split_o_files($obj_file->getSource(), $logfile));
	debug("Looking at old o files " . join(" ", @old_o));
	foreach my $base_o (@old_o) {
	  debug("looking for old .o file $base_o for lib $lib");
	  
	  my $oldlib = get_milieu()->getObject($lib);
	  if (defined $oldlib) {
	    debug("Found orig lib $oldlib");
	    my $o_name = $base_o;
	    $o_name =~ s/^.*\///;
	    my $orig_o = $oldlib->getObject($o_name);
	    if (defined $orig_o) {
	      debug("Found orig .o $orig_o");
	      @defs = $orig_o->getDefinedSymbols;
	      debug("Old defs: ".join(" ", @defs)."\n");
	      @old_def{@defs} = @defs;
	      @defs = $orig_o->getUndefinedSymbols;
	      debug("Old undefs: ".join(" ", @defs)."\n");
	      @old_undef{@defs} = @defs;
	      @{$existing_undefs{$obj_file}}{@defs} = @defs;
	    }
	  }
	}
	foreach my $sym (keys %new_def) {
	  # Remember it for later multidef checking
	  push @{$def_multidefcheck{$sym}}, $new_def{$sym};
	  if (exists $old_def{$sym}) {
	    delete $new_def{$sym};  delete $old_def{$sym};
	  } else {
	    if (exists $def_added{$sym}) {
	      push @{$def_duplicated{$sym}}, @{$def_added{$sym}}, $new_def{$sym};
	      $logfile->log_verbose("Adding new dupe defined sym ", $new_def{$sym}->getLongName());
	    }
	    $logfile->log_verbose("Adding new defined sym ", $new_def{$sym}->getLongName());
	    push @{$def_added{$sym}}, $new_def{$sym};
	  }
	}

	foreach my $sym (keys %old_def) {
	  debug("Adding removed symbol ".$old_def{$sym}."\n");
	  $logfile->log_verbose("Removing defined sym ", $old_def{$sym}->getLongName());
	  push @{$def_removed{$sym}}, $old_def{$sym};
	}

	foreach my $sym (keys %new_undef) {
	  if (exists $old_undef{$sym}) {
	    delete $new_undef{$sym};  delete $old_undef{$sym};
	  } else {
	  push @{$undef_added{$sym}},  $new_undef{$sym};
	  $logfile->log_verbose("Adding new undefined sym ", $new_undef{$sym}->getLongName());
	  }
	}

	foreach my $sym (keys %old_undef) {
	  debug("Adding removed undef ".$old_undef{$sym}."\n");
	  $logfile->log_verbose("Removing undefined sym ", $old_undef{$sym}->getLongName());
	  push @{$undef_removed{$sym}}, $old_undef{$sym};
	}

	# Right, finally go and remove the .o file from the archive.
	remove_o_for_file($ctx, $obj_file, $logfile);
      }
    }

    $logfile->log("Dupe check done");

    # At this point the archive now has the new .o files yanked
    # out. Go look to see if any of the new symbols are defined
    clean_all_symbols();
    my $defined = get_milieu_defined_symbols();
    clean_all_symbols();

    debug("There are ".scalar(keys %$defined) . " symbols in milieu\n");
    debug("Checking for multiply defined symbols\n");
    my (@multiply_defined);
    foreach my $sym (keys %def_added) {
      next if $sym =~ /__RTTI__/;
      next if $sym =~ /__vtbl_$/;
      if ($sym eq '__1cLBloombergLPIl_cnyinsPContingentClaimNgetPriceAsMid6kM_b_') {
	$logfile->log("There are ", scalar(@{$def_multidefcheck{$sym}}), " copies of __1cLBloombergLPIl_cnyinsPContingentClaimNgetPriceAsMid6kM_b_ defined");
      }
      if (exists $defined->{$sym} && $defined->{$sym}->getType eq 'T') {
	foreach my $symobj (@{$def_added{$sym}}) {
	  # Check -- going into the big .o files?
	  if ((!defined $symobj->getArchive ||
	       $symobj->getArchive eq '' ||
	       $symobj->getArchive eq 'libbig.a') &&
	      (!defined $defined->{$sym}->getArchive ||
	       $defined->{$sym}->getArchive eq '' || 
	       $defined->{$sym}->getArchive eq 'libbig.a')) {
	    next;
	  }
	  $logfile->log_verbose("Found multiply defined symbol $sym ".$defined->{$sym}->getLongName());
	  debug("Found multiply defined symbol $sym ".$defined->{$sym}->getLongName() . "\n");
	  push @multiply_defined, [$sym, $def_added{$sym}, $defined->{$sym}];
	  last;
	}
      }
    }
    foreach my $sym (keys %def_multidefcheck) {
      if (@{$def_multidefcheck{$sym}} > 1 && 
	  $def_multidefcheck{$sym}[0]->getType eq 'T') {
	push @multiply_defined, [$sym, $def_multidefcheck{$sym}, undef];
	$logfile->log_verbose("Found multiply defined symbol $sym in-changeset\n");
      }
    }


    # If we had some, dump out the multiply defined syms
    foreach my $md (@multiply_defined) {
      if ($md->[2]) {
	foreach my $sym (@{$md->[1]}) {
	  $logfile->log($sym->getLongName . " is multiply defined in " . $md->[2]->getLongName);
	  error("Symbol ".$md->[0] . " is multiply defined in ". $sym->getObject . " and " . $md->[2]->getLongName . "\n");
	  $rv = 2;
	}
      } else {
	$logfile->log($md->[0] . " is multiply defined in-changeset in " . join(" ", map {$_->getLongName} @{$md->[1]}));
	error($md->[0] . " is multiply defined in-changeset in " . join(" ", map {$_->getLongName} @{$md->[1]}));
	$rv = 2;
      }
    }

    if (%def_duplicated) {
      foreach my $symname (keys %def_duplicated) {
	next if $symname =~ /__RTTI__/;
	next if $symname =~ /__vtbl_$/;
	# Get the first of the symbol instances
	my $sym =  $def_duplicated{$symname}[0];
	# If the dupes aren't text then just bail
	next unless defined $sym; # On the off-chance we got an undef
	next if $sym->getType ne 'T';
	$rv = 2;
	my %uniq;
	foreach my $lsym (@{$def_duplicated{$symname}}) {
	  $uniq{$lsym->getLongName}++;
	}
	$logfile->log("Symbol $symname is multiply defined in-changeset in " . join(", ", sort keys %uniq) . "\n");
	error("Symbol $symname is multiply defined in-changeset in " . join(", ", sort keys %uniq) . "\n");
      }
    }

    $logfile->log("Multiply defined done");

    # Push out the changes from the .o files in the current changeset
    debug("Applying changes from changeset\n");
    clean_all_symbols();
    $pendingstat = apply_cs_changes($ctx, \@file_list, $o_cache, $logfile);
    $rv = $pendingstat if $rv == 1;
    clean_all_symbols();
    debug("Applied\n");

    $logfile->log("cs application done");

    my($base_defined_symbols,$archive_copy);

    # XXXXXXXXXXXXXXXXXXXXXXXXXXXX
    #
    # Need to set up the internal storage here.
    my (@undefs, %base_objs, %agg_cache);

    # Check symbol usage. The cache of libraries includes the
    # changeset changes, so we can assume any undefs are real undefs.
    foreach my $obj_file (@file_list) {
      my $lib = $obj_file->getLibrary();
      my $obj = load_o_file_cached($obj_file, $lib, $o_cache, $logfile);
      $lib =~ s/^lib//;
      $lib =~ s/\..*//;
      my $libname = get_aggregate($ctx, $lib)->getName();
      $logfile->log_verbose("Checking for $lib/$libname $obj_file for undefs");
      debug("Checking .o file $obj_file for undefs\n");

    SYMLOOP:
      foreach my $undef_sym ($obj->getUndefinedSymbols()) {
	my $weakname = $undef_sym->getLongName();
	$weakname =~ s/\.sundev1//;
	$logfile->log_verbose("Looking for weak permission in $lib/$libname for $undef_sym ($weakname)\n");
	if (defined $opts->{weak_symcache}{$lib}{$undef_sym}) {
	  $logfile->log_verbose("Weak symbol defined for $lib $undef_sym");
	  next SYMLOOP;
	}
	if (defined $opts->{weak_symcache}{$libname}{$undef_sym}) {
	  $logfile->log_verbose("Weak symbol defined for $libname $undef_sym");
	  next SYMLOOP;
	}
	if (defined $opts->{weak_symcache}{$lib}{$weakname}) {
	  $logfile->log_verbose("Weak symbol defined for $lib $weakname");
	  next SYMLOOP;
	}
	if (defined $opts->{weak_symcache}{$libname}{$weakname}) {
	  $logfile->log_verbose("Weak symbol defined for $libname $weakname");
	  next SYMLOOP;
	}
	# Skip if the undef already existed
#	if (exists $existing_undefs{$obj}{$undef_sym}) {
#	  $logfile->log("pre-existing Weak symbol defined for $obj $undef_sym");
#	  next SYMLOOP;
#	}


	$logfile->log_verbose("Looking for strong permission in $lib/$libname for $undef_sym ($weakname)\n");

	# So the undef isn't grandfathered. That's fine. Go see if our
	# dependent libraries provide it
	foreach my $deplib (@{$opts->{dependency_cache}{$lib}}) {
	  next if $deplib eq 'big';
	  # Skip if we haven't found the library
	  next if exists $notfoundlibs{$deplib};
	  my $aggregate = $agg_cache{$deplib};
	  if (!defined $aggregate) {
	    $logfile->log_verbose("Loading aggregate for $deplib");
	    $aggregate =  get_aggregate($ctx, $deplib);
	    $agg_cache{$deplib} = $aggregate || 0;
	  }
	  if (!defined $aggregate || !$aggregate) {
	    debug("Can't find aggregate for dependent lib $deplib\n");
	    next;
	  }
	  my $deplibname = $aggregate->getName();
	  
	  if (!exists($defcache{$deplibname})) {
	    $logfile->log_verbose("Populating defined cache for $deplibname\n");
	    $defcache{$deplibname} = $aggregate->getDefinedSymbols();
	  }
	  # Skip if a strong dependent has the sym
	  if (defined $defcache{$deplibname}{$undef_sym}) {
	    $logfile->log_verbose("$undef_sym provided by $deplibname");
	    next SYMLOOP;
	  }
	}
	if (!exists($defcache{__PLINK_OBJS__})) {
	  $defcache{__PLINK_OBJS__} = $plink_archive->getDefinedSymbols();
	}
	if (defined $defcache{__PLINK_OBJS__}{$undef_sym}) {
	  $logfile->log_verbose("$undef_sym provided by bare plink objects");
	  next SYMLOOP;
	}

	# No dependent libs providing, and no weak declaration, so
	# remember for later
	$logfile->log_verbose("Adding undef $undef_sym to obj file $obj_file");
	if (getCachedGroupOrIsolatedPackage($lib)->isHardValidation) {
	  # Hey, it's a hard validation error!
	  $rv = 2;
	  push @undefs, [$obj_file, $undef_sym, 1];
	} else {
	  push @undefs, [$obj_file, $undef_sym, 0];
	}
	
      }
    }
    $logfile->log("undef check done");

    # Right, notes. At this point we have:
    #
    # @undefs. An array of arrays of object file/symbol pairs, that
    #          contains the symbols in the changeset not satisfied by
    #          the base library or any of its declared dependents, and
    #          that have been newly added in the file.
    #
    # %def_added A hash of added symbols. Keys are symbols, values are
    #             the object file the symbol's defined in
    #
    # %def_removed A hash of the removed symbols. Keys are the
    #                symbols, values are the object files the symbols
    #                have been removed from object files
    #
    # %def_duplicated Symbols that are defined in multiple files in
    #                   the changeset
    #
    # %undef_added New undefs for the objects in the changeset.

    # This means whe know what's undefined per dependencies, what's
    # been added, what's been removed, and what's been duplicated in
    # the changeset. We still lack the note of the things that have
    # been duplicated in other object files. I don't know of any good
    # way to do that short of just ripping through each and every
    # object file and complaining. So... we're going to do that.


    # Okay, we have the dupes. Just do a test dump

    $defined = get_milieu_defined_symbols();
    my $defined_offline;
    foreach my $undef (@undefs) {
      my ($obj, $sym) = @$undef;
      $logfile->log_verbose("$obj has undef $sym");
      if (!exists $defined->{$sym}) {
	if (!defined $defined_offline) {
	  $defined_offline = get_milieu_offline_defined_symbols();
	}
	if (!exists $defined_offline->{$sym}) {
	  $rv = 2;
	}
      }
    }
    foreach my $sym (keys %undef_added) {
      foreach my $symobj (@{$undef_added{$sym}}) {
	my $obj = $symobj->getObject;
	$logfile->log_verbose("Added undef $sym to $obj\n");
      }
    }

    $logfile->log("Check for unresolvable undefs done");

    # Go look for a main and yell if we find one
    foreach my $obj (@file_list) {
      my $lib = $obj->getLibrary;
      next if isApplication($lib);
      my $object = load_o_file_cached($obj, $lib, $o_cache, $logfile);
      next unless $object->getSymbol("main");

      error("Disallowed: main() not allowed in ".$obj->getSource()."\n");
      $rv = 2;
    }

    $logfile->log("main check done");


    my (@added, @removed, @removed_defs);
    foreach my $sym (keys %def_added) {
      foreach my $symobj (@{$def_added{$sym}}) {
	$logfile->log_verbose("Added symbol ", $symobj->getLongName());
	push @added, $symobj;
      }
    }
    foreach my $sym (keys %def_removed) {
      foreach my $symobj (@{$def_removed{$sym}}) {
	$logfile->log_verbose("Removed symbol ", $symobj->getLongName());
	push @removed, $symobj;
	push @removed_defs, $symobj;
      }
    }
    foreach my $sym (keys %undef_added) {
      foreach my $symobj (@{$undef_added{$sym}}) {
	$logfile->log_verbose("Added undef ", $symobj->getLongName());
	push @added, $symobj;
      }
    }
    foreach my $sym (keys %undef_removed) {
      foreach my $symobj (@{$undef_removed{$sym}}) {
	$logfile->log_verbose("Removed undef ", $symobj->getLongName());
	push @removed, $symobj;
      }
    }

    $logfile->log("add/remove done");

    my ($cs, $csid);
    $cs = $opts->{cs};
    $csid = $cs->getID() || '<no id>';

    # write out files of new symbols added and old symbols removed
    # (skip writing out if this is a test compile (csid=="<no id>"))
    store_added_removed_symbols($cs,$csid,\@added,\@removed, $logfile)
      if ($csid ne "<no id>");

    $logfile->log("storage done");

    if ($cs->getUser() eq "registry") {
      $logfile->log_verbose("registry user, exiting cleanly");
      return(EXIT_SUCCESS);
    }

    my ($added, $removed);

    #(Although offlines, apps, and functions (f_* libs) do not need to
    # have added/removed symbols validated, to skip these next steps, we
    # would need to verify that changeset consisted only of such items.)
    debug("Checking for in use symbols\n");
    if (!in_use_symbol_check($csid,\@removed_defs, $logfile)) {
      $rv = 2;
      #$rv = 0 if $rv == 1;
    }
    debug("done checking\n");

    $logfile->log("in use check done");

    report_symbols "undefined:", \@undefs, $opts->{match};

    $logfile->log("report done");

    if ($rv != 2) {
      foreach my $ofile ($cs->getFiles()) {
	my $source = $ofile->getSource();
	save_source_to_o_mapping($cs, $source, $logfile);
      }
    }

    # always report undefined symbols even if no undefined report
    verbose_alert scalar(keys %$undefinedsymbols)." undefined symbols"
      .($opts->{match} ? " matching $opts->{match}" : "")." after resolution";

    #---- Exit
    return 2 if ($rv == 2);  ## daemon validation failed; fatal error
    return EXIT_FAILURE if ($rv == 0);  ## daemon validation failed

    # return status = one (1) if undefined symbols (zero (0) = none = success);
    return (scalar(@undefs) ? EXIT_FAILURE : EXIT_SUCCESS);
    return $rv;



}

#==============================================================================

use constant SYMBOL_HTTP_USER_AGENT => "symbol_oracle.pl/0.1";

# This subroutine copied directly from the perlipc man page.
# (and modified slightly)
sub daemonize {
    require POSIX;
    chdir '/'                 or die "Can't chdir to /: $!";
    open STDIN,  '</dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork)   or die "Can't fork: $!";
    exit if $pid;
    POSIX::setsid()           or die "Can't start a new session: $!";
    open STDERR, '>&STDOUT'   or die "Can't dup stdout: $!";
}

sub httpClient_symbol_validate($$) {
    require LWP::UserAgent;
    my ($ctx, $opts) = @_;
    my (@instances) = hosts_and_ports($opts);

    my $csid = $opts->{csid} || "";
    my $file = $opts->{file} || "";
    my $argv = join('\0',@ARGV);
    #unless ($csid || $argv) {
    #    usage("Missing required argument: --csid=<num>");
    #    return 2;
    #}

    my $retrycount;
    foreach my $instance (@instances) {
      $retrycount++;
      my ($host, $port) = @$instance;
      my $uri = new URI;
      $uri->scheme("http");
      $uri->authority("$host:$port");
      $uri->path("symbol_validate");
      $uri->query_form(csid => $csid, file => $file, argv => $argv);
      #$uri->query_form(%$opts, csid => $csid, file => $file, argv => $argv);
      debug("URI = $uri") if $opts->{debug};

      my $request = new HTTP::Request(GET => $uri);
    
      my $client = new LWP::UserAgent(agent => SYMBOL_HTTP_USER_AGENT,
				      timeout => 2400);
      my $response = $client->request($request);
      if (!$response->is_success) {
        print STDERR "Server error ($host:$port): ", $response->message, "\n\n";
        print STDERR $response->content;
	# If it's not a 499 error (which is a "we validated, you
	# failed" status) then we're facing some sort of server
	# problem. 
	if ($response->code != 499) {
	  print STDERR "trying alternate server\n";
	  next;
	} else {
	  return 1;
	}
      }

      print $response->content;
      return 0;
    }
    print STDERR "No servers responded, validation failed\n";
    return 1;
}

sub httpClient_symbol_lookup($) {
    require LWP::UserAgent;
    my $opts = shift;
    my (@instances) = hosts_and_ports($opts);

    foreach my $instance (@instances) {
      my ($host, $port) = @$instance;
      my $uri = new URI;
      $uri->scheme("http");
      $uri->authority("$host:$port");
      $uri->path("symbol_lookup");
      $uri->query_form(%$opts);
      debug("URI = $uri") if $opts->{debug};

##<<<TODO RFE: make bidirectional and asyncronous
      my $content;
      {
	local $/ = undef;
	$content = <STDIN>;
      }

      my $client = new LWP::UserAgent(agent => SYMBOL_HTTP_USER_AGENT,
				      timeout => 60);
      my $response = $client->post($uri, [$content]);
      if (!$response->is_success && $response->code != 499) {
        print STDERR "Server error: ", $response->message, "\n";
	next;
        return 1;
      }

      print $response->content unless $response->content eq "#\r\n";
      return 0;
    }
    return 1;
}


{
  ##<<<TODO: replace this with Sys::Filesystem from CPAN

  ## NOTE: 'man mnttab' warns that parsing /etc/mnttab for dev= is not
  ## safe in 64-bit environments and that getextmntent() should be used.
  ## (Doing it this way works for now, at least on Solaris 9)
  my %solaris_device_map;
  sub _init_solaris_device_map () {
    my $FH = Symbol::gensym;
    open($FH,'<',"/etc/mnttab") || return;
    while (<$FH>) {
	$solaris_device_map{hex($2)} = $1
	  if /^\S+\s+\S+\s+(\S+)\s+\S*\bdev=([0-9A-Fa-f]+)/;
    }
    close $FH;
  }

  my %aix_mount_map;
  sub _init_aix_mount_map () {
    my $PH = Symbol::gensym;
    open($PH,'-|',"/usr/sbin/lsfs") || return;
    $_ = <$PH>;  # discard header line
    my($mount,$fstype);
    while (<$PH>) {
	(undef,undef,$mount,$fstype) = split ' ';
	$aix_mount_map{$mount} = $fstype if defined($mount) && defined($fstype);
    }
    close $PH;
  }

  ## returns 1 for true, 0 for false, undef for unknown (also false)
  sub is_file_on_nfs ($) {
    my $file = shift;
    stat($file) || return undef;
    my($device) = stat(_);
    return 1 if ($device < 0);  ## some systems use negative numbers for NFS
    if ($^O eq "solaris") {
	_init_solaris_device_map() unless %solaris_device_map;
	my $fstype = $solaris_device_map{$device};
	return defined $fstype ? $fstype eq "nfs" : undef;
    }
    elsif ($^O eq "aix") {
	## NOTE: expects $file to be an absolute path; use Cwd::abs_path() arg
	init_aix_mount_map() unless %aix_mount_map;
	my $fstype;
	my @segments = split '/',$file;
	while (@segments > 1) {
	    $fstype = $aix_mount_map{join('/',@segments)};
	    last if defined($fstype);
	    pop @segments;
	}
	$fstype = $aix_mount_map{'/'} unless defined($fstype);
	return defined $fstype
	  ? $fstype =~ /^(?:nfs|nfs3|nfsv3|nfs4|nfsv4)$/
	  : undef;
    }
    else {
	## unhandled; could parse 'mount' output, but would have to set up
	## such parsing on a per-platform basis since output is OS-specific
	return undef;
    }
  }
}


sub httpClient_besteffortlink($) {
    require LWP::UserAgent;
    my $opts = shift;
    my (@instances) = hosts_and_ports($opts);
    my $retrycount;
    my @errors;
    foreach my $instance (@instances) {
      $retrycount++;
      my ($host, $port) = @$instance;
      my $uri = new URI;
      $uri->scheme("http");
      $uri->authority("$host:$port");
      $uri->path("besteffortlink");
      $uri->query_form(%$opts);
      debug("URI = $uri") if $opts->{debug};

      ## NFS-visible location for temporary files
      my $filedroptop = CSCOMPILE_TMP."/metalink";
      -d $filedroptop || (mkdir($filedroptop) && chmod(02777,$filedroptop));
      my $filedrop = $filedroptop."/$^T.$$.".substr(rand(),2); # ok; not great

      my $response = "";
      my $content = "";
      my $umask = umask(0002);
      {
	require Cwd;
	require File::Copy;
	is_file_on_nfs("/"); ## (initialize caches before local $/ = undef)
	local $/ = undef;
	my(@content,$path);
	foreach my $arg (split ' ',<STDIN>) {
	    if (substr($arg,0,2) ne "-l" && $arg =~ /\.(?:o|a|so)$/) {
		unless (-f $arg) {
		    $response .= "error processing object file: $arg\n"
			      .  "  (file does not exist)\n";
		    next;
		}
		$arg = Cwd::abs_path($arg);
		unless (is_file_on_nfs($arg)) {
		    ## copy file to NFS-visible locn unless sure already on NFS
		    ## preserve entire path under $filedrop
		    $path = $filedrop.substr($arg,0,rindex($arg,'/'));
		    unless ((-d $path || File::Path::mkpath($path))
			    && File::Copy::copy($arg, $filedrop.$arg)) {
			$response.="Unable to copy $arg to $filedrop$arg: $!\n";
		    }
		    $arg = $filedrop.$arg;
		}
	    }
	    push(@content,$arg);
	  }
	$content = join(" ",@content);
      }
      umask($umask);
      if ($response ne "") {
        File::Path::rmtree($filedrop) if (-d $filedrop);
        print STDERR "Server error: Bad Request\n", $response;
        return 1;
      }

      my $client = new LWP::UserAgent(agent => SYMBOL_HTTP_USER_AGENT,
				      timeout => 3600);
      $response = $client->post($uri, [$content]);

      ## clean up files copied from local disk (to make them visible to daemon)
      File::Path::rmtree($filedrop) if (-d $filedrop);
      if (!$response->is_success) {
	push @errors, "Server error: ". $response->message. "\n";
	push @errors,  $response->content unless $response->content eq "#\r\n";
	# If it's not a 499 error (which is a "we validated, you
	# failed" status) then we're facing some sort of server
	# problem. 
	if ($response->code != 499 && $retrycount < @instances) {
	  push @errors, "trying next server";
	  next;
	} else {
	  chomp @errors;
	  print STDERR join("\n", @errors), "\n";
	  return 1;
	}
      }
      print $response->content unless $response->content eq "#\r\n";
      return 0;
    }
}

sub httpClient_symbol_refresh($) {
    require LWP::UserAgent;
    my $opts = shift;
    my (@instances) = hosts_and_ports($opts);
    foreach my $instance (@instances) {
      my $port = $instance->[1];
      my $host = $instance->[0];

      my $uri = new URI;
      $uri->scheme("http");
      $uri->authority("$host:$port");
      $uri->path("symbol_refresh");
      debug("URI = $uri") if $opts->{debug};

      my $client = new LWP::UserAgent(agent => SYMBOL_HTTP_USER_AGENT);
      my $response = $client->get($uri);
      unless ($response->is_success) {
        print STDERR "Server error: ($host/$port) ", $response->message, "\n";
      }

      print $response->content;
    }
    return 0;
}

sub httpResponse($$;$$)
{
    my ($client, $statusCode, $statusString, $content) = @_;

    $statusString = HTTP::Status::status_message($statusCode)
      unless (defined($statusString) && $statusString ne "");
    $$content = defined($statusString) ? $statusString : ""
      unless (defined($content) && $$content ne "");
    $$content =~ s/([^\n])\Z/$1\r\n/;  # Add newline if missing

    my $headers = new HTTP::Headers;
    $headers->header('Connection' => 'close',
                     'Expires'    => '0');
    my $response = new HTTP::Response($statusCode, $statusString,
				      $headers, $content);

    $client->send_response($response) if ($client);

    return $response;
}

sub killCmd($$$$$$$) {
    my ($server, $request, $ctx, $opts, $client, $command, $args) = @_;
    httpResponse($client, HTTP::Status::RC_OK(), undef,
		 \"symbol_oracle daemon killed");
    $client->close;
    $server->shutdown(2) if $server;
    exit 0;
}

{
  my $refreshing = 0;  # serialize refreshes

# should this routine send ourselves a HUP signal?
# should it be removed entirely?
  sub refresh_milieu($$$$$$$) {
    my ($server, $request, $ctx, $opts, $client, $command, $args) = @_;

    return httpResponse($client, HTTP::Status::RC_OK())
      if ($refreshing == 1); # serialize refreshes

    my $pid = fork(); # (could be more robust here and check for EAGAIN)
    return httpResponse($client, HTTP::Status::RC_SERVICE_UNAVAILABLE())
      unless defined($pid);

    $refreshing = 1;  # (make sure child does not fork for any refreshes)
    return httpResponse($client, HTTP::Status::RC_OK())
      if ($pid == 0); # fork and continue processing requests in child

    # If parent, re-init and then send child a signal to gracefully exit
    my $FH;
    open( $FH, ">>symbol_oracle.pid");
    print $FH $pid,"\n";
    close $FH;
    init_milieu($ctx, $opts);
    kill(2,$pid); # send child INT signal to have it gracefully exit
    $refreshing = 0;
  }
}

# Return a list of host/port array refs for the oracles answering
# queries for local, source, or stage. The returned 
sub hosts_and_ports {
  my ($opts) = @_;
  my @instances;
  if ($opts->{libtype} eq 'source') {
    if (time % 2) {
      push @instances, [SYMBOL_ORACLE_SOURCE_HOST1, SYMBOL_ORACLE_SOURCE_PORT1];
      push @instances, [SYMBOL_ORACLE_SOURCE_HOST2, SYMBOL_ORACLE_SOURCE_PORT2];
    } else {
      push @instances, [SYMBOL_ORACLE_SOURCE_HOST2, SYMBOL_ORACLE_SOURCE_PORT2];
      push @instances, [SYMBOL_ORACLE_SOURCE_HOST1, SYMBOL_ORACLE_SOURCE_PORT1];
    }
    if ($opts->{port} || $opts->{host}) {
      my $port = ($opts->{port} || SYMBOL_ORACLE_SOURCE_PORT1);
      my $host = ($opts->{host} || SYMBOL_ORACLE_SOURCE_HOST1);
      unshift @instances, [$host, $port];
    }
  } elsif ($opts->{libtype} eq 'stage') {
    if (time % 2) {
      push @instances, [SYMBOL_ORACLE_STAGE_HOST1, SYMBOL_ORACLE_STAGE_PORT1];
      push @instances, [SYMBOL_ORACLE_STAGE_HOST2, SYMBOL_ORACLE_STAGE_PORT2];
    } else {
      push @instances, [SYMBOL_ORACLE_STAGE_HOST2, SYMBOL_ORACLE_STAGE_PORT2];
      push @instances, [SYMBOL_ORACLE_STAGE_HOST1, SYMBOL_ORACLE_STAGE_PORT1];
    }
    if ($opts->{port} || $opts->{host}) {
      my $port = ($opts->{port} || SYMBOL_ORACLE_STAGE_PORT1);
      my $host = ($opts->{host} || SYMBOL_ORACLE_STAGE_HOST1);
      unshift @instances, [$host, $port];
    }
  } elsif ($opts->{libtype} eq 'prod') {

    if (time % 2) {
      push @instances, [SYMBOL_ORACLE_PROD_HOST1, SYMBOL_ORACLE_PROD_PORT1];
      push @instances, [SYMBOL_ORACLE_PROD_HOST2, SYMBOL_ORACLE_PROD_PORT2];
    } else {
      push @instances, [SYMBOL_ORACLE_PROD_HOST2, SYMBOL_ORACLE_PROD_PORT2];
      push @instances, [SYMBOL_ORACLE_PROD_HOST1, SYMBOL_ORACLE_PROD_PORT1];
    }
    if ($opts->{port} || $opts->{host}) {
      my $port = ($opts->{port} || SYMBOL_ORACLE_PROD_PORT1);
      my $host = ($opts->{host} || SYMBOL_ORACLE_PROD_HOST1);
      unshift @instances, [$host, $port];
    }
  } else {
    if (time % 2) {
      push @instances, [SYMBOL_ORACLE_LOCAL_HOST1, SYMBOL_ORACLE_LOCAL_PORT1];
      push @instances, [SYMBOL_ORACLE_LOCAL_HOST2, SYMBOL_ORACLE_LOCAL_PORT2];
    } else {
      push @instances, [SYMBOL_ORACLE_LOCAL_HOST2, SYMBOL_ORACLE_LOCAL_PORT2];
      push @instances, [SYMBOL_ORACLE_LOCAL_HOST1, SYMBOL_ORACLE_LOCAL_PORT1];
    }
    if ($opts->{port} || $opts->{host}) {
      my $port = ($opts->{port} || SYMBOL_ORACLE_LOCAL_PORT1);
      my $host = ($opts->{host} || SYMBOL_ORACLE_LOCAL_HOST1);
      unshift @instances, [$host, $port];
    }
  }
  return @instances;
}

##
## GPS: document that orphan objects can have name conflict in Binary::Aggregate
## So can combinations of objects where some are stubs and some are not.
## In the future, we might add detection of multiple defines for naked objects
## added to the link line, but this does not appear to happen that often, and
## when it does, it seems to be attributable to the Fortran commons problem.
##
sub besteffortlinkCmd($$$$$$$) {
    my ($server, $request, $ctx, $opts, $client, $command, $args) = @_;

    ## TODO return error unless $request->method eq 'POST'

    ## fork() and continue; no need to serialize these requests
    defined(my $pid = fork()) or die "Can't fork: $!";
    return if $pid;
    $server->close() if $server;

    local $SIG{ALRM} = sub {
	httpResponse($client,HTTP::Status::RC_GATEWAY_TIMEOUT(),undef,
		     \("Server unable to process request in "
		      ."timely manner due to heavy workload.\n"
		      ."Please try again in a little while.\n"));
	require POSIX;
	POSIX::_exit(0);  # child exit without calling object destructors
    };
    alarm(3595);  ## <60 minutes; the time before our client is set to time out

    my $response = "";

    ## Read in symbols and print out response of lookup
    ##<<<TODO: use common routines to do URL-decode;
    ## or do different, more efficient form-encoding
    my $content = $request->content_ref() || \("");
    chop($$content) if substr($$content,-1,1) eq '='; ## ???
    $$content =~ tr/+/ /s;
    $$content =~ s/%([0-9A-F]{2})/pack("C", hex($1))/egi;
    my($obj,%undef_syms,%predefined);
    foreach my $name (split " ",$$content) {
	if (substr($name,0,2) ne "-l" && $name =~ /\.(?:o|a|so)$/) {
	    ## For now, we only work on objects created on Sun.
	    ## If we are given an object which tells us it was created on IBM
	    ## give back a useful error message
	    if ($name =~ /\.ibm\.(?:o|a|so)$/) {
		$response .= "error processing object file: $name\n"
		          .  "  (please pass objects created under Solaris)\n";
		next;
	    }
	    unless (-f $name) {
		$response .= "error processing object file: $name\n"
		          .  "  (file does not exist)\n";
		next;
	    }
	    unless (-r _) {
		$response .= "error processing object file: $name\n"
		          .  "  (file is not readable (not world-readable?))\n";
		next;
	    }
	    $obj = undef;
	    eval { $obj = substr($name,-2,2) eq ".o"
		      ? new Binary::Object($name)
		      : new Binary::Archive($name) };
	    if ($obj) {
		$obj->getAllUndefines(\%undef_syms);
		$obj->getDefinedSymbols(\%predefined);
	    }
	    else {
		$response .= "error processing object file: $name ($@)\n";
	    }
	}
	else {
	    $undef_syms{$name} = undef;
	}
    }
    if ($response ne "") {
	httpResponse($client,HTTP::Status::RC_BAD_REQUEST(),undef,\$response);
	require POSIX;
	POSIX::_exit(0);  # child exit without calling object destructors
    }

    BDE::Util::DependencyCache::setFaultTolerant(1);
    my $baselibs;
    map { $baselibs->{$_} = 1 } @{$opts->{deflibs}}, @{$opts->{core_libs}},
				@{$opts->{thirdparty}};

    my $linear_link = "";
    my $defined = get_milieu_defined_symbols();
    my $offline_defined = get_milieu_offline_defined_symbols()
      if $args->{offline};  # (otherwise undef)
    my $bbsrc_big_objs = get_bbsrc_big_objs()
      if $args->{offline};  # (otherwise undef)
    my $undefined = {};
    my $milieu = get_milieu();
    my $milieu_offline = get_milieu_offline();
    my($sym,$archive,$nobj,%next_objs,%libs);
    my $objs = {};
    my $cmns = {};
    my($no_follow_archive_regex,$ignore_libs_regex) =
      set_besteffortlink_no_follow_archive_regex($opts,$args->{ignorelibs});

    foreach my $name (keys %undef_syms) {
	next if exists $predefined{$name};
	$sym = $defined->{$name}
	    || ($offline_defined && $offline_defined->{$name})
	    || ($undefined->{$name}=1, next);
	if ($sym->getType eq 'D') {
	    ## Store Fortran commons that might be pulled in
	    ## by the linker from one of multiple locations.
	    ## (C++ .data symbols with BloombergLP are not Fortran commons)
	    ## (misses case where symbols is defined exactly once in big
	    ##  and once in offline libs -- probably not worth extra effort)
	    $cmns->{$sym} = undef if (exists $sym->{dups}#(see besteffortlink())
				      && $sym !~ /BloombergLP/);
	}
	##(Intentionally ignore data symbols or duplicated text symbols for now)
	##(attempt to catch C++ .data symbols containing BloombergLP string)
	$sym->getType() eq "T" || $sym =~ /BloombergLP/ || next;
	$archive = $sym->getArchive;
	if ($archive) {
	    $libs{$archive} = 1;
	    $archive = $milieu->getObject($archive)
		    || $milieu_offline->getObject($archive);
	    $nobj = $archive->getObject($sym->getObject);
	}
	elsif (($nobj = $milieu->getObject($sym->getObject)
		    || $milieu_offline->getObject($sym->getObject))) {
	    $archive = $nobj->getPath().'/'.$nobj;
	    substr($linear_link,0,0," ".$archive)
	      unless $libs{$archive};
	    $libs{$archive} = 1;
	}
	else {
	    ##(should not happen unless symbols from objects are added
	    ## to defined hashes without being added to milieus)
	    next;
	}
	if ($archive !~ $no_follow_archive_regex) {
	    $next_objs{$archive.':'.$nobj} = [ $nobj, $archive ];
	}
	else {
	    $objs->{$archive.':'.$nobj} = undef; # (see besteffortlink())
	    $undefined->{$name}=1
	      if (defined($ignore_libs_regex)
		  && $archive =~ $ignore_libs_regex);
	}
    }
    $linear_link .= besteffortlinearlink($baselibs,\%libs);
    besteffortlink($ctx,$opts,$baselibs,$milieu,$milieu_offline,\%predefined,
		   $defined,$undefined,$offline_defined,$bbsrc_big_objs,$cmns,
		   $objs,\%next_objs,\%libs,\$linear_link);
    # Remove libraries listed in $opts->{ignorelibs}, if any
    if ($args->{ignorelibs}) {
	foreach my $lib (split ',',$args->{ignorelibs}) {
	    $linear_link =~ s/ -l\Q$lib\E\b//g;
	}
    }
    # Some hand-waving heuristics/observations
    # gtkcore depends on gap which depends on eqtyutil and rptutil (calc route),
    # but if we assume someone else pulled these in, then we can put all this
    # stuff above apputil (gtkcore is not quite ready, but let's try some of
    # its dependencies)
#    foreach my $lib (qw(gsvc gctrl goo a_basglib a_basfs bap a_xmf)) {
#	substr($linear_link, rindex($linear_link," -lapputil")+1, 0, "-l$lib ")
#	  if ($linear_link =~ s/ -l$lib\b//g);
#    }
    # Move compliant hierarchical libraries to the end of link line to optimize
    # away excess duplication.  This list should be in dependency order and,
    # while not the most efficient algorithm, is clear to the reader.  Besides,
    # the string we are operating on is not obscenely long.  Only stuff at the
    # bottom of the link line can move here; no discontinuities as we move up.
    # (I am cheating a bit: bbglib needs savrng in nscrlib, but if you need it,
    #  there is very high probability it was pulled in before you reach bbglib)
    my $plink_provided = "";
# DRS: This region's commented out because it's no longer safe to
# assume these libraries are well formed. They seem to be sprouting
# dependencies that invalidate this code.
#     foreach my $lib (qw(mgk mgu
# 			gsvg a_comdb2glib a_bcem gobject
# 			glibmm sigc++ spidermonk expat_g a_bdema bbglib
# 			bregacclib bregutil
# 			a_comdb2
# 			isl intbasic
# 			e_ipc bbipc 
# 			dbutil peutil
# 			bmq jmq jms tsi fas fab ace
# 			a_gtdb2msg a_bdedb2 a_apdcmsg a_apiymsg 
# 			a_basmq bas bsa xml smr z_bae ftncmns)) {
# 	$linear_link .= " -l$lib" if ($linear_link =~ s/ -l\Q$lib\E\b//g);
#     }
    foreach my $lib (qw(bae  bse bte bce bde)) {
      $linear_link =~ s/ -l$lib\b/ -l$lib.dbg_exc_mt/g;
#      $plink_provided.=" -l$lib.dbg_exc_mt" if ($linear_link=~s/ -l$lib\b//g);
      $linear_link.=" -l$lib.dbg_exc_mt" if ($linear_link=~s/ -l$lib\b//g);
    }
    foreach my $lib (qw(zde xercesc gnuiconv gnucharset sslplus bsafe)) {
	$linear_link .= " -l$lib" if ($linear_link =~ s/ -l$lib\b//g);
    }
    ##
    ## TODO: place thirdparty libraries at this point in the link line
    ## (read lroot/thirdparty) (e.g. xercesc, gnuiconv, gnucharset, etc)
    ## Replace libraries in link line with metadata obtained from defs files.
    ## However, some "thirdparty" like DBInterfaces has dependencies on
    ## dbutil and peutil, so this might not work.
    ##
    # Add third party -L libpaths
    # (might need to move the libbde.dbg_exc_mt.a library after this point
    #  if the thirdparty library is built against the BDE STLPort)
    #<<<TODO: optimize this better in the future to list the third party libs
    # once, and towards the end of the link line, rather than adding the -L
    # rule at the beginning of the link line
    ## GPS: need to preserve ordering in the link line since some thirdparty
    ## libs depend on other thirdparty libs.  For now put -L rules at beginning
    ## of link line
    my $thirdpartylibpaths = get_thirdpartylibpaths();
    my %thirdparty_additions;  ## ok since putting all -L at beginning for now
    foreach (keys %$thirdpartylibpaths) {
	$thirdparty_additions{$thirdpartylibpaths->{$_}} = 1
	  if ($linear_link =~ m/ -l$_\b/);
    }
    $linear_link = " ".join(" ",keys %thirdparty_additions).$linear_link
      if (scalar keys %thirdparty_additions);
    # List core libraries once, and towards the end of the link list
    #<<<TODO:
    # Should prepend with macro containing proper -L rules
    # (but plink does not separate this out)
    $plink_provided .= " -R/opt/SUNWspro8/lib -L/opt/SUNWspro8/lib -Bdynamic"
      if ($^O eq "solaris" && $linear_link ne "");
    # (plink does not provide -ldemangle, although it is a system library)
    # (plink does not always provide -ldl when it is needed)
    $linear_link .= " -ldemangle" if ($linear_link =~ s/ -ldemangle\b//g);
    $linear_link .= " -ldl"       if ($linear_link =~ s/ -ldl\b//g);
    foreach my $lib (@{$opts->{core_libs}}) {
	$plink_provided .= " -l$lib"
	  if ($lib ne "demangle" && $lib ne "dl"
	      && $linear_link =~ s/ -l$lib\b//g);
    }
    # skip default libraries
    foreach my $lib (@{$opts->{deflibs}}) {
	$linear_link =~ s/ -l$lib\b//g;
    }
    # remove libraries duplicated consecutively
    $linear_link =~ s/(?<= -l)(\S+)(?: -l\1)+/$1/g;

    ## ARCHCODE and BBFA hacks
    $linear_link =~ s/\.(?:sundev1|aix)/.\$(ARCHCODE)/g;
    $linear_link =~ s|/3ps/SunOS/|/3ps/\$(UNAME)/|g;
    $linear_link =~ s|/3ps/AIX/|/3ps/\$(UNAME)/|g;

    $response .= "INCLIBS=".$linear_link."\n\n";
    $response .= $plink_provided."\n\n";

    foreach my $lib (sort keys %libs) {
	$lib =~ s/^lib//;
	$lib =~ s/\.(?:a|so)$//;
	$response .= $lib."\n";
    }
    $response .= (scalar keys %libs) ? "\n" : "\n\n";

    # remove from list of undefines known symbols that will be resolved by plink
    delete $undefined->{"plink_timestamp___"};

    foreach $sym (keys %$undefined) {
	$response .= $sym."\n";
    }
    $response .= (scalar keys %$undefined) ? "\n" : "\n\n";

    # list out Fortran commons, but only those data symbols
    # defined more than once in the Big libraries.
    foreach $sym (keys %$cmns) {
	$response .= $sym."\n";
    }
    $response .= (scalar keys %$cmns) ? "\n" : "\n\n";

    httpResponse($client, HTTP::Status::RC_OK(), undef, \$response);

    require POSIX;
    POSIX::_exit(0);  # child exit without calling object destructors
}

sub symbolValidateCmd($$$$$$$) {
    my ($server, $request, $ctx, $opts, $client, $command, $args) = @_;
    return httpResponse($client, HTTP::Status::RC_BAD_REQUEST())
      unless ($args->{csid} || $args->{file} || $args->{argv});

## GPS: TODO run in background and mail results to user?  don't forget $csid!
##	(need to serialize the updates anyway; cscompile should be run from
##	 a background daemon, and cscompile should call symbol oracle daemon)
## GPS: cscompile should capture output and mail to user if failure, and should
##	also trigger rollback of changeset.  These things are
##	for cscompile to handle, and since cscompile is not yet run in the
##	background, we want to return a failure HTTP status.

## GPS: FIXME FIXME FIXME capture STDOUT and STDERR
## Install IO::Capture, or open a temporary file and write out to disk,
## read it back in and send to user in response upon failure.
## Should probably log it as well, since we'll be in warning-mode only
## ==> log it to the cscompile log

    ## XXX: fork for now
    my $pid = fork(); # (could be more robust here and check for EAGAIN)
    return httpResponse($client, HTTP::Status::RC_SERVICE_UNAVAILABLE())
      unless defined($pid);
    return if $pid;   # parent returns to answer other requests
    $server->close() if $server;

    Util::Message::set_recording(1);

    my $wallclock = time();
    my($req_ctx,$req_opts,$rv); 
    if ($args->{file} ne "") {
	$req_opts = $opts;
	$req_ctx = init_changeset_from_file($ctx,$req_opts,$args->{file});
    }
    elsif ($args->{csid} ne "") {
	$req_opts = $opts;
	$req_ctx = init_changeset($ctx,$req_opts,$args->{csid});
    }
    else { # ($args->{argv})
	local @ARGV = split /\0/,$args->{argv};
	## XXX: how should we merge these options with parent $opts (-vvvddd) ?
	##      For now, override with parent opts
	$req_opts = getoptions();
	@{$req_opts}{keys %$opts} = values %$opts;
	## (could take all opts, but then need to know which ones are arrays
	##  and which ones aren't because %$args will have an array as a scalar
	##  when the http query string is parsed if there is only a single
	##  element in that array; the encoding of "array" does not exist.
	##  We could write our own, but not now)
## GPSGPS
## need to fix arg parsing in httpServer() before enabling this code
## GPS: Could take -vvvddd options and set them here.
##	Since we are in a forked child, it won't affect anyone else
#	foreach (qw(defined undefined nobadmeta libraries)) {
#	    $req_opts->{$_} = $args->{$_} if (exists $args->{$_});
#	}
#	unless (!exists($req_opts->{libraries}) || ref($req_opts->{libraries})){
#	    $req_opts->{libraries} = [ $req_opts->{libraries} ];
#	}
#	$req_opts->{undefined} = 0 if $req_opts->{defined};
	delete $req_opts->{uplid}; ## XXX: workaround infra changes
	$req_ctx = parse_options($req_opts);
	## XXX: TODO: should reuse $root et al from parent $ctx
	##      add support to parse_options() to do that
    }

    my $messages;
    eval {
      $rv = $req_ctx
	? (! exists $opts->{cs} || scalar $opts->{cs}->getFiles())
	  ? validate_symbols($req_ctx,$req_opts)
	    : EXIT_SUCCESS  # (no object files in changeset (e.g. headers only))
	      : EXIT_FAILURE;
      $messages = Util::Message::clear_messages() || [];
    };
    # Did we fail? Make a note of it and return a reason why
    if ($@) {
      $rv = EXIT_FAILURE;
      $messages = [$@];
    }

    $wallclock = time() - $wallclock;
    if ($rv == EXIT_SUCCESS) {
	httpResponse($client, HTTP::Status::RC_OK(), undef,
		     \join("\n","Running validation succeeded ".
				"(${wallclock}s)\n", @$messages));
    }
    else {
	httpResponse($client, 499, "Validation Failed",
		     \join("\n","Running validation **FAILED** (rc:$rv) ".
				"(${wallclock}s)\n", @$messages));
    }

    require POSIX;
    POSIX::_exit(0);  # child exit without calling object destructors
}

sub symbolLookupCmd($$$$$$$) {
    my ($server, $request, $ctx, $opts, $client, $command, $args) = @_;

    ## TODO return error unless $request->method eq 'POST'

    ## fork() and continue; no need to serialize these requests
    defined(my $pid = fork()) or die "Can't fork: $!";
    return if $pid;
    $server->close() if $server;

##<<<TODO RFE: make bidirectional and asyncronous
    ## Read in symbols and print out response of lookup
    ## (would prefer to stream in and out instead of
    ##  reading entire input and preparing entire output)
    my $content = $request->content_ref() || \("");
    ##<<<TODO: use common routines to do URL-decode
    $$content =~ tr/+/ /s;
    $$content =~ s/%([0-9A-F]{2})/pack("C", hex($1))/egi;
    my $response = "";
    my($provider,$obj);
    if ($args->{undefined}) {
	my $milieu_undefined = get_milieu_undefined_symbols();
	my $milieu_offline_undefined = $args->{offline}
	  ? get_milieu_offline_undefined_symbols()
	  : {};
	foreach my $name (split " ",$$content) {
	    foreach $provider ($milieu_undefined->{$name},
			       $milieu_offline_undefined->{$name}) {
		next unless $provider;
		foreach $obj (values %{$provider->{refs}}) {
		    next unless defined($obj);
		    $response .= $obj->getFullName()." ".$obj->getType()."\n";
		}
	    }
	}
    }
    else {
	my $milieu_defined = get_milieu_defined_symbols();
	my $milieu_offline_defined = $args->{offline}
	  ? get_milieu_offline_defined_symbols()
	  : {};
	my $want_datasym = $args->{datasym};
#	my $unknown;
	foreach my $name (split " ",$$content) {
	    foreach $provider ($milieu_defined->{$name},
			       $milieu_offline_defined->{$name}) {
		next unless $provider;
		next unless $want_datasym || $provider->getType ne 'D';
#		$unknown = 0;
		foreach $obj ($provider, @{$provider->{dups}}) {
		    next unless defined($obj);
#				 && ($obj ne "unknown" || !$unknown++));
#				## (quell repeat of symbols in system libs)
		    $response .= $obj->getFullName()." ".$obj->getType()."\n";
		}
	    }
	}
    }
    $response = "#" unless $response;
    httpResponse($client, HTTP::Status::RC_OK(), undef, \$response);

    require POSIX;
    POSIX::_exit(0);  # child exit without calling object destructors
}

my %commandDispatch = (kill                => \&killCmd,
		       besteffortlink	   => \&besteffortlinkCmd,
		       symbol_refresh	   => \&refresh_milieu,
                       symbol_lookup       => \&symbolLookupCmd,
                       symbol_validate     => \&symbolValidateCmd );

sub httpServer($$) {
    require HTTP::Daemon;
    require HTTP::Status;
    require POSIX;
    my ($ctx, $opts) = @_;
    my $port = $opts->{port};
    my $debug = $opts->{debug};

    if (!$port) {
      if ($opts->{libtype} eq 'stage') {
	$port = SYMBOL_ORACLE_STAGE_PORT;
      } elsif ($opts->{libtype} eq 'source') {
	$port = SYMBOL_ORACLE_SOURCE_PORT;
      } else {
	$port = SYMBOL_ORACLE_LOCAL_PORT;
      }
    }

    # Process HTTP requests from clients
    if (-e "symbol_oracle.pid") {
	## slight race condition here when someone else might write to the
	## pid file, but it should be rare that multiple people are manually
	## sending signals to the daemon.
	##<<<TODO: even killing these children, for some reason creating a
	## new server below takes about 30 seconds (about 15 retries)
	my $FH = Symbol::gensym;
	open( $FH, "<symbol_oracle.pid");
	while (<$FH>) {
	    chomp;
	    kill 15,$_;
	}
	close $FH;
    }
    alert("($$) Starting up HTTP server on port $port");
    my $server =  new HTTP::Daemon(LocalPort => $port,
				   Proto     => 'tcp',
				   ReuseAddr => 1);
    for (my $retry = 1; ! defined($server) && $retry <= 300; ++$retry) {
        sleep(2);
        alert("($$) Starting up HTTP server (retry $retry)");
	$server = new HTTP::Daemon(LocalPort => $port,
				   Proto     => 'tcp',
				   ReuseAddr => 1);
    }
    die "Cannot initialize HTTP server on port $port" unless ($server);

    # (Wait to unlink pid file until after we successfully attach to socket)
    if (-e "symbol_oracle.pid") {
	unlink ("symbol_oracle.pid");
    }

    my $caught_hup = 0;
    local $SIG{'HUP'} = sub { $caught_hup = 1; };
    local $SIG{'TERM'} =
      sub {
	    alert("($$) Shutting down HTTP server");
	    $server->shutdown(2) if $server;
	    ## exit quickly in an attempt to release socket more quickly
	    ## if everything else we are doing does not already do so.
	    ## Not normally the best idea to skip cleanups and buffer flushes.
	    POSIX::_exit(0);  # child exit without calling object destructors
	    #exit;
	  };
    local $SIG{'INT'} =			# (signalled from refresh_milieu())
      sub { 
	    $server->close() if $server;
	    POSIX::_exit(0);  # child exit without calling object destructors
	  };

    POSIX::sigaction(POSIX::SIGTERM(),
                     POSIX::SigAction->new($SIG{'TERM'})) # use same subroutine
          or die "Error setting SIGTERM handler: $!\n";

    # Accept client connections
    alert("($$) HTTP server is now listening on port $port");
    for (my $client;
	 $caught_hup || ($client = $server->accept()) || $caught_hup;
	 $client && $client->close) {

	if ($caught_hup) {
	    my $pid = fork(); # (could be more robust here and check for EAGAIN)
	    next unless defined($pid);
	    if ($pid == 0) {
		$caught_hup = 0;
		my $FH = Symbol::gensym;
		open( $FH, ">>symbol_oracle.pid");
		print $FH $$,"\n";
		close $FH;
		next;
	    }
	    else {
		$server->close();
		return;
	    }
	}

        # Get headers only (don't read body of request, if any)
	#<<<TODO FIXME reads request body without limit
	# (quick switch from reading headers-only
	#  so that we can now handle POST requests)
        #my $request = $client->get_request(1) or next;
        my $request = $client->get_request() or next;

        debug("    Got request: ".$request->method." ".$request->url) if $debug;

        # We can't afford to have one client hog the server, since it is
        # not multi-threaded.
        $client->force_last_request; # Disconnect after this request.

        if ($request->method ne 'GET' && $request->method ne 'POST') {
            $client->send_error(HTTP::Status::RC_FORBIDDEN());
            next;
        }

        my $command = $request->url->path;
        $command =~ s:^.*/:: ;      # Remove path portion
        $command =~ s:\.[^.]*$:: ;  # Remove extension
        my %cmdArgs = $request->uri->query_form;  # name => value arguments
## GPSGPS
## add support for --offline
## symbol_oracle -f foo.set breaks with this
#	my @cmdArgs = $request->uri->query_form;  # name => value arguments
#	my(%cmdArgs,$k,$v);
#	while (scalar @cmdArgs) {
#	    ($k,$v) = splice @cmdArgs,0,2;
#	    if (not exists $cmdArgs{$k}) {
#		$cmdArgs{$k} = $v;
#	    }
#	    elsif (ref $cmdArgs{$k}) {
#		push @{$cmdArgs{$k}},$v;
#	    }
#	    else {
#		$cmdArgs{$k} = [ $cmdArgs{$k}, $v ];
#	    }
#	}

        my $cmdFunc = $commandDispatch{$command};

        if ($cmdFunc) {
            debug("    Processing $command") if $debug;
	    $cmdFunc->($server, $request, $ctx, $opts, $client, $command,
		       \%cmdArgs);
	    my $kid; do { $kid = waitpid(-1, WNOHANG); } while $kid > 0;

        }
        else {
            debug("    Invalid request: $command") if $debug;
            httpResponse($client, HTTP::Status::RC_BAD_REQUEST(),
			 \"Illegal command: $command");
        }

        debug("Waiting for request on port $port") if $debug && !$caught_hup;
    }

    ## exit quickly in an attempt to release socket more quickly if everything
    ## else we are doing does not already do so.  Not normally the best idea
    ## to skip cleanups and buffer flushes.
    POSIX::_exit(0);  # child exit without calling object destructors
}

#==============================================================================

# Should return S, R, or ? based on what type of emove the day is.
sub get_cur_emov_day {
  my $cs = shift;
  return 'R' unless $cs; # If we got an undef changeset, then we're
                         # just going to go against 
  my $svc = Production::Services->new;
  my (@tasks, @libs);
  @tasks = $cs->getTasks;
  @tasks = ("ibig") unless @tasks;
  @libs = $cs->getTargets;
  @libs = ("acclib") unless @libs;
  my $stage = $cs->getStage;
  if (!defined $stage) {
    print "switching to beta\n";
    $stage = "beta";
  }
  my $type = Production::Services::Move::getEmoveLinkType($svc, $stage,
							  @libs, @libs);
  my $retval;
#  print "$type $stage\n";
  if (defined $type && $type =~ /stage/i) {
    $retval = 'S';
  } else {
    $retval = 'R';
  }
#  $retval = 'R';
  return $retval;
}

#
# Figure out, given the variety of commandline switches, which library
# we're needing to connect to.
#
# Basically there are three options. The first is that we're told,
# with the $opts->{tag} option. That's easy, we just use that.
sub figure_out_dest {
  my ($opts) = @_;
  if ($opts->{tag}) {
    $opts->{libtype} = $opts->{tag};
  } elsif ($opts->{stage} || $opts->{source} || $opts->{local}) {
    $opts->{libtype} = 'local'  if $opts->{local};
    $opts->{libtype} = 'stage'  if $opts->{stage};
    $opts->{libtype} = 'source' if $opts->{source};
  } else {
    my $movetype = 'move';
    my $cs;
    if ($opts->{movetype}) {
      $movetype = $opts->{movetype};
    } else {
      if ($opts->{file}) {
	$cs = eval {load Change::Set($opts->{file})};
	if (defined $cs) {
	  $movetype = 'emov' if $cs->getMoveType() eq MOVE_EMERGENCY;
	  $movetype = 'bugf' if $cs->getMoveType() eq MOVE_BUGFIX;
	  $movetype = 'move' if $cs->getMoveType() eq MOVE_REGULAR;
	} else {
	  $movetype = 'move';
	}
      } else {
	$movetype = 'move';
      }
    }
    $movetype = 'move' unless $movetype;
    $opts->{libtype} = 'source' if $movetype eq 'move';
    $opts->{libtype} = 'source' if $movetype eq 'bugf';
    if ($movetype eq 'emov') {
      my $emovtype = get_cur_emov_day($cs);
      $opts->{libtype} = 'stage' if $emovtype eq 'S';
      $opts->{libtype} = 'source' if $emovtype eq 'R';
      if ($emovtype eq '?') {
	if ($opts->{beta}) {
	  $opts->{libtype} = 'source';
	} else {
	  $opts->{libtype} = 'stage';
	}
      }
    }
  }
}

MAIN: {
  # Unbuffered output's nice, but it slows things down ever so much...
#    $|=1;
    my $opts = getoptions();

    figure_out_dest($opts);

    # symbol lookup mode
    exit httpClient_symbol_lookup($opts) if $opts->{lookup};

    # besteffortlink
    exit httpClient_besteffortlink($opts) if $opts->{besteffortlink};

    # symbol refresh
    exit httpClient_symbol_refresh($opts) if $opts->{refresh};


## GPS: quick tests to pass around @ARGV to daemon
    my @SAVED_ARGV = @ARGV;
    my $ctx = parse_options($opts);

    # If not daemon and no csid provided, just do the work and exit
    exit validate_symbols($ctx,$opts)
      if (!($opts->{daemon} || $opts->{csid} || $opts->{file})
	      && $opts->{daemon_no_connect});

    @ARGV = @SAVED_ARGV;

    # If not daemon, then contact daemon to do the work
## GPS: currently the server-side requires a csid for this request!
    exit httpClient_symbol_validate($ctx, $opts) unless $opts->{daemon};


    # Daemon
    # Clear out $opts; leave only needed opts
    # Run in background (but not if in debug mode)
    delete @{$opts}{'daemon','csid'};
    daemonize unless ($opts->{debug} || $opts->{foreground});

## GPS: FIXME only do this once and for the right area we are in
#<<TODO FIXME get these paths from the infrastructure
    my $plink_arch = $^O eq 'aix' ? "AIX" : "SunOS";
    unshift @{$ctx->{paths}}, COMPCHECK_DIR.$FS.$plink_arch;

    init_milieu($ctx, $opts);
    httpServer($ctx, $opts);

    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 TODO

This program has been tested on Solaris and AIX.

C++ symbols are not fully supported but will be in a future release.
The primary target of this program is legacy Fortan and C, not legacy
C++ (and new C++, of course, should comply with the 30 Rules)

=head1 AUTHOR

Glenn Strauss (gstrauss1@bloomberg.net)
Peter Wainwright (pwainwright@bloomberg.net),

=head1 SEE ALSO

L<bde_verify.pl>, L<bde_symverify.pl>, L<bde_stub.pl>

=cut



__END__
    #<<<TODO: need an interface to managing this cache to allow
    #         for efficient cache update (successful changeset)
    #         and consistent cache rollback

    #<<<TODO: need to get a list of active changesets ahead of this one
    #<<<TODO: need a cache of defined symbols in "the world" in /bbs/lib
    #  We don't want entries in "the world" against which we check for duplicate
    #  symbols to get pushed out of the cache; might need a second cache
    #  Should we use 'findit' for now?  (remember findit works on regexes)
    #  findit :<symbol>\$
    #    and grep out libs in changeset
    #    exit value of 1 means symbol does not exist in findit database
    #    exit value of 0 means it DOES EXIST
    #    (and better only be in changeset libs)
    #    (Don't forget to check against new symbols in changesets ahead of this:
    #      ==> scan new symbols files)
    #    (but we can't catch what is in-flight through old checkin, unless 
    #	  we hook prls_release to call cscheckin to create changeset of
    #     released files, but then we would not want the changeset insertion
    #	  to fail, or we would want it to fail differently)
    #<<<TODO: need a cache of undefined symbols in "the world" in /bbs/lib
    #  (can use 'scant' for now to query if others are using removed symbols)
    #  scant -rxt -b -pl -n <function>
    #    (and check for output; rv == 0)
    #    (skip first line of output and grep -v libraries in changeset)
    #    (but also need to check if libraries in stage areas are using symbol
    #      for now, document limitation; we don't track
    #	   "new undefined symbols resolved by dependencies"; too expensive)
    #	 also grep through added.symbols for changesets ahead
    #	   (not perfect because someone can add and then remove in two
    #       consecutive changesets)
    #<<<TODO: offline applications and functions (f_* libs) are exempt from
    #	 added/removed symbol checks

    # cache with a long lifetime for running within a daemon
    # (RFE: only cache things in a certain path, i.e. not in home dirs)

## If we are parsing requests serially, clean up caches
## If we are forking for each request and then processing (after loading
## milieu), then we are ok, but make sure that when top level cs data libs
## change that we update in the parent.

## symbolvalidate.pl and Binary::Symbols::Scanner operate on globals.
## While that can be changed, right now we work on globals.
## If we want to check the size of variables, we should modify cscompile to
## do this, or we could modify Scanner.pm to have custom nm command lines
## for each platform so that we can obtain size information.  However,
## we do not want to slow down symbol validation with non-globals, and we
## would need to check all variable sizes, static and global.  Therefore,
## such a can be done on coarsely by checking bss size in cscompile, or 
## by running nm on the new *.o files to get variable sizes.



## IFF daemon validation is successful, internal daemon cache is updated with
## symbols from new libraries.  Calling program is responsible for physically
## moving libs into top-level changeset lib.$OStag.

## TODO:
## - write a client program that contacts the daemon users call the client,
## and so we encapsulate the protocol between client and server
##
## - Be sure to support rollback
## rollback will update timestamp on libraries and so they need
## to be detected as out of date.  Write a routine to check lib
## timestamps.  Store daemon startup timestamp (time that libs
## were last loaded, and compare to modification time on libs



## GPS: skip symbol validate on offline dirs?

## GPS: especially for legacy/phantoms, try to order these last in list
##	when producing dependency information

## GPS: will need to run multiple daemons; one for EMOV, one for regular,
##	otherwise, milieu will be out of date.  Otherwise, need to make
##	milieu support multiple staging areas.

## GPS: need to add documentation for --lookup and --refresh

## GPS: revisit areas that use basename() or similar and make sure
##	we will work with UORs containing '/'
##	We don't support versioned libraries
##	  or anything that will cause us to have multiply defined symbols
