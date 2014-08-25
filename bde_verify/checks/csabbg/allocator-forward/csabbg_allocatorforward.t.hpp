// csabbg_allocatorforward.t.hpp                                      -*-C++-*-

#ifndef INCLUDED_CSABBG_ALLOCATORFORWARD
#define INCLUDED_CSABBG_ALLOCATORFORWARD

#ifndef INCLUDED_BDES_IDENT
#  include <bdes_ident.h>
#endif
#ifndef INCLUDED_BSLMF_BSLMF_INTEGRALCONSTANT
#include <bslmf_integralconstant.h>
#endif
#ifndef INCLUDED_CSASCM_VERSION
#  include <csascm_version.h>
#endif

// -----------------------------------------------------------------------------

namespace BloombergLP
{
    namespace bslma
    {
        class Allocator;

        template <typename TYPE> struct UsesBslmaAllocator;
    }

}

namespace bde_verify
{
    namespace csabbg
    {
        class allocatorforward_alloc_unused;
        class allocatorforward_alloc_used;
        void operator+(allocatorforward_alloc_used);
    }
}

// -----------------------------------------------------------------------------

class bde_verify::csabbg::allocatorforward_alloc_unused
{
};

// -----------------------------------------------------------------------------

class bde_verify::csabbg::allocatorforward_alloc_used
{
public:
    //allocatorforward_alloc_used();
    //allocatorforward_alloc_used(int);
                                                                    // IMPLICIT
    explicit allocatorforward_alloc_used(int = 0,
                                         BloombergLP::bslma::Allocator* = 0);
};

// -----------------------------------------------------------------------------

#endif

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
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
