package Change::Util::InterfaceSCM;
use strict;

use base 'Exporter';

use vars qw(@EXPORT_OK);
@EXPORT_OK=qw[
    postChangeSetSCM
    postBundleSCM
    postStructuralChangeSetSCM
    enqueueChangeSetSCM
    sweepSCM
    sweepChangesSCM
    sweepChangesFastSCM
    sweep
    sweepFast
    sweepFastSelective
    recoverFilesSCM
    createRollbackSCM
    copyoutFilesByCsidSCM
    copyoutLatestFilesSCM
    recoverCurrentSCM
    recoverPriorSCM
    recoverListSCM
    csidIsStagedSCM
    doSweepCalculationSCM
    getSweepFilelistSCM
    filesStagedSCM
    recordBranchPromotionSCM
    pathExistsSCM
    blameSCM
];


use HTTP::Request;
use LWP::UserAgent;
use Production::Services;
use Production::Services::ChangeSet qw/getChangeSetDbRecord/;
use Production::Services::LWPHack;
use Sys::Hostname;
use File::Temp qw(tempdir tempfile);
use File::Path;
use Cwd;
use FileHandle;     # need this for autoflush() on the tmp-fh
use URI::Escape;

use Production::Symbols qw($SCM_HOST_SCM $SCM_REQ_POST_CS $SCM_REQ_ENQUEUE_CS
			   $SCM_REQ_SWEEP_INC $SCM_REQ_SWEEP $SCM_REQ_SWEEP_FAST
                           $SCM_REQ_RECOVER_FILES 
                           $SCM_REQ_CREATE_ROLLBACK
			   $SCM_REQ_COPY_OUT_FILES_BY_CSID
			   $SCM_REQ_COPY_OUT_LATEST_FILES
                           $SCM_REQ_RECOVER_CURRENT
                           $SCM_REQ_RECOVER_PRIOR
                           $SCM_REQ_RECOVER_LIST
                           $SCM_REQ_CSID_IS_STAGED
                           $SCM_REQ_DO_SWEEP_CALCULATION
                           $SCM_REQ_GET_SWEEP_FILELIST
                           $SCM_REQ_FILES_STAGED
                           $SCM_REQ_RECORD_BRANCH_PROMOTION
                           $SCM_REQ_PATH_EXISTS
                           $SCM_REQ_BLAME);

use Change::Symbols	qw(CSCOMPILE_TMP STAGE_INTEGRATION
			   MOVE_REGULAR 
		           CHECKIN_ROOT USER GROUP SCM_BUNDLE_DIR
                           STATUS_INPROGRESS);
use Symbols             qw(DEFAULT_FILESYSTEM_ROOT);

use Change::Util::Bundle    qw(bundleChangeSet unbundleChangeSet);
use BDE::Build::Invocation  qw($FS);
use Util::Message	    qw(warning fatal error message alert 
			       debug debug2 debug3 get_debug);
use Change::Util::Canonical qw/bare_canonical_path branch_less/;
use Change::Identity        qw(getLocationOfStage);
use Change::Set;
use Production::Services::Util  qw/getUUIDFromUnixName/;

#==============================================================================

=head1 NAME

Change::Util::InterfaceSCM - Utility functions to access SCM services

=head1 SYNOPSIS

    use Change::Util::InterfaceSCM qw(enqueueChangeSetSCM);

=head1 DESCRIPTION

This module provides utility functions that provide services that implement
SCM queries of various kinds.

=cut

#==============================================================================

=head2 enqueueChangeSetSCM($changeset)

Bundle a changeset (including content) and convey it to the SCM server.

=cut

