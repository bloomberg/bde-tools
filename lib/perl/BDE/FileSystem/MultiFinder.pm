package BDE::FileSystem::MultiFinder;
use strict;

use BDE::FileSystem;
use vars qw(@ISA);

@ISA=qw(BDE::FileSystem);

use BDE::Util::Nomenclature qw(
    isGroup
    isPackage
    isBase
    isAdapter
    isWrapper
    isDepartment
    isEnterprise
    isApplication
    isFunction
    isLegacy
    isThirdParty
    isUORsegment
    getCanonicalUOR
);
use BDE::Build::Invocation qw($FS);
use Util::Message qw(debug);

use DirHandle;

#------------------------------------------------------------------------------

=head1 NAME

BDE::FileSystem::MultiFinder - Multirooting filesystem search extensions

=head1 SYNOPSIS

    my $root=new BDE::FileSystem::MultiFinder("/bbcm/infrastructure");

    my @base_groups=$root->findAllGroups();
    my @adapters=$root->findAllAdapters();
    my @multiverse=$root->findUniverse();

=head1 DESCRIPTION

This module is a subclass of L<BDE::Filesystem> with additional methods to
return information about source units available in the repository.

C<BDE::FileSystem::MultiFinder> is aware of multiple roots and will return the
location for the 'closest' of a selection of possible locations for a given
unit of release. To search in the local filesystem use
L<BDE::FileSystem::Finder> instead of this module.

=cut

#------------------------------------------------------------------------------

sub _findAll ($$&;$) {
    my ($self,$locns,$verifyfn,$uor_prefix_dirs)=@_;
    my @paths=(ref $locns)?@$locns:($locns);
    $uor_prefix_dirs ||= "";

    ##<<<TODO: what purpose does %matches serve?
    ## Something like findUniverse() should be passing in a hash ref so that
    ## if a unit of release is located in more than one category, it is flagged

    my ($uor,@matches,%matches);
    foreach my $locn (@paths) {
	my $dir=new DirHandle($locn);
	next unless defined $dir; #it's ok to be missing a given subdir

	while (defined(my $file = $dir->read())) {
	    next if $file eq '.' || $file eq '..';
	    $uor = $uor_prefix_dirs.$file;
	    next if exists $matches{$uor};
	    if (&$verifyfn($uor)) {
		push @matches,$uor;
		$matches{$uor}=1;
	    }
	    elsif (isUORsegment($locn.$FS.$file)) {
		push @matches,
		     &_findAll($self,$locn.$FS.$file,$verifyfn,$uor.$FS);
	    }
	}
    }

    @matches = grep { defined $_ } map {getCanonicalUOR($_)} @matches;
    my %uniq; @uniq{@matches} = (); @matches = keys %uniq;

    return @matches;
}

#------------------------------------------------------------------------------

sub validBase        ($) { isBase($_[0])        && isGroup($_[0])   };
sub validFunction    ($) { isFunction($_[0])    && isPackage($_[0]) };
sub validApplication ($) { isApplication($_[0]) && isPackage($_[0]) };
sub validDepartment  ($) { isDepartment($_[0])  && isGroup($_[0])   };
sub validEnterprise  ($) { isEnterprise($_[0])  && isGroup($_[0])   };
sub validAdapter     ($) { isAdapter($_[0])     && isPackage($_[0]) };
sub validWrapper     ($) { isWrapper($_[0])     && (isGroup($_[0])
                                                || isPackage($_[0]))};
sub validLegacy      ($) { isLegacy($_[0])      && isPackage($_[0]) };
sub validThirdParty  ($) { isThirdParty($_[0])  && isPackage($_[0]) };

#------------------------------------------------------------------------------


sub findAllGroups ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getBaseLocations),\&validBase);
}

sub findAllFunctions ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getFunctionsLocations),\&validFunction);
}

sub findAllDepartments ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getDepartmentsLocations),\&validDepartment);
}

sub findAllEnterprise ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getEnterpriseLocations),\&validEnterprise);
}

sub findAllAdapters ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getAdaptersLocations),\&validAdapter);
}

sub findAllApplications ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getApplicationsLocations),\&validApplication);
}

sub findAllWrappers ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getWrappersLocations),\&validWrapper);
}

sub findAllLegacy ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getLegacyLocations),\&validLegacy);
}

sub findAllThirdParty ($) {
    my $self=shift;
    return $self->_findAll(scalar($self->getThirdPartyLocations),\&validThirdParty);
}

#------------------------------------------------------------------------------

sub findUniverse ($) {
    my $self=shift;

    return (
        $self->_findAll(scalar($self->getBaseLocations),\&validBase),
        $self->_findAll(scalar($self->getDepartmentsLocations),
			\&validDepartment),
        $self->_findAll(scalar($self->getEnterpriseLocations),
			\&validEnterprise),
        $self->_findAll(scalar($self->getAdaptersLocations),\&validAdapter),
        $self->_findAll(scalar($self->getWrappersLocations),\&validWrapper),
        $self->_findAll(scalar($self->getLegacyLocations),\&validLegacy),
        $self->_findAll(scalar($self->getThirdPartyLocations),
			\&validThirdParty),
        $self->_findAll(scalar($self->getFunctionsLocations),\&validFunction),
        $self->_findAll(scalar($self->getApplicationsLocations),
			\&validApplication),
    );
}

#------------------------------------------------------------------------------

sub test {
    eval { use Symbols qw(ROOT PATH); 1; };

    my $root=new BDE::FileSystem::MultiFinder(ROOT);
    print "Root        : $root\n";
    print "Path        : ${\PATH}\n";
    print "------------|\n";
    print "Groups      : ",      (join' ',$root->findAllGroups()),"\n";
    print "Functions   : ",   (join' ',$root->findAllFunctions()),"\n";
    print "Adapters    : ",    (join' ',$root->findAllAdapters()),"\n";
    print "Wrappers    : ",    (join' ',$root->findAllWrappers()),"\n";
    print "Departments : ", (join' ',$root->findAllDepartments()),"\n";
    print "Applications: ",(join' ',$root->findAllApplications()),"\n";
    print "------------|\n";
    print "Universe    : ",      (join ' ',$root->findUniverse()),"\n";
}

#------------------------------------------------------------------------------

=head1 AUTHOR

    Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

    L<BDE::FileSystem>, L<BDE::FileSystem::Finder>, L<bde_find.pl>

=cut

1;
