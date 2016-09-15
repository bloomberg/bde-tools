#!/usr/bin/env perl

# ----------------------------------------------------------------------------
# Copyright 2016 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE ----------------------------------

use strict;

#==============================================================================
# LIBRARIES
#------------------------------------------------------------------------------
use FindBin qw($Bin);
use lib "$FindBin::Bin/../lib/perl";

use Getopt::Long;
use File::Basename;
use Util::Message qw(fatal error warning alert verbose message debug);
$|=1;

#==============================================================================
# PARSE OPTIONS
#------------------------------------------------------------------------------
sub usage {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print STDERR<<_USAGE_END;

Usage: $prog -h | [-d] [-v] <-o htmlDir>
   --help      | -h            Display usage information (this text)
   --debug     | -d            Enable debug reporting
   --verbose   | -v            Enable verbose reporting
   --htmlDir   | -o <htmlDir>  Output directory (home of Doxygenated files)
                                   default: ./html

_USAGE_END
}

#------------------------------------------------------------------------------
sub getOptions {
    my %opts;

    Getopt::Long::Configure("bundling", "no_ignore_case");
    unless (GetOptions(\%opts, qw[
        help|h|?
        debug|d+
        verbose|v+
        htmlDir|o=s
    ])) {
        usage(), exit 1;
    }

    usage(), exit 0 if $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # output directory
    $opts{htmlDir} ||= "html";

    return \%opts;
}

#==============================================================================
# HELPERS: Architectural Name Validation
#------------------------------------------------------------------------------
{
    my $group     = "^(z_)?([el]_)?[a-z][a-z0-9]{2}";
    my $pig_comp  = $group . "[a-z0-9][a-z0-9]{0,2}";
    my $pig_nonc  = $group . "[+~][a-z][a-z0-9]*";
    my $ip        = "^(z_a_|a_)[a-z][a-z0-9]{3,}";
    my $cmp       = "($pig_comp|$ip)(_[a-z][a-z0-9]*){1,2}";

    sub isPackageGroupName($) {
        my     $name =  shift;
        return $name =~ m|$group$|;
    }
    
    sub isPackageInGroupName($) {
        my     $name =  shift;
        return $name =~ m|$pig_comp$|;
    }

    sub isPackageInGroupNoncName($) {
        my     $name =  shift;
        return $name =~ m|$pig_nonc$|;
    }

    sub isPackageIsolatedName($) {
        my     $name =  shift;
        return $name =~ m|$ip$|;
    }

    sub isPackageName($) {
        my     $name =  shift;
        return     isPackageInGroupName($name)
            || isPackageInGroupNoncName($name)
            ||    isPackageIsolatedName($name);
    }
    
    sub isComponentName($) {
        my     $name =  shift;
        return $name =~ m|$cmp$|;
    }
}

#==============================================================================
# MAJOR SECTION: Process '*_8h.html' File References
#------------------------------------------------------------------------------
sub editNonComponentFile($$) {
    my $ifile  = shift;
    my $entity = shift; $entity =~ s/\+/\\+/;

    my $displayFilename = basename $ifile;
    verbose "Edit: $displayFilename: $entity";

    open(FH, "< $ifile") or fatal "Cannot open for read: $ifile: $!";
    my @lines = <FH>; chomp @lines;
    close FH;


    for my $line (@lines) {
        if    ($line =~
m|^   <title>Bloomberg Development Environment: $entity.h Reference</title>$|)
                                                                              {
            $line =~ s/\.h/.txt/
        }
        elsif ($line =~ m|^<h1>$entity.h File Reference</h1>  </div>$|) {
            $line =~ s/\.h/.txt/
        }
    }

    my $ofile = $ifile;
    open(FH, "> $ofile") or fatal "Cannot open for write: $ofile: $!";
    print FH "$_\n" foreach @lines;
    close FH;
}

