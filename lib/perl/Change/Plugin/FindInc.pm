package Change::Plugin::FindInc;
use strict;

use base 'Change::Plugin::Base';

use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);
use Util::Message qw(fatal error message alert verbose);
use Util::File::Basename qw(dirname basename);
use Util::File::Functions qw (ensure_path);
use Change::Identity qw(deriveTargetfromName
			lookupName identifyProductionName);
use Change::Symbols qw(USER STAGE_PRODUCTION_LOCN STAGE_PREALPHA 
		       CSCOMPILE_TMP CHECKIN_ROOT FILE_IS_UNCHANGED
		       CSCHECKOUT FINDINC $FINDINC_FILES_LIMIT 
		       MOVE_REGULAR MOVE_EMERGENCY MOVE_IMMEDIATE
		       STAGE_BETA STAGE_PRODUCTION SMRG);
use Change::Set;
use Change::AccessControl qw(getFileLock isStraightThroughLibrary);
use Change::Util::SourceChecks qw (Inc2HdrRequired Inc2HdrGenerated);
use BDE::Util::DependencyCache qw(getCachedGroupOrIsolatedPackage);
use BDE::Util::Nomenclature qw(getCanonicalUOR);
use Term::Interact;

#-----------------
use File::Temp                  qw(tempdir);


#==============================================================================

=head1 NAME

Change::Plugin::FindInc - Find files impacted by header files in change set

=head1 SYNOPSIS

