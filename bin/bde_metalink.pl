#!/bbs/opt/bin/perl -w
use strict;

use Symbol ();
use Getopt::Long ();
use File::Copy ();
use IPC::Open3 ();

use FindBin;
use lib "$FindBin::Bin/../lib/perl";
use Util::Filesystem qw(get_nfstmpdir make_visible_on_nfs);

use constant METALINK_BULLETIN =>
  "/bbsrc/bin/cstools/conf/prod/metalink.bulletin";

use constant EXE_GMAKE => "/opt/swt/gmake-3.81/bin/gmake";
use constant EXE_PLINK => "/bb/bin/plink";
use constant EXE_SYMBOL_ORACLE => "/bbsrc/bin/prod/bin/symbol_oracle.pl";

# (bypass /bbsrc/bin/bbarch; each architecture needs special support)
use constant BB_ARCHCODE =>
  $^O eq "solaris" ? "sundev1" : $^O eq "aix" ? "ibm" : "";
my $archcode = BB_ARCHCODE; # (for easy use within strings)

# (support for "call-graph" tools written by Norbert Lis and Joel Silverstein)
# A call graph is generated while the target is linked.
# These LD_OPTIONS will work for either a 32-bit or 64-bit linker.
use constant CGTOOLS => "/bbsrc/internal/isystest/cgtools";
use constant CGTOOLS_LD_OPTIONS =>
  " -zld32=-S".CGTOOLS."/ld-cgtool/ld-cgtool32.so.1".
  " -zld64=-S".CGTOOLS."/ld-cgtool/ld-cgtool64.so.1";
use constant EXE_CGTREE => CGTOOLS."/cgtree/cgtree.".BB_ARCHCODE;

#==============================================================================

=head1 NAME

metalink - link task with hints from metadata

=head1 SYNOPSIS

  $ metalink [-v] [-d] [-h] [-f <mbig.mk>]
	   [-j <num jobs>|--jobs=<num jobs>]
	   [--clean | --realclean]
	   [--offline] [--nononbigdummy] [--nosocheck]
	   [--buildtag=<source|local|prod|stage>]
	   [--ignorelibs=<lib>[,<lib>,...]] [--noaddlib]
	   [--nokick|--nokickstart] [--nolink] [--nomkmod]
	   [--ftncmns] [--cgdum]
	   [--linkordummy]

    metalink --buildtag=source      links against /bbs/lib libraries
    metalink --offline -f mytsk.mk  allows offline-only libraries in link
    metalink --jobs=4               compile objs in parallel (default 4)
    metalink --clean                cleans up object files in build dir
    metalink --realclean            remove all *.metalink backups b/4 link
    metalink --ignorelibs=tst,test  dummy out calls into listed libraries
                                    (use with caution)
    metalink --nokick               skip kick-start link line analysis
    metalink --noaddlib             dummy calls to libs not already listed
    metalink --nolink               update .mk file, but do not link task
    metalink --nomkmod              update dums, refs, etc, but not .mk
    metalink --ftncmns              add ftncmns support to .mk (!default)
    metalink --nononbigdummy        do not add nonbigdummy for offlines
    metalink --nosocheck            skip .so tests for undefines/mult defs
    metalink --cgdum                generate dummy file from call graph
    metalink --linkordummy          do plink and dummy any (non-C++) undefs
    metalink --so_bregacclib        /bbsrc/regobj/bregacclib.$archcode.so
                                    (prerelease lib changes every 10 mins)

    metalink --plink_opts="..."     extra args to pass to plink
                                    equivalent to env var PLINK_OPTS
 
    metalink --clean --buildtag=source -f my_mbig.mk
                                    clean up object files
                                    link against /bbs/lib
                                    use "my_mbig.mk" .mk file
Development process:
    a) metalink
    c) test task
    b) edit code
    c) repeat

=head1 DESCRIPTION

This tool performs makes a best effort to produce a link line to link an mbig
in one pass.  It is aimed at the single pass (default) Solaris linker mode.

If -f <mbig.mk> argument is omitted, metalink assumes that the .mk file is
named after the current directory, or else if there is exactly one .mk file
in the current directory, that .mk will be used.  If you do not have a .mk
file, please use Bloomberg's automake program to create a Bloomberg .mk file
before running metalink.

metalink modifies your .mk file (after backing it up).  Among other things,
_dum.metalink.c and maybe _refs.metalink.c are added to OBJS in the .mk file.
These files are managed by metalink.  _incs.metalink.f is also created.
If autoplink produced your _dum.c and _refs.c files, it is suggested that
you clear both of them, or at least the _refs.c file.  You may also consider
these your "permanent" dum and refs.

After running metalink, a successful result is a working mbig.
To speed up subsequent links, consider renaming your <mbig>_dum.metalink.c
file to <mbig>_dum.c.  This will treat those dummies as "permanent".
metalink will happily regenerate the _dum.metalink.c file for you each time
you run it, so if you run into conflicts with multiply-defined symbols in your
_dum.c file and an object from a library, then wipe out your _dum.c file and
then run metalink again.

A number of switches are available to have metalink perform part of the
process, allow manual modification, and then continue.  If you metalink with
--nolink, you may then metalink with --linkordummy to perform a plink and
then dummy any (non-C++) that remains unresolved (due to the linker pulling
in Fortran commons from this place or that).

While metalink is processing, if plink aborts for various reasons, there
temporary .mk file <mbig>.metalink.mk will remain for visual inspection
and possible manual modification.  Performing plink <mbig>.metalink.mk
is perfectly valid when troubleshooting to generate a working .mk file.

Hint: If you are compiling to test code for an EMOV, you *must* compile
with metalink --buildtag=stage, or else you will be building and testing
against the wrong set of libraries.

Hint: After you get a working task, you might consider adding the contents
of <mbig>_dum.metalink.c to <mbig>_dum.c to permanently dummy these symbols.
In future metalinks, it is more likely that metalink will run in a single
pass rather than taking any extra pass to dummy out the same symbols.

=head1 BUILDING A REAL BIG

It is fairly straightforward to build a Big the same way that robocop builds.
Here is an example how to build an ssebig (one of the "less-large" Bigs)
  mkdir /bb/mbig/mbig0000/ssebig
  cd /bb/mbig/mbig0000/ssebig
  cp /bbsrc/big/ssebig.mk .
  vi ssebig.mk
     VPATH=/bbsrc/big   (add at top of .mk file)
     TSKDIR=./          (replace TSKDIR=/bb/task/)
  plink ssebig.mk

You can also use metalink on the .mk file:
  metalink -f ssebig.mk

For an alpha build:
  metalink --linkordummy -f ssebig.mk

=head1 LIMITATIONS

metalink works only on Solaris.
metalink always generates kick-start link line based on libs in /bbs/lib
  (but passes --buildtag argument through to plink for actual link)
- metalink does not dummy out unresolved C++ symbols, considered a fatal error.
  If you want to dummy out C++ symbols (**NOT RECOMMENDED**), then you
  can temporarily set the following in your .mk file, metalink on Solaris,
  and then remove this from your .mk file.
    USER_LDFLAGS= -filt=no%names

This is not the end-all be-all of .mk file parsers.  It aims to work on the
typical Bloomberg .mk file, where macros for INCLIBS, OBJS, SOBJS, NOCOMPOBJS,
OLDOBJS, etc are defined "MACRO=" and not anything more compicated, such as
"MACRO+=".  This tool *will not* dein to support every possible .mk file
syntax.  For example, metalink does not expand macros within macros, so if
you hide things in a nested macro, then metalink will not see those things.
This is usually not a problem unless those items are specifically what
metalink is looking for when metalink is modifying the .mk file.

To reiterate: INCLIBS, OBJS, SOBJS, NOCOMPOBJS should be defined *simply* --
as in INCLIBS=... OBJS=... SOBJS=... NOCOMPOBJS=...  No other gmake syntactic
sugar should be used.  If you would like to override these values, you may 
include an override file such as -include local.mk at the end of the .mk file,
but before plink.newlink.  metalink will not see these values, but then again,
your production .mk file should be simple, and the local.mk overrides should be
for testing only.  Another alternative is to add something like $(LOCAL_OBJS)
to OBJS and to use gmake rules to modify LOCAL_OBJS.

metalink entirely replaces INCLIBS with only those libraries you really need.
If you would like to supplement the list of libraries for any reason, then
you should modify LIBS instead of INCLIBS.

Compatibility with autoplink:
metalink .mk files are mostly compatible with autoplink.  However, after
running metalink, you must run automake before running autoplink.
metalink does not support "Makefile" or "makefile" because plink requires .mk.
metalink does not co or ci a .mk,v.  You should do that after testing the link.

=head1 TROUBLESHOOTING

If you are having trouble linking an mbig, you might try commenting out all of
the plink macros in your .mk file, leaving only 
  IS_BIG=yes  (for mbigs)
  IS_BDE=yes
  IS_CPPMAIN=yes
  IS_PTHREAD=yes
  IS_EXCEPTION=yes

(Technically, only IS_BIG=yes is needed for mbigs.)

The link line produced generally works on AIX, but you might need to add
a few C++ libraries at the end of the link line to complete the link.
It is relatively straightforward to look at the mangled symbols and guess
which libraries are missing if the C++ libraries are written according to
BP C++ At Bloomberg rules.

