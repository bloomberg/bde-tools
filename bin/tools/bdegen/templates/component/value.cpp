// <#= COMPONENT_NAME #>.<#= EXTENSION #><#= ' '*(66-len(COMPONENT_NAME)-len(EXTENSION)) #>-*-C++-*-
#include <<#= COMPONENT_NAME #>.h>

<#= IDENT #>
#include <bdes_ident.h>
BDES_IDENT_RCSID(<#= COMPONENT_NAME.lower()+"_cpp" #>, "$Id$ $CSID$")

namespace BloombergLP {
namespace <#= PACKAGE_NAME #> {

namespace {

}  // close anonymous namespace

                        // ------<#= '-'*len(CLASS_NAME) #>
                        // class <#= CLASS_NAME #>
                        // ------<#= '-'*len(CLASS_NAME) #>

// CREATORS
<#= CLASS_NAME #>::<#= CLASS_NAME #>(bslma_Allocator *allocator)
{
}

<#= CLASS_NAME #>::~<#= CLASS_NAME #>()
{
}

// MANIPULATORS

// ACCESSORS

}  // close package namespace
}  // close enterprise namespace

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., <#= datetime.date.today().year #>
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
