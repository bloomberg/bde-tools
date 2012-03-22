#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use IO::Handle ();

use Binary::Aggregate;
use Binary::Archive;
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::FileSystem;
use Build::Option::Factory;
use Build::Option::Finder;

use BDE::Util::Nomenclature qw(isGroup isPackage isIsolatedPackage
			       isLegacy isThirdParty);
use BDE::Util::DependencyCache qw(getGroupDependencies getPackageDependencies
				  getCachedGroupOrIsolatedPackage);

use BDE::Build::Invocation qw($FS);

use Change::Symbols qw[ CS_DIR ];

use Symbols qw[
    EXIT_FAILURE EXIT_SUCCESS DEFAULT_FILESYSTEM_ROOT
];

use Util::File::Basename qw(dirname basename);
use Util::Message qw(
    alert verbose verbose2 verbose_alert get_verbose debug fatal warning
);

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

Any library whose symbols are listed in C<_BAD_SYMBOLS> must be listed in
C<_BAD_LIBS>.  This allows the library to be listed in the C<.dep> file --
so that it can still be built -- but tells this tool that the library
should be excluded from the list of valid library dependencies.

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

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-w <dir>] [-X] [-s] [-C] [-B]
                              [-l<lib> ...] [-L<libpath> ...]
                              [-o<object> ...] [-S <[lib:]symbol> ...]
                              <object|library> ...
  --csid          | -C                 registered change set id
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

  Search extension options for component-based libraries:

  --compiler      | -c <comp>          compiler name (default: 'def')
  --target        | -t <ufid>          build target <target>
                                       (default: 'dbg_exc_mt')
  --uplid         | -u <uplid>         target platform (default: from host)
  --where         | -w <dir>           specify explicit alternate root

See 'perldoc $prog' for more information.

_USAGE_END
}

