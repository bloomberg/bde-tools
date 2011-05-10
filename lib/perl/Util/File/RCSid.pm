package Util::File::RCSid;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw(unexpand_rcsid);

use Tie::File;

#==============================================================================

=head1 NAME

Util::File::RCSid - Manipulate RCSid in source code files.

=head1 SYNOPSIS

   use Util::File::RCSid qw(unexpand_rcsid);

   unexpand_rcsid($path);

=head1 DESCRIPTION

Use this module to unexpand an RCSid in a source file.  It determines the file
type and unexpands the ID string in situ.

=cut

#==============================================================================

# The force option should disappear in future.
sub unexpand_rcsid {
  my ($file,$force) = @_;
  $force = $force ? 1 : 0;

  my $tmpfile = "$file.tmp";
  my $lang;

  if ($force) {
    $lang = 'force';
  }
  elsif ($file =~ m/\.(?:c|h|cpp|cc|hpp|cxx)$/){
     $lang = "c";
  } elsif ($file =~ m/\.(?:gob)$/){
     $lang = "gob";
  } elsif ($file =~ m/\.(?:gobxml)$/){
     $lang = "gobxml";
  } elsif ($file =~ m/\.(?:f|inc|ins)$/){
     $lang = "f";
  } else {
     return ("unrecognized file type: $file (use --force option)",0);
  }

  my $found = 0;
  my $c_id_string = qr{Id|Header|Revision|What|Name|RCSfile|Date|Log|CCId};
  my $f_id_string = qr{Id|Header|CCId};

  my ($rfd,$wfd);
  if ($lang eq 'force') {
    # FIX: avoid slurp?
    local $/ = undef;

    open($rfd,"<$file")
      or  return ("cannot open $file: $!",0);
    my $text = <$rfd>;
    close($rfd)
      or  return ("cannot read $file: $!",0);

    $text =~ s/(\$(?:$c_id_string))(?:\s|:)[^\$]*(\$)/$1$2/sg
      and  $found = 1;

    open($wfd,">$tmpfile")
      or  return ("cannot open $tmpfile: $!",0);
    print $wfd "$text"
      or  return ("cannot write $tmpfile: $!",0);
    close($wfd)
      or  return ("cannot close $tmpfile: $!",0);

    rename($tmpfile,$file)
      or  return ("cannot rename $tmpfile to $file: $!",0);

    # Success!
    return (($found ? undef : "no expanded RCSid found in $file"),1);
   }

  # Non-force only from here on: the old stuff.
     
  open($rfd,"<$file")
    or  return ("cannot open $file: $!",0);
  open($wfd,">$tmpfile")
    or  return ("cannot open $tmpfile: $!",0);
  my $state = 0;
  while (<$rfd>) {
    chomp;
    if ($lang eq "c") {
	$found = 1 if s/\$((?:$c_id_string))\s*:.*\$/\$$1\$/i;
    } elsif ($lang eq "gob") {
	    $found = 1  if s/(^#version\s+(?:<?\@\(#\)\s*)?\$(?:$c_id_string))(?:\s|:)[^"]*(\$)$/$1$2/i
    } elsif ($lang eq "gobxml") {
	$found = 1 if s/\$((?:$c_id_string))\s*:.*\$/\$$1\$/i;
    } else {    ###($lang eq "f")
	  if (m/DATA\s+RCSid/i) {
	     $state = 1;
	  }
	  if (m/RCSid\s*=\s*/i) {
	     $state = 2;
	  }
	  if (($state == 1) and (s/(\+\'\$(?:$f_id_string))(?:\s|:).*\$$/$1\$/i)){
	     $found = 1;
	     $state = 0;
	  }
	  if (($state == 2) and (s/(\+\"\$(?:$f_id_string))(?:\s|:).*\$$/$1\$/i)){
	     $found = 1;
	     $state = 0;
	  }
    }
    print $wfd "$_$/"
      or  return ("cannot write $tmpfile: $!",0);
  }

  close($wfd)
    or  return ("cannot close $tmpfile: $!",0);

  rename($tmpfile,$file)
    or  return ("cannot rename $tmpfile to $file: $!",0);

  return (($found ? undef : "no expanded RCSid found in $file"),1);
}

1;

__END__
#==============================================================================

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=head1 SEE ALSO

L<Util::File::Basename>

=head1 TODO
Torture tests.
Continuation lines in Fortran.
Rewrite safely rather than using Tie::File.

=cut
