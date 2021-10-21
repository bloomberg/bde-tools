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
use BDE::Util::Nomenclature qw[ isCompliant
                                isNonCompliant
                                isSubordinateComponent
                                isComponent
                                getComponentPackage
                              ];
$|=1;

#==============================================================================
# PARSE OPTIONS
#------------------------------------------------------------------------------
sub usage {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print STDERR<<_USAGE_END;

Usage: $prog -h | [-d] [-v] [-o htmlDir] [-f filesFile] [-m modulesFile] \
                                                             [-c componentFile]

   --help           | -h           Display usage information (this text)
   --debug          | -d           Enable debug reporting
   --verbose        | -v           Enable verbose reporting
   --buttonTable    | -b           Provide buttons to expand/collapse table
   --htmlDir        | -o <htmlDir> Output directory (home of Doxygenated files)
                                   default: 'html'
   --filesInfo      | -f <filesFile>
                                   File information file (read)
                                   default: 'files.html'
   --modulesInfo    | -m <modulesFile>
                                   Module information file (read)
                                   default: 'modules.html'
   --componentsInfo | -c <componentsFile>
                                   Component information file (written)
                                   default: 'components.html'

Generate 'components.html', containing a collapsible hierarchical listing of
all components in the library being documented.

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
        buttonTable|b+
        htmlDir|o=s
        filesInfo|f=s
        modulesInfo|m=s
        componentsInfo|c=s
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

    # input and output files
         $opts{filesInfo} ||=      "files.html";
       $opts{modulesInfo} ||=    "modules.html";
    $opts{componentsInfo} ||= "components.html";

    return \%opts;
}

#------------------------------------------------------------------------------
# Predefined constants
#------------------------------------------------------------------------------

use constant {
    STATE_Normal   => 0,
    STATE_InList   => 1,
    STATE_Isolated => 2
};

use constant {
    BG_NONE  => "",
    BG_EMPTY => "#BEBEBE",
    BG_GRP   => "#CAC589",
    BG_PKG   => "#DAD6AC",
    BG_CMP   => ""
};

use constant {
    BUTTON_TEXT_EXPANDED   => "-",
    BUTTON_TEXT_COLLAPSED  => "+",
    BUTTON_TEXT_EMPTY      => "."
};

#==============================================================================
# HELPERS: Title Adjustments
#------------------------------------------------------------------------------

sub hrefOfLine($) {
    my $line = shift;

    $line = m/(.*href=")([^"]*)(".*)/;
    return $2;
}

sub getMnemonic($$) {
    my $htmlDir  = shift;
    my $filename = shift;

    my $path = $htmlDir . "/" . $filename;
    open(FH, "< $path") or fatal "!! cannot open $path for reading: $!";
    my @lines = <FH>; close FH; chomp @lines;

    my $pattern = 'MNEMONIC:';
    my @matches = grep /$pattern/, @lines;

    my $numMatches = scalar @matches; 

    if (2 == $numMatches) {
        my $ret = $matches[0];
        $ret =~ s|.*MNEMONIC:||;
        $ret =~ s|</a>.*||;
        $ret =~ s|^ ||;
        $ret =~ s| *\(\w+\) *$||;
    
        return $ret;
    } elsif (0 == $numMatches) {
        return "";
    } else {
        fatal "!! $path: unexpected MNEMONIC match count: $numMatches";
    }
}

sub isDeprecated($$) {
    my $htmlDir  = shift;
    my $filename = shift;

    my $path = $htmlDir . "/" . $filename;
    open(FH, "< $path") or fatal "!! cannot open $path for reading: $!";
    my @lines = <FH>; close FH; chomp @lines;

    my $pattern = "<dl class=\"deprecated\"><dt><b>"
                . "<a class=\"el\" href=\"deprecated.html#_deprecated.*\">"
                . "Deprecated:</a>";

    my @matches = grep /$pattern/, @lines;

    return scalar @matches;
}

sub isPrivateComponent($) {
    my $component = shift;
    isComponent $component or die "not component: $component";

    if ($component =~ s|^bslfwd_||) {
        my $ret = 1 if $component =~ m|buildtarget$|;
        $ret = $ret ? 1 : 0;
        return $ret;                                                   # RETURN
    }

   # return isSubordinateComponent $component; Workaround per DRQS 42208281.

    my $componentPackage =  getComponentPackage($component);
    my $componentStem    =  $component;
       $componentStem    =~ s/^$componentPackage\_//;

    return (scalar split /_/, $componentStem) > 1;
}

sub isEndOfList($) #same for each list
{
    my $line = shift;
    return $line =~ m|^</ul>$|;
}

sub isEndOfListItem($) #same for each list
{
    my $line = shift;
    return $line =~ m|^</li>$|;
}

sub isEndOfDiv($)
{
    my $line = shift;
    return $line =~ m|^</div>$|;
}

sub isEndOfHeaderSection($) {
    my $line = shift;
    return $line =~ m|</head>|i;
}

