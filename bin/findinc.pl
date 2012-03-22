#!/usr/bin/env perl

use strict;
use warnings;

use Carp;

use Getopt::Long;

use Text::Wrap;

$| = 1;


#==============================================================================

=head1 NAME

findinc - List files that include a source file

=head1 SYNOPSIS

    $ findinc includablefile ...
    $ findinc [options] includablefile ...

Options:

  --callers    | -C           list files that include includablefile
  --defines    | -D           list files that look like includablefile
  --all        | -a           list both callers and defines

  --concise    | -c | -n      only list filename of callers (-n historic)
  --exact      | -e           must match entire included pathname
                                  (implies --gtkforce)
  --generated  | -g           list generated file (default off)
  --gtkforce   | -G           don't strip leading gtk/ from includablefile
  --single     | -s           do not recursively list callers of callers
  --trace      | -t           trace calling chain for recursive callers
  --multipath  | -m           list all included files that lead to
                                any specified includablefile
				(implies --generated)

  --immediate  | -i           immediate (historical, ignored)

  --verbose    | -v           extra output (none at present)
  --debug      | -d           enable debug reporting
  --version    | -V           print version info
  --help       | -h           usage information (this text)

  includablefile              file that might be included by other source code


Options:

=head1 DESCRIPTION

Checks to see what files include the listed includable files, which can be
C or C++ header files (.h), Fortran include files (.inc or .ins), etc.
Since this program is a replacement for F<findinc>, which has now been
renamed to F<findinc_old>, the default behaviour
and the base set of options is taken from F<findinc_old>.  See L</LIMITATIONS>
for a description of places where this base functionality fails to be
exactly the same.

=over 4

=item --callers

=item --defines

=item --all

The three options C<--callers> (or C<-C>), C<--defines> (or C<-D>)
and C<--all> (or C<-a>) control what is being searched for and reported
upon.

The default (and the only type of search that was supported by the
F<findinc_old> program) is C<--callers>, which lists all of
the files which include the specified includablefile(s).  When the
C<--defines> option is specified, files known to F<findinc>
that match the names of the includablefile(s) will be listed.
The C<--all> option is a shorthand for C<--callers --defines> - that
gives you both types of output.  When both are specified (either
explicitly or with C<--all>), the format is different from either alone
so that you can distinguish the two parts.

=item --concise

The C<--concise> (or C<-c> or, for legacy purposes, C<-n>) option will
list only  the filename
of callers instead of the file, directory, and include line.
This option was provided by F<findinc_old> only as C<-n>.  That name is
retained although it is not very mnemonic, so the longer name C<--concise>
and the new short name C<-c> are preferred.

=item --exact

