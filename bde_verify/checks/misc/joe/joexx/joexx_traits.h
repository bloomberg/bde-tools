// joexx_traits.h                                                     -*-C++-*-
#ifndef INCLUDED_JOEXX_TRAITS
#define INCLUDED_JOEXX_TRAITS

#ifndef INCLUDED_BSLMF_ISTRIVIALLYCOPYABLE
#include <bslmf_istriviallycopyable.h>
#endif

#ifndef INCLUDED_BSLMF_NESTEDTRAITDECLARATION
#include <bslmf_nestedtraitdeclaration.h>
#endif

namespace BloombergLP {
namespace joexx {
class Traits { int a[7]; };
}  // close package namespace
}  // close enterprise namespace

namespace bsl {
template <>
struct is_trivially_copyable<BloombergLP::joexx::Traits> : true_type
{
};
}  // close traits namespace

namespace BloombergLP {
namespace joexx {
class Traits_Bb {
    BSLMF_NESTED_TRAIT_DECLARATION(Traits_Bb, bsl::is_trivially_copyable)
};
class Traits_Cc {
    BSLMF_NESTED_TRAIT_DECLARATION(Traits_Bb, bsl::is_trivially_copyable)
};
}  // close package namespace
}  // close enterprise namespace

#endif
