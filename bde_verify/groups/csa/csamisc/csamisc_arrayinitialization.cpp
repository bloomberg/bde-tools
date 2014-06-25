// csamisc_arrayinitialization.cpp                                    -*-C++-*-

#include <clang/AST/ASTContext.h>
#include <clang/AST/Expr.h>
#include <clang/AST/ExprCXX.h>
#include <clang/AST/Type.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/APInt.h>
#include <llvm/Support/Casting.h>
#include <set>
#include <string>
#include <utility>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("array-initialization");

// -----------------------------------------------------------------------------

static bool isDefaultConstructor(Analyser& analyser, Expr const* init)
{
    CXXConstructExpr const* ctor = llvm::dyn_cast<CXXConstructExpr>(init);
    return ctor && (ctor->getNumArgs() == 0 ||
                    (ctor->getNumArgs() == 1 &&
                     llvm::dyn_cast<CXXDefaultArgExpr>(ctor->getArg(0))));
}

// -----------------------------------------------------------------------------

static bool
isDefaultValue(Analyser& analyser, InitListExpr const* expr, Expr const* init)
{
    Expr const* orig(init); 
    do
    {
        orig = init;
        init = const_cast<Expr*>(init)->IgnoreImplicit();

        if (CastExpr const* cast = llvm::dyn_cast<CastExpr>(init))
        {
            init = cast->getSubExpr();
        } else if (CXXConstructExpr const* ctor =
                       llvm::dyn_cast<CXXConstructExpr>(init)) {
            if (ctor->getNumArgs() == 1
                && llvm::dyn_cast<MaterializeTemporaryExpr>(ctor->getArg(0)))
            {
                init = llvm::dyn_cast<MaterializeTemporaryExpr>(
                    ctor->getArg(0))->GetTemporaryExpr();
            }
        }
    }
    while (orig != init);

    return llvm::dyn_cast<CXXScalarValueInitExpr>(init) ||
           (llvm::dyn_cast<CharacterLiteral>(init) &&
            llvm::dyn_cast<CharacterLiteral>(init)->getValue() == 0) ||
           (llvm::dyn_cast<IntegerLiteral>(init) &&
            llvm::dyn_cast<IntegerLiteral>(init)
                    ->getValue()
                    .getLimitedValue() == 0u) ||
           isDefaultConstructor(analyser, init);
}

// -----------------------------------------------------------------------------

namespace
{
    struct reported
    {
        std::set<void const*> reported_;
    };
}

static void check(Analyser& analyser, InitListExpr const* expr)
{
    Type const* type(expr->getType().getTypePtr());
    if (type->isConstantArrayType()
        && !expr->isStringLiteralInit()
        )
    {
        ConstantArrayType const* array(
            analyser.context()->getAsConstantArrayType(expr->getType()));
        if (0u < expr->getNumInits() &&
            expr->getNumInits() < array->getSize().getLimitedValue() &&
            !isDefaultValue(
                 analyser, expr, expr->getInit(expr->getNumInits() - 1u)) &&
            analyser.attachment<reported>().reported_.insert(expr).second) {
            analyser.report(expr, check_name, "II01",
                    "Incomplete initialization with non-defaulted last value")
                << expr->getInit(expr->getNumInits() - 1u)->getSourceRange();
        }
    }
}

// -----------------------------------------------------------------------------

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
