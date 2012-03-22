#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
BEGIN {
    $FindBin::Bin =~/^(.*)$/ and $FindBin::Bin=$1;
    $ENV{PATH}="/usr/bin:$FindBin::Bin";
    foreach (sort keys %ENV) {
	delete($ENV{$_}),next unless /^(BDE_|CHANGE_|PRODUCTION_|GROUP$|PATH|$)/;
	$ENV{$_}=~/^(.*)$/ and $ENV{$_}=$1;
    }
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use File::Find;
use File::Temp      qw/tempfile tempdir/;

use Symbols                         qw/EXIT_SUCCESS EXIT_FAILURE/;
use Change::Symbols                 qw/STATUS_ROLLEDBACK $STATUS_SUBMITTED 
                                       $STATUS_ACTIVE $STATUS_WAITING 
                                       $STATUS_INPROGRESS $STATUS_COMPLETE/;

use Util::Message                   qw/message fatal warning error alert debug/;
use Util::File::Functions           qw/ensure_path/;
use Production::Services::ChangeSet qw/getChangeSetDbRecord/;
use Production::Services;
use Change::Util::InterfaceSCM      qw/recoverFilesSCM
                                       recoverCurrentSCM
                                       recoverPriorSCM
                                       recoverListSCM
                                       csidIsStagedSCM/;

#==============================================================================

=head1 NAME

csrecover - Recover the files from a submitted or active change set:

=head1 SYNOPSIS

Recover change set files into current directory using full original paths:

    $ csrecover 428E32AD001476E94D

Recover change set files directly (i.e. flat) into current directory:

    $ csrecover -f 428E32AD001476E94D

Recover change set files into a CSID directory in the current directory:

    $ csrecover -i 428E32AD001476E94D

Recover change set files, flat, into a CSID directory:

    $ csrecover -i -f 428E32AD001476E94D

Recover the current revisions or staged copies of the files in the changeset:

    $ csrecover -C 428E32AD001476E94D

Recover the current revisions, ignoring any staged copies:

    $ csrecover -C -R 428E32AD001476E94D

Recover the file revisions immediately prior to the change set:

    $ csrecover -p 428E32AD001476E94D

Recover the latest revision of a file if it is newer than the change set
revision, or the prior revision otherwise:

    $ csrecover -p -C 428E32AD001476E94D

=head1 DESCRIPTION

C<csrecover> allows the files in a change set to be copied back to the current
directory. Files can be recovered from the staging area, the most recent
revision of a file in the archive, or the revision associated with the
requested change set ID (or IDs).

As with all C<cs> tools, options may be bundled and placed before or after the
CSID argument. More than one CSID argument may also be specified. For example,
this recovers three changesets into flat directories named for each change
set ID:

    $ csrecover 428E32AD001476E94D 4223E2DA001476E94E 4289912DA0014762AE3 -fi

Change set IDs are ordered prior to querying, so if two historical change sets
contain files that overlap, the more recent file version will be recovered.

=head2 File Origin Modes

C<csrecover> allows files to be recovered from the staging area, from
the revisions associated with the change set, from the current revision of
the files associated with the change set, or from the immediately prior version
of the files in the change set.

It can also recover files from several of these areas depending on the use
of the C<--released>, C<--current>, and C<--previous> options, conditioned by
whether the change set is still staged or has been released.

=over 4

=item If the change set has already been processed (a.k.a 'swept'):

=over 4

=item * By default, the historical revision associated with each file in the
        change set is recovered.

=item * If the C<--current> or C<-C> option is used, the most recent revision
        of each file is fetched. If the file is currently staged (as part of
        a more recent change), the staged file is retrieved, unless the
        C<--released> or C<-R> option is used to suppress retrieving files
        from the staging area.

=item * If the C<--previous> or C<-p> option is used, the revision immediately
        prior to the revision associated with the change set is recovered.
        Files in the staging area are ignored. This mode can be used to
        undo a changeset after it has been processed, but might clobber
        changes made to files after the change set was originally submitted.

=item * If both C<--current> and C<--previous> are specified, then the current
        revision is retrieved I<if it is newer than the revision associated
        with the change set>, otherwise the prior revision is retrieived. Files
        in the staging area are retrieved unless C<--released> or C<-R> is
        used, as for C<--current>. This mode can be used to attempt to undo
        a changeset after it has been processed, but without wiping out more
        recent changes that might have been made to files in the change set
        after the change set of inspection was originally submitted.

=back

=item If the change set is still staged:

=over 4

=item * By default, the staged files that form part of the change set are
        recovered.

=item * If the C<--released> option is used, then the last revision processed
        is retrieved (i.e., the current released revision).

=item * C<--previous> is synonymous with C<--released>, since the previous
        version of the staged file is the most recent revision processed.

=item * C<--current> has no effect.

=back

=back

=head2 File Destination Modes

C<csrecover> provides two output modes, I<flat>, and I<structured>. Of the
two, structured mode is the more powerful.

=over 4

=item Flat Recovery

A flat recovery places all files into the current directory (or if the C<--id>
or C<-i> option is used, a change set ID subdirectory) irrespective of the
location that the file were originally destined for. This is convenient
mostly for change sets that involve only one target directory.

=item Structured Recovery

A structured recovery recreates the directory structure of the source files,
but placed under the current working directory.

If the current working directory does not coincide with the paths of the source
files, then the source files are placed under a directory structure that
replicates the whole path up to the root. If, however, the current working
directory forms the prefix of any file in the change set, it is stripped from
the source path prior to reconstruction.

This means that if developer C<one> recovers into their workspace a change set
originally submitted by developer <two>, and uses the C<--id> option to insert
the change set ID as a directory, the recovered directory structure will
resomble something like this:

    Checked in:              /home/two/twoswpro/acclib/que.c
    'csrecover -i' run from: /home/one/mywork
    Recovered file:          /home/one/mywork/<CSID>/two/twoswork/acclib/que.c

This is because C</home> is the common path in this case. If developer two
recovers their own change set, the structure will instead look like this:

    Checked in:             /home/two/twoswpro/acclib/que.c
    csrecover -i' run from: /home/two/twoswork
    Recovered file:         /home/one/twoswork/<CSID>/acclib/que.c

If the C<--id> option is I<not> used, this second case will cause the recovered
files to be copied back into the exact locations they were originally checked
in from. Note that this will overwrite any existing versions of those files if
they are present.

=head2 File Version Information

C<csrecover> can list file-information pertaining both to SCM (C<--list>) and
RCS (C<--rcs>). In SCM mode, each path will be qualified with one or more
of the following keywords:

=over 4

=item * staged

The file is staged.

=item * new

The file is new (either staged or new in SCM).

=item * previous

The file version is that prior to the CS version.

=item * head

The file version is the head of the SCM repository.

=item * current

The file version is the current version (meaning it is either staged or the
head of the SCM repository and no staged version is present)

=back

A file qualified as C<(staged,new)> is therefore a new file that is staged. A
file qualified as C<new,current,head> is a file that was new in SCM for
the changeset which suppied it, is the current head of the SCM repository, and
has no newer version staged.

The C<--rcs> option will give you the RCS-ID of the file version prior
to the given CSID, the RCS-ID assiocated with the RCS-ID and the RCS-ID
of head.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = "csrecover"; #basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-l | [-f] [-i]] [-R] [-C] [-p] [-P|-M] <csid> [<csid>...]
  --debug       | -d              enable debug reporting
  --help        | -h              usage information (this text)
  --verbose     | -v              enable verbose reporting

File destination options:

  --flat        | -f              copy all files into the current directory
                                  (or change set directory, with --id)
  --id          | -i              place all files/directories under a
                                  directory named for the change set ID
  --list        | -l              list file origins and versions without
                                  extracting them
  --rcs         | -r              print RCS information
  --unexpand    | -U              unexpand RCS IDs (remove the expanded RCSid)

File origin options:

  --current     | -C              extract the current rather than historical
                                  revision when retrieving a released change
                                  set.
  --previous    | -p              extract the previous revision to the
                                  historical revision associated with the
                                  change set. See manual page for using -C and
                                  -p together.
  --released    | -R              ignore staged files, look only in archives
  --staged      | -S              include staged staged files (default).

Display options:

  --pretty      | -P              list changes in human-parseable output
                                  (default if run interactively)
  --machine     | -M              list changes in machine-parseable output
                                  (default if run non-interactively)

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        debug|d+
        flat|f
        help|h
        id|i
        list|l
        rcs|r
        machine|M
        current|C
        pretty|P
	previous|p
        released|R
        staged|S
	unexpand|U
        verbose|v+

    ])) {
        usage();
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # no arguments
    usage, exit EXIT_FAILURE if @ARGV<1 and not $opts{list};

    # pretty/machine
    if ($opts{pretty} and $opts{machine}) {
	usage("--pretty and --machine are mutually exclusive");
	exit EXIT_FAILURE;
    }
    unless ($opts{pretty} or $opts{machine}) {
	if (-t STDIN) { $opts{pretty}=1; } else { $opts{machine}=1; }
    }

    # released/staged
    if ($opts{staged} and $opts{released}) {
	usage("--released and --staged are mutually exclusive");
	exit EXIT_FAILURE;
    }

    # list mode
    if ($opts{list} and ($opts{flat} or $opts{id})) {
	warning "--flat and --id have no effect when specified with --list";
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

sub recoverFiles {
    my ($cs, %opts)=@_;

    my $csid    = $cs->getID();
    my $status  = $cs->getStatus();
    my $move    = $cs->getMoveType();


    my (undef, $tarball) = do {
        local $^W;
        tempfile(OPEN => 0, CLEANUP => 1);
    };
    
    my ($ok, $error);
    if ($opts{current}) {
        if ($opts{previous}) {
            ($ok, $error) = recoverPriorSCM($cs, $tarball, $move, 1);
        } elsif ($opts{released}) {
            ($ok, $error) = recoverCurrentSCM($cs, $tarball, $move, 0);
        } else {
            ($ok, $error) = recoverCurrentSCM($cs, $tarball, $move, 1);
        }
    } elsif ($opts{previous}) {
        ($ok, $error) = recoverPriorSCM($cs, $tarball, $move, 0);
    } elsif ($opts{released}) {
        ($ok, $error) = recoverCurrentSCM($cs, $tarball, $move, 0);
    } else {
        ($ok, $error) = recoverFilesSCM($cs, $tarball);
    }

    return $tarball if $ok;
    
    error $error;
}

sub unpackTarball {
    my ($tarball, $csid, %opts) = @_;

    my $scratch = tempdir(CLEANUP => 0);

    system("cd $scratch && gunzip -c $tarball | tar xf -") == 0
        or return (undef, "Error unpacking $tarball: $!, $?");

    my $dir = '.';

    mkdir $csid or return (undef, "Cannot create directory $csid: $!")
        if $opts{id} and not -d $csid;
    
    $dir = $csid if $opts{id};

    my $callback = sub {
        return if -d $File::Find::name;
        return if $_ eq "$scratch/meta";

        my ($targetdir) = $File::Find::dir =~ m#^$scratch/(.*)#;
        my $destdir = $dir;
        $destdir .= "/$targetdir" if not $opts{flat};

        ensure_path($destdir);
        
        system("cp $_ $destdir") == 0
            or die "Could not copy $_ to $destdir: $!, $?";
    };

    eval {
        find({ no_chdir => 1, wanted => $callback, }, $scratch);
    };

    return (undef, $@) if $@;
    return 1;
}

sub inspectRCS {
    my ($cs) = @_;

    require Change::Util::InterfaceRCS;
    Change::Util::InterfaceRCS->import(qw/getFileVersions/);

    my $prefix = '/bbsrc/lroot';

    my $info;
    for ($cs->getFiles) {
        (my $file = getCanonicalPath($_)) =~ s#^root/##;
        $info->{$file} = [ getFileVersions("$prefix/$file", $cs->getID) ];
        $info->{$file}[$_] ||= '<no ID>' for 0 .. 2;
    }
    return $info;
}


#----

MAIN: {
    my $opts = getoptions();

    my %opts_retrieve;
    my %opts_unpack;

    @opts_retrieve{ qw/previous current staged released/ } =
        @$opts{ qw/previous current staged released/ };
    @opts_unpack{ qw/flat id list unexpand/ } =
        @$opts{ qw/flat id list unexpand/ };

    my $tarball;
    my $svc = new Production::Services();

    CSID: foreach my $csid (@ARGV) {

	my $changeset = getChangeSetDbRecord($svc, $csid);
    
        if (not defined $changeset) {
	    warning "Change set $csid not found in database - ignored";
            next;
        }

        if (-t STDIN) {
            message "change set $csid is ".
              (csidIsStagedSCM($csid) ? "staged" : "processed");
        }


        if ($opts->{list} || $opts->{rcs}) {
            require Change::Util::Interface;
            Change::Util::Interface->import(qw/getCanonicalPath/);
            my @files = map getCanonicalPath($_), $changeset->getFiles;
            s#^root/## for @files;

            my ($scminfo, $rcsinfo);
            
            if ($opts->{list}) {
                ($scminfo, my $err) = recoverListSCM($changeset);
                error "No SCM info available for $csid" if defined $err;
            }

            $rcsinfo = inspectRCS($changeset) if $opts->{rcs};

            my $len = max(@files);
            my $template = $opts->{rcs} 
                ? "%-${len}s  (%s)\n" .  
                  "  RCS ID prior $csid: %s\n" . 
                  "  RCS ID for $csid: %s\n" .
                  "  RCS ID for head: %s\n"
                : "%-${len}s  (%s)\n";

            for (sort @files) {
                printf $template, $_, join(',', @{$scminfo->{$_} || []}), 
                                                @{$rcsinfo->{$_} || []};
            }
            next CSID;
        }

        $tarball = recoverFiles($changeset, %opts_retrieve);
        if ($tarball and not $opts_unpack{list}) {
            my ($ok, $err) = unpackTarball($tarball, $csid, %opts_unpack);
            if ($ok) {
                alert "Change set $csid recovered" if -t STDIN;
            } else {
                fatal "Failed to extract tarball: $err";
            }
        }
    }

    exit EXIT_SUCCESS;
}

sub max {
    my $len = 0;
    length > $len and $len = length for @_;
    return $len;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<bde_querycs.pl>, L<bde_findcs.pl>

=cut
