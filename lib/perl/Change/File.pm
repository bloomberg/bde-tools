package Change::File;
use strict;

use overload '""'     => "toString",
             fallback => 1;
use base 'BDE::Object';

use BDE::Build::Invocation qw($FS $FSRE);
use Util::File::Basename qw(dirname basename);

use Change::Symbols qw(
    FILE_IS_NEW FILE_IS_CHANGED FILE_IS_UNCHANGED
    FILE_IS_UNKNOWN FILE_IS_REMOVED FILE_IS_RENAMED
    FILE_IS_COPIED FILE_IS_REVERTED
    SERIAL_DELIMITER
);

#==============================================================================

=head1 NAME

Change::File - Abstract representation of a member of a change set.

=head1 SYNOPSIS

    my $cf=new Change::File("acclib","local/newque.c","/bbsrc/acclib/que.c");
    print $cf;               #prints "/bbsrc/acclib/que.c";
    print $cf->getSource();  #prints "local/newque.c"
    print $cf->getTarget();  #prints "acclib"
    $cf->setFileIsNew(1);    #mark as a new file

=head1 DESCRIPTION

C<Change::File> implements a change file object class. Collections of
change files are managed and organized by L<Change::Set> objects; refer to
that module for more information.

A change file consists of three primary attributes: the target to
which it being sent, the source location of the file, and the destination
location of the file. While these three attributes will typically agree with
each other, no assumption is made that the destination is actually
under the official directory associated with the target in question.
Similarly, the name of the source file does not have to agree with that of
the destination. Lastly, this module does I<not> check that the source
(or destination) actually exists or is in any way 'valid'.

=head2 Targets vs Libraries

For most libraries (a.k.a 'units of release'), the target name is the same
as the library name, because the library exists as a directory immediately
under the staging root directory, and because most libraries are flat
internally. However, when these conditions do not apply the target may hold
path information both before or after the library name. In this case, the
library name can also be specified (see L<"new">). For example:

    Library name    File                Target name
    ------------    ---------------     ---------------------
    acclb           que.c               acclib
    gtkcore         xmlargs.h           gtk/gtkcore
    bde             bdet_datetime.h     proot/groups/bde/bdet

The creator of the C<Change::File> object is expected to determine the
library name in the process of deriving the target location. The
L<Change::Identity> module is usually employed to determine both pieces of
information based on context. Note that the target name should contain the
library name as a path element for the object to be sane.

=head2 Change File States

Change file states are defined in L<Change::Symbols>. The following state
symbols are supported:

    FILE_IS_NEW       - file is new for target
    FILE_IS_CHANGED   - file is changed in target
    FILE_IS_UNCHANGED - file is unchanged in target
    FILE_IS_REMOVED   - file is to be removed from target
    FILE_IS_RENAMED   - file is renamed (moved)
    FILE_IS_COPIED    - file is copied
    FILE_IS_UNKNOWN   - file status is unknown

=head2 Evaluation in String Context

The string context evaluation of a Change::File is the I<destination> filename.
This means that, to iterate over a list of change file source locations (as is
often the case when a change set is being created for the first time), it is
important to invoke and use the return value of L<"getSource"> rather than
use the object in string context directly.

=cut

#==============================================================================

=head1 CONSTRUCTORS

=head2 new($target,$source,$destination [,$type [,$library [,$production]]])

Create a new change file with the specified unit-of-release, source, and
destination properties. If the type is not specified it defaults to changed
(see L<"setType"> below).

A target and source file must be specified. The destination may be specified
or given as C<undef>, but in the later case I<only> if the type is explicitly
specified as C<FILE_IS_UNKNOWN>.

The library name, if different to the target, may also be specified,
otherwise it is taken from the target name.

=head2 new({ target=>$target, source=>$src, destination=>$dest, type=>$type
             library=>$library, production=>$production_library })

Like above, except using a hash reference of named properties and values. The
library is still inferred from the target if unspecified, but unlike above,
no other checks or defaults (i.e. for undefined destination) are applied.

