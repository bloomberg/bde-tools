package Source::Util::ParseTools;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK);
@ISA=qw(Exporter);
@EXPORT_OK=qw(slimSrcLines
              getParamUserTypes
              normalizeScopedName
              isCplusPlus);

use Text::Balanced qw(gen_delimited_pat);
use Symbols qw($NO_FOLLOW_MARKER $NOT_A_COMPONENT);
use Util::Message qw(fatal);
use Util::Test qw(ASSERT); #for testing only

#==============================================================================

=head1 NAME

Source::Util::ParseTools - file parsing tools

=head1 SYNOPSIS

use BDE::Util::Nomenclature qw(isPackage getPackageGroup);
use Source::Util::ParseTools qw(extractStatements);

my $src = "int i;\n// Comment\nint j;\n";
my $ref = slimSrcLines(\$src);

=head1 DESCRIPTION

This module provides utility functions used during processing of source files.

=head1 TEST DRIVERS

This module implement test drivers that may be invoked with:

perl -MSource::Util::ParseTools -e "Source::Util::ParseTools->slimSrcLine"
perl -MSource::Util::ParseTools -e "Source::Util::ParseTools->slimSrcLines"
perl -MSource::Util::ParseTools -e "Source::Util::ParseTools->normalizeScopedName"

=cut

#==============================================================================

=head1 SUBROUTINES

=cut

#==============================================================================

{
my $_inCommentBlk;
sub setInCommentBlk($) { $_inCommentBlk = $_[0] || 0; }
sub inCommentBlk()     { return $_inCommentBlk;  }

# Depth of nested #if 0 blocks.
# Nesting any #if block within an #if 0 block increases the nesting level
# An #else block doesn't change the nesting level unless it matches the
# top-most #if 0 block (in which case it set the nesting level to zero).
my $_ifZeroBlkDepth = 0;
sub setIfZeroBlkDepth(@) { $_ifZeroBlkDepth = $_[0] || 0; }
sub beginIfBlk($)    { ++$_ifZeroBlkDepth if ($_[0] || $_ifZeroBlkDepth); }
sub beginElseBlk()   { $_ifZeroBlkDepth = 0 if ($_ifZeroBlkDepth == 1); }
sub endIfBlk()       { $_ifZeroBlkDepth = 0 if (--$_ifZeroBlkDepth < 0); }
sub inIfZeroBlk()    { return $_ifZeroBlkDepth; }
}

#------------------------------------------------------------------------------

=head2 rmRCS()

Replace RCS construct(s) with newlines.  This is meant to be Bloomberg-specific.

=cut

sub rmRCS($) {
    my($input) = @_;

    printf "Called rmRCS on input of length %d\n",length($$input);

    fatal("not a ref") if !ref($input);

    my $lint = qr/^\s*\#\s*ifndef\s+lint.*?\n/om;
    my $rcs = qr/^.*?char\s+[Rr][Cc][Ss].*?\n/om;
    my $endif = qr/^.*?\s*\#\s*endif.*?\n/om;

    $$input =~ s/$lint$rcs$endif/\n\n\n/g;

    # The $rcs regex is very expensive.  Avoid it if possible.
    if($$input =~ /\bchar\s+[Rr][Cc][Ss]/) {
        $$input =~ s/$rcs/\n/;
    }
}

#------------------------------------------------------------------------------

=head2 significantComment()

This routine returns true if a line has a comment that must be maintained.

The regexp's are very precise, both to enforce a standard, and because we
are not including logic to cater for strings and/or c-style comments.

Of course it would be better not to have this so tightly coupled to higher
levels of the infrastructure.

=cut

