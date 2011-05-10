package Change::Plugin::FileMap;
use strict;

use base 'Change::Plugin::Base';

use Util::File::Basename qw(dirname);
use Util::File::Functions qw(wild2re);
use Util::Message qw(fatal warning verbose debug debug2 message);

my $mapname="file.map";

sub import {
    my ($package,$newname)=@_;

    $mapname=$newname if $newname;

    if ($mapname =~ m{/}) {
      fatal "FATAL: mapfile name '$mapname' includes a directory path";
    }
}

#==============================================================================

=head1 NAME

Change::Plugin::FileMap - Use map files to derive target library names

=head1 SYNOPSIS

    $ cscheckin -LFileMap <files> ...

    $ cscheckin -LFilemap=filemap.list <files> ...

=head1 DESCRIPTION

This plugin inserts an additional step into the processing of a candidate
change set between the initial derivation of the file list and the
identification of the target library/path for each file. The additional step
is to look for a C<file.map> file in the same directory as each source file,
and if present, look up the file by its leafname to see if a destination is
given for it.

When mapping from one nested directory structure to another, a map file must be
present in each subdirectory containing files to be mapped; the filename to be
mapped is I<always> specified as a leafname, not a relative path.

Specifying a file in a file map I<does not> automatically imply that it is to
be checked in any time L<cscheckin> is run. It I<only> specifies what would
happen to the file if it is checked in. To actually check in files, the
user still needs to specify the files to be checked in, as usual. The file
map allows the files to exist all in a local directory even if they are
destined for different target locations.

Because the file map is not an input file for specifying which files are to be
checked in, it can use advanced wildcards to provide sophisticated mappings
for large numbers of files without requiring the specification many mappings
to do so.

=head2 Map File Syntax

The format of a map file is a series of space separared key-value pairs, one
per line, listing the leafname of the file to be mapped and the target to which
it should be sent (the target being the library plus any additional trailing
path necessary). Blank lines and comments are ignored, and leading and
trailing space is stripped:

   # example file.map
   asourcefile.f appscrn
   anotherfile.c derutil
   gtkfile.gob   gtkapp

To match more than one file, wildcards can be used. In the event that two
wildcard specifications can match the same file, the first one listed will be
used as the mapping:

   ts{mv,rc}*.c  apputil
   *.[cf]        derutil
   *.h           bbinc/Cinclude

Accepted wildcards are C<?>, C<*>, C<[class]> and C<{list,of,alternates}>. (See
L<Util::File::Functions/wild2re> for details.)

B<When using wildcard mappings, use of C<cscheckin -l> to confirm the
destination location of all files before committing a changeset is strongly
encouraged. Use C<cscheckin -l -v> to enable diagnostic messages from the
plugin indicating the mapping (or not) of each file in the change set.>

=head2 Changing the Map File Name

The default name of the map file, C<file.map>, may be overridden by specifying
a new name to the plugin on the commandline, as shown in the L<"SYNOPSIS">
above.  The name of the mapfile must I<not> contain a directory path.  Absolute
paths to mapping files are not supported.

=head2 Debugging and Verbose Output

File map processing can be viewed with one level of verbosity. Loading of
map files can be seen with one level of debug, and the maps found inside viewed
with two levels of debug.

=cut

#==============================================================================

{ my %map=(); my %maporder=();

  sub load_map ($) {
      my $mapfile=shift;

      my $mapdir=dirname($mapfile);
      $map{$mapdir}={};
      $maporder{$mapdir}=[];
      open MAP,$mapfile or fatal "Unable to open $mapfile: $!";
      while (<MAP>) {
	  next if /^\s*(#|$)/;
	  s/^\s+//; s/\s+$//;
	  my ($file,$target,$more)=split(/\s+/,$_);
	  fatal ("Parse error content '$more' found in $mapfile line $.")
	    if $more;
	  fatal ("Directory separator found in leafname $file, ".
		 "$mapfile line $.") if $file=~m|/|;
	  fatal ("No target for '$file', $mapfile line $.")
	    unless $target;
	  my $filematch=wild2re($file);
	  $map{$mapdir}{$filematch}=$target;
	  push @{$maporder{$mapdir}},$filematch;
	  debug2 "'$filematch' mapped to $target by $mapfile";

	  #<<<TODO: check legality of target
      }
      close MAP;

      debug scalar(keys %{$map{$mapdir}}).
		   " file mappings loaded from $mapfile";

      if (grep { index($_,"gtk/") != -1 } values %{$map{$mapdir}}) {
	warning("\n\n".
	  "Use of 'gtk/' prefix on library names is DEPRECATED\n".
	  "Please omit the 'gtk/' prefix (and do not create 'gtk/' subdirs).\n".
	  "Canonical robocop library names -do not- contain 'gtk/'\n\n");
	sleep 3;
      }
  }

  sub find_in_map ($$) {
      my ($leafname,$map)=@_;

      unless (exists $map{$map}) {
	  if (-f $map.'/'.$mapname) {
	      message("Using map file found at $map/$mapname");
	      load_map($map.'/'.$mapname);
	  } else {
	      message("No map file found at $map/$mapname");
	      $map{$map}="no map"; #scalar
	  }
      }

      return undef unless ref $map{$map}; # no  - scalar = no map here

      foreach my $filematch (@{$maporder{$map}}) {
	  return $map{$map}{$filematch}
	    if $leafname=~m~^$filematch$~; # yes - regexp match
      }

      return 0; # no - none of the above
  }
}

#------------------------------------------------------------------------------

{ my $using_to=0;

  sub plugin_initialize ($$) {
      my ($plugin,$opts)=@_;
      my $using_to=(exists $opts->{to}) ? 1 : 0;
      return 1;
  }

  sub plugin_pre_find_filter ($$) {
      my ($plugin,$changeset)=@_;

      if ($using_to) {
	  debug "Explicit library destination specified, $plugin disabled";
	  return 1;
      }

      foreach my $file ($changeset->getFiles) {
	  my $mapped=find_in_map($file->getLeafName,$file->getSourceDirectory);
	  if ($mapped) {
	      verbose $file->getLeafName()." mapped to $mapped";
	      $file->setTarget($mapped);
	  } else {
              verbose $file->getLeafName()." not mapped";
	  }
      }

      # note: identifyArguments is responsible for correcting uncanonical
      # targets, and determining library and production target/lib.

      return 1;
  }
}

#==============================================================================

1;

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>

=cut
