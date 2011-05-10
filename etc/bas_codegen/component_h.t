[% PROCESS component_util.t -%]
// [% String.new(basename).append('.h').lower %]   -*-C++-*-   [% -%]
[%- %]GENERATED FILE -- DO NOT EDIT
[% SET INCLUDE_GUARD = String.new('INCLUDED_').append(basename).upper -%]
#ifndef [% INCLUDE_GUARD %]
#define [% INCLUDE_GUARD %]

#ifndef INCLUDED_BDES_IDENT
#include <bdes_ident.h>
#endif
BDES_IDENT_RCSID([% basename %]_h,"\$Id\$ \$CSID\$ \$CCId\$")
BDES_IDENT_PRAGMA_ONCE

//@PURPOSE: Provide value-semantic attribute classes
//
//@AUTHOR: [% cmp.author %]

[% IF cmp.hasCustomizedType -%]
[% IF cmp.supportsAggregateConversion -%]
#ifndef INCLUDED_BCEM_AGGREGATE
#include <bcem_aggregate.h>
#endif

[% END -%]
[% END -%]
#ifndef INCLUDED_BDEALG_TYPETRAITS
#include <bdealg_typetraits.h>
#endif

[% IF cmp.supportsIntrospection -%]
#ifndef INCLUDED_BDEAT_ATTRIBUTEINFO
#include <bdeat_attributeinfo.h>
#endif

[% IF cmp.hasEnumeration -%]
#ifndef INCLUDED_BDEAT_ENUMERATORINFO
#include <bdeat_enumeratorinfo.h>
#endif

[% END -%]
[% IF cmp.hasComplexType -%]
#ifndef INCLUDED_BDEAT_SELECTIONINFO
#include <bdeat_selectioninfo.h>
#endif

[% END -%]
[% END -%]
#ifndef INCLUDED_BDEAT_TYPETRAITS
#include <bdeat_typetraits.h>
#endif
[% IF cmp.hasCustomizedType -%]

#ifndef INCLUDED_BDEAT_VALUETYPEFUNCTIONS
#include <bdeat_valuetypefunctions.h>
#endif
[% END -%]

[% IF cmp.hasComplexType -%]
#ifndef INCLUDED_BDES_OBJECTBUFFER
#include <bdes_objectbuffer.h>
#endif

[% END -%]
#ifndef INCLUDED_BDEX_INSTREAMFUNCTIONS
#include <bdex_instreamfunctions.h>
#endif

#ifndef INCLUDED_BDEX_OUTSTREAMFUNCTIONS
#include <bdex_outstreamfunctions.h>
#endif

[% IF cmp.allocatesMemory -%]
#ifndef INCLUDED_BSLMA_DEFAULT
#include <bslma_default.h>
#endif

[% END -%]
#ifndef INCLUDED_BSLS_ASSERT
#include <bsls_assert.h>
#endif

[% SET thisFile = String.new(basename).append('.h') -%]
[% FOREACH cmp.include -%]
[% IF thisFile != file -%]
#ifndef [% guard %]
#include <[% file %]>
[% IF defineGuardExternally -%]
#define [% guard %]
[% END -%]
#endif
[% END -%]

[% END -%]
#ifndef INCLUDED_BSL_IOSFWD
#include <bsl_iosfwd.h>
#define INCLUDED_BSL_IOSFWD
#endif

[% IF cmp.hasEnumeration -%]
#ifndef INCLUDED_BSL_OSTREAM
#include <bsl_ostream.h>
#define INCLUDED_BSL_OSTREAM
#endif

