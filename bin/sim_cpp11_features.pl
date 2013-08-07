#!/usr/bin/env perl

# Translate variadic C++ function templates into multiple function templates
# with variable numbers of arguments.  For example, translate:
#
#   template <typename ...T> f(const T& ...a);
#
# into:
#
#   template <> f();
#   template <typename T_1> f(const T_1& a_1);
#   template <typename T_1, typename T_2> f(const T_1& a_1, const T_2& a_2);
#   // etc.
#
# Usage: sim_cpp11_features.pl <input-file-name> [ <num-reps> ]
#
#   The input file contains the variadic function templates.  The optional
#   num-reps argument specifies the maximum number of variadic arguments to be
#   supported (default 15).  Output is written to standard out.

use strict;
use 5.010;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use common::sense;
use Getopt::Long;
use File::Spec;

use Util::Message qw(fatal debug message);

# Debug settings
$Util::Message::DEBUG_PREFIX =  "##";   # Prefix for each debug line
$Util::Message::DEBUG2_PREFIX = "###";  # Prefix for each detailed debug line
Util::Message::set_prog("");  # Don't prefix each debug line with prog name

my $debug = 0;
my $clean = 0;
my $defaultMaxArgs = 10;
my $maxArgs = $defaultMaxArgs;
my $maxColumn = 79;  # Maximum allowed output line length

# 80 spaces, for constructing indentations.
my $spaces = ("                                        ".
              "                                        ");

# Dummy character to fill in for string literal contents in stripped code
# buffers.  A normal period is easier to view in debug mode, whereas a Latin-1
# interpunct (centered dot) is less likely to show up in search.
our $dummyChar = $debug ? "." : "\267";

my %traceCtrls;

# Return the larger of the level for the specified trace label or the
# currently-specified debug level.
sub getTraceLevel($)
{
    my $traceLabel = $_[0];

    my $traceLevel = $traceCtrls{$traceLabel} || 0;
    my $debugLevel = Util::Message::get_debug();

    if ($debugLevel > $traceLevel) {
        return $debugLevel;
    }
    else {
        return $traceLevel;
    }
}

sub doTrace($$$@) {
    my ($traceLabel, $debugLevel, $msgfunc, $message, @args) = @_;

    my $traceLevel = getTraceLevel($traceLabel);
    return unless ($traceLevel >= $debugLevel);

    my $oldDebugLevel = Util::Message::get_debug();
    my $oldMsgPrefix = Util::Message::get_prefix();
    Util::Message::set_debug($traceLevel);
    Util::Message::set_prefix($traceLabel);
    &$msgfunc(sprintf($message, @args));
    Util::Message::set_prefix($oldMsgPrefix);
    Util::Message::set_debug($oldDebugLevel);
}

sub trace($@)
{
    my ($traceLabel, @message) = @_;
    doTrace($traceLabel, 1, \&debug, @message);
}

sub trace2($@)
{
    my ($traceLabel, @message) = @_;
    doTrace($traceLabel, 2, \&debug2, @message);
}

# Return a unique generated name using the supplied prefix argument.
my $nextGenParam = 0;
sub genName($)
{
    return $_[0].$nextGenParam++;
}

# Input file as a single string.  A position within this string is represented
# as an integer index of a character in the string.  The '$inputEnd' position
# is set to 'length($input)', which is the first position past the end of the
# string.  The $shroudedInput string is the same as $input except with
# comments, string literals, and comment shrouded so that their contents
# will not interfere with regular expression matches.
my $input;
my $inputEnd;
my $shroudedInput;

my %matchingBrackets = ( '[' => ']',
                         '{' => '}',
                         '(' => ')',
                         '<' => '>' );

my $generatedCodeBegin = <<EOT;
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
EOT

chomp $generatedCodeBegin;

my $generatedCodeEnd = <<EOT;
// }}} END GENERATED CODE
EOT

chomp $generatedCodeEnd;

my $commandLine;  # command line used to invoke the generator

