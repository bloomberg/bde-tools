// csatr_nesteddeclarations.t.hpp                                     -*-C++-*-

#ifndef INCLUDED_CSATR_NESTEDDECLARATIONS
#define INCLUDED_CSATR_NESTEDDECLARATIONS

#if !defined(INCLUDED_BDES_IDENT)
#  include <bdes_ident.h>
#endif
#ifndef INCLUDED_CSASCM_VERSION
#  include <csascm_version.h>
#endif

#ifndef INCLUDED_CSATR_OTHERS
#include "csatr_others.hpp"
#endif

// -----------------------------------------------------------------------------

struct good_global_struct;
struct nesteddeclarations_bad_global_struct
{
    int member;
    void method();
    struct nested {};
};
void nesteddeclarations_bad_global_function();
int nesteddeclarations_bad_global_variable;

namespace bde_verify
{
    struct good_bde_verify_struct;
    struct nesteddeclarations_bad_bde_verify_struct
    {
        int member;
        void method();
        struct nested {};
    };
    void nesteddeclarations_bad_bde_verify_function();
    int nesteddeclarations_bad_bde_verify_variable;

    namespace csamisc
    {
        struct good_bde_verify_csamisc_struct;
        struct nesteddeclarations_bad_bde_verify_csamisc_struct
        {
            int member;
            void method();
            struct nested {};
        };
        void nesteddeclarations_bad_bde_verify_csamisc_function();
        int nesteddeclarations_bad_bde_verify_csamisc_variable;
    }

    namespace csatr
    {
        struct good_struct1;
        struct nesteddeclarations_good_struct2
        {
            struct good_nested {};
            void good_method();
            int  good_member;
        };

        void nesteddeclarations_good_function();
        int nesteddeclarations_good_bde_verify_csatr_variable;
    }

    struct csatr_NestedDeclarations
    {
    };

    void swap(csatr_NestedDeclarations&, csatr_NestedDeclarations&);
    bool operator== (const csatr_NestedDeclarations&,
                    const  csatr_NestedDeclarations&);
    bool operator!= (const csatr_NestedDeclarations&,
                    const  csatr_NestedDeclarations&);
}

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
