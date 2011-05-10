package bde_build;
use strict;

use Carp;
use Exporter;
use Util::Retry qw(:all);
use Util::Message qw(warning);
use Util::File::Basename qw(basename dirname);
use BDE::Build::Invocation qw($FS);

use vars qw(@ISA @EXPORT);

@ISA = ('Exporter');
@EXPORT = qw[
     isNonCompliant
     isCompliant
     setGroupsRoot
     getGroupsRoot
     getGroupDir
     getGroupDepFile
     getPackageGroup
     getPackageDir
     getPackageDepFile
     getPackageMemFile
     getComponentBasepath
     getComponentPackage
     getComponentInterfaceFile
     getComponentImplementationFile
     getComponentAssemblyFile
     getComponentTestFile
     readGroupMemFile
     readPackageMemFile
     scanPackageDirectory
     mkDotOCompCmd
     mkDotOAssyCmd
     mksymlink
     checkComponentName
];

#----------

=head1 isNonCompliant($package)

Returns 1 if the package name is non-compliant, indicating a
pseudo-package rather than a BDE-conformant package. Returns
0 if the package name indicates a standard package.

'non-compliant' is defines as a name containing a non-word
character (such as '.' or '-').

=cut

sub isNonCompliant ($) {
    my $package=shift;

    return 1 if $package=~/\W/;
    return 0;
}

sub isCompliant ($) {
    return isNonCompliant($_[0])?0:1;
}

#----------

my $groups_root;

=head1 setGroupsRoot(group)

Set the directory of the groups root so that it is available to
other subroutines in this module. E.g. 
/view/bde_integrator/bbcm/infrastructure/groups

=cut

sub setGroupsRoot($) {
    $groups_root = $_[0];
    if ($FS ne "/") {
        $groups_root =~ s|/|$FS|sg;
    }
    return $groups_root;
}

=head1 getGroupsRoot()

Get the directory of the groups root

=cut

sub getGroupsRoot() {
    return $groups_root;
}

#----------

=head1 getGroupDir(group_name)

Returns full path of package group directory from a group name, e.g. 
getGroupDir("bde") returns "/view/bde_integrator.../bde". 
Dies if directory not found.

=cut

sub getGroupDir($) {
    my $group = shift;

    die "ERROR: bad group name: '$group'\n" if $group !~ /^(\S{3})$/;

    die "group directory $groups_root${FS}$group not found" if 
      ! -d "$groups_root${FS}$group";

    return "$groups_root${FS}$group";
}

#----------

=head1 getGroupMemFile(group)

Returns full path of package group .mem file, e.g. 
getGroupMemFile("bde") returns "/view/bde_integrator.../bde/group/bde.mem". 
Dies if file not found.

=cut

sub getGroupMemFile($) {
    my $group = shift;
    my $dir = getGroupDir($group);
    my $memfile = "$dir${FS}group${FS}$group.mem";

    die "$memfile not found" unless retry_file($memfile);

    return $memfile;
}

#----------

=head1 getGroupDepFile(group)

Returns full path of package group .dep file, e.g. 
getGroupDepFile("bde") returns "/view/bde_integrator.../bde/group/bde.dep". 
Dies if file not found.

=cut

sub getGroupDepFile($) {
    my $group = shift;
    my $dir = getGroupDir($group);
    my $depfile = "$dir${FS}group${FS}$group.dep";

    die "ERROR: $depfile not found" unless retry_file($depfile);

    return $depfile;
}

#----------

=head1 getPackageDir(package)

Returns full path of package directory, e.g. 
getPackageDir("bdes") returns "/view/bde_integrator.../bde/bdes". 
Dies if file not found.

=cut

sub getPackageDir($) {
    my $pkg = shift;
    my $group;

    if ($pkg =~ /^(\S{3})\S+$/) {
        $group = $1;
    }
    else {
        die "ERROR: bad package name: '$pkg'";
    }

    -d "$groups_root${FS}$group${FS}$pkg" or 
      die "package directory $groups_root${FS}$group${FS}$pkg not found";

    return "$groups_root${FS}$group${FS}$pkg";
}

#----------

=head1 getPackageMemFile(package)

Returns full path of package .mem file, e.g. 
getPackageMemFile("bdes") returns 
"/view/bde_integrator.../bdes/package/bdes.mem".
Dies if file not found.

=cut

sub getPackageMemFile($) {
    my $pkg = shift;
    my $dir = getPackageDir($pkg);
    my $memfile = "$dir${FS}package${FS}$pkg.mem";

    die "ERROR: $memfile not found" unless retry_file($memfile);

    return $memfile;
}

#----------

=head1 getPackageDepFile(package)

Returns full path of package .dep file, e.g. 
getPackageDepFile("bdes") returns
"/view/bde_integrator.../bdes/package/bdes.dep".
Dies if file not found.

