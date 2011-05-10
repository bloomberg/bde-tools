package BDE::File::Finder;
use strict;

use base 'BDE::Object';
use BDE::Package::Include;
use BDE::Build::Invocation qw($FS);
use Util::Message qw(debug2);

my @DEFAULT_FORBID=qw[/usr /bbsrc];

#==============================================================================

=head1 NAME

BDE::File::Finder - Class for locating files

=head1 SYNOPSIS

    use BDE::FileSystem::Finder;
    use BDE::FileSystem;
    my $root=new BDE::FileSystem("/bbcm/infrastructure");

    my $finder=new BDE::File::Finder($root);
    $finder->setSearchPath("/bbcm/infrastructure/bde");
    $finder->addPackageSearchPath("bdet");
    $finder->addPackageSearchPath("bde+pcre");
    $finder->addPackageSearchPath("bde+stlport","stlport");
    foreach (qw[bdet_datetime.h pcre.h cassert notthere]) {
	my $where=$finder->find($_);
	if ($where) {
	    $where->dump();
	} else {
	    print "$_: *not found*\n";
	}
    }

=head1 DESCRIPTION

This module provides a simple object class that is a helper class for the
L<BDE::Util::DependencyCache> module. It looks for a requested file in
one of the pre-established search locations provided.

This modules is considered an internal implementation detail of the dependency
caching algoritm and is not expected to have external application.

=cut

#==============================================================================

sub initialise ($$) {
    my ($self,$init)=@_;

    $self->SUPER::initialise($init);

    $self->{where} = {} unless exists $self->{where};
    $self->{forbid}=[@DEFAULT_FORBID] unless exists $self->{forbid};

    return $self;
}

sub initialiseFromScalar ($$) {
    my ($self,$init)=@_;

    $self->throw("Scalar initialiser must be BDE::FileSystem root object")
      unless $init->isa("BDE::FileSystem");
    $self->setFileSystemRoot($init);

    return $self;
}

#------------------------------------------------------------------------------

# required by Package methods only, not required for basic file searches
sub setFileSystemRoot ($$) {
    $_[0]->throw("Not a BDE::FileSystem root object")
      unless $_[1]->isa("BDE::FileSystem");
    $_[0]->{root}=$_[1];
}

sub setSearchPath ($$;$) {
    my ($self,$path,$subdir)=@_;

    $self->removeAllSearchPath();
    $self->addSearchPath($path,$subdir);
}

sub addSearchPath ($$;$$) {
    my ($self,$path,$subdir,$type)=@_;
    $self->throw("No path passed") unless defined $path and length $path;

    $subdir ||= ".";
    $type ||=0; #0 for files, package for packages
    $self->{where}{$path}{$subdir}=$type; #exists but not true
}

sub getSearchPath() {
    my $self=shift;

    my $where=$self->{where};
    my @paths;
    foreach my $path (keys %$where) {
	foreach my $subdir (keys %{$where->{$path}}) {
	    # more useful for debugging than anything else
	    push @paths, $path.'[/'.$subdir.']='.$where->{$path}{$subdir};
	}
    }

    return @paths;
}

sub setPackageSearchPath ($$;$) {
    my ($self,$package,$subdir)=@_;

    $self->removeAllSearchPath();
    $self->addSearchPath($package,$subdir);
}

sub addPackageSearchPath ($$;$) {
    my ($self,$package,$subdir)=@_;

    $self->throw("No filesystem root set")
      unless exists $self->{root};
    my $path=$self->{root}->getPackageLocation($package);
    $self->throw("Not a package: $package") unless $path;
    $self->addSearchPath($path,$subdir,$package);
}

sub removeAllSearchPath ($)  { $_[0]->{where}={}; }

sub getForbiddenPath ($) { return @{$_[0]->{forbid}}; }

sub setForbiddenPath ($@) { @{$_[0]->{forbid}}= $_[1..-1]; }

sub addForbiddenPath ($@) {
    my ($self,@paths)=@_;

    my %f=map {$_=>1} @{$self->{forbid}};
    foreach (@paths) {
	push @{$self->{forbid}},$_ unless exists $f{$_};
    }
}

sub removeAllForbiddenPath ($) { $_[0]->{forbid}=[]; }

#------------------------------------------------------------------------------

# look for the requested file using the where/forbid criteria
sub find ($$) {
    my ($self,$file)=@_;
    my $debug = Util::Message::get_debug();

    # entirely skip files on forbidden paths
    foreach ($self->{forbid}) {
	return undef if $file=~/^$_/;
    }

    # scan for file on permitted paths
    foreach my $path (keys %{$self->{where}}) {
	foreach my $subdir (keys %{$self->{where}{$path}}) {
	    my $realfile=$path.$FS;
	    $realfile.=$subdir.$FS if $subdir ne ".";
	    $realfile.=$file;
#print "---->ff:looking for '$realfile'\n";
	    debug2 "looking for '$realfile'" if ($debug >= 2);

	    if (-f $realfile) {
		my $fi=new BDE::Package::Include({
	            fullname => $file,
                    pathname => (($subdir eq ".")?$file:"$subdir${FS}$file"),
	            package  => $self->{where}{$path}{$subdir},
	            realname => $realfile,
	        });
		$fi->setNotAComponent(1);
		$fi->setName($file); #override splitter

		debug2 "got".$fi->getPackage()."=>".$fi->getFullname()
		  if ($debug >= 2);
#print "<----ff:found $file in ".$fi->getPackage()." as ".$fi->getFullname(),"\n";
		return $fi;
	    }
	}
    }

    return undef;
}

#==============================================================================

sub test {
    eval { use BDE::FileSystem; };
    my $root=new BDE::FileSystem("/bbcm/infrastructure");

    my $finder=new BDE::File::Finder($root);
    $finder->setSearchPath("/bbcm/infrastructure/bde");
    $finder->addPackageSearchPath("bdet");
    $finder->addPackageSearchPath("bde+pcre");
    $finder->addPackageSearchPath("bde+stlport","stlport");
    foreach (qw[bdet_datetime.h pcre.h cassert notthere]) {
	my $where=$finder->find($_);
	if ($where) {
	    $where->dump();
	} else {
	    print "$_: *not found*\n";
	}
    }
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainright@bloomberg.net)

=head1 SEE ALSO

L<BDE::Component>, L<BDE::Util::DependencyCache>, L<BDE::Package::Include>

=cut

1;
