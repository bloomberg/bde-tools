package Change::Identity;
use strict;

use base qw(Exporter);
use vars qw(@EXPORT_OK);

use Cwd 'abs_path';

#   Standard Exports         Deprecated alternatives
@EXPORT_OK=qw[
    getLocationOfStage
    getRootLocationOfStage

    getStageRoot
    getStageLocationOfTarget getStageLocationOfUOR

    identifyLocation
    identifyPlace
    identifyName
    identifyProductionName
    lookupLocation           locationFromName
    lookupPlace
    lookupName
    lookupProductionName

    setLocationPlaceName

    deriveTargetfromName     deriveUORfromName
    deriveTargetfromFile     deriveUORfromFile

    cached_rel2abs
];

use Util::File::Basename qw(dirname basename fileparse);

use BDE::FileSystem;
use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Util::Nomenclature qw(
    getCanonicalUOR getSubdirsRelativeToUOR isNonCompliantUOR getRootDevEnvUOR
    isGroup
);

use Util::Message qw(fatal warning debug debug2);

use Change::Symbols qw(
    MOVE_BUGFIX MOVE_EMERGENCY STAGE_INTEGRATION

    STAGE_PRODUCTION  STAGE_PRODUCTION_ROOT STAGE_PRODUCTION_LOCN
    STAGE_BETA        STAGE_BETA_ROOT       STAGE_BETA_LOCN
    STAGE_ALPHA       STAGE_ALPHA_ROOT      STAGE_ALPHA_LOCN
    STAGE_PREALPHA    STAGE_PREALPHA_ROOT   STAGE_PREALPHA_LOCN
    STAGE_DEPARTMENT  STAGE_DEPARTMENT_ROOT STAGE_DEPARTMENT_LOCN
    STAGE_DEVELOPMENT
);
use Symbols qw(ROOT FILESYSTEM_NO_LOCAL FILESYSTEM_NO_DEFAULT);

#==============================================================================

=head1 NAME

Change::Identity - Routines for file and UOR locations and path manipulation

=head1 SYNOPSIS

    use Change::Identify(deriveUORfromName deriveUORfromFile);

    my $library=deriveUORfromFile($file);

=head1 DESCRIPTION

C<Change::Identity> encapsulates logic to derive the library name and related
information such as the relative path of a file under the library location
and the full path to that location. It works primarily through the
L<"deriveUORfromFile"> and L<"deriveUORfromName"> routines, which carve
up the supplied pathname into directories and then attempt to identify a
library that corresponds to each directory in turn, scanning last to first
until a match is found or the first directory (i.e. the root) is reached.

The implementation details of this module are somewhat fluid as the underlying
logic of legacy library name handling and the production location of
well-formed units of release is subject to change. See the
L<bde_createcs.pl> and L<bde_compilecs.pl> tools for examples of how the
routines in this module are actually used.

A variety of level one and level two debug information is available if
debug messages (see L<Util::Message/set_debug>) are enabled.

=head2 Note on Library/Target/Path vs Name/Place/Location

Note that a 'place' in this module is the same thing as a 'target' described
elsewhere (e.g. L<Change::File>.). Similarly, a 'name' is the same as a
library, and a location is just a full path. The alternate nomenclature used
here is mostly historical and may be transitioned in time.

=cut

#==============================================================================

=head1 BASE STAGE CONFIGURATION INFORMATION FUNCTIONS

These functions return basic information about the configuration of the
various stages.

=head2 getStageRoot($stage)

Return a correctly configured L<BDE::FileSystem> instance for the specified
stage. If the stage is C<STAGE_DEVELOPMENT> (defined in L<Change::Symbols>),
a normal development-oriented filesystem object is returned. Otherwise,
a filesystem object restricted to searching the root for the specified stage
and the link root (a.k.a. I<lroot>) cache is returned.

I<Note: The constructed filesystem object is cached internally and reused if a
request for the same root is made. This means that alteration of the instance
properties will affect all future requests for a filesystem instance for the
same stage.>

=cut

{ my %roots;

  sub getStageRoot ($) {
      my $stage=shift;
      fatal "No stage!" unless $stage;

      unless (exists $roots{$stage}) {
	  my $stage_root=getRootLocationOfStage($stage);

	  if ($stage_root) {
	      $roots{$stage}=new BDE::FileSystem($stage_root);
	      $roots{$stage}->setPath(undef);
	      #only use CONSTANT_PATH for these stage roots (see B::FS)

	      $roots{$stage}->setSearchMode(FILESYSTEM_NO_LOCAL
					    | FILESYSTEM_NO_DEFAULT);
	  } else {
	      #normal unrestructed 'development' root, PATH & CONSTANT_PATH
	      $roots{$stage}=new BDE::FileSystem(ROOT);
	  }
      }

      return $roots{$stage};
  }
}

