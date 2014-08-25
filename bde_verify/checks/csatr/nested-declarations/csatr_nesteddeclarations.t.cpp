// csatr_nesteddeclarations.t.cpp                                     -*-C++-*-

#include "csatr_nesteddeclarations.t.hpp"
#include <bdes_ident.h>

// -----------------------------------------------------------------------------

struct bad_global_struct1;
struct bad_global_struct2 {};
int bad_global = 0;
void bad_global_function() {}

namespace
{
    struct bad_anonymous_struct1;
    struct bad_anonymous_struct2 {};
    int bad_anonymous_global = 0;
    void bad_anonymous_function() {}
}

namespace csatr
{
    struct bad_csatr_struct1;
    struct bad_csatr_struct2 {};
    int bad_csatr_variable = 0;
    void bad_csatr_function() {}

    namespace
    {
        struct bad_csatr_anonymous_struct1;
        struct bad_csatr_anonymous_struct2 {};
        int bad_csatr_anonymous_variable = 0;
        void bad_csatr_anonymous_function() {}
    }
}

namespace top
{
    namespace csatr
    {
        struct bad_top_csatr_struct1;
        struct bad_top_csatr_struct2 {};
        int bad_top_csatr_variable = 0;
        void bad_top_csatr_function() {}

        namespace
        {
            struct bad_top_csatr_anonymous_struct1;
            struct bad_top_csatr_anonymous_struct2 {};
            int bad_top_csatr_anonymous_variable = 0;
            void bad_top_csatr_anonymous_function() {}
        }
    }
}

namespace bde_verify
{
    namespace csatr
    {
        struct good_source_struct1;
        struct good_source_struct2 {};
        int good_source_global = 0;
        void good_source_function() {}

        namespace
        {
            struct good_source_anonymous_struct1;
            struct good_source_anonymous_struct2 {};
            int good_source_anonymous_global = 0;
            void good_source_anonymous_function() {}
        }
    }
}

int main()
{
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
