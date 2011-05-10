package Change::Util::SourceChecks;
use strict;

use base 'Exporter';
use Symbol ();

use vars qw(@EXPORT_OK);
my @SOURCE_CHECKS=qw[checkTabs checkTypes checkName checkIncludes 
		     checkInc2HdrGenerated
		     Inc2HdrRequired Inc2HdrGenerated checkCompileHeaderList
		     TreatWarningsAsErrors];
@EXPORT_OK=('checkChangeSet',@SOURCE_CHECKS);

use Util::File::Basename qw(dirname basename);

use Util::Message qw(message message error warning fatal debug debug2);
use BDE::Util::Nomenclature qw(isCompliant isComponent isPackage
			       getComponentPackage getComponentGroup
			       getPackageGroup);
use BDE::Build::Invocation qw($FSRE);

use Symbols qw(DEFAULT_JOBS);
use Change::Symbols qw(
    CHECKFORTABS SCANT_N TYPESCAN TYPESCANSKIPLIST INC2HDR_LIST
    FILELENGTH_LIMIT FILELENGTH_LIMIT_LK
    GTK_FORBIDDEN_INCLUDES COMPILEHDREXCEPTIONLIST $BBFA_HEADERS_LIST
    SLINTENFORCEMENT SLINTEXCEPTION FILE_IS_NEW FILE_IS_UNKNOWN FILE_IS_UNCHANGED
);
use Task::Manager;
use Task::Action;

use BDE::Util::DependencyCache qw(getCachedGroupOrIsolatedPackage);

use Production::Symbols qw/ENVIRONMENT_IS_TEST/;

#---

#<<<TODO: create generic 'getLanguage' functionality to abstract all the
#<<<TODO: extension frobbing that goes on now. Source::Util::Language

sub _getSourceType ($) {
    ## return extension if '.' present, else return "UNKNOWN"
    my $i = rindex($_[0],".")+1;
    return $i ? substr($_[0],$i) : "UNKNOWN";
}

sub _getSourceName ($) {
    ## return path without extension
    ## return "UNKNOWN" if only '.' in name is first char
    my $i = rindex($_[0],".");
    return $i > 0 ? substr($_[0],0,$i) : $i != 0 ? $_[0] : "UNKNOWN";
}


#==============================================================================

=head1 NAME

Change::Util::SourceChecks - Utility functions to perform source checks

=head1 SYNOPSIS

    use Change::Util::Interface qw(checkChangeSet checkTypes checkTabs 
checkInc2HdrGenerated CheckInc2HdrRequired 
CheckInc2HdrGenerated);

=head1 DESCRIPTION

This module provides utility functions that provide services that implement
arbitrary miscellaneous source checks expected by the current implementation.
Most of these are invokations of existing tools that check source files for
various criteria. Over time these will be folded in, removed, or adapted as
the process evolves.

=cut

#==============================================================================

=head1 GENERAL ROUTINES

=head2 checkChangeSet($changeset,$concurrency)

Check the files in the supplied change set, parallelising checks up to the
number specified by the second optional argument, or the default
concurrency otherwise. To run serially, pass C<1>.

Returns true if all tests were passed successfully, or false if any test
failed.

=cut