=head2 getLocationOfStage($stage)

Return the base location for the specified stage. For production this is
C</bbsrc>.

=cut

{
  my %map=(
	   STAGE_PRODUCTION()  => STAGE_PRODUCTION_LOCN(),
	   STAGE_BETA()        => STAGE_BETA_LOCN(),
	   STAGE_ALPHA()       => STAGE_ALPHA_LOCN(),
	   STAGE_PREALPHA()    => STAGE_PREALPHA_LOCN(),
	   STAGE_DEPARTMENT()  => STAGE_DEPARTMENT_LOCN(),
	   STAGE_DEVELOPMENT() => ""
	  );

  sub getLocationOfStage ($) {
      my $stage=shift;
      my $stage_root=$map{$stage};
      fatal "Stage '$stage' does not exist" unless defined $stage_root;

      return $stage_root;
  }

}

=head2 getRootLocationOfStage($stage)

Return the base development root location for the specified stage. For
production this is C</bbsrc/proot>.

=cut

{
  my %map=(
	   STAGE_PRODUCTION()  => STAGE_PRODUCTION_ROOT(),
	   STAGE_BETA()        => STAGE_BETA_ROOT(),
	   STAGE_ALPHA()       => STAGE_ALPHA_ROOT(),
	   STAGE_PREALPHA()    => STAGE_PREALPHA_ROOT(),
	   STAGE_DEPARTMENT()  => STAGE_DEPARTMENT_ROOT(),
	   STAGE_DEVELOPMENT() => ""
	  );

  sub getRootLocationOfStage ($) {
      my $stage=shift;
      my $stage_root=$map{$stage};
      fatal "Stage '$stage' does not exist" unless defined $stage_root;

      return $stage_root;
  }

}

#------------------------------------------------------------------------------
# somewhat private low-level identification routines

=head2 getStageLocationOfTarget($target,$stage)

Return the appropriate stage-qualified path for the specified target. This is
a convenience routine that simply calls L<"getLocationOfStage"> and appends a
directory separator and the specified target (valid or not).

=cut

sub getStageLocationOfTarget ($$) {
    my ($target,$stage)=@_;

    return getLocationOfStage($stage).$FS.$target;
}

{
    no warnings 'once';
    *getStageLocationOfUOR=\&getStageLocationOfTarget;
}

#--------
#<<<TODO: These are really BDE::FileSystem methods that are camped out here
#<<<TODO: for the initial implementation.

