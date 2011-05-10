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
    LIST_TYPE_Numbered     => 2
};

my %listTypeToAscii = (
    LIST_TYPE_Unordered, "Unordered",
    LIST_TYPE_Numbered,  "Numbered"
);

#------------------------------------------------------------------------------
# Predefined regex patterns
#------------------------------------------------------------------------------
my $listMarker   = qr "^ *//:";
my $ulToken      = qr "[o\*] ";
my $nlToken      = qr "[1-9][0-9]* ";
my $ulListItem   = qr "$listMarker ((?:  )*)($ulToken)";
my $listItem     = qr "$listMarker ((?:  )*)($ulToken|$nlToken)";
my $listItemText = qr "$listMarker( *)\S+";  # NOTE: matches tokens
#my $listItemCont = qr "$listMarker(  )+( )(\S+)";
my $listItemCont = qr "$listMarker ((?:  )+)(\S+)";
my $listItemTerm = qr "$listMarker *$";

#------------------------------------------------------------------------------
# Global Data
#------------------------------------------------------------------------------

my @listLinesIn  = ();
my @listLinesOut = ();

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

sub isListItemCont($)
{
    my $line = shift;
    return $line =~ $listItemText
        && $line !~ $listItem;
}

sub isListMarkup($)
{
    my $line = shift;
    return $line =~ $listMarker;
}

sub listItemInfo($) {
    my $line = shift;

    $line =~ m|$listItem|;
    my $listLevel = 1 + (length($1) / 2);
    my $listType  = ($line =~ $ulListItem)
                  ? LIST_TYPE_Unordered
                  : LIST_TYPE_Numbered;
    return ($listLevel, $listType);
}

sub levelOfCont($)
{
    my $line = shift;
    $line =~ m|$listItemCont|;
    return (length($1) / 2);
}

sub listStart($) {
    my $listType = shift;
    return $listType == LIST_TYPE_Unordered ? "<ul>" : "<ol>";
}

sub listEnd($) {
    my $listType = shift;
    return $listType == LIST_TYPE_Unordered ? "</ul>" : "</ol>";
}

sub processList($$);  #forward declaration (of recursive function).
sub processList($$)
{
    my $listLines = shift;
    my $ar        = shift;

    my $line = shift @$ar;
    $line =~ $listItem or die "not a list item: $line";
    my ($givenListLevel, $givenListType) = listItemInfo($line);

    push @$listLines, " * " . listStart($givenListType);
    push @$listLines, " * " . "<li>";
    $line =~ s|$listItem||;
    push @$listLines, " * " . escape($line);

    while ($line = shift @$ar) {

        if ($line =~ $listItem) {
            my ($listLevel, $listType) = listItemInfo($line);
            #print "SRB: $givenListLevel: $listLevel: $line\n";

            if      ($listLevel > $givenListLevel) {
                unshift @$ar, $line;
                $line = processList($listLines, $ar);
                unshift @$ar, $line;
                next;
            } elsif ($listLevel < $givenListLevel) {
                push @$listLines, " * " . "</li>";
                push @$listLines, " * " . listEnd($givenListType);
                return $line;
            } else {
                push @$listLines, " * " . "</li>";
                push @$listLines, " * " . "<li>";
                $line =~ s|$listItem||;
                push @$listLines, " * " . escape($line);
                next;
            }
        } elsif (isListItemCont($line)) {
            my $listLevel = levelOfCont($line);
            print "srb: $givenListLevel: $listLevel: $line\n";
            if ($listLevel > $givenListLevel) {
                push @$listLines, " * " . "</LI>";
                push @$listLines, " * " . listEnd($givenListType);
                return $line;
            }
            $line =~ s|$listItemCont|$2|;
            push @$listLines, " * " . escape($line);
            next;
        } elsif ($line =~ $listMarker) {
            $line =~ s|$listItemTerm||;
            push @$listLines, " * " . escape($line);
            next;
        } else {
            push @$listLines, " * " . "</li>";
            push @$listLines, " * " . listEnd($givenListType);
            return $line;
        }
    }

    push @$listLines, " * " . "</li>";
    push @$listLines, " * " . listEnd($givenListType);
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
    use constant MAXHEADERLEVELS => 6;
    my @headers;
    my @levels;
    my $nheaders = 0;
    my $prevlevel = 0;

    # increment level count and return tag for this level
    sub getTag($) {
        my $hlev = shift;
        $hlev --;  # caller is 1-indexed
        $levels[$hlev] ++;
        my $tag = join('.',@levels[0..$hlev]);
        $hlev ++;
        while ($hlev < MAXHEADERLEVELS) {
            $levels[$hlev] = 0;
            $hlev++;
        }
        return $tag;
    }
    # main working routine
    sub pushheader($$) {
        my ($level, $txt) = @_;
        my $dashes="------";   # need MAXHEADERLEVELS dashes

        ++ $nheaders;
        my $tag = getTag($level);
        pushline(" * \\par");
        pushline(" * <A NAME=\"$tag\"> \\par $txt </A>");
        pushline(" * \\par");
        #my $tag = "$nheaders.$level";
        #pushline(" * \\htmlonly");
        #if ($level <= 3)    {
        #    my $hlvl=$level+2;  # Levels 1 and 2 are in use already
        #    pushline("\t<A name=\"$tag\"><H$hlvl>$txt</H$hlvl></A>");
        #} else {
        #    pushline("\t<A name=\"$tag\"><P><B>$txt</B></P></A>");
        #}
        #pushline(" * \\endhtmlonly");
        #
        # TOC entries
        $txt =~ s/:$//o;    # remove trailing colon from TOC entry
        #
        # Adjust nesting for level
        while ($prevlevel < $level) {
            push @headers, " * <UL>";
            $prevlevel ++;
        }
        while ($prevlevel > $level) {
            push @headers, " * </UL>";
            $prevlevel --;
        }
        push @headers, " * <LI><A HREF=\"#$tag\"> $txt </A></LI>";
    }
    # Insert the Table of Contents in position $pos
    sub insertTOC ($$) {
        my $lines = shift;
        my $pos = shift;

        while ($prevlevel > 0) {
            push @headers, " * </UL>";
            $prevlevel --;
        }
        my $headers = getheaders();

        splice ( @$lines, $pos, 0, ( " * \\par " ) );
        splice ( @$lines, $pos, 0, @$headers );
        splice ( @$lines, $pos, 0, ( " * \\par Outline" ) );
    }

    # retrieve processed output
    sub getheaders () {
        return \@headers;
    }

    # reset headers
    sub resetheaders () {
        @headers=();
        @levels = ( 0, 0, 0, 0, 0, 0 ); # should be MAXHEADERLEVELS
        $prevlevel = 0;
    }
}
#------------------------------------------------------------------------------
# escape Doxygen-significant characters - use for comments only, not code.
# also, translate 'code' and *italic* markers in the text
# Note: - Funky multi-line s/// translates '*' to '\f' to avoid interpretation
#         as italics. tr/// undoes this after italics are done.
#       - Italics include (*this* *text*) but not (*)

