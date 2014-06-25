// csamisc_auto.t.cpp                                                 -*-C++-*-

#if 0
template <typename T>
struct general_iterator
{
    void operator++();
    bool operator!= (general_iterator const&) const;
    T& operator*();
};

template <typename T>
struct vector
{
#if 0
    struct iterator
    {
        void operator++();
        bool operator!= (iterator const&) const;
        T& operator*();
    };
#else
    typedef general_iterator<T> iterator;
#endif
    iterator begin();
    iterator end();
};

int main()
{
    int  i = 17;
    auto var = 17;
    vector<int> v;
    for (auto it = v.begin(); it != v.end(); ++it) {
        auto& r = *it;
    }
}
#endif

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
