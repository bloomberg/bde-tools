# vim:set ts=8 sts=2 sw=2 noet:

package SCM::Util::Slurp;

use base qw(Exporter);
our $VERSION = '0.01';
our %EXPORT_TAGS = ( all => [ qw(slurp) ] );
our @EXPORT_OK= map @$_, values %EXPORT_TAGS;
our @EXPORT	= qw();   # nothing by default

use strict;

sub slurp {
  my ($from, $to) = @_;

  my $isfh = sub { 
      return UNIVERSAL::isa($_[0], 'IO::Handle') ||
             ref($to) eq 'GLOB';
  };
  
  local $/ = \16384;

  if (@_ == 1 and $from) {
    if ($isfh->($from)) {
      my $ret = '';
      while (<$from>) { $ret .= $_; }
      return $ret;
    }
  }
  elsif (@_ == 2 and $from and $to) {
    if ($isfh->($from) and ref($to) eq 'SCALAR') {
      while (<$from>) { $$to .= $_; }
      return 1;
    }
    elsif (not ref($from) and $isfh->($to)) {
      return print $to $from;
    }
    elsif ($isfh->($from) && $isfh->($to)) {
      while (<$from>) { print $to $_ or return undef; }
      return 1;
    }
  }

  return undef;
}

1;