sub escape ($) {
    my $string = shift;
    $string=~s{([\@<>&\$#\\])}{\\$1}go if $string;

    my $t;
    $string =~ s{(\s|^)' ([^']+) '}
                 {   $t = "$1<code>$2</code>";
                     $t =~ tr|\*|\f|;
                     $t =~ tr|\!|\e|;
                     $t =~ tr|\_|\r|;
                     $t
                 }gexo;
    $string =~ s{((\s|^)\(?)\*([^)*][^*]*)\*}{$1<I>$3</I>}g;
    $string =~ s{((\s|^)\(?)\!([^)!][^!]*)\!}{$1<B>$3</B>}g;
    $string =~ s{((\s|^)\(?)\_([^)_][^_]*)\_}{$1<B><I>$3</I></B>}g;
    $string =~ tr[\f][\*];
    $string =~ tr[\e][\!];
    $string =~ tr[\r][\_];

#    if ($string =~ m|^//|) {
#        $string =~ s!/\*!|*!g;
#        $string =~ s!/*/!*|!g;
#    }

    return $string;
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

                    @listLinesOut = ();
                    processList(\@listLinesOut, \@listLinesIn);

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
                    $pending_header = escape($line);
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

        if ( $line =~ m!^\s*(template|class|struct)\s*!o ) {
            openGroups(0);
        }

        ### start of class
        if ($line =~ m!^\s*(class|struct)\s*(.*?)\s*{!) {
            # non-comment line: terminate existing comment
            if (minorstate()==COMMENT) {
                pushline(" */");
                popstate();
                pushline("");
            }
            openGroups(0);
            # not currently used because Doxygen doesn't allow a space in
            # specified classnames (like for instance in a specialised
            # template class). Retained until this is a solvable problem.
            $classname = $2;
            # currently only the outer class causes the state depth to
            # increase internally. This may change once internal class/structs
            # can always detect their ends.
            pushstate(CLASS,NOSTATE) if statedepth()==0;

            # enter class head state
            pushstate(CLASS,CLASSHEAD);

            # save the actual code line to place it after the class comment.
            # Doxygen doesn't grok the class docs being *inside* the class as
            # BDE has it. Neither can we use the 'class' special command as
            # it doesn't work for template specialisations including spaces in
            # the classname (as in: 'template<> class foobar<void *>'
            push @class_decl, $line;
            # in fact this cases the comment to end up between the template
            # and the class in cases where they appear on seperate lines.
            # However Doxygen appears not to care. However lines following
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

            if ($line=~m|^\s*\w| and minorstate()==CLASSHEAD) {
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
            #} elsif ($line =~ m|^\s*};|) {  #ends early for enums.
            } elsif ($line =~ m|^};|) {      #stricter
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
                popstate() if statedepth()==1; #end of outer class
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
                            pushline("/*!<");  #SRB EXPER
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
    # If there's a Purpose, we can place a TOC.
    insertTOC(getlines(),$TOClocation) if defined($TOClocation);

    return getlines();
}

#==============================================================================

1;
