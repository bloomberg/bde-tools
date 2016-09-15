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

Usage: $prog -h | [-d] [-v] <-f fileList> <-o htmlDir> [-b <baseTitle>]
   --help      | -h            Display usage information (this text)
   --debug     | -d            Enable debug reporting
   --verbose   | -v            Enable verbose reporting
   --fileList  | -f <fileList> File listing input file pathnames
   --htmlDir   | -o <htmlDir>  Output directory (home of Doxygenated files)
                                   default: ./html
   --baseTitle | -b            Base HTML title
                                   default: "Bloomberg Development Environment"

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
        htmlDir|o=s
        baseTitle|b=s
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

    # base title for HTML files
    $opts{baseTitle} ||= "Bloomberg Development Environment";

    return \%opts;
}

#==============================================================================
# HELPERS: Restore '.h' Files
#------------------------------------------------------------------------------

sub outputHtmlPrologue  (*$) {
    my ($outPut, $title) = @_;

    print $outPut <<END_OF_HTML_PROLOGUE
<!doctype HTML public "-//W3C//DTD HTML 4.0 Frameset//EN">
<html>
<title>$title</title>
<html>
<pre>
END_OF_HTML_PROLOGUE
}

sub outputHtmlEpilogue (*) {
    my ($outPut) = @_;
    print $outPut <<'END_OF_HTML_EPILOGUE'
</pre>
</body>
</html>
END_OF_HTML_EPILOGUE
}

sub convertAsciiToHtmlEntities ($) {
    my ($convertedLine) = @_;
    $convertedLine =~ s/\&/\&amp\;/g;
    $convertedLine =~ s/\"/\&quot;/g;
    $convertedLine =~ s/</\&lt;/g;
    $convertedLine =~ s/>/\&gt;/g;
    $convertedLine =~ s/\'/\&#39;/g;
    return $convertedLine;
}

sub asciiToMinimalHtml (**$) {
    my ($inPut, $outPut, $title) = @_;
    my $count = 0;
    outputHtmlPrologue($outPut, $title);
    while (<$inPut>) {
        print $outPut convertAsciiToHtmlEntities($_);
        ++$count;
    }
    outputHtmlEpilogue($outPut);
    return $count;
}

sub restoreHfiles ($$$) {
    my ($htmlDir, $fileList, $baseTitle) = @_;

    verbose "restore '.h' and '.txt' source files in: $htmlDir";

    unless (open(FILELIST, $fileList)) {
        my $prog = basename $0;
        warning "$prog: cannot open for reading: $$fileList: $!\n";
        exit 1;
    }
    my @files  = <FILELIST>; close FILELIST; chomp @files;

    my $fileCount = 0;

    for my $file (@files) {
        next if $file !~ m%\.(h|txt)$%;

        my $originalHeader = $file;
        unless (open(INPUT, $originalHeader)) {
            warning "cannot open for reading: $originalHeader: $!";
            next;
        }

        my $outputFile = basename $file;
        my $original   = $outputFile;
        $outputFile =~ s/\.txt$/\.h/;  # no-op if already '.h'.
        $outputFile =~ s/_/__/g;
        $outputFile =~ s/\+/_09/g;
        $outputFile =~ s/\.h$/_8h_source.html/;
        $outputFile = $htmlDir . "/" . $outputFile;

        unless (open(OUTPUT, ">".$outputFile))  {
            warning "cannot open for writing: $outputFile: $!";
            close INPUT;
            next;
        }

        my $lineCount = asciiToMinimalHtml(\*INPUT, \*OUTPUT, $baseTitle);
        close  INPUT;
        close OUTPUT;
        ++$fileCount;
    }
    verbose "restored file count: $fileCount";
    return $fileCount;
}

#==============================================================================
# HELPERS: Title Adjustments
#------------------------------------------------------------------------------
sub levelOfAggregation($)
{
    my $uor = shift;

    return $uor =~ m|^\w_\w+_\w+| ? "Component"     :
           $uor =~ m|^\w_\w+|     ? "Package"       :
           $uor =~ m|^\w+_\w+|    ? "Component"     :
           $uor =~ m|^\w{3}$|     ? "Package Group" :
           $uor =~ m|^\w{3}\w+$|  ? "Package"       :
                                                 "" ;
}

sub markupToAscii($)
{
    my $str = shift;
    $str =~ s|__|_|g;
    $str =~ s|_1|:|g;
    return $str;
}

sub classMembersTitle($)
{
    my $file = shift;
    $file =~ m|^class.*-members$| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^class||;
    $title =~ s|-members$||;
    $title =  markupToAscii($title);
    $title = "Class " . $title . " Members";
    return $title;
}

sub classTitle($)
{
    my $file = shift;
    $file =~ m|^class.*| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^class||;
    $title =  markupToAscii($title);
    $title = "Class " . $title;
    return $title;
}

sub groupTitle($)
{
    my $file = shift;
    $file =~ m|^group.*| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^group__||;
    $title =  markupToAscii($title);
    $title =  $title . " " .  levelOfAggregation($title);
    return $title;
}

