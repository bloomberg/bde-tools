// csastil_implicitctor.t.cpp                                         -*-C++-*-

namespace bde_verify {
    namespace csastil {
        namespace
        {
            struct foo {
                foo(foo const&); // -> no warning: this isn't really a conversion
                //foo(foo&&); // -> no warning: this isn't really a conversion
                foo(); // -> no warning: not a conversion
                foo(bool, bool); // -> no warning: not a conversion
                explicit foo(bool); // -> no warning: implicit
                foo(int); // -> warn
                foo(double);                                        // IMPLICIT
                foo(long double);
                                                                    // IMPLICIT
                foo(char = ' '); // -> warn: this is still qualifying for implicit conversions
                foo(short, bool = true, bool = false); // -> warn: ... as is this
                foo(long) {} // -> warn: it is also a definition ...
                foo(unsigned char) {}                               // IMPLICIT
            };

            template <class T>
            struct bar
            {
                bar(int); // -> warn
                bar(char);                                          // IMPLICIT
            };

            template <class T>
            bar<T>::bar(int)
            {
            }

            template <class T>
            bar<T>::bar(char)
            {
            }
        }
    }
}

// ... and none of these should warn:

bde_verify::csastil::foo::foo(bde_verify::csastil::foo const&) {}
//foo::foo(foo&&) {}
bde_verify::csastil::foo::foo(int) {}
bde_verify::csastil::foo::foo(bool) {}
bde_verify::csastil::foo::foo(double) {}
bde_verify::csastil::foo::foo(char) {}
bde_verify::csastil::foo::foo(short, bool, bool) {}

int main()
{
    bde_verify::csastil::bar<int> b0(0);
    bde_verify::csastil::bar<int> b1('c');
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
