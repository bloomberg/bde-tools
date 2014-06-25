// csabase_binder.h                                                   -*-C++-*-

#ifndef INCLUDED_CSABASE_BINDER
#define INCLUDED_CSABASE_BINDER

// ----------------------------------------------------------------------------

namespace csabase
{
template <typename Object, typename Function>
class Binder;

template <typename Object, typename...T>
class Binder<Object, void(*)(Object, T...)>
{
private:
    Object d_object;
    void (*d_function)(Object, T...);

public:
    Binder(Object object, void (*function)(Object, T...));
    void operator()(T...a) const;
};

template <typename Object, typename... T>
inline
Binder<Object, void (*)(Object, T...)>::Binder(Object object,
                                               void (*function)(Object, T...))
: d_object(object)
, d_function(function)
{
}

template <typename Object, typename... T>
inline
void Binder<Object, void (*)(Object, T...)>::operator()(T... a) const
{
    d_function(d_object, a...);
}

template <typename Object, typename Function>
inline
Binder<Object, Function> bind(Object object, Function function)
{
    return Binder<Object, Function>(object, function);
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