{ my %srcnames=(); my %dstnames=(); my %places=(); my %locns=();

  # set up a special case mapping, on demand. E.g. 'mlfiles'.
  # note that path may legitimately be 'undef' if the relationship between
  # location, place, and name is derived from another source than a path
  # analysis (mlfiles is a good example)
  sub setPathLocationPlaceName ($$$$$$) {
      my ($path,$locn,$place,$srcname,$dstname,$stage)=@_;

      debug2 "identified ".($path?$path:"<unpathed>").
	"\@$stage: place=$place srcname=$srcname dstname=$dstname locn=$locn";

      $places{$stage}{$path}=$place if $path;
      $places{$stage}{$place}=$place;
      #$places{$stage}{$locn}=$place; #locn<->uor, not <->target, disabling

      $srcnames{$stage}{$path}=$srcname if $path;
      $srcnames{$stage}{$place}=$srcname;
      $srcnames{$stage}{$locn}=$srcname;

      $dstnames{$stage}{$path}=$dstname if $path;
      $dstnames{$stage}{$place}=$dstname;
      $dstnames{$stage}{$locn}=$dstname;

      $locns{$stage}{$path}=$locn if $path;
      $locns{$stage}{$srcname}=$locn;
      $locns{$stage}{$place}=$locn;

      # 'short name' lookup
      # <<<TODO: what if the path is not supplied because it is not needed/known?
      if ($path) {
	  my $devenv_uor = getRootDevEnvUOR($path);

	  #$places{$stage}{$devenv_uor}=$place; #disabling. deuor/subdir=$place?
	  $srcnames{$stage}{$devenv_uor}=$srcname;
	  $dstnames{$stage}{$devenv_uor}=$dstname;
	  $locns{$stage}{$devenv_uor}=$locn;
      }

      if (Util::Message::get_debug() >= 3) {
	  print "[setPathLocationPlaceName] @_\n";

	  foreach my $stage (sort keys %places) {
	      foreach (sort keys %{$places{$stage}}) {
		  print "[($stage)] PLACES<$_>=",$places{$stage}{$_},"\n";
	      }
	      foreach (sort keys %{$srcnames{$stage}}) {
		  print "[($stage)] SNAMES <$_>=",$srcnames{$stage}{$_},"\n";
	      }
	      foreach (sort keys %{$dstnames{$stage}}) {
		  print "[($stage)] DNAMES <$_>=",$dstnames{$stage}{$_},"\n";
	      }
	      foreach (sort keys %{$locns{$stage}}) {
		  print "[($stage)] LOCNS <$_>=",$locns{$stage}{$_},"\n";
	      }
	  }
      }

  }

  sub setLocationPlaceName ($$$$) {
      my ($locn,$place,$name,$stage)=@_;
      return setPathLocationPlaceName(undef,$locn,$place,$name,$name,$stage);
  }

  sub _identify ($$;$);
  sub _identify ($$;$) {
      my ($path,$stage,$prepath)=@_;
      return 1 if exists $places{$stage}{$path}; #already been here

      debug2("identifying '$path'");

      my $proot = getStageRoot($stage);
      my $srcuor = getCanonicalUOR($path); #'source library' name
      
      return undef unless $srcuor;

      my $locn = eval { $proot->getPackageLocation($srcuor) };
      $locn = eval { $proot->getGroupLocation($srcuor) } unless $locn;
      return undef unless $locn;
      $locn = abs_path($locn);
      return undef unless (defined($locn) && -d $locn);

      my $dstuor=$locn;
      $dstuor=~s|^/bbsrc[^/]*/||;
      #<<<TODO: future-proof this.

      my $subdirs = getSubdirsRelativeToUOR($path) || "";
      my $target  = $subdirs ? $srcuor.$FS.$subdirs : $srcuor;

      return _identify($subdirs,$stage,substr($path,0,index($path,$subdirs)))
	if ($subdirs ne ""
	    && !(-d $locn.$FS.$subdirs)
	    && getCanonicalUOR($subdirs));

      ## Check that target directory exists
      return undef unless -d $locn.$FS.$subdirs;

      $path = $prepath.$path if $prepath and $prepath ne "";
      setPathLocationPlaceName($path,$locn,$target,$srcuor,$dstuor,$stage);
      return 1;
  }

  # --- identify routines - identify from the path, then return requested thing

=head1 IDENTIFICATION ROUTINES

Each of these routines identifies the supplied path and returns the requested
information. All related information is cached, so once a path has been
deconstructed, lookups from one aspect of it may be then made to find any other
with the lookup routines describe in L<"LOOKUP ROUTINES"> below.

=head2 identifyLocation($path,$stage)

Return the whole destination path under the SCM root, for this path. This is
the fully expanded pathname for the equivalent path under the requested stage.

=cut

  sub identifyLocation ($$) {
      my ($path,$stage)=@_;
      _identify $path,$stage;
      return $locns{$stage}{$path};
  }

=head2 identifyPlace($path,$stage)

Return the partial destination path (i.e, target), from UOR to the leaf
directory, for this path.

=cut

  sub identifyPlace ($$) {
      my ($path,$stage)=@_;
      return (_identify $path,$stage) ? $places{$stage}{$path} : undef;
  }

=head2 identifyName($path,$stage)

Return the 'UOR' (i.e, library name) under the SCM root, for this path.

=cut

  sub identifyName ($$) {
      my ($path,$stage)=@_;
      return (_identify $path,$stage) ? $srcnames{$stage}{$path} : undef;
  }

=head2 identifyName($path,$stage)

Return the final destination name of the library, when this is different to
its development-oriented name (for example for name mapping or amalgamation)

=cut

  sub identifyProductionName ($$) {
      my ($path,$stage)=@_;
      return (_identify $path,$stage) ? $dstnames{$stage}{$path} : undef;
  }

=head1 LOOKUP ROUTINES

These routines use previously identified path information to return a name,
place, or location from a supplied location, place, or name.

=head2 lookupLocation($name,$tage)

Return the whole destination path under the SCM root, for this name.
I<Presumes that the supplied name has already been identified from a path
with an identify routine, above>.

I<C<locationFromName>> is an older name for this function,

=cut

  sub lookupLocation ($$) {
      my ($name,$stage)=@_;

      return $locns{$stage}{$name} if exists $locns{$stage}{$name};
      # <<<TODO: why beta is mapped to integration.
      # the meaning of 'beta' currently applies to EMOVs only. It is likely
      # that this will change (i.e. 'stg=beta, mv=emov => stg=prod, mv=bemv)
      # for now, we map 'beta' to integration. cscheckin's logic regarding this
      # will ultimately need to 'get the stage and move type right' near the
      # top of the main block so that lookups of the right staging area are
      # performed correctly. Currently it does not do this because the staging
      # mechanics are not yet known. (i.e., what maps to what). A true SCM
      # will take over and provide this logic in time.
      return $locns{STAGE_INTEGRATION()}{$name};
  }

  {
      no warnings 'once';
      *locationFromName = \&lookupLocation;
  }

=head2 lookupName($name,$tage)

Return the library name under the SCM root, for this name, place, or location.
I<Presumes that the supplied name has already been identified from a path
with an identify routine, above>.

=cut

  sub lookupName ($$) {
      my ($place,$stage)=@_;

      return $srcnames{$stage}{$place} if exists $srcnames{$stage}{$place};
      return $srcnames{STAGE_INTEGRATION()}{$place};
  }

=head2 lookupProductionName($name,$tage)

Return the production library name for this name, place, or location.
I<Presumes that the supplied name has already been identified from a path
with an identify routine, above>.

=cut

  sub lookupProductionName ($$) {
      my ($place,$stage)=@_;

      return $dstnames{$stage}{$place} if exists $dstnames{$stage}{$place};
      return $dstnames{STAGE_INTEGRATION()}{$place};
  }

=head2 lookupPlace($name,$tage)

Return the place (i.e. target) under the SCM root, for this name, place, or
location.
I<Presumes that the supplied name has already been identified from a path
with an identify routine, above>.

=cut

  sub lookupPlace ($$) {
      my ($name,$stage)=@_;

      return $places{$stage}{$name} if exists $places{$stage}{$name};
      return $places{STAGE_INTEGRATION()}{$name};
  }
}