When linking offlines, objects from /bbsrc/big/*.o are not added to OLDOBJS.
If your offline needs to include objects from /bbsrc/big, then they should be
specified explicitly in your .mk file in OLDOBJS or NOCOMPOBJS.  However,
nonbigdummy.o is added (if not already present) to offline .mk files.
Use --offline --nononbigdummy to skip adding nonbigdummy.o to the .mk file.

Manually maintaining dummy files is a (black) art and is an iterative process.
If you maintain your own dummy file instead of, or in addition to, the dummy
file created by metalink, you might end up with multiple-defines between your
_dum.c file and code in a library.  (This usually ends up happening because of
the Fortran common problem in BB libraries.)  Your options are to remove the
symbol from your dummy file (in which case metalink will give you a larger
task), or you can dummy out whatever is calling into the object that is
resulting in the multiply-defined.  There are a number of ways to figure this
out, but it would take too long to explain here how to do it and how to verify
whether you really do need a given symbol or not.

When linking against objects that contain proposed changes to the Big libraries,
it is possible to get multiply-defined errors between your objects and those
objects you intend to replace in the libraries.  Again, this is sometimes due
to the Fortran common problem in BB libraries.  The most robust way to guard
against this is to create your own candidate libraries by copying the existing
libraries you are modifying, 'ar'ing your candidate objects into the libraries,
and then linking against those candidate libraries.  You can set
  LIBS_PRE=-L/path/to/my/candidate/libs
in your .mk file to prepend your candidate library location(s) to the plink
library search path.  A more riskly alternative to creating candidate libraries
is to dummy out the function (.text) symbols that are in the old object you
are replacing, but are not in the new object with which you are replacing it.
If you do this, be sure that your candidate changes are replacing all existing 
calls to the functions you dummy because you are removing those functions.

=cut

#==============================================================================

sub usage(;$) {
    my $prog = "metalink";

    print <<_USAGE_END;

metalink - link task with hints from metadata

Usage: metalink [-v] [-d] [-h] [-f <mbig.mk>]
		[-j <num jobs>|--jobs=<num jobs>]
		[--clean] [--realclean]
		[--offline] [--nononbigdummy] [--nosocheck]
		[--buildtag=<source|local|prod|stage>]
		[--ignorelibs=<lib>[,<lib>,...]] [--noaddlib]
		[--nokick|--nokickstart] [--nolink] [--nomkmod]
		[--ftncmns] [--cgdum]
		[--linkordummy]

    metalink --buildtag=source      links against /bbs/lib libraries
    metalink --offline -f mytsk.mk  allows offline-only libraries in link
    metalink --jobs=4               compile objs in parallel (default 4)
    metalink --clean                cleans up object files in build dir
    metalink --realclean            remove all *.metalink backups b/4 link
    metalink --ignorelibs=tst,test  dummy out calls into listed libraries
                                    (use with caution)
    metalink --nokick               skip kick-start link line analysis
    metalink --noaddlib             dummy out calls into any libraries added
    metalink --nolink               update .mk file, but do not link task
    metalink --nomkmod              update dums, refs, etc, but not .mk
    metalink --ftncmns              add ftncmns support to .mk (not default)
    metalink --nononbigdummy        do not add nonbigdummy for offlines
    metalink --nosocheck            skip .so tests for undefines/mult defines
    metalink --cgdum                generate dummy file from call graph
    metalink --linkordummy          do plink and dummy any (non-C++) undefines
    metalink --so_bregacclib        use /bbsrc/regobj/bregacclib.$archcode.so
                                    (note: prerelease lib changes every 10 mins)

    metalink --plink_opts="..."     extra args to pass to plink
                                    equivalent to env var PLINK_OPTS
 
    metalink --clean --buildtag=source -f mbig.mk
                                    rebuild dum/refs
                                    link against /bbs/lib
                                    use "mbig.mk"
Development process:
    a) metalink
    c) test task
    b) edit code
    c) repeat

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

use Sys::Hostname ();
use Cwd ();

use constant INVOCATION_LOG => "/bb/csdata/logs/usage/metalink.log";

{
    my $host= Sys::Hostname::hostname();
    my $pwd = Cwd::getcwd();
    my $user= getpwuid($<);
    my $pid = $$;
    my $i   = 0;

    sub ident (;$) {
	my($sec,$min,$hour,$mday,$mon,$year)=localtime($_[0]||time());
	return sprintf("%d%02d%02d-%02d:%02d:%02d %s %s(%d):%s [%02d] ",
	    $year+1900,$mon+1,$mday,$hour,$min,$sec,$user,$host,$pid,$pwd,$i++);
    }

    my $LOGFH = Symbol::gensym;
    open($LOGFH,">>",INVOCATION_LOG)
      ? (print $LOGFH ident($^T),"$0 @ARGV\n")
      : ($LOGFH = undef);

    sub logevent (@) {
	print $LOGFH ident(),"@_\n" if $LOGFH;
    }

    sub get_metalink_nfstmpdir ($) {
	return ($_[0]->{'nfstmpdir'} ||=
		get_nfstmpdir("metalink/$user.$host.$pid.$^T"));
    }

    sub set_mk_pwd () {
	$pwd = Cwd::getcwd();
    }

    sub get_mk_pwd () {
	return $pwd;
    }

}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (Getopt::Long::GetOptions(\%opts, qw[
        debug|d+
        help|h
        verbose|v+
	mkfile|f=s
	jobs|j=i
	clean
	realclean
	offline
	buildtag|tag|stage=s
	ignorelibs=s
        port=s
        host=s
	keepdums|keepdum
	linkordummy
	kickstart|kick!
	link!
	link_remotely
	addlibs!
	mkmod!
	ftncmns!
	nonbigdummy!
	socheck!
	plink_opts=s
	callgraph
	cgdum
	so_bregacclib!
    ])) {
        usage();
        exit 1;
    }

    # help
    usage(), exit 0 if $opts{help};


    ## Display metalink bulletin (if present)
    if (-f METALINK_BULLETIN && -s _ > 0) {
	my $FH = Symbol::gensym;
	open($FH,"<",METALINK_BULLETIN) && print STDERR "\n",<$FH>;
	sleep 5;
    }


    $^O eq "solaris"
      || die "Please run on a Solaris box\n";

    ##<<<TODO: should we override the PATH?  probably a good idea, although
    ## most (all?) commands are called with absolute paths (or should be)
    ## (If we do set path, should we include /bb/bin or /usr/local/bin?)
    #$ENV{PATH}=
    #  "/bb/bin:".
    #  "/usr/bin:/usr/sbin:/usr/ccs/bin:/opt/SUNWspro/bin:".
    #  "/usr/local/bin";

    $ENV{TMPDIR} ||= "/bb/data/tmp";  ## choose local disk for TMPDIR
    $ENV{LANG} = "C";  ## ensure consistent messages from vendor tools

    # pass through extra arguments to plink
    $ENV{PLINK_OPTS} = ($ENV{PLINK_OPTS}||"")." ".$opts{plink_opts}
      if $opts{plink_opts};

    # default to executing 4 gmake jobs in parallel unless specified otherwise
    $opts{jobs} = (($ENV{PLINK_OPTS}||"") =~ /(?:\s|^)-jobs\s+(\d+)\b/) ? $1 : 4
      unless ($opts{jobs});
    if ($opts{jobs} > 10) {
	##<<<TODO: should log excessive usage such as this
	warn("\n60 second penalty!\n",
	     "Specifying so many jobs ($opts{jobs}) hogs resources!\n\n");
	$opts{jobs} = 10;
	sleep 60;
    }

    # disable plink remote builds unless already set (not sure if in use at all)
    #$ENV{PLINK_GRIDENABLE} = "no" unless exists $ENV{PLINK_GRIDENABLE};

    # set flag to use platform-specific plink lock file unless already set
    $ENV{PLINK_PARALLEL_BUILD} = "yes" unless exists $ENV{PLINK_PARALLEL_BUILD};

    # set plink verbosity
    $ENV{PLINK_VERBOSE} = "yes" if ($opts{verbose}||0) > 1;

    # choice of shell affects .o compile speed and varies by platform
    $ENV{SHELL} = $^O eq "solaris"
		    ? "/usr/bin/ksh"
		    : $^O eq "aix"
			? "/usr/bin/bash"
			: "/usr/bin/bash";

    # debug mode
    $opts{debug} ||= 0;
    #Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    #Util::Message::set_verbose($opts{verbose} || 0);

    if ($opts{linkordummy}) {
	foreach my $opt (qw(ignorelibs keepdums kickstart link addlibs mkmod
			    ftncmns nonbigdummy callgraph cgdum)) {
	    next unless exists $opts{$opt};
	    warn("\nMost metalink-specific options are ignored when running\n",
		 "  metalink --linkordummy\n\n");
	    sleep 3;
	    last;
	}
    }

    # default to perform kick-start link line analysis
    $opts{kickstart} = 1
      unless (defined($opts{kickstart}) || $opts{linkordummy});

    # default to perform task link
    $opts{link} = 1 unless defined($opts{link});

    # default to perform mbig .so sanity checks
    $opts{socheck} = 1 unless defined($opts{socheck});

    # default to add needed libraries
    $opts{addlibs} = 1 unless defined($opts{addlibs});

    # default to modify the .mk file
    $opts{mkmod} = 1 unless defined($opts{mkmod});

    # default to NOT add ftncmns support to .mk file
    #<<<TODO: this default may flip when ftncmns is fully released
    $opts{ftncmns} = 0 unless defined($opts{ftncmns});

    # call graph and call graph dummy generation supported only on Solaris
    $opts{callgraph} = 1 if $opts{cgdum};  # (need call graph to generate dums)
    if ($^O ne "solaris") {
	$opts{callgraph} = 0 if $opts{callgraph};
	$opts{cgdum}     = 0 if $opts{cgdum};
	# (if defined to 0, we might enable if we remote from AIX to Solaris)
    }

    # check for .mk file
    # If no -f mbig.mk provided, and first arg exists that ends in .mk, use that
    # else assume .mk file is named after current directory if dir.mk exists,
    # else if single .mk file exists in the directory, use that
    $opts{mkfile} = shift @ARGV
      if (!$opts{mkfile} && @ARGV && $ARGV[0] =~ /\.mk$/);
    unless ($opts{mkfile}) {
	if (@ARGV) {
	    usage();
	    die "** Did you mean to specify the .mk file?\n",
		"**   metalink -f $ARGV[0]\n\n";
	}
	my $dir = Cwd::getcwd();
	$opts{mkfile} = substr($dir,rindex($dir,'/')+1).".mk";
	unless (-f $opts{mkfile}) {
	    my @mkfiles = grep !/\.metalink\.mk$/, <*.mk>;
	    @mkfiles == 1
	      ? ($opts{mkfile} = $mkfiles[0])
	      : (usage(), die "** unclear .mk; please specify -f <mkfile>\n\n");
	}
    }

    # check that .mk file exists and is non-empty
    my $mkfile = $opts{mkfile};
    -f $mkfile && -s _
      || (usage(), die "** invalid .mk file or does not exist ($mkfile)\n\n");

    # change dir to that containing .mk file
    my $dir = ".";
    if (index($mkfile,'/') >= 0) {
	$dir = substr($mkfile,0,rindex($mkfile,'/'));
	chdir $dir
	  || die "Failed to chdir $dir: ($!)\n";
	set_mk_pwd();
	$mkfile = substr($mkfile,length($dir)+1);
    }
    -w $dir
      || die "Unable to write to ",
	     ($dir ne "." ? $dir : "current directory"),"\n";

    if (scalar @ARGV) {
	while (scalar @ARGV) {
	    if ($ARGV[0] eq "clean") {
		$opts{clean} = 1;
		shift @ARGV;
	    }
	    elsif ($ARGV[0] eq "realclean") {
		$opts{realclean} = 1;
		shift @ARGV;
	    }
	    else {
		##<<<TODO: if we should support other targets, how to handle?
		print STDERR "\nWARNING: metalink does not support specific ",
			     "targets\n  (@ARGV)\nIgnoring...\n\n";
		sleep 5;
		last;
	    }
	}
    }

    # Not sure why this is needed, but apparently it is needed for mbigs
    # (Shubha mentioned this might be needed by procmgr)
    # DRQS 7231961
    symlink("/bb/bin/ibig.fil", "ibig.fil") unless (-e 'ibig.fil');

    metalink_preprocess_mkfile(\%opts,$mkfile);

    # default to add nonbigdummy.o for offlines
    # (check should follow metalink_preprocess_mkfile())
    $opts{nonbigdummy} = $opts{offline}||0 unless defined($opts{nonbigdummy});

    # default to not add bregacclib.$archcode.so to mbigs
    # (do not add for offlines; we don't want them accidentally shipped to prod)
    $opts{so_bregacclib} = 0 if ($opts{offline});
    $opts{so_bregacclib} = 0 unless (defined $opts{so_bregacclib});

    if (($opts{buildtag} eq 'source' && (  -f "/bbsrc/big/makequicklibs.running"
					|| -f "/bbsrc/big/fridaymakes.running"
					|| -f "/bbsrc/big/mondaymakes.running"))
	|| ($opts{buildtag} eq 'stage'&&-f "/bbsrc/big/makestagelibs.running")){
	warn("\n$opts{buildtag} libraries are being built right now.\n",
	     "Your link will LIKELY FAIL if you continue.\n",
	     "Press Ctrl-C to abort.  Then wait a bit and try again.\n");
	sleep 10;
    }

    return \%opts;
}

#------------------------------------------------------------------------------

# NOTE: works when variable is defined *once* in string
#	(does not work when variable is defined multiple times in string)
#	works only on straight macro defines ("foo="), not others ("foo+=")
#       (Same for mkvar_remove() and mkvar_uncomment() below)
sub mkvar_mod ($$;$$) {
    my($string,$var,$replace,$comment_out) = @_;
    my $search = "^([ \\t]*\\b".quotemeta($var)
		."[ \\t]*=)[ \\t]*((?:[^\\n]*?\\\\[ \\t\\r]*\\n)*[^\\n]*\\n)";
    my $value;
    if (defined($replace)) {
	$value = $2 if ($comment_out
			? $$string =~ s/$search/$1 $$replace\n#$1 $2/ms
			: $$string =~ s/$search/$1 $$replace\n/ms);
	## add to beginning of string unless replacement is successful
	substr($$string,0,0,"$var=$$replace\n") unless (defined($value));
    }
    else {
	(undef,$value) = $$string =~ /$search/ms;
    }
    chomp $value if $value;
    return defined($value) ? \$value : undef;
}
sub mkvar_remove ($$) {
    my($string,$var) = @_;
    my $search = "^[ \\t]*\\b".quotemeta($var)
		."[ \\t]*=[ \\t]*(?:[^\\n]*?\\\\[ \\t\\r]*\\n)*[^\\n]*\\n";
    return $$string =~ s/$search//ms;
}
sub mkvar_uncomment ($$) { # only uncomments beginning of line -- where we put #
    my($string,$var) = @_;
    my $search = "^#+(?=[ \\t]*\\b".quotemeta($var)."[ \\t]*=)";
    return $$string =~ s/$search//ms;
}

sub read_mk_contents ($) {
    my $mkfile = shift;
    my $mkcontents;
    my $FH = Symbol::gensym;
    open($FH,"<",$mkfile)
      || die "Failed to open $mkfile: $!\n";
    {
	local $/ = undef;
	$mkcontents = <$FH>;
    }
    close $FH;
    return \$mkcontents;
}

sub write_mk_contents ($$$) {
    my($origmk,$mkfile,$mkcontents) = @_;
    my $tmpfile = "$mkfile.$^T.$$.metalink";
    my $FH = Symbol::gensym;
    open($FH,'>',$tmpfile)
      || die "Unable to open $tmpfile: $!\n"; 
    print $FH $$mkcontents;
    close $FH
      || die "Error upon close of $tmpfile: ($?) $!\n"; 
    ##<<<TODO: is this needed?  does it have any effect?
    # preserve timestamp on .mk file to avoid unnecessary recompilations
    utime((stat $origmk)[8,9], $tmpfile);
    rename($tmpfile,$mkfile)
      || die "Error renaming $tmpfile to ",$mkfile,": $!\n"; 
}

sub get_automake_build_tag ($) {
    # (could do_plink() with $buildtag=undef and extract this info from gmake)
    my $mkfile = shift;
    my $mktag = $mkfile;
    $mktag =~ s/(?:\.metalink)?\.mk$//;

    return undef unless (-e "$mktag.deprules");
    my $FH = Symbol::gensym;
    open($FH,"<","$mktag.deprules")
      || die "open $mktag.deprules: $!\n";
    while (<$FH>) {
        return $1 if /^MK_BBSRC=(\S+)/;
    }
    return undef;
}

sub metalink_preprocess_mkfile ($$) {
    my($opts,$mkfile) = @_;
    my $mktag = $mkfile;
    $mktag =~ s/(?:\.metalink)?\.mk$//;

    my $automake_build_tag = get_automake_build_tag($mkfile);
    if ($automake_build_tag) {
	# check if user needs to re-run BB automake
	# (verify depend rules set up for proper buildtag (if MK_BBSRC is set))
	# (plink will complain if mismatch between this and -d <buildtag>)
	if ($opts->{buildtag}) {
	    if ($opts->{buildtag} ne $automake_build_tag) {
		die "\nPlease re-run automake -$$opts{buildtag} $mkfile ",
		    "before running metalink again\n\n";
	    }
	}
	elsif ($automake_build_tag ne "local") {
	    warn "\n$mkfile is configured to build tag (stage) ",
		 $automake_build_tag,"\n",
		 "Press Ctrl-C and run automake if this is not correct\n\n";
	    $opts->{buildtag} = $automake_build_tag;
	    sleep 3;
	}
    }
    $opts->{buildtag} ||= "local";

    my($rv,$output) = do_plink($opts,$mkfile,$opts->{buildtag},
			       {print_db=>1,question=>1});
    # (above uses gmake -q, so do not exit upon non-zero return value)
    # Note that db vars might contain other (unexpanded) vars in their values
    my(%gmake_db,$k,$v);
    my $vars = 0;
    foreach (split /\n+/,$$output) {
	$vars || ($vars = ($_ eq "# Variables"), next);
	next if substr($_,0,1) eq "#";
	last if $_ eq "# variable set hash-table stats:";
	next unless index($_,'=') > 0;
	($k,$v) = split / :?= /,$_,2;
	$gmake_db{$k} = $v;
    }

    ## default to offline-mode unless IS_BIG is specified in the .mk file
    ## (most .mk files should contain one of IS_BIG, IS_TMGR, or IS_PEKLUDGE)
    ## (robocop .mk files define IS_BIG_ROBO=yes)
    unless ($opts->{offline}
	    || $gmake_db{IS_BIG}
	    || $gmake_db{IS_BIG_ROBO}
	    || $gmake_db{IS_WGTAPP}) {
	$opts->{offline} = 1;
	if ($opts->{kickstart}) {#(--offline affects libs visible to kick-start)
	    warn("\nDefaulting to metalink --offline (IS_BIG not detected)\n");
	    sleep 1;
	}
    }
    $opts->{so_bregacclib} = 0
      if (($gmake_db{IS_BIG_ROBO} || $gmake_db{IS_WGTAPP})
	  && !defined($opts->{so_bregacclib}));

    my $task = $gmake_db{TASK} || $mktag;
    substr($task,-4,4,'') if (substr($task,rindex($task,'.')) eq ".tsk");
    substr($task,0,9,'')  if (substr($task,0,9) eq '$(TSKDIR)'); # eww FIXME
    $task = substr($task,rindex($task,'/')+1); # basename
    my $sname = $gmake_db{SNAME} || $task;
    substr($sname,-3,3,'') if (substr($sname,rindex($sname,'.')) eq ".so");

    ## (quick fix for 0-length executables; indicates ld interruption)
    ##<<<TODO: FIXME this does not take into account that the target
    ##         might not be in the same directory as the .mk file.
    my $archtask  = "$task.$archcode.tsk";
    -f $archtask  && (-s _ == 0) && unlink($archtask);
    my $archsname = "$sname.$archcode.so";
    -f $archsname && (-s _ == 0) && unlink($archsname);

    $opts->{archtask}     = $archtask;
    $opts->{archsname}    = $archsname;
    $opts->{nm_archsname} = ".nm.".$archsname;

    ## store metalink mkfile, dumfile, refsfile, and incsfile names
    ## store other useful tidbits from gmake database dump
    ## Note that the *.metalink.* files are specific to a .mk file and so are
    ## named based on the basename of the .mk file, not on TASK name variable.
    $opts->{dumfile}      = "${mktag}_dum.c";
    $opts->{refsfile}     = "${mktag}_refs.c";
    $opts->{metamkfile}   = "${mktag}.metalink.mk";
    $opts->{metadumfile}  = "${mktag}_dum.metalink.c";
    $opts->{metarefsfile} = "${mktag}_refs.metalink.c";
    $opts->{metaincsfile} = "${mktag}_incs.metalink.f";
    $opts->{metacgdumfile}= "${mktag}_cgdum.metalink.c";
    $opts->{metacgfile}   = "${mktag}.cg";
    $opts->{metacglibs}   = "${mktag}.libs";
    $opts->{task}         = $task;
    $opts->{sname}        = $sname;
    $opts->{VPATH}        = $gmake_db{VPATH}        || "";
    $opts->{ARCHSOBJS}    = $gmake_db{ARCHSOBJS}    || "";
    $opts->{LD_RUN_PATH}  = $gmake_db{LD_RUN_PATH}  || "";
    $opts->{PLINK_SOPATH} = $gmake_db{PLINK_SOPATH} || "";
    $opts->{INCLIBS}      = exists $gmake_db{INCLIBS}
			    ? $gmake_db{INCLIBS}
			    : $gmake_db{LIBS}       || "";

    if ($opts->{ARCHSOBJS} =~
	  /${mktag}_(?:dum|refs|cgdum)\.metalink\.$archcode\.o/) {
	warn("\nmetalink _dum.metalink.o and _refs.metalink.o\n",
	     "*do not* belong in SOBJS.  Please place in OBJS.\n\n");
	sleep 5;
    }
}

sub metalink_setup ($) {
    my $opts = shift;
    my $origmk = $opts->{mkfile};
    if ($origmk =~ /\.metalink\.mk$/) {
	usage();
	die "\n*** Do not pass .mk file ending in '.metalink.mk' ***\n";
    }

    ## cleanups (do before new backups)
    if ($opts->{realclean}) {
	my $callgraph = $opts->{metacgfile}; # (generated by call graph link)
	my $cglibs    = $opts->{metacglibs}; # (generated by call graph link)
	my $archsname = $opts->{archsname};
	my $nm = ".nm.".$archsname;
	unlink(<*.metalink*>,$nm,$callgraph,$cglibs);
    }

    ## read in .mk file contents
    my $mkcontents = read_mk_contents($origmk);

    ## check for link-time instrumentation
    ##<<<TODO: once libftncmns is made the default, revisit this, since
    ##         the link should then generally work on the first pass.
    my $dbg;
    if ((defined($dbg=mkvar_mod($mkcontents,"IS_PURIFY"))       &&$$dbg ne "")
	|| (defined($dbg=mkvar_mod($mkcontents,"IS_QUANTIFY"))  &&$$dbg ne "")
	|| (defined($dbg=mkvar_mod($mkcontents,"IS_PURECOV"))   &&$$dbg ne "")
	|| (defined($dbg=mkvar_mod($mkcontents,"IS_PURIFY_COV"))&&$$dbg ne "")
	|| (defined($dbg=mkvar_mod($mkcontents,"IS_INSURE"))    &&$$dbg ne "")){
	warn("\n",
	     "Please disable link-time instrumentation when running metalink.",
	     "\n  (IS_PURIFY IS_QUANTIFY IS_PURECOV IS_PURIFY_COV IS_INSURE)\n",
	     "Once you have a working link, delete the .tsk, re-enable the ",
	     "flags, and then\n  plink $origmk\n",
	     "Once you have a working instrumented task, you can ",
	     "recompile \nand instrument the .so by running ",
	     "'repurify' or 'requantify'\nThis will generally save you time.\n",
	     "Press Ctrl-C to abort, or wait 15 seconds to continue anyway.\n");
	die "\nCall graph tools require these be disabled.  Exiting\n\n"
	  if ($opts->{callgraph});
	sleep 15;
	$opts->{so_bregacclib} = 0;
    }

    ## attempt some clean-ups in .mk file
    my $obsolete_flags = "IS_ACE|IS_ASN|IS_JNI|IS_XERCES";
    $obsolete_flags .= "|IS_PFL" unless $opts->{offline};
    $$mkcontents =~ s/^(?=[ \t]*(?:$obsolete_flags)=)/#/gmo;
    $$mkcontents =~ s/\$\(RESCAN\)\s*//g;

    ## verify that LIBS contains $(INCLIBS)
    my $libs = mkvar_mod($mkcontents,"LIBS") || \(my $tmp_libs = "");;
    mkvar_mod($mkcontents,"LIBS",\('$(INCLIBS) '.$$libs))
      unless ($$libs =~ /\$\(INCLIBS\)/);

    ## (disabled optimization since it also disables user-customizations)
    # clear out LIBS; plink seems to duplicate all this by default
    #mkvar_mod($mkcontents,"LIBS",\'$(INCLIBS)');

    ## mbigs get /bbsrc/regobj/bregacclib.$archcode.so unless $is_big_robo
    ## offlines get /bbsrc/big/nonbigdummy.o
    ## (developers should NOT run metalink --offline for widget servers)
    my $nocompobjs = mkvar_mod($mkcontents,"NOCOMPOBJS") || \(my $nocomp = "");
    if ($opts->{offline}) {
	if ($opts->{nonbigdummy}) {
	    unless ($$nocompobjs ne ""
		    && (index($$nocompobjs,'$(NONBIGDUMMY)') >= 0
			|| index($$nocompobjs,"/bbsrc/big/nonbigdummy.o") >=0)){
		$$nocompobjs .= ' $(NONBIGDUMMY)';
		mkvar_mod($mkcontents,"NOCOMPOBJS",$nocompobjs);
	    }
	}
    }
    else {  ## (Big or widget app)
	## breg one-off (why do these seem to pop up in every script?)
	## Add breg candidate shared library to link lines of test mbigs
	## (add to NOCOMPOBJS so that .tsk does not have gmake dependency
	##  on it, but is nevertheless linked against it)
	my $so_bregacclib = '/bbsrc/regobj/bregacclib.$(ARCHCODE).so';
	my $add_linkpath = 1;
	if (index($$nocompobjs,$so_bregacclib) >= 0) {
	    unless ($opts->{so_bregacclib}) {
		$$nocompobjs =~ s%\s?\Q$so_bregacclib\E%%o;
		mkvar_mod($mkcontents,"NOCOMPOBJS",$nocompobjs);
		$add_linkpath = 0;
	    }
	}
	elsif ($opts->{so_bregacclib}) {
	    $$nocompobjs .= " $so_bregacclib";
	    mkvar_mod($mkcontents,"NOCOMPOBJS",$nocompobjs);
	}
	else {
	    $add_linkpath = 0;
	}
	## (technically this is only needed on AIX because of the flags that
	##  plink passes on AIX which results in not finding the bregacclib .so)
	if ($$mkcontents =~ m|^LINKPATH:=\$\(LINKPATH\):/bbsrc/regobj\n|m) {
	    $$mkcontents =~ s|^LINKPATH:=\$\(LINKPATH\):/bbsrc/regobj\n||m
	      unless $add_linkpath;
	}
	else {
	    $$mkcontents .= 'LINKPATH:=$(LINKPATH):/bbsrc/regobj'."\n"
	      if $add_linkpath;
	}
    }

    ## write out .mk file modifications
    write_mk_contents($origmk,$opts->{metamkfile},$mkcontents);

    ## [do not keep backups of metalink-specific refs and dum]

    ## dum file: verify dum file (if it exists) contains #include <blpdummy.h>
    my $dumfile = $opts->{metadumfile};
    if ($opts->{keepdums} && -e $dumfile) {
	my $FH = Symbol::gensym;
	open($FH,'+<',$dumfile)
	  || die "Unable to read/write $dumfile: ($!)\n";
	local $/ = undef;
	my $dummy_contents = <$FH>;
	unless ($dummy_contents =~ /^\s*#\s*include\s*<\s*blpdummy.h\s*>/) {
	    seek($FH,0,2);
	    print $FH "#include <blpdummy.h>\n",$dummy_contents;
	    truncate $FH,tell($FH);
	}
	close $FH;
    }

    ## make sure *.metalink.* files exist or create stubs
    ## (otherwise compilation of local objects will obviously fail)
    my $cgdumfile = $opts->{metacgdumfile};
    my $refsfile  = $opts->{metarefsfile};
    my $incsfile  = $opts->{metaincsfile};
    my $mkobjs = mkvar_mod($mkcontents,"OBJS") || \(my $tmp_objs = "");
    while ($$mkobjs =~ /\b(\S+\.metalink\.)o\b/g) {
	if ($1."c" eq $dumfile) {
	    create_dumfile($dumfile) unless (-e $dumfile);
	}
	elsif ($1."c" eq $cgdumfile) {
	    create_dumfile($cgdumfile) unless (-e $cgdumfile);
	}
	elsif ($1."c" eq $refsfile) {
	    next if -e $refsfile;
	    my $FH = Symbol::gensym;
	    open($FH,'>',$refsfile)
	      || die "Unable to write $refsfile: ($!)\n";
	    print $FH "static void xyzzy(void) { }\n";
	    close $FH;
	}
	elsif ($1."f" eq $incsfile) {
	    next if -e $incsfile;
	    my $incsroutine = $incsfile;
	    $incsroutine =~ s/\W/_/g;
	    my $FH = Symbol::gensym;
	    open($FH,'>',$incsfile)
	      || die "Unable to write $incsfile: ($!)\n";
	    print $FH "      SUBROUTINE $incsroutine\n",
		      "      RETURN\n",
		      "      END\n";
	    close $FH;
	}
    }
}

