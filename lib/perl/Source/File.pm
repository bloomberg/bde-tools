package Source::File;
use strict;

use overload '""' => "toString", fallback => 1;
use base 'BDE::Object';

use Util::Retry qw(retry_open retry_output retry_firstof);
use Util::File::Basename qw(basename);
use Util::Message qw(warning debug fatal);

#<<<TODO:
#   - should handle concatenation of new content.
#   - should handle assignment of replacement content.
#   - should evaluate to length in numeric context.
#   - should allow filename to be set without reading it
#     (and then should allow file to be read on first use)
#   - should allow content to be 'dumped' to reclaim memory without
#     destroying the object

#==============================================================================

=head1 NAME

Source::File - Abstract representation of a source file.

=head1 SYNOPSIS

    my $source = new Source::File($filepath);
    print $source;
    print "This source came from ",$self->getName(),"\n";

=head1 DESCRIPTION

This module provides an object that represents a source file (currently C++ or
C).  The initializer can be either the name of a file or the source content
itself (which should be a scalar containing embedded newlines).  Methods are
provided to return a reference to the source, or the source contents.

See also the L<Source::Iterator> module, which  provides an iterator class for
operating on C<Source::File> instances.

=head2 Evaluation Context

In string context, the source text is returned, which allows source files to
be passed by (object) reference but used as strings.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTOR

=head2 new($file|$sourcetext)

Create a new C<Source::File> object with the contents of the specified file or
source text:

=over 4

=item * If no linefeeds are present and the intitialiser is not the empty
        string, the initializer is presumed to be a filename and the source
        text is read from it.

=item * If linefeeds are present or the initialise is the empty string, it
        is presumed to be source text and used to initialise the context as-is
        and the origin name is set to the empty string.

=back

If the filename specified does not exist, an RCS archive will also be looked
for in the same location and in an RCS subdirectory of that location. If found
the most recent revision is extracted from the RCS archive.

In all cases, including the empty string case, a terminating newline is
appended to the end of the source if none is present.

An exception is thrown if no initializer is supplied.

=cut

#<<<TODO:
#   - should handle a named file without reading it
#   - should handle being passed a filehandle rather than a filename
#     (check - may already be handed by BDE::Object)

sub fromString ($$) {
    my($self, $init) = @_;

    $self->throw("Undefined initializer") unless defined($init);

    if (length($init)==0) {
        $self->{name}="";
        $self->{fullSource}=\"";
    } elsif ($init =~ /\n/) {
        # initialise from string
        $self->{name}=undef;
        $self->{fullSource}=\$init;
    } else {
        # initialise from filename
        $self->{name}=$init;
        $self->{fullSource} = $self->_readFile($init);
    }

    $self->{source} = $self->{fullSource};

    return $self;
}

#------------------------------------------------------------------------------

sub _readFile ($$) {
    my ($self, $file) = @_;

    my($fh) = new IO::File;

    my $rcsfile=$file;
    $rcsfile=~s|/([^/]+)$|/RCS/$1|;

    my @files=($file,"$file,v","$rcsfile,v");
    my $found=retry_firstof(@files);
    $self->throw("cannot find '$file'") unless $found;
    my $foundfile=$files[$found-1];

    my $content;
    if ($foundfile=~/,v$/) {
	debug "extracting content from $foundfile";
	$content=retry_output("/opt/swt/bin/co","-p","-q",$foundfile);
    } else {
	debug "reading $file";
	unless (retry_open($fh, "<$file")) {
	    $self->throw("cannot open '$file': $!");
	}

	local $/= undef;
	$content = <$fh>;
	close $fh;
    }

    $content = "" if !defined $content or $content =~ /^\s*$/;
    return \$content;
}

#------------------------------------------------------------------------------

=head1 METHODS

#------------------------------------------------------------------------------

=head2 getName()

Return the origin filename from which the source file object was initialised,
if known.

=cut

sub getName ($) { return $_[0]->{name}; }
sub getBaseName ($) { return basename($_[0]->{name}); }

#------------------------------------------------------------------------------

=head2 setName()

Set the filename for the source object.

=cut

sub setName ($$) { $_[0]->{name} = $_[1]; }

#------------------------------------------------------------------------------

=head2 getFullSource()

Return a reference to the string representation of the source content, with
comments and in original line order, or undef if no content is available.

=cut

sub getFullSource () {
    my $self=shift;

    return $self->{fullSource};
}

#------------------------------------------------------------------------------

=head2 getSource()

=cut

sub getSource () {
    my $self=shift;

    $self->throw("Malformed source attribute")
	unless ref($self->{source}) eq "SCALAR";
    return $self->{source};
}

#------------------------------------------------------------------------------

=head2 isEmpty()

=cut

sub isEmpty ($) { 
    my($self) = @_;

    return ${$self->{source}} eq "";
}

#------------------------------------------------------------------------------

sub toString ($;$) {
    fatal($_[0]->getName() . " not found (in File.pm)") if !defined(${$_[0]->getSource});
    return ${$_[0]->getSource};
}

#==============================================================================

sub ttt($;$) {
    my ($class,$file)=@_;
    my $src = $class->new($file || "ttt.cpp");
    print $src,"\n";
}

#==============================================================================

=head1 AUTHOR

Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<Source::Iterator>, L<Source::File::Slim>, L<Source::File::Statement>

=cut

1;
