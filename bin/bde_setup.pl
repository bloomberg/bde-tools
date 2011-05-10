#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use File::Path;
use Getopt::Long;

use BDE::Build::Invocation qw($FS);
use BDE::Util::Nomenclature qw(
    getType getTypeName getTypeDir getPackageGroup getComponentPackage
    isGroup isPackage isComponent isIsolatedPackage isApplication
);
use Symbols qw(
    /^IS_/ DEFAULT_FILESYSTEM_ROOT EXIT_FAILURE EXIT_SUCCESS
    GROUP_META_SUBDIR PACKAGE_META_SUBDIR INDEX_DIR
    MEMFILE_EXTENSION DEPFILE_EXTENSION OPTFILE_EXTENSION
);
use Util::File::Basename qw(basename);
use Util::Message qw(alert message verbose error fatal);

#==============================================================================

=head1 NAME

bde_setup.pl - Set up BDE root and source directory structures

=head1 SYNOPSIS

  # set up new root, default location
  $ bde_setup.pl

  # set up new root, explicit location
  $ bde_setup.pl -w /home/mylogin/put/root/here

  # set up new root, existing BDE_ROOT
  $ BDE_ROOT=/home/mylogin/somewhere/else bde_setup.pl

  # set up root, create department library and function layout
  $ bde_setup.pl l_dpt f_xxmyfn

=head1 DESCRIPTION

C<bde_setup.pl> creates a BDE root directory structure in the specified
location. If no explicit directory is specified, the value of C<$BDE_ROOT> is
used if defined, otherwise a default location of C<$HOME/bderoot> is used, if
C<$HOME> is defined by the environment. If the root already exists, it will be
checked and any missing subdirectories created.

With one or more package group or package arguments C<bde_setup.pl> will create
the root directory structure if it does not already exist and then create a
skeleton structure for the specified units. New grouped packages may be added
to package groups if and only if that group already exists.

For each unit, C<bde_setup.pl> will ask for the members and dependencies, which
may be separated by any non-word characters (i.e. commas, spaces). Relevant
defaults are suggested where practicable. Component names may be specified with
the package prefix plus underscore ommitted to save typing. If either the
members or dependencies files already exist they will be left alone -- new
packages and component files may be added through C<bde_setup.pl> but users are
responsible for updating the members and dependencies themselves.

If the C<--noroot> or C<-N> option is used, C<bde_setup.pl> will use an
existing root if it is present but will not attempt to create one if not. It
will still create unit subdirectory structures if any release units are
specified.

=head1 TO DO

Currently, component are created as empty files. A minimal but valid skeleton
will replace these in future.

Adding new packages or components to an existing group or package will add
the files but not modify existing membership files. In future, the membership
files will be adjusted when additions are made.

=head1 BUGS

Specified dependencies are checked for general correctness but not for
applicability to the unit being created. This will be corrected in a future
version.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-w <dir>] <component|package|group>
  --help        | -h           usage information (this text)
  --department  | -D           department for creating f_ and l_ units
  --noroot      | -N           do not create root if missing
  --where       | -w <dir>     specify existing/desired root
  --verbose     | -v           report on more of what is being done

See 'perldoc $prog' for more information.

_USAGE_END
}

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        help|h
        department|D
	noroot|N
        where|root|w|r=s
        verbose|v+
    ])) {
        usage("Arfle barfle gloop?");
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    return \%opts;
}

#------------------------------------------------------------------------------

sub isInDepartment ($) {
    my $item=shift;

    return getType($item) & (IS_DEPARTMENT|IS_FUNCTION);
}

sub askQuestion ($;$) {
    my ($question,$default)=@_;
    $default||='';

    print "$question? [$default]: ";
    my $answer=<>;
    chomp $answer;
    return $answer?$answer:$default;
}

