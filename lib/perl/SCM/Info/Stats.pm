# vim:set ts=8 sts=4 noet:

package SCM::Info::Stats;

use warnings;
use strict;

use base qw/SCM::Info/;

use CGI				qw/param start_html end_html/;
use Date::Manip			qw/ParseDate UnixDate DateCalc/;
use List::Util			qw/sum/;

use SCM::Symbols		qw/SCM_CSDB SCM_CSDB_DRIVER/;
use SCM::CSDB::Access::Stats;

my @params = qw/goback bigs filetype extensions/;
my $csq = SCM::CSDB::Access::Stats->new(database => SCM_CSDB, driver => SCM_CSDB_DRIVER);

my $left = 'style="border-left-style:solid;border-left-width:2px"';
my $right = 'style="border-right-style:solid;border-right-width:2px"';

$| = 1;

sub init {
    my ($self) = @_;

    $self->{$_} = param($_) || 0 for @params;

    $self->{goback} ||= 20;
}

sub handle {
    my ($self) = @_;

    if ($self->{bigs}) {
	chomp (my @uors = <DATA>);
	$self->{uors} = \@uors;
    }

    if ($self->{filetype}) {
	$self->{filetype} = [ split /,/, $self->{filetype} ];
    }

    $self->content_type; 
    
    my @intervals = reverse get_intervals($self->{goback});
    if ($self->{presentation} eq 'html') {
	return $self->html(@intervals);
    } else {
	return $self->csv(@intervals);
    }
}

sub html {
    my ($self, @intervals) = @_;

    print start_html(-title	=> 'SCM Metrics',
		     -author	=> 'tvonparseval@bloomberg.net',
		     -style	=> { -code => $self->css, });

    print <<EOTABLE;
<table align="center" width="%100">
    <thead>
	<tr>
	<th align="center" $right>Week</th>
	<th align="center" $right>Quality</th>
	<th colspan="4" align="center" $left>CSs swept</th>
	<th colspan="4" align="center" $left>Files swept</th>
	<th colspan="4" align="center" $left>Avg num per CS</th>
	<th colspan="12" align="center" $left>% of CSs swept/failed/rolledback</th>
	</tr>
    </thead>
    <tbody>
EOTABLE

    for (@intervals) {
	my @average = $csq->getSweepStats(@$_, 
		-uors => $self->{uors}, 
		-type => $self->{filetype},
		-ext  => $self->{extensions},
	);

	my $states;
	if ($self->{completion}) {
	    $states  = $csq->getChangeSetCompletionStates(@$_);
	} else {
	    @{$states->{$_}}{qw/failed rolledback swept/} = (0, 0, 0) for qw/move bugf emov stpr/;
	}

	$self->one_row_html($_, \@average, $states);
    }

    print <<EOTABLE;
    </tbody>
    </table>
EOTABLE

    print end_html;
}

sub csv {
    my ($self, @intervals) = @_;

    print "week,quality,cs_swept_move,cs_swept_bugf,cs_swept_emov,cs_swept_stpr," .
	  "files_swept_move,files_swept_bugf,files_swept_emov,files_swept_stpr," .
	  "files/cs_move,files/cs_bugf,files/cs_emov,files/cs_stpr," .
	  "cs_swept_move,cs_failed_move,cs_rb_move,cs_swept_bugf,cs_failed_bugf,cs_rb_bugf," .
	  "cs_swept_emov,cs_failed_emov,cs_rb_emov,cs_swept_stpr,cs_failed_stpr,cs_rb_stpr\n";

    for (@intervals) {
	my @average = $csq->getSweepStats(@$_, $self->{uors}, $self->{filetype});
	my $states  = $csq->getChangeSetCompletionStates(@$_);
	$self->one_row_csv($_, \@average, $states);
    }

}

sub one_row_html {
    my ($self, $week, $avg, $stat) = @_;
    my ($start, $end) = @$week;
    s/ .*// for $start, $end;

    print <<EOROW;
    <tr>
	<td align="center" $right>$start</td>
	<td align="center" $right>@{[quality($avg)]}</td>
	<td align="center" class="move" $left>$avg->[0]{move}</td>
	<td align="center" class="bugf">$avg->[0]{bugf}</td>
	<td align="center" class="emov">$avg->[0]{emov}</td>
	<td align="center" class="stpr" $right>$avg->[0]{stpr}</td>
	<td align="center" class="move" $left>$avg->[1]{move}</td>
	<td align="center" class="bugf">$avg->[1]{bugf}</td>
	<td align="center" class="emov">$avg->[1]{emov}</td>
	<td align="center" class="stpr" $right>$avg->[1]{stpr}</td>
	<td align="center" class="move" $left>@{[avg($avg, 'move')]}</td>
	<td align="center" class="bugf">@{[avg($avg, 'bugf')]}</td>
	<td align="center" class="emov">@{[avg($avg, 'emov')]}</td>
	<td align="center" class="stpr" $right>@{[avg($avg, 'stpr')]}</td>
EOROW
    $self->states($stat);
    print "    </tr>\n";
}

