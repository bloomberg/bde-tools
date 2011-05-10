package Util::File::Functions;
use strict;

use File::Path qw(mkpath);

use Util::Message qw(fatal debug);

#==============================================================================

=head1 NAME

Util::File::Functions - Utility functions for handling files and filenames

=head1 SYNOPSIS

    use Util::File::Attribute qw(ensure_path);

    ensure_path("/make/sure/this/path/exists");

=head1 DESCRIPTION

C<Util::File::Attribute> provides utility functions that carry out tasks
related to files and filenames.

=cut

#==============================================================================

=head1 EXPORTS

The following groups and individual routines are available for export:

=head2 GROUPS

=over 4

=item path - File path and location routines

=item name - File name manipulation routines

=back

=head2 ROUTINES

=over 4

=item L<"ensure_path"> [path]

=item L<"wild2re"> [name]

=back

=cut

use Exporter;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

my @path_ops=qw[
    ensure_path
];

my @name_ops=qw[
    wild2re
];

my @misc_ops=qw[
    diff_files
];

@ISA = ('Exporter');
@EXPORT_OK = (@path_ops, @name_ops, @misc_ops);

%EXPORT_TAGS = (
    all => \@EXPORT_OK,
   path => \@path_ops,
   name => \@name_ops,
   misc => \@misc_ops,
);

#------------------------------------------------------------------------------

=head1 ROUTINES

The following routines are available for export:

=cut

#------------------------------------------------------------------------------

=head2 ensure_path($dirpath [,$no_create])

Determine whether the supplied path exists in the filesystem and points to
a directory. Unless the optional second argument is true, attempt to create
the path if it is not present using L<File::Path/mkpath>.

An exception is thrown if the path exists but points to a non-directory
(a link to a directory is acceptable), if the directory is not readable,
if the directory path cannot be created or (if the 'no create' flag is used)
does not exist.

The results of the determination (whether the path already existed or was
created) are cached, so subsequent enquiries will not cause access to the
filesystem.

=cut

{ my %ensured;

  sub ensure_path ($;$) {
      my ($dir,$nocreate)=@_;

      return 1 if $ensured{$dir};

      if (-d $dir or -l $dir) {
	  if (-r $dir) {
	      $ensured{$dir}=1;
	  } else {
	      fatal "$dir not readable";
	  }
      } elsif (-e $dir) {
	  fatal "$dir exists but is not a directory";
      } elsif (not $nocreate) {
	  mkpath($dir) or fatal "failed to create $dir: $!";
	  $ensured{$dir}=1;
      } else {
	  fatal "$dir not found";
      }
  }
}

=head2 wild2re($wildcardname)

Convert the supplied filename from wildcarded to regular expression format and
return the result. The following wildcard syntaxes are supported:

    ?     - any character
    *     - zero or more characters
    [abc] - character class
    {a,b} - alternates (bash-style)

Literal wildcard characters C<.> and C<+> are escaped in the returned pattern.

Note that some expressions like character classes are actually more powerful
than most real wildcard syntaxes allow, e.g C<[^a-zA-Z]> would work as
expected even though most shell-supported character classes would not accept
this syntax.

=cut

sub wild2re ($) {
    my $wild=shift;

    $wild=~s/\./\\./g;
    $wild=~s/\*/.*/g;
    $wild=~s/\?/./g;
    $wild=~s/\+/\\+/g;

    # foo{abc,def,gh}bar -> foo(abc|def|gh)bar
    my $tmp;
    $wild=~s/\{(.*?)\}/"(?:" . do { ($tmp = $1) =~ tr!,!|!; $tmp } . ")"/ge;

    return $wild;
}

=head2 diff_files($file1, $file2, [%opts])

Generates a diff-report for the two given files I<$file1> and I<$file2>.

Returns the report as a string in case of success. Otherwise, returns
a two-element list with the first element undef and the second being
the error.

Optional arguments, passed as key/value parts, are:

=over 4

=item html

If set to true, return a string suitable to be included in an HTML report

=item cmd

Use this command to generate the diff. This must be a reference to an array
which is passed as a list to C<open>.

=back

=cut

my @DEFAULT_DIFF = qw#/opt/swt/bin/diff#;

sub diff_files {
    my ($file1, $file2, %opts) = @_;
   
    my @cmd = @DEFAULT_DIFF;

    push @cmd, @{ $opts{diffopts} } if ref($opts{diffopts}) eq 'ARRAY';
    push @cmd, $file1, $file2;

    debug("Pipe-opening", join ' ' => @cmd);
    
    open my $pipe, '-|', @cmd or
        return undef, "Could not run $cmd[0]: $!";

    local $/;
    my $diff = <$pipe>;

    # gnu diff returns 0 or 1 in success case (1 meaning differences were found)
    close $pipe or do {{    # double-block because of 'last'
        my $ec = $?>>8;
        last if $ec == 1;
        return undef, "Could not close pipe to diff. Exit code $ec";
    }};

    if ($opts{html}) {
        $diff =~ s/^--- $file1/--- $file2/;
        for ($diff) {
            s#&#&amp;#g;
            s#<#&lt;#g;
            s#>#&gt;#g;
            s#^(-.*)$#<font color="red"><b>$1</b></font>#mg;
            s#^(\+.*)$#<font color="green"><b>$1</b></font>#mg;
            s#^(@@.*)$#<font color="blue"><b>$1</b></font>#mg;
        }
        $diff = "<pre>\n$diff</pre>\n" if $diff;
    }

    return $diff;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

Tassilo von Parseval (tvonparseval@bloomberg.net)

=cut

1;

