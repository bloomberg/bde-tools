#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
#use Cwd qw(abs_path);
use File::Path qw(mkpath);
use Util::File::Basename qw(basename);

use BDE::Build::Invocation qw($FS $FSRE);
use BDE::FileSystem;
use BDE::Util::Nomenclature qw(getType);
use Symbols qw(
    ROOT INDEX_DIR IS_FUNCTION IS_DEPARTMENT
    EXIT_SUCCESS EXIT_FAILURE
);
use Util::Message qw(message verbose alert verbose_alert debug warning fatal);

#==============================================================================

=head1 NAME

bde_index.pl - Create or rebuild index directories

=head1 SYNOPSIS

  # Check and update everything under default root
  $ bde_index.pl

  # With an explicit explicit root
  $ bde_index.pl -w /home/mylogin/bderoot

  # Check only
  $ bde_index.pl --check

  # Update only
  $ bde_index.pl --update

  # Restrict update to specified department
  $ bde_index.pl --department fi --nocheck

  # Report more information on what the tool is doing
  $ bde_index.pl -v

=head1 DESCRIPTION

C<bde_index.pl> examines the index directories of functions and department
libraries below the current root (specified by -w or BDE_ROOT) and checks their
contents for validity. A valid index entry is a symbolic link to an identically
named function or department directory in an immediately adjacent department
directory. In addition, any functions or department libraries that exist in a
department directory but which are not entered into the index will have their
index links created. Without arguments, a full check and update of all
department directories for both functions and department libraries is carried
out.

C<bde_index.pl> is reasonably tolerant of links used in place of real
directories. A link in the index directory should only point to a similarly
named entry in an adjacent department directory, but that entry is
allowed to be either a real directory or a link elsewhere. Similarly, the
top level department directory may itself be a link if required.

To carry out an index check only, specify C<--check> or C<--noupdate>. To
carry out an index update only, specify C<--update> or C<--nocheck>. To
restrict an index update to a specific department, specify C<--department> or
C<-D> with the name of the department directory.

Additional information about what directories or links are being checked
and created can be extracted with C<--verbose> or C<-v>.

=head1 NOTES

C<bde_setup.pl> can create directories for functions and department libraries
in the appropriate department directory and will set up an index link
automatically. Regular use of that tool should obviate the need to use this
one.

=head1 TO DO

Currently there is no way to restrict checks or updates to just functions or
just department libraries. This may be supported in future.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-d] [-v] [-c | -u] [-D <dept>] [-w <dir>]
  --[no]check   | -c           [do not] check existing contents of index dirs
  --debug       | -d           enable debug reporting
  --department  | -D <dept>    department for creating f_ and l_ units
  --help        | -h           usage information (this text)
  --[no]update  | -u           [do not] update indices from department dirs
  --verbose     | -v           enable verbose reporting
  --where       | -w <dir>     specify existing/desired root

See 'perldoc $prog' for more information.

_USAGE_END
}

sub getoptions {
    my %opts = (
       check  => 2,
       update => 2,
    );

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
        help|h
        check|c!
        debug|d+
        department|D=s
        where|root|w|r=s
        update|u!
        verbose|v+
    ])) {
        usage("Arfle barfle gloop?");
        exit EXIT_FAILURE;
    }

    # help
    usage(), exit EXIT_SUCCESS if $opts{help};

    # mode - check, update, or both
    if ($opts{check}==1 and $opts{update}==2) { $opts{update}=0; }
    if ($opts{check}==2 and $opts{update}==1) { $opts{check}=0;  }
    unless ($opts{check} or $opts{update}) {
	usage("Disabling both --check and --update is pointless");
	exit EXIT_FAILURE;
    }

    if ($opts{department} and not $opts{update}) {
	usage("Specifing a department without --update is pointless");
	exit EXIT_FAILURE;
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    # filesystem root
    $opts{where} = ROOT unless $opts{where};

    return \%opts;
}

#------------------------------------------------------------------------------

sub isInDepartment ($) {
    my $item=shift;

    return getType($item) & (IS_DEPARTMENT|IS_FUNCTION);
}

#------------------------------------------------------------------------------

