package Change::Util::Sweep;

use strict;
use warnings;

use base qw/Exporter/;
use File::Basename;
use Errno;

use Change::Symbols                 qw/$CHECKIN_ROOT/;

use Production::Services;
use Production::Services::ChangeSet qw/getChangeSetDbRecord/;

our @EXPORT_OK = qw/gatherStaleMaterialFromCheckinRoot
                    gatherBregMaterialFromCheckinRoot
                    gatherStprMaterialFromCheckinRoot
                    purgeSweepMaterialFromCheckinRoot
                    changeSetSwept/;

use constant {
    BREG => 1,
    STPR => 2, 
};

my $svc;
my (%suckers, %breg, %stpr);
sub _genuine_sucker {
    my $csid = shift;

    if (exists $suckers{$csid}) {
        return $csid if $suckers{$csid};
        return 0;
    }

    $svc ||= Production::Services->new;
    my $cs = getChangeSetDbRecord($svc, $csid) or return 0;

    if ($cs->isImmediateMove or $cs->isBregMove) {
        $suckers{$csid} = 0;
        return 0;
    }

    $suckers{$csid} = 1;

    return $csid;
}

sub _genuine_breg {
    my $csid = shift;

    if (exists $breg{$csid}) {
        return $csid if $breg{$csid};
        return 0;
    }

    $svc ||= Production::Services->new;
    my $cs = getChangeSetDbRecord($svc, $csid) or return 0;

    {
        no warnings 'syntax';
        $breg{$csid} = 1 and return $csid if $cs->isBregMove;
    }

    return $breg{$csid} = 0;
}

sub _genuine_stpr {
    my $csid = shift;

    if (exists $stpr{$csid}) {
        return $csid if $stpr{$csid};
        return 0;
    }

    $svc ||= Production::Services->new;
    my $cs = getChangeSetDbRecord($svc, $csid) or return 0;

    {
        no warnings 'syntax';
        $breg{$csid} = 1 and return $csid if $cs->isImmediateMove;
    }

    return $stpr{$csid} = 0;
}

sub _get_csid {
    my ($file, $type) = @_;

    # failure to open because the file does not exist 
    # should not be a problem: the file has been moved
    # out of CHECKIN_ROOT between the glob and this open.
    open my $fh, $file or do {
        return if $!{ENOENT};
        die "Could not open $file for reading: $!";
    };

    if (not defined $type) {
        /^# CHANGE_SET: (.{18})/ || /CSID:(.{18}) / 
            and return _genuine_sucker($1) while <$fh>;
    } elsif ($type == BREG) {
        /^# CHANGE_SET: (.{18})/ || /CSID:(.{18}) / 
            and return _genuine_breg($1) while <$fh>;
    } elsif ($type == STPR) {
        /^# CHANGE_SET: (.{18})/ || /CSID:(.{18}) / 
            and return _genuine_stpr($1) while <$fh>;
    }
}

#------------------------------------------------------------------------------

=head1 NAME

Change::Util::Sweep - Sweep-related functionality

=head1 FUNCTIONS

=head2 gatherStaleMaterialFromCheckinRoot([$root])

Scans I<$root> (defaulting to CHECKIN_ROOT) for material left over
from a previous sweep operation.

Returns a hash with CSIDs as keys referenced in I<$root> and an array-ref as
value containing the basename of source files found.

=cut

sub gatherStaleMaterialFromCheckinRoot {
    my $root = shift;

    $root = $CHECKIN_ROOT if not defined $root;

    my @sh = grep /\.checkin\.sh1?$/, glob "$root/*.checkin.sh*";
    push @sh, glob "$root/*.checkin.reason";
    
    my %csids;
    for my $f (@sh) {
        my ($file) = basename($f) =~ /(.*)\.checkin\.(?:sh1?|reason)$/;
        my $csid = _get_csid($f) or next;
        push @{ $csids{$csid} }, $file;
    }

    # filter out duplicate filenames
    for (values %csids) {
        my %seen;
        $_ = [ grep !$seen{$_}++, @$_ ];
    }

    return %csids;
}

=head2 gatherBregMaterialFromCheckinRoot([$root])

Scans I<$root> (defaulting to CHECKIN_ROOT) for breg material.

Returns a hash with CSIDs as keys referenced in I<$root> and an array-ref as
value containing the basename of source files found.

=cut

sub gatherBregMaterialFromCheckinRoot {
    my $root = shift;

    $root = $CHECKIN_ROOT if not defined $root;

    my @sh = grep /\.checkin\.sh1?$/, glob "$root/*.checkin.sh*";
    push @sh, glob "$root/*.checkin.reason";
    
    my %csids;
    for my $f (@sh) {
        my ($file) = basename($f) =~ /(.*)\.checkin\.(?:sh1?|reason)$/;
        my $csid = _get_csid($f, BREG) or next;
        push @{ $csids{$csid} }, $file;
    }

    # filter out duplicate filenames
    for (values %csids) {
        my %seen;
        $_ = [ grep !$seen{$_}++, @$_ ];
    }

    return %csids;
}

=head2 gatherStprMaterialFromCheckinRoot([$root])

Scans I<$root> (defaulting to CHECKIN_ROOT) for STPR material.

Returns a hash with CSIDs as keys referenced in I<$root> and an array-ref as
value containing the basename of source files found.

=cut

sub gatherStprMaterialFromCheckinRoot {
    my $root = shift;

    $root = $CHECKIN_ROOT if not defined $root;

    my @sh = grep /\.checkin\.sh1?$/, glob "$root/*.checkin.sh*";
    push @sh, glob "$root/*.checkin.reason";
    
    my %csids;
    for my $f (@sh) {
        my ($file) = basename($f) =~ /(.*)\.checkin\.(?:sh1?|reason)$/;
        my $csid = _get_csid($f, STPR) or next;
        push @{ $csids{$csid} }, $file;
    }

    # filter out duplicate filenames
    for (values %csids) {
        my %seen;
        $_ = [ grep !$seen{$_}++, @$_ ];
    }

    return %csids;
}

=head2 purgeSweepMaterialFromCheckinRoot($changeset, [$root])

Delete all files of I<$changeset> and their related scripts from
I<$root> which defaults to CHECKIN_ROOT.

Returns a two-element list, with the first element being an array-ref
of files succesfully deleted, and the second element an array-ref
of files that could not been deleted.

=cut

sub purgeSweepMaterialFromCheckinRoot {
    my ($changeset, $root) = @_;

    $root = $CHECKIN_ROOT if not defined $root;

    my (@del, @ndel);
    for my $file ($changeset->getFiles) {
        my $leaf = $file->getLeafName;
        for ($leaf, "$leaf.checkin.reason", 
             "$leaf.checkin.sh", "$leaf.checkin.sh1") {
            next if not -e "$root/$_";
            if (unlink "$root/$_") {
                push @del, "$root/$_";
            } else {
                push @ndel, "$root/$_";
            }
        }
    }

    return (\@del, \@ndel);
}

=head2 changeSetSwept($changeset)

Returns true of I<$changeset> has been fully swept into RCS. False otherwise.

=cut

sub changeSetSwept {
    my $changeset = shift;

    my $stage = $changeset->getStage;
    my $csid  = $changeset->getID;

    my $ok = 1;

    require Change::Util::InterfaceRCS;
    Change::Util::InterfaceRCS->import('getFileVersionForCSID');
    for my $file ($changeset->getFiles) {
        next if $file->isUnchanged;
        if (not defined getFileVersionForCSID($file, $csid, $stage)) {
            $ok = 0;
            last;
        }
    }

    return $ok;
}

1;

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

=cut