sub metalink_update_mk ($$$$) {
    my($opts,$mkfile,$inclibs,$datarefs) = @_;
    my $mkcontents = read_mk_contents($mkfile);
    my $mkobjs = mkvar_mod($mkcontents,"OBJS") || \(my $tmp = "");
    my $mkobjs_changed = 0;

    ## add $(FTNCMNS_LIBS) to beginning of INCLIBS link line
    ## (Note that LIBS_PRE and PLINK_LIBPATH will
    ##  still precede INCLIBS on the link line)
    if ($opts->{ftncmns}) {
	unless ($$mkcontents=~m|^\s*include /bbsrc/tools/data/libmacros.mk|m) {
	    mkvar_mod($mkcontents,"FTNCMNS_LIBS",
		      \' -L/bbsrc/sibuild/ftncmns -lftncmns.$(ARCHCODE)');
	}
	unless ($$inclibs =~ /^ \$\(FTNCMNS_LIBS\)\b/) {
	    substr($$inclibs,0,0," ") unless (substr($$inclibs,0,1) eq " ");
	    substr($$inclibs,0,0,' $(FTNCMNS_LIBS)');
	}
	unless ($$inclibs =~ / -lftncmns\.\$\(ARCHCODE\)$/) {
	    $$inclibs .= " -lftncmns.\$(ARCHCODE)";
	}
    }
    else {
	## else remove all instances -lftncmns from link line
	$$inclibs =~ s/ \$\(FTNCMNS_LIBS\)//g;
	$$inclibs =~ s/ -lftncmns\.\$\(ARCHCODE\)//g;
    }

    ## "offline" glib kludge
    ## remove bbglib from the link line if using "offline" glib
    my $gliboffline = mkvar_mod($mkcontents,"IS_GLIBOFFLINE")
      if $opts->{offline};
    if ($gliboffline && $$gliboffline ne "" && $$gliboffline !~ /^NO$/i) {
	$$inclibs =~ s/ -lgobject\b//g;
	$$inclibs =~ s/ -lbbglib\b//g;
    }

    ## add to OLDOBJS if needed
    ## Note: Anything added to OLDOBJS is not recompiled and is taken verbatim
    ##       Anything added to NOCOMPOBJS is not recompiled and has $(ARCHCODE)
    ##         added.   e.g. foo.$archcode.o instead of foo.o
    my $oldobjs = mkvar_mod($mkcontents,"OLDOBJS");
    $$oldobjs = "" unless defined($oldobjs);
    $$oldobjs.= $1 while ($$inclibs =~ /( \S+\.o)\b/g);
    if ($$oldobjs ne "") {
	$$inclibs =~ s/( \S+\.o)\b//g;
	mkvar_mod($mkcontents,"OLDOBJS",$oldobjs)
	  unless (getpwuid($>) eq "robocop");
	## robocop has permission to build these objects, so do not add to
	## OLDOBJS.  Additionally, robocop must manually add to the .mk file
	## the explicit list of objects robocop used to build the Bigs.
    }

    my $dumfile  = $opts->{metadumfile};
    my $refsfile = $opts->{metarefsfile};
    my $incsfile = $opts->{metaincsfile};
    ## add metalink-managed dum file to OBJS
    create_dumfile($dumfile) unless (-e $dumfile && $opts->{keepdums});
    my $dumobj = $dumfile;
    substr($dumobj,-1,1,'o'); # replace .c with .o
    unless ($$mkobjs =~ /\b\Q$dumobj\E/) {
	my $pdumobj = $opts->{dumfile};
	substr($pdumobj,-1,1,'o'); # replace .c with .o
	$$mkobjs =~ s/\b\Q$pdumobj\E/$pdumobj $dumobj/
	  || ($$mkobjs .= " ".$dumobj);
	$mkobjs_changed = 1;
    }
    ## add metalink-generated data refs to OBJS if data refs file exists
    my $refsobj = $refsfile;
    substr($refsobj,-1,1,'o'); # replace .c with .o
    if ($opts->{ftncmns}) {
	set_drefs($refsfile, map_ftncmns_data_to_fn($datarefs));
	if ($$mkobjs !~ /\b\Q$refsobj\E\b/) {
	    my $prefsobj = $opts->{refsfile};
	    substr($prefsobj,-1,1,'o'); # replace .c with .o
	    $$mkobjs =~ s/\b\Q$prefsobj\E\b/$prefsobj $refsobj/
	      || ($$mkobjs .= " $refsobj");
	    $mkobjs_changed = 1;
	}
    }
    else {
	## else remove drefs from OBJS
	## (write out drefs file, anyway, e.g. for use by cgtool)
	set_drefs($refsfile, $datarefs);
	$mkobjs_changed = 1 if $$mkobjs =~ s/\b\Q$refsobj\E\b//;
    }
    ## write out incs file
    ## (for testing purposes -- not yet automatically added to .mk file above)
    my $FH = Symbol::gensym;
    open( $FH,">",$incsfile) || die "open $incsfile: $!\n";
    print $FH @{ftncmns_incs($opts,$datarefs)};
    close $FH;

    ## replace OBJS
    mkvar_mod($mkcontents,"OBJS",$mkobjs) if $mkobjs_changed;

    ## replace INCLIBS
    ## (must be after objects are removed from INCLIBS and put in OLDOBJS)
    mkvar_mod($mkcontents,"INCLIBS",$inclibs);

    return $mkcontents;
}

