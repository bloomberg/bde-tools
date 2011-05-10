#!/bbs/opt/bin/perl -w
use strict;

use Symbol ();

BEGIN {
    exists $ENV{SUID_EXECUTION_PATH}
      ? $ENV{SUID_EXECUTION_PATH} =~ m|^([\w/\\.-]+)$| && ($FindBin::Bin = $1)
      : eval 'use FindBin';
}
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Symbols qw(EXIT_SUCCESS EXIT_FAILURE);
use Change::Symbols qw(ACCEPTLIST ADMINLIST DENYLIST BETALIST);

use constant TARGETS =>
  {
    addnotetoticket	=> "bde_addticketlog.pl",
    csalter		=> "bde_altercs.pl",
    cscheckin		=> "bde_createcs.pl",
    csprqsst		=> "bde_csprqsst.pl",
    csrollback		=> "bde_rollbackcs.pl",
    csdbdiff            => "bde_diffcsdb.pl",
    isapprover		=> "isapprover.pl",
    isbetaday		=> "isbetaday.pl",
    islockdown		=> "islockdown.pl",
    istester		=> "istester.pl", 
    csuncheckout        => "bde_uncheckoutcs.pl", 
    uorcreate		=> "aotools/uorcreate.pl",
  };

use constant AUTHZ_FILES =>
  {
    addnotetoticket	=> ADMINLIST,
    csalter		=> ADMINLIST,
    cscheckin		=> ACCEPTLIST,
    csprqsst		=> ADMINLIST,
    csdbdiff            => ACCEPTLIST,
    csrollback		=> ACCEPTLIST,
    csuncheckout        => ACCEPTLIST,
    isapprover		=> ACCEPTLIST,
    isbetaday		=> ACCEPTLIST,
    islockdown		=> ACCEPTLIST,
    istester		=> ACCEPTLIST,  
    uorcreate		=> ADMINLIST,
  };

use constant ALPHA_AUTHZ =>
  [ qw(	pwainwri gstrauss dhabte nkhosla shalpenn qchen tvon wbaxter1 agrow
	dsugalsk hchen26
	tmarshal jmacd
	schaud1 anozhnic
	alan mgiroux dstarksb jbelmont) ];

use constant AUTHZ_OVERRIDES =>
  {
    csalter		=> [ "op" ],
    csprqsst		=> [ "op" ],
    csrollback		=> [ "op" ]
  };


#==============================================================================

=head1 NAME

bde_script_authz.pl - Check authorization lists

=head1 SYNOPSIS

    $ bde_script_authz.pl <uid> <target_script_tag>

=head1 DESCRIPTION

C<bde_script_authz.pl> is a command-line interface to check if a given uid
is authorized to call a given target tag.  The full path to the target
script associated with the tag is returned if the user is authorized to call
the script.  This script exits 0 upon success -- i.e. user is authorized --
and non-zero upon failure.

This script is used by setuid programs to see if a user is authorized to
run the script as the privileged user, e.g. as robocop.

=cut

#==============================================================================


sub beta_use_required ($) {
    my($username) = @_;

    foreach (@{(ALPHA_AUTHZ)}) {
	return 0 if $_ eq $username;
    }

    my $FH = Symbol::gensym;
    open($FH,'<'.BETALIST)
      || die "Unable to open ".BETALIST.": $!\n";
    while (<$FH>) {
	chomp;
	return 1 if $_ eq $username;
    }
    return 0;
}


sub is_authorized ($$) {
    my($username,$target) = @_;
    my $authz_file = AUTHZ_FILES->{$target};

    ## special list for beta area
    if ($FindBin::Bin ne "/bbsrc/bin/beta/bin") {
	if (beta_use_required($username)) {
	    warn "\nBeta users must use /bbsrc/bin/beta/$target\n\n";
	    return 0;
	}
    }
    else {
	$authz_file = BETALIST if ($authz_file eq ACCEPTLIST);
    }

    ## special case regular tools and *allow* if ACCEPTLIST is missing
    ## (by default all developers can use the (non-admin) production tools)
    my $is_authorized = $authz_file eq ACCEPTLIST && !(-f ACCEPTLIST);

    ## check if user is listed in authorization list
    if (!$is_authorized) {
	my $FH = Symbol::gensym;
	open($FH,'<'.$authz_file)
	  || die "Unable to open $authz_file: $!\n";
	while (<$FH>) {
	    chomp;
	    $is_authorized = 1, last if $_ eq $username;
	}
	close $FH;
    }

    ## special-case alpha area (before per-target authorization overrides)
    ## XXX: this could be done as a separate robocop-managed file like BETALIST
    if ($is_authorized && ($FindBin::Bin eq "/bbsrc/bin/alpha/bin"
			   || $FindBin::Bin eq "/bbsrc/bin/cstest/bin")) {
	$is_authorized = 0;
	foreach (@{(ALPHA_AUTHZ)}) {
	    $is_authorized = 1, last if $_ eq $username;
	}
    }

    ## check if user is listed in authorization overrides
    my $overrides = AUTHZ_OVERRIDES->{$target};
    if (!$is_authorized && defined($overrides)) {
	foreach (@$overrides) {
	    $is_authorized = 1, last if $_ eq $username;
	}
    }

    return $is_authorized;
}


sub is_blacklisted ($) {
    my($username) = @_;
    my $FH = Symbol::gensym;

    open($FH,'<'.DENYLIST)
      || die "Unable to open ".DENYLIST.": $!\n";
    while (<$FH>) {
	chomp;
	return 1 if $_ eq $username;
    }
    return 0;
}

sub report_cstools_location () {
    return if ($FindBin::Bin eq "/bbsrc/bin/prod/bin");
    my $tool_location =
      ($FindBin::Bin eq "/bbsrc/bin/beta/bin")
	? "beta"
	: ($FindBin::Bin eq "/bbsrc/bin/alpha/bin")
	    ? "alpha"
	    : ($FindBin::Bin eq "/bbsrc/bin/lgood/bin")
		? "lgood"
		: "unreleased";
    print STDERR "cstools location: $tool_location\n\n";

    if ($tool_location eq "lgood") {
	print STDERR
	  "*** WARNING: Do not use cstools lgood release unless you have been ",
	  "***\n",
	  "***          explicitly directed to do so by the SI Build Team.    ",
	  "***\n\n";
	sleep 30;
    }
}


MAIN:
{
    my($uid,$target) = @ARGV;

    my $cmd = TARGETS->{$target};
    exit(EXIT_FAILURE) unless $cmd;

    my $username = getpwuid($uid);
    exit(EXIT_FAILURE) unless $username;

    exit(EXIT_FAILURE) unless is_authorized($username,$target);
    exit(EXIT_FAILURE) if is_blacklisted($username);

    report_cstools_location();

    # This should always be a full path (note: no trailing newline)
    print STDOUT substr($cmd,0,1) ne '/' ? $FindBin::Bin.'/'.$cmd : $cmd;
    exit(EXIT_SUCCESS);
}

#==============================================================================

=head1 AUTHOR

Glenn Strauss (gstrauss1@bloomberg.net)

=head1 SEE ALSO

L<Change::Symbols>

=cut