sub buttonTable($$)
{
    my $buttonTableId = shift;
    my       $tableId = shift;

    return <<"_EO_BUTTON_TABLE_";
 <table id='$buttonTableId' border=1>
  <col width='050'>
  <col width='050'>
  <col width='050'>
  <tbody>
  <tr id="buttonRow">
   <td id="cagButton">
    <button class="outButtonTable"
          onClick="bdedox_cagButtonOnClick    (this, '$tableId')"
      onMouseOver="bdedox_cagButtonOnMouseOver(this)"
       onMouseOut="bdedox_cagButtonOnMouseOut (this)"
    >Collapse All Groups
    </button>
   </td>
   <td id="eapButton">
    <button class="outButtonTable"
          onClick="bdedox_eapButtonOnClick    (this, '$tableId')"
      onMouseOver="bdedox_eapButtonOnMouseOver(this)"
       onMouseOut="bdedox_eapButtonOnMouseOut (this)"
    >Expand All Packages
    </button>
   </td>
  </tr>
  </tbody>
 </table>
_EO_BUTTON_TABLE_

}

sub scriptSection()
{
    return <<'_EO_SCRIPT_';
    <script>

var CELL_IDX_GRP_BUTTON = 0;
var CELL_IDX_GRP_NAME   = 1;
var CELL_IDX_PKG_BUTTON = 2;
var CELL_IDX_PKG_NAME   = 3;
var CELL_IDX_CMP_NAME   = 4;
var CELL_IDX_PURPOSE    = 5;

function bdedox_isGrpRow(rowObj)
{
    var grpButtonCellObj = rowObj.cells[CELL_IDX_GRP_BUTTON];
    var              obj = grpButtonCellObj.childNodes[0];
    return bdedox_isButtonObj(obj);
}

function bdedox_isPkgRow(rowObj)
{
    var pkgButtonCellObj = rowObj.cells[CELL_IDX_PKG_BUTTON];
    var              obj = pkgButtonCellObj.childNodes[0];
    return bdedox_isButtonObj(obj);
}

function bdedox_isCmpRow(rowObj)
{
    return !bdedox_isPkgRow(rowObj) && !bdedox_isGrpRow(rowObj)
}

function bdedox_showRow(rowObj)
{
    rowObj.style.display = 'table-row';
}

function bdedox_hideRow(rowObj)
{
    rowObj.style.display = 'none';
}

function bdedox_setButtonToExpanded(buttonObj)
{
    buttonObj.innerHTML = '-';
}

function bdedox_setButtonToCollapsed(buttonObj)
{
    buttonObj.innerHTML = '+';
}

function bdedox_buttonShowsExpanded(buttonObj)
{
    return "-" == buttonObj.innerHTML;
}

function bdedox_buttonShowsCollapsed(buttonObj)
{
    return "+" == buttonObj.innerHTML;
}

function bdedox_buttonShowsEmpty(buttonObj)
{
    return "." == buttonObj.innerHTML;
}

function bdedox_isEmptyNameCell(cellObj)
{
    return '&nbsp;' == cellObj.innerHTML;
}

function bdedox_isRowWithExpandedGroupButton(rowObj)
{
    var grpButtonCellObj = rowObj.cells[CELL_IDX_GRP_BUTTON];
    var   grpNameCellObj = rowObj.cells[CELL_IDX_GRP_NAME];
    var     grpButtonObj = grpButtonCellObj.childNodes[0];

    return bdedox_buttonShowsExpanded(grpButtonObj)
}

function bdedox_isRowObj(obj)
{
    return "TR".toLowerCase() == obj.nodeName.toLowerCase();
}

function bdedox_isButtonObj(obj)
{
    return "BUTTON".toLowerCase() == obj.nodeName.toLowerCase();
}


function bdedox_getPrevRow(rowObj)
{
    if (null == rowObj) {
        return null;                                                  // RETURN
    }

    var candidateRow;
    for (candidateRow  = rowObj.previousSibling;
         candidateRow != null;
         candidateRow  = candidateRow.previousSibling)
    {
         if (bdedox_isRowObj(candidateRow)) {
             break;
         }
    }
    return candidateRow;
}

function bdedox_getNextRow(rowObj)
{
    if (null == rowObj) {
        return null;                                                  // RETURN
    }

    var candidateRow;
    for (candidateRow  = rowObj.nextSibling;
         candidateRow != null;
         candidateRow  = candidateRow.nextSibling)
    {
         if (bdedox_isRowObj(candidateRow)) {
             break;
         }
    }
    return candidateRow;
}

function bdedox_cagButtonOnClick(cagButtonObj, tableId)
    // Collapse all group rows (thereby hiding all component and package rows)
    // in the table having the specified 'tableId' when the specified
    // 'cagButtonObj' is clicked.  Clicking the button when the table is
    // already collapsed has no effect.
{
    var tableObj          = document.getElementById(tableId);
    var rowObjsOfInterest = new Array();

    for (var rowObj  = tableObj.rows[1];
             rowObj != null;
             rowObj  = bdedox_getNextRow(rowObj))
    {
        if (bdedox_isRowWithExpandedGroupButton(rowObj)) {
            rowObjsOfInterest.push(rowObj);
        }
    }

    while (0 < rowObjsOfInterest.length) {
        var           rowObj = rowObjsOfInterest.pop();
        var grpButtonCellObj = rowObj.cells[CELL_IDX_GRP_BUTTON];
        var   grpNameCellObj = rowObj.cells[CELL_IDX_GRP_NAME];
        var     grpButtonObj = grpButtonCellObj.childNodes[0];

        bdedox_grpButtonOnClick(grpButtonObj);
    }
}

function bdedox_eapButtonOnClick(eapButtonObj, tableId)
    // Display all component rows (by expanding all group group and package
    // rows) in the table having the specified 'tableId' when the specified
    // 'eapButtonObj' is clicked.  Clicking the button when the table is
    // already expanded has no effect.
{
    var tableObj = document.getElementById(tableId);

    for (var rowObj  = tableObj.rows[1];
             rowObj != null;
             rowObj  = bdedox_getNextRow(rowObj))
    {
        var grpButtonColumnCellObj = rowObj.cells[CELL_IDX_GRP_BUTTON];
        var   grpNameColumnCellObj = rowObj.cells[CELL_IDX_GRP_NAME];
        var                    obj = grpButtonColumnCellObj.childNodes[0];

        if (bdedox_isButtonObj(obj)) {
            if (bdedox_buttonShowsCollapsed(obj)) {
                bdedox_grpButtonOnClick(obj)
            }
        } else {
            var pkgButtonColumnCellObj = rowObj.cells[CELL_IDX_PKG_BUTTON];
            var                    obj = pkgButtonColumnCellObj.childNodes[0];

            if (bdedox_isButtonObj(obj)) {
                if (bdedox_buttonShowsCollapsed(obj)) {
                    rowObj = bdedox_pkgButtonOnClick(obj);
                }
            }
         }
    }
}

function bdedox_grpButtonOnClick(grpButtonObj)
    // Expand (collapse) the package rows following the row containing the
    // specified 'grpButtonObj' if the current state of that object shows that
    // it is collapsed (expanded).  Return the highest indexed row object
    // expanded (collapsed) or 'null'.  When a group is expanded (collapsed)
    // the rows are made visible (invisible) from top-to-bottom
    // (bottom-to-top).
{
    var  cellObj = grpButtonObj.parentNode;
    var   rowObj =      cellObj.parentNode;
    var tbodyObj =       rowObj.parentNode;
    var tableObj =     tbodyObj.parentNode;

    var cellIdxOfClickedButton = cellObj.cellIndex;
    var  rowIdxOfClickedButton =  rowObj.rowIndex;

    var returnedRowObj = null;
    var amCollapsing   = bdedox_buttonShowsExpanded(grpButtonObj);

    if (amCollapsing) {
        bdedox_setButtonToCollapsed(grpButtonObj);

        var rowObjsOfInterest = new Array();

        for (var rowObj  = tableObj.rows[rowIdxOfClickedButton + 1];
                 rowObj != null;
                 rowObj  = bdedox_getNextRow(rowObj))
        {
            if (bdedox_isGrpRow(rowObj)) {
                break;
            }

            if (!bdedox_isPkgRow(rowObj)) {
                continue;
            }

            rowObjsOfInterest.push(rowObj);
            returnedRowObj = rowObj;
        }

        while (0 < rowObjsOfInterest.length) {
            var           rowObj = rowObjsOfInterest.pop();
            var pkgButtonCellObj = rowObj.cells[cellIdxOfClickedButton + 2]
            var     pkgButtonObj = pkgButtonCellObj.childNodes[0];

            if (bdedox_buttonShowsExpanded(pkgButtonObj)) {
                bdedox_pkgButtonOnClick(pkgButtonObj);
            }
            bdedox_hideRow(rowObj);
        }
    } else {
        bdedox_setButtonToExpanded(grpButtonObj);

        for (var rowObj  = tableObj.rows[rowIdxOfClickedButton + 1];
                 rowObj != null;
                 rowObj  = bdedox_getNextRow(rowObj))
        {
            if (bdedox_isGrpRow(rowObj)) {
                break;
            }

            if (bdedox_isPkgRow(rowObj)) {
                bdedox_showRow(rowObj);
            }
            returnedRowObj = rowObj;
        }
    }

    return returnedRowObj;
}

function bdedox_pkgButtonOnClick(pkgButtonObj)
    // Expand (collapse) the component rows following the row containing the
    // specified 'pkgButtonObj' if the current state of that object shows that
    // it is collapsed (expanded).  Return the highest indexed row object
    // expanded (collapsed) or 'null'.  When a package is expanded (collapsed)
    // the rows are made visible (invisible) from top-to-bottom
    // (bottom-to-top).
{
    var  cellObj = pkgButtonObj.parentNode;
    var   rowObj =      cellObj.parentNode;
    var tbodyObj =       rowObj.parentNode;
    var tableObj =     tbodyObj.parentNode;

    var cellIdxOfClickedButton = cellObj.cellIndex;
    var  rowIdxOfClickedButton =  rowObj.rowIndex;

    if (bdedox_buttonShowsEmpty(pkgButtonObj)) {
        return null;
    }

    var returnedRowObj = null;
    var amCollapsing   = bdedox_buttonShowsExpanded(pkgButtonObj);

    if (amCollapsing) {
        bdedox_setButtonToCollapsed(pkgButtonObj);

        // Identify range of rows of interest.
        for (var rowObj  = tableObj.rows[rowIdxOfClickedButton + 1];
                 rowObj != null;
                 rowObj  = bdedox_getNextRow(rowObj))
        {
            if (!bdedox_isCmpRow(rowObj)) {
                break;
            }

            returnedRowObj = rowObj;
        }

        // Change rows of interest, from bottom-to-top.
        var initialRowObj = tableObj.rows[rowIdxOfClickedButton + 0];
        for (var rowObj  = returnedRowObj;
                 rowObj !=  initialRowObj;
                 rowObj  = bdedox_getPrevRow(rowObj))
        {
            bdedox_hideRow(rowObj);
        }

    } else {
        bdedox_setButtonToExpanded(pkgButtonObj);

        for (var rowObj  = tableObj.rows[rowIdxOfClickedButton + 1];
                 rowObj != null;
                 rowObj  = bdedox_getNextRow(rowObj))
        {
              if (!bdedox_isCmpRow(rowObj)) {
                  break;
              }

              bdedox_showRow(rowObj);
              returnedRowObj = rowObj;
        }
    }

    return returnedRowObj;
}

function bdedox_buttonOnMouseOver(object)
{
    object.className='over';
}

function bdedox_buttonOnMouseOut(object)
{
    object.className='out';
}

function bdedox_cagButtonOnMouseOut(object)
{
    object.className='outButtonTable';
}

function bdedox_cagButtonOnMouseOver(object)
{
    object.className='overButtonTable';
}

function bdedox_eapButtonOnMouseOut(object)
{
    object.className='outButtonTable';
}

function bdedox_eapButtonOnMouseOver(object)
{
    object.className='overButtonTable';
}

function bdedox_pageLoaded(tableInitiallyCollapsed)
{
    if (tableInitiallyCollapsed) {
        var cagButtonObj = document.getElementById("cagButton");
        bdedox_cagButtonOnClick(cagButtonObj, "myTable");
    }
}
    </script>
_EO_SCRIPT_
}

