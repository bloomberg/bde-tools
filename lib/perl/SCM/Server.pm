# vim:set ts=8 sts=4 noet:

package SCM::Server;

use 5.008008;
use strict;

our $VERSION = '0.01';

use CGI;
use Fcntl               qw/:flock/;

use Util::Message       qw(warning fatal error debug set_debug);
use SCM::Symbols        qw(SCM_REPOSITORY
                           $SCM_QUEUE
                           $SCM_DIR_PREQUEUE 
                           $SCM_DIR_QUEUE
                           $SCM_DIR_PENDING
                           $SCM_DIR_DONE
                           $SCM_DIR_TMP $SCM_DIR_DATA 
                           SCM_CSDB SCM_CSDB_DRIVER
			   $SCM_BRANCH_PROMOTION_MARK
			   $SCM_SWEEPINFO_DATA
			   $SCM_SWEEP_LOCK);

use Production::Symbols qw($SCM_REQ_POST_CS $SCM_REQ_ENQUEUE_CS 
			   $SCM_REQ_SWEEP_INC
                           $SCM_REQ_SWEEP_FAST
			   $SCM_REQ_SWEEP
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

use Change::Symbols     qw($STATUS_INPROGRESS
			   $STATUS_ACTIVE $STATUS_COMPLETE 
			   $STATUS_ROLLEDBACK $STATUS_WITHDRAWN
			   MOVE_IMMEDIATE MOVE_REGULAR MOVE_BUGFIX MOVE_EMERGENCY
			   STAGE_BETA
			   );

#==============================================================================

set_debug(1);

# we only care if it is a betaday for ibig
sub isbetaday {
    require Production::Services;
    require Production::Services::Move;
    my $libs = ["ibig"];
    my $tasks = ["acclib"];
    my $svc = Production::Services->new;
    return &Production::Services::Move::isBetaDay(
	      $svc, $libs, $tasks);
}

sub ensure_path {
    require Util::File::Functions;
    return Util::File::Functions::ensure_path(shift);
}

{ my $queuebase	= $SCM_QUEUE;
  my $prequeue	= $SCM_DIR_PREQUEUE;
  my $queue	= $SCM_DIR_QUEUE;
  my $tmpqueue	= $SCM_DIR_TMP;
  my $dataqueue	= $SCM_DIR_DATA;

  sub new {
    my $cgi = CGI->new();
    my $self = { cgi => $cgi };

    bless $self => __PACKAGE__;
    return $self;
  }

  sub _tempfile($) {
    my $csid = shift;
    my $time = time();
    require Sys::Hostname;
    my $tmp = join('_' => $csid,$time,$$,Sys::Hostname::hostname(),'tmp');
    return $tmp;
  }

  sub postChangeSetSCM ($$$) {
    my ($self,$csid,$rest) = @_;

    debug("postChangeSetSCM: start: $csid, $rest");
    # FIX: check for extant CS
    my $cgi = $self->{cgi};
    my $tmp = _tempfile($csid);
    $tmp = "$queuebase/$tmpqueue/$tmp";

    my $fh = $cgi->upload('csid');
    my $out;

    unless (open ($out,">$tmp")) {
      warning "Failed to open $tmp: $!";
      return 0;
    }

    require File::Copy;
    unless (File::Copy::copy($fh,$out)) {
      warning "Failed to write $tmp: $!";
      unlink($tmp);# ignore error
      return 0;
    }
    unless (close($out)) {
      warning "Failed to close $tmp: $!";
      unlink($tmp);# ignore error
      return 0;
    }
   
    require Change::Util;
    my $dir = "$queuebase/$dataqueue/" . Change::Util::hashCSID2dir( $csid );
    my $data = "$dir/$csid";
    not -d $dir and mkdir $dir;
     
    unless(rename($tmp,$data)) {
      warning "Failed to rename $tmp to $data: $!";
      unlink($tmp);# ignore error
      return 0;
    }

    return 1;
  }

  sub enqueueChangeSetSCM ($$$) {
      my ($self, $csid, $timestamp) = @_;

      debug("enqueueChangeSetSCM: start: $csid, $timestamp");

      require SCM::Checkin;
      my ($ok, $error) = SCM::Checkin::enqueue_changeset($csid, $timestamp);

      if (not $ok) {
	  error "Failed to enqueue $csid: $error";
	  return 0;
      }

      debug("enqueueChangeSetSCM: end");
      return 1;
  }

  sub send_sweep_tarball {
      my ($self, $csids, @additional) = @_;

      require File::Temp;
      my $materialdir = File::Temp::tempdir(CLEANUP => 1);
    
      require SCM::Util;
      require File::Spec;
      for my $csid (@$csids) {
	    my $bundlepath = SCM::Util::getBundlePath($csid) or do {
		warning "Error, bundle for $csid not found";
		return 0;
	    };

	    unless (symlink($bundlepath, "$materialdir/$csid")) {
		warning "Error linking to $bundlepath: $!.";
		return 0; 
	    }
	}

      # copy additional files into tarball
      system("cp $_ $materialdir") == 0
          or warning "Failed to copy $_ to $materialdir: $!, $?"
            for @additional;


      # write out manifest, so client knows csids in commit order

      my $manifest = "$materialdir/manifest";
      my $manifestfh;

      unless (open ($manifestfh, "> $manifest")) {
          warning "Failed to open $manifest for writing: $!.";
          return 0;
      }

      print $manifestfh join $/, @$csids;

      unless (close($manifestfh)) {
          warning "Failed to close $manifest after write: $!.";
          return 0;
      }

      # build the tarball

      my $tarballdir = File::Temp::tempdir(CLEANUP => 1);
      my $tarball = "$tarballdir/sweep.tar";

      if(system("( cd $materialdir && tar chf - . ) > $tarball.tmp &&" . 
                "mv $tarball.tmp $tarball") != 0) {
          warning "Failed to create sweep tarball $tarball: $!.";
          return 0;
      }

      # stream out the tarball
      warn "tarball: $tarball\n";
      return 0 if !$self->_respondWithFile($tarball, 
              -mime => 'application/x-tar');

      debug("sweepChangesSCM: end");

      return -1;
  }

    # sweepversion=1 (prealpha build) in scm_sweep
    sub sweepChangesFastSCM {
        my ($self, $branch, $rest) = @_;

	# SCM_SWEEP_LOCK is the sweepd setlock lock file
	open my $lock, '+>', $SCM_SWEEP_LOCK
	    or die "Royally screwed. Can't open $SCM_SWEEP_LOCK: $!";
    
	warn "Trying to acquire lock for $SCM_SWEEP_LOCK...\n";
	flock $lock, LOCK_EX;	# we try it even if that fails because down-stream
				# operations would bail out later if something was
				# wrong.
	warn "Done!\n";

	require SCM::Sweep;
	my ($data, $err) = SCM::Sweep::compile_sweep_changes_continuous($branch);

	return $self->_send_error(400, $err) if not $data;

        return $self->send_sweep_tarball(@$data);
    }

    # sweepversion=2 in scm_sweep
    sub sweepChangesSCM {
	my ($self, $movetype) = @_;

	# SCM_SWEEP_LOCK is the sweepd setlock lock file
	open my $lock, '+>', $SCM_SWEEP_LOCK
	    or die "Royally screwed. Can't open $SCM_SWEEP_LOCK: $!";
    
	warn "Trying to acquire lock for $SCM_SWEEP_LOCK...\n";
	flock $lock, LOCK_EX;	# we try it even if that fails because down-stream
				# operations would bail out later if something was
				# wrong.
	warn "Done!\n";

	require SCM::Sweep;
	my ($ret, $err) = SCM::Sweep::compile_sweep_changes($movetype);

	return $self->_send_error(500, $err) if $err;

	return $self->send_sweep_tarball(@$ret);
    }

    # /bbsrc/checkin-free incremental sweep
    sub sweepSCM {
	my ($self, $move, $status) = @_;

	# SCM_SWEEP_LOCK is the sweepd setlock lock file
	open my $lock, '+>', $SCM_SWEEP_LOCK
	    or die "Royally screwed. Can't open $SCM_SWEEP_LOCK: $!";

	warn "Trying to acquire lock for $SCM_SWEEP_LOCK...\n";
	flock $lock, LOCK_EX;	# we try it even if that fails because down-stream
				# operations would bail out later if something was
				# wrong.
	warn "Done!\n";

	require SCM::Queue::Util;
	require SCM::CSDB::Sweep;
	require SCM::Repository;

	my $csdb = SCM::CSDB::Sweep->new(database => SCM_CSDB,
					 driver   => SCM_CSDB_DRIVER);
	my $rep = SCM::Repository->new(repo => SCM_REPOSITORY);

	my $jobs = SCM::Queue::Util::get_job_csid_by_move_hash($move, undef, 
							       $SCM_DIR_DONE);
	my @csids = keys %$jobs;

	@csids = $csdb->getChangeSetsForSweep(\@csids, status => $status);


	@csids = sort { $rep->_get_rev_from_csid($a) 
				    <=> 
			$rep->_get_rev_from_csid($b) } @csids;

	return $self->send_sweep_tarball(\@csids);
    }

    sub recoverFilesSCM {
        my ($self, $csid) = @_;

        require Change::Util;
        require File::Spec;
        my $csfile = File::Spec->catfile($SCM_QUEUE, $SCM_DIR_DATA, 
                                         Change::Util::hashCSID2dir($csid), $csid);
       
        $self->_send_error(400, "No change set with ID $csid found")
            if not -e $csfile;

        $self->_respondWithFile($csfile);
        return -1;
    } 

    sub _get_files_from_jobs {
        my ($self, $fromjobs, $tmpout) = @_;

        return if not defined $fromjobs;

        # reorganize $fromjobs. It maps files to csids
        # but we want the reverse mapping in order to 
        # extract a bundle once, grab the files we need
        # from it and then discard it.
        my %jobs;
        while (my ($file, $csid) = each %$fromjobs) {
            push @{ $jobs{$csid} }, $file;
        }

        require File::Temp;
        require Change::Util;
        require Change::Set;
        require File::Spec;

        my $tmpin   = File::Temp::tempdir(CLEANUP => 1);
        while (my ($csid, $files) = each %jobs) {
            my $bundle = File::Spec->catfile($SCM_QUEUE, $SCM_DIR_DATA,
                                             Change::Util::hashCSID2dir($csid));
            unbundleChangeSet(Change::Set->new, $bundle, $tmpin);
            for (@$files) {
                ensure_path("$tmpout/$_");
                system "cp $tmpin/$_ $tmpout/$_";
            }
            system("rm -rf $tmpin/*");
        }
    }

    sub _get_rev {
        my ($rep, $path, $start, $end) = @_;
        my ($id) =  $rep->csid_history($path, startcsid  => $start,
                                              endcsid    => $end,
                                              limit      => 1);
        return $id;
    }

    use constant PRIOR_ONLY         => 1;
    use constant PRIOR_OR_CURRENT   => 2;
    my $rep;
    sub _files_to_tarball {
        my ($self, $csid_or_current, $move, $fromrep, $fromjobs) = @_;

	require SCM::CSDB::Branching;

	my $csdb = SCM::CSDB::Branching->new(database => SCM_CSDB,
					     driver   => SCM_CSDB_DRIVER);
	my $branch = $csdb->resolve_alias(alias => $move)->{branch_id};
        
        require File::Temp;
        my $tmpout  = File::Temp::tempdir(CLEANUP => 1);

        $self->_get_files_from_jobs($fromjobs, $tmpout);
        
        require SCM::Repository;
        my $rep = SCM::Repository->new(repository_path => SCM_REPOSITORY);

        # we either want everything in the most current 
        # revision or in the prior revision:
        # Partition depending on what we want
        my (%current, %prior);  # path => undef (undef later becomes filehandle)
        my ($current, $prior);  # CSIDs 
        if (not defined $csid_or_current) {
            # most recent revision for all files
            my ($head, $err) = $rep->list_commits($branch, undef, 1);
            return $self->_send_error(400, "Could not retrieve HEAD: $err")
                if $err;
            $current = $head->[0];
            %current = %$fromrep;
        } else {
            my ($csid, $mode) = each %$csid_or_current;
            if ($mode eq PRIOR_ONLY) {
                my ($head, $err) = $rep->list_commits($branch, $csid, 2);
                return $self->_send_error(400, "Could not retrieve HEAD: $err")
                    if $err;
                $prior = $head->[0]; 
                %prior = %$fromrep;
            } else {
                # prior or current
		require File::Spec;
                while (my ($path, undef) = %$fromrep) {
		    my $branched = File::Spec->catfile($branch, $path);
                    if ($current = _get_rev($rep, $branched, undef, $csid)) {
                        $current{$path} = undef;
                        next;
                    }
                    $prior{$path} = undef;
                }
            }
        }

        for (keys %current) {
            ensure_path(File::Basename::dirname("$tmpout/root/$_"));
            open +($current{"$branch/$_"} = undef), '>', "$tmpout/root/$_" or
                return $self->_send_error(500, 
                                          "Could not write $tmpout/root/$_: $!");
        }
        if (%current) {
            my ($ok, $err) = $rep->export($move, $current, \%current);
            return $self->_send_error(400, "$_ could not be retrieved: $err")
                if $err;
        }

        for (keys %prior) {
            ensure_path(File::Basename::dirname("$tmpout/root/$_"));
            open +($prior{"$branch/$_"} = undef), '>', "$tmpout/root/$_" or
                return $self->_send_error(500, 
                                          "Could not write $tmpout/root/$_: $!");
        }
        if (%prior) {
            my ($ok, $err) = $rep->export($move, $prior, \%prior);
            return $self->_send_error(400, "$_ could not be retrieved: $err")
                if $err;
        }

        # make tarball
        my (undef, $tarname) =  do {
            local $^W;
            require File::Temp;
            File::Temp::tempfile(OPEN => 0);
        };

        system("cd $tmpout && tar cf - root | gzip -c > $tarname") == 0
            or  return $self->_send_error(500, "Could not create tarball: $!, $?");

        return $tarname;
    }

    # Implements: 'csrecover -C'        ($staged == 1)
    #             'csrecover -C -R'     ($staged == 0)
    sub recoverCurrentSCM {
        my ($self, $csid, $rest) = @_;
        
        my ($movetype, $staged) = split /\//, $rest;

        my %jobs;
        my %repo;

        my @files = split /\n/, $self->{cgi}->param('POSTDATA');
       
        s#^root/##, $repo{$_} = 0 for @files;

        if ($staged) {
            require SCM::Queue::Util;
            for my $j (SCM::Queue::Util::get_staged_jobs()) {
                for (keys %repo) {
                    if ($j->cs->hasFile($_)) {
                        $jobs{$_} = $j;
                        delete $repo{$_};
                    }
                }
            }
        }

        my $tarball = $self->_files_to_tarball(undef, $movetype, \%repo, \%jobs);
        $self->_respondWithFile($tarball, -mime   => 'application/x-tar',
                                          -remove => 1);
    }

    # Implements: 'csrecover -p'
    #             'csrecover -p -C' ($latest == 1)
    sub recoverPriorSCM {
        my ($self, $csid, $rest) = @_;

        my ($movetype, $latest) = split /\//, $rest;

        my %files;

        for (split /\n/, $self->{cgi}->param('POSTDATA')) {
            s#^root##;
            $files{$_} = undef;
        }

        my $specs = {
            $csid => $latest ? PRIOR_OR_CURRENT 
                             : PRIOR_ONLY,
        };
        my $tarball = $self->_files_to_tarball($specs, $movetype, \%files);
        $self->_respondWithFile($tarball, -mime   => 'application/x-tar',
                                          -remove => 1);
    }
  
    my %birth;
    sub _rep_info {
        my ($file, $csid, $move) = @_;

        (my $path = $file) =~ s#^root/##;
    
        require SCM::Repository;
	require SCM::CSDB::Branching;
	require File::Spec;

        my $repo = SCM::Repository->new(repository_path => SCM_REPOSITORY);
	my $csdb = SCM::CSDB::Branching->new(database => SCM_CSDB,
					     driver   => SCM_CSDB_DRIVER);

	my $branch = $csdb->resolve_alias(alias => $move)->{branch_id};

	$path = File::Spec->catfile($branch, $path);

        my ($hist, $err) = $repo->csid_history($path, limit => 2);

        return if $err;

        return 'head'   if $csid eq $hist->[0];
        return 'prior'  if $csid eq $hist->[1];
    }


    sub _get_finfo {
        my ($file, $staged, $sweep, $csid, $move) = @_;

        my @attr;

        if (exists $staged->{ $file }) {
            push @attr, 'staged', 'head', 'current';
        } else {
            push @attr, _rep_info($file, $csid, $move);
            push @attr, 'current' if $attr[-1] eq 'head';
        }

        push @attr, 'in sweep'  
            if ($sweep->{$file} || '') eq $csid;    

        return join ',', @attr;
    }

    # Implements: 'csrecover -l'
    sub recoverListSCM {
        my ($self, $csid, $move) = @_;

        my @files = split /\n/, $self->{cgi}->param('POSTDATA');
       
        require SCM::Queue::Util;
        my $staged  = SCM::Queue::Util::get_staged_files();
        my $sweep;  
        
        if ($move ne MOVE_IMMEDIATE) {
            require SCM::Queue::Util;
            $sweep = SCM::Queue::Util::get_sweep_targets($move);
        } else {
            $sweep = {};
        }

        my %finfo;
        for my $f (@files) {
            $finfo{$f} = _get_finfo($f, $staged, $sweep, $csid, $move);
        }

        print $self->{cgi}->header(
                -status => 200,
                -type   => 'test/plain',
        );

        while (my ($file, $info) = each %finfo) {
            print "$file $info\n";
        }

        return -1;
    }

    sub _send_error {
        my ($self, $code, $string) = @_;
            print $self->{cgi}->header(
                    -type   => 'text/plain',
                    -status => $code,
            );
            print $string;
	    error "$code:$string";
            return -1;
    }

    sub fix_movetype {
	my ($movetype, $stage, $time) = @_;

	# beta emovs submitted after $magic_tsp
	# have been committed to the bugf branch

	# this is 2008-02-05 00:00:00 EST
	my $magic_tsp = 1202187600;

	require HTTP::Date;
	my $tsp = HTTP::Date::str2time($time);

	return 'bugf'	if $movetype  eq MOVE_EMERGENCY	and
			   lc($stage) eq STAGE_BETA	and
			   $tsp >= $magic_tsp;

	return $movetype;
    }

   # 1: look for staged area, compare stage type if it is emov,
   # 2: if not found from stage area, look for repository, for move, bugf, emov beta,
   #    get the most recent swept version regardless of move type.
   # 3: for emov type, if not found from stage area, get the cutoff csid, look for
   #    completed emov after cutoff csid except on betaday, skip the beta emov. 
   #    If no csid found, look for most recent swept csid before cutoff csid
   #    (including cutoff csid)
   #    
   # Cutoff csid usually is updated on thursday night and midday of betaday
   sub copyoutLatestFilesSCM($$) {
        my ($self, $movetype, $rest)=@_;

	my ($beta, $swept);
	($beta, $swept) = split /\//, $rest if $rest;	

	my $files = [ split /\n/, $self->{cgi}->param('POSTDATA') ];
	
	return $self->_send_error(400, "No file specified $!")
	    if not @$files;
		
	$movetype ||= MOVE_REGULAR;

	require File::Temp;
	my $result_dir = File::Temp::tempdir(CLEANUP => 1);
	if((not defined $swept or $swept eq 'approved')) {
	    require SCM::Checkout;
	    SCM::Checkout::export_from_queue($files, $result_dir, 
					     approved => $swept eq 'approved');
	}

	my($csidx, $xstamp, $isbetaday);
	if($movetype eq MOVE_EMERGENCY) {
	    require SCM::Util;
	    ($csidx, $xstamp) = SCM::Util::get_branch_promotion_cutoff() 
		or warn("Failed to get_branch_promotion_cut_off: $!\n");
	    $isbetaday = isbetaday();
	    debug("Cscheckout cutoff csid is $csidx");
	}

	require Util::File::Functions;
	require SCM::Repository;
	require SCM::Util;
	require SCM::CSDB::FileHistory;

	my $csf = SCM::CSDB::FileHistory->new(database	=> SCM_CSDB,
					      driver	=> SCM_CSDB_DRIVER);
	my $repo = SCM::Repository->new(repository_path => SCM_REPOSITORY);

	Util::File::Functions::ensure_path("$result_dir/root");
	my $meta_fh = IO::File->new(">>$result_dir/root/meta") or 
	    return $self->_send_error(500, "Failed to create meta file: $!");

	require File::Basename;
	foreach my $lroot (@$files) {
	    my $base = File::Basename::basename($lroot);
	    (my $branchless = $lroot) =~ s/^\d+//;
	    my $filename = File::Spec->catfile($result_dir, "root", $base);
	    
	    my $rec;
	    if($movetype eq MOVE_EMERGENCY) {
		if($isbetaday) {
		    if (defined $beta) {
			#beta emove is in the same branch as bf and move
			debug("retrive from after cutoff beta");
			$rec = $csf->getLatestSweptCsid($base); 
		    } else {
			debug("retrieve from after cutoff no beta");
			$rec = $csf->history_after_cutoff_no_beta($base,
								  move => $movetype,
								  cutoff => $xstamp);
		    }
		} else {
		    debug("retrieve from after cutoff\n");
		    $rec = $csf->history_after_cutoff($base, 
						      move => $movetype,
						      cutoff => $xstamp);
		}
		unless($rec) {
		    debug("retrieve from before cutoff $xstamp $base");
		    $rec = $csf->history_before_cutoff($base,
						       cutoff => $xstamp);
		}
	    } else {
	       $rec = $csf->getLatestSweptCsid($base);
	    }
	    
	    Util::File::Functions::ensure_path(File::Basename::dirname($filename));

	    require SCM::CSDB::Branching;
	    my $csdb = SCM::CSDB::Branching->new(database   => SCM_CSDB,
						 driver	    => SCM_CSDB_DRIVER);
	    if($rec) {
		debug("retrieving $base from ", $rec->{csid},
		      $rec->{movetype}, $rec->{creator});
		warn "exporting $branchless => $filename\n";
		my $realmove = fix_movetype(@{$rec}{qw/movetype stage create_time/});
		my $branch = $csdb->resolve_alias(alias => $realmove,
						  utc	=> $rec->{create_time})
				  ->{branch_id};
		warn "real movetype: $realmove as branch $branch\n";
		(my $branched = "$branch/$branchless") =~ tr#/#/#s;
		my ($fhs, $err) = $repo->export($rec->{csid}, 
						{ $branched => $filename });

		warn "Failed to retrieve $branched: from $rec->{csid}: $err"
		    if $err;
	    
		print $meta_fh
		    join ',' => $lroot, @{$rec}{ qw/csid createor movetype status/ },				       SCM::Util::datetime2csdate($rec->{create_time});
		print $meta_fh "\n";
	    } else {
		debug("no csid history found, retriving $base from repository");
		# no CSID history so we are just retrieving any version of that file
		# This is most likely the version of the initial import from RCS
		my %csid;
		my ($fhs, $err) = $repo->export(undef, {$lroot => $filename}, \%csid);
		if($err) {
		    warn("Failed to retrieve $lroot: $err");
		    next;
		}
		if ($csid{$branchless}) {
		    # the version of the file exported has a CSID and that means
		    # it is not what we want because the changesetdb did not
		    # give us a CSID that we can check out
		    unlink $filename;
		    next;
		}
		# force an old timestamp since otherwise the commit-time
		# of svn's head-revision would be used which might be too
		# recent for cscheckin's out-of-date test
		my $old_tsp = time - (365 * 24 * 3600);
		utime($old_tsp, $old_tsp, $filename);
	    }
	}
	close $meta_fh;
		
	my $tarball = File::Spec->catfile($result_dir, "copyout.tar");
       
	if ($self->_create_tarball_from_dir("$result_dir/root", $tarball)) {
	    return $self->_send_error(500, "Failed to create tarball: $!");
	}
	
	return 0 if not $self->_respondWithFile($tarball, 
						-mime => 'application/x-tar');
	return 1;
    }


    sub copyoutFilesByCsidSCM($$$) {
	my ($self, $csid, $movetype) = @_;

	require SCM::Util;
	require File::Spec;

	my $csfile = SCM::Util::getBundlePath($csid);

	my $files = $self->_parse_postdata_for_lroots;
	return $self->_send_error(400, "No file specified $!")
	    if not %$files;

	require SCM::CSDB::ChangeSet;
	my $cdb = SCM::CSDB::ChangeSet->new(database => SCM_CSDB,
					    driver   => SCM_CSDB_DRIVER);
	my $cs = $cdb->getChangeSetDbRecord($csid);

	foreach (keys %$files) {	     
	    push @{$files->{$_}}, $cs;
	}

	my $result_dir;
	if (_csidIsStaged($csid)) {	 
	    $result_dir = $self->_getFilesFromStage($files);
	} else {
	    $result_dir = $self->_getFilesFromRepository($movetype, $files);
	}

	return $self->_send_error(500, "Failed to retrieve file.\n")
	    if not defined $result_dir;

	my $tarball = File::Spec->catfile($result_dir, "copyout.tar");

	if($self->_create_tarball_from_dir("$result_dir/root", $tarball)) {
	    return $self->_send_error(500, "Failed to create tarball: $!");
	}

	return 0 if !$self->_respondWithFile($tarball, 
					     -mime => 'application/x-tar');
	return 1;       
    }

   sub _csidIsStaged {
       my $csid = shift;
       
       my $stages = join ',', $SCM_DIR_PREQUEUE, $SCM_DIR_QUEUE, 
                              $SCM_DIR_PENDING, $SCM_DIR_DONE;
       my @files = glob "$SCM_QUEUE/{$stages}/$csid*";
       return scalar @files;
   }

   sub csidIsStagedSCM {
        my ($self, $csid) = @_;
      
	my $staged = _csidIsStaged($csid);

        print $self->{cgi}->header(-status => $staged ? 200 : 201);
        return -1;
   }
       
   sub doSweepCalculationSCM {
       my ($self) = @_;
       require SCM::Queue::Sweep;
       my $sweep = SCM::Queue::Sweep->new($SCM_QUEUE);
       $sweep->run(dry_run => 1);
       return 1;
   }

    sub getSweepFilelistSCM {
	my ($self, $move) = @_;

	require SCM::Queue::Util;
	my $files = SCM::Queue::Util::parse_filelist($move);

	print $self->{cgi}->header(
                -type   => 'text/plain',
                -status => 200,
        );

	while (my ($file, $csid) = each %$files) {
	    print "$csid\t$file\n";
	}

	return -1
    }

    # used by csuncheckout
    sub filesStagedSCM {
	my ($self) = @_;

	my $consider_lib = 0;

	my %paths;
	for (split /\n/, $self->{cgi}->param('POSTDATA')) {
	    warn $_, "\n";
	    # $lib can be undef
	    my ($path, $lib) = split /\t/, $_;
	    if (defined $lib) {
		$consider_lib = 1;
		$paths{$_} = $_;
	    } else {
		$paths{"root/$path"} = $path;
	    }
	}

	require SCM::Queue::Util;
	my @cs = map $_->cs, SCM::Queue::Util::get_staged_jobs();

	my @staged;
	if ($consider_lib) {
	    # basename + lib was provided
	    for my $cs (@cs) {
		for my $file ($cs->getFiles) {
		    my $str = join "\t", $file->getLeafName, $file->getLibrary;
		    push @staged, delete $paths{$str} if $paths{$str};
		    last if not %paths;
		}
	    }
	} else {
	    # change set provided so we have full paths
	    for my $cs (@cs) {
		for my $file ($cs->getFiles) {
		    push @staged, delete $paths{$file} if $paths{$file};
		    last if not %paths;
		}
	    }
	}

	print $self->{cgi}->header(
		-status => 200,
		-type	=> 'text/plain',
	);

    	print $_, "\n" for @staged;

	return -1;
    }

   sub _getFilesFromStage {
       my ($self, $files) = @_;
         
       require File::Temp;
       my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
       mkdir("$tmpdir/csid") or do {
	   debug("Cannot mkdir '$tmpdir/csid': $!");
	   return undef;
       };
       mkdir("$tmpdir/root") or do {
	   debug("Cannot mkdir '$tmpdir/root': $!");
	   return undef;
       };
       
       require Util::File::Copy;
       require SCM::Util;
       require File::Spec;

       my $meta_fh = IO::File->new(">>$tmpdir/root/meta") or 
	   return $self->_send_error(500, "Failed to create meta file: $!");  

       foreach my $entry (values %$files) {
	   next if @$entry == 0;
	   my $cs = $entry->[1] or next;
	   next if not UNIVERSAL::isa($cs, 'Change::Set');
	   my $csid = $cs->getID or next;
	   $csid = $cs->getID or next if $cs;	   
	   debug "_getFilesFromStage: csid is $csid\n";

	   my $tarball = SCM::Util::getBundlePath($csid) or next;
	  
	   my $res_dir = File::Spec->catdir($tmpdir, "csid", $csid);   	  
	   next if -e $res_dir;	  
	 	 
	   mkdir("$tmpdir/csid/$csid") or do {
	       debug("Cannot mkdir '$tmpdir/csid/$csid': $!");
	       next;
	   };
	  	     
	   unless (system("gunzip -c $tarball | { cd $res_dir && tar xf -; }") == 0)
	   {
	       debug("Failed to unbundle the change set $csid\n");
	   }
       }
 
       require SCM::CSDB::Status;
       my $csq = SCM::CSDB::Status->new(database => SCM_CSDB,
	       driver   => SCM_CSDB_DRIVER);   
       require File::Basename;
       foreach my $entry (values %$files) {
	   next if @$entry == 0;
	   my $cs = $entry->[1] or next;
	   next if not UNIVERSAL::isa($cs, 'Change::Set');
	   my $lroot = $entry->[0] or next;
	   my $tsp = $cs->getTsp;

	   my $filename = File::Spec->catfile($tmpdir, "csid", 
		   $cs->getID, "root", $lroot);	 
	   if(-e $filename){
	       my $target = File::Spec->catfile("$tmpdir", "root", File::Basename::basename($lroot));
	       Util::File::Copy::copyx($filename, $target);
	       utime($tsp, $tsp, $target);
	       print $meta_fh join ',', $lroot, $cs->getID,
		     $cs->getUser, $cs->getMoveType,
		     $csq->getChangeSetStatus($cs->getID),
		     $cs->getTime;
	       print $meta_fh "\n";
	   } else {
	       debug("NOT find $filename in stage area\n");
	   }
       }
       $meta_fh->close;

       return $tmpdir;
   }

   sub _getFilesFromRepository($$$;$) {
      my ($self, $movetype, $files, $status) = @_;           

      require SCM::Repository::CSDB; 
      my $repo = SCM::Repository::CSDB->new(repository_path => SCM_REPOSITORY);
		
      require File::Temp;
      my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
      mkdir("$tmpdir/root") or do {
	  debug("Cannot mkdir '$tmpdir/root': $!");
	  return;
      };
      my $meta_fh = IO::File->new(">>$tmpdir/root/meta") or 
	   return $self->_send_error(500, "Failed to create meta file: $!");

      require SCM::CSDB::ChangeSet;
      require SCM::CSDB::Status;
      require SCM::CSDB::Branching;
      my $cdb = SCM::CSDB::ChangeSet->new(database => SCM_CSDB,
					  driver => SCM_CSDB_DRIVER);
      my $css = SCM::CSDB::Status->new(dbh => $cdb->dbh);
      my $csb = SCM::CSDB::Branching->new(dbh => $cdb->dbh);

      my $branch = $csb->resolve_alias(alias => $movetype);
     
      require File::Spec;
      foreach my $file (keys %$files) {

	   my $lroot = $files->{$file}->[0];
	   my $branched = File::Spec->catfile($branch, $lroot);

	   my ($fhs, $err, $cs);
	   my $filename = File::Spec->catfile($tmpdir, "root", $file);	  
	   $cs = $files->{$file}->[1] if  @{$files->{$file}} >= 2;	   
	   my $csid;
	   if ($cs) {
	       $csid = $cs->getID;
	       ($fhs,$err) = $repo->export($csid, { $branched => $filename });
	       if ($err) {
		   warn "$branched not found from $csid\n";
		   goto META;
	       } 
	   } elsif(defined $status){
	       my $found;
	       my $visitor = sub {
		   my $id = shift;
		   if($css->getChangeSetStatus($id) eq $status) {
		       my $cs = $cdb->getChangeSetDbRecord($id);
		       return 1 if $cs->isRollbackChangeSet;
		       $found = $id;
		       return 0; #stop here
		   }
		   return 1;
	       };
	       
	       $repo->csid_history($branched, visit => $visitor);
	       if(not defined $found) {
		   (my $head, $err) = $repo->list_commits($branch, undef, 1);
		   if($err == 0) {
		       debug("No csid history for $lroot $movetype $status");
		       ($fhs, $err) = $repo->export($head->[-1], 
						    { $branched => $filename });
		   }		   
	       } else {
		   debug("retrieving $branched from $found: $movetype $status");
		   ($fhs, $err) = $repo->export($found, { $branched => $filename });
		   $csid = $found;
	       }
	   } else{
	       (my $hist, $err) = $repo->csid_history($branched, limit => 1);     
	       if($err) { #in case there is no csid for the file
		   debug("Error to get csid_history for $branched $movetype $err");
		   ($hist, $err) = $repo->list_commits($branch, undef, 1);
		   ($fhs, $err) = $repo->export($hist->[-1], 
						{ $branched => $filename })
		       unless $err;
	       } elsif (@$hist){		  
		   $csid = $hist->[-1];
		   ($fhs, $err) = $repo->export($hist->[-1], 
						{ $branched => $filename });
		   debug("retrieving $branched from $csid");
	       } else {
		   debug("No csid history for $branched $movetype");
	       }	      
	   }
	   
	   if ($err) {
	       debug("Error on retrieving $branched $movetype from repository ");
	       next;
	   }
	META:
	   if($csid) {
	       my $cs = $cdb->getChangeSetDbRecord($csid);
	       print $meta_fh 
		     join ",", $lroot, $csid, $cs->getUser,
		              $cs->getMoveType, $cs->getStatus,
		              $cs->getTime;
	       print $meta_fh "\n";
	   }
	   	
       }
      $meta_fh->close;

      return $tmpdir;
  }

  sub _parse_postdata_for_lroots {
      my $self = shift;

      my $data = $self->{cgi}->param('POSTDATA');

      my %files;
      require File::Basename;
      for my $e (split /\n/, $data) {	
	  my $fname = File::Basename::basename($e);
	  push @{ $files{$fname} }, $e;
      }
      
      return \%files;
  }

  
  sub _create_tarball_from_dir {
       my ($self, $dir, $tarball) = @_;
       
       if( -z $dir) {
	   return 1;
       }

       return system("(cd $dir && tar cf - .)>$tarball.tmp&&mv $tarball.tmp $tarball");	 
   }

    sub _respondWithFile {
	my ($self, $file, %args) = @_;

	print $self->{cgi}->header(
		-type => $args{-mime} || 'application/octet-stream',
		-Content_length => -s $file,
		);

	{
	    open my $fh, $file or fatal "Could not open $file for reading: $!";
	    local $/ = \4096;
	    print while <$fh>;
	}

	unlink $file if $args{-remove};

	return -1;
    }

    sub recordBranchPromotionSCM {
	my $self = shift;

	require SCM::Repository;
	require SCM::CSDB::Status;
	require SCM::CSDB::ChangeSet;
	require SCM::CSDB::History;
	require SCM::CSDB::Branching;
	require File::Spec;

	my $rep = SCM::Repository->new(repository_path => SCM_REPOSITORY);
	my $sdb = SCM::CSDB::Status->new(database => SCM_CSDB, 
					 driver => SCM_CSDB_DRIVER);
	my $cdb = SCM::CSDB::ChangeSet->new(dbh => $sdb->dbh);
	my $hdb = SCM::CSDB::History->new(dbh => $sdb->dbh);
	my $bdb = SCM::CSDB::Branching->new(dbh => $sdb->dbh);

	my @csids;
	for my $map (@{ $bdb->get_current_mappings }) {
	    next if $map->{alias} eq MOVE_IMMEDIATE;
	    $rep->csid_history($map->{branch_id},
	 		       visit => sub {
				    my $csid = shift;
				    my $status = $sdb->getChangeSetStatus($csid);
				    return 1 if $status ne $STATUS_COMPLETE;

				    warn "Looking closer at $csid ($status)\n";
				    my $cs = $cdb->getChangeSetDbRecord($csid);

				    return 1 if $cs->isBregMove;
				    return 1 if $cs->isRollbackChangeSet;
				    return 1 if $cs->isStructuralChangeSet;
				    warn "$csid is eligible\n";

				    my $hist = $hdb->getChangeSetHistory($csid);
				    my $date = $hist->[-1][0];
				    push @csids, [ $csid, $date ];
				    return 0;	# signal end of iteration
			       }
	    );
	}
	
	my ($max) = sort { $b->[0] cmp $a->[0] } @csids;

	my $tmp = "$SCM_BRANCH_PROMOTION_MARK.$$";
	open my $tmph, '>', $tmp
	    or return $self->_send_error(500, "Could not open $tmp for writing: $!");
	print $tmph $max->[0], "\n", $max->[1], "\n";
	close $tmph
	    or return $self->_send_error(500, "Could not close $tmp: $!");

	rename $tmp => $SCM_BRANCH_PROMOTION_MARK or 
	    return $self->_send_error(500, "Could not rename $tmp => $SCM_BRANCH_PROMOTION_MARK: $!");

	return 1;
    }

    sub pathExistsSCM {
	my $self = shift;

	my @lroot = split /\n/, $self->{cgi}->param('POSTDATA');

	require SCM::Repository;

	my $rep = SCM::Repository->new(repository_path => SCM_REPOSITORY);

	my $exists = 1;
	for (@lroot) {
	    $exists = 0, last if not $rep->path_exists($_);
	}
	
	print $self->{cgi}->header(-status => $exists ? 200 : 201);

	return -1;
    }

    sub blameSCM {
	my ($self, $movetype) = @_;

	chomp(my $lroot = $self->{cgi}->param('POSTDATA'));

	require SCM::Repository::Blame;
	my $blame = SCM::Repository::Blame->new(repository_path => SCM_REPOSITORY);

	open my $fh, '>', \my $report;

	my ($ok, $err) = $blame->blame($movetype, $lroot, $fh);

	return $self->_send_error(500, $err)
	    if $err;

	print $self->{cgi}->header(-status => 200, -type => 'text/plain');
	print $report;

	return -1;
    }

  my %service = (
    $SCM_REQ_POST_CS	                => \&postChangeSetSCM,
    $SCM_REQ_ENQUEUE_CS                 => \&enqueueChangeSetSCM,
    $SCM_REQ_SWEEP_INC			=> \&sweepSCM,
    $SCM_REQ_SWEEP_FAST                 => \&sweepChangesFastSCM,
    $SCM_REQ_SWEEP			=> \&sweepChangesSCM,
    $SCM_REQ_RECOVER_FILES              => \&recoverFilesSCM,
    $SCM_REQ_COPY_OUT_FILES_BY_CSID     => \&copyoutFilesByCsidSCM,
    $SCM_REQ_COPY_OUT_LATEST_FILES      => \&copyoutLatestFilesSCM,
    $SCM_REQ_RECOVER_CURRENT            => \&recoverCurrentSCM,
    $SCM_REQ_RECOVER_PRIOR              => \&recoverPriorSCM,
    $SCM_REQ_RECOVER_LIST               => \&recoverListSCM,
    $SCM_REQ_CSID_IS_STAGED,            => \&csidIsStagedSCM,
    $SCM_REQ_DO_SWEEP_CALCULATION       => \&doSweepCalculationSCM,
    $SCM_REQ_GET_SWEEP_FILELIST         => \&getSweepFilelistSCM,
    $SCM_REQ_FILES_STAGED		=> \&filesStagedSCM,
    $SCM_REQ_RECORD_BRANCH_PROMOTION	=> \&recordBranchPromotionSCM,
    $SCM_REQ_PATH_EXISTS		=> \&pathExistsSCM,
    $SCM_REQ_BLAME			=> \&blameSCM,
  );

  sub handle_request ($) {
    my $self = shift;

    my $cgi = $self->{cgi};

    # request is one of the SCM_REQ_* constants from Production::Symbols.
    # id is usually CSID, but possibly move type (sweep).
    # Populate these from the cgi object if they are not in PATH_INFO.
    # PATH_INFO contains leading /.
    my (undef,$request,$id,$rest) = split('/' => $ENV{'PATH_INFO'},4);
    debug("handle_request: $request, $id, $rest");

    unless (defined $request) {
      $request = $cgi->param('service');
    }
    unless (defined $id) {
      $id = $cgi->param('csid');
    }

    unless (exists($service{$request})) {
      print $cgi->header(-status=> "404 Unknown service");
      exit 0;
    }

=pod
    unless (defined $id) {
      print $cgi->header(-status=> "400 Bad Request");
      exit 0;
    }
=cut

    my $req = $service{$request};
    my ($result, $status) = eval {
	# without CGI::Carp we are suddenly exposed to all these
	# twisted exceptions thrown by SVN. 
	$self->$req($id, $rest);
    };

    if (not $@) {
	debug("handle_request: result = $result, $status");
    } else {
	debug("handle_request: exception was thrown:\n$@");
	return $self->_send_error(500, $@);
    }

    # $result <> 0: success: > 0 => produce reponse and exit, < 0 => exit.
    # $result == 0: error, produced response, exit.
    if (!$result) {
      # result == 0:
      print $cgi->header($status ? (-status => $status)
				 : (-status => "500 Internal Server Error")
			);
      exit 1;
    }
    if ($result > 0) {
      print $cgi->header($status ? (-status => $status) : ());
    }
    # < 0: success, subroutine produced response.
    exit 0;
  }
}

#==============================================================================

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

SCM::Server - Perl extension for blah blah blah

=head1 SYNOPSIS

  use SCM::Server;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for SCM::Server, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

William Baxter -  SI Build, E<lt>wbaxter1@bloomberg.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by william baxter -  SI Build

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
