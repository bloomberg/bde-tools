#!/usr/bin/env perl

# This is used to create a clean, reproducible and documented
# environment for running other commands. It removes everything from
# the environment except for values explicitly specified in an
# environment file and specially named override values in the users
# environment
#
# The usage is:
my $usagemessage="".
  "bde_devenv.pl [--verbose] [--echo] \\\n".
  "          [--strict] [--env file] \\\n".
  "          [--exit-on-hangup] [--quiet] \\\n".
  "          [--inherit-args] [--inherit-my-variables] \\\n".
  "          [--timeout s] [--help] command to run with parameters\n".
  "  --verbose         : Print detailed information about what was done\n".
  "  --echo            : Just echo the commands to run to stdout - use\n".
  "                      with eval - eg eval `bde_devenv.pl --echo`\n".
  "  --strict          : Ignore MY_ prefixed overrides for variables not\n".
  "                      found in the .env file.\n".
  "  --env file        : Read the specified file instead of looking for a\n".
  "                      file named devenv.env. May be specified multiple\n".
  "                      times. The order is significant\n".
  "  --exit-on-hangup  : Terminate if the script is hung up on. Used when\n".
  "                      running remote commands to support tests.\n".
  "  --quiet           : Don't output anything - useful when capturing\n".
  "                      capturing command output.\n".
  "  --inherit-args    : Prepend the contents of DEVENV_ARGUMENTS to the\n".
  "                      arguments. Any devenv which uses this and relies\n".
  "                      on using the default .env file (devenv.env)\n".
  "                      should use an explicit --env devenv.env option as\n".
  "                      otherwise any inherited --env option will cause\n".
  "                      it not to look for the default .env file.\n".
  "  --inherit-my-variables : Treat the contents of the DEVENV_MY_VARIABLES\n".
  "                      as if they were defined in the environment.\n".
  "  --timeout s       : Terminate the script after s seconds\n".
  "  --no-erase        : Don't erase the existing environment. Only for use in\n".
  "                      interactive shells when necessary\n".
  "  --help            : Print this help and exit.\n".
  "\n".
  "If no --env option is given the script tries to use a file named devenv.env.\n".
  "\n".
  "Unquoted parts of the command and parameters are substituted before the\n".
  "environment is set up. 'Quoted' parts of the command and parameters are\n".
  "substituted after the environment has been set up\n".
  "\n";
#
# Some examples:
#
# bde_devenv.pl gmake clean all
#
# Just use the default devenv.env file in the current directory and
# run "gmake clean all"
#
# bde_devenv.pl --verbose --strict --env pgmtest.env runtests.pl
#
# Use the specified pgmtest.env file to setup the environment. Do not
# allow any overrides and log the values set and the command run to
# STDOUT (to capture it in a log file)
#
# Values are specified in a file (with a .env suffix by
# convention). This example shows the syntax of these files:
#
# # A comment
# FOO=foovalue
# BAR=barvalue
# FOOBAR=${FOO}${BAR}
# if '${DEVENV_OS}' eq 'linux'
# LINUX=true
# PPATH=/linux/stuff
# endif
# if '${DEVENV_OS}' eq 'solaris'
# SOLARIS=true
# PPATH=/solaris/stuff
# endif
# include ${PPATH}/platformvalues.env
#
# You can include comments - any line beginning with a #
#
# You can assign values from constants or by referencing other values
# using ${NAME} syntax
#
# You can do if/endif. The text after the if is evaluated as a perl
# expression and can use any values assigned so far.
#
# You can include other files (using absolute or relative pathnames
# and with the ability to use any values already assigned in those
# path names).
#
# The command also interprets values already in your environment which
# are prefixed MY_ as overrides. So in the above example an
# environment variable of MY_FOO=notfoo will override the value of FOO
# in the file (and will also affect the value of FOOBAR). If you don't
# specify --strict it will also copy any MY_ prefixed variables which
# don't appear in the .env file into the environment (after removing
# the MY_ prefix).
#
# bde_devenv defines the value DEVENV_OS to be either linux, solaris,
# mswindows or aix - the result of $OSNAME in perl. It also defines
# DEVENV_PWD as the working directory when the command is executed to
# allow you to specify relative paths in .env files. It defines
# DEVENV_HOSTNAME to be the hostname it is executed on and
# DEVENV_LOCATION as the path to the bde_devenv.pl file which is being
# executed. DEVENV_DIRECTORY is the directory part of
# DEVENV_LOCATION. DEVENV_UNAME is result of sysname portion returned
# from uname (POSIX::uname() in perl) with spaces replaced by
# underscore. DEVENV_LOGIN is the login of the
# user. DEVENV_MY_VARIABLES is set to a string of
# MY_NAME=value,MY_NAME1-value which represents the values of any MY
# variables before the script executed and DEVENV_ARGS is set to the
# arguments supplied to bde_devenv. These allow its effects to be
# replicated on another machine automatically. You can specify
# --inherit-args and/or --inherit-my-variables to make bde_devenv use
# these.
#
# To do
#
# Add an --interactive mode which would present you with a list of the
# variable settings to be used and allow you to edit, remove or add
# ones before running the command. Maybe have the bde_devenv file
# understand NAME=?VALUE syntax which would indicate that the value
# should be promted for?

