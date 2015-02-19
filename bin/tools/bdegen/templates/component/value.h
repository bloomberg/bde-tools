// <#= COMPONENT_NAME #>.<#= EXTENSION #><#= ' '*(66-len(COMPONENT_NAME)-len(EXTENSION)) #>-*-C++-*-
#ifndef INCLUDED_<#= COMPONENT_NAME.upper() #>
#define INCLUDED_<#= COMPONENT_NAME.upper() #>

<#= IDENT #>
//@PURPOSE: Provide an  ...
//
//@CLASSES:
//   <#= PACKAGE_NAME #>::<#= CLASS_NAME #>: <<description>>
//
//@AUTHOR: <#= AUTHOR_INFO #>
//
//@SEE ALSO:
//
//@DESCRIPTION: This component provides a value-semantic attribute class, <#=
// "'"+CLASS_NAME+"'" #>, that is ...
//
///Usage
///-----
// This section illustrates intended use of this component.
//
///Example 1:
///- - - - - -
// Suppose that ...
//

#ifndef INCLUDED_BSLALG_TYPETRAITS
#include <bslalg_typetraits.h>
#endif

namespace BloombergLP {
namespace <#= PACKAGE_NAME #> {

                        // ======<#= '='*len(CLASS_NAME) #>
                        // class <#= CLASS_NAME #>
                        // ======<#= '='*len(CLASS_NAME) #>

class <#= CLASS_NAME #> {
    // This value-semantic class characterizes a

    // DATA
    // AttributeType d_value;

  public:

    // CREATORS
    <#= CLASS_NAME #>();
        // Create a <#= "'"+CLASS_NAME+"'" #> object ...

    // <#= CLASS_NAME #>(const <#= CLASS_NAME #>& original) = default;
        // Create a <#= "'"+CLASS_NAME+"'" #> object having the same value
        // as the specified 'original' object.

    // ~<#= CLASS_NAME #>() = default;
        // Destroy this object.

    // MANIPULATORS
    // <#= CLASS_NAME #>& operator=(const <#= CLASS_NAME #>& rhs) = default;
        // Assign to this object the value of the specified 'rhs' object, and
        // return a reference providing modifiable access to this object..

    // ACCESSORS
};

// FREE OPERATORS
bool operator==(const <#= CLASS_NAME #>& lhs, const <#= CLASS_NAME #>& rhs);
    // Return 'true' if the specified 'lhs' and 'rhs' objects have the same
    // value, and 'false' otherwise.  Two <#= "'"+CLASS_NAME+"'" #> objects
    // have the same if ...

bool operator!=(const <#= CLASS_NAME #>& lhs, const <#= CLASS_NAME #>& rhs);
    // Return 'true' if the specified 'lhs' and 'rhs' objects do not have the
    // same value, and 'false' otherwise.  Two <#= "'"+CLASS_NAME+"'" #>
    // objects do not have the same value if ...

// ===========================================================================
//                  INLINE AND TEMPLATE FUNCTION IMPLEMENTATIONS
// ===========================================================================

                        // ------<#= '-'*len(CLASS_NAME) #>
                        // class <#= CLASS_NAME #>
                        // ------<#= '-'*len(CLASS_NAME) #>

// CREATORS
inline
<#= CLASS_NAME #>::<#= CLASS_NAME #>()
{
}

// MANIPULATORS

// ACCESSORS
// inline
// const AttributeType& <#= CLASS_NAME #>::attributeName() const
// {
// }

// FREE OPERATORS
inline
bool operator==(const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& lhs, const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& rhs)
{
    return true;
}

inline
bool operator!=(const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& lhs, const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& rhs)
{
    return false;
}

}  // close package namespace
}  // close enterprise namespace

#endif

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., <#= datetime.date.today().year #>
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
