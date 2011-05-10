# vim:set ts=8 sts=4 noet:

package SCM::CSDB;

use strict;
use warnings;

use DBI;
use Util::Exception qw/exception/;
use SCM::CSDB::AutoTxn;

our $VERSION = '0.01';

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = bless {
	_sth => undef,	
    } => $class;
    return $self->init(@_);
}

sub init {
    my $self = shift;
    my %arg = @_ & 1 ? die "Expected: parameter hash." : @_;
    my %permitted = map { ($_=>1) }
	qw/driver database autoconnect dbh tracer/;

    for (keys %arg) {
        die "Unknown parameter: $_." unless $permitted{$_};
        $self->{'_'.$_} = $arg{$_};
    }

    $self->{_autoconnect} = 1 if not exists $self->{_autoconnect};
    $self->connect if $self->{_autoconnect} and not $self->dbh;

    return $self;
}

sub connect {
    my ($self) = @_;

    $self->_dbh(DBI->connect($self->_datasource));
    $self->_dbh->{HandleError} = \&_dbierror;

    # XXX make informix 7.3 block when rows / tables are locked e.g. in txn
    # see http://tinyurl.com/y34odb for this non-standard SQL extension
    $self->_dbh->do('set lock mode to wait') if $self->_driver eq 'Informix';

    return $self;
}

sub sql_template {
    my ($self, $query) = @_;

    my $class = ref($self) || $self;

    {
	no strict 'refs';
	my $sql = ${"${class}::SQL"}->{$query}
	    or $self->throw("$query: No such query in package $class");
	
	return $sql;
    }
}

sub throw {
    my ($self, $error) = @_;
    die exception($error, 100);
}

sub dbh {
    my $self = shift;
    return $self->_dbh;
}

sub txn {
    my ($self) = @_;
    return SCM::CSDB::AutoTxn->new(dbh => $self->dbh, tracer => $self->tracer);
}

sub execute {
    my ($self, $query, $queryvalues) = @_;

    my ($sth, $parms) = $self->_get_sth($query, $queryvalues);

    my $rv = $sth->execute(@$parms);
    return $rv ? ($sth,$rv) : (undef,0);
}

sub execute_array {
    my ($self, $query, $queryvalues, %attr) = @_;

    my ($sth, $parms) = $self->_get_sth($query, $queryvalues);

    my $tuples = $sth->execute_array(\%attr, @$parms);
}

sub select_one {
    my $self = shift;
    my ($sth,$rv) = $self->execute(@_);
    return $sth->fetchrow_hashref('NAME_lc');
}

sub select_all {
    my ($self, $query, $queryvalues) = @_;

    my ($sql, $parms, undef) = $self->_get_query($query, $queryvalues);

    return $self->dbh->selectall_arrayref($sql, {}, @$parms);
}

sub _get_query {
    my ($self, $query, $values) = @_;

    my $sql = $self->sql_template($query);

    # A cacheable query is one that contains neither literal nor raw parameters.
    # Bind parameters are ok.
    my $can_cache = 1;

    # replace literals first
    $sql =~ s/\$(\w+?)\$/$self->_sub_literal($values, $1, $query)/ge
	and $can_cache = 0;

    # replace raw parameters for which we don't quote.
    $sql =~ s/&(\w+?)&/$self->_sub_raw($values, $1, $query)/ge
	and $can_cache = 0;

    # replace bind values with placeholder and push params to array
    my @parms;
    $sql =~ s/%(\w+?)%/push @parms, $self->_sub_bind($values, $1, $query); '?'/ge;

    return ($sql, \@parms, $can_cache);
}

sub _sub_literal {
    my ($self, $values, $key, $query) = @_;
    $self->throw("$query: query requires '$key' as literal")
        if not exists $values->{$key};
    return $self->_dbh->quote($values->{$1});
}

sub _sub_bind {
    my ($self, $values, $key, $query) = @_;
    $self->throw("$query: query requires '$key' as bind value")
        if not exists $values->{$key};
    return $values->{$key};
}

sub _sub_raw {
    my ($self, $values, $key, $query) = @_;
    $self->throw("$query: query requires '$key' as raw value")
        if not exists $values->{$key};
    my $val = $values->{$key};

    return $val;
}

# create and return a new transaction, unless 'notxn' flag is passed
sub _enter_txn {
    my ($self, $args) = @_;
    my $txn = $args->{notxn} ? undef : $self->txn;
    $args->{notxn} = 1 if $txn; # callee's need not start txns now
    return $txn;
}

# run a method in a transaction envelope, unless explicitly requested not to
sub _txnwrap {
  my ($self, $f, $param, %args) = @_;
  my $txn = $self->_enter_txn(\%args);
  my @rv = $f->($self, $param, %args);
  $txn->commit if defined $txn;
  return @rv[0..$#rv]; # coerce array into list, in case of scalar context
}

sub _dbh        { shift->_member('dbh', @_); }
sub _driver     { shift->_member('driver', @_); }
sub _database   { shift->_member('database', @_); }
sub _datasource { join ':', 'dbi', @{+shift}{qw/_driver _database/}; }
sub tracer	{ shift->_member('tracer', @_); }

sub _member {
    my ($self, $name) = (shift, shift);
    return $self->{"_$name"} = shift if @_;
    return $self->{"_$name"};
}

sub _dbierror {
    require Carp;
    Carp::cluck($_[0]);
    die(exception($_[0], 111));
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

# -----------------------------------------------
# Retrieve cached statement-handle if it exists.
# Otherwise prepare one and return that.
# Additionally, check if just prepared handle can 
# be cached and if so, do so.
# -----------------------------------------------
sub _get_sth {
    my ($self, $query, $queryvalues) = @_;

    my ($sql, $parms, $can_cache) = $self->_get_query($query, $queryvalues);

    return ($self->{_sth}{$query}, $parms) 
	if $self->{_sth}{$query};

    # not cached: prepare statement and cache if possible
    my $sth = $self->dbh->prepare($sql);

    $self->{_sth}{$query} = $sth if $can_cache;

    return ($sth, $parms);
}

1;

