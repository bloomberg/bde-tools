# vim:set ts=8 sts=4 noet:

package SCM::CSDB::AutoTxn;

use strict;
use warnings;

use constant {
    TXN_NONE        => 'n',
    TXN_INPROGRESS  => 'p',
    TXN_COMMITTED   => 'c',
    TXN_ROLLEDBACK  => 'r',
    TXN_ERROR       => 'e',
};

our $VERSION = '0.01';

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = bless {} => $class;
    return $self->init(@_);
}

sub init {
    my $self = shift;
    my %arg = @_ & 1 ? die "Expected: parameter hash." : @_;

    die "Expected parameter: dbh.$/" unless exists $arg{dbh};

    $self->tracer($arg{tracer});
    $self->_dbh($arg{dbh});
    $self->_state(TXN_NONE);
    $self->ondestroy($arg{ondestroy} || 'rollback');
    $self->oninit($arg{oninit} || 'begin_work');

    $self->begin_work if $self->oninit eq 'begin_work';

    return $self;
}

sub DESTROY {
    my $self = shift;

    if ($self->_state eq TXN_INPROGRESS) {
        return $self->rollback if $self->ondestroy eq 'rollback';
        return $self->commit if $self->ondestroy eq 'commit';
    }
}

sub begin_work {
    my $self = shift;
    $self->_tracef('begin work');
    $self->_dbh->begin_work;
    $self->_state(TXN_INPROGRESS);
    return $self;
}

sub commit {
    my $self = shift;
    $self->_tracef('commit');
    $self->_dbh->commit;
    $self->_state(TXN_COMMITTED);
    return $self;
}

sub rollback {
    my $self = shift;
    $self->_tracef('rollback');
    $self->_dbh->rollback;
    $self->_state(TXN_ROLLEDBACK);
    return $self;
}

sub oninit      { shift->_member('oninit', @_); }
sub ondestroy   { shift->_member('ondestroy', @_); }
sub tracer	{ shift->_member('tracer', @_); }
sub _state      { shift->_member('state', @_); }
sub _dbh        { shift->_member('dbh', @_); }

sub _member {
    my ($self, $name) = (shift, shift);

    if (@_) {
	# setter
	my $v = shift;
	$self->_tracef('%s: %s -> %s', $name, $self->{"_$name"}, $v);
	return $self->{"_$name"} = $v;
    }
    else {
	# getter
        return $self->{"_$name"};
    }
}

sub _trace {
    my $self = shift;
    return $self->tracer->(__PACKAGE__.' '.(shift)) if $self->tracer;
    return undef;
}

sub _tracef {
    my ($self, $fmt) = (shift, shift);
    $self->_trace(sprintf $fmt, map { (defined) ? $_ : 'undef' } @_); 
}

1;