use strict;
use warnings;
use Cwd;
use Getopt::Long;
use Sys::Hostname;
use POSIX ":sys_wait_h";

# Global variables

# Reflect the command line arguments
my $ECHO = 0;
my $VERBOSE = 0;
my $STRICT = 0;
my $DIRECTORY = '';
my $EXIT_ON_HANGUP = 0;
my $TIMEOUT = 0;
my $QUIET = 0;
my $HELP = 0;
my $INHERIT_ARGS = 0;
my $INHERIT_VARIABLES = 0;
my $NOERASE = 0;
my @ENVVARS;
my @SETLINES;
# The SHADOWENV is required because if --echo is specified we don't
# want to actually modify the real environment
my %SHADOWENV; 
# MYENVUSAGE keeps track of whether a MY_ override has been used so
# that we can report that.
my %MYENVUSAGE;

# Subroutines

sub usage {
  die $usagemessage;
}

sub set_env {
  $SHADOWENV{$_[0]}=$_[1];
  if ($ECHO) {
    print "export ", $_[0], "=\"", $_[1], "\";\n";
  } else {
    $ENV{$_[0]}=$_[1];
  }
}

sub delete_env {
  delete $SHADOWENV{$_[0]};
  if ($ECHO) {
    print "unset ", $_[0], ";\n";
  } else {
    delete $ENV{$_[0]};
  }
}

sub expand_expression {
  my $value = "@_";
  my $was;
  do {
    $was = $value;
    if ($value =~ m/\$\{(\w+)\}/) {
      my $name = $1;
      if (!exists $SHADOWENV{$name}) {
        if ($STRICT) {
          die "Reference to undefined variable $name";
        } else {
          $value =~ s/\$\{${name}\}//;
        }
      } else {
        $value =~ s/\$\{${name}\}/$SHADOWENV{$name}/e;
      }
    }
  } while ($was ne $value);
  return $value;
}

sub my_print {
  if ($QUIET) {
    return;
  }
  if ($ECHO) {
    print "echo \"@_\";\n";
  } else {
    print "@_\n";
  }
}

sub reset_all_env {
  # Reset all environment variables except those that begin MY_
  while ((my $name, my $value) = each(%ENV)) {
    if (!($name =~ /^MY_/)) {
      if (!($name =~ /![A-Z]\:/)) {
        delete_env $name;
      }
    }
  }
}

sub set_var {
  # Set the variable (param 1) to the value (param 2) unless there is
  # an override variable (MY_ prefixed) set in which case use that

  my $name=$_[0];
  my $value=$_[1];

  # Expand any environment variables in value
  $value = expand_expression($value);

  if (exists($ENV{"MY_" . $name})) {
    my_print "*OVERRIDE* $name default ($value) overrode by MY_$name (",
      ${ENV{"MY_" . $name}}, ")";
    set_env($name, ${ENV{"MY_" . $name}});
    $MYENVUSAGE{"MY_$name"} = "true";
  } else {
    set_env($name, "$value");
  }
}