sub metalink_get_added_libs ($$$) {
    my($opts,$inclibs,$addlibs) = @_;
    my(%prevlibs,%newlibs,%addedlibs,%removedlibs);
    $prevlibs{$1} = 1 while ($opts->{INCLIBS} =~ / -l(\S+)/gs);
    $newlibs{$1}  = 1 while ($$inclibs =~ / -l(\S+)/gs);
    foreach (keys %newlibs) {
	$addedlibs{$_} = 1 unless exists($prevlibs{$_});
    }
    foreach (keys %prevlibs) {
	$removedlibs{$_} = 1 unless exists($newlibs{$_});
    }
    ##<<<TODO: if !$addlibs, should we report libraries that might be needed?
    if ($opts->{verbose} && $addlibs) {
	if (scalar keys %addedlibs) {
	    print STDERR "metalink: added libraries to link line\n\n",
			 join("\n", sort keys %addedlibs),"\n\n";
	}
	if (scalar keys %removedlibs) {
	    print STDERR "metalink: removed libraries from link line\n\n",
			 join("\n", sort keys %removedlibs),"\n\n";
	}
    }
    return \%addedlibs;
}

sub metalink_commit ($$$) {
    my($opts,$metamkfile,$origmk) = @_;
    my($sec,$min,$hour,$mday,$mon,$year) = localtime($^T); $year+=1900; $mon++;
    my $tag = sprintf("%d%02d%02d-%02d%02d%02d-%d.metalink",
		      $year,$mon,$mday,$hour,$min,$sec,$$);
    if ($opts->{mkmod}) {
	File::Copy::copy($origmk,"$origmk.$tag")
	  || die "Unable to back up $origmk: $!\n";
	rename($metamkfile,$origmk)
	  || warn "rename $metamkfile to $origmk failed: $!\n";
    }
}

#------------------------------------------------------------------------------

sub is_remotable_link_line ($) {
    my $link_line = shift;
    ## check for a recognized linker
    return 0 unless
      $$link_line =~ #"/opt/SUNWspro8/bin/CC"
		     m%^/opt/SUNWspro8/bin/
		     #"/bb/util/version8/usr/vac/bin/cc"
		     |^/bb/util/version8/usr/vac/bin/%x;
    ## check for any -L rules that point to local disk
    my @local_ok = ("/usr/lib" => 1,
		    "/usr/ccs/lib" => 1,
		    "/opt/SUNWspro8/lib" => 1,
		    "/local/lib" => 1,
		    "/usr/local/lib" => 1);
    my $dir;
    my $mk_pwd = get_mk_pwd();
    while ($$link_line =~ /\s-L\s*(\S+)/g) {
	$dir = (substr($1,0,1) eq "/") ? $1 : $mk_pwd."/".$1;
	if (-d $dir     # (check for prefix match @local_ok)
	    && !(grep { substr($dir,0,length($_)) eq $_ } @local_ok)
	    && !is_file_on_nfs($dir)) {
	    warn("\nmetalink detected -L$dir libs on local disk; ",
		 "will not remote link\n\n");
	    return 0;
	}
    }
    return 1;
}

sub do_remote_link ($$) {
    my($opts,$link_line) = @_;
    my $linker = substr($$link_line,0,index($$link_line," "));

    ## metalink intentionally ignores link_wrap.newlink
    ## (skipping link_wrap.newlink breaks IS_64BIT;
    ##  instead, should add -L rule to 64-bit libs or translate w/ gmake rules)
    ## (IMNSHO, link_wrap.newlink and compile_wrap.newlink should be deprecated)

    ## place on the command line any env vars that affect the linker

    ## LD_RUN_PATH
    ## ??? set LD_RUN_PATH=/usr/lib:/lib:/bb/bin/so:/bb/bin:/bb/source/lib:. ???
    ## (assumes LD_RUN_PATH and PLINK_SO_PATH in gmake db are exported to env)
    my $ld_run_path  = $opts->{LD_RUN_PATH}  || $ENV{LD_RUN_PATH};
    my $plink_sopath = $opts->{PLINK_SOPATH} || $ENV{PLINK_SOPATH};
    $ld_run_path = $ld_run_path
      ? join(':',$plink_sopath,$ld_run_path)
      : $plink_sopath if $plink_sopath;
    ##<<<TODO: make this better
    if (index($linker,"/SUNWspro") > 0) {
	substr($$link_line,index($$link_line," "),0," -R$ld_run_path")
	  if $ld_run_path;
    }
    elsif (index($linker,"/vac") > 0) { # includes "/vacpp"
	$$link_line =~ s/-blibpath:(\S+)/-blibpath:$ld_run_path:$1/g 
	  if $ld_run_path;
    }
    else { # gcc
	substr($$link_line,index($$link_line," "),0," -R$ld_run_path")
	  if $ld_run_path;
    }

    ## specify -o $target with absolute path
    ## (not a perfect algorithm when "../" dirs are involved, but handles most)
    ## (with "../", assumes that target is on same volume)
    my($otarget) = $$link_line =~ /-o\s+(\S+)/;
    $otarget || return(-1,\(my $tmp_otarget = "no -o found in $$link_line"));
    my $dir = (substr($otarget,0,1) eq "/")
      ? substr($otarget,0,rindex($otarget,'/'))
      : get_mk_pwd();
    my $is_nfs_target = is_file_on_nfs($dir);
    unless ($is_nfs_target) {
	$dir = get_metalink_nfstmpdir($opts);
	unless (-d $dir) {
	    require File::Path;
	    File::Path::mkpath($dir);
	}
    }
    $$link_line =~ s%-o\s+(?:\S+/)?(\S+)%-o $dir/$1%
      || ((print STDERR "no -o found in $$link_line"),
	  return(-1,\(my $osub = "")));
    my $target = "$dir/$1";

    print STDOUT "\n",$$link_line,"\n";

## GPS: connect to remote machine and do link.  transfer back all output.
## GPS: For now, test with SSH and get_best_host.
##	  (should probably check if get_best_host returns current machine)
## GPS: replace with remote queue daemon
##
## Remotable link:
## Set safe TMPDIR and PATH, clear other env vars
## Verify on the server side that the command, when passed directly to execve()
## is likely to be sane.  Do linkers (compilers) support command line options
## for specifying optional programs to override parts of their behavior?  Yes.
## Must look to see if we can strip these out in is_remotable_link_line().
##
    my $PH = Symbol::gensym;
    #my $get_best_host = `/bb/shared/bin/get_best_host`;
    my $get_best_host = `/bb/shared/bin/get_best_host --ring LNKW-BLDO`;
    chomp $get_best_host;
    $? == 0 || return($?,\(my $tmp_get_best_host = "get_best_host failed"));
    print STDERR "\nRemoting link to machine $get_best_host\n\n"
      if $opts->{verbose};
    my @cmd = ("/usr/local/bin/ssh",$get_best_host,$$link_line);
    my $pid = IPC::Open3::open3(undef,$PH,$PH,@cmd);
    my $output = "";
    while (<$PH>) {
	$output .= $_;
	print $_;
    }
    close $PH;
    waitpid $pid, 0;
    my $rv = $?;
    if ($rv == 0 && !$is_nfs_target) {
	require File::Path;
	if ($opts->{callgraph}) {
	    my $pwd = get_mk_pwd();
	    my @cgdata = ($dir."/".$opts->{metacgfile},
			  $dir."/".$opts->{metacglibs});
	    foreach my $cg (@cgdata) {
		File::Copy::move($cg,$pwd) if -e $cg;
	    }
	}
	File::Copy::move($target,$otarget)
	  && File::Path::rmtree($dir);
    }
    return($rv,\$output);
}

