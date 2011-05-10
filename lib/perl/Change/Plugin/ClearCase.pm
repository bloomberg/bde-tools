package Change::Plugin::ClearCase;
use strict;

use base 'Change::Plugin::Base';
use Change::Plugin::Base;
use POSIX qw(strftime);


use Util::Message qw(message error fatal debug debug2);

use constant NULL          => '/dev/null';
use constant TEMPLATE      => '/bbsrc/tools/bbcm/bb.tcs';
use constant CLEARTOOL     => '/usr/atria/bin/cleartool';
use constant LABEL	   => 'BUILD_TEAM';
use constant ATTRIBUTE     => 'sent_to_build_team';

#==============================================================================

=head1 NAME

Change::Plugin::ClearCase - cscheckin plugin for ClearCase integration

=head1 SYNOPSIS

    $ cscheckin -LClearCase ...

	Please substitute "..." with all cscheckin options and arguments.
	To see all cscheckin options, please run: cscheckin --help

=head1 DESCRIPTION

This is a ClearCase plugin module for L<cscheckin> that implements
utility functions to perform ClearCase checks. This plugin will perform
the following:
	1. Validate the current ClearCase view.
	2. Ensures that the version(s) are from the bb branch.
	3. Ensures that the version(s) will be labeled with "BUILD_TEAM".

=head1 EXAMPLES

Example 1, checkin 1 file to library "test_library":
  cscheckin -LClearCase  file1.c test_library

Example 2, checkin 3 files to library "test_library":
  cscheckin -LClearCase  file1.c file2.c file3.c test_library

There are many examples also avilable at the cscheckin man page, run:
  perldoc cscheckin

=cut

#==============================================================================

# strip out cosmetic content from a config.spec string such as comments and
# whitespace, so that it may be compared to another config.spec.
sub strip_comments_and_whitespace ($) {
    my	$CS = shift;

    $CS =~ s!#.*$!!mg;	# Remove comments
    $CS =~ s!\n! !g;	# Replace \n with a space
    $CS =~ s!\t! !g;	# Replace \t with a space
    $CS =~ s!^\s+!!g;	# Remove any leading spaces
    $CS =~ s!\s+! !g;	# Replace one/more spaces with a single space

    debug2 "CS is $CS";
    return $CS;
}

# compare the active view's config.spec to the template, and return true if
# it conforms, or false (and emit an error to standard error) otherwise.
# Throw an exception if C<cleartool> could not be invoked or the template
# could not be read.
sub verify_config_spec () {
    my	$catCS = `${\CLEARTOOL} catcs` or
      fatal "Error getting catcs: $?";

    my	$templateCS = `cat ${\TEMPLATE}`;
    fatal "Error getting config spec template: $?" if $?;

    my	$CS = $templateCS;
    $catCS = strip_comments_and_whitespace ( $catCS );
    $templateCS = strip_comments_and_whitespace ( $templateCS );
    if ( $catCS ne $templateCS ) {
	error "This is not a script-genrated view.\n".
	      "Your config spec should be:\n\n$CS\n";
	return 0;
    }
    return 1;
}

# return true if we're in a CC view, or false (and emit an error to
# standard error) otherwise. Throw an exception if C<cleartool> could not
# be invoked.
sub in_view () {
    my	$pwv = `${\CLEARTOOL} pwv -short` or
      fatal ("Error doing 'cleartool pwv': $?");

    chomp($pwv);
    debug2 "pwv is $pwv";

    if ( $pwv eq "** NONE **" ) {
	error "User not in a ClearCase view.\n".
	      "You must set into a ClearCase view \n".
	      "before you can use this script\n";
	return 0;
    }
    return 1;
}

# return true of the specified filename is a CC element, or false (and
# emit an error to standard error) otherwise. Throw an exception if
# C<cleartool> could not be invoked.
sub file_is_element ($) {
    my 	$filename=shift;
    debug2 "filename is $filename";

    my	$iselem = `${\CLEARTOOL} ls $filename` or
      fatal ("Error doing 'cleartool ls' on file $filename: $?");

    chomp($iselem);
    debug2 "iselem is $iselem";

    if ($iselem !~ /.*@@.*Rule: /) {
	error "File $filename is not under ClearCase control.\n".
	      "You must make it an element and check it in\n".
	      "before you can use this script.";
	return 0;
    }
    return 1;
}

