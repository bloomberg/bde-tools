// csamisc_stringadd.cpp                                              -*-C++-*-

#include <clang/AST/Expr.h>
#include <clang/AST/OperationKinds.h>
#include <clang/Basic/SourceLocation.h>
#include <csabase_analyser.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <llvm/ADT/APSInt.h>
#include <llvm/Support/Casting.h>
#include <string>

using namespace csabase;
using namespace clang;

// -----------------------------------------------------------------------------

static std::string const check_name("string-add");

static bool is_addition(Analyser& analyser,
                        Expr const* str,
                        Expr const* value,
                        BinaryOperatorKind op)
{
    if (StringLiteral const* lit =
            llvm::dyn_cast<StringLiteral>(str->IgnoreParenCasts())) {
        llvm::APSInt length(32, false);
        llvm::APSInt zero(32, false);
        length = lit->getByteLength();
        zero = 0u;
        value = value->IgnoreParenCasts();
        llvm::APSInt result;
        return !value->isIntegerConstantExpr(result, *analyser.context()) ||
               (op == BO_Add && (result < zero || length < result)) ||
               (op == BO_Sub && (zero < result || length + result < zero));
    }
    return false;
}

static void check(Analyser& analyser, BinaryOperator const* expr)
{
    if ((expr->getOpcode() == BO_Add || expr->getOpcode() == BO_Sub) &&
        (is_addition(
             analyser, expr->getLHS(), expr->getRHS(), expr->getOpcode()) ||
         is_addition(
             analyser, expr->getRHS(), expr->getLHS(), expr->getOpcode()))) {
        analyser.report(expr->getOperatorLoc(), check_name, "SA01",
                        "%0 integer %1 string literal")
            << expr->getSourceRange()
            << (expr->getOpcode() == BO_Add? "Adding": "Subtracting")
            << (expr->getOpcode() == BO_Add? "to": "from");
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
