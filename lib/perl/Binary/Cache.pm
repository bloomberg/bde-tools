package Binary::Cache;
use strict;

use base 'BDE::Object';

use File::Path qw(mkpath);
use Symbol ();
use Util::File::Basename qw(basename dirname);
use Util::File::Attribute qw(is_newer);

use BDE::Build::Invocation qw($FS); #<<<replace with Symbol later

use Symbols qw(ROOT);
use constant CACHE_DIR => ROOT."/data/cache/binary";

#use Storable ();
use Data::Dumper qw(Dumper DumperX);
$Data::Dumper::Terse  = 1;
$Data::Dumper::Indent = 0;
$Data::Dumper::Purity = 1;

#==============================================================================

=head1 NAME

Binary::Cache - Provide caching for binary object symbol data

=head1 SYNOPSIS

    use Binary::Cache;
    use Binary::Archive;

    my $cache=new Binary::Cache();

    ...later...

    my $archive=$cache->load("/path/to/library.a");
    unless ($archive) {
        $archive=new Binary::Archive("/path/to/library.a");
        $cache->save("/path/to/library.a",$archive);
    }

=head1 DESCRIPTION

C<Binary::Cache> provides the underlying caching mechanism used by 
L<Binary::Archive> to cache symbol data for binary archives (i.e. libraries).
It may also be used directly to cache any binary data object, including
symbols, objects, and archives.

When the L<"load"> method is called on an instantiated cache object, the
provided path is checked and the timestamp of the original binary file is
compared to that of the cached datafile. If the datafile does not exist, or
is out of date compared to the original, L<"load"> returns C<undef>. Otherwise,
the symbol data is retrieved from the cache rather than reanalysing the
original binary object. L<"save"> provides the complementary functionality to
create the cached datafile.

The data is cached in a directory C<data/cache/binary> under the currently
set development root. (The ability to control this more precisely will be
introduced at a later date).

=cut

#==============================================================================

sub initialise ($$) {
    my ($self,$cachedir)=@_;
    $self->SUPER::initialise($cachedir);

    $cachedir = CACHE_DIR unless $cachedir;
    die "Unable to create $cachedir" unless
      -d($cachedir) or mkpath($cachedir);

    $self->throw("$cachedir does not exist") unless -d $cachedir;
    $self->throw("$cachedir is not writable") unless -w $cachedir;

    $self->{cachedir}=$cachedir;

    return $self;
}

#------------------------------------------------------------------------------

=head2 load($path [,$force])

Load the cache for the specified pathname. Returns C<undef> if there is no
cache file for this pathname, or if the cache is out-of-date relative to the
pathname. If the optional force argument is specified, the cache is loaded
even if it is out of date.

=cut

sub load ($$;$) {
    my ($self,$itempath,$force)=@_;
    my $cachepath=$self->{cachedir}.$FS.$itempath.".cache.gz";
    return undef unless ($self->uptodate($cachepath,$itempath,$force));

    my $FH = Symbol::gensym;
    open($FH,"gunzip -c $cachepath |")
      || $self->throw("Unable to open $cachepath: $!");
    #return Storable::fd_retrieve($FH);
    local $/ = undef;
    return eval <$FH>;
}

=head2 exists($path)

Return true if there is a cache file for the specified path, false otherwise.

=cut

sub exists ($$) {
    my ($self,$itempath)=@_;

    return 0 unless -f $self->{cachedir}.$FS.$itempath;
    return 1;
}

=head2 uptodate($path)

Return true of there is a cache file for the specified path and the cache
file is newer than the path. Returns false if 

=cut

sub uptodate ($$;$) {
    my ($self,$cachepath,$itempath,$force)=@_;

    my $result=is_newer($cachepath,$itempath);

    if ($result<0) {
	$self->throw("$itempath does not exist");
	return undef;
    } elsif ($result and $result==0) {
	return undef; #cache file does not exist
    } elsif ($result) {
	return $force ? 2 : undef; #cache file exists but is out of date
    }

    return 1; #result is 0, cache file is valid
}

=head2 save($path => $item)

Save a cache file for the specified item, recording it under the specified
original pathname. It is up to the caller to ensure that the path specified is
actually appropriate to the item being cached (or indeed exists at all).

=cut

sub save ($$$) {
    my ($self,$itempath,$item)=@_;

    my $cachedir=$self->{cachedir}.$FS.dirname($itempath);
    $self->throw("Unable to create $cachedir: $!") unless
      -d($cachedir) or mkpath($cachedir);

    my $cachepath=$self->{cachedir}.$FS.$itempath.".cache.gz";
    my $FH = Symbol::gensym;
    open($FH,"| gzip - > $cachepath")
      || $self->throw("Unable to open $cachepath: $!");

    #return Storable::store_fd($item,$FH);
    ## XXX: cache should be on /bbs because data is platform-specific
    ##      (hence using store_fd instead of nstore_fd)
    ## XXX: To allow for a shared cache, write the file out to a unique
    ##      temporary file and then rename over existing cache file.

    print $FH DumperX($item);
    close $FH;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainright@bloomberg.net)

=head1 SEE ALSO

L<Binary::Archive>

=cut

1;
