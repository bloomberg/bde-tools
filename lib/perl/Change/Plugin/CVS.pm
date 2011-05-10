package Change::Plugin::CVS;
use strict;

use base 'Change::Plugin::Base';

use Util::Message qw(fatal message debug);
use File::Temp qw(tempdir);
use Cwd;
use Change::Symbols qw(CSCOMPILE_TMP USER HOME);
use File::Path qw/ rmtree /;
use Util::File::RCSid qw(unexpand_rcsid);

#==============================================================================

=head1 NAME

Change::Plugin::CVS - CVS plugin module for cscheckin

=head1 SYNOPSIS

    $ cscheckin --plugin CVS --cvsroot /dir --cvsmod module --cvstag tag --filelist file --[no]idexpand ...

=head1 DESCRIPTION

This is a plugin module for L<cscheckin>. It inherits from
L<Change::Plugin::Base> and supports pulling changed files from a CVS
repository in order to hand them to cscheckin.  The plugin performs the
following steps:

  1. Check out a CVS revision (head or tag) from the specified CVS root and module.
  2. Determine the list of files to check in from command-line arguments and a
     list extracted from a file via --filelist.
  2. Ensure that the RCSid tag is or is not expanded per the --[no]idexpand
     option.  By default, do not expand IDs.  This is what you want.
  3. Continue with cscheckin processing as usual.

Files named on the command line are relative to the top-level CVS directory.
Files named via --filelist are relative to the directory specified by --cvsmod.
If multiple --cvsmod arguments appear, the combined set of modules is checked
out, and --filelist processing is performed for each module in turn.

=cut

#==============================================================================

sub _plugin_message { message __PACKAGE__." -> @_" };

#------------------------------------------------------------------------------

sub plugin_usage ($) {
    return join("\n" =>
	"  --cvsmod       <string>   the CVS module to check out (required)",
	"  --cvsroot      </dir>     the CVS repository root directory (\${CVSROOT} if absent)",
	"  --cvstag       <string>   the CVS tag for CVS checkout and cscheckin --message",
	"  --filelist     <file>     a file containing the list of source files to check in",
	"  --[no]idexpand	     (do not) expand CVS/RCS Ids when checking out (do not by default)"
    );
}

sub plugin_options ($) {
    return qw[cvstag=s cvsroot=s cvsmod=s@ filelist=s idexpand!];
}

{ my ($tempdir,$prefix);
  sub plugin_initialize ($$) {
      my ($plugin,$opts)=@_;

      my $seg = qr([a-zA-Z]\w*);# FIXME: policy

      (exists $opts->{cvsmod})  or  fatal("--cvsmod argument required");
      my %cvsmod;
      for (map(split(/,/ => $_) => @{$opts->{cvsmod}})) {
	$_ =~ m{^((?:$seg/)*$seg)/?$}
	  or  fatal("Illegal --cvsmod argument: $_");
	$cvsmod{$_} = undef;
      }
      $opts->{cvsmod} = [ keys %cvsmod ];

      $opts->{cvsroot} ||= $ENV{CVSROOT};
      if ($opts->{cvsroot}) {
	$opts->{cvsroot} =~ m{^((?:/$seg)+)/?$}
	  or  fatal("Illegal --cvsroot argument: $opts->{cvsroot}");
	$opts->{cvsroot} = $1;
      }
      else {
	fatal("\$CVSROOT not set; use --cvsroot argument");
      }

      if (exists $opts->{filelist}) {
	  $opts->{filelist} =~ m{^((?:$seg/)*$seg)$}
	    or  fatal("Illegal --filelist argument");
	  $opts->{filelist} = $1;
      }

      exists($opts->{idexpand})  or  $opts->{idexpand} = 0;

      # FIX: should check out specific files rather than whole module.
      my @cmd = (
	  qw(cvs -d),
	  (exists($opts->{cvsroot}) ? $opts->{cvsroot} : $ENV{CVSROOT}),
	  'co',
	  ($opts->{idexpand} ? () : '-kk'),
	  (exists($opts->{cvstag}) ? ('-r',$opts->{cvstag}) : '-A'),
	  @{$opts->{cvsmod}},
      );

      debug("CVS co command is: ",join(' '=>@cmd));

      # Takes template as distinguished leading arg, not hash entry.
      my $mask = umask(0002);
      $tempdir = tempdir("cscheckin.cvs.".USER.".XXXXXX",
			    DIR      => CSCOMPILE_TMP."/csplugin/CVS",
			    # using CLEANUP deletes prematurely
			    #CLEANUP  => Util::Message::get_debug ? 0 : 1,
		    ); 
      chmod(02775,$tempdir);# ignore error
      umask($mask);

      my $rundir = getcwd()  or  fatal("Cannot getcwd(): $!");
      chdir($tempdir)  or  fatal("Cannot chdir($tempdir): $!");
      debug("CVS directory is: ",`pwd`);
      eval { system(@cmd)  and  fatal("Cannot cvs co: $!"); };
      $@  and  do {
	# get out of temporary dir so that we can remove it
	chdir($rundir);# no point in testing result
	fatal("Aborting");
      };
      chdir($rundir)  or  fatal("Cannot chdir($rundir): $!");

      for (@{$opts->{files}}) {
	s!^([^/]+)!$tempdir/$1!;
      }
      if (exists $opts->{filelist}) {
	my %files = ();
	for (@{$opts->{cvsmod}}) {
	  $prefix = "$tempdir/$_";
	  my $filelist = $opts->{filelist};
	  $filelist =~ s!^([^/]+)!$prefix/$1!;
	  if (my $fh=new IO::File($filelist)) {
	    -f $fh  or  fatal("$filelist is not a regular file (directory?)");
	    local $/=undef;
	    my $definition=<$fh>;
	    close $fh  or  fatal("Cannot read $filelist: $!");

	    for (grep(!/^\s*(#|$)/ => split(/\n/ => $definition))) {
	      # paranoia
	      s/^\s*//; s/\s*$//;
	      m/\s+/  and  fatal "malformed CVS filelist line: '$_'";
	      $files{"$prefix/$_"} = undef;
	    }
	  }
	}
	$opts->{files} = [ keys %files ];
      }

      if (!$opts->{idexpand}) {
	  foreach my $file (@{$opts->{files}}) {
	    debug "looking for $file";
	    (-e $file)  or  next;
	    (-w $file)  or  next;

	    my ($msg,$r) = unexpand_rcsid($file,1);
	    if (!$r) {# failure
	      $msg  and  message($msg);
	    }
	 }
      }

      return 1;
  }

  sub plugin_finalize ($$$) {
      my ($plugin,$opts,$exit_code)=@_;
      defined($tempdir)  or  return 1;
      Util::Message::get_debug  and  return 1;
      # rm -rf complains to STDERR about files existing when they do not.
      system("rm -rf $tempdir 2>/dev/null");# no point in checking errors
      return 1;
  }
}

#==============================================================================

1;

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Plugin::Example>, L<cscheckin>

=cut
