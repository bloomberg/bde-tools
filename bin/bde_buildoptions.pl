#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::Util::Nomenclature qw(isComponent isPackage isGroup getPackageGroup);
use BDE::Util::DependencyCache; #temporary w.r.t. to What.pm, see below
use Build::Option::Finder;
use Build::Option::Factory;
use Symbols qw(EXIT_FAILURE EXIT_SUCCESS ROOT);
use Util::Message qw(fatal debug error warning);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

bde_buildoptions.pl - Generate build options for a given UPLID and UFID.

=head1 SYNOPSIS

    $ bde_buildoptions.pl bde > Makefile.vars

    $ bde_buildoptions.pl -u unix-SunOS-sparc-gcc-3.4.2 -t dbg_mt \
        -p BTEMT_DBG_MT_ btemt > btemt.dbg_mt.vars

=head1 DESCRIPTION

C<bde_buildoptions.pl> is a command-line interface to the build options
subsystem used by L<bde_build.pl>. It can be used to extract the configured
build options for use in alternate build systems, or examine the configured
options directly without invoking L<bde_build.pl>.

Given a package group, package, or component argument, C<bde_buildoptions.pl>
will print to standard output the build options that are applicable to the
specified platform ID (a.k.a. I<UPLID>) and build target ID (a.k.a. I<UFID>).

The unit argument (defining what options are to be generated for) is
mandatory. The UPLID and UFID are optipnal, and default to the current platform
ID (as returned by L<bde_uplid.pl>) and C<dbg_exc_mt> respectively.

By default, all options that are present are extracted and printed to standard
output without expansion (i.e. including macros) and with each option value
prefixed by its name and an equals sign, in the manner of a makefile macro
definition. Additional command-line arguments may be specified to expand the
option values or to restrict the options printed to a specified list.

=head2 Expanding values

If the C<--expand> or C<-x> option is specified, build options are expanded
with all option references in their value replaced with their (also
expanded) values.

=head2 Extracting Specific Options by Name

To generate output for a selected list of options, rather than all options
defined, use the C<--option> or C<-o> option. This option can be specified
multiple times, and can also take a comma-separated list of option names.

If just one build option is specified to C<-o>, then the returned option
value is returned naked, without a preceeding name or equals sign.

If more than one build option is specified to C<-o>, either by repeating
the use of C<-o> or using a comma to separate the option names, then each
returned value is prefixed with its name and an equals sign.

=head2 Generating "Raw" Diagnostic Output for Referred-to Options

To generate the output for the options referred to by other options specified
via the C<--option> or C<-o> option, use the S<C<--diagnostic>> or C<-r>
option.  This option provides the "context" for the options selected.
The output for the referred to options follows the output for the options
specified via the C<--option> or C<-o> option,

=head2 Prefixes

An optional C<--prefix> argument extends all build options returned with
the specified prefix, and also expands any reference to the same options to
also include the prefix.

Use of this argument allows the same options to be generated for different
packages or package group. The generated options can later be combined
into the same makefile (for example) without conficting, as the prefixes
prevent names from colliding. As only references that correspond to
defined options are expanded, options that refer to environmental
settings outside the configured build options will still refer to those
settings after the prefix has been applied.

=head1 TO DO

Add a C<--compiler> option in line with the option in L<bde_build.pl>.

Add 'default' options capability.

