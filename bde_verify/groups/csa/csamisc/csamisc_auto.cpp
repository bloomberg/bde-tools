// csamisc_auto.cpp                                                   -*-C++-*-

#include <csabase_analyser.h>
#include <csabase_registercheck.h>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("auto");

// ----------------------------------------------------------------------------

static void
check(Analyser& analyser, VarDecl const* decl)
{
    if (decl->hasDefinition() == VarDecl::Definition) {
        TypeSourceInfo const* tsinfo(decl->getTypeSourceInfo());
        Type const* type(tsinfo->getTypeLoc().getTypePtr());
        if (ReferenceType const* ref
            = llvm::dyn_cast<ReferenceType>(type)) {
            type = ref->getPointeeType().getTypePtr();
        }
        if (AutoType const* at = llvm::dyn_cast<AutoType>(type)){
            Expr const* expr = decl->getInit();
            expr = expr? expr->IgnoreParenCasts(): expr;
            std::string exprType(
                expr ? expr->getType().getAsString() : "<none>");
            QualType deduced(at->getDeducedType());
            analyser.report(decl, check_name, "AU01", "VarDecl: %0 %1 %2")
                << (expr? expr->getSourceRange(): decl->getSourceRange())
                << deduced.getAsString()
                << tsinfo->getType().getAsString()
                << exprType;
        }
    }
}

// ----------------------------------------------------------------------------

static RegisterCheck register_check(check_name, &check);

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
