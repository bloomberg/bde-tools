package Linker::SymbolTable;

use strict;
use Carp;

use Linker::Xcoff;

#============================================================================

=head1 NAME

Linker::SymbolTable - Read symbol tables from object files and libraries

=head1 SYNOPSIS

B<NOTE>: The current implementation works for AIX only.

    use Linker::SymbolTable;

    $tbl = Linker::SymbolTable->new([$objName]);

    $tbl->readFile($filename, [$verbosity] );

    $name    = $tbl->name;
    @objects = $tbl->objects;
    @symbols = $tbl->globalSymbols($object);
    @symbols = $tbl->undefinedSymbols($object);
    $object  = $tbl->findSymbol($symbol);
    $type    = $tbl->symbolType($symbol);
    $tbl0    = $tbl->singleObjectSymbolTable($object);

    $tbl->print([@objects]);
 
    $tbl->reset([$objName]);

=head1 DESCRIPTION

This module is used to read the symbol table from a C<.o>, C<.a>, or
C<.so> file and make them available to the caller.  After reading a
file, the caller can access a list of objects (which will contain
only one element except for C<.a> archives), a list of global
defined symbols, for a given object, a list of undefined symbols for
a given object, or the name of the object file that defines a
specified symbol.

=head1 AUTHOR

Pablo Halpern E<lt>F<phalpern@bloomberg.net>E<gt>.

=cut

#============================================================================

sub reset($)
{
    my ($self, $name) = @_;

    %$self = (
        NAME                 => $name,  # Name of symbol table
        OBJECTS              => [ ],    # Array of object file names
        OBJECT_TO_GLOBALSYMS => { },    # Object -> array of global symbols
        OBJECT_TO_UNDEFSYMS  => { },    # Object -> array of undefined symbols
        GLOBALSYM_TO_OBJECT  => { }     # global symbol -> object
    );
}

sub new($;$) {
    my ($proto, $name) = @_;

    my $ref = { };
    my $class=(ref $proto) || $proto;
    my $self = bless $ref,$class;

    $self->reset($name);
    return $self;
}

# Symbol codes:
use constant UNDEFINED_SYMBOL => 0;
use constant GLOBAL_SYMBOL    => 1;
use constant OTHER_SYMBOL     => 2;