=cut

# it is not clear that this really belongs here, as such wisdom is really
# outside the scope of the implementation of this class. However, it is
# here for now.
use BDE::Util::Nomenclature qw(getCanonicalUOR);
##<<<TODO FIXME FIXME FIXME effectively disables taint safety !!!
sub _libraryFromTarget ($) {
    (getCanonicalUOR($_[0]) || $_[0]) =~ /^(.*)$/;
    return $1;
}

##<<<TODO FIXME FIXME FIXME effectively disables taint safety !!!
sub untaint_change_file_attr ($) {
    my $self = shift;
    foreach (qw(target library source destination type production)) {
	next unless exists $self->{$_} and defined $self->{$_};
	$self->{$_} =~ /^(.*)$/;
	$self->{$_} = $1;
    }
    return $self;
}

sub initialise ($$$$;$) {
    my ($self,$init)=@_;
    my $args;

    if (my $reftype=ref $init) {

	if ($reftype eq 'ARRAY') {
	    my ($tgt,$src,$dst,$typ,$lib,$prdlib)=@$init;
	    $args={
		   target      => ($tgt || (($typ ne FILE_IS_UNKNOWN) &&
				   $self->throw("missing target"))),
		   library     => ($lib || ($tgt ?
					    _libraryFromTarget($tgt) : undef)),
		   source      => ($src || $self->throw("missing source")),
		   destination => ($dst || (($typ ne FILE_IS_UNKNOWN) &&
				   $self->throw("missing destination"))),
		   type        => ($typ || FILE_IS_CHANGED),
		   production  => ($prdlib || $lib),
		  };
	} elsif ($reftype eq 'HASH') {
	    $args=$init;
	} else {
	    $self->throw("Invalid reference type: $reftype");
	}

	$self->SUPER::initialise($args);
    } else {
	$self->SUPER::initialiseFromScalar($init);
    }
    return $self->untaint_change_file_attr();
}

sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->throw("Initialiser passed argument not a hash reference")
      unless UNIVERSAL::isa($args,"HASH");

    $self->{_meta}={map {$_=>undef} (qw[library target source destination
					type production productiontarget])};
    foreach (keys %$args) {
	$self->throw("Invalid attribute: $_\n")
	  unless exists $self->{_meta}{$_};
	$self->{$_}=$args->{$_};
    }
    delete $self->{_meta};

    # set the library from the target if unspecified
    $self->{library}=_libraryFromTarget($self->{target})
      unless defined $self->{library};

    $self->untaint_change_file_attr();

    return 1; #done
}

=head2 new($serialised_string)

Initialise a new C<Change::File> object from the specified serialised string
form, which is a colon-separated list of the unit-of-release, source,
destination, type, and destination library in the form:

   library="lib":target="tgt":from="src":to="dest":type="type":production="production"

Order is not significant, and keys in the string that are not one of these
four are tolerated but ignored. (This permits database file defintions,
including the CSID, to be passed without incident.). The library is
derived from the target if not specified. File type consistency with
the destination is not checked (see L<"new">).

=cut

sub fromString {
    my ($self,$init)=@_;

    my @fields=split(SERIAL_DELIMITER,$init);
    my %fields;
    foreach (@fields) {
	$_.=SERIAL_DELIMITER.shift(@fields) while @fields and /"/ and not /"$/;

	$self->throw("Unparsable change file field: $_")
	  unless /^(\w+)=(")?([^"]*)(")?$/;
	my ($key,$value)=($1,$3);

	#map serialisation keys to internal attributes
	$key="source" if $key eq "from";
	$key="destination" if $key eq "to";

	$fields{$key}=$value
    }

    $self->initialiseFromHash(\%fields);
}

#------------------------------------------------------------------------------

=head1 METHODS

=head2 getLibrary

Get the library for this change file.

=head2 setLibrary

Set the library for this change file.

