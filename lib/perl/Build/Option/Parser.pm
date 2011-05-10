package Build::Option::Parser;
use strict;

use base 'BDE::Object';

use Build::Option::Raw;
use Composite::Commands qw(ADD);
use BDE::Build::Ufid;

#==============================================================================

=head1 NAME

Build::Option::Parser - Generate raw option objects from descriptive strings

=head1 SYNOPSIS

  my $scanner=new Build::Option::Scanner();
  my @lines=$scanner->scan("build.opts");

  my $parser=new Build::Option::Parser();
  my @items=map { $parser->parse($_) } @lines;

=head1 DESCRIPTION

This module generates C<Build::Option::Raw> objects whose attributes are
populated according to the contents of a string.

=head1 METHODS

C<Build::Option::Parser> provides one method, C<parse>.

=head2 parse($string)

This method takes a string as input and returns a C<Build::Option::Raw> object
as output. If the input cannot be parsed, an exception is thrown. See the
L<"SYNOPSIS"> for an example.

=cut

#==============================================================================

{
    my $pattern = qr/^
        (?:([!^+-]{2})\s+)?     # $1=command
        ([^-\s]+)               # $2=kin
        (?:-
        ([^-\s]+)?              # $3=os
        (?:-
        ([^-\s]+)?              # $4=arch
        (?:-
        ([^-\s]+)?              # $5=osver
        (?:-
        ([^-\s]+)?              # $6=comp
        (?:-
        ([^-\s]+)?              # $7=compver
        )?)?)?)?)?
        \s*\b([\w_*]+)\b        # $8=ufid

        \s*\b(\w+)\b\s*         # $9=key
        =
        \s*(?:(\S.*)\s*)?       # $10=value
    $/x;

    sub parse ($$) {
        my ($self,$item)=@_;

        #<<TODO: verify command. verify ufid flags. verify kin

        if ($item =~ /$pattern/) {
            my $ufid=new BDE::Build::Ufid(defined($8) ? $8 : '_');
            $self->throw("Failed to instantiate UFID '$8'\n")
              unless ref $ufid;

            my $bor=new Build::Option::Raw({
                command    => (defined($1) ? $1 : ADD),
                kin        => (defined($2) ? $2 : '*'),
                os         => (defined($3) ? $3 : '*'),
                arch       => (defined($4) ? $4 : '*'),
                os_v       => (defined($5) ? $5 : '*'),
                compiler   => (defined($6) ? $6 : '*'),
                compiler_v => (defined($7) ? $7 : '*'),
                ufid       => $ufid,
                name       => (defined($9) ? $9 : '??NONAME??'), #require name
                value      => (defined($10) ? $10 : ''),
                what       => 'default'
            });
            $self->throw("Failed to instantiate '$item'\n") unless ref $bor;
            return $bor;
        } else {
            $self->throw("Failed to parse '$item'\n");
            return undef;
        }
    }
}

#------------------------------------------------------------------------------

sub test (;$) {
    require Build::Option::Scanner;

    my $what=$_[0] || "/bbcm/infrastructure/etc/default.opts";

    my $scanner=new Build::Option::Scanner();
    my $parser=new Build::Option::Parser();
    print "Scanner: $scanner\n";
    print "Parser: $parser\n";

    print "=== Scanning $what\n";
    my @scans=$scanner->scan($what);
    print join "\n",@scans;
    print "\n=== Parsing $what\n";
    foreach my $scan (@scans) {
        my $item=$parser->parse($scan);
        if (defined $item) {
            $item->setWhat($what);
            print $item,"\n";
        } else {
            print "!! parse of '$scan' failed\n";
        }
    }
    print "\n=== Done\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Build::Option::Scanner>, L<Build::Option>

=cut

1;