sub styleSection()
{
    return <<'_EO_STYLE_';
   <style type="text/css">
    BUTTON.over {
        background-color:rgb(210,187,46);
        padding-top: 2px;
        padding-bottom:2px;
        font-family:"Courier New";
        vertical-alignment: middle;
        height: 25px;
    }
    BUTTON.out  {
        background-color:rgb(149,179,215);
        padding-top: 2px;
        padding-bottom:2px;
        font-family:"Courier New";
        vertical-alignment: middle;
        height: 25px;
    }

    <!-- match grp row color -->
    BUTTON.overButtonTable  {
        background-color:#DAD6AC; padding-top: 2px; padding-bottom:2px;
    }
    <!-- match pkg row color -->
    BUTTON.outButtonTable  {
        background-color:#CAC589; padding-top: 2px; padding-bottom:2px;
    }

   th.cmpTableHeader {
    font-size:  medium;
    text-align: left;
    background-color: #EBEFF6;
    font-weight: bold;
    border: 1px solid #C4CFE5;
    margin: 2px 0px 2px 0;
    padding: 2px 10px;
   }

   </style>
_EO_STYLE_
}

sub tableHeader()
{
    return <<'_EO_TABLE_HEADER_';
<tr>
<th class="cmpTableHeader">&nbsp</th>              <!-- grp button -->
<th class="cmpTableHeader">Group</th>              <!-- grp name   -->
<th class="cmpTableHeader">&nbsp</th>              <!-- pkg button -->
<th class="cmpTableHeader">Package</th>            <!-- pkg name   -->
<th class="cmpTableHeader">Mnemonic/Component</th> <!-- cmp name   -->
<th class="cmpTableHeader">Purpose</th>            <!-- purpose    -->
</tr>

_EO_TABLE_HEADER_
}

