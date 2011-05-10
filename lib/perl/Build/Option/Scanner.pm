package Build::Option::Scanner;
use strict;

use base qw(BDE::Object);

use Util::Message qw(fatal);

#==============================================================================

=head1 NAME

Build::Option::Scanner - Scanner for Options files

=head1 SYNOPSIS

  my $scanner=new Build::Option::Scanner();
  my @lines=$scanner->scan("my.opts");

=head1 DESCRIPTION

C<Build::Option::Scanner> provides the basic scanning functionality to extract
symbol information from options files. It provides an object class with one
public method, C<scan>, that returns one lise of text per option item found.

No attempt is made to parse the extracted information. See
L<Build::Option::Parser> for that.

=cut

#==============================================================================

sub scan ($$) {
    my ($self,$file)=@_;

    return $self->throw("$file does not exist") unless -e $file;
    return $self->throw("$file is not a file") unless -f _;
    return $self->throw("Unable to open $file: $!")
	unless open FILE,$file;

    my @result;

    my $continuation=0;

    while (<FILE>) {
        chomp;
	next if /^\s*(#|$)/;
	s/\s*$//;

	if ($continuation) {
	    s|^\s+||; #remove leading spaces of continuation line
	    $result[-1].=$_;
	} else {
	    push @result,$_;
	}

	if ($result[-1] =~ s|\s*\\\s*$| |) {
	    $continuation=1;
	} else {
	    $continuation=0;
	}
    }

    return wantarray ? @result : \@result;
}

#------------------------------------------------------------------------------

sub test ($) {
    my $scanner=new Build::Option::Scanner();
    print "Scanner: $scanner\n";
    print "=== Scanning $_[0]\n";
    print join "\n",$scanner->scan($_[0]);
    print "\n=== Done\n";
}

#==============================================================================

=head1 AUTHOR

  Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

  L<Build::Option::Parser>, L<Build::Option>

=cut

1;
