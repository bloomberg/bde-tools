// csatr_includefiles.t.cpp                                           -*-C++-*-
// ----------------------------------------------------------------------------

#include "csatr_includefiles.t.h"

#if 0
namespace bde_verify
{
    namespace csatr
    {
        namespace
        {
            class local_class {};
        }

        namespace
        {
            enum E { eval };
            class C { };
            class D;
            typedef D F;
            typedef C G;

            template <typename T, int S> struct Templ {};

            extern int var_builtin;
            extern E   var_enum;
            extern C   var_class;
            extern G   var_typedef;

            extern int* ptr_builtin;
            extern E*   ptr_enum;
            extern C*   ptr_class;
            extern F*   ptr_typedef;

            extern int& ref_builtin;
            extern E&   ref_enum;
            extern C&   ref_class;
            extern F&   ref_typedef;

            extern int D::*member_builtin;
            extern E   D::*member_enum;
            extern C   D::*member_class;
            extern F   D::*member_typedef;

            extern int array_builtin[3];
            extern E   array_enum[3];
            extern C   array_class[3];
            extern G   array_typedef[3];

            extern int incomplete_array_builtin[];
            extern E   incomplete_array_enum[];
            extern C   incomplete_array_class[];
            extern G   incomplete_array_typedef[];

            extern Templ<int, 3> templ_builtin;
            extern Templ<E, 3>   templ_enum;
            extern Templ<C, 3>   templ_class;
            extern Templ<G, 3>   templ_typedef;

            int var_builtin(0);
            E   var_enum(eval);
            C   var_class;
            G   var_typedef;

            int* ptr_builtin(0);
            E* ptr_enum(0);
            C* ptr_class(0);
            F* ptr_typedef(0);

            int& ref_builtin(*ptr_builtin);
            E&   ref_enum(*ptr_enum);
            C&   ref_class(*ptr_class);
            F&   ref_typedef(*ptr_typedef);

            int D::*member_builtin;
            E   D::*member_enum;
            C   D::*member_class;
            F   D::*member_typedef;

            int array_builtin[3];
            E   array_enum[3];
            C   array_class[3];
            G   array_typedef[3];

            Templ<int, 3> templ_builtin;
            Templ<E, 3>   templ_enum;
            Templ<C, 3>   templ_class;
            Templ<G, 3>   templ_typedef;

        }
    }
}
#endif

int                             bde_verify::csatr::includeFilesVarBuiltin;
bde_verify::csatr::IncludeVarEnum    bde_verify::csatr::includeFilesVarEnum;
bde_verify::csatr::IncludeVarClass   bde_verify::csatr::includeFilesVarClass;
bde_verify::csatr::IncludeVarTypedef bde_verify::csatr::includeFilesVarTypedef;

int main(int ac, char*[])
{
    //bde_verify::csatr::local_class();
    return ac;
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
