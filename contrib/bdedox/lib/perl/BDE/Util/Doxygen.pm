package BDE::Util::Doxygen;

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

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK=qw(bde2doxygen);

use Util::Message qw(debug warning verbose);
use BDE::Util::Nomenclature qw(
    getComponentPackage getComponentGroup getPackageGroup
);

#==============================================================================
# LIST BLOCK CODE
#------------------------------------------------------------------------------
# Predefined constants
#------------------------------------------------------------------------------

use constant {
    LIST_TYPE_Unordered    => 1,
    LIST_TYPE_Numbered     => 2,
    LIST_TYPE_Hanging      => 3
};

my %listTypeToAscii = (
    LIST_TYPE_Unordered, "Unordered",
    LIST_TYPE_Numbered,  "Numbered",
    LIST_TYPE_Hanging,   "Hanging"
);

# Map each list type to the lines that must be emitted to start the list, end
# the list, start each item, each item, start a nested list, and end
# a nested list.  Multi-line values have embedded newline characters.
my %listTypeToEmittedLines = (
    LIST_TYPE_Unordered, [
          " * <ul>",
          " * </ul>",
          " * <li>",
          " * </li>",
          " *",
          " *"
        ],
    LIST_TYPE_Numbered, [
          " * <ol>",
          " * </ol>",
          " * <li>",
          " * </li>",
          " *",
          " *"
        ],
    LIST_TYPE_Hanging, [
          ' * <div class="hanging">',
          " * \\par\n * </div>",
          " * \\par",
          " *",
          " * \\par\n * <div class=\"unhanging\">",
          " * \\par\n * </div>"
        ]
);

#------------------------------------------------------------------------------
# Predefined regex patterns
#------------------------------------------------------------------------------
my $listMarker     = qr "^ *//:";
my $ulToken        = qr " [o\*] ";
my $nlToken        = qr "[ 1-9][0-9][.)]? ";  # 1 or 2 digits
# Glossary bullet item starts with text surrounded by double quotes
my $glossaryToken  = qr { "([^"]+)"(\s|:|$)};
my $listItemIndent = qr "$listMarker((?:  )*)"o;
my $ulListItem     = qr "$listMarker((?:  )*)($ulToken)"o;
my $nlListItem     = qr "$listMarker((?:  )*)($nlToken)"o;
my $glossaryItem   = qr "$listMarker((?:  )*)($glossaryToken)"o;
my $listItem       = qr "$listMarker((?:  )*)($ulToken|$nlToken| \S)"o;
my $listItemPrefix = qr "$listMarker((?:  )*)($ulToken|$nlToken)?"o;
my $listItemText   = qr "$listMarker( *)\S+"o;  # NOTE: matches tokens
my $listItemTerm   = qr {$listMarker *$}o;

#------------------------------------------------------------------------------
# Global Data
#------------------------------------------------------------------------------

my @classesList  = ();
my %classesInfo  = ();
my $entityType   = undef;
my $classname    = undef;
my $templateQualifier = undef;

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

{ # Tags closure

    my %tagDefs;

    # pushTagDefs(@lines, $tag1, $tag2, ...)
    #
    # Pushes anchors for zero or more tags onto the specified list of lines.
    # Each tag is pushed on its own line in the format
    # '<A NAME="tag">'
    sub pushTagDefs($@)
    {
        my ($lines, @tags) = @_;

        for my $tag (@tags) {
            $tag = trimGlossaryTag($tag) if isGlossaryTag($tag);

            if (exists $tagDefs{$tag}) { # Avoid duplicate tags
                my $component = getComponent();
                warning "DUPLICATE TAG: $component: $tag";
                next;
            }
            push @$lines, ' * <A NAME="'.$tag.'"></A>';
            $tagDefs{$tag} = 1;
        }
    }

    sub tagExists($)
    {
        my $tag = shift;
        return exists $tagDefs{$tag};
    }

    sub resetTagDefs()
    {
        %tagDefs = ();
    }

} # end tags closure

sub isBloombergLink($)
{
    my $tag = shift;
    return $tag =~ m|~3Cgo~3E|;
}

sub isListItemContinuation($$$)
{
    my ($line, $givenListLevel, $givenListType) = @_;

    if (($line =~ $ulListItem) || ($line =~ $nlListItem)) {
        # This is the beginning of a new numbered or bullet list item; it is
        # not a continuation.
        return 0;
    }

    # Continuation line begins with a list marker and is indented
    # at least two spaces deeper than the list item start.
    my $listItemCont = $listMarker . qr "(  ){$givenListLevel,} +\S";
    return 1 if ($line =~ $listItemCont);
    return 0;
}

sub isListMarkup($)
{
    my $line = shift;
    return $line =~ $listMarker;
}

sub listItemInfo($) {
    my $line = shift;

    my $listType  = (($line =~ $ulListItem)   ? LIST_TYPE_Unordered :
                     ($line =~ $nlListItem)   ? LIST_TYPE_Numbered  :
                     ($line =~ $glossaryItem) ? LIST_TYPE_Hanging   :
                     ($line =~ $listItem)     ? LIST_TYPE_Hanging   : undef);
    my $listLevel = 1 + (length($1) / 2);
    my $listToken = $2;
    return ($listLevel, $listType, $listToken);
}

sub applyCharacterStyles($;$);  # Forward declaration of recursive function

sub encodeUriFragment($) {
    # Convert the input string into a string suitable for use as URI fragment
    # (the portion of a URL/URI after the '#').  Ideally, illegal characters
    # would be "percent-encoded" as a '%' character followed by two hex
    # digits.  See RFC 3986.  Unfortunately, brownsers disagree as to how
    # to decode in-document links with percent-encoded characters in them
    # (Firefox decodes them, whereas IE doesn't).  Thus, instead of
    # percent-encoding illegal characters, this function replaces spaces with
    # underscores and other illegal characters with a tilde (~) followed by
    # two hex digits.  In addition, upper-case letters are converted to
    # lower-case.  It is possible for two distinct inputs to yield
    # the same output (e.g., "abc def" and "abc_Def" would both yield
    # "abc_def"), but distinct labels are rarely so similar as to
    # cause such a collision in practice.

    my $term = shift;
    my $result = lc $term;

    $result =~ s/^\s*//;  # Trim leading whitespace
    $result =~ s/\s*$//;  # Trim trailing whitespace

    # Remove formatting characters ('code', *italic*, !bold!, _italic_).
    $result = applyCharacterStyles($result, "strip");

    # Pattern of characters that are not legal in a URI fragment.  Percent
    # symbols are legal, but only as part of a percent-escaped sequence, so
    # they are considered part of the illegal character set for our purposes.
    # Ampersand (&) and apostrophy (') are also legal, but Doxygen insists on
    # modifying them under certain circumstances, so they are considered
    # illegal here.
    my $illegal = qr "[^-A-Za-z0-9._~!\$()*+,;=]";

    return $result unless ($result =~ $illegal);

    # Replace whitespace with underscores
    $result =~ s/\s/_/g;

    # Tilde-escape any other characters in the illegal list
    while ($result =~ m/($illegal)/o) {
        my $c = $1;                          # Character to be escaped
        my $hex = sprintf("%02X", ord($c));  # c in hex
        $c = "\\$c";  # escape $c
        $result =~ s/$c/~$hex/g;
    }

    return $result;
}

# Return a list of lines to be emitted at the start of a list.
# Usage: my @start = listStart($listType);
sub listStart($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[0];
}

# Return a list of lines to be emitted at the end of a list.
# Usage: my @end = listEnd($listType);
sub listEnd($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[1];
}

# Return a list of lines to be emitted before each list item.
# Usage: my @start = listItemStart($listType);
sub listItemStart($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[2];
}

# Return a list of lines to be emitted after each list item.
# Usage: my @end = listItemEnd($listType);
sub listItemEnd($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[3];
}

# Return a list of lines to be emitted before begining a nested list.
# Usage: my @start = listStartNested($listType);
sub listStartNested($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[4];
}

# Return a list of lines to be emitted after ending a nested list.
# Usage: my @end = listEndNested($listType);
sub listEndNested($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[5];
}

sub isNeedBR($) {
    my $line = shift;
    my $addBR  = $line =~ m|:\s*$|;
       $addBR += $line =~ m|:.*!DEPRECATED!|;  #for synopsis in pkg/grp-doc
       $addBR += $line =~ m|:.*!PRIVATE!|;     #for synopsis in pkg/grp-doc
    return $addBR;
}

