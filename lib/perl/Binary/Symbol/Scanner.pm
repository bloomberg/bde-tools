package Binary::Symbol::Scanner;
use strict;
use Symbol ();
use Util::Message qw(fatal);

use base qw(BDE::Object);

use Symbols qw(ROOT DEFAULT_CACHE_PATH);
use constant CACHE_DIR => ROOT."/data/cache/binary";

use Compat::File::Spec ();
use Util::File::Basename qw(basename fileparse);
use File::Path qw(mkpath);
use BDE::Build::Invocation qw($FS); #<<<replace with Symbol later
use Util::File::Attribute qw(is_newer);

#==============================================================================

=head1 NAME

Binary::Symbol::Scanner - Symbols scanner class for binary objects and archives

=head1 SYNOPSIS

  my $scanner=new Binary::Symbol::Scanner();
  my $symbols=$scanner->scan("myobject.o");
  foreach (@$symbols) { ... }

=head1 DESCRIPTION

C<Binary::Symbol::Scanner> provides the basic scanning functionality to extract
symbol information from binary objects and archives. It provides an object
class with one public method, C<scan>, that generates a nested hash of
C<Binary::Symbol> objects sorted by binary object to which the symbol belongs.
(Debugging symbols, i.e. those with names that begin with '$', are skipped.)

=head1 NOTES

This module is a client of L<Base::Architecture> and comes with SunOS, AIX,
and HP-UX platforms built in. Further platforms may be added through external
modules - see L<Base::Architecture> for details.

=cut

#==============================================================================
# Architecture specific configuration
# (flags with same letter might mean different things on different platforms)

#<<<TODO: to support demangled C++ symbols, the format of _BAD_SYMBOLS in the
#*.opts file will need to change since the symbol might contain spaces.
#Also, the output of 'nm' on Sun has the mangled symbol on the following line,
#so we might want to trap that, too.

# SunOS
{ package Binary::Symbol::Scanner::SunOS;

  sub command { return "/usr/ccs/bin/nm"; }
  sub options { return qw[-A -g -l -t d]; }
}

# HP-UX
{ package Binary::Symbol::Scanner::HP;

  sub command { return "nm"; }
  sub options { return qw[-p -A -g -l -t d]; }
}

# AIX
{ package Binary::Symbol::Scanner::AIX;

  sub command { return "/usr/bin/nm"; }
  sub options { return qw[-P -A -g -l -t d -h -C -p]; }
}

# DG
#{ package Binary::Symbol::Scanner::DG;
#
#  sub command { return "nm"; }
#  sub options { return qw[-p -x -r]; } #as close as we can currently get
#  # the nm manual page disagrees with the nm command line!
#}

# Unsupported Platform
{ package Binary::Symbol::Scanner::Unknown;
  no warnings 'once';
  *command = *options = sub { die "Platform $^O not recognized\n"; }
}

use Base::Architecture qw(auto);

#==============================================================================

sub _is_object_file ($) { substr($_[0],rindex($_[0],'.')+1) eq "o" }

sub _create_writable_dir($$) {
    my($self,$cachedir) = @_;
    unless (-d $cachedir) {
	my $mask = umask(0002);
	die("Unable to create ".$cachedir) unless mkpath($cachedir);
	umask($mask);
	$self->throw("$cachedir does not exist") unless -d $cachedir;
    }
    $self->throw("$cachedir is not writable") unless -w _;
}

sub _cache_init($;$) {
    my($self,$cachedir) = @_;
    return if $self->{cachedir};

    $cachedir ||= CACHE_DIR;
    $cachedir = DEFAULT_CACHE_PATH.'/binary' unless (-w (ROOT));
    $self->_create_writable_dir($cachedir);
    $self->{cachedir} = $cachedir;
}

