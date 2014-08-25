// csastil_uppernames.t.cpp                                           -*-C++-*-

#include <stdio.h>

namespace bde_verify {
namespace csastil {
namespace {

int AA;

void BB()
{
    int BB_AA;
    struct BB_CC
    {
    };
}

struct CC
{
    int CC_AA;
    template <class CC_DD> struct CC_EE { };
};

}

template <class DD> struct EE
{
    int EE_AA;
    struct EE_CC  { };
    template <class EE_DD> struct EE_EE { };
    template <class EE_FF> struct EE_GG;
};

}
}

template <class EE_HH>
template <class EE_II>
struct bde_verify::csastil::EE<EE_HH>::EE_GG
{
    EE_HH JJ;
    EE_II KK;
};

int LL_CSASTIL_UPPERNAMES;

#define BIG BIG_NAME

int BIG;

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
