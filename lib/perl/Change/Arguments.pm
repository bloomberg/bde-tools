package Change::Arguments;
use strict;

use base qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    parseArgumentsRaw
    identifyArguments
    getParsedTrailingLibraryArgument
    parseArguments
    parseArgumentsAsSourceCS
    checkForDuplicateFiles
    parseCheckoutArgumentsRaw
    identifyCheckoutArguments
];

use Util::File::Basename qw(basename dirname);

use Util::Message qw(error fatal warning);

use File::Spec;

use Change::AccessControl qw(getChangeSetManualReleaseState
			     getChangeSetStraightThroughState);
use Change::Set;
use Change::File;
use Change::Symbols qw(FILE_IS_UNKNOWN NUM_FILES_LIMIT $SUPPORTED_FILETYPES);

use Util::Message qw(verbose verbose2 debug debug3 warning);
use Change::Identity qw(
    deriveTargetfromName deriveTargetfromFile
    lookupName lookupPlace lookupProductionName identifyProductionName
    getLocationOfStage
);

use BDE::Build::Invocation qw($FS);
use BDE::Util::Nomenclature qw(getCanonicalUOR);
#==============================================================================

=head1 NAME

Change::Arguments - Parse supplied file list to derive candidate change set

=head1 SYNOPSIS

    use Change::Arguments qw(parseArguments);
    use Change::Symbols qw(STAGE_PRODUCTION STAGE_PRODUCTION_LOCN);
    use BDE::Filesystem;

    my $root=new BDE::FileSystem qw(STAGE_PRODUCTION_LOCN);
    my $candidateset=parseArguments($root,STAGE_PRODUCTION,0,undef,@ARGV);

=head1 DESCRIPTION

Routines to parse supplied arguments and derive candidate files and candidate
change sets from them. L<cscheckin> and L<cscompile> are the primary consumers
of the functionality provided by this module.

=cut

#==============================================================================

=head1 ROUTINES

=head2 parseArguments($root,$stage,$honordeps,$to,@items)

Parse the list of supplied items to identify their destination library and
their target (relative path under the root, see L<Change::File>), discard
any files that are not elegible, and return a change set of the analysed files
that remain. The arguments are as follows:

  root      - filesystem root (or derived class) object
  stage     - the destination stage, e.g. STAGE_INTEGRATION
  honordeps - also analyse dependent libraries (not yet implemented)
  to        - destination library override, if applicable
              (see C<--to> in cscompile)
  items     - list of relative or absolute pathnames to analyse

The returned change set contains L<Change::File> objects that have their
state set to C<FILE_IS_UNKNOWN> and have no set destination location (since
that has not yet been determined). This means that the change file objects
will evaluate to an empty string in string context. To have them evaluate
to the source locations use L<"parseArgumentsAsSourceCS">, below.

If no explicit destination library 'to' argument is supplied, the last item
is checked to see if it corresponds to a destination library. If it does,
it is stripped and applied as if it had been passed as the 'to' argument.
Applications that need to know when this takes place can extract the
result of this determination with L<"getParsedTrailingLibraryArgument">,
below.