# Regular expression to find a comment or string string.  After being used in
# a successful regular expression match, exactly one of the following will be
# set:
#
#  $1   A C++-style comment, e.g. "// comment text\n" (excluding quotes)
#  $2   A C-style comment, e.g., "/* comment text */" (excluding quotes)
#  $3   A string literal, e.g., "string text" (including quotes)
#  $4   A character literal, e.g., 'x' (including quotes)
#
# Note that the string and character literals will terminate without complaint
# at an unescaped newline.  Better to get a clear error from the compiler than
# an obscure error from a Perl script.
my $commentAndStringRe =
    qr{(?:
        (//(?:[^\\\n]+|\\.|\\\n)*$)     | # C++-style comment
        (/\*(?:[^*]+|\*[^*/])*\*/)     | # C-style comment
        ("(?:[^"\\\n]+|\\.|\\\n)*["\n]) | # string literal
        ('(?:[^'\\\n]+|\\.|\\\n)*['\n])   # character literal
       )}mx;

# Make a command line string suitable for putting into the generated file which
# should be sufficient to reliably regenerate the file with the same
# parameters.
sub makeCommandLine {
    my @args = @_;
    my $ret = "";

    # simplify args
    for my $arg (@args) {
        next if ($arg =~ /^--(debug|trace)/);  # discard debugging options

        # Discard the path part of the filename
        my ($vol, $dirs, $file) = File::Spec->splitpath($arg);
        $ret .= ' ' if ($ret);
        $ret .= $file;
    }

    return $ret;
}

# Return a string of whitespace to be used in place of the specified
# '$comment' string.  If $comment contains whitespace before or after the
# actual coment, it is considered as part of the comment for the purpose of
# this transformation.  The specified '$option' (default "single-ws") must be
# one of the following:
#
#  "single-ws"  Result contains a single whitespace character.
#  "keep-nl"    Result contains the same number of newlines as '$comment' does
#  "keep-len"   Result is the same length as '$comment' and has newlines in
#               the same positions.
sub commentToWhitespace($;$)
{
    my ($comment, $option) = @_;
    $option ||= "single-ws";

    my $first = substr($comment, 0, 1);
    my $last  = substr($comment, -1, 1);

    if ($option eq "single-ws") {
        # Choose single whitepace character: newline if comment ends with a
        # newline, space otherwise.
        $comment = $last eq "\n" ? "\n" : " ";
    }
    elsif ($option eq "keep-nl") {
        # Remove all characters except newlines
        $comment =~ s/[^\n]//g;
        $comment ||= ' ';  # Make sure there is at least one whitespace
    }
    elsif ($option eq "keep-len") {
        # Replace all non-newline characters with spaces, preserving the
        # character count and keeping newlines in the same positions.
        $comment =~ s/[^\n]/ /g;
    }
    else {
        fatal("Illegal option $option");
    }

    return $comment;
}

# Return the result of "shrouding" comments, string literals, and character
# literals in the specified '$input' string so that they contain no C++ tokens
# that might confuse a regular expression search.  Comments are replace by
# whitespace and the contents of quoted strings are replaced by dots.
sub shroudCommentsAndStrings($)
{
    my $input = shift;

    pos($input) = 0;

    while ($input =~ m{$commentAndStringRe}g)
    {
        my $start = $-[0];
        my $end   = $+[0];

        my $comment = $1 || $2;
        my $literal = $3 || $4;
        my $replacement;

        if ($comment) {
            $replacement = commentToWhitespace($comment, "keep-len");
        }
        elsif ($literal) {
            my $first = substr($input, $start, 1);
            my $last  = substr($input, $end - 1, 1);
            $replacement = $literal;
            $replacement =~ s/./$dummyChar/mg;
            substr($replacement, 0, 1) = $first;
            substr($replacement, -1)   = $last;
        }
        else {
            fatal("Shouldn't get here");
        }

        substr($input, $start, $end - $start) = $replacement;
        pos($input) = $start + length($replacement);
    }

    return $input;
}

# Strip comments from the specified '$input', replacing them with whitespace
# and return the result.  The optionally specified '$option' (default
# "single-ws") can be one of the following:
#
#  "single-ws"  Replace each comment with a single whitespace character.
#  "keep-nl"    Replace each comment with a string of whitespace containing
#               same number of newlines.
#  "keep-len"   Replace each comment with a string of whitespace of the same
#               length and with newlines in the same positions.
sub stripComments($;$)
{
    my ($input, $option) = @_;
    $option ||= "single-ws";

    pos($input) = 0;

    while ($input =~ m{[ \t]*$commentAndStringRe[ \t]*\n?}g)
    {
        my $start = $-[0];
        my $end   = $+[0];
        my $last  = substr($input, -1);

        if ($1 || $2) {
            my $comment = $&;
            if ($option eq "single-ws" && $last eq "\n" &&
                ($start == 0 || substr($input, $start - 1, 1) eq "\n")) {
                # Comment takes one or more whole lines.  Replace with nothing.
                $comment = "";
            }
            else {
                $comment = commentToWhitespace($comment, $option);
            }
            substr($input, $start, $end - $start) = $comment;
            pos($input) = $start + length($comment);
        }
    }

    return $input;
}

# Sets the input string to the specified '$input' and resets and populates the
# commentAndString arrays.
sub setInput($)
{
    $input = shift;
    $input =~ s:\r\n:\n:g;      # Normalize newlines
    $input .= "\n" if ("\n" ne substr($input, -1, 1));
    $inputEnd = length($input);
    $shroudedInput = shroudCommentsAndStrings($input);
}

# Ability to push and pop input contexts
{
    my @inputStack = ();
    my @inputEndStack = ();
    my @shroudedInputStack = ();
    my @posStack = ();

    # Like 'setInput' but preserves the previous input string,
    # commentAndString arrays, and position.
    sub pushInput($)
    {
        push @inputStack, $input;
        push @inputEndStack, $inputEnd;
        push @shroudedInputStack, $shroudedInput;
        push @posStack, pos($input);

        setInput($_[0]);
    }

    # Restore the input context from the top of the context stack
    sub popInput()
    {
        fatal("Empty input stack") unless (@inputStack);
        my $ret = $input;
        $input = pop @inputStack;
        $inputEnd = pop @inputEndStack;
        $shroudedInput = pop @shroudedInputStack;
        pos($input) = pop @posStack;

        return $ret;
    }
}

# Search the '$input' string within the '[$pos, $endpos)' range for
# the specified '$re' regular expression. The '$pos' and '$endpos' arguments
# are optional and default to '[0, length($input)]'.  Skip matches within
# comments, string literals, and character literals.  If called within array
# context, return an array of captures on success or an empty array on
# failure, just as a normal regular expression match.  If called within scalar
# context, returns 1 on success and an empty string on failure.  Set the
# global variables '@cppMatch', '@cppMatchStart', and '@cppMatchEnd' using the
# following mapping to the normal regexp variables as follows:
#..
#  @cppMatch      is equivalent to (undef, $1, $2, $3, ...)
#  $cppMatchAll   is equivalent to $&
#  @cppMatchStart is equivalent to @-
#  @cppMatchEnd   is equivalent to @+
#..
# Match will fail for strings that appear only within comments or
# quotes: e.g., "//", '"', etc. and newlines will not be found within comments
# (including at the end of C++-style comments.
my @cppMatch;
my $cppMatchAll;
my @cppMatchStart;
my @cppMatchEnd;
sub cppSearch($;$$)
{
    my ($re, $pos, $endpos) = @_;
    $pos    = 0         unless (defined($pos));
    $endpos = $inputEnd unless (defined($endpos));

    pos($input) = $pos;
    pos($shroudedInput) = $pos;
    if ($shroudedInput =~ m/$re/g && $+[0] <= $endpos) {
        @cppMatchStart = @-;
        @cppMatchEnd   = @+;
        $cppMatchAll   = substr($input, $cppMatchStart[0],
                                $cppMatchEnd[0] - $cppMatchStart[0]);
        @cppMatch      = ( $cppMatchAll );

        for (my $i = 1; $i < @cppMatchStart; ++$i) {
            if (defined $cppMatchStart[$i]) {
                push @cppMatch, substr($input, $cppMatchStart[$i],
                                       $cppMatchEnd[$i] - $cppMatchStart[$i]);
            }
            else {
                push @cppMatch, undef;
            }
        }

        pos($input) = $cppMatchEnd[0];
        pos($shroudedInput) = $cppMatchEnd[0];
        if (! wantarray()) {
            return 1;
        }
        else {
            return ($cppMatchAll);
        }
    }

    # Got here if no acceptible match was found
    @cppMatch      = ();
    $cppMatchAll   = undef;
    @cppMatchStart = ();
    @cppMatchEnd   = ();
    return wantarray() ? @cppMatch : "";
}

# Replace the substring in '$input' begining at the speicified '$start'
# position, removing the specified '$length' characters and replacing them
# with the specified '$subst' string.  Adjust all of the 'cppSearch' state
# accordingly.
sub cppSubstitute($$$)
{
    my ($start, $length, $subst) = @_;
    my $end = $start + $length;

    my $lengthChange = length($subst) - ($length);

    substr($input, $start, $length) = $subst;
    substr($shroudedInput, $start, $length) =
        shroudCommentsAndStrings($subst);

    for my $matchPos (@cppMatchStart) {
        if ($matchPos >= $end) {
            $matchPos += $lengthChange;
        }
    }

    for my $matchPos (@cppMatchEnd) {
        if ($matchPos >= $end) {
            $matchPos += $lengthChange;
        }
    }

    if (defined(pos($input)) && pos($input) >= $end) {
        pos($input) = pos($input) + $lengthChange;
    }

    $inputEnd += $lengthChange;
}

# TBD: THIS FUNCTION IS NOT CURRENTLY PRODUCING ACCURATE RESULTS. 
# Return the input line number and column number at the specified '$pos'.  If
# called in a scalar context, return only the line number.  Line and column
# numbers are 1-based.  If the character at '$position' is a newline
# character, it represents the end of a line, not the start of a new line.
# Example:
#..
#  If '$input' is "abc\ndef\n", then:
#
#        character
#  $pos  at $pos    lineAndColumn($pos)
#  ----  ---------  ----------------
#   0       'a'       (1 1)
#   2       'c'       (1 3)
#   3       '\n'      (1 4)
#   4       'd'       (2 1)
#   8       EOF       (3 1)
#..
sub lineAndColumn($)
{
    my $pos = shift;

    my $fragment = substr($input, 0, $pos);

    # Remove all characters except newlines
    $fragment =~ s/[^\n]+//g;

    # Count how many newlines are in the fragment
    my $lineNum = length($fragment) + 1;

    # Count number of characters between the last newline and the current
    # position.
    my $colNum = 1;
    pos($input) = $pos;
    if ($input =~ m{([^\n]*)\G}g ) {
        $colNum = length($1) + 1;
    }

    return wantarray() ? ($lineNum, $colNum) : $lineNum;
}

# TBD: THIS FUNCTION IS NOT CURRENTLY PRODUCING ACCURATE RESULTS. 
# Error-handling routine to print the line within '$input' at the specified
# '$pos' with a caret at under the column.
sub displayPos($)
{
    my $pos = shift;

    if ($pos == $inputEnd) {
        return "\n^\n";
    }

    my ($lineNum, $col) = lineAndColumn($pos);
    pos($input) = $pos;
    $input =~ m{[^\n]*\n}g;     # Move to end of line
    $input =~ m{([^\n]*\n)\G}g; # Get entire line
    my $output = $1;
    do {
        $output .= substr($spaces, 0, $col - 1);
        $col -= length($spaces);
    } while ($col > 1);
    $output .= "^\n";

    return $output;
}

# Usage: $depth = bracketDepth($initDepth, $inputLine, $brackets);
#
#   Returns the bracket nesting depth at the end of $inputLine given a
#   starting depth of $initDepth.  The $bracket arguement is a string of 1 to
#   4 open-bracket types to consider.  Only bracket types '[', '{', '(', and
#   '<' are supported.  Their corresponding close-bracket types, ']', '}',
#   ')', and '>' are automatically matched.  Thus if $bracket is "[{(<", then
#   all bracket types are matched whereas if $bracket is '{', then only curly
#   braces are matched.  The behavior is undefined if either an open or
#   closing bracket is found within a quoted string or a C-style comment.  The
#   behavior is also undefined if an open bracket is matched with a different
#   closing bracket.  If $initDepth is undef and no brackets are found, then
#   returns undef.  The last is so that a sequence of strings with no brackets
#   (return undef) can be distinguised from a sequence of strings with
#   fully-matched brackets (return 0).
sub bracketDepth($$$) {
    my ($depth, $inputLine, $brackets) = @_;

    my ($openBrackets, $closeBrackets) = ("", "");
    for my $bracket (split //,$brackets) {
        if ($bracket eq '[') {
            $openBrackets .= '\\';
            $closeBrackets .= '\\';
        }
        $openBrackets .= $bracket;
        $closeBrackets .= $matchingBrackets{$bracket};
    }
    my $closeBracketsRe = qr/[$closeBrackets]/;

    my @parens = ($inputLine =~ /([$openBrackets$closeBrackets])/g);

    return $depth unless (@parens);

    $depth = $depth || 0; # Don't allow $depth to remain undef
    for my $paren (@parens) {
        if ($paren =~ $closeBracketsRe ) {
            --$depth;
        }
        else {
            ++$depth;
        }
    }

    return $depth;
}

# Find the the specified '$brace' in '$input' starting at the specified
# '$pos', then return the position immediately after the matching end brace.
# Return '$pos' if the starting brace is not found.  The behavior is undefined
# if '$brace' is found but no matching brace is found.
sub findMatchingBrace($$)
{
    my ($brace, $pos) = @_;
    my $startPos = $pos;

    my $openBraces = '\\[({';
    my $closeBraces = '})\\]';
    if ($brace eq '<') {
        $openBraces .= '<';
        $closeBraces .= '>';
    }
    my $allBraces = $openBraces . $closeBraces;
    my $allBracesRe = qr/[$allBraces]/;

    my @matchingBraceStack = ();

    my $done = 0;
    while (! $done) {

        last unless (cppSearch($allBracesRe, $pos));

        my $bracePos   = $cppMatchStart[0];
        $pos           = $cppMatchEnd[0];
        my $foundBrace = substr($input,  $bracePos, 1);

        my $matchingBrace = $matchingBrackets{$foundBrace};

        # debug("*** Brace-matching status\n".
        #       "    foundBrace  = $foundBrace\n",
        #       "    bracePos    = $bracePos");

        if (defined($matchingBrace)) {
            # Found an open brace

            # If this is the first open brace, make sure it matches the
            # brace that was passed in.
            if (0 == @matchingBraceStack && $foundBrace ne $brace) {
                # Fail: No match.
                return $startPos;
            }

            # push matching brace onto the brace stack
            push @matchingBraceStack, $matchingBrace;
            # debug("    push matchingBraceStack = [@matchingBraceStack]");
        }
        else {
            # Found closing brace.  Pop matching brace off the stack.  If
            # top of stack is does not match, abort.  Note that '<' and
            # '>' might be used as greater-than and less-than symbols
            # instead of braces.  Thus, it is not an error to find a
            # non-matching '<' on the stack or a non-matching '>' in the
            # input line.

            # Pop any unmatched '<' off the stack
            while (@matchingBraceStack &&
                   $matchingBraceStack[-1] ne $foundBrace &&
                   $matchingBraceStack[-1] eq '>') {
                pop @matchingBraceStack;
                # debug("    pop matchingBraceStack = [@matchingBraceStack]");
            }

            # Pop the matching brace off the stack
            if (@matchingBraceStack &&
                $matchingBraceStack[-1] eq $foundBrace) {
                pop @matchingBraceStack;
                # debug("    pop matchingBraceStack = [@matchingBraceStack]");
            }
            elsif ($foundBrace eq '>') {
                # Ignore unmatched '>'.
                next;
            }
            else {
                fatal("Mismatched brace '$foundBrace'; ".
                      "expecting '$matchingBraceStack[-1]' at line ".
                      scalar(lineAndColumn($bracePos)).
                      "\n".displayPos($bracePos));
            }

            $done = (0 == @matchingBraceStack);
        }

    } # end while ! done

    return $pos;
}

my @packTypes = ("class", "typename", "int", "unsigned", "unsigned int",
                 "std::size_t", "bsl::size_t", "size_t");
my $packTypesStr = join("|", @packTypes);

# Given an '$input' string where the substring at '$pos' starts with:
#..
#  template <class T, class... XYZ, int... QRS>
#..
# , return a list of type/name pairs
# like the following:
#..
#  (
#    [ "class",    "T"   ],
#    [ "class...", "XYZ" ],
#    [ "int...",   "QRS" ]
#  )
#..
# The parameter pack type (e.g., "class" or "int") must be a term in the
# @packTypes list (above).  Each pack name (e.g., "XYZ" or "QRS") is optional
# and will be replaced by a generated name if absent.
sub getTemplateParams($)
{
    my $pos = $_[0];
    my @packs = ();
    my $searchEnd = $pos;

    while (cppSearch(qr/([<,]\s*)($packTypesStr)\s*(\.\.\.)?(?:\s*([[:word:]]+))?(\s*=\s*[^>,]*)?(\s*[>,])/, $pos))
    {
        my $packType = $cppMatch[2];
        $packType .= $cppMatch[3] if defined $cppMatch[3];
        my $packName = $cppMatch[4] || genName("__Param__");
        my $packDflt = $cppMatch[5] || "";
#        push @packs, [ $packType,  $packName, $packDflt ];
        push @packs, [ $packType,  $packName ];
        $pos = $cppMatchStart[6];  # Include closing delimiter in next search
        $searchEnd = $cppMatchEnd[0];
        last if ($cppMatch[5] =~ />/);
    }

    pos($input) = $searchEnd;

    if (getTraceLevel("getTemplateParams") > 0) {
        my $packStr = "[\n";
        for my $pack (@packs) {
            $packStr .= "  [ ".$pack->[0].", ".$pack->[1]." ]\n";
        }
        $packStr .= "]";
        trace("getTemplateParams", "packs = %s", $packStr);
    }

    return @packs;
}

# Return the substring specified by the range
# '[$templateBegin, $templateEnd)', except with comments stripped.
sub noopTemplateTransform($$$;$)
{
    my ($templateBegin, $templateHeadEnd, $templateEnd, $isVariadic) = @_;

    return stripComments(substr($input, $templateBegin,
                                $templateEnd - $templateBegin));
}

# Usage:
#     $workingBuffer = replaceAndFitOnLine($workingBuffer, $packStart,
#                                          $packLen, $replacement);
#
# Replaces [$packStart, $packEnd) with $replacement, re-indenting as necessary
# so that longest line in $replacement fits within $maxCols.  Modifies
# $workingBuffer.
sub replaceAndFitOnLine($$$$) {
    my ($workingBuffer, $packStart, $packLen, $replacement) = @_;
    my $packEnd = $packStart + $packLen;

    trace("replaceAndFitOnLine", "START workingBuffer = [%s]", $workingBuffer);

    # $prePack is the text on same line preceding the current pack.
    pos($workingBuffer) = $packStart;
    $workingBuffer =~ m/^(.*)\G/mg;
    my $prePack = $1;
    my $column = length($prePack);

    # $postPack is the text on the same line following the current
    # pack.  Truncate $postPack at the start of the next pack, if any.
    pos($workingBuffer) = $packEnd;
    $workingBuffer =~ m/\G(.*)/mg;
    my $postPack  = $1;
    $postPack =~ s/__PACK_[VT][0-9]+[RF]__.*$//;

    my $postLen = length($postPack);

    # Compute length of longest line of $replacement
    my $lastReplacementWidth = 0;
    my $maxReplacementWidth = 0;
    for my $line (split qr/\n[ \t]*/, $replacement) {
        $lastReplacementWidth = length($line);
        $maxReplacementWidth = $lastReplacementWidth
            if ($lastReplacementWidth > $maxReplacementWidth);
    }

    # If $postPack is between 0 and 3 characters long, then leave enough
    # "slack" to fit $postPack on the same line as the current pack.
    # Otherwise, if $postPack starts with a comma, leave enough slack for a
    # single comma.
    my $slack = 0;
    if (0 <= $postLen && $postLen <= 3) {
        # Leave enough slack to fit entire $postPack on same line
        $slack = $postLen;
    }
    elsif ($postPack =~ m/^[ \t]*,/) {
        # Leave enough slack to fit a comma
        $slack = 1;
    }

    # Adjust $maxReplacementWidth to take slack into account
    $maxReplacementWidth = $lastReplacementWidth + $slack
        if ($lastReplacementWidth + $slack > $maxReplacementWidth);

    # Compute indentation.  If possible without exceding the line
    # length, indent to the starting column of the $replacement.
    # Otherwise, find the smallest indent that accomodates each term
    # of the pack expansion (plus slack).
    my $targetCol = $column;
    $targetCol = $maxColumn - $maxReplacementWidth
        if ($column + $maxReplacementWidth > $maxColumn);
    $targetCol = 0 if $targetCol < 0;

    my $indentation = substr($spaces, 0, $targetCol);

    if ($replacement && $targetCol < $column) {
        my $overage = $column - $targetCol;
        $prePack =~ /([ \t]*)$/;  # Match trailing whitespace
        my $spacesAtEndofPrepack = length($1);
        if ($overage <= $spacesAtEndofPrepack) {
            # Remove unneeded spaces so that we can start at $targetCol
            $packStart -= $overage;
        }
        else {
            # Start replacement on next line
            $replacement = "\n".$replacement;

            # Remove trailing whitespace before replacement
            $packStart -= $spacesAtEndofPrepack;
        }
    }

    # Prepend indentation after every newline in $replacement
    $replacement =~ s/\n[ \t]*/\n$indentation/g;

    if ($targetCol + $lastReplacementWidth + $postLen > $maxColumn) {
        # $postPack will not fit on the same line as the last line of the
        # replacement.  Append a newline so that it will fit on the next line.

        # Remove any leading commas from $postPack.  The comma
        # (if any) will be appended to the replacement.
        $postPack =~ s/^([ \t]*(,?)[ \t]*)//;
        my $removedLen = length($1);
        my $comma = $2;
        $packEnd += $removedLen;

        if ($targetCol + $postLen > $maxColumn) {
            # Even at the same indentation as the previous line, it
            # still doesn't fit.  Reduce indentation as needed.
            $indentation .= substr($spaces, 0, $maxColumn - $postLen);
        }

        $replacement =~ s/\s*$//;      # remove trailing spaces and then
        $replacement .= $comma . "\n"; # append new line
        $replacement .= $indentation;
    }

    $packLen = $packEnd - $packStart;
    if ($shroudedInput && $workingBuffer eq $shroudedInput) {
        cppSubstitute($packStart, $packLen, $replacement);
        trace("replaceAndFitOnLine", "RETURN = [%s]", $shroudedInput);
        return $shroudedInput;
    }
    else {
        substr($workingBuffer,
               $packStart, $packLen, $replacement);
        trace("replaceAndFitOnLine", "RETURN = [%s]", $workingBuffer);
        return $workingBuffer;
    }
}

# Replace uses of perfect forwarding within the specified '$input' with
# special macros and return the result: A template argument of type 'T&&' is
# replaced with 'BSLS_COMPILERFEATURES_FORWARD_REF(T)'.  An expression of the
# form 'bsl::forward<T>(expr)' is replaced with
# 'BSLS_COMPILERFEATURES_FORWARD(T, #expr)', where 'T' is a template type
# parameter.
sub replaceForwarding($$$;$)
{
    my ($templateBegin, $templateHeadEnd, $templateEnd, $isVariadic) = @_;

    my $buffer = stripComments(substr($input, $templateBegin,
                                      $templateEnd - $templateBegin));

    pushInput($buffer);
    trace("replaceForwarding", "Stripped input = [%s]", $buffer);

    my @typenames;
    my $pos = 0;
    while (cppSearch(qr/[<,]\s*(?:typename|class)
                        (?:\s*\.\.\.)?\s*([[:word:]]+)\s*[>,]/x, $pos)) {
        $pos = $cppMatchEnd[1];
        push @typenames, $cppMatch[1];
    }

    for my $typename (@typenames) {
        $pos = 0;
        while (cppSearch(qr/\b($typename\s*&&)((?:[ \t]*\.\.\.)?[ \t]*[[:word:]]+)?/,
                         $pos)) {
            # Obtain the argument name from the match found by cppSearch.
            my $argname = $cppMatch[2] || "";
            $argname =~ s/\s+/ /g;  # squash all whitespace to a single space

            replaceAndFitOnLine($shroudedInput,
                                $cppMatchStart[1],
                                $cppMatchEnd[2] - $cppMatchStart[1],
                                "BSLS_COMPILERFEATURES_FORWARD_REF($typename)".
                                $argname);
            $pos = $cppMatchEnd[2];
        }

        $pos = 0;
        while (cppSearch(qr/\b(bsl|std|native_std)\s*::\s*
                            forward\s*<\s*$typename\s*>\s*\(/x,
                         $pos)) {
            replaceAndFitOnLine($shroudedInput,
                                $cppMatchStart[0],
                                $cppMatchEnd[0] - $cppMatchStart[0],
                                "BSLS_COMPILERFEATURES_FORWARD($typename, ");
            $pos = $cppMatchEnd[0];
        }
    }

    trace("replaceForwarding", "Result = [%s]", $input);

    $buffer = popInput();
    return $buffer;
}

# PACK MARKINGS
# -------------
#
# As C++ code is processed by this program, parameter packs are replaced by
# special markers of the form "__PACK_T#R__".  The '#' in the marker is a
# small non-negative integer (in decimal format) that "names" the parameter
# pack.  The 'T' in the marker indicates that the parameter pack represents a
# list of type names.  A 'V' in that position would indicate that the
# parameter pack represents a list of non-typenames, e.g., variable names,
# declarations, or expressions.  The 'R' in the marker indicates that the
# parameter in the pack is repeated in the pack expansion.  An 'F' in that
# position would also indicate that the parameter is repeated, but that the
# list of repetitions is filled out with default types or values.  Thus,
# "__PACK_V2F__" is the third parameter pack (counting from zero),
# represents non-typenames, and should be filled with default values.  A
# separate dictionary maps each parameter pack (by number) to a code snippet.
# In addition, there is an implicit mapping from "__PACKSIZE_#__" marker to
# the size of the parameter pack.

# Replace every parameter pack and pack expansion in '$buffer' with the string
# "__PACK_T#R__" or '__PACK_V#R__' (see "PACK MARKINGS," above), where '#' is
# a unique sequence number within the buffer.  Also replace every use of the
# pattern "sizeof... (X)" with "__PACKSIZE_#__" where '#' is an index into a
# hypothetical array of parameter packs.  Return a list of pack expansions
# where each expansion has the elispsis removed and a "_@" appended to each
# identifier that should be repeated within the expansion.
#
# For example, given the input '$buffer':
#..
#  template <typename ...B, class... A>
#  void foo(C<B...> *c, const A&... a)
#  {
#      D<A...> d(forward<A>(a)...);
#      bar(sizeof... (A), c, &d);
#  }
#..
# This function transforms '$buffer' into:
#..
#  template <__PACK_T0R__, __PACK_T1R__>
#  void foo(C<__PACK_T2R__> *c, __PACK_V3R__)
#  {
#      D<__PACK_T4R__> d(__PACK_V5R__);
#      bar(__PACKSIZE_1__, c, &d);
#  }
#..
# And returns a pack expansion list:
#..
#  (
#    "typename B_@",
#    "class A_@",
#    "B_@",
#    "const A_@& a_@",
#    "A_@",
#    "forward<A_@>(a_@)"
#  )
#..
sub markPackExpansions()
{
    trace("markPackExpansions", "ORIGINAL = [%s]", $input);

    my %typeNames = ();
    my @packIdents;
    my @packExpansions;
    my $packNum = 0;

    # Mark packs in template headers: Find a pattern coming after a '<' or ','
    # delimiter, starting with integer type, the word "class", or the word
    # "typename" and ending with an elipsis ('...') and an optional
    # identifier, and followed by a ',' or '>' delimiter.  If an identifier
    # follows the elipsis, its name is saved in the @packIdents list.  Replace
    # the found pattern with a numbered __PACK_V#R_ string.
    while (cppSearch(qr/([<,]\s*)($packTypesStr)\s*\.\.\.(?:\s*([[:word:]]+))?(\s*[>,])/, 0)) {
        my $PACKR = "__PACK_V".$packNum."R__";
        my $PACKSIZE = "__PACKSIZE_".$packNum."__";

        my $packType = $cppMatch[2];
        my $separator = $cppMatch[4];
        my $paramPackName = $cppMatch[3] || genName("_Tp__");

        if ($packType =~ m/(class|typename)/) {
            $PACKR =~ s/__PACK_V/__PACK_T/;
            $typeNames{$paramPackName} = 1;
        }

        my $replacement = $cppMatch[1] . $PACKR . $separator;

        push @packIdents, $paramPackName;
        push @packExpansions, "$packType $paramPackName";

        substr($input, $cppMatchStart[0], $cppMatchEnd[0] - $cppMatchStart[0],
               $replacement);
        $input =~ s/\bsizeof\s*\.\.\.\s*\(\s*$paramPackName\s*\)/$PACKSIZE/g;
        setInput($input);  # TBD: find a more efficient way to do this

        $packNum = @packExpansions;
    }

    fatal("Expected only variadic functions") if (0 == $packNum);

    # Mark packs in template bodies: Find a pattern coming after a '(', '{',
    # '<', ',', ';', or ':' delimiter (but not '::'), ending with an elipsis
    # ('...') and an optional identifier, and followed by a ';', ',', '>', '{,
    # '}', or ')' delimiter.  If an identifier follows the elipsis, its name
    # is saved in the @packIdents list.  Replace the found pattern with a
    # numbered __PACK_V#R_ string.
    my $B = "({<,;:";  # Begining delimiters
    my $E = ";,>{})";   # End delimiters
    while (cppSearch(qr/([$B]\s*)([^$B]+)\.\.\.(?:\s*([[:word:]]+))?(\s*[$E])/,
                     0))
    {
        trace2("markPackExpansions", "found pack = %s", $cppMatchAll);
        my $PACKR = "__PACK_V".$packNum."R__";

        my $FB = "\\".$cppMatch[1];  # Found begining delimiter
        my $pattern = $cppMatch[2];
        $PACKR =~ s/__PACK_V/__PACK_T/ if (exists($typeNames{$pattern}));
        my $replacement = $cppMatch[1] . $PACKR . $cppMatch[4];
        if ($cppMatch[3]) {
            # Save identifier after the elipsis and append it to the
            # pattern.
            my $arg = $cppMatch[3];
            $pattern .= " ".$arg;
            push @packIdents, $arg;
        }
        # my $FE = $cppMatch[5];  # Found end delimiter

        substr($input, $cppMatchStart[0], $cppMatchEnd[0] - $cppMatchStart[0],
               $replacement);

        # Scan backwards until pattern is fully-balanced wrt brackets.
        # Join sections that are connected by '::'.
        while (1) {
            if ($input =~ s/(::\s*)$PACKR/$PACKR/ ) {
                # Add leading '::' to pattern and loop.
                $pattern = $1.$pattern;

                # Now search for start of pattern again and loop
                $input =~ s/([$B]\s*)([^$B]+\s*)$PACKR/$1$PACKR/;
                $FB = "\\".$1;
                $pattern = $2.$pattern;
            }
            elsif (0 != bracketDepth(0, $pattern, "[{(<")) {
                # Brackets were not matched.
                # Add characters from punctuation to front of pattern and loop.
                $input =~ s/([$B]\s*)([^$B]+$FB\s*)$PACKR/$1$PACKR/;
                $FB = "\\".$1;
                $pattern = $2.$pattern;
            }
            else {
                last;
            }
        }

        setInput($input);  # TBD: find a more efficient way to do this

        push @packExpansions, $pattern;
        $packNum = @packExpansions;
    }

    for my $pattern (@packExpansions) {
        for my $ident (@packIdents) {
            $pattern =~ s/\b$ident\b/${ident}_\@/g;
        }
    }

    trace("markPackExpansion", "AFTER XFORM = [\n%s\n]", $input);
    trace("markPackExpansion", "EXPANSIONS =\n    \"%s",
          join("\"\n    \"", @packExpansions));

    return @packExpansions;
}

# Create multiple copies of '$buffer', replacing each '__PACK_V#R__' or
# '__PACK_T#R__' pattern with an expansion of the parameter packs in
# '@packExpansions' such that on each copy has a longer expansion then the
# previous copy. The first copy has an exapnsion length of 0 and the last copy
# has an expansion length of '$maxArgs'.  The generated copies are returned as
# a list of strings. Thus, if $buffer is: ..  template <__PACK_T0R__> void
# f(__PACK_T1R__); ..  and '$maxArgs' is 2 and '@packExpansions is ("class
# T_@", "const T_@& v_@"), then this function will return the following list
# of three strings: ..  ( "void f();", "template <class T_1> void
# f(const T_1& v_1);", "template <class T_1, class T_2> void f(const T_1& v_1,
# const T_2& v_2;" ) ..
sub repeatPacks($$@)
{
    my ($buffer, $maxArgs, @packExpansions) = @_;

    # '@appliedPackExpansions' will hold an entry for each parameter pack.  As
    # the parameter packs are applied repeatedly, with a repetition count of
    # 0 through '$maxArgs', '@appliedPackExpansions' will accumulate the entire
    # applied expansion up to that point, growing longer with each
    # application.  Thus, if '$parameterPacks[$x]' is 'XYZ_@& abc_@', then
    # when '$repCount' is 2, '$appliedPackExpansions[$x]' will be 'XYZ_1&
    # abc_1, XYZ_2& abc_2'
    my @appliedPackExpansions;
    my $output;

    # If $maxArgs is 2 digits, then pad all argument counts to 2 digits or 2
    # characters (with leading space).
    my $digitPad = ($maxArgs > 9) ? "0" : "";
    my $spacePad = ($maxArgs > 9) ? " " : "";

    for (my $repCount = 0; $repCount <= $maxArgs; ++$repCount)
    {
        my $workingBuffer = $buffer;

        # Express $repCount as a decimal string of 2 characters if $maxArg > 9
        # and 1 character otherwise.  $repString is used for putting an
        # integer literal into the generated code; $repIdString is used for
        # putting the rep count as part of an identifier.
        my $repString   = (($repCount > 9) ? "" : $spacePad).$repCount;
        my $repIdString = (($repCount > 9) ? "" : $digitPad).$repCount;

        # For now, all packs must be the same length.  Replace __PACKSIZE_#__
        # with the expansion length, regardless of the pack to which it refers.
        $workingBuffer =~ s/__PACKSIZE_[0-9]+__/${repString}u/g;

        for (my $expandNum = 0; $expandNum < @packExpansions; ++$expandNum)
        {
            $workingBuffer =~ m/(.*)__PACK_([VT])$expandNum([RF])__(.*)/g or
                fatal("Can't find pack $expandNum in working buffer");
            my $packStart = $+[1];    # Start of pack
            my $packType  = $2;       # 'T' for type, 'V' for value.
            my $isFill    = ($3 eq 'F');
            my $packEnd   = $-[4];    # One past end of pack
            my $packLen   = $packEnd - $packStart;

            # For class specializations with fill-parameters, express the
            # number of fill parameters as a 2-character decimal string.
            my $fillCountStr = ((($maxArgs - $repCount) > 9) ? "" : $spacePad).
                ($maxArgs - $repCount);
            my $FILL = "BSLS_COMPILERFEATURES_FILL".$packType."(".$fillCountStr.")";

            my $expansionTerm = $packExpansions[$expandNum];
            my $replacement = "";

            if ($repCount == 0) {
                # push @appliedPackExpansions, "";

                my $preDelim = "";  # optional comma or colon before pack
                pos($workingBuffer) = $packStart;
                $preDelim = $1 if ($workingBuffer =~ m/([ \t]*[,:]\s*)\G/g);

                my $postDelim = ""; # optional comma after pack
                pos($workingBuffer) = $packEnd;
                $postDelim = $1 if ($workingBuffer =~ m/\G(\s*,\s*)/g);

                unless ($isFill) {
                    if ($postDelim) {
                        # There is a comma after the pack and pack expansion
                        # is empty.  Remove comma after pack.
                        $packLen += length($postDelim);
                    }
                    elsif ($preDelim) {
                        # There is a comma or colon before the pack and no
                        # comma after the pack and the pack expansion is
                        # empty.  Remove comma or colon before the pack.
                        $packLen += length($preDelim);
                        $packStart = $packEnd - $packLen;
                    }
                }

                push @appliedPackExpansions, "";
            }
            else {
                # Replace '@' with expansion number to get new expansion term
                $expansionTerm =~ s/\@/$repIdString/g;
            }

            my $appliedPackExpansion = $appliedPackExpansions[$expandNum];
            if ($repCount > 0) {
                $appliedPackExpansion .= ",\n" if ($repCount > 1);
                $appliedPackExpansion .= $expansionTerm;
                $replacement = $appliedPackExpansion;
            }

            if ($isFill) {
                $replacement .= ",\n" if ($replacement);
                $replacement .= $FILL;
            }

            # substr($workingBuffer, $packStart, $packLen, $replacement);
            $workingBuffer = replaceAndFitOnLine($workingBuffer,
                                                 $packStart, $packLen,
                                                 $replacement);

            $appliedPackExpansions[$expandNum] = $appliedPackExpansion;
        } # end for $expandNum

        $output .= $workingBuffer."\n";

    } # end for $repCount

    return $output;
}

sub transformVariadicFunction($$$;$)
{
    my ($templateBegin, $templateHeadEnd, $templateEnd, $isVariadic) = @_;

    my $buffer = stripComments(substr($input, $templateBegin,
                                      $templateEnd - $templateBegin));

    return $buffer unless ($isVariadic);

    pushInput($buffer);
    my @packExpansions = markPackExpansions();

    # Find functions or variables that fit one of the following patterns:
    #..
    #  template <class... T>
    #  rettype classname<T...>::f( args )
    #..
    # or
    #..
    #  template <class... T>
    #    template <params>
    #  rettype classname<T...>::f( args )
    #..
    # or
    #..
    #  template <class...T>
    #  vartype classname<T...>::variable = initialization;
    #..
    # In other words, look for out-of-line definitions of member functions or
    # static member variables of variadic classes.  For such members, replace
    # the '__PACK_[TV]#R__' marker just before the '>::' with '__PACK_[TV]#F__'
    # indicating that the parameter expansion should include the nil
    # arguments that fill out the template argument list.

    my $pos = 0;
    while (cppSearch(qr/template\s*<[^{;]+__PACK_[TV][0-9]+(R)__\s*>\s*::/,
                     $pos))
    {
        substr($input, $cppMatchStart[1], 1) = 'F';
        $pos = $cppMatchEnd[0];
    }

    $buffer = $input;
    popInput();

    # Expand parameter packs
    $buffer = repeatPacks($buffer, $maxArgs, @packExpansions);

    # Remove empty "template <>" prefixes.  These are non-template functions.
    $buffer =~ s/\btemplate\s*<\s*>\s*//g;

    return $buffer;
}

sub transformVariadicClass($$$)
{
    my ($templateBegin, $templateHeadEnd, $templateEnd, $isVariadic) = @_;

    return noopTemplateTransform($templateBegin,
                                 $templateHeadEnd,
                                 $templateEnd) unless ($isVariadic);

    trace("transformVariadicClass", "TEMPLATE = [%s]",
          substr($input, $templateBegin, $templateEnd - $templateBegin));

    my @templateParams = getTemplateParams($templateBegin);

    cppSearch(qr/\G\s*(class|struct)\s*([[:word:]]+)\b(<)?/, $templateHeadEnd);
    my $classOrStruct  = $cppMatch[1];
    my $className      = $cppMatch[2];
    my $specialization = $cppMatch[3];
    my $classHdrEnd    = $cppMatchEnd[2];

    my $buffer;
    if ($specialization) {
        # Declaration is already a class template partial specialization.
        # Don't modify the declaration.
        $classHdrEnd = findMatchingBrace('<', $cppMatchStart[3])+1;

        $buffer = substr($input, $templateBegin,
                         $classHdrEnd - $templateBegin);
    }
    else {
        # Modify class declaration to look like a template specialization.
        $buffer = substr($input, $templateBegin,
                         $cppMatchEnd[2] - $templateBegin);
        my $sep = "<";
        for my $param (@templateParams) {
            $buffer .= $sep;
            $buffer .= $param->[1];
            $buffer .= "..." if ($param->[0] =~ m/\.\.\./);
            $sep = ", ";
        }
        $buffer .= ">";
    }

    trace2("transformVariadicClass", "specialization buffer=[%s]", $buffer);

    $buffer .= transformForwarding(substr($input, $classHdrEnd,
                                          $templateEnd - $classHdrEnd));

    pushInput($buffer);
    my @packExpansions = markPackExpansions();
    $buffer = $input;
    popInput();

    my $output = "";

    # Generate forward-reference for the primary template, with all of the
    # variadic parameters present but defaulted.  Suppress this primary
    # template if the class we are expanding is a partial specialization.
    unless ($specialization) {
        $output .= "template <";
        my $indent = "          ";
        my $sep = "";
        for my $param (@templateParams) {
            my ($paramType, $paramName) = @$param;
            if ($paramType =~ s/\.\.\.//) {
                my $paramNil = ($paramType =~ m/(struct|class)/ ?
                                "BSLS_COMPILERFEATURES_NILT" :
                                "BSLS_COMPILERFEATURES_NILV");
                for (my $i = 0; $i < $maxArgs; ++$i) {
                    $output .= $sep;
                    $sep = ",\n".$indent;
                    $output .= sprintf("%s %s_%d = %s", $paramType,
                                       $paramName, $i, $paramNil);
                }
                $output .= $sep . "$paramType = $paramNil";
            }
            else {
                $output .= $sep;
                $sep = ",\n".$indent;
                $output .= $paramType." ".$paramName;
            }
        }
        $output .= ">\n".$classOrStruct." ".$className.";\n\n";
    }

    $output .= repeatPacks($buffer, $maxArgs, @packExpansions);
    trace("transformVariadicClass", "OUTPUT = [%s]", $output);
    return $output;
}

# Transforms the specified '$buffer', calling the specified
# '$transformFunction', '$transformClass', '$transformVariadicFunction' or
# '$transformVariadicClass' on each template found.  Return the transformed
# results.
sub transformTemplates($$$)
{
    my ($buffer, $transformFunction, $transformClass) = @_;

    trace("transformTemplates", "buffer = [%s]", $buffer);

    # Line and column at start of this segment
    my ($lineNum, $col) = lineAndColumn(pos($input));
    my $isClass = 0;

    pushInput($_[0]);
    my $output = "";

    my $pos = 0;
    while ($pos < $inputEnd)
    {
        # Find start of a template.
        last unless cppSearch(qr/[ \t]*\btemplate\s*</, $pos);
        my $templateBegin = $cppMatchStart[0];

        # Copy everything before the template to output.
        $output .= stripComments(substr($input, $pos, $templateBegin - $pos));

        # Find end of template parameter list
        $pos = findMatchingBrace('<', $templateBegin);

        while (cppSearch(qr/\G\s*template\s*</, $pos)) {
            # Template member of a template class, defined outside of the
            # class.
            $pos = findMatchingBrace('<', $pos);
        }

        my $templateHeadEnd = $pos;

        # For debugging only
        my $templateHeadLine = lineAndColumn($pos);
        $templateHeadLine += $lineNum;
        trace2("transformTemplates",
               "Template header ends at line %d", $templateHeadLine);

        # If the next word is "class" or "struct", then this is a class
        # template.
        $isClass = cppSearch(qr/\G\s*(?:class|struct)\s*[[:word:]]+\b/, $pos);

        # Saw start of template, now look for end of template: either a
        # semicolon or a matched set of curly braces, whichever comes first.
        cppSearch(qr/[{;]/, $pos) or fatal("Cannot find end of template");
        my $templateEnd = $cppMatchEnd[0];
        if ($cppMatchAll eq '{') {
            $templateEnd = findMatchingBrace('{', $templateEnd - 1);
            if ($isClass) {
                # Class template must be terminated by a semicolon after the
                # close curly brace.
                cppSearch(qr/;/, $templateEnd) or fatal("Missing semicolon");
                $templateEnd = $cppMatchEnd[0];
            }
        }

        # Include trailing end-of-line in template definition
        if (cppSearch(qr/\G[ \t]*\n/, $templateEnd)) {
            $templateEnd = $cppMatchEnd[0];
        }

        # Check within the template header for a variadic parameter.
        my $isVariadic = cppSearch(qr/\b($packTypesStr)\s*\.\.\./,
                                   $templateBegin, $templateHeadEnd);

        if ($isClass) {
            $output .= &$transformClass($templateBegin,
                                        $templateHeadEnd,
                                        $templateEnd,
                                        $isVariadic);
        }
        else {
            $output .= &$transformFunction($templateBegin,
                                           $templateHeadEnd,
                                           $templateEnd,
                                           $isVariadic);
        }

        $pos = $templateEnd;
    }

    $output .= stripComments(substr($input, $pos));

    popInput();
    trace("transformTemplates", "output = [%s]", $output);
    return $output;
}

# Transform all uses of perfect forwarding within top-level function templates
# in the specified input buffer into C++03-compatible code.
sub transformForwarding($)
{
    return transformTemplates($_[0], \&replaceForwarding,
                              \&noopTemplateTransform);
}

# Transform all top-level variadic templates in the specified input buffer
# into C++03-compatible code by converting them into repeated copies with
# different numbers of parameters.
sub transformVariadics($)
{
    return transformTemplates($_[0], \&transformVariadicFunction,
                              \&transformVariadicClass);
}

# Extract script arguments from a proprocessor directive.  Looks for comments
# with the pattern: '$var-args=n' and/or '$local-var-args=m' and returns (n, m).
# The values of 'n' and/or 'm' will be 'undef' if the '$var-args' or
# '$local-var-args' argument, respectively, is absent.
#
# Usage:
#   getArgsFromPPLine($ppLine)
#
sub getArgsFromPPLine($;$$)
{
    my ($ppLine) = @_;
    my ($maxArgs, $localMaxArgs) = (0, 0);

    # Look for // $var-args=n
    if ($ppLine =~ m{/[^/*].*\$var-args=([[:digit:]]+)}) {
        $maxArgs = $1;
    }

    # Look for // $local-var-args=n
    if ($ppLine =~ m{/[^/*].*\$local-var-args=([[:digit:]]+)}) {
        $localMaxArgs = $1;
    }

    return ($maxArgs, $localMaxArgs);
}

###############################################################################
#                            MAIN PROGRAM                                     #
###############################################################################

sub usage {
    print <<EOT;
Usage: sim_cpp11_features.pl [ --output=<filename> ]
                             [ --debug ]
                             [ --clean ]
                             [ --var-args=<max-args> ]
                             { <input-file> | - | TEST }
EOT
    exit 1;
}

sub main() {
    my $inputFilename;
    my $outputFilename;
    my $maxArgsOpt = 0;
    my @traceLabels;

    $commandLine = makeCommandLine($0, @ARGV);

    GetOptions("output=s"      => \$outputFilename,
               "debug=i"       => \$debug,
               "trace=s"       => \@traceLabels,
               "clean"         => \$clean,
               "var-args=i"    => \$maxArgsOpt) or usage("Invalid option");

    Util::Message::set_debug($debug);

    # Multiple trace labels can be specified using either a comma-separated
    # list or multiple --trace options or both.  Combine them all into one
    # array of labels.
    @traceLabels = split(/,/, join(',', @traceLabels));
    for my $traceLabel (@traceLabels) {
        my ($label, $level) = split(/:/, $traceLabel);
        $level = $level || 1;  # "xyz" is equivalent to "xyz:1"
        $level = $level + 0;   # Make numeric
        $traceCtrls{$label} = $level;
    }

    my $timestamp = localtime();
    my $timestampPrefix = "Generated by sim_cpp11_features.pl on ";
    my $timestampComment = $timestampPrefix . $timestamp;

    usage("Must specifiy and input file name, -, or TEST") unless (@ARGV);
    usage("Only one input may be specified") unless (1 == @ARGV);

    $dummyChar = $debug ? "." : "\267";

    $inputFilename = $ARGV[0];

    if ("TEST" eq $inputFilename) {
        $inputFilename = "__DATA__";
        open INPUT, "<& DATA" or fatal("Cannot re-open DATA for reading\n");
    }
    else {
        open INPUT, "<$inputFilename"
            or fatal("Cannot open $inputFilename for reading\n");
    }

    # Read contents of INPUT file and use to set input
    {
        local $/ = undef; # Slurp mode
        my $filedata = <INPUT>;
        $filedata =~ s/\r//g;  # Normalize newlines

        # Replace old timestamp with new timestamp.  Thus, if the original
        # string and the post-processed string differ only in their
        # timestamps, they will compare equal after this replacement.
        $filedata =~ s/$timestampPrefix.*$/$timestampComment/mg;

        setInput($filedata);
        close INPUT
    }

    my $pos = 0;
    my $output = "";

    # Search for '#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES' or
    #            '#ifndef BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES'
    my $simCpp11Macro = "BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES";
    my $simVariadicsMacro = "BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES";
    while (cppSearch(qr/^[ \t]*\#[ \t]*(if(?:ndef[ \t]|[ \t]+!)[ \t]*$simCpp11Macro)\b(.*)\n/m,
                     $pos))
    {
        my $startVerbetim = $pos;
        my $endVerbetim = $cppMatchStart[0];

        # Look for command-line arguments on preprocessor line
        my ($newMaxArgs, $localMaxArgs) = getArgsFromPPLine($cppMatch[2]);
        my $argsComment = "";
        if ($localMaxArgs) {
            $argsComment .= " \$local-var-args=$localMaxArgs";
        }
        # $maxArgsOpt overrides $newMaxArgs if both are specified.
        $maxArgs = $maxArgsOpt || $newMaxArgs || $maxArgs;
        if ($newMaxArgs || $maxArgs != $defaultMaxArgs) {
            # Add $var-args comment if explicitly specified or if $maxArgs
            # differs from default.
            $argsComment .= " \$var-args=$maxArgs";
            $defaultMaxArgs = $maxArgs;
        }
        $argsComment = " //".$argsComment if ($argsComment);

        # Output code before the #if
        $output .= substr($input, $startVerbetim,
                          $endVerbetim - $startVerbetim);

        # Output cannonical form of #if
        $output .= "#if !$simCpp11Macro$argsComment\n";

        my $startCpp11Segment = $cppMatchEnd[0];  # start C++11 code segment
        my $endCpp11Segment;
        $pos = $startCpp11Segment;

        # Now look for the matching #else, #elif, or #endif, handling any
        # nested #if's along the way.
        my $depth = 1;
        my $ppDirective;  # Preprocessor directive
        while (cppSearch(qr{^[ \t]*\#[ \t]*(\w+).*\n}m, $pos)) {
            $pos = $cppMatchEnd[0];
            $ppDirective = $cppMatch[1];
            if (1 == $depth and $ppDirective =~ /^(else|elif|endif)$/ ) {
                $endCpp11Segment = $cppMatchStart[0];
                debug("ppDirective = [".$cppMatchAll."]");
                last;
            }
            $depth++ if ($ppDirective =~ /^if/);
            --$depth if ($ppDirective eq "endif");
        }

        $endCpp11Segment or
            fatal("Unmatched #if:\n".displayPos($endVerbetim));

        my $cpp11Segment = substr($input, $startCpp11Segment,
                                  $endCpp11Segment - $startCpp11Segment);

        $output .= $cpp11Segment;

        if ($ppDirective =~ m/^(?:else|elif)$/) {
            # Consume and discard input until matching '#endif'.  $depth == 1
            # here.
            while (cppSearch(qr/^[ \t]*\#[ \t]*(\w+).*\n/m, $pos)) {
                $pos = $cppMatchEnd[0];
                $ppDirective = $cppMatch[1];
                $depth++ if ($ppDirective =~ /^if/);
                --$depth if ($ppDirective eq "endif");
                last if ($depth < 1);
            }
        }
        pos($input) = $pos;

        if ($clean) {
            # Clean the generated code: just don't produce anything.
            $output .= "#endif\n";
        } else {
            # Temporarily change $maxArgs
            $maxArgs = $localMaxArgs if ($localMaxArgs);

            # Apply the forwarding workaround to the extracted segment.
            my $forwardingWorkaround = transformForwarding($cpp11Segment);
            chomp $forwardingWorkaround;

            # Apply the variadic template simulation on top of the forwardng
            # workaround.
            my $variadicSimulation = transformVariadics($forwardingWorkaround);
            chomp $variadicSimulation;

            # restore $maxArgs
            $maxArgs = $defaultMaxArgs;

            # If the variadic template simulation is identical to the forwarding
            # workaround alone, then there were no variadics in the segment.
            # Output the variadics simulation only if these strings are
            # different.
            if ($variadicSimulation ne $forwardingWorkaround) {
                $output .= <<EOT;
#elif $simVariadicsMacro
$generatedCodeBegin
// Generator command line: $commandLine
$variadicSimulation
EOT
            }

            $output .= <<EOT;
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
$forwardingWorkaround
$generatedCodeEnd
#endif
EOT
        }
    }

    $output .= substr($input, $pos, $inputEnd - $pos);

    if (! $outputFilename || $outputFilename eq $inputFilename) {
        if ($inputFilename eq "-") {
            $outputFilename = "-";
        }
        elsif ($inputFilename eq "__DATA__") {
            if ($output eq $input) {
                message("File is unchanged");
                unlink "sim_cpp11_features.data.h";
                unlink "sim_cpp11_features.output.h";
                return 0;
            }
            else {
                open INPUTDATA, "> sim_cpp11_features.data.h";
                print INPUTDATA $input;
                close INPUTDATA;
                $outputFilename = "sim_cpp11_features.output.h";
                message("File is changed.\n".
                        "Input in sim_cpp11_features.data.h,".
                        " Output in sim_cpp11_features.output.h");
            }
        }
        elsif ($output eq $input) {
            debug("File is unchanged");
            return 0;  # No change to file
        }
        else {
            # Overwrite input file
            $outputFilename = $inputFilename;
        }
    }

    open OUTPUT, ">$outputFilename" or
        fatal("Cannot open $outputFilename for writing\n");

    print OUTPUT $output;
    close OUTPUT;

    if ($inputFilename eq "__DATA__") {
        # Got here only if output does not match input
        system("diff sim_cpp11_features.data.h sim_cpp11_features.output.h");
        return 1;
    }

    return 0;
}

exit main();

# Unit tests
sub testCppSearch()
{
    my $teststr = ("abc // def\n".
                   "def /* *ghi' */ ghi\n".
                   '"jk\\"l"jkl'."\n".
                   "'m' m '\\n' n * end\n");
    print "\n*** testCppSearch: teststr =\n$teststr";
    setInput($teststr);

    for my $re (qr/a/, qr/e/, qr/[ef]+/, qr/g/, qr/\*/, qr/j[^a]/, qr/l/, qr/m/,
                qr/n/, qr/z/, qr/f\s*g/) {

        my $pos = 0;
        while (defined($pos)) {
            print "$re\t$pos\t";

            # Call in array context
            my @found = cppSearch($re, $pos);
            my ($start, $end) = ($cppMatchStart[0], $cppMatchEnd[0]);
            # Call again in scalar context
            my $found = cppSearch($re, $pos);
            $pos = $cppMatchEnd[0];
            if ($found) {
                fatal("\$found but not \@found") unless (@found);
                fatal("mismatch end") unless ($end == $pos);
            }
            else {
                fatal("\@found but not \$found") unless (! @found);
            }
            if (@found) {
                print "[@found]\t$start\t$end\n";
            }
            else {
                print "undef\n";
            }
        }
    }
}

# testCppSearch();

sub testLineAndColumn()
{
    setInput("abc\ndefg\n\nx");
    print "input = \n$input";
    for (my $pos = 0; $pos <= $inputEnd; ++$pos) {
        my ($line, $col) = lineAndColumn($pos);
        my $scalarLine = lineAndColumn($pos);
        fatal("$line mismatch") unless ($line == $scalarLine);
        print "$pos\t($line $col)\n";
    }

    print displayPos(6);
    print displayPos(8);
}

# testLineAndColumn();

sub testFindMatchingBrace()
{
    setInput("struct x { int hello(foo) { std::cout \"hello}\"; } };\n".
             "template <class A, class B>\n".
             "class Foo<A, B, (sizoef(A) < 16)> {\n".
             "    A mismatched[SZ; // missing ]\n".
             "};\n");
    print "input =\n$input";

    my @tests = (0  => '{',
                 10 => '(',
                 54 => '<',
                 81 => '<',
                 81 => '(',
                 92 => '<',
                 121 => '[');

    for (my $i = 0; $i < @tests; $i += 2) {
        my $pos = $tests[$i];
        my $brace = $tests[$i + 1];

        print "***** Find $brace at $pos\n";
        print displayPos($pos);
        eval {
            my $found = findMatchingBrace($brace, $pos);
            print "Found matching brace at ".($found?$found-1:"undef")."\n";
            print displayPos($found - 1) if ($found);
        }
    }
}

# testFindMatchingBrace();

sub testStripComments()
{
    my $input =
        "text // C++ comment\n".
        "text /* C comment */ more text\n".
        "text /* multi-line\n".
        "      * comment.\n".
        "      */\n".
        "text \"string\" more text\n".
        "    // multi-line\n".
        "    // comment block\n".
        "text 'x' more text //comment\n";

    my $single_ws =
        "text\n".
        "text more text\n".
        "text\n".
        "text \"string\" more text\n".
        "text 'x' more text\n";

    my $keep_nl =
        "text\n".
        "text more text\n".
        "text\n".
        "\n".
        "\n".
        "text \"string\" more text\n".
        "\n".
        "\n".
        "text 'x' more text\n";

    my $keep_len =
        "text               \n".
        "text                 more text\n".
        "text              \n".
        "                \n".
        "        \n".
        "text \"string\" more text\n".
        "                 \n".
        "                    \n".
        "text 'x' more text          \n";

    my $result;

    $result = stripComments($input);
    print "\nstripComments(input) returned \n$result"
        unless ($result eq $single_ws);

    $result = stripComments($input, "single-ws");
    print "\nstripComments(input, single-ws) returned \n$result"
        unless ($result eq $single_ws);

    $result = stripComments($input, "keep-nl");
    print "\nstripComments(input, keep-nl) returned \n$result"
        unless ($result eq $keep_nl);

    $result = stripComments($input, "keep-len");
    print "\nshroudCommentsAndStrings(input, keep-len) returned \n$result"
        unless ($result eq $keep_len);
}

# testStripComments();

sub testShroudCommentsAndStrings()
{
    local $dummyChar = '.';  # More convenient to type than "\267"

    my $input =
        "text // C++ comment\n".
        "text /* C comment */ more text\n".
        "text /* multi-line\n".
        "      * comment.\n".
        "      */\n".
        "text \"string\" more text\n".
        "text 'x' more text //comment\n";

    my $shrouded =
        "text               \n".
        "text                 more text\n".
        "text              \n".
        "                \n".
        "        \n".
        "text \"......\" more text\n".
        "text '.' more text          \n";

    my $result;

    $result = shroudCommentsAndStrings($input);
    print "\nshroudCommentsAndStrings(input) returned \n$result"
        unless ($result eq $shrouded);
}

# testShroudCommentsAndStrings();

sub testReplaceAndFitOnLine {
    my $doTest = sub {
        my ($working, $repl) = @_;

        $working =~ s/^(~?)/$1                /mg;
        $working =~ m/([:,]\s*)?(XXX*)(\s*,[ \t]*)?/;
        my $packStart = $-[2];
        my $packEnd   = $+[2];

        if (! $repl) {
            if ($3) {
                $packEnd = $+[3];
            }
            elsif ($1) {
                $packStart = $-[1];
            }
        }

        my $packLen = $packEnd - $packStart;
        if ($working =~ /^~/) {
            pushInput($working);
            replaceAndFitOnLine($shroudedInput, $packStart, $packLen, $repl);
            $working = $input;
            popInput();
        }
        else {
            $working =
                replaceAndFitOnLine($working, $packStart, $packLen, $repl);
        }

        return $working;
    };

    my @in = ("theResult = functionCall(XXX);",
              "theResult = functionCall(a, b, XXX);",
              "theResult = functionCall(XXX, d, e, f);",
              "theResult = functionCall(a, b, XXX, d, e, f);",
              "theResult = functionCall(a, b,\n".
              "                         XXX);",
              "theResult = functionCall(XXX\n".
              "                       , d, e, f);",
              "theResult = functionCall(a, b\n".
              "                       , XXX\n".
              "                       , d, e, f);",
              "pre();\n   theResult = functionCall(a, XXX);\npost()",
              "theResult = aMuchLongerFunctionCallThatNears79Cols(a, XXX, b);",
              "~theResult = /* text */ functionCall(t, u, XXX, x, y, z);"
        );

    my @repl = ("",
                "arg1",
                "arg1,\narg2",
                "BSL_M_FORWARD(arg1),\n    BSL_M_FORWARD(arg2)",
        );

    for my $in (@in) {
        for my $repl (@repl) {
            print &$doTest($in, $repl), "\n";
        }
    }
}

#testReplaceAndFitOnLine();

0;

__DATA__

#ifndef INCLUDED_BSL_M
#   include <bsls_m.h>
#endif

// Sample input
void f(); // Not a template

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3
#  ifdef NESTED
template <int ...B, class... A>
void foo(C<B...> *c, A&&... a)
    // This function does the foolish thing.  It is a variadic function and is
    // fully documented.  The specified 'c' parameter is a single argument
    // that uses a parameter pack in a deduced context.  The specified 'a' is
    // a variadic argument.
{
    D<A...> d(bsl::forward<A>(a)...);
    bar(sizeof... (A), c, &d);

    # Identical expansion twice in one line:
    f(bsl::forward<A>(a)...); g(bsl::forward<A>(a)...);
}
#  endif // NESTED

template <class T>
int bar(int a, T&& v)
    // Non-variadic function template that uses perfect forwarding.
{
    xyz(a, bsl::forward<T>(v));
}

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Generator command line: sim_cpp11_features.pl TEST
#  ifdef NESTED
void foo(C<> *c)
{
    D<> d();
    bar(0u, c, &d);

    # Identical expansion twice in one line:
    f(); g(
                                              );
}

template <int B_1, class A_1>
void foo(C<B_1> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A_1) a_1)
{
    D<A_1> d(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1));
    bar(1u, c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1)); g(
                                             BSLS_COMPILERFEATURES_FORWARD(A_1,
                                             a_1));
}

template <int B_1,
          int B_2, class A_1,
                   class A_2>
void foo(C<B_1,
           B_2> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A_1) a_1,
                    BSLS_COMPILERFEATURES_FORWARD_REF(A_2) a_2)
{
    D<A_1,
      A_2> d(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
             BSLS_COMPILERFEATURES_FORWARD(A_2, a_2));
    bar(2u, c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
      BSLS_COMPILERFEATURES_FORWARD(A_2, a_2)); g(
                                             BSLS_COMPILERFEATURES_FORWARD(A_1,
                                             a_1),
                                             BSLS_COMPILERFEATURES_FORWARD(A_2,
                                             a_2));
}

template <int B_1,
          int B_2,
          int B_3, class A_1,
                   class A_2,
                   class A_3>
void foo(C<B_1,
           B_2,
           B_3> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A_1) a_1,
                    BSLS_COMPILERFEATURES_FORWARD_REF(A_2) a_2,
                    BSLS_COMPILERFEATURES_FORWARD_REF(A_3) a_3)
{
    D<A_1,
      A_2,
      A_3> d(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
             BSLS_COMPILERFEATURES_FORWARD(A_2, a_2),
             BSLS_COMPILERFEATURES_FORWARD(A_3, a_3));
    bar(3u, c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A_1, a_1),
      BSLS_COMPILERFEATURES_FORWARD(A_2, a_2),
      BSLS_COMPILERFEATURES_FORWARD(A_3, a_3)); g(
                                             BSLS_COMPILERFEATURES_FORWARD(A_1,
                                             a_1),
                                             BSLS_COMPILERFEATURES_FORWARD(A_2,
                                             a_2),
                                             BSLS_COMPILERFEATURES_FORWARD(A_3,
                                             a_3));
}

