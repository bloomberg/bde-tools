package Source::Iterator::CPlusMode;
use strict;

use base 'Source::Iterator';
use Source::Util::ParseTools qw(normalizeScopedName);
use Text::Balanced qw(extract_bracketed
                      gen_delimited_pat);
use Source::LineNumber;
use Source::Symbols qw(PREPROCESSOR
                       COMMENT
                       INCLUDE
                       DEFINE
                       NAMESPACE
                       NAMESPACE_END
                       UNAMESPACE
                       UNAMESPACE_END
                       EXTERNC
                       EXTERNC_END
                       CLASS_FWD
                       CLASS
                       CLASS_END
                       UNION_FWD
                       UNION
                       UNION_END
                       ENUM
                       ENUM_END
                       METHOD_FWD
                       METHOD
                       METHOD_END
                       FUNCTION_FWD
                       FUNCTION
                       FUNCTION_END
                       STATIC_FUNCTION
                       STATIC_FUNCTION_END
                       OPERATOR_FWD
                       OPERATOR
                       OPERATOR_END
                       OTHER
                       EXTERN
                       FRIEND
                       TYPEDEF
                       USING
                       STATIC_FUNCTION_FWD
                       SEMI_COLON);
use Util::Test qw(ASSERT); #for testing only
use Util::Message qw(debug fatal);

#==============================================================================

=head1 NAME

Source::Iterator::CPlusMode - C++ iterator