=cut

sub getPackageDepFile($) {
    my $pkg = shift;
    my $dir = getPackageDir($pkg);
    my $depfile = "$dir${FS}package${FS}$pkg.dep";

    die "ERROR: $depfile not found" unless retry_file($depfile);

    return $depfile;
}

#----------

=head1 getPackageGroup(pkg)

Extracts package group from package name and returns value.

=cut

sub getPackageGroup($) {
    my $pkg = shift;
    $pkg =~ /^(\S{3})\S+/ and return $1 or
      carp "ERROR: bad package name: '$pkg'";
}

#----------

=head1 getComponentBasepath(component)

Extracts fullpath from component and returns value. 

=cut

sub getComponentBasepath($;$) {
    my $comp=shift;

    checkComponentName($comp);

    carp "ERROR: bad component name: '$comp'" if
      $comp !~ /^((\w{3})\w+?)_\w+$/;
    my ($group, $pkg) = ($2, $1);
    die "ERROR: bad component name: '$comp'" if ! $group or ! $pkg;

    return "$groups_root${FS}$group${FS}$pkg${FS}$comp";
}

#----------

=head1 getComponentPackage(component)

Extracts package name from component and returns value.

=cut

sub getComponentPackage($) {
    my $comp = shift;
    checkComponentName($comp);

    $comp =~ /^(\w{4,}?)_/ and return $1 or
    #$comp =~ /^(\S{4,}?)\_/ and return $1 or
      carp "ERROR: bad component name: '$comp'";
}

#----------

=head1 getComponentInterfaceFile(component)

Gets path of component .h file, and tests for its existence. Returns
full pathname of file.

=cut

sub getComponentInterfaceFile($) {
    my $comp = shift;
    checkComponentName($comp);
    #$comp = "\L$comp\E";

    my $file = getComponentBasepath($comp) . ".h";
    retry_file($file) or die "ERROR: cannot find interface file for $comp";
    return $file;
}

#----------

=head1 getComponentImplementationFile(component)

Gets path of component .c/.cpp file, and tests for its existence. 
Returns fullpath of file.

=cut

sub getComponentImplementationFile($) {
    my $comp=shift;

    checkComponentName($comp);
    my $bp = getComponentBasepath($comp);

    my $file1;
    my $file2;

    my $found=retry_eitherof("$bp.cpp","$bp.c");
    $found==3 and die "ERROR: both $bp.c and $bp.cpp exist for $comp";
    $file1 = "$bp.cpp" if $found==1;
    $file2 = "$bp.c" if $found==2;

    ! $file1 and ! $file2 and 
      die "ERROR: cannot find implementation file for $comp";

    return $file1 if $file1;
    return $file2;
}

#----------

=head1 getComponentTestFile(component)

Gets full path of component .t.c/.cpp file, and tests for its existence.
Returns fullpath of file.

=cut

sub getComponentTestFile($) {
    my $comp = shift;
    checkComponentName($comp);

    my $file1;
    my $file2;
    my $bp = getComponentBasepath($comp);

    $bp .= ".t";
    my $found=retry_eitherof("$bp.cpp","$bp.c");
    $found==3 and die "ERROR: both $bp.c and $bp.cpp exist for $comp";
    $file1 = "$bp.cpp" if $found==1;
    $file2 = "$bp.c" if $found==2;

    $file1 and $file2 and 
      die "ERROR: both $bp.c and $bp.cpp exist for $comp";

    ! $file1 and ! $file2 and 
      die "ERROR: cannot find implementation file for $comp";

    return $file1 if $file1;
    return $file2;
}

#----------

=head1 getComponentAssemblyFile(component,architecture)

Gets full path of component .<arch>.s file, and tests for its existence.
Returns fullpath of file. NOTE: unlike other routines here, this file
is optional and so failing to locate the file does not cause a die.
Returns: filname if it exists, empty string otherwise.

=cut

sub getComponentAssemblyFile($$) {
    my ($comp,$arch) = @_;

    checkComponentName($comp);

    my $file = getComponentBasepath($comp).".$arch.s";
    #return "" unless retry $file; #need a faster way to do this
    return "" unless -f $file;

    return $file;
}

#----------

=head1 checkComponentName(component)

Checks for valid component name.

=cut

sub checkComponentName($) {
    my $comp = shift;

    $comp =~ /[A-Z]/ and die "ERROR: component cannot have UC chars: '$comp'";
}

#----------

=head1 readGroupMemFile(group)

Extracts list of packages from package group .mem file.

=head2 returns: list of packages

=cut