#  endif

template <class T>
int bar(int a, BSLS_COMPILERFEATURES_FORWARD_REF(T) v)
{
    xyz(a, BSLS_COMPILERFEATURES_FORWARD(T, v));
}
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
#  ifdef NESTED
template <int ...B, class... A>
void foo(C<B...> *c, BSLS_COMPILERFEATURES_FORWARD_REF(A)... a)
{
    D<A...> d(BSLS_COMPILERFEATURES_FORWARD(A, a)...);
    bar(sizeof... (A), c, &d);

    # Identical expansion twice in one line:
    f(BSLS_COMPILERFEATURES_FORWARD(A, a)...); g(
                                              BSLS_COMPILERFEATURES_FORWARD(A,
                                              a)...);
}
#  endif

template <class T>
int bar(int a, BSLS_COMPILERFEATURES_FORWARD_REF(T) v)
{
    xyz(a, BSLS_COMPILERFEATURES_FORWARD(T, v));
}

// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
// The following is a variadic template function
template <typename... A>  // Comments are removed
    void g(const vector<A>&... a)
    {
        if (q()) {
            xyz(forward<A, int>(a)...
                );
        }
    }

template <int X, class ...T>
class C
{
public:
    typename mf<X>::type member(const T&... z);

    template <class U> void member2(U&& v);
};

