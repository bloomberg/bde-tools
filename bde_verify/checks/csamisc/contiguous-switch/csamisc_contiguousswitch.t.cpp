// csamisc_contiguousswitch.t.cpp                                     -*-C++-*-

#include "csamisc_contiguousswitch.t.hpp"
#include <bdes_ident.h>

// -----------------------------------------------------------------------------

namespace bde_verify
{
    namespace csamisc
    {
        namespace
        {
            void f(int ac) {
                switch (ac) {
                case 5:
                    break;
                case 3:
                    break;
                }
            }
        }
    }
}

int main(int, char*[]);

int main(int ac, char* av[])
{
    switch (ac) {
    }

    switch (ac) { // starts with `default:` instead of `case 0:`
    default:
        ++ac;
        break;
    case 1:
        {
            ++ac;
            ++ac;
        }
        break;
    }

    switch (ac) { // doesn't start with `case 0:` and `case 0` in the middle
    case 1: {
        break; 
    }
    case 0: {
        ++ac;
        break;
    }
    default: ;
    }

    switch (ac) { // `default:` not at end
    case 0:
    default: break;
    case 1: break;
    }

    switch (ac) { // `default:` not at end
    case 0:
    case 2: break;
    default: break;
    case 1: break;
    }

    switch (ac) // missing default
    {
    case 0:
        switch (ac + 1) {
        case 10: break;
        case 12: break;
        }
    case 5: break;
    case 4:
    case 3: break;
    case 2: break;
    case 1: break;
    }

    switch (ac)
    {
    case 0:
    case 100: break;
    case 5: break;
    case 4: break;
    case 3: break;
    case 2: break;
    case 1: break;
    case -1: break;
    case -5: break;
    default: break;
    }

    switch (ac)
    {
    case 0:
    case 12:
        ++ac;
        ++ac;
        ++ac;
        { break; }
    case 11:
        { ++ac; }
        ++ac;
        ++ac;
    case 10: {
        ++ac;
        ++ac;
    } break;
    default:
        { break; }
    }
    return 0;
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
