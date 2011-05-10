package BDE::Rule::Codes;
use strict;
use base qw(Context::Message::Codes);

use vars qw($OVERRIDE_PREFIX);
$OVERRIDE_PREFIX = "CONTEXT_MSG_";

1;

__DATA__

# 'NO' - Missing construct errors
NO_IFNDEF_GUARD  => missing/invalid "#ifndef <guard>"
NO_DEFINE_GUARD  => missing/invalid "#define <guard>"
NO_GLUE          => missing glue function declaration
NO_ENTRY         => missing entry point component
NO_ENTRYF        => missing entry point file
NO_TABS          => tab characters are not allowed
NO_INTF_INCLUDE  => .h must be included first
NO_METHOD_TEST   => method not tested:
NO_FUNC_DEC      => method/function definition not declared in .h:
NO_T_CPP         => no .t.cpp file for component:

# 'BAD' - Invalid construct errors

# 'ILL' - Invalid construct in particular context
ILL_EXTERN       => extern declaration not allowed
ILL_FRIEND_TYPE  => friend type must be defined in same component
ILL_FRIEND_ARGS  => friend parameter types must be defined in same component
ILL_TST_DEP      => component dependencies exceeded
ILL_INCLUDE      => invalid dependency
ILL_DPT_INCLUDE  => invalid (inter-departmental) dependency
ILL_USING        => "using" statement not allowed in .h except in function scope
ILL_USING_WARN   => avoid "using" statement except within function scope
ILL_SCOPE        => statement not allowed at this scope
ILL_DECDEF       => invalid namespace scope declaration or definition
ILL_FREE_OP      => free operator does not have any types defined in .h - types:
ILL_METHOD_DEF   => method defined but not declared:

# 'EXT' - Extraneous/Too much input errors
EXT_IFNDEF       => #ifndef prematurely terminated

# 'LNG' - Excessive length errors
LNG_COMPNAME     => component name cannot exceed 30 characters
LNG_LINE         => lines cannot exceed 80 characters

# 'NS' - Namespace-related errors
NS_STATE_NON_NS  => statement not in namespace
NS_STATE_NON_PNS => statement not in package-level namespace
NS_NO_BLP        => missing BloombergLP namespace
NS_NO_PKG        => missing package namespace
NS_PG_INVALID    => package group name is deprecated

# 'DPR' - Deprecation warnings
DPR_GUARD        => guard style deprecated

# 'ETC' - Etc. errors
ETC_MORE_ERRORS  => similar error repeats
