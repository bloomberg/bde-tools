package Util::Message;

#perltidy
use strict;
use warnings;

use IO::File;

#------------------------------------------------------------------------------

use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA       = qw(Exporter);
@EXPORT_OK = qw(
  set_category         get_category		set_default_category
  set_prefix           get_prefix
  set_prog             get_prog

  set_debug            get_debug
  set_verbose          get_verbose
  set_inlog_verbosity  get_inlog_verbosity
  set_outlog_verbosity get_outlog_verbosity

  set_quiet            get_quiet
  set_logging          get_logging
  set_recording        get_recording

  alert error warning warnonce clear_warnonce fatal
  message log_input log_output log_only
  verbose verbose2 verbose3 verbose_alert
  debug debug2 debug3 debug4 debug5 verbose_debug notice
  fatalorwarning

  message_count clear_message_count
  retrieve_messages clear_messages clear_all_messages
  message_count_by_cat

  open_log close_log is_logging

  log_environment log_proctree
);

#==============================================================================

=head1 NAME

Util::Message - Basic messaging facilities for logging and message generation

=head1 SYNOPSIS

    use Util::Message qw[
        message debug debug2 set_debug verbose set_verbose
        warning error alert set_prefix
    ];

    message("Seen message");
    verbose("Hidden verbose");
    set_verbose(1);
    verbose("Seen verbose");
    error("An error is always seen");

    debug("Hidden debug");
    set_debug(1);
    debug("Seen debug");
    debug2("Hidden level 2 debug");

    set_prefix("prefix");
    message("Seen with prefix");
    warning("prefixed warning");
    error("prefixed error");
    alert("prefixed alert");
    set_prefix(""); #clear the prefix

Run C<perl -MUtil::Message -e "Util::Message::test()"> and review the C<test>
routine in this module for an extended usage example.

=head1 DESCRIPTION

C<Util::Message> provides basic messaging facilities for applications. Its
primary interface is a set of message functions for generating messages,
of which the L<"message">, L<"alert">, L<"verbose">, L<"debug">, L<"warning">,
L<"error">, and L<"fatal"> functions are the most important members. These
functions are detailed in L<"MESSAGE FUNCTIONS"> and summarized below.

The module understands different message classes (alert, verbose, debug, etc.),
described in L<"Message Format">; different input criteria described in
L<"Message Inputs">; and different outputs (standard error, log files),
described in L<"Message Outputs">. In addition, C<Util::Message> also provides
an in-memory logging capability that supports message categories.

=head2 Message Format

A message is made up of up to four elements, three of which are configurable
parts of the message prefix and the fourth being the message itself, provided
at the time of invocation with any additional arguments supplied.  The general
form of a message is:

    [user prefix] [message type prefix] [program prefix][message+args]

All of the three prefixes may be omitted. By default both the user-defined
prefix and the program prefix are set to the empty string, and can be queried
or set with the functions described in L<"MESSAGE FORMATTING"> below. The
message type prefix is determined by the function that was used to generate the
message. (The L<"m_message"> function detailed below allows a message to be
generated without a prefix.)

Prefixes that contain non-empty values are space separated from each other in
the final message, as indicated in the syntax above. Empty prefixes do not
contribute a space, however, so if all three prefixes are empty then the
message will be generated without leading spaces.

After the prefixes comes the message itself, which is provided through a
messaging function such as L<"message"> or L<"alert">. All messaging functions
offer the same calling signature, with at least one argument, the main message
text, required. Any number of arguments may also be supplied, in which case
they are combined with the message text using spaces to separate them.

Each of the messaging functions uses its own prefix to discriminate different
classes of message from each other. No direct API exists to change these
prefixes, but the prefix for any message type can be changed by assigning to
the appropriate package variable.  For example, to alter the prefix for debug
messages, write:

    $Util::Message::DEBUG_PREFIX = "dbg> ";

