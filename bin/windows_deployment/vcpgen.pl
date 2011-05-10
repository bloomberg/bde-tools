#/somewhere/you/must/have/perl

use warnings;
use strict;
use Getopt::Long;
use Data::Dumper;
require File::Copy;

# These paths need to update to relate to environment variables created by
# their own install package.
my $openssl_path = '$(ROOT_OPENSSL)';
my $xercesc_path = '$(ROOT_XERCESC)';

my $verbose = 0;
my @projects = ();
my @atests = ();
my @arch = qw(Win32 x64);
my @cfg = qw(Debug Release Debug_dllrt Release_dllrt);
my $BDE_ROOT = '';
my @locations = ();
my $target = "vs2008";
my $loadDepends = 0;
my $includecopydir = undef;

if (!GetOptions("root|r=s"     => \$BDE_ROOT,
		"location|l=s" => \@locations,
		"target|t=s"   => \$target,
		"openssl=s"    => \$openssl_path,
		"xercesc=s"    => \$xercesc_path,
		"copyinc|c=s"  => \$includecopydir,
		"depends|d"    => \$loadDepends,
		"verbose|v"    => \$verbose))
{
	print <<'EOT';
Usage: vcpgen.pl [-r|--root     <bde root path>]
		[-l|--location <extra project location>]*
		[   --openssl  <custom path to openssl library]
		[   --xercesc  <custom path to xercesc library]
		[-c|--copyinc  <path to copy include headers to>]
		[-d|--depends] # search for and load dependencies automatically
		[-v|--verbose] # be more verbose
		<project>*
EOT
	exit 1;
}

$BDE_ROOT =~ s/\\?$/\\/;
#push @locations, "${BDE_ROOT}groups\\", "${BDE_ROOT}adapters\\", "${BDE_ROOT}applications\\";
push @locations, "${BDE_ROOT}groups\\", "${BDE_ROOT}adapters\\";
my ($vcproj_version, $sln_version, $sln_comment);

if ($target eq "vs2008") {
	$vcproj_version = "9.00";
	$sln_version = "10.00";
	$sln_comment = "# Visual Studio 2008";
# WE NO LONGER SUPPORT VC2005
#} elsif ($target eq "vs2005") {
#	$vcproj_version = "8.00";
#	$sln_version = "9.00";
#	$sln_comment = "# Visual Studio 2005";
} else {
	print "Invalid target: $target\n";
	exit 1;
}

@projects = @ARGV;

if (!@projects) {
	print "No projects defined\n";
	exit 1;
}

# The following configuration information also applies a "pre-parsed" set of
# options pulled from the .opt files for each package/group.  We *do not* attempt
# to parse the .opt files directly.
#
# The "configuration" and "tools" follow the same format: a list of key-value 
# pairs, where the key is a dot-separated list of filters, ending with
# the actual tool or attribute name, and optionally prefixed with "+" or "-". All
# filters must match for this entry to be used. Supported filters are:
# "app" : applies to application projects only (including test drivers)
# "lib" : applies to library projects only
# "test" : applies to test drivers only
# configuration-name : applies only to the specified configuration
# architecture-name : applies only to the specified architecture
# project-name : applies only to the specified project
# dep:project-name : applies only to projects dependent on the specified one
# xdep:project-name : applies to the specified project and dependent ones.
# The meaning of a filter starting with "!" is reversed.
# In case of a duplicate entry for the same attribute, an entry prefixed with
# "+" will be appended to the previous ones, an entry prefixed with "-" will
# overwrite the previous ones, and an unprefixed entry will produce an error.