sub _readGroupMemFile($) {
    my $group = shift;
    my $member_file = getGroupMemFile($group);
    my @pkgs;

    $member_file or die "ERROR: cannot obtain group member list for '$group'";

    unless (-d dirname($member_file)) {
        die "ERROR: no group control directory (" . dirname($member_file) .
            ") for group '$group'";
    }

    die "ERROR: member file $member_file not found"
      unless retry_file $member_file;

    my $FIN=new IO::File;
    if (retry_file $member_file) {        # read list of members
        retry_open($FIN, "< $member_file") or 
                die "ERROR: cannot open '$member_file': $!";

        while (<$FIN>) {
            next if /^\s*$/ or /^\s*\#/;
            foreach my $pkg (split) {
                $pkg !~ /^$group\S+$/ and
                  die "ERROR: $member_file:$.: bad package name: $pkg";
                push @pkgs, $pkg;
            }
        }

        close $FIN;
    }

    @pkgs and print "-- $group contains @pkgs\n" or
        warning("$group member file $member_file empty");

    return @pkgs;
}

{
    my %group_packages;

    sub readGroupMemFile ($) {
	unless (exists $group_packages{$_[0]}) {
            $group_packages{$_[0]} = [ _readGroupMemFile($_[0]) ];
        }

	return @{$group_packages{$_[0]}};
    }
}

#----------

=head1 readPackageMemFile(package)

Extracts list of components from package .mem file. Returns list of
components.

=cut

sub _readPackageMemFile($) {
    my $pkg = shift;
    my $member_file = getPackageMemFile($pkg);
    my @comps;

    unless ($member_file) {
        die "ERROR: cannot obtain package member list for '$pkg'";
    }

    die "ERROR: member file $member_file not found"
      unless retry_file $member_file;

    my $FIN=new IO::File;
    if (retry_file $member_file) {        # read list of members
        retry_open($FIN, "< $member_file") or
            die "ERROR: cannot open '$member_file': $!";
        while (<$FIN>) {
            next if /^\s*$/ or /^\s*\#/;        # skip comments
            foreach my $comp (split) {
		unless (isNonCompliant $pkg) {
		    $comp !~ /^$pkg\_\S+$/ and
		      die "ERROR: $member_file:$.: bad component name: $comp";
		}
                push @comps, $comp;
            }
        }
        close $FIN;
    }

    @comps and print "-- $pkg contains @comps\n" or
        warning("package member file $member_file empty");

    return @comps;
}

{
    my %package_components;

    sub readPackageMemFile ($) {
	unless (exists $package_components{$_[0]}) {
            $package_components{$_[0]} = [ _readPackageMemFile($_[0]) ];
        }

	return @{$package_components{$_[0]}};
    }
}

#----------

=head1 scanPackageDirectory(regex)

Extracts list of files matching the specified regex

=cut

sub scanPackageDirectory ($$) {
    my ($package,$regex)=@_;

    my $packagedir=getPackageDir($package);
    opendir(DIR,$packagedir) || die "Can't open $packagedir: $!";
    my @files = sort grep { /$regex/ && -f "$packagedir/$_" } readdir(DIR);
    closedir DIR;

    return @files;
}

#----------
# mksymlink
#----------

sub mksymlink($$) {
    my ($fpath, $symlink) = @_;
    if (-e $symlink) {
        if (! -l $symlink || (readlink($symlink) ne $fpath)) {
            # file exists but is not a link, or link is to the wrong place
            die "ERROR: could not link $fpath to $symlink: existing file in the way";
        }
        # link exists and points to the right place - do nothing
    } else {
        symlink($fpath, $symlink) || die "ERROR: could not link $fpath to $symlink: $!";
    }
}

#----------
# mkDotOCompCmd - make cmd to compile .o
#----------

sub mkDotOCompCmd($;$) {
    my ($impl,$flags) = @_;
    my $retstr;

    my $EXPDECL;

    if ($impl =~ /\.c$/) {
        $retstr = "\n\t\$(CC) \$(CFLAGS) ".($flags?"$flags ":"").
	  "\$(OBJ_OPT) $impl\n\n";
    } elsif ($impl =~ /\.cpp$/ || $impl =~ /\.h$/) {
        $retstr = "\n\t\$(CXX) \$(CXXFLAGS) ".($flags?"$flags ":"").
	  "\$(OBJ_OPT) $impl\n\n";
    } else {
        die "ERROR: bad component file: '$impl'";
    }
    return $retstr;
}

#----------
# mkDotOAssyCmd - make cmd to compile .o from .s
#----------

sub mkDotOAssyCmd($) {
    my ($impl) = @_;
    my $retstr;

    if ($impl =~ /\.s$/) {
        $retstr = "\n\t\$(AS) \$(ASFLAGS) -o \$@ $impl\n\n";
    } else {
        die "ERROR: bad assembly file: '$impl'";
    }
    return $retstr;
}

#===============================================================================

1;
