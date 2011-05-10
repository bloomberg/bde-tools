package Change::Util::Bundle;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    bundleChangeSet
    bundleChangeSetSCM
    convertChangeSetSCM
    unbundleChangeSetMeta
    unbundleChangeSet
];

use Util::File::Copy qw(copyx);
use Util::File::Basename qw(dirname basename);
use Util::File::Functions qw(ensure_path);
use Change::Util::Canonical qw(bare_canonical_path branch_less);
use Util::Message qw(error debug);
use Change::Set;
use Change::Symbols qw/FILE_IS_RENAMED FILE_IS_REMOVED FILE_IS_NEW_UOR/;

#==============================================================================

=head1 NAME

Change::Util::Bundle - Utility functions to pack and unpack Change::Set plus
content for transport to or from SCM.

=head1 SYNOPSIS

    use Change::Util::Bundle qw(unbundleChangeSetMeta);

=head1 DESCRIPTION

This module provides utility functions that package a Change::Set structure
plus associated content into a file for shipment to or from the SCM.  It also
provides means for unpacking the bundle, and for extracting the meta data, i.e.
the Change::Set structure, from the bundle.

=cut

#==============================================================================

=head2 bundleChangeSet($changeset,$tarball,$dir)

Bundle the source files and meta data for a specified changeset in a tarball
under the specified name. The I<Change::Set> should employ only robocop
paths; these are canonicalized during the bundling process without affecting
the original I<Change::Set>. Temporary files are written to I<$dir>. Return 1
for success and 0 for failure.

=cut

sub bundleChangeSet ($$$) {
  my ($changeset,$tarball,$dir) = @_;
  my $scmset = convertChangeSetSCM($changeset) or return 0;
  return bundleChangeSetSCM($scmset,$tarball,$dir);
}

=head2 bundleChangeSetSCM($changeset,$tarball,$dir)

Like I<bundleChangeSet>, except the I<Change::Set> is assumed to contain only
lroot paths.

=cut

sub bundleChangeSetSCM($$$) {
  my ($changeset,$tarball,$dir) = @_;

  # Create data files.
  # Do not append CSID directory.  Otherwise unbundleChangeSetMeta must know
  # the CSID.
  if (system('rm','-rf',"$dir/root","$dir/meta")) {
    error "Failed to remove $dir: $!";
    return 0;
  }

  # Make sure that we have at least a root/ directory
  # so that bundling of change sets without files
  # works.
  ensure_path("$dir/root");

  foreach my $file ($changeset->getFiles) {

    # do not pull in the source for these types
    # as they denote a structural changeset.
    next if $file->getType eq FILE_IS_RENAMED or
            $file->getType eq FILE_IS_REMOVED or
	    $file->getType eq FILE_IS_NEW_UOR;

    # do not bundle directories - denoted by a trailing slash
    next if substr($file->getSource, -1) eq '/';
    next if substr($file->getDestination, -1) eq '/';

    # Copy content to bundle:
    # don't use the branch number in creating the bundle.
    # Instead use the old format: root/legacy/test/...
    my $src = $file->getSource;
    (my $relpath = $file->getDestination) =~ s{^root/\d+/}{root/};
    my $dest = join '/' => $dir, $relpath;

    ensure_path(dirname $dest);
    debug "copyx $src to $dest";
    unless (copyx $src, $dest) {
      error "Failed to copyx $src to $dest: $!";
      return 0;
    }
  }

  # Write Change::Set to meta file
  my $fh;
  unless (open($fh, ">$dir/meta")) {
    error "Failed to open $dir/meta: $!";
    return 0;
  }

  print $fh $changeset->serialise;

  unless (close($fh)) {
    error "Failed to close $dir/meta: $!";
    return 0;
  }

  # FIX: plumb
  debug "create tarball $tarball";
  if (system("( cd $dir && tar -cf - root meta ) | gzip -c > $tarball.tmp && mv $tarball.tmp $tarball")) {
    error "Failed to bundle change set to $tarball: $!";
    return 0;
  }

  return 1;
}

=head2 convertChangeSetSCM($changeset)

Build a new I<Change::Set> with lroot paths from a I<Change::Set> containing
robocop paths. Return the new I<Change::Set> or 0 for failure.

=cut

sub convertChangeSetSCM($) {
    my ($changeset) = @_;
    my $scmset = $changeset->clone;

    my $branch = $changeset->getBranch;
    foreach my $file ($scmset->getFiles) {
	my $canonicalpath = bare_canonical_path($file);
	unless (defined($canonicalpath)) {
	    # Probably big trouble like robo-only commit at this juncture.
	    error "Failed to find canonical path for $file";
	    return 0;
	}
	if (defined $branch) {
	    $canonicalpath = "root/$branch/$canonicalpath";
	} else {
	    $canonicalpath = "root/$canonicalpath";
	}
	$file->setDestination($canonicalpath);
    }

    return $scmset;
}