sub do_plink ($$$$;$) {
    my($opts,$mkfile,$buildtag,$flags,$target) = @_;
    my($show_output,$compile_only,$print_cmds,$print_db,$question) =
      @{$flags}{"show_output","compile_only","print_cmds","print_db",
		"question"};
    my $jobs = defined $flags->{jobs} ? $flags->{jobs} : $opts->{jobs};
    $jobs = 1 if $print_cmds;

    my $gmake_opts =  "-l 25.0";  # arbitrarily-picked load avg limit for gmake
    $gmake_opts   .= " -j $jobs" if $jobs;
    $gmake_opts   .= " -n" if $print_cmds;
    $gmake_opts   .= " -p" if $print_db;
    $gmake_opts   .= " -q" if $question;
    $gmake_opts   .= " -d" if ($opts->{debug} > 3);  ## gmake debug info

    ## (if -noautoport option is removed from default, robocop still needs it)
    ## (probably should tell robocop to add -noautoport to PLINK_OPTS env var)
    my @plink_cmd = (EXE_PLINK,"-noautoport",
		     "-plink-gmake-path",EXE_GMAKE,
		     "-plink-gmake-opts",$gmake_opts,
		     $mkfile);
    splice @plink_cmd,1,0,"-d",$buildtag if $buildtag;
    push @plink_cmd, $target if defined($target);
    push @plink_cmd, "SHELL=$ENV{SHELL}"; # (for compile speed)
    ## (equivalent to passing -c to /bb/bin/plink, but safer without needing -e)
    ## (COMPILE_ONLY is used by linktask.newlink and other *.newlink scripts)
    push @plink_cmd, "COMPILE_ONLY=yes" if $compile_only;
    #splice(@plink_cmd, 1, 0, "-c") if $compile_only;

    my $PH = Symbol::gensym;
    my $pid = IPC::Open3::open3(undef,$PH,$PH,@plink_cmd);
    my $output = "";
    while (<$PH>) {
	$output .= $_;
	print $_ if $show_output;
    }
    close $PH;
    waitpid $pid, 0;
    my $rv = $?;
    $rv == 0 || $show_output || $question || print STDERR "\n",$output;
    return($rv,\$output);
}

sub compile_and_link_sobjs ($$$$) {
    my($opts,$mkfile,$buildtag,$verbose) = @_;
    return(0,\(my $tmp = "")) if ($opts->{ARCHSOBJS} eq "");  # no .so for .tsk
    my $archtask  = $opts->{archtask};
    my $archsname = $opts->{archsname};
    my($so_mtime,$re_chkpt) = so_checkpoint($archsname);
    ## (might prefer gmake -q $archsname, but linktask.newtask rules too noisy)
    my($rv,$output) = do_plink($opts,$mkfile,$buildtag,
			       {show_output=>$verbose},$archsname);
    $rv == 0 || return($rv,$output);
    my $built_so = -f $archsname ? (stat(_))[9] != $so_mtime : 0;
    if ($built_so) { ## ARCHSNAME .so was rebuilt
	print STDERR scalar localtime(time),"\n",
	  "metalink: ($mkfile) built $archsname\n\n";
	logevent("built $archsname");
    }
    return($rv,$output) unless (($built_so || $re_chkpt)
				&& $opts->{socheck} && -f $archtask);

    ## Check if static .tsk is already going to be relinked.
    ##<<<TODO: prefer 'gmake -q $archtask' once it works
    my($rv2,$output2) = do_plink($opts,$mkfile,$buildtag,{print_cmds => 1});
    $rv2 == 0 || exit_rv($rv2);
    return($rv,$output) if (defined get_link_line($output2));

    print STDERR scalar localtime(time),"\n",
      "metalink: ($mkfile) checking if $archtask\n",
      "metalink: ($mkfile) needs to be relinked\n",
      "metalink: ($mkfile) please be patient (1-2 mins)\n\n";

    ## Check if static task needs to be rebuilt
    my $PH = Symbol::gensym;
    if ($^O eq "solaris") {
	my $ldd_output = "";
	my @ldd_cmd = ("/usr/bin/ldd","-r",$archtask);
	print "\n@ldd_cmd\n\n" if $verbose;
	my $pid = IPC::Open3::open3(undef,$PH,$PH,@ldd_cmd);
	while (<$PH>) {
	    $ldd_output .= $_;
	    print $_ if $verbose;
	}
	close $PH;
	waitpid $pid, 0;
	if ($? != 0 || $ldd_output =~ /symbol not found/) {
	    unlink($archtask);
	    print STDERR "Warning: @ldd_cmd\n\n$ldd_output\n",
			 "Attempting to relink static task anyway\n"
	      if (!$verbose && $ldd_output !~ /symbol not found/);
	}
    }
    elsif ($^O eq "aix") {
	## simple check to see if task loads into debugger
	## (autoplink gives more debugging information if load fails)
	my $dbx_output = "";
	my $WR = Symbol::gensym;
	my @dbx_cmd = ("dbx",$archtask);
	print "\n@dbx_cmd\n\n" if $verbose;
	my $pid = IPC::Open3::open3($WR,$PH,$PH,@dbx_cmd);
	print $WR "quit\n";
	close $WR;
	while (<$PH>) {
	    $dbx_output .= $_;
	    print $_ if $verbose;
	}
	close $PH;
	waitpid $pid, 0;
	if ($? != 0) {
	    unlink($archtask)
	      if ($dbx_output !~ /warning.*cannot execute/);
	    ## (hope for the best if bringing up the .tsk in dbx fails)
	}
    }
    else {
	die "not implemented";
    }

    print "\n" if $verbose;
    return($rv,$output);
}

sub comment_out_dummies ($$) {
    my($opts,$dup_syms) = @_;
    my %dups = (map { $_ => undef } @$dup_syms);
    my $found_in_dumfile = 0;
    my $FH = Symbol::gensym;
    my $dumfile = $opts->{dumfile};
    my @dumfile;
    if (-f $dumfile && open($FH,"<",$dumfile)) {
	## (opened for read-only so that modification timestamp is not changed)
	while (<$FH>) {
	    substr($_,0,length($1)+3,"/* D($1) */"), $found_in_dumfile++
	      if (/^D\(([^\)]+)\)/ && exists $dups{$1});
	    push @dumfile,$_;
	}
	close $FH;
    }
    if ($found_in_dumfile) {
	## (modify dum file with duplicated dummy symbols commented-out)
	open($FH,">",$dumfile)
	  ? (print $FH @dumfile)
	  : warn("open $dumfile: $!\n");
    }

    $dumfile = $opts->{metadumfile};
    if (-f $dumfile && open($FH,"<",$dumfile)) {
	while (<$FH>) {
	    $found_in_dumfile++ if (/^D\(([^\)]+)\)/ && exists $dups{$1});
	}
	close $FH;
    }

    return $found_in_dumfile;
}

sub so_checkpoint ($) {
    my $archsname = shift;
    my $nm = ".nm.".$archsname;

    my($so_atime,$so_mtime) = -f $archsname ? (stat(_))[8,9] : (0,0);
    unlink($nm), return (0,0) unless $so_mtime;#(does not matter if it exists)

    my $nm_mtime = -f $nm && -s _ ? (stat(_))[9] : 0;
    return ($so_mtime,0) if ($so_mtime == $nm_mtime);#(match; assume file valid)

    my @nm_output;
    my $PH = Symbol::gensym;
    if ($^O eq "solaris") {
	return ($so_mtime,1)
	  unless (open($PH,'-|',"/usr/ccs/bin/nm","-gP",$archsname));
	@nm_output = grep !/^\$/, <$PH>;  # (skip debug symbols)
    }
    elsif ($^O eq "aix") {
	die "not implemented";
    }
    else {
	die "not implemented";
    }
    close $PH;
    return ($so_mtime,1) unless (@nm_output);

    open($PH,">",$nm) || return ($so_mtime,1);
    print $PH @nm_output;
    close $PH;
    utime($so_atime,$so_mtime,$nm);
    return ($so_mtime,1);
}

sub so_checks ($$) {
    my($opts,$mkfile) = @_;
    my $archtask  = $opts->{archtask};
    my $archsname = $opts->{archsname};
    return 1 unless ($opts->{socheck} && -f $archtask && -f $archsname);

    print STDERR scalar localtime(time),"\n",
      "metalink: ($mkfile) checking (use metalink --nosocheck to skip)\n",
      "metalink: ($mkfile) $archsname and $archtask\n",
      "metalink: ($mkfile) please be patient (1-3 mins)\n\n";
    logevent("performing .so and .tsk checks");

    my($rv,$output);
    my $PH = Symbol::gensym;
    if ($^O eq "solaris") {
	my %so_global_syms;
	if (open($PH,'-|',"/usr/ccs/bin/nm","-gP",$archsname)) {
	    while (<$PH>) {
		$so_global_syms{$1} = undef if /^((?!\$)\S*)\s+[ACDNT]\s/;
	    }
	}
	if (-M $archsname < -M $archtask) { ## (.so rebuilt after static .tsk)
	    my $nm = ".nm.".$archsname;
	    if (open($PH,"<",$nm)) {
		while (<$PH>) {
		    delete $so_global_syms{$1} if /^((?!\$)\S*)\s+[ACDNT]\s/;
		}
	    }
	    ## Trigger rebuild of static .tsk if there are *any* -new- duplicate
	    ## global symbols in .so because static .tsk will not know of them.
	    if (scalar keys %so_global_syms
		&& open($PH,"-|","/usr/ccs/bin/nm","-gP",$archtask)) {
		while (<$PH>) {
		    if (/^(\S+)\s+[ACDNT]\s/ && exists $so_global_syms{$1}) {
			print STDERR
			  "metalink ($mkfile): found in .so new global symbols",
			     " already in .tsk\n",
			  "metalink ($mkfile): removing $archtask\n\n";
			unlink($archtask);
			return 0;
		    }
		}
	    }
	}
	else {                              ## (static .tsk built with new .so)
	    delete @so_global_syms{qw(_fini _init)}; # do not report as dups
	    ## If there are duplicated symbols (other than COMMON .data syms),
	    ## then the symbol in the static .tsk will be used instead of the
	    ## symbol duplicated in the .so.
	    my @dup_syms;
	    if (open($PH,"-|","/usr/ccs/bin/nm","-gP",$archtask)) {
		while (<$PH>) {
		    push @dup_syms,$1
		      if (/^(\S+)\s+[ACNT]\s/ && exists $so_global_syms{$1});
		}
	    }
	    return 1 unless (scalar @dup_syms);

	    print STDERR
	      "metalink: ($mkfile) WARNING: found symbols duplicated between\n",
	      "metalink: ($mkfile) $archsname and $archtask\n";

	    if (comment_out_dummies($opts,\@dup_syms)) {
		print STDERR
		  "metalink: ($mkfile) symbol(s) removed from _dum.c file\n",
		  "metalink: ($mkfile) removing $archtask\n\n",
		unlink($archtask);
		return 0;
	    }
	    else {
		print STDERR
		  "metalink: ($mkfile) running your .tsk will use duplicated ",
		    "symbols\n",
		  "metalink: ($mkfile) from the .tsk and -not- from the .so:\n",
		  "  ",join("\n  ",sort @dup_syms),"\n\n";
	    }
	}
	return 1;
    }
    elsif ($^O eq "aix") {
	    ##<<<TODO: (logic borrowed from autoplink; implementing quickly)
	    ## (revisit for correctness and speed)
	    my $sh_archsname = $archsname;
	    $sh_archsname =~ s/'/'"'"'/g;
	    my $sh_archtask = $archtask;
	    $sh_archtask =~ s/'/'"'"'/g;
	    my $dump_cmd = "/usr/bin/dump -Tv '$sh_archsname' "
			  ."| /usr/bin/awk '/EXP/ && /SECdef/ { print \$8 }' "
			  ."| sort -u";
	    my %so_globals;
	    if (open($PH,'-|',$dump_cmd)) {
		$so_globals{$_} = undef while (<$PH>);
		close $PH;
	    }
# FIXME
#	    $dump_cmd = "/usr/ccs/bin/nm -p '$sh_archtask' "
#		      . "| /usr/bin/awk '/ [ATDCN] / { print \$3 }' | sort -u";
#        if [[ -s ${mapfile} ]]; then
#            $CSPLIT -f ${duptmp} ${mapfile} \
#                '/-------/' '/^RESOLVE:/' > /dev/null 2>&1;
#            if [[ -s ${duptmp}01 ]]; then
#                egrep -v "\*\*Duplicate\*\*|\{$so_name\}" ${duptmp}01 | \
#                ${AWK_TOOL} '{ print $1 }' | \
#                sed 's/^[ \.]*//g' | \
#                sort -u >| $autoplink_taskGlobals
#            fi
#        fi
	    my @dup_syms;
	    if (open($PH,'-|',$dump_cmd)) {
		while (<$PH>) {
		    push @dup_syms, $_ if (defined $so_globals{$_});
		}
		close $PH;
	    }
#
# INCOMPLETE
#
    }
    else {
	die "not implemented";
    }

    return 1;
}

sub compile_local_objects ($$$$) {
    my($opts,$mkfile,$buildtag,$verbose) = @_;
    return do_plink($opts,$mkfile,$buildtag,{ compile_only => 1,
					      show_output => $verbose });
}

