package Change::Bulletin;
use strict;

use base qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[displayBulletin];

#==============================================================================

=head1 NAME

Change::Bulletin - Display message bulletins

=head1 SYNOPSIS

    use Change::Bulletin qw(displayBulletin displayBulletinInXWindow);
    use Change::Symbols qw(CSCHECKIN_NEWS CSCHECKIN_MOTD CSCHECKIN_LOCK);

    displayBulletin (CSCHECKIN_NEWS);
    displayBulletin (CSCHECKIN_LOCK);
    displayBulletinInXWindwo (CSCHECKIN_MOTD);

=head1 DESCRIPTION

Routines to display various message bulletins in STDERR and X-Windows. 
L<cscheckin> is the primary consumer of the functionality provided by this 
module.

=cut

#==============================================================================

=head1 ROUTINES

=head2 displayBulletin ($bulletin)

Display contents of a bulletin file in STDERR

=cut

#------------------------------------------------------------------------------

sub displayBulletin ($;$) {
    my ($bulletin, $delimiter) = @_;
    my $bulletin_displayed=0;

    if (-f $bulletin && -s _ > 0) {
	print STDERR "\n\n";
	my $fh=IO::File->new($bulletin);
	if ($fh->open("< $bulletin")) {
	    unless (defined $delimiter) {
		print STDERR "\n\n", <$fh>, "\n\n";
	    } else {
		while (my $line=<$fh>) {
		    print STDERR "$delimiter $line";
		}
	    }
	    close $fh;
	    
	    print STDERR "\n\n";
	    $bulletin_displayed = 1;
	}
    }

    
    return $bulletin_displayed;
}

=head2 displayBulletinInXWindow ($bulletin)

Display contents of a bulletin file in an X Window (popup window)

=cut

sub displayBulletinInXWindow ($) {
    my $bulletin=shift;
    my $bulletin_displayed=0;
    
    # NOT QUITE WORKING YET: Not able to open 
    # $ENV{DISPLAY} is cleaned before getting here 
    if (-f $bulletin && -s _ > 0) {
	my @cmd = "/usr/local/bin/xmessage -file $bulletin";
        system(@cmd);
        $bulletin_displayed = 1;
    }
    
    return $bulletin_displayed;
}

#==============================================================================

=head1 AUTHOR

Dawit Habte (dawit@bloomberg.net)

=head1 SEE ALSO

L<cscheckin>

=cut

1;
