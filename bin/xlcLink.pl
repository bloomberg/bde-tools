#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Cwd;
use File::Temp qw(tempfile tempdir);
use File::Spec::Functions qw(catfile rel2abs);
use File::Basename qw(basename dirname);
use IPC::Open3;

use Linker::SymbolTable;
use Linker::Xcoff;

#============================================================================

=head1 NAME

xlcLink.pl - Wrapper around AIX linker to reduce C++ code bloat

=head1 SYNOPSIS

    xlcLink.pl [--verbose[=2]] [--[no]rescan] (xlC options and files)

=head1 DESCRIPTION

The C<xlcLink.pl> script is designed to be used instead of xlC when
linking AIX programs that may contain C++ code.  It was created to
work around deficiencies in the AIX linker that caused large
quantities of unused code to be linked into an executable.

When the AIX linker is presented with a library (.a file), it links
in all object files that contain a dynamic initialization -- whether
or not those object files are directly or indirectly referenced
within the program.  Because the C<E<lt>iostreamE<gt>> header
has a small dynamic initializer in it, any file containing
C<#include E<lt>iostreamE<gt>> compiled will be linked into the
executable, along with all of its direct and indirect dependencies.
The result is a huge executable containing mostly dead code.

Although the AIX linker has an option, C<-qtwolink>, that corrects
this problem, the option causes the linker to fail when linking very
large executables (like the big).  The C<xlcLink.pl> script solves
this problem by eliminating any unecessary object files before the
linker even sees them.  The final step in this script invokes
C<xlC> to build the executable.

=head1 OPTIONS

=over

=item --verbose[=2]

Causes C<xlcLink.pl> to send a play-by-play description of what it's
doing to standard output.  With the optional C<=2>, produces
very-verbose output that describes what it is doing with every
symbol.

=item --[no]rescan

Specifying C<--rescan> causes symbols to be resolved even if the
library that resolves them is specified before the library or object
that depends on them.  This allows for circular dependencies among
libraries and reduces the need to order the libraries on the link
line.  The C<--norescan> option turns off this feature, causing the
linker to behave more like a typical Unix linker.  The default is
C<--rescan>, which is compatible with normal xlC operation.

=back

Other than the above options, the command line is identical to C<xlC>.
C<xlcLink.pl> has special handling for C<-l>, C<-L>, and library
names, but otherwise passes the command line to C<xlC> unchanged.

=head1 AUTHOR

Pablo Halpern E<lt>F<phalpern@bloomberg.net>E<gt>.

=cut

#============================================================================

my %resolvedSymbols;
my %unresolvedSymbols;
my %requiredObjects;

my @unprocessedObjects;
my @rescanSymbolTables;

my $verbose = 0;
my $dynamicMode = 1;
my $rescan = 1;

# Indicate that an object file will be required.
sub requireObject($)
{
    my ($object) = @_;

    unless (exists $requiredObjects{$object}) {
        $requiredObjects{$object} = 1;
        push @unprocessedObjects, $object;
    }
}

# Process the symbols in a SymbolTable object.
sub processSymbols($;$)
{
    my ($symbolTable, $types) = @_;
    $types ||= "TD";

    # Find objects within this library that are directly needed to resolve
    # currently-unresolved symbols.
    foreach my $object ($symbolTable->objects) {
        my @symbols = $symbolTable->globalSymbols($object);
        foreach my $symbol (@symbols) {
            if ($symbolTable->matchSymbolType($symbol, $types) &&
                exists $unresolvedSymbols{$symbol}) {
                # This object can resolve this symbol
                requireObject($object);
                last;
            }
        }
    }

    # Loop through objects that have been determined to be required but not
    # yet processed.  If new files are determined to be needed, add them
    # to the list of unprocessed files.
    while (@unprocessedObjects) {
        my $object = shift @unprocessedObjects;
        my $symbol;

        printf("Processing Object $object\n", $symbolTable->name)
            if ($verbose);

        # Add all global symbols from this object to %resolvedSymbols:
        foreach $symbol ($symbolTable->globalSymbols($object)) {
            delete $unresolvedSymbols{$symbol};
            $resolvedSymbols{$symbol} = $object;
        }

        # Try to resolve any undefined symbols in this object
        foreach $symbol ($symbolTable->undefinedSymbols($object)) {

            if (exists $resolvedSymbols{$symbol}) {
                # Symbol has already been resolved.  Do nothing.
            }
            elsif (my $foundObject = $symbolTable->findSymbol($symbol)) {
                # Symbol can be resolved from within this same library.
                # Add $foundObject to list of required objects (and thus to
                # list of objects to be processed).
                requireObject($foundObject);
            }
            else {
                # Symbol will remain unresolved for now.
                $unresolvedSymbols{$symbol} = $object;
            } # end if-elsif-else
        } # end foreach (undefined symbol)
    } # end while (more objects to process)
}

