package Util::File::Types;

use strict;

#------------------------------------------------------------------------------

=head1 NAME

Util::File::Types - Utility functions for querying file meta-information

=head1 SYNOPSIS

    use Util::File::Types qw(isInclude isTranslationUnit hasRcsFile);

    XXX

=head1 DESCRIPTION

C<Util::File::Types> provides utility functions that allow querying of
meta-data concerning individual files (e.g. this is an include file, this is
a compilable translation unit, this is a binary file, etc.).

=cut

#------------------------------------------------------------------------------

=head1 EXPORTS

The following groups and individual routines are available for export:

=head2 GROUPS

=over 4

=item none

=back

=head2 ROUTINES

=over 4

=item L<"isInclude">

=item L<"isTranslationUnit">

=item L<"hasRcsFile">

=back

=cut

use Util::File::Basename qw(dirname basename);
use BDE::Build::Invocation qw($FS);

use Exporter;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

my @stat_ops=qw[
    isInclude
    isTranslationUnit
    hasRcsFile
    is_binary

    $CHECK_RCS
    $VALID_TRANSLATION_UNIT_GLOB
    $VALID_INCLUDE_GLOB 
];

@ISA = ('Exporter');
@EXPORT_OK = (@stat_ops);

%EXPORT_TAGS = (
    all => \@EXPORT_OK,
);


use vars qw(
    $CHECK_RCS

    @g_validTranslationUnitTypes 
    $g_validTranslationUnitRegex
    $VALID_TRANSLATION_UNIT_GLOB

    @g_validIncludeTypes 
    $g_validIncludeRegex
    $VALID_INCLUDE_GLOB
);


# XXX:  Default to considering RCS files for various file type checks.  This
# should probably be turned off once an RCS-robocop environment is no longer
# in use.
$CHECK_RCS = 1;

#------------------------------------------------------------------------------

=head1 PACKAGE VARIABLES

The following variables are available for export:

=over 4

=item $CHECK_RCS

=cut


#------------------------------------------------------------------------------



=head1 ROUTINES

The following routines are available for export:

=over 4

=item isInclude
=item isTranslationUnit
=item hasRcsFile

=cut

#------------------------------------------------------------------------------



@g_validIncludeTypes = qw{
    h
    hpp
    inc
    gobxml
};

$g_validIncludeRegex = qr{
    \. ( @{[join('|', @g_validIncludeTypes)]} )
}x;

$VALID_INCLUDE_GLOB =
    "*.{" . join(',', @g_validIncludeTypes) .
        ($CHECK_RCS ?
            ("," .  join('\,v,', @g_validIncludeTypes) .  '\,v') :
            "") .
    "}";

# internal routine; use isInclude instead
sub _isInclude($;$)
{
    my ($file, $careAboutRcs) = @_;

    my $rcsSuffixRegex = ($careAboutRcs ? "(,v)?" : "");

    # String-check only; does not touch the filesystem.
    return scalar($file =~ m{$g_validIncludeRegex
                             $rcsSuffixRegex
                             $}x);
}   # _isInclude

@g_validTranslationUnitTypes = qw{
    c
    cpp
    gob
    l
    y
    ec
};

$g_validTranslationUnitRegex = qr{
    \. ( @{[join('|', @g_validTranslationUnitTypes)]} )
}x;

$VALID_TRANSLATION_UNIT_GLOB =
    "*.{" . join(',', @g_validTranslationUnitTypes) .
        ($CHECK_RCS ?
            ("," .  join('\,v,', @g_validTranslationUnitTypes) .  '\,v') :
            "") .
    "}";

# internal routine; use isTranslationUnit instead 
sub _isTranslationUnit($;$)
{
    my ($file, $careAboutRcs) = @_;

    my $rcsSuffixRegex = ($careAboutRcs ? "(,v)?" : "");

    # String-check only; does not touch filesystem.
    return scalar($file =~ m{$g_validTranslationUnitRegex
                             $rcsSuffixRegex
                             $}x);
}   # _isTranslationUnit


# internal routine; use hasRcsFile instead
sub _hasRcsFile($)
{
    my ($file) = @_;

    # Figure out what the non-RCS file is called, just in case an RCS file
    # was given.
    my $dir = dirname($file);
    $file = basename($file);

    $dir =~ s{${FS}RCS$}{};
    $file =~ s{,v$}{};

    # Try without RCS subdir
    my $rcsFile = "$dir$FS$file,v";
    return $rcsFile if (-f $rcsFile);

    # Try with RCS subdir
    $rcsFile = "$dir${FS}RCS$FS$file,v";
    return $rcsFile if (-f $rcsFile);

    return undef;
}   # _hasRcsFile



=head2 isInclude(<FILE>[,<ALLOW_RCS>])

Return true if the given filename is an include file.  The check is
entirely string-based and does not involve querying the file system.
An include file is defined to be any file included by any translation unit.
If ALLOW_RCS is set (default=unset), a trailing ',v' on the filename is
permitted.

=cut


sub isInclude($;$)
{
    return _isInclude($_[0], $_[1] ? $_[1] : $CHECK_RCS);
}   # isInclude



=head2 isTranslationUnit(<FILE>[,<ALLOW_RCS>])

Return true if the given filename is a translation unit.  The check is
entirely string-based and does not involve querying the file system.  A
translation unit is defined to be any file intended to be passed through a
compiler.  If ALLOW_RCS is set (default=unset), a trailing ',v' on the
filename is permitted.

=cut


sub isTranslationUnit($;$)
{
    return _isTranslationUnit($_[0], $_[1] ? $_[1] : $CHECK_RCS);
}   # isTranslationUnit



=head2 hasRcsFile(<FILE>)

Return undef if the given filename is not an RCS file and does not have a
corresponding RCS file.  Otherwise, return the pathname to the RCS file.  We
could have just returned true/false but why do the work twice?
Will query the file system.

=cut


sub hasRcsFile($)
{
    return _hasRcsFile($_[0]);
}   # isTranslationUnit

sub is_binary {
    my $file = shift;

    return $file =~ /\.(ml)$/;
}

#------------------------------------------------------------------------------

=head1 AUTHOR

Shawn Halpenny (shalpenny1@bloomberg.net)

=cut

1;