sub checkChangeSet ($;$) {
    my ($changeset,$concurrency)=(@_);
    $concurrency=DEFAULT_JOBS unless $concurrency;

    $concurrency = 1 if ENVIRONMENT_IS_TEST;    # allows debugger-use

    my $mgr=new Task::Manager("Source check");

    foreach my $file ($changeset->getFiles) {
	my $source=$file->getSource();
	my $srctype=_getSourceType($source);

	if ($srctype eq "gob") {
	  $mgr->addAction(new Task::Action({
					    name => "gob check[$source]",
					    action => \&checksGob,
					    args => [$file],
					   }));
	} elsif ($srctype eq "gobxml") {
	  $mgr->addAction(new Task::Action({
					    name => "gobxml check[$source]",
					    action => \&checksGobXML,
					    args => [$file],
					   }));
	} elsif ($srctype eq "f") {
	  $mgr->addAction(new Task::Action({
					    name => "f check[$source]",
					    action => \&checksF,
					    args => [$file],
					   }));
	} elsif ($srctype eq "c") {
	  $mgr->addAction(new Task::Action({
					    name => "C check[$source]",
					    action => \&checksC,
					    args => [$file],
					   }));
	} elsif ($srctype eq "cpp") {
	  $mgr->addAction(new Task::Action({
					    name => "C++ check[$source]",
					    action => \&checksCpp,
					    args => [$file],
					   }));
	} elsif ($srctype eq "h") {
	  $mgr->addAction(new Task::Action({
					    name => "h check[$source]",
					    action => \&checksH,
					    args => [$file],
					   }));
	} elsif ($srctype eq "inc") {
	  $mgr->addAction(new Task::Action({
					    name => "inc check[$source]",
					    action => \&checksInc,
					    args => [$file],
					   }));
	} else {
	  $mgr->addAction(new Task::Action({
					    name => "generic check[$source]",
					    action => \&checksOther,
					    args => [$file],
					   }));
	}

    }

    $mgr->dump() if Util::Message::get_debug > 1;

    if (scalar $mgr->getActions) {
	# run all assembled tasks
	my $result=$mgr->run($concurrency);
	return $result ? 0 : 1;
    }

    message "no applicable source checks for this change set";
    return 1; #automatic success
}

#------------------------------------------------------------------------------

=head1 CHECK ROUTINES

These check routines are invoked by the general routines above, and are
individually available for export. They all follow command execution semantics
for return statuses, returning false on success and true on failure.

=head2 checkTabs($changefile)

Check for tabs in the source file referenced by the passed change file,
which must be an instance of L<Change::File> or a derived class. The
destination file is not considered.

(This check is applicable to Fortran files only.)

I<Implementation Note: This replaces C</bb/shared/bin/checkfortabs>.>

=cut

sub checkTabs ($;$) {
    my $file=shift;
    my $contents=shift;
    unless ($contents) {
	#<<TODO: checks like this should be batched instead
	#        of opening and reading file multiple times.
	#	 This routine should take optional arg containing contents ref
	local $/ = undef;
	my $FH = Symbol::gensym;
	open($FH,'<',$file->getSource)
	  || fatal "Unable to open $file: $!";
	my $slurp = <$FH>;
	close($FH);

	$contents = \$slurp;
    }
    return 0 unless ($$contents =~ /\t/);  # success; no tabs found

    error "fortran file '$file' contains tabs (disallowed)";
    return 1;
}

#---

=head2 checkTypes($changefile)

=head2 checkTypes($filepath,$library)

Check types for the source file and unit-of-release referenced by the
passed change file, which must be an instance of L<Change::File> or a
derived class, or otherwise the pathname to the file. The destination
file is not considered when a change file instance is passed. If a
file path is passed, a library name must be passed as the second
argument.

(This check is typically applicable to C and Fortran files only.)

I<Implementation Note: This check invokes C</bb/shared/bin/typescan>
internally.>

=cut

sub checkTypes ($;$) {
    my ($file,$lib)=@_;

    my $source = (ref $file) ? $file->getSource() : $file;
    my $target = (ref $file) ? $file->getTarget() : $lib;

    fatal "No library specified" unless $target;

    return 0 if skipCheckTypes($source,$target);

    ##<<<TODO: typescan is *temporarily* disabled on C/C++; only run on Fortran
    return unless (substr($source,-2,2) eq ".f");

    # (For some reason, this was triggering "Insecure dependency"
    #  but using the 3+ argument to open() bypasses the error.)
    #my $rc=system(TYPESCAN,$file->getSource,$file->getUOR);
    #return ($rc==0) ? 0 : 1;

    my $FH = Symbol::gensym;
    open($FH,'|-',TYPESCAN,$source,$target) && close($FH);
    return ($?==0) ? 0 : 1;
}

=head2 skipCheckTypes($changefile)

=head2 skipCheckTypes($filepath,$library)

Return true if the L<"checkTypes"> check should be skipped for the specified
file, or false otherwise. This routine is called internally by L<"checkTypes">
but is available directly for direct reuse. In this implementation it makes
use of the C</bbsrc/tools/data/skip-typescan.tbl> configuration file.