=head1 SYNOPSIS

    use Source::Iterator::CPlusMode;
    my $iter = new Source::Iterator::CPlusMode($file);
    while (defined(my $line = $iter->next)) { ...

=head1 DESCRIPTION

This class provides an iterator which is used to read C++ source code and
return syntactically significant "chunks" of it, i.e., statements (';'),
beginning/end of blocks ('{', '}') and preprocessor statements.  It also
provides methods to query the properties of the chunk just read.

=head1 LIMITATIONS

1. The iterator does not preprocess comments and/or strings, so these should
not contain characters used as regexp delimiters, i.e., "#{};".

2. Various missing features should be considered as high-priority when time
and resources allow:

=over

=item *

Capturing of types and identifiers

=item *

"Wrapper" functionality which internally parses the source and returns 
identifiers organized by category (types, method names, etc.), rather than
forcing client to do this.

=item *

Performance considerations (caching)

=back

3. Possible design changes:

=over

=item *

Currently scopes and blocks are managed separately - perhaps they could be
combined.

=back

=cut

#==============================================================================

=head1 METHODS

These are broken down into a number of categories.

=cut

#------------------------------------------------------------------------------

my %blockTypes =
  (&CLASS           => CLASS_END,
   &UNION           => UNION_END,
   &ENUM            => ENUM_END,
   &NAMESPACE       => NAMESPACE_END,
   &UNAMESPACE      => UNAMESPACE_END,
   &METHOD          => METHOD_END,
   &FUNCTION        => FUNCTION_END,
   &STATIC_FUNCTION => STATIC_FUNCTION_END,
   &OPERATOR        => OPERATOR_END,
   &EXTERNC         => EXTERNC_END);

#==============================================================================

=head1 Statement type methods

These methods set/get/deselect statement types.

=cut

#------------------------------------------------------------------------------

=head2 I<setStatementType($statementType)>

Set statement type of current iterator to $statementType.

=cut

sub setStatementType($$) { $_[0]->{currentStatement} = $_[1]; }

#------------------------------------------------------------------------------

=head2 I<getStatementType()>

Return statement type of current iterator.

=cut

sub getStatementType($) { return $_[0]->{currentStatement}; }

#------------------------------------------------------------------------------

=head2 I<isStatementType($statementType)>

Return true if statement type of current iterator = $statementType, else flase.

=cut

sub isStatementType($$)  { return $_[0]->{currentStatement} eq $_[1];  }

#------------------------------------------------------------------------------

=head2 I<deselect(@types)>

Deselect statement types @types for current iterator.

=cut

sub deselect($@) {
    my($self,@types) = @_;

    push(@{$self->{notSelected}}, @types);
}

#------------------------------------------------------------------------------

=head2 I<notSelected()>

Return 1 if statement type is not selected for current iterator, else 0.

=cut

sub notSelected($) {
    my($self) = @_;

    my $stType = $self->getStatementType;
    for my $t (@{$self->{notSelected}}) {
        return 1 if $t eq $stType;
    }
    return 0;
}

#------------------------------------------------------------------------------

=head2 I<privateStatementType()>

Return true if statement is private, else false.

=cut

sub privateStatementType($) {
    my($self) = @_;

    return 1 if 
      $self->getStatementType eq STATIC_FUNCTION     ||
      $self->getStatementType eq STATIC_FUNCTION_END ||
      $self->getStatementType eq STATIC_FUNCTION_FWD;
    return 0;
}

#------------------------------------------------------------------------------

=head1 Block methods

These methods are used to manage blocks (named or otherwise); this is
accomplished by maintaining an array of "block markers", where each marker 
contains the statement type of the block, and the position of its closing 
brace.

=cut

#------------------------------------------------------------------------------

=head2 I<pushBlock($length)>

Push block marker with length of $length.

=cut

sub pushBlock($$) {
    my($self,$len) = @_;

    $self->{blocks}->{pos(${$self->{src}})+$len-1} = $self->getStatementType;
}

#------------------------------------------------------------------------------

=head2 I<popBlock($statementType)>

Clear the *latest* block marker of type $statementType.

=cut

sub popBlock($$) {
    my($self,$type) = @_;

    my $findKey;
    for my $key (keys(%{$self->{blocks}})) {
        $findKey = $key if !$findKey or 
          ($self->{blocks}->{$key} eq $type and $key < $findKey);
    }
    $findKey and delete $self->{blocks}->{$findKey} or
	$self->throw("$findKey not found");
}

#------------------------------------------------------------------------------

=head2 I<inAnyBlock()>

Return true if current iterator is in a block, else false.

=cut

sub inAnyBlock($) {
    my($self) = @_;

    return $self->{blocks};
}

#------------------------------------------------------------------------------

=head2 I<inBlock($statementType)>

Return 1 if current iterator is in block of $statementType, else 0.

=cut

sub inBlock($$) {
    my($self,$type) = @_;

    return 0 if !$self->inAnyBlock;
    for my $val (values(%{$self->{blocks}})) {
        return 1 if $val eq $type;
    }
    return 0;
}

#------------------------------------------------------------------------------

=head2 I<blockDepth($statementType)>

Return block depth for $statementType.

=cut

sub blockDepth($$) {
    my($self,$type) = @_;

    return 0 if !$self->inBlock($type);
    my $depth = 0;
    for my $val (values(%{$self->{blocks}})) {
        $depth++ if $val eq $type;
    }
    return $depth;
}

#------------------------------------------------------------------------------

=head2 I<atBlockEnd()>

Return statement type for block marker at current position - 1; returns undef
if block marker does not exist for this position.

=cut

sub atBlockEnd($) {
    my($self) = @_;

    return($self->{blocks}->{pos(${$self->{src}})-1});
}

#------------------------------------------------------------------------------

=head2 I<blockStatementType()>

Return true if statement type of current iterator is block type, else false.

=cut

sub blockStatementType($) {
    my($self) = @_;

    return($blockTypes{$self->getStatementType});
}

#------------------------------------------------------------------------------

=head2 I<skipBlock()>

Position to the end + 1 of current statement (must be a block statement).

=cut

sub skipBlock($) {
    my($self) = @_;

    my $type = $self->getStatementType;
    $self->throw("$type is not a block statement") if !$self->blockStatementType;

    my $findKey;
    for my $key (keys(%{$self->{blocks}})) {
        $findKey = $key if !$findKey or
          ($self->{blocks}->{$key} eq $type and $key < $findKey);
    }
    if ($findKey) {
        delete $self->{blocks}->{$findKey};
        pos(${$self->{src}}) = $findKey + 1;
    }
    else {
        $self->throw("could not find block for $type");
    }
    return;
}

#------------------------------------------------------------------------------

=head2 I<inClassOrStruct()>

Return true if in type definition block, otherwise return false.

=cut

sub inClassOrStruct($) {
    my($self) = @_;

    return $self->inBlock(CLASS);
}

#------------------------------------------------------------------------------

=head1 Scope methods

These methods are used to manage names in the contect of namespace, class and
struct scope.

=cut

#------------------------------------------------------------------------------

=head2 I<startScopeStatementType()>

Return true if current statement starts scope significant to iterator.

=cut

sub startScopeStatementType($) {
    my($self) = @_;

    my $stType = $self->getStatementType;
    return
      $stType eq CLASS     ||
      $stType eq NAMESPACE;
}

#------------------------------------------------------------------------------

=head2 I<endScopeStatementType()>

Return true if current statement is a scoping statement (in terms of iterator), 
else false.

=cut

sub endScopeStatementType($) {
    my($self) = @_;

    my $stType = $self->getStatementType;
    return
      $stType eq CLASS_END ||
      $stType eq NAMESPACE_END;
}

#------------------------------------------------------------------------------

=head2 I<pushScope($name)>

Push scope with $name.  Namespaces are also maintained in a namespace scope
array.

=cut

sub pushScope($$) {
    my($self,$name) = @_;

    push(@{$self->{currentScope}}, $name);
    push(@{$self->{currentNSScope}}, $name) if $self->getStatementType eq NAMESPACE;
}

#------------------------------------------------------------------------------

=head2 I<popScope($statementType)>

Pop scope.

=cut

sub popScope($$) {
    my($self,$stType) = @_;

    pop(@{$self->{currentScope}});
    pop(@{$self->{currentNSScope}}) if $stType eq NAMESPACE;
}

#------------------------------------------------------------------------------

=head2 I<getScope()>

=cut

sub getScope($) {
    my($self) = @_;

    my $ret = "";
    if ($self->{currentScope} and @{$self->{currentScope}}) {
        $ret = join "", (map { $_ . "::" } @{$self->{currentScope}});
        $ret =~ s/::$//o;
    }
    return $ret;
}

#------------------------------------------------------------------------------

=head2 I<getNSScope()>

=cut

sub getNSScope($) {
    my($self) = @_;

    my $ret = "";
    if ($self->{currentNSScope} and @{$self->{currentNSScope}}) {
        $ret = join "", (map { $_ . "::" } @{$self->{currentNSScope}});
        $ret =~ s/::$//o;
    }
    return $ret;
}

#------------------------------------------------------------------------------

=head1 Name methods

These methods manage exposed names (indentifiers).

=cut

#------------------------------------------------------------------------------

=head2 I<saveName($name)>

Save $name of statement type.

=cut

sub saveName($$) {
    my($self,$name) = @_;

    return if $name eq "";

    my $stType = $self->getStatementType;
    $self->{names}->{$stType}->{$name}++;

    # save definition as declaration in case no separate declaration
  SWITCH: {
        $self->{names}->{METHOD_FWD}->{$name}++,          last SWITCH if $stType eq METHOD;
        $self->{names}->{OPERATOR_FWD}->{$name}++,        last SWITCH if $stType eq OPERATOR;
        $self->{names}->{FUNCTION_FWD}->{$name}++,        last SWITCH if $stType eq FUNCTION;
        $self->{names}->{STATIC_FUNCTION_FWD}->{$name}++, last SWITCH if $stType eq STATIC_FUNCTION;
    }
}

#------------------------------------------------------------------------------

=head2 I<getName()>

Test if name exists, else undef.

=cut


sub getName($$;$) {
    my($self,$name,$stType) = @_;

    my $statementType = $stType || $self->getStatementType;
    return $self->{names}->{$statementType}->{$name};
}

#------------------------------------------------------------------------------

=head2 I<getNames(@statementTypes)>

Return all names of statement types.

=cut


sub getNames($@) {
    my($self,@entities) = @_;

    my @ret;
    for my $entity(@entities) {
        push @ret, keys(%{$self->{names}->{$entity}});
    }
    return @ret;
}

#------------------------------------------------------------------------------

=head1 Parsing methods

These methods do the actual analysis (and identification) of statement content.

=cut

#------------------------------------------------------------------------------

=head2 I<parseStatement()>

Determine type of C++ statement and set it.  As side effect get name of
entity (if appropriate) and return this.

=cut

sub parseStatement($$) {
    my($self,$statement) = @_;

    # do not go inside methods
    if ($self->inBlock(METHOD)   or 
        $self->inBlock(FUNCTION) or 
        $self->inBlock(OPERATOR) or
        $self->inBlock(STATIC_FUNCTION)) {
        $self->setStatementType(OTHER);
        return "";
    }

    my $type;
    my $name = "";
  SWITCH: foreach ($statement) {
        $type = UNAMESPACE,               last if /\bnamespace\b\s*?{/o;
        $type = NAMESPACE,    $name = $1, last if /\bnamespace\b\s*([\w:]*\w)\s*{/so;
        $type = SEMI_COLON,               last if /^\s*;\s*$/o;
        $type = FRIEND,                   last if /\bfriend\b/;
        $type = USING,                    last if /\busing\b/o;
        $type = CLASS,        $name = $1, last if /\b(?:class|struct)\b\s*([\w:]*\w)(?:.*?)\s*{/so;
        $type = CLASS_FWD,                last if /\b(?:class|struct)\b\s*\w+\s*;/o;
        $type = METHOD,       $name = $1, last if /(?:\bextern\s*["]C["])?\s*((?:\w+<[\w\s,]+>::)*[:\w~]+)\s*(?<![\(\)=])\s*\(.*?\)\s*(?:const)?\s*{/so;
        $type = METHOD_FWD,       $name = $1, last if /(?:\bvirtual\s*)?\s*((?:\w+<[\w\s,]+>::)*[:\w~]+)\s*(?<![\(\)=])\s*\(.*?\)\s*(?:const)?\s*=\s*0\s*;/so;
        $type = METHOD_FWD,   $name = $1, last if /(?:\bextern\s*["]C["])?\s*((?:\w+<[\w\s,]+>::)*[:\w~]+)\s*(?<![\(\)=])\s*\(.*?\)\s*(?:const)?\s*;/so;
        $type = EXTERNC,                  last if /\bextern\s+"C"/o;
        $type = EXTERN,                   last if /\bextern\b/o;
        $type = OPERATOR,     $name = $1, last if /\s*((?:\w+<[\w\s,]+>::|[:\w]+)*operator\s*\S+)\s*(?<![\(\)])\s*\(.*?\)\s*{/so;
        $type = OPERATOR_FWD, $name = $1, last if /\s*((?:\w+<[\w\s,]+>::|[:\w]+)*operator\s*\S+)\s*(?<![\(\)])\s*\(.*?\)\s*;/so;
        $type = UNION,        $name = $1, last if /\bunion\b\s*([\w:]*\w)\s*{/o;
        $type = UNION_FWD,                last if /\bunion\b\s*([\w:]*\w)\s*;/o;
        $type = ENUM,         $name = $1, last if /\benum\b\s*([\w:]*\w)\s*{/o;
        $type = OTHER;
    }

    # Do some name normalization...
    $name =~ s/^\s*(.*?)\s*$/$1/go;            # remove leading/trailing spaces
    $name =~ s/([^<]*?)<.*?>([^>]*?)/$1$2/go;  # remove template types
    $name =~ s/operator\s*(\S+)/operator $1/;  # remove extraneous spaces in operator

    # derive function from method...
    if (($type eq METHOD_FWD or $type eq METHOD) and !$self->inClassOrStruct) {
        $type eq METHOD_FWD and $type = FUNCTION_FWD or $type = FUNCTION;
        if ($statement =~ /\bstatic\b/) {
            $type eq FUNCTION and $type = STATIC_FUNCTION or $type = STATIC_FUNCTION_FWD;
        }
    }

    $self->setStatementType($type);
    return ($name);
}

#------------------------------------------------------------------------------

=head1 Iteration methods

These control statement iteration.

=cut

#------------------------------------------------------------------------------

=head2 I<next()>

=cut

my $strpat     = gen_delimited_pat(q'"');
my $charlitPat = gen_delimited_pat(q/'/);   # char' literal

sub next ($) {
    my($self) = @_;

    # infinite loop
    while (1) {

        # 'initialize' resets position and checks for end of input
        return if !$self->initialize;

        # default statement type
        $self->setStatementType(OTHER);

        # return value
        my $match;


        # PRE-PROCESSOR

        if (${$self->{src}} =~ /\G(\s*\#(?:.*\\\n)*.*\n)/o) {
            $match = $1;
            $self->setStatementType(PREPROCESSOR);
            pos(${$self->{src}}) += length($match);
            $self->savePos, next if $self->notSelected;
          SWITCH: {
                $self->setStatementType(INCLUDE),      last if $match =~ /^\s*#\s*include\s+/o;
                $self->setStatementType(DEFINE),       last if $match =~ /^\s*#\s*define\s+/o;
            }
            $self->savePos;
            return $match
        }

        # COMMENT

        if (${$self->{src}} =~ m-\G(\s*//.*)$-mo or
            ${$self->{src}} =~ m-\G(\s*/\*([^*]|\*[^/])*\*/)-so) {
            $match = $1;
            pos(${$self->{src}}) += length($match);
            $self->setStatementType(COMMENT);
            $self->savePos;
            return $match;
        }

        # STATEMENT

        # match up to, and including, either '{', '}' or ';'
        if (${$self->{src}} =~ /\s*(($strpat|$charlitPat|[^\"\'])*?)([{};])/sgo) {
            $match = $1.$3;
        }
        else {
            $self->throw("Can't get next segment of C++ source");
        }
        my $delim = $3;

        # '{' - block start

        if ($delim eq "{") {

            # back up and extract statement within braces
            pos(${$self->{src}}) -= length($match);
            my ($beforeDelim, $inDelim, $afterDelim) = "";
            my $toEnd = substr(${$self->{src}}, pos(${$self->{src}}));
            ($inDelim, $afterDelim, $beforeDelim) = extract_bracketed($toEnd, "{}", "[^{}]*");
            $match = $beforeDelim.$delim;

            # determine statement type, save block info
            my($name) = $self->parseStatement($match);
            $self->pushBlock(length($beforeDelim.$inDelim));
            if ($self->notSelected) {
                $self->skipBlock;
                $self->savePos;
                next;
            }

            # start up new scope and save name (which we know is scope)
            if ($self->startScopeStatementType) {
                $self->pushScope($name);
                $self->saveName($self->getScope);
            }

            # save name with fully-qualified scope
            elsif ($name) {
                $self->saveName(normalizeScopedName($self->getScope, $name));
            }

            pos(${$self->{src}}) += length($beforeDelim) + 1;
        }

        # '}' - block end

        elsif ($delim eq "}") {
	    my $blockType = $self->atBlockEnd;
	    if ($blockType) {
		if ($blockType eq OTHER) {
		    $self->setStatementType(OTHER);
		}
		else {
		    $self->setStatementType($blockTypes{$blockType});
		    $self->popBlock($blockType);
		    $self->popScope($blockType)
		      if $self->endScopeStatementType;
		}
		$self->savePos, next if $self->notSelected;
	    } else {
		# bdes_assert causes this condition amongst other components
		debug "!! Reached end of block but not in a block?\n";
	    }
	}

        # ';' - other statement

        elsif ($delim eq ";") {
            my($name) = $self->parseStatement($match);
            $self->savePos, next if $self->notSelected;
            $name and $self->saveName(normalizeScopedName($self->getScope, $name));
        }

        $self->savePos;
        return $match;

    } 
}

#==============================================================================

=head1 AUTHOR

Ralph Gibbons (rgibbons1@bloomberg.net)

=head1 SEE ALSO

L<SourceIterator>, L<Source::Symbols>

=cut

1;



