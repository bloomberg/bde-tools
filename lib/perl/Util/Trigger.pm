package Util::Trigger;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    triggerPull
];

use Fcntl qw(F_GETFL F_SETFL O_WRONLY O_NONBLOCK);
use Util::Message qw(error);

#==============================================================================

=head1 NAME

Util::Trigger - Trigger pull utilities.

=head1 SYNOPSIS

    use Util::Trigger qw(triggerPull);

=head1 DESCRIPTION

This module provides routines for pulling triggers.  It may in future also
extend to trigger-listen operations.

=cut

#==============================================================================

=head1 ROUTINES

The following routines are available for export:

=head2 triggerPull($trigger)

Perform a nonblocking write of a single character to the file named in the
argument.  Return false if the trigger is not a writable fifo.  Otherwise
return true.

=cut

{
  sub triggerPull ($) {
    my $trigger = shift;
    
    unless (-p $trigger  and  -w _) {
      return 0;
    }

    my $fh;
    unless (sysopen($fh,$trigger,O_WRONLY | O_NONBLOCK)) {
      error "Unable to open $trigger: $!";
      return 0;
    }

    my $flags;
    unless ($flags = fcntl($fh,F_GETFL,0)) {
      error "Unable to read $trigger flags: $!";
      return 0;
    }
    unless (fcntl($fh,F_SETFL,$flags | O_NONBLOCK)) {
      error "Unable to read $trigger flags: $!";
      return 0;
    }

    syswrite($fh,"\0",1);# ignore error
    close($fh);# ignore error

    return 1;
  }
}

#==============================================================================

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=cut

1;
