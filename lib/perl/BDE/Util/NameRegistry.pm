package BDE::Util::NameRegistry;

use strict;
use Symbol ();
use Util::Message 'warning';
use Build::Option::Finder;
use Build::Option::Factory;
use BDE::FileSystem;
use BDE::Build::Uplid;
use BDE::Util::DependencyCache ();
use BDE::Util::Nomenclature qw(isGroup isIsolatedPackage);
use Util::Message qw(debug);
use Symbols qw[
    FILESYSTEM_PATH_ONLY    NAME_REGISTRY_LOCN
    FILESYSTEM_NO_DEFAULT   PATH_REGISTRY_LOCN
    FILESYSTEM_NO_CACHE     ROOT
];

#==============================================================================

=head1 NAME

BDE::Util::NameRegistry - Query authoritative repository of units-of-release names and recognized source locations

=head1 SYNOPSIS

     isRegisteredName($name)
       || warning("name $name is invalid or not available");

     prequalifyName($name)
       || warning("name $name base files are not properly set up");

     my $registered_names_ref = getRegisteredNames();
     my $registered_paths_ref = getRegisteredUniverse();

=head1 DESCRIPTION

C<BDE::Util::NameRegistry> provides support for querying the authoritative
list of registered names and source locations, and validating a submission
to register a new name.

=head1 ENVIRONMENT VARIABLES

C<BDE::Util::NameRegistry> makes use of several symbols that may be overridden
in the environment using one of the following environment variables.  These
values should not be overridden except for testing purposes.

    NAME_REGISTRY_LOCN - path to list of registered names
    PATH_REGISTRY_LOCN - path to list of registered source trees

See L<Symbols> for the default values of these symbols.

=cut

#==============================================================================

=head2 isRegisteredName()

Checks name registry for whether or not a name is registered.
Returns true if registered, false if not registered.

=cut

#------------------------------------------------------------------------------

sub isRegisteredName ($) {
    my $name = shift;
#    return isGroup($name) || isIsolatedPackage($name)
#      ? ((map { $name eq $_ && return 1 } @{getRegisteredNames()}), 0)
#      : (warning("Not a valid unit of release: $name"), undef);
    if (isGroup($name) || isIsolatedPackage($name)) {
	foreach (@{getRegisteredNames()}) {
	    return 1 if ($name eq $_);
	}
	return 0;
    }
    else {
	warning("Not a valid unit of release: $name");
	return undef;
    }
}

#------------------------------------------------------------------------------

=head2 prequalifyName()

Checks that the unit of release the name represents exists in one of the global
registered development roots, has a proper structure, and defines the required
ASSET_* macros in its capabilities file.

If passed a second optional argument to indicate that this is a preregistration
check, the name must not already be registered, and the rest of the validation
checks are performed to see if it is ready to be registered.  This is to be
used prior to submitting a DRQS IW to the BDE Group (101) to have the name
registered.

Required macros in the capabilities file (*.cap) are:
    CAPABILITY               supported platforms
    ASSET_OBJECT_NAME        name of library
    ASSET_OBJECT_DESC        brief description of library
    ASSET_DEPT_GROUP         department group number
    ASSET_CONTACT_PROG_1     programmer contact
    ASSET_PRODUCTION_LOCN    production RCS tree directory

=cut

#------------------------------------------------------------------------------

