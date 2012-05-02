#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use lib "/bbcm/infrastructure/tools/lib/perl";
use Getopt::Long;
use Util::File::Basename qw(basename);
use File::Temp qw(tempdir tempfile);
use Change::File;
use Change::Util::InterfaceSCM qw(copyoutFilesByCsidSCM copyoutFilesByBranchSCM 
				  copyoutStagedFilesSCM);
use Change::Symbols qw(STAGE_PRODUCTION_ROOT STAGE_INTEGRATION SCANT_N TOOLS_SHAREDBIN);
use Change::Util::Interface qw/getCanonicalPath/;
use Util::Message qw(error debug fatal warning verbose);
use Symbols qw(
    EXIT_SUCCESS EXIT_FAILURE DEFAULT_FILESYSTEM_ROOT
);
 
#==============================================================================

=head1 NAME

bde_lookatcs.pl - View file under repository or stage area

=head1 SYNOPSIS
    

    View file in repository under move branch 
    $ lookat acc_f_parmcm8.f acclib
    $ lookat acc_f_parmcm8.f
    
    View file in repository by branch
    $ lookat --move bugf acc_f_parmcm8.c acclib
    $ lookat --move emov acc_f_parmcm8.c acclib 
    $ lookat --move move acc_f_parmcm8.c acclib 

    View file by a change set
    $ lookat bloom-chgsdisp1.gob --csid 44C4F9660C0B21E8F8
    
    View most recent file in stage area
    $ lookat bloom-chgsdisp1.gob f_xxmycs --stage

    View file in stage area under certain move type
    $ lookat bloom-chgsdisp1.gob f_xxmycs --move emov

    View swept version of file 
    $ lookat bloom-chgsdisp1.gob f_xxmycs --swpet

    View swept version of file under certain move type
    $ lookat bloom-chgsdisp1.gob f_xxmycs --move emov --swept

    View file by a given editor
    $ lookat --editor emacs acc_f_parmcm8.f

    Donot fallback to rcslookat
    $ lookat --norcslookat prqspriv.c .
    
=head1 DESCRIPTION

C<bde_lookatcs.pl> view a source file under repository or stage area.

=head2 View file from repository

User can specify which branch to view with. There are three branches:
C<move>, C<bugf>, C<emov>. All the regular checkin goes to C<move> branch.
Bug fix code goes to C<bugf> branch and emov goes to C<emov> branch.
The most recent version of the file under the specified branch will return
from repository. By default, the file under move branch will be returned. 

    $ lookat <file> <lib>
    $ lookat <file> <lib> --move <movetype>

=head2 View file by CSID

User can view an specific version of the file under repository or stage area
by specifying the change set id the version of the file associated with. 
Depending on the status of the changeset, files will be retrieved either 
from staged area or from repository. This implies an old version of file
can be viewed by C<csid> option. With <csid> option, there is no need to
specify library, move type and it should not used together with other
options as well.

Please note, when useing C<--csid>, a change set which is rollback or 
reinstate will not be acceptted.
    
    $ lookat --csid <csid> <file>

=head2 View file in stage area

File stays in stage area between checkin and robocop sweeps. With C<--stage>,
the file under stage area will be viewed. If no move type provided, the latest
version of the file from stage area for all move types will be retrieved.
If specify move type, only the file in stage area matched the move type will 
be viewed. 

    $ lookat --stage <file> <lib>
    $ lookat --stage <file> <lib> --move <movetype>

=head2 View swept file

User can also view most recent swept version of the file with C<--swept> option.
If combined with move type, the swept version of the file from the specified
move type will be viewed. Please note, the sept version of the file means the
change set which the file checkin with is in complete status.
    
    $ lookat --swept <file> <lib>
    $ lookat --swept <file> <lib> --move <movetype>

=head2 Fallback to rcslookat

