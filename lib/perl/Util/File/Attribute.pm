package Util::File::Attribute;
use strict;

#------------------------------------------------------------------------------

=head1 NAME

Util::File::Attribute - Utility functions for handling file attributes

=head1 SYNOPSIS

    use Util::File::Attribute qw(is_newer is_newer_missing_ok);

    my $script_newer_than_libs = 1
        if not is_newer($0 => values(%INC));

=head1 DESCRIPTION

C<Util::File::Attribute> provides utility functions that carry out tasks
related to file attributes (ownership, permissions, timestamps, et al.).

=cut

#------------------------------------------------------------------------------

=head1 EXPORTS

The following groups and individual routines are available for export:

=head2 GROUPS

=over 4

=item stat - File stat routines

=back

=head2 ROUTINES

=over 4

=item L<"is_newer"> [stat]

=item L<"is_newer_missing_ok"> [stat]

=back

=cut

use Exporter;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

my @stat_ops=qw[
    is_newer
    is_newer_missing_ok
];

@ISA = ('Exporter');
@EXPORT_OK = (@stat_ops);

%EXPORT_TAGS = (
    all => \@EXPORT_OK,
   stat => \@stat_ops,
);

#------------------------------------------------------------------------------

=head1 ROUTINES

The following routines are available for export:

=cut

#------------------------------------------------------------------------------

# internal routine; use is_newer or is_newer_missing_ok, below
sub _is_newer($$@) {
    my ($missing_ok,$checkfile,@againstfiles)=@_;

    # if the check file doesn't exist it's clearly out of date!
    return "0 but true" unless -f $checkfile;
    my $checktime=-M _; # '_' reuses result of stat for -f

#print "_ISNEW(@againstfiles): ==$#againstfiles==\n";
    # collect timestaps of dependent files, and ensure all of them exist
    my @againsttimes;
    foreach my $idx (0..$#againstfiles) {
	my $dependant_exists = -f $againstfiles[$idx];
#print "_ISNEW(mok=$missing_ok): Checking $checkfile against $againstfiles[$idx] (e=$dependant_exists)\n";
	if ($dependant_exists) {
	    push @againsttimes,-M _; # '_' reuses result of stat from -f
	} elsif ($missing_ok) {
	    push @againsttimes,-1;
	    next; # for is_newer_missing_ok()
	} else {
	    return -($idx+1); # for is_newer()
	}
    }

    # all files exist, so see if any dependent file is newer
    foreach my $idx (0..$#againsttimes) {
       # relative times: larger is older
       return($idx+1) if $checktime > $againsttimes[$idx];
    }

    return 0; # checkfile is newer
}

=head2 is_newer(<CHECK>,<AGAINST>[,<AGAINST>...])

Check the file supplied as the first parameter against the file or files
supplied as the second and subsequent parameters. The return value from
C<is_newer> is one of:

 "0 but true" if the check file does not exist
 -N           if the Nth dependent file does not exist
  N           if the Nth dependent file is newer than the check file
  0           otherwise

Any true value implies that the check file is not up to date. Finer
granularity can be achieved by analysing the precise return value.

In the event that a dependent file is found to be newer, the return value
is equal to the position of the dependent file in the supplied list, which
is one greater than the array index if the passed values came from an
array.

=cut

sub is_newer ($@) {
    return _is_newer(0,shift,@_);
}

=head2 is_newer_missing_ok(<CHECK>,<AGAINST>[,<AGAINST>...])

C<is_newer_missing_ok> ignores missing dependent files and returns -1, N, or
0 based on the results of the dependent files that were found. If a dependent
files does not exist then it is considered to be older rather than returning
undef to the caller. Other than this it is identical to L<"is_newer">.

=cut

sub is_newer_missing_ok ($@) {
    return _is_newer(1,shift,@_);
}

#------------------------------------------------------------------------------

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=cut

1;