sub one_row_csv {
    my ($self, $week, $avg, $stat) = @_;
    my ($start, $end) = @$week;
    s/ .*// for $start, $end;

    my @all = qw/move bugf emov stpr/;
    print join ',' =>
	    $start, quality($avg), @{$avg->[0]}{@all},
	    @{$avg->[1]}{@all}, map(avg($avg, $_), @all),
	    map(perc($stat, $_), @all);
    print "\n";
}

sub avg {
    my ($avg, $key) = @_;
    return 0 if !$avg->[0]{$key};
    return sprintf "%.2f", $avg->[1]{$key} / $avg->[0]{$key};
}

sub states {
    my ($self, $stats) = @_;

    my $style;
    for (qw/move bugf emov stpr/) {
	my @stats = perc($stats, $_);
	$style = $_ eq 'move' ? $left : '';
	print <<EOCELLS
	<td align="center" class="$_" $style>$stats[0]</td>
	<td align="center" class="$_">$stats[1]</td>
	<td align="center" class="$_">$stats[2]</td>
EOCELLS
    }
}

sub perc {
    my ($stat, $move) = @_;
    my @all = qw/swept failed rolledback/;

    my $swept = sprintf "%.1f",
		100 * ($stat->{$move}{swept} / (sum(@{$stat->{$move}}{@all}) || 1));
    my $failed = sprintf "%.1f",
		 100 * ($stat->{$move}{failed} / (sum(@{$stat->{$move}}{@all}) || 1));
    my $rolledback = sprintf "%.1f",
		     100 * ($stat->{$move}{rolledback} / (sum(@{$stat->{$move}}{@all}) || 1));

    $_ eq '100.0' and $_ = 100 for $swept, $failed, $rolledback;

    return $swept, $failed, $rolledback;
}

sub quality {
    my $avg = shift;
    sprintf "%.3f", $avg->[1]{move} / (sum(@{$avg->[1]}{qw/move bugf emov/}) || 1);
}

sub get_intervals {
    my $n = shift;
    my @intervals;
    my ($year, $week) = split /:/, UnixDate("today", '%Y:%W');
    $week = sprintf "%02i", $week;
    my $start = ParseDate("$year-W$week-1");
    my $end = DateCalc($start, "+6 days 23 hours 59 minutes 59 seconds");
    unshift @intervals, [ iso8601($start), iso8601($end) ];
    for (1 .. $n) {
        $start = DateCalc($start, "-7 days");
        $end = DateCalc($end, "-7 days");
        unshift @intervals, [ iso8601($start), iso8601($end) ];
    }
    return @intervals;
}

sub iso8601 {
    my $date = shift;
    $date =~ s/(\d\d\d\d)(\d\d)(\d\d)(.*)/$1-$2-$3 $4/;
    return $date;
}

sub styles {
    qw/html csv/;
}