Note that in most circumstances the library should be equal to the target,
or a substring of it, since the target reflects the relative path to the
library, the library name itself, and the trailing path from the library
directory down to the location of the file itself. Unexpected results may
occur in client code if this relationship is disturbed by this method or
L<"setTarget"> below. (See also L<"Targets vs Libraries">.)

=cut

sub getLibrary     ($)  { return $_[0]->{library};     }
sub setLibrary     ($$) { $_[0]->{library}=$_[1];      }

=head2 getTarget

Get the target location for this change file.

I<C<getUOR>> is a deprecated alias for this method>

=head2 setTarget

Set the target location for this change file. See C<"setLibrary"> for
additional notes on the possible (mis)uses of this method.

I<C<setUOR>> is a deprecated alias for this method>

=cut

sub getTarget      ($)  { return $_[0]->{target};      }
sub setTarget      ($$) { $_[0]->{target}=$_[1];       }
sub getUOR         ($)  { return $_[0]->{target};      }
sub setUOR         ($$) { $_[0]->{target}=$_[1];       }

=head2 getSource

Get the source location pathname for this change file.

=head2 setSource

Set the source location pathname for this change file.

=cut

sub getSource      ($)  { return $_[0]->{source};      }
sub setSource      ($$) { $_[0]->{source}=$_[1];       }

=head2 getDestination

Get the destination location pathname for this change file.

=head2 setDestination

Get the destination location pathname for this change file.

=cut

sub getDestination ($)  { return $_[0]->{destination}; }
sub setDestination ($$) { $_[0]->{destination}=$_[1];  }

=head2 getType()

Return the file type (new or changed). See also L<"isNew"> and L<"isChanged">.

=head2 setType()

Set the file type (new or changed). Use L<"Change::Symbols"> for the
appropriate symbol constants C<FILE_IS_NEW> or C<FILE_IS_CHANGED> to supply
as arguments to this method.

=cut

sub getType        ($)  { return $_[0]->{type};              }
sub setType        ($$) { $_[0]->{type}=$_[1];               }

=head2 getProductionLibrary

Get the destination (production) library name for this change file.

=head2 setProductionLibrary

Set the destination (production) library name for this change file.

=cut

sub getProductionLibrary      ($)  { return $_[0]->{production};      }
sub setProductionLibrary      ($$) { $_[0]->{production}=$_[1];       }

=head1 UTILITY METHODS

=head2 getLeafName()

Return the leafname of the file. If the destination is set, it is used to
derive the leafname. Otherwise, the source is used. If neither are set
then C<undef> is returned.

=head2 getSourceDirectory()

Return the directory path to the source file. Returns C<undef> if the source
is not set. The destintion is not inspected.

=head2 getTrailingDirectoryPath()

Strip the library name (and any preceeding path) from the target and return
the remaining trailing path.

=head2 getTrailingPath()

As L<"getTrailingDirectoryPath">, but including the leafname of the file also.

=head2 getProductionTarget()

The destination target is defined to be the target, minus the library prefix,
plus the destination library prefix. Any path prior to the library prefix is
also stripped as with L<"getTrailingPath"> above. For example, if:

    library            = alpha/a_foobar
    target             = priorpath/alpha/a_foobar/baz
    destination        = foo/bar

Then:

    destination target = foo/bar/baz

If the target does not contain the library then behaviour is undefined, see
above. If the destination library name is the same as the source library name
then the destination target will be the same as the target.

=cut

sub getLeafName ($) {
    if ($_[0]->{destination}) {
	return basename($_[0]->{destination});
    } elsif ($_[0]->{source}) {
	return basename($_[0]->{source});
    } else {
	return undef;
    }
}

sub getSourceDirectory ($) {
    return (defined $_[0]->{source}) ? dirname($_[0]->{source}) : undef;
}

sub getTrailingDirectoryPath ($) {
    my $self=shift;

    my $target=$self->getTarget();
    my $library=$self->getLibrary();

    $target =~ s/^(.*?$FSRE)?$library($FSRE|$)//;

    return $target;
}

