#!/bbs/opt/bin/perl -w
use strict;

use Symbol ();
use File::Path ();

use base 'Exporter';
our @EXPORT_OK = qw[
    is_file_on_nfs
    make_visible_on_nfs
];


## NFS-visible location for temporary files
## GPS: this should probably be people's mbig dir
##<<<TODO: make a Symbol or put in config file
use constant NFS_TMPDIR_TOP => "/bb/csbuild";

{
  ##<<<TODO: replace this with Sys::Filesystem from CPAN

  ## NOTE: 'man mnttab' warns that parsing /etc/mnttab for dev= is not
  ## safe in 64-bit environments and that getextmntent() should be used.
  ## (Doing it this way works for now, at least on Solaris 9)
  my %solaris_device_map;
  sub _init_solaris_device_map () {
    my $FH = Symbol::gensym;
    open($FH,'<',"/etc/mnttab") || return;
    while (<$FH>) {
	$solaris_device_map{hex($2)} = $1
	  if /^\S+\s+\S+\s+(\S+)\s+\S*\bdev=([0-9A-Fa-f]+)/;
    }
    close $FH;
  }

  my %aix_mount_map;
  sub _init_aix_mount_map () {
    my $PH = Symbol::gensym;
    open($PH,'-|',"/usr/sbin/lsfs") || return;
    $_ = <$PH>;  # discard header line
    my($mount,$fstype);
    while (<$PH>) {
	(undef,undef,$mount,$fstype) = split ' ';
	$aix_mount_map{$mount} = $fstype if defined($mount) && defined($fstype);
    }
    close $PH;
  }

  ## returns 1 for true, 0 for false, undef for unknown (also false)
  sub is_file_on_nfs ($) {
    my $file = shift;
    stat($file) || return undef;
    my($device) = stat(_);
    return 1 if ($device < 0);  ## some systems use negative numbers for NFS
    if ($^O eq "solaris") {
	_init_solaris_device_map() unless %solaris_device_map;
	my $fstype = $solaris_device_map{$device};
	return defined $fstype ? $fstype eq "nfs" : undef;
    }
    elsif ($^O eq "aix") {
	## NOTE: expects $file to be an absolute path; use Cwd::abs_path() arg
	init_aix_mount_map() unless %aix_mount_map;
	my $fstype;
	my @segments = split '/',$file;
	while (@segments > 1) {
	    $fstype = $aix_mount_map{join('/',@segments)};
	    last if defined($fstype);
	    pop @segments;
	}
	$fstype = $aix_mount_map{'/'} unless defined($fstype);
	return defined $fstype
	  ? $fstype =~ /^(?:nfs|nfs3|nfsv3|nfs4|nfsv4)$/
	  : undef;
    }
    else {
	## unhandled; could parse 'mount' output, but would have to set up
	## such parsing on a per-platform basis since output is OS-specific
	return undef;
    }
  }
}


## (generates NFS tmpdir path, but does not create directory on filesystem)
sub get_nfstmpdir (;$) {
    my($nfstmpdir) = @_;
    $nfstmpdir = "$^T.$$.".substr(rand(),2) unless $nfstmpdir; # ok; not great
    unless (substr($nfstmpdir,0,1) eq '/') {
	-d NFS_TMPDIR_TOP
	  || (mkdir(NFS_TMPDIR_TOP) && chmod(02777,NFS_TMPDIR_TOP));
	$nfstmpdir = NFS_TMPDIR_TOP.'/'.$nfstmpdir;
    }
    return $nfstmpdir;
}


## parse given link line, copy files on local disk to NFS for network visibility
##
## Returns a list of the network-visible directory and a modified link line
## On error, first arg returned is undef, and the second arg is error message
##
## Note: caller should clean up files copied from local disk
##   e.g. File::Path::rmtree($nfstmpdir) if (-d $nfstmpdir);
## (FYI, caller might choose to copy .mk file to return $nfstmpdir location,
##  after checking is_file_on_nfs($mkfile))
##
sub make_visible_on_nfs ($;$) {
    my($link_line,$nfstmpdir) = @_;
    $nfstmpdir = get_nfstmpdir($nfstmpdir);

    ## Note that this routine does not handle -L rules that point to local disk
    ## (since we do not want to copy hundreds of large libs over the network)
## GPS: might want to check this and warn, especially if there are relative
##	paths or dots

    my $response = "";
    my $content = "";
    my $umask = umask(0002);
    {
	require Cwd;
	require File::Copy;
	my(@content,%paths,$path,$target,
	   $src_size,$src_atime,$src_mtime,$dst_size,$dst_mtime);
	foreach my $arg (split ' ', $$link_line) {
	    if (substr($arg,0,2) ne "-l" && $arg =~ /\.(?:o|a|so)$/) {
		unless (-f $arg) {
		    $response .= "error processing object file: $arg\n"
			      .  "  (file does not exist)\n";
		    next;
		}
		($src_size,$src_atime,$src_mtime) = (stat(_))[7,8,9];
		$arg = Cwd::abs_path($arg);
		unless (is_file_on_nfs($arg)) {
		    ## copy file to NFS-visible locn unless sure already on NFS
		    ## preserve entire path under $nfstmpdir
		    $target = $nfstmpdir.$arg;
		    ($dst_size,$dst_mtime)= -f $target ? (stat(_))[7,9] : (0,0);
		    $path = $nfstmpdir.substr($arg,0,rindex($arg,'/'));
		    $response .= "Unable to copy $arg to $target: $!\n"
		      unless (($src_size==$dst_size && $src_mtime==$dst_mtime)
			      || (($paths{$path}++ || -d $path
						   || File::Path::mkpath($path))
				  && File::Copy::copy($arg, $target)
				  && utime($src_atime, $src_mtime, $target)));
		    $arg = $target;
		}
	    }
	    push(@content,$arg);
	}
	$content = join(" ",@content);
    }
    umask($umask);
    if ($response ne "") {
	File::Path::rmtree($nfstmpdir) if (-d $nfstmpdir);
	$nfstmpdir = undef;
	$content = "Error copying files to NFS-visible location\n".$response;
    }

    return ($nfstmpdir,\$content);
}

1;