## attempt to detect library includes from multiple different build tags
## (DRQS 7755169)
use constant LIB_LOCNS =>
  {
    "/bb/source/lib"		=> "source",
    "/bbs/lib"			=> "source",
    "/local/lib"		=> "local",
    "/bb/source/stage/stagelib"	=> "stage",
    "/bbs/stage/stagelib"	=> "stage",
    "/bb/source/stage/prodlib"	=> "prod",
    "/bbs/stage/prodlib"	=> "prod"
  };
my $lib_locns = join "|", "usr/local/lib", keys %{(LIB_LOCNS)};
## (approximations to avoid false positive with existing plink link line)
## (usr/local/lib is used to avoid "-L/usr/local/lib/gnuiconv" false positive)
my $lib_locns_re = qr%(?<!L|:)($lib_locns)(?!/libf77override.a)%o;
sub check_link_line_buildtags ($$) {
    my($link_line,$buildtag) = @_;
    my %conflicting_locns;
    while ($$link_line =~ /$lib_locns_re/go) {
	$conflicting_locns{$1} = undef
	  unless ($1 eq "usr/local/lib" || LIB_LOCNS->{$1} eq $buildtag);
    }
    if (scalar keys %conflicting_locns) {
	print STDERR 
	  "\nWARNING: detected paths that might conflict with build tag ",
	  "'$buildtag':\n  ", join("\n  ",sort keys %conflicting_locns),"\n",
	  "Did you mean to use \$(PLINK_LIBPATH) in your .mk instead of to ",
	  "hard-code the path?\n\n";
	sleep 5;
    }
}

sub check_link_line_redirection ($) {
    my $link_line = shift;
    if ($$link_line =~ /[\|\&><;]/) {
	print STDERR 
	  "\nWARNING: detected shell metacharacters in link line.\n",
	  "Output redirection will likely prevent metalink from working.\n",
	  "Please press Ctrl-C and remove redirection from your .mk file.\n\n";
	sleep 5;
    }
}

sub compile_and_link ($$$) {
    my($opts,$mkfile,$buildtag) = @_;
    my($rv,$output) = compile_local_objects($opts,$mkfile,$buildtag,1);
    $rv == 0 || return($rv,$output);
    ($rv,$output) = compile_and_link_sobjs($opts,$mkfile,$buildtag,1);
    $rv == 0 || return($rv,$output);
    ($rv,$output) = do_plink($opts,$mkfile,$buildtag,{print_cmds => 1});
    $rv == 0 || return($rv,$output);
    my $link_line = get_link_line($output)
      || ((print STDERR "Unable to parse link line from gmake -n.\n"),
	  return(-1,\(my $tmp = "")));

    check_link_line_buildtags($link_line,$buildtag);
    check_link_line_redirection($link_line);

    unless ($opts->{link_remotely} && is_remotable_link_line($link_line)) {
	my $env_ld_options = $ENV{LD_OPTIONS};
	$ENV{LD_OPTIONS} = (defined($env_ld_options) ? $env_ld_options : "")
			 . CGTOOLS_LD_OPTIONS if $opts->{callgraph};

	($rv,$output) = do_plink($opts,$mkfile,$buildtag,{show_output => 1});

	defined($env_ld_options)
	  ? ($ENV{LD_OPTIONS} = $env_ld_options)
	  : delete $ENV{LD_OPTIONS} if $opts->{callgraph};

	return($rv,$output);
    }

    $$link_line .= CGTOOLS_LD_OPTIONS if $opts->{callgraph};

    ## parse out commands gmake would run before and after the link command
    my $pre_link_line = get_pre_link_line($output);
    my $post_link_line = get_post_link_line($output);
    defined($pre_link_line) && defined($post_link_line)
      || ((print STDERR "Unable to parse link line from gmake -n.\n"),
	  return(-1,\(my $pre_post = "")));

    ## run any commands that gmake would have run prior to the link command
    ## (creates plink timestamp ephemeral object)
    if ($pre_link_line ne "") {
	system("/usr/bin/ksh","-c",$$pre_link_line);
	$? == 0 || return($?,\(my $ksh_pre = ""));
    }

    ## send link to remote machine
    ##<<<TODO: currently .so is built locally in compile_and_link_sobjs()
    ##         (but that could be remoted, too, if it proves useful)
    my $nfstmpdir = get_metalink_nfstmpdir($opts);
    ($rv,$output) = make_visible_on_nfs($link_line,$nfstmpdir);
    defined($rv)
      ? ($link_line = $output)
      : ((print STDERR $$output), return(-1,$output));

    ($rv,$output) = do_remote_link($opts,$link_line);
    $rv == 0 || return($rv,$output);

    ## run any commands that gmake would have run following the link command
    ## (e.g. echo "Done mbig123.sundev1.tsk")
    if ($post_link_line ne "") {
	system("/usr/bin/ksh","-c",$$post_link_line);
	$? == 0 || return($?,\(my $ksh_post = ""));
    }

    return($rv,$output);
}

## GPS: Fix these to not depend on presense of link_wrap.newlink
## GPS: should probably pull *evaluated* value of PLINK_LINK from gmake db
##	Might override PLINK_LINK to drop in searchable mark that we then omit
my $link_line_re = "^/bb/bin/link_wrap.newlink\\s+";

sub get_pre_link_line ($) {
    my $output = shift;
    my($pre_link_line) = $$output =~ m|\A(.*)$link_line_re|mos;
    return $pre_link_line ? \$pre_link_line : undef;
}

## This aims to return the command that gmake would execute to link the task.
## We will be able to call the C 'execve' with this command as long as it does
## not require shell expansion.  It currently does not.  (Should it need it
## in the future, the callers that are passing to 'execve' will need to have
## the shell expand the string without executing the command so that the caller
## can do things like remote to another machine to execute the command.)
sub get_link_line ($) {
    my $output = shift;
    my($link_line) = $$output =~ m|$link_line_re([^\n]+)$|mos;
    $link_line =~ s/(?<!\\)\\(?=\s)//g if $link_line;
    return $link_line ? \$link_line : undef;
}

sub get_post_link_line ($) {
    my $output = shift;
    my($post_link_line) = $$output =~ m|$link_line_re[^\n]+\s+(.*)\Z|mos;
    return $post_link_line ? \$post_link_line : undef;
}

sub get_plink_objects ($$) {
    my($opts,$output) = @_;
    my $link_line = get_link_line($output);
    $link_line
      || die $$output,"\n\nUnable to retrieve link line from above\n\n";
    ## grab anything explicit on the link line (included whole, not with -l)
    ## and filter derived objects (e.g. $(TASK)_plink_timestamp$(ARCHSFX))
    ## Also filter the 30+ MB bregacclib.$archcode.so so that a working link
    ## line is produced without using the .so (once bregacclib lib is built)
    my $keepdums  = $opts->{keepdums} || 0;
    my $task      = $opts->{task};
    my $archsname = $opts->{archsname};
    my $dumobj    = $opts->{metadumfile};
    my $incsobj   = $opts->{metaincsfile};
    my $refsobj   = $opts->{metarefsfile};
    my $cgdumobj  = $opts->{metacgdumfile};
    substr($dumobj,-1,1,"o");   # replace ".c" with ".o"
    substr($incsobj,-1,1,"o");  # replace ".c" with ".o"
    substr($refsobj,-1,1,"o");  # replace ".c" with ".o"
    substr($cgdumobj,-1,1,"o"); # replace ".c" with ".o"
## GPS add support to oracle for .a and .so (although still filter $archsname)
##    my $so_bregacclib = "/bbsrc/regobj/bregacclib.$archcode.so";
##    my @objs = grep { substr($_,0,2) ne "-l" && /\.(?:o|a|so)$/
##		      && $_ ne $so_bregacclib
##		      && [include the rest of the tests below] }
    my @objs = grep { substr($_,0,2) ne "-l" && /\.(?:o)$/
		      && $_ ne $archsname
		      && $_ ne $refsobj
		      && $_ ne $incsobj
		      && ($keepdums || ($_ ne $dumobj && $_ ne $cgdumobj))
		      && !/${task}_plink_timestamp\.[^.]+\.o$/o }
		    split ' ',$$link_line;
    # append sobjs and manually perform VPATH expansion, if necessary
    my $vpath = $opts->{VPATH} ? $opts->{VPATH}.'/' : "";
    foreach (split ' ',$opts->{ARCHSOBJS}) {
	push @objs, (-e $_ ? $_ : $vpath.$_)
	  if substr($_,rindex($_,'.')) eq ".o";
    }

    return \@objs;
}

sub do_kickstart_link ($$) {
    my($opts,$objs) = @_;
    my @args = (EXE_SYMBOL_ORACLE,"--besteffortlink");
    push @args, "--buildtag=".$opts->{buildtag};
    push @args, "--offline" if $opts->{offline};
    push @args, "--ignorelibs=".$opts->{ignorelibs} if $opts->{ignorelibs};
    push @args, "--port=".$opts->{port} if $opts->{port};
    push @args, "--host=".$opts->{host} if $opts->{host};
    my $WH = Symbol::gensym;
    my $RH = Symbol::gensym;
    my @output;
    my $pid = IPC::Open3::open3($WH,$RH,$RH,@args);
    {
	print $WH "@$objs";
	close $WH;
	# (need to change format that symbol oracle returns to be more robust)
	#local $/ = "";  # paragraph mode
	local $/ = "\n\n";
	@output = <$RH>;
	close $RH;
	waitpid $pid, 0;
    }
    $output[0] = "" unless @output;
    my $inclibs = \$output[0];
    $$inclibs =~ s/^INCLIBS=// 
      || die "Failed to retrieve link line from daemon (output follows)\n\n",
	     "@output";
    $$inclibs =~ s/\s+\Z//s;
    ##<<<TODO: temporary additional modification fudges
    ## (also need to track down where symbol oracle differs from sun linker)
    $$inclibs =~ s/(?:\.dbg_exc_mt)+\b//g;
    $$inclibs =~ s/ -lbsc\.\S+/ -lbsc/g;
    $$inclibs =~ s/ -la_basfs\b/ -la_basfs -lbsc/g;
    $$inclibs =~ s/ -ll_cny\b/ -ll_cny -la_baslt/g;
    $$inclibs =~ s/ -lhfc\b/ -lhfc -lfab/g;
    $$inclibs =~ s/ -lhft\b/ -lhft -lfab/g;
    $$inclibs =~ s/ -l(bae|bce|bde|bte)\b/ -l$1.dbg_exc_mt/g;

    my $dummies  = @output >= 4 ? \$output[3] : \(my $tmp_a = "");
    my $datarefs = @output >= 5 ? \$output[4] : \(my $tmp_b = "");
    return($inclibs,$dummies,$datarefs); 
}

sub add_dums ($$) {
    my($dumfile,$dummies) = @_;
    return if $$dummies eq "";
    my $FH = Symbol::gensym;
    open($FH,'>>',$dumfile)
      || die "Failed to open $dumfile for append: $!\n";
    print $FH "\n/* ",(scalar localtime())," */\n";
    foreach (split ' ',$$dummies) {
	print $FH "D($_)\n";
    }
    close $FH;
}

sub set_drefs ($$) {
    my($refsfile, $datarefs) = @_;
    return if $$datarefs eq "";
    ##<<<TODO: if this is not static and not volatile, will it
    ##         be optimized away after pulling in desired data?
    my $FH = Symbol::gensym;
    open($FH,'>',$refsfile)  ## always wipe out
      || die "Failed to open $refsfile: $!\n";
    foreach (split ' ',$$datarefs) {
	next if (substr($_,0,1) eq '.');
	print $FH (index($_,"ftncmns_") == 0
		    ? "extern void $_ (void);\n"
		    : "extern int $_;\n");
    }
    print $FH "static int metalink_dataref_dummy;\n",
	      "static volatile void *metalink_datarefs[] =\n",
	      "  {\n";
    foreach (split ' ',$$datarefs) {
	next if (substr($_,0,1) eq '.');
	print $FH "    (void *)&$_,\n";
    }
    print $FH "    (void *)&metalink_dataref_dummy\n",
	      "  };\n";
    close $FH;
}

