package BDE::Build::Options;
use strict;

use overload '""' => "toString";
use IO::File;
use FindBin;

use BDE::Object;
use vars qw(@ISA);
@ISA=qw(BDE::Object);

use BDE::Build::Invocation qw($FS $FSRE);
use BDE::Build::Uplid;
use BDE::Build::Ufid;
use BDE::Util::Nomenclature qw(isPackage isGroup isGroupedPackage);
use Symbols qw(
    PACKAGE_META_SUBDIR GROUP_META_SUBDIR TOOLS_ETCDIR DEFAULT_OPTFILE
);
use Util::Message qw(error debug debug2 debug3);

#==============================================================================

=head1 NAME

BDE::Build::Options -- Derive build options for a specified group or package.

=head1 SYNOPSIS

    my $options=new BDE::Build::Options({
        item   => 'bte',
        uplid  => new BDE::Build::Uplid(),
        ufid   => 'dbg_exc_mt',
        prefix => 'BTE_DBG_EXC_MT_'
    });

    print $options;

=head1 DESCRIPTION

B<*THIS MODULE IS DEPRECATED*> -- use L<Build::Option::Factory> instead.

This module extracts build options from the configured options files for a
given group or package, and returns the appropriate values for the
specified platform and build type.

This module does not process capabilities or understand external definitions
(i.e. C<.defs> files), and is therefore not supported for newer releases of
C<default.opts> or other metadata files. Use L<Build::Option::Factory> for
modern build applications.

=cut

#==============================================================================

# Class method: Get list of available option files for a given path.
sub getOptionFiles ($;$@) {
    my ($class,$location,@post_files)=@_;

    $class->throw("Specify location"),return () unless $location;

    $location =~ s[/][$FS]g if $FS ne '/'; # ensure consistent FS for OS
    # if we're in an uplid subdirectory, step up to the source
    $location =~ s[$FSRE(unix|windows)-([^-]+)-([^-]+)-([^-]+)-(\w+)$FSRE?$][];

    debug2 "Looking for configuration files for $location";

    my ($thisdir, $parentdir) = (reverse split('/|\\\\', $location))[0, 1];

    my $UP="..".$FS; #shorthand for 'up one directory'
    my $ETCDFLOPTS=TOOLS_ETCDIR.$FS.DEFAULT_OPTFILE; #trailing path

    # assemble list of possible locations for default and context options files
    my (@default_files,@context_files);
    if (isPackage $thisdir) {
	if (-d "$location${FS}package") {
	    # some packages are in 'index' subdirs so several places to look
	    # for the default.opts file
	    @default_files=(
		$location.$FS.$UP.$UP.$ETCDFLOPTS,
		$location.$FS.$UP.$UP.$UP.$ETCDFLOPTS,
		$location.$FS.$UP.$UP.$UP.$UP.$ETCDFLOPTS,
	    );
	    @context_files=(
	        $location.$FS.PACKAGE_META_SUBDIR.$FS.$thisdir.".opts",
	    );
	}
	if (isGroupedPackage $thisdir) {
	    #insert group overrides before package overrides
	    unshift @context_files,(
	        $location.$FS.$UP.GROUP_META_SUBDIR.$FS.$parentdir.".opts"
	    );
	}
    } elsif (isGroup($thisdir)) {
	if (-d "$location${FS}group") {
	    @default_files=(
		$location.$FS.$UP.$UP.$ETCDFLOPTS,
		$location.$FS.$UP.$UP.$UP.$ETCDFLOPTS,
            );
            @context_files=(
	        $location.$FS.GROUP_META_SUBDIR.$FS.$thisdir.".opts",
            );
	}
    } else {
	@default_files=qw[$location${FS}etc${FS}default.opts];
    }
    # only if the local tree doesn't have a default, use the tool's own.
    push @default_files,$FindBin::Bin.$FS.$UP.$ETCDFLOPTS;

    # scan candidate locations to find files that actually exist
    my @files=();

    # find the first valid default options file. At least one must exist
    foreach my $default_file (@default_files) {
	1 while $default_file =~ s|${FSRE}\w+${FSRE}\.\.${FSRE}|$FS|;
	if (-f $default_file and -r _) {
	    debug "* found default options: $default_file";
	    push @files, $default_file;
	    last; # only one default config allowed
	}
    }

    $class->throw("No default options file - searched for @default_files")
      unless @files;

    # attach any in-context files
    foreach my $context_file (@context_files) {
	1 while $context_file =~ s|${FSRE}\w+${FSRE}\.\.${FSRE}|$FS|;
	if (-f $context_file and -r _) {
	    debug "* found source options: $context_file";
	    push @files, $context_file;
	}
    }

    # attach post files if valid
    foreach my $post_file (@post_files) {
	1 while $post_file =~ s|${FSRE}\w+${FSRE}\.\.${FSRE}|$FS|;
	if (-f $post_file and -r _) {
	    debug "* found additional options: $post_file";
	    push @files, $post_file;
	} else {
	    $class->throw("cannot read post file '$post_file'");
	}
    }

    return @files; #the first element is always the default config
}

