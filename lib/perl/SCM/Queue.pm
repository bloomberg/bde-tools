# vim:set ts=8 sts=4 noet:

package SCM::Queue;

use strict;
use warnings;

use File::Spec;

use SCM::Symbols	qw/SCM_CSDB SCM_CSDB_DRIVER/;
use Change::Symbols	qw/DEPENDENCY_TYPE_ROLLBACK/;

use Util::Message       qw/fatal error/;
use SCM::Queue::Job;
use SCM::CSDB;
use SCM::UUID;

our $VERSION = '0.01';

sub new {
    my ($class, $basedir) = @_;
    my $self = bless {} => $class;
    $self->basedir( $basedir );

    my $csq = eval {
	SCM::CSDB->new(database => SCM_CSDB, driver => SCM_CSDB_DRIVER)
    };

    fatal "Creating of SCM::CSDB::Access failed: $@"
	if $@;

    $self->csq($csq);
    $self->uuid(SCM::UUID->new);
    return $self;
}

sub basedir {
    my $self = shift;
    return $self->{basedir} if not @_;
    $self->{basedir} = shift;
}

sub csq {
    my $self = shift;
    return $self->{csq} if not @_;
    $self->{csq} = shift;
}

sub csq_status {
    my $self = shift;
    require SCM::CSDB::Status;
    $self->{csq_status} ||= SCM::CSDB::Status->new(dbh => $self->csq->dbh);
    return $self->{csq_status};
}

sub csq_hist {
    my $self = shift;
    require SCM::CSDB::History;
    $self->{csq_hist} ||= SCM::CSDB::History->new(dbh => $self->csq->dbh);
    return $self->{csq_hist};
}

sub csq_changeset {
    my $self = shift;
    require SCM::CSDB::ChangeSet;
    $self->{csq_changeset} ||= SCM::CSDB::ChangeSet->new(dbh => $self->csq->dbh);
    return $self->{csq_changeset};
}

sub uuid {
    my $self = shift;
    return $self->{uuid} if not @_;
    $self->{uuid} = shift;
}

sub run {
    fatal(ref shift, " needs to override run()");
}

sub get_jobs {
    my ($self, $dir) = @_;
    
    my $d = File::Spec->catdir( $self->basedir, $dir );
    opendir my $dirh, $d or fatal("Could not open '$d'", $!);

    my @jfiles = grep SCM::Queue::Job::is_jobfile($_), readdir $dirh;
   
    my @jobs = map SCM::Queue::Job->new( File::Spec->catfile($d, $_) ), @jfiles;

    return @jobs;
}

sub set_dbstatus {
    my ($self, $job, $newstatus) = @_;

    my ($err, $uuid) = $self->uuid->uuid2unix($job->cs->getUser);
    $uuid = 0 if $err;

    my $ok = eval {
	$self->csq_status->alterChangeSetDbRecordStatus($job->id, 
							newstatus => $newstatus, 
							uuid	  => $uuid);
    };

    error "DB update for " . $job->id . ": $@" if not $ok;
}

sub get_dbstatus {
    my ($self, $job) = @_;

    my $id = UNIVERSAL::isa($job, 'SCM::Queue::Job') ? $job->id : $job;

    my $status = eval {
	$self->csq_status->getChangeSetStatus($id)
    };

    return $status;
}

sub get_dbrecord {
    my ($self, $job) = @_;
   
    my $id = UNIVERSAL::isa($job, 'SCM::Queue::Job') ? $job->id : $job;

    my $cs = eval {
	$self->csq_changeset->getChangeSetDbRecord($id)
    };

    return $cs;
}

sub add_dbdependency {
    my ($self, $job, $pairs) = @_;

    my $id = UNIVERSAL::isa($job, 'SCM::Queue::Job') ? $job->id : $job;

    return eval {
	$self->csq_changeset->addDependenciesToChangeSet($id, $pairs);
    };
}

sub update_status {
    my ($self, $job, $newstatus) = @_;

    return if not $job->cs->getDependenciesByType(DEPENDENCY_TYPE_ROLLBACK);

    $self->set_dbstatus($job,$newstatus);
}

1;

__END__

=head1 NAME

SCM::Queue - Abstract base class for SCM daemons

=head1 SYNOPSIS

    use base qw/SCM::Queue/;

    sub run {
	my $self = shift;
	warn "Running in base-directory ", $self->basedir;
	...
    }
	
=head1 DESCRIPTION

This package acts as an abstract base class for SCM daemon modules. Currently,
L<SCM::Queue::Prequeue>, L<SCM::Queue::Incoming>, and L<SCM::Queue::Execution> 
all inherit from this class.

It does little more than merely enforcing an interface for derived daemons.

=head1 INTERFACE

The following two methods are provided:

=head2 new( $basedir )

This sets up a new object of your derived class with I<$basedir> as its base-directory.

=head2 run()

An abstract method for you to override where all the action takes place.

=head2 basedir( [$basedir] )

When called without arguments, returns the base-directory of the daemon. With an argument,
sets the daemon's base-directory.

=head1 SEE ALSO

L<SCM::Queue::Prequeue>, L<SCM::Queue::Incoming>, L<SCM::Queue::Execution> for examples on 
how to derive from this class.

=head1 AUTHOR

Tassilo von Parseval, E<lt>tvonparseval@bloomberg.netE<gt>