## (similar to -- but extended from -- SYMBOL_PARSE_REGEX in Parser.pm)
## XXX: NOTE: colons (':') are not supported in archive name!
my $SYMBOL_PARSE_REGEX;
if ($^O eq 'aix') {
  $SYMBOL_PARSE_REGEX = qr/^
    ([^:[]+)(?:\[([^\]]*)\])?   # archive, object name (optional, e.g. if .so)
    :\s*
    (\S.*?)     # name
    \s+
    (\w)(\*?) # type, weakness
    \s+
    (\S+)     # value
    (?:
       \s+
       (\S+)     # size
    )?
			   /x;
}
if ($^O eq 'solaris') {
  $SYMBOL_PARSE_REGEX = qr /^
    ([^:[]+)(?:\[([^\]]*)\])?   # archive, object name (optional, e.g. if .so)
    :\s*
    (\S.*?)     # name
    \s+
    (\w)(\*?) # type, weakness
    \s+
    (\S+)     # value
    (?:
       \s+
       (\S+)     # size
    )?
			    /x;
}


sub scan_init ($$;$$) {
    my($self,$file,$cachedir,$defined_only) = @_;

    my $PH = Symbol::gensym;
    my $cmd  = $self->command();
    my @args = $self->options();

    my ($toggleflag) = 0;
    my($basename,$dirname,$is_object_file);
    unless (($is_object_file = _is_object_file($file))) {
	($basename,$dirname) = fileparse($file);
	#<<<TODO: rel2abs() is not precisely realpath(), so we might get
	#duplicate entries in the cache.  Not a big deal since it will
	#regenerate the entry if the entry is out of date.
	#(Think symbolvalidate.pl -L .)
	#<<<TODO: not tested on Windows
	$dirname=Compat::File::Spec->rel2abs($dirname);
    }

    # (do not cache object files (*.o) or .a's/.so's in .../tmp.*/.... dirs)
    if ($is_object_file || $dirname =~ m|/tmp\..*/|) {
      open($PH,'-|',$cmd,@args,$file)
	|| $self->throw("'$cmd @args $file' failed: $!");
      my @symbols;
      if ($^O eq 'aix') {
	while (defined($_ = <$PH>)) {
	  my @matches;
	  if (scalar(@matches = $_ =~ $SYMBOL_PARSE_REGEX) &&
	      substr($3,0,1) ne '$') {
	    $matches[7] = ''; # No common syms on AIX right now
	    @matches = map {defined $_ ? $_ : ''} @matches;
	    # Remap the weird letters for AIX
	    if ($matches[3] eq 'W') {
	      $matches[3] = 'D';
	      $matches[4] = 1;
	    }
	    if ($matches[3] eq 'V') {
	      $matches[3] = 'T';
	      $matches[4] = 1;
	    }
	    if ($matches[3] eq 'w') {
	      $matches[3] = 'U';
	      $matches[4] = 1;
	    }
	    if ($matches[3] eq 'Z') {
	      $matches[3] = 'B';
	      $matches[4] = 1;
	    }
	    push @symbols, join('|', @matches). "\n"
	  }
	}
      } elsif ($^O eq 'solaris') {
	while (defined($_ = <$PH>)) {
	  chomp;
	  s/\s+//g;
	  my @bits;
	  my @pieces = split(/\|/, $_);
	  next unless @pieces == 8;
	  next if substr($pieces[7],0,1) eq '$';
	  next if substr($pieces[7],0,2) eq '.X';
	  $pieces[0] =~ /([^:[]+)(?:\[([^\]]*)\])?/;
	  $bits[0] = $1 || '';
	  $bits[1] = $2 || '';
	  $bits[2] = $pieces[7];
	  if ($pieces[3] eq 'OBJT') {
	    $bits[3] = 'D';
	  } elsif ($pieces[3] eq 'FUNC') {
	    $bits[3] = 'T';
	  };
	  if ($pieces[6] eq 'UNDEF') {
	    $bits[3] = 'U';
	  }
	  next unless $bits[3];
	  $bits[4] = $pieces[4] eq 'WEAK';
	  $bits[5] = $pieces[1];
	  $bits[6] = $pieces[2];
	  $bits[7] = $pieces[6] eq 'COMMON';
	  push @symbols, join("|", @bits)."\n";
	}
      }
      close $PH;
      return \@symbols;
    }
    else {
	$self->_cache_init($cachedir) unless $self->{cachedir};
	$self->_create_writable_dir($self->{cachedir}.$dirname);
	## XXX: $^O should preferably be $uplid
	my $dcachepath =
	  $self->{cachedir}.$dirname.$FS.$basename.".$^O.dcache2.gz";
	my $cachepath  =
	  $self->{cachedir}.$dirname.$FS.$basename.".$^O.cache2.gz";
	#(second file is checked for is_newer since it is only updated
	# if updating first one succeeds)
	my $is_newer = is_newer($cachepath,$file);
	unless (!$is_newer && $is_newer == 0) {
	    my $mask = umask(0002);
	    substr($basename,-1,1,"realarchive.a")  ## Bloomberg-ism
	      if ($^O eq "aix" && -f substr($file,0,-1)."realarchive.a");
	      ## Bloomberg-ism for non-prelinked archive on AIX
	    # cache output from nm, but only lines we are interested in
	    ## XXX: This code is safe for shared usage, and can safely be
	    ##      periodically cleaned out without ill effects.
	    ## XXX: cache should be located on /bbs because symbol data from
	    ##      libraries is platform-specific (especially if library came
	    ##      from /bbs/lib)
	    ## XXX: cachepathtemp could be generated with better uniqueness
	    my $cachepathtemp = join '_', $cachepath, $$, time();
	    my $dcachepathtemp = join '_', $dcachepath, $$, time();
	    my $cache_cmd = "cd $dirname && $cmd @args $basename";
	    my($NM,$DZ,$GZ) = (Symbol::gensym, Symbol::gensym, Symbol::gensym);
	    open($NM, $cache_cmd.'|')
	      || $self->throw("$cache_cmd failed: $!");
	    open($DZ, "| gzip -c - >$dcachepathtemp")
	      || $self->throw("open of $dcachepathtemp failed: $!");
	    open($GZ, "| gzip -c - >$cachepathtemp")
	      || $self->throw("open of $cachepathtemp failed: $!");
	    if ($^O eq 'aix') {
	      while (defined($_ = <$NM>)) {
		my @matches;
		if (scalar(@matches = $_ =~ $SYMBOL_PARSE_REGEX) &&
		    substr($3,0,1) ne '$') {
		  $matches[7] = ''; # No common syms on AIX righ tnow
		  @matches = map {defined $_ ? $_ : ''} @matches;
		  print $DZ join('|', @matches), "\n"
		    if ($matches[3] ne 'U');
		  print $GZ join('|', @matches), "\n";
		  }
	      }
	    } elsif ($^O eq 'solaris') {
	      while (defined($_ = <$NM>)) {
		chomp;
		s/\s+//g;
		my @bits;
		my @pieces = split(/\|/, $_);
		next unless @pieces == 8;
		next if substr($pieces[7],0,1) eq '$';
		next if substr($pieces[7],0,2) eq '.X';
		$pieces[0] =~ /([^:[]+)(?:\[([^\]]*)\])?/;
		$bits[0] = $1 || '';
		$bits[1] = $2 || '';
		$bits[2] = $pieces[7];
		if ($pieces[3] eq 'OBJT') {
		  $bits[3] = 'D';
		} elsif ($pieces[3] eq 'FUNC') {
		  $bits[3] = 'T';
		} elsif ($pieces[3] eq 'NOTY') {
		  $bits[3] = 'N';
		}
		if ($pieces[6] eq 'UNDEF') {
		  $bits[3] = 'U';
		}
		$bits[4] = $pieces[4] eq 'WEAK';
		$bits[5] = $pieces[1];
		$bits[6] = $pieces[2];
		$bits[7] = $pieces[6] eq 'COMMON';

		print $DZ join("|", @bits), "\n" if ($bits[3] ne 'U');
		print $GZ join("|", @bits), "\n";
	      }
	    }

	    close $NM;
	    close $DZ;
	    close $GZ;
	    # XXX: should use times() to set the time on the cache files
	    #      Otherwise, there is a chance cache could get out of date
	    #      if a new file is created while creating cache entry for
	    #      old file, and it takes a few more seconds to finish
	    #      writing out the cache.  Should open the target library
	    #      at the beginning of this routine to obtain the times()
	    foreach ([$dcachepathtemp,$dcachepath],[$cachepathtemp,$cachepath]){
		next if rename($_->[0], $_->[1]);
		# AIX sometimes has trouble with this rename(), reporting:
		# "A file, file system or message queue is no longer available."
		# when it attempts to unlink the tmpfile.  Check if file still
		# exists, and if so, try to unlink the target and then rename.
		my $err = "$!";
		(stat($_->[0]) && (unlink($_->[1]), rename($_->[0], $_->[1])))
		  || $self->throw("rename @$_ failed: $err");
	    }
	    umask($mask);
	}

	if ($defined_only) {
	    open($PH, "gunzip -c $dcachepath |")
	      || $self->throw("Unable to open $dcachepath: $!");
	}
	else {
	    open($PH, "gunzip -c $cachepath |")
	      || $self->throw("Unable to open $cachepath: $!");
	}
    }

    return $PH;
}