If a file path is passed instead of a change file instance then a library
name must be passed as the second argument, as with L<"checkTypes"> above.

=cut

{ my %skip;

  sub loadSkipFile ($) {
      my $conf=shift;

      my $fh=new IO::File $conf
	or fatal "Unable to open $conf: $!";

      while (my $line=<$fh>) {
	  next if $line=~/^\s*(#|$)/;
	  chomp $line;
	  $skip{$_}=1 foreach split ' ',$line;
      }

      close $fh;
  }

  sub skipCheckTypes ($) {
      my ($file,$lib)=@_;

      my $source = (ref $file) ? $file->getSource() : $file;
      my $target = (ref $file) ? $file->getTarget() : $lib;

      loadSkipFile(TYPESCANSKIPLIST) unless %skip;

      if (exists $skip{$target} or exists $skip{basename($source)}) {
	  debug2 "- $source ($target) is not subject to type scan";
	  return 1;
      }

      debug2 "- $source ($target) is subject to type scan";
      return 0;
  }
}

#---

=head2 checkNomenclature($changefile)

Check that the filename of a source file complies with the nomenclature
rules, if the destination package is compliant and the file is new.

This check does not cover other arbitrary checks that also apply to source
files, see L<"checkName"> for those.

=cut

sub checkNomenclature ($) {
    my $file=shift;

    return 0 unless $file->isNew(); # skip existing files

    my $uor=$file->getLibrary();

    # GTK has its own naming conventions. So any GTK-enabled locn is
    # impossible to police properly.

    return 0 if getCachedGroupOrIsolatedPackage($uor)->isGTKbuild();

    my $leafname=basename $file->getSource();

    my $rulesmsg="(see {BP BASE RULES}:3.e and {BP C++ AT BLOOMBERG})";

    if (isPackage $uor) {
	# isolated package
	return 0 unless isCompliant($uor); # skip NC packages (isolated)
	# the check for components going to NC packages is rendered impotent
	# by the 21 rules; the 30 rules could have regulated it. This means
	# marking a dir as NC will allow components to violate rules.

	my $leafname=basename $file->getSource();
	my $component=$leafname; $component=~s/\..*$//g; #remove extensions
	
	if ($leafname=~/\.xsd$/) { # XSDs can match pkg name or cmp name
            if ($component eq $uor) {
		return 0;
	    }
        }

	unless (isComponent $component) {
	    error "$component ($leafname) is not a legal component name ".
	      $rulesmsg;
	    return 1;
	}

	my $package=getComponentPackage($component);

	if ($package ne $uor) {
	    error "$component does not belong in package $uor ".$rulesmsg;
	    return 1;
	}
    } else {
	# package group

	# (target should equal 'group/package' or 'group/package/subpackage')
	my $target=$file->getTarget();
	my $targetpackage=$target;
	$targetpackage=~s/^\w+$FSRE//o;
	$targetpackage=~s/$FSRE.*$//o;

	return 0 unless isCompliant($targetpackage);# skip NC packages (grouped)

	my $component=$leafname; $component=~s/\..*$//g; #remove extensions
	my $package;
	my $group;

	if ($leafname=~/\.xsd$/) { # XSDs can match pkg name or cmp name
	    unless (isComponent($component) or isPackage($component)) {
		error "$component ($leafname) is not a valid package or ".
		  "component name ".$rulesmsg;
		return 1;
	    }

	    if (isPackage $component) {
		$package=$component;
		$group=getPackageGroup($package);
	    } else { # component
		$package=getComponentPackage($component);
		$group=getComponentGroup($component); #may return undef
	    }
        } else {
	    unless (isComponent $component) {
		error "$component ($leafname) is not a valid component name ".
		  $rulesmsg;
		return 1;
	    }

	    $package=getComponentPackage($component);
	    $group=getComponentGroup($component);
	}

	#<<<TODO: should probably also check that $package eq $targetpackage

	if ($group ne $uor) {
	    error "Component $component does not belong in package group ".
	      $uor." ".$rulesmsg;
	    return 1;
	}

	# trying to check in to the group level?
	if ($target eq $uor) {
	    error "$target is an invalid destination - do not check in ".
	      "source files to the package group directory";
	    return 1;
	}
	
	# legal package name for this group?
	if (getPackageGroup($targetpackage) ne $group) {
	    error "$targetpackage is not a legal package name for $group";
	    return 1;
	}

	# correct package for this component?
	if ($targetpackage ne $package) {
	    error "$component belongs in $package, not $targetpackage ".
	      $rulesmsg;
	    return 1;
	}
    }

    return 0; # success
}

=head2 checkName($changefile)

Check that the filename of a source file is valid in terms of various
arbitrary, possibly subject to change, criteria:

=over 4

=item * Filenames cannot exceed 60 characters

This limit defined by the symbol C<FILELENGTH_LIMIT> for changed files, and
C<FILELLENGTH_LIMIT_LK> for new files. (This distinction is mostly historical
and named for the C<PRQS LK> ticket -- in current usage the two limits are the
same.) See also B<BDE::Rule::X1>, which is also concerned with this limit.

=item * New Fortran filenames must be lower case

The reason for this limitation is currently unknown, although it is consistent
with current policy for other files (e.g. C++ components).

=back

Other filename checks may (and should) be placed here as requirements evolve.
This check does not include nomenclature rules, see L<"checkNomenclature"> for
those.

=cut

sub checkName ($) {
    my $file=shift;

    my $result=0;
    my $base=basename($file);
    my $srctype=_getSourceType($file);

    #<<<TODO: Remove this limit as soon as AK signs of on PRQS EM function.
    #<<<TODO: There is NO limitation in the CS tools, screens, or DB.
    #<<<TODO: This is here purely for compatability with the to-be-deprecated
    #<<<TODO: PRQS LK, and should be removed as soon as PRQS EM is active.
    if (length($base) > ($file->isNew ? FILELENGTH_LIMIT_LK
                                      : FILELENGTH_LIMIT)) {
	error (($file->isNew ? "new ":"")."file '$base' name exceeds ".
	       ($file->isNew ? FILELENGTH_LIMIT_LK : FILELENGTH_LIMIT).
	       " characters");
	$result=1;
    }

    if ($file->isNew) {
        if ($base =~ /\..*\./ and $base !~ /\.[mt]\.\w+$/) {
            error "new file '$base' has more than one '.' in the name";
            $result=1;
        }
    }

    if ($file->isNew) {
	if ($srctype eq "f") {
	    if ($base=~/[A-Z]/) {
		error "new fortran file '$base' name contains ".
		  "uppercase letters";
		$result=1;
	    }
	}
    }

    if (($file->isNew) && ($srctype =~ /^(?:f|c|cpp|gob|h|inc)$/) 
        and not ENVIRONMENT_IS_TEST) {
	my @libs;
	my $FH = Symbol::gensym;
	open($FH,'-|',SCANT_N,$base);
	@libs = map { $_ =~ /Library: (\S+)/ ? $1 : () } <$FH>;
	close($FH);
	if (@libs) {
	    error "Please rename your file. '$base' exists in @libs";
	    $result=1;
	}
    }
    
    if ($file->isNew) {
	if ($base=~/__/) {
	    error "Please rename your file. ".
		"Double underscores are not allowed in filename.";
	    $result=1;
	}
	my $uor=$file->getLibrary();
	if (getCachedGroupOrIsolatedPackage($uor)->isNoNewFiles()) {
	    error "$uor is closed to new development.  No new files allowed.";
	    error "($file is new; not allowed in $uor)\n".
  "\nIn our continuing effort to improve the stability of our code base,\n".
  "$uor is now closed to all new development.  Please make arrangements\n".
  "to organize your code into new or existing libraries.  In particular,\n".
  "use Biglets for Bloomberg function drivers and private code, and use\n".
  "\"utility\" libraries for business logic and graphics that are sharable.\n".
  "Group 412 is available to assist via DRQS OU requests.\n";
	    $result=1;
	    sleep 3;
	}
    }

    return $result; #0=success 1=failure
}

=head2  checkAutoGeneratedFiles($changefile)

Check that auto-generated header or source files are not checked in to 
repository. For now, we are validating gob generated h, c, and cpp files 
only. Other auto-generated files will be validate once proper validation 
mechanism is identified.

=cut

sub checkAutoGeneratedFiles ($) {
    my $file=shift;
    my $source=$file->getSource();
    my $leafname=basename ($source);
    my $result=0;

    my $fs=new IO::File $source
	or fatal "Unable to open $source: $!";

    my $gobfile;
    while (my $line=<$fs>) {
	if (($line=~/Generated\sby\sGOB2o/) || ($leafname=~/-cpp\.cpp$/)) {
	    $line =~ /\b([^\s\.]+\.gob)\b/ and $gobfile=$1;
	    $result=1;
	}
    }

    close $fs;

    unless ($gobfile) {
	$gobfile=$leafname and $gobfile=~s/\..+/.gob/;
    }

    if ($result) {
	error "Please checkout/check-in $gobfile to update $leafname";
	error "You cannot checkout/check-in files generated by ".
	    "the gob compiler.";
    }

    return $result; #0=success 1=failure
}

=head2 checkIncludes($changefile)

Check that the inclusions of the source file are valid, e.g. do not use
inappropriate absolute pathnames.

=cut

sub checkIncludes ($) {
    my $file=shift;
    my $source=$file->getSource();
    my $type=_getSourceType($source);

    $type = "c" if ($type =~ m/^(c|h|cpp|cc|hpp|cxx|gob)$/);
    $type = "f" if ($type =~ m/^(f|inc)$/);

    if ($type ne "c" && $type ne "f") {
        verbose("skipped include check for unsupported file type '$type'");
        return 0;
    }

    unless (open FIN,$source) {
        error "cannot open file '$source': $!";
        return 1;
    }
    my @code = <FIN>;
    chomp @code;
    close FIN;

    my(@bad_code,@Cinclude_bad_code,@gtk_bad_code);
    my(@biglet_bad_code,@Cinclude_bad_code_f);
    my(@boost_bad_code,@ace_bad_code,@bbfa_bad_code);

    my $ftype = $file->getType();

    #<<<TODO: 'fix_inc_path' should be updated to fix these, too.
    if ($type eq "c") {
        push @bad_code, grep { /^\s*#\s*include\s*<\/\S+[>]/ } @code;
        push @bad_code, grep { /^\s*#\s*include\s*"\S*["]/   } @code;

	# suspended check for now - see DRQS 4778670
	#push @bad_code, grep { _checkForBadGlib($file,$_)    } @code;

	# Cinclude/ prefix is not allowed on includes
	# (disallow multiple paths to same include file since
	#  -I.../bbinc/Cinclude -I../bbinc given for free)
        push @Cinclude_bad_code, grep { m%^\s*#\s*include\s*<Cinclude/% } @code;

	# gtk/ prefix is not allowed in include paths
        push @gtk_bad_code, grep { m%^\s*#\s*include\s*<gtk/% } @code;

	# f_*/ prefix is not allowed in include paths
        push @biglet_bad_code, grep { m%^\s*#\s*include\s*<f_\w+/% } @code;

        # DRQS 10049656  boost, ace, and bbfa are deprecated
        my $bbfa_headers = _get_bbfa_headers_href();
        push @boost_bad_code, grep { m%^\s*#\s*include\s*<boost/% } @code;
        push @ace_bad_code, grep { m%^\s*#\s*include\s*<ace/% } @code;
        push @bbfa_bad_code, grep { m%^\s*#\s*include\s*<([^>]+)% and $bbfa_headers->{$1} } @code;

    } elsif ($type eq "f") {
        @bad_code = grep {
	    /[\'\"]+(\/bbsrc|)+(\/bbinc\/|\/bb\/mbig|\/)\S+[\'\"]/
	} grep {
	    /^\s+include\s*[\'\"]+(\/bbsrc|)+(\/bbinc\/|\/bb\/mbig|\/)\S+[\'\"]/i
	} @code;

	# Cinclude/ prefix is not allowed on includes, but there are currently
	# too many existing instances of include 'Cinclude/*/*.inc'
        push @Cinclude_bad_code_f, grep {m%^\s*include\s*['"]Cinclude/%i} @code;
    }

    my $base=basename($file);
    my $is_offline = getCachedGroupOrIsolatedPackage($file->getLibrary)->isOfflineOnly;
    my $file_is_new = ($ftype eq FILE_IS_NEW || $ftype eq FILE_IS_UNKNOWN);
    my $file_is_changed = ($ftype ne FILE_IS_UNCHANGED);

    if (@bad_code) {
	error "$base contains bad include: $_" foreach @bad_code;
	error "* * * use 'fix_inc_path $source' to fix bad includes;";
	error "* * * *IF* the file was added via the FindInc plugin,";
	error "* * * copyout the file, run fix_inc_path on it,";
	error "* * * and explicitly add it to your checkin.";
    }

    if (@Cinclude_bad_code_f and $file_is_changed) {
	error "$base contains bad include: $_" foreach @Cinclude_bad_code_f;
	error "* include .inc header without Cinclude/ prefix";
	push @bad_code, @Cinclude_bad_code_f;
    }

    if (@Cinclude_bad_code) {
	error "$base contains bad include: $_" foreach @Cinclude_bad_code;
	error "* include Cinclude header as #include <header.h>";
	push @bad_code, @Cinclude_bad_code;
    }

    if (@gtk_bad_code and $file_is_changed) {
	error "$base contains bad include: $_" foreach @gtk_bad_code;
	error "* include GTK header as #include <header.h>";
	push @bad_code, @gtk_bad_code;
    }

    if (@biglet_bad_code and $file_is_changed) {
	error "$base contains bad include: $_" foreach @biglet_bad_code;
	error "* include biglet header as #include <header.h>";
	push @bad_code, @biglet_bad_code;
    }

    if (@boost_bad_code) {
        if ($file_is_new and !$is_offline) {
            error "$base contains bad include: $_" foreach @boost_bad_code;
            error "* boost is not allowed in the Bigs -- use BDE shared ptr";
            push @bad_code, @boost_bad_code;
        }
        elsif ($file_is_changed) {
            warning "$base contains bad include: $_" foreach @boost_bad_code;
            warning "* boost is deprecated -- use BDE shared ptr";
        }
    }

    if (@ace_bad_code) {
        if ($file_is_new and !$is_offline) {
            error "$base contains bad include: $_" foreach @ace_bad_code;
            error "* ace is deprecated. Consider using BDE replacements (from bde, bca,";
            error "* bae, and bte) or consult the BDE Team (Group 101) for alternatives.";
            push @bad_code, @ace_bad_code;
        }
        elsif ($file_is_changed) {
            warning "$base contains bad include: $_" foreach @ace_bad_code;
            warning "* ace is deprecated. Consider using BDE replacements (from bde, bca,";
            warning "* bae, and bte) or consult the BDE Team (Group 101) for alternatives.";
        }
    }

    if (@bbfa_bad_code) {
        if ($file_is_new and !$is_offline) {
            error "$base contains bad include: $_" foreach @bbfa_bad_code;
            error "* bbfa is deprecated. Consider using BDE replacements (from bde, bca,";
            error "* bae, and bte) or consult the BDE Team (Group 101) for alternatives.";
            push @bad_code, @bbfa_bad_code;
        }
        elsif ($file_is_changed) {
            warning "$base contains bad include: $_" foreach @bbfa_bad_code;
            warning "* bbfa is deprecated. Consider using BDE replacements (from bde, bca,";
            warning "* bae, and bte) or consult the BDE Team (Group 101) for alternatives.";
        }
    }

    # return 0 for success, 1 for failure in scalar context
    # return the list of bad includes found in array context.
    return wantarray ? @bad_code : (@bad_code ? 1 : 0);
}

#---

=head2 Inc2HdrRequired ($changefile)

In order for a .inc (Fortran header) to auto-generate a .h (c header) file,
the file must be listed in the inc2hdr_list.tbl

=cut

{ my(%required,%required_h_to_inc_map);

  sub loadInc2HdrList ($) {
      my $conf=shift;
      my $fh=new IO::File $conf
	or fatal "Unable to open $conf: $!";
      while (my $line=<$fh>) {
	  next if $line=~/^\s*(#|$)/;
	  $required{$_}=undef, $required_h_to_inc_map{basename($_)}=undef
	    foreach split ' ',$line;
      }
      close $fh;
  }

  sub Inc2HdrRequired ($) {
      my ($file)=@_;

      my $path = $file->getTarget()."/".basename($file);

      # return here if .inc is not passed
      return 0 unless (_getSourceType($path) eq "inc");

      loadInc2HdrList(INC2HDR_LIST) unless %required;

      return (exists $required{$path});
  }

#------------------------------------------------------------------------------

=head2 checkInc2HdrGenerated($changefile)

In order for a .h (c header) to get checked-in, it should not be listed in the
grandfathered exception list of auto-generated headers. This function 
returns true if the header file is in the exception list and contains Inc2hdr.

(This check is applicable to .h files only.)

=cut

  sub Inc2HdrGenerated ($) {
      my ($file)=@_;

      my $source = (ref $file) ? $file->getSource() : $file;

      # return here if .h is not passed
      return 0 unless (_getSourceType($source) eq "h");

      loadInc2HdrList(INC2HDR_LIST) unless %required;
    
      ## Given a .h file, we do not know the *path* to .inc that generated it
      ## Therefore, we do a basename match to see if any .inc generated this .h
      my $srcname=_getSourceName(basename($source)).".inc";
      return (exists $required_h_to_inc_map{$srcname});
  }

  sub checkInc2HdrGenerated ($) {
      my ($file)=@_;
      my $srcname=_getSourceName(basename($file));
      if (Inc2HdrGenerated ($file)) {
	  error "You cannot checkout/check-in ".basename ($file).
	      ". Please checkout/check-in $srcname.inc to update it.";
	  return 1;
      } elsif ($file->isNew()) {
	 # this check is done in case the file is new
	 my $FH = Symbol::gensym;
	 if (open($FH,"<",$file->getSource()) && scalar(grep /Inc2hdr/,<$FH>)) {
	    error "You are not allowed to check-in an auto-generated .h file";
	    error "Please file a DRQS OU ticket to Group 412 in the ".
	        "POLICY queue to have the file added to the INC2HDR list";
	    return 1;
	 }
      }

      return 0; # success
  }
}

#----------------------------------------------------

=head2 checkCompileHeaderList ($changefile)

In order to test compile a C/C++ header, the header must not be in  exception 
list. This function returns true if the header file is in the exception list.

(This check is applicable to .h files only.)

=cut

{ my %required;
 
  sub loadCompileHeaderExceptionList ($) {
      my $conf=shift;

      my $fh=new IO::File $conf
	or fatal "Unable to open $conf: $!";

      while (my $line=<$fh>) {
	  next if $line=~/^\s*(?:#|$)/;
	  chomp $line;
	  $required{$_}=undef foreach split ' ',$line;
      }

      close $fh;
  }

  sub checkCompileHeaderList ($) {
      my $file = shift;
      my $source = $file->getSource();
      return 0 unless (_getSourceType($source) eq "h");

      loadCompileHeaderExceptionList(COMPILEHDREXCEPTIONLIST) unless %required;

      return (exists $required{basename($source)});
  }
 
}

#------------------------------------------------------------------------------

# this simple explicit check will be replaced with a more flexible generic
# mechanism in time if the general case warrants it. Note that general
# UOR->UOR inclusions are limited by dependency declarations and so not need
# a check of this finer granularity.
{ my %badinc=map { $_ => 1 } split /\s/,GTK_FORBIDDEN_INCLUDES;

  sub _checkForBadGlib ($$) {
      if ($_[1] =~ /^\s*#\s*include\s*<([^>]+)>/) {
	  my $inc=basename($1); # no sneaky relative pathing to work around

	  my $filename=basename($_[0]);
	  return 0 if $filename eq "glib.h"; #glib.h can include these guys

	  if (exists $badinc{$inc}) {
	      error "$1 may not be included directly - include glib.h instead";
	      return 1;
	  }
      }

      return 0;
  }
}

#----------------------------------------------------

# Type-specific checks. Groups these things all together so we can run
# them together for each file.

sub checksGob {
  my $file = shift;
  my $rc;
  $rc = checkName($file); 
  $rc ||= checkTypes($file);
  $rc ||= checkIncludes($file);
  return $rc;
}

sub checksGobXML {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  return $rc;
}

sub checksF {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  $rc ||= checkNomenclature($file);
  $rc ||= checkTabs($file);
  $rc ||= checkTypes($file);
  $rc ||= checkIncludes($file);

  return $rc;
}

sub checksC {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  $rc ||= checkNomenclature($file);
  $rc ||= checkTypes($file);
  $rc ||= checkIncludes($file);
  $rc ||= checkAutoGeneratedFiles($file);

  return $rc;
}

sub checksCpp {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  $rc ||= checkNomenclature($file);
  $rc ||= checkIncludes($file);
  $rc ||= checkAutoGeneratedFiles($file);

  return $rc;
}

sub checksH {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  $rc ||= checkNomenclature($file);
  $rc ||= checkIncludes($file);
  $rc ||= checkAutoGeneratedFiles($file);
  $rc ||= checkInc2HdrGenerated($file);

  return $rc;
}

sub checksInc {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  $rc ||= checkNomenclature($file);
  $rc ||= checkIncludes($file);

  return $rc;
}

sub checksOther {
  my $file = shift;
  my $rc;
  $rc = checkName($file);
  $rc ||= checkNomenclature($file);

  return $rc;
}

#----------------------------------------------------

=head2 TreatWarningsAsErrors ($$)

This module is different than the other SourceChecks modules in that it is not
automatically executed when checkChangeSet is called.

Checks whether --Werror (W) (treat gcc -Wall warnings as errors)
needs to be turned on or off. For files/libs listed in
/bbsrc/tools/data/slint_enforcement.tbl, module returns 1.  For files/libs in
/bbsrc/tools/data/slint.exceptions, module returns 0.

=cut

{
  my %enforced;

  sub _init_slint_enforcement () {
    if (my $fh=new IO::File SLINTENFORCEMENT) {
	debug "reading ".SLINTENFORCEMENT;
	while (my $line=<$fh>) {
	    next if $line=~/^\s*(?:#|$)/;
	    $enforced{$_}=1 foreach split /\s+/,$line;
	}
	close $fh;
    } else {
	# this file must exist, or something is wrong
	fatal "Unable to open ${\SLINTENFORCEMENT}: $!";
    }

    if (my $fh=new IO::File SLINTEXCEPTION) {
	debug "reading ".SLINTEXCEPTION;
	while (my $line=<$fh>) {
	    next if $line=~/^\s*(?:#|$)/;
	    $enforced{$_}=0 foreach split /\s+/,$line;
        }
	close $fh;
    } else {
	# this file must exist, or something is wrong
	fatal "Unable to open ${\SLINTEXCEPTION}: $!";
    }
  }

  sub TreatWarningsAsErrors ($$) {
    my($file,$werror)=@_;
    %enforced || _init_slint_enforcement();

    my $target = $file->getTarget();
    my $source = $file->getSource();
    my $basesource = basename $source;

    if ($enforced{$target} || $enforced{$basesource}) {
	debug "For $source ($target), gcc -Wall warnings are treated as errors."
	  unless $werror;
	return 1;
    }
    elsif (exists $enforced{$target} or exists $enforced{$basesource}) {
	message "**WARNING**: ". ($basesource) ." ($target) is in "
	       ."slint exemption list, i.e. gcc -Wall warnings (aka slint "
	       ."checks) are NOT treated as errors. Please file a DRQS "
	       ."ticket to GROUP 412 if you wish to have the file/lib "
	       ."removed from ${\SLINTEXCEPTION}" if $werror;
	return 0;
    }
    return $werror;
  }
}

{
    my %bbfa_headers;

    sub _get_bbfa_headers_href {
        if (!%bbfa_headers) {
            if (open my $FH, '<', $BBFA_HEADERS_LIST) {
                %bbfa_headers = map { chomp; $_ => 1 } <$FH>;
                close $FH;
            }
            else {
                fatal "Unable to load BBFA header file list ($BBFA_HEADERS_LIST): $!";
            }
        }
        return \%bbfa_headers;
    }
}



#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