## GPS: might pull this routine into a module
sub get_ftncmns_data_to_fn_map () {
    my($function,$size,$common,$symbol,%symbols,%functions);
    my $PH = Symbol::gensym;
    if ($^O eq "solaris") {
	my $libftncmns = "/bbsrc/sibuild/ftncmns/libftncmns.$archcode.a";
	my @nm_args = ("/usr/ccs/bin/nm","-g");
	open($PH,'-|',@nm_args,$libftncmns)
	  || die "Failed to generate map of common areas\n",
		 "  (@nm_args $libftncmns: $!)\n";
	while (<$PH>) {
	    next if $_ eq "\n";
	    if (index($_,'|') > 0) {
		chomp;
		($size,$common,$symbol) = (split /\|\s*/)[2,6,7];
		next unless defined($common) && $common eq "COMMON ";
		push @{$symbols{$symbol}}, [ $size, $function ];
		push @{$functions{$function}}, $symbol;
	    }
	    elsif (/\[(.+)\.$archcode\.o\]:$/o) {
		$function = lc($1)."_";
		$function =~ s/[.-]/__/g;  # same as done in docompile.pl
	    }
	}
	close $PH;
	$? == 0 || die "Failed to generate map of common areas\n";
    }
    elsif ($^O eq "aix") {
	## nm on AIX on a library that has been pre-linked does not provide
	## file information from where the symbol of given size originated.
	## The non-prelinked archive contains this information.
	## (Note: the nm -p option is critical to performance)
	my $libftncmns = "/bbsrc/sibuild/ftncmns/libftncmns.realarchive.a";
	my @nm_args = ("/usr/bin/nm","-g","-p","-C");
	open($PH,'-|',@nm_args,$libftncmns)
	  || die "Failed to generate map of common areas\n",
		 "  (@nm_args $libftncmns: $!)\n";
	while (<$PH>) {
	    next if $_ eq "\n";
	    if (/\[(.+)\.$archcode\.o\]:$/o) {
		$function = lc($1)."_";
		$function =~ s/[.-]/__/g;  # same as done in docompile.pl
	    }
	    else {
		($symbol,$common,undef,$size) = (split ' ');
		next unless defined($common) && $common eq "B";
		push @{$symbols{$symbol}}, [ $size, $function ];
		push @{$functions{$function}}, $symbol;
	    }
	}
	close $PH;
	$? == 0 || die "Failed to generate map of common areas\n";
    }
    else {
	warn("unsupported platform; add ftncmns code, rinse, and repeat\n");
    }

    ## The goal is to be able to produce a list of symbols and the preferred
    ## function to which to create a reference where that function must contain
    ## the largest size for a given data symbol, and then the fewest other data
    ## symbols, e.g. a preference for a function which defines one and only one
    ## data symbol (which, of course, has the proper size).

    # For the functions providing the largest size for given data symbols,
    # keep map of (number of data symbols provided => list of function names)
    my(%preferred,$choices,%ftncmns_map);
    foreach $symbol (sort keys %symbols) {
	$size = 0;
	undef %preferred;
	foreach (@{$symbols{$symbol}}) {
	    if ($size == $_->[0]) {
		push @{$preferred{(scalar @{$functions{$_->[1]}})}}, $_->[1];
	    }
	    elsif ($size < $_->[0]) {
		$size = $_->[0];
		%preferred = ((scalar @{$functions{$_->[1]}}) => [ $_->[1] ]);
	    }
	}
	$choices = $preferred{(sort { $a <=> $b } keys %preferred)[0]};
	# For now, print first symbol alphabetically among those functions that
	# provide the least number of other data symbols, while providing the
	# largest data symbol for the given symbol.
	$ftncmns_map{$symbol} = (sort @$choices)[0];
    }
    return \%ftncmns_map;
}

sub map_ftncmns_data_to_fn ($) {
    my $datarefs = $_[0];
    my $ftncmns_map = get_ftncmns_data_to_fn_map();
    my %ftncmns_refs;

    ## map .data symbols to preferred .text symbol that will cause an object
    ## to be pulled in that defines largest storage size in ftncmns for symbol.
    ## For commons not defined in ftncmns, metalink appears to produce a link
    ## line where the common area has a better probability (at least in
    ## practice) of being pulled in from a location that is related to the
    ## calling code, as opposed to referencing the common up front and pulling
    ## it in from the first lib found (which will not be libftncmns since
    ## libftncmns does not know about it)  Therefore, ignore .data symbols
    ## not found in ftncmns (instead of comment immediately following)
    ## (? create .data ref instead? if so, return $datarefs above, too, not \"")
    #$ftncmns_refs{$ftncmns_map->{$_}||$_}=undef foreach (split ' ',$$datarefs);

    foreach (split ' ',$$datarefs) {
	$ftncmns_refs{$ftncmns_map->{$_}} = undef if exists $ftncmns_map->{$_};
    }
    return \(join "\n",keys %ftncmns_refs);   # return reference to string
}

## GPS: FIXME update path
use constant FTNCMNS_SRC => "/bb/csdata/gstrauss/analysis/ftncmns/src/";

sub map_ftncmns_fn_to_f ($;$) {
    my($ftncmns_refs,$verbose) = @_;
    my($f,$inc,$i,@paths);
    $verbose ||= 0;

    ## This could be made more efficient if needed
    ## Create exception list for things that don't match the pattern of having
    ## a single underscore and the second char is not _g_ or _\d+_ and then
    ## check the filesystem for that first.  Could also rename the functions and
    ## files to be directly translatable to filesystem path.  Remember that we
    ## also will need to have .c files including .h inc2hdr in the future, too.

    FTNCMNS_REF:
    foreach $f (keys %$ftncmns_refs) {
	chop $f; # remove trailing "_"
	($inc = $f) =~ s/^ftncmns_//;
	$inc =~ tr|_|/|;
	$inc = "/bbsrc/bbinc/$inc.inc";
	$f .= ".f";
	while (! -e $inc) {
	    $i = rindex($inc,"/");  # (in this case, not >= here)
	    if ($i > 0) {
		substr($inc,$i,1,"_");
	    }
	    else {
		warn("$f not found (or associated .inc not found)\n")
		  if ($verbose > 1);
		next FTNCMNS_REF;
	    }
	}
	$inc =~ s|^/bbsrc/bbinc/||;
	push @paths, FTNCMNS_SRC . substr($inc,0,rindex($inc,"/")+1) . $f;
    }
    return \@paths;
}

sub ftncmns_incs ($$) {
    my($opts,$datarefs) = @_;
    my $FH = Symbol::gensym;
    my $ftncmns_map = get_ftncmns_data_to_fn_map();
    my %ftncmns_refs;
    foreach (split ' ',$$datarefs) {
	$ftncmns_refs{$ftncmns_map->{$_}} = undef if exists $ftncmns_map->{$_};
    }
    my @contents;
    my $verbose = $opts->{verbose};
    foreach my $ftncmns_f (@{map_ftncmns_fn_to_f(\%ftncmns_refs,$verbose)}) {
	open($FH,"<",$ftncmns_f) || (warn("open $ftncmns_f: $!\n"), next);
	while (<$FH>) {
	    push @contents, $_ unless ($_ eq "\n");
	}
	close $FH;
    }
    return \@contents;
}

sub parse_link_error_for_undefs ($$) {
    my($mkfile,$output) = @_;
    my $dummies = "";
    if ($$output =~ s/.*Undefined\s+first referenced\s+symbol\s+in file\s+//s) {
	# (skip C++ demangled symbols; to dummy, we would need -mangled- symbol)
	foreach (split "\n", $$output) {
	    $dummies .= " ".$1
	      if (index($_,"::") < 0		 # skip C++ demangled names
		  && index($_,"[Hint:") != 0     # (C++ hints from Sun ld)
		  && index($_,"CC: Warning:")!=0 # ("Option -t passed to ld...")
		  && index($_,"ld: fatal:") != 0 # (last line "ld: fatal: ...")
		  && /(\w+)(?:\(\))?\s+\S+$/);	 # second to last word in line
	}
    }
    elsif ($$output =~ /ld: fatal: symbol [^\n]+ is multiply-defined:/) {
	print STDERR "metalink: ($mkfile) 'multiply-defined' errors\n",
		     "metalink: ($mkfile) must be resolved before continuing.",
		     "\n\n";
    }
    return \$dummies;
}

sub create_dumfile ($) {
    my $dumfile = shift;
    my $FH = Symbol::gensym;
    open($FH,'>',$dumfile)
     || die "Failed to open $dumfile for writing: $!\n";
    print $FH "#include <blpdummy.h>\n";
    close $FH;
}

sub create_cgdumfile ($$$) {
    my($opts,$mkfile,$link_line) = @_;
    my($CALLGRAPH,$CGTREE) = (Symbol::gensym,Symbol::gensym);
    my $callgraph = $opts->{metacgfile};
    my $cgdumfile = $opts->{metacgdumfile};
    my $cgdumfiletmp = $cgdumfile.".tmp";
    my @cgtree_cmd = (EXE_CGTREE, "-p", $cgdumfiletmp);
    splice @cgtree_cmd, 1, 0, "-debug" if ($opts->{debug} > 3);

    ## move cg data files back to .mk directory if task target is elsewhere
    my($otarget) = $$link_line =~ /-o\s+(\S+)/;
    if (index($otarget,"/") >= 0) {
	$otarget = substr($otarget,0,rindex($otarget,'/'));
	my $pwd = get_mk_pwd();
	if ($otarget ne $pwd && $otarget ne ".") {
	    require File::Path;
	    my @cgdata = ($otarget."/".$opts->{metacgfile},
			  $otarget."/".$opts->{metacglibs});
	    foreach my $cg (@cgdata) {
		File::Copy::move($cg,$pwd) if -e $cg;
	    }
	}
    }

    ## generate new cgdumfile
    open($CALLGRAPH,'<',$callgraph)
      || (warn("open $callgraph: $!\n"), return 0);
    if (open($CGTREE,'|-',@cgtree_cmd)) {
	local $/ = \65536;  # read input in blocks, not lines
	print $CGTREE $_ while (<$CALLGRAPH>);
	close $CGTREE;
	($? == 0) || (warn(EXE_CGTREE," did not succeed ($?)\n"), return 0);
    }
    else {
	warn("@cgtree_cmd: $!\n");
	return 0;
    }
    close $CALLGRAPH;

    my($line,%seen_t,%seen_d);
    my $FH = Symbol::gensym;
#    ## seed filter with symbols defined in objects on link line
#    ## Note: this is not strictly necessary at the moment for majority of cases
#    ## but might be needed in the future for -z allextract and friends
#    ##<<<TODO: will need to scan link line for Solaris linker option to take
#    ## whole archive and include those in the list of binary items to scan
#    ## (-z allextract, and maybe -z weakextract, up to -z defaultextract)
#    my $task = $opts->{task};
#    my @objs = grep { substr($_,0,2) ne "-l" && /\.o$/
#		      && !/${task}_plink_timestamp\.$archcode\.o$/o }
#		    split ' ',$$link_line;
#    if (open($FH,'-|',"/usr/ccs/bin/nm","-gP",@objs)) {
#	my($symbol,$type);
#	while (<$FH>) {
#	    next if (substr($_,0,1) eq '$'); # skip debug symbols
#	    next if (substr($_,0,1) eq '.'); # skip 
#	    ($symbol,$type) = split ' ',$_,3;
#	    $seen_t{$symbol}++ if ($type eq 'T');
#	    $seen_d{$symbol}++ if ($type eq 'D');
#	}
#	close $FH;
#    }

    ## ensure dummies and data definitions are unique
    ## dummy calls such as from externs in multiple places might result
    ## in duplicate dummy instances (fatal if not made unique)
    my @cgdumlines;
    open($FH,'+<',$cgdumfiletmp)
      || (warn("open $cgdumfiletmp: $!\n"), return 0);
    while ($line = <$FH>) {
	push @cgdumlines, $line if (substr($line,0,2) eq "/*"
				    || !( $line =~ /^D\((\S+)\)/
					  ? $seen_t{$1}++
					    ## IS_GLIBOFFLINE kludge
					    || substr($1,0,2) eq "g_"
					    || substr($1,0,3) eq "_g_"
					    || $1 eq "combine"
					  : $line =~ /^int (\S+) =/
					      ? $seen_d{$1}++
					      : 0 ));
    }
    seek($FH,0,0)
      && (print $FH @cgdumlines)
      && truncate($FH,tell($FH))
      && close($FH)
      || (warn("while writing $cgdumfiletmp: $!\n"), return 0);
    rename($cgdumfiletmp,$cgdumfile)
      || (warn("rename $cgdumfiletmp $cgdumfile: $!\n"), return 0);

    ## add cgdumfile to OBJS in mkfile if missing
    my $mkcontents = read_mk_contents($mkfile);
    my $mkobjs     = mkvar_mod($mkcontents,"OBJS") || \(my $mkobjs_tmp = "");
    my $dumobj     = $opts->{dumfile};
    my $cgdumobj   = $cgdumfile;
    substr($dumobj,-1,1,"o");   # replace ".c" with ".o"
    substr($cgdumobj,-1,1,"o"); # replace ".c" with ".o"
    unless ($$mkobjs =~ /\b\Q$cgdumobj\E/) {
	$$mkobjs =~ s/\b\Q$dumobj\E/$dumobj $cgdumobj/
	  || ($$mkobjs .= " ".$cgdumobj);
	mkvar_mod($mkcontents,"OBJS",$mkobjs);
	write_mk_contents($opts->{mkfile},$mkfile,$mkcontents);
    }

    return 1;
}

sub do_link_or_dummy ($) {
    my $opts = shift;
    my($mkfile,$buildtag) = @{$opts}{"mkfile","buildtag"};
    my($rv,$output) = compile_and_link($opts,$mkfile,$buildtag);
    return $rv if $rv == 0;  ## successful link

    my $dummies = parse_link_error_for_undefs($mkfile,$output);
    if ($$dummies ne "") {
	## add dummies
	my $dumfile = $opts->{metadumfile};
	create_dumfile($dumfile) unless (-e $dumfile);
	add_dums($dumfile,$dummies);

	## warn if $dumfile .o is not in .mk file OBJS
	substr($dumfile,-1,1,'o'); # replace .c with .o
	my $mkcontents = read_mk_contents($mkfile);
	my $mkobjs = mkvar_mod($mkcontents,"OBJS") || \(my $tmp = "");
	print STDERR "\n*** Please add $dumfile to OBJS in $mkfile***\n\n"
	  unless ($$mkobjs =~ /\b\Q$dumfile\E/);

	print STDERR "\n*** dummies added to $dumfile ***\n    ",
	  "Re-run metalink --linkordummy to link with dummies\n\n";
    }
    return $rv;
}

