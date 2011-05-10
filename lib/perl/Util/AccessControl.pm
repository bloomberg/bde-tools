package Util::AccessControl;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    acceptUser
    denyUser
];

use IO::File;

use Util::Message qw(fatal);

#==============================================================================

=head1 NAME

Util::AccessControl - Access control utilities

=head1 SYNOPSIS

    use Util::AccessControl qw(acceptUser);

=head1 DESCRIPTION

This module provides routines for maintaining access control.

=cut

#==============================================================================

=head1 ROUTINES

The following routines are available for export:

=head2 acceptUser($acceptfile [,$username])

Return true if the user name supplied as the second argument, or the real user
if no user is supplied, is present in the access list provided as the first
argument. I<If the file does not exist, no access control is applied and
a true value is returned>. If the user is not present, return false. If the
accept list file is present but cannot be opened or read, an exception is
thrown.

=cut

sub acceptUser ($;$) {
    my ($acceptfile,$user)=@_;

    return 1 unless -f $acceptfile; #no list, no access control

    $user=getpwuid($<) unless $user; #real user

    my $fh=IO::File->new($acceptfile);
    fatal "Unable to open $acceptfile ($!), aborting" unless defined $fh;

    my $found=0;
    while (<$fh>) {
	chomp;
	$found=1,last if $_ eq $user;
    }

    return $found;
}

=head2 denyUser($denyfile [,$username])

Return false if the user name supplied as the second argument, or the real user
if no user is supplied, is present in the deny list provided as the first
argument. I<If the file does not exist, no access control is applied and
a true value is returned>. If the user is not present, return true.

=cut

sub denyUser ($;$) {
    my ($denyfile,$user)=@_;
    return 1 unless -f $denyfile;
    return acceptUser($denyfile,$user) ? 0 : 1;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=cut

1;
