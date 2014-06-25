// csabase_visitor.cpp                                                -*-C++-*-

#include <csabase_visitor.h>
#include <csabase_debug.h>
#include <utils/event.hpp>

namespace clang { class Decl; }
namespace clang { class Stmt; }

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

#define DECL(CLASS, BASE)                                    \
    void csabase::Visitor::do_visit(CLASS##Decl const* decl) \
    {                                                        \
        if (on##CLASS##Decl) {                               \
            Debug d("event on" #CLASS "Decl");               \
            on##CLASS##Decl(decl);                           \
        }                                                    \
    }
DECL(,)
#include "clang/AST/DeclNodes.inc"  // IWYU pragma: keep

#define STMT(CLASS, PARENT)                            \
    void csabase::Visitor::do_visit(CLASS const* stmt) \
    {                                                  \
        on##CLASS(stmt);                               \
    }
STMT(Stmt,)
#include "clang/AST/StmtNodes.inc"  // IWYU pragma: keep

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