sub headerTitle($)
{
    my $file = shift;
    $file =~ m|_8h_source$| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^class||;
    $title =~ s|_8h_source$|.h|;
    $title =  markupToAscii($title);
    $title =  $title . " Source";
    return $title;
}

sub fileReferenceTitle($)
{
    my $file = shift;
    $file =~ m|_8h$| or die "bad pattern match on: " . $file;
    my $title = $file;

    $title =~ s|^class||;
    $title =~ s|_8h$|.h|;
    $title =  markupToAscii($title);
    $title =  $title . " Reference";
    return $title;
}

sub structMembersTitle($)
{
    my $file = shift;
    $file =~ m|^struct.*-members$| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^struct||;
    $title =~ s|-members$||;
    $title =  markupToAscii($title);
    $title = "Struct " . $title . " Members";
    return $title;
}

sub structTitle($)
{
    my $file = shift;
    $file =~ m|^struct.*| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^struct||;
    $title =  markupToAscii($title);
    $title = "Struct " . $title;
    return $title;
}

sub namespaceTitle($)
{
    my $file = shift;
    $file =~ m|^namespace.*| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^namespace||;
    $title =  markupToAscii($title);
    $title = "Namespace " . $title;
    return $title;
}

sub indexTitle($)
{
    my $file = shift;
    $file =~ m|^index.*| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^index_||;
    $title =  markupToAscii($title);
    $title =  "Index of ".  $title . " " . levelOfAggregation($title);
    return $title;
}

sub unionMembersTitle($)
{
    my $file = shift;
    $file =~ m|^union.*-members$| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^struct||;
    $title =~ s|-members$||;
    $title =  markupToAscii($title);
    $title = "Union " . $title . " Members";
    return $title;
}

sub unionTitle($)
{
    my $file = shift;
    $file =~ m|^union.*| or die "bad pattern match on: " . $file;

    my $title = $file;
    $title =~ s|^union||;
    $title =  markupToAscii($title);
    $title = "Union " . $title;
    return $title;
}

sub filenameToTitle($)
{
    my $file = shift;

    $file =~ '\.html$' or die "bad filename: " . $file;
    $file =~ s|\.html$||;

    return
        $file =~ m|^class.*-members$|  ?  classMembersTitle($file) :
        $file =~ m|^class.*|           ?         classTitle($file) :
        $file =~ m|^group.*|           ?         groupTitle($file) :
        $file =~ m|_8h_source$|        ?        headerTitle($file) :
        $file =~ m|_8h$|               ? fileReferenceTitle($file) :
        $file =~ m|^struct.*-members$| ? structMembersTitle($file) :
        $file =~ m|^struct.*|          ?        structTitle($file) :
        $file =~ m|^namespace.*|       ?     namespaceTitle($file) :
        $file =~ m|^index.*|           ?         indexTitle($file) :
        $file =~ m|^union.*-members$|  ?  unionMembersTitle($file) :
        $file =~ m|^union.*|           ?         unionTitle($file) :
                                                                "" ;

}

sub editHtmlFiles($$)
{
    my $htmlDir   = shift;
    my $baseTitle = shift;

    verbose "editing HMTL files in $htmlDir";

    opendir(DIR, $htmlDir) or fatal "cannot open directory: $htmlDir: $!";

    my $fileCount = 0;

    while (my $file = readdir(DIR)) {
        if ($file !~ m|\.html$|) {
            verbose "SKIP file:$file";
            next;
        }
        verbose "PROC file:$file";

        open(FH, "< $htmlDir/$file") or fatal "cannot open $file: $!";
        my $content = join '', <FH>;  #input entire file
        close(FH) or fatal "cannot close: $file: $!";

        open(FH, "> $htmlDir/$file") or fatal "cannot open $file: $!";

        #optionally customize title of each page
        if ($baseTitle) {
            my $title =  filenameToTitle(basename($file));
            $title    =  $title ? "$baseTitle: $title" : "$baseTitle";
            $content  =~ s{<title>.*</title>}{<title>$title</title>}sg
        }

        $content =~
            s{<a class="qindex[^>]+>(Main|Alpha|Namespace).*?</a>\s+\|}{}sg;

        # Convert "module" (not a BDE term) to "component"
        $content =~ s{\bModule(s?)\b}{Component$1}sg;
        $content =~ s{\bmodule(s?)\b}{component$1}sg;
        $content =~ s{\bmain\.html\b}{components.html}sg;

        print FH $content;
        close(FH) or fatal "cannot close $file: $!";
        ++$fileCount;
    }
    closedir(DIR) or fatal "cannot closedir: $!";

    return $fileCount;
}

#==============================================================================
# MAIN
#------------------------------------------------------------------------------
MAIN: {
    my $prog     = basename $0;
    my $opts     = getOptions();
    my $fileList = $opts->{fileList}; $fileList or
                                            fatal "$prog: no input file list";
    my $htmlDir  = $opts->{htmlDir};  $htmlDir  or
                                            fatal "$prog: no output directory";

    restoreHfiles($htmlDir, $fileList, $opts->{baseTitle});
    exit 0;
}
