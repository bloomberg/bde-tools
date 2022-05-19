#!/opt/bb/bin/perl

use strict;
use warnings;
use Getopt::Long;

sub usage($$) {
    my $message = $_[0] || "";
    my $exitCode = $_[1];

    print <<EOT;
$message

Usage: bde_replace_fwd_decls.pl [ --inplace ]
                                [ --debug=<level> ]
                                [ --disable-comments ]
                                [ --reverse ]
                             { <input-header>... }
    Replaces forward declarations to classes outside the current UOR with the
    equivalent include, unless the declaration is tagged with // KEEPFWDDCL

    --help: Display this message and exit.

    --inplace: The result for a given 'input-header' is placed in
               input-header.NEW, unless the '--inplace' option is specified.

    --debug: defaults to 0 - positive integer values increase the amount of
             output

    --disable-comments: By default, the added includes have a comment block
                        explaining their presence, and the removed declarations
                        are similarly commented out and left in the code,
                        unless --disable-comments is specified.

    --reverse: (TODO, not implemented yet) This option "undoes" the effects of
               this script, if the original run did not use the
               --disable-comments switch.  The coments are used to guide the
               reversal.

EOT

    exit $exitCode;
}


my %known_header_fixes = (
    "bscapi_clientcontext.h" => "bscapi_clientcontextutil.h"
  , "bscmsg_rolenextnotificationmethod.h" => "bscmsg_rolenext.h"
  , "dmcu_blobposition.h" => "dmcu_blobutil.h"
  , "bdlbb_blobbufferfactory.h" => "bdlbb_blob.h"
);

sub getHeaderName {
    my ($uor, $classname) = @_;

    $classname = lc($classname);
    my $header_name = "";

    if ($classname =~ /^ber(en|de)coder/ ) {
        $classname =~ s/_.*//;
        $header_name = "balber_" . $classname . ".h";
    }
    elsif ($classname =~ /^[a-z]+_/) {
        $header_name = $classname.".h";
    }
    else {
        $header_name = $uor."_".$classname.".h";
    }

    return $known_header_fixes{$header_name} || $header_name;
}

sub commentOutLine {
    my ($line_r) = @_;

    my $tag = " // FWDDCL";

    return if $$line_r =~ /$tag/;

    chomp($$line_r);

    # +3 for the leading "// "
    my $addedLen = length($tag) + 3;
    $$line_r =~ s! {3,$addedLen}!!;
    $$line_r = "// " . $$line_r . $tag . "\n";

    # 80 = 79 + "\n"
    if (length($$line_r) < 80) {
        my $added = " " x (80 - length($$line_r));
        $$line_r =~ s!$tag!$added$tag!;
    }
}


my $inplace = 0;
my $debug = 0;
my $reverse = 0;
my $disablecomments = 0;
my $help = 0;

if (!@ARGV) {
    usage("No files passed as arguments", 1);
}

GetOptions("debug=i"            => \$debug,
           "disable-comments!"  => \$disablecomments,
           "help!"              => \$help,
           "inplace!"           => \$inplace,
           "reverse"            => \$reverse) or usage("Invalid option", 1);

if ($help) {
    usage("", 0);
}

if ($reverse) {
    print STDERR "TODO: reverse option is not yet implemented.\n";
    # TODO: The unwind (reverse) option is pretty simple.
    #    1. Remove any includes tagged with // FWDDCL
    #    2. On each line of the file, perform:
    #       s!^// (.*) // FWDDCL!$1!
    #    3. Output the result (in-place, if $inplace is true)
    exit(1);
}

# TODO: Use arguments to try to winnow down header names for extra types in
# components?
my %seen_packages;
my %seen_headers;

foreach my $ARGV (@ARGV) {
    my $filename=$ARGV;
    $filename=~s!.*/!!;
    $filename=~/^((?:s_|m_|f_)?[^_]+)/ or next;
    $seen_packages{$1}++;
    $seen_headers{$filename}++;
}

