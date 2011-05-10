package SupportToken;

use Time::HiRes     qw/gettimeofday/;
use POSIX           qw/uname/;
use Math::BigInt;
use Cwd;

use Change::Symbols qw/$TOKEN_DB_DIR USER/;
use Util::Message;
use Util::File::Functions;

my $token   = generate_token();
my $logfile = Util::Message::open_log();
my $tool    = $0;
my $args    = join ' ' => @ARGV;
my $cwd     = cwd();
my $time    = localtime;
my $user    = USER;

generate_token_file(
        token   => $token,
        logfile => $logfile,
        tool    => $tool,
        args    => $args,
        cwd     => $cwd,
        time    => $time,
        user    => $user,
);

# make sure that END block is run
$SIG{$_} = sub { exit } for qw/INT TERM/;

END {
    Util::Message::alert("******************************************************");
    Util::Message::alert("Support token: $token");
    Util::Message::alert("Please specify the above token in requests to SIBUILD.");
    Util::Message::alert("******************************************************");
}

sub generate_token_file {
    my %args = @_;

    my ($hashed) = $args{token} =~ /(..)-/;
    my $dir = "$TOKEN_DB_DIR/$hashed";

    Util::File::Functions::ensure_path($dir);

    open my $fh, '>', "$dir/$args{token}"
        or Util::Message::error("Cannot create support token file $dir/$args{token}: $!");

    printf $fh "%-7s: %s\n", uc($_), $args{$_}
        for qw/token user tool args cwd time logfile/;
}

sub generate_token {
    (my $time = Time::HiRes::gettimeofday()) =~ s/\.//;
    (my $timex = Math::BigInt->new($time)->as_hex) =~ s/^0x//;
    return sprintf "%X-%s-%X-%s", $<, uc($timex), $$, hostname();
}

sub hostname {
    return (uname)[1];
}

1;
__END__
=head1 NAME

SupportToken - Automated logging and support token generation

=head1 SYNOPSIS

    use SupportToken;

    # your script follows

=head1 DESCRIPTION

By including this module in your script, your program will generate a unique support token
and on exiting the program echo this token to the user. This token can later be used to 
retrieve valuable information such as the corresponding logfile, the directory from which 
the program was run, the arguments to your program etc.

Additionally, C<SupportToken> will turn on full debugging and log all output to 
F</bb/csdata/logs/progname/>.

The generated support token can later be fed to C<cstoken> to retrieve all available information
for that particular run of the program.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>

=head1 SEE ALSO

L<cstoken>
