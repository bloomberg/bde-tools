// csamisc_memberdefinitioninclassdefinition.v.cpp                    -*-C++-*-

#include "csamisc_memberdefinitioninclassdefinition.v.hpp"
#include <bdes_ident.h>

void bde_verify::csamisc::memberdefinitioninclassdefinition_foo::g()
{
}

// -----------------------------------------------------------------------------

template <typename T>
inline void bde_verify::csamisc::memberdefinitioninclassdefinition_bar<T>::f()
{
}

template class bde_verify::csamisc::memberdefinitioninclassdefinition_bar<int>;

namespace bde_verify
{
    namespace csamisc
    {
        namespace
        {
            void instantiate()
            {
                bde_verify::csamisc::memberdefinitioninclassdefinition_bar<int> b;
            }
        }
    }
}

// ----------------------------------------------------------------------------

namespace bde_verify
{
    namespace csamisc
    {
        struct base {
            virtual ~base();
            virtual void f();
        };
        struct foobar: base {
            void f();
        };

        void operator-(base&) {
            bde_verify::csamisc::foobar u;
            bde_verify::csamisc::foobar o(u);
            o.f();
        }

        void f() {
            struct g {
                g() { }
                void foo() { }
            };
        }
    }
}

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
