#!/opt/bb/bin/perl

use strict;
use warnings;

use Pod::Usage qw(pod2usage);

use FindBin;
use File::Path;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use BDE::FileSystem;
use BDE::Component;

=head1 SYNOPSIS

insert-boilerplat-to-sources.pl repoPath patchFile componentListFile

Takes the specified 'patchfile' and applies it to all the files (.h, .cpp, and
.t.cpp) for each of the files listed in the 'componentListFile' file in the
specified 'repoPath' repository.

Note that no attempt is made to avoid applying patches twice, so if this script
is run twice, the banner WILL be repeated.

A sample patchfile would contain something like the following:

  *** /home/mgiroux/bsl-internal/groups/bal/balb/balb_controlmanager.h	Thu Oct  1 12:37:34 2015
  --- /home/mgiroux/bsl-internal/groups/bal/balb/balb_controlmanager.h.patched	Tue Oct  6 10:55:52 2015
  ***************
  *** 1 ****
  --- 2,9 ----
  + 
  + ///NON STANDARD//NON STANDARD//NON STANDARD//NON STANDARD//NON STANDARD////////
  + //
  + // Note that this component does not follow the current BDE style guidelines,
  + // and should not be taken as an exemplar.
  + //
  + ///NON STANDARD//NON STANDARD//NON STANDARD//NON STANDARD//NON STANDARD////////
  + 

=cut

$|++;

if (@ARGV != 3) {
    pod2usage(2);
}

my $repoPath = $ARGV[0];
my $patchFile = $ARGV[1];
my $componentListFile = $ARGV[2];

my $root=new BDE::FileSystem($repoPath);

my %seenComponents;

open(my $componentListFH, "<", $componentListFile)
    or die "Error $! opening $componentListFile";

COMPONENT: foreach my $componentName(<$componentListFH>) {
    chomp $componentName;
    my $componentLocation = $root->getComponentLocation($componentName);

    if ($seenComponents{$componentName}++) {
        print "=!=!=!=!=!=!=!=!=!=!=!=! Already processed $componentName\n";
        next COMPONENT;
    }

    print "======== patching component $componentName\n";
    foreach my $ext(qw(.h .cpp .t.cpp)) {
        my $filename = "$componentLocation/$componentName$ext";

        system "/opt/bb/bin/patch  $filename $patchFile";

        if ($?==0) {
            print "OK\n";
        }
        else {
            print "FAILED - error $?\n";
        }
    }
}
