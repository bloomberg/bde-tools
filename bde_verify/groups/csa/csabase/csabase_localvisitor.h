// csabase_localvisitor.h                                             -*-C++-*-

#ifndef INCLUDED_CSABASE_LOCALVISITOR
#define INCLUDED_CSABASE_LOCALVISITOR

#include <csabase_abstractvisitor.h>
#if defined(UTILS_CXX2011)
#  include <utils/forward.hpp>
#endif
#include <clang/AST/Stmt.h>
#include <clang/AST/StmtVisitor.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclVisitor.h>
#include <memory>

// ----------------------------------------------------------------------------

namespace csabase
{
namespace detail
{
#if defined(UTILS_CXX2011)
template <typename...>
class visitor;

template <>
class visitor<>;

template <typename F0, typename... F>
class visitor<F0, F...>;
#else
template <typename F0>
class visitor;
#endif
}

// ----------------------------------------------------------------------------

#if defined(UTILS_CXX2011)
template <>
class detail::visitor<> : public AbstractVisitor
{
};

template <typename F0, typename...F>
class detail::visitor<F0, F...> : public visitor<F...>
{
public:
    typedef typename F0::argument_type argument_type;
    visitor(F0&& functor, F&&...functors);
    void do_visit(argument_type arg);

private:
    F0 functor_;
};

template <typename F0, typename... F>
inline
detail::visitor<F0, F...>::visitor(F0&& functor, F&&...functors)
: visitor<F...>(forward<F>(functors)...)
, functor_(forward<F0>(functor))
{
}

template <typename F0, typename...F>
inline
void detail::visitor<F0, F...>::do_visit(argument_type arg)
{
    functor_(arg);
}
#endif

// ----------------------------------------------------------------------------

#if !defined(UTILS_CXX2011)
template <typename F0>
class detail::visitor : public AbstractVisitor
{
public:
    typedef typename F0::argument_type argument_type;
    visitor(F0 const& functor);
    void do_visit(argument_type arg);

private:
    F0 functor_;
};

template <typename F0>
inline
detail::visitor<F0>::visitor(F0 const& functor)
: functor_(functor)
{
}

template <typename F0>
inline
detail::visitor<F0>::do_visit(argument_type arg)
{
    functor_(arg);
}
#endif

// ----------------------------------------------------------------------------

class local_visitor
{
public:
#if defined(UTILS_CXX2011)
    template <typename...F>
    local_visitor(F&&...functors);
#else
    template <typename F0>
    local_visitor(F0 const& functor);
#endif
    void visit(clang::Decl const* ptr);
    void visit(clang::Stmt const* ptr);

private:
    std::auto_ptr<AbstractVisitor> visitor_;
};

#if defined(UTILS_CXX2011)
template <typename...F>
inline
local_visitor<F...>::local_visitor(F&&...functors)
: visitor_(new detail::visitor<F...>(forward<F>(functors)...))
{
}
#else
template <typename F0>
inline
local_visitor(F0 const& functor)
: visitor_(new detail::visitor<F0>(functor))
{
}
#endif

inline
void local_visitor::visit(clang::Decl const* ptr)
{
    visitor_->visit(ptr);
}

inline
void local_visitor::visit(clang::Stmt const* ptr)
{
    visitor_->visit(ptr);
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
