#!/usr/local/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Cwd;

use bde_build;
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::Build::Options;
use Util::Message qw(error fatal debug set_debug get_debug);
use Util::File::Basename qw(basename);

#------------------------------------------------------------------------------

my $prog = basename $0;

# prototypes
sub usage();
sub process_prefix_macros($$@);

#------------------------------------------------------------------------------

# parse & check the options
my %opts;
Getopt::Long::Configure("bundling");
unless (GetOptions(\%opts,qw[
    debug|d
    help|h
    options|f=s
    only-value|o
    post-file|pf=s@
    service-vars|x
    show-nufid|n
    show-xnufid|N
    skip-empty|s
    uplid|p=s
    ufid|t=s
    initial|i:s
    location|l=s
    all|a
])) {
    usage();
    exit 1;
}

usage if $opts{help};
set_debug($opts{debug});
my $show_all    = $opts{all};
my $output_xtra = $opts{"service-vars"};
my $skip_blanks = $opts{"skip-empty"};
my $show_nufid  = $opts{"show-nufid"} || $opts{"show-xnufid"};
my $keep_hidden = 1 if $opts{"show-xnufid"};
my $only_value  = $opts{"only-value"};
my @post_files   = @{$opts{"post-file"} || []};
my $location    = $opts{"location"} || "$FindBin::Bin/../etc/default.opts";
my $prefix      = $opts{"initial"};

#----

push @post_files,$ENV{BDE_USER_OPT_FILE} if $ENV{BDE_USER_OPT_FILE};

#----

# get the UFID
my $ufid;
if ($opts{ufid}) {
    $ufid=new BDE::Build::Ufid($opts{ufid});
} elsif (@ARGV) {
    $ufid=new BDE::Build::Ufid(shift @ARGV);
} else {
    error("Must specify a value for UFID");
    usage();
    exit 1;
}

# -n mode: just print a normalized UFID
if ($show_nufid) {
    if ($output_xtra || $show_all || $only_value) {
	error("-n is not compatible with -a, -o, or -x");
	usage();
	exit 1;
    }

    print $ufid->toString($keep_hidden) . "\n";
    exit 0;
}

#----

# get the UPLID
my $uplid=(exists $opts{uplid})
  ? BDE::Build::Uplid->fromString($opts{uplid})
  : BDE::Build::Uplid->new();

# no vars specified, show all that we can find
$show_all = 1 if !$output_xtra && !$show_nufid && !@ARGV;

#-o mode: only one variable allowed
if ($only_value) {
    if (scalar(@ARGV) !=1)  {
	error("Specify only one variable with -o option");
	usage();
	exit 1;
    } elsif ($output_xtra || $show_all || $prefix) {
	error("-o is not compatible with -a, -i, or -x");
	usage();
	exit 1;
    }
}

# set the prefix from the NUFID if -i specified without parameter
$prefix=uc($ufid).'_' if defined($prefix) and not $prefix;
$prefix="" unless defined($prefix);

#----

my $def_opt_file = $opts{options}?$opts{options}:"default.opts";
if ($def_opt_file !~ m[^(\w:)?(/|\\)] ) {
    $def_opt_file = "$FindBin::Bin/../etc/".$def_opt_file;
    1 while $def_opt_file =~ s|/[^/]+/\.\./|/|;
}

#----

my $options=new BDE::Build::Options({
    ufid    => $ufid,
    uplid   => $uplid,
    from    => $location
});

foreach (@post_files) {
    debug "about to process file '$_'";

    $options->processOptionFile($_) ||
	fatal "failed to process '$_'";
}

#----

if ($only_value) {
    my $value=$options->getOption($ARGV[0]);
    $value=$options->processPrefixMacros($value,$prefix) if $prefix;
    print $value,"\n";
} else {
    print $options->toString({
        prefix => $prefix,
        skip   => $skip_blanks,
        extra  => $output_xtra
    });
}

exit 0;

#--------------------------------------------------------------------------------

sub usage() {
    print "Usage: $prog [-x] [-s] [-p] <ufid> [-a | <variables>]\n";
    print "       $prog -n [-u] <ufid>\n";
    print "Or:    $prog -t <ufid> [-x] [-s] [-p] [-a | <variables>]\n";
    print "       $prog -t <ufid> -n [-u]\n";
    print "\n";

    print "$prog computes values for all variables specified using the
'options' file on each level of the design (from the current level up to the
top. Values on lower levels override (are appended to) values on upper levels.
The first options file read is the \"default\" file. It is expected in
$def_opt_file (but can be overriden by
'BDE_DEF_OPT_FILE' environment variable).

Each record in the 'options' file is a combination of the following fields:
* optional override indicator: '!' or '!!' (see below)
* UPLID (Unified PLatform ID) pattern. The record will not match if current
  host's UPLID doesn't match this pattern (as defined by 'uplid -m').
* UFID (Unified Flag ID) set. The record will not match if the specified UFID
  contains flags that are *not* set in the UFID specified in the command line.
* variable name. Obviously only records with variables specified in the command
  line would match (matching is case-insensitive).
* variable value - this is what will be appended to (or replaces ) the
  accumulated value in case the record matches.

When the record matches, the action depends on the type of the override
indicator ('!', '!!', or nothing):
* With no indicator, the value is *appended* to that accumulated so far.
* If '!' is specified, the value is *set* to the value derived from the
  'default' options file.
* If '!!' is specified, the value *replaces* that accumulated so far.

The following generic options are supported:
    --debug        | -d          enablle debug mode
    --help         | -h | -?     show help (this screen)
    --ufid         | -t          required target ID (a.k.a unified flag); if not
                                 specified, taken from the first parameter value

The following options apply to Variable Extraction mode only:
    --all          | -a          output all available applicable variables.
                                 (default, if no variables, -n or -x specified)
    --initial      | -i [<str>]  prefix variables with an optional string. If
                                 none is supplied, the NUFID is used.
    --location     | -l <dir>    look for option files from this directory
                                 (default: current working directory)
    --only-value   | -o          for one variable only, return just the value
                                 rather than variable = value.
    --options      | -f <file>   override default options file entirely
    --post-file    | -pf <file>  append an additional options file to the chain
                                 of files automatically detected by $prog.
    --service-vars | -x          output service variables that are used
                                 by build environment (see below)
    --skip-empty   | -s          suppress output of variables with empty values
    --uplid        | -p <uplid>  specify rather than derive platform UPLID

The following options apply to Normalize NUFID mode only:
    --show-nufid   | -n          print the specified UFID in normalized form only
                                 (does not compute or output variables)
    --show-xnufid  | -N          print the speficied UFID in normalised form only
                                 including normally hidden parts (e.g. 'shr')

Option '--service-vars' outputs the following additional variables:
* NUFID: specified UFID in 'normalized form' which uniquely defines the flags.
* BDE_BUILD_CFLAGS: set of cpp-style flags with platform/target-specific defines.
";

    print "\n";
    exit 0;
}

#--------------------------------------------------------------------------------