my $vcproj_settings = [
	[
		'InheritedPropertySheets' => '[prj].vsprops',
		'+Debug.InheritedPropertySheets' => ';common_debug.vsprops',
		'+Release.InheritedPropertySheets' => ';common_release.vsprops',
		'+Win32.InheritedPropertySheets' => ';common_32.vsprops',
		'+x64.InheritedPropertySheets' => ';common_64.vsprops',
		'OutputDirectory' => '[cfg]_[arch]',
		'IntermediateDirectory' => '[cfg]_[arch]\\[prj]',
		'lib.ConfigurationType' => '4',
		'app.ConfigurationType' => '1',
		'CharacterSet' => '0',
		'utest.ExcludeBuckets' => '12;14'
	],
	'VCCLCompilerTool' => [
		'+dep:bsl.PreprocessorDefinitions' => ';BSL_OVERRIDES_STD',
		'+bde.PreprocessorDefinitions' => ';SUPPORT_UTF8;POSIX_MALLOC_THRESHOLD=10;NOPOSIX',
		'+xdep:bte.PreprocessorDefinitions' => ';FD_SETSIZE=256',
		'+xdep:a_xercesc.PreprocessorDefinitions' => ';XML_LIBRARY',
		'+dep:bas.PreprocessorDefinitions' => ';NO_FASTSEND;BAS_NOBBENV;BAS_NOBBCOM',
		'Release.RuntimeLibrary' => '0',
		'Debug.RuntimeLibrary' => '1',
		'-Release.dllrt.RuntimeLibrary' => '2',
		'-Debug.dllrt.RuntimeLibrary' => '3',
		'-app.DebugInformationFormat' => '3'
	],
	'lib.VCLibrarianTool' => [
		'OutputFile' => 'lib\\debug_static_win32\\[prj].lib',
		'-Debug.Win32.OutputFile' => 'lib\\debug_static_32\\[prj].lib',
		'-Debug.x64.OutputFile' => 'lib\\debug_static_64\\[prj].lib',
		'-Debug.dllrt.Win32.OutputFile' => 'lib\\debug_dynamic_32\\[prj].lib',
		'-Debug.dllrt.x64.OutputFile' => 'lib\\debug_dynamic_64\\[prj].lib',
		'-Release.Win32.OutputFile' => 'lib\\release_static_32\\[prj].lib',
		'-Release.x64.OutputFile' => 'lib\\release_static_64\\[prj].lib',
		'-Release.dllrt.Win32.OutputFile' => 'lib\\release_dynamic_32\\[prj].lib',
		'-Release.dllrt.x64.OutputFile' => 'lib\\release_dynamic_64\\[prj].lib'
	],
	'app.VCLinkerTool' => [ 
		'OutputFile' => '$(OutDir)\[sprj].exe',
		'+dep:a_ossl.AdditionalDependencies' => ' ssleay32.lib libeay32.lib',
		'+dep:a_xercesc.Debug.AdditionalDependencies' => ' Xerces-c_static_2D.lib',
		'+dep:a_xercesc.Release.AdditionalDependencies' => ' Xerces-c_static_2.lib',
		'+dep:a_ossl.AdditionalLibraryDirectories' => ';'.$openssl_path.'\lib',
		'+dep:a_xercesc.Win32.AdditionalLibraryDirectories' => ';'.$xercesc_path.'\Build\Win32\VC8\Static[cfg]',
		'+dep:a_xercesc.x64.AdditionalLibraryDirectories' => ';'.$xercesc_path.'\Build\Win64\VC8\Static[cfg]'
	],
];

my $vsprops_settings = [
        'VCCLCompilerTool' => [
		'AdditionalIncludeDirectories' => '[include]', 
        #'+dep:bsl.AdditionalIncludeDirectories' => ';[bsl]\bsl+stdhdrs',
	    '+dep:bsl.AdditionalIncludeDirectories' => ';$(DEV_PATH)\bsl\bsl+stdhdrs',
		'+xdep:a_ossl.AdditionalIncludeDirectories' => ';'.$openssl_path.'\\include',
		'+xdep:a_xercesc.AdditionalIncludeDirectories' => ';'.$xercesc_path.'\\src',
	],
	'VCResourceCompilerTool' => [
		'AdditionalIncludeDirectories' => '[include]'
	],
];


# =========
# MAIN CODE
# =========

my $depends = {};
my $missingDepends = {};
my $prjguid = {};
my $pathof = {};
my $prjtype = {};
my $include = {};
my $componentprj = {};
my $source = {};
my $group = {};

my $gotWin32API = 0;
{
  eval { 
  require Win32::API;
  $gotWin32API = 1;
  }
};

print "Target: $target\n";
print "Platforms: ",join(" ",@arch),"\n";
print "Configurations: ",join(" ",@cfg),"\n";
print "OpenSSL path: $openssl_path\n";
print "Xerces-C path: $xercesc_path\n";

for my $prj (@{[ @projects ]}) {
	loadProject($prj);
}

# =================================
# ACTUAL VCPROJ/SLN FILE GENERATION
# =================================

push @projects, @atests;

for my $g (@projects) {
	next if $g =~ /\.allt$/;
	generateVcproj($g);
	
	#AJM experimentation
	generateProjectPropSheets($g);	
}