# return true of file is checked out of ClearCase, or false (and emit an error
# to standard error) otherwise. Throw an exception of C<cleartool> could not
# be invoked.
sub file_is_checkedout ($) {
    my 	$filename=shift;
    debug2 "filename is $filename";
	

    my $lsco = `${\CLEARTOOL} lsco -short -brtype bb $filename`;
	fatal ("Error doing 'cleartool lsco' on file $filename: $?") if ($?);

    chomp($lsco);
    debug2 "lsco is $lsco";

    if ( $lsco eq $filename ) {
	error "File $filename is checkedout on 'bb' branch.\n".
	      "You must check in the file to ClearCase\n".
	      "before you can use this script.";
	return 1;
    }
    return 0;
}

# return true if file is I<not> the latest version on the C<bb> branch,
# or false (and emit an error to standard error) otherwise. Throw an
# exception if C<cleartool> could not be invoked.
sub file_is_not_latest ($) {
    my 	$filename=shift;
    debug2 "filename is $filename";

    my	$ctls = `${\CLEARTOOL} ls -vob $filename` or
      fatal ("Error doing 'cleartool ls' on file $filename: $?");

    chomp($ctls);
    debug2 "ctls is $ctls";
    if ( $ctls !~ q!Rule: .../bb/LATEST$! ) {
	error "File $filename is not the latest version on 'bb' branch.\n".
	      "You cannot run this script on a version other than\n".
	      ".../bb/LATEST.";
	return 0;
    }
    return 1;
}

# converts localtime to ClearCase date and time format.
# uses POSIX qw(strftime);
sub getClearCaseTimeString () {
    my $str = strftime( '%e-%b-%Y.%T', localtime );
    debug2 "str is $str";

    return $str;
}

#------------------------------------------------------------------------------

sub plugin_usage ($) {
    return
      "  This plugin requires cscheckin to run from a valid ClearCase view.\n".
      "  --autoco is enabled by default; use --noautoco to disable it.\n".
      "  For more information see the Change::Plugin::ClearCase manual page.";
}

sub plugin_initialize ($$) {
    my ($plugin,$opts)=@_;

    # switch on autoco unless already specified. This allows
    # '--noautoco' to work to disable this feature if necessary.
    $opts->{autoco}=1 unless defined $opts->{autoco};

    fatal "User not in a ClearCase view - aborting" unless in_view();
    fatal "Invalid view - aborting" unless verify_config_spec();

    return 1;
}

sub plugin_post_find_filter ($$) {
    my ($plugin,$changeset)=@_;

    my @files=map { $_->getSource() } $changeset->getFiles();

    foreach my $file (@files) {
	fatal "File $file is not under ClearCase control - aborting"
	  unless file_is_element($file);

	fatal "File $file is checkedout - aborting"
	  if file_is_checkedout($file);

	fatal "File $file is not the latest version on '/bb' branch - aborting"
	  unless file_is_not_latest($file);
    }
  return 1;
}

sub plugin_post_change_success ($$) {
    my ($plugin,$changeset)=@_;

    my @files=map { $_->getSource() } $changeset->getFiles();

    my	$comment = "Label applied by cscheckin";
    my $cmd = "${\CLEARTOOL} mklabel -replace -c '$comment' ${\LABEL} "
		. "@files >${\NULL} 2>&1";
    debug2 "cmd is $cmd";
    system ( $cmd );
    if ($?) {
	# this error is not fatal as the CS was committed. It's just going
	# to require fixing the VOB later.
	error "Moving of ".LABEL." label failed.";
	return 1;
    }

    $comment = "Attribute applied by cscheckin";
    my	$sent_to = getClearCaseTimeString();
    $cmd = "${\CLEARTOOL} mkattr -replace -c '$comment' ${\ATTRIBUTE} "
		. "$sent_to @files >${\NULL} 2>&1";
    debug2 "cmd is $cmd";
    system ( $cmd );
    if ($?) {
	# this error is not fatal as the CS was committed. It's just going
	# to require fixing the VOB later.
	error "Applying ".ATTRIBUTE." attribute failed.";
	return 1;
    }

    return 1;
}

#==============================================================================

=head1 AUTHOR

Sucharita Kesani (skesani@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>

=cut

1;

#==============================================================================
