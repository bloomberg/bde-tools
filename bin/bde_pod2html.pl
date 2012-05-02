#!/usr/bin/env perl

require v5.8;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Getopt::Long;
use Pod::Html;
use File::Find;
use File::Path;

use Util::File::Basename qw(basename);
use Util::Message qw(verbose debug fatal);

use Symbols qw(EXIT_SUCCESS EXIT_FAILURE USER);

#==============================================================================

=head1 NAME

bde_pod2html.pl - Convert BDE Perl POD documentation into HTML manual pages

=head1 SYNOPSIS

    $ bde_pod2html.pl                  # convert all default files and install
                                       # HTML into the default location
    $ bde_pod2html.pl module.pm dir    # convert named files and directories
    $ bde_pod2html.pl --list           # list all files that would be converted
    $ bde_pod2html.pl --to /tmp        # specify output directory for HTML
    $ bde_pod2html.pl --user sventek   # specify other user's default directory
                                       # (not with --to)

=head1 DESCRIPTION

F<bde_pod2html.pl> generates HTML manual pages for the BDE tools and the BDE
Perl Infrastructure. By default, it scans the Perl source adjacent to the
script and creates HTML pages in the invoking user's F<public_html> directory.

An arbitrary list of directories and/or files can be supplied to have
F<bde_pod2html.pl> convert those files instead of carrying out the default
search. Directories are recursed into, and any files ending in C<.pl>, C<.pm>,
or C<.pod> are converted.

Use the C<--list> or C<-l> option to cause the tool to generate a list of the
files that it would convert, instead of carrying out the conversion. Use the
C<--to> or C<-t> option to change the destination directory for HTML pages,
or C<--user> or C<-u> to change just the name of the user whose F<public_html>
directory will be used as the destination.

=cut

#==============================================================================

sub usage(;$) {
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    print <<_USAGE_END;
Usage: $prog -h | [-l] [-d] [-v] [-t <dir>|-u <user>] [<directory|file> ...]
  --debug       | -d           enable debug reporting
  --help        | -h           usage information (this text)
  --list        | -l           list files that would be converted rather than
                               converting them.
  --quiet       | -q           do not display mostly harmless warnings.
  --to          | -t <dir>     specify output directory for HTML
                               default: /home/${\USER}/public_html
  --htmlroot    | -H <url>
  --cachedir                   pod2html temporary directory
  --user        | -u <user>    specify user for default output directory
                               default: ${\USER}
  --verbose     | -v           enable verbose reporting

If no explicit directory or file is specified, the Perl source relative to
the location from which $prog is run is used.

See "perldoc $prog" for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub getoptions {
    my %opts;

    Getopt::Long::Configure("bundling");
    unless (GetOptions(\%opts, qw[
	cachedir=s
        debug|d+
        help|h
        list|l
        quiet|q
        to|t=s
	htmlroot|H=s
        user|u=s
        verbose|v+
    ])) {
        usage();
        exit EXIT_FAILURE;
    }
  
    # help
    usage(), exit EXIT_SUCCESS if $opts{help};
  
    # nothing to do
    unless (@ARGV) {
        @ARGV = ($FindBin::Bin,
                "$FindBin::Bin/../lib/perl",
                "$FindBin::Bin/../lib/perl/site-perl");
        s|/[^/]+/../|/|g foreach @ARGV;
    }

    $opts{user} = USER unless defined $opts{user};
    if ($opts{user} eq "noname") {
        fatal "User unknown";
    }

    #default destination directory 
    $opts{to} = "/home/$opts{user}/public_html" unless defined $opts{to};

    unless ($opts{htmlroot}) {
        $opts{htmlroot}="http://sundev3.bloomberg.com/~$opts{user}";
    }

    # debug mode
    Util::Message::set_debug($opts{debug} || 0);

    # verbose mode
    Util::Message::set_verbose($opts{verbose} || 0);

    return \%opts;
}

#------------------------------------------------------------------------------

# File::Find closure
{
    my @perlfiles;
    my %exclusions = map { $_ => 1 } qw[
        Attic
        attic
    ];

    sub findfiles (@) {
        @perlfiles=();

        find(\&wanted, @_);

        return @perlfiles;
    }

    sub wanted {
        if (-d $File::Find::name) {
            $File::Find::prune=1 if exists $exclusions{$_};
        } elsif (-f _) {
          push @perlfiles, $File::Find::name if /.*\.(pl|pm|pod)$/;
        }
    }
}

#------------------------------------------------------------------------------

sub makeTargetDirectory {
    my ($source, $podroot, $htmldir) = @_;
    my $file = basename $source;

    $source =~ s!^$podroot/!!;
    $source =~ s!/$file$!!;

    mkpath "$htmldir/$source"  unless -d "$htmldir/$source";

    return $source;
}

#---------

sub read_content ($) {
    my $file=$_[0];
    open FILE, $file or die "Unable to open $file for reading: $!\n";

    local $/=undef;
    my $content=<FILE>;
    close FILE; 

    return $content;
}

#---

sub add_index_links (\$$) {
    my $links=<<_LINKS_END;
<a href="$_[1]->{htmlroot}">Home</a> | <a href="$_[1]->{htmlroot}/bin">Tools</a> | <a href="$_[1]->{htmlroot}/lib/perl">Modules</a>
_LINKS_END

    ${$_[0]} =~ s|(<body [^>]+>)|$1\n$links<br><br>|;
    ${$_[0]} =~ s|(</body>)|\n<br><a href="#top">Top</a> \| $links$1|;
}

sub add_short_anchor_names (\$$) {
    ${$_[0]} =~ s|<a name="(([^"]+?)__[^"]+)">|<a name="$1"></a><a name="$2">|g;
}