sub processList($$);  #forward declaration (of recursive function).
sub processList($$)
{
    my $listLines = shift;
    my $ar        = shift;

    # the first line of a doubly spaced list can be (must be) a
    # single empty list-block-line (i.e., "//:").  Modify the prior
    # test to allow one, and only one, such line.

    my $line =  shift @$ar;            # Get the first line.
       $line =~ $listItem              # Is it a "list item"?
    or $line =  shift @$ar             # If not, get the second line.
    or $line =~ $listItem              # Is it a "list item"?
    or die "not a list item: $line";   # If not, the list is broken.

    my ($givenListLevel,$givenListType,$givenListToken) = listItemInfo($line);

    push @$listLines, listStart($givenListType);
    push @$listLines, listItemStart($givenListType);
    if ($givenListToken =~ $glossaryToken) {
        my $glossaryRef = encodeUriFragment($1);
        pushTagDefs($listLines, $glossaryRef, getSectionTags($glossaryRef));
        $line =~ s{$glossaryToken}{ *$1*$2};  # Italicize term
    }
    $line =~ s|$listItemPrefix||;
    push @$listLines, " * " . escape($line);
    push @$listLines, " * " . "<br>" if isNeedBR($line);

    my $withinItem = 1;

    while ($line = shift @$ar) {
        if ($withinItem &&
            isListItemContinuation($line, $givenListLevel, $givenListType)) {
            $line =~ s|$listItemIndent||;
            push @$listLines, " * " . escape($line);
            next;
        } elsif ($line =~ $listItem) {
            my ($listLevel, $listType, $listToken) = listItemInfo($line);

            if ($listLevel > $givenListLevel) {
                push @$listLines, listStartNested($givenListType);
                unshift @$ar, $line;
                $line = processList($listLines, $ar);
                unshift @$ar, $line;
                push @$listLines, listEndNested($givenListType);
                $withinItem = 0;
                next;
            } elsif ($listLevel < $givenListLevel) {
                push @$listLines, listEnd($givenListType);
                return $line;
            } else {
                push @$listLines, listItemEnd($givenListType);
                if ($listType != $givenListType) {
                    # End one type of list and start another
                    push @$listLines, listEnd($givenListType);
                    push @$listLines, listStart($listType);
                    $givenListType = $listType;
                }
                push @$listLines, listItemStart($listType);

                if ($listToken =~ $glossaryToken) {
                    my $glossaryRef = encodeUriFragment($1);
                    pushTagDefs($listLines,
                                $glossaryRef,
                                getSectionTags($glossaryRef));
                    $line =~ s{$glossaryToken}{ *$1*$2};  # Italicize term
                }
                $line =~ s|$listItemPrefix||;
                push @$listLines, " * " . escape($line);
                push @$listLines, " * " . "<br>" if isNeedBR($line);
                $withinItem = 1;
                next;
            }
        } elsif ($line =~ $listItemTerm) {
            $withinItem = 0;
            next;
        } else {
            push @$listLines, listItemEnd($givenListType);
            push @$listLines, listEnd($givenListType);
            return $line;
        }
    }

    push @$listLines, listItemEnd($givenListType);
    push @$listLines, listEnd($givenListType);
    return $line;
}

#==============================================================================

=head1 NAME

=head1 SYNOPSIS

    use BDE::Util::Doxygen qw(bde2doxygen);

    my $filename="documentation.txt";
    open FILE,$filename or die "Unable to open $filename: $!";
    my @lines=<FILE>;
    close FILE;

    my $doxygenated_content=bde2doxygen(\@lines,$filename);

=head1 DESCRIPTION

This module implements a translator that converts BDE-style documentation
to Doxygen format.

=cut

#==============================================================================

# major states
use constant NOSTATE        => 0;
use constant INTRO          => 1;
use constant CLASS          => 2;

# minor states
use constant CLASSES        => 3;
use constant DESC           => 4;
use constant CLASSHEAD      => 5;
use constant PROTOTYPE      => 6;
use constant COMMENT        => 7;
use constant PREFORM        => 8;
use constant TITLE          => 9;
use constant CLASSES_BULLET => 10;
use constant LIST_BLOCK     => 11;
use constant MACRO          => 12;

my ${BR}="\\n\\n"; # whitespace around code blocks

#==============================================================================


{ # state closure
    my (@majorstate,@minorstate); # major/minor state

    sub pushstate  ($$) { push @majorstate, $_[0]; push @minorstate, $_[1]; }
    sub popstate   ()   { return pop(@majorstate),pop(@minorstate); }
    sub majorstate ()   { return $majorstate[-1]; }
    sub minorstate ()   { return $minorstate[-1]; }
    sub statedepth ()   { return scalar(@majorstate)-2; }
    sub resetstate ()   { @majorstate=(-1,NOSTATE); @minorstate=(-1,NOSTATE); }
    # the initial states have an extra '-1' in it to help track state errors
    # in debug mode
}

my $namespaceStack = 0;

{ # Output line closure

    my @lines; # this is the output
    my $debug = Util::Message::get_debug();

    #----------

    # reset line store
    sub resetlines () {
        @lines=();
    }

    sub pushline ($) {
        my $string = shift;

        if ($debug) {
            push @lines, statedepth().' '.majorstate()."/".minorstate().
                 ": ".$string;
        } else {
            push @lines, $string;
        }
    }
    sub appendline ($) {
        my $string = shift;

        if ($debug) {
            push @lines, statedepth().' '.majorstate()."/".minorstate().
                 "[Append]: ".$string;
        } else {
            push @lines, pop(@lines) . $string;
        }
    }

    # retrieve processed output
    sub getlines () {
        return \@lines;
    }

    # retrieve current line count
    sub getlinecount () {
        return $#lines;
    }

    sub getline($) {
        my $lineNumber = shift;
        return $lines[$lineNumber];
    }

    sub setline($$) {
        my $lineNumber = shift;
        my $line       = shift;
        $lines[$lineNumber] = $line;
    }
}