sub ensurePath ($;$) {
    my ($dir,$nocreate)=@_;

    if (-d $dir or -l $dir) {
	if (-r $dir) {
	    verbose "Found $dir";
	} else {
	    fatal "$dir not readable";
	}
    } elsif (-e $dir) {
	fatal "$dir is not a directory";
    } elsif (not $nocreate) {
	mkpath($dir) or fatal "Failed to create $dir: $!";
	message "Created $dir";
    } else {
	fatal "$dir not found";
    }
}

#------------------------------------------------------------------------------

sub setupGroup ($$;$) {
    my ($group,$where,$dept)=@_;

    my $categorydir=getTypeDir(getType($group));
    my $originpath=$where.$FS.$categorydir.
      (isInDepartment($group) ? $FS.$dept : "").
	$FS.$group;
    my $grouppath=$originpath.$FS.GROUP_META_SUBDIR;
    ensurePath($grouppath);

    #---

    my $depfile=$grouppath.$FS.$group.DEPFILE_EXTENSION;
    unless (-f $depfile) {
	my $depends=askQuestion("What will $group depend upon","bde");
	my @depends=split/\W+/,$depends;
	foreach (@depends) {
	    #<<<TODO: not rigourous enough
	    fatal "Not a group or isolated package: $_"
	      unless isIsolatedPackage($_) or isGroup($_);
	}

	open DEP,">$depfile" or fatal "Failed to create $depfile: $!";
	print DEP "# Dependants of group $group\n",map { $_."\n" } @depends;
	close DEP or fatal "Failed to close $depfile: $!";
	message "Created $depfile";
    } else {
	verbose "$depfile already exists - leaving alone";
    }

    #---

    my $memfile=$grouppath.$FS.$group.MEMFILE_EXTENSION;
    if (-f $memfile) {
	message "$memfile already exists - leaving alone";
    }

    my $packages=askQuestion("What packages will $group contain",$group."scm");
    my @packages=split/[\s,:-]+/,$packages;
    foreach my $package (@packages) {
	$package=$group.$package unless $package=~/^$group/;
	error("$package is not a legal package name, skipping"), next
	  unless isPackage($package) and getType($package);
	setupPackage($package,$where,$dept);
    }

    if (-f $memfile) {
	message "Remember to update $memfile with these new packages";
    } else {
	open MEM,">$memfile" or fatal "Failed to create $memfile: $!";
	print MEM "# Members of group $group\n",map { $_."\n" } @packages;
	close MEM or fatal "Failed to close $memfile: $!";
	message "Created $memfile";
    }

    #---

    my $optfile=$grouppath.$FS.$group.OPTFILE_EXTENSION;
    if (-f $optfile) {
	message "$optfile already exists - leaving alone";
    } else {
	open OPT,">$optfile" or fatal "Failed to create $optfile: $!";
	print OPT "# Options for group $group\n\n";
	print OPT "*-              _       OPTS_FILE        = $group.opts\n";
	if (getType($group) & IS_DEPARTMENT) {
	    print OPT "\n",
	      "*-              _       DEF_CXXFLAGS     = -I\$(CINCLUDE)\n";
	}
	close OPT or fatal "Failed to close $optfile: $!";
	message "Created $optfile";
    }

    #---

    if (isInDepartment $group) {
	my $indexdir=$where.$FS.$categorydir.$FS.INDEX_DIR;
	ensurePath($indexdir);
	my $indexfile=$indexdir.$FS.$group;
	if (-l $indexfile) {
	    message "$indexfile exists - leaving alone";
	} elsif (-e $indexfile) {
	    fatal "$indexfile exists but is not a link";
	} else {
	    my $err=system('ln','-s',$originpath,$indexfile);
	    fatal "link of $originpath to $indexfile failed: $err" if $err;
	}
    }
}