# set the package and group of this options object, if relevant, based on the
# supplied path
sub setLocationContext ($$) {
    my ($self,$location)=@_;

    my ($thisdir, $parentdir) = (reverse split(/\Q$FS\E/, $location))[0, 1];

    if ($thisdir =~ /^$parentdir/ && -d "$location${FS}package"
	  && -d "$location${FS}..${FS}group") {
        $self->setPackage($thisdir);
	$self->setGroup($parentdir);
	return 2;
    } elsif (isGroup($thisdir) && -d "$location${FS}group") {
       $self->setPackage(undef);
       $self->setGroup($thisdir);
	return 1;
    }

    return 0;
}

#------------------------------------------------------------------------------
# constructor support

sub initialiseFromScalar ($$) {
    my ($self,$scalar)=@_;

    $self->initialiseFromHash({
	uplid   => BDE::Build::Uplid->new(),
	ufid    => BDE::Build::Ufid->new(BDE::Build::Ufid::DEFAULT_UFID),
        from    => $scalar
    });
}

sub initialiseFromHash ($$) {
    my ($self,$args)=@_;

    $self->throw("Specify ufid"),return 0 unless defined $args->{ufid};
    $self->throw("Specify uplid"),return 0 unless defined $args->{uplid};

    $self->setUfid(delete $args->{ufid});
    $self->setUplid(delete $args->{uplid});

    # process the 'from' argument
    if (my $from=$args->{from}) {
	if (-f $from) {
	    # initialise from single option file
	    $self->processDefaultOptionFile($from);
	    $self->setLocationContext($from);
	} elsif (-d $from) {
	    # initialise from location (multiple option files)
	    my ($def_opt_file,@opt_files)=$self->getOptionFiles($from);
	    $self->setLocationContext($from);
	    unless ($def_opt_file) {
		$self->throw("Initialise failed: no configuration in '$from'");
	    } else {
		$self->processDefaultOptionFile($def_opt_file);
		$self->processOptionFile($_) foreach @opt_files;
	    }
	} else {
	    $self->throw("Initialise failed: '$from' not a file or directory");
	}
	delete $args->{from};
    }

    $self->SUPER::initialiseFromHash($args);
    $self->{options}||={};
    $self->{defaults}||={};

    return 1; #done
}

#------------------------------------------------------------------------------

