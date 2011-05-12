package BDE::Package;
use strict;

use IO::File;
use overload '""' => "toString", fallback => 1;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

use BDE::FileSystem;
use BDE::Package::Include;
use BDE::Util::Nomenclature qw(
    isPackage isGroup getPackageGroup isComponent isNonCompliant isFunction
    isIsolatedPackage isAdapter isWrapper isCompliant isLegacy isThirdParty
    getCanonicalUOR isNonCompliantUOR getSubdirsRelativeToUOR isApplication
    getRootRelativePath  getRootRelativeUOR getApplicationLeafPath
    getFullUntaggedApplicationName
);
use BDE::Build::Invocation qw($FS);
use Util::Message qw(debug warning);
use Util::File::Basename qw(dirname basename);
use Util::File::Types qw(isInclude isTranslationUnit hasRcsFile $CHECK_RCS
    $VALID_TRANSLATION_UNIT_GLOB $VALID_INCLUDE_GLOB );
use Util::Retry qw(retry_file retry_open);
use Symbols qw[
    PACKAGE_META_SUBDIR DEFAULT_FILESYSTEM_ROOT
    MEMFILE_EXTENSION DEPFILE_EXTENSION INCFILE_EXTENSION LCKFILE_EXTENSION
    IS_PREBUILT_LEGACY IS_PREBUILT_THIRDPARTY IS_METADATA_ONLY
    MAY_DEPEND_ON_ANY IS_MANUAL_RELEASE IS_HARD_INBOUND IS_NO_NEW_FILES
    IS_RELATIVE_PATHED IS_OFFLINE_ONLY IS_GTK_BUILD IS_HARD_VALIDATION
    IS_SCREEN_LIBRARY IS_BIG_ONLY IS_CLOSED IS_MECHANIZED IS_UNDEPENDABLE
];

#------------------------------------------------------------------------------

=head1 SYNOPSIS

    use BDE::Package;

    my $bdem=new BDE::Package("bdem");
    $bdem->readMembers($location_of_members_file);
    $bdem->addDependant("bdesma");
    $bdem->removeMember("bdes");
    $bdem->addMember("bdem_rope");
    $bdem->addMember("lclp_rope"); #add different package component explicitly
    $bdem->isLocked("lclp_rope");

  or:

    use BDE::Package;
    use BDE::FileSystem;

    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    my $initialised_bdem=new BDE::Package($root->getPackageLocation("bdem"));

=head1 DESCRIPTION

This module implements a package object. It manages lists of component members
and dependent packages.

The package object is filesystem independent, and carries no knowledge of
physical location. See the L<BDE::FileSystem> module for methods to derive
pathnames for member and dependency files for initialising BDE::Package
objects.

If a pathname to a package directory is provided to the constructor then it
will look for a C<package> subdirectory and attempt to initialise itself from
the membership and dependency files located within it.

=cut

#------------------------------------------------------------------------------
# Constructor support

sub fromString ($$) {
    my ($self,$init)=@_;
    my $package;
    if (isNonCompliantUOR($init)) {
        $package = getCanonicalUOR($init);
        $init = substr($init,0,
                       length($init)-(length getSubdirsRelativeToUOR($init)));
    } else {
        $package = basename($init);
    }

    if (-f $init) {
        # initialise directly from a members file
        $self->{name}=undef;
        $self->readMembers($init);
    } elsif (-d $init.$FS.PACKAGE_META_SUBDIR) {
        # initialise from a package metadata directory
        $self->{name}=$package;
        $self->readMembers($init.$FS.PACKAGE_META_SUBDIR
                           .$FS.basename($package).MEMFILE_EXTENSION);
        $self->readDependants($init.$FS.PACKAGE_META_SUBDIR
                           .$FS.basename($package).DEPFILE_EXTENSION);
        $self->readLock($init.$FS.PACKAGE_META_SUBDIR
                           .$FS.basename($package).LCKFILE_EXTENSION);
        if (isNonCompliant($package)) {
            # non-compliant packages may declare their includables here
            $self->readIncludes($init.$FS.PACKAGE_META_SUBDIR
                                  .$FS.basename($package).INCFILE_EXTENSION);
        }
    } elsif (isNonCompliantUOR($package)) {
        # it's legacy, it's not findable, it must be a 'phantom', or otherwise
        # an entity that corresponds to a prebuilt legacy library
        $self->{prebuilt}=1;
        $self->{metadataonly}=1;
        $self->{name}=$package;
    } elsif (isPackage $init) {
        # trivially initialise from the literal name
        $self->{name}=$init;
    } else {
        warning("not a valid package location: $init");
        return undef;
    }

    return $self;
}

