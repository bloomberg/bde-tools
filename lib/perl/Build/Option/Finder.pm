package Build::Option::Finder;
use strict;

use base 'BDE::FileSystem';

use Util::Message qw(verbose verbose2 fatal);
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::Nomenclature qw(
    isGroup isPackage isGroupedPackage isIsolatedPackage isComponent
);

use BDE::Util::DependencyCache qw(getAllGroupDependencies getBuildOrder);

use Symbols qw[
    GROUP_META_SUBDIR PACKAGE_META_SUBDIR DEFAULT_OPTFILE DEFAULT_OPTFILE_INTERNAL
    OPTFILE_EXTENSION CAPFILE_EXTENSION DEFFILE_EXTENSION
];

#==============================================================================

=head1 NAME

Build::Option::Finder - Locate options files in multi-rooting filesystem

=head1 SYNOPSIS

    my $optroot=new Build::Option::Root("/local/root");

    my @default_optss=$optroot->getDefaultOptionFiles();
    my @btemt_opts=$optroot->getOptionFiles("btemt");

=head1 DESCRIPTION

This module implements a subclass of L<BDE::FileSystem> that locates options
files for a requested group or package.

Option files are looked for in the closest location of a given group or package
only, as determined by the configured local root and search path. Specifically,
group and package options files are not scanned for in the search path if they do not exist in the closest location. Additionally, options files do not
accumulate across the search path; once a given option file is found it is not
then combined with any other versions located in more distant roots on the
search path.

The default options file C<default.opts> is separately scanned for in all
configured roots, starting with the local root. It is therefore not necessary
to provide a local C<default.opts> (unless an override is intended).

=cut

#==============================================================================

sub identify ($$) {
    my ($self,$what)=@_;

    my ($cmp,$pkg,$grp)=(undef,undef,undef);

    if (isComponent $what) {
	$cmp=$what;
	$what=$self->getComponentPackage($what);
    }

    if (isPackage $what) {
	$pkg=$what;
	if (isGroupedPackage $what) {
	    $what=$self->getPackageGroup($what);
	}
    }

    if (isGroup $what) {
	$grp=$what;
    }

    return ($grp,$pkg,$cmp);
}

{
    my %seen=(); #shared between all instances, this hash records the results
                  #of the actual filesystem scans, for efficiency. See also
                  #%VS_INC in Build::Option::Factory

    sub noFile ($$) {
	my ($self,$what)=@_;

	$seen{$what}=undef; #log this file as unfindable
    }

    ## "what" and "where" are "hash key" and "path", although they look similar
    ## Their differences are related to "what" needing to be a unique hash key
    ## and "where" being the path to the metadata file.
    sub haveFile ($$;$) {
	my ($self,$what,$where,$final)=@_;

	return $seen{$what} if exists $seen{$what};

	my $verbose = Util::Message::get_verbose();
	if (-f $where) {
	    verbose2 "Found $what options at $where"
	      if ($verbose >= 2);
	    $seen{$what}=$where;
	} else {
	    verbose2 "Did not find $what options at $where"
	      if ($verbose >= 2);
	    $self->noFile($what) if $final;
	    return undef;
	}

	return $seen{$what};
    }

    sub clearFileCache ($) { %seen=(); }
}

#------------------------------------------------------------------------------

# don't much like this name. Rebrand?
sub getGoPOptionFiles ($$) {
    my ($self,$what)=@_;

    my @files=();

    my ($grp,$pkg,$cmp)=$self->identify($what);
    my $gop=$grp || $pkg;

    my $gop_locn=$grp ? $self->getGroupLocation($grp)
                  : $self->getPackageLocation($pkg);

    # caps and defs of units on which we depend
    my @capdef_files=$self->getGoPCapDefFiles($what);
    if (scalar @capdef_files) {
	push @files,@capdef_files;
    }

    # our own caps and defs, if present
    my ($gop_defs,$gop_caps);
    my $base = substr($gop,rindex($gop,'/')+1); # basename
    if ($grp) {
	$gop_caps=$gop_locn.$FS.GROUP_META_SUBDIR.$FS.$base.CAPFILE_EXTENSION;
	$gop_defs=$gop_locn.$FS.GROUP_META_SUBDIR.$FS.$base.DEFFILE_EXTENSION;
    } else {
	$gop_caps=$gop_locn.$FS.PACKAGE_META_SUBDIR.$FS.$base.CAPFILE_EXTENSION;
	$gop_defs=$gop_locn.$FS.PACKAGE_META_SUBDIR.$FS.$base.DEFFILE_EXTENSION;
    }

    if (my $cap=$self->haveFile($gop.CAPFILE_EXTENSION()
				=> $gop_caps, 'final')) {
	push @files,$cap;
    }
    if (my $def=$self->haveFile($gop.DEFFILE_EXTENSION()
				=> $gop_defs, 'final')) {
	push @files,$def;
    }

    if ($grp) {
	# group options
	$base = substr($grp,rindex($grp,'/')+1); # basename
	my $grp_opts=$gop_locn.$FS.GROUP_META_SUBDIR.$FS.
	  $base.OPTFILE_EXTENSION;
	if (my $file=$self->haveFile($grp.OPTFILE_EXTENSION()
				     => $grp_opts, 'final')) {
	    push @files,$file;
	}

	# grouped package options
	if ($pkg) {
	    $base = substr($pkg,rindex($pkg,'/')+1); # basename
	    my $pkg_locn=$self->getPackageLocation($pkg);
	    my $pkg_opts=$pkg_locn.$FS.PACKAGE_META_SUBDIR.$FS.
	      $base.OPTFILE_EXTENSION;
	    if (my $file=$self->haveFile($pkg.OPTFILE_EXTENSION()
					 => $pkg_opts, 'final')) {
		push @files,$file;
	    }
	}
    } else {
	# isolated package options
	$base = substr($pkg,rindex($pkg,'/')+1); # basename
	my $pkg_opts=$gop_locn.$FS.PACKAGE_META_SUBDIR.$FS.
	  $base.OPTFILE_EXTENSION;
	if (my $file=$self->haveFile($pkg.OPTFILE_EXTENSION()
				     => $pkg_opts, 'final')) {
	    push @files,$file;
	}
    }

    return @files;
}