sub significantComment($) {
    my($line) = @_;

    # #include <foo.h> /[/*] $NO_FOLLOW_MARKER|$NOT_A_COMPONENT
    return 1 if $$line =~
      m{^\s*#\s*include\s+["<][\w\.]+[">]\s*/[/*]\s*(?:(?i)$NO_FOLLOW_MARKER|$NOT_A_COMPONENT)}mo;

    # extern int i; /[/*]  EXCEPTED: <reason>
    # NB: KEEP THIS REGEXP IN LINE WITH BDE::Rule::L2::verifyL2
    return 1 if $$line =~
      m{^\s*extern\s*[\w\s]+;\s*/[/*]\s*[A-Z]\d\s+EXCEPTED:\s*\w[\w\s]*$}mo;

    return 0;
}

#------------------------------------------------------------------------------

=head2 slimSrcLine()

Removes comment sequences from $line, where $line is a scalar ref.  State
information is maintained so that c-style comment blocks can also be processed.
Strings are also removed if $keepStrings is false.  "Empty" lines (i.e., all
comment and/or whitespace) are returned as "" (i.e., $$line is guaranteed to
be defined on exit, though it might be the empty string).

Exceptions:

  - calls BDE/Bloomberg-specific routine doNotSlim
  - the string "C" is not removed (unless it is in comment!)
  - "" in #include statements is not treated as a string

=cut

my $strpat        = gen_delimited_pat(q/"/);
my $charlitPat    = gen_delimited_pat(q/'/);
my $inCCommentPat = qr-(?:[^*]|\*+[^/*]|\*$)*-;  # Insides of C comment
my $nonCommentPat = qr-(?:[^/]|/[^/*])*-;        # Outside of a comment

sub slimSrcLine ($;$) {
    # Note that sequence of operations is ordered to cater for multiple-comment
    # constructs on a single line - so know what you're doing if you alter!

    my($line,$keepStrings) = @_;

    $$line = "", return if $$line =~ /^\s*$/o;

    if (inCommentBlk()) {
        if ($$line =~ s:$inCCommentPat\*+/::ox) {
            # Found terminating "*/" and removed from start of line
            setInCommentBlk(0);
        }
        else {
            # still in block
            $$line = "";
            return;
        }
    }
    elsif ($$line =~ m-^\s*\#\s*if\b($nonCommentPat)((?://|/\*)?.*)-ox) {
        # Found start of an "#if" block.
        my $condition = $1;
        my $comment = $2;
        if ($condition =~ /\s*0\s*/ox) {
            # Found start of an "#if 0" block.  Remove everything up until
            # the optional comment.
            $$line = $comment;
            beginIfBlk(1);
        }
        else {
            beginIfBlk(0);
        }
    }
    elsif ($$line =~ m-^\s*\#\s*els(?:e|if)\b\s*($nonCommentPat)((?://|/\*)?.*)-ox )
    {
        # Found an "#else"
        if (inIfZeroBlk() == 1) {
            # #else within top-level "#if 0" block.  Remove everything up
            # until the (optional) comment and replace it with "#if 1"
            my $condition = $1 || "1";
            $$line = "#if $condition$2";
        }
        beginElseBlk();
    }
    elsif ($$line =~ m-^\s*\#\s*endif\b$nonCommentPat((?://|/\*)?.*)-ox) {
        # Found terminating "#endif"
        if (inIfZeroBlk() == 1) {
            # End of "if 0" block.  Remove everything up until the (optional)
            # comment.
            $$line = $1;  # Preserve comment (if any) for further processing
        }
        endIfBlk();
    }

    # exception processing
    return if !inCommentBlk() and significantComment($line);

    # Repeatedly match one of the following:
    #   string
    #   character literal
    #   C++ comment (//)
    #   C comment (/* ... */)
    #   Unclosed C comment (/* ...$)
    while ($$line =~ m{($strpat                |
                        $charlitPat            |
                        //.*$                  |
                        /\*$inCCommentPat(\*+/)? )}gxo) {

        my $found = $1;
        my $foundpos = pos($$line) - length($found);
        my $start    = substr($found, 0, 2);
        my $closeComment = $2;

        if ($start =~ /^\"./) {
            # String
            # If not $keepStrings, remove strings if requested, BUT preserve
            # "C" and #include "".
#             next if ($keepStrings or
#                      $found eq q/"C"/ or
#                      $$line !~ /^\s*\#\s*include\s+/mo);
#             substr($$line, $foundpos, length($found)) = q/""/;
#             pos($$line) = $foundpos + 2;
        }
        elsif ($start eq "//") {
            # C++ comment.  Delete to end-of-line
            substr($$line, $foundpos, length($found)) = "";
            last;
        }
        elsif ($start eq "/*") {
            # C comment, replace with space.  Detect unclosed comment.
            substr($$line, $foundpos, length($found)) = " ";
            pos($$line) = $foundpos + 1;
            setInCommentBlk(1) unless $closeComment;
        }
    }

    if (inIfZeroBlk()) {
        $$line = "";
    }
    else {
        $$line =~ s/\s+$// ;  # Remove trailing blanks (possibly make empty)
    }

    return;
}

#------------------------------------------------------------------------------

=head2 slimSrcLines()

Slims $src, where $src is a reference to source held as scalar with embedded
newlines.  "Lines" are slimmed via repeated calls to slimSrcLine, with
block-comment state being maintained as necessary.

By default strings are modified to be empty, and RCS blocks are removed.
Set $keepStrings and/or $keepRCS to true to change this behavior.

The result is also a reference to a scalar with embedded newlines, including a
guaranteed trailing newline.  Howeverm if the output is "empty" (null or
whitespace only) then a reference to a null string is returned.

=cut

sub slimSrcLines($;$$) {
    my($input,$keepStrings,$keepRCS) = @_;

    fatal("not a ref") if !ref($input);
    return \"" if $$input =~ m-^\s*$-o;
    my @input = split /\n/, $$input;
    my @output;
    setInCommentBlk(0);

    my $defineContinue;
    for my $t (@input) {
        if ($t =~ /\s*\#\s*define/o and $t !~ /INCLUDED/o) {
            if ($t =~ /\\\n/) {
                $defineContinue++;
            }
            push @output, "";
            next;
        }
        elsif ($defineContinue) {
            $defineContinue = 0 unless $t =~ /\\\n/;
            push @output, "";
            next;
        }
        else {
            slimSrcLine(\$t, $keepStrings);
            push @output, $t;
        }
    }

    my $output = join "\n", @output;
    return \"" if $output =~ m-^\s*$-o;
    $output .= "\n" if $output !~ /\n$/o;
    rmRCS(\$output) if !$keepRCS;
    return \$output;
}

#------------------------------------------------------------------------------

=head2 isCV()

Is input string a C++ const or volatile keyword.

=cut

sub isCV($) {
    my($input) = @_;

    return
      $input =~ /\bconst\b/ ||
      $input =~ /\bvolatile\b/ ;
}

#------------------------------------------------------------------------------

=head2 isStorageClass()

Is input string a C++ storage class keyword.

=cut

sub isStorageClass($) {
    my($input) = @_;

    return
      $input =~ /\bstatic\b/   ||
      $input =~ /\bauto\b/     ||
      $input =~ /\bregister\b/ ||
      $input =~ /\bextern\b/   ||
      $input =~ /\bmutable\b/ ;
}

#------------------------------------------------------------------------------

=head2 isSimpleType

Is input string a C++ simple type name.

=cut

sub isSimpleType($) {
    my($input) = @_;

return 
   $input =~ /\bint\b/      ||
   $input =~ /\blong\b/     ||
   $input =~ /\bchar\b/     ||
   $input =~ /\bvoid\b/     ||
   $input =~ /\bbool\b/     ||
   $input =~ /\bdouble\b/   ||
   $input =~ /\bshort\b/    ||
   $input =~ /\bfloat\b/    ||
   $input =~ /\bunsigned\b/ ||
   $input =~ /\bsigned\b/   ||
   $input =~ /\bsize_t\b/   ||
   $input =~ /\bwchar_t\b/;
}

#------------------------------------------------------------------------------

=head2 getParamUserTypes()

Extract user-defined types from a C++ parameter list.

#<<<TODO: needs testing

=cut

sub getParamUserTypes($) {
    my($input) = @_;

    my @results;

    for my $list (split /,/, $input) {
        $list =~ s/\s*(.*?)/$1/;
        for my $term (split /\s/, $list) {
            last if !defined($term) or $term eq "";
            next if isCV($term) or isStorageClass($term);
            last if isSimpleType($term);
            $term =~ /([\w:]+)/;
            push @results, $1;
            last;
        }
    }
    return @results;
}

#------------------------------------------------------------------------------

=head2 normalizeScopedName($scope,$name)

Combines scope and name, removing any redundancy as allowed by the language.

   Scope          Name            Result
   -----          ----            ------
       A             -                 -
    A::B             -                 -
       -             Z                 Z
       -          Y::Z              Y::Z
       A             A             undef
    A::B          A::B             undef
       A             Z              A::Z
    A::B             Z           A::B::Z
       A          A::Z              A::Z
    A::A          A::Z           A::A::Z
    A::B          A::Z        A::B::A::Z


=cut

sub normalizeScopedName($$) {
    my ($scope,$name) = @_;

    return "" if !$name or $name eq "";       # return nothing if no name
    return $name if !$scope or $scope eq "";  # return name if no scope

    # if name doesn't contain '::' then return scope+::+name
    return $scope."::".$name unless $name =~ /((?:[^:]+::)+)([^:]+)$/;
    my ($namespace,$leafname) = ($1,$2);
    $namespace=~s/::$//;

#print "SCOPE=[$scope] NAME=[$name] NS=[$namespace] LEAF=[$leafname]\n";
    # if the scope contains the namespace as suffix, return scope+::+leafname
    return $scope."::".$leafname if $scope =~ /(^|::)\Q$namespace\E$/;

    # remove the common terms between the scope and the namespace
    # A::B::C & B::C::D -> A::B::C::D

    my @scope=split /::/,$scope;
    foreach my $ns (split /::/,$namespace) {
	pop @scope if $scope[-1] eq $ns;
    }

    return join("::",@scope,$namespace,$leafname);
#    my ($result,$suffix);
#    do {
#        $namespace =~ /((?:[^:]+::)+)([^:]+)|([^:]+)/;
#        if ($3) {
#            $namespace = "";
#            $suffix = $3;
#        } else {
#            $suffix = $2;
#            ($namespace = $1) =~ s/::$//;
#        }
#	$result = (defined $result) ? $suffix."::".$result : $suffix;
#    } until (!$namespace or $scope =~ /(^|::)\Q$namespace\E$/);
#
#    return $scope."::".$result."::".$leafname;
}

#------------------------------------------------------------------------------

=head2 isCplusPlus($file)

Determine if a file is present, and if so whether or not it contains C++ code.
The return value is a list of two elements, with the following meanings:

  (true, true)       - $file contains C++
  (true, false)      - $file does not contain C++
  (false, <message>) - error occured, reason retuned in <message>

An empty file I<is> considered to contain C++.

=cut

sub isCplusPlus($) {
    my($file) = @_;

    my $fh = new IO::File;
    return(0, "cannot open $file: $!") unless open($fh, "<$file");
    local $/= undef;
    my ($content) = <$fh>;
    return (0, "cannot close $file: $!") unless close($fh);

    return (1,1) unless $content;
    return (1, $content =~ m-\s*(?://|\bclass\b)-);
}

#==============================================================================

sub testSlimSrcLine() {

my @DATA = (

{
a=>__LINE__,
b=>0,
c=>'    (char *)"C", // country name"',
d=>'    (char *)"C",',
f=>0},

# depth ordered by number of comment signifiers
#
# cblk = Comment block
#
#            <------- INPUT -------> <--------------- OUTPUT --------------->
#
#    Line    cblk      inline             outline                        cblk
#=========== ==== ================== =================                   ====


# --- D0 ---

{a=>__LINE__,b=>0,c=>             "",d=>            "",                  f=>0},

# --- D1 ---

{a=>__LINE__,b=>0,c=>           "//",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>          "//A",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>         "A//B",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>        "A //B",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>      "A B//CD",d=>         "A B",                  f=>0},
{a=>__LINE__,b=>0,c=>     "A B //CD",d=>         "A B",                  f=>0},
{a=>__LINE__,b=>0,c=>           "/*",d=>            "",                  f=>1},
{a=>__LINE__,b=>0,c=>          "/*A",d=>            "",                  f=>1},
{a=>__LINE__,b=>0,c=>         "A/*B",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>        "A/**B",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>        "A/*B*",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>      "A B /*B",d=>         "A B",                  f=>1},
{a=>__LINE__,b=>1,c=>             "",d=>            "",                  f=>1},
{a=>__LINE__,b=>1,c=>            "*",d=>            "",                  f=>1},
{a=>__LINE__,b=>1,c=>           "//",d=>            "",                  f=>1},
{a=>__LINE__,b=>1,c=>           "*/",d=>            "",                  f=>0},
{a=>__LINE__,b=>1,c=>          "*/A",d=>           "A",                  f=>0},
{a=>__LINE__,b=>1,c=>         "*/AB",d=>          "AB",                  f=>0},
{a=>__LINE__,b=>1,c=>         "*/A ",d=>           "A",                  f=>0},
{a=>__LINE__,b=>1,c=>        "//*/A",d=>           "A",                  f=>0},


# --- D2 ---

# ////
{a=>__LINE__,b=>0,c=>         "////",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>       "//B//C",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>      "A//B//C",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>     "A //B//C",d=>           "A",                  f=>0},

# ///*
{a=>__LINE__,b=>0,c=>         "///*",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>        "A///*",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>       "A///*B",d=>           "A",                  f=>0},

# //*/
{a=>__LINE__,b=>0,c=>         "//*/",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>        "A//*/",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>       "A//*/B",d=>           "A",                  f=>0},

# //"
{a=>__LINE__,b=>0,c=>         "//\"",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>        "A//\"",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>       "A//B\"",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>      "A//B\"C",d=>           "A",                  f=>0},

# # //'
# {a=>__LINE__,b=>0,c=>          "//'",d=>            "",                  f=>0},
# {a=>__LINE__,b=>0,c=>         "A//'",d=>           "A",                  f=>0},
# {a=>__LINE__,b=>0,c=>        "A//B'",d=>           "A",                  f=>0},
# {a=>__LINE__,b=>0,c=>       "A//B'C",d=>           "A",                  f=>0},

# //""
{a=>__LINE__,b=>0,c=>       "//\"\"",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>      "A//\"\"",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>     "A//B\"\"",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>    "A//B\"C\"",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>   "A//B\"C\"D",d=>           "A",                  f=>0},

# # //''
# {a=>__LINE__,b=>0,c=>         "//''",d=>            "",                  f=>0},
# {a=>__LINE__,b=>0,c=>        "A//''",d=>           "A",                  f=>0},
# {a=>__LINE__,b=>0,c=>       "A//B''",d=>           "A",                  f=>0},
# {a=>__LINE__,b=>0,c=>      "A//B'C'",d=>           "A",                  f=>0},
# {a=>__LINE__,b=>0,c=>     "A//B'C'D",d=>           "A",                  f=>0},

# /*//
{a=>__LINE__,b=>0,c=>         "/*//",d=>            "",                  f=>1},
{a=>__LINE__,b=>0,c=>        "A/*//",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>       "A/*//B",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>      "A/*B//C",d=>           "A",                  f=>1},

# /*/*
{a=>__LINE__,b=>0,c=>         "/*/*",d=>            "",                  f=>1},
{a=>__LINE__,b=>0,c=>        "A/*/*",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>       "A/*/*B",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>      "A/*B/*C",d=>           "A",                  f=>1},

# /*""
{a=>__LINE__,b=>0,c=>       "/*\"\"",d=>            "",                  f=>1},
{a=>__LINE__,b=>0,c=>      "A/*\"\"",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>     "A/*B\"\"",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>    "A/*B\"C\"",d=>           "A",                  f=>1},
{a=>__LINE__,b=>0,c=>   "A/*B\"C\"D",d=>           "A",                  f=>1},

# # /*''
# {a=>__LINE__,b=>0,c=>         "/*''",d=>            "",                  f=>1},
# {a=>__LINE__,b=>0,c=>        "A/*''",d=>           "A",                  f=>1},
# {a=>__LINE__,b=>0,c=>       "A/*B''",d=>           "A",                  f=>1},
# {a=>__LINE__,b=>0,c=>      "A/*B'C'",d=>           "A",                  f=>1},
# {a=>__LINE__,b=>0,c=>     "A/*B'C'D",d=>           "A",                  f=>1},

# *///
{a=>__LINE__,b=>1,c=>         "*///",d=>            "",                  f=>0},
{a=>__LINE__,b=>1,c=>        "A*///",d=>            "",                  f=>0},
{a=>__LINE__,b=>1,c=>       "A*///B",d=>            "",                  f=>0},
{a=>__LINE__,b=>1,c=>      "A*/B//C",d=>           "B",                  f=>0},

# /**
{a=>__LINE__,b=>0,c=>         "A/**",d=>           "A",                  f=>1},

# /**/
{a=>__LINE__,b=>0,c=>         "/**/",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>        "/*A*/",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>      "A/*B*/C",d=>         "A C",                  f=>0},

# --- D3 ---

{a=>__LINE__,b=>0,c=>     "A/**/B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>0,c=>    "A/***/B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>0,c=>   "A/****/B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>0,c=>   "A/****/B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>0,c=>  "A/* ***/B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>0,c=>  "A/** **/B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>0,c=>  "A/*** */B/*C",d=>        "A B",                  f=>1},
{a=>__LINE__,b=>1,c=>     "*B*/C //D",d=>          "C",                  f=>0},
{a=>__LINE__,b=>1,c=>    "**B*/C //D",d=>          "C",                  f=>0},
{a=>__LINE__,b=>1,c=>    "*B**/C //D",d=>          "C",                  f=>0},
{a=>__LINE__,b=>1,c=>    "B***/C //D",d=>          "C",                  f=>0},

# /*""*/
{a=>__LINE__,b=>0,c=>     "/**/\"\"",d=>         ' ""',                  f=>0},
{a=>__LINE__,b=>0,c=>      "/*\"*/A",d=>          " A",                  f=>0},
{a=>__LINE__,b=>0,c=>     "/*\"\"*/",d=>            "",                  f=>0},
{a=>__LINE__,b=>0,c=>    "A/**/\"\"",d=>        'A ""',                  f=>0},
{a=>__LINE__,b=>0,c=>    "A/*\"\"*/",d=>           "A",                  f=>0},
{a=>__LINE__,b=>0,c=>     "A/*\"*/B",d=>         "A B",                  f=>0},

# # /*''*/
# {a=>__LINE__,b=>0,c=>     "/**/'A'",d=>         " 'A'",                  f=>0},
# {a=>__LINE__,b=>0,c=>      "/*'*/A",d=>           " A",                  f=>0},
# {a=>__LINE__,b=>0,c=>     "/*'A'*/",d=>             "",                  f=>0},
# {a=>__LINE__,b=>0,c=>    "A/**/'B'",d=>        "A 'B'",                  f=>0},
# {a=>__LINE__,b=>0,c=>    "A/*'B'*/",d=>            "A",                  f=>0},
# {a=>__LINE__,b=>0,c=>    "A/*B'*/C",d=>          "A C",                  f=>0},

# *//*
{a=>__LINE__,b=>1,c=>      "A*/B/*C",d=>           "B",                  f=>1},

# /**//*
{a=>__LINE__,b=>0,c=>   "A/*B*/C/*D",d=>         "A C",                  f=>1},

# *//**/
{a=>__LINE__,b=>1,c=>   "A*/B/*C*/D",d=>         "B D",                  f=>0},

# /**//**/
{a=>__LINE__,b=>0,c=> "A/*B*/C/*D*/",d=>         "A C",                  f=>0},
{a=>__LINE__,b=>0,c=>"A/*B*/C/*D*/E",d=>       "A C E",                  f=>0},

# quotes, remove strings

#{a=>__LINE__,b=>0,c=>          'A""B',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>         'A"X"B',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>       'A" X "B',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>        'A"/*"B',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>      'A"/*"/*B',d=>        'A""',                  f=>1},
#{a=>__LINE__,b=>0,c=>        'A"//"B',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>         'A"C"B',d=>      'A"C"B',                  f=>0},
#{a=>__LINE__,b=>0,c=>     'A"//"B//C',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>     'A"/*"B//C',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>     'A"*/"B//C',d=>       'A""B',                  f=>0},
#{a=>__LINE__,b=>0,c=>     'A"/*B*/"C',d=>       'A""C',                  f=>0},

{a=>__LINE__,b=>0,c=>   '#include "A.h"',   d=>'#include "A.h"',         f=>0},

{a=>__LINE__,b=>0,c=>  "#include <foo.h> //not a component",
                  d=>  "#include <foo.h> //not a component",             f=>0},

{a=>__LINE__,b=>0,c=>  "#include \"foo.h\" //not a component",
                  d=>  "#include \"foo.h\" //not a component",           f=>0},

{a=>__LINE__,b=>0,c=>  "extern i; // L2 EXCEPTED: foobar",
                  d=>  "extern i; // L2 EXCEPTED: foobar",               f=>0},

# quotes, keep strings

{a=>__LINE__,b=>0,c=>        'A"/*"B',d=>       'A"/*"B',         f=>0, g=> 1},
{a=>__LINE__,b=>0,c=>     'A"/*"B/*C',d=>       'A"/*"B',         f=>1, g=> 1},
{a=>__LINE__,b=>0,c=>        "A'\"'B",d=>       "A'\"'B",         f=>0, g=> 1},

# single quotes
{a=>__LINE__,b=>0,c=>    "A'\"'B'\"'",d=>   "A'\"'B'\"'",         f=>0, g=> 1},
{a=>__LINE__,b=>0,c=>   "A'\"'//'\"'",d=>        "A'\"'",         f=>0, g=> 1},
{a=>__LINE__,b=>0,c=>   "A'\"'/*'\"'",d=>        "A'\"'",         f=>1, g=> 1},

# If 0 blocks
{a=>__LINE__,b=>0,B=>0,c=>        "#if 0",d=> "",          f=>0, F=>1},
{a=>__LINE__,b=>0,B=>0,c=> "#if X // abc",d=> "#if X",     f=>0, F=>0},
{a=>__LINE__,b=>0,B=>1,c=>       "abc /*",d=> "",          f=>1, F=>1},
{a=>__LINE__,b=>1,B=>1,c=>    "*/ #endif",d=> "",          f=>0, F=>1},
{a=>__LINE__,b=>1,B=>1,c=>       "#endif",d=> "",          f=>1, F=>1},
{a=>__LINE__,b=>1,B=>0,c=>        "#if 0",d=> "",          f=>1, F=>0},
{a=>__LINE__,b=>0,B=>1,c=> " # endif //x",d=> "",          f=>0, F=>0},
{a=>__LINE__,b=>0,B=>1,c=>   "#endif /*x",d=> "",          f=>1, F=>0},
{a=>__LINE__,b=>0,B=>0,c=>   "#endif /*x",d=> "#endif",    f=>1, F=>0},
{a=>__LINE__,b=>0,B=>1,c=>    "#else /*x",d=> "#if 1",     f=>1, F=>0},
{a=>__LINE__,b=>0,B=>1,c=> "#elsif X /*x",d=> "#if X",     f=>1, F=>0},
{a=>__LINE__,b=>0,B=>0,c=>    "#else /*x",d=> "#else",     f=>1, F=>0},
{a=>__LINE__,b=>0,B=>0,c=> "#elsif X /*x",d=> "#elsif X",  f=>1, F=>0},

{a=>__LINE__,b=>0,B=>1,c=>        "#if 0",d=> "",          f=>0, F=>2},
{a=>__LINE__,b=>0,B=>1,c=> "#if X // abc",d=> "",          f=>0, F=>2},
{a=>__LINE__,b=>0,B=>2,c=>       "abc /*",d=> "",          f=>1, F=>2},
{a=>__LINE__,b=>1,B=>2,c=>    "*/ #endif",d=> "",          f=>0, F=>2},
{a=>__LINE__,b=>1,B=>2,c=>       "#endif",d=> "",          f=>1, F=>2},
{a=>__LINE__,b=>1,B=>1,c=>        "#if 0",d=> "",          f=>1, F=>1},
{a=>__LINE__,b=>0,B=>2,c=> " # endif //x",d=> "",          f=>0, F=>1},
{a=>__LINE__,b=>0,B=>2,c=>   "#endif /*x",d=> "",          f=>1, F=>1},
{a=>__LINE__,b=>0,B=>1,c=>   "#endif /*x",d=> "",          f=>1, F=>0},
{a=>__LINE__,b=>0,B=>2,c=>    "#else /*x",d=> "",          f=>1, F=>2},
{a=>__LINE__,b=>0,B=>2,c=> "#elsif X /*x",d=> "",          f=>1, F=>2},
{a=>__LINE__,b=>0,B=>1,c=>    "#else /*x",d=> "#if 1",     f=>1, F=>0},
{a=>__LINE__,b=>0,B=>1,c=> "#elsif X /*x",d=> "#if X",     f=>1, F=>0},

   );

    for my $entry (@DATA) {
    last unless ${$entry}{a};
    my $line       = ${$entry}{a};
    my $inCblk     = ${$entry}{b};  # read-write
    my $inIf0Blk   = ${$entry}{B};  # read-write
    my $inLine     = ${$entry}{c};
    my $outLine    = ${$entry}{d};
    my $outCblk    = ${$entry}{f} || 0;
    my $outIf0Blk  = ${$entry}{F} || 0;
    my $keepStr    = ${$entry}{g} || 0;

    setInCommentBlk($inCblk);
    setIfZeroBlkDepth($inIf0Blk || 0);
    slimSrcLine(\$inLine, $keepStr);
    ASSERT(__LINE__ . ".$line", $inLine, $outLine);
    ASSERT(__LINE__ . ".$line", inCommentBlk(), $outCblk);
    ASSERT(__LINE__ . ".$line", inIfZeroBlk(), $outIf0Blk);
    }
}

#------------------------------------------------------------------------------

sub testSlimSrcLines() {

my @DATA = (

#            <---- INPUT -----> <----------------- OUTPUT ------------------>
#
#    Line          src
#=========== ================== =============================================

# --- D0 ---

{a=>__LINE__,b=>             "",c=>                            ""},
{a=>__LINE__,b=>   "ABC\nDEF\n",c=>                  "ABC\nDEF\n"},
{a=>__LINE__,b=>   " A \n B \n",c=>                    " A\n B\n"},

# --- D1 ---

{a=>__LINE__,b=>     "//A\nB\n",c=>                       "\nB\n"},
{a=>__LINE__,b=>    "A//B\nC\n",c=>                      "A\nC\n"},
{a=>__LINE__,b=>     "A\n//B\n",c=>               "A\n",d=>0,e=>1},
{a=>__LINE__,b=>    "A\nB//C\n",c=>            "A\nB\n",d=>0,e=>1},

# --- D2 ---

{a=>__LINE__,b=>    "A/*C*/D\n",c=>                        "A D\n"},

# --- D3 ---

{a=>__LINE__,b=> "A/*\n*\n*/B\n",c=>         "A\n\nB\n",d=>0,e=>1},
{a=>__LINE__,b=> "A/*\n*\n*/B\n",c=>         "A\n\nB\n",d=>1,e=>1},
{a=>__LINE__,b=> "A/*\n*\n*/B\n",c=>         "A\n\nB\n",d=>2,e=>2},
{a=>__LINE__,b=> "A/*\n*\n*/B\n",c=>         "A\n\nB\n",d=>3,e=>3},
{a=>__LINE__,b=>"A/**/B\nC//D\n",c=>         "A B\nC\n"},

# --- D4 ---

{a=>__LINE__,b=>"A/*\n\nB\n*\n*/\n",c=>     "A\n\n\n\n"},

{
 a=>__LINE__,
 b=>"AAA\n".
    "char RCS  \$Id: \n".
    "BBB\n",
 c=>"AAA\n".
    "\n".
    "BBB\n"
},

{
 a=>__LINE__,
 b=>"AAA\n".
    "#ifndef lint\n".
    "char RCS  \$Id: \n".
    "#endif\n".
    "BBB\n",
 c=>"AAA\n".
    "\n".
    "\n".
    "\n".
    "BBB\n"
},

{
 a=>__LINE__,
 b=>"AAA\n".
    "#ifndef lint\n".
    "char RCS  \$Id: \n".
    "#endif\n".
    "BBB\n".
    "char RCS  \$Id: \n".
    "CCC\n",
 c=>"AAA\n".
    "\n".
    "\n".
    "\n".
    "BBB\n".
    "\n".
    "CCC\n"
},

);

  for my $entry (@DATA) {
    last if !${$entry}{a};
    my $line         = ${$entry}{a};
    my $inSrc        = ${$entry}{b};
    my $outSrc       = ${$entry}{c};

    my($src) = slimSrcLines(\$inSrc);
    ASSERT(__LINE__ . ".$line", $$src, $outSrc);
  }
}

#==============================================================================

sub testNormalizeScopedName() {

my @DATA = (

#            <------------------ INPUT --------------------> <------- OUTPUT ------>
#
#    Line            scope                     name                  result
#=========== ======================= ======================= =======================

{a=>__LINE__,b=>              "A::B::C",c=>        "B::C::D",d=>        "A::B::C::D"},

# --- D0 ---

{a=>__LINE__,b=>                  "",c=>                  "",d=>                  ""},

# --- D1 ---

{a=>__LINE__,b=>                 "A",c=>                  "",d=>                  ""},
{a=>__LINE__,b=>                  "",c=>                 "A",d=>                 "A"},

# --- D2 ---

{a=>__LINE__,b=>              "A::B",c=>                  "",d=>                  ""},
{a=>__LINE__,b=>                 "A",c=>                 "A",d=>              "A::A"},
{a=>__LINE__,b=>                  "",c=>              "A::B",d=>              "A::B"},

# --- D3 ---

{a=>__LINE__,b=>              "A::B::C",c=>               "",d=>                  ""},
{a=>__LINE__,b=>                 "A::B",c=>              "C",d=>           "A::B::C"},
{a=>__LINE__,b=>                 "A::B",c=>              "A",d=>           "A::B::A"},
{a=>__LINE__,b=>                 "A::B",c=>              "B",d=>           "A::B::B"},
{a=>__LINE__,b=>                 "A::A",c=>              "A",d=>           "A::A::A"},

# --- D4 ---

{a=>__LINE__,b=>                    "A",c=>        "B::C::D",d=>        "A::B::C::D"},
{a=>__LINE__,b=>                 "A::B",c=>        "B::C::D",d=>        "A::B::C::D"},
{a=>__LINE__,b=>              "A::B::C",c=>        "B::C::D",d=>        "A::B::C::D"},
{a=>__LINE__,b=>                    "A",c=>        "A::B::C",d=>           "A::B::C"},
{a=>__LINE__,b=>                 "A::B",c=>        "A::B::C",d=>           "A::B::C"},

);

    for my $entry (@DATA) {
    last if !${$entry}{a};
    my $line       = ${$entry}{a};
    my $scope      = ${$entry}{b};
    my $name       = ${$entry}{c};
    my $result     = ${$entry}{d};

    ASSERT(__LINE__ . ".$line", normalizeScopedName($scope, $name), $result);
    }
}


#==============================================================================

=head1 AUTHOR

Ralph Gibbons, rgibbons1@bloomberg.net

=cut

1;

#==============================================================================



