#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;

use BDE::Rule::Base;
use Util::Message qw(fatal error alert message debug);
use Symbols qw(EXIT_FAILURE EXIT_SUCCESS);
use Util::File::Basename qw(basename);
use BDE::RuleSet::Conf "$FindBin::Bin/../etc/rules.conf";

#==============================================================================

=head1 NAME

bde_rule.pl - Extract and display documentation for rules modules

=head1 SYNOPSIS

    bde_rule.pl L1 L2,N5 L3, L4
    bde_rule.pl 

=head1 DESCRIPTION

C<bde_rule.pl> returns the detailed description of the rule or rules supplied
as command-line arguments. Multiple rules may be specified as comma- or space-
separated strings, or any combination of commas and spaces. Descriptions are
output in the order specified. The exit status is 0 if all rules exist or a
positive number equal to the number of rules that could not be found otherwise.

If no rules are supplied on the command line then details for *all* rules 
within the rules configuration file are returned.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [<rule>[,| ][<rule>[,| ]...]]
  --debug      | -d           enable debug reporting
  --help       | -h           usage information (this text)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        help|h
    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    return \%opts;
}

sub displayRuleText($$) {
    my($rule,$text) = @_;

    print "\n======================================== Rule $rule ========================================\n" if $rule ne "INTRO";
    print "$text";
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();

    my $result=0;

    # if no argument is supplied retrieve Doc.pm and drive from that
    if (!@ARGV) {
        print <DATA>, "\n";
        if (eval "require BDE::Rule::Doc") {
            my $rule = "BDE::Rule::Doc"->new();
            my $doc = $rule->getDescription();
            pos($doc) = 0;
            while (1) {
                $doc =~ /<<<([\w\s]+)>>>(.*?)(<<<[\w\s]+>>>)/sgo;
                my ($action,$text,$nextAction) = ($1,$2,$3);
                pos($doc) = pos($doc) - length($nextAction);
                if ($action =~ /INCLUDE (\w+)/o) {
                    my $rule = $1;
                    if (eval "require BDE::Rule::$rule") {
                        displayRuleText($rule, "BDE::Rule::$rule"->new->getDescription);
                    }
                    else {
                        die "cannot eval $rule: $!";
                    }
                }
                else {
                    displayRuleText($action, $text);
                }
                last if $doc =~ /\G<<<END>>>/;
            }
        }
        else {
            die "cannot eval Doc.pm: $!";
        }
    }

    # argument supplied
    else {
        foreach my $rule (grep { /\w/ } map { split /,/,$_ } @ARGV) {
            if (eval "require BDE::Rule::$rule") {
                my $rule="BDE::Rule::$rule"->new();
                print "=== Rule $rule ===\n\n";
                my $description=$rule->getDescription();
                chomp $description;
                print "$description\n\n";
            } else {
                $result++;
                print "!!! Rule $rule does not exist\n\n";
            }
        }
    }

    exit $result;
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_verify.pl>, L<bde_build.pl>, L<BDE::Rule>

=cut

__DATA__

