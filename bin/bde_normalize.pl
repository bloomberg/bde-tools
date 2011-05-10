#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use IO::Handle;
use File::Copy;
use File::Path;
use File::Compare;
use Getopt::Long;

use BDE::FileSystem;
use BDE::Util::Nomenclature qw(
    isGroup isPackage isComponent
    getComponentGroup getComponentPackage getPackageGroup
);

use BDE::Build::Invocation qw($FS);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
    FILESYSTEM_NO_PATH PACKAGE_META_SUBDIR GROUP_META_SUBDIR
);
use Util::Message qw(fatal alert message verbose verbose2 warning);
use Util::File::Basename qw(dirname basename);

#==============================================================================

=head1 NAME

bde_normalize.pl - Construct well-formed structure from component files

=head1 SYNOPSIS

    # reconstruct components from the named library locations
    $ bde_normalize.pl -licpplib -licpputil -lderutil

    # reconstruct l_foo and e_bar only, from an arbitrary location
    $ bde_normalize.pl --units l_foo,e_bar /path/to/filesdir

    # reconstruct a library from its location, plus staging areas
    $ bde_normalize.pl -licpputil -CU -ul_foo

=head1 DESCRIPTION

C<bde_normalize.pl> takes the supplied list of files and directories and
generates one or more unit-of-release directory structures, under the current
root (or directory specified with C<-w>/C<--where>), with copies of all
files that correspond to identifiable components.

If the C<-l> or C<--libraries> option is specified, the supplied
comma-separated list of library locations under C</bbsrc> are prepended to the
list of files and directories to scan. C<-C> or C<--checkin> adds the
checkin/PRLS staging area, while C<-U> or C<--unreleased> adds the unreleased
files staging area, in both cases after library locations specified with C<-l>
but before any explicitly provided filename arguments.

Files are scanned for in the following order:

  Library locations specified with C<-l>, in the specified order
  The checkin/PRLS staging area (if C<-C> is active)
  The unreleased staging area (if C<-U> is active)
  Trailing filename arguments, in the specified order

When the same filename occurs in more than one location, the last file found
overrides any earlier instances.

If RCS files are present in the input list then they are checked out into
the directory structure. If a checked out file exists in the same location
as the RCS file, they are checked for consistency. The checked out file is
used in the event that they disagree, and a warning is generated. To avoid
RCS detection and consistency checks, do not specify the RCS file in the
input list.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-w <dir>] [-X] [-u <grp|pkg>[,<grp|pkg>...] <files>
  --checkin     | -C           retrieve files from checkin/PRLS staging area
  --debug       | -d           enable debug reporting
  --exclude     | -E <dirs>    do not recurse into directories matching one of
                               the list of comma-separated names
                               (default: archive,CVS,RCS,SCCS)
  --help        | -h           usage information (this text)
  --libraries   | -l <libs>    retrieve files from the specified comma-
                               separated list of /bbsrc library directories
  --units       | -u <units>   retrieve files for the specified comma-
                               separated list of groups/packages only
                               (may be specified multiple times)
  --unreleased  | -U           retrieve files from unreleased staging area
  --verbose     | -v           enable verbose reporting
  --where       | -w <dir>     specify explicit alternate root
  --noretry     | -X           disable retry semantics on file operations

See 'perldoc $prog' for more information.

_USAGE_END
}
# --extensions  | -e           limit copied files to specified comma-separated
#                              list of extensions

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        checkin|C|prls|P
        unreleased|unrel|U
        debug|d+
        help|h
        libraries|library|l=s@
        where|root|w|r=s
        units|unit|u=s@
        noretry|X
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # filesystem root
    $opts{where} = DEFAULT_FILESYSTEM_ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
	$Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # default exclusions
    $opts{exclude} = [qw(archive RCS CVS SCCS)]
      unless defined $opts{exclude};
    if ($opts{exclude}->[0]=~s/^\+//) { #append to default
	unshift @{$opts{exclude}},qw(archive RCS CVS SCCS);
    }
    verbose2 "Excluding directories: @{$opts{exclude}}";

    foreach my $lib (@{$opts{libraries}}) {
	push @ARGV, map {
	    expand_files("/bbsrc/$_",1,@{$opts{exclude}})
	} split(',',$lib);
    }
    push @ARGV, expand_files("/bbsrc/checkin") if $opts{checkin};
    push @ARGV, expand_files("/bbsrc/vc/unreleased") if $opts{unreleased};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{list};

    return \%opts;
}

