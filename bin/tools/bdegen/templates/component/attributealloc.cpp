// <#= COMPONENT_NAME #>.<#= EXTENSION #><#= ' '*(66-len(COMPONENT_NAME)-len(EXTENSION)) #>-*-C++-*-
#include <<#= COMPONENT_NAME #>.h>

<#= IDENT #>
namespace BloombergLP {
namespace <#= PACKAGE_NAME #> {

                        // ------<#= '-'*len(CLASS_NAME) #>
                        // class <#= CLASS_NAME #>
                        // ------<#= '-'*len(CLASS_NAME) #>


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
