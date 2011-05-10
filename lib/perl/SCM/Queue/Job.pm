# vim:set ts=8 sts=4 noet:

package SCM::Queue::Job;

our $VERSION = '0.01';

use strict;
use warnings;

use File::Basename          qw/basename fileparse/;
use File::stat;
use File::Temp	            qw/tempfile/;
use File::Basename;

use File::Spec;

use Change::Symbols         qw/MOVE_EMERGENCY MOVE_REGULAR 
			       MOVE_BUGFIX MOVE_IMMEDIATE 
			       $STATUS_SUBMITTED/;
use Change::Set;
use Change::Util::Bundle;    
use Util::Message           qw/fatal debug/;
use SCM::Symbols            qw/SCM_PRIO_ROLLBACK SCM_PRIO_EMERGENCY
		               SCM_PRIO_BUGFIX SCM_PRIO_DEVCHANGE 
			       SCM_PRIO_IMMEDIATE
		               SCM_QUEUE SCM_DIR_TMP/;

my %MOVE2PRIO = (
    &MOVE_EMERGENCY => SCM_PRIO_EMERGENCY,
    &MOVE_REGULAR   => SCM_PRIO_DEVCHANGE,
    &MOVE_BUGFIX    => SCM_PRIO_BUGFIX,
    &MOVE_IMMEDIATE => SCM_PRIO_IMMEDIATE,
);

Util::Message::set_debug(1) if not Util::Message::get_debug();

my $STATUS_RE   = "[A-Z]";

sub is_jobfile {
    return 1 if 
        shift =~ /^[A-F0-9]+?_\d+?_\d+?_.+?_\d\d?_${STATUS_RE}_\d+_\d+(_[01])?/;
    return 0;
}

sub parse_filename {
    my $fname = shift;
    $fname =~ /^([A-F0-9]+?)_	# changeset ID
                (\d+?)_		# timestamp
                (\d+?)_		# pid
                (.+?)_		# hostname
                (\d\d?)_	# priority
                ($STATUS_RE)_	# status
                (\d+)_		# pid of child process handling this job (if any)
                (\d+)           # revision ID
                _?([01])?       # dependencies
              /x;
}

sub _change_filename {
    my ($fname,%change) = @_;
    my ($csid, $time, $pid, $host, $prio, $status, $exec_pid, $rev_id, $dep) = 
	parse_filename($fname);
    my %fname = (
	csid => $csid,
	subtime => $time,
	pid => $pid,
	host => $host,
	priority => $prio,
	status => $status,
	execpid => $exec_pid || 0,
	revid => $rev_id || 0,
	hasdeps => $dep || 0,
    );
    %fname = (%fname, %change);
    join('_' => @fname{qw(csid subtime pid host priority status execpid revid hasdeps)}); 
}

sub _rename_job {
    my ($self,%change) = @_;
    my $oldpath = File::Spec->catfile( $self->dir, $self->name );
    my $newname = _change_filename($self->name,%change);
    $self->name($newname);
    my $newpath = File::Spec->catfile( $self->dir, $self->name );
    $self->safe_rename($oldpath => $newpath);
}

sub new {
    my ($class, $csfile, $timestamp) = @_;
    
    my $self = bless {} => $class;

    if (is_jobfile( basename($csfile) )) {
	my ($bname, $dir) = fileparse( $csfile );

	my ($csid, $time, $pid, $host, $prio, $status, $exec_pid, $rev_id, $dep) = 
            parse_filename($bname);
    
	$self->id($csid);
	$self->dir($dir);
	$self->name($bname);
	$self->timestamp($time);
	$self->priority($prio);
	$self->status($status);
	$self->handled_by($exec_pid);
        $self->rev_id($rev_id);
        $self->has_dep($dep);

	my ($csstring, $pre) = do {
	    my $f = $self->safe_open($csfile, '<');
	    my @lines = <$f>;
            my $pre = '';
            if ($lines[-1] =~ /^precursors=/) {
                ($pre = pop @lines) =~ s/^precursors=//;
                chomp $pre;
            }
            (join('', @lines), $pre);
	};
	$self->cs( Change::Set->new($csstring) );
        $self->precursors(split /,/, $pre);
    } else {
	not defined $timestamp
	    and fatal("'$csfile' has no timestamp in name");
	my $csid = basename($csfile);
    
        my $cs;
        if (-B $csfile) {
	    $cs = Change::Util::Bundle->new(bundle => $csfile)->cs;
        } else {
            $cs = Change::Set->load($csfile);
        }
	$self->cs( $cs );
	$self->priority( $MOVE2PRIO{ $cs->getMoveType });
        $self->rev_id(0);
	$self->construct_name( $timestamp );
	$self->dir( undef );
	$self->id( $csid );
        $self->has_dep(0);
    }

    return $self;
}


