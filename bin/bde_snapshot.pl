#!/bbs/opt/bin/perl -w
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path;

use BDE::Group;
use BDE::Package;
use BDE::Component;
use BDE::FileSystem::Finder;
use BDE::Util::DependencyCache qw(
    getAllGroupDependencies getAllPackageDependencies
);
use BDE::Util::Nomenclature qw(
    isGroup isPackage isGroupedPackage isIsolatedPackage
    isCompliant isApplication isFunction getType getTypeDir
);
use BDE::Build::Invocation qw($FS $FSRE);
use Build::Option::Factory;
use Build::Option::Finder;
use Util::Message qw(message alert warning verbose debug fatal);
use Util::File::Basename qw(basename);
use Util::File::Attribute qw(is_newer);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE
    PACKAGE_META_SUBDIR GROUP_META_SUBDIR
    ROOT
    $DEFAULT_JOBS
    FILESYSTEM_NO_LOCAL FILESYSTEM_NO_ROOT
);
use Task::Manager;
use Task::Action;

my @metafiles = qw[mem dep opts pub cap defs];

#==============================================================================

=head1 NAME

bdesnapshot.pl - create/update local copies of groups and packages

=head1 SYNOPSIS

  To destination directory, with test drivers
  $ bde_snapshot.pl bde bce bae a_bael a_bdema --to /to/here

  To local root, with all dependants
  $ bde_snapshot.pl -t $BDE_ROOT a_bdema -D

  To current directory, without test drivers
  $ bde_snapshot.pl --nodrivers bde

  To current directory, flat, without drivers or metafiles
  $ bde_snapshot.pl --nodrivers --flat f_ykmnem

  To current directory, in categories, with drivers, metafiles, dependants
  $ bde_snapshot.pl -fcmD f_ykmnem

=head1 DESCRIPTION

This program creates I<snapshots> of one or more source units (packages or
package groups) in the target directory. Rather than carry out a blanket copy,
it uses the I<members> and I<dependencies> files of each package or package
group to determine which source files constitute registered components.

Snapshots are taken from the directory specified by C<--where> or C<-w>, or
if not specified, the configured root, as set by C<BDE_ROOT>. If not found
there, C<BDE_PATH> is searched.

The destination directory may be specified by C<--to> or C<-t>, otherwise the
current working directory is presumed. Any local copies of source units
(such as those created by C<bde_snapshot.pl> itself) are not considered as a
valid source location as they would by other tools such as L<bde_build.pl>.
This allows a local isloated snapshot to be updated from a repository
location. If the destination for the snapshot corresponds to a location under
the configured root, the root is also ignored for the purposes of locating a
valid origi, and only locations on the path are considered. This allows a local
root to be updated. If the C<--categories> or C<-c> option is used then
(in non-flat mode) category directories are also created and the copied source
units are place within them.

Files are compared before they are copied, and existing files are updated only
if they deemed to be older than the origin. Previously made snapshots may
therefore be refreshed, but note that if the origin file has changed more
recently than a locally modified file, it will be overwritten as its timestamp
is older.

If desired, dependent packages and package groups may also be automatically
snapshotted by specifying the C<--dependants> or C<-D> flag. This will cause
C<bde_snapshot.pl> to calculate the union of all dependants of the specified
list of source units and copy/refresh them also.

=head2 Structured Snapshots

By default the directory structure of the specified source units is replicated
at the destination, including C<group> and C<package> metafile subdirectories.

If the C<--category> or C<-c> option is specified, category directories (i.e.
I<groups>, I<adapters>, etc.) are also created if not present, and the
requested units copied underneath them.

To disable the copying of metafiles, use C<--nometafiles>. To disable the
copying in test drivers, use C<--nodrivers>.

=head2 Flat Snapshots

If the C<--flat> or C<-f> option is used, source files are copied directly to
the destination and no directory structure is created. In addition, metafiles
are I<not> copied unless the C<--metafiles> or C<-m> option is also specified.
In this case metafiles are copied directly to the destination directory and
not a C<group> or C<package> subdirectory.

As with structured snapshots, C<--nodrivers> may be used to suppress copying
or updating the test drivers.

=head1 TO DO

