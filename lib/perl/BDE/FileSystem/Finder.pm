package BDE::FileSystem::Finder;
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
    isApplication
    isFunction
    getCanonicalUOR
);
use Util::Message qw(debug);

use DirHandle;

#------------------------------------------------------------------------------

=head1 SYNOPSIS

    my $root=new BDE::FileSystem::Finder("/bbcm/infrastructure");

    my @base_groups=$root->findAllGroups();
    my @adapters=$root->findAllAdapters();

=head1 DESCRIPTION

Thia module is a subclass of L<BDE::Filesystem> with additional methods to
return information about source units available in the repository.

=cut

#------------------------------------------------------------------------------

sub _findAll ($$&) {
    my ($self,$locn,$verifyfn)=@_;

    my $dir=new DirHandle($locn);
    return () unless defined $dir; #it's ok to be missing a given subdir

    my @matches=();
    while (defined(my $file = $dir->read())) {
	if (&$verifyfn($file)) {
	    push @matches,$file;
	}
    }

    @matches = map {getCanonicalUOR($_)} @matches;
    my %uniq; @uniq{@matches} = (); @matches = keys %uniq;
    return @matches;
}

#------------------------------------------------------------------------------

sub validBase        ($) { isBase($_[0])        && isGroup($_[0])   };
sub validFunction    ($) { isFunction($_[0])    && isPackage($_[0]) };
sub validApplication ($) { isApplication($_[0]) && isPackage($_[0]) };
sub validDepartment  ($) { isDepartment($_[0])  && isGroup($_[0])   };
sub validAdapter     ($) { isAdapter($_[0])     && isPackage($_[0]) };
sub validWrapper     ($) { isWrapper($_[0])     && (isGroup($_[0])
                                                || isPackage($_[0]))};

#------------------------------------------------------------------------------


sub findAllGroups ($) {
    my $self=shift;
    return $self->_findAll($self->getGroupsLocation(),\&validBase);
}

sub findAllFunctions ($) {
    my $self=shift;
    return $self->_findAll($self->getFunctionsLocation(),\&validFunction);
}

sub findAllDepartments ($) {
    my $self=shift;
    return $self->_findAll($self->getDepartmentsLocation(),\&validDepartment);
}

sub findAllAdapters ($) {
    my $self=shift;
    return $self->_findAll($self->getAdaptersLocation(),\&validAdapter);
}

sub findAllApplications ($) {
    my $self=shift;
    return $self->_findAll($self->getApplicationsLocation(),\&validApplication);
}

sub findAllWrappers ($) {
    my $self=shift;
    return $self->_findAll($self->getWrappersLocation(),\&validWrapper);
}

#------------------------------------------------------------------------------

sub findUniverse ($) {
    my $self=shift;

    return (
        $self->_findAll($self->getGroupsLocation(),\&validBase),
        $self->_findAll($self->getFunctionsLocation(),\&validFunction),
        $self->_findAll($self->getDepartmentsLocation(),\&validDepartment),
        $self->_findAll($self->getAdaptersLocation(),\&validAdapter),
        $self->_findAll($self->getApplicationsLocation(),\&validApplication),
        $self->_findAll($self->getWrappersLocation(),\&validWrapper)
    );
}

#------------------------------------------------------------------------------

sub test {
    my $root=new BDE::FileSystem::Finder("/bbcm/infrastructure");
    print "Root        : $root\n";
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

    L<BDE::FileSystem>, L<bde_find.pl>, L<bde_snapshot.pl>

=cut

1;