sub construct_name {
    my ($self, $timestamp) = @_;
    chomp( my $host = `hostname` );
    $self->name( join "_" => $self->id || $self->cs->getID,
			     $timestamp,
			     $$,
			     $host,
			     $self->priority,
			     $STATUS_SUBMITTED,
			     0,
                             0,
                             0);
    $self->timestamp( $timestamp );
    $self->host( $host );
    $self->pid( $$ );
    $self->status( $STATUS_SUBMITTED );
    $self->handled_by(0);
    $self->rev_id(0);
    $self->has_dep(0);
}
    

sub flush_to {
    my ($self, $targetdir, $emptyjob) = @_;
    
    my $target = File::Spec->catfile( $targetdir, $self->name );

    my ($tmpfh, $tmpnam) = tempfile( DIR => $targetdir , SUFFIX => '.tmp' );
    print $tmpfh $self->serialize;
    close $tmpfh;

    # we are going through hoops here to remain atomic:
    # rename tmpfile to empty job file. After that it is no longer empty
    # and in case the rename to $target fails because the process dies,
    # the next instance would find a populated jobfile which it would 
    # simply move to $target.
    if (defined $emptyjob) {
	rename $tmpnam => $emptyjob
	    or fatal("Could not move '$tmpnam' to '$emptyjob': $!");
	rename $emptyjob => $target
	    or fatal("Could not move '$emptyjob' to '$target':", $!);
    } else {
	rename $tmpnam => $target
	    or fatal("Could not move '$tmpnam' to '$target': $!");
    }
    $self->dir( $targetdir );
}

sub copy_to {
    my ($self, $targetdir) = @_;

    require Storable;
    require File::Copy;

    my $clone = Storable::dclone($self);

    my $src	= File::Spec->catfile($clone->dir, $clone->name);
    my $dest	= File::Spec->catfile($targetdir, $clone->name);

    File::Copy::copy($src, $dest) 
	or return;

    $clone->dir($targetdir);

    return $clone;
}

sub move_to {
    my ($self, $targetdir) = @_;
    
    my $src	= File::Spec->catfile( $self->dir, $self->name );
    my $dest	= File::Spec->catfile( $targetdir, $self->name );

    (my $from = $self->dir) =~ s#/+$##;
    (my $to   = $targetdir) =~ s#/+$##;

    $from = (File::Spec->splitdir($from))[-1];
    $to   = (File::Spec->splitdir($to))[-1];

    $self->safe_rename($src => $dest);

    $self->run_hooks($from, $to);

    $self->dir( $targetdir );
}

sub serialize {
    my $self = shift;
    my $string = $self->cs->serialise;
    $string .= "precursors=" . join ',' => $self->precursors;
    return $string;
} 

sub get_files {
    my $self = shift;
    return $self->cs->getFiles;
}

sub process {
    my $self = shift;
    debug("processing " . $self->name);
}

sub change_status {
    my ($self, $new) = @_;
    return if $new eq $self->status;
    $self->status($new);
    $self->_rename_job('status',$new);
}

sub change_execpid {
    my ($self, $newpid) = @_;
    return if $newpid eq $self->handled_by;
    $self->handled_by($newpid);
    $self->_rename_job('execpid',$newpid);
}

sub change_rev_id {
    my ($self, $revid) = @_;
    return if $revid eq $self->rev_id;
    $self->rev_id($revid);
    $self->_rename_job('revid',$revid);
}

sub add_dep {
    my ($self) = @_;
    $self->_rename_job('hasdeps', 1);
}

sub remove_dep {
    my ($self) = @_;
    $self->_rename_job('hasdeps', 0);
}

sub check_constraints {
    my ($class, $job, %constraints) = @_;
    
    UNIVERSAL::isa($job, 'SCM::Queue::Job') and
        return Change::Set->checkConstraints($job->cs, %constraints);
    
    # It's a string    
    my ($cs) = $job =~ /(.*)^precursors=/sm;
    return Change::Set->checkConstraints($cs, %constraints);
}

sub check_constraints_for_file {
    my ($class, $file, %constraints) = @_;

    if (not ref $file) {
        open $file, '<', $file
            or return 0;
    }

    my $job = do {
        local $/;
        <$file>;
    };

    return $class->check_constraints($job, %constraints);
}

# status methods


