package Util::File::Path;

=head1 NAME

Util::File::Path - work with unix paths

=head1 SYNOPSIS

  $path1 = Util::File::Path->new("the/quick/brown/cat");
  $basename = pop @{$path1};
  push @{$path1}, "dog";
  $path2 = Util::File::Path::relative_to($path1, "the/slow/green/dog");
  $path3 = Util::File::Path->new("/usr/share/animals");
  $path4 = Util::File::Path->new(@{$path3}, @{$path2});
  $path4->collapse();

=head1 DESCRIPTION

=cut

use overload
  fallback => 1,
  '@{}' => 'to_arrayref',
  'bool' => 'to_boolean',
  q{""} => 'to_string';

our @ISA;
our $VERSION = '0.01';
our %EXPORT_TAGS = ();
our @EXPORT_OK	= map @$_, values %EXPORT_TAGS;
our @EXPORT	= qw();   # nothing by default

use strict;

sub new {
  my $this = shift;
  my $class = ref($this) || $this;
  my $self = {};

  bless $self => $class;
  $self->init(@_);

  return $self;
}

sub init {
  my $self = shift;

  if (@_ == 1) {
    my $ref = ref($_[0]);
    return $self->_from_string($_[0]) if !$ref;
    return $self->_from_object($_[0]) if $ref eq __PACKAGE__;
    return $self->_from_array(@{$_[0]}) if $ref eq 'ARRAY';
  }
  else {
    return $self->_from_array(@_);
  }
}

# turn something into an object of the class, if it isn't already
sub coerce { return ref($_[0]) eq __PACKAGE__ ? $_[0] : new(__PACKAGE__, @_); }

=head1 METHODS

=head2 $path->parent()

Return a new Util::File::Path representing the parent. If the path
only has one component, the empty path is returned.

=cut

sub parent {
  my @parts = @{shift()};
  return Util::File::Path->new(splice @parts, 0, -1);
}

=head2 $path->collapse()

Remove as many C<'..'> and C<'.'> references from C<$path> as possible.
The C<'.'> path is returned in cases where the path would otherwise collapse
to the empty path, e.g.

  collapse("foo/../bar/..") eq '.';   # TRUE

=cut

sub collapse {
  my $self = shift;
  my @oldparts = @{$self};
  my @newparts;

  while (@oldparts) {
    my $part = shift @oldparts;

    if ($part eq '..') {
      @newparts ? pop @newparts : push @newparts, $part;
    }
    elsif ($part ne '.') {
      push @newparts, $part;
    }
  }

  @{$self} = @newparts ? @newparts : qw(.);
  return $self;
}

=head2 $path->relative_to($basepath)

Compute and return a new relative path from C<$basepath> to C<$path>.
If the paths have no common ancestor, the empty path is returned.
If the paths are identical, the C<'.'> path is returned.

=cut

sub relative_to {
  my ($topath, $frompath) = @_;
  my $ancestor = longest_ancestor($frompath, $topath);
  return $ancestor if $ancestor->is_empty();

  my @back = (qw(..)) x (@{$frompath} - @{$ancestor});
  my @forward = splice @{$topath->clone()}, scalar @{$ancestor};
  my @rel = (@back, @forward);

  return Util::File::Path->new([@rel ? @rel : qw(.)]);
}

sub rebase {
  my ($child, $oldbase, $newbase) = map { _coerce($_) } @_;
  return Util::File::Path::add($newbase, $child->relative_to($oldbase));
}

=head2 $path1->longest_ancestor($path2)

Find the longest common ancestor path shared by two paths. Returns the
empty path if they have no common ancestor.

=cut

sub longest_ancestor {
  my ($path1, $path2) = map { __PACKAGE__->new($_) } @_;
  my $ancestor = __PACKAGE__->new();
  
  while ($path1 and $path2) {
    my ($d1, $d2) = (shift(@{$path1}), shift(@{$path2}));
    last if $d1 ne $d2;
    push @{$ancestor}, $d1;
  }

  return $ancestor;
}

=head2 $path->is_ancestor($path2)

Test if C<$path1> is an ancestor of C<$path2>.

=cut

sub is_ancestor {
  my ($path1, $path2) = @_;
  return $path1 eq longest_ancestor($path1, $path2);
}

sub is_strict_ancestor {
  my ($path1, $path2) = @_;
  return Util::File::Path::is_ancestor($path1, $path2) && $path1 ne $path2;
}

sub add {
  my @parts = map { @{$_} } @_;
  return Util::File::Path->new(\@parts);
}

sub basename { return @{$_[0]}[-1]; }

sub no_root {
  my $self = shift;
  @{$self} = grep length, @{$self};
  return $self;
}

sub no_up {
  my $self = shift;
  @{$self} = grep $_ ne '..', @{$self};
  return $self;
}

sub to_string { return _join(@{$_[0]->{_parts}}); }
sub to_arrayref { return shift->{_parts}; }
sub to_boolean { return not $_[0]->is_empty(); }
sub clone { return Util::File::Path->new(shift->{_parts}); }

sub is_root { my @parts = @{$_[0]}; return @parts == 1 and $parts[0] eq ''; }
sub is_absolute { return $_[0]->{_parts}->[0] eq ''; }
sub is_relative { return not is_absolute(@_); }
sub is_empty { return @{$_[0]} == 0; }

sub _from_object {
  # copy constructor
  return %{$_[0]} = %{ $_[1]->clone() };
}

sub _from_string {
  return $_[0]->{_parts} = [ _split(_canonical($_[1])) ];
}

sub _from_array {
  return $_[0]->{_parts} = [ @_[1..@_-1] ];
}

# private utility subs (these are not methods)
sub _join { return @_ > 0 ? join '/', @_ : undef; }
sub _split { return @_ == 0 ? () : ($_[0] eq '' ? '' : split m{/}, $_[0]); }
sub _canonical { my $path = shift; $path =~ s{/$}{}; return $path; }

1;

__END__

=head1 NOTES

=over 4

=item *

in string context, the path is always canonical (ala File::Spec)

=item *

in string context, '' is the canonical form of the root path
(not '/' as you're perhaps used to thinking of it)

=item *

in string context, undef is the canonical form of the empty path

=item *

@{$path} gives you direct access to the path's component list

=back

=cut

=head1 AUTHORS

Alan Grow <agrow@bloomberg.net>


