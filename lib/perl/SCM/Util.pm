# vim:set ts=8 sts=4 noet:

package SCM::Util;

use base qw/Exporter/;

use strict;
use warnings;

use Digest::MD5	    qw/md5_hex/;
use File::Basename;

use Change::Symbols qw(/^MOVE_/
		       FILE_IS_UNCHANGED FILE_IS_REMOVED FILE_IS_UNKNOWN);
use SCM::Symbols    qw/SCM_QUEUE SCM_DIR_DATA $SCM_DIFF_PATH 
		       $SCM_BRANCH_PROMOTION_MARK
		       $SCM_SWEEPINFO_DATA/;
use Change::Util    qw/hashCSID2dir/;
use Util::Message   qw/error verbose/;

our $VERSION = '0.01';
our @EXPORT_OK = qw/isValidMoveType 
                    generateDiffReport
                    datetime2csdate csdate2datetime
		    get_branch_promotion_cutoff
                    any all part firstidx none getBundlePath/;

{
    my %move = (
	map (($_ => MOVE_REGULAR)   => qw(move regular reg rmove r)),
	map (($_ => MOVE_BUGFIX)    => qw(bugf bfix bugfix bf bmove b)),
	map (($_ => MOVE_EMERGENCY) => qw(emov emergency emove e)),
	map (($_ => MOVE_IMMEDIATE) => qw(imov immediate imove i)),
    );

    sub isValidMoveType {
	my $type = shift;
	return if not exists $move{$type};
	return $move{$type};
    }
}

sub generateDiffReport {
    my ($cs, $repo) = @_;
    
    require Change::Set;
    require HTML::Entities;

    my $csid = $cs->getID();

    open my $fh, '>', "$SCM_DIFF_PATH/$csid.diff.html" or do {
        error "Could not create $SCM_DIFF_PATH/$csid.diff.html: $!";
        return;
    };

    print $fh <<EODIFF;
<html>
    <head>
        <title>Difference report for Change Set $csid</title>
    </head>
    <body>
        <font size="5">Difference report for Change Set $csid</font>
        <hr noshade size="1" color="black">
        <pre>
    @{[ $cs->listChanges('pretty', 'header only') ]}
        </pre>
EODIFF

    # diff report index
    print $fh <<EODIFF;
        <ul>
EODIFF

    foreach my $target ($cs->getTargets) {
        my @files = $cs->getFilesInTarget($target);
        print $fh <<EODIFF;
            <li>Target: $target (@{[ scalar @files ]} files)</li>
            <ul>
EODIFF
        foreach my $file (@files) {
            my $src     = $file->getSource;
            my $dest    = $file->getDestination;
            my $type    = $file->getType;
            print $fh <<EODIFF;
                <li><a href="#$src">$src-&gt;$dest ($type)</a></li>
EODIFF
        }

        print $fh <<EODIFF;
            </ul>
EODIFF
    }

    print $fh <<EODIFF;
        </ul>
EODIFF
    
    # diff reports

    foreach my $file ($cs->getFiles) {

	my $type = $file->getType;
	next if $type eq FILE_IS_UNCHANGED ||
		$type eq FILE_IS_REMOVED   ||
		$type eq FILE_IS_UNKNOWN;

        next if $file->getLeafName =~ /\.ml$/;   # don't include binary files in the report

        my $src         = $file->getSource;
        my $targ        = $file->getTarget;
        my $base        = basename($file);

        my ($diff, $err) = $repo->diff($cs->getMoveType, $csid, $file->getDestination); 

        $diff = $err if $err;

        HTML::Entities::encode_entities($diff);
        $diff =~ s#^(\-.*)$#<font color="red"><b>$1</b></font>#mg;
        $diff =~ s#^(\+.*)$#<font color="green"><b>$1</b></font>#mg;
        $diff =~ s#^(\@\@.*)$#<font color="blue"><b>$1</b></font>#mg;
        $diff =~ tr/\t/ /;

        print $fh <<EODIFF;
        <br>
        <table width="100%" style="border:1px solid black;">
        <tr><td width="*">
            <table width="100%" bgcolor="#a0a0a0">
                <tr><td width="*">
                    &nbsp;<a name="$src"><font size="4">$targ/$base</font></a>
                </td></tr>
            </table>
            <pre>
$diff
            </pre>
        </td></tr>
        </table>
    </body>
EODIFF
    }
    print $fh <<EODIFF;
</html>
EODIFF
    
    return 1;
}

sub getBundlePath {
    my ($csid, $basedir) = @_;

    $basedir = SCM_QUEUE if not defined $basedir;

    require File::Spec;
    my $path = File::Spec->catfile($basedir, SCM_DIR_DATA, 
                                   hashCSID2dir($csid), $csid);

    return $path if -e $path;
}

sub datetime2csdate {
    my $datetime = shift;

    require HTTP::Date;
    my $time = HTTP::Date::str2time($datetime);
    
    return scalar localtime($time);
}

sub csdate2datetime {
    my $csdate = shift;
    
    require HTTP::Date;
    my $time = HTTP::Date::str2time($csdate);

    require POSIX;
    POSIX::strftime('%Y-%m-%d %T', localtime($time));
}

sub get_branch_promotion_cutoff {
    open my $fh, '<', $SCM_BRANCH_PROMOTION_MARK
	or return;
    chomp(my @cutoff = <$fh>);
    return @cutoff;
}

sub any (&@) {
    my $f = shift;
    return if ! @_;
    for (@_) {
        return 1 if $f->();
    }
    return 0;
}

sub all (&@) {
    my $f = shift;
    return if ! @_;
    for (@_) {
        return 0 if ! $f->();
    }
    return 1;
}

sub part(&@) {
    my ($code, @list) = @_;
    my @parts;
    defined && push @{ $parts[$code->($_)] }, $_  for @list;
    return @parts;
}

sub firstidx (&@) {
    my $f = shift;
    for my $i (0 .. $#_) {
        local *_ = \$_[$i]; 
        return $i if $f->();
    }
    return -1;
}

sub none (&@) {
    my $f = shift;
    return if ! @_;
    for (@_) {
        return 0 if $f->();
    }
    return 1;
}


1;

__END__

=head1 NAME

SCM::Util - SCM-related utility functions

=head1 FUNCTIONS

=head2 isValidMoveType( $type )

Returns a true value if the passed in string I<$type> refers to a valid move
type. The returned value in this case will be a normalized string in terms of
Change::Util::MOVE_*.

Returns false otherwise.

=head2 generateDiffReport( $cs, $repository )

Generates a diff report for the change set I<$cs> by querying I<$repository> which
must be a I<SCM::Repository> object pointing to the code repository. 

On success, returns the name of a temporary file where this diff report has
been written to. A false value otherwise.

The caller is responsible for deleting this temporary file when it no longer
needs it.

=head2 datetime2csdate( $datetime )

Formats a DATETIME string in the format C<YYYY-MM-DD hh:mm:ss.fffff> into the
format used in change sets C<Day Mon DD hh:mm:ss YYYY>.

Returns the date in the change set format if successful. C<undef> otherwise.

=head1 EXPORTS

Nothing by default.

=head1 AUTHOR

Tassilo von Parseval E<lt>tvonparseval@bloomberg.netE<gt>