sub cs {
    my $self = shift;
    return $self->{cs} if not @_;
    $self->{cs} = shift;
}

sub priority {
    my $self = shift;
    return $self->{priority} if not @_;
    $self->{priority} = shift;
}

sub name {
    my $self = shift;
    return $self->{name} if not @_;
    $self->{name} = shift;
}

sub dir {
    my $self = shift;
    return $self->{dir} if not @_;
    $self->{dir} = shift;
}

sub timestamp {
    my $self = shift;
    return $self->{timestamp} if not @_;
    $self->{timestamp} = shift;
}

sub pid {
    my $self = shift;
    return $self->{pid} if not @_;
    $self->{pid} = shift;
}

sub host {
    my $self = shift;
    return $self->{host} if not @_;
    $self->{host} = shift;
}

sub id {
    my $self = shift;
    return $self->{id} if not @_;
    $self->{id} = shift;
}

sub status {
    my $self = shift;
    return $self->{status} if not @_;
    $self->{status} = shift;
}

sub handled_by {
    my $self = shift;
    return $self->{handled_by} if not @_;
    $self->{handled_by} = shift;
}

sub rev_id {
    my $self = shift;
    return $self->{rev_id} if not @_;
    $self->{rev_id} = shift;
}

sub has_dep {
    my $self = shift;
    return $self->{has_dep} if not @_;
    $self->{has_dep} = shift;
}

sub precursors {
    my $self = shift;
    return @{ $self->{precursors} || [] } if not @_;
    @{ $self->{precursors} } = @_;
}

sub add_precursors {
    my $self = shift;
    push @{ $self->{precursors} }, @_;
}

sub safe_open {
    my ($self, $file, $mode) = @_;

    if (open my ($f), $mode, $file) {
        return $f;
    }

    fatal "'$file' was mysteriously unopenable: $!";
}

sub safe_rename {
    my ($self, $src, $dest) = @_;

    warn "renaming " . $self->id, "\n";
    rename $src => $dest and return;

    fatal "'$src' mysteriously was unrenameable to '$dest': $!";
}

# hooks

sub add_hook {
    my ($self, %args) = @_;
    
    !defined $args{$_} and fatal "Cannot add hook with undefined '$_'"
	for qw/name code/;

    my $name = $args{name};
    push @{ $self->{all_hooks} }, $name;

    my $hook = {
	code => $args{code},
	when => $args{when},
	idx  => $#{ $self->{all_hooks} },
    };

    $self->{hooks}{$name} = $hook;
}

sub delete_hook {
    my ($self, $name) = @_;
    
    my $hook = delete $self->{hooks}{$name}
	or return;

    splice @{ $self->{all_hooks} }, $hook->{idx}, 1;
}

sub run_hooks {
    my ($self, $from, $to) = @_;

    warn "running hooks: $from => $to\n";

    my @all = @{ $self->{all_hooks} || []};

    for (@all) {
	warn "checking hook $_\n";
	my $hook = $self->{hooks}{$_} or next;	# hook deleted
	warn "not deleted\n";

	if ($hook->{when}) {
	    my ($hfrom, $hto) = map defined $_ ? $_ : '', @{ $hook->{when} };
	    next if $hfrom ne $from or $hto ne $to;
	}

	warn "yes\n";
	$hook->{code}->($self);
    }
}

# methods that are slightly different from methods in Change::Set 
sub get_file_by_name {
    my ($job, $file) = @_;

    require Change::Util::Canonical;
    my $bl = Change::Util::Canonical::branch_less($file);

    for my $f ($job->cs->getFiles) {
	return $f if Change::Util::Canonical::branch_less($f) eq $bl;
    }
}

1;
__END__

=head1 NAME

SCM::Queue::Job - One job within the queue management system

=head1 SYNOPSIS

    use SCM::Symbols	qw/SCM_PRIO_EMERGENCY/;
    use SCM::Queue::Job;

    while (my $next = <*>) {
	my $job = SCM::Queue::Job->new($next);
	next if not defined $job;
	print "Found emergency job" if $job->priority == SCM_PRIO_EMERGENCY;
    }

=head1 DESCRIPTION

This class implements jobfile objects which describe incoming changesets in
the context of the prequeue, queueing and execution daemon. In addition to
changesets (see L<Change::Set>) these job objects have a notion of precursor
changesets (changesets with an overlapping set of affected source files), the
current location within the queue, the priority and other queue related
information not present in I<Change::Set>.

=head1 CONSTRUCTOR

=head2 new( $path, [$timestamp] )