[% END -%]
[% cmp.annotation.appinfo.rawCppHeader -%]
namespace BloombergLP {

[% IF cmp.allocatesMemory -%]
class bslma_Allocator;

[% END -%]
[% IF cmp.supportsAggregateConversion -%]
[% IF cmp.hasComplexType && !cmp.hasCustomizedType -%]
class bcem_Aggregate;

[% END -%]
[% END -%]
[% FOREACH class = cmp.classes -%]
[% UNLESS "enumeration" == class.trait -%]
namespace [% namespace %] { class [% class.cpptype %]; }
[% END -%]
[% END -%]
[%- FOREACH class = cmp.classes -%]
namespace [% namespace %] {
[%- IF "sequence" == class.trait -%]
[%- SET sequence = class -%]
[%- PROCESS sequence_h.t -%]
[%- INCLUDE sequenceClassDeclaration -%]
[%- ELSIF "choice" == class.trait -%]
[%- SET choice = class -%]
[%- PROCESS choice_h.t -%]
[%- INCLUDE choiceClassDeclaration -%]
[%- ELSIF "customizedtype" == class.trait -%]
[%- SET customizedtype = class -%]
[%- PROCESS customizedtype_h.t -%]
[%- INCLUDE customizedtypeClassDeclaration -%]
[%- ELSIF "enumeration" == class.trait -%]
[%- SET enumeration = class -%]
[%- PROCESS enumeration_h.t -%]
[%- INCLUDE enumerationClassDeclaration -%]
[%- END -%]

}  // close namespace [% namespace %]

// TRAITS
[%- IF "sequence" == class.trait -%]
[%- SET sequence = class -%]
[%- PROCESS sequence_h.t -%]
[%- INCLUDE sequenceTraitDeclarations -%]
[%- ELSIF "choice" == class.trait -%]
[%- SET choice = class -%]
[%- PROCESS choice_h.t -%]
[%- INCLUDE choiceTraitDeclarations -%]
[%- ELSIF "customizedtype" == class.trait -%]
[%- SET customizedtype = class -%]
[%- PROCESS customizedtype_h.t -%]
[%- INCLUDE customizedtypeTraitDeclarations -%]
[%- ELSIF "enumeration" == class.trait -%]
[%- SET enumeration = class -%]
[%- PROCESS enumeration_h.t -%]
[%- INCLUDE enumerationTraitDeclarations -%]
[%- END %]

[% END -%]
[% IF opts.needDummyType -%]
namespace [% namespace %] {

[% SET fatline = String.new('=').repeat(opts.dummyTypeName.length)
                                .append('======')
-%]
[% String.new("// $fatline").center(80) %]
[% String.new("// class $opts.dummyTypeName").center(80) %]
[% String.new("// $fatline").center(80) %]

struct [% opts.dummyTypeName -%] {
    // This class serves as a place holder to reserve a type having the same
    // name as this component.  Doing so ensures that such a type cannot be
    // defined outside of this component in the current namespace.
};

}  // close namespace [% namespace %]

[% END -%]
// ============================================================================
//                         INLINE FUNCTION DEFINITIONS
// ============================================================================

namespace [% namespace %] {[% -%]
[%- FOREACH class = cmp.classes -%]
[%- IF "sequence" == class.trait -%]
[%- SET sequence = class -%]
[%- PROCESS sequence_h.t -%]
[%- INCLUDE sequenceInlineMethods -%]
[%- ELSIF "choice" == class.trait -%]
[%- SET choice = class -%]
[%- PROCESS choice_h.t -%]
[%- INCLUDE choiceInlineMethods -%]
[%- ELSIF "customizedtype" == class.trait -%]
[%- SET customizedtype = class -%]
[%- PROCESS customizedtype_h.t -%]
[%- INCLUDE customizedtypeInlineMethods -%]
[%- ELSIF "enumeration" == class.trait -%]
[%- SET enumeration = class -%]
[%- PROCESS enumeration_h.t -%]
[%- INCLUDE enumerationInlineMethods -%]
[%- END -%]
[%- END -%]
}  // close namespace [% namespace %]

// FREE FUNCTIONS
[%- FOREACH class = cmp.classes -%]
[%- IF "sequence" == class.trait -%]
[%- SET sequence = class -%]
[%- PROCESS sequence_h.t -%]
[%- INCLUDE sequenceInlineFreeFunctions -%]
[%- ELSIF "choice" == class.trait -%]
[%- SET choice = class -%]
[%- PROCESS choice_h.t -%]
[%- INCLUDE choiceInlineFreeFunctions -%]
[%- ELSIF "customizedtype" == class.trait -%]
[%- SET customizedtype = class -%]
[%- PROCESS customizedtype_h.t -%]
[%- INCLUDE customizedtypeInlineFreeFunctions -%]
[%- ELSIF "enumeration" == class.trait -%]
[%- SET enumeration = class -%]
[%- PROCESS enumeration_h.t -%]
[%- INCLUDE enumerationInlineFreeFunctions -%]
[%- END -%]

[%- END -%]

}  // close namespace BloombergLP
#endif

// GENERATED BY [% version %] [% timestamp %]
// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., [% year.format %]
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ------------------------------ END-OF-FILE ---------------------------------
