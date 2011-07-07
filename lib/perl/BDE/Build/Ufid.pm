package BDE::Build::Ufid;
use strict;

use vars qw(@ISA);
use overload '""' => "toString", fallback => 1;

use BDE::Object;
@ISA=qw(BDE::Object);

use Util::Message qw(fatal);

#==============================================================================

=head1 NAME

BDE::Build::Ufid - Class for the Universal (Build) Flag ID (a.k.a. UFID)

=head1 SYNOPSIS

    my $ufid=new BDE::Build::Ufid(); #default

    print "Library UFID is: $ufid\n";
    print "Full UFID is: ",$ufid->toString(1),"\n";
    print "MT-enabled\n" if $ufid->hasFlag("mt");
    print "foo: not a valid flag!" unless $ufid->isValidFlag("foo");

    $ufid->setFlag("shr");
    $ufid->unsetFlag("exc");

    print "Library UFID is now: $ufid\n";
    print "Full UFID is now: ",$ufid->toString(1),"\n";

    my $ufid2=new BDE::Build::Ufid("dbg_exc_mt_shr_64");
    my @flags=$ufid2->getFlags();

    my $ufid3=new BDE::Build::Ufid("dbg_exc");
    print "$ufid2 matches $ufid3" if $ufid2->match($ufid3);

=head1 DESCRIPTION

This module encapsulates UFID (Uniform (Build) Flag ID) derivation in the form:

    I<flag>[_I<flag>[_I<flag>...]]

Where C<flag> can have the following values and meanings:

    dbg      Build with debugging information
    opt      Build optimized
    exc      Exception support
    mt       Multithread support
    ndebug   Build with NDEBUG defined
    64       Build for 64-bit architecture
    safe     Build safe (paranoid) libraries
    safe2    Build safe2 (paranoid AND binary-incompatible) libraries
    shr      Build dynamic libraries
    rtd      Build with dynamic MSVC runtime (Windows only)
    pic      Build static libraries with PIC support (often redundant)
    ins      Build with Insure++
    pure     Build with Purify
    purecov  Build with Pure Coverage
    qnt      Build with Quantify
    win      Use windowed GUI for instrumenting tools (e.g dbg_pure_win)
    stlport  Build with the STLPort v.4 Standard Library supplied with Sun CC
             compiler (-library=stlport4, Sun only)

Example:

    dbg_exc_mt

In string context the flags set in a UFID object are returned in a
predictable cannonical order, according to their position in the list above
and irrespective of the order in which they were set.

The UFID has two representations. By default, 'hidden' flags are not shown.
To render the UFID including the hidden flags, call the C<"toString"> method
directly with a true argument. Currently the only hidden flag is C<shr>, so
the default representation is the 'library' UFID, suitable for use in
constructing library names (where the extension communicates the static or
shared nature of the library).

=cut

#------------------------------------------------------------------------------

# index into ufid_flags
use constant VISIBLE      => 0;
use constant ORDER        => 1;
use constant DESC         => 2;

# whether or not a flag should appear in the normalised UFID
use constant SHOW         => 1;
use constant HIDE         => 0;

# ordering
use constant ORDER_FRONT  => 1;
use constant ORDER_MIDDLE => 50;
use constant ORDER_BACK   => 99;

# allowed UFID flags -> flags' descriptions
my %ufid_flags = (
  dbg     => [ SHOW, ORDER_FRONT ,     'Build with debugging information'   ],
  opt     => [ SHOW, ORDER_FRONT,      'Build optimized'                    ],
  exc     => [ SHOW, ORDER_MIDDLE,     'Exception support'                  ],
  mt      => [ SHOW, ORDER_MIDDLE + 1, 'Multithread support'                ],
  ndebug  => [ SHOW, ORDER_MIDDLE + 2, 'Build with NDEBUG defined'          ],
  64      => [ SHOW, ORDER_BACK   - 5, 'Build for 64-bit architecture'      ],
  safe2   => [ SHOW, ORDER_BACK   - 4,
                'Build safe2 (paranoid and binary-incompatible) libraries'  ],
  safe    => [ SHOW, ORDER_BACK   - 3, 'Build safe (paranoid) libraries'    ],
  shr     => [ HIDE, ORDER_BACK   - 2, 'Build dynamic libraries'            ],
  pic     => [ SHOW, ORDER_BACK   - 1, 'Build static PIC libraries'         ],
  rtd     => [ SHOW, ORDER_BACK,       'Build with dynamic MSVC runtime'    ],
  ins     => [ SHOW, ORDER_BACK,       'Build with Insure++'                ],
  pure    => [ SHOW, ORDER_BACK,       'Build with Purify (no windows)'     ],
  pure    => [ SHOW, ORDER_BACK,       'Build with Purify (windows)'        ],
  purecov => [ SHOW, ORDER_BACK,       'Build with Pure Coverage'           ],
  qnt     => [ SHOW, ORDER_BACK,       'Build with Quantify'                ],
  win     => [ SHOW, ORDER_BACK   + 1, 'Use GUI for instrumenting tools'    ],
  stlport => [ SHOW, ORDER_BACK      , 'Build with STLPort on Sun'          ],
);

use constant DEFAULT_UFID => "dbg_exc_mt";

#------------------------------------------------------------------------------
# Class methods/Subroutines

sub isValidFlag ($;$) {
    my ($self,$flag)=@_;
    $flag=$self unless $flag;

    return (defined $ufid_flags{$flag})?1:0;
}