=head2 getGoPCapDefFiles($what)

Return the capability and definition files of the specified unit of release,
by deriving the list of dependent units of release and scanning for them.

=cut

sub getGoPCapDefFiles ($$) {
    my ($self,$what)=@_;

    # propagate to unit of release name (the 'GOP')
    $what=$self->getComponentPackage($what) || $what;
    $what=$self->getPackageGroup($what) || $what;

    # get files in correct dependency order (gAGD also works for isolated pkgs)
    my @deps=getBuildOrder(getAllGroupDependencies($what));

    my @files=();
    foreach my $dep (@deps) {
	my $ispkg=isPackage($dep); #can only be group or islated pkg as a dep
	my $locn=$ispkg
	  ? $self->getPackageLocation($dep)
	    : $self->getGroupLocation($dep);

	my $basename=$locn.$FS.($ispkg?PACKAGE_META_SUBDIR:GROUP_META_SUBDIR)
		    .$FS.substr($dep,rindex($dep,'/')+1); # basename

	if (my $def=$self->haveFile($dep.DEFFILE_EXTENSION()
				    => $basename.DEFFILE_EXTENSION, 'final')) {
	    push @files,$def;
	}
	if (my $cap=$self->haveFile($dep.CAPFILE_EXTENSION()
				    => $basename.CAPFILE_EXTENSION, 'final')) {
	    push @files,$cap;
	}
    }

    return @files;
}

=head2 getOptionFiles($what)

Return the default options file, as searched for in the local root and the
search path. An exception is thrown if no default option file can be found.
Note that the search mode does I<not> constrain this search.

=cut

sub getDefaultOptionFiles ($) {
    my $self=shift;

    my @etcs=$self->getEtcLocations();

    my $found_default = undef;
    my $found_internal = undef;
    my $file = undef;

    foreach my $etc_locn (@etcs) {

        $file=$etc_locn.$FS.DEFAULT_OPTFILE;
        if (!$found_default && $self->haveFile(DEFAULT_OPTFILE() => $file)) {

            $found_default=$file;
        }

        $file=$etc_locn.$FS.DEFAULT_OPTFILE_INTERNAL;
        if (!$found_internal && $self->haveFile(DEFAULT_OPTFILE_INTERNAL() => $file)) {
            $found_internal=$file;
        }

        if ($found_default && $found_internal) {
            last;
        }
    }

    if (!$found_default) {
        $self->noFile(DEFAULT_OPTFILE);
        # a default.opts is mandatory.
        $self->throw("Unable to locate ${\DEFAULT_OPTFILE} in @etcs");
    }

    my @files = ($found_default);
    if ($found_internal) {
        push @files, $found_internal
    }

    return @files
}

=head2 getOptionFiles($what)

Return the option, capability, and definition files for the given group,
package, or component. The default options file is always returned as the
first file in the list. An exception is thrown if no default option file can
be found.

Since this method does not take into account dependencies, defintion files for
units of release on which the requested item depends are I<not> returned by
this method; see L<"getDefinitionFiles"> below.

=cut

sub getOptionFiles ($$) {
    my ($self,$what)=@_;

    my @files=$self->getDefaultOptionFiles;
    push @files, ($self->getGoPOptionFiles($what));

    return @files;
}

#==============================================================================

sub test (;@) {
    eval { use Symbols qw(ROOT); 1; };

    my @tests=@_;
    @tests=(qw[bde bce bces btemt a_bdema e_ipc l_ipc m_bdeoffline])
      unless @tests;

    $|=1;

    my $root=new Build::Option::Finder(ROOT);
    print "Root: $root\n";
    foreach my $i (1..2) {
	print "Iteration $i\n";
	foreach my $unit (@tests) {
	    print "  $unit => @{[ $root->getOptionFiles($unit) ]}\n";
	}
    }
}

#==============================================================================

1;
