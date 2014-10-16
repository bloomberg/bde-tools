#!/opt/swt/bin/perl

use strict;
use warnings;
use File::Copy;
use Getopt::Long;

sub Usage()
{
    return <<USAGE;
$0 [-h|--help|--bsl|--macro] [--backups] [--check] files...
    -h or --help: print this help text and exit

    --macro     : converts "BloombergLP::bcema_SharedPtr" into its
                  macro equivalent to prepare for the bsl::shared_ptr
                  transition.  This is the default!

    --bsl       : converts the --macro macros and the "old" bcema/bdema forms
                  to their bsl equivalents.

    --backups   : saves backup files (.bak)

    --check     : check-only mode - prints any files which would be modified, but
                  has no on-disk effect (and ignores the --backups switch).

    This script converts C++ header/source files to help with the
    change from bcema/bslma pointer types into more-standard bsl types, working
    in-place and leaving the original files with a ".bak" (or ".bak.1", etc...
    if there are collisions) extension.

    The default '--macro' conversion converts the following namespace'd types
    into macro references, so the macros can be redirected once the bsl
    conversion is complete.
            Original                        Converted To
            BloombergLP::bdema_ManagedPtr   BLOOMBERGLP_BDEMA_MANAGEDPTR
            BloombergLP::bcema_SharedPtr    BLOOMBERGLP_BCEMA_SHAREDPTR
            BloombergLP::bcema_WeakPtr      BLOOMBERGLP_BCEMA_WEAKPTR

    The '--bsl' conversion should be run after BDE's bsl pointer conversion is
    complete, and will switch from the "old" names to new names:
            Original                        Converted To
            BloombergLP::bdema_ManagedPtr   BloombergLP::bslma::ManagedPtr
            BLOOMBERGLP_BDEMA_MANAGEDPTR    BloombergLP::bslma::ManagedPtr
            bdema_ManagedPtr                bslma::ManagedPtr

            BloombergLP::bcema_SharedPtr    bsl::shared_ptr
            BLOOMBERGLP_BCEMA_SHAREDPTR     bsl::shared_ptr
            bcema_SharedPtr                 bsl::shared_ptr

            BloombergLP::bcema_WeakPtr      bsl::weak_ptr
            BLOOMBERGLP_BCEMA_WEAKPTR       bsl::weak_ptr
            bcema_WeakPtr                   bsl::weak_ptr

USAGE
}

sub findBackupName
{
    my $filename = shift;
    my $ext = ".bak";

    my $result = "$filename$ext";

    if (!-e $result) {
        return $result;
    }

    my $extNumber = "0";
    $ext.=".";

    do {
        $result = $filename.$ext.$extNumber;

        goto RESULT unless -e $result;

        ++$extNumber;
    } while(1);

RESULT:
    return $result;
}

sub doSubstitution {
    my $needle            = shift;
    my $replacement       = shift;

    my $count             = 0;
    my $replacementLength = length($replacement);

    while(s!$needle
           !$replacement.(" "x(length($&)-$replacementLength))!gex) {
        ++$count;
    }

    return $count;

}