sub fix_manpage_links (\$$) {
    ${$_[0]} =~ s|(<a href=[^>]+>)the ([^<]+) manpage(</a>)|$1$2$3|g;
}

sub fix_script_links (\$$) {
    ${$_[0]} =~ s|<em>(\w+)\.pl</em>|<a href="$_[1]->{htmlroot}/bin/$1.html">$1.pl</a>|g;
    ${$_[0]} =~ s~<em>((?:cs|bde)\w+)</em>~<a href="$_[1]->{htmlroot}/bin/$1.html">$1</a>~g;
}

sub tweak_colours (\$$) {
    # cccccc is the colour of the --header block
    ${$_[0]} =~ s|#cccccc|#ff9900|g;

    # links
    ${$_[0]} =~ s|<body |<body link="#ff9900" alink="#ef8900" vlink="#ff9900"|;
}

sub fix_exterior_links (\$$) {
    # this moves /home/foo to ~foo, for external Perl doc (see @INC in podpath)
    ${$_[0]} =~ s|/home/${\USER}|~${\USER}|g;
}

#---

sub write_content (\$$) {
    my ($contentref,$file)=@_;
    open FILE, ">", $file or die "Unable to open $file for writing: $!\n";
    print FILE $$contentref;
    close FILE;
}

sub postprocess ($$) {
    my ($file,$opts)=@_;

    my $content=read_content($file);

    fix_manpage_links $content,$opts;
    fix_script_links $content,$opts;
    add_short_anchor_names $content,$opts;
    add_index_links $content,$opts;
    tweak_colours $content,$opts;
    fix_exterior_links $content,$opts;

    write_content($content => $file);
}

#------------------------------------------------------------------------------

MAIN: {
    my @dirs = ();
    my $script = basename $0;
    my $opts=getoptions();

    foreach (@ARGV) {
        my $dir=$_;
        if ( -d $dir ) {
            push(@dirs, $dir);
#       } elsif (-f $dir) {
#         .... handle files too ...
        } else {
            fatal "$dir not a directory\n";
        }
    }

    my $user=$opts->{user};
    #my $htmldir= defined $opts->{user} ? "/home/$user/public_html" : $opts->{to};
    my $htmldir= $opts->{to};
    my $podroot= "$FindBin::Bin/..";
    $podroot =~ s!/[^/]+/..($|/)!!g;

    my $cachedir = ($opts->{cachedir} || "$podroot/data/cache")."/bde_pod2html";
    mkpath $cachedir unless -d $cachedir;

    my @pod2html_args=(
        "--cachedir=$cachedir",
        "--header",
        "--libpods=perlfunc:perlops:perlrun:perlvar",
        ($opts->{quiet} ? "--quiet" : "--noquiet"),
        ($opts->{verbose} ? "--verbose" : "--noverbose"),
        "--podpath=bin:lib:etc:".join(":",@INC),
        "--podroot=$podroot",
        "--htmldir=$htmldir",
        "--htmlroot=$opts->{htmlroot}",
        "--recurse",
    );

    debug "Searching: ".join(" ", @dirs);

    foreach my $source (findfiles @dirs) {
        my $base=basename $source;
        $base =~ s/\.(pl|pm|pod)$//;

        if ($opts->{list}) {
            print "$source\n";
        } else {
            debug "$source -> $htmldir/$base.html\n";
            my $path=makeTargetDirectory($source, $podroot, $htmldir);
            pod2html($source,
                     "--infile=$source",
                     "--outfile=$htmldir/$path/$base.html",
                     @pod2html_args
            );

            postprocess("$htmldir/$path/$base.html",$opts);
        }
    }
}

#==============================================================================

=head1 AUTHOR

Marty Vasas (mvasas@bloomberg.net)

=head1 SEE ALSO

L<bde_build.pl>, L<bde_setup.pl>, L<bde_verify.pl>, etc...

=cut

1;
