// csamisc_boolcomparison.t.cpp                                       -*-C++-*-

namespace bde_verify
{
    namespace csamisc
    {
        bool boolcomparison();
    }
}

int main()
{
    typedef bool Boolean;
    bool       b0 = bde_verify::csamisc::boolcomparison();
    Boolean    b1 = bde_verify::csamisc::boolcomparison();
    bool const b2 = bde_verify::csamisc::boolcomparison();
    int  i(0);

    if (i     == 0) {}
    if (i     == true) {}
    if (i     == false) {}
    if (b0    == 0) {}
    if (b0    == true) {}
    if (b0    == false) {}
    if (b1    == 0) {}
    if (b1    == true) {}
    if (b1    == false) {}
    if (b2    == 0) {}
    if (b2    == true) {}
    if (b2    == false) {}
    if (0     == i) {}
    if (true  == i) {}
    if (false == i) {}
    if (0     == b0) {}
    if (true  == b0) {}
    if (false == b0) {}
    if (0     == b1) {}
    if (true  == b1) {}
    if (false == b1) {}
    if (0     == b2) {}
    if (true  == b2) {}
    if (false == b2) {}

    if (true  != b0) {}
    if (true  <= b0) {}
    if (true  <  b0) {}
    if (true  >= b0) {}
    if (true  >  b0) {}
    if (true  |  b0) {}
    if (true  +  b0) {}
    if (true  || b0) {}
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