sub editNonComponentFileFiles($) {
    my $dir = shift;

    while (my $filename = <$dir/*_8h.html>) {
        my $entity = basename $filename; 
        $entity =~ s/_8h\.html$//;
        $entity =~ s/_09/\+/;
        $entity =~ s/__/_/;
        my $levelOfAggregation = isPackageGroupName($entity) ? 2 :
                                 isPackageName     ($entity) ? 1 :
                                                               0 ;
        if (0 < $levelOfAggregation) {
            editNonComponentFile($filename, $entity);
        } else {
           verbose "editNonComponentFileFiles: skip: $filename: $entity";
        }
    }

}

#==============================================================================
# MAJOR SECTION: Process 'files.html'
#------------------------------------------------------------------------------
sub editFilesFile($) {
    my $dir = shift;

    my $ifile = $dir . "/". "files.html";

    my $displayFilename = basename $ifile;
    verbose "Edit: $displayFilename";

    open(FH, "< $ifile") or fatal "Cannot open for read: $ifile: $!";
    my @lines = <FH>; chomp @lines;
    close FH;

    for my $line (@lines) {
        chomp $line;

        if ($line !~ m|^  <tr>|) {
            next;
        }

        my $entity = $line;
        $entity =~ s/<\/a>.*//;
        $entity =~ s/.*>//;
        $entity =~ s/\.h//;
        my $levelOfAggregation = isPackageGroupName($entity) ? 2 :
                                 isPackageName     ($entity) ? 1 :
                                                               0 ;
        if (0 < $levelOfAggregation) {
            $line =~ s/\.h</.txt</;
            $line =~ s/\[code\]/[text]/;
        }
    }

    my $ofile = $ifile; #$ofile =~ s/.html$/X.html/;
    open(FH, "> $ofile") or fatal "Cannot open for write: $ofile: $!";
    print FH "$_\n" foreach @lines;
    close FH;
}

#==============================================================================
# MAJOR SECTION: Process 'tree.html'
#------------------------------------------------------------------------------
sub editTreeFileLine($) {
    my $line     = shift;
   
    my $filename = $line;     $filename =~ s|</a></p>$||; $filename =~ s|.*>||;
    my $entity   = $filename; $entity =~ s|\.h$||;

    if (    isPackageName($entity)
    || isPackageGroupName($entity)) {
        my $old = $filename;
        my $new = $old;
        $old =~ s|\+|\\+|;
        $new =~ s|\.h|.txt|;
        $line =~ s|$old|$new|;
    }

    return $line;
}

use constant {
    STATE_Normal          => 0,
    STATE_NearListofFiles => 1,
    STATE_InListOfFile    => 2
};

sub editTreeFile($)
{
    my $htmlDir = shift;

    my $ifile = "$htmlDir" . "/" . "tree.html";
    verbose "Edit: $ifile";

    open(FH, "< $ifile") or fatal "Cannot open for read: $ifile: $!";
    my @lines = <FH>; chomp @lines;
    close FH;

    my $state = STATE_Normal;

    for my $line (@lines) {

    $line =~ s|target="basefrm"|target="_blank"|;

    if (STATE_Normal == $state) {
            if ($line =~ m|File List|) {
                $state = STATE_NearListofFiles;
            }
            next;
        } elsif (1 == $state) {
            if ($line =~ m|<div id=|) {    #<div id="folder8">
                $state = STATE_InListOfFile;
            }
            next;
        } elsif (STATE_InListOfFile == $state) {
            if ($line =~ m|</div>|) {
                $state = STATE_Normal;
            } else {
                $line = editTreeFileLine $line;
            }
            next;
        } else {
            fatal "logic error";
        }
    }

    my $ofile = $ifile; #$ofile =~ s/.html$/X.html/;
    open(FH, "> $ofile") or fatal "Cannot open for write: $ofile: $!";
    print FH "$_\n" foreach @lines;
    close FH;
}

#==============================================================================
# MAIN
#------------------------------------------------------------------------------
MAIN: {
    my $prog    = basename $0;
    my $opts    = getOptions();
    my $htmlDir = $opts->{htmlDir}; $htmlDir or
                                            fatal "$prog: no output directory";
                editTreeFile ($htmlDir);
               editFilesFile ($htmlDir);
    editNonComponentFileFiles($htmlDir);
    exit 0;
}