# my $cachedopts=cached BDE::Build::Options({...});
{ my $cache={};

  sub cached ($$) {
      my ($self,$init)=@_;

      #pre-establish values from defaults (if necessary) to derive full key
      $init->{uplid} ||= BDE::Build::Uplid->new(),
      $init->{ufid}  ||= BDE::Build::Ufid->new(BDE::Build::Ufid::DEFAULT_UFID),

      my $key=$init->{from}."|".$init->{uplid}."|".$init->{ufid};

      unless (exists $cache->{$key}) {
	  $cache->{$key}=new $self($init);
	  debug "Options cache added: $key";
      } else {
	  debug "Options cache hit: $key";
      }

      return $cache->{$key};
  }
}

#------------------------------------------------------------------------------

# add prefixes to embedded macros in definitions if (and only if) those macros
# are themselves present in the list of defined options.
sub processPrefixMacros ($$$) {
    my ($self,$value,$prefix)=@_;

    foreach my $var (keys %{$self->{options}}) {
        $value =~ s|\$\($var\)|\$(${prefix}${var})|sg;
    }

    return $value;
}

#------------------------------------------------------------------------------
# parse specified option file and override matching variables

sub processDefaultOptionFile ($$) {
    return $_[0]->processOptionFile($_[1],1);
}

sub processOptionFile ($$;$) {
    my ($self,$fname,$is_default) = @_;
    $is_default ||=0;

    my $optfh=IO::File->new($fname,"r") ||
      $self->throw("cannot open '$fname': $!");

    my $failed = 0;
    my $saveline = "";

    # TODO: read option file into class data if as-yet unread
    #       match class data against this object's criteria

    while (<$optfh>) {
	chomp;

	# ignore blank lines and comments
	next if /^\s*$/;
	next if /^\s*\#/;

	# continuations
	if (/(.*)\\\s*$/) {
	    if ($saveline) {
		$saveline.=" $1";
	    } else {
		$saveline = $1;
	    }

	    next;
	} elsif ($saveline) {
	    $_ = "$saveline $_";
	    $saveline = "";
	}

	unless ($self->processOptionLine($_,$is_default)) {
	    $failed=1;
	    error("$fname:$.: bad syntax: $_");
	}
    }


    close $optfh;
    return $failed?0:1;
}

# check whether passed line matches configured uplid and ufid and update object
# if so. Return 0 if the line is not a valid line, 1 if it is valid but doesn't
# match and 2 if it is valid, matched, and updated the object.
# NOTE: this sub should be split into parsing and matching routines and used
# in caching schema instead.
sub processOptionLine ($$$) {
    my ($self,$line,$is_default)=@_;
    $is_default ||=0;

    unless ($line =~
	    /^\s*(\!{1,2}\s+)?(\S+)\s+(\S+)\s+(\S+)\s*\=\s*(.*?)\s*$/o) {
	return 0; #failed
    }

    my ($override, $m_uplid, $m_ufid, $varname, $varval) = ($1,$2,$3,$4,$5);

    $varname = "\U$varname\E";

    if (defined($override) && $override =~ /^\s*$/) {
	$override = undef;
    }

    debug3("$.: new spec: ovr: '" .
	  ($override || '') . "', uplid: " .
	  "'$m_uplid', ufid: '$m_ufid', var: '$varname'" .
	  ", val: '$varval'");

    if ($self->getUplid) {
	# match the UPLID
	$m_uplid =~ s/\*/[^-]+/g;
	$m_uplid =~ s/\?/[^-]/g;
	debug3("$.: <- uplid ".$self->getUplid()." <=> $m_uplid");
	return 1 unless $self->getUplid() =~ /^$m_uplid/; #ok nonmatch
    }

    if ($self->getUfid) {
	unless ($self->getUfid()->isValidWildUfid($m_ufid)) {
	    error("$.: bad UFID '$m_ufid' in configuration");
	    return 0; #failed
	}

	# match the UFID
	debug3("$.: <- ufid  ".$self->getUfid()." <=> $m_ufid");
	return 1 unless $self->getUfid()->match($m_ufid); #ok nonmatch
    }

    # successfull match
    debug2("$.: -> match: $varname='$varval'");
    #debug("$.:     current value: '" . $self->getOption($varname) . "'");

    if (defined $override) {
	if ($override =~ /\!\!/) {
	    # replace value
	    if ($is_default) {
		$self->setDefaultOption($varname => $varval);
	    }
	    $self->setOption($varname => $varval);
	} else {
	    # set to default
	    if ($is_default) {
		$self->throw("Cannot reset to default value in default file");
	    } else {
		$self->setOptionFromDefault($varname);
	    }
	}
    } else {
	# append
	if ($is_default) {
	    $self->appendToDefaultOption($varname => $varval);
	}
	$self->appendToOption($varname => $varval);
    }

    debug3("$.:     new value: '" . $self->getOption($varname) . "'");

    return 2; #ok match
}