generateSln();

# ================
# HELPER FUNCTIONS
# ================

sub loadProject {
	my $prj = shift;

	$prjguid->{$prj} = guidgen();
	for my $loc (@locations) {
		if(loadGroup($prj, "$loc$prj")
		or loadTopPackage($prj, "$loc$prj")
		or loadTest($prj)
		or loadUnityTest($prj)) 
		{
			print "$prj: ", join(",",@{$prjtype->{$prj}}),
				" -> ", join(",", @{$depends->{$prj}}), "\n";
			return;
		}
	}
#	die "unable to load $prj";
	print "IGNORING $prj";
}

sub guidgen {
    if (!$gotWin32API)  {
		# fall back to uuidgen
		my $r = `uuidgen /c`;
		chomp $r;
		return $r;
    }
    my $UuidCreate = new Win32::API('rpcrt4', 'UuidCreate', 'P', 'N');
    die 'Could not load UuidCreate from rpcrt4.dll' unless $UuidCreate;
    
    my $UuidToString = new Win32::API('rpcrt4', 'UuidToString', 'PP', 'N');
    die 'Could not load UuidToString from rpcrt4.dll' unless $UuidToString;
    
    my $RpcStringFree = new Win32::API('rpcrt4', 'RpcStringFree', 'P', 'N');
    die 'Could not load RpcStringFree from rpcrt4.dll' unless $RpcStringFree;
 
    my $uuid = "*" x 16; # Allocate enough space to store the uuid structure
    
    my $ret = $UuidCreate->Call( $uuid );
    die "UuidCreate failed with error: $ret" unless $ret == 0;
 
    my $ptr_str = pack("P",0);
    $ret = $UuidToString->Call( $uuid, $ptr_str );
    die "UuidToString failed with error: $ret" unless $ret == 0;
 
    my $guid_str = unpack( "p", $ptr_str );
 
    $ret = $RpcStringFree->Call( $ptr_str );
    die "RpcStringFree failed with error: $ret" unless $ret == 0;
 
    return uc($guid_str);
}

