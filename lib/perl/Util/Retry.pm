package Util::Retry;
use strict;

use IO::Handle;
use IO::File;
use IPC::Open2;
use IPC::Open3;
use Util::Message qw(fatal);

#==============================================================================

=head1 NAME

Util::Retry - Retry filesystem and subprocess functions on transient failure

=head1 SYNOPSIS

    retry_chdir("/sometimes/here/sometimes/not");

    my $found=retry_eitherof("foo.cpp","foo.c");

    my $output_and_errors=retry_output3("echo","hello world");

=head1 DESCRIPTION

This module wraps common filesystem operations in protective wrappers that will
attempt to retry an operation multiple times, on the basis that the failure may
be transient. This should not be an issue, but on certain platforms and with
certain filesystems, it may.

Note that routines requiring filehandle arguments I<must> be passed an instance
of an IO::Handle or IO::Handle-derived object class.

=cut

#==============================================================================

=head1 EXPORTS

Each routine rescribed under L<"ROUTINES"> below may be exported on demand. In
addition, the following export tags are defined:

=over 4

=item :all

export all available routines

=item :file

export file operations (e.g. L<"retry_open">)

=item :test

export file test operations (e.g. L<"retry_file">)

=item :proc

export command execution operations (e.g. L<"retry_output">)

=back

=cut

use Exporter;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS);

my @file_ops=qw[
     retry_chdir
     retry_open
];

my @test_ops=qw[
     retry_file
     retry_rfile
     retry_dir
     retry_eitherof
     retry_firstof
];

my @proc_ops=qw[
     retry_exec
     retry_system
     retry_open2
     retry_open3
     retry_output
     retry_output3
];

@ISA = ('Exporter');
@EXPORT_OK = (@file_ops,@test_ops,@proc_ops);

%EXPORT_TAGS = (
    all => \@EXPORT_OK,
   file => \@file_ops,
   test => \@test_ops,
   proc => \@proc_ops
);

#------------------------------------------------------------------------------

=head1 CLASS VARIABLES

The number of times an operation is attempted is controlled by the class
variable C<$BDE::Utility::Retry::ATTEMPTS>. It defaults to C<9>. To override
use e.g:

    C<$BDE::Utility::Retry::ATTEMPTS = 20>

The delay between each attempt and subsequent ones is controlled by the class
variable C<$BDE::Utility::Retry::PAUSE>. It defaults to C<3>, meaning that
a random pause between 0 and 3 seconds will occur on each failed attempt up
to the limit imposed by  C<$BDE::Utility::Retry::ATTEMPTS>. To override use
e.g:

   C<$BDE::Utility::Retry::PAUSE = 60>

=cut

use vars qw($ATTEMPTS $PAUSE);
$ATTEMPTS ||= 9;
$PAUSE ||= 3;

#------------------------------------------------------------------------------