sub prequalifyName ($;$) {
    my($name,$register) = @_;
    my $status = isRegisteredName($name); ## validates name
    return 0 if ($register ? $status : !defined($status) || !$status);

    $ENV{BDE_PATH} = join  ':', @{getRegisteredUniverse()};
    my $root = new BDE::FileSystem(ROOT);
    $root->setSearchMode( FILESYSTEM_PATH_ONLY
			| FILESYSTEM_NO_DEFAULT
			| FILESYSTEM_NO_CACHE );
    
    my $locn = undef;
    eval { $locn = isGroup($name)
		 ? $root->getGroupLocation($name)
		 : $root->getPackageLocation($name) };
    defined($locn) && $locn ne ""
      || (chomp($@), debug($@),
	  warning("Unable to find $name in a "
		 ."registered global development root"),
	  warning("(Did you create it?)"),
	  return);

    # Check that required ASSET_* tags are defined in the package *.cap file

    BDE::Util::DependencyCache::setFileSystemRoot($root); #<<<TODO: temporary
    my $finder  = new Build::Option::Finder($root);
    my $factory = new Build::Option::Factory($finder);
    $factory->setDefaultUplid(new BDE::Build::Uplid);
    $factory->setDefaultUfid(new BDE::Build::Ufid("dbg_exc_mt"));
    my $options = $factory->construct($name);

    # XXX: RFE: abstract all ASSET_* labels and values into a structure that is
    # (more fully) validated and optionally updates info in SCANT and/or PWHO
    # XXX: Should we allow different contacts for different platforms?

    my $valid_assets = 1;

    my @ASSET_LABELS_REQUIRED = qw(
	CAPABILITY
	ASSET_OBJECT_NAME
	ASSET_OBJECT_DESC
	ASSET_DEPT_GROUP
	ASSET_CONTACT_PROG_1
	ASSET_PRODUCTION_LOCN
      );
    my $value;
    foreach my $asset_label (@ASSET_LABELS_REQUIRED) {
	$value = $options->getValue($asset_label);
	unless (defined($value) && $value ne '') {
	    warning("Undefined or empty $asset_label");
	    $valid_assets = 0;
	}
    }

    unless ($valid_assets) {
	warning("Please edit $locn/"
		.(isGroup($name) ? "group" : "package")
		."/$name.cap") if (!$valid_assets);
	warning("'perldoc BDE::Util::NameRegistry' for more information");
    }

    return $valid_assets;
}

#------------------------------------------------------------------------------

=head2 getRegisteredNames()

Returns a reference to a list of all registered names.

=head2 getRegisteredUniverse()

Returns a reference to a list of all registered universes (development roots).

=cut

#------------------------------------------------------------------------------

sub _slurpFlatRegistry ($) {
    local $/ = undef;
    my $FH = Symbol::gensym;
    return open($FH, '<'.$_[0])
      ? [ split /\s+/, <$FH> ]
      : (warning("Error opening $_[0]: $!"), []);
}

#------------------------------------------------------------------------------

sub getRegisteredNames () {
    return _slurpFlatRegistry(NAME_REGISTRY_LOCN);
}

#------------------------------------------------------------------------------

sub getRegisteredUniverse () {
    return _slurpFlatRegistry(PATH_REGISTRY_LOCN);
}

1;

#------------------------------------------------------------------------------

=head1 CAPABILITY FILE MACROS

  Metadata available in capability (*.cap) file.
  Note the similarity to PWHO fields; {HELP PWHO} for more information.
  Warning: excepting required capabilities, list below might change
  to conform with the developing PWHO, SCANT, SMOV, etc databases.

  ('*' entries are required)

  * CAPABILITY               supported platforms
  * ASSET_OBJECT_NAME        name of object (e.g. the library 'libbde')
  * ASSET_OBJECT_DESC        brief description of library
    ASSET_OBJECT_ID          identification number (a.k.a. PWHO ID)
    ASSET_FN_LINKS           function name linked to programming object
    ASSET_FN_MNEMONIC        function mnemonic
    ASSET_DB_NUMBER          database number(s) of db(s) used by object
    ASSET_DB_PCS             PCS number of database or server used
    ASSET_BIG_NAME           BIG name
    ASSET_YELLOW_KEY         associated yellow key
  * ASSET_PRODUCTION_LOCN    production RCS tree directory (/bbsrc/...)
  * ASSET_DEPT_GROUP         department group number
    ASSET_ARCH_GROUP         department acronym (e.g. ae fi gt ts ...)
    ASSET_CONTACT_BIZ_1      business contact
    ASSET_CONTACT_BIZ_2      business contact
    ASSET_CONTACT_DATA_1     data contact
    ASSET_CONTACT_DATA_2     data contact
    ASSET_CONTACT_QA_1       quality assurance contact
    ASSET_CONTACT_QA_2       quality assurance contact
    ASSET_CONTACT_HELP_1     help contact 
    ASSET_CONTACT_HELP_2     help contact 
  * ASSET_CONTACT_PROG_1     programmer contact
    ASSET_CONTACT_PROG_2     programmer contact
    ASSET_PINDEX             pindex number
    ASSET_RMDBEX             RMDBEX broadcase code
    ASSET_WIKI               WIKI page keywords
    ASSET_NOTES_GENERAL      general notes
    ASSET_NOTES_RELEASE      release notes
    ASSET_NOTES_HELP         help notes
    ASSET_KEYWORDS           keywords describing object

=cut

#==============================================================================

=head1 AUTHOR

Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<BDE::Util::Nomenclature>, L<BDE::FileSystem>, L<Build::Option::Finder>

=cut
