
package uorscan;

my $cachehome = "/bb/csdata/cache/aotools";
# my $cachehome = "/home/jmacd";
my $cache_file = "$cachehome/uor.cache";

use strict;
use FindBin ();
use lib '/bbsrc/bin/prod/lib/perl';
use lib "$FindBin::Bin/../../lib/perl";

use BDE::Group ();
use BDE::Package ();
use BDE::FileSystem::MultiFinder ();
use BDE::Util::DependencyCache ();
use BDE::Util::Nomenclature qw(isGroup getCanonicalUOR);
use Symbols qw(CONSTANT_PATH FILESYSTEM_PATH_ONLY FILESYSTEM_NO_DEFAULT);
use Util::Message qw(verbose warning);

use Exporter 'import';
our @EXPORT_OK = qw(libmap libgrepkey init_metadir);
our @EXPORT    = qw(libmap);

my $metadir;

my $warnings;
my $default_warnings = 1;

my @d1_list;
my @dr_list;

my %otherclass = (
    group	=>	'package',
    'package'	=>	'group',
    );

sub def_str {
    my $item = shift
	or return '';
    while( @_ ) {
	my $next = shift;
	exists $item->{$next}
	    or return '';
	$item = $item->{$next}
	    or return '';
    }
    return $item;
}


#------------------------------------------------------------------------------

sub scan_subpackages {
    my ($uor, $baseuor, $locn) = @_;
    my $fh;
    unless (opendir $fh, $locn) {
	warning("Unable to opendir $locn for $uor to check for sub-packages: $@");
	return;
    }
    for my $subdir (readdir $fh) {
	next if $subdir eq '.';
	next if $subdir eq '..';
	init_uor_info( "$uor/$subdir", 'package', "$locn/$subdir", $uor );
    }
}

sub init_uor_info {
    my ($uor, $type, $locn, $pgrp) = @_;

    # TODO: phantoms/foo is the official canonical name for now,
    #       but foo is what gets used for dependencies and will
    #       likely become the cananical name for all of them that
    #       are depended upon, so the leading phantoms/ is trimmed.
    $uor =~ s{^phantoms/}{};

    my $baseuor = $uor;
    $baseuor =~ s{.*/}{};

    my $entry = { type=>$type };
    $entry->{group} = $pgrp
	if $pgrp;

    # determine whether $locn is a symlink
    unless (lstat $locn) {
	warning("Unable to lstat lib $locn for $uor: $@")
	    unless $pgrp;
	return;
    }
    if (-l _) {
	$entry->{symname} = $locn;
	$locn = readlink $locn;
    }

    unless (-d $locn) {
	warning("Lib $locn for $uor is not a directory")
	    unless $pgrp;
	return;
    }
    $entry->{dir} = $locn;
    my $mdir = "$locn/$type";
    unless (-d $mdir) {
	warning("Lib $mdir for $uor is not a $type metadata directory")
	    unless $pgrp;
	return;
    }
    unless (-f "$mdir/$baseuor.dep") {
	warning("Metadata directory $mdir\n   for $uor\n   has no dep file: $baseuor.dep"
 	    . ((exists $entry->{symname})
		?"\n   symlink: $entry->{symname}"
		:''))
	    unless $pgrp;
	return;
    }
    $entry->{metadir} = "$mdir";

    $metadir->{$uor} = $entry;

    scan_subpackages( $uor, $baseuor, $locn )
	if $type eq 'group';
}

sub get_all_libs {
    my $root = BDE::FileSystem::MultiFinder->new(CONSTANT_PATH);
    $root->setPath("");
    $root->setSearchMode(FILESYSTEM_PATH_ONLY|FILESYSTEM_NO_DEFAULT);
    BDE::Util::DependencyCache::setFileSystemRoot($root); #<<<TODO: temporary

    my @uors = $root->findUniverse();

    foreach my $lib (@uors) {
	my ($uor, $type, $locn, $pkg );

	eval { $uor = getCanonicalUOR($lib) }
	  || (warning("Unable to determine canonical name for $lib: $@"), next);
print "Skipping dup $uor\n" and
	next if $metadir->{$uor};

	$type = isGroup($uor) ? 'group' : 'package';

	eval { $locn = (isGroup($uor)
			? $root->getGroupLocation($uor)
			: $root->getPackageLocation($uor)) }
	  || (warning("Unable to determine package location of $uor: $@"),next);
	# eval { $pkg = (isGroup($uor)
			# ? BDE::Group->new($locn)
			# : BDE::Package->new($locn)) }
	  # || (warning("Unable to instantiate BDE UOR object of $uor: $@"),next);
	init_uor_info( $uor, $type, $locn );
    }
}

{
    use Storable;

    # age (in hours) that is tolerable for re-using old cache data
    my $max_cache_age = 4;

    sub retrieve_metadir {
	if (-f $cache_file && (-M _)*24 < $max_cache_age) {
	    return $metadir = retrieve( $cache_file );
	}
    }

    sub store_metadir {
	store( $metadir, $cache_file )
	    or warn "Saving cache of uor info failed: ($!)\n";
    }

}

sub init_metadir {
    $warnings = shift if @_;
    $metadir = undef;
    if ( (exists $ENV{UOR_RELOAD} && $ENV{UOR_RELOAD})
	    or ! retrieve_metadir ) {
	get_all_libs;
	store_metadir;
    }
}

sub libmap {
    my( $lib ) = shift;
    init_metadir( $default_warnings ) unless $metadir;
    return unless exists $metadir->{$lib};
    return $metadir->{$lib};
}

sub libgrepkey {
    my( $pat ) = shift;
    init_metadir( $default_warnings ) unless $metadir;
    my @list = grep { /$pat/ } keys %$metadir;
    return @list;
}

1;