sub check_unused_my_variables {
  # Warn about any MY_ environment variables that weren't consumed
  while ((my $name, my $value) = each(%ENV)) {
    if ($name =~ /^MY_/) {
      if (!exists $MYENVUSAGE{"$name"}) {
        if ($STRICT) {
          my_print "*WARNING* $name was ignored.";
        } else {
          my $realname = $name;
          $realname =~ s/^MY_//;
          set_env($realname, "$value");
        }
      }
      delete_env("$name");
    }
  }
}

sub read_envvars_file {
  my $file = $_[0];
  if ($file eq "<default>") {
    $file = "devenv.env";
  }
  if (-r $file) {
    open(my $FH, $file) or die "Couldn't open $_";
    my $skip = 0;
    while (<$FH>) {
      chomp;
      if (m/^\#/) {
        # Comments
        next;
      } elsif (m/^ *$/) {
        # Blank lines
        next;
      } elsif (m/^endif/) {
        if ($skip) {
          $skip--;
        }
      } elsif ($skip && m/^if /) {
        $skip++;
      } elsif (m/^if /) {
        s/^if //;
        $_ = expand_expression($_);
        if (!eval) {
          $skip++;
        }
      } elsif ($skip==0) {
        if (m/^include /) {
          s/^include //;
          $_ = expand_expression($_);
          read_envvars_file($_);
        } else {
          (my $name, my $value) = split('=');
          set_var $name, $value;
        }
      }
    }
  } elsif ($_[0] ne "<default>") {
    die "Couldn't find file $file\n";
  }
}


# Main execution starts here

# Add any arguments cascaded from a previous DEVENV to our arguments
if (grep(/--inherit-args/, @ARGV)) {
  if (exists($ENV{"DEVENV_ARGUMENTS"})) {
    unshift(@ARGV, split(',', $ENV{"DEVENV_ARGUMENTS"}));
  }
}

if ($#ARGV<0) {
  usage();
}

# Add any cascaded MY_ variables to the environment first
if (grep(/--inherit-my-variables/, @ARGV)) {
  if (exists($ENV{"DEVENV_MY_VARIABLES"})) {
    foreach my $my_variable (split(',',$ENV{"DEVENV_MY_VARIABLES"})) {
      if ($my_variable ne "") {
        (my $name, my $value) = split('=', $my_variable);
        $ENV{$name} = $value;
      }
    }
  }
}

# Save the arguments we were run with for cascading
my @arguments = ();
push(@arguments, @ARGV);

# Read options
Getopt::Long::Configure("require_order");
GetOptions('verbose' => \$VERBOSE,
           'echo' => \$ECHO,
           'env=s' => \@ENVVARS,
           'strict' => \$STRICT,
           'exit-on-hangup' => \$EXIT_ON_HANGUP,
           'timeout=s' => \$TIMEOUT,
           'set=s' => \@SETLINES,
           'quiet' => \$QUIET,
           'inherit-args' => \$INHERIT_ARGS,
           'inherit-my-variables' => \$INHERIT_VARIABLES,
           'no-erase' => \$NOERASE,
           'help' => \$HELP);

if ($HELP) {
  usage();
}

