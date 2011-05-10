package Util::File::Copy;

use strict;
use warnings;

use base    qw/Exporter/;

use Fcntl   qw/S_IXUSR S_IXGRP S_IXOTH/;

use vars qw(@ISA @EXPORT_OK);

BEGIN {

    require File::Copy; #avoid import

    @EXPORT_OK=(@File::Copy::EXPORT,@File::Copy::EXPORT_OK);

    no strict 'refs';

    foreach my $sub (@EXPORT_OK) {
        *$sub = \&{'File::Copy::'.$sub};
    }

    push @EXPORT_OK, 'copyx';
}

sub copyx {
    my @args = @_;

    File::Copy::copy(@args)
        or return;

    # a sensible default 
    my $perms = 0644;
    
    # preserve executable bit in source if present
    my $mode = (stat($args[0]))[2];
    $perms |= $mode & S_IXUSR;
    $perms |= $mode & S_IXGRP;
    $perms |= $mode & S_IXOTH;

    # make sure that $args[1] is in fact a file and not a directory
    # or we end up chmodding that directory
    my $path = $args[1];
    if (-d $path) {
        require File::Basename;
        my $leaf = File::Basename::basename($args[0]);
        $path = "$path/$leaf";
    }

    chmod $perms, $path;

    return 1;
}

#==============================================================================

=head1 NAME

Util::File::Copy - Default import-suppressing wrapper for File::Copy

=head1 SYNOPSIS

    use Util::File::Copy qw(copy);

=head1 DESCRIPTION

This wrapper simply overrides the default import behaviour of the real
L<File::Copy>. Use it in place of the standard module to force imports.
Note that the only difference in behaviour between the two modules is when
no import arguments and no parantheses are used:

    use File::Copy;       # default imports
    use Util::File::Copy; # no imports

The second line is therefore equivalent to:

    use File::Copy();     # no imports (explicitly)

It additionally provides the following additional functions built
on top of L<File::Copy>:

=head2 FUNCTIONS

==head3 copyx($src, $dest)

Does the exact same thing as C<File::Copy::copy> except that it will preserve
the executable bits for user, group and other of I<$src>.  Furthermore, mode of
I<$dest> will be user-read/writeable and group/world-readable. 

Returns true if the actual copy succeeded, regardless of whether the chmod
succeeded.

=cut

#==============================================================================

=head1 SEE ALSO

L<File::Copy>

=cut

1;
