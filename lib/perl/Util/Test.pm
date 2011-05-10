package Util::Test;
use strict;

#------------------------------------------------------------------------------
#
# This module is responsible for testing infrastructure.
#
#------------------------------------------------------------------------------

sub ASSERT(;$$$);
sub genTestSrc($;$);
sub writeTestSrc($$);

use Exporter;
use vars qw(@ISA @EXPORT_OK);
@ISA=qw(Exporter);
@EXPORT_OK=qw(ASSERT genTestSrc writeTestSrc);

#------------------------------------------------------------------------------

sub ASSERT(;$$$) {
    my $line = shift;
    my $actual = shift;
    my $expect = shift;

    return 1 if !defined($actual) and !defined($expect);

    if (defined($actual) and !defined($expect)
        or !defined($actual) and defined($expect)) {
	print "!! $line FAILED - UNDEFINED TERM\n";
	return 0;
    }

    if ($actual ne $expect) {
	$actual =~ s-\n-\\n-g;
	$expect =~ s-\n-\\n-g;
	print "!! $line FAILED - ACTUAL:  \"$actual\" EXPECTED:  \"$expect\"\n";
	return 0;
    }	
    return 1;
}

{
    my @SRC;
    my $UC_COMP;
    my $UC_FILE;
    my $PKG;

    sub INIT_SRC($) {
	my $file = shift;

	@SRC = ();
	($UC_COMP = $file) =~ s/(.*)\..*/\U$1/;
	($UC_FILE = $file) =~ s/(.*)\.(.*)/\U$1_$2/;
        ($PKG  = $file) =~ s/([a-z]+_[a-z0-9]+)_[a-z0-9]+/$1/;
    }

    sub START_GUARD() {
	push @SRC, <<"" =~ m/(\S.*\S)/g;
        #ifndef INCLUDED_$UC_COMP
        #define INCLUDED_$UC_COMP

    }

    sub END_GUARD() {
	push @SRC, <<"" =~ m/(\S.*\S)/g;
        #endif  // INCLUDED_$UC_COMP

    }

    sub PUT_RCS() {
	push @SRC, <<"" =~ m/(\S.*\S)/g;
        #ifndef lint
        static char RCSId_$UC_FILE\[] = "\$Id: \$";
        #endif

    }

    sub START_BB_NS() {
	push @SRC, <<"" =~ m/(\S.*\S)/g;
        namespace BloombergLP \{

    }

    sub START_PKG_NS() {
	push @SRC, <<"" =~ m/(\S.*\S)/g;
        namespace $PKG \{

    }

    sub END_NS() {
	push @SRC, <<"" =~ m/(\S.*\S)/g;
        \} // END NAMESPACE

    }

    sub GET_SRC() {
	return \@SRC;
    }

}

=head1



#------------------------------------------------------------------------------

sub pushNSStart($$) {
    my $a = shift;
    my $file = shift;

    (my $pkg = $file) =~ s/(.*)\..*/$1/;
    $pkg =~ s/([a-z]+_[a-z0-9]+)_[a-z0-9]+/$1/;
    push @$a, "";
    push @$a, "namespace $pkg"." {";
}

#------------------------------------------------------------------------------

sub pushNSEnd($$) {
    my $a = shift;

    RB($a);
    RB($a);
}

#------------------------------------------------------------------------------

sub pushIncH($$) {
    my $a = shift;
    my $file = shift;

    $file =~ s/(.*\.).*/$1h/;  # foo.cpp -> foo.h
    push @$a, "#include \"$file\"";
}

#------------------------------------------------------------------------------

sub pushEntryH($$) {
    my $a = shift;
    my $file = shift;

    pushGuardStart($a, $file);
    pushRCS($a, $file);
    push @$a, "#ifdef __cplusplus";
    pushNSStart(\@$a, $file);
    push @$a, "extern \"C\" {";
    endif($a);
    (my $str = $file) =~ s/(.*)\..*/$1/;
    push @$a, "int $str();";
    push @$a, "#ifdef __cplusplus";
    RB($a);
    pushNSEnd($a, $file);
    endif($a);
    pushGuardEnd($a, $file);
}

=cut

#------------------------------------------------------------------------------

sub genTestSrc($;$) {
    my $codeStr = shift;
    my $file = shift;

    INIT_SRC($file);

    my $i = 0;
    while (1) {
        my $code = substr($codeStr, $i, 2);
        last if !$code;
        SWITCH: {

	    $code =~ /G1/ && do { START_GUARD();    last SWITCH; };
	    $code =~ /R1/ && do { PUT_RCS();    last SWITCH; };
	    $code =~ /G0/ && do { END_GUARD();    last SWITCH; };
	    $code =~ /N1/ && do { START_BB_NS();    last SWITCH; };
	    $code =~ /N2/ && do { START_PKG_NS();    last SWITCH; };
	    $code =~ /N0/ && do { END_NS();    last SWITCH; };

=head1

	    $code =~ /G/ && do { pushGuardStart(\@o, $file);    last SWITCH; };
	    $code =~ /g/ && do { pushGuardEnd(\@o, $file);      last SWITCH; };
	    $code =~ /R/ && do { pushRCS(\@o, $file);           last SWITCH; };
	    $code =~ /N/ && do { pushNSStart(\@o, $file);       last SWITCH; };
	    $code =~ /n/ && do { pushNSEnd(\@o, $file);         last SWITCH; };
	    $code =~ /I/ && do { pushIncH(\@o, $file);          last SWITCH; };
	    $code =~ /E/ && do { pushEntryH(\@o, $file);        last SWITCH; };
	    $code =~ /t/ && do { testsub();        last SWITCH; };

=cut

        }
        $i++;
    }
    return GET_SRC();
}

#------------------------------------------------------------------------------

sub writeTestSrc($$) {
    my $contents = shift;
    my $ofile = shift;

    open(FD, ">$ofile") or die "cannot open $ofile";
    for (@$contents) { print FD "$_\n"; }
    close(FD) or die "cannot close $ofile";
}

1;