# Parse a single line of 'nm' output in a platform-dependent way.
# Argument: a string holding one line from the 'nm' command.
# Return: a list of four items:
#  1. library name (empty if stand-alone .o file)
#  2. object file name
#  3. symbol name
#  4. symbol code
sub parseNmLine($)
{
    my ($line) = @_;

    # For AIX, the line format is:
    #
    #   objectFileName: symbol       code       address
    #
    # Split on first colon, then split on whitespace:
    my ($fullobj, $rest) = split( /:\s+/, $line, 2);
    my ($symbol, $code) = split( /\s+/, $rest, -1);
    my ($library, $object) = ("", $fullobj);

    if ($fullobj =~ /^([^\[]+)\[([^\[]+)\]/) {
        $library = $1;
        $object = $2;
    }

    if ($code eq 'U') {
        # Code indicates undefined symbol.
        $code = &UNDEFINED_SYMBOL;
    }
    elsif ($code =~ /[ABDT]/o) {
        # Code indicates a global symbol (code A, B, D or T).
        print "INCORRECT ASSUMPTION: $symbol was not expected to be of type $code\n"
            unless (Linker::SymbolTable->matchSymbolType($symbol, $code));
        $code = &GLOBAL_SYMBOL;
    }
    else {
        $code = &OTHER_SYMBOL;
    }

    return ($library, $object, $symbol, $code);
}

# Extract the symbols in a given file and process them.
# The file may be a library or a single object file.
sub readFile($$;$)
{
    my ($self, $filename, $verbose) = @_;

    # Check if this is an import (non-Xcoff) file:
    unless ($filename =~ /\.a|\.so/ ) {
        my $xcoff = new Linker::Xcoff($filename);
        return readImportFile(@_) unless ($xcoff->isXcoff);
    }

    my %needs;
    my %supplies;

    $self->{NAME} = $filename;

    # Run the "nm" command to extract the symbols from the file.
    # The -C option disables symbol demangling (needed to avoid whitespace)
    # The -A option prepends each line with the object file name.
    # The -g option limits the output to global symbols only
    open NM, "nm -CAhgp $filename |" or die "Can't nm file $filename\n";
    print "Reading symbols from $filename\n" if ($verbose);

    my $currObject = undef;
    my $line;
    while (defined($line = <NM>)) {
        my ($library, $object, $symbol, $code) = parseNmLine($line);
        $object = $library.':'.$object;

        printf("Object = '%s', Symbol = '%s', Code = %d\n",
               $object, $symbol, $code)
            if ($verbose > 1);

        # If the object file is different from the current object file
        # then process the symbols seen in the current object file then make
        # the new object file current.
        if (! defined $currObject) {
            $currObject = $object;
            push @{$self->{OBJECTS}}, $currObject;
        }
        elsif ($object ne $currObject) {
            my @suppliesArray = keys %supplies;
            my @needsArray = keys %needs;
            $self->{OBJECT_TO_GLOBALSYMS}{$currObject} = \@suppliesArray;
            $self->{OBJECT_TO_UNDEFSYMS}{$currObject} = \@needsArray;
            map {
                $self->{GLOBALSYM_TO_OBJECT}{$_} = $currObject;
            } @suppliesArray;
            %supplies = ();
            %needs = ();
            $currObject = $object;
            push @{$self->{OBJECTS}}, $currObject;
        }

        # Take action based on code
        if ($code == &UNDEFINED_SYMBOL) {
            # Add to set of needed symbols unless it is also supplied.
            $needs{$symbol} = 1 unless exists $supplies{$symbol};
        }
        elsif ($code == &GLOBAL_SYMBOL) {
            # Add to set of supplied symbols.
            # Remove from set of needed symbols.
            $supplies{$symbol} = 1;
            delete $needs{$symbol};
        }
    }

    if (defined $currObject) {
        # Process the last object file in this library
        my @suppliesArray = keys %supplies;
        my @needsArray = keys %needs;
        $self->{OBJECT_TO_GLOBALSYMS}{$currObject} = \@suppliesArray;
        $self->{OBJECT_TO_UNDEFSYMS}{$currObject} = \@needsArray;
        map {
            $self->{GLOBALSYM_TO_OBJECT}{$_} = $currObject;
        } @suppliesArray;
   }

    unless (close NM) {
        if (scalar keys %{$self->{OBJECT_TO_GLOBALSYMS}} ||
            scalar keys %{$self->{OBJECT_TO_UNDEFSYMS}}) {
            print STDERR "Error running 'nm -CAhgp $filename'.\n".
                "    nm exit status $? (ignored).\n";
        }
        else {
            die "Error running 'nm -CAhgp $filename'.  Exit status $?.\n";
        }
    }
}

sub readImportFile($$;$)
{
    my ($self, $filename, $verbose) = @_;

    $self->{NAME} = $filename;

    open IMPORT_FILE, "< $filename" or croak("Cannot open file $filename");

    my $currObject = ":$filename";
    push @{$self->{OBJECTS}}, $currObject;

    my %supplies;
    my $line;
    while (defined($line = <IMPORT_FILE>)) {
        next if ($line =~ /^\#/);       # Discard linker directives
        next if ($line =~ /^\s*$/);     # Discard blank lines
        next if ($line =~ /^\s*\*/);    # Discard comments (starting with '*')

        my ($symbol) = split /\s/, $line, 2;
        $supplies{$symbol} = 1;
    }

    my @suppliesArray = keys %supplies;
    $self->{OBJECT_TO_GLOBALSYMS}{$currObject} = \@suppliesArray;
    $self->{OBJECT_TO_UNDEFSYMS}{$currObject} = [ ];
    map {
        $self->{GLOBALSYM_TO_OBJECT}{$_} = $currObject;
    } @suppliesArray;
}

sub name($) {
    my ($self) = @_;
    return $self->{NAME};
}

sub objects($) {
    my ($self) = @_;
    return @{$self->{OBJECTS}};
}

sub globalSymbols($$) {
    my ($self, $object) = @_;
#     $self->{OBJECT_TO_GLOBALSYMS}{$object} = [ ]
#         unless exists $self->{OBJECT_TO_GLOBALSYMS}{$object};
    return @{$self->{OBJECT_TO_GLOBALSYMS}{$object} || [ ] };
}

sub undefinedSymbols($$) {
    my ($self, $object) = @_;
#     $self->{OBJECT_TO_UNDEFSYMS}{$object} = [ ]
#         unless exists $self->{OBJECT_TO_UNDEFSYMS}{$object};
    return @{$self->{OBJECT_TO_UNDEFSYMS}{$object} || [ ] };
}

sub singleObjectSymbolTable($$) {
    my ($self, $object) = @_;
    $object = ":$object" unless ($object =~ /:/);

    return $self if (1 == scalar @{$self->{OBJECTS}});

    my $subTable = $self->new($object);

    push @{$subTable->{OBJECTS}}, $object;
    $subTable->{OBJECT_TO_GLOBALSYMS}{$object} =
        $self->{OBJECT_TO_GLOBALSYMS}{$object} || [ ];
    $subTable->{OBJECT_TO_UNDEFSYMS}{$object} =
        $self->{OBJECT_TO_UNDEFSYMS}{$object} || [ ];
    my %symToObj = map { $_ => $object
        } @{$subTable->{OBJECT_TO_GLOBALSYMS}{$object}};

    return $subTable;
}

sub findSymbol($$) {
    my ($self, $symbol) = @_;

    # OK to return 'undef' is symbol not found.
    return $self->{GLOBALSYM_TO_OBJECT}{$symbol};
}

# Return 'T' or 'D'
sub symbolType($$) {
    my ($self, $symbol) = @_;

    return ($symbol =~ /^\./ ? 'T' : 'D');
}

sub matchSymbolType($$$) {
    my ($self, $symbol, $types) = @_;

    if ($symbol =~ /^\./) {
        return ($types =~ /[TA]/ ? 1 : 0);
    }
    else {
        return ($types =~ /[DB]/ ? 1 : 0);
    }
}

# Print contents of symbol table.
# Optional arguments: list of objects to print
sub print($@)
{
    my ($self, @objects) = @_;
    @objects = $self->objects unless(@objects);

    foreach my $object (@objects) {
        print "  Object file: $object\n";
        print "    Global Symbols:\n";
        foreach my $symbol ($self->globalSymbols($object)) {
            print "      ", $symbol, "\n";
        }
        print "    Undefined Symbols:\n";
        foreach my $symbol ($self->undefinedSymbols($object)) {
            print "      ", $symbol, "\n";
        }
    }    
}

1;
