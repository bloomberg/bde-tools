package Source::Symbols;

use base 'Symbols';

#------------------------------------------------------------------------------

1;

__DATA__

# TODO: these are strings just to make debugging easier

PREPROCESSOR           => "preprocessor"
COMMENT                => "comment"
INCLUDE                => "include"
DEFINE                 => "define"

EXTERN                 => "extern"
EXTERNC                => "externc"
EXTERNC_END            => "_externc"

UNAMESPACE             => "unamespace"
UNAMESPACE_END         => "_unamespace"
NAMESPACE              => "namespace"
NAMESPACE_END          => "_namespace"

CLASS_FWD              => "class_fwd"
CLASS                  => "class"
CLASS_END              => "_class"

# 'STRUCT' is the same as 'CLASS'.
# STRUCT_FWD             => "struct_fwd"
# STRUCT                 => "struct"
# STRUCT_END             => "_struct"

METHOD_FWD             => "method_fwd"
METHOD                 => "method"
METHOD_END             => "_method"

OPERATOR_FWD           => "operator_fwd"
OPERATOR               => "operator"
OPERATOR_END           => "_operator"

FUNCTION_FWD           => "function_fwd"
FUNCTION               => "function"
FUNCTION_END           => "_function"

STATIC_FUNCTION_FWD    => "static_function_fwd"
STATIC_FUNCTION        => "static_function"
STATIC_FUNCTION_END    => "_static_function"

UNION_FWD              => "union_fwd"
UNION                  => "union"
UNION_END              => "_union"

ENUM                   => "enum"
ENUM_END               => "_enum"

FRIEND                 => "friend"
TYPEDEF                => "typedef"
USING                  => "using"
OTHER                  => "other"


SEMI_COLON             => "semi_colon"

DUMMY                  => "DUMMY"