#------------------------------------------------------------------------------

##
## GPS: AIX madness
## read breg.ibm.tsk.mapfile
##   lookup in symbol oracle and add necessary C++ libs
##     (add special variable for additional AIX libraries?)
##       (==> yes -- add it to $(LIBS))
##     (add special rule on AIX which uniquifies INCLIBS when building on AIX?)
##     or add additional dummies for C++ on AIX?
##

#------------------------------------------------------------------------------

sub exit_rv ($) {
    my $rv = shift;
    exit ($rv >> 8) ? ($rv >> 8) : (($rv & 127) || ($rv & 128)) ? -1 : $rv;
}

sub exit_clean ($$$) {
    my($rv,$mkfile,$logmsg) = @_;
    print STDERR "metalink: ($mkfile) $logmsg\n\n",
		 "metalink: ($mkfile) Start:  ",scalar localtime($^T),"\n",
		 "metalink: ($mkfile) Finish: ",scalar localtime(time),"\n";
    logevent($logmsg);
    exit_rv($rv);
}

MAIN: {
    my $opts = getoptions();
    my($rv,$output);

    my $origmk    = $opts->{mkfile};
    my $buildtag  = $opts->{buildtag};
    my $metamkfile= $opts->{metamkfile};
    my $dumfile   = $opts->{metadumfile};
    my $verbose   = $opts->{verbose} || 0;
    my $addlibs   = $opts->{addlibs};

    ## run "clean" (if asked)
    system(EXE_PLINK,$origmk,"clean")
      if ($opts->{clean} || $opts->{realclean});

    ## (special mode for robocop; mimic autoplink for robocop)
    if ($opts->{linkordummy}) {
	print STDERR "\n",scalar localtime($^T),"\n",
		     "metalink: ($origmk) Running plink --\n",
		     "metalink: ($origmk) please be patient\n\n";
	$rv = do_link_or_dummy($opts);
	exit_clean($rv,$origmk,"completed linkordummy (rv:$rv)");
    }

    ## set up for metalink
    metalink_setup($opts);

    ## compile local objects
    print STDERR "\n",scalar localtime($^T),"\n",
      "metalink: ($metamkfile) Compiling base objects\n\n";
    logevent("compiling base objects");
    ($rv,$output)= compile_local_objects($opts,$metamkfile,$buildtag,$verbose);
    $rv == 0 || exit_rv($rv);
    ($rv,$output)= compile_and_link_sobjs($opts,$metamkfile,$buildtag,$verbose);
    $rv == 0 || exit_rv($rv);

    ## retrieve objects in link line
    ($rv,$output) = do_plink($opts,$metamkfile,$buildtag,{print_cmds => 1});
    $rv == 0 || exit_rv($rv);
    ## "gmake -q" would be a nice test to determine if everything is up to date,
    ## but linktask.newlink task creation rules always trigger (even if only to
    ## print out "Done...")  Instead we must "guess" if task need to be rebuilt.
    my $archtask = $opts->{archtask};
    if (!defined get_link_line($output)){#(no link -- static .tsk is up to date)
	if (-f $archtask && -s _
	    && (!$opts->{socheck} || so_checks($opts,$origmk))) {
	    unlink($metamkfile);
	    exit_clean(0,$origmk,"success (static .tsk not relinked)");
	}
	else {
	    ($rv,$output) = do_plink($opts,$metamkfile,$buildtag,
				     {print_cmds => 1});
	    $rv == 0 || exit_rv($rv);
	}
    }

    ## kick-start link
    if ($opts->{kickstart}) {
	check_link_line_buildtags($output,$buildtag);
	my $objs = get_plink_objects($opts,$output);

	## copy objects to NFS-visible disk
	##<<<TODO: inefficient to stringifying and split, but suffices for now
	my $nfstmpdir = get_metalink_nfstmpdir($opts);
	($rv,$output) = make_visible_on_nfs(\(join " ",@$objs),$nfstmpdir);
	$rv ? (@$objs = split ' ',$$output) : ((print STDERR $$output), exit 1);

	print STDERR "\n" if $verbose;
	print STDERR scalar localtime(time),"\n",
	  "metalink: ($metamkfile) Performing kick-start link --\n",
	  "metalink: ($metamkfile) please be patient\n\n";
	logevent("performing kick-start link");
	my($inclibs,$dummies,$datarefs) = do_kickstart_link($opts,$objs);
	logevent("finished kick-start link");
	my $mkcontents=metalink_update_mk($opts,$metamkfile,$inclibs,$datarefs);
	my $addedlibs =metalink_get_added_libs($opts,$inclibs,$addlibs);

	## repeat kick-start link if there were libs added and we wish to ignore
	## (if frequently used, might move this functionality into symbol
	##  oracle so that it can be done in a single kick-start link)
	if (!$addlibs && scalar keys %$addedlibs) {
	    $opts->{ignorelibs} =
	      ($opts->{ignorelibs} && $opts->{ignorelibs} ne "")
		? join(",",$opts->{ignorelibs}, keys %$addedlibs)
		: join(",",keys %$addedlibs);
	    logevent("re-running kick-start link with ignorelibs");
	    ($inclibs,$dummies,$datarefs) = do_kickstart_link($opts,$objs);
	    logevent("finished 2nd kick-start link");
	    $mkcontents =
	      metalink_update_mk($opts,$metamkfile,$inclibs,$datarefs);
	    $addedlibs = metalink_get_added_libs($opts,$inclibs,!$addlibs);
	}

	## update .mk, dums, and refs as appropriate
	write_mk_contents($origmk,$metamkfile,$mkcontents);
	#add_refs($opts->{metarefsfile},$opts->{ARCHSOBJS})
	#  if (${$opts->{ARCHSOBJS}} ne "");
	## ([ARCHSOBJS needs VPATH expansion if used above)
	print STDERR "metalink: some symbols were not found in the ",
		     "symbol cache\n\n", $$dummies
	  if ($$dummies !~ /\A\s*\Z/s && $verbose >= 2);
	##<<<TODO: Disabled until there are multiple symbol oracles set up for
	## linking against source (/bbs/lib), local (/local/lib), and stage
	## (/bbs/stage/lib) libraries.  At that point, C++ symbols will be
	## dummied if not found, unless we filter /BloombergLP/ from the list.
	## Probably should skip unknown symbols matching =~ /BloombergLP/
	## unless a flag is provided as an argument.
	## Probably should leave this disabled so that symbols can be found by
	## plink in cases of Quantify, Purify, etc, where oracle does not see
	## those symbols.  If other symbols are not found, a dummy-then-plink
	## pass will enable a task to be linked.
	#add_dums($dumfile,$dummies);
	## The above used to also check --keepdums, with the following comment,
	## (though if we keep the feature, probably want a different flag once
	##  ftncmns is in place)
	## (If --keepdums is set, skip initial dummying on first pass so that 
	##  rest of metalink activities will be performed.  This is useful when 
	##  symbol oracle does not know about a symbol, but plink can find it.)
    }

    ## exit early if not linking task
    if (!$opts->{link}) {
	metalink_commit($opts,$metamkfile,$origmk);
	exit_clean(0,$origmk,"success (nolink)");
    }

    $rv = 0;

    if ($opts->{callgraph}) {
	my $link_line;
	if ($opts->{cgdum}) {
	    ($rv,$output)=do_plink($opts,$metamkfile,$buildtag,{print_cmds=>1});
	    $rv == 0 || exit_rv($rv);
	    $link_line = get_link_line($output)
	      || die $$output,"\n\nUnable to retrieve link line from above\n\n";
	}
	create_dumfile($opts->{metacgdumfile}) unless $opts->{keepdums};#wipeout
	print STDERR scalar localtime(time),"\n",
	  "metalink: ($metamkfile) Generating call graph from link --\n",
	  "metalink: ($metamkfile) please be patient\n\n";
	logevent("generating call graph from link");
	($rv,$output) = compile_and_link($opts,$metamkfile,$buildtag);
	$opts->{callgraph} = 0; # done (skip for subsequent compile_and_link())
	logevent("finished generating call graph from link (rv:$rv)");
	## check for completed call graph
	## (undefined symbols indicate complete call graph, even if link failed)
	if ($rv != 0) {
	    my $dummies = parse_link_error_for_undefs($metamkfile,$output);
	    if ($$dummies ne "") {
		$rv = 0 if $opts->{cgdum};	# success; complete call graph
	    }
	    else {
		$output = $dummies;		# (clear error output; set "")
		unlink( $opts->{metacgfile},	# remove incomplete call graph
			$opts->{metacglibs});	# remove incomplete libs file
	    }
	}
	if ($rv == 0 && $opts->{cgdum}) {
	    ## use call graph to generate dummies for unreachable code
	    ## touching dummy file will cause gmake to relink task
	    ## (smaller task links and comes up in debugger more quickly)
	    ## (relinking task also eliminates any potential interference
	    ##  from call graph generation)
	    ## (specify --callgraph without --cgdum for testing and no relink)
	    print STDERR "\n",scalar localtime(time),"\n",
	      "metalink: ($origmk) Generating dummies from call graph\n\n";
	    logevent("generating dummies from call graph");
	    create_cgdumfile($opts,$metamkfile,$link_line);
	    ## Future potential optimization:
	    ##  redo kick-start link after adding new dums or refs
	    ##  (to potentially reorder/remove libraries from link line)
	}
    }

    ## attempt the real plink
    if ($rv == 0) {
	print STDERR scalar localtime(time),"\n",
	  "metalink: ($metamkfile) Performing plink (initial pass) --\n",
	  "metalink: ($metamkfile) please be patient\n\n";
	logevent("performing plink (initial pass)");
	($rv,$output) = compile_and_link($opts,$metamkfile,$buildtag);
	logevent("finished plink (initial pass)");
    }

    ## Any failures result from real undefined symbols or from unrelated objects
    ## that were pulled in to resolve Fortran common area data symbols.
    ## Therefore, dummy everything that fails and link once more.
    ## (If !$opts->{kickstart}, then this is very similar to --linkordummy)
    if ($rv != 0) {
	my $dummies = parse_link_error_for_undefs($metamkfile,$output);
	if ($$dummies ne "") {
	    create_dumfile($dumfile) unless (-e $dumfile);
	    add_dums($dumfile,$dummies);
	    print STDERR "\n",scalar localtime(time),"\n",
	      "metalink: ($metamkfile) Performing plink (final pass) --\n",
	      "metalink: ($metamkfile) please be patient\n\n";
	    logevent("performing plink (final pass)");
	    ($rv,$output) = compile_and_link($opts,$metamkfile,$buildtag);
	    logevent("finished plink (final pass)");
	}
    }

    if ($rv == 0 && $opts->{socheck} && !so_checks($opts,$origmk)) {
	$rv = 1;
	print STDERR
	  "metalink: ($origmk) detected conflict between .so and .tsk.\n",
	  "metalink: ($origmk) please re-run metalink to try again\n\n";
    }

    if ($rv == 0) {
	metalink_commit($opts,$metamkfile,$origmk);
    }

    exit_clean($rv,$origmk,($rv == 0 ? "success (linked)" : "link failed"));
}

#==============================================================================

=head1 AUTHOR

Glenn Strauss (gstrauss1@bloomberg.net)

=cut

## RFE: AIX: ability to dummy C++ on AIX (read mapfile)
## RFE: AIX: removal of multiply defined syms (listed in mapfile) from dum files

## RFE: parse link failures and recommend/take actions (see autoplink)
## RFE: automake creates a task debug script
##	autoplink creates some hint files for debug script using nm. What is it?
## RFE: search objects (not final .tsk or .so) for main() or issue warning
##	(might do that in symbol oracle if --offline is passed because we
##	 are already reading the objects at that point)

## Note, when we support multiple platforms, we might institute locking around
## writing the .mk file.  Or we might append $^O.metalink.mk, though that would
## mean needing to update all places that get mktag from the prefix (and would
## need to know $^O for all supported platforms).  In any case, because the
## refs and dums and incs files are not platform-specific, we might just say
## "Don't do that" to people running metalink on the same makefile on multiple
## machines/platforms at the same time.

## People should opt to run metalink on Solaris so that dummies, if needed,
## will be better.  Then run metaink on AIX to have it add the extraneous C++
## libraries that AIX thinks it needs, but really does not.  Maybe put this
## into a macro so that Solaris links are not slowed down by these extra
## libraries on the link line.

## Uniquify (and reverse?) INCLIBS for AIX?  It does not need to see duplicated
## library names, and uniquifying the libs might speed up the link a bit on AIX.

## RFE: print a final note at the end of linking suggesting moving metalink
##	dum file to permanent dum file

## RFE: cgtool aborts if it detects that libraries have changed during linking
##	(probably better to set up an environment where this shouldn't happen)

## RFE: log the size of the task that was created in final log event

## RFE: reference all .text symbols up front and simplify the link line