template <int X, class ...T>
typename mf<X>::type C<X, T...>::member(const T&... z)
{
}

template <int X, class ...T>
    template <class U>
void C<X, T...>::member2(U&& v)
{
    q(std::forward< U >( v ));
}

template <int X, unsigned ...V>
struct D
{
    typename mf<X>::type member();
};

template <int X, unsigned ...V>
typename mf<X>::type D<V...>::member()
{
}

template <class ...T>
    X::X(const T&... args) : v(args)... { }

template <typename T>
    void z(const vector<T>& v);  // No variadics

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Generator command line: sim_cpp11_features.pl TEST
void g()
    {
        if (q()) {
            xyz(
                );
        }
    }

template <typename A_1>
    void g(const vector<A_1>& a_1)
    {
        if (q()) {
            xyz(forward<A_1, int>(a_1)
                );
        }
    }

template <typename A_1,
          typename A_2>
    void g(const vector<A_1>& a_1,
           const vector<A_2>& a_2)
    {
        if (q()) {
            xyz(forward<A_1, int>(a_1),
                forward<A_2, int>(a_2)
                );
        }
    }

template <typename A_1,
          typename A_2,
          typename A_3>
    void g(const vector<A_1>& a_1,
           const vector<A_2>& a_2,
           const vector<A_3>& a_3)
    {
        if (q()) {
            xyz(forward<A_1, int>(a_1),
                forward<A_2, int>(a_2),
                forward<A_3, int>(a_3)
                );
        }
    }


