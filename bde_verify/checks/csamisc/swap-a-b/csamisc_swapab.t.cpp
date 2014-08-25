// csamisc_swapab.t.cpp                                               -*-C++-*-

namespace bde_verify
{
    namespace {
        void swap(int  x, int  y);
        void swap(int *x, int &y);
        void swap(int *x, int *y);
        void swap(int *x, int *b);
        void swap(int *a, int *y);
        void swap(int *a, int *b);
        void swap(int &x, int &y);
        void swap(int &x, int &b);
        void swap(int &a, int &y);
        void swap(int &a, int &b);
        void swap(int &a, int &b);
        void swap(int &a, int & );
        void swap(int & , int &b);
        void swap(int & , int & );
        void swap(int * , int *b);
        void swap(int *a, int * );
        void swap(int * , int * );
            // Exchange the specified items.

        template <class SS> void swap(SS  x, SS  y);
        template <class SS> void swap(SS *x, SS &y);
        template <class SS> void swap(SS *x, SS *y);
        template <class SS> void swap(SS *x, SS *b);
        template <class SS> void swap(SS *a, SS *y);
        template <class SS> void swap(SS *a, SS *b);
        template <class SS> void swap(SS &x, SS &y);
        template <class SS> void swap(SS &x, SS &b);
        template <class SS> void swap(SS &a, SS &y);
        template <class SS> void swap(SS &a, SS &b);
        template <class SS> void swap(SS &a, SS &b);
        template <class SS> void swap(SS &a, SS & );
        template <class SS> void swap(SS & , SS &b);
        template <class SS> void swap(SS & , SS & );
        template <class SS> void swap(SS * , SS *b);
        template <class SS> void swap(SS *a, SS * );
        template <class SS> void swap(SS * , SS * );
            // Exchange the specified items.
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