sub syntheticGroupRowForIsolatedPackages()
{
    # Note: The 'indexkey' class renders normal text in bold, normally unseen
    # since the text is futther rendered as links.  Override with '<span>' to
    # avoid creating a new style class for just two fields.

    my $grp     = '<span style="font-weight: normal;">'
                . 'None'
                . '</span>' ;
    my $purpose = '<span style="font-weight: normal;">'
                . 'Isolated (Stand-Alone) Packages'
                . '</span>';

    return startTableRowShow()
         . grpButtonCell(BUTTON_TEXT_COLLAPSED, BG_GRP)             #grp button
         . textCell($grp, BG_GRP)                                   #grp name
         . emptyCell(BG_GRP)                                        #grp button
         . emptyCell(BG_GRP)                                        #pkg name
         . emptyCell(BG_GRP)                                        #cmp name
         . textCell($purpose, BG_GRP)                               #purpose
         . endTableRow()
         . "\n";
}

sub isStartOfTopList($)
{
    my $line = shift;
    return undef if $line !~ m|^Here is a list of all components:<ul>$|;
    $line =~ s|list|table|;
    $line =~ s|components|package groups (a.k.a., groups), packages, and components|;
    $line =~ s|^|<p>|;
    $line =~ s|<ul>$|</p>|;
    return $line;
}

