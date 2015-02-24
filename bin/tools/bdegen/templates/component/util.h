// <#= COMPONENT_NAME #>.<#= EXTENSION #><#= ' '*(66-len(COMPONENT_NAME)-len(EXTENSION)) #>-*-C++-*-
#ifndef INCLUDED_<#= COMPONENT_NAME.upper() #>
#define INCLUDED_<#= COMPONENT_NAME.upper() #>

<#= IDENT #>
//@PURPOSE: Provide utilities for
//
//@CLASSES:
//   <#= PACKAGE_NAME #>::<#= CLASS_NAME #>: namespace for
//
//@AUTHOR: <#= AUTHOR_INFO #>
//
//@SEE ALSO:
//
//@DESCRIPTION: This component provides a namespace, <#= "'"+CLASS_NAME+"'" #>
// containing utility functions for ...
//
///Usage
///-----
// This section illustrates intended use of this component.
//
///Example 1:
///- - - - - -
// Suppose that ...
//

namespace BloombergLP {
namespace <#= PACKAGE_NAME #> {

                        // =======<#= '='*len(CLASS_NAME) #>
                        // struct <#= CLASS_NAME #>
                        // =======<#= '='*len(CLASS_NAME) #>

struct <#= CLASS_NAME #> {
    // This 'struct' provides a namespace for utility functions that

    // CLASS METHODS
    static void doSomething();
        // Function level doc
};

// ============================================================================
//                      INLINE FUNCTION DEFINITIONS
// ============================================================================

                        // -------<#= '-'*len(CLASS_NAME) #>
                        // struct <#= CLASS_NAME #>
                        // -------<#= '-'*len(CLASS_NAME) #>

// CLASS METHODS
inline
void <#= CLASS_NAME #>::doSomething()
{
}

}  // close package namespace
}  // close enterprise namespace

#endif

// ----------------------------------------------------------------------------
// Copyright (C) <#= datetime.date.today().year #> Bloomberg L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------