Add files that include headers in the change set for auto-recompilation:

   $ cscheckin -LFindInc nalert/* news/* ...
   $ cscheckin -LFindInc=list nalert/* news/* ...
   $ cscheckin -LFindInc=add nalert/* news/* ...
   $ cscheckin -LFindInc=add,ignoreheader nalert/* news/* ...

Include(and not skip) unchanged header files for findinc processing
   $ cscheckin -LFindInc=forceUnchanged foo/*

Stream candidate change set to a file and read change set from file:

    $ cscheckin -lM -LFindInc=add nalert/* news/* > candidate.set
    <edit candidate.set to remove unwanted files>
    $ cscheckin -a -f candidate.set

Limit the number of files to recompile:

    $ cscheckin -LFindInc --findinclimit 200 news/nalert/*
    $ cscheckin -LFindInc=add --findinclimit 200 news/nalert/*

Donnot add UNCHANGED headers to changeset
     $ cscheckin -LFindInc=add,ignoreheader news/nalert/*

Remove found restricted files the user does not have permission to check in:

    $ cscheckin -LFindInc -LNoRestricted nalert/* news/* ...
    $ cscheckin -LFindInc=add -LNoRestricted nalert/* news/* ...

=head1 DESCRIPTION

C<FindInc> is a plugin to C<findinc>, a SCANT tool that generates a list of
files that include a header. This plugin searches recursively for files that
include a header in a given I<change set> and allows developers to
auto-recompile the files that include the header. The files are added to the
I<change set> for recompilation.

Whenever the C<FindInc> plugin is used, C<--unchanged>/C<-U> and
C<--autoco>/C<-a> options are turned on by default for commits in order that
the found headers can be included for recompilation automatically. (This
behaviour does not apply when using the C<--nocommit>/C<-n> or C<--list>/C<-l>
options).

The --findinclimit option can also be used to limit the maximimum number of 
files to add to a change set for recompilation. If more files than the 
specified maximimum number are found, C<cscheckin> will fail. The current 
default limit is 500. If FindInc returns more than 500 files that need 
recompilation, C<cscheckin> will fail.

=head2 Using FindInc to Generate a Candidate Change Set

The C<FindInc> plugin is consistent with all cscheckin options including
redirecting the output to user specified file. Using the C<--list>/C<-l> and
C<--machine>/C<-M> options, it is possible to stream a candidate change set to
a file and edit the I<change set> prior to submission using C<--from>/C<-f>
option to read it in again.

=head2 Removing Restricted Files from the Change Set

It is possible that some of the files returned by the C<FindInc> plugin are
restricted and may not be checked-in by the user. In this case, the
L<NoRestricted> plugin can be used to automatically filter these files out.

    $ cscheckin -LFindInc -LNoRestricted <files>

It is the responsibility of the user to consider whether or not these files
need to be recompiled, and to contact the owners if so.

=cut

#==============================================================================

sub plugin_usage ($) {
    return join("\n" =>
	      "  FindInc=forceUnchanged Include(an not skip) unchanged headers",
	      "  FindInc=ignoreheader   Do not add UNCHANGED headers ",
	      "  FindInc=prompt   prompt to proceed ",
	      "  FindInc=add      add files for recompilation without prompt ",
	      "  FindInc=list     list dependent files but do not add to cs ",
	      "  FindInc=TSMV     Load FindInc plugin for TSMV users ",
	      "  FindInc=GTK      Add GTK-build dependent files only ",
	      "  --findinclimit  <number>   maximum number of files to"
	      ." add to change set for recompilation ");
}

#------------------------------------------------------------------------------

sub plugin_options ($) {
    return qw[findinclimit=s FindInc=s@];
}

#------------------------------------------------------------------------------

{
    my $term = Term::Interact->new;
    my $files_limit=$FINDINC_FILES_LIMIT;
    my $no_header;
    my @file_list;
    my @ignored_file_list;
    my $file_count=0;
    my $tmpdir="${\CSCOMPILE_TMP}/csplugin/FindInc/${\USER}$$";
    my $checkout_file = "$tmpdir/FindIncGeneratedFileList.set";
    my $ignored_file = "$tmpdir/FindIncIgnoredFiles.txt";
    my $FindInc_opts;


    sub plugin_initialize ($$) {
        my ($plugin,$opts)=@_;

        # Parse FindInc options (add, list, prompt, TSMV, GTK, ignoreheader)
        foreach my $option (map { split /[,=]/,$_ } @{$opts->{plugin}}) {
            $FindInc_opts->{$option}=1 
                if ($option =~ /^(prompt|list|add|TSMV|GTK|ignoreheader|forceUnchanged)$/);
        }

        $FindInc_opts->{prompt}=1 unless ($FindInc_opts->{add});

        # switch on autoco unless nocommit or list are specified.
        $opts->{autoco} = 1 unless ($opts->{nocommit} || $opts->{list});

        $files_limit = $opts->{findinclimit} if (exists $opts->{findinclimit});

        return 1;
    }

#------------------------------------------------------------------------------

    sub getFilesForRecompilation ($$) {
        my ($files, $changeset)=@_;

        my $findinc_args = join ' ' => @$files;

        if (my @files = qx "${\FINDINC} $findinc_args 2>/dev/null") {

            if (@files > $files_limit) {
	        my $file_count = @files;
                error "Exceeded maximum number of files (limit of".
                    " $files_limit but $file_count were found). ".
                    "You can increase the max number of files using ".
                    "--findinclimit option, if you wish to do so.";
                return 0;
            }

	    my %incs;
	    $incs{ $_->getLeafName } = 1 for $changeset->getFiles;
	    my %added;
            foreach my $file_from_findinc (@files) {

		# Get library and file name from findinc output:
		#    lib:file source:include <header>
		# For example:
		#    intlib:file sdsu_mainmenu.c:include <isys_iceberg.h>
                chomp $file_from_findinc;
                my @result;
                unless (@result = (split /[:\s+]/, $file_from_findinc)) {
                    push @ignored_file_list, "FORMAT: $file_from_findinc \n";
                    next;
                }

                my $scantfile = $result[2];
                my $scantlib = $result[0];

		# skip files already in the change set
		next if exists $incs{ $scantfile };

                # Skip UNCHANGED headers if `ignoreheader` is specified
                if (($scantfile=~/\.h$/) && $FindInc_opts->{ignoreheader}) {
                    push @ignored_file_list, "IgnoreHDR: $file_from_findinc \n";
                    verbose "IgnoreHDR: $file_from_findinc \n";
                    next;
                }

                my $tmplib = eval { 
		    deriveTargetfromName ($scantlib, STAGE_PREALPHA) 
		};

                # Skip files in non-robo locations
                unless ($tmplib) {
                    push @ignored_file_list, "NON-ROBO: $file_from_findinc \n";
                    verbose "Ignored NON-ROBO: $file_from_findinc \n";
                    next;
                }

                my $tmpuor = getCanonicalUOR($tmplib);
                my $uor = getCachedGroupOrIsolatedPackage($tmpuor);

                # Skip files in non-cscheckin configured locations
                unless ($tmpuor) {
                    push @ignored_file_list, "NON-CS: $file_from_findinc \n";
                    verbose "ignored NON-CS: $file_from_findinc \n";
                    next;
                }

                # Skip source files in STP locations.
                if (isStraightThroughLibrary ($uor)) {
                    push @ignored_file_list, "STPR: $file_from_findinc \n";
                    verbose "ignored STPR: $file_from_findinc \n";
                    next;
                }

                # Skip wgtsvr dependecy check for GTK dependecy build,
                # This prevents cscompile failure when the same file name 
                # exists in big libraries and wgtsvr (GTK dependent offline).
                # Also, skip source files in non-GTK libraries. No need to 
                # compile test these files.
                if ($FindInc_opts->{GTK}) {
                    next if ($scantlib=~/wgtsvr/);
                    next unless ($uor->isGTKbuild());
                }

                my $file_with_lib = "$tmplib/$scantfile";

                # Skip unless the file referenced in SCANT is
                # actually archived in the repository.
                my @arch_file = 
                    glob "${\STAGE_PRODUCTION_LOCN}/$tmplib/$scantfile,v";
                unless (@arch_file) {
                    push @ignored_file_list, "NO-,v: $file_from_findinc \n";
                    next;
                }

		if (exists $added{ $scantfile }) {
		    verbose "Already present: $scantfile, scant-lib:$tmplib";
		    # file found lets move on.
		    next;
		}

		print STDERR "$file_with_lib \n";
		push @file_list, $file_with_lib;
		$added{ $scantfile } = 1;
		$file_count++;
            }
        } else {
            unless (!$?) {
                error "${\FINDINC} $findinc_args failed. ".
                    "Please try running findinc on the command line";
                return 0;  # return 0 for failure
            }
        }

        return 1;    # return 1 for success
    }

    # Return of 0 means unchanged headers, 1 means changed.
    sub are_ml_headers_changed($) {
        # create a tmp dir.
        # run smrg stuff to generate.
        # diff headers with /bbsrc/proot/prebuild/prodins
	##<<<FIXME should not hard-code this path
        my $bfile=shift;
        my $source = basename($bfile);
        my $tmpdir = tempdir(DIR => '/bb/data/tmp', CLEANUP => 1);
        my $cmd = "cp $bfile $tmpdir && cd $tmpdir && ".SMRG." $source.error -batch $source -robo";
        my $rcode = system($cmd);

        # return good even though smrgNT did not work.
        # it may not be worth the effort to fatally exit so lets move on.
        # 0 means unchanged headers, 1 means changed.
        return 0 if $rcode!=0;

        my $h_file=$source; $h_file=~s/\..+/_ins.h/;
        my $ins_file=$source; $ins_file=~s/\..+/.ins/;
        my $cmd2="cd $tmpdir && diff $h_file /bbsrc/proot/prebuild/prodins/ >/dev/null && \
                  diff $ins_file /bbsrc/proot/prebuild/prodins/ >/dev/null";
        $rcode = system($cmd2);
        return $rcode;
    }

    sub get_headers {
        my $cs = shift;

        my @files;
        for my $file ($cs->getFiles) {

            my $src = $file->getSource;
            my $lib = $file->getLibrary;

            if (!$FindInc_opts->{forceUnchanged} and $file->isUnchanged) {
                verbose "FindInc: skipping unchanged file $file";
                next;
            }

            # No GTK dependency check for headers that live in 
            # units of release (uor) that do not depend on GTK build
            if ($FindInc_opts->{GTK}) {
                my $tmpuor = getCanonicalUOR($lib);
                my $uor = getCachedGroupOrIsolatedPackage($tmpuor);
                if (!$uor->isGTKbuild()) {
                    verbose "FindInc: skipping non-GTK file $file for GTK findinc";
                    next;
                }
            }

            if ($src =~ /\.inc$/) {
                verbose "FindInc: adding file " . basename($src);
                push @files, basename($src);
                if (Inc2HdrRequired($file)) {
                    (my $h = basename($src)) =~ s/\.inc$/.h/;
                    verbose "FindInc: adding derived file $h";
                    push @files, $h;
                }
            } elsif ($src =~ /\.h$/) {
                if (Inc2HdrGenerated($src)) {
                    error "FindInc: $src is autogenerated - skipping";
                    next;
                }
                verbose "FindInc: addomg " . basename($src);
                push @files, basename($src);
            } elsif ($src =~ /\.gob$/) {
                verbose "FindInc: adding file " . basename($src);
                push @files, basename($src);
            } 
            elsif ($src =~ /\.ml$/) {
                # invoking this code because headers have timestamp field
                # and that get changed even 
                my $smart_check = are_ml_headers_changed($src);
                if(!$FindInc_opts->{forceUnchanged} && $smart_check == 0) {
                    verbose "ml headers are not unchanged. skipping";
                    next;
                }
                verbose "FindInc: adding " . basename($src);
                # findinc.pl is smart enough to translate
                # .ml files into .ins and _ins.h
                push @files, basename($src);
            }
        }

        return @files;
    }

    sub plugin_post_find_filter ($$) {
        my ($plugin,$changeset)=@_;

        my $move_type = $changeset->getMoveType();
        $move_type ||= MOVE_REGULAR;
        if ($move_type eq MOVE_IMMEDIATE) {
            alert "Bypassing FindInc for headers in STP units of release.";
            return 1;
        }

        alert "Searching for files that need recompilation";
        my @headers = get_headers($changeset);

	alert "Found " . @headers . " changed header(s) to pass to findinc";

        my $rcode = @headers ? getFilesForRecompilation(\@headers, $changeset) : 1;

        return 0 unless ($rcode); # return failure if any so far
        unless ($file_count) { # return success if no files are found
            alert "There are no files that need recompilation";
            return 1;
        }

        return $rcode if ($FindInc_opts->{list});

        if ($file_count eq 1) {
            alert "There is 1 file that needs recompilation due to ".
                "header change";
        } else {
            alert "There are $file_count files that need recompilation due to ".
                "changes to headers in this change-set. Files in Non-source ".
                "controlled (NON-ROBOISED) offlines are NOT included.";
            alert "Files that need recompilation are listed in $checkout_file";
            alert "Excluded files will be listed in $ignored_file";
        }

        my $candidateset = new Change::Set({
                plugin=>$plugin,
                stage=>$changeset->getStage(),
                when=>$changeset->getTime(),
                user=>$changeset->getUser(),
                group=>$changeset->getGroup(),
                ctime=>$changeset->getCtime(),
                move=>$changeset->getMoveType(),
                status=>$changeset->getStatus(),
                message=>$changeset->getMessage(),
                depends=>$changeset->getDependencies(),
                reference=> { $changeset->getReferences() },
                });

        foreach my $file (@file_list) {
            my $basefile=basename($file);
            my $scantlib=dirname($file);
            my $localfile ="$tmpdir/$basefile";

            my $target = deriveTargetfromName($scantlib,${\STAGE_PREALPHA});
            my $prdlib= identifyProductionName($target,${\STAGE_PREALPHA});
            my $dest = "${\CHECKIN_ROOT}/$basefile";
            my $lib=lookupName($target, ${\STAGE_PREALPHA});
            $candidateset->addFile($target,$localfile,$dest, FILE_IS_UNCHANGED,
                    $lib,$prdlib);
        }

        # (make sure umask is consistent on files and directories created)
        umask(0002);

        # Ensure tmpdir (/bb/csdata/tmp/Findinc/USER$$...) exists
        ensure_path ($tmpdir) || die"Failed to create $tmpdir ".
            "- cannot proceed";

        # Putting files that need compilation in a tmp file for use by cscheckout
        my $fh=new IO::File("> $checkout_file") || 
            die "cannot open file: " . $!;
        print $fh $candidateset->listChanges();
        $fh->close;

        # Putting files obtained from scant but not added to chage-set 
        # in to a tmp file
        $fh=new IO::File("> $ignored_file") || 
            die "cannot open file: " . $!;
        print $fh @ignored_file_list;
        $fh->close;

        if ($term->isInteractive || ($FindInc_opts->{TSMV})) {
            my $y=($FindInc_opts->{prompt} ? $term->promptForYN
                    ("Do you want to add these files to this changeset (y/n)? ", 1)
                    : "y");
            return $rcode unless ($y); # Don't add files to change set unless "y"
        }

        message "Adding files to changeset. Please wait...";
        foreach my $file ($candidateset->getFiles()) {
            $changeset->addFile($file);
        }

        # Copyout latest files (scm, emov, bugf, regular) using cscheckout
        $move_type = $changeset->getMoveType();
        $move_type ||= MOVE_REGULAR;
        my $cmd="${\CSCHECKOUT} -n -c --do=none --noaddrcsid -f $checkout_file".
            " --$move_type";

        if ($changeset->isEmergencyMove() and
            $changeset->getStage() ne STAGE_PRODUCTION)
        {
            $cmd .= " --beta";
        }

        verbose "CSCHECKOUT cmd = $cmd \n";
        qx "cd $tmpdir; $cmd";
        return $rcode;
    }
}
#==============================================================================

1;

=head1 AUTHOR

Dawit Habte (Dawit@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Plugin::Example>, L<cscheckin>

=cut