#------------------------------------------------------------------------------

# expand a directory and return files contained within, optionally recursing
sub expand_files ($;$@) {
    my ($dir,$recurse,@exclude)=@_;
    my @files=();
    my %exclude=map { $_=>1 } @exclude;

    my $dh=new IO::Handle;
    opendir $dh,$dir or do {
	warning "unable to open $dir: $!";
	return ();
    };

    verbose "expanding $dir";

    while (my $base=readdir $dh) {
	next if $base=~/^\./;
	my $file=$dir.$FS.$base;
	$file=readlink $file if -l $file;

	if (-f $file) {
	    push @files,$file;
	} elsif ($recurse and -d $file) {
	    if (exists $exclude{$base}) {
		verbose "skipping $file" ;
	    } else {
		push @files, expand_files($file,$recurse,@exclude);
	    }
	}
    }

    closedir $dh;

    return @files;
}

# caching directory path creator, wraps File::Path::mkpath
{ my %ensured;

  sub ensure_path ($;$) {
      my ($dir,$nocreate)=@_;

      return 1 if $ensured{$dir};

      if (-d $dir or -l $dir) {
	  if (-r $dir) {
	      $ensured{$dir}=1;
	      verbose "found $dir";
	  } else {
	      fatal "$dir not readable";
	  }
      } elsif (-e $dir) {
	  fatal "$dir is not a directory";
      } elsif (not $nocreate) {
	  mkpath($dir) or fatal "failed to create $dir: $!";
	  message "created $dir";
	  $ensured{$dir}=1;
      } else {
	  fatal "$dir not found";
      }
  }
}

# Return basename, extension, optionally archive suffix for a filename,
# if it corresponds (roughly) to an acceptable form.
sub file_base ($) {
    return ($_[0]=~/^(.*)\.((?:[mt]\.)?\w{1,4})(,v)?$/)
      ? ($1,$2,$3)
      : undef;
}

# Expand list of passed files and directories and assign legal component
# filenames to the appropriate component. Returns a hash keyed by component
# name, containing the files that were found. Does not (as yet) notice or
# deal with a .cpp and a .c for the same component.
sub parse_files ($@) {
    my ($units,$exclude,@files)=@_;

    my %units = map {$_ => 1} map { split /,/ } @$units;

    my %files;
    while (my $file=shift @files) {
	my $item=basename $file;

	$file=readlink $file if -l $file;

	if (-f $file) {
	    my ($base,$ext,$isrcs)=file_base($item);

	    if ($base and isComponent($base)) {
		my $pkg=getComponentPackage($base);
		my $grp=getPackageGroup($pkg);
		if (!%units or exists($units{$pkg})
		    or ($grp and exists($units{$grp}))) {
		    $files{$base}{$ext}=$file;
		}
	    } else {
		verbose2 "Ignored file '$item' - not part of a component";
	    }

	} elsif (-d $file) {
	    $exclude = [] unless $exclude;
	    $exclude = [$exclude] unless ref $exclude;
	    push @files, expand_files($file,1,@$exclude);
	} else {
	    verbose2 "Ignored '$item' - not a file or directory";
	}
    }

    return wantarray ? %files : \%files;
}

#------------------------------------------------------------------------------