The full list of message functions, override variables, and default message
prefixes is:

    Message Function     | Override Variable | Default Prefix
    ---------------------+-------------------+---------------
    message              | $MESSAGE_PREFIX   | --
    verbose              | $VERBOSE_PREFIX   | --
    verbose2, verbose3   | $VERBOSE2_PREFIX  | --
    alert,verbose_alert  | $ALERT_PREFIX     | **
    error                | $ERROR_PREFIX     | !!
    warning              | $WARNING_PREFIX   | ??
    debug, verbose_debug | $DEBUG_PREFIX     | [[
    debug2, debug3       | $DEBUG2_PREFIX    | [[
    inlog_message        | $INLOG_PREFIX     | <<
    outlog_message       | $OUTLOG_PREGIX    | >>
    log_only             | $LOGONLY_PREFIX   | }}
    notice               | $NOTICE_PREFIX    | //

As noted earlier, to get a completely unprefixed message, use the core
messaging function L<"m_message">.

=head2 Message Inputs

Messages are issued through one of the message generation functions listed
in the previous section and detailed in L<"MESSAGING FUNCTIONS>" below.
A message will not be generated, however, if its input criteria are not met.
Five classes of input message are catered for:

=over 4

=item *

L<"message">, L<"alert">, L<"warning"> and L<"error"> messages are
always accepted for logging.

=item *

Verbose messages are only logged if the verbosity is set high enough:

=over 4

=item *

L<"verbose">, L<"verbose_alert">, 

=item *

L<"verbose2"> - 2 or more

=item *

L<"verbose3"> - 3 or more

=back

The verbosity level is controlled by L<"set_verbose">. The default verbosity
level is 0.

=item *

Debug messages are only logged if the debug level is set high enough:

=over 4

=item *

L<"debug">, L<"debug_alert">, L<"verbose_debug"> - 1 or more (plus
verbose 1 or more)

=item *

L<"debug2"> - 2 or more

=item *

L<"debug3"> - 3 or more

=back

The debug level is controlled by L<"set_debug">. The default debug level is 0.

=item *

Messages for reporting input and output can make use of specialised
versions of the L<"verbose"> routine, using a different prefox to
allow them to be distinguished from other kinds of message. They also
have independent verbose levels, which by default are:

=over 4

=item * L<"log_output"> - 2+

=item * L<"log_input"> - 3+

=back

The verbose level of these messages may be changed with L<"set_inlog_verbosity">
and L<"set_outlog_verbosity">, independently of the main verbose level.

=back

See L<"INPUT CONTROLS"> below for more details.

=head2 Message Outputs

Once a message has been accepted and rendered, it is sent to all of the outputs
that are currently active. Three kinds of output are supported:

=over 4

=item *

Logging to STDERR, controlled by L<"set_quiet">.

=item *

Logging to in-memory category logs, controlled by L<"set_recording">
Categories may be switched with L<"set_category"> and
L<"set_default_category">.

=item *

Logging to a master logfile, controlled by L<"open_log"> and L<"close_log">.

In addition, L<"fatal"> is a special case of L<"error"> which logs an error
and then dies. Optionally, it can also generate a backtrace.

=back

Each logging output may be enabled or disabled independently of the others.
See L<"OUTPUT CONTROLS"> below for more details. Note that is is quite
possible for a message to be generated that is not sent out if none of the
available output channels are enabled. (See also L<"message_count">).

=cut

#==============================================================================

use vars qw(
  $DEFAULT_CATEGORY $DEFAULT_INLOG_VERBOSITY $DEFAULT_OUTLOG_VERBOSITY
);

$DEFAULT_CATEGORY         = "DEFAULT";
$DEFAULT_INLOG_VERBOSITY  = 3;
$DEFAULT_OUTLOG_VERBOSITY = 2;

use vars qw(
  $MESSAGE_PREFIX $ALERT_PREFIX $ERROR_PREFIX $WARNING_PREFIX
  $VERBOSE_PREFIX $VERBOSE2_PREFIX $VERBOSE3_PREFIX
  $DEBUG_PREFIX $DEBUG2_PREFIX $DEBUG3_PREFIX
  $INLOG_PREFIX $OUTLOG_PREFIX $LOGONLY_PREFIX $NOTICE_PREFIX
);

$MESSAGE_PREFIX  = "--";
$VERBOSE_PREFIX  = "--";
$VERBOSE2_PREFIX = "--";
$ALERT_PREFIX    = "**";
$ERROR_PREFIX    = "!!";
$WARNING_PREFIX  = "??";
$DEBUG_PREFIX    = "[[";
$DEBUG2_PREFIX   = "[[";
$INLOG_PREFIX    = "<<";
$OUTLOG_PREFIX   = ">>";
$LOGONLY_PREFIX  = "}}";
$NOTICE_PREFIX   = "//";

#------------------------------------------------------------------------------
# Internal package-scope state

my $category = $DEFAULT_CATEGORY;    # default category

my %log = ();    # hash of category log lists when recording is enabled

#------------------------------------------------------------------------------

=head1 MESSAGE FORMATTING

These functions control the format and rendered fields of logged messages.

=head2 set_prefix($prefix)

Set the user-defined prefix. This prefix appears first in the generate message
text, before the message prefix and program prefix.

I<Although there is no connection between the category of a message and its
visual representation, this prefix is often set from the category name in
order to reflect the category visually. See L<"set_category">.>

=head2 get_prefix()

Get the current value of the user-defined prefix, by default the empty string.

=head2 set_prog($progname)

Set the program prefix. This prefix appears after the message prefix but
before the message text itself. As its name suggests, this prefix element is
intended to be used to set the name of the program (which may be derived from
C<$0>), but it may be set to any arbitrary value.

=head2 get_prog()

Get the current value of the program prefix, by default the empty string.

=cut

# message prefix?
my $prefix = "";
sub set_prefix ($) { $prefix = $_[0] || "" }
sub get_prefix () { return $prefix }

# program name?
my $prog = $0;
$prog =~ m|([^/\\]+)$| and $prog = $1;
sub set_prog ($) { $prog = $_[0] || "" }
sub get_prog () { return $prog }

=head1 INPUT CONTROLS

These functions control whether or not messages are processed, conditioned on
the type of message being issued. The two primary controls are the debugging
level and the verbosity level. Input and output messages (so called simply
because they use appropriate message prefixes) can additionally have their
verbosity level controlled independently of the main verbose level.

=head2 set_debug($level)

Set the debug level to the specified positive integer value.
Messages issued by L<"debug">, L<"debug2">, L<"debug3"> and
L<"verbose_debug"> are controlled by this value.

=head2 get_debug()

Retrieve the current debug level, by default 0.

=head2 set_verbose($level)

Set the verbose level to the specified positive integer value. Messages issued
by L<"verbose">, L<"verbose2">, L<"verbose3">, L<"verbose_debug">, and
L<"verbose_alert"> are controlled by this value.

=head2 get_verbose()

Retrieve the current verbose level, by default 0.

=head2 set_inlog_verbosity($level)

Set the independent verbose level for input messages issued by L<"log_input">.

=head2 get_inlog_verbosity()

Retrieve the current input verbosity level, by default equal to the current
verbose level.

=head2 set_outlog_verbosity($level)

Set the independent verbose level for input messages issued by L<"log_output">.

=head2 get_outlog_verbosity()

Retrieve the current output verbosity level, by default equal to the current
verbose level.

=cut

# are level of debug is accepted?
my $debug = 0;
sub set_debug ($) { $debug = $_[0] || 0 }
sub get_debug () { return $debug }

# what level of verbosity is accepted?
my $verbose = 0;
sub set_verbose ($) { $verbose = $_[0] || 0 }
sub get_verbose () { return $verbose }

# what level of verbosity are inlog messages?
my $inlog_verbosity = $DEFAULT_INLOG_VERBOSITY;
sub set_inlog_verbosity { $inlog_verbosity = $_[0] || 0 }
sub get_inlog_verbosity { return $inlog_verbosity }

# what level of verbosity are outlog messages?
my $outlog_verbosity = $DEFAULT_OUTLOG_VERBOSITY;
sub set_outlog_verbosity { $outlog_verbosity = $_[0] || 0 }
sub get_outlog_verbosity { return $outlog_verbosity }

=head1 OUTPUT CONTROLS

These function controls the destinations to which messages are sent: standard
error, an external log file, and an in-memory log. Each output can be enabled
or disabled independently.

=head2 set_quiet($flag)

Enable or disable output to standard error. If the flag is true, output is
disabled. Otherwise, it is enabled (the default).

=head2 get_quiet()

Get the current status of the quiet flag. A true value means that it is
enabled (i.e. output to standard error is disabled). Otherwise it is
disabled.

=head2 set_recording($flag)

Enable or disable recording of messages to an in-memory log. If the flag is
true, recording is enabled. Otherwise, it is disabled (the default). Disabling
the in-memory log does not clear it.

See L<"IN-MEMORY LOG FUNCTIONS"> for routines to manage the in-memory log.

=head2 get_recording()

Get the current status of the in-memory log. A true value means it is
enabled, otherwise it is disabled.

=head2 set_logging($flag)

Enable or disable output to the disk-based logfile. If the flag is true,
output is enabled. Otherwise it is disabled.

Output is by default disabled while there is no log file, and enabled
automatically when L<"open_log"> is called. Similarly, L<"close_log">
will automatically clear the logging flag.

Note that enabling logging when no log file is opened will have no
effect; the flag only controls output to a log file that has been 
opened previously with L<"open_log">.

=head2 get_logging()

Get the current status of the logging flag. A true value means that it is
enabled, otherwise it is disabled.

=cut

#------------------------------------------------------------------------------

# are messages displayed?
my $quiet = 0;
sub set_quiet ($) { $quiet = $_[0] || 0 }
sub get_quiet () { return $quiet }

# are messages logged to file (assuming there is a log file)
my $logging = 0;
sub set_logging ($) { $logging = $_[0] || 0 }
sub get_logging () { return $logging }

# are messages recorded in memory?
my $recording = 0;
sub set_recording ($) { $recording = $_[0] || 0 }
sub get_recording () { return $recording }

#------------------------------------------------------------------------------
# Messages

{
    my $msg_count = 0;    #line count, mostly for testing purposes
    my %msg_count_by_cat;
    my $logh           = undef;    #file handle, if logging to file directly
    my $logf           = undef;    #filename corresponding to file handle
    my $logall         = 1;        # By default log everything
    my $defaultlogfile = "";

=head2 open_log($filename)

Open a new log file with the specified filename, truncating any existing 
content in the file if it already exists. If a log file has already been 
opened by a previous call to C<open_log> then it is closed first.  An
exception is thrown if the file cannot be opened for output.

Once the log is opened, output to it is automatically enabled. To
subsequently control output to the log, use the L<"set_logging"> function.
The current state of logging can be retrieved with the corresponding
L<"get_logging"> function.

=cut

    sub open_log {
        my $logfile = shift;
        if ( !defined $logfile ) {
            return $defaultlogfile if $defaultlogfile;
            my $dir = $prog;
            $dir =~ s/\..*$//;
            if ( -d "/bb/csdata/logs/$dir" ) {
                $logfile = "/bb/csdata/logs/$dir/$dir.";
            } else {
                $logfile = "/bb/csdata/logs/$dir.";
            }

            # (check env for convenient username tag to add to the log filename
            #  instead of using the expensive Change::Symbols USER lookup)
            my $user = $ENV{CHANGE_USER} || $ENV{USER} || $ENV{LOGNAME};
            if ( defined $user and $user eq 'robocop' ) {
                $user = $ENV{unixnameis} || 'robocop';
            }
            if ( !defined $user or $user eq 'noname' ) {
                $user = getpwuid($<);
            }
            $logfile .= $user . "." . time();
            $defaultlogfile = $logfile;
        }

        $logall = 1;

        close_log() if $logh;

        $logh = new IO::File;
        $logh->open( ">>" . $logfile )
          or die "Failed to open log file $logfile: $!\n";
        $logh->autoflush(1);
        $logf = $logfile;
        verbose("Opened logfile $logf");
        set_logging(1);

        return $logfile;
    }

=head2 close_log()

Close the disk-based logfile (previously opened by L<"open_log">). Returns the
return value from C<close>. An exception is thrown if the log file is not
currently open.

=cut

    sub close_log () {
        if ($logh) {
            set_logging(0);
            verbose("Closed logfile $logf");
            my $rc = close $logh;
            $defaultlogfile = "";
            $logh           = undef;
            $logf           = undef;
            return $rc;
        }
        die "Attempt to close unopened logfile\n";
    }

=head2 is_logging

Returns true if we're currently logging to a file, false if we're not.

=cut

    sub is_logging {
        $logh ? return (1) : return;
    }

    # Future Extension:
    # sub open_category_log...
    # sub close_category_log...

    sub log_environment {

        # log command line
        verbose("Command line:");
        verbose("$0 @ARGV");

        # working dir and machine
        require Cwd;
        verbose( "Working dir:", Cwd::cwd() );
        require Sys::Hostname;
        verbose( "Hostname:", Sys::Hostname::hostname() );
    }

    sub log_proctree {

        # log proc table (so we see potential wrappers used)
        my $proc =
            $^O eq 'aix'     ? '/usr/bin/proctree'
          : $^O eq 'solaris' ? '/usr/bin/ptree'
          : $^O eq 'linux'   ? '/usr/bin/pstree -c'
          :                    '';
        if ($proc) {
            verbose( "Proc tree:\n" . `$proc $$` );
        }
    }

=head1 CORE MESSAGING FUNCTIONS

=head2 m_message($msg,@args)

The C<m_message> function is the base message generator. This function is
called by all the routines detailed in L<"MESSAGING FUNCTIONS"> with the
appropriate prefix attached, if the input criteria are satisfied (i.e. at least
verbose level 1 for L<"verbose">).

C<m_message> may also be called directly to generate an unprefixed message,
with the same usage and behaviour (less the prefix) as the L<"message">
function.

=cut

    sub m_message ($@) {
        my $msg = shift;

        # Got an irritating undef? uncomment this to track it down and use
        # BDE_BACKTRACE=1 to generate the stack trace and see the origin.
        #foreach (@_) {
        #    fatal("Undefined value passed to message") unless defined $_;
        #}

        $msg = "$prefix $msg" if $prefix;

        my $tmsg = $msg;
        my $rmsg = $msg;
        if ($logging) {
            my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime();
            $year += 1900;
            $mon  += 1;
            my $timestamp = sprintf( "%4d-%02d-%02d %02d:%02d:%02d",
                $year, $mon, $mday, $hour, $min, $sec );

            $tmsg = "$timestamp $msg" if $timestamp;
        }
        $msg = "$prog: $msg" if $prog;
        $msg  .= " @_" if @_;
        $tmsg .= " @_" if @_;
        $rmsg .= " @_" if @_;

        # unless quiet, print to STDERR
        print STDERR $msg unless $quiet;

        # if logging to a file, print to the logfile
        print $logh $tmsg if $logh and $logging;

        # if recording to memory, store in the category log
        chomp $rmsg;
        push @{ $log{$category} }, $rmsg if $recording;

        $msg_count++;
    }

    sub _m_message {
        my $should_print   = shift;
        my $msg            = shift;
        my $localquiet     = $quiet;
        my $locallogging   = $logging;
        my $localrecording = $recording;

        $logging = ( $should_print || $logall );
        $quiet = !$should_print || $quiet >= $should_print;
        $recording = $recording
          && $should_print
          ; # Only record the thing if recording's on and we'd otherwise print the message

        m_message( $msg, @_ );

        $quiet     = $localquiet;
        $logging   = $locallogging;
        $recording = $localrecording;
        return 1;
    }

=head2 message_count()

Return the total number of log messages issued since the module was loaded.
Messages that were denied by their input criteria not being met (i.e. a
L<"debug"> message when debug is not enabled) are not counted.

The message I<will> be counted if no output criteria are satisfied:
If quiet mode is enabled, there is no log file, and in-memory
recording is disabled; the message will be counted even though no
outputs are available to it.

=cut

    sub message_count () {
        return $msg_count;
    }

=head2 clear_message_count()

Reset the message count to zero.

=cut

    sub clear_message_count () {
        $msg_count = 0;
    }

    sub record_msg {
        my $cat = shift;
        $msg_count_by_cat{$cat}++;
    }

=head2 message_count_by_cat($cat1, $cat2, ...)

Returns the total number of messages of the passed in categories.

This can be used to determine the exit-code of a program:

    exit EXIT_FAILURE if message_count_by_cat(qw/error fatal/);

    exit EXIT_SUCCESS;

=cut

    sub message_count_by_cat {
        my @cat = @_;

        my $cnt;
        $cnt += $_ || 0 for @msg_count_by_cat{@cat};

        return $cnt;
    }
}

#------------------------------------------------------------------------------

=head1 MESSAGE FUNCTIONS

These functions generate log messages.

=head2 message($msg,@args)

Generate a standard message (see L<"Message Format">).
Return value is 1.

=head2 verbose($msg,@args)

Generate a standard message if the verbose level is 1 or higher.
The return value is 1.

=head2 verbose2($msg,@args)

Generate a standard message if the verbose level is 2 or higher.
The return value is 1.

=head2 verbose3($msg,@args)

Generate a standard message if the verbose level is 3 or higher.
The return value is 1.

=head2 alert($msg,@args)

Generate an alert message (see L<"Message Format">).
The return value is 1.

=head2 verbose_alert($msg,@args)

Generate an alert message if the verbose level is 1 or higher.
The return value is 1.

=cut

sub message ($@) {
    record_msg('message');
    _m_message( 1, $MESSAGE_PREFIX, @_, "\n" );
    return 1;
}

sub verbose ($@) {
    record_msg('verbose');
    _m_message( $verbose >= 1, $VERBOSE_PREFIX, @_, "\n" );
    return 1;
}

sub verbose2 ($@) {
    record_msg('verbose2');
    _m_message( $verbose >= 2, $VERBOSE2_PREFIX, @_, "\n" );
    return 1;
}

sub verbose3 ($@) {
    record_msg('verbose3');
    _m_message( $verbose >= 3, $VERBOSE2_PREFIX, @_, "\n" );
    return 1;
}

sub alert($@) {
    record_msg('alert');
    _m_message( 1, $ALERT_PREFIX, @_, "\n" );
    return 1;
}

sub verbose_alert ($@) {
    record_msg('verbose_alert');
    _m_message( $verbose, $ALERT_PREFIX, @_, "\n" );
    return 1;
}

=head2 log_input($msg,@arg)

Generate an 'input' message (see L<"Message Format">), if the verbose
level is at least equal to the input verbosity level (which is by
default equal to the main verbose level).

The verbose level for input messages is controlled with
L<"set_inlog_verbosity"> and can be queried with L<"get_inlog_verbosity">.

=head2 log_output($msg,@arg)

Generate an 'input' message (see L<"Message Format">), if the verbose
level is at least equal to the input verbosity level (which is by
default equal to the main verbose level).

The verbose level for output messages is controlled with
L<"set_outlog_verbosity"> and can be queried with L<"get_outlog_verbosity">.

=head2 log_only($msg,@arg)

Generate a message that only goes to the log file.

=cut

sub log_input ($@) {
    _m_message( $verbose >= $inlog_verbosity, $INLOG_PREFIX, @_, "\n" );
}

sub log_output ($@) {
    _m_message( $verbose >= $outlog_verbosity, $OUTLOG_PREFIX, @_, "\n" );
}

sub log_only ($@) {
    _m_message( 0, $LOGONLY_PREFIX, @_, "\n" );
}

=head2 error($msg,@args)

Generate an error message (see L<"Message Format">).
The return value is 1.

=cut

sub error($@) {
    record_msg('error');
    _m_message( 1, $ERROR_PREFIX, @_, "\n" );
    return 1;
}

=head2 warning($msg,@args)

Generate a warning message (see L<"Message Format">).
The return value is 1.

=cut

sub warning ($@) {
    record_msg('warning');
    m_message( $WARNING_PREFIX, @_, "\n" );
    return 1;
}

=head2 warnonce($msg,@args)

Generate a warning, and additionally record it for future reference. If the
same warning is issued again, it is suppressed. Note that warnings 
issued via L<warning> are I<not> recorded and will not be suppressed,
nor suppress the same warning issued via C<warnonce>.

=head2 clear_warnonce()

Clear the record of previously issued warnings.

=cut

{
    my %msgs = ();

    sub warnonce ($@) {
        my $msg = "@_";
        &warning and $msgs{$msg} = 1 unless $msgs{$msg};
    }

    sub clear_warnonce() {
        %msgs = ();
    }
}

=head2 fatal($msg,@args)

Generate a fatal message and terminate. If the environment variable
C<BDE_BACKTRACE> is set to a true value then this function will generate a
subroutine stacktrace.

I<Note: This function should always be used in preference to L<die>, at least
for module code.>

=cut

{
    my $loaded = 0;
    my $backtrace;

    sub _backtrace {
        if ( !$loaded ) {
            eval "use Symbols qw(BACKTRACE); \$backtrace = BACKTRACE;";
            $loaded = 1;
        }
        return $backtrace;
    }
}

sub fatal ($@) {
    record_msg('fatal');
    m_message( $ERROR_PREFIX, @_, "\n" );
    if ( _backtrace() ) {
        local $^W = 0;
        require Carp;
        Carp::confess "Fatal error\n";
    } else {
        die "Fatal error\n";
    }
}

=head2 fatalorwarning($tolerant,$msg,@args)

Generate a warning as with L<warning>, if C<$tolerant> is true. Otherwise,
generate a fatal message and terminate as with L<fatal>.

This routine is a convenience wrapper for L<warning> and L<fatal> for callers
who need to conditionally throw an exception based on run-time criteria --
for example, a 'fault tolerance' mode that allows bad input if enabled but
aborts if disabled.

=cut

sub fatalorwarning ($$@) {
    my $tolerant = shift;
    fatal( shift, @_ ) unless $tolerant;
    warning shift, @_;
}

=head2 debug($msg,$args)

Generate a debug message (see L<"Message Format">) if the debug level is 1
or higher.

=head2 debug2($msg,$args)

Generate a debug message if the debug level is 2 or higher.

=head2 debug3($msg,$args)

Generate a debug message if the debug level is 3 or higher.

=cut

sub debug($@)  { _m_message( $debug >= 1, $DEBUG_PREFIX,  @_, "\n" ) }
sub debug2($@) { _m_message( $debug >= 2, $DEBUG2_PREFIX, @_, "\n" ) }
sub debug3($@) { _m_message( $debug >= 3, $DEBUG2_PREFIX, @_, "\n" ) }
sub debug4($@) { _m_message( $debug >= 4, $DEBUG2_PREFIX, @_, "\n" ) }
sub debug5($@) { _m_message( $debug >= 5, $DEBUG2_PREFIX, @_, "\n" ) }

=head2 verbose_debug($msg,@args)

Generate a verbose debug message. Both the debug and verbose levels must be
at least 1 for the message to be handled.

=cut

sub verbose_debug ($@) {
    _m_message( ( $verbose && $debug ), $DEBUG_PREFIX, @_, "\n" );
}

=head2 notice ($msg,@args)

Generate a notice message. Notices are intended to be ultra-low priority
messages, equivalent to the standard message but with a different prefix to
allow them to be filtered more easily.

=cut

sub notice ($@) {
    record_msg('notice');
    m_message( $NOTICE_PREFIX, @_, "\n" );
}

#------------------------------------------------------------------------------

=head1 IN-MEMORY LOG HANDLING

If recording is enabled through L<"set_recording"> then messages will be saved
in an in-memory log. Messages may then be retrieved from this log with the
L<"retrieve_messages"> function.

The in-memory log supports I<categories>, with one category active at any
given time. If no explicit category is specified then a default category is
used. Messages may later be retrived from a category specified by name to
L<"retrieve_messages">. The default category is used if no category is
specified, so there is no need to use categories to make use of the in-memory
log.

The following functions enable category management of the in-memory log:

=head2 set_category($name)

Set the name of the category to which messages should now be recorded,
if recording is enabled. The category remains in effect until it is changed.

=head2 get_category()

Get the name of the currently selected category. This will be the default
category if L<"set_category"> has not been previously invoked.

=head2 set_default_category($name)

Set the name of the category to the default category. The
L<"retrieve_messages"> function retrieves messages from the default category
if no explicit category is specified.

=cut

sub set_category($) {
    $category = $_[0];
    $log{$category} = [] unless exists $log{$category};
}
sub get_category () { return $category }
sub set_default_category() { $category = $DEFAULT_CATEGORY }

=head2 retrieve_messages([$category])

Retrieve an in-memory message log from the specified category, or from the
default category if no explicit category is requested. Returns an array
reference of messages on success (the array may be empty if there are no
messages in the category, however) or C<undef> if the category does not exist.

=cut

sub retrieve_messages (;$) {
    $_[0] = $DEFAULT_CATEGORY unless $_[0];

    if ( exists $log{ $_[0] } ) {
        return $log{ $_[0] };
    }
    return;
}

=head2 clear_messages([$category])

Clear all extant messages in the specified category, or clear the default
category if no explicit category is requested. The category is also removed.
Returns the array reference to the messages that were removed, or C<undef>
if the category was not present.

=cut

sub clear_messages (;$) {
    $_[0] = $DEFAULT_CATEGORY unless $_[0];

    if ( exists $log{ $_[0] } ) {
        return delete $log{ $_[0] };
    }
    return;
}

=head2 clear_all_messages()

Clears all extants messages in all categories. No return value.

=cut

# clear all in-memory message-logs
sub clear_all_messages () {
    %log = ();

    return;
}

$SIG{__DIE__} = sub {

    # we're not interested in die when used like 'throw'
    unless ($^S) {
        require Carp;
        my $str = join '', @_;

        # log_only will add a newline so we remove any trailing newline and
        # (by splitting) remove any internal newlines
        chomp $str;

        # perl has already added the line number to die messages without
        # trailing newlines, remove it so that it is not duplicated by
        # longmess
        $str =~ s/ at \S+ line \d+\.$//;
        log_only( "DIE:", $_ ) for split /\n/, Carp::longmess($str);
    }
};

$SIG{__WARN__} = sub {
    require Carp;
    my $str = join '', @_;

    # log_only will add a newline so we remove any trailing newline and
    # (by splitting) remove any internal newlines
    chomp $str;

    # perl has already added the line number to die messages without
    # trailing newlines, remove it so that it is not duplicated by
    # longmess
    $str =~ s/ at \S+ line \d+\.$//;
    log_only( "WARN:", $_ ) for split /\n/, Carp::longmess($str);

    # a __WARN__ handler suppresses the normal warn, call it explicitly
    warn(@_);
};

#------------------------------------------------------------------------------

sub test {
    message("Seen message");
    message( "Seen", message_count(), "1 expected" );

    verbose("Hidden verbose");
    set_verbose(1);
    verbose("Seen verbose");
    verbose2("Hidden verbose2");
    set_verbose(2);
    verbose2("Seen verbose2");
    set_verbose(0);
    alert( "Seen", message_count(), "4 expected" );

    debug("Hidden debug");
    set_debug(1);
    debug("Seen debug");
    debug2("Hidden debug2");
    set_debug(2);
    debug2("Seen debug2");
    set_debug(0);
    alert( "Seen", message_count(), "7 expected" );

    set_prefix("prefix");
    message("Seen with prefix");
    set_prog("prog");
    message("Seen with prog");
    warning("Seen warning");
    error("Seen error");
    alert("Seen alert");
    set_prefix("");
    set_prog("");
    alert( "Seen", message_count(), "13 expected" );

    set_verbose(1);
    log_input("Hidden inlog");
    log_output("Hidden outlog");
    set_verbose(2);
    log_input("Hidden inlog");
    log_output("Seen outlog");
    set_verbose(3);
    log_input("Seen inlog");
    alert( "Seen", message_count(), "16 expected" );
    set_verbose(1);
    set_inlog_verbosity(2);
    log_input("Hidden inlog verbosity 2");
    set_inlog_verbosity(1);
    log_input("Seen inlog verbosity 1");

    set_recording(1);
    message("Seen default category");
    set_category("Category1");
    message("Seen Category1 message");
    alert("Seen Category1 alert");
    set_category("Category2");
    warning("Seen Category2 warning");
    set_recording(0);
    alert( "Seen", message_count(), "22 expected" );

    my $cdfl = retrieve_messages();
    message( "Default category $cdfl", scalar( @{$cdfl} ), "messages" );
    message("Default category: $_") foreach @$cdfl;

    my $cat1 = retrieve_messages("Category1");
    message( "Category1 $cat1", scalar( @{$cat1} ), "messages" );
    message("Category1: $_") foreach @$cat1;

    my $cat2 = retrieve_messages("Category2");
    message( "Category2 $cat2", scalar( @{$cat2} ), "messages" );
    message("Category2: $_") foreach @$cat2;

    clear_messages("Category1");
    $cat1 = retrieve_messages("Category1");
    if ( $cat1 == undef ) {
        message("Category1 now empty");
    } else {
        fatal( "Category1 now contains", scalar( @{$cat1} ), "messages" );
    }
    alert( "Seen", message_count(), "31 expected" );

    message("Seen going quiet");
    set_recording(1);
    set_category("QuietCategory");
    set_quiet(1);
    message( "Category now:", get_category() );
    message("Hidden on the quiet");
    set_category_default();
    set_quiet(0);
    my $qc = retrieve_messages("QuietCategory");
    message("Seen back in default");
    message( "Quiet Category $qc", scalar( @{$qc} ), "messages" );
    message("Quiet Category: $_") foreach @$qc;
    set_recording(0);

    alert( "Seen", message_count(), "39 expected" );

    my $logfile = "./tmp.log";
    open_log $logfile;
    message("Seen message in logfile");
    set_quiet(1);
    alert("Seen quiet alert in logfile");
    set_quiet(0);
    close_log();
    fatal("Logfile not created") unless -f $logfile;
    my $size = ( stat $logfile )[7];
    fatal("Logfile not correct size") unless $size == 118;
    open( LOGFILE, $logfile ) || die "Failed to open logfile: $!\n";
    set_debug(1);
    chomp, debug "logged: $_" while <LOGFILE>;
    set_debug(0);
    close LOGFILE || die "Failed to close logfile: $!\n";
    message("Logfile size = $size");
    alert( "Seen", message_count(), "49 expected" );

    fatal("Thank you and goodnight");

    fatal("!! I am never seen");
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Context::Log>

=cut

1;
