package Linker::Xcoff;
# Reads the XCOFF header from IBM object files.

@EXPORT_OK = qw(F_RELFLG F_EXEC F_LNNO F_FDPR_PROF F_FDPR_OPTI F_DSA
                F_DYNLOAD F_SHROBJ F_LOADONLY);
use base Exporter;

use strict;
use English;
use Carp qw(croak);

use constant XCOFF32_TEMPLATE => "SSlLLSS";
use constant F_RELFLG     => 0x0001;
use constant F_EXEC       => 0x0002;
use constant F_LNNO       => 0x0004;
use constant F_FDPR_PROF  => 0x0010;
use constant F_FDPR_OPTI  => 0x0020;
use constant F_DSA        => 0x0040;
use constant F_DYNLOAD    => 0x1000;
use constant F_SHROBJ     => 0x2000;
use constant F_LOADONLY   => 0x4000;

#============================================================================

=head1 NAME

Linker::Xcoff - Manipulate XCOFF file headers on AIX

=head1 SYNOPSIS

    use Linker::Xcoff;

    $xcoff = Linker::Xcoff->new($filename);

    $xcoff->isXcoff or die "File is not XCOFF";

    $xcoff->isShared and print "File is a shared object";

    $magic  = $xcoff->f_magic ;
    $nscns  = $xcoff->f_nscns ;
    $timdat = $xcoff->f_timdat;
    $symptr = $xcoff->f_symptr;
    $nsyms  = $xcoff->f_nsyms ;
    $opthdr = $xcoff->f_opthdr;
    $flags  = $xcoff->f_flags ;

    $xcoff->f_magic ($magic );
    $xcoff->f_nscns ($nscns );
    $xcoff->f_timdat($timdat);
    $xcoff->f_symptr($symptr);
    $xcoff->f_nsyms ($nsyms );
    $xcoff->f_opthdr($opthdr);
    $xcoff->f_flags ($flags );

    $filename = $xcoff->filename;
    $xcoff->filename($filename);

    $xcoff->write;

=head2 Exported Flag Constants

The following constants can be used to read or modify the C<f_flags>
field using bitwise operations (C<&>, C<|>, and C<^>).

    Constant        Value
    
    F_RELFLG        0x0001
    F_EXEC          0x0002
    F_LNNO          0x0004
    F_FDPR_PROF     0x0010
    F_FDPR_OPTI     0x0020
    F_DSA           0x0040
    F_DYNLOAD       0x1000
    F_SHROBJ        0x2000
    F_LOADONLY      0x4000

=head1 DESCRIPTION

This module is used to read and write the XCOFF header of AIX C<.o>
and C<.so> files.  The XCOFF header contains information such as the
number of symbols in the object file and a bit indicating whether
the the file is shared object.

Documentation for XCOFF can be found by typing "C<man XCOFF>".

=head1 AUTHOR

Pablo Halpern E<lt>F<phalpern@bloomberg.net>E<gt>.

=cut

#============================================================================

sub _setGet($$;$) {
    my ($self, $index, $newval) = @ARG;
    $self->[$index] = $newval if (defined $newval);
    return $self->[$index];
}

sub f_magic ($;$) { return $ARG[0]->_setGet(0, $ARG[1]); }
sub f_nscns ($;$) { return $ARG[0]->_setGet(1, $ARG[1]); }
sub f_timdat($;$) { return $ARG[0]->_setGet(2, $ARG[1]); }
sub f_symptr($;$) { return $ARG[0]->_setGet(3, $ARG[1]); }
sub f_nsyms ($;$) { return $ARG[0]->_setGet(4, $ARG[1]); }
sub f_opthdr($;$) { return $ARG[0]->_setGet(5, $ARG[1]); }
sub f_flags ($;$) { return $ARG[0]->_setGet(6, $ARG[1]); }
sub filename($;$) { return $ARG[0]->_setGet(7, $ARG[1]); }

sub new($$) {
    my ($proto, $object) = @ARG;

    my $class=(ref $proto) || $proto;
    my $self = bless [ ], $class;

    open OBJECT, "< $object" or return undef;
    binmode OBJECT;

    my $packedHdr = "";
    my $bytesRead = read OBJECT, $packedHdr, 24;
    close OBJECT;

    return $self if ($bytesRead < 20);  # Return empty object

    @$self = unpack(XCOFF32_TEMPLATE, $packedHdr);
    push @$self, $object;

    return $self;
}

sub isXcoff($) {
    my ($self) = @ARG;
    return 0 unless scalar @$self;
    my $magic = $self->f_magic();
    return ($magic == 0x01df); # || ($magic == 0x01f7) || ($magic == 0x0104)
}

sub isShared($) {
    my ($self) = @ARG;
    return 0 != ($self->f_flags & F_SHROBJ);
}

sub write($) {
    my ($self) = @ARG;

    my $packedHdr = pack(XCOFF32_TEMPLATE, @$self);
    die "Invalid header length" unless (length($packedHdr) == 20);

    my $object = $self->filename;
    open OBJECT, "+< $object" or return undef;
    binmode OBJECT;

    my $bytesWritten = syswrite OBJECT, $packedHdr, 20, 0;
    close OBJECT;

    die "Failed to write 20 bytes to $object" unless ($bytesWritten == 20);
    return $self;
}

1;  # End package Xcoff;