The C<--exact> (or C<-e>) option will cause F<findinc> to match an
include line only if it includes exact same pathname as is specified.
The default is to match any inclusion that ends with the specified
pathname.  (So, if a file has an include line that looks like:

        #include <foo/bar/baz.h>

it will be listed by the command: C<findinc baz.h> or
the command: C<findinc bar/baz.h> or the command:
C<findinc foo/bar/baz.h> or the command C<findinc
home/devel/test/library/foo/bar/baz.h> but if the --exact option is
specified, the first two would fail, while the third of those variants:
C<findinc --exact foo/bar/baz.h> would list this line
as a match, and the others would not match.

The fourth example above: C<findinc home/devel/test/library/foo/bar/baz.h>
will match regardless of whether C<--exact> is specified.
That is the normal case so that F<findinc> can be called with
pathnames derived from a directory tree.  (Something like:
C<findinc `find workdir -name '*.h' -print`> for example,
which runs F<findinc> against all of the .h files under the C<workdir>
directory.

However, the C<--exact> option only affects the matching done
on files listed as arguments.  It does not affect the matching
done for files that are being scanned because they had an
inclusion.  The problem is that C<findinc> has no way of choosing
which portion of recursively included names are to be used for the
exact match.  (It has no way of determining which of the directories
in the name of a matched file happen to correspond to the various search paths
used when searching for includable files.)

This option formerly implied C<--single>, but it no longer does.
While the two options can be useful together, having C<--exact> be
available as part of a full recursive search is also useful in
some cases.

This option implies C<--gtkforce> to avoid having the C<--gtkforce>
option strip a leading "gtk/" from the provided target and then doing
an exact match on a value that is different from what was requested.

=item --generated

The option C<--generated> (or C<-g>) causes F<findinc> to
change how it displays files that are generated from source files.
For example, a source file with a .gob extension can generate
either or both of a .c and a .h file.  By default, if either of
those files is found to be including an includablefile target,
the original .gob file is displayed (which is what is needed for
cscheckin's purposes but can be confusing for humans.  With this
option set, findinc will display the name of the generated file
instead.  The C<--multipath> option below will list all of them that
are actually used.  The C<--trace> option (see below) will in either case
list them both using "foo.h (from foo.gob)" if any file includes
this file.

=item --gtkforce

For historical reasons, a leading gtk/ on a provided includablefile
argument is stripped off.  The C<gtkforce> (or C<-G>) option forces
it to be accepted as is.
(It is automatically turned on by C<--exact>.)  The need to explicitly
ignore a leading gtk/ is now largely obsolete.  At some point
in the future, this option will be determined to be unneccessary
and will be removed.

=item --single

The option C<--single> (or C<-s>) prevent the recusive scan
for callers of callers (and callers of callers of callers, etc.)
So, only files that directly include those includablefile(s) that
were specified on the command line, will
be listed.  This option is no longer implied by C<--exact>, but
it used to be.

=item --trace

The C<--trace> (or C<-t>) option causes F<findinc> to augment
its output so that when an inclusion is found, as well as the
normal output an extra line of output is displayed that lists the
chain of file inclusions that cause the including file to be found.
(There will often be other chains that would also cause the same
including file to include the same target, only the first discovered
is listed.  See C<--multipath> to get some more of the paths listed.)

=item --multipath

The C<--multipath> (or C<-m>) option causes F<findinc> to list
all inclusions from a file that directly or indirectly lead to an
includablefile
that was specified on the command line.  This option implies the
C<--generated> option, so inclusions from both the original source
file and each of the generated files will all be listed as
appropriate.  If an include line is present in the original, it
will be listed for the original and for each of the generated files
that gets a copy of the include line.  If an include line is created
as part of the generating process, only the generated files into which
it is inserted will be listed.  (Note that without the C<--multipath>
or C<--generated> options specified, a created include line is shown
as coming from the original (e.g. .gob) file, even though it is not
actually present in the text of that file.)

Even with C<--multipath> specified, the C<--trace> path
will not list all the possible paths from the including file to the
includablefile target.  Using C<--multipath> will list one path from
each directly included file for each target that can be reached from
that file; without
C<--multipath> only a single path to the includable target would be
listed.

=item --immediate

The C<--immediate> (or C<-i>) option was provided by F<findinc_old> and
remains here to be upward compatible.  It is ignored.  (It was
used by F<findinc_old> to affect the order that output was displayed,
but the order of F<findinc> is different anyhow and has
no current need to have an alternate order.  This option may be
reused in the future.)

=item --verbose

The C<--verbose> (or C<-v>) option is reserved for future use.

=item --debug

The C<--debug> (or C<-d>) option enables extra debug reporting.
It is used for development purposes and the output is liable
to change at any time.

=item --version

The C<--version> (or C<-V>) option displays version information
about the programs and terminates without any other processing.
The format of this output is subject to change.

=item --help

The C<--help> (or C<-h>) option displays help information and terminates
without any other processing.

=back

=head1 LIMITATIONS

This program is a replacement for the original F<findinc>, now called
F<findinc_old>, so its default interface mimics the traditional
F<findinc_old> one.  There are some differences between (the new)
F<findinc> and F<findinc_old> that might still be significant.

=over 4

=item * dated information

Both F<findinc_old> and F<findinc> use dated information, which
lags behind changes to the actual code repository.  The information
used by F<findinc> is updated hourly; the scant database
used by F<findinc_old> is updated daily.

=item * one universe view

Both F<findinc_old> and F<findinc> report on the files that have been
checked in with cscheckin.  They do not include changes that
are staged.  They do include changes that might still be backed out during
the next build.

=item * false positives

F<findinc_old> would determine that a file including a queried file using a 
method that sometimes found extra inclusions.  In particular, if a
file (file1) includes file2.h which is generated from file2.gob, and
file2.gob also generates file2.c file that includes a changed file, file1
would always be reported.  F<findinc> will only list file1 if the
generated file2.h has the inclusion of the changed file.  This is a
good thing.

However, F<findinc> can give a false positive report in two cases.

First, F<findinc> does not completely parse the source files.
It will accept as significant lines that appear to be valid include
lines but which would be
suppressed during compilation by the surrounding context.
So, an include line that has been commented out with text
that only appears on other lines would still be processed.
Similarly, an include line that is wrapped in a conditional
compilation macro will be processed regardless of whether
the condition is actually true of false.  (This is actually
a usually-true positive instead of a false positive.  The
conditional compilation is generally there for a purpose,
and that purpose will sometimes happen.  So, platform-specific
inclusions will get used when compiling for that platform,
and findinc is generally more useful if it reports all of the
inclusions that will get used, even the inclusions for other
platforms than the one that findinc is currently running on.)

Second, F<findinc> does not have know which parts of filenames
happen to be used in C<-L> link directives.  So, if a file is
C<a/b/c/foo.h>, F<findinc> cannot tell whether any of C<a>,
C<b>, or C<c> are in the include search path for files that
might be including F<foo.h>,  So, it accepts an include line
of:

   #include <foo.h>
   #include <c/foo.h>
   #include <b/c/foo.h>
   #include <a/b/c/foo.h>

but will reject lines:

   #include <d/foo.h>
   #include <a/b/foo.h>

etc. - i.e. whenever the include request cannot match the actual
location.

=item * false negatives

F<findinc> uses a database that is built with a pattern match
of the source repository.  It does not use any compiler specific
macro processing.  This means that an include line that is affected by macro
processing may be processed wrong.  If the syntaxt of the include
line is generated by a macro (e.g. C<#include _MACRO_(foo)> expands to
C<#include E<lt>lib/foo.hE<gt>>) the line will not be detected at all by
F<findinc>.  If the include filename is generated by the macro
(e.g. C<#include E<lt>_MACRO_E<gt>> expands to C<#include E<lt>lib/foo.hE<gt>>,
the line will be seen by F<findinc> but it will be treated as
as an inclusion of C<_MACRO_> instead of C<lib/foo.h>.

=item * report order

The order that F<findinc_old> and F<findinc> list the including files is
likely to be different.

=item * report repetitions

If a file has multiple include sequences to one or more of the target files,
it will only be listed one time (by default, but see the C<--multipath>
option to get more occurrences).  There may have been circumstances in which
F<findinc_old> reported the same file more than once.

=item * include line content

F<findinc_old> displayed a "reconstituted" include line that was generated on
the fly.  F<findinc> displays the contents of the actual include
line.  The reconstituted content from F<findinc_old> omits the exact syntax
used (e.g. what characters surround the name of the included file),
and uses the name of the target file from the command line, which
could have a different path specification from what is in the actual
include line (e.g. gtk/foo.h instead of foo.h).  Generally, getting
the real content, instead of an intuited guess, should be a benefit;
but any caller that parses this output now has to be prepared to deal
with the full range of syntax that is possible; and with the filename
being different from what was asked for.

=item * immediate option

F<findinc_old> had an option (-i) which caused it to present its output at a
different point in its internal processing, perhaps in a different order.
F<findinc> uses a different implementation and always displays items
as they are found, so -i is ignored.  This difference is a slightly different
version of the "report order" issue listed above.

=item * mangled source code

F<findinc> will list I<inclusions> that are present in the source
file, even if there is no corresponding real file that matches.  So, if
a source file contains: C<#include E<lt>*.hE<gt>> and you run: C<findinc
'*.h'> it will report that inclusion.  However, if an inclusion has embedded
space or tab characters it will not be collected into the database used
by F<findinc> - embedded whitespace is far too likely to cause
problem on a Unix system to be treated as legitimate.

=item * Fortran case sensitivity

F<findinc> treats the filename included by Fortran source as if it
was written "correctly" for the Unix case-sensitive file system.
It is conceivable that because of its
historical legacy (in which Fortran was written using keypunches
that did not support lower case letters) there may be Fortran
compilers that provide some case mapping fallbacks when it looks
for include files allowing the source code to have the wrong case.
If there are any instances where Fortran code depends upon such a
capability, F<findinc> will fail to understand it.

=back

=head AUTHOR

John Macdonald (jmacdonald6@bloomberg.net)

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    # my $prog = basename $0;
    my $prog = $0;

    print <<_USAGE_END;
Usage: $prog [-h|-V]
       $prog [option]* includablefile [...]
  --callers    | -C           list files that include includablefile (default)
  --defines    | -D           list files that look like includablefile
  --all        | -a           list both callers and defines

  --concise    | -c | -n      only list filename of callers (-n historic)
  --exact      | -e           must match entire included pathname
                                  (implies --gtkforce)
  --generated  | -g           list generated file (default off)
  --gtkforce   | -G           don't strip leading gtk/ from includablefile
  --single     | -s           do not recursively list callers of callers
  --trace      | -t           trace calling chain for recursive callers
  --multipath  | -m           list all included files that lead to
                                any specified includablefile
				(implies --generated)

  --immediate  | -i           immediate (historical, ignored)

  --verbose    | -v           extra output (none at present)
  --debug      | -d           enable debug reporting
  --version    | -V           print version info
  --help       | -h           usage information (this text)

  includablefile              file that might be included by other source code

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

my $concise;
my $exact;
my $generated;
my $gtkforce;
my $callers;
my $defines;
my $all;
my $single;
my $trace;
my $multipath;
my $immediate;
my $verbose;
my $debug;
my $version;
my $help;


sub getoptions {
    Getopt::Long::Configure("bundling", "no_ignore_case");
    unless (GetOptions(
	'callers|C'	=> \$callers,
	'defines|D'	=> \$defines,
	'all|a'		=> \$all,

	'concise|c|n'	=> \$concise,
	'exact|e'	=> \$exact,
	'generated|g'	=> \$generated,
	'gtkforce|G'	=> \$gtkforce,
	'single|s'	=> \$single,
	'trace|t'	=> \$trace,
	'multipath|m'	=> \$multipath,

	'immediate|i'	=> \$immediate,

	'verbose|v'	=> \$verbose,
        'debug|d+'	=> \$debug,
	'version|V'	=> \$version,
        'help|h'	=> \$help,
    )) {
        usage();
        exit 1;
    }

    # help
    if ($help) {
	usage();
	exit 0;
    }

    # version
    if ($version) {
	my $version_string = 'findinc (new) version 2';
	print( "findinc version: $version_string\n" );
	exit 0;
    }

    unless (@ARGV) {
	warn "Need at least one <includablefile> argument\n";
        usage();
        exit 1;
    }

    # --all means both
    # neither of --defines or --callers defaults to --callers only
    if ( $all ) {
	++$callers;
	++$defines;
    }
    else {
	# callers is the default is nothing is asked for
	++$callers unless $defines;

	# if both --callers and --defines were specified ten
	# that is the same as --all
	++$all if $callers && $defines;
    }
    ++$gtkforce if $exact;
    ++$generated if $multipath;
}


#------------------------------------------------------------------------------


my $included_extensions;

{
    my $workdir = "/bb/csdata/logs/source-scans";
    my $seekfile = "$workdir/seekinfo";

    my $seekinfo;

    my %basic_file_info = (
			    first_letter => '',
			    last_key => '',
			    next_key => '',
			    at_eof => 0,
			);

    my %fileinfo;

    sub init_1_file {
	my $name = shift;
	my $fullname = "$workdir/$name";

	# just in case we've got the new seekinfo before the new
	# data file has been moved in...
	sleep 1
	    if (stat $fullname)[9] != $seekinfo->{$name}{timestamp};

	# if it's still wrong, we're in real trouble
	my $timestamp = (stat $fullname)[9];
	die "wrong timestamp on $fullname, expected $seekinfo->{$name}{timestamp}, found $timestamp"
	    if $timestamp != $seekinfo->{$name}{timestamp};

	open my $fd, "<", $fullname
	    or die "failed open of $fullname ($!)";

	# if it changed before we got it open, we'll have to
	# start opening everything from scratch
	$timestamp = (stat $fullname)[9];
	# return
	    # if $timestamp < $seekinfo->{$name}{timestamp}
	    # || $timestamp > ($seekinfo->{$name}{timestamp}+10);
	return
	    if $timestamp != $seekinfo->{$name}{timestamp};
	return
	    $fileinfo{$name}
		= { %basic_file_info,
		    fd=> $fd,
		    seekposinfo => $seekinfo->{$name}{pos}
		};
    }

    sub init_files {
	use Storable;

	my $tries = 0;
	my $max_tries = 3;

	RETRY:
	{
	    my $ok = 1;
	    $seekinfo = retrieve( $seekfile );
	    if ($callers) {
		$ok = init_1_file( 'includes' );
		$included_extensions = $seekinfo->{includes}{exts}
		    if defined $seekinfo->{includes}
		       && defined $seekinfo->{includes}{exts}
		       && defined $seekinfo->{includes}{exts}{'.h'};
	    }
	    if ($ok) {
		$ok = init_1_file( 'files' );
	    }
	    unless ($ok) {
		redo RETRY if $tries++ < $max_tries;
		die "Too many retries, trying to open a synchronized set of workfiles";
	    }
	}
    }

    # we're asked to read the next line in the file that starts
    # with $key.  The file is sorted, and we have an index of
    # where in the file the first letter of a line changes to
    # each new value
    sub read_file {
	my( $key, $target ) = @_;
	my $first_letter = substr($target,0,1);
	my $fileinfo = $fileinfo{$key};
	my $fd = $fileinfo->{fd};

	my @lines;

	# Do we have to skip somewhere in the file?
	# If we're at a different initial letter, or else if we've
	# already passed the section within the current letter
	# Note that by keeping both last_key and next_key we don't
	# have to rescan the earlier portion of this letter if we
	# get a series of empty section requests.
	# e.g. if the file has fields x1 and x5, but we are asked
	# for each of x1, x2, x3, x4, and x5, we won't scan from
	# the start of x to the end of x1 for every one that isn't
	# there.
	if ($first_letter ne $fileinfo->{first_letter}
		|| $target lt $fileinfo->{last_key}) {
	    if (exists $fileinfo->{seekposinfo}{$first_letter}) {
		$fileinfo->{first_letter}
		    = $fileinfo->{last_key}
		    = $fileinfo->{next_key}
		    = $first_letter;
		$fileinfo->{at_eof} = 0;
		seek $fd, $fileinfo->{seekposinfo}{$first_letter}, 0;
	    }
	    else {
		# if the letter is not in the file, this $target has ended
		# before it starts
		return \@lines;
	    }
	}

	# nothing for this target if we've already reached end of file
	return \@lines
	    if $fileinfo->{at_eof};

	my $exttarget = "$target ";
	my $line = $fileinfo->{line};

	# Collect all of the lies that are in range
	my $next_key = $fileinfo->{next_key};
	my $last_key = $fileinfo->{last_key};

	LINE:
	while(1) {
	    # read on until we get to the start of the section
	    # (Note that next_key has no trailing blank if we've
	    # just done a seek, so we'll always need to read a line
	    # and will never accidentally try to use the previous
	    # line (that we've never read yet)).
	    next LINE if $exttarget gt $next_key;

	    # If at the end of section, save the line for the next section
	    if ($exttarget ne $next_key) {
		$fileinfo->{line} = $line;
		$fileinfo->{next_key} = $next_key;
		$fileinfo->{last_key} = $last_key;
		# The first letter might have changed
		$fileinfo->{first_letter} = substr($next_key,0,1);
		return \@lines;
	    }
	    # collect lines in the middle of the section
	    push @lines, $line;
	}
	continue {
	    unless( defined( $line = <$fd> ) ) {
		$fileinfo->{at_eof} = 1;
		return \@lines;
	    }
	    $last_key = $next_key;
	    # key is the leading field (including the terminating blank)
	    ($next_key) = $line =~ m{ ^ ([^ ]* [ ])}x;
	}
    }

    sub read_files {
	my $key = shift;
	my $list_ref = read_file( 'files', $key );

	return map { s/^\S+ //; chomp; $_ } @$list_ref;
    }
}

# %search_files is the key stucture here.
# It is indexed by the basename of files that are (to be) processed.
# $search_files{$base}                        is a hash
#                     {misses}{$path}         files with the base that
#                                             have never been processed
#                     {done}{$path}           files that have been processed
#                     {hits}{$path}           files that are to be processed
#                     {exact_hits}{$path}     files that are to be processed
#                     {trace}{$match}{$trace} when we process files looking
#                                             for $match, the traceback info
#                                             is $trace.  Usually, $match will
#                                             be the same as $base, but when
#                                             exact processing is going on, it
#                                             will have leading directories as
#                                             specified in the arglist.
my %search_files;

# $search_files is a list of the next batch of files to be processed
my $search_files = [ ];

{
    my $match_ref;
    my $match_key = '';

    my %already_printed;

    sub scan_for_callers {
	my ($key, $exact_key, $realfile, $cleanfile, $trace_back ) = @_;

	# The target might repeat if different full pathnames
	# were provided for the same filename, so we cache
	# the section that matches the filename part
	if ($key ne $match_key) {
	    $match_ref = read_file( 'includes', $key );
	    $match_key = $key;
	}

	if ($debug) {
	    print   "\t===>\tPotential callers:\n";
	    print   "\t===>\t\t$_\n" for @$match_ref;
	}

	# each line has 5 parts:
	#     incname callerfullpath callerusedpath incpath includeline
	my @fields = map { [ split / /, $_, 5 ] } @$match_ref;

	# exact_key has to match the entire included name
	# otherwise, the full requested name can be prefixed
	# with extra leading directories in the included filename
	if ($exact_key) {
	    @fields
		= grep { $_->[3] eq $exact_key } @fields;
	}
	else {
	    my $matclean = quotemeta $cleanfile;
	    @fields
		= grep {    my $incpath = $_->[3];
			    my $match_incpath = quotemeta $incpath;
			    $incpath eq $cleanfile
			    or $cleanfile =~ m{ / $match_incpath $ }x
			    # or $incpath eq "/$cleanfile"  # buggy Fortran fix
			    or $incpath =~ m{ / $matclean $ }x
		       } @fields;
	}

	if ($debug) {
	    print   "\t===>\tMatched callers:\n";
	    print   "\t===>\t\t@$_\n" for @fields;
	}

	# offer all of the including files for recursive scan
	unless ($single) {
	    add_target( $_->[2], $trace_back ) for @fields;
	}

	# discard printable names that we've already printed
	my $print_index = $generated ? 2 : 1;
	unless ($multipath) {
	    @fields = grep
		    { ! $already_printed{$_->[$print_index]}++ } @fields;
	}

	if ($concise) {
	    @fields = map { "$_->[$print_index]\n" } @fields;
	}
	else {
	    @fields =
		map { # my( $ifile, $cfull, $cused, $ipath, $incline ) = @$_;
		      my( $showfile, $incline ) = @{$_}[$print_index,4];
		      my( $dir, $path )
			    = $showfile
				=~ m{ /bbsrc\d*/ (.*) / (.*?) (,v)? $ }x;
		      $dir =~ s{/RCS$}{};
		      print STDERR "No dir found for $showfile\n"
			  unless length $dir;
		      "$dir:file $path:$incline"
		} @fields;
	}
	if ($trace) {
	    $_ .= "    include trace: $trace_back\n" for @fields;
	}
	return \@fields;
    }
}

my %missing_message = (
    callers	=> "    No match for %s being included anywhere.\n",
    defines	=> "    No file named %s was found.\n",
);

sub print_list {
    my ( $key, $item_ref, $name ) = @_;
    if( @$item_ref ) {
	print "    $key:\n";
	print "        $_" for sort @$item_ref;
    }
    elsif ( my $msg = $missing_message{$key} ) {
	printf $msg, $name;
    }
    print "\n";
}

# unless we get report-includes to pass us the exact list of
# derived files, we have to "just know" what they can be
my %generated_extensions = (
    '.gob'	=> [ qw( .c .h -protected.h ) ],
    '.ml'	=> [ qw( .ins .ins_h ) ],
    # add .gmm .y .l as needed
);

sub clean_path {
    my $path = shift;
    $path =~ s/,v$//;
    $path =~ s{ RCS/ ([^/]+) $}{$1}x;
    $path =~ s{^/bbsrc\d*/}{};
    $path =~ s{^proot/include/}{};
    return $path;
}

sub expand_generated {
    my $path = shift;
    my ($ext) = ($path =~ m{ ( (?: \.[^.]*)? ) $ }x);
    my @list = ($path );
    if (exists $generated_extensions{$ext}) {
	my $basepath = $path;
	my $extlen = length $ext;
	substr($basepath, -$extlen, $extlen, '');
	foreach my $g_ext ( @{ $generated_extensions{$ext} } ) {
	    push @list, "$basepath$g_ext";
	}
    }
    return @list;
}

sub add_target {
    my $orig_target = shift;
    my $target = clean_path($orig_target);
    my $not_first_time = shift || '';
    if ($debug) {
	print "\t===> add_target( $orig_target($target), $not_first_time)\n";
    }

    for my $path (expand_generated($target)) {
	my $trace_back = $path;
	$trace_back .= " (from $target)"
	    unless $target eq $path;
	$trace_back .= " -> $not_first_time" if $not_first_time;
	my ($base) = $path =~ m{ ( [^/]+ ) $ }x;
	my $match = $exact ? $path : $base;
	if ( ! exists $search_files{$base}) {
	    # first time for this $base
	    #    get the list of all files ending with $base
	    # if exact is turned on, some of them will later be moved
	    #    over to misses in exactify_search
	    $search_files{$base}{hits}{$base} = clean_path($base);
	    #    arrange for it to be processed
	    push @$search_files, $base;
	    # The command line can ask about include files that are
	    # not themselves scanned; so they don't show up in the
	    # files data but still are included bvy other files that
	    # are scanned, so they do show up in the include data.
	    # For these files, we don't have a complete pathname, but
	    # will still reject parent directories that were not noted
	    # in the command line argument. So, findinc foo.h will reject
	    # files that #include <sys/foo.h>.
	    $search_files{$base}{hits}{$base} = clean_path($base)
		if (! exists $search_files{$base}) && (! $not_first_time);
	}
	else {
	    # multiple files with the same basename can be ignored
	    # only warn for the parent of an expanded list, if it
	    # is a dup
	    # but warn for all children if the parent was *not* a dup
	    if (exists $search_files{$base}{exact}{$path} ) {
		warn "Rejecting duplicate: $orig_target, we're already handling $path\n";
		return if $target eq $path;
	    }
	    if (exists $search_files{$base}{misses}) {
		if (exists $search_files{$base}{hits}) {
		    while (my ($key,$value)
			    = each %{ $search_files{$base}{misses} } ) {
			$search_files{$base}{hits}{$key} ||= $value;
		    }
		}
		else {
		    push @$search_files, $base;
		    $search_files{$base}{hits} = $search_files{$base}{misses};
		}
		delete $search_files{$base}{misses};
	    }
	}
	$search_files{$base}{trace}{$match} = $trace_back;
    }
}

sub exactify_search {
    for my $base (@$search_files) {
	my $base_ref = $search_files{$base};
	my @match_pairs
	    = map {
		      [ $_, "/\Q$_" ]
		  }
	      sort {
		      length($b) <=> length($a)
		  }
	      keys %{ $base_ref->{trace} };
	FILELOOP:
	while (my ($key,$file) = each %{ $base_ref->{hits} }) {
	    foreach my $match_pair (@match_pairs) {
		if ($file eq $match_pair->[0]
			or $file =~ m{ $match_pair->[1] $ }x) {
		    $base_ref->{exact_hits}{$match_pair->[0]}{$key} = $file;
		    next FILELOOP;
		}
	    }
	    $base_ref->{misses}{$key} = $file;
	}
	delete $base_ref->{hits};
    }
}

sub scan_for_target {
    my( $key, $exact_key, $realfile, $cleanfile, $trace_back ) = @_;
    my $caller_details;
    my $caller_list;

    if ($debug) {
	print   "\t===> Scanning: $key",
		($exact_key ? "($exact_key)" : ''),
		"\n",
		"\t===>\t$realfile($cleanfile))",
		"\t===>\ttrace: $trace_back\n";
    }

    $caller_details =
	    scan_for_callers(
		    $key,
		    $exact_key,
		    $realfile,
		    $cleanfile,
		    $trace_back
		)
	if $callers;

    if ( $all ) {
	print "$key:\n";
	print_list( 'defines', [$realfile], $key );
	print_list( 'callers', $caller_details, $key );
    }
    elsif ($callers && @$caller_details) {
	print $_ for @$caller_details;
    }
    elsif ($defines) {
	print "$key $realfile\n";
    }
}

sub scan_target {
    my $key = shift;
    my $target_ref = $search_files{$key};

    if (exists $target_ref->{exact_hits}) {
	for my $match (sort keys %{ $target_ref->{exact_hits} }) {
	    for my $file (keys %{ $target_ref->{exact_hits}{$match} }) {
		scan_for_target(
			$key,
			$match,
			$file,
			$file,
			$target_ref->{trace}{$match}
		    );
		++$target_ref->{done}{$file};
	    }
	}
	delete $target_ref->{exact_hits};
    }
    if (exists $target_ref->{hits}) {
	for my $file (sort keys %{ $target_ref->{hits} }) {
	    scan_for_target(
		    $key,
		    '',
		    $file,
		    $target_ref->{hits}{$file},
		    $target_ref->{trace}{$key}
		);
	    ++$target_ref->{done}{$file};
	}
	delete $target_ref->{hits};
    }
}

#------------------------------------------------------------------------------

MAIN: {
    getoptions();
    init_files();

    for my $arg (@ARGV) {
	add_target( $arg );
    }

    if ($exact) {
	exactify_search();
	undef $exact;
    }

    while (scalar @$search_files) {
	my @this_search_files = sort @$search_files;
	$search_files = [ ];
	scan_target( $_ ) for @this_search_files;
    }
}