template <int X,
          class T_0 = BSLS_COMPILERFEATURES_NILT,
          class T_1 = BSLS_COMPILERFEATURES_NILT,
          class T_2 = BSLS_COMPILERFEATURES_NILT,
          class = BSLS_COMPILERFEATURES_NILT>
class C;

template <int X>
class C<X>
{
public:
    typename mf<X>::type member();

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};

template <int X, class T_1>
class C<X, T_1>
{
public:
    typename mf<X>::type member(const T_1& z_1);

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};

template <int X, class T_1,
                 class T_2>
class C<X, T_1,
           T_2>
{
public:
    typename mf<X>::type member(const T_1& z_1,
                                const T_2& z_2);

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};

template <int X, class T_1,
                 class T_2,
                 class T_3>
class C<X, T_1,
           T_2,
           T_3>
{
public:
    typename mf<X>::type member(const T_1& z_1,
                                const T_2& z_2,
                                const T_3& z_3);

    template <class U> void member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v);
};


template <int X>
typename mf<X>::type C<X, BSLS_COMPILERFEATURES_FILLT(3)>::member()
{
}

template <int X, class T_1>
typename mf<X>::type C<X, T_1,
                          BSLS_COMPILERFEATURES_FILLT(2)>::member(
                                                                const T_1& z_1)
{
}

