// csamisc_unnamed_temporary.t.cpp                                    -*-C++-*-

#include <string>

namespace bde_verify {
namespace {

std::string f()
{
    int i1(5);
    int(5);
    (void)int(5);
    int i2(int(5));

    std::string s1("5");
    std::string("5");
    (void)std::string("5");
    std::string s2(std::string("5"));
    std::string(std::string("5"));

    std::string s3(5, ' ');
    std::string(5, ' ');
    (void)std::string(5, ' ');
    std::string s4(std::string(5, ' '));
    std::string(std::string(5, ' '));

    static volatile int i;
    if (i) return std::string();
    if (i) return std::string("5");
    if (i) return std::string(5, ' ');

    for (std::string(); i; std::string()) {
    }

    return std::string();
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
