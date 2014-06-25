// csamisc_charvsstring.t.cpp                                         -*-C++-*-

namespace bde_verify
{
    namespace csamisc
    {
        void f(const char*);
        void f(int, const char*);
        void f(int, const char*, int);

        namespace {
            struct g
            {
                g(const char*) {}                                   // IMPLICIT
                g(int, const char*) {}
                void operator()(const char*) {}
                void operator()(int, const char*) {}
            };
        }
    }
}

using namespace bde_verify::csamisc;

int main()
{
    char array[] = "hello";
    char value('/');
    f("hello"); // OK
    f(array); // OK
    f(&array[0]); // OK
    f(&value); // not OK
    f(0, "hello"); // OK
    f(0, array); // OK
    f(0, &array[0]); // OK
    f(0, &value); // not OK
    f(0, "hello", 1); // OK
    f(0, array, 1); // OK
    f(0, &array[0], 1); // OK
    f(0, &value, 1); // not OK

    g g0("hello"); // OK
    g g1(array); // OK
    g g2(&array[0]); // OK
    g g3(&value); // not OK
    g g4(0, "hello"); // OK
    g g5(0, array); // OK
    g g6(0, &array[0]); // OK
    g g7(0, &value); // not OK

    g0("hello"); // OK
    g1(array); // OK
    g2(&array[0]); // OK
    g3(&value); // not OK
    g4(0, "hello"); // OK
    g5(0, array); // OK
    g6(0, &array[0]); // OK
    g7(0, &value); // not OK
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
