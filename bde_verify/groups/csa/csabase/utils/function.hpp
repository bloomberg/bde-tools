// function.hpp                                                       -*-C++-*-

#ifndef INCLUDED_UTILS_FUNCTION_HPP
#define INCLUDED_UTILS_FUNCTION_HPP

#include <algorithm>

// -----------------------------------------------------------------------------

namespace utils
{
    template <typename Signature> class function;
    template <typename RC, typename ...T> class function<RC(T...)>;
}

// -----------------------------------------------------------------------------

template <typename RC, typename... T>
class utils::function<RC(T...)>
{
  private:
    struct base
    {
        virtual ~base() { }
        virtual base* clone() = 0;
        virtual RC call(T...) = 0;
    } *function_;

    template <typename Functor>
    struct concrete : base
    {
        concrete(Functor functor) : functor_(functor) { }
        base* clone() { return new concrete(*this); }
        RC call(T... a) { return functor_(a...); }

        Functor functor_;
    };

  public:
    template <typename Functor>
    function(Functor const& functor)
        : function_(new concrete<Functor>(functor))
    {
    }

    function(function const& other) : function_(other.function_->clone())
    {
    }

    function& operator=(function const& other)
    {
        function(other).swap(*this);
        return *this;
    }

    ~function()
    {
        delete function_;
    }

    void swap(function& other)
    {
        std::swap(function_, other.function_);
    }

    RC operator()(T...a) const
    {
        return function_->call(a...);
    }
};

// -----------------------------------------------------------------------------

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
