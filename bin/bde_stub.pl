#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Component;
use BDE::FileSystem;
use BDE::Util::DependencyCache qw(
    getCachedComponent getCachedPackage getAllInternalComponentDependencies
);
use BDE::Util::Nomenclature qw(
    getType isGroup isPackage isComponent
);
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::Build::Invocation qw($FS);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
);
use Util::Message qw(fatal error alert message debug);
use Util::File::Basename qw(basename);

#==============================================================================

=head1 NAME

bde_stub.pl - Create stub functions to isolate test drivers

=head1 SYNOPSIS

    # generate stubs for one component, write stubs to standard output
    $ bde_stub.pl f_ykmnem_entry

    # generate stubs for a whole package, write stubs to files, with bookends
    $ bde_stub.pl -C -s f_ykmnem

=head1 DESCRIPTION

C<bde_stub.pl> is a tool to generate 'stub' functions for unresolved external
C language dependencies. It can be used to provide the required symbols for
test drivers to link and run without requiring external linkage beyond C++
libraries. This in turn allows test drivers to carry out unit testing of their
components. Developers may subsequently choose to expand the stubs to provide
test values for test cases, if desired.

For C<bde_stub.pl> to function, it must be able to access pre-built objects for
the components to be stubbed. Typically this can be achieved by running
C<bde_build.pl -e> for the component or package in question first. If using
L<bde_build.pl> with a different build type (e.g. 'dbg_mt') the same type
should be supplied to c<bde_stub.pl> with C<-t> or C<--target> so that it will
locate the generated object files correctly. I<(Similarly, The C<-p> or
C<--platform> option can be used to change the location where the objects are
looked for; this should never be necessary in practice.)>

If run on a component, C<bde_stub.pl> will output the stubs for that component
and all components in the same package on which it depends (all of which must
be satisfied for the test driver to link and run).  If run on a package,
C<bde_stub.pl> will output stubs for all the components in the package. More
than one component or package may be supplied as arguments in which case the
tool will generate stubs for all requested source units.

With the C<-s> or C<--stubfiles> option, C<bde_stub.pl> will output the stubs
into a files named for each component with an extension of '.stubs'. This file
may be embedded into the comonent's test driver between 'extern "C"' bookends.
If desired, the C<-C> or C<--externc> option may be used to automatically
indent the stubs and add the bookends to the output. Note that it is illegal
to simply include this file from a test driver; it must be embedded.

The output of C<bde_stub.pl> is not guaranteed to be 100% correct, but it is
accurate enough to allow developers to get most dependencies resolved
correctly. Note that some symbols (typically from the standard C library) may
be identified as unresolved but do not in fact require stubbing. In this case
simply remove the stubs in question.

If a component has no unresolved dependencies, no stubs will be generated.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-w <root>] [-X] <component>|<package>
  --debug      | -d           enable debug reporting
  --externc    | -C           include 'extern "C"' bookends
  --help       | -h           usage information (this text)
  --keeptmps   | -k           retain temporary files rather than deleting them
  --platform   | -p           target platform (default: from host)
  --stubfiles  | -s           write out results to .stubs files (otherwise to
                              standard output)
  --target     | -t           target ufid (default: dbg_exc_mt)
  --where      | -w <dir>     specify explicit alternate root
  --noretry    | -X           disable retry semantics on file operations

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        externc|C
        help|h
        keeptmps|k
	ufid|target|t=s
        uplid|platform|p|u=s
        stubfiles|s
        where|root|w|r=s
        noretry|X
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV != 1;

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

sub getComponentsOf ($) {
    my $item=shift;

    my @components=();

    if (isGroup($item)) {
	alert("Checking group $item...");
	foreach my $pkg (getCachedGroup($item)->getMembers()) {
	    push @components,getCachedPackage($pkg)->getMembers();
	}
    } elsif (isPackage($item)) {
	alert("Checking package $item...");
	push @components,getCachedPackage($item)->getMembers();
    } elsif (isComponent($item)) {
	alert("Checking component $item...");
	push @components,$item;
    }

    return wantarray ? @components : \@components;
}

#------------------------------------------------------------------------------

