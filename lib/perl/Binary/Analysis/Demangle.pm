package Binary::Analysis::Demangle;

use strict;
use Carp;
BEGIN {
if ($^O eq 'solaris') {
  my $username = (getpwuid($<))[0];
  eval {mkdir "/bb/data/tmp/$username"};
  eval {mkdir "/bb/data/tmp/$username/$^O"};
  eval {mkdir "/bb/data/tmp/$username/$^O/$]"};
  eval "use Inline C => Config => LIBS => '-ldemangle' => MAKE => '/opt/swt/bin/gmake' => DIRECTORY => '/bb/data/tmp/$username/$^O/$]';"
};

if ($^O eq 'aix') {
  my $username = (getpwuid($<))[0];
  eval {mkdir "/bb/data/tmp/$username"};
  eval {mkdir "/bb/data/tmp/$username/$^O"};
  eval {mkdir "/bb/data/tmp/$username/$^O/$]"};
  eval "use Inline C => Config => MAKE => '/opt/swt/bin/gmake' => DIRECTORY => '/bb/data/tmp/$username/$^O/$]';
"};
}

use Exporter;
use vars qw(@ISA @EXPORT_OK);
@ISA=qw(Exporter);
@EXPORT_OK=qw(demangle_sym);

BEGIN {
if ($^O eq 'solaris') {
my $code = '
#include <demangle.h>
#define BUFLEN 100000
void demangle_sym(SV *basename) {
  SV *returnsv = newSV(0);
  char tempchar[BUFLEN+1];
  char *mangled;
  int stat;

  mangled = SvPV_nolen(basename);
  stat = cplus_demangle(mangled, tempchar, BUFLEN);
  if (stat != DEMANGLE_ESPACE) {
    sv_setpv(returnsv, tempchar);
  }
  Inline_Stack_Vars;
  Inline_Stack_Reset;
  Inline_Stack_Push(sv_2mortal(returnsv));
  Inline_Stack_Done;
}
';
  Inline->bind(C => $code);
} else {
  my $code = '
#include <demangle.h>
#define BUFLEN 100000
void demangle_sym_x(SV *basename) {
  SV *returnsv = newSV(0);
  char tempchar[BUFLEN+1];
  char *mangled;
  char *demangled;
  char *extra;
  int stat;
  Name *myname;

  mangled = SvPV_nolen(basename);
  myname = demangle(mangled, &extra, RegularNames | ClassNames | SpecialNames | ParameterText | QualifierText);
  demangled = text(myname);
  sv_setpv(returnsv, text(myname));
  Inline_Stack_Vars;
  Inline_Stack_Reset;
  Inline_Stack_Push(sv_2mortal(returnsv));
  Inline_Stack_Done;
}
';
  Inline->bind(C => $code);
  eval 'sub demangle_sym {my $sym = shift; $sym =~ s/^\.//; my $dsym = demangle_sym_x($sym); return $dsym ? $dsym : $sym}';
}
}
1;
