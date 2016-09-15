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
use BDE::Util::Doxygen qw(bde2doxygen);
use Util::Message      qw(fatal error warning alert verbose message debug);
$|=1;

#==============================================================================
# PARSE OPTIONS
#------------------------------------------------------------------------------
sub usage {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print STDERR<<_USAGE_END;

Usage: $prog -h | [-d] [-v] <-f fileList > <-o doxyDir>
  --help       | -h            Display usage information (this text)
  --debug      | -d            Enable debug reporting
  --verbose    | -v            Enable verbose reporting
  --fileList   | -f <fileList> File listing input file pathnames
  --preprocess | -p <filter>   Input filter of form 'cmd [opts] <filename>'.
                                   default: none
  --doxyDir    | -o <dir>      Output directory (for Doxygen-ated files)
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
        fileList|f=s
        preprocess|p=s
        doxyDir|o=s
    ])) {
        usage(), exit 1;
    }

    usage(), exit 0 if  $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#==============================================================================
# SUPPORTING FUNCTIONS
#------------------------------------------------------------------------------
sub convertC2CppComments($)
{
    my $line = shift;
    $line =~ s|/\* |// |;
    $line =~ s| \*/$||;
    $line =~ s|^\*/$||;
    $line =~ s|^( *) \*\*|$1///|;
    $line =~ s|^( *) \*|$1//|;
    $line =~ s|^/\*|//|;
    $line =~ s| *$||;
    return $line;
}
#------------------------------------------------------------------------------
sub isZdeFile($)
{
    my $line = shift;
    return $line =~ m|/zde/|;
}

#------------------------------------------------------------------------------
sub isWrapper($$)
{
    my $linesRef = shift;
    my $fname    = shift;

    return 0 if (0 == scalar(@$linesRef));

    my $lineFirst = ${$linesRef}[0];
    my $basename  = basename($fname);
    my $pattern   = "^/\\* $basename.*\\*\/\$"; # Allows for "-*-C-*-" but does
                                                # not enforce it.

    return $lineFirst =~ m|$pattern|;
}
#------------------------------------------------------------------------------
sub readFile ($$) {
    my $fname         = shift;
    my $preprocessCmd = shift;

    fatal "$fname not regular file" if ! -f $fname;

    if ($preprocessCmd) {
        my $cmd = "$preprocessCmd" . " " . "$fname" . " |";
        open(FH, $cmd)       or fatal "!! cannot open $cmd for reading: $!";
    } else {
        open(FH, "< $fname") or fatal "!! cannot open $fname for reading: $!";
    }

    my @lines = <FH>; close FH; chomp @lines;

    if (isWrapper(\@lines, basename($fname))) {
        @lines = map { convertC2CppComments $_ } @lines;
    }

    return \@lines;
}
#------------------------------------------------------------------------------
sub writeFile($$) {
    my ($fname,$lines) = @_;

    open(FH, "> $fname") or fatal "!! cannot open $fname for writing: $!";
    print FH "$_\n" foreach @$lines;
    close(FH);
}
#------------------------------------------------------------------------------
sub processFile ($$$$) {
    my ($file,$doxydir,$suffix, $preprocessCmd)=@_;

    my $basename=basename($file);

    verbose "Processing $basename";

    my $lines = readFile($file, $preprocessCmd);
    $lines = bde2doxygen($lines,$basename);
    if ($lines) {
        $basename =~ s/\.[a-zA-Z]+$//;        # replace non-*.h extensions
        if ($doxydir) {
            writeFile("$doxydir/$basename.h".$suffix, $lines);
        } else {
            print STDOUT map { "$_\n" } @$lines;
        }
    } else {
        warn "No identifying name found in $file, skipped";
    }

    return 0;
}

#==============================================================================
# MAIN
#------------------------------------------------------------------------------
MAIN: {
    my $prog     = basename $0;
    my $opts     = getOptions();
    my $fileList = $opts->{fileList}; $fileList or
                                            fatal "$prog: no input file list";
    my $doxyDir  = $opts->{doxyDir};  $doxyDir or
                                            fatal "$prog: no output directory";

    my $preprocessCmd = $opts->{preprocess};

    unless (open(FILELIST, $fileList)) {
        fatal "$prog: cannot open for reading: $fileList: $!";
    }

    unless (-w $doxyDir) {
        fatal "$prog: cannot write to: $doxyDir: $!";
    }

    my @files = <FILELIST>;  close FILELIST; chomp @files;

    processFile($_, $doxyDir,"", $preprocessCmd) foreach sort @files;
    exit 0;
}