sub filter {
#	print Dumper($include);
#	die;

	my ($set,$a,$c,$prj) = @_;
	my $dep = $depends->{$prj};
	my $misdep = keys %{$missingDepends->{$prj}};
	my $sprj = $prj; $sprj =~ s/^[sm]_//;
#	print Dumper($prj,$include->{$prj}, $dep);
	my %subst = ( "cfg" => $c, "arch" => $a, "prj" => $prj, "sprj" => $sprj,
			"include" => join(";", @{$include->{$prj}}, map { @{$include->{$_}} } @$dep)
				);
				
	# hack in some patch-ups for the include path, using project macros rather than specific paths to allow easier retargetting
	my $bde_root = $BDE_ROOT . "groups";
	$bde_root =~ s/\\/\\\\/g;
	$subst{"include"} =~ s/$bde_root/\$(DEV_PATH)/g;
	$bde_root =~ s/groups$/adapters/;
	$subst{"include"} =~ s/$bde_root/\$(ADAPT_PATH)/g;
	
	my @cc = ($c);
	if ($c=~/_/) {
		push @cc, split("-",$c);
	}
	my %allowed = map {($_ => 1)} ($target,$a,$c,split("_",$c),$prj,@{$prjtype->{$prj}},
		(map {"dep:$_"} @$dep), (map {"xdep:$_"} ($prj,@$dep)));
#	if ($nopdep) { $allowed{"nopdep"} = 1; }
#	print Dumper({subst => \%subst, allowed => \%allowed});
	my $opt = undef;
	my %out = ();
	my @order = ();
	OPT: for my $v (@$set) {
		if (!defined $opt) { $opt=$v; next; }
		my $val = $v;
		my @ovlist;
		if ($opt =~ /\?\?\?/) {
			@ovlist = map { 
				my $oopt = $opt;
				$oopt=~s/\?\?\?/$_/g;
				my $vval = $val;
				$vval=~s/\?\?\?/$_/g;
				[$oopt,$vval]
			} @projects;
			
		} else {
			@ovlist = ([$opt,$val]);
		}
		for my $vv (@ovlist) {
			$opt=$vv->[0]; $val=$vv->[1];
			my $text = "$opt => $val";
			my $pfx = "";
			if ($opt =~ s/^([-+])//) { $pfx=$1; }
			my @filters = split /\./, $opt;
			$opt = pop @filters;
			if (ref($val) eq "") {
				$val =~ s/\[([a-z0-9+-_]+?)\]/
					exists $subst{$1} ? $subst{$1}
					: exists $pathof->{$1} ? $pathof->{$1}
					: die "Invalid macro $1 in $text"
				/egx;
			}
			for my $filter (@filters) {
				my $f = $filter;
				if ($f=~s/^\!// ? exists $allowed{$f} : !exists $allowed{$f}) {
					$opt = undef;
					next OPT;
				}
			}
			if (exists $out{$opt}) {
				if ($pfx eq "+") {
					$out{$opt} .= "$val";
#					$out{$opt} .= " $val";
				}
				elsif ($pfx eq "-") {
					$out{$opt} = $val;
				}
				else { 
					die "Duplicate entry for $opt";
				}
			} else {
				push @order, $opt;
				$out{$opt} = $val;
			}
		}
		$opt = undef;
	}
	return map {[ $_, $out{$_} ]} @order;
};

sub formatSettings {
	my $prefix = shift;
	return join("", map {sprintf("$prefix%s=\"%s\"\n",$_->[0],$_->[1])} filter(@_));
};

sub readmem {
	local *F;
#	printf "readmem %s\n", $_[0];
	open F,"<".$_[0] or return ();
	my @result = map { s/^\s+//; s/\s+$//; $_ } grep {!/^#/ and !/bsl\+apache/ and !/bsltst/ and !/bsl\+stdhdrs/ and !/^\[/ and /\S/} <F>; # HACK
	close F;
	return @result;
}

sub rdepends {
	my ($name, $path) = @_;
	my @dep = map { split " " } readmem($path);
	my %dep = ();
	for my $ddep (@dep) {
		if (!exists $depends->{$ddep}) {
			if ($loadDepends) {
				push @projects, $ddep;
				loadProject($ddep);
			} else {
				print "Ignoring unknown dependency of $name on $ddep\n";
				$missingDepends->{$name}->{$ddep} = 1;
				next;
			}
		}
		$dep{$ddep} = 1;
		for my $rdep (@{$depends->{$ddep}}) {
			$dep{$rdep} = 1;
		}
	}
	return [ keys %dep ];
};

sub loadGroup {
	my ($name, $path) = @_;
	print "Trying to loadGroup $name from $path\\group\n" if $verbose;
	my $memfile = "$path\\group\\$name.mem";
	my @mem = sort { $a cmp $b } readmem($memfile);
	return 0 unless @mem;
	$group->{$name} = [ @mem ];
	my @inc = ();
	for my $p (@mem) {
		loadPackage($p, "$path\\$p", $name) or die "unable to load $p";
		push @inc, @{$include->{$p}};
	}
	$include->{$name} = [ @inc ];
	$depends->{$name} = rdepends($name, "$path\\group\\$name.dep");
	$prjtype->{$name} = [ "lib" ];
	$pathof->{$name} = $path;
	return 1;
}

sub loadTopPackage {
	my ($name, $path) = @_;
	return 0 unless loadPackage($name, $path, $name);
	my $main =  "$path\\$name.m.cpp";
	if (!-f $main) {
		my $n = $name;
		$n =~ s/^[ms]_//i;
		$main = "$path\\$n.m.cpp";
	}
	if (-f $main) {
#		@{$source->{$name}} = grep { $_ ne $main } @{$source->{$name}};
		push @{$source->{$name}}, $main;
		$prjtype->{$name} = [ "app" ];
	} else {
		$prjtype->{$name} = [ "lib" ];
	}
	$depends->{$name} = rdepends($name, "$path\\package\\$name.dep");
	return 1;
}

sub loadPackage {
	my ($name, $path, $prj) = @_;
	my $mem = "$path\\package\\$name.mem";
	print "Trying to loadPackage $name from $mem\n" if $verbose;
	return 0 unless -f $mem;
	my @mem = sort { $a cmp $b } readmem($mem);
	if (@mem) {
		$source->{$name} = [ map {
								$pathof->{$_} = "$path\\$_";
								$componentprj->{$_} = $prj;
								("$path\\$_.cpp", "$path\\$_.h")
								} @mem ];
	}
	else {
		$source->{$name} = [ grep { $_!~/(?:_dum|_refs|\.m)\.(?:c|cpp)/i } (<$path\\*.cpp>, <$path\\*.c>, <$path\\*.h>) ];
	}
	if (defined $includecopydir) {
		for my $f (@{$source->{$name}}) {
			if ($f =~ /\.h$/) {
				my $dst = $f;
				$dst =~ s/^.*[\\\/]//;
				$dst = $includecopydir.$dst;
#				print "$f -> $dst\n";
				File::Copy::copy($f,$dst);
			}
		}
	}
	$include->{$name} = [ $path ];
	$pathof->{$name} = $path;
	return 1;
}

sub loadTest {
	my $name = shift;
	my $comp = $name;
	return 0 unless $comp =~ s/.t$//;
	return 0 unless exists $pathof->{$comp};
	my $src = $pathof->{$comp}.".t.cpp";
	return 0 unless -f $src;
	$include->{$name} = [ ];
	$source->{$name} = [ $src ];
	$depends->{$name} = [
		$componentprj->{$comp},
		@{$depends->{$componentprj->{$comp}}},
	];
	$prjtype->{$name} = [ "app", "test" ];
}

sub loadUnityPackage {
	my ($p, $path) = @_;
#	print "LUP,$p,$path\n";

	# we'll have to re-read the package
	my $memfile = "$path\\package\\$p.mem";
	return unless -f $memfile;
	my @pkg = readmem($memfile);
	my @testfiles = ();
	for my $c (@pkg) {
		my $tcpp = "$path\\$c.t.cpp";
		if (-f $tcpp) {
			push @testfiles, $tcpp;
#			push @$tests, $c;
		}
	}
	$source->{$p.".ut"} = [ @testfiles ];
}

sub loadUnityTest {
	my $name = shift;
	my $prj = $name;
#	print "$prj\n";
	return 0 unless $prj =~ s/.ut$//;
	my $path = $pathof->{$prj};
	if (exists $group->{$prj}) {
		my @utgroup = ();
		my @mem = @{$group->{$prj}};
		for my $p (@mem) {
			loadUnityPackage($p, "$path\\$p");
			push @utgroup, $p.".ut";
		}
		$group->{$name} = [ @utgroup ];
	} else {
		loadUnityPackage($prj, $path)
	}
	$include->{$name} = $include->{$prj};
	$depends->{$name} = [ $prj, @{$depends->{$prj}} ];
	$prjtype->{$name} = [ "app", "utest" ];
	$pathof->{$name} = "";
	return 1;
}

sub printConfig
{
	my ($prj,$toolsettings) = @_;
	my @ts = @$toolsettings;
	my $cs = undef;
	if (ref($ts[0]) eq "ARRAY") {
		$cs = shift @ts;
	}
	for my $c (@cfg) {
		for my $a (@arch) {
			print F "\t\t<Configuration Name=\"$c|$a\"\n";
			if ($cs) {
				print F formatSettings("\t\t\t",$cs,$a,$c,$prj);
			}
			print F "\t\t\t>\n";
			
			for my $tool (filter(\@ts,$a,$c,$prj)) {
				my ($name, $set) = @$tool;
				print F "\t\t\t<Tool Name=\"$name\"\n";
				print F formatSettings("\t\t\t\t",$set,$a,$c,$prj);
				print F "\t\t\t/>\n"
			}
			print F "\t\t</Configuration>\n";
		}
	}
}

sub generateVcproj 
{
	my $prj = shift;
	my $guid = $prjguid->{$prj};
	die "Undefined guid for $prj" unless defined $guid;
	open F,">$prj.vcproj";
	print F  <<"EOT";
<?xml version="1.0" encoding="Windows-1252"?>
<VisualStudioProject
\tProjectType="Visual C++"
\tVersion="$vcproj_version"
\tName="$prj"
\tProjectGUID="{$guid}"
\tRootNamespace="$prj"
\tKeyword="Win32Proj"
\tTargetFrameworkVersion="131072"
\t>
\t<Platforms>
EOT
	for my $a (@arch) {
		print F "\t\t<Platform Name=\"$a\"/>\n";
	}
	print F  <<"EOT";
\t</Platforms>
\t<ToolFiles>
\t</ToolFiles>
\t<Configurations>
EOT
	printConfig($prj,$vcproj_settings);

	print F  <<"EOT";
\t</Configurations>
\t<References>
\t</References>
\t<Files>
EOT
	# source files
	if ($group->{$prj}) {
		for my $p (@{$group->{$prj}}) {
			print F "\t\t<Filter Name=\"$p\">\n";
			for my $f (@{$source->{$p}}) {
			
				# hack in some patch-ups for the include path, using project macros rather than specific paths to allow easier retargetting
				my $bde_root = $BDE_ROOT . "groups";
				$bde_root =~ s/\\/\\\\/g;
				$f =~ s/$bde_root/\$(DEV_PATH)/g;
				$bde_root =~ s/groups$/adapters/;
				$f =~ s/$bde_root/\$(ADAPT_PATH)/g;

				print F "\t\t\t<File RelativePath=\"$f\"/>\n";
			}
			print F "\t\t</Filter>\n";
		}
	} 
	else {
		for my $f (@{$source->{$prj}}) {

			# hack in some patch-ups for the include path, using project macros rather than specific paths to allow easier retargetting
			my $bde_root = $BDE_ROOT . "groups";
			$bde_root =~ s/\\/\\\\/g;
			$f =~ s/$bde_root/\$(DEV_PATH)/g;
			$bde_root =~ s/groups$/adapters/;
			$f =~ s/$bde_root/\$(ADAPT_PATH)/g;

			print F "\t\t<File RelativePath=\"$f\"/>\n";
		}
	}
	print F  <<"EOT";
\t</Files>
\t<Globals>
\t</Globals>
</VisualStudioProject>
EOT
	close F;
}

# subroutine to extract just the include paths for the compiler tools
sub printConfigSheet
{
	my ($prj,$toolsettings) = @_;
	my @ts = @$toolsettings;
	my $cs = undef;
	if (ref($ts[0]) eq "ARRAY") {
		$cs = shift @ts;
	}
	my $c = 'n/a';
	my $a = 'n/a';

	for my $tool (filter(\@ts,$a,$c,$prj)) {
		my ($name, $set) = @$tool;
		print F "\t<Tool Name=\"$name\"\n";
		print F formatSettings("\t\t",$set,$a,$c,$prj);
		print F "\t/>\n"
	}
}

# generate a '/project/_paths.vsprops' property sheet, that sets paths for the various tools
# ideally want a single vsprops to share between lib project and its unit tests
sub generateProjectPropSheets 
{
	my $prj = shift;
	my $sheetname = $prj;
	open F,">$sheetname.vsprops";
	print F  <<"EOT";
<?xml version="1.0" encoding="Windows-1252"?>
<VisualStudioPropertySheet
\tProjectType="Visual C++"
\tVersion="8.00"
EOT
	print F "\tName=\"$sheetname\"\n\t>\n";

	printConfigSheet($prj,$vsprops_settings);

	print F  "</VisualStudioPropertySheet>\n";
	
	close F;
}

sub generateSln {
	open F, ">build.sln";
	print F "Microsoft Visual Studio Solution File, Format Version $sln_version\n";
	print F "$sln_comment\n";
	my $slnguid = guidgen();
	for my $prj (reverse (@projects)) {
		next if $prj =~ /\.allt$/;
		my $guid = $prjguid->{$prj};
		print F <<"EOT";
Project("{$slnguid}") = "$prj", "$prj.vcproj", "{$guid}"
\tProjectSection(ProjectDependencies) = postProject
EOT
		for my $dep (@{$depends->{$prj}}) {
			my $dguid = $prjguid->{$dep};
			print F "\t\t{$dguid} = {$dguid}\n";
		}
		print F <<"EOT";
\tEndProjectSection
EndProject
EOT
	}
	print F <<"EOT";
Global
\tGlobalSection(SolutionConfigurationPlatforms) = preSolution
EOT
	for my $c (@cfg) {
		for my $a (@arch) {
			print F "\t\t$c|$a = $c|$a\n";
		}
	}
	print F <<"EOT";
\tEndGlobalSection
\tGlobalSection(ProjectConfigurationPlatforms) = postSolution
EOT
	for my $prj (@projects) {
		next if $prj =~ /\.allt$/;
		my $guid = $prjguid->{$prj};
		for my $c (@cfg) {
			for my $a (@arch) {
				print F "\t\t{$guid}.$c|$a.ActiveCfg = $c|$a\n";
				print F "\t\t{$guid}.$c|$a.Build.0 = $c|$a\n";
			}
		}
	}
	print F <<"EOT";
\tEndGlobalSection
\tGlobalSection(SolutionProperties) = preSolution
\t\tHideSolutionNode = FALSE
\tEndGlobalSection
EndGlobal
EOT
	close F;
}