Internally, C<parseArguments> is a basic wrapper for the following routines,
which can be called individually for finer control of the parsing process (for
example, for plugin support in L<cscheckin>, and is identical to:

    my $candidateset=parseArgumentsRaw($root,$stage,$honordeps,$to,@items);
    $to=getParsedTrailingLibraryArgument();
    return identifyArguments($root,$stage,$honordeps,$to,$candidateset);

=head2 parseArgumentsRaw($root,$stage,$honordeps,$to,@items)

Parses the list of supplied items and returns a new list of elegible items,
with archives, object files, and other 'disqualified' files removed. The
trailing library argument is also removed and noted internally.

In list context, returns the list of files preserved, in the order they were
submitted. In scalar contect, returns a candidate change set object instance.

=head2 getParsedTrailingLibraryArgument()

Return the trailing library argument, if detected, that was removed by the
previous call to L<"parseArgumentsRaw">. If an explicit C<to> was passed to
that function it is returned by this one.

=head2 identifyArguments($root,$stage,$honordeps,$to,@parsed_items)

Given a list of items, determine where they belong based on their context,
including the current working directory. The list of items is typically that
returned by L<"parseArgumentsRaw"> and is already filtered to remove
undesirables. In these cases, the L<to> argument is typically derived from
L<"getParsedTrailingLibraryArgument"> (and is C<undef> if no explicit library
was passed or extracted from the original list of items).

If a change file already has a target associated with it, that target is used
instead of attempting to derive it from the local context or using the passed
C<to> value (if set). This allows the pre-find plugin method to assign targets
prior to this routine being invoked. (See L<Change::Plugin::FileMap> for an
example).

=cut

{ my $realto;

  sub parseArgumentsRaw ($$$$$@) {
      my ($root,$forlist,$stage,$honordeps,$to,@args)=@_;
      
      # remove trailing library argument, if present
      if ($args[-1]!~/\*/ and not -f $args[-1]) {
	  if ($args[-1]=~/^\//) {
	      error "$args[-1] is not a valid destination target";
	      fatal "specify a library or offline target, not a path";
	  }
	  if (my $uor=deriveTargetfromName $args[-1],$stage) {
	      fatal "Explicit destination '$to' conflicts with ".
		"trailing implicit destination '$uor'"
		  if $to and ($to ne $uor); #can't specify '--to foo foo.c bar'
	      pop @args; #last arg is destination
	      $realto=$uor;
	  } else {
	      #doesn't exist, isn't a library, will be caught below
	      $realto=undef;
	  }
      } elsif ($to) {
	  if ($to=~/^\//) {
	      error "$to is not a valid destination target";
	      fatal "specify a library or offline target, not a path";
	  }
	  $realto=deriveTargetfromName $to,$stage; #check it's real
	  fatal "specified destination '$to' is not valid" unless $realto;
      } else {
	$realto=undef;
      }

      $realto =~ s{/$}{} if defined $realto;

      # pare down supplied filenames to those elegible for consideration
      my @items;
      my $missing=0;
      foreach my $item (@args) {
	  if ($item=~/\*/) {
	      # unexpanded wildcard in name, no matches
	      error "wildcard '$item' matches no files";
	      $missing++;
	      next;
	  }

	  my $base=basename($item);
	  next if $base=~/^\W/;       # ignore files starting with non-word chr
	  next if $base=~/\W$/;       # ignore files ending with non-word chr
	  next if $base=~/,v$/;       # skip local RCS files
	  next if $base=~/NORCSID/;   # skip 'NORCSID' backup files
	  next if $item=~/\.o(bj)?$/; # skip objects <<<TODO:get from symbol

	  my $real;
	  if (-l $item) {
	      $real=readlink $item;
	      if ($real!~/^\// and dirname($item)) {
		  $real=dirname($item).'/'.$real;
	      }
	  } else {
	      $real=$item;
	  }

	  unless (-e $real) {
	      if ($item eq $real) {
		  error "file '$real' not found";
	      } else {
		  error "link '$item' pointing to '$real' is broken";
	      }
	      $missing++;
	      next;
	  }

	  next if -d $real;           # skip directories and directory links

	  # if it is a unknown lib 'f_xx'. It should be found above
	  # before SUPPORT_FILE check
	  if ($base =~ /\./) {
	      unless ($base =~ /\.(?:$SUPPORTED_FILETYPES)$/) {
		  fatal("file type not supported: $base");
		  next;
	      }
	  }
	  
	  $item=~/^(.*)$/ and $item=$1; #untain
	  push @items,$item;
      }
      fatal "one or more specified files are missing" if $missing;

      fatal "number of files in change set exceeds limit (".NUM_FILES_LIMIT.")"
	if (scalar @items > NUM_FILES_LIMIT && !$forlist);

      # list context return
      return @items if wantarray;

      # scalar context return
      my $candidateset=new Change::Set({stage=>$stage});
      foreach my $item (@items) {
	  $candidateset->addFile($realto,$item,undef,FILE_IS_UNKNOWN,
				 undef,undef); #lib and prdlib unknown as yet
      }

      return $candidateset;
  }

 # checkout acclib/prqs*
    # FUNCTION: expand the wildcard
    # get the stage location and then then expand all the files.
    # 'ls $LOCN/prqs*,v' |  
    # List all the files. Ask the question if user wants to continue(y/n)
    # Create that changeset.
  sub expand_wildcard($$$$) {
       my ($item, $stage, $realto, $yes) = @_;
       my $changeset=new Change::Set({stage=>$stage});
       verbose "Expand wildcard: $item";
       # this is done purely to make use of file object. 
       $changeset->addFile(undef, $item, undef, FILE_IS_UNKNOWN,
			   undef, undef);
       # get the file object
       my $file = ($changeset->getFiles)[0];
       # get its source 
       my $source = $file->getSource();
       my $target;
       if ($realto) {
	   # if there is realto you dont want to do derivetarget
	    $target=$file->getTarget() || $realto;
	} else {
	    $target=$file->getTarget() ||
	      deriveTargetfromFile($source,$stage); #identifies
	    fatal "Can't guess the library for '".$file->getLeafName().
		"'. Please provide it explicitly." unless $target;
	}
       debug3 "Realto: $realto " if $realto;
       debug3 "Target: $target " if $target;
       my $prdlib=identifyProductionName($target,$stage);
       my $lib=lookupName($target,$stage);
       debug3 "Production Target: $prdlib " if $prdlib;
       # this is required below to retrieve correct prod target value
       $file->setTarget($target);
       $file->setLibrary($lib);
       $file->setProductionLibrary($prdlib);

	#identifies, redundantly if deriveTargetfromFile was hit
       fatal "'$target' is not a legal library/target name"
	   unless $prdlib;   
       my $stagelocn=getLocationOfStage($stage).$FS.$file->getProductionTarget;
       my $leafname=$file->getLeafName();
       my $stagefile=$stagelocn.$FS.$leafname;       

       my $bfile = basename $item; 
       my @allfiles1 = glob $stagelocn.$FS.$bfile.",v";
       my @allfiles2 = glob $stagelocn.$FS.'RCS'.$FS.$bfile.",v";
       my @files;
       my $count1 = scalar(@allfiles1);
       my $count2 = scalar(@allfiles2);
        # if both are present, then there is a problem
       # else
       #   check if all files only, remove directories
       # ask question to user, there are X files. want to continue y/n
       # if n, then fatal error.
       # if yes, then return all files

       if($count1 == 0 && $count2 == 0) {
	   fatal "No file found with wildcard match: '$item' in '$prdlib'";
       }
       if($count1 != 0 && $count2 != 0) {
	   fatal "Found too many files. Be more specific.";
       }
       
       if($count1 !=0) {
	   @files = @allfiles1;
       } elsif($count2 !=0) {
	   @files = @allfiles2;
       }

       $changeset->removeAllFiles();

       # below is expansion of wildcard with source path prepended.
       # identifyArguments function depends on either target specified OR 
       # source to identify correct library.
       # above is done for cases when cscheckout is run as
       # cscheckout <dir>/file*inc,  cscheckout <dir>/file*
       $source = $file->getTarget();
       foreach $bfile (@files) {
	   $bfile =~ s/,v//;
	   # add the lib path so that identifyArgument work properly.
	   $bfile = $source.$FS.basename($bfile);
	   debug3 "bfile added to changeset: $bfile\n";
       }
       return @files;
   }

   # $checkout suggests if it is called as checkout or copyout
   sub parseCheckoutArgumentsRaw ($$$$$$$@) {
      my ($root,$listonly,$stage,$honordeps,$to,$checkout,$yes,@args)=@_;

      verbose "Parse checkout Arguments";

      # file-support indirectly checks if last argument is a file/directory
      # remove trailing library argument, if present
      if ($args[-1]!~/\*/ && $args[-1] !~ /\.(?:$SUPPORTED_FILETYPES)$/) {
	  if ($args[-1]=~/^\//) {
	      error "$args[-1] is not a valid destination target";
	      fatal "specify a library or offline target, not a path";
	  }
	  if (my $uor=deriveTargetfromName $args[-1],$stage) {
	      fatal "Explicit destination '$to' conflicts with ".
		  "trailing implicit destination '$uor'"
		    if $to and ($to ne $uor); #can't specify --to foo foo.c bar
	      pop @args; #last arg is destination
	      $realto=$uor;
	  } else {
	      #doesn't exist, isn't a library, will be caught below
	      $realto=undef;
	  }
	  # if --to is given then all files go to that library
      } elsif ($to) {
	  if ($to=~/^\//) {
	      error "$to is not a valid destination target";
	      fatal "specify a library or offline target, not a path";
	  }
	  $realto=deriveTargetfromName $to,$stage; #check it's real
	  fatal "specified destination '$to' is not valid" unless $realto;
      } else {
	$realto=undef;
      }

      $realto =~ s{/$}{} if defined $realto;

      # pare down supplied filenames to those elegible for consideration
      my @items;
      foreach my $item (@args) {
	  if ($item=~/\*/) {
	      # expand the wildcard
	      my @files = expand_wildcard($item, $stage, $realto, $yes);
	      push @items, @files;
	      next;
	  } else {
	      my $base=basename($item);
	      next if $base=~/^\W/;       # ignore starting with non-word chr
	      next if $base=~/\W$/;       # ignore ending with non-word chr
	      next if $base=~/,v$/;       # skip local RCS files
	      next if $base=~/NORCSID/;   # skip 'NORCSID' backup files
	      next if $item=~/\.o(bj)?$/; # skip objects <<<TODO: from symbol
	      if ($base =~ /\./ && $base !~ /\.mk$/) {
		  # copyout but checkout files which are not supported.
		  if ($base !~ /\.(?:$SUPPORTED_FILETYPES)$/ && 
		      defined $checkout && $checkout == 1) {
		      warning("file type not supported: $base");
		      next;
		  }
	      }

	      $item=~/^(.*)$/ and $item=$1; #untaint
	      push @items,$item;

	  }
      }

      fatal "number of files in change set exceeds limit (".NUM_FILES_LIMIT.")"
	if (scalar @items > NUM_FILES_LIMIT && !$listonly);

      # list context return
      return @items if wantarray;

      # scalar context return
      my $candidateset=new Change::Set({csid=>"!candidate!",stage=>$stage});
      foreach my $item (@items) {
	  $candidateset->addFile($realto,$item,undef,FILE_IS_UNKNOWN,
				 undef,undef); #lib and prdlib unknown as yet
      }

      fatal "duplicate files found - cannot proceed"
	if checkForDuplicateFiles($candidateset);

      return $candidateset;
  }

  sub getParsedTrailingLibraryArgument () {
      return $realto;
  }

} # end 'realto' closure'


sub identifyCheckoutArguments ($$$$@;$) {
    my ($root,$stage,$honordeps,$realto,$candidateset, $checkout)=@_;

    my ($target,$source,$prdlib,$lib,$abssrc);

    my $error=0;
    # for each remaining file, determine if it has a deducible origin
    foreach my $file ($candidateset->getFiles) {
	$source=$file->getSource();

	if ($realto) {
	    $target=$file->getTarget() || $realto;
	} else {
	    $target=$file->getTarget() ||
	      deriveTargetfromFile($source,$stage); #identifies
	    fatal "Can't guess the library for '".$file->getLeafName().
	      "'. Please provide it explicitly." unless $target;
	}

	my $base=basename($source);
	if ($base =~ /\./ && $base !~ /\.mk$/) {
	    if ($base !~ /\.(?:$SUPPORTED_FILETYPES)$/ && defined $checkout 
		    && $checkout == 1) {
		warning "file type not supported for check-in: $base";
		$candidateset->removeFile($file);
		next;
	    }
	}
	
	$prdlib=identifyProductionName($target,$stage);
	#identifies, redundantly if deriveTargetfromFile was hit
	fatal "'$target' is not a legal library/target name" unless $prdlib;

	$lib=lookupName($target,$stage);
	$target=lookupPlace($target,$stage); #if target itself got corrected
	$abssrc=Compat::File::Spec->rel2abs($source);
	
	if ($abssrc eq "/$source") {
            $error=1;
            error "Cannot determine local path for $source: $!";
        }

	$file->setTarget($target);
	$file->setLibrary($lib);
	$file->setProductionLibrary($prdlib);
	$file->setSource($abssrc);
    }

    # 'reconstruct' the changeset so that the target structure is
    # correct. This is an internal aspect of the CS object.
    $candidateset->addFiles($candidateset->removeAllFiles);

    return $candidateset;
}

sub identifyArguments ($$$$@) {
    my ($root,$stage,$honordeps,$realto,$candidateset)=@_;

    my ($target,$source,$prdlib,$lib,$abssrc);

    my $error=0;
    # for each remaining file, determine if it has a deducible origin
    foreach my $file ($candidateset->getFiles) {
	$source=$file->getSource();

	if ($source =~ m!(\A|/)\.\.?/!) {
	    fatal "Source path may not contain '.' or '..' components, please run from a higher level directory to avoid using '..' : $source";
	}
	
	if ($realto) {
	    $target=$file->getTarget() || $realto;
	} else {
	    $target=$file->getTarget() ||
	      deriveTargetfromFile($source,$stage); #identifies
	    fatal "the library to which $source belongs could not be ".
	      "determined from its path" unless $target;
	}

	my $base=basename($source);
	if ($base =~ /\./) {
	    if ($base =~ /\.mk$/) {
		error("Cannot include $base in change set");
		fatal("Makefiles must be submitted to group 55 by DRQS");
	    } else {
		unless ($base =~ /\.(?:$SUPPORTED_FILETYPES)$/) {
		    fatal("file type not supported for check-in: $base");
		}
	    }
	}

	$prdlib=identifyProductionName($target,$stage);
	#identifies, redundantly if deriveTargetfromFile was hit
	fatal "'$target' is not a legal library/target name" unless $prdlib;

	$lib=lookupName($target,$stage);
	$target=lookupPlace($target,$stage); #if target itself got corrected
	$abssrc=Compat::File::Spec->rel2abs($source);
	
	if ($abssrc eq "/$source") {
            $error=1;
            error "Cannot determine local path for $source: $!";
        }
	if ($abssrc =~ /\:/) {
	    fatal "source path cannot have ':' in it";
	}

	$file->setTarget($target);
	$file->setLibrary($lib);
	$file->setProductionLibrary($prdlib);
	$file->setSource($abssrc);
    }
	
    fatal "Errors encountered accessing local files" if ($error);	

    # 'reconstruct' the changeset so that the target structure is
    # correct. This is an internal aspect of the CS object.
    $candidateset->addFiles($candidateset->removeAllFiles);

    ## check for duplicated file basenames within the change set
    ## "Progress" and (for now) "Manual Release" libs can have duplicate files
    unless (getChangeSetStraightThroughState($candidateset)==2     ## Progress
	    || getChangeSetManualReleaseState($candidateset)==1) { ## Manual Rel
	if (checkForDuplicateFiles($candidateset)) {
	    fatal "duplicate files found - cannot proceed";
	}
    }

    return $candidateset;
}

sub parseArguments ($$$$@) {
    my ($root,$stage,$honordeps,$to,@items)=@_;

    my $candidateset=parseArgumentsRaw($root,0,$stage,$honordeps,$to,@items);
    $to=getParsedTrailingLibraryArgument();
    return identifyArguments($root,$stage,$honordeps,$to,$candidateset);
}

=head2 parseArgumentsAsSourceCS($root,$stage,$honordeps,$to,@items)

Parse the list of supplied items as above, but additionally copy the source
location of each change file to the destination location attribute for each
L<Change::File> member object. No other changes are made, and in particular
the file stati remain L<FILE_IS_UNKNOWN> since the destination has not been
identified.

The returned change set is more conveniently usable by applications that
want to deal with the files in a candidate change set in their original
locations, since the behavior of a change file in string context is to
return its destination location. (L<cscompile> is an instance of such an
application, when run in 'local' rather than 'csid' mode.)

=cut

sub parseArgumentsAsSourceCS ($$$$@) {
    my ($root,$stage,$honordeps,$to,@args)=@_;

    my $candidateset=parseArguments($root,$stage,$honordeps,$to,@args);

    foreach my $file ($candidateset->getFiles) {
	$file->setDestination($file->getSource);
    }

    return $candidateset;
}

=head2 checkForDuplicateFiles($candidateset)

Return true if any of the files in the supplied changeset have the same
leafname, or false otherwise. If duplicates are found, details are printed
to standard error. If no duplicates are found no output is generated.

I<Note: this function is more generic than its place in this module would
imply. It might move to L<Change::Util::SourceChecks> in time.>

=cut

sub checkForDuplicateFiles ($) {
    my $candidateset=shift;

    my $dup=0;
    my %seen;
    foreach my $file ($candidateset->getFiles) {
	my $src=$file->getSource();
	my $leaf=basename($src);
	$seen{$leaf}{$src}=1;
    }
    foreach my $file (keys %seen) {
	my $saw=$seen{$file};
	if (keys(%$saw) > 1) {
	    error "duplicate file '$file' found in candidate change set: ";
	    error "* $_" foreach (sort keys %$saw);
	    $dup=1;
	}
    }

    return $dup;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Create::Identity>, L<cscheckin>, L<cscompile>

=cut

1;