# parse a commandline. <<<TODO: make smarter with Text::Balanced for quotematch
sub _parse_cli (@) {
    my @cmd=@_;

    if (@cmd == 1) {
	@cmd=(split /\s+/,$cmd[0]);
	map {
	    s/^(['"])(.*)(\1)$/$2/o
	} @cmd; #strip shell quotes as we go direct
    }

    return @cmd;
}

#------------------------------------------------------------------------------

=head1 ROUTINES

The following routines are available for export:

=head2 retry_chdir(<dir>)

Wraps L<"chdir">. Protectively change to the specified directory. Returns the
return value of the last invoked L<"chdir">.

=cut

sub retry_chdir ($) {
    my $dir=shift;

    my $rc;
    for (0..$ATTEMPTS) {
	$rc=chdir $dir;
        return $rc if $rc;
        sleep int(rand $PAUSE) unless $)==$ATTEMPTS;
    }

    return $rc; #from last chdir
}

#------------------------------------------------------------------------------

=head2 retry_open(<FH>,<FILENAME>)

Wraps L<"open">. Protectively opens the specified file. C<FH> must be an
instance of an IO::Handle-derived object class. C<FILENAME> is a
filename in the same format as the second argument to L<"open">.
C<retry_open> dies if C<FH> is not a valid filehandle.

=cut

sub retry_open ($$) {
    my ($fh,$file)=@_;

    die "Not an IO::Handle handle" unless $fh->isa("IO::Handle");
    die "No file argument" unless $file;

    my $rc;
    for (0..$ATTEMPTS) {
        $rc=open($fh,$file);
        return $rc if $rc;
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return $rc; #from last open
}

#------------------------------------------------------------------------------

=head2 retry_open2(<RDFH>,<WRFH>,<COMMAND>[,<ARG>,<ARG>])

Wraps L<IPC::Open2::open2>. Protectively opens the specified command for
reading and writing using the filehandles supplied. Both C<INFH> and C<OUTFH>
must be an instance of an L<IO::Handle>-derived object class. Returns undef if
the open failed, or the PID of the child process otherwise. On a successful
return the input and output filehandles are connected to the standard output
and standard input of the sub-process respectively. Standard error is not
captured; use L<"retry_open3"> for that.

See also L<"retry_open3">, L<"retry_output">.

=cut

sub retry_open2 ($$;@) {
    my ($rdfh,$wrfh,@cmd)=@_;

    die "RDFH not an IO::Handle handle" unless $rdfh->isa("IO::Handle");
    die "WRFH not an IO::Handle handle" unless $wrfh->isa("IO::Handle");
    die "No command argument" unless @cmd;

    @cmd=_parse_cli(@cmd);

    my $pid;
    for (0..$ATTEMPTS) {
	$pid=open2($rdfh,$wrfh,@cmd);
        last if defined $pid;
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }
    return undef unless defined $pid;

    return $pid;
}

#------------------------------------------------------------------------------

=head2 retry_open3(<RDFH>,<WRFH>,<ERFH>,<COMMAND>[,<ARG>,<ARG>])

Wraps L<IPC::Open3::open3>. Protectively opens the specified command for
reading and writing using the filehandles supplied. Both C<INFH> and C<OUTFH>
must be an instance of an IO::Handle-derived object class. Returns undef if the
open failed, or the PID of the child process otherwise. On a successful return
the input and output filehandles are connected to the standard output and
standard input of the sub-process respectively. Standard error is not captures;
use L<"retry_open3"> for that.

See also L<"retry_open2">, L<"retry_output">.

=cut

sub retry_open3 ($$$@) {
    my ($rdfh,$wrfh,$erfh,@cmd)=@_;

    die "RDFH not an IO::Handle handle" unless $rdfh->isa("IO::Handle");
    die "WRFH not an IO::Handle handle" unless $wrfh->isa("IO::Handle");
    die "ERFH not an IO::Handle handle" unless $erfh->isa("IO::Handle");
    die "No command argument" unless @cmd;

    @cmd=_parse_cli(@cmd);

    my $pid;
    for (0..$ATTEMPTS) {
	$pid=open3($wrfh,$rdfh,$erfh,@cmd); #yes, the arg order is different
        last if defined $pid;
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }
    return undef unless defined $pid;

    return $pid;
}

#------------------------------------------------------------------------------

=head2 retry_file(<FILENAME>)

Wraps L<-f> file test operator. Returns true if the specified file exists,
C<undef> otherwise.

See also L<"retry_rfile">.

=cut

# Try to determine a file's existence in an uncertain filesystem
sub retry_file($) {
    my $file=shift;

    my $rc;
    for (0..$ATTEMPTS) {
        $rc = -f $file;
        return $rc if $rc;
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return $rc; #from last -f
}

#------------------------------------------------------------------------------

=head2 retry_dir(<FILENAME>)

Wraps L<-d> file test operator. Returns true if the specified directory exists,
C<undef> otherwise.

=cut

sub retry_dir ($) {
    my $dir=shift;

    for (0..$ATTEMPTS) {
        return 1 if -d $dir;
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return undef;
}

#------------------------------------------------------------------------------

=head2 retry_rfile(<FILENAME>)

Wraps combination of L<-f> and L<-r> file test operators. Returns true if the
specified file exists and is readable, C<undef> otherwise.

See also L<"retry_file">

=cut

sub retry_rfile ($) {
    my $file=shift;

    for (0..$ATTEMPTS) {
        return 1 if -f $file and -r _;
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return undef;
}

#------------------------------------------------------------------------------

=head2 retry_eitherof($file1,$file2)

Checks for the existence of both of the specified files. Returns 0 if neither
were found, 1 if the first file is found but not the second, 2 if the second
file is found but not the first, and 3 if both were found.

This routine is more efficient than using L<"retry_file"> in cases where the
existence of only one of the two files is expected; it will retry until one
file is found and will not continue to attempt to find the other. However,
it can produce a false negative result if both files do exist but one was
simply transiently unavailable. If this is an issue, use L<"retry_file"> on
each filename separately.

=head2 retry_firstof(@files)

As L<"retry_eitherof"> except that any number of files may be supplied, and
the first file found will be returned, even if others exist.

=cut

# Try to determine one of two  file's existence in an uncertain filesystem
# return 0, 1 if file1, 2 if file2 or 3 if both
sub retry_eitherof ($$) {
    my ($file1,$file2)=@_;

    for (0..$ATTEMPTS) {
        my $found1=-f $file1;
	my $found2=-f $file2;
        if ($found1 or $found2) {
           return 3 if $found1 and $found2;
           return 2 if $found2;
           return 1;
        }
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return 0;
}

sub retry_firstof (@) {
    my @files=@_;
    return 0 unless @files;

    for (0..$ATTEMPTS) {
	my @found=map { -f $_ } @files;
	foreach my $i (0..$#files) {
	    return ($i+1) if $found[$i];
	}

	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return 0;
}

#------------------------------------------------------------------------------

=head2 retry_exec(<CMD>,[<ARG>...])

Wraps L<exec>.

See also L<"retry_system"> and L<"retry_output">.

=cut

sub retry_exec {
    fatal "no command" unless @_;

    for (0..$ATTEMPTS) {
        exec @_ or sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    fatal "failed to exec '@_'";
}

#------------------------------------------------------------------------------

=head2 retry_system(<COMMANDLINE> [,<ARG>...])

Wraps L<system>. The C<COMMANDLINE> parameter may be either a list of
command plus arguments, or a single space-delimited command containing all
arguments. In the latter case, the command is split into an array and
quotes stripped, in order to invoke the subprocess without an intermediate
shell. To suppress this behavior, include at least one C<ARG> (even if it
is blank).

Returns the value of the last system call to be attempted (i.e. 0 on
success, or >>8 for the exit status otherwise).

=cut

sub retry_system(@) {
    my @cmd=@_;

    die "No command argument" unless @cmd;

    @cmd=_parse_cli(@cmd);

    my $rc;

    for (0..$ATTEMPTS) {
	last unless $rc=system(@cmd);
	sleep int(rand $PAUSE) unless $_==$ATTEMPTS;
    }

    return $rc;
}

#<<< migrate this to retry_system_cli; make retry_system work with @args.

#------------------------------------------------------------------------------

=head2 retry_output(<COMMANDLINE>)

Wraps forked L<open>. Executes the supplied single-string command and returns
the standard output from the command to the caller. Returns C<undef> if the
subprocess could not be created, or the output of the invoked command
otherwise.  An empty string is returned if the command was executed but
returned no output.

See also L<"retry_system">, L<"retry_output3">.

=cut

sub retry_output (@) {
    my @cmd=@_;

    die "No command argument" unless @cmd;

    @cmd=_parse_cli(@cmd);

    my ($wrfh,$rdfh)=(new IO::Handle,new IO::Handle);

    my $pid=retry_open2($rdfh,$wrfh,@cmd);
    return undef unless defined $pid;

    my $output="";
    $output.=$_ while <$rdfh>; close $rdfh;

    waitpid $pid,0;
    $?=0 if $?==-1; #autoreap

    return $output;
}

#------------------------------------------------------------------------------

=head2 retry_output3(<COMMANDLINE>)

Wraps L<IOC::Open3::open3>. Executes the supplied single-string command and
collects both the standard output and standard error streams from the invoked
command.  Returns C<undef> if the command could not be invoked, and the
combined output stream otherwise. An empty string is returned if the command
was executed but returned no output.

See also L<"retry_open3">, L<"retry_output">.

=cut

sub retry_output3 (@) {
    my @cmd=@_;

    die "No command argument" unless @cmd;

    @cmd=_parse_cli(@cmd);

    my ($wrfh,$rdfh)=(new IO::Handle,new IO::Handle);

    my $pid=retry_open3($rdfh,$wrfh,$rdfh,@cmd);
    return undef unless defined $pid;

    my $output="";
    $output.=$_ while <$rdfh>; close $rdfh;

    waitpid $pid,0;
    $?=0 if $?==-1; #autoreap

    return $output;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

The L<retry> command.

=cut

#==============================================================================

1;
