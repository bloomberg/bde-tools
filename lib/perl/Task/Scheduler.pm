package Task::Scheduler;

use strict;
use warnings;

use Util::Message   qw/fatal/;
use Errno	    qw/EINTR ECHILD/;

our $VERSION = '0.01';


sub new {
    my ($class, %args) = @_;

    my $self = bless {} => $class;
    
    $self->slots	( $args{ slots }	|| 4 );
    $self->job		( $args{ job } );
    $self->data		( $args{ data }		|| [] );
    $self->sighandlers	( $args{ sighandlers }	|| {} );
    $self->delay	( $args{ delay }	|| 0 );
    $self->pids		( {} );
    $self->running	( 0 );
    $self->abnormal	( $args{ abnormal }	|| sub {} );
    
    return $self;
}

sub run {
    my $self = shift;
    $self->check;
    $self->init;
   
    my $data;
    while ( defined( $data = $self->datafeed->() ) ) {
	if ($self->running >= $self->slots) {
	    my $pid = $self->do_wait;
	    $self->abnormal->( delete $self->pids->{$pid}, $pid, $?) if $?;
	    $self->running( $self->running - 1 );
	}
	my $pid = $self->spawn( $data );
	
	# crucial line:
	# we store the datapiece under the pid
	# of the process that is running it
	# That way, we can later pass the correct
	# piece of data to the abnormal termination
	# handler.
	$self->pids->{$pid} = $data;

	select undef, undef, undef, $self->delay;
    }

    while ($self->running) {
	my $pid = $self->do_wait;
	$self->abnormal->( delete $self->pids->{$pid}, $pid, $? ) if $?;
	$self->running( $self->running - 1 );
    }
}

sub check {
    my $self = shift;

    $self->slots > 0
	or fatal("A Task::Scheduler object needs at least one slot");
    
    ref($self->job) eq 'CODE'
	or fatal("A Task::Scheduler's job to run must be a code-references");
    
    ref($self->data) eq 'ARRAY' ||
    ref($self->data) eq 'CODE'
	or fatal("A Task::Scheduler's Data must be either array- or code-reference");
}

sub init {
    my $self = shift;

    if (ref $self->data eq 'ARRAY') {
	$self->datafeed( sub { return shift @{ $self->data } } );
    } else {
	$self->datafeed( sub { $self->data->() } );
    }
}

sub spawn {
    my ($self, $data) = @_;

    not defined( my $pid = fork ) and fatal("Could not spawn child: ", $!);

    if ($pid) {
	$self->running( $self->running + 1 );
	return $pid;
    }
    
    # START OF CHILD
    while (my ($sig, $handler) = each %{ $self->sighandlers } ) {
	$SIG{ $sig } = sub { $handler->( $data ) };
    }

    $self->job->( $data );
    exit 0;
}

# utility stuff

sub do_wait {
    my $self = shift;

    # waiting....the paranoid way
    my $pid;
    while (($pid = wait) == -1) {
	$!{EINTR}	and next;
	$!{ECHILD}	and fatal("No child processes running (should be ", $self->running, ")");
	fatal("Received strange error: $!");
    }
    return $pid;
}

sub add_sighandler {
    my ($self, $sig, $handler) = @_;
    fatal("Second argument to add_sighandler() must be code-reference") 
	if ref $handler ne 'CODE';
    $self->sighandlers->{ $sig } = $handler;
}

sub slots {
    my $self = shift;
    return $self->{slots} if not @_;
    $self->{slots} = shift;
}
sub job {
    my $self = shift;
    return $self->{job} if not @_;
    $self->{job} = shift;
}
sub sighandlers {
    my $self = shift;
    return $self->{sighandlers} if not @_;
    $self->{sighandlers} = shift;
}
sub pids {
    my $self = shift;
    return $self->{pids} if not @_;
    $self->{pids} = shift;
}
sub data {
    my $self = shift;
    return $self->{data} if not @_;
    $self->{data} = shift;
}
sub running {
    my $self = shift;
    return $self->{running} if not @_;
    $self->{running} = shift;
}
sub datafeed {
    my $self = shift;
    return $self->{datafeed} if not @_;
    $self->{datafeed} = shift;
}
sub delay {
    my $self = shift;
    return $self->{delay} if not @_;
    $self->{delay} = shift;
}
sub abnormal {
    my $self = shift;
    return $self->{abnormal} if not @_;
    $self->{abnormal} = shift;
}

1;

=head1 NAME

Task::Scheduler - A generic job scheduler

=head1 SYNOPSIS

    use Task::Scheduler;

    my $sched = Task::Scheduler->new(
	slots		=> 10,
	job		=> sub { print "$$ - $_[0]" },
	data		=> [ 1 .. 100 ],
	sighandlers	=> {
	    TERM => sub { my $datapiece = shift; 
			   ...
			   exit 0; },
	    },
	abnormal	=> sub { warn "One process exited abnormally while working on ", shift },
			    
    );

    $sched->run;

=head1 DESCRIPTION

I<Task::Scheduler> lets you distribute a sequence of data pieces across separate and
detached processes. Once the object is configured, you essentially just need to
call the L<"run()"> method and wait till it returns. 

=head1 CONSTRUCTOR

=head2 new( %args )

Creates a new Task::Scheduler object on behalf of the configuration given through I<%args>. Options are:

=over 4

=item * slots

The maximum number of concurrent processes. Defaults to 4.

=item * job

The code to run as code-reference. 

=item * data

The data-set to process. This may either be an array-reference or a
code-reference in which case I<data> acts like an iterator: The code-reference
is expected to return one data-set per invocation. The end of the feed is
signaled by return C<undef>. 

=item * delay

A floating-point value being used as delay between spawning the children. This
is used as safety measure to avoid over-load on the machine when many children
have to be spawned.

=item * sighandlers

A hash-reference of signal/coderef pairs. For each pair, the child sets up a
signalhandler for the given signal:

    use Task::Scheduler;
    
    my $s = Task::Scheduler->new(
	...
	sighandlers => {
	    TERM => sub { my $data = shift; 
			  warn "called sigterm" },
	},
    );

The signalhandler is passed the piece of data the process was working on when
it got the signal.

=item * abnormal 

A code-reference run in the parent when a child exited abnormally. The handler
is passed the piece of data the child was working on when it exited, the process
ID and the value of $?.

=back

=head1 METHODS

=head2 run()

This sets of the mainloop of the scheduler. It blocks until all datasets have
been processed. It croaks when the I<Task::Scheduler> object hasn't yet been set up
properly.

=head1 EXPORTS

Nothing by default.

=head1 SEE ALSO

For a more sophisticated tasking module see L<Task::Manager>

=head1 AUTHOR

Tassilo von Parseval, E<lt>tvonparseval@bloomberg.netE<gt>

