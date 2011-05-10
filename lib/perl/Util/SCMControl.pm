package Util::SCMControl;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    acceptSCMUser
];

use IO::File;

#==============================================================================

=head1 NAME

Util::SCMControl - Access control utilities for SCM direct access

=head1 SYNOPSIS

    use Util::SCMControl qw(acceptSCMUser);

=head1 DESCRIPTION

This module provides routines for maintaining access control.

=cut

#==============================================================================

=head1 ROUTINES

The following routines are available for export:

=head2 acceptSCMUser()

Real user must be on the accept list.  This list must exist and should include
robocop.  If the user is robocop, check for CHANGE_USER on list.  Also accept
unset CHANGE_USER, because the gateway always sets this variable, therefore
unset indicates robo execution.

=cut

sub acceptSCMUser {
    # Use of a symbol drags in Sybmols.pm etc.  Don't for now.
    my $acceptfile = '/bbsrc/tools/data/newcheckin/scm.accept';
    return 0 unless -f $acceptfile; #no list, no access

    my $user=getpwuid($<); #real user

    my $fh=IO::File->new($acceptfile);
    if (!defined $fh) {
      print STDERR "!! ERROR: SCMControl: unable to open $acceptfile ($!)\n";
      return 0;
    }

    my $found=0;
    while (<$fh>) {
	chomp;
	$found=1,last if $_ eq $user;
    }
    if (!$found) {
      print STDERR "!! ERROR: SCMControl: no access for $user\n";
      return 0;
    }
    if ($user ne 'robocop') {
      return 1;
    }
    if (!exists $ENV{'CHANGE_USER'}) {
      return 1;
    }
    $fh->seek(0,0)  or  return 0;
    $user = $ENV{'CHANGE_USER'};
    while (<$fh>) {
	chomp;
	$found=1,last if $_ eq $user;
    }
    if (!$found) {
      print STDERR "!! ERROR: SCMControl: no access for $user\n";
    }
    return $found;
}

#==============================================================================

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=cut

1;