# (Can save 300+MB when loading known big lib universe (symbol oracle) if a
#  string cache is used, a reference for 'archive' and 'object' name saved, and
#  Symbol.pm modified to dereference it where appropriate.  Can save an
#  additional 100+MB if this is also done for 'name')
{
    my %strcache = ("" => "", unknown => "unknown");
    keys(%strcache) = 662144;  # preallocate hash buckets (for symbol oracle)

    sub strcache ($) {
	$strcache{$_[0]} = $_[0] unless (exists $strcache{$_[0]});
	return \$strcache{$_[0]};
    }
}

## scan and parse Symbol in one shot to reduce string slinging
sub scan_next_symbol ($$;$) {
    my($self,$PH,$objects) = @_;

    if (ref($PH) eq 'ARRAY') {
      while (defined($_ = shift @$PH)) {
        chomp;
	# parse line and skip debugging symbols (name begins with '$')
        my (@parts) = split(/\|/, $_);
	next if (!$objects && $parts[3] eq 'U'); # caller wants defined symbols only

	my($archive,$obj_name, $size);
	if (!_is_object_file($parts[0])) {
	  $archive  = \$parts[0];
	  $obj_name = $parts[1] ? \$parts[1] : \("unknown");
        } else {
	  $archive  = \("");
          $obj_name = \(substr($parts[0],rindex($parts[0],$FS)+1)); # basename w/o regex
        }
        $size = $parts[6] || "";
        my $type = $parts[3];
        # The symbol oracle blows chunks on these when its memory
        # footprint gets too big, so we only put in the things we
        # actually need.
        my $symbol = new Binary::Symbol({archive  => strcache($$archive),
					 object   => strcache($$obj_name),
					 name     => strcache($parts[2]),
					 type     => strcache($parts[3]),
					});
	# Is it weak? Note it if so
	if ($parts[4]) {
	  $symbol->setWeak(1);
	}
	# Is there a size? We return a 0 size by default, and we don't
	# bother recording for undefs
	#
	# This uses a magic flag, which is icky
	if ($size && $type ne 'U') {
	  $symbol->setSize($size+0);
	}
	if ($parts[5] && $parts[5] ne '-') {
	  $symbol->setValue($parts[5] + 0);
	}
        if ($parts[7]) {
	  $symbol->setCommon(1);
	}

	if ($objects) {
	  if (!exists $objects->{$$obj_name}{${$symbol->{name}}} ||
	     ($type ne 'U')) {
	    $objects->{$$obj_name}{${$symbol->{name}}} = $symbol;
	  }
	}
	return $symbol;

      }
    } else {
      while (defined($_ = <$PH>)) {
        chomp;
	# parse line and skip debugging symbols (name begins with '$')
        my (@parts) = split(/\|/, $_);
	next if (!$objects && $parts[3] eq 'U'); # caller wants defined symbols only

	my($archive,$obj_name, $size);
	if (!_is_object_file($parts[0])) {
	    $archive  = \$parts[0];
	    $obj_name = $parts[1] ? \$parts[1] : \("unknown");
	}
	else {
	    $archive  = \("");
	    $obj_name = \(substr($parts[0],rindex($parts[0],$FS)+1)); # basename w/o regex
	}
        $size = $parts[6] || "";
	my $type = $parts[3];
	# The symbol oracle blows chunks on these when its memory
	# footprint gets too big, so we only put in the things we
	# actually need.
	my $symbol = new Binary::Symbol({archive  => strcache($$archive),
					 object   => strcache($$obj_name),
					 name     => strcache($parts[2]),
					 type     => strcache($parts[3]),
					});
			#	    value    => strcache($6),
			#           size     => strcache($size)
	# Is it weak? Note it if so
	if ($parts[4]) {
	  $symbol->setWeak(1);
	}
	# Is there a size? We return a 0 size by default, and we don't
	# bother recording for undefs
	#
	# This uses a magic flag, which is icky
	if ($size && $type ne 'U') {
	  $symbol->setSize($size+0);
	}
	if ($parts[5] && $parts[5] ne '-') {
	  $symbol->setValue($parts[5] + 0);
	}
        if ($parts[7]) {
	  $symbol->setCommon(1);
	}

	if ($objects) {
	  if (!exists $objects->{$$obj_name}{${$symbol->{name}}} ||
	     ($type ne 'U')) {
	    $objects->{$$obj_name}{${$symbol->{name}}} = $symbol;
	  }
	}
	return $symbol;
      }
    }

    return undef;
}