my @bslModeConversions = (
    sub {
        return doSubstitution(
                    'BloombergLP\s*::\s*bcema_SharedPtrUtil\s*::\s*dynamicCast'
                  , "bsl::dynamic_pointer_cast"
               );
     },

    sub {
        return doSubstitution(
                    'bcema_SharedPtrUtil\s*::\s*dynamicCast'
                  , "bsl::dynamic_pointer_cast"
               );
     },

    sub {
        return doSubstitution(
                    '(BloombergLP\s*::\s*)?\bbcema_SharedPtrNilDeleter\b'
                  , "bslstl::SharedPtrNilDeleter"
               );
     },

    sub {
        return doSubstitution(
                    'BloombergLP\s*::\s*bdema_ManagedPtr'
                  , "BloombergLP::bslma::ManagedPtr"
               );
     },

    sub {
        return doSubstitution(
                    'BLOOMBERGLP_BDEMA_MANAGEDPTR'
                  , "BloombergLP::bslma::ManagedPtr"
               );
     },

    sub {
        return doSubstitution(
                    'bdema_ManagedPtr'
                  , "bslma::ManagedPtr"
               );
     },

    sub {
        return doSubstitution(
                    'BloombergLP\s*::\s*bcema_SharedPtr'
                  , "bsl::shared_ptr"
               );
     },

    sub {
        return doSubstitution(
                    'BLOOMBERGLP_BCEMA_SHAREDPTR'
                  , "bsl::shared_ptr"
               );
     },

    sub {
        return doSubstitution(
                    'bcema_SharedPtr'
                  , "bsl::shared_ptr"
               );
     },

    sub {
        return doSubstitution(
                    'BloombergLP\s*::\s*bcema_WeakPtr'
                  , "bsl::weak_ptr"
               );
     },

    sub {
        return doSubstitution(
                    'BLOOMBERGLP_BCEMA_WEAKPTR'
                  , "bsl::weak_ptr"
               );
     },

    sub {
        return doSubstitution(
                    'bcema_WeakPtr'
                  , "bsl::weak_ptr"
               );
     },
);

my $isBslMode   = 0; # 0 for macro mode, 1 for bsl.
my $isMacroMode = 0; # 1 for macro mode, 0 for bsl.

my $useBackups  = 0;

my $isCheckMode = 0;

my $isHelp      = @ARGV==0;

GetOptions("bsl"     => \$isBslMode,
           "macro"   => \$isMacroMode,
           "backups" => \$useBackups,
           "check"   => \$isCheckMode,
           "h|help"  => \$isHelp,
       );

if ($isHelp) {
    print Usage();
    exit 0;
}

if ($isMacroMode && $isBslMode) {
    print STDERR "Only one of --macro or --bsl may be specified\n";
    exit 1;
}

# Default to macro mode
if (!($isMacroMode || $isBslMode)) {
    $isMacroMode = 1;
}

# Check mode disables backup logic
if ($isCheckMode) {
    $useBackups = 0;
}

for my $originalFilename(@ARGV) {
    my ($inFile, $outFile);
    my $bakFilename = findBackupName($originalFilename);

    if (!$isCheckMode) {
        copy($originalFilename, $bakFilename)
            or die "Copy from $originalFilename to $bakFilename failed, error $!";

        open($inFile, "<", $bakFilename)
            or die "Error '$!' opening $bakFilename";

        open($outFile, ">", $originalFilename)
            or die "Error '$!' opening $originalFilename";
    }
    else {
        open($inFile, "<", $originalFilename)
            or die "Error '$!' opening $originalFilename";

        open($outFile, ">", "/dev/null")
            or die "Error '$!' opening /dev/null";
    }

    my $count = 0;
    if ($isBslMode) {
        while(<$inFile>) {
            for my $substFunction(@bslModeConversions) {
                $count+=$substFunction->();
            }
            print $outFile $_;
        }
    }
    else {
        while(<$inFile>) {
            while(s!BloombergLP\s*::\s*(bcema_(SharedPtr|WeakPtr)|bdema_ManagedPtr)
                !"BLOOMBERGLP_".uc($1)." "!egx
            ) {
                ++$count;
            }
            # Trailing space added to keep lengths equal
            print $outFile $_;
        }
    }

    if (!$isCheckMode) {
        print STDERR "$originalFilename... ";

        if ($useBackups) {
            print STDERR "(backed up to $bakFilename)... ";
        }

        print STDERR "$count change(s)\n";

        if (!$useBackups) {
            unlink $bakFilename;
        }
    }
    else {
        if ($count) {
            printf "%-50s would be changed %4d time(s)\n", $originalFilename, $count;
        }
    }

    close($outFile);
    close($inFile);
}