sub setupPackage ($$;$) {
    my ($package,$where,$dept)=@_;

    my $categorydir=getTypeDir(getType($package));
    my $group=getPackageGroup($package); #undef if isolated package
    my $originpath=$where.$FS.$categorydir.
      (isInDepartment($package) ? $FS.$dept : "").
      ($group ? $FS.$group : "").
	$FS.$package;
    my $packagepath=$originpath.$FS.PACKAGE_META_SUBDIR;

    if ($group) {
	unless (-d $where.$FS.$categorydir.
		(isInDepartment($group) ? $FS.$dept : "").
		$FS.$group.$FS.GROUP_META_SUBDIR) {
	    fatal "Cannot create $package - please create $group first"
	}
    }

    ensurePath($packagepath);

    #---

    my $depfile=$packagepath.$FS.$package.DEPFILE_EXTENSION;
    unless (-f $depfile) {
	my @depends=();
	if (!$group or ($package ne $group."scm")) {
	    my $depends=askQuestion("What will $package depend upon", $group
				    ? "${group}scm" : "bde");
	    @depends=split/\W+/,$depends;
	}

	open DEP,">$depfile" or fatal "Failed to create $depfile: $!";
	print DEP "# Dependants of package $package\n",map {
	    $_."\n"
	} @depends;
	close DEP or fatal "Failed to close $depfile: $!";
	message "Created $depfile";
    } else {
	message "$depfile already exists - leaving alone";
    }

    #---

    my $memfile=$packagepath.$FS.$package.MEMFILE_EXTENSION;
    if (-f $memfile) {
	message "$memfile already exists - leaving alone";
    }

    my @components=();
    if (!$group or ($package ne $group."scm")) {
	my $components=askQuestion("What components will $package contain");
	@components=split/\W+/,$components;
	@components=map {
	    m|^${package}_| ? $_ : "${package}_${_}"
	} @components;
    } else {
	@components=$package."_version";
    }
    setupComponent($_,$where,$dept) foreach @components;

    if (-f $memfile) {
	message "Remember to update $memfile with these new components";
    } else {
	open MEM,">$memfile" or fatal "Failed to create $memfile: $!";
	print MEM "# Members of package $package\n",map {
	    $_."\n"
	} @components;
	close MEM or fatal "Failed to close $memfile: $!";
	message "Created $memfile";
    }

    if (isApplication $package) {
	setupApplicationMain($package,$originpath);
    }

    #---

    my $optfile=$packagepath.$FS.$package.OPTFILE_EXTENSION;
    if (-f $optfile) {
	message "$optfile already exists - leaving alone";
    } else {
	open OPT,">$optfile" or fatal "Failed to create $optfile: $!";
	print OPT "# Options for package $package\n\n";
	print OPT "*-              _       OPTS_FILE        = $package.opts\n";
	if (getType($package) &
	    (IS_ADAPTER|IS_FUNCTION|IS_APPLICATION|IS_LEGACY)) {
	    print OPT "\n",
	      "*-              _       DEF_CXXFLAGS     = -I\$(CINCLUDE)\n";
	}
	if (getType($package) & IS_APPLICATION) {
	    print OPT "\n",
	      "*-              _       APPLICATION_MAIN =".
		"$package.m.cpp=$package.\$(UFID).tsk\n";
	}
	close OPT or fatal "Failed to close $optfile: $!";
	message "Created $optfile";
    }

    #---

    if (!$group and isInDepartment($package)) {
	my $indexdir=$where.$FS.$categorydir.$FS.INDEX_DIR;
	ensurePath($indexdir);
	my $indexfile=$indexdir.$FS.$package;
	if (-l $indexfile) {
	    message "$indexfile exists - leaving alone";
	} elsif (-e $indexfile) {
	    fatal "$indexfile exists but is not a link";
	} else {
	    my $err=system('ln','-s',$originpath,$indexfile);
	    fatal "link of $originpath to $indexfile failed: $err" if $err
	}
    }
}

