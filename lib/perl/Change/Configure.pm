package Change::Configure;
use strict;

use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw(readConfiguration);

use Text::ParseWords qw(shellwords);
use Util::Message qw(debug2 debug message warning verbose fatal);

# since this module is used to read in commandline arguments, we can't know
# if any switches are set yet. So we assume a common form for debug and
# verbose and switch on one level of each if we find an applicable option
{ my ($debug,$verbose);
  foreach (@ARGV) {
      $debug+=(length $1) if /^-(d{1,})$/;
      $verbose+=(length $1) if /^-(v{1,})$/;
  }
  Util::Message::set_debug($debug) if $debug;
  Util::Message::set_verbose($verbose) if $verbose;
}

#==============================================================================

=head1 NAME

Change::Configure - Parser for change resource (.csrc) files

=head1 SYNOPSIS

    use Change::Configure qw(readConfiguration);
    readConfiguration(\@ARGV,"myprogram","/home/myhome/.csrc");

=head1 DESCRIPTION

C<Change::Configure> provides functionality to allow command line options to
be automatically read from a configuration resource file. For an example of
its use see L<cscheckin>.

=head2 Configuration File Format

A configuration file has the following format:

   [program1]
   options and arguments
   more options and argments

   [program2]
   ...

   [all]
    options and arguments applying to all programs

A given program name will match all configuration lines applying to a section
named for it explicitly, and all configuration lines applying to the special
section named C<all>. The program 'name' is passewd to L<"readConfiguration">
and need not necessarily correspond to the program's actual name.

=cut

#==============================================================================

=head1 ROUTINES

The following routines are available for export

=head2 readConfiguration(@argv,$program,@locations)

Search the list of locations provided, and for each one found read
configuration data for the specified program. Modify the passed array (which is
passed by reference) to prepend the parsed configuration to it. Returns the
parsed configuration (which may evaluate to a false value if no configuration
data was found).

Configuration data is parsed according to the rules of command line parsing,
i.e. quotes are recognized and handled as a shell would handle them.

=cut

sub readConfigFile ($$) {
    my ($program,$file)=@_;
    my @args;
    my $section="none";

    open FH,$file or fatal "Unable to open $file: $!";
    while (<FH>) {
	next if /^\s*($|#)/;
	$section=$1,next if /^\[(\w+)\]/;
	chomp;
	warning("$file contains '$_' before a section marker, ignored"),next
	  if $section eq "none";
	next unless $section eq "all" or $section eq $program;
	s/^\s+//; s/\s+$//;
	push @args,$_;
    }
    close FH;

    warning("$file contained no valid configuration data"),return
      unless @args;

    verbose "read '@args' for $program from $file";
    return shellwords @args;
}

sub readConfiguration (\@$@) {
    my ($argv,$program,@locations)=@_;

    debug2 "Looking in @locations for configuration";

    my $found=0;
    my @args;

    foreach my $location (@locations) {
	if (-f $location) {
	    $found++;
	    debug "Reading configuration from $location";
	    push @args, readConfigFile($program,$location);
	}
    }

    if ($found) {
	verbose "Read ".scalar(@args).
	  " parameters from $found configuration files";
    } else {
	verbose "No configuration files found (searched @locations)";
    }

    unshift @{$argv},@args;
    return @args;
}

#==============================================================================

1;

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<bde_createcs.pl>, L<Change::Arguments>

=cut
