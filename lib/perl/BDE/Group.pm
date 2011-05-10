package BDE::Group;
use strict;

use IO::File;
use overload '""' => "toString", fallback => 1;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

use BDE::FileSystem;
use BDE::Util::Nomenclature qw(
    isGroup isPackage isIsolatedPackage isCompliant getPackageGroup isLegacy
);
use BDE::Build::Invocation qw($FS);
use Util::Message qw(debug verbose warning);
use Util::File::Basename qw(dirname basename);
use Util::Retry qw(retry_file retry_open);
use Symbols qw[
    GROUP_META_SUBDIR PACKAGE_META_SUBDIR
    MEMFILE_EXTENSION DEPFILE_EXTENSION LCKFILE_EXTENSION
    IS_PREBUILT_LEGACY IS_PREBUILT_THIRDPARTY IS_METADATA_ONLY
    IS_MANUAL_RELEASE IS_HARD_INBOUND IS_NO_NEW_FILES
    IS_RELATIVE_PATHED IS_OFFLINE_ONLY IS_GTK_BUILD IS_HARD_VALIDATION
    IS_SCREEN_LIBRARY IS_BIG_ONLY IS_CLOSED IS_MECHANIZED IS_UNDEPENDABLE
];

#------------------------------------------------------------------------------

=head1 SYNOPSIS

    use BDE::Group;

    my $bde=new BDE::Group("bde");
    $bde->readMembers($location_of_members_file);
    $bde->addDependant("bfu");
    $bde->removeMember("bdempu");
    $bde->addMember("bdextr");
    $bde->addMember("lclmpu"); #may add different group package explicitly
    $bdem->isLocked("bde");

  or:

    use BDE::Group;
    use BDE::FileSystem;

    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    my $initialised_bde=new BDE::Group($root->getGroupLocation("bde"));

=head1 DESCRIPTION

This module implements a group object. It manages lists of package members and
dependent groups.

The group object is filesystem independent, and carries no knowledge of
physical location. See the L<BDE::FileSystem> module for methods to derive
pathnames for member and dependency files for initialising BDE::Group objects.
If a pathname to a group directory is provided to the constructor then it will
look for a C<group> subdirectory and attempt to initialise itself from the
membership and dependency files located within it.

=cut

#------------------------------------------------------------------------------
# Constructor support

sub initialise ($$) {
    my ($self,$arg)=@_;

    $self->SUPER::initialise($arg);

    $self->{name}       = undef unless exists $self->{name};
    $self->{dependents} = {} unless exists $self->{dependents};
    $self->{members}    = {} unless exists $self->{members};
    $self->{regions}    = {} unless exists $self->{regions};
    $self->{lock}       = undef unless exists $self->{lock};
}

sub fromString ($$) {
    my ($self,$init)=@_;

    if (-f $init) {
	$self->{name}=undef;
	$self->readMembers($init);
    } elsif (-d $init.$FS.GROUP_META_SUBDIR) {
	my $group=basename($init);
	$self->{name}=$group;
	$self->readMembers($init.$FS.GROUP_META_SUBDIR
			   .$FS.$group.MEMFILE_EXTENSION);
	$self->readDependants($init.$FS.GROUP_META_SUBDIR
			   .$FS.$group.DEPFILE_EXTENSION);
	$self->readLock($init.$FS.GROUP_META_SUBDIR
			   .$FS.$group.LCKFILE_EXTENSION);
    } elsif (isGroup $init) {
	$self->{name}=$init;
    } elsif (!isLegacy(($self->{name}=substr($init,rindex($init,$FS)+1)))) {
	warning("not a valid group location: $init");
	return undef;
    }

    return $self;
}

#------------------------------------------------------------------------------
# Members