# a very dumb implemention until we put skeletons in the closet
sub setupComponent ($$;$) {
    my ($component,$where,$dept)=@_;

    my $categorydir=getTypeDir(getType($component));
    my $package=getComponentPackage($component);
    my $group=getPackageGroup($package); #undef if isolated package
    my $componentpath=$where.$FS.$categorydir.
      (isInDepartment($package) ? $FS.$dept : "").
	($group ? $FS.$group : "").
	$FS.$package;

    unless (-f "$componentpath${FS}$component.h") {
	system("touch","$componentpath${FS}$component.h");
	message "Created $componentpath${FS}$component.h";
    }
    unless (-f "$componentpath${FS}$component.cpp") {
	system("touch","$componentpath${FS}$component.cpp");
	message "Created $componentpath${FS}$component.cpp";
    }
    unless (-f "$componentpath${FS}$component.t.cpp") {
	system("touch","$componentpath${FS}$component.t.cpp");
	message "Created $componentpath${FS}$component.t.cpp";
    }
    return 0;
}

sub setupItem ($$;$) {
    return setupGroup($_[0],$_[1],$_[2]) if isGroup($_[0]);
    return setupPackage($_[0],$_[1],$_[2]) if isPackage($_[0]);
    return setupComponent($_[0],$_[1],$_[2]) if isComponent($_[0]);

    fatal ("Not a unit of release: $_[0]");
}

sub setupApplicationMain ($$) {
    my ($package,$packagepath)=@_;

    system("touch","$packagepath${FS}$package.m.cpp");
    message "Created $packagepath${FS}$package.m.cpp";

    return 0;
}

#------------------------------------------------------------------------------

MAIN: {
    STDOUT->autoflush(1);

    my $opts=getoptions();
    my @items = map {
	fatal "Not a legal group, package, or component name: $_" unless
	  isGroup($_) or isPackage($_) or isComponent($_);
	$_;
      } @ARGV;
    undef @ARGV;

    # determine location of root
    if ($opts->{where}) {
	alert "Using root $opts->{where}";
    } else {
	my $default;
	if ($ENV{BDE_ROOT}) {
	    $default=$ENV{BDE_ROOT};
	    alert "Predefined BDE_ROOT ($default) detected";
	} else {
	    my $HOME=$ENV{HOME};
	    fatal "\$HOME is not defined in environment" unless $HOME;
	    $default=$HOME.$FS.'bderoot';
	}

	$opts->{where} =
	  askQuestion("Where is/do you want the root" => $default);
    }

    # create or verify existing root
    ensurePath $opts->{where},$opts->{nocreate};
    foreach (IS_BASE,IS_ADAPTER,IS_FUNCTION,IS_APPLICATION,
	     IS_DEPARTMENT,IS_WRAPPER,IS_ENTERPRISE,IS_LEGACY,IS_THIRDPARTY) {
	my ($name,$dir)=(getTypeName($_),getTypeDir($_));
	ensurePath $opts->{where}.$FS.$dir,$opts->{nocreate};
    }

    # determine department ID
    unless ($opts->{department}) {
	if ($ENV{BDE_DEPARTMENT}) {
	    $opts->{department}=$ENV{BDE_DEPARTMENT};
	} else {
	    # get a department ID only if we actually need one
	    foreach my $item (@items) {
		if (isInDepartment($item)) {
		    unless ($opts->{department}) {
			do {
			    $opts->{department}=askQuestion(
			      "What is the department directory name" =>
							    "REQUIRED");
			} until ($opts->{department} ne "REQUIRED");
		    }
		    last; #once we have a dept no need to keep going
		}
	    }
	}
    }

    # create or verify unit of release
    my $result=0;
    if (@items) {
	message "Setting up: @items";
	message "(Press return to accept defaults)";
	foreach my $item (@items) {
	    $result += setupItem($item,$opts->{where},$opts->{department});
	}
    }

    unless ($result) {
	unless ($ENV{BDE_ROOT}) {
	    my $envfile = $ENV{ENV} ? $ENV{ENV} : "your .kshrc or .bashrc";
	    print "Now add 'BDE_ROOT=$opts->{where}' to $envfile\n";
	}
    }

    exit $result;
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_build.pl>, L<bde_verify.pl>, L<bde_rule.pl>, L<bde_snapshot.pl>

=cut