1;
__DATA__
bde
db2
oop
otl
zde
glib
mqcm
xml2
boost
asn1cpp
openssl
sysutil
xercesc
gnuiconv
informix
intbasic
mqseries
nwsxcvrt
unixODBC
mtgenosrc
f77override
bbinc/prodins
bbinc/Cinclude
ace
bce
bse
crd
fat
gto
tr1
tsb
ruli
l_fcu
l_lme
fietasn
fofrmsg
mstrserv
a_apdcmsg
a_apidmsg
a_apiymsg
c_nwssrch
numformat
a_apiy2msg
a_gtdb2msg
tktproxymsg
DBInterfaces
bbinc/servarch
bae
bsa
bte
isl
sslplus
bsc
smr
glpm
z_bae
cixmsg
fabcmn
a_bteso
xml
a_xml2
newsism
a_xercesc
a_ossl
a_bcedb2
fablog
bas
fab
dmsgdb
a_basmq
portmsg
fas
hfc
hfs
tsh
acq
aeb
aum
bap
bcl
bdd
big
cdi
cix
crf
efp
ems
fal
faq
fde
fto
fxb
fxi
fxu
fxx
gap
gee
goo
gpg
gtb
hfb
hfd
hft
ird
irg
isb
isf
isu
jmf
lgy
mga
mgb
mgk
mgp
mgu
msg
mtc
mtu
pfl
pmu
pom
ptd
qrd
rgt
rpo
stk
swt
tae
tag
tbe
tca
tk2
tkr
tkt
tom
tpa
tpc
tpl
tsa
tsf
tsi
tsl
tsm
tsu
twm
utl
vap
vwp
bbdm
fxpv
gdmo
gsvc
gsvg
gtbu
nqms
olgy
outl
pben
pbls
test
a_xmf
bbapi
bbipc
bbsvr
e_ipc
gctrl
gentb
gtest
gtkdm
isism
l_bbg
l_bbo
l_bbw
l_blp
l_cdb
l_cna
l_cnb
l_cny
l_crd
l_dat
l_fcl
l_fcw
l_fix
l_fps
l_fxa
l_fxf
l_fxg
l_fxo
l_fxx
l_gui
l_isa
l_oms
l_scr
l_tbf
l_tfo
l_tfs
mtgui
pdsvc
rebal
snsvc
tsism
tslst
z_gtb
z_hft
acclib
aeback
aescrn
aeutil
bbglib
btscrn
btutil
cciapi
dbutil
eorlib
f_lpib
f_xxbr
f_xxct
f_xxgp
f_xxhg
f_xxod
f_xxsm
faicpp
fcblib
feutil
fiwrap
ftscrn
ftutil
fxutil
glibmm
gtkapp
gtkbdd
gtscrn
gtutil
ibutil
intlib
ioioff
ismsor
mlscrn
mlutil
nwsvwr
otutil
peutil
s_bass
squawk
tkrlib
trdmon
tsaesu
a_basfs
a_baslt
a_bdema
aeptrdb
appscrn
apputil
bbtsapi
calclib
citnews
crdutil
datelib
derscrn
derutil
emsscrn
expat_g
f_clpdr
f_crcbe
f_crovs
f_eqhvg
f_eqtca
f_mtcmo
f_mtnyt
f_xxbbt
f_xxbep
f_xxbwx
f_xxcem
f_xxems
f_xxeor
f_xxetk
f_xxexc
f_xxfos
f_xxioi
f_xxitm
f_xxmav
f_xxmax
f_xxmov
f_xxmrr
f_xxmte
f_xxsor
f_xxsuo
f_xxtag
f_xxtkt
f_xxvap
f_xxvat
favlmid
faxmgui
fietbas
fietlib
fticket
futscrn
gobject
gtkcore
icpplib
intutil
ismaalt
ismuent
ismuser
misutil
msgutil
newsgui
niorlib
nscrlib
nwsread
portmid
prsscrn
prsutil
rptscrn
rptutil
synutil
tcautil
telutil
tomslib
tradrpt
trdscrn
trdutil
z_l_fxo
z_l_tbf
z_l_tfs
a_comdb2
apipmlib
backutil
bbserver
bregutil
calcsync
cardscmn
dcdfutil
eqrtsmon
eqtyapps
eqtyutil
f_clprep
f_cmcmip
f_crftmq
f_crfxcf
f_crfxdb
f_crfxip
f_crfxpa
f_crvcal
f_crwvol
f_crxxfx
f_eqcitr
f_eqhivg
f_eqlpqr
f_eqmbtr
f_eqomon
f_eqopsa
f_eqovch
f_eqovmc
f_eqsmdv
f_eqvcmp
f_inlmfb
f_inlmwh
f_lpnlrt
f_mtades
f_mtallq
f_mtdldu
f_mtldes
f_mtmbss
f_mtratc
f_mtrchg
f_mttbap
f_mtvall
f_wstzro
f_xxaalt
f_xxacdr
f_xxacms
f_xxadsk
f_xxamap
f_xxamcr
f_xxamon
f_xxapid
f_xxaxsu
f_xxbass
f_xxbbat
f_xxbbda
f_xxbbdp
f_xxbbdr
f_xxbcmp
f_xxbepc
f_xxbfco
f_xxbflf
f_xxbfmc
f_xxbkpr
f_xxblal
f_xxblpx
f_xxboso
f_xxbpdb
f_xxbreg
f_xxbrrp
f_xxbrtf
f_xxbskt
f_xxbste
f_xxbsvy
f_xxbtvm
f_xxbwmx
f_xxbwrx
f_xxcact
f_xxccpm
f_xxcdsl
f_xxclad
f_xxcmfs
f_xxcmpu
f_xxcolm
f_xxcust
f_xxdcdf
f_xxddrv
f_xxdmda
f_xxdmdl
f_xxdrqs
f_xxebnd
f_xxedgs
f_xxefsc
f_xxemsb
f_xxeorg
f_xxeqap
f_xxessc
f_xxesui
f_xxfcmt
f_xxfixd
f_xxfixs
f_xxflng
f_xxftmq
f_xxfudt
f_xxfuna
f_xxfxby
f_xxgmgr
f_xxgoal
f_xxgtcm
f_xxgtdd
f_xxgtfe
f_xxgtkx
f_xxgtpl
f_xxgtsa
f_xxgtsb
f_xxgtsc
f_xxgtsd
f_xxhier
f_xxhmgr
f_xxirdg
f_xxisen
f_xxixsu
f_xxlebc
f_xxlmgr
f_xxmdtf
f_xxmemc
f_xxmftb
f_xxmgip
f_xxmgsi
f_xxmktp
f_xxmtkt
f_xxmtmr
f_xxmycs
f_xxnior
f_xxnqms
f_xxomlm
f_xxorqs
f_xxoten
f_xxpcha
f_xxpdfa
f_xxpfst
f_xxpgps
f_xxphdc
f_xxpimc
f_xxplab
f_xxpout
f_xxpros
f_xxprqs
f_xxprtu
f_xxqcfg
f_xxrdef
f_xxrdmv
f_xxrdsw
f_xxregr
f_xxrgty
f_xxrhst
f_xxrskc
f_xxrtkt
f_xxrtrs
f_xxsbof
f_xxscfn
f_xxscmt
f_xxscub
f_xxsdsk
f_xxsisn
f_xxsiwb
f_xxsqdf
f_xxsqpr
f_xxsqst
f_xxsqsv
f_xxssia
f_xxstli
f_xxsube
f_xxtfcm
f_xxtfli
f_xxtfts
f_xxtran
f_xxtreq
f_xxtscf
f_xxtscg
f_xxtsid
f_xxtslp
f_xxtsmv
f_xxvcad
f_xxvcon
f_xxvesl
f_xxwacc
f_xxwcds
f_xxxtbl
faxdblib
fxaxutil
graphlib
icpputil
logiscrn
lpadutil
mathutil
mmktscrn
mmktutil
mntascrn
mntautil
mtgescrn
mtgeutil
muniscrn
muniutil
newscore
newsnscr
newsscrn
portback
portdata
portscrn
portutil
prqsutil
retfdlib
tomsutil
tradfeed
apidbutil
chartutil
faxpopups
ioimanapi
ismaaltdb
moneyscrn
moneyutil
msgcpplib
newsmedia
rmdbexlib
sseomslib
sseomsmid
volderlib
z_a_bdema
apptwoline
backendcpp
bregacclib
btktguilib
fixutillib
intoffline
ismbasbase
lpadalerts
msgfunclib
nailguilib
prqsacclib
s_prqssrch
spidermonk
aerunsutils
auctionutil
faxscrnutil
fiettktutil
ioiscrnutil
ismdistadsk
ismdistctrl
smartclient
techstudies
a_comdb2glib
bregapiutils
fietunittest
ismbasfscomm
ismbasltcomm
ismdistagent
offlineldlib
stliscrnutil
ismbastcpcomm
news/nlrtsvco
news/newsbeutil
fou
fxo
jms
raq
tfx
otkt
epndb
l_fcd
l_fcg
l_ind
f_xxoa
f_xxom
f_xxox
chatlib
f_xxbds
f_xxmsg
gtlibcc
nwssrch
f_crfxfc
f_crovdv
f_xxadmi
f_xxapdc
f_xxapim
f_xxaxal
f_xxdmsg
f_xxdsrc
f_xxerqs
f_xxfxos
f_xxfxrt
f_xxgtrn
f_xxlgvr
f_xxovsn
f_xxtspa
newsutil
apitradsys
fixroutlib
audt_common
gtkjbiginit
gtknbiginit
news/newsutilcpp
news/newsdbaccess
fob
gof
jmq
otae
slcc
f_incpf
f_iniso
f_crfxtp
f_xxbtca
f_xxfxpv
f_xxgtcb
f_xxmfix
gtktsbiginit
news/nlrtutil
news/newsserver
news/nlrtverityso
auf
bmq
l_fcb
f_xxrmcr
nwsstory
gtkpbiginit
tktproxyclient
news/nlrtdputil
news/nlrtfoutil
ttp
l_fcs
l_msg
f_xxnsn
junkifmx
news/newsdataaccess
l_frb
a_l_cng
f_cmcrr
f_crtmfx
news/newsdataaccesscpp
f_crfrb
f_crfxct
gtkmsgbiginit
news/newsbeapp
l_cng
gtkibiginit
f_crovml
f_crvolc
f_crxcut
gtktbiginit