template <int X, class T_1,
                 class T_2>
typename mf<X>::type C<X, T_1,
                          T_2,
                          BSLS_COMPILERFEATURES_FILLT(1)>::member(
                                                                const T_1& z_1,
                                                                const T_2& z_2)
{
}

template <int X, class T_1,
                 class T_2,
                 class T_3>
typename mf<X>::type C<X, T_1,
                          T_2,
                          T_3,
                          BSLS_COMPILERFEATURES_FILLT(0)>::member(
                                                                const T_1& z_1,
                                                                const T_2& z_2,
                                                                const T_3& z_3)
{
}


template <int X>
    template <class U>
void C<X, BSLS_COMPILERFEATURES_FILLT(3)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}

template <int X, class T_1>
    template <class U>
void C<X, T_1,
          BSLS_COMPILERFEATURES_FILLT(2)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}

template <int X, class T_1,
                 class T_2>
    template <class U>
void C<X, T_1,
          T_2,
          BSLS_COMPILERFEATURES_FILLT(1)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}

template <int X, class T_1,
                 class T_2,
                 class T_3>
    template <class U>
void C<X, T_1,
          T_2,
          T_3,
          BSLS_COMPILERFEATURES_FILLT(0)
          >::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}


template <int X,
          unsigned V_0 = BSLS_COMPILERFEATURES_NILV,
          unsigned V_1 = BSLS_COMPILERFEATURES_NILV,
          unsigned V_2 = BSLS_COMPILERFEATURES_NILV,
          unsigned = BSLS_COMPILERFEATURES_NILV>