# Now remove the entries from arguments which were not consumed so we
# are left with only devenv arguments in @arguments. The difference
# between the size of @arguments and @ARGV at this point is the number
# of devenv arguments that were consumed and we know these must be at
# the beginning.
splice(@arguments, $#arguments-$#ARGV);

# Finally remove --inherit arguments as these are never cascaded
@arguments = grep(!/--inherit-args|--inherit-my-variables/, @arguments);

my $platform = $^O;
if ($platform eq "MSWin32" || $platform eq "cygwin") {
  $platform="mswindows";
} elsif (($platform ne "solaris") &&
         ($platform ne "linux") &&
         ($platform ne "aix")) {
  die "Unrecognized platform: $platform\n";
}

my $pwd=cwd();


if (!$NOERASE) {
  reset_all_env();
} else {
  %SHADOWENV = %ENV;
}

my $devenv_my_variables="";
while ((my $name, my $value) = each %ENV) {
  if ($name =~ /^MY_/) {
    $devenv_my_variables .= "$name=$value,";
  }
}

my $filename = __FILE__;
my $directory = __FILE__;
$directory =~ s/\/[^\/]*$//;

set_var('DEVENV_MY_VARIABLES', $devenv_my_variables);
set_env('DEVENV_ARGUMENTS', join(",", @arguments));
set_var('ARCH', "$platform"); # Should be removed one day
set_var('DEVENV_OS', "$platform");
set_var('DEVENV_LOCATION', "$filename");
set_var('DEVENV_DIRECTORY', "$directory");
set_var('DEVENV_PWD', "$pwd");
set_var('DEVENV_HOSTNAME', hostname());
set_var('DEVENV_LOGIN', getpwuid($<));
my $uname_zero = (POSIX::uname())[0];
$uname_zero =~ s/ /_/g;
set_var('DEVENV_UNAME', $uname_zero);
set_var('PS1', "devenv env> ");

if (scalar(@ENVVARS)==0) {
  unshift(@ENVVARS, '<default>');
}

while (<@ENVVARS>) {
  read_envvars_file($_);
  shift @ENVVARS;
}

foreach my $setline (@SETLINES) {
  (my $name, my $value) = split('=',$setline);
  set_var($name, $value);
}

check_unused_my_variables();

if ($VERBOSE) {
  my_print "Environment set to:";
  if ($ECHO) {
    print "env;";
  } else {
    while ((my $name,my $value) = each(%ENV)) {
      print "$name=$value\n";
    }
  }
}

if (@ARGV) {
  # If any parts of ARGV were quoted try substituting them now
  for (my $argc=0; $argc<=$#ARGV; $argc++) {
    $ARGV[$argc] = expand_expression($ARGV[$argc]);
  }
  if ($VERBOSE) {
    my_print("Executing command: @ARGV");
  }
  if ($ECHO) {
    print "@ARGV", ";";
  } else {
    my $parentPid = getppid();
    my $childPid = fork();
    if ($childPid == 0) {
      my @args = @ARGV;
      exec(@args)==0 or die "!! Failed to run $ARGV[0] $ARGV";
    } else {
      my $waitPid=0;
#      my_print "pid:$childPid (@ARGV)";
      if ($EXIT_ON_HANGUP || $TIMEOUT) {
        my $endTime = time() + $TIMEOUT;
        # Wait until either the parent or the child is no more...
        while (1) {
          if ($EXIT_ON_HANGUP) {
            # perls getppid() doesn't notice when our parent dies and we get
            # reparented to init. All the platforms we care about appear
            # to make init have pid=1 (if not we could just watch when this
            # differs from what it started out as)
            my $myPPid = `ps -p $$ -o ppid | tail -1`;
            if ($myPPid==1) {
#              my_print "parent exited, --exit-on-hangup specified kill child ($childPid) and exit";
              kill(15, $childPid);
              sleep 4;
              kill(15, $childPid);
              sleep 4;
              kill(9, $childPid);
              last;
            }
          }

          $waitPid = waitpid($childPid, WNOHANG);
          if ($waitPid != 0) {
#            my_print "waitpid returned $waitPid, exit";
            last;
          }

          if ($TIMEOUT && (time() >= $endTime)) {
            kill(15, $childPid);
            sleep 4;
            kill(15, $childPid);
            sleep 4;
            kill(9, $childPid);
            last;
          }

          sleep 1;
        }
      } else {
        my $waitPid = wait();
#        my_print "wait returned $waitPid, exit";
      }
      if (($waitPid>0) && ($waitPid!=$childPid)) {
        die "!! Unexpected child process\n";
      }
      if ($? == -1) {
        exit $?;
      }
      elsif ($? & 127) {
        printf "child died with signal %d, %s coredump\n",
          ($? & 127),  ($? & 128) ? 'with' : 'without';
        exit $?;
      }
      else {
        exit ($? >> 8);
      }
    }
  }
}
