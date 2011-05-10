package Term::Interact;
use strict;

use base 'BDE::Object';

## set TERM unconditionally to deterministic, sane setting
## (an unset TERM, or TERM=dumb result in issues with Term::ReadLine)
## (set HOME to quiet Perl warning if HOME is not set)
BEGIN { $ENV{TERM} ||= "vt100"; $ENV{HOME} ||= "/nonexistent"; }

use Term::ReadLine;
use Util::File::Basename qw(basename);
use Util::Message qw(log_only fatal);

#==============================================================================

=head1 NAME

Term::Interact - Object class for user interaction and response gathering

=head1 SYNOPSIS

    my $term=new Term::Interact;
    my $response=$term->promptForSingle("Enter your name: ");
    my $lines=$term->promptForMultiple("Enter several lines> ");
    my $boolean=$term->promptForYN("yes or no? ");

=head1 DESCRIPTION

Term::Interact is a simple utility class for interacting with a user. It
creates a singleton L<Term::ReadLine> instance for input and output, and
provides useful methods for performing common kinds of interaction such
as Yes/No prompts.

=cut

#==============================================================================

my $term;

#------------------------------------------------------------------------------

sub initialise {
    my ($self, $arg) = @_;

    $arg = basename $0 if not defined $arg;

    if (not $term) {
        $term = eval {
            Term::ReadLine->new($arg);
        };
        $term = undef 
            if $term and not defined $term->IN;
    }

    return $self;
}

=head1 METHODS

=head2 isInteractive()

Returns true if running interactively, false otherwise.

More to the point, it checks if there is a terminal object. If there is, 
various methods are used to figure out if STDIN is still connected to a 
terminal. It does NOT inspect the status of STDOUT, nor should it.

=cut

sub isInteractive {
    my $self = shift;

    if ($term and $term->IN and fileno($term->IN)) {
        # in absense of SIGHUP handling, this seems the only way
        my $rin = '';
        vec($rin, fileno($term->IN), 1) = 1;
        return if select($rin, undef, undef, 0.05) == -1;
        return 1;
    } 
    
    return;
}

=head2 promptForSingle([$prompt, [$checkre]])

Get one line of text from the user, optionally with a prompt. If the
optional check regular expression is supplied, keep asking the question until
the response from the user matches the regular expression. For example:

    my $yn=$self->promptForSingle("Is the glass half full?",q{^(?i)[yn]});

=cut

sub promptForSingle ($;$$$) {
    my ($self,$prompt,$checkre,$default)=@_;

    if (not $self->isInteractive) {
        fatal "Not running interactively and no default supplied"
            if not defined $default;
        return $default;
    }

    $checkre = ".+" unless $checkre;

    log_only("prompt:   $prompt");

    my $text;
    do {
	$text=$term->readline($prompt);
    } until (not defined $text or $text =~ /$checkre/i);

    if (not defined $text) {
        log_only("Read undef from terminal. Probably no longer interactive");
        return $default if defined $default;
        fatal "Not running interactively and no default supplied";
    }

    log_only("response: $text");

    return $text;
}

=head2 promptForYN([$prompt])

Get a Yes/No response from the user, optionally with a prompt. Returns true
if C<y> or C<Y> is entered, and false if C<n> or C<N> is entered. Any other
response will cause the question to be repeated.

Note that at this time a return is still needed to complete the response. This
may change in future.

=cut

sub promptForYN ($;$) {
    my ($self,$prompt,$default)=@_;

    if (not $self->isInteractive) {
        fatal "Not running interactively and no default supplied"
            if not defined $default;
        return $default;
    }

    my $yn=$self->promptForSingle($prompt,q{^(?i)[yn]});
    return ($yn=~/y/i) ? 1 : 0;
}

sub promptForYNA ($;$$) {
    my ($self, $prompt,$default)=@_;
    my $yna=$self->promptForSingle($prompt,qr/^[yYnNaA]/,$default);
    return 0 if $yna !~ /^[yYaA]/;
    return lc substr $yna, 0, 1;
}

=head2 promptForMultiple([$prompt [,$checkre]])

Get a multi-line response from the user, optionally with a prompt. The prompt
is repeated for each line. Text entry is terminated by entering a single dot
on its own (in the manner of CVS and other SCMs) or a blank line. The text
entered is returned as a single text string with embedded linefeeds.

The check regular expression, if supplied, is applied to the whole text once
entry has been completed, and not to each line individually. On failure to
match, the entry process continues (i.e. existing lines are retained).

=cut

sub promptForMultiple ($;$$$) {
    my ($self,$prompt,$checkre,$default)=@_;

    if (not $self->isInteractive) {
        fatal "Not running interactively and no default supplied"
            if not defined $default;
        return $default;
    }

    $checkre = ".+" unless $checkre;
        
    my $text;   
    do {
	while (my $input=$term->readline($prompt)) {	
	    last if $input eq '.';
	    $text.="\n" if $text;
	    $text.=$input;	 
	}
    } until (not defined $text or $text =~ /$checkre/i);

    log_only("prompt:   $prompt");

    if (not defined $text) {
        log_only("Read undef from terminal. Probably no longer interactive");
        return $default if defined $default;
        fatal "Not running interactively and no default supplied";
    }

    log_only("response: $text");

    return $text;
}

=head2 promptForMultipleMax([$prompt $num, [,$checkre]])

same with promptForMultiple except checking if the maximum
length reached or not. If input exceeds maximum length,
will ask user to enter it again

=cut

sub promptForMultipleMax {
    my ($self, $prompt, $num, $checkre, $default) = @_;

    if (not $self->isInteractive) {
        fatal "Not running interactively and no default supplied"
            if not defined $default;
        return $default;
    }

    $checkre = '\S+' if not defined $checkre;

    my $text;
    {
	while (defined(my $l = $term->readline($prompt))) {
            $text = '' if not defined $text;
	    last if $l eq '.';
	    $text.="\n" if $text;
	    $text .= $l;
	}

        if (not defined $text) {
            log_only("prompt:   $prompt");
            log_only("Read undef from terminal. Probably no longer interactive");
            return $default if defined $default;
            fatal "Not running interactively and no default supplied";
        }
	
	if (defined $num and length($text) > $num) {
	    $self->printOut("Input too long. Max is $num. ".
			    "Please reenter your description for this change.\n");	
	    $text = '';
	    redo;
	}

	if ($text !~ /$checkre/) {
	    $self->printOut("Invalid entry\n");
	    $text = '';
	    redo;
	}
    }

    log_only("prompt:   $prompt");
    log_only("response: $text");

    return $text;
}

=head2 printOut(@msgs)

Issue the specified messages. This is analgous to using C<print>, but is
marshalled via the C<Term::Interact> instance, and passed through the
underlying L<Term::ReadLine> object. This allows output to be coordinated
with other interactions (such as in the methods above).

=cut

sub printOut (@) {
    my $self=shift;

    my $OUT = $self->isInteractive ? $term->OUT : \*STDERR;
    
    print $OUT @_;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Term::ReadLine>

=cut

1;