foreach my $ARGV (@ARGV) {
    my $filename=$ARGV;
    $filename=~m!(?:groups|adapters|enterprise|(?:legacy|departments|functions)/index|thirdparty|standalones|applications)/(\w+)!;
    my $uor = $1;
    die "unable to find uor in $filename" unless defined $uor;

    print STDERR "Processing $filename ($uor)\n" if $debug >= 1;

    open(my $fh, "<", $filename) or die "Can't open $filename, error $!";
    my @original_lines=<$fh>;
    close($fh);

    my @namespace_stack;
    my @brace_stack;

    my $last_include_idx = 0;
    my $pin_last_include_idx = 0;
    my %added_includes;

    my $line_no = 0;

    my $force_bdlt = 0;

    foreach my $original_line (@original_lines) {
        next if $original_line =~ m!// KEEPFWDDCL!;

        my $mangled_line = $original_line;

        ++$line_no;

        $mangled_line=~s!//.*!!;
        $mangled_line=~s!\s+! !;
        $mangled_line=~s!^ !!;

        if (!$pin_last_include_idx && $mangled_line =~ /^#\s*include\b/) {
            $last_include_idx = $line_no - 1;
            next;
        }

        if ($mangled_line =~ /#ifndef BDE_DONT_ALLOW/) {
            $last_include_idx = $line_no - 2;
            $pin_last_include_idx = 1;
            next;
        }

        if (!$pin_last_include_idx && $mangled_line =~ /^#\s*endif\b/ && $last_include_idx == $line_no - 2) {
            $last_include_idx = $line_no;
            next;
        }

        # Note the use of $original_line here - $manged_line no longer has
        # comments
        if ($disablecomments &&
            ($original_line =~
                 m!// Updated by 'bde-replace-bdet-forward-declares.py!
            || $original_line =~
                 m!// Updated declarations tagged with '// bdet!)) {
            $original_line="";

            next;
        }

        while ($mangled_line=~/^namespace/) {
            if ($mangled_line=~/^friend\b.*/) {
                $mangled_line="";
                next;
            }

            if ($mangled_line=~/^(namespace (\w+)? ?\{)/) {
                my $namespace = $2;
                if (!defined $namespace) {
                    $namespace="<anon>";
                }
                push @namespace_stack, $namespace;
                push @brace_stack, "ns";
                $mangled_line=~s!$1 *!!; # remove processed text
            }

            if ($mangled_line=~/^((?:struct|class) (\w+).*;)/) {
                my $classname = $2;
                $mangled_line=~s!$1 *!!; # remove processed text

                if ($classname=~/^$uor/
                      || (@namespace_stack && $namespace_stack[-1]=~/^$uor/)) {
                    next;
                }

                my $namespace = $namespace_stack[-1];
                # Note the use of $original_line here - $mangled_line no longer
                # has comments.
                if (($namespace eq "bdlt" || $namespace eq "bsls")
                                      && $original_line =~ m!// bdet -> bdlt!) {
                    $namespace="bdet";
                }

                my $newHeader = getHeaderName($namespace, $classname);

                if (!keys %added_includes) {
                    ++$last_include_idx;
                }

                $added_includes{$newHeader}++;

                if ($disablecomments) {
                    $original_line="";
                } else {
                    commentOutLine(\$original_line);
                }
                next;
            }

            if ($mangled_line=~/^((?:\w|\s|[\(\)\[\]:])*){/) {
                push @brace_stack, "not-ns";
                $mangled_line=~s!$1 *!!; # remove processed text
            }

            if ($mangled_line=~/^( *})/) {
                die unless @brace_stack;
                if ($brace_stack[-1] eq "ns") {
                    pop @namespace_stack;
                }
                pop @brace_stack;
                $mangled_line=~s!$1 *!!; # remove processed text
            }

            if ($mangled_line=~/namespace\s+\w+\s*=/) {
                last;
            }
        }

        if ($original_line =~ m!// bdet -> bdlt!
                && $original_line !~ m!Updated declarations tagged with!) {
            if ($disablecomments) {
                $original_line="";

                if ($original_lines[$line_no] =~ /^\n$/) {
                    $original_lines[$line_no] = "";
                }
            } else {
                commentOutLine(\$original_line);
            }
            next;
        }
    }

    if (keys %added_includes) {
        my $prevPackage;
        my @added_includes=
            map {
                /^(\w+)_/;
                my $splitPackages="";
                if ($disablecomments
                            and defined $prevPackage
                            and $1 ne $prevPackage) {
                    $splitPackages="\n";
                }
                $prevPackage=$1;
                "$splitPackages#include <$_>\n"
            }
            sort keys %added_includes;
        my $new_include_count = scalar @added_includes;
        @added_includes=(
             "// Changes made with bde_replace_fwd_decls.pl (lines marked with"
             ." // FWDDCL)\n",
             @added_includes) unless $disablecomments;
        unshift @added_includes, "\n"
                         unless $original_lines[$last_include_idx - 1] eq "\n";
        push @added_includes, "\n"
                             unless $original_lines[$last_include_idx] eq "\n";
        splice @original_lines, $last_include_idx, 0, @added_includes;

        printf STDERR "======= adding %d includes to $filename\n",
                      $new_include_count;

        my $outFilename = "$filename.NEW";
        $outFilename = $filename if $inplace;
        open(my $out_fh, ">", $outFilename)
                                    or die "can't open $outFilename, error $!";
        print $out_fh @original_lines
                                or die "can't write to $outFilename, error $!";
        close($out_fh)             or die "can't close $outFilename, error $!";
    }
}