# check index directory. Warn about any unexpected entries, return list of
# valid entries found (if any). If $fc (full check) is false, just find the valid
# entries and don't bother with anything else.
sub check_index ($$$;$) {
    my ($type,$path,$indexsubdir,$fc)=@_;
    #my $abspath=abs_path($path);
    my @valid=();

    # verify existence of index directory
    my $indexdir=$path.$FS.$indexsubdir;

    verbose_alert "Checking $indexdir" if $fc;

    unless (-d $indexdir) {
	if (-e $indexdir) {
	    fatal "$indexdir is not a directory\n";
	} else {
	    mkpath $indexdir or fatal "Unable to create $indexdir: $!";
	}
    }

    # validate current contents of index directory
    my $dh=new IO::Handle;
    opendir $dh,$indexdir or fatal "Unable to open $indexdir: $!";
    while (my $entry=readdir $dh) {
	next if $entry=~/^\./; #ignore any dotfiles
	my $filetype=((-d $indexdir.$FS.$entry)?"Directory":
		      (-l $indexdir.$FS.$entry)?"Link":"File");

	debug "Considering $entry..." if $fc;

	if (my $etype=getType($entry)) {
	    if ($etype == $type) {
		if (-l $indexdir.$FS.$entry) {
		    my $truepath=readlink($indexdir.$FS.$entry);
		    if ($truepath) {
			$truepath=$indexdir.$FS.$truepath
			  if substr($truepath,0,1) ne $FS;
			1 while $truepath =~ s|${FSRE}\w+${FSRE}\.\.${FSRE}|$FS|;

			unless (-e $truepath || -l $truepath) {
			    warning "'$entry' points to $truepath *BROKEN LINK*" if $fc;
			} elsif ($truepath=~/^$path${FS}(\w+)${FS}$entry/) {
			    verbose "Index entry '$entry' OK" if $fc;
			    push @valid,$entry;
			} else {
			    warning "'$entry' points outside root to '$truepath'" if $fc;
			}
		    } else {
			warning "'$entry' points nowhere" if $fc;
		    }
		} elsif (-d $indexdir.$FS.$entry) {
		    warning "Found directory not index link for '$entry'" if $fc;
		} else {
		    warning "File '$entry' not an index link" if $fc;
		}
	    } else {
		warning "$filetype '$entry' does not belong in $indexdir" if $fc;
	    }
	} else {
	    warning "$filetype '$entry' does not belong in $indexdir" if $fc;
	}
    }
    closedir $dh,$indexdir or fatal "Unable to close $indexdir: $!";

    verbose "Found valid entries: @valid" if $fc;
    return wantarray ? @valid : \@valid;
}

sub update_index ($$$$;$) {
    my ($type,$path,$deptsubdir,$existing,$indexsubdir)=@_;
    my @created=();
    my %existing = map { $_ => 1 } @$existing;

    # verify existence of index directory
    my $indexdir=$path.$FS.$indexsubdir;
    my $deptdir=$path.$FS.$deptsubdir;

    unless (-d $indexdir) {
	if (-e $indexdir) {
	    fatal "$indexdir is not a directory\n";
	} else {
	    fatal "$indexdir does not exist";
	}
    }
    unless (-d $deptdir) {
	if (-e $deptdir) {
	    fatal "$deptdir is not a directory\n";
	} else {
	    warning "$deptdir does not exist";
	    return wantarray ? () : [];
	}
    }

    verbose_alert "Updating index for $deptdir";

    my $dh=new IO::Handle;
    opendir $dh,$deptdir or fatal "Unable to open $deptdir: $!";
    while (my $entry=readdir $dh) {
	next if $entry=~/^\./; #ignore any dotfiles
	my $filetype=((-d $deptdir.$FS.$entry)?"Directory":
		      (-l $deptdir.$FS.$entry)?"Link":"File");

	debug "Considering $entry...";

	if (my $etype=getType($entry)) {
	    if ($etype == $type) {
		if ($filetype eq "Directory" or $filetype eq "Link") {
		    if ($existing{$entry}) {
			verbose "'$entry' already present in index";
		    } else {
			symlink($deptdir.$FS.$entry, $indexdir.$FS.$entry) or
			  fatal "Could not link $deptdir$FS$entry "
			        ."to $indexdir$FS$entry: $!";
			push @created, $entry;
		    }
		} else {
		    warning "File '$entry' not a directory or a link";
		}
	    } else {
		warning "$filetype '$entry' does not belong in $deptdir";
	    }
	} else {
	    warning "$filetype '$entry' does not belong in $deptdir";
	}
    }
    closedir $dh,$deptdir or fatal "Unable to close $deptdir: $!";

    if (@created) {
	alert "Created new '$deptsubdir' index for: @created";
    } else {
	verbose "No new index entries created for $deptdir";
    }
    return wantarray ? @created : \@created;
}

#------------------------------------------------------------------------------

MAIN: {
    my $opts=getoptions();
    my $root=new BDE::FileSystem($opts->{where});

    verbose_alert "Rebuilding indices under $root";
    foreach my $type (IS_DEPARTMENT,IS_FUNCTION) {
	my $path=($type == IS_DEPARTMENT) ? $root->getDepartmentsLocation()
	  : $root->getFunctionsLocation();
	my $INDEX_DIR=INDEX_DIR;
	$path=~s/${FS}$INDEX_DIR$//;

	my $validentries=check_index($type,$path,INDEX_DIR,$opts->{check});
	if ($opts->{update}) {
	    if ($opts->{department}) {
		update_index($type,$path,$opts->{department},
			     $validentries,INDEX_DIR);
	    } else {
		my $dh=new IO::Handle;
		opendir $dh, $path or fatal "Unable to open $path: $!";
		while (my $adjacent=readdir $dh) {
		    next if $adjacent=~/^\./; #ignore any dotfiles
		    next if $adjacent eq INDEX_DIR;
		    my $filetype=((-d $path.$FS.$adjacent)?"Directory":
				  (-l $path.$FS.$adjacent)?"Link":"File");
		    next unless $filetype eq "Directory" or $filetype eq "Link";
		    update_index($type,$path,$adjacent,$validentries,INDEX_DIR);
		}
	    }
	}
    }
    verbose_alert "Done.";
}

#==============================================================================

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<bde_setup.pl>

=cut