Additional options are planned to snapshot the 'universe' and various
subsets of it.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-D] [-m] [-f] [-t <dir>] [-w <root>] <unit> ...
  --category   | -c           create/use category directory (e.g. 'groups')
                              under destination directory (not with --flat)
  --debug      | -d           enable debug reporting
  --etc        | -e           include "etc/" directory
  --drivers    | -T           include test drivers
  --flat       | -f           do not create subdirectories
  --help       | -h           usage information (this text)
  --honordeps  | -H           snapshot dependants also
  --jobs       | -j [<jobs>]  snapshot in parallel up to the specified number
                              of jobs (default: $DEFAULT_JOBS jobs)
  --metafiles  | -m           copy meta files in --flat mode (automatically
                              enabled otherwise)
  --serial     | -s           serial build (equivalent to -j1)
  --to         | -t <dir>     destination directory
  --verbose    | -v           enable verbose reporting
  --where      | -w <dir>     specify explicit alternate root (default: .)
  --noretry    | -X           disable retry semantics on file operations

See 'perldoc $prog' for more information.

_USAGE_END
}

# TO DO:
# --all                         the universe
# --all=functions,adapters      all functions and adapters in the universe
# --except                      list of things not to snap when using 'all'

#------------------------------------------------------------------------------

sub getoptions {
    my %opts=(
        flat      => 0,
        metafiles => 2,
        drivers   => 1,
    );

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        category|c
        debug|d+
        drivers|T!
        honordeps|honourdeps|H|dependants|dependents|D!
        etc|e!
        flat|f!
        help|h
        jobs|parallel|j|p=i
        metafiles|m!
        where|root|w|r=s
        serial|s!
        to|t=s
        verbose|v+
        noretry|X
    ])) {
        usage("Arfle Barfle Gloop?");
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage("Nothing to do"), exit EXIT_FAILURE if @ARGV < 1;

    # filesystem root
    $opts{where} = ROOT unless $opts{where};

    # disable retry
    if ($opts{noretry}) {
        $Util::Retry::ATTEMPTS = 0;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # destination directory
    $opts{to} ||= ".";

    # metafiles
    if ($opts{metafiles}==1 and not $opts{flat}) {
        warning "--metafiles is redundant without --flat";
    } elsif ($opts{metafiles}==2 and $opts{flat}) {
        $opts{metafiles}=0;
    }

    # serial override
    $opts{jobs}=1 if $opts{serial};

    # jobs
    $opts{jobs}=$DEFAULT_JOBS unless $opts{jobs};
    unless ($opts{jobs}>=1) {
        usage("number of --jobs must be >= 1");
        exit EXIT_FAILURE;
    }

    return \%opts;
}

#------------------------------------------------------------------------------

# copy a leafname file from directory to directory
sub copyfiledirtodir ($$$) {
    my ($leafname,$fromdir,$todir)=@_;

    my $fromfile=$fromdir.$FS.$leafname;
    my $tofile=$todir.$FS.$leafname;

    copyfiletofile($fromfile,$tofile);
}

# copy a fully qualified filename to another fully qualified name
sub copyfiletofile ($$) {
    my ($fromfile,$tofile)=@_;

    if (is_newer($tofile,$fromfile)) {
        debug "copying $fromfile to $tofile";
        copy($fromfile => $tofile) or
          fatal "Failed to copy $fromfile to $tofile: $!";
    } else {
        debug "$tofile is newer than $fromfile - skipping";
        return 2; #nop
    }

    return 1;
}

# File::Find closure for snapshotting non-compliant packages
{
    my ($frompath,$topath);

    sub snapshotFile {
        my $from=$File::Find::name;
        my $name=$_;

        return if $name eq '.';
        return if $name=~/\.o(bj)$/; #just in case
        $File::Find::prune=1,return if $name =~ m[^(include|lib|test|exp)$];
        $File::Find::prune=1,return if $name =~
          m[^(unix|windows)-([^-]+)-([^-]+)-([^-]+)-(\w+)];

        my $to=$from;
        $to=~s/^\Q$frompath\E/$topath/
          or fatal "Couldn't remap $to from $frompath to $topath";

        if (-f $from) {
            copyfiletofile($from,$to);
        } elsif (-d $from) {
            unless (-d $to) {
                debug "Creating directory $to";
                mkpath $to or die "Failed to make path $to: $!";
            }
        } elsif (-l $from) {
            debug "Ignoring symlink $from";
        } else {
            warning "Not a file or directory: $from";
        }
    }

    sub snapshotPackageFiles ($$$) {
        my ($from,$to,$opts)=@_;
        $frompath=$from; $topath=$to;
        find(\&snapshotFile,$frompath);
    }
}

sub snapshotPackage ($$$) {
    my ($package,$root,$opts)=@_;
    my $to=$opts->{to};
    my $drivers=$opts->{drivers};
    my $factory=$opts->{_factory};

    message "Snapshotting package $package";
    my $frompackagedir=$root->getPackageLocation($package,
        FILESYSTEM_NO_LOCAL | (($to eq $root)?FILESYSTEM_NO_ROOT:0)
    );
    debug "$package source directory: $frompackagedir";

    my $topackagedir=$to;
    unless ($opts->{flat}) {
        $topackagedir=$to.$FS.$package;
        # a grouped pkg cannot be snapped in category mode unless
        # via a group
        if ($opts->{category} and not isGroupedPackage($package)) {
            my $category=getTypeDir(getType($package));
            $topackagedir=$to.$FS.$category.$FS.$package;
            unless (-d $to.$FS.$category) {
                mkdir($to.$FS.$category,0755) or
                  fatal "Failed to create $to${FS}$category: $!";
            }
        }
        unless (-d $topackagedir) {
            mkdir($topackagedir,0755) or
              fatal "Failed to create $topackagedir: $!";
        }
    }

    $package=new BDE::Package($frompackagedir);

    # all packages
    my @components=$package->getMembers();
    debug "$package components: @components";
    foreach my $component (@components) {
        $component=new BDE::Component($frompackagedir.$FS.$component);
        my $lang=$component->getLanguage();
        copyfiledirtodir($component.".h",$frompackagedir,$topackagedir);
        copyfiledirtodir($component.".$lang",$frompackagedir,$topackagedir);
        if ($drivers) {
            copyfiledirtodir($component.".t.$lang",$frompackagedir,$topackagedir);
        }
    }
    # non-compliant
    unless (isCompliant $package) {
        snapshotPackageFiles($frompackagedir,$topackagedir,$opts);
    }

    my $frommetadir=$frompackagedir.$FS.PACKAGE_META_SUBDIR;
    if ($opts->{metafiles}) {
        my $tometadir=$topackagedir;
        unless ($opts->{flat}) {
            $tometadir=$topackagedir.$FS.PACKAGE_META_SUBDIR;
            unless (-d $tometadir) {
                mkdir($tometadir,0755) or
                  fatal "Failed to create $tometadir: $!";
            }
        }

        foreach (@metafiles) {
            copyfiledirtodir($package.".".$_,$frommetadir,$tometadir)
              if -e $frommetadir.$FS.$package.".".$_;
        }
    }

    my $options=$factory->construct({
        what  => $package,
        uplid => undef,
        ufid  => undef,
    });

    if (my $main=$options->getValue("APPLICATION_MAIN")) {
        my @mains=split /\s+/,$main;
        @mains=map { (split /=/)[0] } @mains; # strip off '=task' suffixes
        copyfiledirtodir($_,$frompackagedir,$topackagedir) foreach @mains;
    } elsif (isApplication($package)) {
        #default application name
        copyfiledirtodir($package.".m.cpp",$frompackagedir,$topackagedir);
    }

    #<<<only works if the architecture matches! problem!
    if (my $xsrc=$options->getValue("EXTRA_".uc($package)."_SRCS")) {
        my @xfiles=split /\s+/,$xsrc;
        copyfiledirtodir($_,$frompackagedir,$topackagedir) foreach @xfiles;
    }

    if (isApplication($package) or isFunction($package)) {
        if (-f $frompackagedir.$FS.$package.".mk") {
            # optionally copy a plink makefile, if one is lurking
            copyfiledirtodir($package.".mk",$frompackagedir,$topackagedir);
        }
    }
}

sub snapshotGroup ($$$) {
    my ($group,$root,$opts)=@_;
    my $to=$opts->{to};
    my $drivers=$opts->{drivers};

    message "Snapshotting group $group";

    my $fromgroupdir=$root->getGroupLocation($group,
        FILESYSTEM_NO_LOCAL | (($to eq $root)?FILESYSTEM_NO_ROOT:0)
    );

    debug "$group source directory: $fromgroupdir";

    my $togroupdir=$to;
    unless ($opts->{flat}) {
        $togroupdir=$to.$FS.$group;
        if ($opts->{category}) {
            my $category=getTypeDir(getType($group));
            $togroupdir=$to.$FS.$category.$FS.$group;
            unless (-d $to.$FS.$category) {
                mkdir($to.$FS.$category,0755) or
                  fatal "Failed to create $to${FS}$category: $!";
                ##<<TODO: race condition in parallel snaps, fix
            }
        }
        unless (-d $togroupdir) {
            mkdir($togroupdir,0755) or
              fatal "Failed to create $togroupdir: $!";
        }
    }

    $group=new BDE::Group($fromgroupdir);
    my @packages=$group->getMembers();
    debug "$group packages: @packages";

    local $opts->{to}=$togroupdir unless $opts->{flat};
    if ($opts->{jobs}>1) {
        my $mgr=new Task::Manager("$group snapshot");
        foreach my $package (@packages) {
            $mgr->addAction(new Task::Action({
                name     => "$package.snapshot",
                action   => \&snapshotPackage,
                args     => [ $package, $root, $opts ],
            }));
        } 
        $mgr->run($opts->{jobs});
    } else {
        foreach my $package (@packages) {
            snapshotPackage($package,$root,$opts);
        }
    }


    if ($opts->{metafiles}) {
        my $frommetadir=$fromgroupdir.$FS.GROUP_META_SUBDIR;

        my $tometadir=$togroupdir;
        unless ($opts->{flat}) {
            $tometadir=$togroupdir.$FS.GROUP_META_SUBDIR;
            unless (-d $tometadir) {
                mkdir($tometadir,0755) or
                  fatal "Failed to create $tometadir: $!";
            }
        }

        foreach (@metafiles) {
            copyfiledirtodir($group.".".$_,$frommetadir,$tometadir)
              if -e $frommetadir.$FS.$group.".".$_;
        }
    }
}

#------------------------------------------------------------------------------

sub get_dependants ($) {
    my $item=shift;

    my @dependants=();

    if (isGroup $item or isIsolatedPackage $item) {
        @dependants=getAllGroupDependencies($item);
    } else {
        @dependants=getAllPackageDependencies($item);
    }

    return @dependants;
}

#------------------------------------------------------------------------------

MAIN {
    my $opts=getoptions();
    my $root=new Build::Option::Finder($opts->{where});
    $opts->{_factory}=new Build::Option::Factory($root); 
    BDE::Util::DependencyCache::setFileSystemRoot($root);

    foreach my $item (@ARGV) {
        fatal "Unknown source unit: $item"
          unless isGroup($item) or isPackage($item);
    }

    if (defined $opts->{etc}) {
        message "Snapshotting etc";
        system("/opt/swt/bin/rsync -av $opts->{where}/etc $opts->{to}/");
    }

    my @items=();
    foreach my $item (@ARGV) {
        if ($opts->{honordeps}) {
            if (isGroupedPackage($item)) {
                fatal "$item is not a unit of release -",
                  "not permissable with --dependants";
            } else {
                push @items,get_dependants($item);
            }
        }
        push @items,$item;
    }
    my %items=map {$_=>1} @items;
    @items = keys %items;

    unless (-d $opts->{to}) {
        fatal "Destination '$opts->{to}' is not a directory";
    }
    $opts->{to}=abs_path($opts->{to})
      or fatal "Failed to get absolute path for $opts->{to}: $!";

    alert "Snapshotting @items" if @items>1;
    if (scalar(@items)>1 and $opts->{jobs}>1) {
        my $mgr=new Task::Manager("snapshot");
        foreach my $item (@items) {
            if (isGroup($item)) {
                $mgr->addAction(new Task::Action({
                    name     => "$item.snapshot",
                    action   => \&snapshotGroup,
                    args     => [ $item, $root, $opts ],
                }));
            } elsif (isPackage($item)) {
                $mgr->addAction(new Task::Action({
                    name     => "$item.snapshot",
                    action   => \&snapshotPackage,
                    args     => [ $item, $root, $opts ],
                }));
            }
        }
        $mgr->dump() if $opts->{debug};
        $mgr->run($opts->{jobs});
    } else {
        foreach my $item (@items) {
            if (isGroup($item)) {
                snapshotGroup($item,$root,$opts);
            } elsif (isPackage($item)) {
                snapshotPackage($item,$root,$opts);
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

L<bde_build.pl>, L<bde_setup.pl>, L<bde_verify.pl>, L<bde_rule.pl>

=cut
