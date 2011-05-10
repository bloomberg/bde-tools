package BDE::Util::IncludeCache;
use strict;

use Util::Message qw(debug2 fatal warning);
use Symbols qw($NO_FOLLOW_MARKER $NOT_A_COMPONENT);
use BDE::Util::Nomenclature qw(
    isComponentHeader isCompliant isNonCompliant getComponentPackage
);

use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw[
    getCachedInclude getFileIncludes
];

#==============================================================================

sub _readFile ($) {
    my $file=shift;

    my $fh=new IO::File;
    unless (open($fh, "< $file")) {
	fatal "cannot open '$file': $!";
	return undef;
    }

    local $/=undef;
    my $content=<$fh>;
    close $fh;
    return $content;
}

=head2 getFileIncludes($content [,$filename [,$package]])

Get the includes for the content passed as the first argument, returning
a list of L<BDE::Package::Include> objects for each include found.

If a second argument is passed, it is used in informational messages if
debug level is 2 or greater, and also in the following diagnostic situations:

=over 4

=item *

If an include statement with inconsistent delimiters is seen, an
exception is thrown.

=item *

If a use of inappropriate delimiters is seen, a warning is issued.
(Only if complient package name is passed as third argument.)

=back

Note that the second argument is purely informational, and need not correspond
to any actual file, since the content is passed as the first argument.

I<Inappropriate delimiters> are quotes used for an include statement for
a component header in a different package. This warning is however only
generated if the third argument, the package name, is passed. This allows
the caller to distinguish between a real component header and a header that
correponds to a component in a real package, but which none-the-less actually
refers to a header in a non-compliant package.

=cut

my $incRE=q[^\s*\#\s*include\s+([<"])([^<"]+?)([">])\s*(//[\s\S]+?)?$];

sub getFileIncludes ($;$$) {
    my ($content,$file,$package)=@_;
    my $package_regex = quotemeta $package;
    my @includes=();
    $file = "file" unless $file;
    $content = $$content if (ref $content) and (ref($content) eq 'SCALAR');

    my $debug = Util::Message::get_debug();
    debug2 "Going to read includes of $file" if ($debug >= 2);

    while ($content =~ m|$incRE|mg) {
	my ($lbr,$include,$rbr,$maybemarker)=($1,$2,$3,$4);
	$maybemarker ||= "";

	# check delimiters are sane
	fatal("$file: inconsistent delimiters: $1 $3") unless
	  ($lbr eq '"' and $rbr eq '"') or ($lbr eq '<' and $rbr eq '>');

	if ($maybemarker=~/$NO_FOLLOW_MARKER/i) {
	    debug2 "$file: ignored $include" if ($debug >= 2);
	} else {
	    debug2 "$file: got $include ($lbr$rbr|$include|$maybemarker)"
	      if ($debug >= 2);

	    my $incobj=new BDE::Package::Include({
                fullname => $include, package => undef, name => $include
	    });
	    $incobj->setLocal( ($lbr eq q["]) ? 1 : 0 );

	    ### determine nature of include - component or non-component
	    if (isComponentHeader($include)) {
		# looks like a component...
		if ($maybemarker=~/$NOT_A_COMPONENT/i) {
		    # explicitly marked as not a component
		    $incobj->setNotAComponent(1);
		} elsif ($package and isNonCompliant($package)
			 and $incobj->isLocal()) {
		    # a local include in a non-compliant pkg can't be comp.
		    $incobj->setNotAComponent(1);
		    $incobj->setPackage($package); #plus we know the package
		} else {
		    # it's a component
		    $incobj->setNotAComponent(0);
		    my $name = $incobj=~/^(.*?)\.h$/ && $1;
		    $incobj->setPackage(getComponentPackage $name);
		}

		### check delimiters are appropriate
		if ($package and isCompliant($package)) {
		    if ($include =~ /^${package_regex}_/) {
			# (skip; practice is now expected by John Lakos)
			# warning "$what includes local file $include with <>";
			#   if $lbr ne '"';
		    } elsif ($lbr eq '"') {
			warning
			  "$file: includes non-local file $include with \"\"";
		    }
		}
	    } else {
		$incobj->setNotAComponent(1);
	    }

	    push @includes,$incobj;
 	}
    }

    return wantarray ? @includes : \@includes;
}

=head2 getCachedInclude($file [,$finder])

Return the cached include object for the requested file, searching for it
using the provided finder object if it is not present in the cache. If the
file is not present and cannot be found, C<undef> is returned.

The file argument may itself be an include object, in which case its
full name is extracted and used to search the cache. The returned include
object, if found, is not necessarily the same as the one passed.

The finder argument is an instance of a L<BDE::File::Finder> object, and
is preset with the valid locations for searching for the file if the cache
does not currently hold it. If no finder is provided and the file is not
in the cache, an exception is thrown.

=cut

{ my %incs; #include cache

  sub getCachedInclude ($;$$) {
      my ($file,$finder,$package)=@_;
      my $debug = Util::Message::get_debug();
      # $package not currently used.

      debug2 "Searching include cache for $file" if ($debug >= 2);

      # if it's already a B::P::I object, check for it by the full name
      # note that just because a B::P::I object is passed in doesn't
      # mean it's also in the cache... this routine won't return it
      # unless it actually exists somewhere.
      $file=$file->getFullname()
	if ref($file) and $file->isa("BDE::Package::Include");

      unless (exists $incs{$file}) {
	  fatal("Cannot locate include '$file' without a finder")
	    unless defined $finder and $finder->isa("BDE::File::Finder");
	  if (my $fi=$finder->find($file)) {

	      debug2 "Found file $file:",$fi->getFullname(),
		     "(".$fi->getPackage().")" if ($debug >= 2);
	      my $realfile=$fi->getRealname();
	      my $content=_readFile($realfile);
              $incs{$file}=$fi;
	      $fi->{includes}=[
	          getFileIncludes($content,$file,$fi->getPackage())
	      ];
	      debug2 "Cached $fi ($realfile)" if ($debug >= 2);
	  }
      }

      if ($debug >= 2) {
	  # this typically means an include of something in the system
	  # so we don't warn about it unless debug is on
	  warning "No such file '$file'" unless exists $incs{$file};
      }

      return $incs{$file}; # a BDE::Package::Include object, or undef
  }
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::Util::DependencyCache>, L<BDE::File::Finder>

=cut

1;