sub getTrailingPath ($) {
    if (my $trailing_dirpath=$_[0]->getTrailingDirectoryPath) {
	return $trailing_dirpath.$FS.$_[0]->getLeafName();
    }
    return $_[0]->getLeafName();
}

sub getProductionTarget ($) {
    my $self=shift;

    unless ($self->{productiontarget}) {
	$self->{productiontarget}=$self->getProductionLibrary();
	$self->{productiontarget}=$self->getLibrary()
	  unless $self->{productiontarget}; # bbinc/Cinclude needs this

	if (my $trailing_dirpath=$self->getTrailingDirectoryPath) {
	    $self->{productiontarget}.=$FS.$trailing_dirpath;
	}
    }

    return $self->{productiontarget};
}

=head2 setFileIsNew()

Set the file type to new.

=head2 setFileIsChanged()

Set the file type to changed.

=head2 setFileIsUnchanged()

Set the file type to unchanged.

=head2 setFileIsRemoved()

Set the file type to removed.

=head2 setFileIsRenamed()

Set the file type to unknown.

=head2 setFileIsCopied()

Set the file type to unknown.

=head2 setFileIsUnknown()

Set the file type to unknown.

=cut

sub setFileIsNew       ($)  { $_[0]->setType(FILE_IS_NEW);       }
sub setFileIsChanged   ($)  { $_[0]->setType(FILE_IS_CHANGED);   }
sub setFileIsUnchanged ($)  { $_[0]->setType(FILE_IS_UNCHANGED); }
sub setFileIsRemoved   ($)  { $_[0]->setType(FILE_IS_REMOVED);   }
sub setFileIsUnknown   ($)  { $_[0]->setType(FILE_IS_UNKNOWN);   }
sub setFileIsRenamed   ($)  { $_[0]->setType(FILE_IS_RENAMED);   }
sub setFileIsCopied    ($)  { $_[0]->setType(FILE_IS_COPIED);    }
sub setFileIsReverted  ($)  { $_[0]->setType(FILE_IS_REVERTED);  }

=head2 isNew()

Return true if the file is new, or false otherwise.

=head2 isChanged()

Return true if the file is changed, or false otherwise.

=head2 isUnchanged()

Return true if the file is unchanged or reverted, or false otherwise.

=head2 isRemoved()

Return true if the file is to be removed, or false otherwise.

=head2 isUnknown()

Return true if the file state is unknown, or false otherwise.

=head2 isReverted()

Return true if the file is used to revert to a previously swept version, or
false otherwise.

=cut

sub isNew          ($)  { return $_[0]->{type} eq FILE_IS_NEW       }
sub isChanged      ($)  { return $_[0]->{type} eq FILE_IS_CHANGED   }
sub isUnchanged    ($)  { return $_[0]->{type} eq FILE_IS_UNCHANGED }
sub isRemoved      ($)  { return $_[0]->{type} eq FILE_IS_REMOVED   }
sub isRenamed      ($)  { return $_[0]->{type} eq FILE_IS_RENAMED   }
sub isCopied       ($)  { return $_[0]->{type} eq FILE_IS_COPIED    }
sub isUnknown      ($)  { return $_[0]->{type} eq FILE_IS_UNKNOWN   }
sub isReverted     ($)  { return $_[0]->{type} eq FILE_IS_REVERTED  }

#------------------------------------------------------------------------------

=head1 RENDERING-METHODS

=head2 serialise()

Serialises the object to a machine-parsable format.

=cut

sub serialise {
    return join ":",
     'library='.$_[0]->{library},
      'target='.$_[0]->{target},
        'from='.$_[0]->{source},
          'to='.$_[0]->{destination},
        'type='.$_[0]->{type},
  'production='.$_[0]->{production};
}

=head2 toString()

Stringify the object to its destination location. This method is used
for overloading stringification.

=cut

# stringify to the destination location - this is so $tgt{$src}=$file gives
# 'source => destination' semantics.
sub toString {
    return $_[0]->getDestination();
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::File>, L<Change::Symbols>, L<Change::DB>

L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