By default, if the lib user viewed is not setup for cscheckin, cslookat will 
run rcslookat. With option C<--norcslookat>, it will not run rcslookat

    $ lookat prqspriv.c tools/prqs/prqspriv
    $ lookat prqspriv.c tools/prqs/prqspriv --norcslookat

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h |  [-d] [-v] <file name> [-c <chagneset id>] [-m <move type>] [-s <stage>] [-w <swept>] [-e <editor>] <library name>
  --debug        | -d             enable debug reporting
  --verbose      | -v             enable verbose
  --help         | -h             usage information (this text) 
  --stage        | -s	          view staged files  
  --swept        | -w             view swept version of files
  --csid         | -c <csid>      view file of a specified change set id
  --move         | -m <move type> view file under specified move branch
  --rcslookat    | -r             view the file use rcslookat
  --editor       | -e <editor>    open the file with provided editor
 

See 'perldoc $prog' for more information.

_USAGE_END
    
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
	help|h	  
        debug|d+
	verbose|v+
	stage|s	
	swept|w
	csid|c=s
	move|m=s
	rcslookat|r!	
	editor|e=s	
    ])) {
	usage();
	exit EXIT_FAILURE;
    }

    usage, exit EXIT_SUCCESS if $opts{help};
    #no arguments
    usage, exit EXIT_FAILURE if @ARGV<1;
      

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);
 
    if($opts{csid} and ($opts{stage} or $opts{move})) {
	warning "--stage and --move have no effect when specified with --csid";	
    } 
    
    $opts{rcslookat} = 1 unless defined $opts{rcslookat};
    $opts{rcslookat} = 0 if (defined $opts{stage} or defined $opts{swept} or
			     defined $opts{csid} or defined $opts{move});

    return \%opts;
}

sub findLib ($){
    my $file = shift;

    my $FH = Symbol::gensym;
    open($FH,'-|',SCANT_N,$file);
    my @libs = map { $_ =~ /Library: (\S+)/ ? $1 : () } <$FH>;
    print while <$FH>;
    close($FH);
       
    unless(@libs) {
	error "Can not find library for $file.";
	return undef;
    }
      
    if(scalar @libs > 1) {
	error "Scant repoprts more than one library for $file.";
	error "Please provide the library explicitly.";
	return undef;
    }
    
    debug("library is $libs[0]");

    return $libs[0];
}

sub deriveLroot ($$$){
    my ($lib, $file, $opts) = @_;
    require Change::Identity;

    my $target;
    $target = Change::Identity::deriveTargetfromName($lib, STAGE_INTEGRATION);
    unless ($target) {	
	if($opts->{rcslookat}) {
	    error "Invalid library: $lib. falling back to rcslookat";	
	} else {
	    error "Invalid library: $lib";
	    warning "Please make sure the spelling of the library is correct ";
	    warning "Please make sure the library has been set up for cscheckin.";
	}
	return undef;
    }
    debug("Target of $file, $lib is $target");

    my $cf;
    $cf = Change::File->new({
	target => $target,
	source => $file,
    });
    my $lroot = getCanonicalPath($cf);
  
    debug("lroot of $file is $lroot");

    return $lroot;
}

#------------------------------------------------------------------------------