#------------------------------------------------------------------------------
# Package members

sub readMembers ($$) {
    my ($self,$memfile)=@_;

    unless ($memfile) {
        warning("cannot obtain package member list for ".$self->{name});
        return undef;
    }

    unless (-d dirname($memfile)) {
        warning("no package control directory (".dirname($memfile).
                     ") for package ".$self->{name});
        return undef;
    }

    my $debug = Util::Message::get_debug();
    unless (-f $memfile) {
        if (isNonCompliantUOR($self)) {
            $self->{metadataonly}=1;
            $self->{prebuilt}=1;
            debug("member file $memfile not found for legacy package $self")
              if $debug;
            return;
        }
        unless (retry_file $memfile) {
            warning("member file $memfile not found");
            return undef;
        }
    }

    my $fh=new IO::File;
    unless (retry_open($fh, "< $memfile")) {
        warning("cannot open '$memfile': $!");
        return undef;
    }

    delete $self->{members} if exists $self->{members};

    local $_;
    while (<$fh>) {
        next if /^\s*$/;
        if (/^\s*#/) {
            # support for special-case packages. This support is still in
            # development. In particular, the 'thirdparty' attribute has
            # no formal use yet. Criteria are as follows:
            #   metadata + prebuilt = add -l rules
            #   metadata - prebuilt = no -l rules
            next unless /^\s*#\s*(\[.*\])\s*$/;
            my $comment=$1;

            if ($comment eq IS_METADATA_ONLY) {
                $self->{metadataonly}=1;
            } elsif ($comment eq IS_PREBUILT_LEGACY) {
                $self->{prebuilt}=1;
                $self->{thirdparty}=0;
            } elsif ($comment eq IS_PREBUILT_THIRDPARTY) {
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
            } elsif ($comment eq MAY_DEPEND_ON_ANY) {
                $self->{dependsonany}=1;
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
            if (isCompliant $self->{name}) {
                unless (isComponent($member) and $member=~/^$self->{name}/) {
                    warning("$memfile:$.: bad component: $member");
                    next;
                }
            }

            #<<<TODO: for non-std packages a different attribute might be
            #<<<TODO: more appropriate, with getNSImpl getNSIntf methods?
            $self->{members}{$member} = 1;
        }
    }

    close $fh;

    debug "$self is metadata-only" if $debug && $self->isMetadataOnly();
    debug "$self is prebuilt" if $debug && $self->isPrebuilt();

    return $self->getMembers() if defined(wantarray);
}

## This routine exists to delay autovivification of members list for
## non-compliant packages until the list is actually needed
sub _initMembers ($) {
    my $self = shift;
    $self->{members} ||= {};
    return unless isNonCompliant($self);

    ##<<<TODO: disabled for now
    return;
    ## From where should we be reading the source?
    my $memfile;

    ##<<<TODO: bad assumptions -- we should be parsing subdirectories, too
    # If no includes specified, scan the package's top-level source
    # directory and add any include files found.
    # Can be assumed that the pkg's source is always in the parent dir
    # of the metadata.
    my $parentDir = dirname(dirname($memfile));

    for my $file (<$parentDir/$VALID_TRANSLATION_UNIT_GLOB>) {
        $file =~ s{,v$}{} if ($CHECK_RCS);
        $self->addMember(basename($file));
    }

    return unless Util::Message::get_debug();

    my @members=values %{$self->{members}};
    if (@members) {
        #if ($self->isPrebuilt() or $self->isMetadataOnly()) {
        #    $self->throw("$self contains members but is marked ".
        #                "as a non-building package");
        #}
        debug($self->{name}." contains @members");
    } else {
        debug($self->{name}." has no members");
    }
}

sub getMembers ($) {
    my $self=shift;
    $self->_initMembers() unless exists $self->{members};
    return sort keys(%{ $self->{members} });
}

sub hasMember ($$) {
    my ($self,$member)=@_;
    $self->_initMembers() unless exists $self->{members};

    # XXX: what about for NC packages?
    return undef unless isComponent($member);
    return 0 unless exists $self->{members}{$member};
    return 1;
}

sub addMember ($$) {
    my ($self,$member)=@_;
    $self->_initMembers() unless exists $self->{members};

    # XXX: what about for NC packages?
    return undef if (!isComponent($member) && !isNonCompliant($self));

    $self->{members}{$member}=1;
    return 1;
}

sub addMembers ($$;@) {
    my ($self,@members)=@_;
    $self->_initMembers() unless exists $self->{members};

    # XXX: what about for NC packages?
    return undef if grep { !isComponent($_) } @members;
    $self->{members}{$_}=1 foreach @members;
    return 1;
}

sub removeMember ($$) {
    my ($self,$member)=@_;
    $self->_initMembers() unless exists $self->{members};

    # XXX: what about for NC packages?
    return undef unless isComponent($member);
    return 0 unless exists $self->{members}{$member};
    delete $self->{members}{$member};
    return 1;
}

sub removeMembers ($$;@) {
    my ($self,@members)=@_;
    $self->_initMembers() unless exists $self->{members};

    # XXX: what about for NC packages?
    return undef if grep { !isComponent($_) } @members;
    delete $self->{members}{$_} foreach @members;
    return 1;
}

sub removeAllMembers ($) {
    $_[0]->{members}={};  ##<<<TODO: should this be undef for NC packages?
    return 1;
}

sub isMetadataOnly         ($) { return $_[0]->{metadataonly}; }
sub isPrebuilt             ($) { return $_[0]->{prebuilt};     }
sub isRelativePathed       ($) { return $_[0]->{relative};     }
sub isOfflineOnly          ($) { return $_[0]->{offlineonly}||
                                        isApplication($_[0]);  }
sub isGTKbuild             ($) { return $_[0]->{gtkbuild};     }
sub isManualRelease        ($) { return $_[0]->{manualrelease};}
sub mayDependOnAny         ($) { return $_[0]->{dependsonany}; }
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
# Package dependents

sub readDependants ($) {
    my ($self,$depfile)=@_;

    unless ($depfile) {
        warning("cannot obtain package dependent list for ".
                     $self->{name});
        return undef;
    }

    unless (-d dirname($depfile)) {
        warning("no package control directory (".dirname($depfile).
                     ") for package ".$self->{name});
        return undef;
    }

    my $debug = Util::Message::get_debug();
    unless (-f $depfile) {
        if (isNonCompliantUOR($self)) {
            debug("dependent file $depfile not found for legacy package $self")
              if $debug;
            return (wantarray ? () : undef);
        }
        unless (retry_file $depfile) {
            warning("dependent file $depfile not found");
            return undef;
        }
    }

    my $fh=new IO::File;
    unless (retry_open($fh, "< $depfile")) {
        warning("cannot open '$depfile': $!");
        return undef;
    }

    delete $self->{dependents} if exists $self->{dependents};
    $self->{weakdeps} = {}     if exists $self->{weakdeps};
    $self->{codeps} = {}       if exists $self->{codeps};

    my $tag;
    my $group=$self->getGroup();
    local $_;
    while (<$fh>) {
        next if /^\s*(?:#|$)/;

        foreach my $dependent (split) {

            # check for leading 'weak:' to indicate undesirable dependency
            $tag = undef;
            if (index($dependent, ':') >= 0) {
                ($tag,$dependent) = split ':',$dependent,2;
                $self->{weakdeps}{$dependent} = 1 if $tag eq "weak";
                $self->{codeps}{$dependent}   = 1 if $tag eq "codep";
            }

            if ($group) {
                # group packages depend on packages in the same group only
                if (isPackage($dependent)) {
                    if ($dependent eq $self) {
                        warning("$depfile:$.: package depends on itself");
                        next;
                    } else {
                        my $depgroup=getPackageGroup($dependent);
                        if ($depgroup ne $group) {
                            warning(
                                         "$depfile:$.: $dependent is not ".
                                         "a legal member of $group");
                            next;
                        }
                    }
                } elsif (isGroup($dependent)) {
                    warning("$depfile:$.: $dependent is not a package; "
                                ."it must be listed in the $group.dep file");
                    next;
                }
                else {
                    warning("$depfile:$.: $dependent is not a package");
                    next;
                }
            } else {
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

                # isolated packages depend on groups (core & dept) and adaptors
                if ($tag && $tag eq "codep") {
                    # ewww.
                    # circularly codependent while developer claims to refactor.
                } elsif (isGroup($dependent)
                    and (!isWrapper($dependent) or isFunction($self))) {
                    # isolated packages may depend on all groups types
                    # except wrappers #TODO expand when we handle more C
                } elsif (isAdapter($dependent)) {
                    # isolated packages may depend on adapters
                } elsif (isLegacy($dependent) || isThirdParty($dependent)) {
                    # legacy...
                #} elsif ($self->{weakdeps}{$dependent} &&isFunction($dependent)
                #        && isLegacy($self)) {
                #   # $self is legacy; allow weak dependency on function...
                } elsif (isLegacy($self)) {
                    # $self is legacy;
                } elsif (isFunction($self) && isWrapper($dependent)) {
                    # allow biglets to depend on package wrappers (z_a_bdema)
                } elsif (isFunction($self) && isFunction($dependent)
                         && $tag && $tag eq "weak") {
                    # allow biglets to depend on biglets (f_******) only if weak
                    # Dependencies between biglets should only be on driver
                    # entry points, which are already pulled in by the router
                    # (and therefore will be resolved and will not break an
                    # application link as long as all these biglets are
                    # present in the router)
                } elsif (isApplication($self) && isFunction($dependent)) {
                    # allow applications to depend on biglets and wiglets (f_ws)
                } elsif (isApplication($self) && isWrapper($dependent)) {
                    # allow applications to depend on wrappers
                } elsif (isApplication($self) && $tag && $tag eq "weak") {
                    # begrudgingly permit apps to depend weakly on anything
                } elsif ($self->mayDependOnAny()) {
                    # $self is allowed to depend on any other UOR
                } else {
                    warning("$depfile:$.: $dependent is invalid");
                    next;
                }

                my @explicit=split /,/,$explicit if $explicit;
                if (@explicit) {
                    $self->setExplicitDependencies($dependent => @explicit);
                }
            }

            $self->{dependents}{$dependent} = 1;

        }
    }

    close $fh;

    my @dependents=$self->getDependants();
    if (@dependents) {
        debug($self->{name}." depends on @dependents") if $debug;
        foreach my $dependent (@dependents) {
            if (my @explicit=$self->getExplicitDependencies($dependent)) {
                debug "  dependency $dependent limited to @explicit" if $debug;
            }
        }
    } else {
        debug($self->{name}." has no dependents") if $debug;
    }

    return @dependents if defined(wantarray);
}

# get all dependents. Note that because a package may be grouped or isolated,
# the values may be packages or groups (but not both). So you may want to use
# the routines getPackageDependants and getDependantGroups instead.
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

    if ($self->isIsolatedPackage() or $self->isGroup()) {
        return undef unless isGroup($dependent)
          or isIsolatedPackage($dependent);
    } else {
        return undef unless isGroupedPackage($dependent);
    }

    return 0 unless exists $self->{dependents}{$dependent};
    return 1;
}

sub addDependant ($$) {
    my ($self,$dependent)=@_;

    if ($self->isIsolatedPackage() or $self->isGroup()) {
        return undef unless isGroup($dependent)
          or isIsolatedPackage($dependent);
    } else {
        return undef unless isGroupedPackage($dependent);
    }

    $self->{dependents}{$dependent}=1;
    return 1;
}

sub addDependants ($$;@) {
    my ($self,@dependents)=@_;

    foreach my $dependent (@dependents) {
        if ($self->isIsolated()) {
            return undef unless isGroup($dependent);
        } else {
            return undef unless isPackage($dependent);
        }
    }

    $self->{dependents}{$_}=1 foreach @dependents;
    return 1;
}

sub removeDependant ($$) {
    my ($self,$dependent)=@_;

    if ($self->isIsolated()) {
        return undef unless isGroup($dependent);
    } else {
        return undef unless isPackage($dependent);
    }

    return 0 unless exists $self->{dependents}{$dependent};
    delete $self->{codeps}{$dependent};
    delete $self->{weakdeps}{$dependent};
    delete $self->{dependents}{$dependent};
    return 1;
}

sub removeDependants ($$;@) {
    my ($self,@dependents)=@_;

    foreach my $dependent (@dependents) {
        if ($self->isIsolated()) {
            return undef unless isGroup($dependent);
        } else {
            return undef unless isPackage($dependent);
        }
    }

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
# Package includes (non-compliant packages only)

sub readIncludes ($$) {
    my ($self,$memfile)=@_;

    unless ($memfile) {
        $self->throw("cannot obtain package include list for ".$self->{name});
        return undef;
    }

    unless (-d dirname($memfile)) {
        $self->throw("no package control directory (".dirname($memfile).
                     ") for package ".$self->{name});
    }

    unless (-f $memfile) {
        if (isNonCompliantUOR($self)) {
            debug("include file $memfile not found for legacy package $self")
              if Util::Message::get_debug();
            return (wantarray ? () : undef);
        }
        unless (retry_file $memfile) {
            $self->throw("include file $memfile not found");
            return undef;
        }
    }

    my $fh=new IO::File;
    unless (retry_open($fh, "< $memfile")) {
        $self->throw("cannot open '$memfile': $!");
        return undef;
    }

    delete $self->{includes} if exists $self->{includes};

    while (<$fh>) {
        next if /^\s*$/ or /^\s*\#/;
        foreach my $include (split) {
            $self->addInclude($include);
        }
    }

    close $fh;

    return $self->getIncludes() if defined(wantarray);
}

## This routine exists to delay autovivification of includes list
## for non-compliant packages until the list is actually needed
sub _initIncludes ($) {
    my $self = shift;
    $self->{includes} ||= {};
    return unless isNonCompliant($self);

    ##<<<TODO: disabled for now
    return;
    ## From where should we be reading the source?
    my $memfile;

    ##<<<TODO: bad assumptions -- we should be parsing subdirectories, too
    # If no includes specified, scan the package's top-level source
    # directory and add any include files found.
    # Can be assumed that the pkg's source is always in the parent dir
    # of the metadata.
    my $parentDir = dirname(dirname($memfile));

    for my $file (<$parentDir/$VALID_INCLUDE_GLOB>) {
        $file =~ s{,v$}{} if ($CHECK_RCS);
        $self->addInclude(basename($file));
    }

    return unless Util::Message::get_debug();

    my @includes=values %{$self->{includes}};
    if (@includes) {
        debug($self->{name}." contains @includes");
    } else {
        debug($self->{name}." has no includes");
    }
}

sub getInclude ($$) {
    my ($self,$include)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    if (exists $self->{includes}{$include}) {
        return $self->{includes}{$include};
    }
    return undef;
}

sub getIncludes ($) {
    my $self=shift;
    $self->_initIncludes() unless exists $self->{includes};
    return sort values(%{ $self->{includes} });
}

sub getIncludeFullname ($$) {
    my ($self,$include)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    return undef unless exists $_[0]->{includes}{$include};
    return $_[0]->{includes}{$include}->getFullname();
}

sub getIncludeFullnames ($) {
    my $self=shift;
    $self->_initIncludes() unless exists $self->{includes};
    return sort map { $_->getFullname() } keys %{$self->{includes}};
}

sub hasInclude ($$) {
    my ($self,$include)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    return 0 unless exists $self->{includes}{$include};
    return 1;
}

sub addInclude ($$;$) {
    my ($self,$include,$full)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    if (ref $include and $include->isa("BDE::Package::Include")) {
        $self->{includes}{$include}=$include; #stringify hash key
    } else {
        $full=$include unless $full;
        my $incobj=new BDE::Package::Include({
            name => $include,
            fullname => $full,
            package => $self->{name},
        });
        $incobj->setNotAComponent(1);
        $self->{includes}{$incobj}=$incobj;
    }

    return 1;
}

sub addIncludes ($$;@) {
    my ($self,@includes)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    foreach (@includes) {
        $self->throw("Not an include object: $_"), return undef
          unless $_->isa("BDE::Package::Include");
        $self->{includes}{$_}=$_;
    }

    return 1;
}

sub removeInclude ($$) {
    my ($self,$include)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    return 0 unless exists $self->{includes}{$include};
    delete $self->{includes}{$include};
    return 1;
}

sub removeIncludes ($$;@) {
    my ($self,@includes)=@_;
    $self->_initIncludes() unless exists $self->{includes};

    delete $self->{includes}{$_} foreach @includes;
    return 1;
}

sub removeAllIncludes ($) {
    $_[0]->{includes}={};  ##<<<TODO: should this be undef for NC packages?
    return 1;
}

#------------------------------------------------------------------------------

# get all direct dependent groups of this package. For grouped packages this
# is the distillation of their package dependencies. For isolated packages it
# is directly equal to their dependencies (which are groups).
sub getGroupDependants ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return undef if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    if ($self->isIsolated()) {
        return @deps;
    } else {
        my %grps=map { getPackageGroup($_) => 1 } @deps;
        return sort keys %grps;
    }
}

# get all direct dependent packages of this package. See above.
sub getPackageDependants ($) {
    my $self=shift;

    my @deps=$self->getDependants();
    return undef if $#deps==0 and not defined $deps[0];
    return () unless @deps;

    if ($self->isIsolated()) {
        return ();
    } else {
        return @deps;
    }
}

#------------------------------------------------------------------------------

sub getGroup ($) {
    return getPackageGroup($_[0]->{name});
}

sub isIsolated ($) {
    return isIsolatedPackage($_[0]->{name});
}

sub isGrouped ($) {
    return isGroupedPackage($_[0]->{name});
}

#------------------------------------------------------------------------------

sub toString ($) {
    return $_[0]->{name};
}

#------------------------------------------------------------------------------

sub readLock ($) {
    my ($self,$lckfile)=@_;

    unless (-d dirname($lckfile)) {
        warning("no package control directory (".dirname($lckfile).
                     ") for package ".$self->{name});
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


sub st ($) { return defined($_[0])?$_[0]:"u"; }

sub test {
    my $rc;
    my $bdem=new BDE::Package("bdem");

    print "Package: (explicit) ",$bdem->toString(),"\n";
    print "Package: (toString) $bdem\n";

    print "Dependants test: ",join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->addDependant("bdebfu");
    print st($rc)." Dependants: ",join(' ',$bdem->getDependants()),"\n";
    print "- Has 'bdebfu': ",join(' ',$bdem->hasDependant("bdebfu")),"\n";
    print "- Has 'bdenon': ",join(' ',$bdem->hasDependant("bdenon")),"\n";
    $rc=$bdem->addDependants(qw[bdebfv bdebfw bdebfz]);
    print st($rc)." addDependants(bdebfv,bdebfw,bdebfz): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->removeDependant("bdebfu");
    print st($rc)." removeDependant(bdebfu): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->removeDependants(qw[bdebfw bdebfv]);
    print st($rc)." removeDependants(bdebfw,bdebfv): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->addDependant("invalid");
    print st($rc)." addDependant(invalid): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->addDependants("bdefoo","bdebar","invalid");
    print st($rc)." addDependants(bdefoo,bdebar,invalid): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->removeDependant("invalid");
    print st($rc)." removeDependant(invalid): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->removeDependants("bdefoo","bdebar","invalid");
    print st($rc)." removeDependants(bdefoo,bdebar,invalid): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->removeDependant("bdenon");
    print st($rc)." removeDependant(bdenon): ",
      join(' ',$bdem->getDependants()),"\n";
    $rc=$bdem->removeAllDependants();
    print st($rc)." removeAllDependants(): ",
      join(' ',$bdem->getDependants()),"\n";

    print "-----\n";

    print "FileSystem test:\n";
    require BDE::FileSystem;
    my $root=new BDE::FileSystem("/bbcm/infrastructure");
    print "  Filesystem located at: $root\n";
    print "  Groups located at: ",$root->getGroupsLocation(),"\n";
    foreach (qw[bdes bdex bdem bdet bdempu bde+stlport]) {
        print "$_ located at: ",$root->getPackageLocation($_),"\n";
        my $package=new BDE::Package($root->getPackageLocation($_));
        print "  $package members   : ",join(' ',$package->getMembers),"\n";
        unless (isNonCompliant($package)) {
            print "  $package dependents: ",
              join(' ',$package->getDependants),"\n";
        } else {
            print "  $package includes  : ",join(' ',map {
                "[".$_." => ".$_->getFullname()." (".$_->getPackage().")]"
            } $package->getIncludes()),"\n";
        }
    }
}

#------------------------------------------------------------------------------

=head1 SEE ALSO

  L<BDE::Group>, L<BDE::Component>, L<BDE::FileSystem>

=cut

1;