sub scan ($$) {
    my($self,$file)=@_;
    my($objects,$rv);

    fatal "$file does not exist" unless -e $file;
    fatal "$file is not a file"  unless -f _;
    return unless -s _;

    my $retry = 0;
    do {
	$objects = {};
	my $PH = $self->scan_init($file);
	do {} while (defined($self->scan_next_symbol($PH,$objects)));
	close $PH unless ref($PH) eq 'ARRAY';
	$rv = $?;
	warn "retrying Binary::Symbol::Scanner::scan $file ($?)\n" if $rv;
    } while ($rv != 0 && $retry++ < 10);

    return $objects;
}

sub scan_for_defined ($$$) {
    my($self,$file,$defined)=@_;
    my($symbol,$rv);

    fatal "$file does not exist" unless -e $file;
    fatal "$file is not a file"  unless -f _;
    return unless -s _;

    my $retry = 0;
    do {
	my $PH = $self->scan_init($file,undef,$defined);
	while (defined($symbol = $self->scan_next_symbol($PH,undef))) {
	    $defined->{$symbol->toString()} = $symbol;
	}
	close $PH unless ref($PH) eq 'ARRAY';
	$rv = $?;
	warn "retrying Binary::Symbol::Scanner::scan_for_defined $file ($?)\n"
	  if $rv;
    } while ($rv != 0 && $retry++ < 10);
}

#------------------------------------------------------------------------------

sub test ($) {
    my $scanner=new Binary::Symbol::Scanner();
    print "Scanner: $scanner\n";
    print "=== Scanning $_[0]\n";
    print join "\n",$scanner->scan($_[0]);
    print "\n=== Done\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)
Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<Binary::Symbol>, L<Binary::Symbol::Parser>

=cut

1;