sub readMembers ($) {
    my ($self,$memfile)=@_;

    unless ($memfile) {
	warning("cannot obtain group member list for ".$self->{name});
	return undef;
    }

    unless (-d dirname($memfile)) {
        warning("no group control directory (".dirname($memfile).
		     ") for group ".$self->{name});
	return undef;
    }

    unless (retry_file $memfile) {
	warning("member file $memfile not found");
	return undef;
    }

    my $fh=new IO::File;
    unless (retry_open($fh, "< $memfile")) {
	warning("cannot open '$memfile': $!");
	return undef;
    }

    $self->{members}={} if exists $self->{members};

    my $region=$self->getDefaultRegion();
    while (<$fh>) {
	next if /^\s*$/;
        if (/^\s*#/) {
	    # support for special-case packages. This support is still in
            # development. In particular, the 'thirdparty' attribute has
            # no formal use yet. Criteria are as follows:
            #   metadata + prebuilt = add -l rules
            #   metadata - prebuilt = no -l rules
	    # not all of these properties may actually apply to groups
	    # see BDE::Package.
	    next unless /^\s*#\s*(\[.*\])\s*$/;
	    my $comment=$1;

	    if ($comment eq IS_METADATA_ONLY) {
		$self->{metadataonly}=1;
	    } elsif ($comment eq IS_PREBUILT_LEGACY) {
		$self->{metadataonly}=1;
		$self->{prebuilt}=1;
		$self->{thirdparty}=0;
	    } elsif ($comment eq IS_PREBUILT_THIRDPARTY) {
		$self->{metadataonly}=1;
		$self->{prebuilt}=1;
		$self->{thirdparty}=1;
	    } elsif ($comment eq IS_RELATIVE_PATHED) {
		$self->{relative}=1;
	    } elsif ($comment eq IS_OFFLINE_ONLY) {
		$self->{offlineonly}=1;
	    } elsif ($comment eq IS_GTK_BUILD) {
		$self->{gtkbuild}=1;
	    } elsif ($comment eq IS_MANUAL_RELEASE) {
		$self->{manualrelease}=1;
	    } elsif ($comment eq IS_HARD_VALIDATION) {
	        $self->{hardvalidation} = 1;
	    } elsif ($comment eq IS_HARD_INBOUND) {
	        $self->{hardinbound} = 1;
	    } elsif ($comment eq IS_NO_NEW_FILES) {
	        $self->{no_new_files} = 1;
	    } elsif ($comment eq IS_SCREEN_LIBRARY) {
	        $self->{screenlibrary} = 1;
	    } elsif ($comment eq IS_BIG_ONLY) {
	        $self->{bigonly} = 1;
	    } elsif ($comment eq IS_CLOSED) {
	        $self->{closed} = 1;
	    } elsif ($comment eq IS_UNDEPENDABLE) {
	        $self->{undependable} = 1;
	    } elsif ($comment eq IS_MECHANIZED) {
	        $self->{mechanized} = 1;
	    }
	    next;
	}
	foreach my $member (split) {
	    if ($member =~ /^\[/) {
		if ($member =~ /^\[([a-zA-Z]{3}\w*)\]$/) {
		    $region = $1;
		    if ($region !~ /^$self\w+/) {
			$region = $self.'_'.$region;
		    }
		    $self->addRegion($region);
		} else {
		    warning("$memfile:$.: ".
				 "bad region specification: $member");
		}
	    } else {
		unless (isPackage($member) and $member=~/^$self->{name}/) {
		    warning("$memfile:$.: bad package: $member");
		    return undef;
		}

		$self->addMember($member);
		$self->addMemberToRegion($region => $member);
	    }
	}
    }

    close $fh;
	
    my @members=$self->getMembers();

    if (Util::Message::get_debug()) {
	if (@members) {
	    debug($self->{name}." contains @members");
	    my @regions=$self->getRegions();
	    if (@regions) {
		debug($self->{name}." defines regions @regions");
		foreach my $region (@regions) {
		    if (my @rmembers=$self->getRegionMembers($region)) {
			verbose("  region $region contains @rmembers");
		    } else {
			$self->removeRegion($region);
		    }
		}
	    }
	} else {
	    debug($self->{name}." has no members");
	}
    }

    return @members if defined(wantarray);
}

sub getMembers ($) {
    my $self=shift;

    if (exists $self->{members}) {
	return sort keys(%{ $self->{members} });
    } else {
	return ();
    }
}

sub hasMember ($$) {
    my ($self,$member)=@_;

    return undef unless isPackage($member);
    return 0 unless exists $self->{members}{$member};
    return 1;
}

sub addMember ($$) {
    my ($self,$member)=@_;

    return undef unless isPackage($member);
    my $region=$self->getDefaultRegion();
    $self->{members}{$member}=$region;
    $self->{regions}{$region}{$member}=1;
    return 1;
}

sub addMembers ($$;@) {
    my ($self,@members)=@_;

    return undef if grep { !isPackage($_) } @members;
    $self->addMember($_) foreach @members;
    return 1;
}

sub removeMember ($$) {
    my ($self,$member)=@_;

    return undef unless isPackage($member);
    return 0 unless exists $self->{members}{$member};
    my $region=$self->{members}{$member};
    delete $self->{members}{$member};
    delete $self->{regions}{$region}{$member};
    return 1;
}

sub removeMembers ($$;@) {
    my ($self,@members)=@_;

    return undef if grep { !isPackage($_) } @members;
    delete $self->{members}{$_} foreach @members;
    return 1;
}

sub removeAllMembers ($) {
    $_[0]->{members}={};
    return 1;
}

# NOTE: there is no actual concept of a 'metadata only' package group, so
# this support is considered alpha for support for 'prebuilt' groups only.
sub isMetadataOnly         ($) { return $_[0]->{metadataonly}; }
sub isPrebuilt             ($) { return $_[0]->{prebuilt};     }
sub isRelativePathed       ($) { return $_[0]->{relative};     }
sub isOfflineOnly          ($) { return $_[0]->{offlineonly};  }
sub isGTKbuild             ($) { return $_[0]->{gtkbuild};     }
sub isManualRelease        ($) { return $_[0]->{manualrelease};}
sub isHardValidation       ($) { return $_[0]->{hardvalidation}}
sub isHardInboundValidation($) { return $_[0]->{hardinbound}   }
sub isNoNewFiles           ($) { return $_[0]->{no_new_files}  }
sub isBigOnly              ($) { return $_[0]->{bigonly}       }
sub isScreenLibrary        ($) { return $_[0]->{screenlibrary} }
sub isClosed               ($) { return $_[0]->{closed}        }
sub isUndependable         ($) { return $_[0]->{undependable}  }
sub isMechanized           ($) { return $_[0]->{mechanized}    }
#... add set/unset

#------------------------------------------------------------------------------
# Regions (package group partitions) -- subsets of members

sub getDefaultRegion () {
    return $_[0].'_'.$_[0];
}

sub getRegions ($) {
    my $self=shift;

    my @regions=sort keys %{ $self->{regions} };

    #<<<TODO: This imp doesn't let you define a single region in a package
    #<<<TODO: group, if that region is the default region. This is an
    #<<<TODO: assumption, revisit if this ever becomes needed (unlikely)
    if (@regions==1 and $regions[0] eq $self->getDefaultRegion) {
	return (); # if the default region is the only region, no regions
    }

    return @regions;
}

sub getRegionMembers ($$) {
    my ($self,$region)=@_;

    unless (exists $self->{regions}{$region}) {
	$self->throw("$self does not define region $region"); return undef;
    }

    return sort keys %{ $_[0]->{regions}{$region} };
}

sub setRegionMembers ($$@) {
    my ($self,$region,@members)=@_;

    $self->addMemberToRegion($region => $_) foreach @members;
    return $self;
}

sub addRegion ($$) {
    my ($self,$region)=@_;

    unless (exists $self->{regions}{$region}) {
	$self->{regions}{$region}={};
    }
    return $self;
}

sub removeRegion ($$) {
    my ($self,$region)=@_;

    if (exists $self->{regions}{$region}) {
	my $region=$self->{regions}{$region};
	my @members=keys %$region;
	# move all members in this region to the 'base' region since they
	# must belong to some region or other.
	$self->addMemberToRegion($self => $_) foreach @members;
	delete $self->{regions}{$region};
    }

    return $self;
}

sub addMemberToRegion ($$$) {
    my ($self,$region,$member)=@_;

    unless (exists $self->{members}{$member}) {
	$self->throw("$self does not contain member $member"); return undef;
    }
    unless (exists $self->{regions}{$region}) {
	$self->throw("$self does not define region $region"); return undef;
    }

    my $oldregion=$self->{members}{$member};
    return $self if $oldregion eq $region; #already in target region

    delete $self->{regions}{$oldregion}{$member}; #out with the old
    $self->{members}{$member}=$region;
    $self->{regions}{$region}{$member}=1; #in with the new
}

sub regionHasMember($$$) {
    my ($self,$region,$member)=@_;

    unless (exists $self->{members}{$member}) {
	$self->throw("$self does not contain member $member"); return undef;
    }

    return 1 if $region eq $self; # member always belongs to the whole group

    return (exists $self->{regions}{$region}{$member}) ? 1 : 0;
}

#------------------------------------------------------------------------------

sub getCompliantMembers ($) {
    my @members=$_[0]->getMembers();
    return () unless @members;

    return grep { isCompliant($_) } @members;
}

sub getNonCompliantMembers ($) {
    my @members=$_[0]->getMembers();
    return () unless @members;

    return grep { ! isCompliant($_) } @members;
}

#------------------------------------------------------------------------------
# dependents

sub readDependants ($) {
    my ($self,$depfile)=@_;

    unless ($depfile) {
	warning("cannot obtain group dependent list for ".$self->{name});
	return undef;
    }

    unless (-d dirname($depfile)) {
        warning("no group control directory (".dirname($depfile).
		     ") for group ".$self->{name});
	return undef;
    }

    unless (retry_file $depfile) {
	warning("dependent file $depfile not found");
	return undef;
    }

    my $fh=new IO::File;
    unless (retry_open($fh, "< $depfile")) {
	warning("cannot open '$depfile': $!");
	return undef;
    }

    $self->{dependents}={} if exists $self->{dependents};
    $self->{weakdeps}={}   if exists $self->{weakdeps};
    $self->{codeps}={}     if exists $self->{codeps};

    while (<$fh>) {
	next if /^\s*$/ or /^\s*\#/;
	foreach my $dependent (split) {

	    # check for leading 'weak:' to indicate undesirable dependency
	    if (index($dependent, ':') > 0) {  
		my $tag;
		($tag,$dependent) = split ':',$dependent,2;
		$self->{weakdeps}{$dependent} = 1 if $tag eq "weak";
		$self->{codeps}{$dependent}   = 1 if $tag eq "codep";
	    }

	    # look for explicit qualification
	    my $fulldependent=$dependent;
	    my $explicit;
	    ($dependent,$explicit)=
	      $fulldependent =~ m|^([^<]+)<([^>]+)>$|;
	    $dependent=$fulldependent unless $dependent;

	    #<<TODO: look for 'special' dependencies
	    #<<TODO: e.g. '3pty:openssl'
	    #<<TODO: or   'bbslib:acclib'
	    #<<TODO: extensible rules for these extensions?

	    # only units of release in the .dep file
	    unless ((isGroup($dependent) or isIsolatedPackage($dependent))
		    and $dependent ne $self->{name}) {
		    #and $dependent!~/^$self->{name}/) {
		warning("$depfile:$.: bad group: $dependent");
		next;
	    }

	    $self->{dependents}{$dependent} = 1;

	    my @explicit=split /,/,$explicit if $explicit;
	    if (@explicit) {
		$self->setExplicitDependencies($dependent => @explicit);
	    }
	}
    }

    close $fh;

    my @dependents=$self->getDependants();
    if (Util::Message::get_debug()) {
	if (@dependents) {
	    debug($self->{name}." depends on @dependents");
	    foreach my $dependent (@dependents) {
		if (my @explicit=$self->getExplicitDependencies($dependent)) {
		    debug "  dependency $dependent limited to @explicit";
		}
	    }
	} else {
	    debug($self->{name}." has no dependents");
	}
    }

    return @dependents if defined(wantarray);
}

sub getDependants ($) {
    my $self=shift;

    if (exists $self->{dependents}) {
	return sort keys(%{ $self->{dependents} });
    } else {
	return ();
    }
}

sub hasDependant ($$) {
    my ($self,$dependent)=@_;

    return undef unless isGroup($dependent);
    return 0 unless exists $self->{dependents}{$dependent};
    return 1;
}

sub addDependant ($$) {
    my ($self,$dependent)=@_;

    return undef unless isGroup($dependent);
    $self->{dependents}{$dependent}=1;
    return 1;
}

sub addDependants ($$;@) {
    my ($self,@dependents)=@_;

    return undef if grep { isGroup($_)==0 } @dependents;
    $self->{dependents}{$_}=1 foreach @dependents;
    return 1;
}

sub removeDependant ($$) {
    my ($self,$dependent)=@_;

    return undef unless isGroup($dependent);
    return 0 unless exists $self->{dependents}{$dependent};
    delete $self->{dependents}{$dependent};
    delete $self->{weakdeps}{$dependent};
    delete $self->{codeps}{$dependent};
    return 1;
}

sub removeDependants ($$;@) {
    my ($self,@dependents)=@_;

    return undef if grep { isGroup($_)==0 } @dependents;
    foreach (@dependents) {
	delete($self->{dependents}{$_});
	delete($self->{weakdeps}{$_});
	delete($self->{codeps}{$_});
    }
    return 1;
}

sub removeAllDependants ($) {
    $_[0]->{dependents}={};
    $_[0]->{weakdeps}={};
    $_[0]->{codeps}={};
    return 1;
}

#------------------------------------------------------------------------------
# co-dependencies (marked as 'codep:<dep>', used by symbol validation

sub isCoDependant ($$) {
    return exists $_[0]->{codeps}{$_[1]};
}

sub getCoDependants ($) {
    return keys %{$_[0]->{codeps}};
}

#------------------------------------------------------------------------------
# weak dependencies (marked as 'weak:<dep>', used by symbol validation

sub isWeakDependant ($$) {
    return exists $_[0]->{weakdeps}{$_[1]};
}

sub getWeakDependants ($) {
    return keys %{$_[0]->{weakdeps}};
}

sub isStrongDependant ($$) {
    my ($self,$dependant)=@_;

    return undef unless $self->hasDependant($dependant); #not a dependency

    return $self->isWeakDependant($dependant) ? 0 : 1;
}

sub getStrongDependants ($) {
    my $self=shift;

    my %dependants=map { $_ => 1 } $self->getDependants();
    delete $dependants{$_} foreach $self->getWeakDependants();

    return keys %dependants;
}

#------------------------------------------------------------------------------
# explicit dependencies (dependencies on packages within a group)

sub getExplicitDependencies ($$) {
    my ($self,$dependent)=@_;

    unless (exists $self->{explicit}{$dependent}) {
	return ();
    }

    return sort keys %{ $self->{explicit}{$dependent} };
}

sub setExplicitDependencies ($$@) {
    my ($self,$dependent,@explicit)=@_;

    unless (exists $self->{dependents}{$dependent}) {
	$self->throw("$dependent is not a dependent of $self"); return undef;
    }

    foreach my $exp (@explicit) {
	my $group=getPackageGroup($exp);
	if ((not $group) or $group ne $dependent) {
	    $self->throw("$exp is not a legal member of $dependent");
	    return undef;
	}
    }

    $self->{explicit}{$dependent}={ map {$_ => 1} @explicit };

    return $self;
}

sub hasExplicitDependency ($$) {
    my ($self,$explicit)=@_;

    my $dependent=getPackageGroup($explicit);

    unless ($dependent) {
	# only package groups can be qualified with explicit packages
	$self->throw("$explicit is not a grouped package"); return undef;
    }
    unless (exists $self->{dependents}{$dependent}) {
	$self->throw("$dependent is not a dependent of $self"); return undef;
    }

    return (exists $self->{explicit}{$dependent}{$explicit}) ? 1 : 0;
}

#------------------------------------------------------------------------------

sub readLock ($) {
    my ($self,$lckfile)=@_;

    unless (-d dirname($lckfile)) {
        warning("no group control directory (".dirname($lckfile).
		     ") for group ".$self->{name});
	return undef;
    }

    unless (-f $lckfile) {
	return undef;
    }

    my $fh=new IO::File;
    unless (retry_open($fh, "< $lckfile")) {
	warning("cannot open '$lckfile': $!");
	return undef;
    }

    local $/=undef;
    $self->{lock}=<$fh>; # NB: can be empty but defined, still locked.

    close $fh;
}

sub isLocked ($) {
    my ($self)=@_;

    return defined $self->{lock}; # empty string is still locked
}

sub getLockMessage ($) { return $_[0]->{lock}; }

sub setLock        ($) { $_[0]->{lock}=$_[1];  }

sub clearLock      ($) { $_[0]->{lock}=undef;  }

#------------------------------------------------------------------------------

sub toString ($) {
    return $_[0]->{name};
}

#------------------------------------------------------------------------------

sub st ($) { return defined($_[0])?$_[0]:"u"; }

sub test {
    my $rc;
    my $bde=new BDE::Group("bde");

    print "Group: (explicit) ",$bde->toString(),"\n";
    print "Group: (toString) $bde\n";
    print "Dependants test: ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->addDependant("bfu");
    print st($rc)." Dependants: ",join(' ',$bde->getDependants()),"\n";
    print "- Has 'bfu': ",join(' ',$bde->hasDependant("bfu")),"\n";
    print "- Has 'non': ",join(' ',$bde->hasDependant("non")),"\n";
    $rc=$bde->addDependants(qw[bfv bfw bfz]);
    print st($rc)." addDependants(bfv,bfw,bfz): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->removeDependant("bfu");
    print st($rc)." removeDependant(bfu): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->removeDependants(qw[bfw bfv]);
    print st($rc)." removeDependants(bfw,bfv): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->addDependant("invalid");
    print st($rc)." addDependant(invalid): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->addDependants("foo","bar","invalid");
    print st($rc)." addDependants(foo,bar,invalid): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->removeDependant("invalid");
    print st($rc)." removeDependant(invalid): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->removeDependants("foo","bar","invalid");
    print st($rc)." removeDependants(foo,bar,invalid): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->removeDependant("non");
    print st($rc)." removeDependant(non): ",join(' ',$bde->getDependants()),"\n";
    $rc=$bde->removeAllDependants();
    print st($rc)." removeAllDependants(): ",join(' ',$bde->getDependants()),"\n";
    print "Members test: ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->addMember("bdebfu");
    print st($rc)." Members: ",join(' ',$bde->getMembers()),"\n";
    print "- Has 'bdebfu': ",join(' ',$bde->hasMember("bdebfu")),"\n";
    print "- Has 'bdenon': ",join(' ',$bde->hasMember("bdenon")),"\n";
    $rc=$bde->addMembers(qw[bdebfv bdebfw bdebfz]);
    print st($rc)." addMembers(bdebfv,bdebfw,bdebfz): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->removeMember("bdebfu");
    print st($rc)." removeMember(bdebfu): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->removeMembers(qw[bdebfw bdebfv]);
    print st($rc)." removeMembers(bdebfw,bdebfv): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->addMember("invalid");
    print st($rc)." addMember(invalid): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->addMembers("bdefoo","bdebar","invalid");
    print st($rc)." addMembers(bdefoo,bdebar,invalid): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->removeMember("invalid");
    print st($rc)." removeMember(invalid): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->removeMembers("bdefoo","bdebar","invalid");
    print st($rc)." removeMembers(bdefoo,bdebar,invalid): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->removeMember("bdenon");
    print st($rc)." removeMember(bdenon): ",join(' ',$bde->getMembers()),"\n";
    $rc=$bde->removeAllMembers();
    print st($rc)." removeAllMembers(): ",join(' ',$bde->getMembers()),"\n";

    print "FileSystem test:\n";
    require BDE::FileSystem;
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    print "  Filesystem located at: $root\n";
    print "  Groups located at: ",$root->getGroupsLocation(),"\n";
    foreach (qw[bde bce bte bae]) {
	print "$_ located at: ",$root->getGroupLocation($_),"\n";
	my $group=new BDE::Group($root->getGroupLocation($_));
	print "  $group members   : ",join(' ',$group->getMembers()),"\n";
	print "  $group dependents: ",join(' ',$group->getDependants()),"\n";
    }
}

#------------------------------------------------------------------------------

=head1 SEE ALSO

  L<BDE::FileSystem>, L<BDE::Package>

=cut

1;
