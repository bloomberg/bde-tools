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
use Util::Message           qw( fatal
                                error
                                warning
                                alert
                                verbose
                                message
                                debug);
use BDE::Util::Nomenclature qw[ isPackage
                                isGroup
                                isComponent
                                isIsolatedPackage
                                getPackageGroup
                                getComponentPackage
                                getComponentGroup
                              ];

$|=1;

#==============================================================================
# PARSE OPTIONS
#------------------------------------------------------------------------------

sub usage {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print STDERR<<_USAGE_END;

Usage: $prog -h | [-d] [-v] <-f fileList> <-o doxyDir> [-r file.header ]
   --help    | -h            Display usage information (this text)
   --debug   | -d            Enable debug reporting
   --verbose | -v            Enable verbose reporting
   --fileList| -f <fileList> File listing input file pathnames
   --doxyDir | -o <doxyDir>  Output directory (for Doxygen-ated files)
                                 default: .
   --header  | -r <header>   header filename defining HTML 'quick links'
                                 default: doxydir/BDEQuicklinks.header'

Generate the standard html header for all documentation output, including
quicklinks to all included UORs.

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
        doxyDir|o=s
        header|r=s
    ])) {
        usage(), exit 1;
    }

    usage(), exit 0 if  $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # output directory
    $opts{doxydir} ||= ".";

    # quicklinks html header file
    $opts{header} ||= "BDEQuickLinks.header";

    return \%opts;
}

#==============================================================================
# HELPERS
#------------------------------------------------------------------------------
sub sortUnique($)
{
    my $listRef = shift;
    my %seen    = ();
    @$listRef   = sort
                  grep !$seen{$_}++,
                  grep defined $_,   #Why getting 'undef's?
                  @$listRef;
}
#------------------------------------------------------------------------------
sub generateHtmlPageHeader($$) {
    my $headerFile = shift;
    my   $fileList = shift;

    verbose "* Generating HTML header for quick links navigation";

    open(HEADER, "> $headerFile") || fatal "cannot create $headerFile: $!";
    print HEADER<<_HEADER_1_END;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/xhtml;charset=UTF-8"/>
<title>\$title</title>
<link href="\$relpath\$tabs.css" rel="stylesheet" type="text/css"/>
<link href="\$relpath\$search/search.css" rel="stylesheet" type="text/css"/>
<script type="text/javaScript" src="\$relpath\$search/search.js"></script>
<link href="\$relpath\$doxygen.css" rel="stylesheet" type="text/css"/>
    <style>
      div.hanging {
        padding-left: 0.75in;
        text-indent: -0.50in;
      }
      div.unhanging {
        text-indent:     0in;
      }
      a.glossary {
        font-weight: bold;
        font-style: italic;
      }
    </style>
</head>
<!--
<body onload='searchBox.OnSelectItem(0);'>
-->
<body>

_HEADER_1_END

    my @pkgList = ();
    my @grpList = ();

    for my $file (@$fileList) {
        verbose "file: $file";
        if ($file =~ m|\.h$|) {
            my $component = basename($file, ".h");
            if (!isComponent($component)) {
                warning "not a component header: skip: $file";
                next;
            }
            my $pkg = getComponentPackage($component);
            if (isIsolatedPackage($pkg)) { #Handle it as a group.
                push @grpList, $pkg;
            } else {
                my $grp = getComponentGroup($component);
                push @pkgList, $pkg;
                push @grpList, $grp;
            }
            next;

        } elsif ($file =~ m|\.txt$|) {
            my $entity = basename($file, ".txt");
            if (isPackage($entity)) {
                my $grp = getPackageGroup($entity);
                push @pkgList, $entity;
                push @grpList, $grp;
                next;

            } elsif (isGroup($entity)) {
                push @grpList, $entity;
                next;

            } else {
                warning "neither a pkg nor a grp: skip: $file";
                next;
            }

        } else {
            warning "Unexpected suffix: skip: $file";
            next;
        }
    }

    sortUnique(\@pkgList);
    sortUnique(\@grpList);

    my @headerList = @grpList > 1 ? @grpList :
                     @pkgList > 1 ? @pkgList :
                                          () ;
    if (@headerList > 0) {
        print HEADER
                  "<table border=2 cellspacing=0 cellpadding=0 align=center>\n"
                . "<tr>\n"
                . " <td valign=top align=center>\n"
                . " <p align=center><b><i>Quick Links:</i></b></p>\n"
                . " </td>\n"
                . " <td valign=top align=center>\n"
                . " <p align=center>\n";

        print HEADER
            join ' | ', map {
                verbose "link: $_";
                my $name = $_; # preserve "normal" name in a temp.
                s/_/__/g;      # doxygen turns _ into __ so mimic it
                s/\+/__P__/g;   # another doxygen transformation
                qq[<a class="qindex" href="group__${_}.html" target="_blank">$name</a>]
            } @headerList;

        print HEADER "\n"
                  .  " </td>\n"
                  .  " </tr>\n"
                  .  " </table>\n";
    }

    print HEADER "\n  </div>\n";
    close HEADER;
}

#==============================================================================
# MAIN
#------------------------------------------------------------------------------
MAIN: {
    my $prog     = basename $0;
    my $opts     = getOptions();
    my $fileList = $opts->{fileList}; $fileList or
                                            fatal "$prog: no input file list";
    my $doxyDir  = $opts->{doxyDir};  $doxyDir  or
                                            fatal "$prog: no output directory";

    unless (open(FILELIST, $fileList)) {
        error "$prog: cannot open for reading: $fileList: $!\n";
        exit 1;
    }

    my @files = <FILELIST>; close FILELIST; chomp @files;

    generateHtmlPageHeader($doxyDir . "/". $opts->{header}, \@files);
    exit 0;
}