# copy a file, checking it out from RCS if necessary and testing the RCS file
# versus the checked-out version if both exist in the same location.
sub copy_file ($$) {
    my ($file,$locn)=@_;

    my $base = basename($file);
    my $dir  = dirname($file);
    my $tmpd = $ENV{TMPDIR} || '.';

    if ($base=~/^(.*),v$/) {
	my $cofile=$1;

	copy $file => $tmpd;
	`cd $tmpd && co -q -f $cofile` # && rm $base`
	  and fatal "Failed to generate checkout: $!";

	if (-f $dir.$FS.$cofile) {
	    #print "FOO:$dir$FS$cofile EXISTS\n";

	    if (compare $dir.$FS.$cofile => $tmpd.$FS.$cofile) {
		warning "In $dir, $cofile conflicts with $base, using $cofile";
	    } else {
		verbose "In $dir, $cofile agrees with $base";
	    }

	    copy $dir.$FS.$cofile => $locn; #which to do?
	} else {
	    copy $tmpd.$FS.$cofile => $locn;
	}
	unlink $tmpd.$FS.$base;
	unlink $tmpd.$FS.$cofile;
    } else {
	return copy $file => $locn;
    }
}

sub copy_component ($$$) {
    my ($comp,$locn,$info)=@_;
	
    verbose "$comp:";
    foreach my $ext (sort keys %{$info}) {
	my $file=$info->{$ext};
	ensure_path($locn);
	if (copy_file $file => $locn) {
	    message("copied $file to $locn");
	} else {
	    warning("failed to copy $file to $locn: $!");
	}
    }
}

#------------------------------------------------------------------------------

sub create_package_memfile ($$@) {
    my ($package,$locn,@members)=@_;

    ensure_path($locn.$FS.PACKAGE_META_SUBDIR);
    my $memfile=$locn.$FS.PACKAGE_META_SUBDIR.$FS.$package.".mem";

    open MEM,">$memfile" or fatal "Failed to create $memfile: $!";
    print MEM "# Members of package $package\n",map { $_."\n" } @members;
    close MEM or fatal "Failed to close $memfile: $!";
    message "created $memfile";
}

sub create_group_memfile ($$@) {
    my ($group,$locn,@members)=@_;

    ensure_path($locn.$FS.GROUP_META_SUBDIR);
    my $memfile=$locn.$FS.GROUP_META_SUBDIR.$FS.$group.".mem";

    open MEM,">$memfile" or fatal "Failed to create $memfile: $!";
    print MEM "# Members of group $group\n",map { $_."\n" } @members;
    close MEM or fatal "Failed to close $memfile: $!";
    message "created $memfile";
}

# create group and package membership files based provided component names
sub create_memfiles ($@) {
    my ($root,@comps)=@_;
    my (%groups,%packages);

    # get packages from components
    foreach my $comp (@comps) {
	my $package=getComponentPackage($comp);
	$packages{$package} ||= [];
	push @{$packages{$package}},$comp;
    }

    # get package groups from packages
    foreach my $package (sort keys %packages) {
	if (my $group=getPackageGroup($package)) {
	    $groups{$group} ||= [];
	    push @{$groups{$group}}, $package;
	}
    }

    # generate group memfiles and grouped package memfiles
    foreach my $group (sort keys %groups) {
	my @packages=@{$groups{$group}};
	create_group_memfile($group,
	   $root->getGroupLocation($group), @packages);
	foreach my $package (@packages) {
	    create_package_memfile($package,
                $root->getPackageLocation($package), @{$packages{$package}});
	}
    }

    # generate isolated package memfiles
    foreach my $package (sort keys %packages) {
	next if getPackageGroup($package); #grouped package already done
	create_package_memfile($package,
          $root->getPackageLocation($package), @{$packages{$package}});
    }
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    # set up filesystem
    my $root=new BDE::FileSystem($opts->{where});
    $root->setSearchMode(FILESYSTEM_NO_PATH);

    # find all components
    my $comps=parse_files($opts->{units},$opts->{exclude},@ARGV);

    # copy all component files
    foreach my $comp (sort keys %$comps) {
	my $locn=$root->getComponentLocation($comp);
	copy_component($comp,$locn,$comps->{$comp});
    }

    # compute membership file contents
    create_memfiles($root,sort keys %$comps);
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_snapshot.pl>

=cut