MAIN: {
  my $opts=getoptions();
 
  my ($file, $lib) = @ARGV;

  
  unless ($file ) {
      usage;
      exit EXIT_FAILURE;
  }

  my ($status, $response);
  my ($lroot ,$filename);
  
  my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
  my $targetfile = "$tmpdir/$file.tar"; 
  system("touch $targetfile");
  debug("Temp dir created is $tmpdir");

  my $editor= $opts->{editor}? $opts->{editor}: $ENV{'EDITOR'};
  $editor ||='vi';

  if($opts->{csid}) {
       require Production::Services;
       require Production::Services::ChangeSet;

       my $svc=new Production::Services;
      
       my $changeset = Production::Services::ChangeSet::getChangeSetDbRecord(
				     $svc, $opts->{csid});
     
       unless ($changeset) {
	   error $opts->{csid}, " not found\n";
	   exit EXIT_FAILURE;
       }
           
       my $fobject;
       foreach my $cf ( $changeset->getFiles) {	
	   my $leafname = $cf->getLeafName;
	   if ( $leafname eq $file) {
	       $fobject = $cf;	      
	       last;
	   }
       }
     
       if (!$fobject) {
	   error "$file not found in $opts->{csid}.";
	   exit EXIT_FAILURE;
       }       
   
       $lroot = getCanonicalPath($fobject);
       $filename = "$tmpdir/root/$lroot";   
  
       debug("lroot is $lroot");
       debug("Move type is ", $changeset->getMoveType);

       if($changeset->getStatus ne 'S' &&
	  $changeset->getStatus ne 'A' &&
	  $changeset->getStatus ne 'N' &&
	  $changeset->getStatus ne 'P' &&
	  $changeset->getStatus ne 'C'
	  ){
	   error "Change set $opts->{csid} has state ",$changeset->getStatus;
           error "Cannot retrieve file for this change set.";
	   exit EXIT_FAILURE;
       }      
      
       verbose("Invoking copyoutFilesByCsidSCM request");

       ($status, $response)=copyoutFilesByCsidSCM($targetfile, $opts->{csid}, 
						  $changeset->getMoveType,
						  $lroot);
       if (!$status) {
	   error $response;
	   exit EXIT_FAILURE;
       }	 
  } else {
      unless($lib) {
	  $lib = findLib($file);	
	  goto EXIT_CHECK unless($lib);	 
      }

      $lroot = deriveLroot($lib, $file, $opts);     
      goto EXIT_CHECK unless $lroot;
      

      if($opts->{stage}){     
    
	  verbose("Invoking copyoutStagedFilesSCM request");
	  ($status, $response)=copyoutStagedFilesSCM($targetfile, $opts->{move}, $lroot);      
	  if (!$status) {
	      error $response;
	      goto EXIT_CHECK;
	  }
      } elsif($opts->{swept}){

	   verbose("Invoking copyoutFilesByBranchSCM request for swept");	   
	   my ($status, $response)=copyoutFilesByBranchSCM($targetfile, 
				$opts->{move}, "C",$lroot);
	   if (!$status) {
	       error $response;
	       goto EXIT_CHECK;
	   }
       } else {

	   verbose("Invoking copyoutFilesByBranchSCM request");
	   my ($status, $response)=copyoutFilesByBranchSCM($targetfile, 
				$opts->{move}, undef,$lroot);
	   if (!$status) {
	       error $response;
	       goto EXIT_CHECK;
	   }
       }
  }
 
  if (defined $targetfile) {    
      unless (system ( "cd $tmpdir && tar xmf $targetfile") == 0) {
          error "Failed to retrieve data from the tarball: $!";
          exit EXIT_FAILURE;
      }
      $filename = "$tmpdir/$file";
  }

  verbose("Invoking editor $editor on $filename");

  if (-e $filename) {      
      chmod 0444, $filename; 

      my $viewoption;
      my $io_done = $ENV{'IO_DONE'};

      if ($editor eq "emacs" && $ENV{'DISPLAY'}) {
	  system("unset $io_done") if defined $io_done;
      } elsif(($editor =~ "gvim"  or $editor eq "gview")
	      && $ENV{'DISPLAY'}) {
	  $viewoption = '-f';
	  system("unset $io_done") if defined $io_done;
      }
      
   
      if($viewoption) {
	  my $cmd = " $editor $viewoption $filename";
	  if (system("$editor $viewoption $filename")) {
	      error "Error invoking editor '$editor': $?";
	      exit EXIT_FAILURE;
	  }
      } else {	 
	  if (system("$editor $filename")) {
	      error "Error invoking editor '$editor': $?";
	      exit EXIT_FAILURE;
	  }
      } 
      exit EXIT_SUCCESS;
  } elsif(!$opts->{rcslookat})  {
      error "Failed to retrieve $file $!";
      warning "Please make sure the spelling of the file name is correct ";
      warning "and the file has been set up for cscheckin.";  
      exit EXIT_FAILURE;
  }

EXIT_CHECK:
  if($opts->{rcslookat}) {
      verbose("Running rcslookat instead");
      $ENV{'VIEWER'}=$editor;
      my $cmd = TOOLS_SHAREDBIN.'/'."rcslookat";
      system("$cmd @ARGV");
  }

  exit EXIT_SUCCESS;
}

#==============================================================================

=head1 AUTHOR

Ellen Chen (qchen1@bloomberg.net)



