// csamisc_boolcomparison.cpp                                         -*-C++-*-

#include <clang/AST/Expr.h>
#include <clang/AST/ExprCXX.h>
#include <clang/AST/OperationKinds.h>
#include <clang/AST/Type.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("boolcomparison");

// ----------------------------------------------------------------------------

static bool
is_bool_comparison(Expr* expr0, Expr* expr1)
{
    expr0 = expr0->IgnoreParenCasts();
    if (llvm::dyn_cast<CXXBoolLiteralExpr>(expr0))
    {
        expr1 = expr1->IgnoreParenCasts();
        return expr0->getType().getUnqualifiedType().getCanonicalType()
            == expr1->getType().getUnqualifiedType().getCanonicalType();
    }
    return false;
}

// ----------------------------------------------------------------------------

static bool
is_comparison(BinaryOperatorKind opcode)
{
    return opcode == BO_LT
        || opcode == BO_GT
        || opcode == BO_LE
        || opcode == BO_GE
        || opcode == BO_EQ
        || opcode == BO_NE
        ;
}

// ----------------------------------------------------------------------------

static void
check(Analyser& analyser, BinaryOperator const* expr)
{
    if (is_comparison(expr->getOpcode())
        && (is_bool_comparison(expr->getLHS(), expr->getRHS())
            || is_bool_comparison(expr->getRHS(), expr->getLHS())))
    {
        analyser.report(expr, check_name, "BC01",
                        "Comparing a Boolean expression to a Boolean literal")
            << expr->getSourceRange();
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
