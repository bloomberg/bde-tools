package Binary::Analysis::Tools;

use strict;
use Carp;
use Production::Services;
use Production::Services::Move;
use Binary::Analysis::Files;
use Exporter;
use Change::Symbols qw(MOVE_EMERGENCY MOVE_REGULAR MOVE_BUGFIX MOVE_IMMEDIATE);
use vars qw(@ISA @EXPORT_OK);
@ISA=qw(Exporter);
@EXPORT_OK=qw(cs_to_objset load_objset);

=item cs_to_objset($cs, $fh)

Takes a changeset object and a filehandle, and serializes the info
extracted out of the object files for the changeset to the file

=cut

sub cs_to_objset {
  my ($cs, $fh, $branchid) = @_;

  $branchid ||= 0;
  my $csid = $cs->getID;
  my $move_subtype;

  # We're dumping a version number for ease of use
  my $movetype = $cs->getMoveType();
  my $user = $cs->getUser;
  my $status = $cs->getStatus;
  my $time = $cs->getCtime;
  my $stage = $cs->getStage;
  # If they haven't given us a branch, go figure out what we need
  if (!$branchid) {
    if ($movetype eq MOVE_EMERGENCY) {
      my $svc = Production::Services->new;
      my (@tasks, @libs);
      @tasks = $cs->getTasks;
      @tasks = ("ibig") unless @tasks;
      @libs = $cs->getTargets;
      @libs = ("acclib") unless @libs;
      if (!defined $stage) {
	print "switching to beta\n";
	$stage = "beta";
      }
      my $type = Production::Services::Move::getEmoveLinkType($svc, $stage,
							      @libs, @libs);
      if (defined $type && $type =~ /stage/i) {
	$branchid = -1;
      }
    }
  }

  $move_subtype = 3;
  if ($movetype eq MOVE_IMMEDIATE) {
    $move_subtype = 4;
  }
  if ($movetype eq MOVE_REGULAR) {
    $move_subtype = 3;
  }
  if ($movetype eq MOVE_BUGFIX) {
    $move_subtype = 2;
  }
  if ($movetype eq MOVE_EMERGENCY) {
    if ($stage eq 'beta') {
      $move_subtype = 2;
    } else {
      $move_subtype = 1;
    }
  }
  # This is evil and wrong. Breg switches shouldn't be tagged as move
  # changesets because they aren't, dammit!
  if ($user eq 'registry') {
    $movetype = MOVE_EMERGENCY;
    $move_subtype = 1;
  }


  my $arch; $arch = ($^O =~ /solaris/i ? 1 : 2);
  print $fh ">\tV:1.0\tchangeset symbol data\n";
  print $fh join("\t", ')', $csid, $user, $movetype, $status, $time, $stage, $branchid, $move_subtype), "\n";
  foreach my $file ($cs->getFiles()) {
    my $lib = $file->getLibrary();
    my $source = $file->getSource;
    my $target = $file->getTarget;
    my $dest = $file->getDestination;
    my $o_file = Binary::Analysis::Files::Object->new($file);
    my $size = (stat $file)[7];
    my $munch_file = $file;
    # Toss everything up to the last slash
    $munch_file =~ s/^.*\///;
    $munch_file =~ s/\.[^\.]*\.o/.o/;
    print $fh join("\t", '*', $lib, $source, $target, $dest, $munch_file, $arch, $size), "\n";
    my %defs;
    foreach my $symbol ($o_file->getSymbols()) {
      $defs{$symbol}++ if $symbol->getType ne 'U';
    }
    foreach my $symbol ($o_file->getSymbols()) {
      # It's local if its tagged local or if its an undef with a def
      # in the same object.
      my $local = $symbol->isLocal;
      $local = 1 if (($symbol->getType() eq 'U') && $defs{$symbol});
      print $fh join("\t", '+', $symbol, $symbol->getType, $symbol->getValue, $symbol->getSize, $symbol->isWeak, $symbol->isCommon, $symbol->getSection, $local, $symbol->isTemplate), "\n";
    }
  }
}

=item load_objset($fh)

Takes a filehandle and returns a ref to a hash with the requested
object set loaded in. 

=cut

sub load_objset {
  my ($fh) = @_;
  my $line;
  $line = <$fh>;
  my ($type, $version, $comment) = split(/\t/, $line);
  if ($version ne 'V:1.0') {
    die "Bad changeset symbol data version number $version";
  }

  $line = <$fh>;
  chomp $line;
  my ($csid, $user, $movetype, $status, $time, $stage, $branchid, $subtype);
  ($type, $csid, $user, $movetype, $status, $time, $stage, $branchid, $subtype) = split(/\t/, $line);
  if ($type ne ')') {
    die "Bad changeset info line $line";
  }

  if (!$subtype) {
    $subtype = 3;
    $subtype = 4 if $movetype eq MOVE_IMMEDIATE;
    $subtype = 3 if $movetype eq MOVE_REGULAR;
    $subtype = 2 if $movetype eq MOVE_BUGFIX;
    $subtype = 1 if $movetype eq MOVE_EMERGENCY;
    $subtype = 2 if ($movetype eq MOVE_EMERGENCY and $stage eq 'beta');
  }
  my (@objs, $current);
  while ($line = <$fh>) {
    chomp $line;

    # New file?
    if ($line =~ /^\*/) {
      my (undef, $lib, $source, $target, $dest, $munch, $arch, $size) =
	split(/\t/, $line);
      $current = [];
      $size ||= 0;
      push @objs, {lib => $lib,
		   source => $source,
		   target => $target,
		   dest => $munch,
		   arch => $arch,
		   size => $size,
		   symbols => $current};
      next;
    }

    # Symbol in the file
    if ($line =~ /^\+/) {
      my (undef, $symbol, $type, $value, $size, $weak, $common, $csect, $local, $template) =
	split(/\t/, $line);
      $local ||= 0;
      $template ||= 0;
      push @$current, {symbol => $symbol,
		       type => $type,
		       value => $value,
		       size => $size,
		       weak => $weak,
		       common => $common,
		       section => $csect,
		       local => $local,
		       template => $template,
		      };
      next;
    }

    die "Bad line!";
  }
  return {type => $type,
	  csid => $csid,
	  user => $user,
	  movetype => $movetype,
	  status => $status,
	  ctime => $time,
	  stage => $stage,
	  branch => $branchid,
          subtype => $subtype,
	  objects => \@objs
	 };
}

