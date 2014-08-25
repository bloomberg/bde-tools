// csatr_globaltypeonlyinsource.v.cpp                                 -*-C++-*-

#include "csatr_globaltypeonlyinsource.v.hpp"
#include <bdes_ident.h>

namespace bde_verify
{
    namespace csatr
    {
                         struct          { int member; } s_val;
                 typedef struct          { int member; } s_typedef;
                         struct s_extern { int member; };
        namespace      { struct s_local  { int member; }; }

                         class           { int member; } c_val;
                 typedef class           { int member; } c_typedef;
                         class  c_extern { int member; };
        namespace      { class  c_local  { int member; }; }

                         enum            { e0_member   } e_val;
                 typedef enum            { e1_member   } e_typedef;
                         enum   e_extern { e2_member   };
        namespace      { enum   e_local  { e3_member   }; }

                         typedef int t_typedef;
        namespace      { typedef int t_typedef; }
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