# This distinction may or may not be necessary for this tool
#  --units       | -u <units>         retrieve symbols for the specified comma-
#                                     separated list of groups/packages only

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (@ARGV && GetOptions(\%opts, qw[
	csid|C=s
        compiler|c=s
        debug|d+
        defined|D!
	nodl|M!
        nodp|P!
	nobadmeta|B!
        help|h
        libraries|library|l=s@
        libpath|L=s@
        match|m=s
        objects|o=s@
        owner|O=s
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

    # set up filesystem
    my $finder=new Build::Option::Finder($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($finder);
    my $factory=new Build::Option::Factory($finder);

    # set UPLID
    if ($opts->{uplid}) {
	fatal "--uplid and --compiler are mutually exclusive"
	  if $opts->{compiler};
	$opts->{uplid} = BDE::Build::Uplid->unexpanded($opts->{uplid});
    } elsif ($opts->{compiler}) {
	$opts->{uplid} = BDE::Build::Uplid->new({ compiler=>$opts->{compiler},
						  where   =>$opts->{where}
						});
    } else {
	$opts->{uplid} = BDE::Build::Uplid->new({ where   =>$opts->{where} });
    }
    my $uplid=$opts->{uplid};
    fatal "Bad uplid: $opts->{uplid}" unless defined $uplid;

    # set UFID
    $opts->{target} = "dbg_exc_mt" unless $opts->{target};
    my $ufid=new BDE::Build::Ufid($opts->{target});
    fatal "Bad ufid: $opts->{target}" unless defined $ufid;

    # default library paths
    $opts->{libpath}=[] unless defined $opts->{libpath};
    @{$opts->{libpath}}=map { split /,/ } @{$opts->{libpath}};
    unless ($opts->{nodp}) {

	# default location of BB libraries
	push @{$opts->{libpath}}, "/bbs/lib";

	#<<<TODO: defaults for AIX, Linux, Darwin
	#<<<TODO: migrate to an options file (UPLID+UFID) somewhere?
        SWITCH: foreach ($^O) {
	    /^(solaris|SunOS)/ and do {
		push @{$opts->{libpath}}, "/opt/SUNWspro8/lib", "/usr/ccs/lib";
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
	push @{$opts->{core_libs}},
	     qw(pure_stubs demangle openbsd-compat
		l y m z dl rt mqiz sys pthread);
      SWITCH: foreach ($^O) {
	    /^(solaris|SunOS)/ and do {
		@{$opts->{deflibs}}=qw(c Crun Cstd);
		push @{$opts->{core_libs}},
		     qw(nsl socket xnet posix4
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
	    #<<<TODO: default libraries:use Base::Architecture OR default.opts
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
    my @extensions=$opts->{static} ? qw(.a .so) : qw(.so .a);
    my $extsize=$#extensions;
    foreach (@extensions[0..$extsize]) {
	push @extensions, ".${ufid}$_"; #search for ufid-extended libs
    }
    push @extensions, ""; #allow for fully qualified names too

    my @paths=@{$opts->{libpath}};
    if ($opts->{csid}) {
	usage(), exit EXIT_FAILURE if (@ARGV == 0);
	unshift @paths, CS_DIR.$FS."lib.".$^O;
	unshift @paths, CS_DIR.$FS.$opts->{csid}.$FS."lib.".$^O;
    }
    verbose "searching locations: @paths";
    verbose "searching extensions: @extensions";

    #<<<TODO: encapsulate this information into an object
    find_library_cache_init(\@paths,\@extensions);
    return($finder,$factory,$uplid,$ufid,\@paths);
}

#------------------------------------------------------------------------------

sub is_metadata_only ($$) {
    my($finder,$library)=@_;
    my $pkg = new BDE::Package($finder->getPackageLocation($library))
      if isIsolatedPackage($library);
    return $pkg && $pkg->isMetadataOnly() && !$pkg->isPrebuilt();
}

#<<<TODO: find_library and get_library_path should be methods on an object
#	  encapsulating all of this

sub get_library_path ($$$) {
    my($lib,$finder,$uplid) = @_;

    # check multi-rooted path if the library resembles a UOR
    if (isIsolatedPackage($lib) or isGroup($lib)) {
	# it *might* be a legacy lib, package group, or 'a_' package:
	# add to search path (it might also just happen to look like one
	# but is really just a regular system library).
	my $locn=isPackage($lib) ? $finder->getPackageRoot($lib)
				 : $finder->getGroupRoot($lib);
	$locn.=$FS."lib".$FS.$uplid;
	return find_library($lib,[$locn]);
    }
    else {
	return find_library($lib);
    }
}

#----

{ 
    my %found          = ();
    my $def_paths      = [];
    my $def_extensions = [];

    sub find_library_cache_init ($;$) {
	my($paths_init,$extensions_init) = @_;
	$def_paths      = $paths_init      if $paths_init;
	$def_extensions = $extensions_init if $extensions_init;
        %found          = ();
    }

    sub fatal_library_not_found ($;$) {
	my($lib,$paths)=@_;
	$paths = $paths ? [@$paths,@$def_paths] : $def_paths;
	fatal("Unable to locate library for $lib in ".join(":",@$paths));
    }

    sub find_library ($;$$) {
	my ($library,$paths,$extensions)=@_;
	my $lib = substr($library,rindex($library,'/')+1); # basename
		#<<<TODO: use BDE::Util::DependencyCache::getLinkName()

	return $found{$library} if (exists $found{$library});

	$paths = $paths ? [@$paths,@$def_paths] : $def_paths;
	$extensions ||= $def_extensions;

	foreach my $path (@$paths) {
	    foreach my $ext (@$extensions) {
		my $pathname=$path.'/lib'.$lib.$ext;
		debug("looking for $pathname...");
		if (-f $pathname) {
		    $found{$library} = $pathname;
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
		    $found{$library} = $pathname;
		    return $pathname;
		}
	    }
	}

	return undef;
    }
}

#----

{
    my %loaded;

    sub load_library ($$$) {
	my ($library,$pathname,$aggregate)=@_;
	if (!exists $loaded{$library}) {
	    my $ok=$aggregate->addArchiveFile($pathname);
	    fatal("Unable to add $pathname") unless $ok;
	    verbose("loaded $library from $pathname");
	    $loaded{$library} = 1;
	}
	return $aggregate;
    }
}

#----

{
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
    #<<<TODO: offlines applications are exempt from added/removed symbol checks

    # cache with a long lifetime for running within a daemon
    # (RFE: only cache things in a certain path, i.e. not in home dirs)

    my %defined_cache;

    sub load_library_defines ($$$) {
	my($library,$pathname,$defined_symbols)=@_;
	my($def,$k,$v);
	my $entry = $defined_cache{$library};
	if (defined($entry) && $entry->[0] eq $pathname) {
	    my $mtime = (stat($pathname))[9];
	    $def = $entry->[2] if ($entry->[1] > $mtime);
	}
	if (!defined($def)) {
	    $def = {};
	    my $time = time();
	    (new Binary::Symbol::Scanner)->scan_for_defined($pathname, $def);
	    verbose("loaded $library from $pathname");
	    $defined_cache{$library} = [$pathname, $time, $def];
	}
	keys(%$defined_symbols) =  # (preallocate more hash buckets)
	  (scalar keys %$defined_symbols) + (scalar keys %$def);
	while (($k,$v) = each %$def) {
	    $defined_symbols->{$k} = $v;  # shallow copy
	}
    }
}

#----

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

sub load_from_meta ($$$$;$$) {
    my($uor,$aggregate,$options,$paths,$dep_defined_symbols,$bad_libs) = @_;
    $bad_libs ||= {};

    my $addtl_libs=" ".$options->expandValue(uc($uor)."_OTHER_LIBS");
    my @meta_paths = ();
    while ($addtl_libs =~ /\s-L(?:\s+)?([^\s]+)/g) {
	unshift @meta_paths,$1;
    }
    ## XXX: should this be a local (temporary) addition, or global?
    ## ==> should be global; currently is not
    ##     (should also be unique, else lots of -lm -lm -lm -lm ...)
    ## (technically should build this up through all deps before loading
    ##  any libraries, so that full path is employed by all library searches)
    ## (and so that find_library_cache_init() can be initialized properly)
    #unshift @$paths,@meta_paths;
    push @meta_paths, @$paths;

    $addtl_libs = " ".$options->expandValue(uc($uor)."_SYSTEM_LIBS")
		. $addtl_libs;

    while ($addtl_libs =~ /\s-l(?:\s+)?([^\s]+)/g) {
	# skip libraries that are bad dependencies --
	# such libs must have bad symbols listed in _BAD_SYMBOLS
	next if ($bad_libs->{$1});
	if (my $pathname=find_library($1, \@meta_paths)) {
	    load_library_defines($1, $pathname, $dep_defined_symbols);
	    ## (load_from_meta() is only called on things added to dependency
	    ##  aggregate; we always want to remove undefined symbols from it)
	} else {
	    fatal("Unable to locate library for $1 in ".
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

# filter out undefined symbols that are defined in the
# list of symbols derived from _BAD_SYMBOLS and -S
#<<<TODO: there might be some inaccuracies where the object is "unknown"
#         in one or both of the lists
sub filter_bad_symbols ($$$) {
    my($undefinedsymbols,$symlist,$warn_missing)=@_;
    my $filtered=0;

    my($badlib,$badobj,$sym,$got,$ref,%unknown);
    foreach my $symbol (@$symlist) {

	$got = '';
	if ($symbol =~ /^[^[]+\[([^\]]+)\]:([^:]+)$/
	    || $symbol =~ /^[^:]+?:([^:]+?):([^:]+)$/
	    || $symbol =~ /^([^:]+?):([^:].*)$/ && $1 ne "unknown") {
	    ##$badobj=$1; $sym=$2;
	    if (exists $$undefinedsymbols{$2}
		&& ($got = delete $$undefinedsymbols{$2}{refs}{$1})) {
		delete $$undefinedsymbols{$2}
		  unless (scalar keys %{$$undefinedsymbols{$2}{refs}});
	    }
	    elsif (exists $$undefinedsymbols{'.'.$2}
		   && ($got = delete $$undefinedsymbols{'.'.$2}{refs}{$1})) {
		delete $$undefinedsymbols{'.'.$2}
		  unless (scalar keys %{$$undefinedsymbols{'.'.$2}{refs}});
	    }
	    elsif ($^O eq 'aix') {
		# (these tests are less accurate on AIX, where nm on XCOFF
		#  does not provide object name of symbols located in archive)
		($got = delete $$undefinedsymbols{$2}{refs}{unknown})
		|| ($got = delete $$undefinedsymbols{'.'.$2}{refs}{unknown})
		  ? ($unknown{$2} = $got)
		  : ($got = $unknown{$2});
		delete $$undefinedsymbols{$2}
		  unless (scalar keys %{$$undefinedsymbols{$2}{refs}});
		delete $$undefinedsymbols{'.'.$2}
		  unless (scalar keys %{$$undefinedsymbols{'.'.$2}{refs}});
	    }
        } else {
	    ##$sym=$symbol;
	    $got = delete $$undefinedsymbols{$symbol};
	}

	if ($got) {
	    $filtered++;
	}
	else {
	    alert "Ignored symbol is no longer present: $symbol"
	      if ($warn_missing && $symbol ne "plink_timestamp___");
	}
    }

    return $filtered;
}

# Filter out undefined symbols that are defined in the dependency list.
# If -D was specified, list out the symbols that were resolved.
sub filter_defined_symbols ($$$) {
    my($opts,$undefinedsymbols,$definedsymbols)=@_;
    my $defined_by_deps = 0;

    # The list of defined symbols in the dependency aggregate could be
    # very, very large.  Iterate over the undefined symbols instead and
    # see if they are defined by dependencies.  Walk the hash twice
    # (if reporting) because it is a no-no to delete entries from a hash
    # while iterating over it.


    if ($opts->{defined}) {  ## report defined symbols
	my %libs = (map { $_ => 1 } @{$opts->{libraries}});
	if ($opts->{deflibs}) {
	    delete $libs{$_} foreach (@{$opts->{deflibs}});
	}
	delete $libs{$opts->{owner}} if ($opts->{owner});
	my $match = scalar keys %libs
	  ? join('|', map {quotemeta($_)} keys %libs)
	  : '';
	my $regex = qr/^lib(?:$match)[.-]/ if $match;
	my $terse  = $opts->{terse};
	my($symname,$symbol,$defined);

	while (($symname,$symbol) = each %$undefinedsymbols) {

	    next unless (($defined = $definedsymbols->{$symname}));
	    if (!$match || $defined->getArchive() =~ $regex) {
		verbose_alert "defined:" unless ($defined_by_deps++);
		foreach (values %{$symbol->{refs}}) {
		    print STDERR "  ",$_->getLongName(),
			  ($terse?'':" provided by ".$defined->getLongName()),
			  "\n";
		}
	    }
	}
    }

    $defined_by_deps = 0;
    foreach (keys %$undefinedsymbols) {
	next unless $definedsymbols->{$_};
	delete $undefinedsymbols->{$_};
	$defined_by_deps++;
    }

    return $defined_by_deps;
}

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
}

#----

sub report_symbols ($$$) {
    my ($title,$symbols,$match)=@_;
    $match = qr/$match/ if $match;

    verbose_alert $title if ($title && scalar keys %$symbols);

    my($symbol,@longnames);
    foreach my $hash (values %$symbols) {
	foreach (values %{$hash->{refs}}) {
	    $symbol = $_->getLongName();
	    next if (defined($match) && $symbol !~ $match);
	    push @longnames,$symbol;
	}
    }
    print STDERR "  $_\n" foreach (sort @longnames);
}

#==============================================================================

MAIN: {
    my $opts=getoptions();
    my($finder,$factory,$uplid,$ufid,$paths) = parse_options($opts);

    my $dep_defined_symbols = {};
    my $aggregate=new Binary::Aggregate("symbol validation");

    #---- Create the aggregate of 'dependency' symbols

    foreach my $lib (@{$opts->{libraries}}) {

	# (should not occur; user provided owner library twice, -O and -l)
	# (harmless to load here; just skipped as an optimization.
	#  we do not check for this in load_from_meta)
	#<<<TODO: should check that {owner} not loaded in load_from_meta()
	#	  or at least not loaded into dependency $aggregate)
	next if ($opts->{owner} && $lib eq $opts->{owner});

	next if is_metadata_only($finder,$lib);
	my $pathname = get_library_path($lib,$finder,$uplid)
	  || fatal_library_not_found($lib);

	if (@ARGV) {		# load library defined symbols only
	    load_library_defines($lib, $pathname, $dep_defined_symbols);
	}
	else {			# load library and its additionally defined libs
	    load_library($lib, $pathname, $aggregate);
	    next unless (isIsolatedPackage($lib) or isGroup($lib));
	    my $options=$factory->construct({
		what => $lib, ufid => $ufid, uplid => $uplid
	    });
	    load_from_meta($lib,$aggregate,$options,$paths);
	}
    }

    # load any explicitly requested objects
    foreach my $pathname (@{$opts->{objects}}) {
	load_object($aggregate => $pathname, $dep_defined_symbols);
    }

    verbose((@ARGV ? "dependency " : "untargetted ").
      "aggregate: @{[ $aggregate->getObjects() ]}") if (get_verbose);

    #---- Analyse symbols

    my($definedsymbols,$undefinedsymbols,$options);

    if (@ARGV) {
	# targeted mode - resolve symbols in supplied arguments using
	# the objects and binaries specified to -l and -o

	#---- Create the aggregate of 'target' symbols

	my $binaries=new Binary::Aggregate();

	# If a library for orphaned objects is specified,
	# add it to the list of entities to search for.
	my $owner=undef;
	if ($opts->{owner}) {
	    #<<<TODO: this should probably be hasMetadata()
	    if (isLegacy($opts->{owner})) {
		my $locn = $finder->getPackageLocation($opts->{owner});
		if (! -d $locn.$FS."package"
		    && ! -d $locn.$FS."group"){#(group check prob not necessary)
		    debug("$$opts{owner} does not have metadata configured; "
			 ."skipping symbol validation");
		    exit EXIT_SUCCESS;
		}
	    }
	    # owner library special-cased below; must be -first- in @ARGV
	    unshift @ARGV, $opts->{owner};
	}

	foreach my $item (@ARGV) {
	    # we accept either explicit objects or a UOR library as the
	    # target, not a system or generic anonymous library.
	    if (isIsolatedPackage($item) or isGroup($item)) {

		my $options=$factory->construct({
		    what => $item, ufid => $ufid, uplid => $uplid
		});

		# seek out 'waived' symbols and add them to symbol list
		my $bad_symbols = $options->expandValue("_BAD_SYMBOLS")
		  unless $opts->{nobadmeta};
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
		    }
		    if (get_verbose) {
			verbose2 "added ".scalar(@symbols)
				." symbol waivers for $item: @symbols";
		    }
		    push @{$opts->{symbols}}, @symbols;
		}

		my $pathname = get_library_path($item,$finder,$uplid);
		if (!$opts->{owner} || $item ne $opts->{owner}) {
		    $pathname
		      ? load_library($item, $pathname, $binaries)
		      : is_metadata_only($finder,$item)
			|| fatal_library_not_found($item);
		}
		else {
		    # owner library might not exist if it is new.
		    # metadata must still exist prior to first object checkin,
		    # even though new library does not exist yet. 
		    if ($pathname) {
			load_library($item, $pathname, $binaries);
			$owner = $binaries->getObject(basename $pathname);
		    }
		    else {
			$owner = new Binary::Archive();
			$owner->setName($opts->{owner});
		    }
		    $binaries->addObject($owner);
		}

		## do not load any dependent libraries if performing a
		## targetted check of lib versus libs listed on command line
		next if ($opts->{defined} && scalar @{$opts->{libraries}});

		my $obj = getCachedGroupOrIsolatedPackage($item);
		my $bad_libs = $options->expandValue("_BAD_LIBS") || '';
		my %bad_libs = map { $_ => 1 }  split(' ',$bad_libs),
						$obj->getWeakDependants();

		# load direct dependencies into dependency aggregate
		my @listed_deps = isGroup($item)
		  ? getGroupDependencies $item
		  : getPackageDependencies $item;
		foreach my $d (@listed_deps) {
		    # skip libraries that are bad dependencies --
		    # such libs must have bad symbols listed in _BAD_SYMBOLS
		    next if ($bad_libs{$d});
		    my $depname = get_library_path($d,$finder,$uplid);
		    if ($depname) {
			load_library_defines($d,$depname,$dep_defined_symbols);
		    } elsif (!is_metadata_only($finder,$d)) {
			##<<<TODO: FIXME why is this happening?
			next unless (defined $d);
			warning("Unable to locate dependency $d for $item");
			fatal_library_not_found($d);
		    }

		    ## ThirdParty might be marked metadata-only and define
		    ## its library location(s) in the .defs file, so process
		    ## metadata for third-party.
		    if (isThirdParty($d)) {
			my $doptions=$factory->construct({
			    what => $d, ufid => $ufid, uplid => $uplid
			});
			load_from_meta($d,$aggregate,$doptions,$paths,
				       $dep_defined_symbols,\%bad_libs);
		    }
		}

		load_from_meta($item,$aggregate,$options,$paths,
			       $dep_defined_symbols,\%bad_libs)
		  unless $opts->{nodl};

		if (get_verbose) {
		    verbose "extended dependency aggregate: "
			   ."@{[ $aggregate->getObjects() ]}";
		}
	    } else {
		# it's an explicit object
		if ($owner) {
		    # Remove the naked object from the owning library archive
		    $owner->removeObject($item) if ($owner->getObject($item));

		    # $owner is part of the target aggregate to be checked.
		    # It is a sparse archive of only those objects listed
		    # naked on the command line.  Add this naked object to
		    # the archive, which is part of the target aggregate.
		    load_object($owner => $item); #known origin
		} else {
		    load_object($binaries => $item); #indeterminate origin
		}
	    }
	}

	if (get_verbose) {
	    verbose "target aggregate: @{[ $binaries->getObjects() ]}";
	    # for informational purposes only
	    $definedsymbols = $binaries->getDefinedSymbols();
	    verbose scalar(keys %$definedsymbols)." symbols defined in target";
	}

	#---- Find undefined symbols in 'target' not defined in 'dependencies'


	$undefinedsymbols = $binaries->getUndefinedSymbols();
	macro_kludge($undefinedsymbols);
	verbose scalar(keys %$undefinedsymbols)." symbols undefined in target";

	if (scalar keys %$undefinedsymbols) {
	    $definedsymbols = $aggregate->getDefinedSymbols();
	    my $warn_missing = !(@{$opts->{libraries}} > @{$opts->{deflibs}});
	    my $ignored=filter_bad_symbols($undefinedsymbols,$opts->{symbols},
					   $warn_missing);
	    verbose "$ignored ignored symbols";

	    my $defined=
	      filter_defined_symbols($opts,$undefinedsymbols,
				     $dep_defined_symbols);
	    verbose "$defined symbols defined by dependencies";
	}

	# load target aggregate of libraries from stage (without new objects)
	# and determine which symbols have been added and which ones removed
	if ($opts->{csid} && !(scalar keys %$undefinedsymbols)) {
	    # remove change_set local lib location from path
	    my $cspath = shift @$paths;
	    if ($cspath ne CS_DIR.$FS.$opts->{csid}.$FS."lib.$^O") {
		fatal("$cspath not equivalent to expected path: ".
		      CS_DIR.$FS.$opts->{csid}.$FS."lib.$^O");
	    }

	    # clear library load caches to allow reload of libraries
	    # from diff location
	    find_library_cache_init($paths);

	    my $base_defined_symbols = {};

	    foreach my $lib (@ARGV) {
		next if is_metadata_only($finder,$lib);
		my $pathname = get_library_path($lib,$finder,$uplid)
		  || fatal_library_not_found($lib);
		load_library_defines($lib, $pathname, $base_defined_symbols);
	    }

	    my @added   = ();
	    my @removed = ();
	    my $cs_defined_symbols = $binaries->getDefinedSymbols();
	    foreach (keys %$cs_defined_symbols) {
		push @added, $_ unless (exists $$base_defined_symbols{$_});
	    }
	    foreach (keys %$base_defined_symbols) {
		push @removed, $_ unless (exists $$cs_defined_symbols{$_});
	    }

	    # write out files of new symbols added and old symbols removed
	    my $FH = new IO::Handle;
	    if (@added) {
		if (open($FH,">$cspath/symbols.added")) {
		    print $FH join("\n", @added);
		    close $FH;
		}
		else {
		    fatal("open $cspath/symbols.added: $!");
		}
	    }
	    if (@removed) {
		if (open($FH,">$cspath/symbols.removed")) {
		    print $FH join("\n", @removed);
		    close $FH;
		}
		else {
		    fatal("open $cspath/symbols.removed: $!"); 
		}
	    }

#<<<TODO: process added symbols against list of deprecated symbols
#	  --> will need to provide a bypass mechanism so that top level
#	      managers can say "allow it" and robocop can bypass this check
#<<<TODO: test this code; COMPLETELY UNTESTED; abstract to subroutine
	    if (@added) {
		##NOTE: can get around this restriction by checking in code as
		##	part of the changeset that already has the deprecated
		##	symbol defined in it.
		## RFE:	when printing out deprecated symbols, give additional
		##	info where the symbols came from, if not in terse mode
		## RFE:	check that deprecated symbol is still defined in the
		##	library that declared it deprecated; that way, when it
		##	is finally removed, it should be removed from the
		##	deprecated symbols list; but what about versioning?
		my %deprecated_symbols;
		foreach my $lib ($binaries->getObjects(),
				 $aggregate->getObjects()) {
		    next unless (isIsolatedPackage($lib) or isGroup($lib));
		    my $options=$factory->construct({
			what => $lib, ufid => $ufid, uplid => $uplid
		    });
		    my $deprecated_symbols =
		      $options->expandValue("_DEPRECATED_SYMBOLS");
		    if ($deprecated_symbols) {
			#<<<TODO: to support demangled C++ symbols, the format
			#of _DEPRECATED_SYMBOLS will need to change since symbol
			#might contain spaces
			foreach (split /(?:\s+|,)/s,$deprecated_symbols) {
			    # skip symbols that begin with '#'
			    # (note that '#' must immediately precede symbol
			    #  no spaces inbetween '#' and symbol)
			    $deprecated_symbols{$_} = 1
			      unless (substr($_,0,1) eq "#");
			}
		    }
		}
		# (might reverse logic above by creating a hash of @added and
		#  looking each deprecated symbol up in list of @added symbols
		#  as deprecated symbols are parsed
		my @deprecated;
		foreach (@added) {
		    push @deprecated,$_ if $deprecated_symbols{$_};
		}
		if (@deprecated) {
		    alert "No new usage of deprecated symbols is allowed";
		    print STDERR "  $_\n" foreach (sort @deprecated);
		    exit(EXIT_FAILURE);
		}
	    }

#<<<TODO: process added/removed symbols against rest of world
#	  (specifically include other changesets, too!)
## (offline applications do not get added/removed symbols validated)

#<<<TODO: rerun symbolvalidate.pl on EACH library if multiple libraries
#	  are in the change set (@ARGV > 1)
#	  (if reinvoking symbolvalidate.pl, don't pass the csid)






	}
    } else {
	#---- Untargeted: Find all undefined symbols in 'dependency' aggregate

	if (get_verbose) {
	    # for informational purposes only
	    $definedsymbols=$aggregate->getDefinedSymbols();
	    verbose scalar(keys %$definedsymbols)." defined symbols";
	}

	$undefinedsymbols=$aggregate->getUndefinedSymbols();
	macro_kludge($undefinedsymbols);
	my $ignored=filter_bad_symbols($undefinedsymbols,$opts->{symbols},1);
	verbose "$ignored ignored symbols" if $ignored;
    }

    #---- Display results

    if ($opts->{defined} and not @ARGV) {
	# (untargeted mode; in targetted mode, see filter_defined_symbols())
	$definedsymbols=$aggregate->getDefinedSymbols() unless $definedsymbols;
	report_symbols "defined:", $definedsymbols, $opts->{match};

	# only report defined symbols if defined report is requested
	verbose_alert scalar(keys %$definedsymbols)." defined symbols".(
            $opts->{match} ? " matching $opts->{match}" : ""
        );
    }

    if ($opts->{undefined}) {
	report_symbols "undefined:", $undefinedsymbols, $opts->{match};
    }

    # always report undefined symbols even if no undefined report
    verbose_alert scalar(keys %$undefinedsymbols)." undefined symbols".(
        $opts->{match} ? " matching $opts->{match}" : ""
    )." after resolution";

    #---- Exit

    # exit status = one (1) if undefined symbols (zero (0) = none = success);
    exit(scalar(keys %$undefinedsymbols) ? EXIT_FAILURE : EXIT_SUCCESS);
}

#==============================================================================

=head1 TODO

This program has been tested on Solaris and AIX.

C++ symbols are not fully supported but will be in a future release.
The primary target of this program is legacy Fortan and C, not legacy
C++ (and new C++, of course, should comply with the 30 Rules)

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net),
Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<bde_verify.pl>, L<bde_symverify.pl>, L<bde_stub.pl>

=cut