sub generateStubs ($$$$$) {
    my ($root,$component,$uplid,$ufid,$keeptmps)=@_;

    # extract the list of dependent objects
    $component=getCachedComponent($component);
    my $locn=$root->getComponentLocation($component);
    my @components=getAllInternalComponentDependencies($component);
    my @objects=map {
	$locn.$FS.$uplid.$FS.$_.".".$ufid.".o";
    } ($component,@components);

    debug "$component requires @components";
    debug "$component objects: @objects\n";

    # check that they all exist
    my $package=$component->getPackage();
    foreach (@objects) {
	fatal "$_ is missing: unable to generate stubs for $component\n".
	      "(is $package library built yet?)" unless -f $_;
    }

    # Find undefined symbols
    my $command2=qq{nm -C -p -u -h @objects | grep -v '\\[' | sed 's/^  */||/' | sort -u -t "|" -k 3 > $locn${FS}$component.usym};
    my $c2rc=system($command2);
    fatal "Undefined nm '$command2' failed: $!" if $c2rc;

    my $size=(stat "$locn${FS}$component.usym")[7];
    if ($size == 0) {
	alert "$component has no undefined symbols";
	return "// $component has no undefined symbols\n";
    }

    # find global symbols
    my $command1=qq{nm -C -p -g -h @objects | grep -v '\\[' | sed 's/ /|/' | sed 's/ /|/' | grep -v '|U|' | sort -u -t "|" -k 3 > $locn${FS}$component.gsym};
    my $c1rc=system($command1);
    fatal "Global nm '$command1' failed: $!" if $c1rc;

    # Join the two
    my $command3=qq{join -t '|' -j 3 -v 2 -o 0 $locn${FS}$component.gsym $locn${FS}$component.usym};
    my $result=`$command3`;
    fatal "Merge command '$command3' failed: $!" unless $result;

    # Pare down the results
    $result =~ s/^.*::.*$//mg; #remove 'type Namespace::foo' (C++)
    $result =~ s/^__.*$//mg;         #remove __symbols
    $result =~ s/void[ *]operator.*$//mg; #misc

    # the ususal Standard C library suspects
    $result =~ s/^(
      | abs
      | [sf]?printf
      | strn?(cpy|len|cmp)
      | mem(cpy|move|set|cmp)
    )$//mxg;

    unless ($keeptmps) {
	unlink "$locn${FS}$component.gsym";
	unlink "$locn${FS}$component.usym";
    }

    # Blank lines
    $result =~ s/\n{2,}/\n/sg;
    $result =~ s/^\n//s;

    if ($result=~/^\s*$/) {
	alert "all $component symbols resolved by package";
	return "// all external $component symbols resolved in package\n";
    }

    # Stub the remainder
    $result =~ s/^(.*)$/void $1() {}/mg;

    return $result;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $root=new BDE::FileSystem($opts->{where});
    BDE::Util::DependencyCache::setFileSystemRoot($root); #for components

    my $ufid=new BDE::Build::Ufid($opts->{ufid} || "dbg_exc_mt");
    my $uplid=(exists $opts->{uplid})
      ? BDE::Build::Uplid->fromString($opts->{uplid})
      : BDE::Build::Uplid->new();

    foreach my $item (@ARGV) {
	my $type=getType($item);
	fatal("Not a valid item: '$item'") unless $type;

	my @components=getComponentsOf($item);
	fatal("No components for '$item'") unless @components;

	foreach my $component (@components) {
	    message("Generating stubs for $component...");
	    my $stubs=generateStubs($root,$component,$uplid,$ufid,
				   $opts->{keeptmps});

	    if ($opts->{externc}) {
		$stubs=~s/^/    /mg;
		$stubs=qq[// stubs for $component\nextern "C" \{\n].
		  $stubs.qq[}\n];
	    }

	    if ($opts->{stubfiles}) {
		my $stubfile = $root->getComponentLocation($component).
		               $FS.$component.".stubs";
		my $fh=new IO::File "> $stubfile";
		fatal "Error opening $stubfile: $!" unless defined $fh;
		print $fh $stubs or fatal "Error writing to $stubfile: $!";
		close $fh or fatal "Error closing $stubfile: $!";
	    } else {
		print $stubs;
	    }
	}
    }

    alert "Done";
    exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_build.pl>, L<bde_verify.pl>

=cut