#------------------------------------------------------------------------------

sub _getOption ($$$;$) {
    my ($self,$attr,$var,$prefix)=@_;

    return "" unless exists $attr->{$var};
    if ($prefix) {
	return $self->processPrefixMacros($attr->{$var},$prefix);
    }
    return $attr->{$var};
}

sub getOption ($$;$) {
    return $_[0]->_getOption($_[0]->{options},$_[1],$_[2]);
}

sub getDefaultOption ($$;$) {
    return $_[0]->_getOption($_[0]->{defaults},$_[1],$_[2]);
}

#---

sub setOption ($$$) {
    my ($self,$var,$value)=@_;
    return $self->{options}{$var}=$value;
}

sub setDefaultOption ($$$) {
    my ($self,$var,$value)=@_;
    return $self->{defaults}{$var}=$value;
}

sub setOptionFromDefault ($$) {
    my ($self,$var)=@_;

    if (exists $self->{defaults}{$var}) {
	$self->{options}{$var}=$self->{defaults}{$var};
	return 1;
    }

    return 0;
}

sub setDefaultFromOption ($$) {
    my ($self,$var)=@_;

    if (exists $self->{options}{$var}) {
	$self->{defaults}{$var}=$self->{options}{$var};
	return 1;
    }

    return 0;
}

sub setDefaultsFromOptions ($) {
    %{ $_[0]->{defaults} } = %{ $_[0]->{options} };
}

sub appendToOption ($$$) {
    my ($self,$var,$value)=@_;

    if (exists $self->{options}{$var}) {
	$self->{options}{$var}.=" ".$value;
    } else {
	$self->{options}{$var}=$value;
    }
}

sub appendToDefaultOption ($$$) {
    my ($self,$var,$value)=@_;

    if (exists $self->{defaults}{$var}) {
	$self->{defaults}{$var}.=" ".$value;
    } else {
	$self->{defaults}{$var}=$value;
    }
}

sub clearOptions ($) { $_[0]->{options}={}; }

sub clearDefaultOptions ($) { $_[0]->{defaults}={}; }

sub setUfid ($$) {
    my ($self,$ufid)=@_;

    if ($ufid) {
	$ufid=new BDE::Build::Ufid($ufid) unless ref $ufid;
    }
    $self->{ufid}=$ufid;
}

sub getUfid ($) { return $_[0]->{ufid}; }

sub setUplid ($$) {
    my ($self,$uplid)=@_;

    if ($uplid) {
	$uplid=new BDE::Build::Uplid($uplid) unless ref $uplid;
    }
    $self->{uplid}=$uplid;
}

sub getUplid ($) { return $_[0]->{uplid}; }

sub setGroup ($$) { $_[0]->{group}=$_[1]; }
sub getGroup ($)  { return exists($_[0]->{group})?$_[0]->{group}:undef }

sub setPackage ($$) { $_[0]->{package}=$_[1]; }
sub getPackage ($)  { return exists($_[0]->{package})?$_[0]->{package}:undef }

#------------------------------------------------------------------------------
# extra
# skip
# prefix

