package BDE::Build::Invocation;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw(
  $INVOKE
  $FS
  $FSRE
);

use vars qw($INVOKE $FS $FSRE);

#==============================================================================

=head1 NAME

BDE::Build::Invocation - Platform-specific invocation constants

=head1 SYNOPSIS

    use BDE::Build::Invocation qw($INVOKE $FS $FSRE);

    system("$INVOKE .${FS}directory${FS}script");

    my @directory_path_parts = split /$FSRE/,$0;

=head1 DESCRIPTION

This module provides platform-specific constants related to invocation of
external processes, each of which is available for export:

=over 4

=item C<$INVOKE>

The correct way to invoke a Perl script on this platform. For Windows,
this is C<$^X> (the pathname of the Perl interpreter used to run the
invoking script), in case the .pl mapping is not present.

=item C<$FS>

The directory separator for this platform.

=item C<$FSRE>

The regular expression to match the directory separator for this platform.

=back

=head1 NOTES

C<BDE::Build::Invocation> is not currently a derived class of L<Symbols>, but
this may change in time. It is also not a client of L<File::Spec> since its
needs are currently still basic.

=cut

#==============================================================================

$INVOKE="";
$FS="";

if ($^O =~ /win/i and $^O !~ /(cyg|dar)win/i) {
    # Windows may require explicit perl invokation
    my $PERL_PROG = $^X;
    $INVOKE="$PERL_PROG ";
    $FS="\\";
    $FSRE='\\\\'
} else {
    $INVOKE="";
    $FS="/";
    $FSRE='/';
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<BDE::FileSystem>, L<Compat::File::Spec>, L<Util::File::Basename>

=cut

1;