Allow an explicit subset of specified build variables to be queried.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-p <prefix>] [-t <ufid>] [-u <ufid>] [-w <root>] [-r]
                           [-o name,name [-o name]] [-d[d]] [-v[v]] [-x]
                           <group|package|component>
  --compiler   | -c  <comp>   compiler name (default: 'def')
  --debug      | -d           enable debug reporting
  --expand     | -x           fully expand variables in values
  --help       | -h           usage information (this text)
  --option     | -o           display the specified option(s) only,
                              may be specified multiple times
  --prefix     | -p <prefix>  prefix output variables
  --diagnostic | -r           'raw' diagnostic output which lists the
                              specified options first followed by the
                              referred-to options
  --target     | -t <ufid>    build target <target> (default: 'dbg_exc_mt')
  --uplid      | -u <uplid>   target platform (default: from host)
  --verbose    | -v           enable verbose reporting
  --where      | -w <dir>     specify explicit alternate root (default: .)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
	compiler|c=s
        debug|d+
        diagnostic|r
        expand|x
        help|h
        option|o=s@
        prefix|p=s
	target|t=s
        uplid|platform|u=s
        where|w=s
        verbose|v+
    ])) {
        usage("Arfle Barfle Gloop?");
        exit EXIT_FAILURE;
    }

    # no arguments
    usage("Nothing to do"), exit EXIT_FAILURE if @ARGV < 1;

    # too many arguments
    usage("Specify only one group or package argument"), exit EXIT_FAILURE
      if @ARGV > 1;

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # filesystem root
    $opts{where} = ROOT unless $opts{where};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # prefix
    $opts{prefix} ||= "";

    # options
    $opts{option}=[] unless defined $opts{option};
    my @options=();
    foreach my $optstr (@{$opts{option}}) {
	push @options, split /,/,$optstr;
    }
    $opts{option}=\@options;

    # UFID
    $opts{target} = "dbg_exc_mt" unless $opts{target};

    # UPLID
    if ($opts{uplid}) {
	fatal "--uplid and --compiler are mutually exclusive"
	  if $opts{compiler};
	$opts{uplid} = BDE::Build::Uplid->unexpanded($opts{uplid});
    } elsif ($opts{compiler}) {
	$opts{uplid} = BDE::Build::Uplid->new({ compiler=>$opts{compiler},
						 where   =>$opts{where}
					      });
    } else {
	$opts{uplid} = BDE::Build::Uplid->new({
						 where   =>$opts{where}
					      });
    }

    return \%opts;
}

#------------------------------------------------------------------------------

MAIN {
    my $opts=getoptions();

    my $unit=shift @ARGV;

    fatal ("$unit is not a valid group, package, or component name")
      unless isGroup($unit) or isPackage($unit) or isComponent($unit);

    my $uplid=$opts->{uplid};
    fatal "Bad uplid: $opts->{uplid}" unless defined $uplid;
    debug "Using UPLID $uplid";

    my $ufid=new BDE::Build::Ufid($opts->{target});
    fatal "Bad ufid: $opts->{target}" unless defined $ufid;
    debug "Using UFID $ufid";

    my $finder=new Build::Option::Finder($opts->{where});
    # temporary until dependency cache use in What.pm is
    # resolved more elegantly w.r.t origin of filesystem root.
    BDE::Util::DependencyCache::setFileSystemRoot($finder);
    debug "Using root $finder";

    my $factory=new Build::Option::Factory($finder);
    my $options;
    my $vars;

    if ($opts->{diagnostic}) {
	$factory->load($unit);
	$options=$factory->getValueSet();

	my @opts;

	if (@{$opts->{option}}) {
	    @opts = map { $options->getValue($_) } @{$opts->{option}};

	    if ($opts->{expand}) {
		my %refVars = map { $_ => 0 } @opts;

		foreach my $optValue (@opts) {
		    foreach my $item ($optValue->getValueItems) {
			my @varsInStr = (($item->getValue) =~ m/\$\(([^)]+)\)/g);
			foreach (@varsInStr) {
			    $refVars{$_}=1 unless exists $refVars{$_};
			}
		    }
		}

		foreach my $refOpt (keys %refVars) {
		    next unless $refVars{$refOpt};

		    my $option=$options->getValue($refOpt);
		    if (defined $option) {
			push @opts,$option;
		    } else {
			warning "referred option [$refOpt] does not exist in the option set";
		    }
		}
	    }
	} else {
	    @opts=$options->getValues();
	}

	foreach my $option (@opts) {
	    $vars .= $option->dump();
	}
    } else {
	$options=$factory->construct({
            uplid => $uplid,
            ufid  => $ufid,
            what  => $unit,
            derive=> 1,
        });

	if (@{ $opts->{option} }) {
	    my @vars;
	    foreach my $name (@{ $opts->{option} }) {
		if (my $option=$options->getValue($name)) {
		    push @vars, $opts->{expand}
                      ? (@{$opts->{option}}>1 ? $option->getName.'=' : '' )
		        .$options->expandValue($option)
		      : (@{$opts->{option}}>1 ? $option->getName.'=' : '' )
		        .$option->getValue($opts->{prefix});
		}
	    }
	    $vars = join("\n",@vars)."\n";
	} else {
	    $vars = $opts->{expand}
	      ? $options->expandValues($opts->{prefix})
	      : $options->render($opts->{prefix});
	}

	# ::GROUP:: expansion
	my %expansion = (
            group   => (getPackageGroup($unit) || $unit),
            package => (isPackage($unit) ? $unit : "NOT_A_PACKAGE"),
	);
	$vars =~ s/::([A-Z]+)::/uc($expansion{lc($1)})/ge;

    }

    print $vars;

    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_build.pl>, L<Build::Options::Factory>, L<Build::Options::Finder>

=cut