{ # Input line closure
    # Mange stepping through the array (via reference) of input lines.  Methods
    # are provided to set the static reference to the input array
    # (the 'setLineRef' function), to get the next line from the current
    # position and automatically update that position to the next line (the
    # 'getNextLine' function), to decrement the current position ('ungetLine')
    # and to retrieve the current line number and curly-brace nesting level
    # ('lineNum' and 'curlyBraceDepth').

    my $linesRef   = undef;
    my $offset     = undef;
    my $lineCount  = undef;
    my $curlyDepth = undef;

    sub countCurlies($)
        # Count the open and close curly braces within the specified input
        # string.  Returns the difference between the number of open braces
        # and close braces (negative if close braces outnumber open braces.
        # Quoted strings and comments are skipped.  This function uses a
        # primitive counting mechanism; no attempt is made to ensure that
        # close braces match open braces (i.e., "}{}{" will return zero, even
        # though the braces do not correctly match).
    {
        my $line = shift;

        # Remove comments and quoted strings
        $line =~ s/"(\\"|[^"])*"//g;
        $line =~ s/'(\\'|[^'])*'//g;
        $line =~ s|//.*$||;

        # Remove all characters except the curly braces
        $line =~ s/[^{}]//g;

        my $curlyCount = length($line);
        $line =~ s/\{//g; # Remove the open curlies
        my $closeCurlies = length($line);
        my $openCurlies = $curlyCount - $closeCurlies;

        return $openCurlies - $closeCurlies;
    }

    sub setLinesRef($)
        # Set the specified $linesRef, a reference to an array, as the source
        # of input lines.
    {
        $linesRef = shift;
        if (defined $linesRef) {
            $offset     = 0;
            $lineCount  = scalar @$linesRef;
            $curlyDepth = 0;
        }
    }

    sub getNextLine()
        # Return the line from the current position in the input lines, and
        # increment the current position.  Return undef when current position
        # is just past the last line.  The behavior is undefined unless
        # '0 <= $offset <= $lineCount'.
    {
       0 <= $offset and $offset <= $lineCount or
              die "getNextLine: offset $offset not in range [0, $lineCount]\n";

       return undef if $lineCount <= $offset;
       my $line = $linesRef->[$offset++];
       $curlyDepth += countCurlies($line);
       # print "$offset: $line\n";  # For debugging
       return $line;
    }

    sub peekNextLine()
        # Return the line from the current position in the input lines, and
        # increment the current position.  Return undef when current position
        # is just past the last line.  The behavior is undefined unless
        # '0 <= $offset <= $lineCount'.
    {
       0 <= $offset and $offset <= $lineCount or
              die "getNextLine: offset $offset not in range [0, $lineCount]\n";

       return undef if $lineCount <= $offset;
       my $line = $linesRef->[$offset];
       return $line;
    }

    sub ungetLine()
        # Decrement the offset.
    {
       my $line = $linesRef->[--$offset];
       $curlyDepth -= countCurlies($line);
    }

    sub insertLine($) 
    {
       my $line = shift;  # Becomes next line returned by 'getNextLine'.

       splice @$linesRef, $offset, 0, ($line);
       $lineCount  = scalar @$linesRef;
    }

    sub lineNum()
        # Return the line number of the line corresponding to the most recent
        # call to 'getNextLine'
    {
        # zero-based offset but one-based line numbers.  Since the offset
        # has already been incremented, don't do it again.
        return $offset;
    }

    sub curlyBraceDepth()
    {
        return $curlyDepth;
    }
}


#------------------------------------------------------------------------------
# Group levels and names
#  Supporting three levels of nesting
use constant PACKAGE_GROUP => 0;
use constant PACKAGE       => 1;
use constant COMPONENT     => 2;
use constant MAX_GROUPS    => 3;

{ # Groups closure
    # TODO: Need to provide a function to yield groupname without +
    #       And then use it to provide the "\defgroup" header
    #
    my @beginGroups;
    my @endGroups;
    my $inGroup = 0;

    my @level_name = (
       "Package Group",
       "Package",
       "Component"
       );

    sub isPackageGroupName($) {
        my $groupName =  shift;
        return $groupName =~ m|^(z_)?([el]_)?[a-z][a-z0-9]{2}$|;
    }

    sub getLevelName($$) {
        my $group_level = shift;
        my $groupName   = shift;

        my $levelName = $level_name[$group_level];

    if ($group_level eq PACKAGE_GROUP
         && !isPackageGroupName($groupName)) {
            $levelName = "Package (Isolated)";
        }
        return $levelName;
    }

    sub setGroups($@) {
        my ($group,@names) = @_;
        my $g = 0;

        @beginGroups = ( );
        @endGroups = ( );

        my  $old = "";
        while($g <= $group) {
            my $g_noplus = $names[$g];
            $g_noplus =~ s/\+/_P_/g;

            # Do not push anything if $g_noplus has the same name as the
            # previous one.  This can happen for isolated packages that are
            # treated as package groups.  Otherwise, there would be the package
            # would be a member of itself.

            if ($old ne $g_noplus) {
                push @beginGroups, "/** \\addtogroup $g_noplus";
                push @beginGroups, " * \@{ ";
                push @beginGroups, " */"   if ($g < $group);
            }
            ++$g;
            $old = $g_noplus;
        }
        while ($g > 0) {
            push @endGroups, "/* \@} */";
            --$g;
        }
    }
    sub openGroups($) {
        my $inComment = shift;
        unless ($inGroup) {
            $inGroup = 1;
            #pushline("/*") unless ($inComment);
            for my $b (@beginGroups) {
                pushline($b);
            }
            pushline(" */") unless ($inComment);
        }
    }
    sub closeGroups() {
        if ($inGroup) {
            for my $e (@endGroups) {
                pushline($e);
            }
            $inGroup = 0;
        }
    }

    my $s_component          = undef;
    my $s_pkg                = undef;
    my $s_pkgGroup           = undef;
    my $s_levelOfAggregation = undef;
    my @s_groups             = ();

    sub initGroupInfo($) {
        my $component = shift;

        # derive package and package group from component
        my $package=getComponentPackage($component) || $component;
        my $package_group=getPackageGroup($package) || $package;

        my @groups = ( $package_group, $package, $component );

        # what group level are we at?
        my $group_level = ($package_group eq $package
                        && $package eq $component) ? PACKAGE_GROUP:
                          ($package eq $component) ? PACKAGE      :
                                                     COMPONENT    ;
        setGroups($group_level, @groups);

        $s_component          = $component;
        $s_pkg                = $package;
        $s_pkgGroup           = $package_group;
        $s_levelOfAggregation = $group_level;
        @s_groups             = @groups;
    }
    sub getComponent() {
        return $s_component;
    }
    sub getGroups() {
        return @s_groups;
    }
    sub getLevelOfAggregation() {
        return $s_levelOfAggregation;
    }
}

#------------------------------------------------------------------------------
{ # header closure
    my @TOC_entries;
    my @levels;
    # Section names encoded for use in URIs
    my @seclinks;

    # return tag for specified level
    sub getTag($) {
        my $hlev = shift;
        return join('.',@levels[0..$hlev-1]);
    }

    # special handling for tags in 'bsls_glossary'
    sub isGlossaryTag($){
        my $tag = shift;
        return $tag =~ m|_~5B.*~5D$|;
    }
    sub trimGlossaryTag($) {
        my $oldTag = shift;
        my $newTag = $oldTag; $newTag =~ s|_~5B.*~5D$||;
        return $newTag;
    }

    # Return a list of tags that are all aliases for the current section,
    # appending an optional suffix to each.  The first tag is the encoded name
    # of the current section.  The second tag is a concatonation of the name
    # of the parent section and the current section.  The tag before that
    # prepends the parent's parent, etc..  The longer tags are used to
    # disambiguate in the case where the same subsection shows up in multiple
    # sections.
    sub getSectionTags(;$) {
        my $suffix = shift;

        $suffix = $suffix ? ('.' . $suffix) : "";
        my @ret;
        my $lastidx = @seclinks - 1;  # zero-based indexing
        for (my $i = $lastidx; $i >= 0; --$i) {
            push @ret, join('.', @seclinks[$i..$lastidx]).$suffix;
        }
        if ($seclinks[$lastidx] =~ s|~3A.*||) {

            # Succeeded in removing a ':' and trailing material.
            # Redo section tags with abbreviated section tag name

            for (my $i = $lastidx; $i >= 0; --$i) {
                push @ret, join('.', @seclinks[$i..$lastidx]).$suffix;
            }
        }
        return @ret;
    }

    # main working routine.
    # Note: $txt must not be escaped
    sub pushheader($$) {
        my ($level, $txt) = @_;
        $txt =~ s/:$//o;    # remove trailing colon from TOC entry

        # Adjust TOC nesting for level
        while (@levels < $level) {
            push @levels, 0;
            push @seclinks, "";
            push @TOC_entries, " * <UL>";

            # If we skipped levels, then we must add an empty list item
            push @TOC_entries, " * <LI>&nbsp;</LI>" if (@levels < $level);
        }
        while (@levels > $level) {
            pop @levels;
            pop @seclinks;
            push @TOC_entries, " * </UL>";
        }
        ++$levels[-1];  # Increment deepest level
        $seclinks[-1] = encodeUriFragment($txt);

        # Add tag link and section links
        pushline(" * \\par");
        my @sectags = getSectionTags();
        pushTagDefs(getlines(), @sectags);
        my $tag = getTag($level);
        pushline(" * <A NAME=\"$tag\"> \\par ".escape($txt).": </A>");
        pushline(" * \\par");

        # Add TOC entry
        push @TOC_entries," * <LI><A HREF=\"#$tag\">".escape($txt)."</A></LI>";
    }
    # Insert the Table of Contents in position $pos
    sub insertTOC ($$) {
        my $lines = shift;
        my $pos = shift;

        while (@levels) {
            push @TOC_entries, " * </UL>";
            pop @levels;
        }

        splice ( @$lines, $pos, 0, ( " * \\par " ) );
        splice ( @$lines, $pos, 0, @TOC_entries );
        splice ( @$lines, $pos, 0, ( " * \\par Outline" ) );
    }

    # retrieve processed output
    sub getheaders () {
        return \@TOC_entries;
    }

    # reset headers
    sub resetheaders () {
        @TOC_entries=();
        @levels = ();
        @seclinks = ();
    }
}
#------------------------------------------------------------------------------

sub strpbrk($$$)
    # Return the offset in the specified '$string' of the first instance at or
    # after the specified '$offset' of any of the characters in the specified
    # '$accept', or a value less then 0 if none are found.
{
    my $string = shift;
    my $accept = shift;
    my $offset = shift;

    my $retPos = -1;

    for my $chr (split //, $accept) {
        my $pos = index $string, $chr, $offset;
        next if $pos < 0;
        $retPos = $pos if $retPos < 0
                       or $pos    < $retPos;
    }
    return $retPos;
}

sub findDoubleQuote($$)
    # Return the offset in the specified '$string' of the first double-quote
    # ('"') at or after the specified '$offset', or a negative value if none
    # is found.  The special sequences '"', and '\"' are skipped since they
    # do not delimit quoted strings.
{
    my $string = shift;
    my $offset = shift;

    my $specialCase1 =   "'\"'";  # '"'
    my $specialCase2 = "'\\\"'";  # '\"'

    for (my $dquotePos = $offset;; ++$dquotePos) {
        $dquotePos = index $string, '"', $dquotePos;
        if (0 <= $dquotePos) {
            next if $specialCase1 eq substr($string, $dquotePos - 1, 3);
            next if $specialCase2 eq substr($string, $dquotePos - 2, 4);
        }
        return $dquotePos;                                             # RETURN
    }
}

sub partitionByDoubleQuotes($)
    # Partition the specified '$string' into quoted and unquoted substrings
    # where a quoted string is surrounded by two double-quote characters ('"').
    # Return a reference to an array of two-element array references in which:
    #: o the first element is a "tag" that can be 'quoted' or 'unquoted' or
    #:   'unbalanced', and
    #: o the second element is the corresponding sub-string.
    # The 'quoted' sub-strings are *not* stripped of their delimiting quote
    # characters.  The array of two-elment arrays is ordered so that the
    # associated sub-strings can be concatinated to re-create the original
    # '$string'.  If '$string' has any unbalanced quote characters, return a
    # reference to a single two-element array with a "tag" of 'unbalanced'
    # and a "sub-string" consisting of the original '$string'.
{
    my $string      = shift;

    my @fragments   =     ();
    my $begOfSearch =      0;
    my $begOfQuoted =  undef;

    while (0 <= ($begOfQuoted = findDoubleQuote($string, $begOfSearch))) {

        my $lenUnquoted = $begOfQuoted - $begOfSearch;
        if ($lenUnquoted > 0) {
            push @fragments, [ "unquoted",
                                substr($string, $begOfSearch, $lenUnquoted) ];
        }

        my $endOfQuoted = findDoubleQuote $string, $begOfQuoted + 1;
        if (0 > $endOfQuoted) {
            @fragments = ();
            push @fragments, [ "unbalanced", $string ];
            return \@fragments;                                        # RETURN
        }

        my $lenQuoted = $endOfQuoted - $begOfQuoted + 1;
        push @fragments, [ "quoted",
                            substr($string, $begOfQuoted, $lenQuoted) ];

        $begOfSearch = $endOfQuoted + 1;
    }

    my $lenRestOfLine = length($string) - $begOfSearch;
    if ($lenRestOfLine > 0) {
        push @fragments, [ "unquoted",
                            substr($string, $begOfSearch, $lenRestOfLine) ];
    }

    return \@fragments;
}

sub escapeDoxygenSpecials($)
    # Return a string in which the Doxygen special characters (e.g., '@', '&')
    # have been escaped by a preceding '\' character, *except* within
    # sub-strings delimited by pairs of single- or double-quote characters.
{
    my $string = shift;

    my $retStr =  "";

    for my $pairRef (@{partitionByDoubleQuotes($string)}) {
        my $category = $pairRef->[0];
        my $subStr   = $pairRef->[1];

             if (  "unquoted" eq $category) {
                                            $subStr=~s{([\@<>&\$#\\])}{\\$1}go;
        } elsif (    "quoted" eq $category) { # no xform
        } elsif ("unbalanced" eq $category) { return $string;           #RETURN
        } else                              {
                                             die "unknown category: $category";
        }

        $retStr .= $subStr;
    }
    return $retStr;
}

# Replace 'code', *italic*, !bold!, or _italic_ text with the appropriate HTML
# character-format markup.  If second second argument ('strip') is provided
# and has a true value, then the markup text is stripped out rather than
# replaced (i.e., "*text*" becomes simply "text", with no character
# formatting).  The start of the 'code', *italic*, !bold!, or _italic_ text is
# recognized only if the "'", "*", "!", or "_" is preceded by a space,
# begining-of-line, or open parenthesis and followed by a non-space,
# non-close-parenthesis character.  The end of the formatted text is
# recognized only if the "'", "*", "!", or "_" is preceded by a non-space,
# non-open-parenthesis character and followed by a non-word character or
# end-of-line, except that the word endings, "s", "ed", and "ing" can appear
# after the closing delimiter. Thus "*italic*" and "*italic*s" are treated
# specially but "a * b", "(*)", or "*) x (*" are not.  These character-format
# marks may be nested (so that "*!bold-italic!*" is recognized), except that
# any text nested within single quotes is treated as raw code and nested "*",
# "!", or "_" characters are NOT interpreted as format directives.  No attempt
# is made to detected mismatched parenthesis, etc..
sub applyCharacterStyles($;$)
{
    my ($string, $strip) = @_;

    my %replacements = (
        "'" => "code",
        "*" => "em",
        "!" => "strong",
        "_" => "em"
        );

    # Word endings allow special cases of word characters after a closing tick:
    #  'object's
    #  'allocate'd
    #  'destroy'ed
    #  'i'th
    my $word_ending = "(?:s|d|ed|th|ing)";

    my $result = "";

    # Find the start of the formatted text
    while ($string =~ m{(?:\s|^|\(|/)   # space, BOL, '(', or '/'
                        ([\'*!_])       # formatting delimiter
                        [^ \)]          # non-ws, non-')'
                       }x) {

        my $delimiter = $1;      # Formatting delimiter ("'", "*", "!", or "_")
        my $start_delim_pos = $-[1]; # Position of starting formatting delim
        $result .= substr($string, 0, $start_delim_pos);
        $string = substr($string, $start_delim_pos + 1);

        if ($delimiter ne "'" && $string =~ s/^([$delimiter]+)// ) {
            # Skip repeated delimiter (e.g., "***" or "__").
            $result .= $delimiter.$1;
            next;
        }

        # Find end of formatted text.  Does not match empty sequence.
        if ($string !~ m{[^ \(]        # non-ws, non-'('
                         ([$delimiter])
                         $word_ending? # optional word ending
                         (?:\W|$)      # non-word or EOL
                        }x) {
            $result .= $delimiter;
            next;  # resume parsing from character after failed delimiter
        }

        my $end_delim_pos = $-[1];  # Position of ending formatting delimiter
        my $delimited_text = substr($string, 0, $end_delim_pos);
        $string = substr($string, $end_delim_pos + 1);

        my $start_tag = "";
        my $end_tag   = "";
        unless ($strip) {
            $start_tag = "<".$replacements{$delimiter}.">";
            $end_tag   = "</".$replacements{$delimiter}.">";
        }

        # Recursively apply character styles in delimited text
        $delimited_text = applyCharacterStyles($delimited_text, $strip)
            unless ($delimiter eq "'");  # But not on <code>-delimited text

        # Append formatted piece to result
        $result .=  $start_tag . $delimited_text . $end_tag;
    }

    # Append remaining string to result
    $result .= $string;

    return $result;
}

# escape Doxygen-significant characters - use for comments only, not code.
# also, translate 'code', *italic*, and !bold! markers in the text. Italics
# include (*this* *text*) but not (*).  Similarly for bold.
sub escape ($) {
    my $string = shift;

    $string = escapeDoxygenSpecials($string) if $string;

    my $obscuredColonColon = "PER_DRQS-27494910_OBSCURE"
                           . "_COLON-COLON_HERE"
                           . "_THEN_RESTORE_IN_POST-PROCESSING";
    $string =~ s|'::|'${obscuredColonColon}|g;

    my $obscuredAsertiskSlash = "PER_DRQS-28777305_OBSCURE"
                              . "_ASTERISK-SLASH_HERE"
                              . "_THEN_RESTORE_IN_POST-PROCESSING";
    $string =~ s|\*\/|${obscuredAsertiskSlash}|g;

    # Zero-width before- and after-match expressions:
    my $P = qr{(?:\s|^|\(|/)\K};  # match PREFIX: space, BOL, '(', or '/'
    my $S = qr{(?=(?:\W|$))};     # match SUFFIX: non-word or EOL

    my $bellCode = "<code>\a</code>";
    $string =~ s|$P\'\'\'$S|$bellCode|gexo;     # Special case '''
    $string =~ s|$P\'\\\\\'\'$S|$bellCode|gexo; # Special case '\'',
                                                # which is '\\'' after
                                                # 'escapeDoxygenSpecials'
                                                # is called.
    $bellCode = "<code>\a&nbsp;\a</code>";
    $string =~ s|$P\'\s\'$S|$bellCode|gexo;     # Special case ' '

    $string = applyCharacterStyles($string);

    $string =~ tr[\a][\'];
    return $string;
}

sub escapePreform($) {
    my $string = shift;
    $string =~ s/@/\\@/g;
    return $string;
}

# Reverse the effects of escape($string).
sub unescape($)
{
    my $string = shift;

    $string =~ s{</?em>}{*}g;
    $string =~ s{</?strong>}{!}g;
    $string =~ s{</?code>}{'}g;

    $string =~ s{\\([\@<>&\$#\\])}{$1}go;

    return $string;
}

my $generalLink    = qr /{(\'?\w[^{}]*)}/io;
my $glossaryLink   = qr /(\s)"([^"]+)"(\s+\(see\s+$generalLink\))/io;

sub splitLink($)
{
    my $link = shift;

    # Split into a maximum of two parts separated by '|'
    my @parts = split(/\|/, $link, 2);

    if ($parts[0] =~ /^'([^']+)'$/) {
        # First part of link is document name in 'single-quotes'.
        # Return document name (without quotes) and section name (if any)
        $parts[0] = $1;
        push @parts, "" unless (@parts > 1);
    }
    else {
        # First part is not a document name in 'single-quotes'.
        # return empty document name with unmodified input as section name.
        @parts = ("", $link);
    }

    return @parts;
}

# Mangle a source filename into the form generated by Doxygen
sub doxygenizeFilename($)
{
    my $filename = shift;

    $filename =~ s/_/__/g;
    $filename =~ s/\./_8/g;
    $filename =~ s/:/_1/g;
    $filename =~ s/\+/__P__/g;

    return $filename;
}

# Convert the specified package group, package, or component name into
# a URL pointing to its documentation.
sub documentToUriPath($)
{
    my $document = shift;
    die "missing document name" if !$document;

    return "group__" . doxygenizeFilename($document) . ".html";
}

{   # 'codeField' Closure

    my $codeFieldRegex  = "<code>.*?</code>";
    my $lengthStartTag  = length("<code>");
    my $lengthEndTag    = length("</code>");
    my @codeFields      = ();
    my $line            = undef;
    my $isCodeFieldsSet = 0;

    sub setLineForCodeFields($) {
        my $nextLine     = shift;
        $line            = $nextLine;
        @codeFields      = (); # lazy evaluation
        $isCodeFieldsSet = 0;  # lazy evaluation
    }

    sub setCodeFields() {
        die "code fields line has not been called set." if !defined($line);

        while ($line =~ m|($codeFieldRegex)|g) {
            my $codeFieldStart  = $-[1];
            my $codeFieldLength = $+[1] - $codeFieldStart + 1;
               $codeFieldStart  += $lengthStartTag;
               $codeFieldLength -= $lengthStartTag + $lengthEndTag + 1;
            push @codeFields,  [ $codeFieldStart, $codeFieldLength ];
        }
        $isCodeFieldsSet = 1;
    }

    sub getLineForCodeFields() {
        return $line;
    }

    sub getCodeFieldsRef() {
        setCodeFields() if !$isCodeFieldsSet;
        return \@codeFields;
    }

    sub isInSomeCodeField($$) {
        my $start = shift;
        my $len   = shift;
        my $end   = $start + $len;

        setCodeFields() if !$isCodeFieldsSet;

        for my $itemRef (@codeFields) {
            my $codeFieldStart  = $itemRef->[0];
            my $codeFieldLength = $itemRef->[1];
            my $codeFieldEnd    = $codeFieldStart + $codeFieldLength;

            next if $start <  $codeFieldStart;
            next if $start >= $codeFieldStart + $codeFieldLength;

            return substr($line, $codeFieldStart, $codeFieldLength);
        }
        return undef;
    }
}

# Replace each link in the input string of the form:
#
#   {doc|section.subsection}
#
# with an HTML hyperlink to the specified subsection within the specified
# section within the specified document.  The document can be the name of a
# component, package, or package group.  If the document is not specified
# (i.e., there is no '|' in the link, then the current document is assumed.  A
# link of form
#
#   {doc|*}
#
# links to the top of the specified document.  A link of the form:
#
#   "glossary phrase" (see {link})
#
# (quotes required) will create two hyperlinks: {link} is replaced by a
# hyperlink to the subesection specified by link, as usual, and "glossary
# phrase" is replaced by a hyperlink to the definition of phrase within the
# subection.
#
# Usage: my $string2 = replaceLinks($string1);
#
sub replaceLinks($)
{
    my $string = shift;

    setLineForCodeFields($string);

    while ($string =~ m/$generalLink/g) {
        # Save pos so that next search will not start from the
        # begining:
        my $rawlink = $1;
        # $rawlinkstart and $rawlinklen include open and close curlies
        my $rawlinkstart = $-[1] - 1;
        my $rawlinklen   = $+[1] - $rawlinkstart + 1;

        next if isInSomeCodeField($rawlinkstart, $rawlinklen);

        next if ($rawlink =~ /\s$/);  # Skip if trailing whitespace
        my $link = unescape($rawlink);

        # Split document part from section within document
        my ($document, $section) = splitLink($link);
        my $sectionTag = encodeUriFragment($section);

        # Don't replace local link to non-existant tag
        if (!$document && !tagExists($sectionTag)) {
            my $component = getComponent();
            warning
              "BAD LINK: $component: document=$document sectionTag=$sectionTag"
                                           unless isBloombergLink($sectionTag);
            next;
        }

        my $linkPath = documentToUriPath($document
                                       ? $document
                                       : getComponent());

        if ($string =~ $glossaryLink) {
            # Replace the glossary reference within the link with a glossary
            # link.
            my $rawname = $2;
            # $rawnamestart and $rawnamelen include open and close quotes
            my $rawnamestart = $-[2] - 1;
            my $rawnamelen   = $+[2] - $rawnamestart + 1;

            # Unescape special characters in glossary name
            my $name = unescape($rawname);

            my $nameTag = encodeUriFragment($name);
            $nameTag = $sectionTag . ($section ? "." : "") . $nameTag;
            if ($document || tagExists($nameTag)) {
                my $htmlref = "<A CLASS=\"glossary\" ".
                    "HREF=\"$linkPath#$nameTag\">".escape($name)."</A>";
                my $lenchange = length($htmlref) - $rawnamelen;
                substr($string, $rawnamestart, $rawnamelen) = $htmlref;
                $rawlinkstart += $lenchange;  # compenstate for change
            }
        }

        my $linkUrl = $linkPath;
        $linkUrl .= '#' . $sectionTag if ($section);
        # Format document name in code font
        $rawlink =~ s{^'(.+)'}{<code>$1</code>};
        my $htmlref = "<A CLASS=\"el\" HREF=\"$linkUrl\">$rawlink</A>";
        substr($string, $rawlinkstart, $rawlinklen) = $htmlref;
    } # end while more links in line

    return $string;
}

# Iterate over the comment lines 'getlines()' and replace the {links} with
# HTML hyperlinks.  Each link or glossary entry can extend  across two lines, but not more than two
# lines.
sub insertLinks()
{
    my $lines = getlines();
    for (my $i = 0; $i < @$lines; ++$i) {
        my $string = $lines->[$i];
        next unless ($string =~ m{^\s\*\s} );  # Skip non-comments

        my $nextline = $i < @$lines ? $lines->[$i + 1] : "";
        my $nextlineprefix;
        if ($nextline =~ s{^( \*\s+)}{}) {
            # Combine current and next line into one string with newline in
            # between.  The comment prefix is removed from the second line
            # but is saved so that it can be put back.
            $nextlineprefix = $1;
            $string .= "\n".$nextline;
        }

        $string = replaceLinks($string);

        if ($nextlineprefix) {
            # If two lines were combined, separate them now.
            ($string, $nextline) = split(/\n/, $string);
            $lines->[$i + 1] = $nextlineprefix.$nextline;
        }

        $lines->[$i] = $string;

    } # end for each string in lines
}

sub isAspectsBanner($)
{
    my $line = shift;
    return $line =~ m|^ +// +Aspects *$|;
}

sub editClassBriefDesc($)
{
    my $classBriefDesc = shift;
    return "" eq $classBriefDesc ? "TBD" : $classBriefDesc;
}

sub getClassBriefDesc($$) {
    my $classname         = shift;
    my $templateQualifier = shift;
    my $defaultValue = ""; # "Not Available";

    if (exists($classesInfo{$classname})) {
        return editClassBriefDesc(
               $classesInfo{$classname});
    }

    if (!$templateQualifier) {
        return $defaultValue;
    }

    my $classnameWithTemplate = $classname . $templateQualifier;

    if (exists($classesInfo{$classnameWithTemplate})) {
        return editClassBriefDesc(
               $classesInfo{$classnameWithTemplate});
    }

    my $reducedTemplateQualifier = $templateQualifier;
    $reducedTemplateQualifier =~ s|\w+::||g;

    if ($templateQualifier eq $reducedTemplateQualifier) {
        return $defaultValue;
    }

    my $classnameWithReducedTemplate = $classname . $reducedTemplateQualifier;

    if (exists($classesInfo{$classnameWithReducedTemplate})) {
        return editClassBriefDesc(
               $classesInfo{$classnameWithReducedTemplate});
    }

    return $defaultValue;
}

# --Process Blocks --

sub isCommentLine($)
{
    my $line = shift;
    return $line =~ m|^\s*//|;
}

sub isNoFillToggle($)
{
    my $line = shift;
    return $line =~ m|^\s*//\.\.|;
}

sub processNoFillBlock()
    # Process the nofill-block starting at the current position in the input
    # lines.  Push the results to the output lines.
{
    pushline("${BR}\\code");
    for (my $line, my $firstLoop = 1; defined($line = getNextLine());
         $firstLoop = 0) {
        if ($firstLoop) {
            isNoFillToggle($line) or
                die "processNoFillBlock: no toggle: $line";
            next;
        }
        last if not $firstLoop and isNoFillToggle($line);

        isCommentLine($line) or
            die "processNoFillBlock: non-comment in nofill-block: $line";
        $line =~ s|//||o; pushline($line);
    }
    pushline("\\endcode${BR}");
}

sub processListBlock()
    # Process the list-block starting at the current position in the input
    # lines.  Push the results to the output lines.
{
    my @listLinesIn = ();

    for (my $line, my $firstLoop = 1; defined($line = getNextLine());
         $firstLoop = 0) {
         if ($firstLoop) {
             isListMarkup($line) or
                                die "processListBlock: not list markup: $line";
         }
         last if not $firstLoop and not isListMarkup($line);
         push @listLinesIn, $line;
    }
    ungetLine();

    my @listLinesOut = ();
    processList(\@listLinesOut, \@listLinesIn);
    pushline $_ foreach @listLinesOut;
}

sub processCommentBlock($)
    # Process the sequence of comments starting at the current position in the
    # input lines.  Push the results to the output lines.  If the specified
    # '$suppressDoxygenStartOfCommentBlock' is 'true', do not push the sequence
    # "/*<".  Note that # list-blocks and nofill-blocks are handled implicitly.
{
    my $suppressDoxygenStartOfCommentBlock = shift;
    pushline("/*!<") unless  $suppressDoxygenStartOfCommentBlock;

    for (my $line, my $firstLoop = 1; defined($line = getNextLine());
         $firstLoop = 0) {
         if ($firstLoop) {
             isCommentLine($line) or
                                  die "processCommentBlock: no comment: $line";
         }

         last if not isCommentLine($line);

              if (isNoFillToggle($line)) { ungetLine();
                                           processNoFillBlock();
         } elsif (  isListMarkup($line)) { ungetLine();
                                           processListBlock();
         } else {
                                           $line =~ s|//||;
                                           pushline(" *".escape($line));
         }
    }
    ungetLine();
    pushline(" */");
}

#==============================================================================
sub isStartOfEnum($) {
    my $line = shift;
    return $line =~ m|^\s*enum\s+(\w+\s+)?{\s*$|;
}
sub isEndOfEnum($) {
    my $line = shift;
    return $line =~ m|^\s*};|;
}
sub isCommentOnlyLine($) {
    my $line = shift;
    return $line =~ m|^\s*//|;
}
sub hasComment($) {
    my $line = shift;
    return $line =~ m|//|;
}
sub isEnumElementLine($) {
    my $line = shift;
    return $line =~ m|^\s*,?\s*([ek]_)?[A-Z]+|;
}
sub isEmptyLine($) {
    my $line = shift;
    return $line =~ m|^\s*$|;
}

sub isEnumPassthroughLine($) {
    my $line = shift;
    return (isEmptyLine($line))
        or ($line =~ m|^\s*#if|)
        or ($line =~ m|^\s*#else|)
        or ($line =~ m|^\s*#endif|);
}

sub escapeEnumLine($) {
    my $line = shift;

    $line =~ m|///<?| or die "escapeEnumLine: no comment|$line|";

    $line =~ m!(.*)(///<?)(.*)!;
    my $prefix         = $1;
    my $startOfComment = $2;
    my $comment        = $3;
    return $prefix . $startOfComment . escape($comment);
}

sub processMultilineEnum($$) {
    my $outputLinesRef = shift;
    my  $inputLinesRef = shift;

    defined $outputLinesRef           or
                          die "processMultilineEnum: undefined outputLinesRef";
    defined $inputLinesRef            or
                           die "processMultilineEnum: undefined inputLinesRef";
    isStartOfEnum @$inputLinesRef[ 0] or
                             die "processMultilineEnum: missing start-of-enum";
      isEndOfEnum $inputLinesRef->[-1] or
                               die "processMultilineEnum: missing end-of-enum";
    my $inputLinesCount = scalar @$inputLinesRef;
       $inputLinesCount > 1            or
                                   die "processMultilineEnum: has single line";

    debug "processMultilineEnum: enter: ". scalar @$inputLinesRef;

    my @classLevelDoc = ();
    my $i = 0;
    my $numLines = scalar @$inputLinesRef;
    for ($i = 1; $i < $numLines; ++$i) {
        my $line = @$inputLinesRef[$i];
        if (isCommentOnlyLine $line) {
            push @classLevelDoc, $line;
        } else {
            last;
        }
    }

    my @processedClassLeveDoc = map { s|//|///|; escapeEnumLine("$_"); }
                                @classLevelDoc;
    push @$outputLinesRef, @processedClassLeveDoc;
    push @$outputLinesRef, @$inputLinesRef[0];

    my $state          = 0;
    my $commentStarted = 0;
    for (; $i < $numLines - 1; ++$i) {
        my $line = @$inputLinesRef[$i];

        if (isEnumPassthroughLine $line) {       
            push  @$outputLinesRef, $line;
            next;
        }


        if (1 == $state and isCommentOnlyLine($line)) {
            if ($commentStarted) {
                $line =~ s|//|///|;
            } else {
                $line =~ s|//|///<|;
                $commentStarted = 1;
            }
            push  @$outputLinesRef, escapeEnumLine($line);
            next;
        }

        if (0 == $state and isEnumElementLine($line)) {
            $state = 1;
            if (hasComment($line)) {
                $line =~ s|//|///<|;
                $commentStarted = 1;
                push  @$outputLinesRef, escapeEnumLine($line);

            } else {
                push  @$outputLinesRef, $line;

            }
            next;
        }

        if (1 == $state and isEmptyLine($line)) {
            $state          = 0;
            $commentStarted = 0;
            push  @$outputLinesRef, $line;
            next;
        }

        if (1 == $state and isEnumElementLine($line)) {
            $commentStarted = 0;
            $state = 1;
             if (hasComment($line)) {
                 $line =~ s|//|///<|;
                 $commentStarted = 1;
                 push  @$outputLinesRef,  escapeEnumLine($line);
             } else {
                 push  @$outputLinesRef, $line;
             }
             next;
        }

        #default
        push  @$outputLinesRef, $line;
        next;
    }
    
    push @$outputLinesRef,  @$inputLinesRef[-1];

    @$outputLinesRef = map { "$_\n";} @$outputLinesRef;

    my $outputLinesCount = scalar @$outputLinesRef;

    $inputLinesCount == $outputLinesCount or
         die "processMultilineEnum: unequal counts: "
           .   "input=$inputLinesCount "
           . "output=$outputLinesCount";
    
    debug "processMultilineEnum: leave";
}

#==============================================================================

=head2 bde2doxygen($lines_aref,$filename)

Process the file contents represented by the array reference of strings passed
as the first argument, converting BDE-style documentation into Doxygen format.
The name of the file to which the content belongs is passed as the second
argument. Returns a new array reference containing the processed string. Parse
errors are emitted as warnings to standard error.

=cut

sub bde2doxygen($$) {


    my ($linesref, $filename) = @_;

    resetstate(); # the previous file isn't guaranteed to leave the stack clean
    resetlines(); # clear out the line store
    resetheaders(); # start new list of headers for this file
    resetTagDefs(); # start a new set of tags for this file

    # add in the double slashes for *.txt files
    my $prepend = (($filename =~ m/\.txt$/) ? "//" : undef);
    $filename=~/^([^.]+)\./;
    my $memberPrefix = $1 || $filename;
    my $component    = $memberPrefix; # or 'pkg.txt' or 'pgkgrp.txt'.

    initGroupInfo($component);

    my @class_decl;
    my $TOClocation = undef;

    pushline("/** \\file $component.h */");
    my $group_level = getLevelOfAggregation();
    my @groups      = getGroups();
    my $g_noplus = $groups[$group_level];
    $g_noplus =~ s!\+!_P_!g;
    my $groupName = $groups[$group_level];
    my $levelName = getLevelName($group_level, $groupName);
    pushline("/** \\defgroup $g_noplus"
           . " $levelName $groupName */");
    my $defgroupLineNum = getlinecount();  #new

    pushline("");

    my $pending_header;     # there *might* be a /// ------ line coming.
    my $ispending = 0;      # is there a header pending?

    my @listLinesIn  = ();
    my @nestingLevels = (); # Curly-brace levels of nested classes/functions

    setLinesRef($linesref);
    my $lno = lineNum();
    for (my $line; defined($line = getNextLine()); ) {

        $lno = lineNum();
        $line =~ s/^/$prepend/ if defined($prepend);

        next if isAspectsBanner($line);

        if (minorstate()==LIST_BLOCK) {
            if (isListMarkup($line)) {
                push @listLinesIn, $line;
                next;
            } else {
                popstate();

                my @listLinesOut = ();
                processList(\@listLinesOut, \@listLinesIn);

                for my $listLineOut (@listLinesOut) {
                    pushline($listLineOut);
                }

                #Fall through for processing of current line.
            }
        } else {
            if (isListMarkup($line)) {
                pushstate(majorstate(),LIST_BLOCK);
                @listLinesIn = ();
                push @listLinesIn, $line;
                next;
            }
        }

        #last if $line =~ m|INLINE|; # This is too hasty; terminates on com.
        if (majorstate() != INTRO && $line =~ m|INLINE|) {
            for (my $i = 0; $i < $namespaceStack; ++$i) {
                pushline("}");
            }

            last;
        }

        # parse and verify filename on line 1
        if ($lno == 1) {
            if ($line =~ m|^//\s*([\w+]+)|) {
                my $c_component = $1;
                warning "$filename: line 1 comment ($c_component) ".
                  "does not match file name"
                    if $c_component ne $component;
            } else {
                warning "$filename: #1 comment not found";
            }
            next;
        }

        # never stay in group declaration for #includes
        closeGroups()  if ($line =~ m|^\s*#\s*include|);

        # INTRO - starts with PURPOSE
        if ($line =~ m|^//\@PURPOSE:?|) {
            # don't know why we're not in COMMENT.
            if (minorstate() == COMMENT) {
                pushline(" */");
                popstate();
            }
            openGroups(1);
            $TOClocation = getlinecount() + 1;
            pushheader(1, "Purpose");
            $line =~ s|^//\@PURPOSE:?\s*||;
            warning "$filename: PURPOSE: not completed!" if $line =~ m/^$/;
            my $purpose = $line;
            pushline(" * ".escape($line));
            pushstate(INTRO,NOSTATE);

           #Now, adorn the 'defgroup' line title with purpose.
           my $defgroupLine = getline($defgroupLineNum);
           $defgroupLine =~ s| \*/$||;
           $defgroupLine .= "\n";
           $defgroupLine .= "\\brief ";
           $defgroupLine .= escape($purpose);
           $defgroupLine .= "\n";
           my $fileRefName = $filename;  $fileRefName =~ s/\.txt$/.h/;
           $defgroupLine .= "\\file $fileRefName\n";
           $defgroupLine .= "\\brief ";
           $defgroupLine .= escape($purpose);
           $defgroupLine .= "\n";
           $defgroupLine .= "*/";
           setline($defgroupLineNum, $defgroupLine);

            next;
        }

        # INTRO
        if (majorstate() == INTRO) {

            # @CLASSES
            if ($line =~ s|^//\@CLASS(?:ES)?:?||) {
                pushheader(1, "Classes");
                $line =~ s/^\s*//;
                pushstate(INTRO,CLASSES);
                @classesList = ();
                %classesInfo = ();
                next;
            }
            # @MACROS
            if ($line =~ s|^//\@MACRO(?:S)?:?||) {
                pushheader(1, "Macros");
                $line =~ s/^\s*//;
                pushstate(INTRO,CLASSES);  #format the same as @CLASSES
                @classesList = ();
                %classesInfo = ();
                next;
            }
            # @COMPONENTS
            if ($line =~ s|^//\@COMPONENT(?:S)?:?||) {
                pushheader(1, "Components");
                pushline(" * \\par ".escape($line));
                pushstate(INTRO,CLASSES);
                next;
            }
            # @PACKAGES
            if ($line =~ s|^//\@PACKAGE(?:S)?:?||) {
                pushheader(1, "Packages");
                pushline(" * \\par ".escape($line));
                pushstate(INTRO,CLASSES);
                next;
            }
            # inside @CLASSES, @COMPONENTS, or @PACKAGES:
            if (minorstate() == CLASSES) {

               if ($line =~ m|^// *(\S+.*) *: +(.*)|) {
                    my $className = $1;
                    my $classDesc = $2;
                    push (@classesList, $className);
                    $classesInfo{$className} = $classDesc;
                    next;
                }
                else {
                    if (scalar(@classesList) > 0) {
                        pushline(" * <table>");
                        for my $className (@classesList) {
                             my $info = $classesInfo{$className};
                             pushline(" * <tr>");
                             pushline(" * <td>" . $className.     "</td>");
                             pushline(" * <td>" . escape($info) . "</td>");
                             pushline(" * </tr>");
                        }
                        pushline(" * </table>");
                    }
                    popstate();
                }
            }

            # AUTHOR
            if ($line =~ s|^//\@AUTHOR:?||o) {
                pushline(" * \\author".escape($line));
                pushline(" * \\par");
                next;
            }

            # SEE_ALSO
            if ($line =~ s|^//\@SEE[_ ]*ALSO:?||o) {
                pushline(" * \\sa".escape($line));
                next;
            }

            # CONTACT
            if ($line =~ s|^//\@CONTACT:?||o) {
                pushline(" * \\note Contact:".escape($line));
                next;
            }
            # LAST_MODIFIED
            if ($line =~ s|^//\@LAST[_ ]*MODIFIED:?||o) {
                pushline(" * \\note Last-Modified:".escape($line));
                next;
            }
            # DEPRECATED
            if ($line =~ s|^//\@DEPRECATED:?||o
             || $line =~ s|^//\@INTERNAL_DEPRECATED:?||o) {
                pushline(" * \\deprecated ".escape($line));
                next;
            }

            # DESCRIPTION
            if ($line =~ s|^//\@DESCRIPTION:?||o) {
                pushheader(1,"Description");
                pushline(" * ".escape($line));
                popstate();
                pushstate(INTRO,DESC);
                next;
            }

            if (minorstate()==PREFORM) {
                if ($line =~ m|^//\.\.|o) {
                    pushline("\\endcode${BR}");
                    popstate();
                    next;
                }
                if ($line =~ m|^//|o) {
                    $line =~ s|^//||o;
                    pushline(escapePreform($line));
                    next;
                }
                # not a comment; it must be *real* code.
                popstate();
                pushline("\\endcode${BR}");
                warning "$filename#$lno: code block not terminated";
                # fall through
            }

            if (minorstate()==NOSTATE or minorstate()==DESC) {

                my $fallthrough = 0;
                if ($ispending) {
                    $ispending = 0;
                    if ($line =~ m|^///\s*([-=]\s*[-=])|) {
                        # header level is 2 + num spaces btw [-=] chars
                        pushheader(length($1),$pending_header);
                        next;
                    } else {
                        pushheader(2,$pending_header);
                        # fall through; this line didn't match
                    }
                }
                # Header at some level
                if ($line =~ m|^///\s*[\w"'\*\_\!]|) {
                    $line =~ s|^///\s*||;
                    $ispending = 1;
                    $pending_header = $line;
                    # pushline(" * \\par ".escape($line));
                } elsif ($line =~ m|^//\.\.|) {
                    pushstate(INTRO,PREFORM);
                    pushline("${BR}\\code");
                } elsif ($line =~
                         m|^//\s*[\w\\&'"~(*!{}\[\]^\.\$=?:<>\|+-]| ) {
                    # most common lines -- DCL What is the prev RE???
                    $line =~ s|^//\s*||o;
                    pushline(" * ".escape($line));
                } elsif ($line =~ m|^//\s+/|o) {
                    # special case: // /+ is distinct from ///+
                    $line =~ s|^//||o;
                    pushline(" *".escape($line));
                } elsif ($line =~ m|^//\s+\.[^.]|o) {
                    # special case: // . is distinct from //..
                    $line =~ s|^//||o;
                    pushline(" *".escape($line));
                } elsif ($line =~ m|^//\s*$|o) {
                    pushline(" * \\par ");
                } elsif ($line !~ m|^//|o) {
                    # no comment - must be code.
                    popstate();
                    pushline(" */");
                    closeGroups();
                    $fallthrough = 1;
                } elsif ($line =~ s|^//@\s*(.*):?\s*$||) {
                    pushheader(1, $1);
                    pushline(" * \\par");
                    pushline(" * ".escape($line));
                    next;
                } else {
                    warning "$filename: ".
                      "Don't know what to do with line $lno: $line";
                }

                next if not $fallthrough;
            }
        }

        # ----------- code -----------
        #

        if ($line =~ m[^\s*//!]) { # Comment denoting use of default method.
            $line =~ s|//!|   |;   # Let doxygen process as if declared.
            $line =~ s|\s*=\s*default||; # Strip; confuses 'doxygen'.
        }

        if ($line =~ s|\s*// IMPLICIT$|| # Strip; confuses 'doxygen'.
        or  $line =~ s|\s*// IMPLICIT[^:]||) {
         
            #Re-create at front of function-level doc.

            my $implicitLine = "// IMPLICIT:";  # Need ':'. (All caps eaten??)
            insertLine $implicitLine;
        }

        if (minorstate()==MACRO) {
            pushline($line);
            if ($line !~ m|\\$|) {
                # end of macro
                popstate();
            }
            next;
        }

        if ($line !~ m[^\s*//]) {
            if (minorstate()==COMMENT) {
                # safety check, just to make sure that we end any comment.
                pushline(" */");
                popstate();
            }
            if (minorstate()==PROTOTYPE && $line =~ m[^\s*{]) {
                # Start of function body (end of prototype).  Consume and
                # output entire function body with no further processing.

                # Compute curly-brace depth before start of function
                my $startDepth = curlyBraceDepth() - countCurlies($line);

                # Consume lines until curly-brace depth is the same as before
                # start of function.
                #
                # TBD: We discard comment lines in order to be compatable with
                # previous versions of this script.  We could actually discard
                # the entire function body, since we don't put any Doxygen
                # annotations there.
                while (curlyBraceDepth() > $startDepth) {
                    pushline($line) unless ($line =~ m|^\s*//|);
                    $line = getNextLine();
                }
                pushline($line);

                $lno = lineNum();
                warning "$filename#$lno: too many closing curly braces"
                    if (curlyBraceDepth() < $startDepth);

                popstate();
                next;
            }
            if (minorstate()==CLASSHEAD && $class_decl[-1] =~ m|{|) {
                # End of class head.  The current line is not part of the
                # class head.  Unget line and end the interior states, then
                # loop back and re-process the current line.
                ungetLine();
                while (minorstate()!=NOSTATE) {
                    if (minorstate()==CLASSHEAD) {
                        # push out a held-back class declaration
                        pushline(pop @class_decl);
                    }
                    popstate();
                }

                # Record the curly-brace depth at the start of the class
                push @nestingLevels, curlyBraceDepth();

                next;
            }
        }

        # Use namespace BloombergLP as a guard for bde groups
        # But remove the namespace for clarity
        if ($line =~ m[^namespace\s+BloombergLP\s*{]) {
            openGroups(0);
            next;
        }
        if ($line =~ m[^}\s*//\s*[a-z]*\s*namespace\s*BloombergLP]) {
            closeGroups();
            next;
        }
        if ($line =~ m[^}\s*//\s*[a-z]*\s*namespace\s*]) {
            --$namespaceStack;
        }
        if ($line =~ m|^namespace\s+\w+\s*{[^}]*$|) {
            ++$namespaceStack;
        }

        if ($line =~ m!^\s*(template|class|struct|union|enum)\s*!o ) {
            openGroups(0) unless ($line =~ m|;| );
        }

        if ($line =~ m|^\s*template\s*<|) {
            # Template declaration.  Consume up until closing '>'
            while ($line !~ m|^.*>\s*(\w+.*)?$|) {
                pushline($line);
                $line = getNextLine();
            }
            # Split line after the closing '>'
            $line =~ m!(^.*>)\s*(\w+.*|)$!;
            my $templatepart = $1;
            $line = $2;
            pushline($templatepart);

            # Go to next input line if this line was entirely consumed.
            # Otherwise, keep processing the remainder of the line.
            next unless ($line);
        }

        ### start of enum
        if (isStartOfEnum $line) {
            my @rawEnumLines = ();
            push @rawEnumLines, $line;
            for (my $enumLine; defined($enumLine = getNextLine()); ) {
                push @rawEnumLines, $enumLine;
                last if isEndOfEnum $enumLine;
            }
            my @processedEnumLines = ();
            processMultilineEnum(\@processedEnumLines, \@rawEnumLines);
            chomp @processedEnumLines;
            pushline $_ foreach(@processedEnumLines);
            next;
        }
        ### end of enum (above)

        ### start of class or enum
        if ($line =~ m!^\s*(class|struct|union)\s*(\w*)
                       \s*(<[^>]*>)?(?:[^{;]*{.*}\s*\w*)?(;?)!x) {

            $templateQualifier = $3 || "";
            my $lineTerminator = $4;

            # non-comment line: terminate existing comment
            if (minorstate()==COMMENT) {
                pushline(" */");
                popstate();
                pushline("");
            }

            # No special processing for forward or one-line declarations of
            # classes or enums.
            if ($lineTerminator eq ";") {
                pushline($line);
                next;
            }

            openGroups(0);
            # not currently used because Doxygen doesn't allow a space in
            # specified classnames (like for instance in a specialised
            # template class). Retained until this is a solvable problem.

            $entityType        = $1;
            $classname         = $2;

            # enter class state
            pushstate(CLASS,NOSTATE);

            # enter class head state
            pushstate(CLASS,CLASSHEAD);

            # Save the actual code line to place it after the class comment.
            # Doxygen doesn't grok the class docs being *inside* the class as
            # BDE has it. Neither can we use the 'class' special command as
            # it doesn't work for template specialisations including spaces in
            # the classname (as in: 'template<> class foobar<void *>'.
            # In fact this causes the comment to end up between the template
            # and the class in cases where they appear on seperate lines,
            # but Doxygen appears not to care. However lines following
            # the class/struct are handled - see 'multi-line class head' below.
            push @class_decl, $line;
            next;
        }

        ### class body
        if (majorstate()==CLASS or majorstate()==NOSTATE) {

            if (minorstate()==CLASSHEAD and $class_decl[-1] !~ m|{|) {
                # multi-line class head
                $class_decl[-1].="\n$line";
            } elsif ( $line =~ m|\s+//\s*=+\s*$|o ) {
                # beginning or end of a centred title (ignore)
                if (minorstate()==TITLE) {
                    popstate();
                } else {
                    pushstate(majorstate,TITLE);
                }
                # ignore
            } elsif (minorstate()==TITLE) {
                # ignore - interior of centred title
            } elsif ($line =~ m|^ *//[ A-Z]+$|
                 ||  $line =~ m|\/\/ \*\*\* .* \*\*\*$|) {
                # ignore - one line titles (e.g., "CREATORS", "ACCESSORS")
                #          and "banners"
            } elsif ($line =~ m|//\s*=+\s*$|) {
                # ignore - generic underlines
            } elsif ($line =~ m|^\s*$|) {
                # blank line ends all interior states
                if (minorstate()==PREFORM) {
                    pushline("\\endcode${BR}");
                    popstate();
                    warning "$filename#$lno: code block not terminated";
                }
                if (minorstate()==COMMENT) {
                    pushline(" */");
                    popstate();
                }
                # if we were in a PROTOTYPE/CLASSHEAD we're not now
                while (minorstate()!=NOSTATE) {
                    if (minorstate()==CLASSHEAD) {
                        # push out a held-back class declaration
                        pushline(pop @class_decl);
                    }
                    popstate();
                }
                pushline("");
            } elsif (majorstate() == CLASS and
                     $line =~ m|^\s*};| and
                     curlyBraceDepth() < $nestingLevels[-1]) {
                # end of multi-line class body
                # note this does *not* detect one-liner classes.
                if (minorstate()==PREFORM) {
                    pushline("\\endcode${BR}");
                    popstate();
                    warning "$filename#$lno: code block not terminated";
                }
                if (minorstate()==COMMENT) {
                    pushline(" */");
                    popstate();
                }
                if (minorstate()==PROTOTYPE) {
                    #proto before comment
                    popstate();
                } elsif (minorstate()==CLASSHEAD) {
                    #class doc
                    popstate();
                    pushline(pop @class_decl);
                }
                pushline($line);
                pop @nestingLevels;
                popstate(); #end of class
#            } elsif ($line =~ m|//| and
#                     ($line =~ m[MANIP|ACCES|OPERATOR])) {
#                # convert titles we don't want to ignore
#                $line =~ s|//||o;
#                pushline("/** \\par ".escape($line)." */");
#                pushline("");
            } elsif ($line =~ m|^\s*\#\s*define|) {
                # Macro
                if (minorstate()==COMMENT) {
                    pushline(" */");
                    popstate();
                }
                if ($line =~ m|\\$| and minorstate != MACRO) {
                    pushstate(majorstate,MACRO);
                }
                pushline($line);
            } elsif ($line !~ m|//| and $line =~ m|\(|) {
                # function prototype
                if (minorstate()==COMMENT) {
                    pushline(" */");
                    popstate();
                }
                pushstate(majorstate,PROTOTYPE) unless minorstate==PROTOTYPE;
                pushline($line);
            } elsif (isCommentLine($line) and CLASSHEAD == minorstate()) {
                # comment immediately folllowing class head
                pushline("/*!");
                my $classBriefDesc = getClassBriefDesc($classname,
                                                       $templateQualifier);
                if ($classBriefDesc) {
                    pushline(" * \\brief " . escape($classBriefDesc));
                    pushline(" *");
                }

                ungetLine();
                processCommentBlock(1);
                next;
            } elsif (isCommentLine($line) and PROTOTYPE == minorstate()) {
                # comment immediately folllowing prototype
                ungetLine();
                processCommentBlock(0);
                next;
            } elsif ($line =~ m|^\s*//|) {
                # regular comment or preformatted text
                $line=~s/\bBUG\b/\bug/g;
                if ($line =~ m|^\s*//\.\.|) {
                    if (minorstate()==COMMENT) {
                        pushstate(majorstate,PREFORM);
                        pushline("${BR}\\code");
                    } elsif (minorstate()==PREFORM) {
                        pushline("\\endcode${BR}");
                        popstate();
                    }
                } else {
                    if (majorstate() != NOSTATE) {
                        unless (minorstate()==COMMENT
                                or minorstate()==PREFORM) {
                            pushstate(majorstate,COMMENT);

                            # pushline("/*!");
                            # pushline("/*!<");
                            pushline("/*");     # PGH prevent weird artifacts
                        }
                        $line =~ s|//||o;
                        if (minorstate()==PREFORM) {
                            pushline(escapePreform($line)); #noesc # yesesc, actually.
                        } else {
                            pushline(" *".escape($line));
                        }
                    }
                }
            } elsif ($line !~ m|^\s*//| and minorstate()==PREFORM) {
                # end of comments, in PREFORM block (abnormal termination)
                warning "$filename#$lno: code block not terminated";
                pushline("\\endcode${BR}");
                pushline(" */");
                pushline($line); #noesc
                popstate();        # PREFORM->COMMENT
                popstate();        # COMMENT->PROTOTYPE|NOSTATE
                if (minorstate()==PROTOTYPE) {
                    #proto before comment
                    popstate();
                } elsif (minorstate()==CLASSHEAD) {
                    #class doc
                    popstate();
                    pushline(pop @class_decl);
                }
                warning "$filename#$lno: code block not terminated";
            } elsif ($line !~ m|^\s*//| and minorstate()==COMMENT) {
                # end of comments
                pushline(" */");
                popstate();
                #popstate() if minorstate==PROTOTYPE; #proto before comment
                if (minorstate()==PROTOTYPE) {
                    #proto before comment
                    popstate();
                } elsif (minorstate()==CLASSHEAD) {
                    #class doc
                    popstate();
                    pushline(pop @class_decl);
                }
                pushline($line); #noesc
            } elsif ($line =~ m|^(\s*\w+.*)//(.*)$|) {
                # comment following code
                my ($before,$after)=($1,$2);
                pushline("/*! ".escape($after)." */");
                pushline($before);
            } else {
                pushline($line);
            }
            next;
        }

        #pushline($line);  #no longer output by default
    }                                # for my $line...

    if (minorstate()==LIST_BLOCK) { #list-block ran to end of file
        popstate();

        my @listLinesOut = ();
        processList(\@listLinesOut, \@listLinesIn);

        for my $listLineOut (@listLinesOut) {
            pushline($listLineOut);
        }
    }

    if (minorstate()==PREFORM) {
        pushline("\\endcode${BR}");
        popstate();
        warning "$filename#$lno: code block not terminated";
    }
    if (majorstate()==INTRO) {
        pushline(" */");
        popstate();
    }
    if (minorstate()==COMMENT) {
        pushline(" */");
        popstate();
    }
    pushline("");
    closeGroups();
    insertLinks();
    # If there's a Purpose, we can place a TOC.
    insertTOC(getlines(),$TOClocation) if defined($TOClocation);

    return getlines();
}

#==============================================================================

1;
