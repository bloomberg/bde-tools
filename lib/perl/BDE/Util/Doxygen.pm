package BDE::Util::Doxygen;
use strict;

use base 'Exporter';
use vars qw(@EXPORT_OK);
@EXPORT_OK=qw(bde2doxygen);

use Util::Message qw(warning);
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
          " * <UL>",
          " * </UL>",
          " * <LI>",
          " * </LI>",
          " *",
          " *"
        ],
    LIST_TYPE_Numbered, [
          " * <OL>",
          " * </OL>",
          " * <LI>",
          " * </LI>",
          " *",
          " *"
        ],
    LIST_TYPE_Hanging, [ 
          ' * <DIV class="hanging">',
          " * \\par\n * </DIV>",
          " * \\par",
          " *",
          " * \\par\n * <DIV class=\"unhanging\">",
          " * \\par\n * </DIV>"
        ]
);

#------------------------------------------------------------------------------
# Predefined regex patterns
#------------------------------------------------------------------------------
my $listMarker     = qr "^ *//:";
my $ulToken        = qr " [o\*] ";
my $nlToken        = qr "[1-9][0-9]*[.)]? ";
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
            next if exists $tagDefs{$tag}; # Avoid duplicate tags
            push @$lines, ' * <A NAME="'.$tag.'"></A>';
            $tagDefs{$tag} = 1;
        }
    }

    sub tagExists($)
    {
        my $tag = shift;
        return exists $tagDefs{$tag};
    }

} # end tags closure

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

    # Remove formatting characters
    $result =~ s{((\s|>|^)[\{(*!_]*)\'([^']+)\'}{$1$3}g;
    $result =~ s{((\s|>|^)[\{(!_']*)\*(\S[^*]+)(?<!\s)\*}{$1$3}g;
    $result =~ s{((\s|>|^)[\{(*_']*)\!(\S[^!]+)(?<!\s)\!}{$1$3}g;
    $result =~ s{((\s|>|^)[\{(*!']*)\_(\S[^_]+)(?<!\s)\_}{$1$3}g;

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

# Return a list of lines to be emited at the end of a list.
# Usage: my @end = listEnd($listType);
sub listEnd($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[1];
}

# Return a list of lines to be emited before each list item.
# Usage: my @start = listItemStart($listType);
sub listItemStart($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[2];
}

# Return a list of lines to be emited after each list item.
# Usage: my @end = listItemEnd($listType);
sub listItemEnd($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[3];
}

# Return a list of lines to be emited before begining a nested list.
# Usage: my @start = listStartNested($listType);
sub listStartNested($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[4];
}

# Return a list of lines to be emited after ending a nested list.
# Usage: my @end = listEndNested($listType);
sub listEndNested($) {
    my $listType = shift;
    return split /\n/, $listTypeToEmittedLines{$listType}->[5];
}

sub processList(\@\@);  #forward declaration (of recursive function).
sub processList(\@\@)
{
    my $listLines = shift;
    my $ar        = shift;

    my $line = shift @$ar;
    $line =~ $listItem or die "not a list item: $line";
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
    my $withinItem = 1;

    while ($line = shift @$ar) {
        if ($withinItem &&
            isListItemContinuation($line, $givenListLevel, $givenListType)) {
            $line =~ s|$listItemIndent||;
            push @$listLines, " * " . escape($line);
            next;
        } elsif ($line =~ $listItem) {
            my ($listLevel, $listType, $listToken) = listItemInfo($line);
            #print "SRB: $givenListLevel: $listLevel: $line\n";

            if ($listLevel > $givenListLevel) {
                push @$listLines, listStartNested($givenListType);
                unshift @$ar, $line;
                $line = processList(@$listLines, @$ar);
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
                    pushTagDefs($listLines, $glossaryRef,
                                getSectionTags($glossaryRef));
                    $line =~ s{$glossaryToken}{ *$1*$2};  # Italicize term
                }
                $line =~ s|$listItemPrefix||;
                push @$listLines, " * " . escape($line);
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


my %stateToAscii = (
    NOSTATE,        "NOSTATE",
    INTRO,          "INTRO",
    CLASS,          "CLASS",
    CLASSES,        "CLASSES",
    DESC,           "DESC",
    CLASSHEAD,      "CLASSHEAD",
    PROTOTYPE,      "PROTOTYPE",
    COMMENT,        "COMMENT",
    PREFORM,        "PREFORM",
    TITLE,          "TITLE",
    CLASSES_BULLET, "CLASSES_BULLET",
    LIST_BLOCK,     "LIST_BLOCK",
);

sub stateToAscii($)
{
    my $state = shift;
    return $stateToAscii{$state};
}

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

{ # line store closure

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
    sub popline () {
        return pop @lines;
    }

    # retrieve processed output
    sub getlines () {
        return \@lines;
    }

    # retrieve current line count
    sub getlinecount () {
        return $#lines;
    }
}

#------------------------------------------------------------------------------
# Group levels and names
#  Supporting three levels of nesting
use constant PACKAGE_GROUP => 0;
use constant PACKAGE       => 1;
use constant COMPONENT     => 2;
use constant MAX_GROUPS    => 3;
my @level_name = (
   "Package Group",
   "Package",
   "Component"
   );

{ # Groups closure
    # TODO: Need to provide a function to yield groupname without +
    #       And then use it to provide the "\defgroup" header
    #
    my @beginGroups;
    my @endGroups;
    my $inGroup = 0;

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
        return @ret;
    }
    # main working routine.
    # Note: $txt must not be escaped
    sub pushheader($$) {
        my ($level, $txt) = @_;
        $txt =~ s/:$//o;    # remove trailing colon from TOC entry
        my $txt_prefix = $txt;
        $txt_prefix =~ s/:\s.*$//;  # Remove anything after the first colon

        # Adjust TOC nesting for level
        while (@levels < $level) {
            push @levels, 0;
            push @seclinks, "";
            push @TOC_entries, " * <UL>";
        }
        while (@levels > $level) {
            pop @levels;
            pop @seclinks;
            push @TOC_entries, " * </UL>";
        }
        ++$levels[-1];  # Increment deepest level
        $seclinks[-1] = encodeUriFragment($txt_prefix);

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
    }
}
#------------------------------------------------------------------------------
# escape Doxygen-significant characters - use for comments only, not code.
# also, translate 'code', *italic*, and !bold! markers in the text. Italics
# include (*this* *text*) but not (*).  Similarly for bold.

sub escape ($) {
    my $string = shift;

    # escape characters that are meaningful to Doxygen
    $string=~s{([\@<>&\$#\\])}{\\$1}go if $string;

    # Note: - Funky multi-line substitution translates '*' to '\f' to avoid
    #         interpretation as italics. tr/// undoes this after italics are
    #         done. Similarly for '!' and '_'.
    my $t;
    $string =~ s{((?:\s|>|^)[\{(*!_]*)' ([^']+) '}
                 {   $t = "<code>$2</code>";
                     $t =~ tr|\*|\f|;
                     $t =~ tr|\!|\e|;
                     $t =~ tr|\_|\r|;
                     "$1$t"
                 }gexo;

     
    $string =~ s{((\s|>|^)[\{(!_']*)\*([^)* ][^*]+)(?<!\s)\*}{$1<em>$3</em>}g;
    $string =~ s{((\s|>|^)[\{(*_']*)\!([^)! ][^!]+)(?<!\s)\!}{$1<strong>$3</strong>}g;
    $string =~ s{((\s|>|^)[\{(*!']*)\_([^)_ ][^_]+)(?<!\s)\_}{$1<em>$3</em>}g;

    $string =~ tr[\f][\*];
    $string =~ tr[\e][\!];
    $string =~ tr[\r][\_];

#    if ($string =~ m|^//|) {
#        $string =~ s!/\*!|*!g;
#        $string =~ s!/*/!*|!g;
#    }
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




my $generalLink    = qr /{([^{} ][^{}]*)}/io;
my $glossaryLink   = qr /(\s)"([^"]+)"(\s+\(see\s+$generalLink\))/io;

sub splitLink($)
{
    my $link = shift;
    my @parts = split(/\|/, $link);

    # Prepend an empty document name if fewer than 2 parts
    unshift @parts, "" if (@parts < 2);

    $parts[1] = "" if $parts[1] eq '*';

    return @parts;
}

# Mangle a source filename into the form generated by Doxygen
sub doxygenizeFilename($)
{
    my $filename = shift;

    $filename =~ s/_/__/g;
    $filename =~ s/\./_8/g;
    $filename =~ s/:/_1/g;

    return "group__" . $filename;
}

sub documentToUriPath($)
{
    my $document = shift;

    return "" unless $document;

    if ($document =~ m{^\w{3}$})
    {
        # Package group
    }
    elsif ($document =~ m{^\w_\w+$|^\w{3}\w+$})
    {
        # Package
    }
    elsif ($document =~ m{^\w_\w+_\w+|^\w{3}\w+_\w+})
    {
        # Component
        $document .= ".h";
    }

    return doxygenizeFilename($document) . ".html";
}

# Replace each link of the form:
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
sub insertLinks()
{
    my $lines = getlines();
    for my $string (@$lines) {
        while ($string =~ m/$generalLink/g) {
            # Save pos so that next search will not start from the
            # begining:
            my $rawlink = $1;
            # $rawlinkstart and $rawlinklen include open and close curlies
            my $rawlinkstart = $-[1] - 1;
            my $rawlinklen   = $+[1] - $rawlinkstart + 1;

            next if ($rawlink =~ /\s$/);  # Skip if trailing whitespace
            my $link = unescape($rawlink);

            # Split document part from section within document
            my ($document, $section) = splitLink($link);
            my $sectionTag = encodeUriFragment($section);

            # Don't replace local link to non-existant tag
            next unless ($document || tagExists($sectionTag));

            my $linkPath = documentToUriPath($document);

            if ($string =~ $glossaryLink) {
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
            my $htmlref = "<A CLASS=\"el\" HREF=\"$linkUrl\">$rawlink</A>";
            substr($string, $rawlinkstart, $rawlinklen) = $htmlref;
        } # end while more links in line
    } # end for each string in lines
}

#==============================================================================

=head2 bde2doxygen($lines_aref,$filename)

Process the file contents represented by the array reference of strings passed
as the first argument, converting BDE-style documentation into Doxygen format.
The name of the file to which the content belongs is passed as the second
argument. Returns a new array reference containing the processed string. Parse
errors are emitted as warnings to standard error.

=cut

sub bde2doxygen ($$) {
    my ($linesref,$filename) = @_;

    # add in the double slashes for *.txt files
    my $prepend = (($filename =~ m/\.txt$/) ? "//" : undef);
    $filename=~/^([^.]+)\./;
    my $memberPrefix = $1 || $filename;
    my $component = $memberPrefix; #probably

    resetstate(); # the previous file isn't guaranteed to leave the stack clean
    resetlines(); # clear out the line store
    resetheaders(); # start new list of headers for this file
    my $TOClocation = undef;

    # derive package and package group from component
    my $package=getComponentPackage($component) || $component;
    my $package_group=getPackageGroup($package) || $package;

    my @groups = ( $package_group, $package, $component );

    # what group level are we at?
    my $group_level =   ($package_group eq $package && $package eq $component)
                      ? PACKAGE_GROUP
                      : ($package eq $component) ? PACKAGE : COMPONENT;
    setGroups($group_level,@groups);

    my ($classname,@class_decl);

    pushline("/** \\file $component.h */");
    my $g_noplus = $groups[$group_level];
    $g_noplus =~ s!\+!_P_!g;
    pushline("/** \\defgroup $g_noplus"
        . " $level_name[$group_level] $groups[$group_level] */");
    pushline("");

    my $lno = 0;            # line number
    my $pending_header;     # there *might* be a /// ------ line coming.
    my $ispending = 0;      # is there a header pending?

    my @listLinesIn  = ();

    for my $line (@$linesref) {
        $line =~ s/^/$prepend/ if defined($prepend);
        $lno++;
        #printf "kilroy: %d: %s, %s: %s\n",
        #        $lno,
        #        stateToAscii(majorstate()),
        #        stateToAscii(minorstate()),
        #        $line;

        #last if $line =~ m|INLINE|; # This is too hasty; terminates on com.
        if (majorstate() != INTRO && $line =~ m|INLINE|) {
            for (my $i = 0; $i < $namespaceStack; ++$i) {
                pushline("}");
            }

            last;
        }

        # parse and verify filename on line 1
        if ($lno == 1) {
            if ($line =~ m!^(//|/\*)\s*([\w+]+)!) {
                my $c_component = $2;
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
            pushline(" * ".escape($line));
            pushstate(INTRO,NOSTATE);
            next;
        }

        # INTRO
        if (majorstate() == INTRO) {

            # @CLASSES
            if ($line =~ s|^//\@CLASS(?:ES)?:?||) {
                pushheader(1, "Classes");
                pushline(" * <TABLE>");
                $line =~ s/^\s*//;
                if ($line) {
                     warn "misplaced class item ignored: $line";
#                    print "MATCH1: $line\n";
#                    $line =~ m|(.*): +(.*)|;
#                    my $className = defined($1) ? $1 : "TBD";
#                    my $classDesc = defined($2) ? $1 : "TBD";
#                    pushline(" * <TR>");
#                    pushline(" * <TD>");
#                    pushline(" * ".escape("'".$className."'"));
#                    pushline(" * </TD>");
#                    pushline(" * <TD>");
#                    pushline(" * ".escape($classDesc));
#                    pushline(" * </TD>");
#                    pushline(" * </TR>");
                }

                pushstate(INTRO,CLASSES);
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
                if ($line =~ m|^// *$|) {
                    my $previousLine = popline();
                    if ($previousLine eq " * <TABLE>") {
                        # don't restore; avoid empty table;
                    } else {
                        pushline($previousLine);
                        pushline(" * </TABLE>");
                    }
                    popstate();
                } else {
                    #print "CLASSES: $memberPrefix: $line\n";
                    #print "MATCH: $memberPrefix: $line\n";

                    #$line =~ s|^// *($memberPrefix.*:)|\*$1\*|;
                    #pushstate(INTRO,CLASSES_BULLET);
                    #pushline(" * - ".escape($line)); # first bullet

                    $line =~ s|^// *||;
                    $line =~ m|(.*): +(.*)|;
                    my $className = $1;
                    my $classDesc = $2;
                    pushline(" * <TR>");
                    pushline(" * <TD>");
                    pushline(" * ".escape("'".$className."'"));
                    pushline(" * </TD>");
                    pushline(" * <TD>");
                    pushline(" * ".escape($classDesc));
                    pushline(" * </TD>");
                    pushline(" * </TR>");

                    next;
                }
            }
            if (minorstate() == CLASSES_BULLET) {
                $line =~ s|^// *||o;
                if ($line =~ /\w/) {
                    if ($line =~ m/^$memberPrefix.*:/) {
                       $line =~ s/^($memberPrefix.*:)/\*$1\*/;
                       pushline(" * - ".escape($line)); # bullet
                    } else {
                       appendline(" ".escape($line)); # more bullet text
                    }
                } else {
                    pushline(" *");
                    popstate();    # CLASSES_BULLET
                    popstate();    # CLASSES
                }
                next;
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

            # MNEMONIC
            if ($line =~ s|^//\@MNEMONIC:?||o) {
                pushheader(1,"Mnemonic");
                pushline(" * ".escape($line));
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
            if ($line =~ s|^//\@DEPRECATED:?||o) {
                pushline(" * \\note DEPRECATED:".escape($line));
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
                    pushline($line);
                    next;
                }
                # not a comment; it must be *real* code.
                popstate();
                pushline("\\endcode${BR}");
                warning "$filename#$lno: code block not terminated";
                # fall through
            }

            if (minorstate()==LIST_BLOCK) {
                if (isListMarkup($line)) {
                    push @listLinesIn, $line;
                    next;
                } else {
                    popstate();

                    my @listLinesOut = ();
                    processList(@listLinesOut, @listLinesIn);

                    for my $listLineOut (@listLinesOut) {
                        pushline($listLineOut);
                    }

                    #Fall through for processing of current line.
                }
            }

            if (minorstate()==NOSTATE or minorstate()==DESC) {

                if (isListMarkup($line)) {
                    pushstate(INTRO,LIST_BLOCK);
                    @listLinesIn = ();
                    push @listLinesIn, $line;
                    next;
                }

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
                if ($line =~ m|^///\s*[\w"']|) {
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
        if ($line !~ m[^\s*//]) {
            # safety check, just to make sure
            if (minorstate()==COMMENT) {
                pushline(" */");
                popstate();
            }
            if (minorstate()==PROTOTYPE && $line =~ m[^\s*{]) {
                popstate();
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

        if ( $line =~ m!^\s*(template|class|struct|enum)\s*!o ) {
            openGroups(0) unless ($line =~ m|;| );
        }

        ### start of class or enum
        if ($line =~ m!^\s*(class|struct|enum)\s*(\S[^{;]*)(?:{.*})?(;?)!) {
            # non-comment line: terminate existing comment
            if (minorstate()==COMMENT) {
                pushline(" */");
                popstate();
                pushline("");
            }

            # No special processing for forward or one-line declarations of
            # classes or enums.
            if ($3 eq ";") {
                pushline($line);
                next;
            }

            openGroups(0);
            # not currently used because Doxygen doesn't allow a space in
            # specified classnames (like for instance in a specialised
            # template class). Retained until this is a solvable problem.
            $classname = $2;

            # enter class state
            pushstate(CLASS,NOSTATE);

            # enter class head state
            pushstate(CLASS,CLASSHEAD);

            # save the actual code line to place it after the class comment.
            # Doxygen doesn't grok the class docs being *inside* the class as
            # BDE has it. Neither can we use the 'class' special command as
            # it doesn't work for template specialisations including spaces in
            # the classname (as in: 'template<> class foobar<void *>'
            push @class_decl, $line;
            # in fact this causes the comment to end up between the template
            # and the class in cases where they appear on seperate lines,
            # but Doxygen appears not to care. However lines following
            # the class/struct are handled - see 'multi-line class head' below.
            next;
        }

        ### class body (or not!)
        if (majorstate()==CLASS or majorstate()==NOSTATE) {

            if (minorstate()==COMMENT && $line =~ m[^\s*//]) {
                $line =~ s|//||o;
                pushline(" *".escape($line));
                next;
            }

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
            #} elsif ($line =~ m|//| and $line =~ m|CREATOR|) {
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
            } elsif ($line =~ m|^\s*};|) {
                #print "MATCH: $lno\n";

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
                    popstate();
                } elsif (minorstate()==CLASSHEAD) {
                    #class doc
                    popstate();
                    pushline(pop @class_decl);
                }
                pushline($line);
                popstate(); #end of class
#            } elsif ($line =~ m|//| and
#                     ($line =~ m[MANIP|ACCES|OPERATOR])) {
#                # convert titles we don't want to ignore
#                $line =~ s|//||o;
#                pushline("/** \\par ".escape($line)." */");
#                pushline("");
            } elsif ($line !~ m|//| and $line =~ m|\(|) {
                # function prototype
                if (minorstate()==COMMENT) {
                    pushline(" */");
                    popstate();
                }
                pushstate(majorstate,PROTOTYPE) unless minorstate==PROTOTYPE;
                pushline($line);
            } elsif ($line =~ m|^\s*//| and
                     (minorstate()==PROTOTYPE or minorstate()==CLASSHEAD)) {
                # comment immediately following prototype or class head
                if (minorstate()==CLASSHEAD) {
                    pushline("/*!");
                } else {
                    pushline("/*!<");
                }
                pushstate(majorstate,COMMENT);
                $line =~ s|//||;
                pushline(" *".escape($line));
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

                            #printf "KILROY: %s: %d: %s, %s\n",
                            #       $filename,
                            #       $lno,
                            #       stateToAscii(majorstate()),
                            #       stateToAscii(minorstate());
                            pushstate(majorstate,COMMENT);
                            #pushline("/*!");
                            #pushline("KILROY WAS HERE: $lno:|$line|");
                            #pushline("/*!<");  #SRB EXPER
                            pushline("/*");     #PGH prevent weird artifacts
                        }
                        $line =~ s|//||o;
                        if (minorstate()==PREFORM) {
                            pushline($line); #noesc
                        } else {
                            pushline(" *".escape($line));
                        }
                    }
                }
            } elsif ($line !~ m|^\s*//| and minorstate()==PREFORM) {
                # end of comments, in PREFORM block (abnormal termination)
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

        #pushline($line);  #SRB EXPERIMENT; Do not output as default;
    }                                # for my $line...

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
