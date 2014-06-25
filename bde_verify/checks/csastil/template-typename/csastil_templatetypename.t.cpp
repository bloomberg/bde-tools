// csastil_templatetypename.t.cpp                                     -*-C++-*-

#include "csastil_templatetypename.t.h"
#include <bdes_ident.h>

template <typename T>
static void bad();

template <typename TT>
static void good();

namespace bde_verify
{
    namespace csastil
    {
        namespace
        {
            template <typename T>
            static void localBad();

            template <class TT>
            static void localGood();
        }

        template <typename AA>
        struct BB
        {
            template <typename CC>
            void f();
        };
    }
}

template <typename YY>
template <typename CC>
void bde_verify::csastil::BB<YY>::f()
{
}

namespace AA {
namespace BB {
    template <typename CC>
    struct DD {
        template <typename EE>
        void f();
    };
}
}

template <typename GG>
template <typename HH>
void AA::BB::DD<GG>::f()
{
}

namespace II {
namespace JJ {
    template <typename KK>
    struct LL
    {
        template <typename MM>
        struct NN;
    };
}
}

template <typename OO>
template <typename PP>
struct II::JJ::LL<OO>::NN
{
};

template<template <class> class QQ>
void RR()
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