sub isMatchLinkAndNameHdrs($$)
{
    my $link = shift;
    my $name = shift;
    $link =~ s/__P__/+/g;
    return $link eq $name ? $name : undef;
}

sub isMatchLinkAndName($$)
{
    my $link = shift;
    my $name = shift;
    $link =~ s/__/_/g;
    return $link eq $name ? $name : undef;
}

sub isStartOfIsolatedPackage($)
{
    my $line = shift;
    my $ret  = $line =~
m|<li><a class="el" href="group__(\w+).html">Package \(Isolated\) (\w+)</a><ul>|;
    return $ret if not $ret;
    return isMatchLinkAndName($1, $2);
}

sub isStartOfPackageGroup($)
{
    my $line = shift;
    my $ret  = $line =~
  m|^<li><a class="el" href="group__(\w+)\.html">Package Group (\w+)</a><ul>$|;
    return $ret if not $ret;
    return isMatchLinkAndName($1, $2);
}

sub isStartOfPackage($)
{
    my $line = shift;

    # Is it an ill-formed BAS package group header?
    my $ret  = $line =~
    m|^<li><a class="el" href="group__([\w+]+)\.html">(\w+)</a><ul>$|;
    if ($ret) {
        my $link = $1;
        my $name = $2; $name = lc $name;
        if (isMatchLinkAndName($link, $name)) {
            return $name;
        }
    }

    # Special handling of '+' in two non-conforming 'bsl' packages:
    #     'bsl+bslhdrs' and 'bsl+stdhdrs'.
    $ret = $line =~
        m!^<li><a class="el" href="group__bsl__P__(bsl|std)hdrs\.html">Package bsl\+(bsl|std)hdrs</a></li>$!;
    if ($ret) {
        my $link = "bsl__P__" . $1 . "hdrs";
        my $name = "bsl+"     . $2 . "hdrs";
        return isMatchLinkAndNameHdrs($link, $name);
    }

    $ret = $line =~
        m|^<li><a class="el" href="group__(\w+)\.html">Package (\w+)</a><ul>$|;

    my $link = $1;
    my $name = $2;

    return $ret if not $ret;
    return isMatchLinkAndName($link, $name);
}

sub isComponentEntry($)
{
    my $line = shift;
    my $ret  = $line =~
    m|<li><a class="el" href="group__(\w+)\.html">Component (\w+)</a></li>|;
    return $ret if not $ret;
    return isMatchLinkAndName($1, $2);
}