struct D;

template <int X>
struct D<X>
{
    typename mf<X>::type member();
};

template <int X, unsigned V_1>
struct D<X, V_1>
{
    typename mf<X>::type member();
};

template <int X, unsigned V_1,
                 unsigned V_2>
struct D<X, V_1,
            V_2>
{
    typename mf<X>::type member();
};

template <int X, unsigned V_1,
                 unsigned V_2,
                 unsigned V_3>
struct D<X, V_1,
            V_2,
            V_3>
{
    typename mf<X>::type member();
};


template <int X>
typename mf<X>::type D<BSLS_COMPILERFEATURES_FILLV(3)>::member()
{
}

template <int X, unsigned V_1>
typename mf<X>::type D<V_1,
                       BSLS_COMPILERFEATURES_FILLV(2)>::member()
{
}

template <int X, unsigned V_1,
                 unsigned V_2>
typename mf<X>::type D<V_1,
                       V_2,
                       BSLS_COMPILERFEATURES_FILLV(1)>::member()
{
}

template <int X, unsigned V_1,
                 unsigned V_2,
                 unsigned V_3>
typename mf<X>::type D<V_1,
                       V_2,
                       V_3,
                       BSLS_COMPILERFEATURES_FILLV(0)>::member()
{
}


X::X() { }