Constructs a new SCM::Queue::Job object from I<$path> which is the path to the
CS tarball or a job-file or a serialised Change::Set object. This function
works in terms of Change::Util::Bundle if a change set bundle got passed to it.

I<$timestamp> is only optional when I<$path> refers to a job-file, in which
case it is ignored. When passing in a bundled change set or a serialised
Change::Set object, I<$timestamp> is mandatory as this value is used in
constructing a job-file's name.

Returns the object on success. Otherwise it croaks.

=head1 METHODS

=head2 id()

Returns the changeset ID for this job.

=head2 timestamp()

Returns the timestamp of the jobfile (which denotes the time when this
changeset was committed).

=head2 priority()

Returns one of PRIO_ROLLBACK, PRIO_EMERGENCY, PRIO_BUGFIX and PRIO_DEVCHANGE.

=head2 name()

The raw filename of the job (with the path portion stripped).

=head2 dir()

The raw directory location of the job (without the filename). This, effectively, can
be used to query the stage the jobfile is currently in:
    
    my $stage = DIR_PENDING;
    if ($job->dir =~ /$stage$/) {
	print "Job ", $job->name, " is waiting for execution\n";
    }

=head2 cs()

Return the underlying Change::Set object.

=head2 serialize()

Returns a serialized string of the object to be stored on disk. This method
returns what is usualluy stored in a jobfile.

=head2 flush_to( $targetdir, $emptjob )

Flushes the jobfile (which was created from a bundled changeset pointed to by
I<$emptyjob>) to disk and moves it to I<$targetdir>.

=head2 move_to( $new_path  )

Moves the jobfile to I<$new_path> which must be on the same device as its
previous location. 

=head1 CONSTRAINTS

Constraints are a set of conditions that must be a true for a job file.
They are a cheap and fairly generic way of checking the saneness of a
given jobfile.

The following two methods are class methods.

=head2 check_constraints($job, %constraints)

Given I<$job> which is either an SCM::Queue::Job object or a serialized
version thereof, returns true if its Change::File objects satisfy all
the constraints given through I<%constraints>.

Please see L<Change::Set/"checkConstraints"> for more details on the format
of I<%constraints>.

=head2 check_constraints_for_file($file, %constraints)

Given I<$file> which is either a filename or a reference to a readable
filehandle, returns true of its Change::File objects satisfy all the
constraints given through I<%constraints>.

This method has the same semantics as its Change::Set counterpart
C<checkConstraintsForFile>.

=head1 HOOKS

Hooks are software triggers which are run when a job-file moves from one
directory to another. They have three properties: A name, a code-reference that
is executed and a condition, which is a pair of tail directory-elements.

Here is an example for a hook that sends out a message when a jobfile is moved
from prequeued to testd:

    sub notify {
	my $job = shift;
	require SCM::Message;
	SCM::Message->send(
		to	=> 'tvon',
		from	=> 'tvon',
		subject	=> 'Job moved in queue',
		body	=> $job->id . " moved to testd\n",
	);
    }

    $job->add_hook(
	    name    => 'testd',
	    when    => [ SCM_DIR_PREQUEUE, SCM_DIR_QUEUE ],
	    code    => \&notify
    );

Hooks can be deleted by name:

    $job->delete_hook('testd');

Furthermore, it is possible to define more than one hook for the same event.
The hooks will then be run in the same order as they were defined. It is
furthermore possible to delete a hook from inside a handler function:

    sub hook1 {
	my $job = shift;
	$job->delete_hook('hook2');
    }
    
    sub hook2 {
	my $job = shift; 
	...
    }

    ...
    $job->add_hook(name => 'hook1', 
		   code => \&hook1,
		   when => [ DIR1 => DIR2 ]);
    ...
    $job->add_hook(name => 'hook2',
		   code => \&hook2);

The following methods exist:

=head2 add_hook(name => $name, code => \&code, [when => \@from_to])

Adds a hook under the name I<$name> to a job. When the job is moved from
I<$from_to[0]> to I<$from_to[1]>, C<code> is run. The job object is being
passed to the function as only argument.

The I<when> paramter is optional. If it is not specified, the hook will be
triggered on any move from one directory to the next.

=head2 delete_hook($name)

Deletes the hook with the name I<$name> from the job object.

=head1 AUXILIARY FUNCTIONS

=head2 is_jobfile( $path )

Returns a boolean telling you if the given path refers to a proper jobfile. It
does so by looking at the filename only.

=head1 EXPORTS

Nothing.

=head1 SEE ALSO

L<Change::Util::Bundle>

=head1 AUTHOR

Tassilo von Parseval, E<lt>tvonparseval@bloomberg.netE<gt>
