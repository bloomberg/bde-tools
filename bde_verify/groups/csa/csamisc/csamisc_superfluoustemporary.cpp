// csamisc_superfluoustemporary.cpp                                   -*-C++-*-

#include "framework/analyser.hpp"
#include "framework/register_check.hpp"
#include "framework/cast_ptr.hpp"

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("superfluous-temporary");

// -----------------------------------------------------------------------------

static void check_entry(Analyser& analyser, CXXConstructExpr const* expr)
{
    if (expr && expr->getNumArgs() == 1)
    {
        bde_verify::cast_ptr<MaterializeTemporaryExpr const> materialize(
            expr->getArg(0));
        bde_verify::cast_ptr<ImplicitCastExpr const> implicit(
            materialize ? materialize->GetTemporaryExpr() : 0);
        if (implicit)
        {
#if 0
            llvm::errs()
                << "ctor type=" << expr->getType().getAsString() << " "
                << "arg-type=" << expr->getArg(0)->getType().getAsString()
                << " "
                << "sub-expr-type="
                << implicit->getSubExpr()->getType().getAsString() << " "
                << "\n";
            analyser.report(expr, check_name, "superfluous temporary");
#endif
        }
    }
}

// -----------------------------------------------------------------------------

static RegisterCheck check(check_name, &check_entry);

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