#------------------------------------------------------------------------------
{
    my %map = ();

    sub initFilesInfoMap($)
    {
        my $filesInfo = shift;
        open(FH, "< $filesInfo") or
                                fatal "Cannot open $filesInfo for reading: $!";
        close FH;

        my $cmd = << 'END';
sed -n \
'/<table>/,/<\/table>/{
/^  <tr>/{
    s/ <a.*>\[code\]<\/a>//
    s/_8h\.html"/.html"/
    s/href="bsl_09/href="bsl__P__/
    s/href="/&group__/
    s/\.h<\/a>/<\/a>/
    h
    s/<\/a>.*//
    s/^.*>//
    s/$/|/
    G
    s/\n//
    s/  <tr>//
    s/<\/tr>$//
    s/ <\/td>$/<\/td>/
    s/href="[^"]*"/& target="_blank"/
    p
}
}'
END
         chomp $cmd;
         $cmd .= " $filesInfo |";

         open(FH, $cmd) or fatal "Cannot open \"$cmd\" for reading: $!";
         my @lines = <FH>; close FH; chomp @lines;

         for my $line (@lines) {
             my ($component, $tableEntry, $residual) = split(/\|/, $line);
             !defined($residual) || fatal "initMap: bad format: $line";
             $map{$component} = $tableEntry;
         }
    }

    sub getTableEntry($)
    {
        my $entity = shift;
        return $map{$entity};
    }

    sub setCellBackgroundColor($$)
    {
        my $tag   = shift;
        my $color = shift;
        $tag =~ s|>| style=\"background-color:$color;\">|;
        return $tag;
    }

    sub markNameDeprecated($) {
        my $cell = shift;

        my $startOfSpan = '<span style="color:gray;font-weight:normal;">';
        my   $endOfSpan = '</span>';

        if ($cell !~ m|<a.*">$startOfSpan|) {
            $cell =~ s|(<a.*">)|$1$startOfSpan|;
        }

        if ($cell !~ m|$endOfSpan</a></td>|) {
            $cell =~ s|(<\/a><\/td>)|$endOfSpan$1|;
        }

        return $cell;
    }

    sub getEntityNameCell($$$)
    {
        my $entity       = shift;
        my $color        = shift;
        my $isDeprecated = shift;

        my $entry  = getTableEntry($entity);
        return undef if not defined $entry;
        $entry =~ m|(.*<\/td>)(<td .*)|;
        my $cell = $1;

        if ($isDeprecated) {
            $cell = markNameDeprecated($cell);
        }

        if ($color) {
            $cell = setCellBackgroundColor($cell, $color);
        }
        return $cell;
    }

    sub markComponentNamePrivate($) {
        my $cell = shift;
        
        return markNameDeprecated $cell;
    }

    sub getComponentNameCell($$$) {
        my $component            = shift;
        my $deprecatedFlag       = shift;
        my $privateComponentFlag = shift;

        my $cell = getEntityNameCell($component, BG_CMP, $deprecatedFlag);

        if ($privateComponentFlag) {
            $cell = markComponentNamePrivate($cell);
        }

        return $cell;
    }

    sub makePurposeGray($) {
        my $cell = shift;

        my $startOfTableEntry = '<td class="indexvalue">';
        my   $endOfTableEntry = '</td>';

        $cell =~ m|^$startOfTableEntry| or
               fatal "makePurposeGray: $cell: has no start-of-table-entry tag";
        $cell =~ m|$endOfTableEntry$| or
               fatal "makePurposeGray: $cell: has no   end-of-table-entry tag";


        my $startOfSpan = '<span style="color:gray;">';
        my   $endOfSpan = '</span>';

        $cell =~ s|$startOfTableEntry|$startOfTableEntry$startOfSpan|;
        $cell =~ s|$endOfTableEntry|$endOfSpan$endOfTableEntry|;
 
        return $cell;
    }

    sub markPurposeDeprecated($) {
        my $cell = shift;
        $cell =~ s/\[DEPRECATED\] //;  #old-style markup
        $cell =~ s/(<td class="indexvalue">)/$1DEPRECATED: /;
        $cell =~ s/(DEPRECATED:)/<strong>$1<\/strong>/;
        $cell = makePurposeGray  $cell;
        return $cell;
    }

    sub getEntityPurposeCell($$$) {
        my $entity       = shift;
        my $color        = shift;
        my $isDeprecated = shift;

        my $entry  = getTableEntry($entity);
        return undef if not defined $entry;

        $entry =~ m|(.*<\/td>)(<td .*)|;
        my $cell = $2;

        if ($isDeprecated) {
            $cell = markPurposeDeprecated($cell);
        }

        if ($color) {
            $cell = setCellBackgroundColor($cell, $color);
        }
        return $cell;
    }


    sub addPrivatePrefix($) {
        my $cell = shift;
        if ($cell =~ m|<strong>DEPRECATED:</strong>|) {
            $cell =~
          s|<strong>DEPRECATED:</strong>|<strong>DEPRECATED/PRIVATE:</strong>|;
        } else {
          $cell =~ s|(<td class="indexvalue">)|$1<strong>PRIVATE:</strong> |;
        }
        return $cell;
    }

    sub markComponentPurposePrivate($) {
        my $cell = shift;

        $cell = addPrivatePrefix $cell;
        $cell = makePurposeGray  $cell;
        return $cell;
    }

    sub getComponentPurposeCell($$$) {
        my $component            = shift;
        my $deprecatedFlag       = shift;
        my $privateComponentFlag = shift;

        my $cell = getEntityPurposeCell($component, BG_CMP, $deprecatedFlag);

        if ($privateComponentFlag) {
            $cell = markComponentPurposePrivate($cell);
        }

        return $cell;
    }

    sub emptyCell($)
    {
        my $color = shift;
        my $cell = "<td>&nbsp;</td>";
        #my $cell = "<td class=\"indexkey\">&nbsp;</td>";
        if ($color) {
            $cell = setCellBackgroundColor($cell, $color);
        }
        return $cell;
    }

    sub markMnemonicCellDeprecated($) {
        my $cell = shift;

        $cell =~ m|style=\"[^\"]*">| or fatal "cell has no style: $cell";
        $cell =~ s|(style=\")|$1color:gray;|;
        return $cell;
    }

    sub getMnemonicCell($$$) {
        my $mnemonic       = shift;
        my $color          = shift;
        my $deprecatedFlag = shift;

        if ("" eq $mnemonic) {
            return emptyCell($color);                                  # RETURN
        }

        # Override the column attribute
        my $startOfSpan = '<span style="font-weight:normal;">';
        my   $endOfSpan = '</span>';

        $mnemonic = $startOfSpan
                  . $mnemonic
                  . $endOfSpan;

        my $cell = textCell($mnemonic, $color);

        if ($deprecatedFlag) {
            $cell = markMnemonicCellDeprecated($cell);
        }
        return $cell;
    }

    sub defaultCell($$)
    {
        my $name  = shift;
        my $color = shift;
        my $cell  = emptyCell($color);
        $cell =~ s/&nbsp;/&nbsp;$name/;
        return $cell;
    }

    sub tbdCell($)
    {
        my $color = shift;
        return defaultCell("TBD", $color);
    }

    sub printTableEntries()
    {
        foreach my $key (sort keys %map) {
            printf "%s:|%s|\n", $key, $map{$key};

        }
    }
}


#------------------------------------------------------------------------------

sub startTableRowShow()
{
    return '<tr style="display: table-row;">';
}

sub startTableRowHide()
{
    return '<tr style="display: none;">';
}

sub endTableRow()
{
    return "</tr>\n";
}

sub grpButton($$)
{
    my $text   = shift;
    my $color  = shift;
    my $button = '<button'
               . ' class="out"'
               . '     onClick="bdedox_grpButtonOnClick (this)"'
               . ' onMouseOver="bdedox_buttonOnMouseOver(this)"'
               . '  onMouseOut="bdedox_buttonOnMouseOut (this)"'
               . '>'
               . $text
               . '</button></td>';
    if ($color) {
        $button = setCellBackgroundColor($button, $color);
    }
    return $button;
}

sub pkgButton($$)
{
    my $text   = shift;
    my $color  = shift;
    my $button = '<button'
               . ' class="out"'
               . '     onClick="bdedox_pkgButtonOnClick (this)"'
               . ' onMouseOver="bdedox_buttonOnMouseOver(this)"'
               . '  onMouseOut="bdedox_buttonOnMouseOut (this)"'
               . '>'
               . $text
               . '</button></td>';
    if ($color) {
        $button = setCellBackgroundColor($button, $color);
    }
    return $button;
}

sub grpButtonCell($$)
{
    my $text  = shift;
    my $color = shift;

    my $styleAdjustment = 'style="padding: 2px 2px;"';
        # The 'indexkey' css class has 10px padding on sides;
        # too much for the buttons.  Override locally.

    my $cell  = "<td class=\"indexkey\" $styleAdjustment>"
              .  grpButton($text, "")  # button color set by its class
              . '</td>';
    if ($color) {
        $cell = setCellBackgroundColor($cell, $color);
    }
    return $cell;
}

sub pkgButtonCell($$)
{
    my $text  = shift;
    my $color = shift;

    my $styleAdjustment = 'style="padding: 2px 0px;"';
        # The 'indexkey' css class has 10px padding on sides;
        # too much for the buttons.  Override locally.

    my $buttonColor = BUTTON_TEXT_EMPTY eq $text
                    ? BG_EMPTY
                    : "";

    my $cell  = "<td class=\"indexkey\" $styleAdjustment>"
              . pkgButton($text, $buttonColor)
              . '</td>';
    if ($color) {
        $cell = setCellBackgroundColor($cell, $color);
    }
    return $cell;
}

sub textCell($$)
{
    my $text  = shift;
    my $color = shift;
    my $cell  = '<td class="indexkey">'
              .  $text
              . '</td>';
    if ($color) {
        $cell = setCellBackgroundColor($cell, $color);
    }
    return $cell;
}


#==============================================================================
# MAIN
#------------------------------------------------------------------------------
MAIN: {

    my $prog           = basename $0;
    my           $opts = getOptions();
    my      $filesInfo = $opts->{filesInfo};
    my    $modulesInfo = $opts->{modulesInfo};
    my $componentsInfo = $opts->{componentsInfo};
    my    $buttonTable = $opts->{buttonTable};
    my        $htmlDir = $opts->{htmlDir}; $htmlDir or
                                            fatal "$prog: no output directory";

    initFilesInfoMap($filesInfo);

    open(MH, "< $modulesInfo")      or
                           fatal "!! cannot open $modulesInfo for reading: $!";
    open(CH, "> $componentsInfo") or
                        fatal "!! cannot open $componentsInfo for writing: $!";

    my @output = ();

    my $offsetOfSyntheticGroupRowForIsolatedPackages = undef;
    my $countOfIsolatedPackages                      = 0;

    for (my $state = STATE_Normal; <MH>; ) {
         my $line = $_; chomp $line;


        if      (STATE_Normal == $state and isEndOfHeaderSection($line)) {
            push @output, scriptSection();
            push @output,  styleSection();
            push @output, "$line\n";

        } elsif (STATE_Normal == $state
             and my $leadIn = isStartOfTopList($line)) {

            push @output, "$leadIn\n";
            $state = STATE_InList;
            if ($buttonTable) {
                push @output, buttonTable('bdedox_componentsButtonTable_top',
                                          'bdedox_componentsTable');
                push @output, "<p>&nbsp;</p>\n";
            }
            push @output, "<table id=\"bdedox_componentsTable\">\n";
            push @output, tableHeader();

            push @output, syntheticGroupRowForIsolatedPackages();
            $offsetOfSyntheticGroupRowForIsolatedPackages = $#output;

        } elsif (STATE_InList == $state
             and my $isolatedPackage = isStartOfIsolatedPackage($line)) {

            ++$countOfIsolatedPackages;

            my $href                       = hrefOfLine($line);
            my $deprecatedFlag             = isDeprecated($htmlDir, $href);
            my $mnemonic                   =  getMnemonic($htmlDir, $href); 

            my $isolatedPackageNameCell    = getEntityNameCell(
                                                              $isolatedPackage,
                                                              BG_PKG,
                                                              $deprecatedFlag);
            my $isolatedPackagePurposeCell = getEntityPurposeCell(
                                                              $isolatedPackage,
                                                              BG_PKG,
                                                              $deprecatedFlag);
            my $mnemonicCell               = getMnemonicCell($mnemonic,
                                                             BG_PKG,
                                                             $deprecatedFlag);

            push @output,
                     startTableRowHide()
                   . emptyCell(BG_NONE)                             #grp button
                   . emptyCell(BG_NONE)                             #grp name
                   . pkgButtonCell(BUTTON_TEXT_COLLAPSED, BG_PKG)   #pkg button
                   . $isolatedPackageNameCell                       #pkg name
                   . $mnemonicCell                                  #cmp name
                   . $isolatedPackagePurposeCell                    #purpose
                   . endTableRow()
                   . "\n";


        } elsif (STATE_InList == $state
             and my $packageGroup = isStartOfPackageGroup($line)) {

            my $href                    = hrefOfLine($line);
            my $deprecatedFlag          = isDeprecated($htmlDir, $href);
            my $mnemonic                =  getMnemonic($htmlDir, $href); 

            my $packageGroupNameCell    = getEntityNameCell(  $packageGroup,
                                                              BG_GRP,
                                                              $deprecatedFlag);
            my $packageGroupPurposeCell = getEntityPurposeCell(
                                                              $packageGroup,
                                                              BG_GRP,
                                                              $deprecatedFlag);
            my $mnemonicCell            = getMnemonicCell(    $mnemonic,
                                                              BG_GRP,
                                                              $deprecatedFlag);

            push @output,
                     startTableRowShow()
                   . grpButtonCell(BUTTON_TEXT_COLLAPSED, BG_GRP)   #grp button
                   . $packageGroupNameCell                          #grp name
                   . emptyCell(BG_GRP)                              #grp button
                   . emptyCell(BG_GRP)                              #pkg name
                   . $mnemonicCell                                  #cmp name
                   . $packageGroupPurposeCell                       #purpose
                   . endTableRow()
                   . "\n";

        } elsif (STATE_InList == $state
            and my $package = isStartOfPackage($line)) {

            my $href               = hrefOfLine($line);
            my $deprecatedFlag     = isDeprecated($htmlDir, $href);
            my $mnemonic           =  getMnemonic($htmlDir, $href); 

            my $packageNameCell    = getEntityNameCell(   $package,
                                                          BG_PKG,
                                                          $deprecatedFlag);
            my $packagePurposeCell = getEntityPurposeCell($package,
                                                          BG_PKG,
                                                          $deprecatedFlag);
            my $mnemonicCell       = getMnemonicCell(     $mnemonic,
                                                          BG_PKG,
                                                          $deprecatedFlag);

            #No data on missing BAS packages.  Synthesize cells.
            if (!$packageNameCell) {
                $packageNameCell = defaultCell($package, BG_PKG);
            }
            if (!$packagePurposeCell) {
                $packagePurposeCell = tbdCell(BG_PKG);
            }

            my $buttonState = isNonCompliant($package)
                            ? BUTTON_TEXT_EMPTY
                            : BUTTON_TEXT_COLLAPSED;

            push @output,
                     startTableRowHide()
                   . emptyCell(BG_NONE)                             #grp button
                   . emptyCell(BG_NONE)                             #grp name
                   . pkgButtonCell($buttonState, BG_PKG)            #pkg button
                   . $packageNameCell                               #pkg name
                   . $mnemonicCell                                  #cmp name
                   . $packagePurposeCell                            #purpose
                   . endTableRow()
                   . "\n";

        } elsif (STATE_InList == $state
            and my $component = isComponentEntry($line)) {

            my $deprecatedFlag       = isDeprecated($htmlDir,
                                                    hrefOfLine($line));

            my $privateComponentFlag = isPrivateComponent($component);

#           my $componentNameCell    = getEntityNameCell(   $component,
#                                                           BG_CMP,
#                                                           $deprecatedFlag);
#           my $componentPurposeCell = getEntityPurposeCell($component,
#                                                           BG_CMP,
#                                                           $deprecatedFlag);

            my $componentNameCell    = getComponentNameCell(
                                                        $component,
                                                        $deprecatedFlag,
                                                        $privateComponentFlag);
            my $componentPurposeCell = getComponentPurposeCell(
                                                        $component,
                                                        $deprecatedFlag,
                                                        $privateComponentFlag);

            push @output,
                      startTableRowHide()
                   .  emptyCell(BG_NONE)                            #grp button
                   .  emptyCell(BG_NONE)                            #grp name
                   .  emptyCell(BG_NONE)                            #pkg button
                   .  emptyCell(BG_NONE)                            #pkg name
                   . $componentNameCell                             #cmp name
                   . $componentPurposeCell                          #purpose
                   . endTableRow()
                   . "\n";

        } elsif (STATE_InList == $state
             and isEndOfList($line)) {

        } elsif (STATE_InList == $state
             and isEndOfListItem($line)) {

        } elsif (STATE_InList == $state
             and isEndOfDiv($line)) {

            push @output, "</table>\n";
            if ($buttonTable) {
                push @output, "<p>&nbsp;</p>\n";
                push @output, buttonTable(
                                         'bdedox_componentsButtonTable_bottom',
                                         'bdedox_componentsTable');
            }
            $state = STATE_Normal;
            push @output, "$line\n";

        } else {

            push @output, "$line\n";
        }
    }

    if (0 == $countOfIsolatedPackages) {
        splice @output, $offsetOfSyntheticGroupRowForIsolatedPackages, 1;
    }

    print CH @output;
}