sub isValidWildFlag ($;$) {
    my ($self,$flag)=@_;
    $flag=$self unless $flag;

    return 2 if $flag=~/^[_*]?$/;
    return isValidFlag($flag);
}

sub isValidWildUfid ($;$) {
    my ($self,$ufid)=@_;

    foreach my $flag (split /_+/,$ufid) {
	return 0 unless isValidWildFlag($flag);
    }
    return 1;
}

#------------------------------------------------------------------------------

sub setFlag ($$) {
    my ($self,$flag)=@_;

    unless (defined $ufid_flags{$flag}) {
	fatal("bad UFID flag: $flag");
    }

    $self->{flags}{$flag}=1;
    return 1;
}

sub unsetFlag ($$) {
    my ($self,$flag)=@_;

    if ($self->{flags}{$flag}) {
	delete $self->{flags}{$flag};
	return 1;
    }

    return 0;
}

sub hasFlag($$) {
    my ($self,$flag)=@_;

    return ($self->{flags}{$flag})?1:0;
}

# modern wrapper for 'flags' below that forces on return of all flags
# see also 'flags' below.
sub getFlags ($) {
    return $_[0]->flags(1);
}

# return flags, omitting hidden ones unless asked for them
sub flags ($;$) {
    my ($self,$keep_hidden)=@_;

    my @flags=keys %{$self->{flags}};

    unless ($keep_hidden) {
        @flags = grep { $ufid_flags{$_}[VISIBLE]==SHOW } @flags;
    }

    @flags = sort {
	$ufid_flags{$a}[ORDER] <=> $ufid_flags{$b}[ORDER]
    } @flags;


    return wantarray?@flags:\@flags;
}

#------------------------------------------------------------------------------

# check requested UFID for validity
sub fromString ($$) {
    my ($self,$ufid) = @_;

    $self=$self->new() unless ref $self; #called as Class method?

    # disassemble string and set flags from element parts
    $self->setFlag($_) foreach split /_+/, "\L$ufid\E";

    return 1;
}

# convert to string form. Include 'hidden' flags if argument is true.
sub toString ($;$) {
    my ($self,$keep_hidden) = @_;

    return join "_",$self->flags($keep_hidden);
}

# match against specified ufid, which may be wildcarded. The ufid must contain
# each flag mentioned in the specified ufid
sub match ($$) {
    my ($self, $match) = @_;

    return 2 if $match=~/^[_*]?$/;

    # do the match
    foreach my $matchflag (split(/_+/, $match)) {
	return 0 unless $self->hasFlag($matchflag);
    }

    return 1;
}

#------------------------------------------------------------------------------

# return definition string (list of -Defines) for this uplid
# DEPRECATED - now handled by default.opts
sub definitionString ($) {
    my $self=shift;

    my @flags=$self->flags(1);

    return join " ",map { "-DBDE_BUILD_TARGET_".uc($_) } @flags;
}

#==============================================================================

sub test () {
    my $string="dbg_mt";
    my $ufid=new BDE::Build::Ufid($string);
    print "dbg: 1==",$ufid->hasFlag("dbg"),"\n";
    print "exc: 0==",$ufid->hasFlag("exc"),"\n";
    print "mt : 1==",$ufid->hasFlag("mt"),"\n";
    $ufid->setFlag("exc");
    print "exc: 1==",$ufid->hasFlag("exc"),"\n";
    $ufid->unsetFlag("mt");
    print "mt : 0==",$ufid->hasFlag("mt"),"\n";
    eval { $ufid->setFlag("foo") };
    print "flags now:",(join ',',$ufid->flags),"\n";
    print "toString :$ufid\n";
    print "isValidFlag(dbg)    : 1==",isValidFlag("dbg"),"\n";
    print "isValidFlag(foo)    : 0==",isValidFlag("foo"),"\n";
    print "isValidFlag(*)      : 0==",isValidFlag("*"),"\n";
    print "isValidWildFlag(*)  : 2==",isValidWildFlag("*"),"\n";
    print "isValidWildFlag(_)  : 2==",isValidWildFlag("_"),"\n";
    print "isValidWildFlag(foo): 0==",isValidWildFlag("foo"),"\n";
    print "match(dbg)          : 1==",$ufid->match("dbg"),"\n";
    print "match(exc)          : 1==",$ufid->match("exc"),"\n";
    print "match(mt)           : 0==",$ufid->match("mt"),"\n";
    print "match(_)            : 2==",$ufid->match("_"),"\n";
    print "match(dbg_exc)      : 1==",$ufid->match("dbg_exc"),"\n";
    $ufid->setFlag("shr");
    print "shr: 1==",$ufid->hasFlag("shr"),"\n";
    print "toString: $ufid\n";
    print "toString(+hidden): ",$ufid->toString(1),"\n";
    print "match(dbg)          : 1==",$ufid->match("dbg"),"\n";
    print "match(exc)          : 1==",$ufid->match("exc"),"\n";
    print "match(mt)           : 0==",$ufid->match("mt"),"\n";
    print "match(_)            : 2==",$ufid->match("_"),"\n";
    print "match(dbg_exc)      : 1==",$ufid->match("dbg_exc"),"\n";
    print "match(dbg_shr)      : 1==",$ufid->match("dbg_shr"),"\n";
    print "match(opt_shr)      : 0==",$ufid->match("opt_shr"),"\n";
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_build.pl>

=cut

1;