=head2 unbundleChangeSetMeta($changeset,$bundle,$dir)

Unbundle the meta data of a bundled change set.  Return 1 for success and 0 for
failure.

=cut

sub unbundleChangeSetMeta ($$$) {
  my ($changeset,$tarball,$dir) = @_;

  local $SIG{CHLD};

  if (system('rm','-rf',"$dir/meta")) {
    error "Failed to remove $dir: $!";
    return 0;
  }

  # FIX: plumb
  if (system("gunzip -c $tarball | { cd $dir && tar xf - meta; }")) {
    error "Failed to unbundle change set meta: $!";
    return 0;
  }

  # Read change set data.
  { local $/ = undef;
    my $fh;
    unless (open($fh,"<$dir/meta")) {
      error "Failed to open $dir/meta: $!";
      return 0;
    }
    my $cstext = <$fh>;
    unless (close($fh)) {
      error "Failed to close $dir/meta: $!";
      return 0;
    }
    $changeset->fromString($cstext);
  }

  # FIX: Test that files exist in tarball.  Test that no extra files exist.

  return 1;
}

=head2 unbundleChangeSet($changeset,$bundle,$dir)

Unbundle the meta data of a bundled change set.  Return 1 for success, having
populated $changeset, and 0 for failure.  Creates $dir containing root/
directory and meta file.

=cut

sub unbundleChangeSet ($$$) {
  my ($changeset,$tarball,$dir) = @_;

  local $SIG{CHLD};

  if (system('rm','-rf',"$dir/root", "$dir/meta")) {
    error "Failed to remove $dir: $? . $!";
    return 0;
  }

  # FIX: plumb
  if (system("gunzip -c $tarball | { cd $dir && tar xf -; }")) {
    error "Failed to unbundle change set: $!";
    return 0;
  }

  # Read change set data.
  { local $/ = undef;
    my $fh;
    unless (open($fh,'<', "$dir/meta")) {
      error "Failed to open $dir/meta: $!";
      return 0;
    }
    my $cstext = <$fh>;
    unless (close($fh)) {
      error "Failed to close $dir/meta: $!";
      return 0;
    }
    $changeset->fromString($cstext);
  }

  # FIX: Test that files exist in tarball.  Test that no extra files exist.

  return 1;
}

# Object-oriented interface

sub new {
    my ($class, %args) = @_;

    my ($path, $cs);
    if ($args{bundle}) {
        $path = $args{bundle};
    } elsif ($args{csid}) {
        require SCM::Util;
        $path = SCM::Util::getBundlePath($args{csid});
    } elsif ($args{meta}) {
        $cs = Change::Set->load($args{meta});        
    } elsif ($args{cs}) {
        $cs = $args{cs};
    }

    require File::Temp;

    my $self = bless {
        _path   => $path,
        _cs     => $cs,
        _tmp    => File::Temp::tempdir(CLEANUP => 1),
    } => $class;

    $self->_unpack if $self->path;

    return $self;
}

sub extract {
    my ($self, $lroot, $dest) = @_;

    my $tmp = $self->tmp;

    die "Bundle doesn't yet exist." if not $self->path;

    $self->_unpack if not -d "$tmp/root";

    (my $local = $lroot) =~ s!^root/(?:\d+/)?!!;
    $local =~ s!^\d+/!!;

    return if not my $file = $self->cs->getFileByName($local);
   
    my $src = branch_less($file->getDestination);
    my ($atime, $mtime) = (stat "$tmp/$src")[8, 9];
    copyx("$tmp/$src" => $dest)
        or die "Error copyxing $tmp/$src to $dest: $!";

    my $base = basename($local);
    utime $atime, $mtime, "$dest/$base";

    return 1;
}

sub build {
    my ($self, $tarball, %args) = @_;
    
    $self->tmp(File::Temp::tempdir(CLEANUP => 1)) if not $self->tmp;
    return bundleChangeSet($self->cs, $tarball, $self->tmp) if $args{canonicalize};
    return bundleChangeSetSCM($self->cs, $tarball, $self->tmp);
}

sub _unpack {
    my $self = shift;

    my $cs = Change::Set->new;
    unbundleChangeSet($cs, $self->path, $self->tmp);
    $self->cs($cs);
}

# accessors

sub path { 
    my $self = shift;
    $self->{_path} = shift if @_;
    return $self->{_path};
}

sub tmp { 
    my $self = shift;
    $self->{_tmp} = shift if @_;
    return $self->{_tmp};
}

sub cs {
    my $self = shift;
    $self->{_cs} = shift if @_;
    return $self->{_cs};
}

#==============================================================================

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=head1 SEE ALSO

L<Change::Set>

=cut

1;