# Given a library root (without the "lib" prefix or ".a" suffix) and a path,
# find the library in the path and return its full path name.  Return 'undef'
# if not found.
sub findlib($@) {
    my ($libroot, @libpath) = @_;
    my $lib = "lib$libroot";

    foreach my $dir (@libpath) {
        my $libfile = catfile($dir, $lib);
        return "$libfile.so" if ($dynamicMode && -f "$libfile.so");
        return "$libfile.realarchive.a"  if (-f "$libfile.realarchive.a");
        return "$libfile.a"  if (-f "$libfile.a");
    }

    print("Can't find $lib in @libpath\n") if ($verbose);
    return undef;
}

MAIN: {
    # Ensure that we are on AIX
    my $prog = basename($0);
    my $platform = `uname`;
    die "ERROR: $prog runs on AIX only\n" unless ($platform eq "AIX\n");

    ######################
    # Process arguments
    ######################
    my @xlcopts;
    my @fileargs;
    my @libpath;
    my %fileargsOptRefs;
    while (@ARGV) {
        my $arg = shift @ARGV;
        
        # Match --verbose, --rescan, --norescan
        # Anything else is just added to the xlC options list.
        $verbose = $1,                 next if ($arg =~ /^--verbose=([0-9]+)/);
        $verbose = 1,                  next if ($arg eq "--verbose");
        $rescan = 1,                   next if ($arg eq "--rescan");
        $rescan = 0,                   next if ($arg eq "--norescan");
        
        # Transform "-l xyz" into "-lxyz" or "-L xyz" into "-Lxyz"
        $arg .= shift(@ARGV)           if ($arg =~ /^-[lL]$/);

        # Append to options list
        push(@xlcopts, $arg);

        # Recognize specific options
        $dynamicMode = 1,              next if ($arg eq "-bdynamic");
        $dynamicMode = 1,              next if ($arg eq "-bshared");
        $dynamicMode = 0,              next if ($arg eq "-bstatic");

        $unresolvedSymbols{$1} = 1,    next if ($arg =~ /^-u(.+)$/);

        push(@libpath, $1),            next if ($arg =~ /^-L(.+)$/);

        if ($arg =~ /^-l(.+)$/ and
            defined(my $libfile = findlib($1, @libpath))) {
            print("Found library $libfile\n") if $verbose;
            push(@fileargs, $libfile);
            $xlcopts[$#xlcopts] = "##$arg";
            $fileargsOptRefs{$libfile} = \$xlcopts[$#xlcopts];
            next;
        }
        if ($arg =~ /(:?\.[oa]|\.so)$/ && -f $arg) {
            push(@fileargs, $arg);
            $xlcopts[$#xlcopts] = "##$arg";
            $fileargsOptRefs{$arg} = \$xlcopts[$#xlcopts];
            next;
        }

    }

    ##################################
    # Process each .o, .a, or .so file
    ##################################
#    $unresolvedSymbols{"main"} = 1;
    for my $file (@fileargs) {

        # .a files are optional, but .o files are always required
        # If this is a .o file, add it to set of required files. 
        requireObject ":$file" if ($file =~ /\.o$/o);

        # Read symbol table from file
        my $symbolTable = new Linker::SymbolTable;
        $symbolTable->readFile($file, $verbose);
        if ($verbose > 2) {
            printf("File %s\n", $symbolTable->name);
            $symbolTable->print;
        }

        # Resolve symbols and find new unresolved symbols
        processSymbols($symbolTable, ($rescan ? "T" : "TD"));

        if ($rescan) {
            # If any object in $symbolTable that is not currently required,
            # then save $symbolTable for later rescanning.
            foreach my $object ($symbolTable->objects) {
                next if (exists $requiredObjects{$object});

                push @rescanSymbolTables, $symbolTable;
                last;
            }
        }
    }

    #####################################################
    # Process the symbol tables that need to be rescanned
    #####################################################

    # If rescan is enabled, rescan all files until no new object files are
    # added to the required list.
    my $oldNumRequiredObjects = 0;
    my $newNumRequiredObjects = keys %requiredObjects;

    # Rescan for text symbols only:
    while ($rescan && $oldNumRequiredObjects != $newNumRequiredObjects) {
        $oldNumRequiredObjects = $newNumRequiredObjects;
        foreach my $symbolTable (@rescanSymbolTables) {
            printf "Rescanning file %s for text symbols\n", $symbolTable->name;
            processSymbols($symbolTable, "T");
        }
        $newNumRequiredObjects = keys %requiredObjects;
    }

    # Now rescan for data (and any additional text) symbols:
    $oldNumRequiredObjects = 0;
    while ($rescan && $oldNumRequiredObjects != $newNumRequiredObjects) {
        $oldNumRequiredObjects = $newNumRequiredObjects;
        foreach my $symbolTable (@rescanSymbolTables) {
            printf "Rescanning file %s for data symbols\n", $symbolTable->name;
            processSymbols($symbolTable, "TD");
        }
        $newNumRequiredObjects = keys %requiredObjects;
    }

    # At this point, we know exactly which object files are needed.
    # Display the result if in verbose mode.
    my @requiredObjects = sort(keys %requiredObjects);
    if ($verbose) {
        printf "Required objects (%d):\n  ", scalar @requiredObjects;
        print join("\n  ", @requiredObjects), "\n";
    }

    if ($verbose > 2) {
        print "ALL FILES\n";
        print "    Resolved Symbols:\n";

        while (my ($symbol, $object) = each %resolvedSymbols) {
            printf ("      %s [%s]\n", $symbol, $object);
        }
    }

    #######################################
    # Create archive of needed object files
    #######################################

    # Group required objects into their archives
    my %requiredArchives;
    foreach my $object (@requiredObjects) {
        my ($library, $component) = split( /:/, $object);

        if ($library) {
            $requiredArchives{$library} = []
                unless exists $requiredArchives{$library};
            push @{$requiredArchives{$library}}, $component;
        }
        else {
            $requiredArchives{$component} = undef;
        }
    }    

    # Create an .a archive to hold all of the .o files that are extracted from
    # other archives.
    my $tmpdir = tempdir("xlcLink_XXXX", TMPDIR => 1, CLEANUP => 1);
    my $libAgg = catfile($tmpdir, "libAgg.a");

    my $originalDir = getcwd();
    $SIG{__DIE__} = sub { chdir $originalDir; };  # Make sure cleanup can happen
    chdir $tmpdir;
    my $createdLibXlcLink = 0;
    while (my ($library, $components) = each %requiredArchives) {

        if ($components) {
            my @components = @{$components};
            my $absLibrary = rel2abs($library, $originalDir);

            my $numcomponents = @components;
            print "Adding $numcomponents objects from $library to $libAgg\n"
                if ($verbose);
            system("ar", "xl", $absLibrary, @components) == 0
                or die("extract failure: ar xl $absLibrary @components\n".
                       "    Return code $?");

            # $fileargsOptRefs{$library} will refer to a string begining with
            # '##' if library has not been seen in this loop yet and "" if the
            # library has been seen and contains normal (non-shared) objects.
            # Otherwise the library contains a shared object and should not be
            # processed.
            if (${$fileargsOptRefs{$library}} =~ /^\#\#/ ) {
                # If the first object we encounter in this library is a shared
                # object file, then we force don't add the library to $libAgg.
                # Otherwise, we assume none of the objects are shared and we
                # skip this test in the future.
                my $xcoffHdr = new Linker::Xcoff($components[0]);
#                 die "Non XCOFF File: $library:$component"
#                     unless ($xcoffHdr && $xcoffHdr->isXcoff);
                if ($xcoffHdr && $xcoffHdr->isXcoff && $xcoffHdr->isShared) {
                    # This is a shared object.  Leave on command line.
                    # Strip off leading '##', leaving just the library name.
                    ${$fileargsOptRefs{$library}} =~ s/^\#\#// ;
                    next;
                }
                else {
                    # Clear string to remove non-shared library from
                    # command line
                    ${$fileargsOptRefs{$library}} = "";
                }
            }
            elsif (${$fileargsOptRefs{$library}} ne "") {
                # Previous visit to this library indicated that there was a
                # shared object in it.  Skip all remaining objects in this
                # library.
                next;
            }

            my $vflag = ($verbose ? "v" : "");
            system("ar", "qcl$vflag", $libAgg, @components) == 0
                or die("archive failure: ar qcl$vflag $libAgg @components\n".
                       "    Return code $?");
            $createdLibXlcLink = 1;
            unlink(@components);
        }
        else {
            # This is a plain .o file.  Leave on command line.
            # Strip off leading '##', leaving just the object file name.
            ${$fileargsOptRefs{$library}} =~ s/^\#\#// ;
        }
    }

    chdir $originalDir;

    ###########################################
    # Remove unused libraries from command line
    ###########################################
    for (my $i = 0; $i < @xlcopts; ++$i) {
        if ($xlcopts[$i] =~ /^\#\#/ or
            $xlcopts[$i] eq "") {
            splice(@xlcopts, $i, 1);
            --$i;
        }
    }

    # Add our special archive to the end of the command line
    push(@xlcopts, $libAgg) if ($createdLibXlcLink);

    ########################################
    # Run xlC with our modified command line
    ########################################
    printf("running xlC @xlcopts\n") if $verbose;

    my $xlcOutput = "";
    my $xlcPid = open3("<&STDIN", $xlcOutput, undef, "xlC", @xlcopts);
    while (my $errorLine = <$xlcOutput>) {
        chomp $errorLine;
        if ($errorLine =~ /ERROR: Undefined symbol: \.?([^.].*)$/ ) {
            # Find out who referenced this unresolved symbol.
            # Append used-by information to error line.
            # TBD: linker errors produce demangled C++ names which will
            # fail look up in our mangled %unresolvedSymbols hash.
            my $usedBy = $unresolvedSymbols{$1} || $unresolvedSymbols{".$1"};
            if ($usedBy) {
                $usedBy =~ s/^://;
                $errorLine .= " ($usedBy)";
            }
        }
        print "$errorLine\n";
    }

    waitpid $xlcPid, 0;
    die("Link Error $?: xlC @xlcopts\n") if ($?);
}
