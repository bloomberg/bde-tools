#!/opt/swt/bin/perl

use strict;
use warnings;
use File::Copy;

sub Usage()
{
    return <<USAGE;
$0 [-h|--help|--bsl|--macro] [--backups] files...
    -h or --help: print this help text and exit

    --macro     : converts "BloombergLP::bcema_SharedPtr" into its
                  macro equivalent to prepare for the bsl::shared_ptr
                  transition.  This is the default!

    --bsl       : converts the --macro macros and the "old" bcema/bdema forms
                  to their bsl equivalents.

    --backups   : saves backup files (.bak)


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

my @bslModeConversions = (
    sub {
        my $count = 0;
        my $replacement="bsl::dynamic_pointer_cast";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BloombergLP\s*::\s*bcema_SharedPtrUtil\s*::\s*dynamicCast
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="bsl::dynamic_pointer_cast";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!bcema_SharedPtrUtil\s*::\s*dynamicCast
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="BloombergLP::bslma::ManagedPtr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BloombergLP\s*::\s*bdema_ManagedPtr
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="BloombergLP::bslma::ManagedPtr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BLOOMBERGLP_BDEMA_MANAGEDPTR
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="bslma::ManagedPtr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!bdema_ManagedPtr
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },


    sub {
        my $count = 0;
        my $replacement="bsl::shared_ptr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BloombergLP\s*::\s*bcema_SharedPtr
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="bsl::shared_ptr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BLOOMBERGLP_BCEMA_SHAREDPTR
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="bsl::shared_ptr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!bcema_SharedPtr
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },


    sub {
        my $count = 0;
        my $replacement="bsl::weak_ptr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BloombergLP\s*::\s*bcema_WeakPtr
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="bsl::weak_ptr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!BLOOMBERGLP_BCEMA_WEAKPTR
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },

    sub {
        my $count = 0;
        my $replacement="bsl::weak_ptr";
        my $replacementLength=length($replacement);

        $count++
            foreach
                s!bcema_WeakPtr
                 !$replacement.(" "x(length($&)-$replacementLength))!gex;

        return $count;
     },
);

if (!@ARGV || $ARGV[0] =~ m!-h|--help!) {
    print Usage();
    exit 1;
}

my $isBslMode = 0; # 0 for macro mode, 1 for bsl.

my $useBackups = 0;

if ($ARGV[0] =~ m!^--bsl!) {
    print STDERR "--bsl mode selected\n";
    $isBslMode = 1;
    shift @ARGV;
}

if ($ARGV[0] =~ m!^--macro!) {
    print STDERR "--macro mode selected (which is already the default)\n";
    $isBslMode = 0;
    shift @ARGV;
}

if ($ARGV[0] =~ m!^--backups!) {
    print STDERR "--backups enabled\n";
    $useBackups = 1;
    shift @ARGV;
}

for my $originalFilename(@ARGV) {
    my $bakFilename = findBackupName($originalFilename);

    if ($useBackups) {
        print STDERR "$originalFilename ($bakFilename)... ";
    }
    else {
        print STDERR "$originalFilename... ";
    }

    copy($originalFilename, $bakFilename)
        or die "Copy from $originalFilename to $bakFilename failed, error $!";

    open(my $inFile, "<", $bakFilename)
      or die "Error '$!' opening $bakFilename";

    open(my $outFile, ">", $originalFilename)
      or die "Error '$!' opening $originalFilename";

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
            $count++
                foreach
              s!BloombergLP\s*::\s*(bcema_(SharedPtr|WeakPtr)|bdema_ManagedPtr)
               !"BLOOMBERGLP_".uc($1)." "!egx;
                    # Trailing space added to keep lengths equal
            print $outFile $_;
        }
    }

    print STDERR "$count change(s)\n";

    close($outFile);
    close($inFile);

    if (!$useBackups) {
        unlink $bakFilename;
    }
}