#------------------------------------------------------------------------------
# derive - wrappers for 'identify' functions

{ my %cache;

  sub cached_rel2abs ($) {
      my $file=shift;

      return $cache{$file} if exists $cache{$file};
      my ($base,$path)=fileparse $file;

      return $cache{$path}.$FS.$base if exists $cache{$path};

      my $absfile=Compat::File::Spec->rel2abs($file);

      $cache{$file}=$absfile;
      my $absdir=dirname($absfile);
      $cache{$path}=$absdir;

      return $absfile;
  }
}

=head1 HIGH-LEVEL IDENTIFICATION ROUTINES

These routines encapsulate the identification and lookup routines above.

=head2 deriveTargetFromFile($filename,$stage)

Return the target for the specified filename given the specified stage, using
local context if the filename is not absolute.

This routine calls L<"identifyPlace"> to extract the target, and so will
update the cache for lookup routines (described above).

=cut

# determine the robo/lib in '/local/dir/robo/lib/subdir/file.c'
# returns the lib plus trailing path: robo/lib/subdir
sub deriveTargetfromFile ($$) {
    my ($file,$stage)=@_;

    $file=cached_rel2abs($file);

    my $target;
    if ($file=~/\.(ml|msd|bst)$/) { #<<<TODO:get exts from symbol
	#<<<TODO: isCanonicalUOR also does this check but doesn't know
	#<<<TODO: to update _identity's cache, so duped here for now.
	$target="${1}files";
	setLocationPlaceName("/bbsrc/$target",$target,$target,$stage);
	#<<<TODO: fix up explicit 'bbsrc' later - direct call to _identify?
    } else {
	$target=identifyPlace(dirname($file),$stage);
    }

    debug "$file belongs to ".($target?$target:"*no known unit of release*");

    return $target;
}

{
    no warnings 'once';
    *deriveUORfromFile = \&deriveTargetfromFile;
}

=head2 deriveTargetFromName($simplename_or_directorypath,$stage)

Return the target for the specified directory path given the specified stage,
using local context if the directory path is not absolute, or alternatively
is a simple name such as C<acclib>.

This routine calls L<"identifyPlace"> to extract the target, and so will
update the cache for lookup routines (described above).

=cut

sub deriveTargetfromName ($$) {
    my ($name,$stage)=@_;

    #$name=Compat::File::Spec->rel2abs($name);
    my $target = identifyPlace($name,$stage);

    return $target;
}

{
    no warnings 'once';
    *deriveUORfromName = \&deriveTargetFromName;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_compilecs.pl>

=cut

1;
