// <#= COMPONENT_NAME #>.<#= EXTENSION #><#= ' '*(66-len(COMPONENT_NAME)-len(EXTENSION)) #>-*-C++-*-
#ifndef INCLUDED_<#= COMPONENT_NAME.upper() #>
#define INCLUDED_<#= COMPONENT_NAME.upper() #>

<#= IDENT #>
//@PURPOSE: Provide an attribute class for characterizing ...
//
//@CLASSES:
//   <#= PACKAGE_NAME #>::<#= CLASS_NAME #>: <<description>>
//
//@AUTHOR: <#= AUTHOR_INFO #>
//
//@SEE ALSO:
//
//@DESCRIPTION: This component provides a single, simply constrained
// (value-semantic) attribute class, <#= "'"+CLASS_NAME+"'" #>, that is used
// to characterize ...
//
///Attributes
///----------
//..
//  Name                Type         Default  Simple Constraints
//  ------------------  -----------  -------  ------------------
//  name                type         0        none
//..
//: o 'name': <<description>>
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

#ifndef INCLUDED_BSLMA_ALLOCATOR
#include <bslma_allocator.h>
#endif

namespace BloombergLP {
namespace <#= PACKAGE_NAME #> {

                        // ======<#= '='*len(CLASS_NAME) #>
                        // class <#= CLASS_NAME #>
                        // ======<#= '='*len(CLASS_NAME) #>

class <#= CLASS_NAME #> {
    // This simply constrained (value-semantic) attribute class characterizes a
    // ....  See the Attributes section under
    // @DESCRIPTION in the component-level documentation for information on the
    // class attributes.  Note that the class invariants are identically the
    // constraints on the individual attributes.
    // This class:
    //: o supports a complete set of *value-semantic* operations
    //:   o except for 'bdex' serialization
    //: o is *exception-neutral* (agnostic)
    //: o is *alias-safe*
    //: o is 'const' *thread-safe*
    // For terminology see 'bsldoc_glossary'.

    // DATA
    // AttributeType d_value;

  public:
    // TRAITS
    BSLALG_DECLARE_NESTED_TRAITS(<#= CLASS_NAME #>,
                                 bslalg_TypeTraitUsesBslmaAllocator);

    // CREATORS
    explicit <#= CLASS_NAME #>(bslma_Allocator *basicAllocator = 0);
        // Create a <#= "'"+CLASS_NAME+"'" #> object having the (default)
        // attribute values:
        //..
        //  accessor() == val
        //..
        // Optionally specify a 'basicAllocator' used to supply memory.  If
        // 'basicAllocator' is 0, the currently installed default allocator is
        // used.

    // explicit <#= CLASS_NAME #>(const AttirbuteType& value,
    //                            bslma_Allocator *basicAllocator = 0);
        // Create a <#= "'"+CLASS_NAME+"'" #> object having the specified
        // 'value'... attribute
        // values.  Optionally specify a 'basicAllocator' used to supply
        // memory.  If 'basicAllocator' is 0, the currently installed default
        // allocator is used.  The behavior is undefined unless ...

    <#= CLASS_NAME #>(const <#= CLASS_NAME #>&   original,
                      bslma_Allocator           *allocator = 0);
        // Create a <#= "'"+CLASS_NAME+"'" #> object having the same value
        // as the specified 'original' object.  Optionally specify a
        // 'basicAllocator' used to supply memory.  If 'basicAllocator' is 0,
        // the currently installed default allocator is used.

    // ~<#= CLASS_NAME #>() = default;
        // Destroy this object.

    // MANIPULATORS
    <#= CLASS_NAME #>& operator=(const <#= CLASS_NAME #>& rhs);
        // Assign to this object the value of the specified 'rhs' object, and
        // return a reference providing modifiable access to this object.

    // void setAttributeName(const AttributeType& value)
        // Set the 'attributeName' attribute of this object to the specified
        // 'value'.  The behavior is undefined unless ...

    // ACCESSORS
    // const AttributeType& attributeName() const;
        // Return a reference providing non-modifiable access to the
        // 'attributeName' attribute of this object.
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
<#= CLASS_NAME #>::<#= CLASS_NAME #>(bslma_Allocator *basicAllocator)
{
}

// inline
// <#= CLASS_NAME #>::<#= CLASS_NAME #>(const AttirbuteType& value,
//                                      bslma_Allocator *basicAllocator)
// {
// }

// inline
// <#= CLASS_NAME #>::<#= CLASS_NAME #>(const <#= CLASS_NAME #>& original,
//                                      bslma_Allocator *basicAllocator)
// {
// }

// MANIPULATORS
// inline
// void <#= CLASS_NAME #>::setAttributeName(const AttributeType& value)
// {
// }

// ACCESSORS
// inline
// const AttributeType& <#= CLASS_NAME #>::attributeName() const
// {
// }

// FREE OPERATORS
// inline
// bool operator==(const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& lhs, const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& rhs)
// {
//     return lhs.attributeName() == rhs.attributeName();
// }

// inline
// bool operator!=(const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& lhs, const <#= PACKAGE_NAME #>::<#= CLASS_NAME #>& rhs)
// {
//     return lhs.attributeName() != rhs.attributeName();
// }

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
