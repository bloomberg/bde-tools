package BDE::Util::RuntimeFlags;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw(
    setDeprecationLevel
    getDeprecationLevel
    setNoMetaMode
    getNoMetaMode
);

#==============================================================================

my $deprecationLevel = 0;
my $noMetaMode = 0;

sub setDeprecationLevel($) { $deprecationLevel = $_[0]; }
sub getDeprecationLevel()  { return $deprecationLevel; }

sub setNoMetaMode() {
    $noMetaMode = 1;
    #setDeprecationLevel(1);  
}
sub getNoMetaMode()  { return $noMetaMode; }

#==============================================================================

=head1 AUTHOR

Ralph Gibbons (rgibbons1@bloomberg.net)

=cut

1;