# output variables' assignments
sub toString ($$) {
    my ($self,$args)=@_;
    my @vars;

    #TD: validation of arguments plus default when passed a scalar
    #$args=$self->validArgs($args,qw[extra skip prefix],scalar => "prefix");

    $args ||= {};
    $args = { prefix => $args } unless ref $args;
    $args->{prefix} ||= $self->{prefix} || '';

    if ($args->{options}) {
	@vars = ref($args->{options})?@{$args->{options}}:($args->{options});
    } else {
	@vars = sort keys %{$self->{options}};
    }

    my $string="";
    foreach my $k (@vars) {
	my $v=$self->{options}{$k};

	next if $v=~/^\s*$/ and
	  exists($args->{skip})?$args->{skip}:$self->{skip};

	$v =~ s/\s*(.*?)\s*//;
        if ($args->{prefix}) {
            $v=$self->processPrefixMacros($v,$args->{prefix});
        }

	# explicit substitutions: ::GROUP:: => $self->{group} => 'bce' => 'BCE
	$v =~ s/::([A-Z]+)::/uc($self->{lc($1)})/e;
	$string.=$args->{prefix}.$k." = ".$v."\n";
    }

    if (exists($args->{extra})?$args->{extra}:$self->{extra}) {
	my %extras=$self->getExtraOptions($args->{prefix});
	$string .= join "\n",map { "$_ = $extras{$_}" } sort keys %extras;
    }

    return $string;
}

# return derived options from uplid and ufid
sub getExtraOptions ($;$) {
    my ($self,$args)=@_;

    $args ||= {};
    $args = { prefix => $args } unless ref $args;
    $args->{prefix} ||= $self->{prefix} || '';

    my %extras = (
        $args->{prefix}."UPLID"            => $self->{uplid}->toString(),
        $args->{prefix}."UFID"             => $self->{ufid}->toString(1),
	$args->{prefix}."LIBUFID"          => $self->{ufid}->toString(0),
    );

    return wantarray?%extras:\%extras;
}

#------------------------------------------------------------------------------

sub test {
    #Non-fatal throw
    {
        no warnings 'once';
        *BDE::Build::Options::throw = sub { print "Throw! $_[0]: $_[1]\n" };
    }

    Util::Message::set_debug(1);

    my $prefix="F:/views/bde_devwin/";

    my $options_file = "$prefix/infrastructure/etc/default.opts";
    1 while $options_file =~ s|/[^/]+/\.\./|/|;
    $options_file =~ s|/|$FS|g;

    my $options=new BDE::Build::Options($options_file);
    print $options->toString();
    print $options->dump();
    foreach (qw(OPTS_FILE AR CXX)) {
	print "$_ = ",$options->getOption($_),"\n";
    }
    foreach (qw(OPTS_FILE AR CXX)) {
	print "PREFIX_$_ = ",$options->getOption($_,"PREFIX_"),"\n";
    }
    $options->setOption(NONSUCH => q[$(UNPREFIXED) $(CXX)] );
    print "NONSUCH => ",$options->getOption("NONSUCH"),"\n";
    print "PREFIX_NONSUCH => ",$options->getOption("NONSUCH","PREFIX_"),"\n";

    Util::Message::set_debug(2);
    my $location;

    foreach my $location (
        "$prefix/infrastructure/groups/bce/bces",
        "$prefix/infrastructure/groups/bce",
        "/foobar",
        undef
    ) {
        my $fslocation=$location;
	$fslocation=~s|/|$FS|g;

	my @files=$options->getOptionFiles($fslocation);
	print "Files: @files\n";
	$options->setLocationContext($fslocation);
	print "Package: ",$options->getPackage(),"\n";
	print "Group: ",$options->getGroup(),"\n";
    }
}

#------------------------------------------------------------------------------

=head1 SEE ALSO

L<Build::Option::Factory>, L<BDE::Build::Uplid>, L<BDE::Build::Ufid>.

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net), abstracted from original code by
various authors.

=cut

1;