template <class T_1>
    X::X(const T_1& args_1) : v(args_1) { }

template <class T_1,
          class T_2>
    X::X(const T_1& args_1,
         const T_2& args_2) : v(args_1),
                              v(args_2) { }

template <class T_1,
          class T_2,
          class T_3>
    X::X(const T_1& args_1,
         const T_2& args_2,
         const T_3& args_3) : v(args_1),
                              v(args_2),
                              v(args_3) { }


template <typename T>
    void z(const vector<T>& v);
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <typename... A>
    void g(const vector<A>&... a)
    {
        if (q()) {
            xyz(forward<A, int>(a)...
                );
        }
    }

template <int X, class ...T>
class C
{
public:
    typename mf<X>::type member(const T&... z);

    template <class U> void member2(U&& v);
};

template <int X, class ...T>
typename mf<X>::type C<X, T...>::member(const T&... z)
{
}

template <int X, class ...T>
    template <class U>
void C<X, T...>::member2(BSLS_COMPILERFEATURES_FORWARD_REF(U) v)
{
    q(BSLS_COMPILERFEATURES_FORWARD(U,  v ));
}

template <int X, unsigned ...V>
struct D
{
    typename mf<X>::type member();
};

template <int X, unsigned ...V>
typename mf<X>::type D<V...>::member()
{
}

template <class ...T>
    X::X(const T&... args) : v(args)... { }

template <typename T>
    void z(const vector<T>& v);

// }}} END GENERATED CODE
#endif

template <class T>
class NonVaridadicClassWithVariadicMember
{
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $local-var-args=4
    template <class... U>
        NonVaridadicClassWithVariadicMember(const U&... u);

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Generator command line: sim_cpp11_features.pl TEST
    NonVaridadicClassWithVariadicMember();

    template <class U_1>
        NonVaridadicClassWithVariadicMember(const U_1& u_1);

    template <class U_1,
              class U_2>
        NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                            const U_2& u_2);

    template <class U_1,
              class U_2,
              class U_3>
        NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                            const U_2& u_2,
                                            const U_3& u_3);

    template <class U_1,
              class U_2,
              class U_3,
              class U_4>
        NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                            const U_2& u_2,
                                            const U_3& u_3,
                                            const U_4& u_4);

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
    template <class... U>
        NonVaridadicClassWithVariadicMember(const U&... u);

// }}} END GENERATED CODE
#endif
};

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
template <class T>
    template <class... U>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U&... u);

template <class... TYPE>
void Cls<TYPE...>::functionWithLongExpansion79Columns(TYPE&&... a, double b);

#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Generator command line: sim_cpp11_features.pl TEST
template <class T>
    NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember();

template <class T>
    template <class U_1>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U_1& u_1);

template <class T>
    template <class U_1,
              class U_2>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                        const U_2& u_2);

template <class T>
    template <class U_1,
              class U_2,
              class U_3>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U_1& u_1,
                                        const U_2& u_2,
                                        const U_3& u_3);


void Cls<BSLS_COMPILERFEATURES_FILLT(3)>::functionWithLongExpansion79Columns(
                                  double b);

template <class TYPE_1>
void Cls<TYPE_1,
         BSLS_COMPILERFEATURES_FILLT(2)>::functionWithLongExpansion79Columns(
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_1) a_1,
                                  double b);

template <class TYPE_1,
          class TYPE_2>
void Cls<TYPE_1,
         TYPE_2,
         BSLS_COMPILERFEATURES_FILLT(1)>::functionWithLongExpansion79Columns(
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_1) a_1,
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_2) a_2,
                                  double b);

template <class TYPE_1,
          class TYPE_2,
          class TYPE_3>
void Cls<TYPE_1,
         TYPE_2,
         TYPE_3,
         BSLS_COMPILERFEATURES_FILLT(0)>::functionWithLongExpansion79Columns(
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_1) a_1,
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_2) a_2,
                                 BSLS_COMPILERFEATURES_FORWARD_REF(TYPE_3) a_3,
                                  double b);

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <class T>
    template <class... U>
NonVaridadicClassWithVariadicMember<T>::
    NonVaridadicClassWithVariadicMember(const U&... u);

template <class... TYPE>
void Cls<TYPE...>::functionWithLongExpansion79Columns(
                                  BSLS_COMPILERFEATURES_FORWARD_REF(TYPE)... a,
                                  double b);

// }}} END GENERATED CODE
#endif

void h();

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class... CTOR_ARGS>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                                            CTOR_ARG&&       ctorArg,
                                            CTOR_ARGS&&...   ctorArgs)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        std::forward<CTOR_ARG>(ctorArg),
        std::forward<CTOR_ARGS>(ctorArgs)...,
        mechanism(allocator, IsBslma()));
}
#elif BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
// {{{ BEGIN GENERATED CODE
// The following section is automatically generated.  **DO NOT EDIT**
// Generator command line: sim_cpp11_features.pl TEST
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        mechanism(allocator, IsBslma()));
}

template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class CTOR_ARGS_1>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_1) ctorArgs_1)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_1, ctorArgs_1),
        mechanism(allocator, IsBslma()));
}

template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class CTOR_ARGS_1,
                                              class CTOR_ARGS_2>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_1) ctorArgs_1,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_2) ctorArgs_2)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_1, ctorArgs_1),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_2, ctorArgs_2),
        mechanism(allocator, IsBslma()));
}

template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class CTOR_ARGS_1,
                                              class CTOR_ARGS_2,
                                              class CTOR_ARGS_3>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_1) ctorArgs_1,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_2) ctorArgs_2,
                     BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS_3) ctorArgs_3)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_1, ctorArgs_1),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_2, ctorArgs_2),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS_3, ctorArgs_3),
        mechanism(allocator, IsBslma()));
}

#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <class ALLOCATOR_TYPE>
template <class ELEMENT_TYPE, class CTOR_ARG, class... CTOR_ARGS>
inline void
allocator_traits<ALLOCATOR_TYPE>::construct(ALLOCATOR_TYPE&  allocator,
                                            ELEMENT_TYPE    *elementAddr,
                           BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARG) ctorArg,
                      BSLS_COMPILERFEATURES_FORWARD_REF(CTOR_ARGS)... ctorArgs)
{
    BloombergLP::bslalg_ScalarPrimitives::construct(
        elementAddr,
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARG, ctorArg),
        BSLS_COMPILERFEATURES_FORWARD(CTOR_ARGS, ctorArgs)...,
        mechanism(allocator, IsBslma()));
}
// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
// Function with perfect forwarding but no variadics
template <typename A>
void forwardingFunction(A&& x);
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
template <typename A>
void forwardingFunction(BSLS_COMPILERFEATURES_FORWARD_REF(A) x);
// }}} END GENERATED CODE
#endif

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
// Non-template function
void nonTemplateFunction(int x);

// Template function with neither forwarding nor variadics.
template <typename X>
void normalTemplate(const X& v);
#else
// The generated code below is a workaround for the absence of perfect
// forwarding in some compilers.
void nonTemplateFunction(int x);

template <typename X>
void normalTemplate(const X& v);
// }}} END GENERATED CODE
#endif
