// csamisc_selfinitialization.cpp                                     -*-C++-*-

#include <csabase_analyser.h>
#include <csabase_registercheck.h>
#include <csabase_visitor.h>
#include <csabase_localvisitor.h>
#include <functional>
#include <utility>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("self-init");

// -----------------------------------------------------------------------------

namespace
{
    struct match_var_decl
    {
        typedef DeclRefExpr const* argument_type;
        match_var_decl(Analyser& analyser, VarDecl const* decl):
            analyser_(analyser),
            decl_(decl)
        {
        }
        void operator()(DeclRefExpr const* ref) const
        {
            if (ref->getDecl() == decl_)
            {
                analyser_.report(decl_, check_name, "SI01",
                                 "Variable %0 used for self-initialization")
                    << decl_->getName()
                    << ref->getSourceRange();
            }
        }
        Analyser& analyser_;
        VarDecl const* decl_;
    };
}

// -----------------------------------------------------------------------------

static void
checker(Analyser& analyser, VarDecl const* decl)
{
    bde_verify::local_visitor visitor(match_var_decl(analyser, decl));
    visitor.visit(decl);
}

// -----------------------------------------------------------------------------

static RegisterCheck check(check_name, &checker);

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