{ my $service_url = $SCM_HOST_SCM;
  my $local_t = CSCOMPILE_TMP."/sweep";

  sub _agent () {
    # FIX: credentials
    ## Setup the HTTP::DAV client
    my $useragent = LWP::UserAgent->new();
    $useragent->agent('InterfaceSCM ');
    $useragent->timeout(3600);
    {
        no warnings 'once';
        $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
    }
    # FIX: debug
    return $useragent;
  }

    sub _log_header {# Must match log output from unpack_from_bundle
	print join("\t" => qw(CSID FILE CANONICAL_PATH USER GROUP
			      TICKET STAGE MOVETYPE SRC_LIB FILE_TYPE)),"\n";
    }

    sub unpack_from_bundle {
        my ($bundle, $destdir, @files) = @_;

        my $cs = $bundle->cs;

	my $user  = $cs->getUser();
	my $ticket= $cs->getTicket();
	my $stage = $cs->getStage();
	my $move  = $cs->getMoveType();
	my $msg   = $cs->getMessage();
	my $csid  = $cs->getID();
	my $group = $cs->getGroup() || GROUP;

	my $root = Change::Identity::getStageRoot($stage);
        
        require BDE::Util::DependencyCache;
	BDE::Util::DependencyCache::setFileSystemRoot($root);

        my %include;
        @include{@files} = ();

        require Change::Util::Interface;

	foreach my $file ($cs->getFiles) {
	    my $bl = branch_less($file);
            next if @files and not exists $include{$bl};
            
            $bundle->extract($file => $destdir);

            my $leaf = $file->getLeafName;
            my $type = $file->getType;

            my ($atime, $mtime) = (stat "$destdir/$leaf")[8, 9];

            # create reason file
            Change::Util::Interface::installReason("$destdir/$leaf", $type, $user, $msg, $ticket, 
                                                   $stage, $move, $csid, 
                                                   "$destdir/$leaf.checkin.reason"); 
            utime($atime, $mtime, "$destdir/$leaf.checkin.reason");

            # create checkin script
            my $fclone = $file->clone;
            $fclone->setDestination("/bbsrc/checkin/$leaf");
            Change::Util::Interface::installScript($fclone, $user, $group, $ticket, $stage, $move, 
                                                   $csid, "$destdir/$leaf.checkin.sh");

            my $target = $file->getProductionTarget;
            s!^/+!!, s!/+$!! for $target;

            print join "\t" => $csid, "$destdir/$leaf", $file->getDestination,
                               $user, $group, $ticket, $stage, $move, $target, $type;
            print "\n";

	}
    }

    # If $status_to_p is true, then SCM will update status to P for
    # change sets that will contribute to the sweep.
    sub sweepFast {
        my ($movetype, $destdir, $recalculate, $status_to_p) = @_;

        my $rundir = getcwd();
        $destdir = File::Spec->rel2abs($destdir);

        my $tmpdir = tempdir('sweep'.USER.'XXXXXX', DIR => $local_t, CLEANUP => 1);
        chmod 02775, $tmpdir;
        
        for (qw(data sweep sweep/data)) {
            mkdir "$tmpdir/$_" or fatal "Cannot mkdir $tmpdir/$_: $!";
        }

        fatal "Cannot fetch sweep data: $!"
            if not sweepChangesFastSCM($movetype, "$tmpdir/sweep/tarball",
					$recalculate,$status_to_p);
        
	fatal "cannot unpack sweep data"
	    if system("cd $tmpdir/sweep/data && " . 
                      "tar xf $tmpdir/sweep/tarball") != 0;

        open my $fh, '<', "$tmpdir/sweep/data/FILELIST.$movetype"
            or fatal "No FILELIST.$movetype found: $!";
        
        my (%files, %eclipsed);
        while (<$fh>) {
            no warnings 'syntax';
            my ($csid, $file) = split;
            $eclipsed{$csid} = 1 and next if not $file;
            push @{ $files{$csid} }, $file;
        }

        chdir("$tmpdir/data")
            or fatal "Could not change directory to $tmpdir/sweep/data: $!";

	_log_header();
        # print out eclipsed CSIDs first
        print "$_\n" for keys %eclipsed;

        while (my ($csid, $files) = each %files) {
            next if not @$files;
            my $bundle = Change::Util::Bundle->new(bundle => "$tmpdir/sweep/data/$csid");
            unpack_from_bundle($bundle, $destdir, @$files);
        }
        chdir($rundir);
    }

        sub sweepFastSelective {
            my ($destdir, $csid, $status_to_p) = @_;

            my $rundir = getcwd();
            $destdir = File::Spec->rel2abs($destdir);

            my $tmpdir = tempdir('sweep'.USER.'XXXXXX', DIR => $local_t, CLEANUP => 1);
            chmod 02775, $tmpdir;
            
            for (qw(data sweep sweep/data)) {
                mkdir "$tmpdir/$_" or fatal "Cannot mkdir $tmpdir/$_: $!";
            }

            my $movetype = do {
                my $svc = Production::Services->new;
                my $cs = getChangeSetDbRecord($svc, $csid);
                $cs->getMoveType;
            } || fatal "Could not determine movetype for $csid";

            fatal "Cannot fetch sweep data: $!"
                if not sweepChangesFastSCM($movetype, "$tmpdir/sweep/tarball",undef,$status_to_p);
            
            fatal "cannot unpack sweep data"
                if system("cd $tmpdir/sweep/data && " . 
                          "tar xf $tmpdir/sweep/tarball") != 0;

            open my $fh, '<', "$tmpdir/sweep/data/FILELIST.$movetype"
                or fatal "No FILELIST.$movetype found: $!";
            
            my %files;
            while (<$fh>) {
                my ($csid, $file) = split;
                push @{ $files{$csid} }, $file;
            }

            chdir("$tmpdir/data")
                or fatal "Could not change directory to $tmpdir/data: $!";

	    _log_header();

            while (my ($id, $files) = each %files) {
                next if $id ne $csid;
                next if not @$files;
                my $bundle = Change::Util::Bundle->new(bundle => "$tmpdir/sweep/data/$csid");
                unpack_from_bundle($bundle, $destdir, @$files);
            }

            chdir($rundir);
        }

    sub sweep {
        my ($movetype, $destdir) = @_;

        my $rundir = getcwd();
        $destdir = File::Spec->rel2abs($destdir);

        my $tmpdir = tempdir('sweep'.USER.'XXXXXX', DIR => $local_t, CLEANUP => 1);
        chmod 02775, $tmpdir;
        
        for (qw(data sweep sweep/data)) {
            mkdir "$tmpdir/$_" or fatal "Cannot mkdir $tmpdir/$_: $!";
        }

        fatal "Cannot fetch sweep data: $!"
            if not sweepChangesSCM($movetype, "$tmpdir/sweep/tarball");
				
	fatal "cannot unpack sweep data"
	    if system("cd $tmpdir/sweep/data && " . 
                      "tar xf $tmpdir/sweep/tarball") != 0;

        open my $fh, '<', "$tmpdir/sweep/data/FILELIST.$movetype"
            or fatal "No FILELIST.$movetype found: $!";
        
        my (%files, %eclipsed);
        my @csids;  # store correct order in which CSIDs later must be updated to C
        while (<$fh>) {
            my ($csid, $file) = split;
	    if (not $file) {
		$eclipsed{$csid} = 1; 
		next;
	    }
            push @csids, $csid if not exists $files{$csid};
            push @{ $files{$csid} }, $file;
        }

        chdir("$tmpdir/data")
            or fatal "Could not change directory to $tmpdir/data: $!";

	_log_header();

        # print out eclipsed CSIDs first
        print "$_\n" for keys %eclipsed;

        for my $csid (@csids) {
            my $files = $files{$csid};
            next if not @$files;
            my $bundle = Change::Util::Bundle->new(bundle => "$tmpdir/sweep/data/$csid");
            unpack_from_bundle($bundle, $destdir, @$files);
        }
        chdir($rundir);
  }

  sub postChangeSetSCM ($) {
    my $changeset = shift;
    
    my $csid = $changeset->getID();
    unless (defined($csid)) {
      error "Change set lacks id";
      return 0;
    }

    my $tmp = join('.' => $csid,hostname(),time(),$$,'tmp');
    my $local_tmpdir = "$local_t/$tmp.dir";
    my $local_tmp = "$local_t/$tmp";

    my $mask = umask(0002);
    mkdir($local_tmpdir)  or  fatal "Unable to mkdir $local_tmpdir: $!";
    chmod(02775,$local_tmpdir);# ignore error
    umask($mask);
    unless (bundleChangeSet($changeset,$local_tmp,$local_tmpdir)) {
      error "Failed to bundle $csid";
      return 0;
    }
    system('rm','-fr',$local_tmpdir);# ignore error

    if (!system('cp',$local_tmp,SCM_BUNDLE_DIR."/$csid.tmp")) {
      rename(SCM_BUNDLE_DIR."/$csid.tmp",SCM_BUNDLE_DIR."/$csid");# ignore error
    }

    my $result = postBundleSCM($local_tmp,$csid);

    system('rm','-fr',$local_tmp);# ignore error

    return $result;
  }

  sub postBundleSCM ($$) {
    my ($bundle,$csid) = @_;
    my $agent = _agent();

    unless ($agent) {
      error "Failed to get LWP::UserAgent";
      return 0;
    }

    my $url = "$service_url/$SCM_REQ_POST_CS/$csid";

    debug("posting to $url");

    my $response = $agent->post($url,
      Content_Type => 'form-data',
      Content	   => [
	service => $SCM_REQ_POST_CS,
	name => 'csid',
	csid => [ $bundle, $csid,
		  'Content-Type' => 'application/octet-stream',
	        ],
      ],
    );

    return $response->is_success;
  }

  # The main difference between postStructuralChangeSetSCM and
  # postChangeSetSCM is that the first posts only a serialized
  # Change::Set object whereas the latter posts bundled
  # change sets. 
  sub postStructuralChangeSetSCM ($) {
    my $changeset = shift;
    
    my $agent = _agent();
    unless ($agent) {
      error "Failed to get LWP::UserAgent";
      return 0;
    }
    my $csid = $changeset->getID();
    unless (defined($csid)) {
      error "Change set lacks id";
      return 0;
    }

    my ($fh, $local_tmp) = tempfile(DIR => $local_t, UNLINK => 1);
    $fh->autoflush(1);
    print $fh $changeset->serialise;

    my $url = "$service_url/$SCM_REQ_POST_CS/$csid";
    my $response = $agent->post($url,
      Content_Type => 'form-data',
      Content	   => [
	service => $SCM_REQ_POST_CS,
	name => 'csid',
	csid => [ $local_tmp, $csid,
		  'Content-Type' => 'application/octet-stream',
	        ],
      ],
    );
    return ($response->is_success) ? 1 : 0;
  }

  sub enqueueChangeSetSCM ($) {
    my $changeset = shift;

    my $agent = _agent();
    unless ($agent) {
      error "Failed to get LWP::UserAgent";
      return 0;
    }

    my $csid;
    if (UNIVERSAL::isa($changeset, 'Change::Set')) {
        $csid = $changeset->getID();
    } else {
        $csid = $changeset;
    }

    debug3("enqueueing $csid");

    unless (defined($csid)) {
      error "Change set lacks id";
      return 0;
    }
    my $url = "$service_url/$SCM_REQ_ENQUEUE_CS/$csid";

    debug3("enqueueChangeSetSCM: url = $url");

    my $response = $agent->post($url,
      Content_Type => 'form-data',
      Content	   => [
	service => $SCM_REQ_ENQUEUE_CS,
	name => 'csid',
	csid => $csid,
      ],
    );

    debug3("enqueueChangeSetSCM: response is");
    debug3($response->as_string);

    return ($response->is_success) ? 1 : 0;
  }

    sub sweepSCM {
	my ($destfile, $movetype, $status) = @_;

        my $agent = _agent();
        $agent->timeout(3600);

        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

	$status ||= STATUS_INPROGRESS;
        my $url = "$service_url/$SCM_REQ_SWEEP_INC/$movetype/$status";

        my $request = HTTP::Request->new('GET' => $url);
        my $response = $agent->request($request, $destfile);

        return $response->is_success;
    }
	
    sub sweepChangesSCM ($$$) {
        my ($movetype, $destfile) = @_;

        my $agent = _agent();
        $agent->timeout(3600);

        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_SWEEP/$movetype";

        my $request = HTTP::Request->new('GET' => $url);
        my $response = $agent->request($request,$destfile);

        return $response->is_success;
    }

  sub sweepChangesFastSCM {
      my ($movetype, $destfile, $recalculate, $status_to_p) = @_;

      my $agent = _agent();
      $agent->timeout(3600);

      my $url = "$service_url/$SCM_REQ_SWEEP_FAST/$movetype";
      $url .= ($recalculate ? '/1' : '/0');
      $url .= ($status_to_p ? '/1' : '/0');
      my $request = HTTP::Request->new(GET => $url);
      my $response = $agent->request($request,$destfile);

      return $response->is_success;
  }

    sub recoverFilesSCM ($;$) {
        my ($csid, $target) = @_;

        if (not defined $target) {
            local $^W = 0;  # or else File::Temp::tempdir will warn
            (undef, $target) = tempfile(UNLINK => 0, OPEN => 0, SUFFIX => '.tgz');
        }

        my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }


        my $url = "$service_url/$SCM_REQ_RECOVER_FILES/$csid";

        my $request = HTTP::Request->new('POST' => $url);
        my $response = $agent->request($request, $target);

        return (0, $response->content || $response->message || 'Generic error') 
            if not $response->is_success;
        
        return $target;
    }

    sub createRollbackSCM {
        my ($changeset, $msg, $ticket) = @_;

        my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $csid = $changeset->getID;
        $msg = "Rollback: $csid" if not defined $msg;
        my $user = USER;
        my $uuid = getUUIDFromUnixName($user);   
        $ticket ||= 0;

        my $url = "$service_url/$SCM_REQ_CREATE_ROLLBACK/$csid/$user/$uuid/$ticket";

        my $request = HTTP::Request->new(POST => $url);
        $request->header('Content-Type' => 'text/plain');
        $request->content($msg);

        my $response = $agent->request($request);

        if ($response->is_success) {
            my $csstring = $response->content;
            return Change::Set->new($csstring);
        } else {
            return (0, $response->content || $response->message || 'Generic error');
        }
    }

    sub copyoutFilesByCsidSCM {
	my ($target, $csid, $movetype, @files) = @_;
	
	unless (@files) {
	    error "No files specified.";
	    return (0, "No files specifed");
	}
	
	my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

	my $url = "$service_url/$SCM_REQ_COPY_OUT_FILES_BY_CSID";
	$url .= "/$csid" ;
	$url .= "/$movetype";
       
	my $request = HTTP::Request->new('POST' => $url);
        $request->header('Content-Type' => 'text/plain');
			
	my $body = "";
	
	foreach my $file (@files) {
	    next if (not $file);
	    $body .= $file;
	    $body .= "\n";
	}
		
        $request->content($body) if $body;

        my $response = $agent->request($request, $target);
		
	return (0, $response->content || $response->message || 'Generic error') 
            if not $response->is_success;
	return $target;
    }

    sub copyoutLatestFilesSCM {
	my ($target, $move, $beta, $swept, @lroots) = @_;
	if (!-e $target) {
	    error "Target file does not exist";
	    return 0;
	}

	unless (@lroots) {
	    error "No lroot specified.";
	    return 0;
	}
	
	my $agent = _agent();
	unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

	my $url = "$service_url/$SCM_REQ_COPY_OUT_LATEST_FILES";
	
	$move ||= MOVE_REGULAR;	
	$url .= "/$move";
	
	if(defined $beta) {	    
	    $url .= "/beta";
	} elsif(defined $swept) {
	    $url .= "/";
	}

	if(defined $swept) {
	    $url .= "/$swept";
	}

	my $request = HTTP::Request->new('POST' => $url);
        $request->header('Content-Type' => 'text/plain');

	my $body = "";
	
	foreach my $lroot (@lroots) {
	    next if (not $lroot);
	    $body .= $lroot;
	    $body .= "\n";
	}
		
        $request->content($body) if $body;

	my $response = $agent->request($request, $target);	
	return (0, $response->content || $response->message || 'Generic error') 
            if not $response->is_success;
	
	return $target;
    }

    sub _cs_to_canonfiles {
        my $cs = shift;
        return map bare_canonical_path($_, $cs->getMoveType), $cs->getFiles;
    }


    sub recoverCurrentSCM {
        my ($cs, $file, $move, $staged) = @_;

        $move ||= $cs->getMoveType;
        my @files   = _cs_to_canonfiles($cs);

        $staged = "staged" if $staged;
        my $csid = $cs->getID;
        my $url = "$service_url/$SCM_REQ_RECOVER_CURRENT/$csid/$move/$staged";
        my $agent = _agent();

        my $request = HTTP::Request->new('POST' => $url);
        $request->header('Content-Type' => 'text/plain');
        $request->content(join "\n", @files);
        
        my $response = $agent->request($request, $file);

        return 1 if $response->is_success;

        return (0, $response->content || $response->message || 'Generic error');
    }

    sub recoverPriorSCM {
        my ($cs, $file, $move, $latest) = @_;

        $move ||= $cs->getMoveType;
        my @files   = _cs_to_canonfiles($cs);

        $latest = "latest" if $latest;
        my $csid = $cs->getID;
        my $url = "$service_url/$SCM_REQ_RECOVER_PRIOR/$csid/$move/$latest";
        my $agent = _agent();

        my $request = HTTP::Request->new('POST' => $url);
        $request->header('Content-Type' => 'text/plain');
        $request->content(join "\n", @files);
        
        my $response = $agent->request($request, $file);

        return 1 if $response->is_success;

        return (0, $response->content  || $response->message || 'Generic error');
    }

    sub recoverListSCM {
        my ($cs, $mode) = @_;

        my $move = $cs->getMoveType;
        my $csid = $cs->getID;
        my $url = "$service_url/$SCM_REQ_RECOVER_LIST/$csid/$move";
        my $agent = _agent();
        $agent->timeout(3600);

        my (@files, %isnew);
        for ($cs->getFiles) {
            my $canon = bare_canonical_path($_, $cs->getMoveType);
            push @files, $canon;
            $isnew{$canon} = $_->isNew;
        }

        my $request     = HTTP::Request->new('POST' => $url);
        $request->header('Content-Type' => 'text/plain');
        $request->content(join "\n", @files);
        
        my $response = $agent->request($request);

        return (0, $response->content || $response->message || 'Generic error')
            if not $response->is_success;

        my %ret;
        for (split /\n/, $response->content) {
            my ($file, $attr) = /([^ ]+?) (.*)/;
            $ret{$file} = [ split /,/, $attr ];
            push @{$ret{$file}}, 'new' if $isnew{$file};
        }

        return \%ret;
    }

    sub csidIsStagedSCM {
        my ($csid) = @_;

        my $url = "$service_url/$SCM_REQ_CSID_IS_STAGED/$csid";
        my $agent = _agent();

        my $request = HTTP::Request->new(POST => $url);
        my $response = $agent->request($request);

        return $response->code == 200;  # 200 staged, 201 processed
    }

    sub doSweepCalculationSCM {

	my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_DO_SWEEP_CALCULATION";

	my $request = HTTP::Request->new('POST' => $url);
        my $response = $agent->request($request);

        return 1 if $response->is_success;
    }

    sub getSweepFilelistSCM {
        my $movetype = shift;

        $movetype = MOVE_REGULAR if not defined $movetype;

        my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_GET_SWEEP_FILELIST/$movetype";

        my $request = HTTP::Request->new('POST' => $url);
        my $response = $agent->request($request);

        return (0, $response->content || $response->message || 'Generic error') 
            if not $response->is_success;

        my %files;
        for (split /\n/, $response->content) {
            my ($csid, $file) = split;
            $files{$file} = $csid;
        }

        return \%files;
    }

    sub filesStagedSCM {
        my @input = @_;

        my ($is_cs, @body) = _prepare_staged_files_input(@input);

	my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_FILES_STAGED";

	my $request = HTTP::Request->new('POST' => $url);
        $request->header('Content-Type' => 'text/plain');
        $request->content(join "\n", @body);

        my $response = $agent->request($request);

        return (0, $response->content || $response->message || 'Generic error') 
            if not $response->is_success;

        # success: mangle return into an array ref
        return _parse_staged_files_output($response->content, $is_cs);
    }

    sub _prepare_staged_files_input {
        my @input = @_;

        if (UNIVERSAL::isa($input[0], 'Change::Set')) {
            return 1, map bare_canonical_path($_, $input[0]->getMoveType),
                          $input[0]->getFiles;
        } elsif (grep ref($_) ne 'ARRAY', @input) {
            error "Invalid input: must be file/library pairs only";
            return;
        } else {
            return 0, map join("\t", @$_), @input; 
        }
    }

    sub _parse_staged_files_output {
        my ($str, $is_cs) = @_;
        
        my @ret;
        if ($is_cs) {
            @ret = split /\n/, $str;
        } else {
            @ret = map [ split /\t/ ], split /\n/, $str;
        }
        
        return \@ret;
    }

    sub recordBranchPromotionSCM {

	my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_RECORD_BRANCH_PROMOTION";

	my $request = HTTP::Request->new('POST' => $url);
        
        $agent->timeout(1);
        my $response = $agent->request($request);

        return (0, $response->content || $response->message || 'Generic error')
            if not $response->is_success;

        return 1;
    }

    sub pathExistsSCM {
        my @lroot = @_;

	my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_PATH_EXISTS";

	my $request = HTTP::Request->new('POST' => $url);

        $request->header('Content-Type' => 'text/plain');
        $request->content(join "\n", @lroot);

        my $response = $agent->request($request);

        if (not $response->is_success) {
            my $error = $response->content || $response->message || 'Generic error';
            fatal("Could not determine existance of @lroot: $error");
        }
    
        return $response->code == 200;
    }

    sub blameSCM {
        my ($file, $lib, $movetype) = @_;

        require Change::Identity;

        my $stage = STAGE_INTEGRATION;
        my $target = Change::Identity::deriveTargetfromName($lib, STAGE_INTEGRATION);

        return (0, "Invalid library: $lib")
            if not defined $target;

        my $cf = Change::File->new({
                target => $target,
                source => $file,
        });

        my $lroot = bare_canonical_path($cf) or
            return (0, "Could not canonicalize $cf");

	my $agent = _agent();
        unless ($agent) {
            error "Failed to get LWP::UserAgent";
            return (0, "Failed to get LWP::UserAgent");
        }

        my $url = "$service_url/$SCM_REQ_BLAME/$movetype";

	my $request = HTTP::Request->new('POST' => $url);

        $request->header('Content-Type' => 'text/plain');
        $request->content($lroot);

        my $response = $agent->request($request);
        
        if ($response->is_success) {
            return $response->content;
        } else {
            my $error = $response->content || $response->message;
            return (0, "Could not annotate $lib/$file: $error");
        }
    }
}

1;

#==============================================================================

=head1 AUTHOR

William Baxter (wbaxter1@bloomberg.net)

=head1 SEE ALSO

L<InterfaceRCS.pm>,
L<bde_createcs.pl>, L<bde_rollbackcs.pl>

=cut

1;
